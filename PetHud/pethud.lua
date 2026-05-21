--[[
* PetHUD - ペット情報 HUD アドオン for Ashita v4
* ジョブ別タブ表示、マウスドラッグ移動、ウィンドウ位置保存に対応
* 対応ジョブ: PUP（優先1）/ BST / SMN / DRG
--]]

addon.name    = 'PetHUD';
addon.author  = 'xxxkouxxx';
addon.version = '1.0.0';
addon.desc    = 'Pet information HUD with per-job tabs. Supports PUP/BST/SMN/DRG.';

require('common');
local imgui    = require('imgui');
local settings = require('settings');
local chat     = require('chat');

local gConfig  = require('config');
local gPackets = require('packets');
local gGui     = require('gui');

local DEBUG_LOG_FILE = AshitaCore:GetInstallPath() .. 'logs\\PetHud_debug.log';

local function abiscan_log(msg)
    print('[PetHud] ' .. msg);
    local f = io.open(DEBUG_LOG_FILE, 'a');
    if f then
        f:write(string.format('[%s] %s\n', os.date('%H:%M:%S'), msg));
        f:close();
    end
end

-- アビリティリキャストメモリの全スキャン（ID 特定用）
local function abiscan()
    local ptr = nil;
    pcall(function()
        local p = ashita.memory.find('FFXiMain.dll', 0, '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);
        ptr = ashita.memory.read_uint32(p);
    end);
    if ptr == nil then
        abiscan_log('ERROR: AbilityRecastPointer not found');
        return;
    end
    abiscan_log('--- ability recast scan ---');
    for i = 1, 31 do
        local compId = ashita.memory.read_uint8(ptr + (i * 8) + 3);
        local recast = ashita.memory.read_uint32(ptr + (i * 4) + 0xF8);
        if compId ~= 0 then
            abiscan_log(string.format('  slot[%d] compId=%d recast=%d (%.1fs)', i, compId, recast, recast / 60.0));
        end
    end
    abiscan_log('--- scan end ---');
    print('[PetHud] スキャン完了。logs\\PetHud_debug.log を確認してください。');
end

--------------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    -- 設定はロード時に config.lua 内で自動ロード済み
end);

--------------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    settings.save();
end);

--------------------------------------------------------------------
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args();
    if #args == 0 or not args[1]:any('/pethud', '/ph') then
        return;
    end
    e.blocked = true;

    if #args == 1 then
        -- 設定メニュー開閉トグル
        gConfig.params.configMenuOpen[1] = not gConfig.params.configMenuOpen[1];
    elseif args[2] == 'abiscan' then
        abiscan();
    end
end);

--------------------------------------------------------------------
ashita.events.register('packet_in', 'packet_in_cb', function(e)
    gPackets.packet_in_cb(e);
end);

--------------------------------------------------------------------
ashita.events.register('packet_out', 'packet_out_cb', function(e)
    gPackets.packet_out_cb(e);
end);

-- ペット消滅タイマー（Deactivate 判定用）
-- SPアビ使用時はペットが一時的に消える可能性があるため、
-- 3秒間消え続けた場合のみ本当の Deactivate として扱う
local petGoneTimer  = nil;      -- ペット消滅を検出した os.time()
local PET_GONE_GRACE = 3;       -- 秒: この間は Deactivate 扱いしない

--------------------------------------------------------------------
ashita.events.register('d3d_present', 'd3d_present_cb', function()
    if gConfig.hideWindow() then return; end

    local player = GetPlayerEntity();
    if player == nil then return; end  -- ゾーニング中

    -- マニューバー期限切れ掃除
    gPackets.tick();

    -- ペットタイプの自動検出（未設定 & ペット存在時）
    local pet = GetEntity(player.PetTargetIndex);
    if pet ~= nil and pet.Name ~= nil then
        -- ペットが存在する → 消滅タイマーをリセット
        petGoneTimer = nil;

        if gConfig.params.mobInfo.petType == gConfig.petType.NONE then
            autoDetectPetType(pet);
        end
    else
        -- ペットなし → すぐにはリセットせず猶予タイマーで判定
        if gConfig.params.mobInfo.petType ~= gConfig.petType.NONE then
            if petGoneTimer == nil then
                -- 消滅を初めて検出: タイマー開始
                petGoneTimer = os.time();
            elseif (os.time() - petGoneTimer) >= PET_GONE_GRACE then
                -- 猶予時間を過ぎても消えていた → 本当の Deactivate
                gConfig.params.mobInfo.petType = gConfig.petType.NONE;
                gConfig.params.mobInfo.pupPet.maneuvers = {};
                petGoneTimer = nil;
            end
            -- 猶予時間内は何もしない（SPアビ一時消滅を無視）
        else
            -- petType がすでに NONE なら猶予タイマー不要
            petGoneTimer = nil;
        end
    end

    -- 設定メニュー描画
    if gConfig.params.configMenuOpen[1] then
        gGui.renderMenu();
    end

    -- メインウィンドウ描画（ペットあり or alwaysVisible 時）
    if pet ~= nil or gConfig.params.settings.components.alwaysVisible[1] then
        gGui.renderMainWindow();
    end
end);

--------------------------------------------------------------------
-- ペットタイプを名前リストから推定する
-- packets.lua のパケット検出を補完する
--------------------------------------------------------------------
function autoDetectPetType(pet)
    local jugPet  = require('petBSTJug');
    local smnPet  = require('petSMN');
    local drgPet  = require('petDRG');
    local geoPet  = require('petGEO');

    if geoPet.checkIsLuopan(pet.Name) then
        gConfig.params.mobInfo.petType = gConfig.petType.LUOPAN;

    elseif jugPet.checkIsJugPet(pet.Name) then
        gConfig.params.mobInfo.petType = gConfig.petType.JUG;
        jugPet.newJug();

    elseif smnPet.checkIsSummon(pet.Name) then
        gConfig.params.mobInfo.petType = gConfig.petType.SUMMON;

    elseif drgPet.checkIsDragon(pet.Name) then
        gConfig.params.mobInfo.petType = gConfig.petType.DRAGON;

    else
        -- ジョブから PUP / GEO / BST(Charm) かを判定
        local mainJob = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
        local subJob  = AshitaCore:GetMemoryManager():GetPlayer():GetSubJob();
        if mainJob == 18 or subJob == 18 then  -- PUP
            gConfig.params.mobInfo.petType = gConfig.petType.PUPPET;
        elseif mainJob == 21 or subJob == 21 then  -- GEO
            gConfig.params.mobInfo.petType = gConfig.petType.LUOPAN;
        else
            -- BST 魅了扱い（デフォルト）
            gConfig.params.mobInfo.petType = gConfig.petType.CHARMED;
        end
    end
end

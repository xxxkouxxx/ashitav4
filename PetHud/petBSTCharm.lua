-- BST 魅了ペット専用 UI（petme petBSTCharm.lua を PetHUD 用に改修）
local Charm = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local settings   = require('settings');
local genPet     = require('petGeneric');

-- 魅了強化装備テーブル（item ID → Charm+ 値）
local charmGear = T{
    [17936] = 1,  -- De Saintre's Axe
    [17950] = 2,  -- Marid Ancus
    [12517] = 4,  -- Beast Helm
    [15157] = 5,  -- Bison Warbonnet
    [15158] = 6,  -- Brave's Warbonnet
    [16104] = 5,  -- Khimaira Bonnet
    [16105] = 6,  -- Stout Bonnet
    [15080] = 5,  -- Monster Helm
    [15233] = 4,  -- Beast Helm +1
    [15253] = 5,  -- Monster Helm +1
    [12646] = 5,  -- Beast Jackcoat
    [14418] = 5,  -- Bison Jacket
    [14419] = 6,  -- Brave's Jacket
    [14566] = 5,  -- Khimaira Jacket
    [14567] = 6,  -- Stout Jacket
    [15095] = 6,  -- Monster Jackcoat
    [14481] = 6,  -- Beast Jackcoat +1
    [14508] = 7,  -- Monster Jackcoat +1
    [13969] = 3,  -- Beast Gloves
    [14850] = 5,  -- Bison Wristbands
    [14851] = 6,  -- Brave's Wristbands
    [14981] = 5,  -- Khimaira Wristbands
    [14982] = 6,  -- Stout Wristbands
    [14898] = 3,  -- Beast Gloves +1
    [15110] = 4,  -- Monster Gloves
    [14917] = 4,  -- Monster Gloves +1
    [14222] = 6,  -- Beast Trousers
    [14319] = 5,  -- Bison Kecks
    [14320] = 6,  -- Brave's Kecks
    [15645] = 5,  -- Khimaira Kecks
    [15646] = 6,  -- Stout Kecks
    [15125] = 2,  -- Monster Trousers
    [15569] = 6,  -- Beast Trousers +1
    [15588] = 2,  -- Monster Trousers +1
    [14097] = 2,  -- Beast Gaiters
    [15307] = 5,  -- Bison Gamashes
    [15308] = 6,  -- Brave's Gamashes
    [15731] = 5,  -- Khimaira Gamashes
    [15732] = 6,  -- Stout Gamashes
    [15360] = 2,  -- Beast Gaiters +1
    [15140] = 3,  -- Monster Gaiters
    [15673] = 3,  -- Monster Gaiters +1
    [14658] = 4,  -- Atlaua's Ring
    [13667] = 5,  -- Trimmer's Mantle (HorizonXI /BST)
};

-- レベル差 → 魅了時間倍率テーブル
local dLevel = {
    { ld = -6, chg = 0.04 }, { ld = -5, chg = 0.08 }, { ld = -4, chg = 0.12 },
    { ld = -3, chg = 0.16 }, { ld = -2, chg = 0.33 }, { ld = -1, chg = 0.66 },
    { ld =  0, chg = 1.00 }, { ld =  1, chg = 1.40 }, { ld =  2, chg = 1.80 },
    { ld =  3, chg = 2.20 }, { ld =  4, chg = 2.60 }, { ld =  5, chg = 3.00 },
    { ld =  6, chg = 3.40 }, { ld =  7, chg = 4.00 }, { ld =  8, chg = 5.00 },
    { ld =  9, chg = 6.00 },
};

local function getCharmEquipValue()
    local charmValue = 0;
    for i = 0, 15 do
        local equipped = AshitaCore:GetMemoryManager():GetInventory():GetEquippedItem(i);
        local index    = bit.band(equipped.Index, 0x00FF);
        if index > 0 then
            local container = bit.rshift(bit.band(equipped.Index, 0xFF00), 8);
            local item      = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(container, index);
            if charmGear[item.Id] ~= nil then
                charmValue = charmValue + charmGear[item.Id];
            end
        end
    end
    return charmValue;
end

-- 魅了持続時間を計算して os.time() + 秒数 で返す
Charm.calculateCharmTime = function(mobLevel)
    local playerLvl = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
    local baseChr   = AshitaCore:GetMemoryManager():GetPlayer():GetStat(6);

    local levelDiff = math.max(-6, math.min(9, playerLvl - mobLevel));

    local lvlModifier = 0;
    for _, item in ipairs(dLevel) do
        if item.ld == levelDiff then lvlModifier = item.chg; break; end
    end

    local baseCharmDuration = math.floor(1.25 * baseChr + 150);
    local preGear           = baseCharmDuration * lvlModifier;
    local charmDuration     = preGear * (1 + 0.05 * getCharmEquipValue());
    return os.time() + charmDuration;
end

--------------------------------------------------------------------
Charm.gui = function(pet)
    if pet == nil then return; end

    local cfg = gConfig.params.settings.components;
    local mob = gConfig.params.mobInfo;

    -- ペット名・レベル・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, mob.mobLevel);
    end

    -- 魅了残り時間
    if cfg.petDuration[1] then
        if mob.charmUntil ~= 0 then
            local dur  = math.max(0, math.floor(mob.charmUntil - os.time()));
            local hrs  = math.floor(dur / 3600);
            local mins = math.floor((dur % 3600) / 60);
            local secs = dur % 60;
            imgui.Text(string.format('Charm: %01d:%02d:%02d', hrs, mins, secs));
        else
            imgui.Text('Charm: (Unknown)');
        end
    end

    -- リキャスト表示
    if cfg.petRecasts[1] then
        local sicSecs    = gFunctions.GetSicRecast();
        local rewardSecs = gFunctions.GetRewardRecast();
        imgui.Text(string.format('Sic: %ds', sicSecs));
        imgui.SameLine();
        local rewText = string.format('Reward: %ds', rewardSecs);
        local rewWidth, _ = imgui.CalcTextSize(rewText);
        imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - rewWidth);
        imgui.Text(rewText);
    end

    -- Stay ヒールカウント
    if cfg.petStayCounter[1] then
        Charm.drawStayTick();
    end
end

-- Stay ヒールティック表示（Charm / Jug 共通）
Charm.drawStayTick = function()
    local player = GetPlayerEntity();
    if player == nil then return; end

    local bst = gConfig.params.mobInfo.bstPet;
    if bst.stayTicks == 0 then return; end

    local petMovement = AshitaCore:GetMemoryManager():GetEntity():GetLocalMoveCount(player.PetTargetIndex);
    if petMovement ~= 0 and bst.stayTicks - os.time() < 19 then
        bst.stayTicks = 0;  -- ペットが動いたらリセット
        return;
    end

    if bst.stayTicks - os.time() <= 0 then
        bst.stayTicks = os.time() + 10;
    end
    imgui.Text('Heal tick: ' .. tostring(bst.stayTicks - os.time()) .. 's');
end

return Charm;

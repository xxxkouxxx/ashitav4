-- PUP（からくり士）専用 UI（PetHUD 新規実装）
local Pup = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local genPet     = require('petGeneric');

-- オーバーロード状態効果 ID（要実機確認: 一般的に 275 とされている）
local OVERLOAD_STATUS_ID = 275;

--------------------------------------------------------------------
Pup.gui = function(pet)
    if pet == nil then return; end

    local cfg = gConfig.params.settings.components;
    local pup = gConfig.params.mobInfo.pupPet;

    -- ペット名・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, 0);
    end

    -- マニューバー状態表示
    if cfg.maneuvers[1] then
        Pup.drawManeuvers(pup);
    end

    -- オーバーロード警告
    if cfg.overloadStatus[1] then
        Pup.drawOverload();
    end
end

--------------------------------------------------------------------
-- マニューバーのアクティブ状態と残り時間を描画
--------------------------------------------------------------------
Pup.drawManeuvers = function(pup)
    imgui.Separator();
    imgui.Text('Maneuvers:');

    local now  = os.time();
    local list = pup.maneuvers;

    if #list == 0 then
        imgui.SameLine();
        imgui.Text('--');
        return;
    end

    -- 各マニューバーを横並びで表示
    for i, mnv in ipairs(list) do
        local mName  = gConfig.maneuverName[mnv.mType] or '?';
        local color  = gConfig.maneuverColor[mnv.mType] or { 1, 1, 1, 1 };
        local remain = mnv.expiry - now;
        if remain < 0 then remain = 0; end

        local label = string.format('%s(%ds)', mName, remain);

        imgui.PushStyleColor(ImGuiCol_Text, color);
        imgui.Text(label);
        imgui.PopStyleColor(1);

        if i < #list then
            imgui.SameLine();
            imgui.Text(' > ');
            imgui.SameLine();
        end
    end
end

--------------------------------------------------------------------
-- オーバーロード状態を描画（赤文字警告）
--------------------------------------------------------------------
Pup.drawOverload = function()
    -- バフリストから確認（ID は要実機確認）
    local overloaded = gFunctions.HasStatusEffect(OVERLOAD_STATUS_ID);
    if overloaded then
        imgui.Separator();
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.2, 0.2, 1.0 });
        imgui.Text('!! OVERLOAD !!');
        imgui.PopStyleColor(1);
    end
end

return Pup;

-- ジョブ共通: HP/MP/TP バーとターゲットバー
local gPet = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');

-- HP/MP/TP の横並びバーを描画
gPet.statBars = function(pet)
    local scale      = gConfig.params.settings.window.scale[1];
    local windowSize = gConfig.params.windowSize * scale;
    local barH       = 15 * scale;
    local barW       = windowSize / 3 - 10;

    local hpColor;
    if     pet.HPPercent > 75 then hpColor = gConfig.colors.HpBarFull
    elseif pet.HPPercent > 50 then hpColor = gConfig.colors.HpBar75
    elseif pet.HPPercent > 25 then hpColor = gConfig.colors.HpBar50
    else                           hpColor = gConfig.colors.HpBar25
    end

    local petmp = AshitaCore:GetMemoryManager():GetPlayer():GetPetMPPercent();
    local pettp = AshitaCore:GetMemoryManager():GetPlayer():GetPetTP();

    imgui.Separator();

    imgui.PushStyleColor(ImGuiCol_PlotHistogram, hpColor);
    imgui.ProgressBar(pet.HPPercent / 100, { barW, barH });
    imgui.PopStyleColor(1);

    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, gConfig.colors.MpBar);
    imgui.ProgressBar(petmp / 100, { barW, barH });
    imgui.PopStyleColor(1);

    imgui.SameLine();
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, gConfig.colors.TpBar);
    imgui.ProgressBar(pettp / 3000, { barW, barH }, tostring(pettp));
    imgui.PopStyleColor(1);
end

-- ペットのターゲット情報を描画
gPet.targetBar = function()
    local scale      = gConfig.params.settings.window.scale[1];
    local windowSize = gConfig.params.windowSize * scale;
    local barH       = 15 * scale;

    local target = gFunctions.GetEntityByServerId(gConfig.params.mobInfo.petTarget);
    if target == nil or target.ActorPointer == 0 or target.HPPercent == 0 then
        gConfig.params.mobInfo.petTarget = nil;
        return;
    end

    local dist  = ('%.1f'):fmt(math.sqrt(target.Distance));
    local x, _  = imgui.CalcTextSize(dist);
    local tname = target.Name or '';

    imgui.Separator();
    imgui.Text(tname);
    imgui.SameLine();
    imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
    imgui.Text(dist);
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, gConfig.colors.TargetBar);
    imgui.ProgressBar(target.HPPercent / 100, { -1, barH });
    imgui.PopStyleColor(1);
end

-- ペット名・距離の共通ヘッダ行を描画（レベル付き）
gPet.nameHeader = function(pet, level)
    if pet == nil then return; end
    local dist = ('%.1f'):fmt(math.sqrt(pet.Distance));
    local x, _ = imgui.CalcTextSize(dist);
    local nameStr;
    if level and level > 0 then
        nameStr = pet.Name .. ' (Lv' .. tostring(level) .. ')';
    else
        nameStr = pet.Name;
    end
    imgui.Text(nameStr);
    imgui.SameLine();
    imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - x - imgui.GetStyle().FramePadding.x);
    imgui.Text(dist .. 'm');
end

return gPet;

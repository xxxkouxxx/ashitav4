-- GEO（風水士）専用 UI
local Geo = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local genPet     = require('petGeneric');

--------------------------------------------------------------------
Geo.checkIsLuopan = function(petName)
    if petName == nil then return false; end
    return string.find(petName, 'Luopan') ~= nil;
end

--------------------------------------------------------------------
Geo.gui = function(pet)
    if pet == nil then return; end

    local cfg = gConfig.params.settings.components;

    -- ラバン名・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, 0);
    end

    -- GEO アビリティリキャスト
    -- ⚠ compId は実機で /pethud abiscan を実行して確認・更新してください
    if cfg.petRecasts[1] then
        local fcSecs = gFunctions.GetFullCircleRecast();
        local raSecs = gFunctions.GetRadialArcanaRecast();
        local lcSecs = gFunctions.GetLifeCycleRecast();
        local blSecs = gFunctions.GetBolsterRecast();

        imgui.Text(string.format('Full Circle:   %ds', fcSecs));
        imgui.Text(string.format('Radial Arcana: %ds', raSecs));
        imgui.Text(string.format('Life Cycle:    %ds', lcSecs));
        imgui.Text(string.format('Bolster:       %ds', blSecs));
    end
end

return Geo;

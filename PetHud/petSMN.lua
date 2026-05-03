-- SMN（召喚士）専用 UI（petme petSMN.lua を PetHUD 用に改修）
local Smn = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local genPet     = require('petGeneric');

local summonList = {
    'Carbuncle', 'Fenrir', 'Ifrit', 'Titan', 'Leviathan', 'Garuda',
    'Shiva', 'Ramuh', 'Diabolos', 'Cait Sith', 'Siren', 'Atomos',
    'Alexander†', 'Odin†',
    'Fire Spirit', 'Ice Spirit', 'Air Spirit', 'Earth Spirit',
    'Thunder Spirit', 'Water Spirit', 'Light Spirit', 'Dark Spirit',
}

--------------------------------------------------------------------
Smn.checkIsSummon = function(petName)
    for _, entry in ipairs(summonList) do
        if string.match(entry, petName) ~= nil then return true; end
    end
    return false;
end

--------------------------------------------------------------------
Smn.gui = function(pet)
    if pet == nil then return; end

    local cfg = gConfig.params.settings.components;

    -- アバター名・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, 0);
    end

    -- BP リキャスト
    if cfg.petRecasts[1] then
        local rageSecs = gFunctions.GetBPRageRecast();
        local wardSecs = gFunctions.GetBPWardRecast();
        imgui.Text(string.format('BP Rage: %ds', rageSecs));
        imgui.Text(string.format('BP Ward: %ds', wardSecs));
    end
end

return Smn;

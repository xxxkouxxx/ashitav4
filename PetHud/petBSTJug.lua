-- BST 獣呼びペット専用 UI（petme petBSTJug.lua を PetHUD 用に改修）
local Jug = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local settings   = require('settings');
local genPet     = require('petGeneric');
local charmPet   = require('petBSTCharm');

-- HorizonXI 準拠の獣呼びペットリスト { 名前, 最大レベル, 持続時間(分) }
local jugPetList = {
    { petName='HareFamiliar',    maxlevel=35, duration=90 },
    { petName='SheepFamiliar',   maxlevel=35, duration=60 },
    { petName='FlowerpotBill',   maxlevel=40, duration=60 },
    { petName='TigerFamiliar',   maxlevel=40, duration=60 },
    { petName='FlytrapFamiliar', maxlevel=40, duration=60 },
    { petName='LizardFamiliar',  maxlevel=45, duration=60 },
    { petName='MayflyFamiliar',  maxlevel=45, duration=60 },
    { petName='EftFamiliar',     maxlevel=45, duration=60 },
    { petName='BeetleFamiliar',  maxlevel=45, duration=60 },
    { petName='AntlionFamiliar', maxlevel=50, duration=60 },
    { petName='CrabFamiliar',    maxlevel=55, duration=30 },
    { petName='MiteFamiliar',    maxlevel=55, duration=60 },
    { petName='KeenearedSteffi', maxlevel=75, duration=90 },
    { petName='LullabyMelodia',  maxlevel=75, duration=60 },
    { petName='FlowerpotBen',    maxlevel=75, duration=60 },
    { petName='SaberSiravarde',  maxlevel=75, duration=60 },
    { petName='FunguarFamiliar', maxlevel=65, duration=60 },
    { petName='ShellbusterOrob', maxlevel=75, duration=60 },
    { petName='ColdbloodComo',   maxlevel=75, duration=60 },
    { petName='CourierCarrie',   maxlevel=75, duration=30 },
    { petName='Homunculus',      maxlevel=75, duration=60 },
    { petName='VoraciousAudrey', maxlevel=75, duration=60 },
    { petName='AmbusherAllie',   maxlevel=75, duration=60 },
    { petName='PanzerGalahad',   maxlevel=75, duration=60 },
    { petName='LifedrinkerLars', maxlevel=75, duration=60 },
    { petName='ChopsueyChucky',  maxlevel=75, duration=60 },
    { petName='AmigoSabotender', maxlevel=75, duration=30 },
}

local newJug = false;

local function initJug(pet)
    Jug.calculateJugPetTime(pet.Name);
    gConfig.params.mobInfo.mobLevel = Jug.getJugLevel(pet.Name);
    newJug = false;
end

Jug.newJug = function()
    newJug = true;
end

--------------------------------------------------------------------
Jug.calculateJugPetTime = function(petName)
    if petName == nil then return; end
    local duration = 0;
    for _, entry in ipairs(jugPetList) do
        if string.match(entry.petName, petName) ~= nil then
            duration = entry.duration;
            break;
        end
    end
    local charmDuration = duration * 60;
    gConfig.params.mobInfo.charmUntil             = os.time() + charmDuration;
    gConfig.params.settings.charmUntil            = T{gConfig.params.mobInfo.charmUntil};
    settings.save();
end

--------------------------------------------------------------------
Jug.getJugLevel = function(petName)
    local playerLvl = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
    local petLevel  = playerLvl;
    for _, entry in ipairs(jugPetList) do
        if string.match(entry.petName, petName) ~= nil then
            if playerLvl >= entry.maxlevel then petLevel = entry.maxlevel; end
            break;
        end
    end
    return petLevel;
end

--------------------------------------------------------------------
Jug.checkIsJugPet = function(petName)
    for _, entry in ipairs(jugPetList) do
        if string.match(entry.petName, petName) ~= nil then return true; end
    end
    return false;
end

--------------------------------------------------------------------
Jug.gui = function(pet)
    if pet == nil then return; end

    if newJug then initJug(pet); end

    local cfg = gConfig.params.settings.components;
    local mob = gConfig.params.mobInfo;

    -- ペット名・レベル・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, mob.mobLevel);
    end

    -- 持続時間
    if cfg.petDuration[1] then
        if mob.charmUntil == 0 then
            mob.charmUntil = gConfig.params.settings.charmUntil[1];
        end
        local dur  = math.max(0, math.floor(mob.charmUntil - os.time()));
        local hrs  = math.floor(dur / 3600);
        local mins = math.floor((dur % 3600) / 60);
        local secs = dur % 60;
        imgui.Text(string.format('Duration: %01d:%02d:%02d', hrs, mins, secs));
    end

    -- Ready / Reward リキャスト
    if cfg.petRecasts[1] then
        local readyData  = gFunctions.GetReadyRecast();
        local rewardSecs = gFunctions.GetRewardRecast();
        imgui.Text(string.format('Ready: %d (%ds)', readyData[1], readyData[2]));
        imgui.SameLine();
        local rewText = string.format('Reward: %ds', rewardSecs);
        local rewWidth, _ = imgui.CalcTextSize(rewText);
        imgui.SetCursorPosX(imgui.GetCursorPosX() + imgui.GetColumnWidth() - rewWidth);
        imgui.Text(rewText);
    end

    -- Stay ヒールカウント
    if cfg.petStayCounter[1] then
        charmPet.drawStayTick();
    end
end

return Jug;

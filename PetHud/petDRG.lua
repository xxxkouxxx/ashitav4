-- DRG（竜騎士）専用 UI（petme petDRG.lua を PetHUD 用に改修）
local Drg = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local gFunctions = require('helper');
local genPet     = require('petGeneric');

-- ワイバーン名リスト
local dragonList = {
    'Azure','Cerulean','Rygor','Firewing','Delphyne','Ember','Rover','Max',
    'Buster','Duke','Oscar','Maggie','Jessie','Lady','Hien','Raiden','Lumiere',
    'Eisenzahn','Pfeil','Wuffi','George','Donryu','Qiqiru','Karav-Marav','Oboro',
    'Darug-Borug','Mikan','Vhiki','Sasavi','Tatang','Nanaja','Khocha','Dino',
    'Chomper','Huffy','Pouncer','Fido','Lucy','Jake','Rocky','Rex','Rusty',
    'Himmelskralle','Gizmo','Spike','Sylvester','Milo','Tom','Toby','Felix',
    'Komet','Bo','Molly','Unryu','Daisy','Baron','Ginger','Muffin','Lumineux',
    'Quatrevents','Toryu','Tataba','Etoilazuree','Grisnuage','Belorage',
    'Centonnerre','Nouvellune','Missy','Amedeo','Tranchevent','Soufflefeu',
    'Etoile','Tonnerre','Nuage','Foudre','Hyuh','Orage','Lune','Astre',
    'Waffenzahn','Soleil','Courageux','Koffla-Paffla','Venteuse','Lunaire',
    'Tora','Celeste','Galja-Mogalja','Gaboh','Vhyun','Orageuse','Stellaire',
    'Solaire','Wirbelwind','Blutkralle','Bogen','Junker','Flink','Knirps',
    'Bodo','Soryu','Wanaro','Totona','Levian-Movian','Kagero','Joseph',
    'Paparaz','Coco','Ringo','Nonomi','Teter','Gigima','Gogodavi','Rurumo',
    'Tupah','Jyubih','Majha',
}

--------------------------------------------------------------------
Drg.checkIsDragon = function(petName)
    for _, entry in ipairs(dragonList) do
        if string.match(entry, petName) ~= nil then return true; end
    end
    return false;
end

--------------------------------------------------------------------
Drg.gui = function(pet)
    if pet == nil then return; end

    local cfg = gConfig.params.settings.components;

    -- ワイバーン名・距離
    if cfg.petName[1] then
        genPet.nameHeader(pet, 0);
    end

    -- Jump 系アビリティ リキャスト
    if cfg.petRecasts[1] then
        local jumpSecs        = gFunctions.GetJumpRecast();
        local highJumpSecs    = gFunctions.GetHighJumpRecast();
        local superJumpSecs   = gFunctions.GetSuperJumpRecast();
        local spiritJumpSecs  = gFunctions.GetSpiritJumpRecast();
        local spiritLinkSecs  = gFunctions.GetSpiritLinkRecast();

        local function recastText(secs)
            if secs <= 0 then return 'Ready'; end
            if secs >= 60 then
                return string.format('%d:%02d', math.floor(secs / 60), secs % 60);
            end
            return string.format('%ds', secs);
        end

        imgui.Text(string.format('Jump:         %s', recastText(jumpSecs)));
        imgui.Text(string.format('High Jump:    %s', recastText(highJumpSecs)));
        imgui.Text(string.format('Super Jump:   %s', recastText(superJumpSecs)));
        imgui.Text(string.format('Spirit Jump:  %s', recastText(spiritJumpSecs)));
        imgui.Text(string.format('Spirit Link:  %s', recastText(spiritLinkSecs)));
        -- Soul Jump: compId 未確定のため一時非表示（/pethud abiscan で要確認）
    end
end

return Drg;

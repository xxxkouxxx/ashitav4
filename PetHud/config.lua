local gConfig = T{};

local settings = require('settings');

------------------------------ENUMS---------------------------------
gConfig.petType = T{
    NONE    = 0,
    CHARMED = 1,
    JUG     = 2,
    DRAGON  = 3,
    SUMMON  = 4,
    PUPPET  = 5,
    LUOPAN  = 6,
    UNKNOWN = -1,
}

-- マニューバー種別
gConfig.maneuverType = T{
    NONE      = 0,
    FIRE      = 1,
    ICE       = 2,
    WIND      = 3,
    EARTH     = 4,
    LIGHTNING = 5,
    WATER     = 6,
    LIGHT     = 7,
    DARK      = 8,
}

gConfig.maneuverName = T{
    [1] = 'Fire',
    [2] = 'Ice',
    [3] = 'Wind',
    [4] = 'Earth',
    [5] = 'Lightning',
    [6] = 'Water',
    [7] = 'Light',
    [8] = 'Dark',
}

-- マニューバー使用時の色（ImGui RGBA）
gConfig.maneuverColor = T{
    [1] = { 1.0, 0.35, 0.15, 1.0 }, -- Fire     赤橙
    [2] = { 0.4, 0.75, 1.0,  1.0 }, -- Ice      水色
    [3] = { 0.6, 0.9,  0.5,  1.0 }, -- Wind     黄緑
    [4] = { 0.6, 0.45, 0.2,  1.0 }, -- Earth    茶
    [5] = { 1.0, 1.0,  0.3,  1.0 }, -- Lightning 黄
    [6] = { 0.3, 0.6,  1.0,  1.0 }, -- Water    青
    [7] = { 1.0, 1.0,  0.9,  1.0 }, -- Light    白
    [8] = { 0.5, 0.2,  0.7,  1.0 }, -- Dark     紫
}

------------------------------SETTINGS------------------------------
local defaultConfig = T{
    window = T{
        posX            = T{100},
        posY            = T{100},
        scale           = T{1.0},
        opacity         = T{0.8},
        backgroundColor = T{0.23, 0.23, 0.26, 1.0},
        textColor       = T{1.00, 1.00, 1.00, 1.0},
        borderColor     = T{0.00, 0.00, 0.00, 1.0},
    },
    components = T{
        petName         = T{true},
        petDuration     = T{true},
        petRecasts      = T{true},
        petStats        = T{true},
        petTarget       = T{true},
        petStayCounter  = T{true},
        maneuvers       = T{true},
        overloadStatus  = T{true},
        hideMap         = T{true},
        hideLog         = T{false},
        alwaysVisible   = T{false},
    },
    -- マニューバー継続時間（秒）
    -- ギア強化で延長されている場合はここを変更する
    -- 例: 60（素）/ 90（Strobe 装備）/ 120（最大強化）
    maneuverDuration = T{60},
    charmUntil = T{0},
}

gConfig.params = T{
    settings = settings.load(defaultConfig);

    windowSize = 360;
    configMenuOpen = {false};

    mobInfo = T{
        petType         = 0,   -- gConfig.petType.NONE
        lastPetType     = 0,
        mobLevel        = 0,
        charmUntil      = 0,
        petTarget       = nil,
        bstPet = T{
            stayTicks = 0;
        },
        -- PUP 専用
        pupPet = T{
            maneuvers   = {},  -- { {type=N, expiry=unix_time}, ... } 最大3スタック
            overloaded  = false,
        },
    },
}

-- タブ自動切り替え制御（ペットタイプ変化時のみ SetSelected）
gConfig.tabAutoSelect = T{
    lastType       = -99,
    pendingSelect  = false,
}

---------------------------カラー定義------------------------------
gConfig.colors = {
    HpBarFull  = { 0.10, 0.60, 0.10, 1.0 },
    HpBar75    = { 0.70, 0.60, 0.10, 1.0 },
    HpBar50    = { 0.80, 0.40, 0.10, 1.0 },
    HpBar25    = { 0.80, 0.10, 0.10, 1.0 },
    MpBar      = { 0.20, 0.20, 0.80, 1.0 },
    TpBar      = { 0.40, 0.40, 0.40, 1.0 },
    TargetBar  = { 0.70, 0.40, 0.40, 1.0 },
}

--------------------------------------------------------------------------------
-- GetMenuName: 最前面メニュー名を取得（XITools / petme 由来）
--------------------------------------------------------------------------------
local menuBase = nil;
pcall(function()
    menuBase = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0);
end);

function GetMenuName()
    if menuBase == nil then return ''; end
    local ok, result = pcall(function()
        local subPointer = ashita.memory.read_uint32(menuBase);
        local subValue   = ashita.memory.read_uint32(subPointer);
        if subValue == 0 then return ''; end
        local menuHeader = ashita.memory.read_uint32(subValue + 4);
        local menuName   = ashita.memory.read_string(menuHeader + 0x46, 16);
        return string.gsub(menuName, '\x00', '');
    end);
    if ok then return result else return ''; end
end

gConfig.hideWindow = function()
    local menuName = GetMenuName();

    if gConfig.params.settings.components.hideMap[1] == true then
        if string.match(menuName, 'map') or string.match(menuName, 'cnqframe') then
            return true;
        end
    end

    if gConfig.params.settings.components.hideLog[1] == true then
        if string.match(menuName, 'fulllog') then
            return true;
        end
    end

    return menuName:match('menu%s+scanlist.*') ~= nil
        or menuName:match('menu%s+dbnamese') ~= nil
        or menuName:match('menu%s+ptc6yesn') ~= nil;
end

--------------------------------------------------------------------
settings.register('settings', 'settings_update', function(s)
    if s ~= nil then
        gConfig.params.settings = s;
    end
    settings.save();
end);

return gConfig;

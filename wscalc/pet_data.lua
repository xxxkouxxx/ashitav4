--[[
    pet_data.lua
    PetCalc 用データベース
    SMN / BST / PUP のペット基礎ステータスプリセットと技定義を提供する
]]

local M = {}

-- =============================================================================
-- 技定義（ペット共通スキーマ）
-- base_power  : 武器D値相当（物理） or 魔法威力の基準値
-- wsc_pct     : ステータス補正係数（0.0〜1.0）
-- damage_type : "physical" / "magical"
-- hits        : ヒット数
-- ftp         : {[1]=1000TP, [2]=2000TP, [3]=3000TP}
-- =============================================================================

-- SMN 技
local smn_ws = {
    carbuncle = {
        {
            name = "Searing Light",
            display_name = "カーバンクル - Searing Light",
            damage_type = "magical",
            hits = 1,
            base_power = 200,
            wsc_pct = 0.0,
            ftp = { 1.0, 2.0, 4.0 },
        },
    },
    garuda = {
        {
            name = "Predator Claws",
            display_name = "ガルーダ - Predator Claws",
            damage_type = "physical",
            hits = 4,
            base_power = 50,
            wsc_pct = 0.50,   -- STR 50%
            ftp = { 1.0, 1.0, 2.5 },
        },
        {
            name = "Aerial Blast",
            display_name = "ガルーダ - Aerial Blast",
            damage_type = "magical",
            hits = 1,
            base_power = 300,
            wsc_pct = 0.0,
            ftp = { 1.0, 2.0, 4.0 },
        },
    },
    ifrit = {
        {
            name = "Flaming Crush",
            display_name = "イフリート - Flaming Crush",
            damage_type = "physical",
            hits = 1,
            base_power = 60,
            wsc_pct = 0.30,
            ftp = { 3.0, 4.0, 5.0 },
        },
        {
            name = "Inferno",
            display_name = "イフリート - Inferno",
            damage_type = "magical",
            hits = 1,
            base_power = 300,
            wsc_pct = 0.0,
            ftp = { 1.0, 2.0, 4.0 },
        },
    },
    shiva = {
        {
            name = "Rush",
            display_name = "シヴァ - Rush",
            damage_type = "physical",
            hits = 5,
            base_power = 40,
            wsc_pct = 0.40,
            ftp = { 1.0, 1.5, 2.5 },
        },
        {
            name = "Diamond Dust",
            display_name = "シヴァ - Diamond Dust",
            damage_type = "magical",
            hits = 1,
            base_power = 300,
            wsc_pct = 0.0,
            ftp = { 1.0, 2.0, 4.0 },
        },
    },
}

-- BST ジュガー技
local bst_ws = {
    jugner = {
        {
            name = "Sweeping Gouge",
            display_name = "ジュガー - Sweeping Gouge",
            damage_type = "physical",
            hits = 3,
            base_power = 45,
            wsc_pct = 0.50,
            ftp = { 1.0, 2.0, 3.0 },
        },
        {
            name = "Pinal Nail",
            display_name = "ジュガー - Pinal Nail",
            damage_type = "physical",
            hits = 2,
            base_power = 50,
            wsc_pct = 0.60,
            ftp = { 2.0, 3.0, 4.0 },
        },
    },
}

-- PUP オートマトン技
local pup_ws = {
    automaton = {
        {
            name = "Stringing Pummel",
            display_name = "オートマトン - Stringing Pummel",
            damage_type = "physical",
            hits = 4,
            base_power = 40,
            wsc_pct = 0.50,
            ftp = { 1.0, 1.5, 2.5 },
        },
        {
            name = "String Shredder",
            display_name = "オートマトン - String Shredder",
            damage_type = "physical",
            hits = 2,
            base_power = 55,
            wsc_pct = 0.60,
            ftp = { 2.0, 3.0, 4.0 },
        },
    },
}

-- =============================================================================
-- ステータスプリセット（ペット種別ごとの基礎値）
-- ATK, STR, INT は手動ボーナスで補正する
-- =============================================================================

local smn_presets = {
    carbuncle = {
        { name = "Lv99 Carbuncle",  ATK = 300, STR = 80,  INT = 100 },
    },
    garuda = {
        { name = "Lv99 Garuda",     ATK = 400, STR = 110, INT = 90  },
    },
    ifrit = {
        { name = "Lv99 Ifrit",      ATK = 380, STR = 120, INT = 80  },
    },
    shiva = {
        { name = "Lv99 Shiva",      ATK = 340, STR = 90,  INT = 110 },
    },
}

local bst_presets = {
    jugner = {
        { name = "Lv99 Juggernaut",  ATK = 450, STR = 120, INT = 60  },
        { name = "Lv99 (Reward+)",   ATK = 500, STR = 130, INT = 60  },
    },
}

local pup_presets = {
    automaton = {
        { name = "Lv99 Automaton (Melee)",  ATK = 380, STR = 100, INT = 80 },
        { name = "Lv99 Automaton (Magic)",  ATK = 300, STR = 80,  INT = 130 },
    },
}

-- =============================================================================
-- パブリック API
-- =============================================================================

-- ジョブ一覧（Combo 用）
M.jobs = {
    { job = "SMN", display = "SMN 召喚獣" },
    { job = "BST", display = "BST ジュガー" },
    { job = "PUP", display = "PUP オートマトン" },
}

function M.get_job_names()
    local t = {}
    for _, j in ipairs(M.jobs) do table.insert(t, j.display) end
    return t
end

-- ジョブに対応するペット/技リストを返す
-- 戻り値: { { pet_name, display_name, ws } } の配列
function M.get_pets(job)
    local result = {}
    if job == "SMN" then
        for pet_name, ws_list in pairs(smn_ws) do
            for _, ws in ipairs(ws_list) do
                table.insert(result, { pet_name = pet_name, display_name = ws.display_name, ws = ws })
            end
        end
    elseif job == "BST" then
        for pet_name, ws_list in pairs(bst_ws) do
            for _, ws in ipairs(ws_list) do
                table.insert(result, { pet_name = pet_name, display_name = ws.display_name, ws = ws })
            end
        end
    elseif job == "PUP" then
        for pet_name, ws_list in pairs(pup_ws) do
            for _, ws in ipairs(ws_list) do
                table.insert(result, { pet_name = pet_name, display_name = ws.display_name, ws = ws })
            end
        end
    end
    -- 表示順を安定させるためにソート
    table.sort(result, function(a, b) return a.display_name < b.display_name end)
    return result
end

-- ジョブ・ペット名に対応するプリセット一覧を返す
function M.get_presets(job, pet_name)
    local map = { SMN = smn_presets, BST = bst_presets, PUP = pup_presets }
    local preset_group = map[job]
    if not preset_group then return {} end
    return preset_group[pet_name] or {}
end

return M

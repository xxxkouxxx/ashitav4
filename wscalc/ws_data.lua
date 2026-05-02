--[[
    ws_data.lua
    WSダメージ計算用データベース
    weapon_rank_caps と ws_list を提供する純データモジュール
]]

local M = {}

-- =============================================================================
-- fSTR 武器ランク別キャップテーブル
-- raw_fSTR = floor((PSTR - EVIT) / 4 + floor(rank/2)) をクランプする上下限
-- =============================================================================
M.weapon_rank_caps = {
    [1]  = { min = -2,  max = 4  },
    [2]  = { min = -4,  max = 8  },
    [3]  = { min = -6,  max = 10 },
    [4]  = { min = -8,  max = 12 },
    [5]  = { min = -10, max = 14 },
    [6]  = { min = -12, max = 16 },
    [7]  = { min = -14, max = 18 },
    [8]  = { min = -16, max = 20 },
    [9]  = { min = -18, max = 22 },
    [10] = { min = -20, max = 24 },
    [11] = { min = -22, max = 26 },
}

-- =============================================================================
-- WS データ一覧
-- フィールド説明:
--   name         表示名（英語）
--   jp_name      日本語名
--   skill_type   武器種別（表示用）
--   hits         ヒット数
--   damage_type  "physical" / "magical" / "special"
--   weapon_rank  武器ランク（fSTRキャップ参照）
--   stat1/val1   主WSC補正ステータス名と係数(%)
--   stat2/val2   副WSC補正（nil可）
--   ftp          {[1]=1000TP倍率, [2]=2000TP倍率, [3]=3000TP倍率}
--   spirits_within  true = HP依存特殊計算
--   atonement       true = ヘイスト依存特殊計算（要手動入力）
-- =============================================================================
M.ws_list = {

    -- --------------------------------------------------------
    -- 片手剣
    -- --------------------------------------------------------
    {
        name = "Shining Blade",     jp_name = "シャイニングブレード",
        skill_type = "Sword",       hits = 1,
        damage_type = "physical",   weapon_rank = 2,
        stat1 = "STR", val1 = 20,
        ftp = { 1.0, 1.0, 1.0 },
    },
    {
        name = "Seraph Blade",      jp_name = "セラフブレード",
        skill_type = "Sword",       hits = 1,
        damage_type = "magical",    weapon_rank = 2,
        stat1 = "MND", val1 = 20,
        ftp = { 1.0, 1.0, 1.0 },
    },
    {
        name = "Vorpal Blade",      jp_name = "ボーパルブレード",
        skill_type = "Sword",       hits = 4,
        damage_type = "physical",   weapon_rank = 3,
        stat1 = "DEX", val1 = 30,
        ftp = { 1.0, 1.0, 1.0 },
    },
    {
        name = "Swift Blade",       jp_name = "スウィフトブレード",
        skill_type = "Sword",       hits = 1,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "STR", val1 = 60,
        ftp = { 4.0, 5.0, 6.0 },
    },
    {
        name = "Savage Blade",      jp_name = "サベッジブレード",
        skill_type = "Sword",       hits = 2,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "STR", val1 = 30,
        stat2 = "MND", val2 = 50,
        ftp = { 1.0, 2.0, 3.0 },
    },
    {
        name = "Sanguine Blade",    jp_name = "サンギンブレード",
        skill_type = "Sword",       hits = 1,
        damage_type = "magical",    weapon_rank = 4,
        stat1 = "STR", val1 = 33,
        stat2 = "MND", val2 = 17,
        ftp = { 1.0, 2.0, 3.0 },
    },
    {
        name = "Requiescat",        jp_name = "レキエスカット",
        skill_type = "Sword",       hits = 5,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "MND", val1 = 30,
        ftp = { 1.0, 2.0, 3.0 },
    },
    {
        name = "Atonement",         jp_name = "アトーンメント",
        skill_type = "Sword",       hits = 1,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "MND", val1 = 0,   -- ヘイスト依存のため WSC は UI で特別処理
        ftp = { 2.0, 3.0, 4.0 },
        atonement = true,
    },
    {
        name = "Chant du Cygne",    jp_name = "シャン・デュ・シーニュ",
        skill_type = "Sword",       hits = 4,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "DEX", val1 = 10,
        stat2 = "CHR", val2 = 10,
        ftp = { 2.0, 2.0, 2.0 },
        -- 注意: fTP は最終打のみ適用の可能性あり（要実機確認）
    },
    {
        name = "Resolution",        jp_name = "レゾリューション",
        skill_type = "Sword",       hits = 6,
        damage_type = "physical",   weapon_rank = 5,
        stat1 = "STR", val1 = 60,
        ftp = { 1.5, 2.25, 3.0 },
    },

    -- --------------------------------------------------------
    -- 格闘棒（Club）
    -- --------------------------------------------------------
    {
        name = "Spirits Within",    jp_name = "スピリッツウィズイン",
        skill_type = "Club",        hits = 1,
        damage_type = "special",    weapon_rank = 4,
        stat1 = "MND", val1 = 0,   -- HP依存計算のため WSC は特別処理
        ftp = { 1.0, 1.0, 1.0 },
        spirits_within = true,
    },
    {
        name = "Hexa Strike",       jp_name = "ヘキサストライク",
        skill_type = "Club",        hits = 6,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "MND", val1 = 60,
        ftp = { 1.0, 1.0, 1.0 },
    },
    {
        name = "Black Halo",        jp_name = "ブラックヘイロー",
        skill_type = "Club",        hits = 2,
        damage_type = "physical",   weapon_rank = 5,
        stat1 = "STR", val1 = 30,
        stat2 = "MND", val2 = 50,
        ftp = { 1.0, 3.0, 5.0 },
    },
    {
        name = "Realmrazer",        jp_name = "レルムレイザー",
        skill_type = "Club",        hits = 6,
        damage_type = "physical",   weapon_rank = 5,
        stat1 = "MND", val1 = 50,
        ftp = { 1.0, 1.5, 2.5 },
    },
    {
        name = "Judgment",          jp_name = "ジャッジメント",
        skill_type = "Club",        hits = 2,
        damage_type = "physical",   weapon_rank = 5,
        stat1 = "STR", val1 = 50,
        stat2 = "MND", val2 = 10,
        ftp = { 2.0, 3.0, 4.0 },
    },

    -- --------------------------------------------------------
    -- 大剣（Great Sword）
    -- --------------------------------------------------------
    {
        name = "Shockwave",         jp_name = "ショックウェーブ",
        skill_type = "Great Sword", hits = 1,
        damage_type = "physical",   weapon_rank = 4,
        ftp = { 1.0, 1.0, 1.0 },
    },
    {
        name = "Ground Strike",     jp_name = "グラウンドストライク",
        skill_type = "Great Sword", hits = 1,
        damage_type = "physical",   weapon_rank = 6,
        stat1 = "STR", val1 = 50,
        stat2 = "VIT", val2 = 25,
        ftp = { 3.5, 4.0, 5.0 },
    },

    -- --------------------------------------------------------
    -- 斧（Axe）
    -- --------------------------------------------------------
    {
        name = "Raging Rush",       jp_name = "レイジングラッシュ",
        skill_type = "Axe",         hits = 3,
        damage_type = "physical",   weapon_rank = 4,
        stat1 = "STR", val1 = 60,
        ftp = { 1.0, 2.0, 3.0 },
    },

    -- --------------------------------------------------------
    -- 大斧（Great Axe）
    -- --------------------------------------------------------
    {
        name = "Calamity",          jp_name = "カラミティ",
        skill_type = "Great Axe",   hits = 2,
        damage_type = "physical",   weapon_rank = 5,
        stat1 = "STR", val1 = 60,
        ftp = { 1.75, 3.0, 4.0 },
    },
    {
        name = "Fell Cleave",       jp_name = "フェルクリーヴ",
        skill_type = "Great Axe",   hits = 1,
        damage_type = "physical",   weapon_rank = 6,
        stat1 = "STR", val1 = 60,
        ftp = { 3.0, 4.0, 5.0 },
    },
    {
        name = "Upheaval",          jp_name = "アップヒーヴァル",
        skill_type = "Great Axe",   hits = 1,
        damage_type = "physical",   weapon_rank = 6,
        stat1 = "VIT", val1 = 85,
        ftp = { 3.0, 4.0, 5.0 },
    },
}

-- ComboBox 用の名前配列を事前生成
M.ws_names = {}
for _, ws in ipairs(M.ws_list) do
    table.insert(M.ws_names, ws.name)
end

return M

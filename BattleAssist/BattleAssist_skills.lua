-- BattleAssist_skills.lua
-- 即死技・危険技の定義テーブル（ナイト向け）
-- phase: "cast"=構え検知, "impact"=発動検知, "both"=両方
--
-- ※ 技IDはデバッグログで実測確認すること
--   DEBUG_PACKET = true にして /addon reload BattleAssist 後、
--   チャットログの [BattleAssist DEBUG] action_id= の値を使う。

local M = {}

M.dangerous_skills = {

    -- === 即死技（Doom系） ===
    [220]  = { name = "ドゥーム",              level = "critical", phase = "cast" },
    [1928] = { name = "デス",                  level = "critical", phase = "cast" },

    -- === ナイトが遭遇しやすいボス技 ===
    [749]  = { name = "アブソリュートテラー",  level = "critical", phase = "cast" },
    [1246] = { name = "テラー",                level = "critical", phase = "cast" },

    -- 追加する場合はここに続けて記述する
    -- [技ID] = { name = "技名", level = "critical", phase = "cast" },

}

return M

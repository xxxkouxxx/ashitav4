-- DangerAlert_skills.lua
-- 危険技（即死技・状態異常技）の技ID定義テーブル
--
-- phase:
--   "cast"   : 詠唱開始時に検知 (category == 8 or 11)
--   "impact" : 発動時に検知    (category == 2)
--   "both"   : 両方
--
-- 技IDはデバッグログで実測確認すること
--   DangerAlert.lua の DEBUG_PACKET = true にして /addon reload DangerAlert
--   チャットログの [DangerAlert DEBUG] action_id= の値を使う

local M = {}

M.dangerous_skills = {

    -- === 即死技 (Doom系) ===
    [220]  = { name = "Doom",           level = "critical", phase = "cast" },
    [1928] = { name = "Death",          level = "critical", phase = "cast" },

    -- === 状態異常・危険技 ===
    [749]  = { name = "AbsoluteTerror", level = "critical", phase = "cast" },
    [1246] = { name = "Terror",         level = "critical", phase = "cast" },

    -- 追加する場合はここに続けて記述する
    -- [技ID] = { name = "技名", level = "critical", phase = "cast" },
}

return M

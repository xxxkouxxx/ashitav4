-- BattleAssist_skills.lua
-- 即死技・危険技の定義テーブル（ナイト向け）
--
-- フィールド説明:
--   name   : 技名（UI表示用）
--   effect : 効果説明（敵技ログに表示）
--   level  : "critical"（赤）/ "warning"（黄）/ "info"（白）
--   phase  : "cast"=構え検知, "impact"=発動検知, "both"=両方
--
-- ※ "-- ※要実測" のコメントが付いたIDはプレースホルダーです。
--   DEBUG_PACKET = true にして /addon reload BattleAssist 後、
--   チャットログの [BattleAssist DEBUG] action_id= の値を使ってください。

local M = {}

M.dangerous_skills = {

    -- === 即死技（Doom/Death系）===
    [220]  = { name = "ドゥーム",             effect = "カウントダウン即死",          level = "critical", phase = "cast"   },
    [1928] = { name = "デス",                 effect = "即死魔法",                    level = "critical", phase = "cast"   },

    -- === ナイトが遭遇しやすいボス技 ===
    [749]  = { name = "アブソリュートテラー", effect = "テラー（行動不能）",          level = "critical", phase = "cast"   },
    [1246] = { name = "テラー",               effect = "テラー（行動不能）",          level = "critical", phase = "cast"   },

    -- === トンベリ系 ===
    [298]  = { name = "千本針",               effect = "対象に1000固定ダメージ",      level = "critical", phase = "impact" }, -- ※要実測
    [299]  = { name = "ウラミ",               effect = "蘇生回数×100固定ダメージ",   level = "critical", phase = "impact" }, -- ※要実測
    [300]  = { name = "みんなのうらみ",       effect = "PT人数×蘇生数固定ダメージ",  level = "critical", phase = "impact" }, -- ※要実測
    [301]  = { name = "ランタンのひかり",     effect = "全ステータスDOWN",            level = "warning",  phase = "cast"   }, -- ※要実測

    -- === ゴブリン系 ===
    [410]  = { name = "ゴブリンラッシュ",    effect = "単体物理3段攻撃",             level = "warning",  phase = "impact" }, -- ※要実測
    [411]  = { name = "ランページ",           effect = "全方位物理範囲攻撃",          level = "warning",  phase = "impact" }, -- ※要実測
    [412]  = { name = "ゴブリンバスター",    effect = "範囲炎属性ダメージ",          level = "warning",  phase = "impact" }, -- ※要実測
    [413]  = { name = "ゴブリングライド",    effect = "突進・ノックバック",          level = "info",     phase = "impact" }, -- ※要実測

    -- === オーク系 ===
    [430]  = { name = "スピアストーム",       effect = "範囲物理ダメージ",            level = "warning",  phase = "impact" }, -- ※要実測
    [431]  = { name = "ウォークライ",         effect = "周囲の敵の攻撃力UP",          level = "warning",  phase = "cast"   }, -- ※要実測
    [432]  = { name = "マイティストライク",   effect = "単体大ダメージ",              level = "warning",  phase = "impact" }, -- ※要実測

    -- === アンデッド系 ===
    [450]  = { name = "ドレインタッチ",       effect = "HPドレイン",                  level = "warning",  phase = "impact" }, -- ※要実測
    [451]  = { name = "ペストブレス",         effect = "範囲毒ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [452]  = { name = "ボーンクラッシュ",    effect = "STR/VIT DOWN",                level = "warning",  phase = "impact" }, -- ※要実測
    [453]  = { name = "スリープガス",         effect = "範囲睡眠",                    level = "warning",  phase = "cast"   }, -- ※要実測
    [454]  = { name = "アンデッドエアレイド", effect = "範囲暗闇付与",               level = "info",     phase = "cast"   }, -- ※要実測

    -- === ワイバーン/ドラゴン系 ===
    [500]  = { name = "ファイアブレス",       effect = "範囲炎ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [501]  = { name = "アイスブレス",         effect = "範囲氷ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [502]  = { name = "サンダーブレス",       effect = "範囲雷ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [503]  = { name = "ポイズンブレス",       effect = "範囲毒ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [504]  = { name = "アシッドブレス",       effect = "防御・魔防DOWN",              level = "warning",  phase = "impact" }, -- ※要実測
    [505]  = { name = "チャージング",         effect = "突進・大ダメージ",            level = "critical", phase = "cast"   }, -- ※要実測
    [506]  = { name = "テールスイング",       effect = "範囲ノックバック",            level = "warning",  phase = "impact" }, -- ※要実測
    [507]  = { name = "グランドスラム",       effect = "範囲大ダメージ+ノックダウン", level = "warning",  phase = "impact" }, -- ※要実測

    -- === リッチ/ダークネス系 ===
    [550]  = { name = "ダークネスブレス",    effect = "範囲闇属性大ダメージ",        level = "warning",  phase = "impact" }, -- ※要実測
    [551]  = { name = "メイズブラスト",      effect = "範囲混乱付与",                level = "warning",  phase = "cast"   }, -- ※要実測
    [552]  = { name = "デスクラウド",        effect = "範囲ドゥーム蓄積ガス",        level = "critical", phase = "cast"   }, -- ※要実測

    -- === サハギン系 ===
    [620]  = { name = "アクアブレス",        effect = "範囲水ブレス",                level = "warning",  phase = "impact" }, -- ※要実測
    [621]  = { name = "クリティカルバイト",  effect = "単体大ダメージ",              level = "warning",  phase = "impact" }, -- ※要実測
    [622]  = { name = "タイダルウェーブ",   effect = "範囲水属性ダメージ（大）",    level = "critical", phase = "impact" }, -- ※要実測

    -- === クゥダフ系 ===
    [640]  = { name = "バルダーブレイカー",  effect = "範囲デバフ+ダメージ",         level = "warning",  phase = "impact" }, -- ※要実測
    [641]  = { name = "ドラムビート",        effect = "範囲スタン付与",              level = "warning",  phase = "cast"   }, -- ※要実測

    -- === ボス・NM汎用 ===
    [700]  = { name = "カーズスフィア",      effect = "範囲全デバフ付与",            level = "critical", phase = "cast"   }, -- ※要実測
    [701]  = { name = "ドレッドウィンド",   effect = "範囲HP半減",                  level = "critical", phase = "impact" }, -- ※要実測
    [702]  = { name = "グラビスフィア",      effect = "範囲重力付与",                level = "warning",  phase = "cast"   }, -- ※要実測
    [703]  = { name = "ペトリフィケーション",effect = "石化付与",                    level = "critical", phase = "cast"   }, -- ※要実測
    [704]  = { name = "カオスブレス",        effect = "範囲全属性混合ブレス",        level = "critical", phase = "impact" }, -- ※要実測
    [705]  = { name = "アバドンクラッシュ",  effect = "単体即死級ダメージ",          level = "critical", phase = "impact" }, -- ※要実測
    [706]  = { name = "スピンアタック",      effect = "範囲物理回転攻撃",            level = "warning",  phase = "impact" }, -- ※要実測
    [707]  = { name = "スロウガス",          effect = "範囲スロウ付与",              level = "info",     phase = "cast"   }, -- ※要実測
    [708]  = { name = "アシッドミスト",      effect = "範囲防御DOWN",                level = "info",     phase = "cast"   }, -- ※要実測
    [709]  = { name = "アームスマッシュ",   effect = "単体防御DOWN+大ダメージ",     level = "warning",  phase = "impact" }, -- ※要実測

    -- === オデッセイ・ジェール ===
    -- 技名リスト確定後に追加する:
    -- [TODO_ID] = { name = "技名", effect = "効果", level = "critical|warning|info", phase = "cast|impact" },

}

return M

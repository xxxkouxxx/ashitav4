-- ============================================================
-- CorDice.lua
-- Ashita v4 アドオン - コルセア ファントムロール可視化ツール
-- 機能: 全ロール出目・効果値 + アビリティリキャスト表示
-- ============================================================

addon.name    = 'CorDice'
addon.author  = '7xxxk'
addon.version = '0.3.0'
addon.desc    = 'コルセア ファントムロール可視化 (出目/効果/アビリティ)'

require('common')
local imgui    = require('imgui')
local settings = require('settings')
local tables   = require('CorDice_tables')

-- ============================================================
-- デバッグモード
-- バフID特定: true にして各ロールをかけ、チャットログの
--   [CorDice DEBUG] slot[n] bid= の値を確認する。
-- アビリティインデックス特定: アビリティ使用後に
--   ability[n] timer= の出力を確認する。
-- ============================================================
local DEBUG_MODE     = false
local DEBUG_LOG_FILE = AshitaCore:GetInstallPath() .. 'logs\\CorDice_debug.log'

local function debug_log(msg)
    if not DEBUG_MODE then return end
    local ts   = os.date('%H:%M:%S')
    local line = string.format('[%s] %s\n', ts, msg)
    print('[CorDice DEBUG] ' .. msg)
    local f = io.open(DEBUG_LOG_FILE, 'a')
    if f then
        f:write(line)
        f:close()
    end
end

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    x              = 100,
    y              = 100,
    alpha          = 0.8,
    show_abilities = true,
    auto_notify    = false,  -- ロール確定時に /p 自動通知
}
local cfg = T{}

settings.register('settings', 'cordice_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- 状態管理
-- ============================================================
-- active_rolls[buff_id] = {
--     dice = 出目 (1〜11, またはnil=解析中),
-- }
local active_rolls = {}

-- Fold 等でロールが消えた後、メモリチェックでクリアするための最終確認時刻
local last_buff_poll = 0

-- wild_card_result: Wild Card 使用時の結果を一時保持（WILDCARD_SHOW_DURATION 秒後に非表示）
local wild_card_result = {
    dice     = nil,    -- 出目数値 (1〜6): animation - 131 で取得
    effect   = nil,    -- 効果種別: "SP" / "JAs+TP" / "JAs" / nil（dice が取れない場合の fallback）
    shown_at = 0,      -- os.time() タイムスタンプ
}

-- cut_card_result: Cut Card 使用時の結果を一時保持
local cut_card_result = {
    dice     = nil,    -- 出目数値 (1〜6): animation - 320 で取得
    shown_at = 0,
}

-- dice_queue: 0x028で取得した出目を 0x063 が来るまで保持
local dice_queue = {
    last_val     = nil,
    timestamp    = 0,
    is_double_up = false,  -- ダブルアップ由来かどうか（fallback用）
    roll_id      = nil,    -- 0x028 の roll_id（どのロールか識別）
}

-- roll_id → buff_id マッピング（初回ロール時に自動学習）
-- ダブルアップ時に「どの buff_id を更新すべきか」を roll_id で判断する
local roll_id_map = {}

-- pending_buff_check: 0x063 到着を d3d_present に伝えるフラグ
-- 0x063 ハンドラ内では GetBuffs() がまだ古い状態を返すことがある（メモリ更新遅延）
-- → 次の d3d_present フレームでメモリが確実に更新されてからバフ処理を行う
local pending_buff_check = false

-- ============================================================
-- Wild Card 設定
-- ============================================================
-- Wild Card の 0x028 パケット roll_id 値（実測確認: category=6, roll_id=96）
local WILDCARD_ROLL_ID       = 96
-- Cut Card の 0x028 パケット roll_id 値
local CUTCARD_ROLL_ID        = 339
-- Wild Card アビリティの GetAbilityTimer インデックス
-- abiscan 実測: ability[0]=2094s (使用10分後) → 45分リキャスト (2700s) に一致
local WILDCARD_ABILITY_INDEX = 0
-- Wild Card / Cut Card 出目の表示継続秒数
local WILDCARD_SHOW_DURATION = 8


-- ============================================================
-- アビリティ定義
-- ※ index は GetAbilityTimer() に渡すインデックス（要実測）
-- ============================================================
local ABILITIES = {
    { name = 'Double Up',    index = 2  },   -- COR/踊 実測確認済み
    { name = 'Snake Eye',    index = 6  },   -- COR/踊 abiscan実測: ability[6]=Snake Eye
    { name = 'Crookd Cards', index = 21 },   -- COR/踊 abiscan実測: ability[21]=Crookd Cards
    { name = 'Fold',         index = 7  },   -- COR/踊 abiscan実測: ability[7]=Fold
    { name = 'Cut Card',     index = 10 },   -- 未確認（Ready のため未測定）
    { name = 'Wild Card',    index = WILDCARD_ABILITY_INDEX },  -- TODO: 実測後に index を埋める
}

-- スネークアイ・クルケッドカード 効果中バフID（※要実測）
local BUFF_SNAKE_EYE     = 357  -- 実測確認済み
local BUFF_CROOKED_CARDS = 601  -- 実測確認済み
-- ダブルアップ可能状態バフID（実測確認済み）
local BUFF_DOUBLE_UP_CHANCE = 308

-- ============================================================
-- カラー定数
-- ============================================================
local COL_LUCKY   = { 0.3, 1.0, 0.3, 1.0 }   -- 緑（ラッキー）
local COL_UNLUCKY = { 1.0, 0.3, 0.3, 1.0 }   -- 赤（アンラッキー）
local COL_ELEVEN  = { 1.0, 0.85, 0.0, 1.0 }  -- 金（11ゾロ）
local COL_NORMAL  = { 1.0, 1.0, 1.0, 1.0 }   -- 白（通常）
local COL_TITLE   = { 0.6, 0.85, 1.0, 1.0 }  -- 水色（ヘッダー）
local COL_READY   = { 0.4, 1.0, 0.4, 1.0 }   -- 緑（リキャスト完了）
local COL_RECAST  = { 1.0, 0.75, 0.0, 1.0 }  -- 橙（リキャスト中）
local COL_DIM     = { 0.5, 0.5, 0.5, 1.0 }   -- グレー（非アクティブ）
-- Wild Card 出目色分け
local COL_WC_SP     = { 0.0, 1.0, 1.0, 1.0 }  -- シアン（5/6: SPアビ回復）
local COL_WC_NORMAL = { 0.85, 0.65, 1.0, 1.0 } -- 薄紫（1〜4: 通常効果）

-- ============================================================
-- ヘルパー関数
-- ============================================================
local function has_buff(buff_id)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return false end
    local buffs = player:GetBuffs()
    for i = 0, 31 do
        if buffs[i] == buff_id then return true end
    end
    return false
end

local function get_roll_color(dice, def)
    if dice == 11          then return COL_ELEVEN  end
    if dice == def.lucky   then return COL_LUCKY   end
    if dice == def.unlucky then return COL_UNLUCKY end
    return COL_NORMAL
end

-- バスト確率 (0.0〜1.0): 現在の出目からダブルアップした場合に 12+ になる割合
-- dice+roll > 11 となる roll の数 / 6
local function bust_rate(dice)
    return math.max(0, dice - 5) / 6
end

-- バスト確率の表示色
local function bust_color(rate)
    if rate == 0   then return COL_READY   end   -- 緑 (0%: 安全)
    if rate <= 0.5 then return COL_RECAST  end   -- 橙 (〜50%: 中リスク)
    return COL_UNLUCKY                           -- 赤 (67%〜: 高リスク)
end

-- Shift-JIS 丸数字テーブル: ①〜⑪ (0x87 0x40〜0x4A)
-- Roll Tracker と同じ方式で出目を丸数字で表示する
local CIRCLED = {}
for i = 1, 11 do
    CIRCLED[i] = string.char(0x87, 0x3F + i)
end

-- ============================================================
-- Shift-JIS ロール名テーブル (buff_id → Shift-JIS バイト列)
-- print() に渡す文字列は Shift-JIS が必要なため string.char() で明示定義
-- カタカナ対応表 (先頭 0x83、2バイト目は下記):
--   ア=41 イ=43 ウ=45 エ=47 オ=49 カ=4A キ=4C ク=4E ケ=50 コ=52
--   サ=54 シ=56 ス=58 セ=5A ソ=5C タ=5E チ=60 ツ=63 テ=65 ト=67
--   ナ=69 ニ=6A ヌ=6B ノ=6D ハ=6E ヒ=71 フ=74 ヘ=77 ホ=7A
--   マ=7D ミ=7E ム=80 メ=81 モ=82 ヤ=84 ユ=86 ヨ=88
--   ラ=89 リ=8A ル=8B ル=8B ロ=8D ワ=8F ン=93 ヴ=94
--   濁音: ガ=4B ギ=4D グ=4F ゾ=5D ダ=5F ヂ=61 ヅ=64 デ=66 ド=68
--         バ=6F ビ=72 ブ=75 ベ=78 ボ=7B ザ=55 ジ=57 ズ=59
--   半濁: パ=70 ピ=73 プ=76 ペ=79 ポ=7C
--   小字: ァ=40 ィ=42 ゥ=44 ォ=48 ッ=62 ャ=83 ュ=85 ョ=87
--   長音: ー = 0x81 0x5C
-- ============================================================
local ROLL_JP_SJIS = {
    [310] = string.char(0x83,0x74, 0x83,0x40, 0x83,0x43, 0x83,0x5E, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ファイターズロール
    [311] = string.char(0x83,0x82, 0x83,0x93, 0x83,0x4E, 0x83,0x58,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- モンクスロール
    [312] = string.char(0x83,0x71, 0x81,0x5C, 0x83,0x89, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ヒーラーズロール
    [313] = string.char(0x83,0x45, 0x83,0x42, 0x83,0x55, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ウィザーズロール
    [314] = string.char(0x83,0x45, 0x83,0x48, 0x81,0x5C, 0x83,0x8D,
                        0x83,0x62, 0x83,0x4E, 0x83,0x58,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ウォーロックスロール
    [315] = string.char(0x83,0x8D, 0x81,0x5C, 0x83,0x4F, 0x83,0x58,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ローグスロール
    [316] = string.char(0x83,0x4B, 0x83,0x89, 0x83,0x93, 0x83,0x63,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ガランツロール
    [317] = string.char(0x83,0x4A, 0x83,0x49, 0x83,0x58,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- カオスロール
    [318] = string.char(0x83,0x72, 0x81,0x5C, 0x83,0x58, 0x83,0x67,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ビーストロール
    [319] = string.char(0x83,0x52, 0x81,0x5C, 0x83,0x54, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- コーサーズロール
    [320] = string.char(0x83,0x6E, 0x83,0x93, 0x83,0x5E, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ハンターズロール
    [321] = string.char(0x83,0x54, 0x83,0x80, 0x83,0x89, 0x83,0x43,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- サムライロール
    [322] = string.char(0x83,0x6A, 0x83,0x93, 0x83,0x57, 0x83,0x83,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ニンジャロール
    [323] = string.char(0x83,0x68, 0x83,0x89, 0x83,0x62, 0x83,0x77,
                        0x83,0x93, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ドラッヘンロール
    [324] = string.char(0x83,0x47, 0x83,0x94, 0x83,0x48, 0x81,0x5C,
                        0x83,0x4A, 0x81,0x5C, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- エヴォーカーズロール
    [325] = string.char(0x83,0x81, 0x83,0x43, 0x83,0x4B, 0x83,0x58,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- メイガスロール
    [326] = string.char(0x83,0x52, 0x83,0x8B, 0x83,0x5A, 0x83,0x41,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- コルセアズロール
    [327] = string.char(0x83,0x70, 0x83,0x79, 0x83,0x62, 0x83,0x67,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- パペットロール
    [328] = string.char(0x83,0x5F, 0x83,0x93, 0x83,0x54, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ダンサーズロール
    [329] = string.char(0x83,0x58, 0x83,0x4A, 0x83,0x89, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- スカラーズロール
    [330] = string.char(0x83,0x7B, 0x83,0x8B, 0x83,0x5E, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ボルターズロール
    [331] = string.char(0x83,0x4C, 0x83,0x83, 0x83,0x58, 0x83,0x5E,
                        0x81,0x5C, 0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- キャスターズロール
    [332] = string.char(0x83,0x4D, 0x83,0x83, 0x83,0x93, 0x83,0x75,
                        0x83,0x89, 0x81,0x5C, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ギャンブラーズロール
    [333] = string.char(0x83,0x75, 0x83,0x8A, 0x83,0x62, 0x83,0x63,
                        0x83,0x40, 0x81,0x5C, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ブリッツァーズロール
    [334] = string.char(0x83,0x5E, 0x83,0x4E, 0x83,0x65, 0x83,0x42,
                        0x83,0x56, 0x83,0x83, 0x83,0x93, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- タクティシャンズロール
    [335] = string.char(0x83,0x41, 0x83,0x89, 0x83,0x43, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- アライズロール
    [336] = string.char(0x83,0x7D, 0x83,0x43, 0x83,0x55, 0x81,0x5C,
                        0x83,0x59, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- マイザーズロール
    [337] = string.char(0x83,0x52, 0x83,0x93, 0x83,0x70, 0x83,0x6A,
                        0x83,0x49, 0x83,0x93, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- コンパニオンズロール
    [338] = string.char(0x83,0x41, 0x83,0x78, 0x83,0x93, 0x83,0x57,
                        0x83,0x83, 0x81,0x5C, 0x83,0x59,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- アベンジャーズロール
    [339] = string.char(0x83,0x69, 0x83,0x60, 0x83,0x85, 0x83,0x89,
                        0x83,0x8A, 0x83,0x58, 0x83,0x67,
                        0x83,0x8D, 0x81,0x5C, 0x83,0x8B),             -- ナチュラリストロール
    [600] = string.char(0x83,0x8B, 0x81,0x5C, 0x83,0x93, 0x83,0x69,
                        0x83,0x43, 0x83,0x67, 0x83,0x8D, 0x81,0x5C, 0x83,0x8B), -- ルーンナイトロール
}

-- Wild Card の Shift-JIS 名: ワイルドカード
local WC_JP_SJIS = string.char(
    0x83,0x8F, 0x83,0x43, 0x83,0x8B, 0x83,0x68,
    0x83,0x4A, 0x81,0x5C, 0x83,0x68)

-- 出目ラベル文字列（Lucky/Unlucky/11）
local function dice_label(dice, def)
    if     dice == 11          then return ' [11!!]'
    elseif dice == def.lucky   then return ' [Lucky!]'
    elseif dice == def.unlucky then return ' [Unlucky]'
    end
    return ''
end

-- ローカルチャットログ通知（Roll Tracker スタイル）
-- print() は Ashita が FFXI 内チャットログに描画するため常時表示
-- \31\200 = 白, \31\05 = 青, \31\190 = 薄白（Roll Tracker と同じ色コード）
local function print_notify(msg)
    print('\31\200[\31\05CorDice\31\200]\31\190 ' .. msg)
end

-- /p 自動通知: 通常ロール確定時
-- ・print() でローカルに丸数字付き表示（常時）
-- ・auto_notify ON の時のみ /p でパーティ通知（ASCII）
local function send_party_notify(roll_name, dice, def)
    local label    = dice_label(dice, def)
    local bust     = bust_rate(dice)
    local bust_str = bust == 0
        and ''
        or string.format(' Bust:%d%%', math.floor(bust * 100 + 0.5))

    -- ローカル表示: 丸数字で見やすく（常時出力）
    -- roll_name は呼び出し元で ROLL_JP_SJIS[buff_id] に差し替え済み
    print_notify(string.format('%s %s%s%s',
        roll_name, CIRCLED[dice] or tostring(dice), label, bust_str))

    -- /p パーティ通知（ON 時のみ、ASCII）
    if cfg.auto_notify then
        AshitaCore:GetChatManager():QueueCommand(
            1, string.format('/p [%s] %d%s%s', roll_name, dice, label, bust_str))
    end
end

-- Cut Card の Shift-JIS 名: カットカード
local CC_JP_SJIS = string.char(
    0x83,0x4A, 0x83,0x62, 0x83,0x67,
    0x83,0x4A, 0x81,0x5C, 0x83,0x68)

-- /p 自動通知: Wild Card 確定時
local function send_wc_notify()
    local dice = wild_card_result.dice
    local is_sp, label

    if dice then
        -- animation から出目が取れた場合
        is_sp = dice >= 5
        label = string.format('%s (%s)',
            CIRCLED[dice] or tostring(dice),
            is_sp and 'SP Reset!!' or 'TP/MP')
    elseif wild_card_result.effect then
        -- fallback: message フィールドから効果種別のみ
        is_sp = wild_card_result.effect == 'SP'
        label = is_sp and 'SP Reset!!' or wild_card_result.effect
    else
        return
    end

    -- ローカル表示（常時出力）
    print_notify(WC_JP_SJIS .. ' ' .. label)

    -- /p パーティ通知（ON 時のみ、ASCII）
    if cfg.auto_notify then
        if dice then
            AshitaCore:GetChatManager():QueueCommand(
                1, string.format('/p [Wild Card] %d (%s)',
                    dice, is_sp and 'SP Reset' or 'TP/MP'))
        else
            AshitaCore:GetChatManager():QueueCommand(
                1, string.format('/p [Wild Card] %s', label))
        end
    end
end

-- /p 自動通知: Cut Card 確定時
local function send_cc_notify()
    local dice = cut_card_result.dice
    if not dice then return end
    local circled = CIRCLED[dice] or tostring(dice)

    -- ローカル表示（常時出力）: CC_JP_SJIS = カットカード
    print_notify(CC_JP_SJIS .. ' ' .. circled)

    -- /p パーティ通知（ON 時のみ、ASCII）
    if cfg.auto_notify then
        AshitaCore:GetChatManager():QueueCommand(
            1, string.format('/p [Cut Card] %d', dice))
    end
end


-- ============================================================
-- ============================================================
-- パケット監視: 0x028 アクションパケット（出目取得）
-- Roll Tracker 参考: big-endian ビットストリーム解析
--   category (bit 82, 4bit) == 6 → コルセアロール
--   roll_number (bit 213, 17bit) → 出目合計値（1-11=有効, 12+=バスト）
-- ============================================================

-- Ashita bits.unpack_be 互換: LSB-first ビット抽出
-- ビット N = byte[N//8] の bit(N%8)、ビット i は 2^i の重みを持つ
local function bits_be(data, bit_offset, bit_count)
    local result = 0
    for i = 0, bit_count - 1 do
        local abs_bit  = bit_offset + i
        local byte_idx = math.floor(abs_bit / 8)
        local bit_pos  = abs_bit % 8  -- LSB-first
        local byte_val = struct.unpack('B', data, byte_idx + 1)  -- 1-based
        local bit_val  = bit.band(bit.rshift(byte_val, bit_pos), 1)
        result = bit.bor(result, bit.lshift(bit_val, i))  -- bit i → 2^i
    end
    return result
end

ashita.events.register('packet_in', 'cordice_packet_0x028', function(e)
    if e.id ~= 0x028 then return end

    local ok, err = pcall(function()
        local category    = bits_be(e.data, 82, 4)
        local roll_number = bits_be(e.data, 213, 17)
        -- roll_id (bit 86, 10bit): どのロールに対する出目かを示すID
        local roll_id     = bits_be(e.data, 86, 10)
        -- actor: パケット送信者のサーバーID (byte 4-7, 1-based offset 5)
        local actor       = struct.unpack('I', e.data, 5)
        local my_id       = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)

        debug_log(string.format('0x028: category=%d roll_number=%d roll_id=%d actor=%d my_id=%d',
            category, roll_number, roll_id, actor, my_id))

        -- Wild Card / Cut Card 検出: category=6 かつ roll_id が WC/CC
        -- 出目の取得方法（yyoshisaur ブログ 2025/09/06 より）:
        --   per-action animation (offset+5, 12bit) から計算
        --   Wild Card: dice = animation - 131
        --   Cut Card:  dice = animation - 320
        -- 効果種別は message フィールド (offset+44, 10bit) から取得（fallback 用）
        --   435/436=JAs, 437/438=JAs+TP, 439/440=SP
        if category == 6 and (roll_id == WILDCARD_ROLL_ID or roll_id == CUTCARD_ROLL_ID) then
            local now = os.time()
            local is_wc = roll_id == WILDCARD_ROLL_ID
            debug_log(string.format('%s 0x028: actor_is_me=%s pkt_size=%d',
                is_wc and 'wild card' or 'cut card', tostring(actor == my_id), #e.data))

            -- 最初のターゲットの最初のアクションから animation と message を読む
            local target_count = bits_be(e.data, 72, 10)
            local anim, wc_msg
            if target_count >= 1 then
                local a_offset = 150 + 36  -- target: server_id(32)+action_count(4)=36
                anim   = bits_be(e.data, a_offset + 5,  12)
                wc_msg = bits_be(e.data, a_offset + 44, 10)
            end

            if is_wc then
                -- Wild Card: dice = animation - 131
                local dice = anim and (anim - 131) or nil
                if dice and dice >= 1 and dice <= 6 then
                    wild_card_result.dice   = dice
                    wild_card_result.effect = nil
                else
                    -- animation から取れない場合は message フィールドで効果種別のみ
                    wild_card_result.dice = nil
                    if     wc_msg == 439 or wc_msg == 440 then wild_card_result.effect = 'SP'
                    elseif wc_msg == 437 or wc_msg == 438 then wild_card_result.effect = 'JAs+TP'
                    elseif wc_msg == 435 or wc_msg == 436 then wild_card_result.effect = 'JAs'
                    else                                        wild_card_result.effect = nil
                    end
                end
                debug_log(string.format('wc_parse: anim=%s dice=%s msg=%s',
                    tostring(anim), tostring(wild_card_result.dice), tostring(wc_msg)))
                wild_card_result.shown_at = now
                send_wc_notify()
            else
                -- Cut Card: dice = animation - 320
                local dice = anim and (anim - 320) or nil
                if dice and dice >= 1 and dice <= 6 then
                    cut_card_result.dice     = dice
                    cut_card_result.shown_at = now
                    debug_log(string.format('cc_parse: anim=%s dice=%d', tostring(anim), dice))
                    send_cc_notify()
                else
                    debug_log(string.format('cc_parse: anim=%s dice out of range', tostring(anim)))
                end
            end
            return
        end

        if category ~= 6 then return end

        if roll_number >= 1 and roll_number <= 11 then
            local is_du = has_buff(BUFF_DOUBLE_UP_CHANCE)
            dice_queue.last_val     = roll_number
            dice_queue.timestamp    = os.time()
            dice_queue.is_double_up = is_du
            dice_queue.roll_id      = roll_id  -- どのロールか識別するため記録
            debug_log(string.format('roll captured: %d is_double_up=%s roll_id=%d actor_is_me=%s',
                roll_number, tostring(is_du), roll_id, tostring(actor == my_id)))
        elseif roll_number > 11 and roll_number < 0x1FFFF then
            -- roll_number が範囲外（Crookd Cards 使用時などの特殊パケット）→ 無視
            debug_log(string.format('unknown roll(skip): roll_id=%d roll_number=%d', roll_id, roll_number))
        end
    end)
    if not ok then
        debug_log('0x028 error: ' .. tostring(err))
    end
end)



-- ============================================================
-- バフ状態処理: dice_queue の出目を active_rolls に割り当てる
-- ※ 0x063 到着時・毎 d3d_present フレームで呼ばれる
--   dice_queue.last_val が nil のときは即 return（軽量）
--   バフがメモリに未反映の場合は次フレームで再試行する
--   タイムアウト: 30 秒（DU Chance が切れてから 0x063 が来るケースに対応）
-- ※ ロール切れ検出は 2 秒ポーリング（d3d_present の poll ブロック）が担当
-- ============================================================
local function process_roll_buffs()
    if not dice_queue.last_val then return end
    local now = os.time()
    if (now - dice_queue.timestamp) >= 30 then
        debug_log('dice_queue timeout: ' .. tostring(dice_queue.roll_id))
        dice_queue.last_val = nil
        return
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then return end
    local mem_buffs = player:GetBuffs()

    local mapped_bid = dice_queue.roll_id and roll_id_map[dice_queue.roll_id] or nil
    local claimed_buff_ids = {}
    for _, bid in pairs(roll_id_map) do
        claimed_buff_ids[bid] = true
    end
    -- ロード時に active_rolls に追加されたが roll_id_map 未登録のバフも claimed 扱い
    -- （既存ロールの buff_id を別ロールの初回割り当てで上書きしないようにする）
    for bid in pairs(active_rolls) do
        claimed_buff_ids[bid] = true
    end

    for i = 0, 31 do
        local buff_id = mem_buffs[i]
        if buff_id and tables.rolls[buff_id] then
            local was_active = active_rolls[buff_id] ~= nil

            if not was_active then
                -- ★ 新規バフ → 初回ロール
                if dice_queue.roll_id then
                    roll_id_map[dice_queue.roll_id] = buff_id
                    debug_log(string.format('roll_id_map: roll_id=%d -> buff_id=%d',
                        dice_queue.roll_id, buff_id))
                end
                active_rolls[buff_id] = { dice = dice_queue.last_val, notify_at = os.time() + 3 }
                debug_log(string.format('assigned(new): buff_id=%d dice=%d',
                    buff_id, dice_queue.last_val))
                dice_queue.last_val = nil
                return
            elseif buff_id == mapped_bid then
                -- ★ ダブルアップ（既知マッピング）: タイマーをリセットして3秒後に通知
                debug_log(string.format('assigned(DU): buff_id=%d %s->%d',
                    buff_id, tostring(active_rolls[buff_id] and active_rolls[buff_id].dice), dice_queue.last_val))
                active_rolls[buff_id] = { dice = dice_queue.last_val, notify_at = os.time() + 3 }
                dice_queue.last_val = nil
                return
            elseif dice_queue.roll_id and (roll_id_map[dice_queue.roll_id] == nil)
                   and not claimed_buff_ids[buff_id] then
                -- ★ 初回ロール（roll_id_map 未登録）
                roll_id_map[dice_queue.roll_id] = buff_id
                active_rolls[buff_id] = { dice = dice_queue.last_val, notify_at = os.time() + 3 }
                debug_log(string.format('assigned(first): buff_id=%d dice=%d roll_id=%d',
                    buff_id, dice_queue.last_val, dice_queue.roll_id))
                dice_queue.last_val = nil
                return
            end
        end
    end
    -- バフがまだメモリに未反映 → 次フレームで再試行（ログなし・高頻度なのでスキップ）
end

-- ============================================================
-- パケット監視: 0x063 バフステータス更新
-- ★ 追加トリガーとして pending_buff_check をセット
--   メイン処理は d3d_present の毎フレーム呼び出しが担当
-- ============================================================
ashita.events.register('packet_in', 'cordice_packet_0x063', function(e)
    if e.id ~= 0x063 then return end
    pending_buff_check = true
end)

-- ============================================================
-- アビリティインデックス実測用スキャン（DEBUG_MODE時のみ）
-- ============================================================
local ability_scan_requested = false

local function debug_scan_abilities()
    if not ability_scan_requested then return end
    ability_scan_requested = false

    local recast = AshitaCore:GetMemoryManager():GetRecast()
    -- スキャン結果はログファイルと画面に出力（DEBUG_MODE に依存しない）
    local ts   = os.date('%H:%M:%S')
    local function scan_log(msg)
        print('[CorDice DEBUG] ' .. msg)
        local f = io.open(DEBUG_LOG_FILE, 'a')
        if f then f:write(string.format('[%s] %s\n', ts, msg)) f:close() end
    end
    scan_log('--- ability recast scan ---')
    for i = 0, 200 do
        local t = recast:GetAbilityTimer(i)
        -- 0xFFFF0000 以上はゴミ値（uint32 オーバーフロー）なのでスキップ
        if t and t > 0 and t < 0xFFFF0000 then
            -- GetAbilityTimer は 1/60秒単位
            scan_log(string.format('  ability[%d] = %d (%.1f s)', i, t, t / 60.0))
        end
    end
    scan_log('--- scan end ---')
end

-- ============================================================
-- コマンドハンドラ
-- /cordice abiscan  → アビリティインデックス全スキャン（実測用）
-- /cordice reset    → active_rolls をクリア
-- ============================================================
ashita.events.register('command', 'cordice_command', function(e)
    -- コマンドを空白で分割
    local parts = {}
    for w in e.command:gmatch('%S+') do
        parts[#parts + 1] = w:lower()
    end
    if #parts == 0 or parts[1] ~= '/cordice' then return end
    e.blocked = true

    local sub = parts[2] or ''
    if sub == 'abiscan' then
        ability_scan_requested = true
        print('[CorDice] アビリティスキャン開始...')
    elseif sub == 'reset' then
        active_rolls              = {}
        roll_id_map               = {}
        wild_card_result.dice     = nil
        wild_card_result.effect   = nil
        wild_card_result.shown_at = 0
        cut_card_result.dice      = nil
        cut_card_result.shown_at  = 0
        print('[CorDice] ロール表示をリセットしました。')
    elseif sub == 'wc' then
        -- Wild Card 出目の手動設定（パケット解析で効果種別が取れなかった場合のフォールバック）
        local n = tonumber(parts[3])
        if n and n >= 1 and n <= 6 then
            wild_card_result.dice     = n
            wild_card_result.effect   = nil
            wild_card_result.shown_at = os.time()
            send_wc_notify()
            print(string.format('[CorDice] Wild Card set: %d', n))
        else
            print('[CorDice] 使用方法: /cordice wc <1-6>')
        end
    elseif sub == 'notify' then
        -- /p 自動通知の ON/OFF 切り替え
        local val = parts[3] or ''
        if val == 'on' then
            cfg.auto_notify = true
            settings.save()
            print('[CorDice] /p 自動通知: ON')
        elseif val == 'off' then
            cfg.auto_notify = false
            settings.save()
            print('[CorDice] /p 自動通知: OFF')
        else
            print(string.format('[CorDice] 自動通知は現在 %s です。', cfg.auto_notify and 'ON' or 'OFF'))
            print('  /cordice notify on  - 通知を有効化')
            print('  /cordice notify off - 通知を無効化')
        end
    else
        print('[CorDice] コマンド一覧:')
        print('  /cordice abiscan       - アビリティindex全スキャン（ログ出力）')
        print('  /cordice reset         - ロール表示クリア')
        print('  /cordice wc <1-6>      - Wild Card 出目を手動設定')
        print('  /cordice notify on/off - /p 自動通知の ON/OFF')
    end
end)

-- ============================================================
-- UIサブ関数: ロール1件の描画
-- ============================================================
local function draw_roll_entry(buff_id, data)
    local def = tables.rolls[buff_id]
    if not def then return end

    if data.dice then
        local col    = get_roll_color(data.dice, def)
        local label  = ''
        if     data.dice == 11          then label = ' [11!]'
        elseif data.dice == def.lucky   then label = ' [Lucky]'
        elseif data.dice == def.unlucky then label = ' [Unlucky]'
        end

        -- ロール名 + ダイス + Lucky/Unlucky + バスト確率 を1行
        imgui.PushStyleColor(ImGuiCol_Text, COL_TITLE)
        imgui.Text(def.name)
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, col)
        imgui.Text(string.format('%d%s', data.dice, label))
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, COL_LUCKY)
        imgui.Text(string.format('L:%d', def.lucky))
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, COL_UNLUCKY)
        imgui.Text(string.format('U:%d', def.unlucky))
        imgui.PopStyleColor()
        imgui.SameLine()
        local bust = bust_rate(data.dice)
        imgui.PushStyleColor(ImGuiCol_Text, bust_color(bust))
        imgui.Text(string.format('DU:%d%%bust', math.floor(bust * 100 + 0.5)))
        imgui.PopStyleColor()

        -- 効果値
        local effect = def.rolls[data.dice]
        imgui.PushStyleColor(ImGuiCol_Text, col)
        imgui.Text(string.format('  +%s%s', tostring(effect), def.unit))
        imgui.PopStyleColor()
    else
        -- 出目未確定
        imgui.PushStyleColor(ImGuiCol_Text, COL_TITLE)
        imgui.Text(def.name)
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, COL_DIM)
        imgui.Text('...')
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, COL_LUCKY)
        imgui.Text(string.format('L:%d', def.lucky))
        imgui.PopStyleColor()
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, COL_UNLUCKY)
        imgui.Text(string.format('U:%d', def.unlucky))
        imgui.PopStyleColor()
    end

    imgui.Separator()
end

-- ============================================================
-- UIサブ関数: アビリティセクションの描画
-- ============================================================
local function draw_abilities()
    imgui.PushStyleColor(ImGuiCol_Text, COL_TITLE)
    imgui.Text('- Abilities -')
    imgui.PopStyleColor()

    local recast = AshitaCore:GetMemoryManager():GetRecast()

    for _, ab in ipairs(ABILITIES) do
        if ab.index == nil then
            -- index 未設定（要実測）のアビリティはリキャスト表示をスキップ
            imgui.PushStyleColor(ImGuiCol_Text, COL_DIM)
            imgui.Text(string.format('  %-15s [?]', ab.name))
            imgui.PopStyleColor()
        else
            local timer_cs = recast:GetAbilityTimer(ab.index)
            local is_ready = (timer_cs == 0)

            if is_ready then
                imgui.PushStyleColor(ImGuiCol_Text, COL_READY)
                imgui.Text(string.format('  %-15s [Ready]', ab.name))
                imgui.PopStyleColor()
            else
                -- GetAbilityTimer は 1/60秒単位で返すため 60.0 で割る
                local secs = timer_cs / 60.0
                local disp = secs >= 60
                    and string.format('%d:%02d', math.floor(secs/60), math.floor(secs%60))
                    or  string.format('%5.1f s', secs)
                imgui.PushStyleColor(ImGuiCol_Text, COL_RECAST)
                imgui.Text(string.format('  %-15s [%s]', ab.name, disp))
                imgui.PopStyleColor()
            end
        end
    end

    if has_buff(BUFF_DOUBLE_UP_CHANCE) then
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('  * Double-Up Chance!')
        imgui.PopStyleColor()
    end
    if has_buff(BUFF_SNAKE_EYE) then
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('  * Snake Eye Active')
        imgui.PopStyleColor()
    end
    if has_buff(BUFF_CROOKED_CARDS) then
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('  * Crooked Cards Active')
        imgui.PopStyleColor()
    end

    -- Wild Card: 使用後 WILDCARD_SHOW_DURATION 秒間だけ表示
    -- SP = シアン、JAs+TP / JAs = 薄紫
    local now_t = os.time()
    local wc_active = wild_card_result.shown_at > 0 and
                      (now_t - wild_card_result.shown_at) < WILDCARD_SHOW_DURATION
    if wc_active then
        local dice  = wild_card_result.dice
        local is_sp = (dice and dice >= 5) or (wild_card_result.effect == 'SP')
        local wc_col = is_sp and COL_WC_SP or COL_WC_NORMAL
        local label
        if dice then
            label = string.format('%s (%s)',
                CIRCLED[dice] or tostring(dice),
                is_sp and 'SP Reset!!' or 'TP/MP')
        elseif wild_card_result.effect then
            label = is_sp and 'SP Reset!!' or wild_card_result.effect
        else
            label = '?'
        end
        imgui.PushStyleColor(ImGuiCol_Text, wc_col)
        imgui.Text(string.format('  * Wild Card: %s', label))
        imgui.PopStyleColor()
    end

    -- Cut Card: 使用後 WILDCARD_SHOW_DURATION 秒間だけ表示
    local cc_active = cut_card_result.shown_at > 0 and
                      (now_t - cut_card_result.shown_at) < WILDCARD_SHOW_DURATION
    if cc_active and cut_card_result.dice then
        imgui.PushStyleColor(ImGuiCol_Text, COL_WC_NORMAL)
        imgui.Text(string.format('  * Cut Card: %s',
            CIRCLED[cut_card_result.dice] or tostring(cut_card_result.dice)))
        imgui.PopStyleColor()
    end

    imgui.Separator()
end

-- ============================================================
-- render - ImGui 描画
-- ============================================================
ashita.events.register('d3d_present', 'cordice_render', function()

    debug_scan_abilities()

    -- Fold 等でロールが消えた場合の保険: 2秒ごとにメモリを直接確認
    -- dice_queue に出目が pending な間は毎フレーム割り当てを試みる
    -- （0x063 が来ない場合でも、メモリ更新を待ちながらリトライする）
    if pending_buff_check or dice_queue.last_val ~= nil then
        pending_buff_check = false
        process_roll_buffs()
    end

    -- 0x063 パケット後にメモリ更新が遅れても最終的にクリアできる
    local now_poll = os.time()
    if now_poll - last_buff_poll >= 2 then
        last_buff_poll = now_poll
        for buff_id in pairs(active_rolls) do
            if not has_buff(buff_id) then
                active_rolls[buff_id] = nil
                debug_log(string.format('poll: roll removed (not in memory) buff_id=%d', buff_id))
                pcall(function()
                    ashita.misc.play_sound(addon.path .. 'sounds\\roll_expired.wav')
                end)
            end
        end
    end

    -- /p 通知タイマー: 最後の出目確定から3秒後に1回だけ通知（DU連打中はリセット）
    for buff_id, data in pairs(active_rolls) do
        if data.notify_at and now_poll >= data.notify_at and data.dice then
            local def = tables.rolls[buff_id]
            if def then
                -- ROLL_JP_SJIS[buff_id] が定義済みなら Shift-JIS 名、なければ英語名
                send_party_notify(ROLL_JP_SJIS[buff_id] or def.name, data.dice, def)
            end
            data.notify_at = nil  -- 通知済みフラグ
        end
    end

    local flags = bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav
    )

    imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowBgAlpha(cfg.alpha)

    if imgui.Begin('CorDice##main', true, flags) then

        cfg.x, cfg.y = imgui.GetWindowPos()

        -- タイトル + notify 状態
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('CorDice')
        imgui.PopStyleColor()
        imgui.SameLine()
        if cfg.auto_notify then
            imgui.PushStyleColor(ImGuiCol_Text, COL_READY)
            imgui.Text('[notify:ON]')
        else
            imgui.PushStyleColor(ImGuiCol_Text, COL_DIM)
            imgui.Text('[notify:OFF]')
        end
        imgui.PopStyleColor()
        imgui.Separator()

        -- アビリティセクション
        if cfg.show_abilities then
            draw_abilities()
        end

        -- ロールセクション
        if not next(active_rolls) then
            imgui.PushStyleColor(ImGuiCol_Text, COL_DIM)
            imgui.Text('Waiting for roll...')
            imgui.PopStyleColor()
        else
            for buff_id, data in pairs(active_rolls) do
                draw_roll_entry(buff_id, data)
            end
        end

    end
    imgui.End()

end)

-- ============================================================
-- load イベント - 設定読み込み・既存ロール検出
-- ============================================================
ashita.events.register('load', 'cordice_load', function()
    cfg = settings.load(default_settings)

    -- メモリから既存のロールバフを読み込んで即表示
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player then
        local buffs = player:GetBuffs()
        if buffs then
            for i = 0, 31 do
                local bid = buffs[i]
                if bid and tables.rolls[bid] then
                    active_rolls[bid] = { dice = nil }
                    debug_log(string.format('load: existing roll buff_id=%d', bid))
                end
            end
        end
    end

    print(string.format('[CorDice] v%s loaded. Debug=%s', addon.version, tostring(DEBUG_MODE)))
    if DEBUG_MODE then
        ability_scan_requested = true
    end
end)

-- ============================================================
-- unload イベント - 設定保存
-- ============================================================
ashita.events.register('unload', 'cordice_unload', function()
    settings.save()
    print('[CorDice] unloaded.')
end)

-- ============================================================
-- CorDice.lua
-- Ashita v4 アドオン - コルセア ファントムロール可視化ツール
-- 機能: 全ロール出目・効果値 + アビリティリキャスト表示
-- ============================================================

addon.name    = 'CorDice'
addon.author  = '7xxxk'
addon.version = '0.2.0'
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
local DEBUG_MODE     = true
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

-- dice_queue: 0x029で取得した出目を 0x063 が来るまで保持
local dice_queue = {
    last_val     = nil,
    timestamp    = 0,
    is_double_up = false,  -- ダブルアップ由来かどうか
}

-- ============================================================
-- アビリティ定義
-- ※ index は GetAbilityTimer() に渡すインデックス（要実測）
-- ============================================================
local ABILITIES = {
    { name = 'Double Up',    index = 2 },    -- 実測確認済み
    { name = 'Snake Eye',    index = 7 },    -- 実測確認済み
    { name = 'Crookd Cards', index = 11 },   -- 実測確認済み
    { name = 'Fold',         index = 8 },    -- 実測確認済み
    { name = 'Cut Card',     index = 10 },   -- 実測確認済み
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

        if category ~= 6 then return end

        if roll_number >= 1 and roll_number <= 11 then
            local is_du = has_buff(BUFF_DOUBLE_UP_CHANCE)
            dice_queue.last_val     = roll_number
            dice_queue.timestamp    = os.time()
            dice_queue.is_double_up = is_du
            debug_log(string.format('roll captured: %d is_double_up=%s roll_id=%d actor_is_me=%s',
                roll_number, tostring(is_du), roll_id, tostring(actor == my_id)))
        end
    end)
    if not ok then
        debug_log('0x028 error: ' .. tostring(err))
    end
end)

-- ============================================================
-- パケット監視: 0x063 バフステータス更新（アクティブバフ検出）
-- ============================================================
ashita.events.register('packet_in', 'cordice_packet_0x063', function(e)
    if e.id ~= 0x063 then return end

    local now = os.time()

    -- DEBUGモード: 非ゼロスロットを出力（バフID特定用）
    if DEBUG_MODE then
        for i = 0, 31 do
            local bid = struct.unpack('H', e.data, (0x04 + i * 2) + 1)
            if bid ~= 0 and bid ~= 255 and bid ~= 0xFFFF then
                debug_log(string.format('  slot[%d] bid=%d', i, bid))
            end
        end
    end

    -- アクティブなロールを収集して active_rolls を更新
    local new_rolls = {}
    for i = 0, 31 do
        local buff_id = struct.unpack('H', e.data, (0x04 + i * 2) + 1)
        if tables.rolls[buff_id] then
            local d_val = active_rolls[buff_id] and active_rolls[buff_id].dice or nil

            if dice_queue.last_val and (now - dice_queue.timestamp) < 5 then
                if not d_val then
                    -- 初回ロール: キューから取得
                    d_val = dice_queue.last_val
                    dice_queue.last_val = nil
                elseif dice_queue.is_double_up then
                    -- ダブルアップ: roll_number はすでに合計値なので置換
                    debug_log(string.format('double_up: %d -> %d', d_val, dice_queue.last_val))
                    d_val = dice_queue.last_val
                    dice_queue.last_val = nil
                end
            end

            new_rolls[buff_id] = { dice = d_val }
            debug_log(string.format('0x063: roll buff_id=%d dice=%s', buff_id, tostring(d_val)))
        end
    end

    -- ロール切れ検出: active_rolls にあって new_rolls にない
    for buff_id in pairs(active_rolls) do
        if not new_rolls[buff_id] then
            if has_buff(buff_id) then
                -- メモリにはまだ存在 → ダブルアップ等による一時的なパケット欠落
                -- ロールを保持して誤検知を防ぐ
                debug_log(string.format('packet gap (buff still in memory): buff_id=%d, keeping', buff_id))
                new_rolls[buff_id] = active_rolls[buff_id]
            else
                -- メモリにも存在しない → 本当に切れた
                local def = tables.rolls[buff_id]
                debug_log(string.format('roll expired: buff_id=%d (%s)',
                    buff_id, def and def.name or '?'))
                pcall(function()
                    ashita.misc.play_sound(addon.path .. 'sounds\\roll_expired.wav')
                end)
                break  -- 複数同時切れでも1回だけ再生
            end
        end
    end

    active_rolls = new_rolls
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
            scan_log(string.format('  ability[%d] = %d cs (%.1f s)', i, t, t / 100.0))
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
        active_rolls = {}
        print('[CorDice] ロール表示をリセットしました。')
    else
        print('[CorDice] コマンド一覧:')
        print('  /cordice abiscan  - アビリティindex全スキャン（ログ出力）')
        print('  /cordice reset    - ロール表示クリア')
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

        -- ロール名 + ダイス + Lucky/Unlucky を1行
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

    imgui.Separator()
end

-- ============================================================
-- render - ImGui 描画
-- ============================================================
ashita.events.register('d3d_present', 'cordice_render', function()

    debug_scan_abilities()

    -- Fold 等でロールが消えた場合の保険: 2秒ごとにメモリを直接確認
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

        -- タイトル
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('CorDice')
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

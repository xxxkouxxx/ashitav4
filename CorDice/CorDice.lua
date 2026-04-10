-- ============================================================
-- CorDice.lua
-- Ashita v4 アドオン - コルセア ファントムロール可視化ツール
-- 機能: 全ロール出目・効果値・残り時間 + アビリティリキャスト表示
-- ============================================================

addon.name    = 'CorDice'
addon.author  = '7xxxk'
addon.version = '0.1.0'
addon.desc    = 'コルセア ファントムロール可視化 (出目/効果/残り時間/アビリティ)'

require('common')
local imgui  = require('imgui')
local settings = require('settings')
local tables = require('CorDice_tables')

-- ============================================================
-- デバッグモード
-- バフID特定: true にして各ロールをかけ、チャットログの
--   [CorDice DEBUG] 0x063: buff[n]= の値を確認する。
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
}
local cfg = T{}

-- 設定変更コールバック
settings.register('settings', 'cordice_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- 状態管理
-- ============================================================
-- active_rolls[buff_id] = {
--     dice        = 出目 (1〜11, またはnil=解析中),
--     seconds     = パケット受信時点の残り秒数,
--     max_seconds = ロール初回適用時のduration（残り時間バーの分母）,
--     last_update = os.time() at パケット受信,
-- }
local active_rolls = {}

-- dice_queue: 0x029で取得した出目を 0x063 が来るまで保持
local dice_queue = {
    last_val  = nil,
    timestamp = 0,
}

-- ============================================================
-- アビリティ定義
-- ※ index は GetAbilityTimer() に渡すインデックス（要実測）
--   DEBUG_MODE = true で全スロットをスキャンして特定すること
-- ============================================================
local ABILITIES = {
    { name = 'ダブルアップ',     index = 163 },  -- ※要実測
    { name = 'スネークアイ',     index = 164 },  -- ※要実測
    { name = 'クルケッドカード', index = 165 },  -- ※要実測
    { name = 'フォールド',       index = 166 },  -- ※要実測
}

-- スネークアイ・クルケッドカード 効果中バフID（※要実測）
local BUFF_SNAKE_EYE     = 385  -- ※要実測
local BUFF_CROOKED_CARDS = 386  -- ※要実測

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
local COL_TIMER_LOW = { 1.0, 0.5, 0.2, 1.0 } -- 橙赤（残り30秒以下）

-- ============================================================
-- ヘルパー関数
-- ============================================================
local function format_time(s)
    if s <= 0 then return '00:00' end
    return string.format('%02d:%02d', math.floor(s / 60), math.floor(s % 60))
end

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
    if dice == 11       then return COL_ELEVEN  end
    if dice == def.lucky   then return COL_LUCKY   end
    if dice == def.unlucky then return COL_UNLUCKY end
    return COL_NORMAL
end

-- ============================================================
-- パケット監視: 0x029 アクションメッセージ（出目取得）
-- message_id 420 = ロール実行, 424 = ダブルアップ
-- ============================================================
ashita.events.register('packet_in', 'cordice_packet_0x029', function(e)
    if e.id ~= 0x029 then return end

    local message_id = struct.unpack('H', e.data, 0x0C + 1)
    if message_id == 420 or message_id == 424 then
        local dice_val = struct.unpack('b', e.data, 0x0C + 5)
        dice_queue.last_val  = dice_val
        dice_queue.timestamp = os.time()
        debug_log(string.format('0x029: message_id=%d dice=%d', message_id, dice_val))
    end
end)

-- ============================================================
-- パケット監視: 0x063 バフステータス更新（残り時間取得）
-- ============================================================
ashita.events.register('packet_in', 'cordice_packet_0x063', function(e)
    if e.id ~= 0x063 then return end

    -- DEBUGモード: 全バフスロットを出力（バフID特定用）
    if DEBUG_MODE then
        for i = 0, 31 do
            local bid = struct.unpack('H', e.data, (0x04 + i * 2) + 1)
            if bid ~= 0 and bid ~= 0xFFFF then
                debug_log(string.format('0x063: buff[%d]=%d', i, bid))
            end
        end
    end

    local server_time = AshitaCore:GetMemoryManager():GetInventory():GetServerTime()
    local new_rolls   = {}

    for i = 0, 31 do
        local buff_id = struct.unpack('H', e.data, (0x04 + i * 2) + 1)

        if tables.rolls[buff_id] then
            local end_time = struct.unpack('I', e.data, (0x44 + i * 4) + 1)
            local duration = end_time - server_time

            if duration > 0 then
                -- 出目: 既存データを優先し、なければ dice_queue から取得（5秒タイムアウト）
                local d_val = active_rolls[buff_id] and active_rolls[buff_id].dice or nil
                if not d_val
                    and dice_queue.last_val
                    and (os.time() - dice_queue.timestamp < 5)
                then
                    d_val = dice_queue.last_val
                    dice_queue.last_val = nil
                end

                -- max_seconds: 初回適用時のdurationを保持（バーの分母に使用）
                local max_s = active_rolls[buff_id]
                    and active_rolls[buff_id].max_seconds
                    or duration

                new_rolls[buff_id] = {
                    dice        = d_val,
                    seconds     = duration,
                    max_seconds = max_s,
                    last_update = os.time(),
                }

                debug_log(string.format('0x063: roll buff_id=%d duration=%d dice=%s',
                    buff_id, duration, tostring(d_val)))
            end
        end
    end

    active_rolls = new_rolls
end)

-- ============================================================
-- アビリティインデックス実測用スキャン（DEBUG_MODE時のみ）
-- アビリティ使用直後に一度だけ実行し、timer>0 のスロットを記録する
-- ============================================================
local ability_scan_requested = false

local function debug_scan_abilities()
    if not DEBUG_MODE or not ability_scan_requested then return end
    ability_scan_requested = false

    local recast = AshitaCore:GetMemoryManager():GetRecast()
    debug_log('--- ability recast scan ---')
    for i = 0, 200 do
        local t = recast:GetAbilityTimer(i)
        if t and t > 0 then
            debug_log(string.format('  ability[%d] = %d cs (%.1f s)', i, t, t / 100.0))
        end
    end
    debug_log('--- scan end ---')
end

-- ============================================================
-- UIサブ関数: ロール1件の描画
-- ============================================================
local function draw_roll_entry(buff_id, data)
    local def = tables.rolls[buff_id]
    if not def then return end

    local elapsed   = os.time() - data.last_update
    local current_s = math.max(0, data.seconds - elapsed)
    local ratio     = (data.max_seconds > 0)
        and math.min(1.0, current_s / data.max_seconds)
        or 0

    -- ロール名・残り時間
    imgui.PushStyleColor(ImGuiCol_Text, COL_TITLE)
    imgui.Text(def.name)
    imgui.PopStyleColor()
    imgui.SameLine()
    imgui.Text(string.format('[%s]', format_time(current_s)))

    -- 出目・ラベル・効果値
    if data.dice then
        local col    = get_roll_color(data.dice, def)
        local effect = def.rolls[data.dice]
        local label  = ''
        if     data.dice == 11          then label = ' [11!]'
        elseif data.dice == def.lucky   then label = ' [Lucky]'
        elseif data.dice == def.unlucky then label = ' [Unlucky]'
        end

        imgui.PushStyleColor(ImGuiCol_Text, col)
        imgui.Text(string.format('  出目: %d%s  効果: +%s%s',
            data.dice, label, tostring(effect), def.unit))
        imgui.PopStyleColor()
    else
        imgui.PushStyleColor(ImGuiCol_Text, COL_DIM)
        imgui.Text('  出目: 解析中...')
        imgui.PopStyleColor()
    end

    -- 残り時間バー（残り30秒以下で色変化）
    local bar_col = (current_s <= 30) and COL_TIMER_LOW or COL_LUCKY
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, bar_col)
    imgui.ProgressBar(ratio, { -1, 6 }, '')
    imgui.PopStyleColor()

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
            imgui.Text(string.format('  %-15s [使用可能]', ab.name))
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(ImGuiCol_Text, COL_RECAST)
            imgui.Text(string.format('  %-15s [%5.1f s]', ab.name, timer_cs / 100.0))
            imgui.PopStyleColor()
        end
    end

    -- スネークアイ・クルケッドカード 効果中マーカー
    if has_buff(BUFF_SNAKE_EYE) then
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('  ★ スネークアイ 効果中')
        imgui.PopStyleColor()
    end
    if has_buff(BUFF_CROOKED_CARDS) then
        imgui.PushStyleColor(ImGuiCol_Text, COL_ELEVEN)
        imgui.Text('  ★ クルケッドカード 効果中')
        imgui.PopStyleColor()
    end

    imgui.Separator()
end

-- ============================================================
-- render - ImGui 描画
-- ============================================================
ashita.events.register('render', 'cordice_render', function()

    debug_scan_abilities()

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

        -- ウィンドウ移動後に座標を保存
        local pos = imgui.GetWindowPos()
        cfg.x = pos.x
        cfg.y = pos.y

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
            imgui.Text('ロール待機中...')
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
-- load イベント - 設定読み込み
-- ============================================================
ashita.events.register('load', 'cordice_load', function()
    cfg = settings.load(default_settings)
    print(string.format('[CorDice] v%s loaded. Debug=%s', addon.version, tostring(DEBUG_MODE)))
    if DEBUG_MODE then
        -- 起動直後にアビリティスキャンをスケジュール
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

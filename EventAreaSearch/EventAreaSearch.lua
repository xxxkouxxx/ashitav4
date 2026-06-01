-- ============================================================
-- EventAreaSearch.lua
-- Ashita v4 アドオン - イベントエリア戦闘検知（3ゾーン対応）
--
-- 概要:
--   最大3ゾーンを順番に /sea でサーチし、プレイヤーが一定数（デフォルト10名）
--   以上検出された場合に「戦闘中」と判定してアラートを表示する。
--   ゾーン1→2→3 の順にサーチし、全完了後にインターバル待機。
--
-- コマンド:
--   /eas                   - ウィンドウ 表示/非表示 切替
--   /eas on                - 監視開始（即時初回サーチ）
--   /eas off               - 監視停止
--   /eas search            - 手動即時サーチ（全ゾーン）
--   /eas zone <n> <name>   - ゾーン n（1-3）の名前設定
--   /eas zoneid <n> <id>   - ゾーン n の ID 設定（パケットフィルタ用）
--   /eas threshold <n>     - 戦闘検知しきい値設定（デフォルト 10）
--   /eas interval <n>      - サーチ間隔設定（秒、デフォルト 300）
--   /eas debug             - パケットデバッグログ 有効/無効 切替
--   /eas clear             - 全結果クリア
--   /eas help              - ヘルプ表示
--
-- パケット ID の確認方法:
--   1. /eas debug → DEBUG モード ON
--   2. /eas search → サーチ実行
--   3. チャットログに [EAS DEBUG] id=0xXXXX ... が出る
--   4. /sea 実行直後に現れる ID を SEARCH_RESULT_PACKET に設定
-- ============================================================

addon.name    = 'EventAreaSearch'
addon.author  = '7xxxk'
addon.version = '1.1'
addon.desc    = '3-zone event combat detection by /sea player count'

require('common')
local settings = require('settings')
local imgui    = require('imgui')

-- ============================================================
-- Shift-JIS → UTF-8 変換（PTChatLog.lua より流用）
-- ============================================================
local ffi = nil
local k32 = nil
pcall(function() ffi = require('ffi') end)
if ffi then
    pcall(function()
        ffi.cdef([[
            int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags,
                const char* lpMultiByteStr, int cbMultiByte,
                unsigned short* lpWideCharStr, int cchWideChar);
            int WideCharToMultiByte(unsigned int CodePage, unsigned long dwFlags,
                const unsigned short* lpWideCharStr, int cchWideChar,
                char* lpMultiByteStr, int cbMultiByte,
                const char* lpDefaultChar, int* lpUsedDefaultChar);
        ]])
    end)
    pcall(function() k32 = ffi.load('kernel32') end)
end

local CP_SJIS = 932
local CP_UTF8 = 65001

local function sjis_to_utf8(str)
    if not str or str == '' then return str end
    if not ffi or not k32 then return str end
    local ok, result = pcall(function()
        local wlen = k32.MultiByteToWideChar(CP_SJIS, 0, str, #str, nil, 0)
        if wlen <= 0 then return str end
        local wbuf = ffi.new('unsigned short[?]', wlen + 1)
        k32.MultiByteToWideChar(CP_SJIS, 0, str, #str, wbuf, wlen)
        local ulen = k32.WideCharToMultiByte(CP_UTF8, 0, wbuf, wlen, nil, 0, nil, nil)
        if ulen <= 0 then return str end
        local ubuf = ffi.new('char[?]', ulen + 1)
        k32.WideCharToMultiByte(CP_UTF8, 0, wbuf, wlen, ubuf, ulen, nil, nil)
        return ffi.string(ubuf, ulen)
    end)
    return ok and result or str
end

-- NUL 終端文字列をパケットデータから読み取る
local function read_string(data, byte_offset)
    local result = {}
    local i      = byte_offset
    local limit  = byte_offset + 256
    while i < limit do
        local b = ashita.bits.unpack_be(data, i * 8, 8)
        if not b or b == 0 then break end
        result[#result + 1] = string.char(b)
        i = i + 1
    end
    return table.concat(result)
end

-- FFXI エスケープコード除去 + SJIS 変換
local function clean_str(raw)
    if not raw or raw == '' then return '' end
    local result = {}
    local i, len = 1, #raw
    while i <= len do
        local b = raw:byte(i)
        if (b == 0x1E or b == 0x1F) and i < len then
            i = i + 2
        elseif b < 0x20 then
            i = i + 1
        else
            result[#result + 1] = raw:sub(i, i)
            i = i + 1
        end
    end
    return sjis_to_utf8(table.concat(result))
end

-- ============================================================
-- パケット ID（要実機確認）
-- DEBUG_PACKET = true で /eas search を実行して ID を特定する
-- ============================================================
local SEARCH_RESULT_PACKET = 0x00B4  -- サーチ結果 1 エントリ（推定値）
local SEARCH_END_PACKET    = 0x00B5  -- サーチ結果終端（推定値）
local DEBUG_PACKET         = true    -- パケット ID 未確定の間は true 推奨

-- ============================================================
-- 設定デフォルト値（3ゾーン対応）
-- ============================================================
local default_settings = T{
    visible    = true,
    x          = 20,
    y          = 20,
    zone1_name = 'Alzadaal Undersea Ruins',
    zone1_id   = 0,
    zone2_name = 'The Boyahda Tree',
    zone2_id   = 0,
    zone3_name = "Ru'Aun Gardens",
    zone3_id   = 0,
    threshold  = 10,   -- 戦闘検知しきい値（全ゾーン共通）
    interval   = 300,  -- サーチサイクル間隔（秒）
    sound      = false,
}
local cfg = T{}

settings.register('settings', 'eas_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- ゾーン情報アクセスヘルパー
-- ============================================================
local function zone_name(i)
    if i == 1 then return cfg.zone1_name
    elseif i == 2 then return cfg.zone2_name
    elseif i == 3 then return cfg.zone3_name
    end
    return ''
end

local function zone_id(i)
    if i == 1 then return cfg.zone1_id
    elseif i == 2 then return cfg.zone2_id
    elseif i == 3 then return cfg.zone3_id
    end
    return 0
end

local function set_zone_name(i, name)
    if i == 1 then cfg.zone1_name = name
    elseif i == 2 then cfg.zone2_name = name
    elseif i == 3 then cfg.zone3_name = name
    end
end

local function set_zone_id(i, id)
    if i == 1 then cfg.zone1_id = id
    elseif i == 2 then cfg.zone2_id = id
    elseif i == 3 then cfg.zone3_id = id
    end
end

-- ============================================================
-- 状態変数
-- ============================================================

-- サイクル全体の状態
local state = {
    active        = false,  -- 監視有効フラグ
    timer         = 0,      -- サイクル間隔タイマー（秒）
    current_zone  = 0,      -- 現在サーチ中のゾーン番号（0=非サーチ中）
    searching     = false,  -- サーチ応答待ちフラグ
    search_timeout= 0,      -- タイムアウトカウントダウン（秒）
    combat_blink  = 0,      -- 点滅アニメーションタイマー
}

-- ゾーンごとの状態（インデックス 1-3）
local zs = {
    { count = 0, combat = false, results = {}, last_time = '---' },
    { count = 0, combat = false, results = {}, last_time = '---' },
    { count = 0, combat = false, results = {}, last_time = '---' },
}

-- いずれかのゾーンで戦闘中か
local function any_combat()
    return zs[1].combat or zs[2].combat or zs[3].combat
end

-- ============================================================
-- サーチサイクル制御
-- ============================================================

-- 次にサーチすべきゾーンを探して実行する
-- current_zone の次から順に、名前が設定されているゾーンを探す
local function do_search_next()
    for i = state.current_zone + 1, 3 do
        if zone_name(i) ~= '' then
            state.current_zone  = i
            state.searching     = true
            state.search_timeout = 8.0
            zs[i].count   = 0
            zs[i].results = {}
            zs[i].last_time = os.date('%H:%M:%S')

            local cmd = string.format('/sea all "%s"', zone_name(i))
            AshitaCore:GetChatManager():QueueCommand(-1, cmd)
            return
        end
    end

    -- 全ゾーン完了
    state.current_zone = 0
    state.searching    = false
end

-- サイクル開始（ゾーン1 から）
local function start_cycle()
    state.current_zone = 0
    do_search_next()
end

-- 現在ゾーンの評価 → 次のゾーンへ
local function evaluate_and_continue()
    local i = state.current_zone
    if i >= 1 and i <= 3 then
        local was_combat = zs[i].combat
        zs[i].combat     = (zs[i].count >= cfg.threshold)

        if zs[i].combat and not was_combat then
            print(string.format('[EAS] !! COMBAT !! %d players in "%s"',
                zs[i].count, zone_name(i)))
            if cfg.sound then
                pcall(function()
                    ashita.misc.play_sound(addon.path .. 'sounds\\alert.wav')
                end)
            end
        end
    end
    do_search_next()
end

-- ============================================================
-- パケット受信ハンドラ
-- ============================================================
ashita.events.register('packet_in', 'eas_packet_in', function(e)

    -- デバッグ: サーチ中の全パケットをログ出力（パケット ID 特定用）
    if DEBUG_PACKET and state.searching then
        local hex = ''
        for i = 0, math.min(31, #e.data - 1) do
            hex = hex .. string.format('%02X ', ashita.bits.unpack_be(e.data_raw, i * 8, 8) or 0)
        end
        print(string.format('[EAS DEBUG] id=0x%04X len=%3d | %s', e.id, #e.data, hex))
    end

    -- サーチ結果終端パケット → 現在ゾーン評価 → 次のゾーンへ
    if e.id == SEARCH_END_PACKET then
        if state.searching then
            evaluate_and_continue()
        end
        return
    end

    if e.id ~= SEARCH_RESULT_PACKET then return end
    if not state.searching then return end

    local i = state.current_zone
    if i < 1 or i > 3 then return end

    local ok, err = pcall(function()
        -- !!!! パケット構造は要実機確認 !!!!
        -- デバッグ出力でオフセットを確認後、以下を修正:
        --   local zid  = ashita.bits.unpack_be(e.data_raw, ZONE_OFFSET * 8, 16)
        --   local name = clean_str(read_string(e.data_raw, NAME_OFFSET))
        --   local comm = clean_str(read_string(e.data_raw, COMMENT_OFFSET))
        --   if zone_id(i) ~= 0 and zid ~= zone_id(i) then return end

        -- 暫定: パケット 1 つ = プレイヤー 1 名
        zs[i].count = zs[i].count + 1

        -- 構造確定後に有効化:
        -- if name ~= '' then
        --     zs[i].results[name] = { comment = comm, time = os.time() }
        -- end
    end)
    if not ok then
        print('[EAS] Packet error: ' .. tostring(err))
    end
end)

-- ============================================================
-- ImGui ウィンドウ描画
-- ============================================================
local function draw_zone_row(i)
    local name = zone_name(i)
    if name == '' then
        imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 0.4, 0.4, 1.0 })
        imgui.Text(string.format('Zone %d: (not set - /eas zone %d <name>)', i, i))
        imgui.PopStyleColor()
        return
    end

    local z = zs[i]

    -- ゾーン名（現在サーチ中は黄色）
    if state.searching and state.current_zone == i then
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.85, 0.2, 1.0 })
        imgui.Text(string.format('Zone %d: %s  [Searching...]', i, name))
        imgui.PopStyleColor()
    else
        imgui.PushStyleColor(ImGuiCol_Text, { 0.75, 0.75, 0.75, 1.0 })
        imgui.Text(string.format('Zone %d: %s', i, name))
        imgui.PopStyleColor()
    end

    -- プレイヤー数 + ステータス
    if z.combat then
        local a = 0.6 + 0.4 * math.abs(math.sin(state.combat_blink * 2.5))
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.15, 0.15, a })
        imgui.Text(string.format('  Players: %d / %d  !! COMBAT !!', z.count, cfg.threshold))
        imgui.PopStyleColor()
    else
        local col = z.count >= cfg.threshold
            and { 1.0, 0.3, 0.3, 1.0 }
            or  { 0.85, 0.85, 0.85, 1.0 }
        imgui.PushStyleColor(ImGuiCol_Text, col)
        imgui.Text(string.format('  Players: %d / %d', z.count, cfg.threshold))
        imgui.PopStyleColor()
    end

    -- 最終サーチ時刻
    imgui.PushStyleColor(ImGuiCol_Text, { 0.55, 0.55, 0.55, 1.0 })
    imgui.Text('  Last: ' .. z.last_time)
    imgui.PopStyleColor()
end

local function render_window()
    if not cfg.visible then return end

    -- いずれかのゾーンで戦闘中なら背景を赤に
    local pushed_color = false
    if any_combat() then
        local a = 0.45 + 0.25 * math.abs(math.sin(state.combat_blink * 2.5))
        imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.55, 0.04, 0.04, a })
        pushed_color = true
    end

    local win_flags = bit.bor(
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoNav
    )

    imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)

    if imgui.Begin('EventAreaSearch##eas_main', true, win_flags) then
        cfg.x, cfg.y = imgui.GetWindowPos()

        -- タイトル
        imgui.PushStyleColor(ImGuiCol_Text, { 0.6, 0.85, 1.0, 1.0 })
        imgui.Text('EventAreaSearch v' .. addon.version)
        imgui.PopStyleColor()

        imgui.Separator()

        -- ゾーン1
        draw_zone_row(1)

        imgui.Separator()

        -- ゾーン2
        draw_zone_row(2)

        imgui.Separator()

        -- ゾーン3
        draw_zone_row(3)

        imgui.Separator()

        -- 全体ステータス + 次回サーチまでの時間
        if not state.active then
            imgui.PushStyleColor(ImGuiCol_Text, { 0.45, 0.45, 0.45, 1.0 })
            imgui.Text('Stopped')
            imgui.PopStyleColor()
        elseif state.searching then
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.8, 0.2, 1.0 })
            imgui.Text('Searching...')
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.9, 0.5, 1.0 })
            local remain = math.ceil(math.max(0, cfg.interval - state.timer))
            imgui.Text(string.format('Watching... (next cycle: %ds)', remain))
            imgui.PopStyleColor()
        end

        imgui.Separator()

        -- 操作ボタン
        if not state.active then
            if imgui.Button(' Start ##eas') then
                state.active = true
                state.timer  = cfg.interval   -- 即座に初回サーチ
                print('[EAS] Started.')
            end
        else
            if imgui.Button(' Stop ##eas') then
                state.active       = false
                state.searching    = false
                state.current_zone = 0
                print('[EAS] Stopped.')
            end
        end

        imgui.SameLine()
        if imgui.Button(' Search Now ##eas') then
            state.timer = 0
            start_cycle()
        end

        imgui.SameLine()
        if imgui.Button(' Clear ##eas') then
            for i = 1, 3 do
                zs[i].count   = 0
                zs[i].combat  = false
                zs[i].results = {}
            end
        end

        imgui.End()
    end

    if pushed_color then
        imgui.PopStyleColor()
    end
end

-- ============================================================
-- d3d_present: タイマー更新 + 描画
-- ============================================================
ashita.events.register('d3d_present', 'eas_render', function()
    local dt = imgui.GetIO().DeltaTime

    -- サイクル間隔タイマー（サーチ中は進めない）
    if state.active and not state.searching and state.current_zone == 0 then
        state.timer = state.timer + dt
        if state.timer >= cfg.interval then
            state.timer = 0
            start_cycle()
        end
    end

    -- サーチタイムアウト
    if state.searching then
        state.search_timeout = state.search_timeout - dt
        if state.search_timeout <= 0 then
            evaluate_and_continue()
        end
    end

    -- 点滅アニメーション用タイマー
    if any_combat() then
        state.combat_blink = state.combat_blink + dt
    else
        state.combat_blink = 0
    end

    render_window()
end)

-- ============================================================
-- コマンドハンドラ
-- ============================================================
ashita.events.register('command', 'eas_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    if args[1] ~= '/eventareasearch' and args[1] ~= '/eas' then return end
    e.blocked = true

    local sub = args[2] and args[2]:lower() or ''

    if sub == '' then
        cfg.visible = not cfg.visible
        settings.save()

    elseif sub == 'on' or sub == 'start' then
        state.active = true
        state.timer  = cfg.interval   -- 即座に初回サーチ
        print('[EAS] Started.')

    elseif sub == 'off' or sub == 'stop' then
        state.active       = false
        state.searching    = false
        state.current_zone = 0
        print('[EAS] Stopped.')

    elseif sub == 'search' then
        state.timer = 0
        start_cycle()

    elseif sub == 'zone' then
        -- /eas zone <1-3> <name...>
        local idx = tonumber(args[3])
        if idx and idx >= 1 and idx <= 3 and args[4] then
            local parts = {}
            for i = 4, #args do parts[#parts + 1] = args[i] end
            local name = table.concat(parts, ' ')
            set_zone_name(idx, name)
            settings.save()
            print(string.format('[EAS] Zone %d: %s', idx, name))
        else
            print('[EAS] Usage: /eas zone <1-3> <zone name>')
            for i = 1, 3 do
                local n = zone_name(i)
                print(string.format('  Zone %d: %s', i, n ~= '' and n or '(not set)'))
            end
        end

    elseif sub == 'zoneid' then
        -- /eas zoneid <1-3> <id>
        local idx = tonumber(args[3])
        local id  = tonumber(args[4])
        if idx and idx >= 1 and idx <= 3 and id then
            set_zone_id(idx, id)
            settings.save()
            print(string.format('[EAS] Zone %d ID: %d', idx, id))
        else
            print('[EAS] Usage: /eas zoneid <1-3> <zone_id>')
        end

    elseif sub == 'threshold' then
        if args[3] then
            cfg.threshold = math.max(1, tonumber(args[3]) or 10)
            settings.save()
            print('[EAS] Threshold: ' .. cfg.threshold)
        end

    elseif sub == 'interval' then
        if args[3] then
            cfg.interval = math.max(10, tonumber(args[3]) or 300)
            settings.save()
            print('[EAS] Interval: ' .. cfg.interval .. 's')
        end

    elseif sub == 'debug' then
        DEBUG_PACKET = not DEBUG_PACKET
        print('[EAS] Debug: ' .. (DEBUG_PACKET and 'ON' or 'OFF'))

    elseif sub == 'clear' then
        for i = 1, 3 do
            zs[i].count   = 0
            zs[i].combat  = false
            zs[i].results = {}
        end

    elseif sub == 'help' then
        print('[EAS] ---- EventAreaSearch v' .. addon.version .. ' ----')
        print('  /eas                  ウィンドウ 表示/非表示')
        print('  /eas on/off           監視 開始/停止')
        print('  /eas search           手動サーチ（全ゾーン）')
        print('  /eas zone <1-3> <name> ゾーン名設定')
        print('  /eas zoneid <1-3> <id> ゾーン ID 設定')
        print('  /eas threshold <n>    戦闘検知しきい値（デフォルト 10）')
        print('  /eas interval <n>     サーチ間隔（秒、デフォルト 300）')
        print('  /eas debug            パケットデバッグ 有効/無効')
        print('  /eas clear            結果クリア')
    end
end)

-- ============================================================
-- ロード / アンロード
-- ============================================================
ashita.events.register('load', 'eas_load', function()
    cfg = settings.load(default_settings)
    print('[EventAreaSearch] v' .. addon.version .. ' loaded. /eas help for commands.')
    if DEBUG_PACKET then
        print('[EAS] DEBUG mode ON - use /eas search to identify packet IDs.')
    end
end)

ashita.events.register('unload', 'eas_unload', function()
    settings.save()
    print('[EventAreaSearch] unloaded.')
end)

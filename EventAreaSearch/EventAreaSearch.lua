-- ============================================================
-- EventAreaSearch.lua
-- Ashita v4 アドオン - イベントエリア戦闘検知
--
-- 概要:
--   指定ゾーンを /sea で定期サーチし、プレイヤーが一定数（デフォルト10名）
--   以上検出された場合に「戦闘中」と判定してアラートを表示する。
--   別ゾーンからのリモート監視専用。
--
-- コマンド:
--   /eas              - ウィンドウ 表示/非表示 切替
--   /eas on           - 監視開始（即時初回サーチ）
--   /eas off          - 監視停止
--   /eas search       - 手動即時サーチ
--   /eas zone <name>  - 対象ゾーン名設定（/sea コマンドに渡すゾーン名）
--   /eas zoneid <n>   - ゾーン ID 設定（パケットフィルタ用、0=フィルタなし）
--   /eas threshold <n>- 戦闘検知しきい値設定（デフォルト 10）
--   /eas interval <n> - サーチ間隔設定（秒、デフォルト 300）
--   /eas debug        - パケットデバッグログ 有効/無効 切替
--   /eas clear        - 結果クリア
--   /eas help         - ヘルプ表示
--
-- パケット ID の確認方法:
--   1. /eas debug → DEBUG モード ON
--   2. /eas search → サーチ実行
--   3. チャットログに [EAS DEBUG] id=0xXXXX ... が出る
--   4. /sea 実行直後に現れるパケット ID を SEARCH_RESULT_PACKET に設定
-- ============================================================

addon.name    = 'EventAreaSearch'
addon.author  = '7xxxk'
addon.version = '1.0'
addon.desc    = 'Event area combat detection by /sea player count'

require('common')
local settings = require('settings')
local imgui    = require('imgui')

-- ============================================================
-- Shift-JIS → UTF-8 変換（PTChatLog.lua より流用）
-- サーチコメントが SJIS の場合に使用
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

-- ============================================================
-- NUL 終端文字列をパケットデータから読み取る（PTChatLog.lua より流用）
-- ============================================================
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

-- FFXI エスケープコード（色・書式）を除去してから SJIS 変換する
local function clean_str(raw)
    if not raw or raw == '' then return '' end
    local result = {}
    local i, len = 1, #raw
    while i <= len do
        local b = raw:byte(i)
        if (b == 0x1E or b == 0x1F) and i < len then
            i = i + 2   -- エスケープコード + 引数1バイトをスキップ
        elseif b < 0x20 then
            i = i + 1   -- その他の制御文字をスキップ
        else
            result[#result + 1] = raw:sub(i, i)
            i = i + 1
        end
    end
    return sjis_to_utf8(table.concat(result))
end

-- ============================================================
-- パケット ID
--
-- !! 要実機確認 !!
-- 下記の ID はコミュニティ調査に基づく推定値。
-- DEBUG_PACKET = true で /eas search を実行し、
-- [EAS DEBUG] ログを見てサーチ結果パケットの ID を特定してください。
-- ============================================================

-- サーチ結果エントリ（プレイヤー1件分）
-- 候補: 0x00B4 付近（要確認）
local SEARCH_RESULT_PACKET = 0x00B4

-- サーチ結果リスト終端（これが来たら集計する）
-- 候補: SEARCH_RESULT_PACKET の直後（要確認）
local SEARCH_END_PACKET    = 0x00B5

-- パケットデバッグモード（ID 未確定の間は true 推奨）
local DEBUG_PACKET = true

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    visible   = true,
    x         = 20,
    y         = 20,
    zone_name = '',   -- /sea に渡すゾーン名（例: "Ru'Aun Gardens"）
    zone_id   = 0,    -- ゾーン ID（パケットフィルタ用、0=フィルタなし）
    threshold = 10,   -- 戦闘検知しきい値（人数）
    interval  = 300,  -- サーチ間隔（秒）
    sound     = false,-- アラートサウンド再生
}
local cfg = T{}

settings.register('settings', 'eas_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- 状態変数
-- ============================================================
local state = {
    active          = false,  -- 監視有効フラグ
    timer           = 0,      -- サーチ間隔タイマー（秒）
    searching       = false,  -- サーチ応答待ちフラグ
    search_timeout  = 0,      -- タイムアウトカウントダウン（秒）
    result_count    = 0,      -- 今回の検出人数
    combat          = false,  -- 戦闘検知フラグ
    combat_blink    = 0,      -- 点滅アニメーションタイマー
    results         = {},     -- name -> { comment, time } テーブル
    last_search_str = '---',  -- 最終サーチ時刻（表示用）
}

-- ============================================================
-- サーチ実行
-- ============================================================
local function do_search()
    local cmd
    if cfg.zone_name ~= '' then
        cmd = string.format('/sea all "%s"', cfg.zone_name)
    else
        cmd = '/sea all'
    end
    AshitaCore:GetChatManager():QueueCommand(-1, cmd)
    state.searching      = true
    state.search_timeout = 8.0   -- 8 秒以内に終端パケットが来なければタイムアウト
    state.result_count   = 0
    state.results        = {}    -- 今回分をリセット
    state.last_search_str = os.date('%H:%M:%S')
end

-- ============================================================
-- 戦闘状態評価（サーチ完了またはタイムアウト時に呼ぶ）
-- ============================================================
local function evaluate_combat()
    local was_combat = state.combat
    state.combat    = (state.result_count >= cfg.threshold)
    state.searching = false

    -- 新規検知時のみアラート出力
    if state.combat and not was_combat then
        print(string.format('[EventAreaSearch] !! COMBAT DETECTED !! %d players in "%s"',
            state.result_count, cfg.zone_name ~= '' and cfg.zone_name or 'all'))
        if cfg.sound then
            pcall(function()
                ashita.misc.play_sound(addon.path .. 'sounds\\alert.wav')
            end)
        end
    end
end

-- ============================================================
-- パケット受信ハンドラ
-- ============================================================
ashita.events.register('packet_in', 'eas_packet_in', function(e)

    -- デバッグ: サーチ中の全パケットをログ出力（パケット ID 特定用）
    if DEBUG_PACKET and state.active then
        local hex = ''
        for i = 0, math.min(31, #e.data - 1) do
            hex = hex .. string.format('%02X ', ashita.bits.unpack_be(e.data_raw, i * 8, 8) or 0)
        end
        print(string.format('[EAS DEBUG] id=0x%04X len=%3d | %s', e.id, #e.data, hex))
    end

    -- サーチ結果終端パケット → 集計
    if e.id == SEARCH_END_PACKET then
        if state.searching then
            evaluate_combat()
        end
        return
    end

    -- サーチ結果 1 エントリパケット
    if e.id ~= SEARCH_RESULT_PACKET then return end
    if not state.searching then return end

    local ok, err = pcall(function()
        -- !!!! パケット構造は要実機確認 !!!!
        --
        -- デバッグ出力を見てオフセットを特定したら下記を修正:
        --   zone_id = ashita.bits.unpack_be(e.data_raw, ZONE_OFFSET * 8, 16)
        --   name    = clean_str(read_string(e.data_raw, NAME_OFFSET))
        --   comment = clean_str(read_string(e.data_raw, COMMENT_OFFSET))
        --
        -- ゾーン ID フィルタ（zone_id == 0 はフィルタなし）:
        --   if cfg.zone_id ~= 0 and zone_id ~= cfg.zone_id then return end

        -- 暫定: パケット 1 つ = プレイヤー 1 名として計上
        state.result_count = state.result_count + 1

        -- パケット構造確定後に以下を有効化:
        -- local name    = clean_str(read_string(e.data_raw, NAME_OFFSET))
        -- local comment = clean_str(read_string(e.data_raw, COMMENT_OFFSET))
        -- if name ~= '' then
        --     state.results[name] = { comment = comment, time = os.time() }
        -- end
    end)
    if not ok then
        print('[EAS] Packet error: ' .. tostring(err))
    end
end)

-- ============================================================
-- ImGui ウィンドウ描画
-- ============================================================
local function render_window()
    if not cfg.visible then return end

    -- 戦闘検知中はウィンドウ背景を赤にする
    local pushed_color = false
    if state.combat then
        local a = 0.5 + 0.3 * math.abs(math.sin(state.combat_blink * 2.5))
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

        -- ゾーン
        local zone_label = cfg.zone_name ~= '' and cfg.zone_name or '(not set - use /eas zone <name>)'
        imgui.Text('Zone: ' .. zone_label)

        -- 検出人数（しきい値以上で赤）
        local cnt_col = state.result_count >= cfg.threshold
            and { 1.0, 0.3, 0.3, 1.0 }
            or  { 0.9, 0.9, 0.9, 1.0 }
        imgui.PushStyleColor(ImGuiCol_Text, cnt_col)
        imgui.Text(string.format('Players: %d  /  Threshold: %d', state.result_count, cfg.threshold))
        imgui.PopStyleColor()

        -- ステータス行
        if state.combat then
            local a = 0.6 + 0.4 * math.abs(math.sin(state.combat_blink * 2.5))
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.15, 0.15, a })
            imgui.Text('!! COMBAT DETECTED !!')
            imgui.PopStyleColor()
        elseif state.searching then
            imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.8, 0.2, 1.0 })
            imgui.Text('Searching...')
            imgui.PopStyleColor()
        elseif state.active then
            imgui.PushStyleColor(ImGuiCol_Text, { 0.5, 0.9, 0.5, 1.0 })
            local remain = math.ceil(math.max(0, cfg.interval - state.timer))
            imgui.Text(string.format('Watching... (next: %ds)', remain))
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(ImGuiCol_Text, { 0.45, 0.45, 0.45, 1.0 })
            imgui.Text('Stopped')
            imgui.PopStyleColor()
        end

        imgui.Separator()

        -- 最終サーチ時刻
        imgui.PushStyleColor(ImGuiCol_Text, { 0.65, 0.65, 0.65, 1.0 })
        imgui.Text('Last search: ' .. state.last_search_str)
        imgui.PopStyleColor()

        imgui.Separator()

        -- 操作ボタン
        if not state.active then
            if imgui.Button(' Start ##eas') then
                state.active = true
                state.timer  = cfg.interval   -- 即座に初回サーチ
                print('[EAS] Started monitoring: ' ..
                    (cfg.zone_name ~= '' and cfg.zone_name or 'all zones'))
            end
        else
            if imgui.Button(' Stop ##eas') then
                state.active    = false
                state.searching = false
                print('[EAS] Stopped.')
            end
        end

        imgui.SameLine()
        if imgui.Button(' Search Now ##eas') then
            do_search()
        end

        imgui.SameLine()
        if imgui.Button(' Clear ##eas') then
            state.results      = {}
            state.result_count = 0
            state.combat       = false
        end

        -- プレイヤーリスト（コメント収集後に表示）
        local has_results = false
        for _ in pairs(state.results) do has_results = true; break end
        if has_results then
            imgui.Separator()
            imgui.Text('Players found:')
            if imgui.BeginChild('eas_list##eas', { 0, 120 }, true) then
                for name, info in pairs(state.results) do
                    local line = name
                    if info.comment and info.comment ~= '' then
                        line = line .. '  ' .. info.comment
                    end
                    imgui.Text(line)
                end
                imgui.EndChild()
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

    -- サーチ間隔タイマー（サーチ待ち中は進めない）
    if state.active and not state.searching then
        state.timer = state.timer + dt
        if state.timer >= cfg.interval then
            state.timer = 0
            do_search()
        end
    end

    -- サーチタイムアウト処理
    if state.searching then
        state.search_timeout = state.search_timeout - dt
        if state.search_timeout <= 0 then
            evaluate_combat()
        end
    end

    -- 点滅アニメーション用タイマー
    if state.combat then
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
        print('[EAS] Started. Zone: ' .. (cfg.zone_name ~= '' and cfg.zone_name or 'all'))

    elseif sub == 'off' or sub == 'stop' then
        state.active    = false
        state.searching = false
        print('[EAS] Stopped.')

    elseif sub == 'search' then
        do_search()

    elseif sub == 'zone' then
        if args[3] then
            -- 残り引数をスペースで結合（ゾーン名にスペースが含まれる場合）
            local parts = {}
            for i = 3, #args do parts[#parts + 1] = args[i] end
            cfg.zone_name = table.concat(parts, ' ')
            settings.save()
            print('[EAS] Zone: ' .. cfg.zone_name)
        else
            print('[EAS] Zone: ' .. (cfg.zone_name ~= '' and cfg.zone_name or '(not set)'))
        end

    elseif sub == 'zoneid' then
        if args[3] then
            cfg.zone_id = tonumber(args[3]) or 0
            settings.save()
            print('[EAS] Zone ID: ' .. cfg.zone_id)
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
        state.results      = {}
        state.result_count = 0
        state.combat       = false

    elseif sub == 'help' then
        print('[EAS] ---- EventAreaSearch コマンド ----')
        print('  /eas              ウィンドウ 表示/非表示')
        print('  /eas on/off       監視 開始/停止')
        print('  /eas search       手動サーチ')
        print('  /eas zone <name>  対象ゾーン名設定')
        print('  /eas zoneid <n>   ゾーン ID フィルタ設定（0=なし）')
        print('  /eas threshold <n> 戦闘検知しきい値（デフォルト 10）')
        print('  /eas interval <n> サーチ間隔（秒、デフォルト 300）')
        print('  /eas debug        パケットデバッグ 有効/無効')
        print('  /eas clear        結果クリア')
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

-- ============================================================
-- PTChatLog.lua
-- Ashita v4 アドオン - パーティ/アライアンスチャット + 戦闘ログ統合記録
-- 機能: チャット蓄積・表示・Markdownエクスポート（AI分析用）
-- Version: 1.4.0
-- ============================================================

addon.name    = 'PTChatLog'
addon.author  = '7xxxk'
addon.version = '1.4.0'
addon.desc    = 'PT/Allianceチャット + 戦闘ログ統合記録・Markdownエクスポート'

require('common')
local settings = require('settings')
local imgui    = require('imgui')

-- ============================================================
-- 定数
-- ============================================================
local PACKET_CHAT   = 0x017
local MODE_PARTY    = 0x05
local MODE_ALLIANCE = 0x0D

-- デバッグフラグ: true にすると PARTY/ALLIANCE 以外の全 0x017 モードをプリント
-- 実機で戦闘してモードIDを確認後、battle_modes 設定に追加すること
local DEBUG_BATTLE = false

-- ジョブ名テーブル (ID 0-22)
local JOB_NAMES = {
    [0]='None', [1]='WAR', [2]='MNK', [3]='WHM', [4]='BLM',
    [5]='RDM',  [6]='THF', [7]='PLD', [8]='DRK', [9]='BST',
    [10]='BRD', [11]='RNG', [12]='SAM', [13]='NIN', [14]='DRG',
    [15]='SMN', [16]='BLU', [17]='COR', [18]='PUP', [19]='DNC',
    [20]='SCH', [21]='GEO', [22]='RUN',
}

-- ============================================================
-- デフォルト設定
-- ============================================================
local default_settings = T{
    window = T{
        x = 100, y = 300, w = 520, h = 380,
        visible = true, locked = false,
        settings_visible = false,
    },
    display = T{
        bg_alpha = 0.80, font_scale = 1.0,
        max_lines = 300, auto_scroll = true,
    },
    colors = T{
        party    = T{0.40, 0.90, 1.00, 1.0},
        alliance = T{0.80, 0.60, 1.00, 1.0},
        battle   = T{1.00, 0.75, 0.35, 1.0},
        highlight= T{1.00, 0.95, 0.30, 1.0},
    },
    highlight_keywords = T{},   -- [{word=string}]
    filter_players     = T{},   -- [string]
    filter_keywords    = T{},   -- [string]
    show_battle        = true,
    battle_modes       = T{},   -- 実測後に設定 例: {0x1D, 0x1E}
    ai_hint = 'FF11コンテンツ攻略セッションの記録です。戦術・役割分担・問題点を分析し、次回攻略プランを提案してください。',
}

local cfg = T{}

settings.register('settings', 'ptchatlog_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- 状態変数
-- ============================================================
local chat_buffer      = {}
local scroll_to_bottom = false

-- InputText 用バッファ（NULパディング）
local ui_kw_input = { string.rep('\0', 64) }
local ui_fp_input = { string.rep('\0', 64) }
local ui_fk_input = { string.rep('\0', 64) }
local ui_bm_input = { string.rep('\0', 16) }

-- ============================================================
-- ヘルパー関数
-- ============================================================

-- NUL終端文字列をパケットデータから読み取る（byte_offset: 0-indexed）
local function read_string(data, byte_offset)
    local result = {}
    local i = byte_offset
    local limit = byte_offset + 256
    while i < limit do
        local b = ashita.bits.unpack_be(data, i * 8, 8)
        if not b or b == 0 then break end
        result[#result + 1] = string.char(b)
        i = i + 1
    end
    return table.concat(result)
end

-- ディレクトリ作成（Windows/Wine対応）
local function ensure_dir(path)
    os.execute('mkdir "' .. path .. '" 2>NUL')
end

-- フィルタ判定（trueなら追加しない）
local function is_filtered(entry)
    local sender_lower = (entry.sender or ''):lower()
    for _, name in ipairs(cfg.filter_players) do
        if sender_lower == name:lower() then return true end
    end
    local msg_lower = (entry.message or ''):lower()
    for _, kw in ipairs(cfg.filter_keywords) do
        if kw ~= '' and string.find(msg_lower, kw:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- ハイライト色を返す（マッチなしは nil）
local function find_highlight(message)
    local msg_lower = message:lower()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party then
        local my_name = party:GetMemberName(0)
        if my_name and my_name ~= '' then
            if string.find(msg_lower, my_name:lower(), 1, true) then
                return cfg.colors.highlight
            end
        end
    end
    for _, kw_entry in ipairs(cfg.highlight_keywords) do
        if kw_entry.word and kw_entry.word ~= '' then
            if string.find(msg_lower, kw_entry.word:lower(), 1, true) then
                return cfg.colors.highlight
            end
        end
    end
    return nil
end

-- 戦闘モード判定
local function is_battle_mode(mode)
    for _, m in ipairs(cfg.battle_modes) do
        if m == mode then return true end
    end
    return false
end

-- パーティ構成スナップショット（エクスポート時に呼び出す）
local function get_party_snapshot()
    local snap = {}
    local party = AshitaCore:GetMemoryManager():GetParty()
    if not party then return snap end
    for i = 0, 17 do
        local name = party:GetMemberName(i)
        if name and name ~= '' then
            local main_id = party:GetMemberMainJob(i)
            local sub_id  = party:GetMemberSubJob(i)
            snap[#snap + 1] = {
                name = name,
                job  = JOB_NAMES[main_id] or '?',
                sub  = JOB_NAMES[sub_id]  or '?',
            }
        end
    end
    return snap
end

-- バッファにエントリを追加（フィルタ後）
local function push_entry(entry)
    if is_filtered(entry) then return end
    chat_buffer[#chat_buffer + 1] = entry
    while #chat_buffer > cfg.display.max_lines do
        table.remove(chat_buffer, 1)
    end
    scroll_to_bottom = true
end

-- ============================================================
-- export_markdown: Markdownエクスポート（前方宣言）
-- render_main から呼ばれるため local で前方宣言し後で代入
-- ============================================================
local export_markdown

-- ============================================================
-- render_main: メインウィンドウ
-- ============================================================
local function render_main()
    if not cfg.window.visible then return end

    imgui.SetNextWindowBgAlpha(cfg.display.bg_alpha)
    imgui.SetNextWindowSize({cfg.window.w, cfg.window.h}, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos({cfg.window.x, cfg.window.y}, ImGuiCond_FirstUseEver)

    local flags = ImGuiWindowFlags_NoCollapse
    if cfg.window.locked then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoResize)
    end

    if imgui.Begin('PTChatLog##main', true, flags) then
        imgui.SetWindowFontScale(cfg.display.font_scale)
        cfg.window.x, cfg.window.y = imgui.GetWindowPos()
        cfg.window.w, cfg.window.h = imgui.GetWindowSize()

        -- ---- ツールバー ----
        if imgui.Button('Export') then
            export_markdown()
        end
        imgui.SameLine()
        if imgui.Button('Settings') then
            cfg.window.settings_visible = not cfg.window.settings_visible
        end
        imgui.SameLine()
        if imgui.Button('Clear') then
            chat_buffer = {}
        end
        imgui.SameLine()
        if imgui.Button(cfg.window.locked and 'Unlock' or 'Lock') then
            cfg.window.locked = not cfg.window.locked
            settings.save()
        end
        imgui.SameLine()
        imgui.TextDisabled(string.format('(%d/%d)', #chat_buffer, cfg.display.max_lines))

        imgui.Separator()

        -- ---- ログ表示領域 ----
        if imgui.BeginChild('ptchatlog_scroll', {0, 0}, false, ImGuiWindowFlags_HorizontalScrollbar) then
            for _, entry in ipairs(chat_buffer) do
                local badge_color
                if entry.type == 'PARTY' then
                    badge_color = cfg.colors.party
                elseif entry.type == 'ALLIANCE' then
                    badge_color = cfg.colors.alliance
                else
                    badge_color = cfg.colors.battle
                end

                -- タイムスタンプ
                imgui.TextColored({0.55, 0.55, 0.55, 1.0},
                    string.format('[%s]', entry.timestamp))
                imgui.SameLine()

                -- タイプバッジ + 送信者
                if entry.sender and entry.sender ~= '' then
                    imgui.TextColored(badge_color,
                        string.format('[%s] %s:', entry.type, entry.sender))
                else
                    imgui.TextColored(badge_color,
                        string.format('[%s]', entry.type))
                end
                imgui.SameLine()

                -- メッセージ（ハイライト色または白）
                local hl = find_highlight(entry.message)
                imgui.TextColored(hl or {1.0, 1.0, 1.0, 1.0}, entry.message)
            end

            -- 自動スクロール
            if scroll_to_bottom and cfg.display.auto_scroll then
                imgui.SetScrollHereY(1.0)
            end
            scroll_to_bottom = false
        end
        imgui.EndChild()
    end
    imgui.End()
end

-- ============================================================
-- render_settings: 設定ウィンドウ
-- ============================================================
local function render_settings()
    if not cfg.window.settings_visible then return end

    imgui.SetNextWindowSize({440, 520}, ImGuiCond_FirstUseEver)

    local vis_ref = {cfg.window.settings_visible}
    if imgui.Begin('PTChatLog Settings##cfg', vis_ref, ImGuiWindowFlags_None) then

        -- ---- 表示設定 ----
        if imgui.CollapsingHeader('Display##h', ImGuiTreeNodeFlags_DefaultOpen) then
            local alpha_ref = {cfg.display.bg_alpha}
            if imgui.SliderFloat('BG Alpha##d', alpha_ref, 0.0, 1.0) then
                cfg.display.bg_alpha = alpha_ref[1]
            end

            local scale_ref = {cfg.display.font_scale}
            if imgui.SliderFloat('Font Scale##d', scale_ref, 0.5, 2.0) then
                cfg.display.font_scale = scale_ref[1]
            end

            local lines_ref = {cfg.display.max_lines}
            if imgui.InputInt('Max Lines##d', lines_ref, 10, 100) then
                cfg.display.max_lines = math.max(50, math.min(2000, lines_ref[1]))
            end

            local scroll_ref = {cfg.display.auto_scroll}
            if imgui.Checkbox('Auto Scroll##d', scroll_ref) then
                cfg.display.auto_scroll = scroll_ref[1]
            end
        end

        -- ---- 色設定 ----
        if imgui.CollapsingHeader('Colors##h') then
            imgui.Text('Party   :')
            imgui.SameLine()
            imgui.ColorEdit4('##col_party', cfg.colors.party)

            imgui.Text('Alliance:')
            imgui.SameLine()
            imgui.ColorEdit4('##col_alliance', cfg.colors.alliance)

            imgui.Text('Battle  :')
            imgui.SameLine()
            imgui.ColorEdit4('##col_battle', cfg.colors.battle)

            imgui.Text('Highlight:')
            imgui.SameLine()
            imgui.ColorEdit4('##col_highlight', cfg.colors.highlight)
        end

        -- ---- 戦闘ログ設定 ----
        if imgui.CollapsingHeader('Battle Log##h') then
            local sb_ref = {cfg.show_battle}
            if imgui.Checkbox('Show Battle Log##bl', sb_ref) then
                cfg.show_battle = sb_ref[1]
            end

            imgui.Spacing()
            imgui.TextColored({0.8, 0.8, 0.3, 1.0},
                string.format('Active modes: %d', #cfg.battle_modes))
            for i, m in ipairs(cfg.battle_modes) do
                imgui.Text(string.format('  0x%02X', m))
                imgui.SameLine()
                if imgui.Button('X##bm_' .. i) then
                    table.remove(cfg.battle_modes, i)
                    settings.save()
                    break
                end
            end

            imgui.Spacing()
            imgui.InputText('Hex##bm_add', ui_bm_input, 16)
            imgui.SameLine()
            if imgui.Button('Add##bm') then
                local hex_str = ui_bm_input[1]:match('^[^\0]*')
                local val = tonumber(hex_str, 16)
                if val and val > 0 and val <= 0xFF then
                    cfg.battle_modes[#cfg.battle_modes + 1] = val
                    ui_bm_input[1] = string.rep('\0', 16)
                    settings.save()
                end
            end

            imgui.Spacing()
            imgui.TextDisabled('DEBUG_BATTLE=true で実機ログを確認し')
            imgui.TextDisabled('mode ID を Hex 欄に入力して Add してください')
        end

        -- ---- キーワードハイライト ----
        if imgui.CollapsingHeader('Highlight Keywords##h') then
            imgui.InputText('Keyword##kw_add', ui_kw_input, 64)
            imgui.SameLine()
            if imgui.Button('Add##kw') then
                local word = ui_kw_input[1]:match('^[^\0]*')
                if word and word ~= '' then
                    cfg.highlight_keywords[#cfg.highlight_keywords + 1] = { word = word }
                    ui_kw_input[1] = string.rep('\0', 64)
                    settings.save()
                end
            end
            for i, kw in ipairs(cfg.highlight_keywords) do
                imgui.TextColored(cfg.colors.highlight, '  ' .. kw.word)
                imgui.SameLine()
                if imgui.Button('X##kw_' .. i) then
                    table.remove(cfg.highlight_keywords, i)
                    settings.save()
                    break
                end
            end
        end

        -- ---- フィルタ: プレイヤー名 ----
        if imgui.CollapsingHeader('Filter Players##h') then
            imgui.InputText('Name##fp_add', ui_fp_input, 64)
            imgui.SameLine()
            if imgui.Button('Add##fp') then
                local name = ui_fp_input[1]:match('^[^\0]*')
                if name and name ~= '' then
                    cfg.filter_players[#cfg.filter_players + 1] = name
                    ui_fp_input[1] = string.rep('\0', 64)
                    settings.save()
                end
            end
            for i, name in ipairs(cfg.filter_players) do
                imgui.Text('  ' .. name)
                imgui.SameLine()
                if imgui.Button('X##fp_' .. i) then
                    table.remove(cfg.filter_players, i)
                    settings.save()
                    break
                end
            end
        end

        -- ---- フィルタ: キーワード ----
        if imgui.CollapsingHeader('Filter Keywords##h') then
            imgui.InputText('Keyword##fk_add', ui_fk_input, 64)
            imgui.SameLine()
            if imgui.Button('Add##fk') then
                local word = ui_fk_input[1]:match('^[^\0]*')
                if word and word ~= '' then
                    cfg.filter_keywords[#cfg.filter_keywords + 1] = word
                    ui_fk_input[1] = string.rep('\0', 64)
                    settings.save()
                end
            end
            for i, word in ipairs(cfg.filter_keywords) do
                imgui.Text('  ' .. word)
                imgui.SameLine()
                if imgui.Button('X##fk_' .. i) then
                    table.remove(cfg.filter_keywords, i)
                    settings.save()
                    break
                end
            end
        end

        -- ---- AI ヒント ----
        if imgui.CollapsingHeader('AI Analysis Hint##h') then
            imgui.TextWrapped(cfg.ai_hint)
        end

        imgui.Separator()
        if imgui.Button('Save Settings') then
            settings.save()
            print('[PTChatLog] 設定を保存しました。')
        end
    end
    imgui.End()

    -- X ボタンで閉じた場合に反映
    cfg.window.settings_visible = vis_ref[1]
end

-- ============================================================
-- export_markdown: Markdownエクスポート（本体）
-- ============================================================
export_markdown = function()
    if #chat_buffer == 0 then
        print('[PTChatLog] バッファが空です。エクスポートするものがありません。')
        return
    end

    local export_dir = addon.path .. 'exports\\'
    ensure_dir(export_dir)

    local filename = os.date('PTChatLog_%Y%m%d_%H%M%S.md')
    local filepath = export_dir .. filename
    local f = io.open(filepath, 'w')
    if not f then
        print('[PTChatLog] エクスポート失敗: ' .. filepath)
        return
    end

    -- ---- ヘッダー ----
    f:write('# PTChatLog Export\n\n')
    f:write(string.format('- **Generated**: %s\n', os.date('%Y-%m-%d %H:%M:%S')))
    f:write(string.format('- **Version**: %s\n', addon.version))
    f:write(string.format('- **Entries**: %d\n\n', #chat_buffer))

    -- ---- パーティメタデータ ----
    local snap = get_party_snapshot()
    if #snap > 0 then
        f:write('## Party Metadata\n\n')
        f:write('| Name | Job | SubJob |\n')
        f:write('|------|-----|--------|\n')
        for _, m in ipairs(snap) do
            f:write(string.format('| %s | %s | %s |\n', m.name, m.job, m.sub))
        end
        f:write('\n')
    end

    -- ---- ログ本文 ----
    f:write('## Log\n\n')
    f:write('| Time | Type | Sender | Message |\n')
    f:write('|------|------|--------|--------|\n')

    for _, entry in ipairs(chat_buffer) do
        if entry.type ~= 'BATTLE' or cfg.show_battle then
            local sender  = (entry.sender  or ''):gsub('|', '\\|')
            local message = (entry.message or ''):gsub('|', '\\|')
            f:write(string.format('| %s | %-8s | %-14s | %s |\n',
                entry.timestamp, entry.type, sender, message))
        end
    end

    -- ---- AI 分析ヒント ----
    f:write('\n---\n\n')
    f:write('<!-- AI Analysis Instructions:\n')
    f:write(cfg.ai_hint .. '\n')
    f:write('-->\n')

    f:close()
    print('[PTChatLog] エクスポート完了: ' .. filename)
end

-- ============================================================
-- packet_in: 0x017 チャットパケット
-- ============================================================
ashita.events.register('packet_in', 'ptchatlog_packet_in', function(e)
    if e.id ~= PACKET_CHAT then return end
    -- offset 0x04: モードバイト（チャット種別）
    local mode    = ashita.bits.unpack_be(e.data_raw, 0x04 * 8, 8)
    -- offset 0x08-0x17: 送信者名（16バイト固定パディング、NUL終端）
    local sender  = read_string(e.data_raw, 0x08)
    -- offset 0x18-: メッセージ本文（NUL終端）
    local message = read_string(e.data_raw, 0x18)

    if message == '' then return end

    -- デバッグ: 0x017 パケットをファイルにダンプ（オフセット確認用）
    if DEBUG_BATTLE then
        local dbg = io.open(addon.path .. 'debug.txt', 'a')
        if dbg then
            local hex = {}
            for i = 0, 23 do
                hex[i+1] = string.format('%02X', ashita.bits.unpack_be(e.data_raw, i * 8, 8) or 0)
            end
            dbg:write('[' .. os.date('%H:%M:%S') .. '] hex: ' .. table.concat(hex, ' ') .. '\n')
            dbg:write(string.format('  mode=0x%02X\n', mode))
            dbg:close()
        end
    end

    local entry
    if mode == MODE_PARTY then
        entry = {
            timestamp = os.date('%H:%M:%S'),
            type      = 'PARTY',
            sender    = sender,
            message   = message,
            color     = cfg.colors.party,
        }
    elseif mode == MODE_ALLIANCE then
        entry = {
            timestamp = os.date('%H:%M:%S'),
            type      = 'ALLIANCE',
            sender    = sender,
            message   = message,
            color     = cfg.colors.alliance,
        }
    elseif cfg.show_battle and is_battle_mode(mode) then
        entry = {
            timestamp = os.date('%H:%M:%S'),
            type      = 'BATTLE',
            sender    = sender,
            message   = message,
            color     = cfg.colors.battle,
        }
    end

    if entry then
        push_entry(entry)
    end
end)

-- ============================================================
-- command ハンドラ: /ptlog [export|clear|lock|settings]
-- ============================================================
ashita.events.register('command', 'ptchatlog_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/ptlog' and cmd ~= '/ptl' then return end

    e.blocked = true
    local sub = args[2] and args[2]:lower() or ''

    if sub == 'export' then
        export_markdown()
    elseif sub == 'clear' then
        chat_buffer = {}
        print('[PTChatLog] バッファをクリアしました。')
    elseif sub == 'lock' then
        cfg.window.locked = not cfg.window.locked
        settings.save()
        print('[PTChatLog] Lock: ' .. tostring(cfg.window.locked))
    elseif sub == 'settings' then
        cfg.window.settings_visible = not cfg.window.settings_visible
    else
        cfg.window.visible = not cfg.window.visible
    end
end)

-- ============================================================
-- d3d_present ハンドラ
-- ============================================================
ashita.events.register('d3d_present', 'ptchatlog_present', function()
    render_main()
    render_settings()
end)

-- ============================================================
-- load / unload
-- ============================================================
ashita.events.register('load', 'ptchatlog_load', function()
    cfg = settings.load(default_settings)
    -- v1.3.0 からのアップグレード対策（不足フィールドをデフォルト補完）
    cfg.highlight_keywords = cfg.highlight_keywords or T{}
    cfg.filter_players     = cfg.filter_players     or T{}
    cfg.filter_keywords    = cfg.filter_keywords    or T{}
    cfg.show_battle        = cfg.show_battle ~= nil and cfg.show_battle or true
    cfg.battle_modes       = cfg.battle_modes or T{}
    cfg.ai_hint            = cfg.ai_hint or default_settings.ai_hint
    print(string.format('[PTChatLog] v%s loaded.', addon.version))
end)

ashita.events.register('unload', 'ptchatlog_unload', function()
    settings.save()
    print('[PTChatLog] unloaded.')
end)

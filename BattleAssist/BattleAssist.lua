-- ============================================================
-- BattleAssist.lua
-- Ashita v4 アドオン - ナイト（PLD）向け戦闘支援ツール
-- 機能: 即死技アラート + バフ切れ警告 + 敵技ログ (ImGui HUD)
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '3.0'
addon.desc    = 'PLD向け即死技アラート + バフ切れ警告 + 敵技ログ'

require('common')
local skills_def = require('BattleAssist_skills')
local settings = require('settings')
local imgui = require('imgui')

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    x       = 10,
    y       = 10,
    visible = true,
}
local cfg = T{}

-- 設定変更コールバック
settings.register('settings', 'battleassist_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- 即死技アラート状態
-- ============================================================
local alert = {
    active  = false,
    message = '',
    timer   = 0,
    blink   = 0,
}

-- ============================================================
-- バフアラート状態
-- ============================================================
local buff_alert = {
    active  = false,
    message = '',
    timer   = 0,
}
local buff_check_timer = 0
local debug_buff_timer = 0
local prev_missing_count = 0   -- 前回のバフ切れ数（音を鳴らすタイミング判定用）
local buff_watch_ready   = false  -- リロード直後の誤検知防止フラグ

-- ============================================================
-- 敵技ログ状態
-- ============================================================
-- ログエントリ構造: { name, effect, level, timestamp }
local SKILL_LOG_MAX    = 8     -- 最大表示件数
local SKILL_LOG_EXPIRE = 60.0  -- エントリ有効期間（秒）
local skill_log        = {}    -- 新→古の順で格納

-- ============================================================
-- UIカラー定数
-- ============================================================
local COL_CRITICAL = { 1.0, 0.25, 0.25, 1.0 }  -- 赤（即死級）
local COL_WARNING  = { 1.0, 0.80, 0.10, 1.0 }  -- 黄（要注意）
local COL_INFO     = { 1.0, 1.0,  1.0,  1.0 }  -- 白（通常）
local COL_HEADER   = { 0.6, 0.85, 1.0,  1.0 }  -- 水色（ヘッダー）
local COL_ELAPSED  = { 0.55, 0.55, 0.55, 1.0 } -- グレー（経過時間）

-- ============================================================
-- デバッグモード（技ID実測時に true に変更する）
-- ============================================================
local DEBUG_PACKET = false
local DEBUG_LOG_FILE = AshitaCore:GetInstallPath() .. 'logs\\BattleAssist_debug.log'

local function debug_log(msg)
    if not DEBUG_PACKET then return end
    local timestamp = os.date('%H:%M:%S')
    local line = string.format('[%s] %s\n', timestamp, msg)
    print('[BattleAssist DEBUG] ' .. msg)
    local f = io.open(DEBUG_LOG_FILE, 'a')
    if f then
        f:write(line)
        f:close()
    end
end

-- ============================================================
-- バフID定義（※要実測 - DEBUG_PACKET=true で確認すること）
-- ============================================================
local BUFF_PHALANX  = 116  -- Phalanx
local BUFF_SENTINEL = 62   -- Sentinel
local BUFF_REPRISAL = 403  -- Reprisal
local BUFF_CRUSADE  = 289  -- Crusade

-- ============================================================
-- ヘルパー: 指定バフIDがアクティブか確認
-- ============================================================
local function has_buff(buff_id)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return false end
    local buffs = player:GetBuffs()
    if buffs == nil then return false end
    for _, v in pairs(buffs) do
        if v == buff_id then return true end
    end
    return false
end

-- ============================================================
-- ヘルパー: levelに対応するカラーを返す
-- ============================================================
local function level_color(level)
    if level == 'critical' then return COL_CRITICAL end
    if level == 'warning'  then return COL_WARNING  end
    return COL_INFO
end

-- ============================================================
-- packet_in ハンドラ - 0x028 アクションパケット解析
-- ============================================================
ashita.events.register('packet_in', 'battleassist_packet_in', function(e)

    if e.id ~= 0x028 then return end

    -- パケット構造 (0x028 Action Packet)
    -- actor_id  : offset 0x04 (uint32)
    -- action_id : offset 0x18 (uint16) ※要実測確認
    -- category  : offset 0x0A (uint8)
    local actor_id  = ashita.bits.unpack_be(e.data_raw, 0x04 * 8, 32)
    local action_id = ashita.bits.unpack_be(e.data_raw, 0x18 * 8, 16)
    local category  = ashita.bits.unpack_be(e.data_raw, 0x0A * 8, 8)

    -- デバッグモード: 全アクションパケットをログ出力
    debug_log(string.format(
        'actor=%08X action_id=%d category=%d',
        actor_id, action_id, category
    ))

    -- パーティメンバーの技は無視
    local party = AshitaCore:GetMemoryManager():GetParty()
    for i = 0, 5 do
        if party:GetMemberServerId(i) == actor_id then
            return
        end
    end

    -- 技定義テーブルと照合
    local skill = skills_def.dangerous_skills[action_id]
    if skill then
        local should_alert = false

        if skill.phase == 'cast' or skill.phase == 'both' then
            if category == 8 or category == 11 then  -- ※要実測
                should_alert = true
            end
        end

        if skill.phase == 'impact' or skill.phase == 'both' then
            if category == 2 then  -- ※要実測
                should_alert = true
            end
        end

        if should_alert then
            -- フラッシュアラート（即死技）
            alert.active  = true
            alert.message = '⚠ ' .. skill.name .. ' ！'
            alert.timer   = 5.0
            alert.blink   = 0

            -- サウンド通知（critical.wav が存在する場合のみ再生）
            -- ファイルを配置: addons/BattleAssist/sounds/critical.wav
            local sound_path = addon.path .. 'sounds/critical.wav'
            pcall(function()
                ashita.misc.play_sound(sound_path)
            end)

            -- 敵技ログに追加（新しいエントリを先頭に挿入）
            table.insert(skill_log, 1, {
                name      = skill.name,
                effect    = skill.effect or '不明',
                level     = skill.level,
                timestamp = os.clock(),
            })
            -- 最大件数超過分を末尾から削除
            if #skill_log > SKILL_LOG_MAX then
                table.remove(skill_log, #skill_log)
            end
        end
    end
end)

-- ============================================================
-- バフ監視（1秒ごとにチェック）
-- ============================================================
local function update_buff_watch(dt)
    buff_check_timer = buff_check_timer + dt
    if buff_check_timer < 1.0 then return end
    buff_check_timer = 0

    local missing = {}
    if not has_buff(BUFF_PHALANX) then
        table.insert(missing, 'Phalanx')
    end
    if not has_buff(BUFF_SENTINEL) then
        table.insert(missing, 'Sentinel')
    end
    if not has_buff(BUFF_REPRISAL) then
        table.insert(missing, 'Reprisal')
    end
    if not has_buff(BUFF_CRUSADE) then
        table.insert(missing, 'Crusade')
    end

    -- バフ切れが新たに増えた時だけ音を鳴らす（リロード直後は除く）
    if buff_watch_ready and #missing > prev_missing_count then
        ashita.misc.play_sound(addon.path .. '\\sounds\\buff_off.wav')
    end
    prev_missing_count = #missing
    buff_watch_ready = true

    if #missing > 0 then
        buff_alert.active  = true
        buff_alert.message = table.concat(missing, ' / ') .. ' OFF!'
        buff_alert.timer   = 5.0
    end
end

-- ============================================================
-- render - ImGui 描画
-- ============================================================
ashita.events.register('d3d_present', 'battleassist_render', function()

    local dt = imgui.GetIO().DeltaTime

    -- バフ監視を更新
    update_buff_watch(dt)

    -- 期限切れの敵技ログエントリを削除（末尾から走査して安全に削除）
    local now = os.clock()
    for i = #skill_log, 1, -1 do
        if now - skill_log[i].timestamp > SKILL_LOG_EXPIRE then
            table.remove(skill_log, i)
        end
    end

    -- --------------------------------------------------------
    -- デバッグ: 現在のバフID一覧をログ出力（DEBUG_PACKET=true 時のみ、3秒ごと）
    -- ※ バフIDが特定できたらこのブロックを削除すること
    -- --------------------------------------------------------
    if DEBUG_PACKET then
        debug_buff_timer = debug_buff_timer + dt
        if debug_buff_timer >= 3.0 then
            debug_buff_timer = 0
            local player = AshitaCore:GetMemoryManager():GetPlayer()
            if player then
                local buffs = player:GetBuffs()
                if buffs then
                    local buff_list = {}
                    for _, v in pairs(buffs) do
                        if v > 0 then
                            table.insert(buff_list, tostring(v))
                        end
                    end
                    debug_log('BUFFS: ' .. table.concat(buff_list, ','))
                end
            end
        end
    end

    -- --------------------------------------------------------
    -- メインHUD: タブ切り替えウィンドウ（ナイトバフ / 敵技ログ）
    -- --------------------------------------------------------
    if cfg.visible then
        local win_flags = bit.bor(
            ImGuiWindowFlags_NoTitleBar,
            ImGuiWindowFlags_NoScrollbar,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav
        )

        imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)
        imgui.SetNextWindowBgAlpha(0.80)

        if imgui.Begin('BattleAssist##main', true, win_flags) then

            -- ウィンドウ移動後に座標を保存
            cfg.x, cfg.y = imgui.GetWindowPos()

            if imgui.BeginTabBar('BA_Tabs') then

                -- ====================================================
                -- タブ1: ナイトバフ
                -- ====================================================
                if imgui.BeginTabItem('ナイトバフ') then

                    -- ファランクス状態
                    local ph_ok = has_buff(BUFF_PHALANX)
                    imgui.PushStyleColor(ImGuiCol_Text,
                        ph_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
                    imgui.Text(ph_ok and '[*] Phalanx' or '[ ] Phalanx')
                    imgui.PopStyleColor()

                    -- センチネル状態
                    local st_ok = has_buff(BUFF_SENTINEL)
                    imgui.PushStyleColor(ImGuiCol_Text,
                        st_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
                    imgui.Text(st_ok and '[*] Sentinel' or '[ ] Sentinel')
                    imgui.PopStyleColor()

                    -- リプライザル状態
                    local rp_ok = has_buff(BUFF_REPRISAL)
                    imgui.PushStyleColor(ImGuiCol_Text,
                        rp_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
                    imgui.Text(rp_ok and '[*] Reprisal' or '[ ] Reprisal')
                    imgui.PopStyleColor()

                    -- クルセード状態
                    local cr_ok = has_buff(BUFF_CRUSADE)
                    imgui.PushStyleColor(ImGuiCol_Text,
                        cr_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
                    imgui.Text(cr_ok and '[*] Crusade' or '[ ] Crusade')
                    imgui.PopStyleColor()

                    -- バフ切れアラートテキスト（HUD内）
                    if buff_alert.active then
                        buff_alert.timer = buff_alert.timer - dt
                        if buff_alert.timer <= 0 then
                            buff_alert.active = false
                        else
                            imgui.Separator()
                            imgui.PushStyleColor(ImGuiCol_Text, COL_WARNING)
                            imgui.Text(buff_alert.message)
                            imgui.PopStyleColor()
                        end
                    end

                    imgui.EndTabItem()
                end

                -- ====================================================
                -- タブ2: 敵技ログ
                -- ====================================================
                if imgui.BeginTabItem('敵技ログ') then

                    -- ヘッダー行
                    imgui.PushStyleColor(ImGuiCol_Text, COL_HEADER)
                    imgui.Text('技名')
                    imgui.PopStyleColor()
                    imgui.SameLine()
                    imgui.PushStyleColor(ImGuiCol_Text, COL_HEADER)
                    imgui.Text('| 効果')
                    imgui.PopStyleColor()
                    imgui.SameLine()
                    imgui.PushStyleColor(ImGuiCol_Text, COL_HEADER)
                    imgui.Text('| 経過')
                    imgui.PopStyleColor()

                    imgui.Separator()

                    if #skill_log == 0 then
                        imgui.PushStyleColor(ImGuiCol_Text, COL_ELAPSED)
                        imgui.Text('記録なし')
                        imgui.PopStyleColor()
                    else
                        for _, entry in ipairs(skill_log) do
                            local col     = level_color(entry.level)
                            local elapsed = math.floor(os.clock() - entry.timestamp)

                            -- 技名
                            imgui.PushStyleColor(ImGuiCol_Text, col)
                            imgui.Text(entry.name)
                            imgui.PopStyleColor()

                            -- 効果
                            imgui.SameLine()
                            imgui.PushStyleColor(ImGuiCol_Text, col)
                            imgui.Text('| ' .. entry.effect)
                            imgui.PopStyleColor()

                            -- 経過時間
                            imgui.SameLine()
                            imgui.PushStyleColor(ImGuiCol_Text, COL_ELAPSED)
                            imgui.Text(string.format('| %ds', elapsed))
                            imgui.PopStyleColor()
                        end
                    end

                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
        end
        imgui.End()
    end

    -- --------------------------------------------------------
    -- 即死技アラート描画（画面中央・赤文字点滅）
    -- --------------------------------------------------------
    if alert.active then

        alert.timer = alert.timer - dt
        if alert.timer <= 0 then
            alert.active = false
        end

        -- 点滅制御（0.6秒周期 / 0.3秒ON・0.3秒OFF）
        alert.blink = alert.blink + dt
        local visible = (alert.blink % 0.6) < 0.3

        if visible then
            local io    = imgui.GetIO()
            local win_w = 420
            local win_h = 80

            imgui.SetNextWindowPos(
                { (io.DisplaySize.x - win_w) * 0.5, io.DisplaySize.y * 0.35 },
                ImGuiCond_Always
            )
            imgui.SetNextWindowSize({ win_w, win_h }, ImGuiCond_Always)
            imgui.SetNextWindowBgAlpha(0.85)

            local flags = bit.bor(
                ImGuiWindowFlags_NoDecoration,
                ImGuiWindowFlags_NoInputs,
                ImGuiWindowFlags_NoNav,
                ImGuiWindowFlags_NoMove
            )

            if imgui.Begin('##danger_alert', true, flags) then
                imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.15, 0.15, 1.0 })

                local text   = alert.message
                local text_w = imgui.CalcTextSize(text)
                imgui.SetCursorPosX(math.max((win_w - text_w.x) * 0.5, 8))
                imgui.SetWindowFontScale(1.6)
                imgui.Text(text)
                imgui.SetWindowFontScale(1.0)

                imgui.PopStyleColor()

                imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 1.0, 0.2, 0.2, 0.8 })
                imgui.ProgressBar(alert.timer / 5.0, { -1, 6 }, '')
                imgui.PopStyleColor()
            end
            imgui.End()
        end
    end
end)

-- ============================================================
-- zone_change イベント - エリアチェンジ時はバフ監視をリセット
-- ============================================================
ashita.events.register('zone_change', 'battleassist_zone_change', function(e)
    buff_watch_ready   = false
    prev_missing_count = 0
end)

-- ============================================================
-- load イベント - 設定を読み込む
-- ============================================================
ashita.events.register('load', 'battleassist_load', function()
    cfg = settings.load(default_settings)
    print('[BattleAssist] v3.0 loaded. Debug=' .. tostring(DEBUG_PACKET))
end)

-- ============================================================
-- unload イベント - 設定を保存する
-- ============================================================
ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

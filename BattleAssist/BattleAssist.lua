-- ============================================================
-- BattleAssist.lua
-- Ashita v4 アドオン - ナイト（PLD）向け戦闘支援ツール
-- 機能: 即死技アラート + バフ切れ警告 (ImGui HUD)
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '2.0'
addon.desc    = 'PLD向け即死技アラート + バフ切れ警告'

require('common')
local skills_def = require('BattleAssist_skills')
local settings = require('settings')

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

-- ============================================================
-- デバッグモード（技ID実測時に true に変更する）
-- ============================================================
local DEBUG_PACKET = true
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
local BUFF_PHALANX  = 53   -- ファランクス ※要実測
local BUFF_REPRISAL = 294  -- レプリザル  ※要実測

-- ============================================================
-- ヘルパー: 指定バフIDがアクティブか確認
-- ============================================================
local function has_buff(buff_id)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return false end
    local buffs = player:GetBuffs()
    for i = 0, 31 do
        if buffs[i] == buff_id then
            return true
        end
    end
    return false
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
        table.insert(missing, 'ファランクス')
    end
    if not has_buff(BUFF_REPRISAL) then
        table.insert(missing, 'レプリザル')
    end

    if #missing > 0 then
        buff_alert.active  = true
        buff_alert.message = table.concat(missing, ' / ') .. ' 切れ！'
        buff_alert.timer   = 5.0
    end
end

-- ============================================================
-- render - ImGui 描画
-- ============================================================
ashita.events.register('render', 'battleassist_render', function()

    local dt = imgui.GetIO().DeltaTime

    -- バフ監視を更新
    update_buff_watch(dt)

    -- --------------------------------------------------------
    -- メインHUD（バフ状態ステータス表示）
    -- --------------------------------------------------------
    if cfg.visible then
        local hud_flags = bit.bor(
            ImGuiWindowFlags_NoTitleBar,
            ImGuiWindowFlags_NoScrollbar,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav
        )

        imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)
        imgui.SetNextWindowBgAlpha(0.65)

        if imgui.Begin('BattleAssist##hud', true, hud_flags) then

            -- ウィンドウ移動後に座標を保存
            local pos = imgui.GetWindowPos()
            cfg.x = pos.x
            cfg.y = pos.y

            -- タイトル
            imgui.PushStyleColor(ImGuiCol_Text, { 0.6, 0.85, 1.0, 1.0 })
            imgui.Text('⚔ BattleAssist')
            imgui.PopStyleColor()

            imgui.Separator()

            -- ファランクス状態
            local ph_ok = has_buff(BUFF_PHALANX)
            imgui.PushStyleColor(ImGuiCol_Text,
                ph_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
            imgui.Text(ph_ok and '● ファランクス' or '○ ファランクス')
            imgui.PopStyleColor()

            -- レプリザル状態
            local rp_ok = has_buff(BUFF_REPRISAL)
            imgui.PushStyleColor(ImGuiCol_Text,
                rp_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
            imgui.Text(rp_ok and '● レプリザル' or '○ レプリザル')
            imgui.PopStyleColor()

            -- バフ切れアラートテキスト（HUD内）
            if buff_alert.active then
                buff_alert.timer = buff_alert.timer - dt
                if buff_alert.timer <= 0 then
                    buff_alert.active = false
                else
                    imgui.Separator()
                    imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.75, 0.0, 1.0 })
                    imgui.Text(buff_alert.message)
                    imgui.PopStyleColor()
                end
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
-- load イベント - 設定を読み込む
-- ============================================================
ashita.events.register('load', 'battleassist_load', function()
    cfg = settings.load(default_settings)
    print('[BattleAssist] v2.0 loaded. Debug=' .. tostring(DEBUG_PACKET))
end)

-- ============================================================
-- unload イベント - 設定を保存する
-- ============================================================
ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

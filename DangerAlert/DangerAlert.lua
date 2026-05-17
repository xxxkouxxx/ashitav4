-- ============================================================
-- DangerAlert.lua
-- Ashita v4 アドオン - 危険技（即死技・状態異常）アラート
-- ============================================================

addon.name    = 'DangerAlert'
addon.author  = '7xxxk'
addon.version = '1.0'
addon.desc    = 'Danger skill alert (instant-kill / status)'

require('common')
local settings   = require('settings')
local imgui      = require('imgui')
local skills_def = require('DangerAlert_skills')

-- ============================================================
-- デバッグモード
-- true にするとチャット + logs/DangerAlert_debug.log に出力
-- ============================================================
local DEBUG_PACKET = false

local function debug_log(msg)
    if not DEBUG_PACKET then return end
    local ts   = os.date('%H:%M:%S')
    local line = string.format('[%s] %s\n', ts, msg)
    print('[DangerAlert DEBUG] ' .. msg)
    local log_path = AshitaCore:GetInstallPath() .. 'logs\\DangerAlert_debug.log'
    local f = io.open(log_path, 'a')
    if f then
        f:write(line)
        f:close()
    end
end

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    x               = 10,
    y               = 10,
    alpha           = 0.8,
    visible         = true,
    disabled_skills = T{},
}
local cfg = T{}

settings.register('settings', 'dangeralert_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- アラート表示状態
-- ============================================================
local alert = {
    active  = false,
    message = '',
    timer   = 0,
    blink   = 0,
}

-- ============================================================
-- パケット監視: 0x028 アクションパケット（危険技検知）
-- ============================================================
ashita.events.register('packet_in', 'dangeralert_packet_in', function(e)
    if e.id ~= 0x028 then return end

    local ok, err = pcall(function()
        local actor_id  = ashita.bits.unpack_be(e.data_raw, 0x04 * 8, 32)
        local action_id = ashita.bits.unpack_be(e.data_raw, 0x18 * 8, 16)
        local category  = ashita.bits.unpack_be(e.data_raw, 0x0A * 8, 8)

        debug_log(string.format('actor=%08X action_id=%d category=%d',
            actor_id, action_id, category))

        -- パーティメンバー（自分含む）の行動は無視
        local party = AshitaCore:GetMemoryManager():GetParty()
        for i = 0, 5 do
            if party:GetMemberServerId(i) == actor_id then return end
        end

        local skill = skills_def.dangerous_skills[action_id]
        if not skill then return end

        local should_alert = false
        if skill.phase == 'cast' or skill.phase == 'both' then
            if category == 8 or category == 11 then should_alert = true end
        end
        if skill.phase == 'impact' or skill.phase == 'both' then
            if category == 2 then should_alert = true end
        end

        if should_alert and not cfg.disabled_skills[action_id] then
            alert.active  = true
            alert.message = '!! ' .. skill.name .. ' !!'
            alert.timer   = 5.0
            alert.blink   = 0
            pcall(function()
                ashita.misc.play_sound(addon.path .. 'sounds\\critical.wav')
            end)
        end
    end)

    if not ok then
        debug_log('packet_in error: ' .. tostring(err))
    end
end)

-- ============================================================
-- コマンドハンドラ
--   /dangeralert または /da  → HUD 表示/非表示トグル
--   /da debug                → DEBUG_PACKET ランタイムトグル
--   /da test                 → テスト用ダミーアラート発火
-- ============================================================
ashita.events.register('command', 'dangeralert_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    if args[1] ~= '/dangeralert' and args[1] ~= '/da' then return end

    e.blocked = true

    if args[2] == 'debug' then
        DEBUG_PACKET = not DEBUG_PACKET
        print(string.format('[DangerAlert] DEBUG_PACKET = %s', tostring(DEBUG_PACKET)))
        return
    end

    if args[2] == 'test' then
        alert.active  = true
        alert.message = '!! TEST !!'
        alert.timer   = 5.0
        alert.blink   = 0
        print('[DangerAlert] Test alert fired.')
        return
    end

    cfg.visible = not cfg.visible
    settings.save()
    print(string.format('[DangerAlert] HUD %s', cfg.visible and 'shown' or 'hidden'))
end)

-- ============================================================
-- render: ImGui 描画（毎フレーム）
--   ウィンドウ1: HUD（スキルリスト・チェックボックス）
--   ウィンドウ2: アラートオーバーレイ（画面中央・赤文字点滅）
-- ============================================================
ashita.events.register('d3d_present', 'dangeralert_render', function()

    local dt = imgui.GetIO().DeltaTime

    -- HUD 非表示でもアラートタイマーは常に更新（見逃し防止）
    if alert.active then
        alert.timer = alert.timer - dt
        if alert.timer <= 0 then
            alert.active = false
        end
    end

    -- -------------------------------------------------------
    -- ウィンドウ1: メイン HUD
    -- -------------------------------------------------------
    if cfg.visible then
        local hud_flags = bit.bor(
            ImGuiWindowFlags_NoScrollbar,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav
        )
        imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)
        imgui.SetNextWindowBgAlpha(cfg.alpha)

        if imgui.Begin('DangerAlert##hud', true, hud_flags) then
            cfg.x, cfg.y = imgui.GetWindowPos()

            imgui.PushStyleColor(ImGuiCol_Text, { 0.6, 0.85, 1.0, 1.0 })
            imgui.Text('DangerAlert')
            imgui.PopStyleColor()

            imgui.Separator()

            for id, skill in pairs(skills_def.dangerous_skills) do
                local val = { not cfg.disabled_skills[id] }
                if imgui.Checkbox(skill.name .. '##da_' .. id, val) then
                    cfg.disabled_skills[id] = (not val[1]) or nil
                    settings.save()
                end
            end
        end
        imgui.End()
    end

    -- -------------------------------------------------------
    -- ウィンドウ2: アラートオーバーレイ
    -- -------------------------------------------------------
    if alert.active then
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

            local overlay_flags = bit.bor(
                ImGuiWindowFlags_NoDecoration,
                ImGuiWindowFlags_NoInputs,
                ImGuiWindowFlags_NoNav,
                ImGuiWindowFlags_NoMove
            )
            if imgui.Begin('##dangeralert_popup', true, overlay_flags) then
                imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.15, 0.15, 1.0 })
                local text_w = imgui.CalcTextSize(alert.message)
                imgui.SetCursorPosX(math.max((win_w - text_w.x) * 0.5, 8))
                imgui.SetWindowFontScale(1.6)
                imgui.Text(alert.message)
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
-- load / unload
-- ============================================================
ashita.events.register('load', 'dangeralert_load', function()
    cfg = settings.load(default_settings)
    print('[DangerAlert] v' .. addon.version .. ' loaded.')
    if DEBUG_PACKET then
        print('[DangerAlert] DEBUG_PACKET = true (packet logging enabled)')
    end
end)

ashita.events.register('unload', 'dangeralert_unload', function()
    settings.save()
    print('[DangerAlert] unloaded.')
end)

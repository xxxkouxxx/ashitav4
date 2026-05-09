-- ============================================================
-- BattleAssist.lua
-- Ashita v4 アドオン - ナイト（PLD）向けバフ監視 HUD
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '3.0'
addon.desc    = 'PLD向けバフ切れ警告 HUD'

require('common')
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

settings.register('settings', 'battleassist_settings_update', function(new_cfg)
    cfg = new_cfg
end)

-- ============================================================
-- バフ監視状態
-- ============================================================
local buff_alert = {
    active  = false,
    message = '',
    timer   = 0,
}
local buff_check_timer   = 0
local prev_missing_count = 0
local buff_watch_ready   = false

-- ============================================================
-- バフID定義
-- ============================================================
local BUFF_PHALANX  = 116
local BUFF_SENTINEL = 62
local BUFF_REPRISAL = 403
local BUFF_CRUSADE  = 289

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
-- バフ監視（1秒ごとにチェック）
-- ============================================================
local function update_buff_watch(dt)
    buff_check_timer = buff_check_timer + dt
    if buff_check_timer < 1.0 then return end
    buff_check_timer = 0

    local missing = {}
    if not has_buff(BUFF_PHALANX)  then table.insert(missing, 'Phalanx')  end
    if not has_buff(BUFF_SENTINEL)  then table.insert(missing, 'Sentinel')  end
    if not has_buff(BUFF_REPRISAL)  then table.insert(missing, 'Reprisal')  end
    if not has_buff(BUFF_CRUSADE)   then table.insert(missing, 'Crusade')   end

    if buff_watch_ready and #missing > prev_missing_count then
        ashita.misc.play_sound(addon.path .. '\\sounds\\buff_off.wav')
    end
    prev_missing_count = #missing
    buff_watch_ready   = true

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
    update_buff_watch(dt)

    if not cfg.visible then return end

    local hud_flags = bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoNav
    )

    imgui.SetNextWindowPos({ cfg.x, cfg.y }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowBgAlpha(0.65)

    if imgui.Begin('BattleAssist##hud', true, hud_flags) then

        cfg.x, cfg.y = imgui.GetWindowPos()

        imgui.PushStyleColor(ImGuiCol_Text, { 0.6, 0.85, 1.0, 1.0 })
        imgui.Text('BattleAssist')
        imgui.PopStyleColor()

        imgui.Separator()

        local ph_ok = has_buff(BUFF_PHALANX)
        imgui.PushStyleColor(ImGuiCol_Text, ph_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
        imgui.Text(ph_ok and '[*] Phalanx' or '[ ] Phalanx')
        imgui.PopStyleColor()

        local st_ok = has_buff(BUFF_SENTINEL)
        imgui.PushStyleColor(ImGuiCol_Text, st_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
        imgui.Text(st_ok and '[*] Sentinel' or '[ ] Sentinel')
        imgui.PopStyleColor()

        local rp_ok = has_buff(BUFF_REPRISAL)
        imgui.PushStyleColor(ImGuiCol_Text, rp_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
        imgui.Text(rp_ok and '[*] Reprisal' or '[ ] Reprisal')
        imgui.PopStyleColor()

        local cr_ok = has_buff(BUFF_CRUSADE)
        imgui.PushStyleColor(ImGuiCol_Text, cr_ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
        imgui.Text(cr_ok and '[*] Crusade' or '[ ] Crusade')
        imgui.PopStyleColor()

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
end)

-- ============================================================
-- zone_change - エリアチェンジ時はバフ監視をリセット
-- ============================================================
ashita.events.register('zone_change', 'battleassist_zone_change', function()
    buff_watch_ready   = false
    prev_missing_count = 0
end)

-- ============================================================
-- load / unload
-- ============================================================
ashita.events.register('load', 'battleassist_load', function()
    cfg = settings.load(default_settings)
    print('[BattleAssist] v3.0 loaded.')
end)

ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

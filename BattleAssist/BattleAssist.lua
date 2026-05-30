-- ============================================================
-- BattleAssist.lua
-- Ashita v4 アドオン - ナイト（PLD）向けバフ監視 HUD
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '4.0'
addon.desc    = 'PLD向けバフ切れ警告 + リキャスト表示 HUD'

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
-- リキャストタイマー定義（バフ消滅時にソフトウェア計測で開始）
-- recast: デフォルトのリキャスト秒数
-- ============================================================
local RECAST_DEFS = {
    [BUFF_REPRISAL] = { name = 'Reprisal', recast = 30  },
    [BUFF_SENTINEL] = { name = 'Sentinel', recast = 300 },
    [BUFF_CRUSADE]  = { name = 'Crusade',  recast = 300 },
}

local recast_timers = {
    [BUFF_REPRISAL] = 0,
    [BUFF_SENTINEL] = 0,
    [BUFF_CRUSADE]  = 0,
}

local prev_buff_state = {
    [BUFF_PHALANX]  = false,
    [BUFF_SENTINEL] = false,
    [BUFF_REPRISAL] = false,
    [BUFF_CRUSADE]  = false,
}

-- ============================================================
-- スペルリキャスト取得（メモリ読み取り）
-- Ashita v4: GetSpellTimerByIndex(spell_id) → 1/4秒単位のtick
-- ============================================================
local function get_spell_recast_secs(spell_id)
    local recast = AshitaCore:GetMemoryManager():GetRecast()
    if recast == nil then return 0 end
    local tick = recast:GetSpellTimerByIndex(spell_id)
    if tick == nil then return 0 end
    return math.ceil(tick / 4)
end

-- スペルリキャスト表示リスト
-- spell_id は実機で確認が必要。コメントアウトで無効化できる
local SPELL_RECASTS = {
    -- Flash（PLD/RDM）: spell_id は実機確認要
    -- { name = 'Flash',   spell_id = 57  },
    -- Phalanx（PLD II）: spell_id は実機確認要
    -- { name = 'Phalanx', spell_id = 36  },
}

-- ============================================================
-- 時間フォーマット（秒 → 表示文字列）
-- ============================================================
local function fmt_time(secs)
    secs = math.ceil(secs)
    if secs <= 0 then return '' end
    if secs < 60 then
        return string.format('%ds', secs)
    else
        return string.format('%d:%02d', math.floor(secs / 60), secs % 60)
    end
end

-- ============================================================
-- バフ監視・リキャストタイマー更新
-- ============================================================
local function update_buff_watch(dt)
    -- フレームごとにリキャストカウントダウン
    for buff_id in pairs(recast_timers) do
        if recast_timers[buff_id] > 0 then
            recast_timers[buff_id] = math.max(0, recast_timers[buff_id] - dt)
        end
    end

    -- 1秒ごとにバフ状態チェック
    buff_check_timer = buff_check_timer + dt
    if buff_check_timer < 1.0 then return end
    buff_check_timer = 0

    local cur = {
        [BUFF_PHALANX]  = has_buff(BUFF_PHALANX),
        [BUFF_SENTINEL] = has_buff(BUFF_SENTINEL),
        [BUFF_REPRISAL] = has_buff(BUFF_REPRISAL),
        [BUFF_CRUSADE]  = has_buff(BUFF_CRUSADE),
    }

    if buff_watch_ready then
        -- バフ消滅を検知 → リキャストタイマー開始
        for buff_id, def in pairs(RECAST_DEFS) do
            if prev_buff_state[buff_id] and not cur[buff_id] then
                recast_timers[buff_id] = def.recast
            end
        end
    end

    for buff_id in pairs(prev_buff_state) do
        prev_buff_state[buff_id] = cur[buff_id]
    end

    local missing = {}
    if not cur[BUFF_PHALANX]  then table.insert(missing, 'Phalanx')  end
    if not cur[BUFF_SENTINEL]  then table.insert(missing, 'Sentinel')  end
    if not cur[BUFF_REPRISAL]  then table.insert(missing, 'Reprisal')  end
    if not cur[BUFF_CRUSADE]   then table.insert(missing, 'Crusade')   end

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
-- バフ行描画ヘルパー
-- ok: バフ有効か, name: 表示名, recast_secs: リキャスト残り秒
-- ============================================================
local function draw_buff_row(ok, name, recast_secs)
    local label
    local time_str = fmt_time(recast_secs)
    if ok then
        label = string.format('[*] %-10s', name)
    elseif time_str ~= '' then
        label = string.format('[ ] %-10s %s', name, time_str)
    else
        label = string.format('[ ] %s', name)
    end

    imgui.PushStyleColor(ImGuiCol_Text,
        ok and { 0.4, 1.0, 0.4, 1.0 } or { 1.0, 0.35, 0.35, 1.0 })
    imgui.Text(label)
    imgui.PopStyleColor()
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

        -- アビリティ系バフ（リキャスト表示付き）
        draw_buff_row(has_buff(BUFF_PHALANX),  'Phalanx',  0)
        draw_buff_row(has_buff(BUFF_SENTINEL), 'Sentinel', recast_timers[BUFF_SENTINEL])
        draw_buff_row(has_buff(BUFF_REPRISAL), 'Reprisal', recast_timers[BUFF_REPRISAL])
        draw_buff_row(has_buff(BUFF_CRUSADE),  'Crusade',  recast_timers[BUFF_CRUSADE])

        -- スペルリキャスト表示（spell_id 確認後にコメントアウト解除）
        if #SPELL_RECASTS > 0 then
            imgui.Separator()
            for _, sp in ipairs(SPELL_RECASTS) do
                local secs = get_spell_recast_secs(sp.spell_id)
                local label
                if secs > 0 then
                    label = string.format('%-10s %s', sp.name, fmt_time(secs))
                    imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.75, 0.35, 1.0 })
                else
                    label = string.format('%-10s READY', sp.name)
                    imgui.PushStyleColor(ImGuiCol_Text, { 0.4, 1.0, 0.4, 1.0 })
                end
                imgui.Text(label)
                imgui.PopStyleColor()
            end
        end

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
-- zone_change - エリアチェンジ時はバフ監視・タイマーをリセット
-- ============================================================
ashita.events.register('zone_change', 'battleassist_zone_change', function()
    buff_watch_ready   = false
    prev_missing_count = 0
    for buff_id in pairs(recast_timers) do
        recast_timers[buff_id] = 0
    end
    for buff_id in pairs(prev_buff_state) do
        prev_buff_state[buff_id] = false
    end
end)

-- ============================================================
-- load / unload
-- ============================================================
ashita.events.register('load', 'battleassist_load', function()
    cfg = settings.load(default_settings)
    print('[BattleAssist] v4.0 loaded.')
end)

ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

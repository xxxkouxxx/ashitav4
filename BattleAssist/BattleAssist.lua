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
-- アビリティリキャスト定義
-- call_id: GetAbilityCallByIndex が返す値（実機で /ba debug 確認）
-- 未確認の場合は 0 にしておくとリキャスト表示をスキップ
-- ============================================================
local ABILITY_DEFS = {
    { buff_id = BUFF_REPRISAL, name = 'Reprisal', call_id = 177 },
    { buff_id = BUFF_SENTINEL, name = 'Sentinel', call_id = 71  },
    { buff_id = BUFF_CRUSADE,  name = 'Crusade',  call_id = 231 },
}

-- スペルリキャスト定義
-- spell_id: GetSpellTimerByIndex に渡す値（実機で /ba debug 確認）
-- 未確認の場合は nil にしておくとスキップ
local SPELL_DEFS = {
    -- { name = 'Flash',   spell_id = 57  },
    -- { name = 'Phalanx', spell_id = 36  },
}

-- ============================================================
-- メモリ読み取り（全て pcall でラップしてクラッシュ防止）
-- GetAbilityTimerByIndex の単位は秒（実機確認要）
-- GetSpellTimerByIndex の単位は 1/4 秒（実機確認要）
-- ============================================================
local function get_ability_recast_secs(call_id)
    if call_id == 0 or call_id == nil then return 0 end
    local ok, result = pcall(function()
        local recast = AshitaCore:GetMemoryManager():GetRecast()
        if recast == nil then return 0 end
        for i = 0, 31 do
            local c = recast:GetAbilityCallByIndex(i)
            if c ~= nil and c == call_id then
                local t = recast:GetAbilityTimerByIndex(i)
                return (t ~= nil) and t or 0
            end
        end
        return 0
    end)
    return (ok and type(result) == 'number') and result or 0
end

local function get_spell_recast_secs(spell_id)
    if spell_id == nil then return 0 end
    local ok, result = pcall(function()
        local recast = AshitaCore:GetMemoryManager():GetRecast()
        if recast == nil then return 0 end
        local t = recast:GetSpellTimerByIndex(spell_id)
        return (t ~= nil) and math.ceil(t / 4) or 0
    end)
    return (ok and type(result) == 'number') and result or 0
end

-- ============================================================
-- 時間フォーマット（秒 → "Xs" / "X:XX"）
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
-- バフ行描画ヘルパー
-- ============================================================
local function draw_buff_row(ok, name, recast_secs)
    local time_str = fmt_time(recast_secs)
    local label
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

        -- アビリティバフ（リキャストはメモリから直接取得）
        draw_buff_row(has_buff(BUFF_PHALANX), 'Phalanx', 0)
        for _, def in ipairs(ABILITY_DEFS) do
            local recast = get_ability_recast_secs(def.call_id)
            draw_buff_row(has_buff(def.buff_id), def.name, recast)
        end

        -- スペルリキャスト（SPELL_DEFS に定義がある場合のみ）
        if #SPELL_DEFS > 0 then
            imgui.Separator()
            for _, sp in ipairs(SPELL_DEFS) do
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
-- zone_change - エリアチェンジ時はバフ監視をリセット
-- ============================================================
ashita.events.register('zone_change', 'battleassist_zone_change', function()
    buff_watch_ready   = false
    prev_missing_count = 0
end)

-- ============================================================
-- コマンド処理
-- /ba debug  - リキャストスロット一覧をチャットに表示（call_id 確認用）
-- /ba hide   - HUD を非表示
-- /ba show   - HUD を表示
-- ============================================================
ashita.events.register('command', 'battleassist_command', function(e)
    local args = e.command:lower():args()
    if args[1] ~= '/ba' then return end

    if args[2] == 'debug' then
        -- アビリティリキャストスロット一覧
        print('[BattleAssist] === アビリティリキャスト スロット一覧 ===')
        local ok = pcall(function()
            local recast = AshitaCore:GetMemoryManager():GetRecast()
            if recast == nil then
                print('[BattleAssist] GetRecast() が nil です')
                return
            end
            for i = 0, 31 do
                local call  = recast:GetAbilityCallByIndex(i)
                local timer = recast:GetAbilityTimerByIndex(i)
                if call ~= nil and call > 0 then
                    print(string.format('[BattleAssist]  slot=%d  call_id=%d  timer=%s',
                        i, call, tostring(timer)))
                end
            end
        end)
        if not ok then
            print('[BattleAssist] デバッグ中にエラーが発生しました')
        end

        -- スペルリキャストスロット一覧（リキャスト中のもののみ）
        print('[BattleAssist] === スペルリキャスト（リキャスト中のみ）===')
        local ok2 = pcall(function()
            local recast = AshitaCore:GetMemoryManager():GetRecast()
            if recast == nil then return end
            for i = 0, 1023 do
                local timer = recast:GetSpellTimerByIndex(i)
                if timer ~= nil and timer > 0 then
                    print(string.format('[BattleAssist]  spell_id=%d  timer=%d (約%ds)',
                        i, timer, math.ceil(timer / 4)))
                end
            end
        end)
        if not ok2 then
            print('[BattleAssist] スペルデバッグ中にエラーが発生しました')
        end

        e.blocked = true

    elseif args[2] == 'hide' then
        cfg.visible = false
        settings.save()
        e.blocked = true

    elseif args[2] == 'show' then
        cfg.visible = true
        settings.save()
        e.blocked = true
    end
end)

-- ============================================================
-- load / unload
-- ============================================================
ashita.events.register('load', 'battleassist_load', function()
    cfg = settings.load(default_settings)
    print('[BattleAssist] v4.0 loaded.')
    print('[BattleAssist] /ba debug でリキャストスロット一覧を確認できます')
end)

ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

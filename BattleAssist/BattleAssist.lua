-- ============================================================
-- BattleAssist.lua  v4.1
-- Ashita v4 アドオン - ナイト（PLD）向けバフ監視 HUD
-- ファランクス最優先 + パニック時の立て直しUI
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '4.1'
addon.desc    = 'PLD向けファランクス最優先バフ監視 HUD'

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
-- バフID定義
-- ============================================================
local BUFF_PHALANX  = 116
local BUFF_SENTINEL = 62
local BUFF_REPRISAL = 403
local BUFF_CRUSADE  = 289

-- ファランクスのスペルリキャスト（spell_id は /ba debug で実機確認。暫定36）
local PHALANX_SPELL_ID = 36

-- ============================================================
-- アビリティリキャスト定義（call_id は /ba debug で実機確認）
-- ============================================================
local ABILITY_DEFS = {
    { buff_id = BUFF_REPRISAL, name = 'Reprisal', call_id = 177 },
    { buff_id = BUFF_SENTINEL, name = 'Sentinel', call_id = 71  },
    { buff_id = BUFF_CRUSADE,  name = 'Crusade',  call_id = 231 },
}

-- ============================================================
-- バフ監視状態
-- ============================================================
local buff_check_timer   = 0
local prev_missing_count = 0
local buff_watch_ready   = false

-- ============================================================
-- バフ有無チェック
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
-- バフ残り時間取得（秒）
-- 取得できない場合は -1 を返す（表示側で "ACTIVE" にフォールバック）
-- GetBuffTimers() の存在は実機依存のため pcall でラップ
-- ============================================================
local function get_buff_remaining(buff_id)
    local ok, result = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player == nil then return -1 end
        local buffs   = player:GetBuffs()
        local timers  = player:GetBuffTimers()
        if buffs == nil or timers == nil then return -1 end
        for i = 1, #buffs do
            if buffs[i] == buff_id then
                local t = timers[i]
                return (t ~= nil and type(t) == 'number') and t or -1
            end
        end
        return -1
    end)
    return (ok and type(result) == 'number') and result or -1
end

-- ============================================================
-- スペルリキャスト残り秒数取得
-- ============================================================
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
-- アビリティリキャスト残り秒数取得
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
-- バフ監視（1秒ごと。バフが増えたら警告音）
-- ============================================================
local function update_buff_watch(dt)
    buff_check_timer = buff_check_timer + dt
    if buff_check_timer < 1.0 then return end
    buff_check_timer = 0

    local missing = 0
    if not has_buff(BUFF_PHALANX)  then missing = missing + 1 end
    if not has_buff(BUFF_SENTINEL)  then missing = missing + 1 end
    if not has_buff(BUFF_REPRISAL)  then missing = missing + 1 end
    if not has_buff(BUFF_CRUSADE)   then missing = missing + 1 end

    if buff_watch_ready and missing > prev_missing_count then
        ashita.misc.play_sound(addon.path .. '\\sounds\\buff_off.wav')
    end
    prev_missing_count = missing
    buff_watch_ready   = true
end

-- ============================================================
-- ファランクス パニックパネル描画
--   has_ph    : バフ有無
--   ph_remain : バフ残り秒数（-1 = 取得不可）
--   ph_recast : リキャスト残り秒数（0 = 使用可能）
-- ============================================================
local function draw_phalanx_panel(has_ph, ph_remain, ph_recast)
    local t    = imgui.GetTime()
    local fast  = math.floor(t * 4) % 2 == 0  -- 4Hz点滅
    local slow  = math.floor(t * 2) % 2 == 0  -- 2Hz点滅

    -- リキャスト記号（◎ or ×）
    local rc_ready  = (ph_recast <= 0)
    local rc_symbol = rc_ready and '\xe2\x97\x8e' or '\xc3\x97'  -- ◎ / ×
    local rc_color  = rc_ready and { 0.3, 1.0, 0.3, 1.0 } or { 1.0, 0.3, 0.3, 1.0 }

    -- 残り時間テキスト
    local remain_str
    if not has_ph then
        remain_str = '---'
    elseif ph_remain >= 0 then
        local r = fmt_time(ph_remain)
        remain_str = (r ~= '') and r or 'ACTIVE'
    else
        remain_str = 'ACTIVE'
    end

    -- === 行1: バフ状態（大フォント） ===
    imgui.SetWindowFontScale(1.5)

    if has_ph then
        local low = (ph_remain >= 0 and ph_remain <= 30)
        if low then
            -- 残り少ない: 橙低速点滅
            local c = slow and { 1.0, 0.65, 0.0, 1.0 } or { 0.85, 0.45, 0.0, 1.0 }
            imgui.PushStyleColor(ImGuiCol_Text, c)
            imgui.Text(string.format('! PHALANX %s !', remain_str))
        else
            -- 余裕あり: 緑
            imgui.PushStyleColor(ImGuiCol_Text, { 0.3, 1.0, 0.4, 1.0 })
            imgui.Text(' \xe2\x96\xa0 PHALANX ON \xe2\x96\xa0')  -- ■ PHALANX ON ■
        end
        imgui.PopStyleColor()
    else
        if rc_ready then
            -- バフOFF + RC完了 → 高速点滅で緊急通知
            local c = fast and { 1.0, 1.0, 0.0, 1.0 } or { 1.0, 0.15, 0.15, 1.0 }
            imgui.PushStyleColor(ImGuiCol_Text, c)
            imgui.Text('>> CAST PHALANX! <<')
        else
            -- バフOFF + RC中 → 低速赤点滅
            local c = slow and { 1.0, 0.25, 0.25, 1.0 } or { 0.65, 0.1, 0.1, 1.0 }
            imgui.PushStyleColor(ImGuiCol_Text, c)
            imgui.Text(' !! PHALANX OFF !!')
        end
        imgui.PopStyleColor()
    end

    -- === 行2: 残り時間 + RC記号（中フォント） ===
    imgui.SetWindowFontScale(1.15)

    -- 残り時間
    local remain_color = has_ph
        and { 0.85, 0.95, 0.85, 1.0 }
        or  { 0.65, 0.65, 0.65, 1.0 }
    imgui.PushStyleColor(ImGuiCol_Text, remain_color)
    imgui.Text(string.format('  \xe6\xae\x8b\xe3\x82\x8a: %-6s', remain_str))  -- 残り:
    imgui.PopStyleColor()

    -- RC記号（同じ行に横並び）
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol_Text, { 0.65, 0.65, 0.65, 1.0 })
    imgui.Text('  RC:')
    imgui.PopStyleColor()
    imgui.SameLine()

    -- RC完了 + バフOFFの場合は RC記号も点滅させて強調
    if rc_ready and not has_ph then
        local c = fast and { 1.0, 1.0, 0.0, 1.0 } or { 1.0, 0.5, 0.0, 1.0 }
        imgui.PushStyleColor(ImGuiCol_Text, c)
    else
        imgui.PushStyleColor(ImGuiCol_Text, rc_color)
    end
    imgui.Text(rc_symbol)
    imgui.PopStyleColor()

    imgui.SetWindowFontScale(1.0)
end

-- ============================================================
-- サブバフ行（Sentinel / Reprisal / Crusade）
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
    imgui.SetNextWindowBgAlpha(0.78)

    if imgui.Begin('BattleAssist##hud', true, hud_flags) then
        cfg.x, cfg.y = imgui.GetWindowPos()

        -- ファランクス最優先パネル
        local has_ph   = has_buff(BUFF_PHALANX)
        local ph_remain = get_buff_remaining(BUFF_PHALANX)
        local ph_recast = get_spell_recast_secs(PHALANX_SPELL_ID)
        draw_phalanx_panel(has_ph, ph_remain, ph_recast)

        -- 区切り線
        imgui.Separator()

        -- Sentinel / Reprisal / Crusade（小さめ）
        imgui.SetWindowFontScale(0.9)
        for _, def in ipairs(ABILITY_DEFS) do
            local recast = get_ability_recast_secs(def.call_id)
            draw_buff_row(has_buff(def.buff_id), def.name, recast)
        end
        imgui.SetWindowFontScale(1.0)
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
-- /ba debug  - リキャストスロット一覧をチャットに表示（ID確認用）
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
        if not ok then print('[BattleAssist] デバッグ中にエラーが発生しました') end

        -- スペルリキャストスロット一覧
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
        if not ok2 then print('[BattleAssist] スペルデバッグ中にエラーが発生しました') end

        -- バフタイマー取得テスト
        print('[BattleAssist] === バフタイマー取得テスト ===')
        local ok3 = pcall(function()
            local player = AshitaCore:GetMemoryManager():GetPlayer()
            if player == nil then print('[BattleAssist] GetPlayer() が nil') return end
            local buffs  = player:GetBuffs()
            local timers = player:GetBuffTimers()
            if timers == nil then
                print('[BattleAssist] GetBuffTimers() は未対応（残り時間表示不可）')
                return
            end
            for i = 1, #buffs do
                if buffs[i] ~= nil and buffs[i] > 0 and buffs[i] ~= 0xFFFF then
                    print(string.format('[BattleAssist]  buff_id=%d  timer=%s',
                        buffs[i], tostring(timers[i])))
                end
            end
        end)
        if not ok3 then print('[BattleAssist] バフタイマーテスト中にエラーが発生しました') end

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
    print('[BattleAssist] v4.1 loaded.')
    print('[BattleAssist] Phalanx spell_id=36（暫定値）。/ba debug で実機確認してください。')
end)

ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

-- ============================================================
-- BattleAssist.lua  v4.1
-- Ashita v4 アドオン - ナイト（PLD）向けバフ監視 HUD
-- ファランクス最優先 + パニック時の立て直しUI
-- ============================================================

addon.name    = 'BattleAssist'
addon.author  = '7xxxk'
addon.version = '4.3'
addon.desc    = 'PLD向けファランクス最優先バフ監視 HUD'

require('common')
local settings = require('settings')
local imgui = require('imgui')

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    x              = 10,
    y              = 10,
    visible        = true,
    phalanx_recast = 60,  -- Phalanxリキャスト時間（秒）。/ba rc <秒> で変更
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

-- ============================================================
-- サブバフ定義（Sentinel / Reprisal / Crusade）
-- ============================================================
local ABILITY_DEFS = {
    { buff_id = BUFF_REPRISAL, name = 'Reprisal' },
    { buff_id = BUFF_SENTINEL, name = 'Sentinel' },
    { buff_id = BUFF_CRUSADE,  name = 'Crusade'  },
}

-- ============================================================
-- バフ監視状態
-- ============================================================
local buff_check_timer   = 0
local prev_missing_count = 0
local buff_watch_ready   = false
local ph_prev_active     = false  -- 前回チェック時のPhalanxバフ状態

-- ============================================================
-- ファランクスRCトラッカー
-- GetSpellTimerByIndex が使えないため、バフ付与タイミングを検知して推定
-- Phalanxバフが false→true に変わった瞬間 = 詠唱完了とみなして記録
-- ============================================================
local ph_recast_track = {
    cast_time = -1,  -- 最後にPhalanxが付いた時刻。-1 = 不明（ロード時点で有効だった場合）
}

local function get_phalanx_rc_remain()
    if ph_recast_track.cast_time < 0 then return 0 end  -- 不明 → 使用可とみなす
    local elapsed = imgui.GetTime() - ph_recast_track.cast_time
    local remain  = cfg.phalanx_recast - elapsed
    return (remain > 0) and remain or 0
end

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
-- statustimers アドオンと同じ方式:
--   player:GetStatusIcons()  → バフIDの配列
--   player:GetStatusTimers() → 生タイマー値の配列（ヴァナ紀元ベース）
-- 取得できない場合は -1 を返す
-- ============================================================
local VANA_EPOCH     = 0x3C307D70  -- ヴァナ・ディール紀元 Unix タイムスタンプ（2002年1月）
local INFINITE_TIMER = 0x7FFFFFFF  -- 無限バフのマーカー値

local function calc_remain_secs(raw_timer)
    if raw_timer == nil or raw_timer == 0 or raw_timer == INFINITE_TIMER then
        return -1
    end
    local offset   = os.time() - VANA_EPOCH
    local comparand = offset * 60
    local remain   = raw_timer - comparand
    -- トリエニアル（3年周期）オーバーフロー対策
    while remain < -2147483648 do
        remain = remain + 0xFFFFFFFF
    end
    if remain < 1 then return 0 end
    return math.ceil(remain / 60)
end

local function get_buff_remaining(buff_id)
    local ok, result = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer()
        if player == nil then return -1 end
        local icons  = player:GetStatusIcons()
        local timers = player:GetStatusTimers()
        if icons == nil or timers == nil then return -1 end
        for i = 1, #icons do
            if icons[i] == buff_id then
                return calc_remain_secs(timers[i])
            end
        end
        return -1
    end)
    return (ok and type(result) == 'number') and result or -1
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
-- バフ監視（1秒ごと。バフが増えたら警告音 + Phalanx付与検知）
-- ============================================================
local function update_buff_watch(dt)
    buff_check_timer = buff_check_timer + dt
    if buff_check_timer < 1.0 then return end
    buff_check_timer = 0

    local curr_ph = has_buff(BUFF_PHALANX)

    -- Phalanx が false→true に変わった = 詠唱完了 → RC開始を記録
    if curr_ph and not ph_prev_active then
        ph_recast_track.cast_time = imgui.GetTime()
    end
    ph_prev_active = curr_ph

    local missing = 0
    if not curr_ph                  then missing = missing + 1 end
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

    -- リキャスト記号
    local rc_ready  = (ph_recast <= 0)
    local rc_symbol = rc_ready and '[O]' or '[X]'
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
            imgui.Text('* PHALANX ON *')
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
            imgui.Text('!! PHALANX OFF !!')
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
    imgui.Text(string.format('  Time: %-6s', remain_str))
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
        local has_ph    = has_buff(BUFF_PHALANX)
        local ph_remain = get_buff_remaining(BUFF_PHALANX)
        local ph_recast = get_phalanx_rc_remain()
        draw_phalanx_panel(has_ph, ph_remain, ph_recast)

        -- 区切り線
        imgui.Separator()

        -- Sentinel / Reprisal / Crusade（小さめ、リキャスト時間なし）
        imgui.SetWindowFontScale(0.9)
        for _, def in ipairs(ABILITY_DEFS) do
            draw_buff_row(has_buff(def.buff_id), def.name, 0)
        end
        imgui.SetWindowFontScale(1.0)
    end
    imgui.End()
end)

-- ============================================================
-- zone_change - エリアチェンジ時はバフ監視をリセット
-- ============================================================
ashita.events.register('zone_change', 'battleassist_zone_change', function()
    buff_watch_ready          = false
    prev_missing_count        = 0
    ph_prev_active            = false
    ph_recast_track.cast_time = -1  -- エリアチェンジでRC履歴をリセット
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
        -- ability recast slots
        print('[BattleAssist] === ABILITY RECAST SLOTS ===')
        local ok = pcall(function()
            local recast = AshitaCore:GetMemoryManager():GetRecast()
            if recast == nil then print('[BattleAssist]  GetRecast() = nil') return end
            for i = 0, 31 do
                local call  = recast:GetAbilityCallByIndex(i)
                local timer = recast:GetAbilityTimerByIndex(i)
                if call ~= nil and call > 0 then
                    print(string.format('[BattleAssist]  slot=%d  call_id=%d  timer=%s',
                        i, call, tostring(timer)))
                end
            end
        end)
        if not ok then print('[BattleAssist]  ERROR in ability recast') end

        -- spell recast slots (active only)
        print('[BattleAssist] === SPELL RECAST (active only) ===')
        local ok2 = pcall(function()
            local recast = AshitaCore:GetMemoryManager():GetRecast()
            if recast == nil then return end
            for i = 0, 1023 do
                local timer = recast:GetSpellTimerByIndex(i)
                if timer ~= nil and timer > 0 then
                    print(string.format('[BattleAssist]  spell_id=%d  timer=%d (approx %ds)',
                        i, timer, math.ceil(timer / 4)))
                end
            end
        end)
        if not ok2 then print('[BattleAssist]  ERROR in spell recast') end

        -- GetStatusIcons / GetStatusTimers test
        print('[BattleAssist] === STATUS ICONS / TIMERS TEST ===')
        local okST = pcall(function()
            local player = AshitaCore:GetMemoryManager():GetPlayer()
            if player == nil then print('[BattleAssist]  player nil') return end
            local icons  = player:GetStatusIcons()
            local timers = player:GetStatusTimers()
            if icons == nil then
                print('[BattleAssist]  GetStatusIcons() = nil')
                return
            end
            if timers == nil then
                print('[BattleAssist]  GetStatusTimers() = nil')
                return
            end
            print(string.format('[BattleAssist]  icons count=%d  timers count=%d', #icons, #timers))
            local utc = os.time()
            print(string.format('[BattleAssist]  os.time()=%d  VANA_EPOCH=%d  offset=%d', utc, VANA_EPOCH, utc - VANA_EPOCH))
            for i = 1, #icons do
                local id = icons[i]
                if id ~= nil and id > 0 and id ~= 255 and id ~= 0xFFFF then
                    local raw = timers[i]
                    local secs = calc_remain_secs(raw)
                    print(string.format('[BattleAssist]    slot=%d  id=%d  raw=%s  remain=%ds',
                        i, id, tostring(raw), secs))
                end
            end
        end)
        if not okST then print('[BattleAssist]  ERROR - GetStatusIcons/GetStatusTimers failed') end
        print('[BattleAssist] === END TEST ===')

        e.blocked = true

    elseif args[2] == 'rc' then
        local secs = tonumber(args[3])
        if secs and secs > 0 then
            cfg.phalanx_recast = secs
            settings.save()
            print(string.format('[BattleAssist] Phalanx recast set to %ds', secs))
        else
            print(string.format('[BattleAssist] Current Phalanx recast: %ds  (usage: /ba rc <seconds>)', cfg.phalanx_recast))
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
    print('[BattleAssist] v4.2 loaded.')
    print('[BattleAssist] Phalanx spell_id=36 (tentative). Run /ba debug to verify.')
end)

ashita.events.register('unload', 'battleassist_unload', function()
    settings.save()
    print('[BattleAssist] unloaded.')
end)

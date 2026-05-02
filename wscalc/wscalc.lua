--[[
    Addon: wscalc
    Description: WSダメージ計算ツール（WSCalc + PetCalc）
    Author: 7xxxk
    Version: 3.0.0
]]

addon.name    = 'wscalc'
addon.author  = '7xxxk'
addon.version = '3.0.0'
addon.desc    = 'WS / Pet Damage Calculator'

require('common')
local imgui   = require('imgui')
local settings = require('settings')
local ws_db   = require('ws_data')
local pet_db  = require('pet_data')

-- =============================================================================
-- 設定
-- =============================================================================
local default_settings = {
    auto_sync   = true,
    selected_ws = 0,
    current_tp  = 1000,
    weapon_dmg  = 200,
    enemy_vit   = 130,
    enemy_def   = 900,
    bonus_pct   = 0,
    stats = {
        STR = 100, DEX = 100, VIT = 100, AGI = 100,
        INT = 100, MND = 100, CHR = 100, ATT = 1000
    },
    pet = {
        job_idx    = 0,
        ws_idx     = 0,
        preset_idx = 0,
        atk_bonus  = 0,
        str_bonus  = 0,
        int_bonus  = 0,
        enemy_def  = 900,
        enemy_mdef = 50,
        current_tp = 1000,
    }
}

local saved = settings.load(default_settings)

-- ImGui バインド用テーブル（全てシングル要素配列）
local ui = {
    show     = { true },
    auto_sync = { saved.auto_sync },
    sel_ws   = { saved.selected_ws },
    tp       = { saved.current_tp },
    wdmg     = { saved.weapon_dmg },
    evit     = { saved.enemy_vit },
    edef     = { saved.enemy_def },
    bonus    = { saved.bonus_pct },
    stats = {
        STR = { saved.stats.STR }, DEX = { saved.stats.DEX },
        VIT = { saved.stats.VIT }, AGI = { saved.stats.AGI },
        INT = { saved.stats.INT }, MND = { saved.stats.MND },
        CHR = { saved.stats.CHR }, ATT = { saved.stats.ATT },
    },
    -- Spirits Within 用 HP 入力
    sw_hp_cur = { 1000 },
    sw_hp_max = { 3000 },
    -- Atonement 用ヘイスト入力
    aton_enmity = { 0 },
    -- Pet タブ
    pet = {
        job_idx    = { saved.pet.job_idx },
        ws_idx     = { saved.pet.ws_idx },
        preset_idx = { saved.pet.preset_idx },
        atk_bonus  = { saved.pet.atk_bonus },
        str_bonus  = { saved.pet.str_bonus },
        int_bonus  = { saved.pet.int_bonus },
        enemy_def  = { saved.pet.enemy_def },
        enemy_mdef = { saved.pet.enemy_mdef },
        current_tp = { saved.pet.current_tp },
    }
}

local function save_settings()
    saved.auto_sync   = ui.auto_sync[1]
    saved.selected_ws = ui.sel_ws[1]
    saved.current_tp  = ui.tp[1]
    saved.weapon_dmg  = ui.wdmg[1]
    saved.enemy_vit   = ui.evit[1]
    saved.enemy_def   = ui.edef[1]
    saved.bonus_pct   = ui.bonus[1]
    for k in pairs(ui.stats) do saved.stats[k] = ui.stats[k][1] end
    for k in pairs(ui.pet) do saved.pet[k] = ui.pet[k][1] end
    settings.save()
end

-- =============================================================================
-- 計算エンジン
-- =============================================================================

-- fTP 線形補間
local function calc_ftp(ws, tp)
    local t = ws.ftp
    if tp <= 1000 then return t[1] end
    if tp >= 3000 then return t[3] end
    if tp < 2000 then
        return t[1] + (t[2] - t[1]) * (tp - 1000) / 1000.0
    else
        return t[2] + (t[3] - t[2]) * (tp - 2000) / 1000.0
    end
end

-- fSTR（ランクキャップあり）
local function calc_fstr(pstr, evit, ws)
    local rank   = ws.weapon_rank or 4
    local offset = math.floor(rank / 2)
    local raw    = math.floor((pstr - evit) / 4 + offset)
    local cap    = ws_db.weapon_rank_caps[rank]
    return math.max(cap.min, math.min(cap.max, raw))
end

-- WSC（stat 補正合計）
local function calc_wsc(ws)
    local wsc = 0
    if ws.stat1 and ws.val1 > 0 then
        wsc = wsc + ui.stats[ws.stat1][1] * (ws.val1 / 100.0)
    end
    if ws.stat2 then
        wsc = wsc + ui.stats[ws.stat2][1] * (ws.val2 / 100.0)
    end
    return math.floor(wsc)
end

-- pDIF（攻防比 min/mid/max）
local function calc_pdif(patk, edef)
    local r = patk / edef
    return {
        min = math.max(0.0, math.min(3.0, r * 0.875)),
        mid = math.max(0.0, math.min(3.0, r)),
        max = math.max(0.0, math.min(3.0, r * 1.125)),
    }
end

-- WS ダメージ計算（結果テーブルを返す）
local function calc_ws_damage()
    local ws = ws_db.ws_list[ui.sel_ws[1] + 1]
    if not ws then return nil end

    -- Spirits Within: HP 基準の特殊計算
    if ws.spirits_within then
        local hp_ratio = ui.sw_hp_cur[1] / math.max(1, ui.sw_hp_max[1])
        local ftp_val  = calc_ftp(ws, ui.tp[1])
        local dmg      = math.floor(ui.sw_hp_cur[1] * ftp_val)
        return {
            special   = true,
            label     = "Spirits Within",
            total_mid = dmg, total_min = dmg, total_max = dmg,
            hits = 1, ftp = ftp_val, fstr = 0, wsc = 0, base = 0,
            pdif_mid = 1.0,
            note = string.format("HP %.0f%%", hp_ratio * 100),
        }
    end

    -- Atonement: ヘイスト基準の特殊計算（簡易）
    if ws.atonement then
        local ftp_val = calc_ftp(ws, ui.tp[1])
        local dmg     = math.floor(ui.aton_enmity[1] * ftp_val)
        return {
            special   = true,
            label     = "Atonement",
            total_mid = dmg, total_min = dmg, total_max = dmg,
            hits = 1, ftp = ftp_val, fstr = 0, wsc = 0, base = 0,
            pdif_mid = 1.0,
            note = string.format("Enmity: %d", ui.aton_enmity[1]),
        }
    end

    -- 魔法 WS: pDIF なし（物理計算と分離、現状は簡易扱い）
    if ws.damage_type == "magical" then
        local ftp_val = calc_ftp(ws, ui.tp[1])
        local wsc     = calc_wsc(ws)
        local dmg     = math.floor((ui.wdmg[1] + wsc) * ftp_val)
        return {
            special   = true,
            label     = ws.name,
            total_mid = dmg, total_min = dmg, total_max = dmg,
            hits = ws.hits, ftp = ftp_val, fstr = 0, wsc = wsc,
            base = ui.wdmg[1] + wsc,
            pdif_mid = 1.0,
            note = "Magical WS (pDIF n/a)",
        }
    end

    -- 通常物理 WS
    local fstr  = calc_fstr(ui.stats.STR[1], ui.evit[1], ws)
    local wsc   = calc_wsc(ws)
    local ftp_v = calc_ftp(ws, ui.tp[1])
    local base  = ui.wdmg[1] + fstr + wsc
    local pdif  = calc_pdif(ui.stats.ATT[1], ui.edef[1])
    local bonus = 1.0 + (ui.bonus[1] / 100.0)

    local function hit(p) return math.floor(math.floor(base * ftp_v) * p * bonus) end
    return {
        special     = false,
        fstr        = fstr, wsc = wsc, ftp = ftp_v, base = base,
        pdif_mid    = pdif.mid,
        hits        = ws.hits,
        per_hit_min = hit(pdif.min),
        per_hit_mid = hit(pdif.mid),
        per_hit_max = hit(pdif.max),
        total_min   = hit(pdif.min) * ws.hits,
        total_mid   = hit(pdif.mid) * ws.hits,
        total_max   = hit(pdif.max) * ws.hits,
    }
end

-- Pet ダメージ計算
local function calc_pet_damage()
    local job_data = pet_db.jobs[ui.pet.job_idx[1] + 1]
    if not job_data then return nil end

    local pet_list = pet_db.get_pets(job_data.job)
    local pet      = pet_list[ui.pet.ws_idx[1] + 1]
    if not pet then return nil end

    local preset_list = pet_db.get_presets(job_data.job, pet.pet_name)
    local preset      = preset_list[ui.pet.preset_idx[1] + 1]
    if not preset then return nil end

    local ws = pet.ws
    if not ws then return nil end

    local ftp_v  = calc_ftp(ws, ui.pet.current_tp[1])
    local bonus  = 1.0 + (ui.bonus[1] / 100.0)

    if ws.damage_type == "magical" then
        -- 魔法: MAB / MND / INT ベースの簡易計算
        local int_total = preset.INT + ui.pet.int_bonus[1]
        local mab_bonus = 1.0
        local wsc  = math.floor(int_total * (ws.wsc_pct or 0))
        local base = (ws.base_power or 100) + wsc
        local dmg  = math.floor(base * ftp_v * mab_bonus * bonus)
        return {
            special = true, label = ws.name, note = "Magical",
            total_min = dmg, total_mid = dmg, total_max = dmg,
            hits = ws.hits, ftp = ftp_v, wsc = wsc, base = base, pdif_mid = 1.0,
        }
    else
        -- 物理
        local atk_total = preset.ATK + ui.pet.atk_bonus[1]
        local str_total = preset.STR + ui.pet.str_bonus[1]
        local fstr_raw  = math.floor((str_total - 80) / 4)
        local wsc       = math.floor(str_total * (ws.wsc_pct or 0))
        local base      = (ws.base_power or 50) + fstr_raw + wsc
        local pdif      = calc_pdif(atk_total, ui.pet.enemy_def[1])
        local function hit(p) return math.floor(math.floor(base * ftp_v) * p * bonus) end
        return {
            special     = false,
            fstr = fstr_raw, wsc = wsc, ftp = ftp_v, base = base, pdif_mid = pdif.mid,
            hits        = ws.hits,
            per_hit_min = hit(pdif.min),
            per_hit_mid = hit(pdif.mid),
            per_hit_max = hit(pdif.max),
            total_min   = hit(pdif.min) * ws.hits,
            total_mid   = hit(pdif.mid) * ws.hits,
            total_max   = hit(pdif.max) * ws.hits,
        }
    end
end

-- =============================================================================
-- ImGui 共通ヘルパ
-- =============================================================================

local COL_GOLD   = { 1.0, 0.85, 0.0, 1.0 }
local COL_CYAN   = { 0.0, 1.0,  1.0, 1.0 }
local COL_ORANGE = { 1.0, 0.5,  0.5, 1.0 }
local COL_DIM    = { 0.6, 0.6,  0.6, 1.0 }
local COL_GREEN  = { 0.3, 1.0,  0.4, 1.0 }

-- 結果パネル（WS / Pet 共用）
local function draw_result_panel(res)
    imgui.Separator()
    imgui.TextColored(COL_CYAN, "--- Results ---")

    if not res then
        imgui.TextDisabled("  (WS not selected)")
        return
    end

    -- デバッグ行
    if not res.special then
        imgui.TextDisabled(string.format(
            "  fSTR: %d   WSC: %d   Base: %d   fTP: %.2f   pDIF: %.2f",
            res.fstr, res.wsc, res.base, res.ftp, res.pdif_mid))
    else
        imgui.TextDisabled(string.format("  %s  |  fTP: %.2f  %s",
            res.label or "", res.ftp, res.note or ""))
    end

    imgui.Spacing()

    -- 多段: Per hit 行
    if res.hits > 1 and not res.special then
        imgui.TextColored(COL_DIM, string.format(
            "  Per hit :  %d  /  %d  /  %d",
            res.per_hit_min, res.per_hit_mid, res.per_hit_max))
    end

    -- Total（金色・大字）
    imgui.SetWindowFontScale(1.2)
    imgui.TextColored(COL_GOLD, string.format(
        "  Total   :  %d  /  %d  /  %d",
        res.total_min, res.total_mid, res.total_max))
    imgui.SetWindowFontScale(1.0)

    imgui.TextDisabled("             (min   /  mid   /  max)")
end

-- =============================================================================
-- WS Calc タブ描画
-- =============================================================================
local function draw_wscalc_tab()
    imgui.TextColored(COL_ORANGE, "--- 1. Weapon Skill ---")
    imgui.SetNextItemWidth(-1)
    imgui.Combo("##ws_sel", ui.sel_ws, ws_db.ws_names, #ws_db.ws_names)

    local ws = ws_db.ws_list[ui.sel_ws[1] + 1]
    if ws then
        local info = string.format("  %s  |  %d hit(s)  |  %s",
            ws.skill_type, ws.hits, ws.damage_type)
        if ws.stat1 and ws.val1 > 0 then
            info = info .. string.format("  |  WSC: %s %d%%", ws.stat1, ws.val1)
        end
        if ws.stat2 then
            info = info .. string.format(" + %s %d%%", ws.stat2, ws.val2)
        end
        imgui.TextDisabled(info)
    end

    imgui.Spacing()

    -- ---- Player Stats ----
    imgui.TextColored(COL_ORANGE, "--- 2. Player Conditions ---")
    imgui.Checkbox("Auto Sync Stats (packet 0x061)", ui.auto_sync)

    imgui.SliderInt("Current TP##tp", ui.tp, 1000, 3000)
    imgui.SetNextItemWidth(140)
    imgui.InputInt("Weapon D##wdmg", ui.wdmg)

    if imgui.CollapsingHeader("Manual Stat Edit##stathead") then
        imgui.BeginDisabled(ui.auto_sync[1])

        -- 1行3列で並べる
        imgui.SetNextItemWidth(100); imgui.InputInt("STR##str", ui.stats.STR)
        imgui.SameLine()
        imgui.SetNextItemWidth(100); imgui.InputInt("DEX##dex", ui.stats.DEX)
        imgui.SameLine()
        imgui.SetNextItemWidth(100); imgui.InputInt("VIT##vit", ui.stats.VIT)

        imgui.SetNextItemWidth(100); imgui.InputInt("AGI##agi", ui.stats.AGI)
        imgui.SameLine()
        imgui.SetNextItemWidth(100); imgui.InputInt("INT##int", ui.stats.INT)
        imgui.SameLine()
        imgui.SetNextItemWidth(100); imgui.InputInt("MND##mnd", ui.stats.MND)

        imgui.SetNextItemWidth(100); imgui.InputInt("CHR##chr", ui.stats.CHR)
        imgui.SameLine()
        imgui.SetNextItemWidth(140); imgui.InputInt("Attack##att", ui.stats.ATT)

        imgui.EndDisabled()
    end

    imgui.Spacing()
    imgui.TextColored(COL_ORANGE, "--- 3. Enemy Stats ---")
    imgui.SetNextItemWidth(160); imgui.SliderInt("Enemy VIT##evit", ui.evit, 1, 500)
    imgui.SameLine()
    imgui.SetNextItemWidth(160); imgui.SliderInt("Enemy DEF##edef", ui.edef, 1, 3000)

    imgui.Spacing()
    imgui.TextColored(COL_ORANGE, "--- 4. Bonus ---")
    imgui.SetNextItemWidth(160); imgui.SliderInt("WS Dmg +%%##bonus", ui.bonus, 0, 100)

    -- Spirits Within 用 HP 入力
    if ws and ws.spirits_within then
        imgui.Spacing()
        imgui.TextColored(COL_DIM, "  Spirits Within: HP input")
        imgui.SetNextItemWidth(120); imgui.InputInt("Current HP##swhp", ui.sw_hp_cur)
        imgui.SameLine()
        imgui.SetNextItemWidth(120); imgui.InputInt("Max HP##swmhp", ui.sw_hp_max)
    end

    -- Atonement 用ヘイスト入力
    if ws and ws.atonement then
        imgui.Spacing()
        imgui.TextColored(COL_DIM, "  Atonement: Enmity input")
        imgui.SetNextItemWidth(160); imgui.SliderInt("Enmity (CE+VE)##aton", ui.aton_enmity, 0, 10000)
    end

    -- 結果
    local res = calc_ws_damage()
    draw_result_panel(res)

    imgui.Spacing()
    if imgui.Button("Save Settings##wssave") then
        save_settings()
        print('[wscalc] settings saved.')
    end
end

-- =============================================================================
-- Pet タブ描画
-- =============================================================================
local function draw_pet_tab()
    imgui.TextColored(COL_ORANGE, "--- 1. Job / Pet / Skill ---")

    -- ジョブ選択
    local job_names = pet_db.get_job_names()
    imgui.SetNextItemWidth(100)
    if imgui.Combo("Job##petjob", ui.pet.job_idx, job_names, #job_names) then
        ui.pet.ws_idx[1]     = 0
        ui.pet.preset_idx[1] = 0
    end

    local job_data = pet_db.jobs[ui.pet.job_idx[1] + 1]
    if not job_data then return end

    -- ペット/技選択
    local pet_list = pet_db.get_pets(job_data.job)
    local pet_ws_names = {}
    for _, p in ipairs(pet_list) do
        table.insert(pet_ws_names, p.display_name)
    end
    imgui.SetNextItemWidth(200)
    if imgui.Combo("Pet / Skill##petws", ui.pet.ws_idx, pet_ws_names, #pet_ws_names) then
        ui.pet.preset_idx[1] = 0
    end

    local pet = pet_list[ui.pet.ws_idx[1] + 1]
    if not pet then return end

    -- プリセット選択
    local preset_list  = pet_db.get_presets(job_data.job, pet.pet_name)
    local preset_names = {}
    for _, p in ipairs(preset_list) do table.insert(preset_names, p.name) end
    imgui.SetNextItemWidth(200)
    imgui.Combo("Preset##petpre", ui.pet.preset_idx, preset_names, #preset_names)

    imgui.Spacing()
    imgui.TextColored(COL_ORANGE, "--- 2. Manual Bonus ---")
    imgui.SetNextItemWidth(120); imgui.InputInt("Pet ATK+##patk",  ui.pet.atk_bonus)
    imgui.SameLine()
    imgui.SetNextItemWidth(120); imgui.InputInt("Pet STR+##pstr",  ui.pet.str_bonus)
    imgui.SameLine()
    imgui.SetNextItemWidth(120); imgui.InputInt("Pet INT+##pint",  ui.pet.int_bonus)

    imgui.Spacing()
    imgui.TextColored(COL_ORANGE, "--- 3. Enemy ---")
    imgui.SetNextItemWidth(160); imgui.SliderInt("Enemy DEF##pedef",  ui.pet.enemy_def,  1, 3000)
    imgui.SameLine()
    imgui.SetNextItemWidth(160); imgui.SliderInt("Enemy MDEF##pemdef", ui.pet.enemy_mdef, 1, 500)

    imgui.Spacing()
    imgui.SetNextItemWidth(160); imgui.SliderInt("TP##pettp", ui.pet.current_tp, 1000, 3000)

    -- 結果
    local res = calc_pet_damage()
    draw_result_panel(res)

    imgui.Spacing()
    if imgui.Button("Save Settings##petsave") then
        save_settings()
        print('[wscalc] settings saved.')
    end
end

-- =============================================================================
-- イベント: パケット 0x061 Auto-Sync
-- =============================================================================
ashita.events.register('packet_in', 'wscalc_packet_in', function(e)
    if e.id ~= 0x061 then return end
    if not ui.auto_sync[1] then return end

    -- base + bonus を合算して実効値を取得
    local function get_stat(base_off, bonus_off)
        local ok1, base  = pcall(struct.unpack, 'H', e.data, base_off + 1)
        local ok2, bonus = pcall(struct.unpack, 'h', e.data, bonus_off + 1)
        if ok1 and ok2 then return base + bonus end
        return nil
    end

    local function set(key, val)
        if val and val > 0 then ui.stats[key][1] = val end
    end

    set('STR', get_stat(0x28, 0x36))
    set('DEX', get_stat(0x2A, 0x38))
    set('VIT', get_stat(0x2C, 0x3A))
    set('AGI', get_stat(0x2E, 0x3C))
    set('INT', get_stat(0x30, 0x3E))
    set('MND', get_stat(0x32, 0x40))
    set('CHR', get_stat(0x34, 0x42))

    local ok, att = pcall(struct.unpack, 'H', e.data, 0x58 + 1)
    if ok and att and att > 0 then ui.stats.ATT[1] = att end
end)

-- =============================================================================
-- イベント: コマンド
-- =============================================================================
ashita.events.register('command', 'wscalc_command', function(e)
    local args = e.command:args()
    if args[1] ~= '/wscalc' then return end
    e.blocked = true

    if args[2] == 'debug' then
        -- パケット 0x061 の最初の 128 バイトをコンソールに表示
        print('[wscalc] Debug mode: equip something to trigger 0x061 packet dump.')
        return
    end

    ui.show[1] = not ui.show[1]
end)

-- =============================================================================
-- イベント: フレーム描画
-- =============================================================================
ashita.events.register('d3d_present', 'wscalc_present', function()
    if not ui.show[1] then return end

    imgui.SetNextWindowSize({ 460, 580 }, ImGuiCond_FirstUseEver)

    if imgui.Begin('WS Calc v3##wscalc_main', ui.show, ImGuiWindowFlags_None) then

        if imgui.BeginTabBar('##wscalc_tabs') then

            if imgui.BeginTabItem('WS Calc##tab_ws') then
                draw_wscalc_tab()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('Pet##tab_pet') then
                draw_pet_tab()
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    end
    imgui.End()
end)

-- =============================================================================
-- イベント: ロード / アンロード
-- =============================================================================
ashita.events.register('load', 'wscalc_load', function()
    print(string.format('[wscalc] v%s loaded. /wscalc to toggle.', addon.version))
end)

ashita.events.register('unload', 'wscalc_unload', function()
    save_settings()
    print('[wscalc] unloaded.')
end)

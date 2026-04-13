-- ============================================================
-- MacroSwitcher.lua
-- Ashita v4 アドオン - ジョブチェンジ時マクロ自動切り替えツール
-- 機能: メイン/サポジョブ検知 + マクロブック/セット自動変更
-- ============================================================

addon.name    = 'MacroSwitcher'
addon.author  = '7xxxk'
addon.version = '1.2.1'
addon.desc    = 'Auto macro book/set switcher on job change'

require('common')
local settings = require('settings')
local imgui    = require('imgui')

-- ============================================================
-- ジョブ名テーブル (ID 1-22) ※ImGui 表示用は英語のみ
-- ============================================================
local jobs = {
    [1]  = 'Warrior (WAR)',    [2]  = 'Monk (MNK)',        [3]  = 'White Mage (WHM)',
    [4]  = 'Black Mage (BLM)', [5]  = 'Red Mage (RDM)',    [6]  = 'Thief (THF)',
    [7]  = 'Paladin (PLD)',    [8]  = 'Dark Knight (DRK)', [9]  = 'Beastmaster (BST)',
    [10] = 'Bard (BRD)',       [11] = 'Ranger (RNG)',      [12] = 'Samurai (SAM)',
    [13] = 'Ninja (NIN)',      [14] = 'Dragoon (DRG)',     [15] = 'Summoner (SMN)',
    [16] = 'Blue Mage (BLU)', [17] = 'Corsair (COR)',     [18] = 'Puppetmaster (PUP)',
    [19] = 'Dancer (DNC)',    [20] = 'Scholar (SCH)',      [21] = 'Geomancer (GEO)',
    [22] = 'Rune Fencer (RUN)',
}

-- imgui.Combo 用ジョブ名リスト（1始まりインデックス）
local job_names_list = {}
for i = 1, 22 do
    job_names_list[i] = jobs[i]
end

-- ============================================================
-- 設定デフォルト値
-- ============================================================
local default_settings = T{
    ui      = T{ open = T{ false } },
    configs = T{},
}
for i = 1, 22 do
    default_settings.configs[i] = T{
        book        = 1,
        set         = 1,
        enabled     = false,
        sub_configs = T{},  -- [サポジョブID] = T{ book, set, enabled }
    }
end

local macro_settings = nil

-- 設定変更コールバック（/addon reload 等の外部リロード時に再同期）
settings.register('settings', 'macroswitcher_settings_update', function(new_cfg)
    macro_settings = new_cfg
end)

-- ============================================================
-- 監視用状態変数
-- ============================================================
local last_main      = -1
local last_sub       = -1
local is_initialized = false

-- サポジョブ追加UI用の一時選択状態（セッション内のみ・保存不要）
local add_sub_sel = {}
for i = 1, 22 do
    add_sub_sel[i] = { 0 }
end

-- ============================================================
-- ヘルパー関数
-- ============================================================

local function apply_macro(book, set)
    AshitaCore:GetChatManager():QueueCommand(-1, string.format('/macro book %d', book))
    AshitaCore:GetChatManager():QueueCommand(-1, string.format('/macro set %d', set))
end

local function get_effective_config(main_id, sub_id)
    local main_cfg = macro_settings.configs[main_id]
    if main_cfg == nil then return nil end
    if sub_id and sub_id > 0 and main_cfg.sub_configs then
        local sub_cfg = main_cfg.sub_configs[sub_id]
        if sub_cfg and sub_cfg.enabled then
            return sub_cfg
        end
    end
    return main_cfg
end

-- force=true の場合は enabled 状態に関わらず強制実行
local function apply_current_job(force)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then
        AshitaCore:GetChatManager():QueueCommand(-1, '/echo [MacroSwitcher] Cannot get player info.')
        return
    end

    local main_id = player:GetMainJob()
    local sub_id  = player:GetSubJob()
    if main_id == 0 then
        AshitaCore:GetChatManager():QueueCommand(-1, '/echo [MacroSwitcher] Job info not available.')
        return
    end

    local effective = get_effective_config(main_id, sub_id)
    local job_name  = jobs[main_id] or ('JobID:' .. main_id)

    if effective and (force or effective.enabled) then
        apply_macro(effective.book, effective.set)
        AshitaCore:GetChatManager():QueueCommand(-1,
            string.format('/echo [MacroSwitcher] %s -> Book:%d Set:%d applied.', job_name, effective.book, effective.set))
    else
        AshitaCore:GetChatManager():QueueCommand(-1,
            string.format('/echo [MacroSwitcher] %s : disabled (enable in UI).', job_name))
    end
end

-- ============================================================
-- イベント: アドオン読み込み / 終了
-- ============================================================
ashita.events.register('load', 'macroswitcher_load', function()
    macro_settings = settings.load(default_settings)
    print('[MacroSwitcher] v' .. addon.version .. ' loaded.')
end)

ashita.events.register('unload', 'macroswitcher_unload', function()
    settings.save()
    print('[MacroSwitcher] unloaded.')
end)

-- ============================================================
-- イベント: コマンド処理
--   /ms             → UI表示/非表示トグル
--   /ms apply       → 現在ジョブの設定を即時適用（force=true）
--   /macroswitcher  → 上記と同様
-- ============================================================
ashita.events.register('command', 'macroswitcher_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    if args[1] ~= '/ms' and args[1] ~= '/macroswitcher' then return end

    e.blocked = true

    if #args >= 2 and args[2] == 'apply' then
        apply_current_job(true)
    else
        macro_settings.ui.open[1] = not macro_settings.ui.open[1]
    end
end)

-- ============================================================
-- イベント: 毎フレーム描画（ジョブ監視 + ImGui UI描画）
-- ============================================================
ashita.events.register('d3d_present', 'macroswitcher_present', function()

    -- ジョブ監視
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player ~= nil then
        local current_main = player:GetMainJob()
        local current_sub  = player:GetSubJob()

        if not is_initialized and current_main ~= 0 then
            last_main      = current_main
            last_sub       = current_sub
            is_initialized = true
        end

        if is_initialized and current_main ~= 0 then
            if current_main ~= last_main or current_sub ~= last_sub then
                local effective = get_effective_config(current_main, current_sub)
                if effective and effective.enabled then
                    apply_macro(effective.book, effective.set)
                end
                last_main = current_main
                last_sub  = current_sub
            end
        end
    end

    -- ImGui UI描画
    if not macro_settings.ui.open[1] then return end

    imgui.SetNextWindowSize({ 380, 490 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('MacroSwitcher##ms_main', macro_settings.ui.open) then

        imgui.Text('Auto Macro Book/Set on Job Change')
        imgui.TextDisabled('/ms apply: force apply  |  /ms: toggle UI')
        imgui.Separator()

        if imgui.BeginChild('ms_job_scroll', { 0, -65 }, true) then

            for main_id = 1, 22 do
                local main_name = jobs[main_id]
                local main_cfg  = macro_settings.configs[main_id]

                if imgui.TreeNode(main_name .. '##ms_job_' .. main_id) then
                    local changed = false

                    -- メインジョブ設定
                    local enabled = { main_cfg.enabled }
                    if imgui.Checkbox('Enable auto-switch##ms_en_' .. main_id, enabled) then
                        main_cfg.enabled = enabled[1]; changed = true
                    end

                    local book = { main_cfg.book }
                    if imgui.SliderInt('Book##ms_bk_' .. main_id, book, 1, 20) then
                        main_cfg.book = book[1]; changed = true
                    end

                    local set = { main_cfg.set }
                    if imgui.SliderInt('Set##ms_st_' .. main_id, set, 1, 10) then
                        main_cfg.set = set[1]; changed = true
                    end

                    -- サポジョブ個別設定
                    imgui.Spacing()
                    imgui.TextDisabled('  Sub-job overrides (takes priority over main when enabled)')
                    imgui.Separator()

                    if main_cfg.sub_configs then
                        local delete_sub_id = nil

                        for sub_id, sub_cfg in pairs(main_cfg.sub_configs) do
                            local sub_name = jobs[sub_id] or ('SubID:' .. sub_id)
                            local node_id  = main_id .. '_' .. sub_id

                            if imgui.TreeNode(sub_name .. '##ms_sub_' .. node_id) then
                                local s_en = { sub_cfg.enabled }
                                if imgui.Checkbox('Enable for this sub-job##ms_sen_' .. node_id, s_en) then
                                    sub_cfg.enabled = s_en[1]; changed = true
                                end

                                local s_bk = { sub_cfg.book }
                                if imgui.SliderInt('Book##ms_sbk_' .. node_id, s_bk, 1, 20) then
                                    sub_cfg.book = s_bk[1]; changed = true
                                end

                                local s_st = { sub_cfg.set }
                                if imgui.SliderInt('Set##ms_sst_' .. node_id, s_st, 1, 10) then
                                    sub_cfg.set = s_st[1]; changed = true
                                end

                                imgui.Spacing()
                                imgui.PushStyleColor(ImGuiCol_Button,       { 0.65, 0.10, 0.10, 0.70 })
                                imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.80, 0.20, 0.20, 0.90 })
                                if imgui.Button('Delete##ms_del_' .. node_id) then
                                    delete_sub_id = sub_id
                                end
                                imgui.PopStyleColor(2)

                                imgui.TreePop()
                            end
                        end

                        if delete_sub_id ~= nil then
                            main_cfg.sub_configs[delete_sub_id] = nil
                            changed = true
                        end
                    end

                    -- サポジョブ追加
                    imgui.Spacing()
                    imgui.SetNextItemWidth(200)
                    imgui.Combo('##ms_add_combo_' .. main_id, add_sub_sel[main_id], job_names_list, 22)
                    imgui.SameLine()
                    if imgui.SmallButton('+ Add##ms_add_' .. main_id) then
                        local new_sub_id = add_sub_sel[main_id][1] + 1
                        if new_sub_id ~= main_id then
                            if main_cfg.sub_configs[new_sub_id] == nil then
                                main_cfg.sub_configs[new_sub_id] = T{
                                    book    = main_cfg.book,
                                    set     = main_cfg.set,
                                    enabled = false,
                                }
                                changed = true
                            end
                        end
                    end

                    if changed then settings.save() end
                    imgui.TreePop()
                end
            end

            imgui.EndChild()
        end

        -- 下部ボタン
        imgui.Spacing()
        if imgui.Button('Apply Now##ms_apply_now', { -90, 28 }) then
            apply_current_job(true)
        end
        imgui.SameLine()
        if imgui.Button('Close##ms_close', { -1, 28 }) then
            macro_settings.ui.open[1] = false
        end

        imgui.End()
    end
end)

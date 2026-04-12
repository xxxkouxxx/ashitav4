-- ============================================================
-- MacroSwitcher.lua
-- Ashita v4 アドオン - ジョブチェンジ時マクロ自動切り替えツール
-- 機能: メイン/サポジョブ検知 + マクロブック/セット自動変更
-- ============================================================

addon.name    = 'MacroSwitcher'
addon.author  = '7xxxk'
addon.version = '1.2.0'
addon.desc    = 'ジョブチェンジ時にマクロブック/セットを自動切り替えします'

require('common')
local settings = require('settings')
local imgui    = require('imgui')

-- ============================================================
-- ジョブ名テーブル (ID 1-22)
-- ============================================================
local jobs = {
    [1]  = '戦士 (WAR)',      [2]  = 'モンク (MNK)',      [3]  = '白魔道士 (WHM)',
    [4]  = '黒魔道士 (BLM)',   [5]  = '赤魔道士 (RDM)',    [6]  = 'シーフ (THF)',
    [7]  = 'ナイト (PLD)',     [8]  = '暗黒騎士 (DRK)',    [9]  = '獣使い (BST)',
    [10] = '吟遊詩人 (BRD)',   [11] = '狩人 (RNG)',        [12] = '侍 (SAM)',
    [13] = '忍者 (NIN)',       [14] = '竜騎士 (DRG)',      [15] = '召喚士 (SMN)',
    [16] = '青魔道士 (BLU)',   [17] = 'コルセア (COR)',    [18] = 'からくり士 (PUP)',
    [19] = '踊り子 (DNC)',     [20] = '学者 (SCH)',        [21] = '風水士 (GEO)',
    [22] = '魔導剣士 (RUN)',
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
local last_main      = -1   -- 前フレームのメインジョブID
local last_sub       = -1   -- 前フレームのサポジョブID
local is_initialized = false

-- サポジョブ追加UI用の一時選択状態（セッション内のみ・保存不要）
-- add_sub_sel[main_id] = { combo_index }  ※0始まりインデックス
local add_sub_sel = {}
for i = 1, 22 do
    add_sub_sel[i] = { 0 }
end

-- ============================================================
-- ヘルパー関数
-- ============================================================

-- マクロコマンドをチャットマネージャーにキューイング
local function apply_macro(book, set)
    AshitaCore:GetChatManager():QueueCommand(-1, string.format('/macro book %d', book))
    AshitaCore:GetChatManager():QueueCommand(-1, string.format('/macro set %d', set))
end

-- メイン+サポジョブに対応する有効な設定を返す
-- サポジョブ個別設定が enabled=true の場合はそちらを優先し、
-- 未設定またはdisabledの場合はメインジョブ設定にフォールバック
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

-- 現在のジョブ設定を適用する（手動適用ボタン + /ms apply コマンドで共用）
-- force=true の場合は enabled 状態に関わらず強制実行
local function apply_current_job(force)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then
        AshitaCore:GetChatManager():QueueCommand(-1, '/echo [MacroSwitcher] プレイヤー情報を取得できません')
        return
    end

    local main_id = player:GetMainJob()
    local sub_id  = player:GetSubJob()
    if main_id == 0 then
        AshitaCore:GetChatManager():QueueCommand(-1, '/echo [MacroSwitcher] ジョブ情報が未取得です')
        return
    end

    local effective = get_effective_config(main_id, sub_id)
    local job_name  = jobs[main_id] or ('ジョブID:' .. main_id)

    if effective and (force or effective.enabled) then
        apply_macro(effective.book, effective.set)
        AshitaCore:GetChatManager():QueueCommand(-1,
            string.format('/echo [MacroSwitcher] %s → Book:%d Set:%d 適用', job_name, effective.book, effective.set))
    else
        AshitaCore:GetChatManager():QueueCommand(-1,
            string.format('/echo [MacroSwitcher] %s の設定が無効です（UIで有効化してください）', job_name))
    end
end

-- ============================================================
-- イベント: アドオン読み込み
-- ============================================================
ashita.events.register('load', 'macroswitcher_load', function()
    macro_settings = settings.load(default_settings)
    print('[MacroSwitcher] v' .. addon.version .. ' loaded.')
end)

-- ============================================================
-- イベント: アドオン終了
-- ============================================================
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
        -- 強制適用: enabled に関わらず現在ジョブのconfigを実行
        apply_current_job(true)
    else
        -- UIトグル
        macro_settings.ui.open[1] = not macro_settings.ui.open[1]
    end
end)

-- ============================================================
-- イベント: 毎フレーム描画（ジョブ監視 + ImGui UI描画）
-- ============================================================
ashita.events.register('d3d_present', 'macroswitcher_present', function()

    -- ----------------------------------------------------------
    -- ジョブ監視（メモリ監視でジョブIDを取得・比較）
    -- ----------------------------------------------------------
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player ~= nil then
        local current_main = player:GetMainJob()
        local current_sub  = player:GetSubJob()

        -- 初回: ジョブが確定したら現在値を記録（0はデータ未確定）
        if not is_initialized and current_main ~= 0 then
            last_main      = current_main
            last_sub       = current_sub
            is_initialized = true
        end

        -- メインまたはサポジョブの変化を検知して自動適用
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

    -- ----------------------------------------------------------
    -- ImGui UI描画
    -- ----------------------------------------------------------
    if not macro_settings.ui.open[1] then return end

    imgui.SetNextWindowSize({ 380, 490 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('MacroSwitcher 設定##ms_main', macro_settings.ui.open) then

        imgui.Text('ジョブチェンジ時の自動マクロ設定')
        imgui.TextDisabled('/ms apply で即時適用 | /ms でUI開閉')
        imgui.Separator()

        -- ジョブ設定リスト（スクロール可能エリア、下部ボタン分を除く）
        if imgui.BeginChild('ms_job_scroll', { 0, -65 }, true) then

            for main_id = 1, 22 do
                local main_name = jobs[main_id]
                local main_cfg  = macro_settings.configs[main_id]

                if imgui.TreeNode(main_name .. '##ms_job_' .. main_id) then
                    local changed = false

                    -- ---- メインジョブ設定 ----
                    local enabled = { main_cfg.enabled }
                    if imgui.Checkbox('自動切り替えを有効にする##ms_en_' .. main_id, enabled) then
                        main_cfg.enabled = enabled[1]; changed = true
                    end

                    local book = { main_cfg.book }
                    if imgui.SliderInt('ブック番号##ms_bk_' .. main_id, book, 1, 20) then
                        main_cfg.book = book[1]; changed = true
                    end

                    local set = { main_cfg.set }
                    if imgui.SliderInt('セット番号##ms_st_' .. main_id, set, 1, 10) then
                        main_cfg.set = set[1]; changed = true
                    end

                    -- ---- サポジョブ個別設定セクション ----
                    imgui.Spacing()
                    imgui.TextDisabled('  サポジョブ個別設定（有効にするとメイン設定より優先）')
                    imgui.Separator()

                    -- 既存サポジョブ設定の表示・編集・削除
                    if main_cfg.sub_configs then
                        local delete_sub_id = nil  -- ループ後に削除するID

                        for sub_id, sub_cfg in pairs(main_cfg.sub_configs) do
                            local sub_name = jobs[sub_id] or ('サポID:' .. sub_id)
                            local node_id  = main_id .. '_' .. sub_id

                            if imgui.TreeNode(sub_name .. '##ms_sub_' .. node_id) then
                                local s_en = { sub_cfg.enabled }
                                if imgui.Checkbox('このサポジョブ時に優先##ms_sen_' .. node_id, s_en) then
                                    sub_cfg.enabled = s_en[1]; changed = true
                                end

                                local s_bk = { sub_cfg.book }
                                if imgui.SliderInt('ブック番号##ms_sbk_' .. node_id, s_bk, 1, 20) then
                                    sub_cfg.book = s_bk[1]; changed = true
                                end

                                local s_st = { sub_cfg.set }
                                if imgui.SliderInt('セット番号##ms_sst_' .. node_id, s_st, 1, 10) then
                                    sub_cfg.set = s_st[1]; changed = true
                                end

                                -- 削除ボタン（赤系ボタン）
                                imgui.Spacing()
                                imgui.PushStyleColor(ImGuiCol_Button,        { 0.65, 0.10, 0.10, 0.70 })
                                imgui.PushStyleColor(ImGuiCol_ButtonHovered,  { 0.80, 0.20, 0.20, 0.90 })
                                if imgui.Button('この設定を削除##ms_del_' .. node_id) then
                                    delete_sub_id = sub_id  -- ループ外で処理
                                end
                                imgui.PopStyleColor(2)

                                imgui.TreePop()
                            end
                        end

                        -- ループ後に削除を実行（pairs中のnil代入を回避）
                        if delete_sub_id ~= nil then
                            main_cfg.sub_configs[delete_sub_id] = nil
                            changed = true
                        end
                    end

                    -- サポジョブ追加UI（コンボ + 追加ボタン）
                    imgui.Spacing()
                    imgui.SetNextItemWidth(200)
                    imgui.Combo('##ms_add_combo_' .. main_id, add_sub_sel[main_id], job_names_list, 22)
                    imgui.SameLine()
                    if imgui.SmallButton('+ 追加##ms_add_' .. main_id) then
                        local new_sub_id = add_sub_sel[main_id][1] + 1  -- 0始まり→1始まりに変換
                        -- 自分自身はサポジョブになれないので除外
                        if new_sub_id ~= main_id then
                            if main_cfg.sub_configs[new_sub_id] == nil then
                                -- メイン設定値を初期値として引き継ぐ
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

        -- 下部ボタン（今すぐ適用 + 閉じる）
        imgui.Spacing()
        if imgui.Button('今すぐ適用##ms_apply_now', { -90, 28 }) then
            -- UIを閉じずに現在ジョブの設定を強制適用
            apply_current_job(true)
        end
        imgui.SameLine()
        if imgui.Button('閉じる##ms_close', { -1, 28 }) then
            macro_settings.ui.open[1] = false
        end

        imgui.End()
    end
end)

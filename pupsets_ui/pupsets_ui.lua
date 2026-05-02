--[[
* pupsets_ui - からくり師アタッチメントセット切り替え UI
*
* pupsets アドオン（有志作成）の保存済みセットをボタンで切り替える
* 独立した ImGui ウィンドウアドオン。タブで Load / Equip / Manage を切り替え。
* pupsets.lua への変更は一切不要。ボタンクリックで /ps コマンドを発行する。
*
* 使い方:
*   addon load pupsets
*   addon load pupsets_ui
*   /psui          -- ウィンドウ表示/非表示トグル
*   /psui refresh  -- セットファイル一覧を再スキャン
--]]

addon.name    = 'pupsets_ui';
addon.author  = 'xxxkouxxx';
addon.version = '1.3';
addon.desc    = 'ImGui UI for pupsets addon. Requires pupsets to be loaded.';

require('common');
local chat  = require('chat');
local imgui = require('imgui');

-- pup モジュール（pupsets アドオンの pup.lua）。load イベントで初期化。
local pup       = nil;
local headList  = T{};
local frameList = T{};

-- ID → 英語名マッピング（クライアント日本語版の文字化け回避）
local HEAD_EN = {
    [1] = 'Harlequin Head',
    [2] = 'Valoredge Head',
    [3] = 'Sharpshot Head',
    [4] = 'Stormwaker Head',
    [5] = 'Soulsoother Head',
    [6] = 'Spiritreaver Head',
    [7] = 'Maestro Head',
}
local FRAME_EN = {
    [32] = 'Harlequin Frame',
    [33] = 'Valoredge Frame',
    [34] = 'Sharpshot Frame',
    [35] = 'Stormwaker Frame',
    [36] = 'Soulsoother Frame',
    [37] = 'Spiritreaver Frame',
    [38] = 'Ruinator Frame',
    [39] = 'Mayhem Frame',
}

-- UI 状態
local ui = {
    open         = { true },  -- imgui.Begin 用テーブル参照（起動時に表示）
    sets         = T{ },      -- セット名リスト（.txt 除去済み）
    dirty        = true,      -- true のとき次フレームでファイル一覧を再スキャン
    save_buf     = { '' },    -- Manage タブの保存名入力バッファ
};

-- ヘッド・フレーム一覧を構築（ゲームリソースで存在確認 + 英語名ハードコード）
local function buildEquipList()
    headList  = T{};
    frameList = T{};
    for i = 1, 7 do
        local item = AshitaCore:GetResourceManager():GetItemById(0x2000 + i);
        if item ~= nil and item.Name[1] ~= nil and item.Name[1] ~= '.' then
            headList:append({ id=i, name=HEAD_EN[i] or ('Head #' .. i) });
        end
    end
    for i = 32, 39 do
        local item = AshitaCore:GetResourceManager():GetItemById(0x2000 + i);
        if item ~= nil and item.Name[1] ~= nil and item.Name[1] ~= '.' then
            frameList:append({ id=i, name=FRAME_EN[i] or ('Frame #' .. i) });
        end
    end
end

-- config/addons/pupsets/ からセットファイル一覧をスキャン
local function scan_sets()
    local path = ('%s\\config\\addons\\pupsets\\'):fmt(AshitaCore:GetInstallPath());
    local files = ashita.fs.get_dir(path, '.*.txt', true);
    ui.sets = T{ };
    if files ~= nil then
        T(files):each(function(v)
            ui.sets:append(v:gsub('.txt', ''));
        end);
    end
    ui.dirty = false;
end

--[[
* event: load
--]]
ashita.events.register('load', 'pupsets_ui_load', function()
    -- pupsets/pup.lua を require するためにパスを追加
    local pupsets_path = AshitaCore:GetInstallPath() .. 'addons\\pupsets\\';
    package.path = package.path .. ';' .. pupsets_path .. '?.lua';
    local ok, result = pcall(require, 'pup');
    if ok then
        pup = result;
        buildEquipList();
    else
        print(chat.header(addon.name):append(chat.error('Failed to load pup module. Is pupsets loaded?')));
    end
    scan_sets();
end);

--[[
* event: command
* /psui          -- ウィンドウトグル
* /psui refresh  -- ファイル一覧再スキャン
--]]
ashita.events.register('command', 'pupsets_ui_cmd', function(e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/psui')) then return end
    e.blocked = true;

    if (#args >= 2 and args[2]:any('refresh')) then
        scan_sets();
        print(chat.header(addon.name):append(chat.message('Set list refreshed.')));
        return;
    end

    ui.open[1] = not ui.open[1];
end);

--[[
* event: d3d_present  -- ImGui ウィンドウ描画
--]]
ashita.events.register('d3d_present', 'pupsets_ui_render', function()
    if not ui.open[1] then return end

    -- ウィンドウが開いているとき dirty なら再スキャン
    if ui.dirty then scan_sets() end

    imgui.SetNextWindowSize({ 260, 0 }, ImGuiCond_FirstUseEver);
    if imgui.Begin('Pupsets##psui_win', ui.open) then

        if imgui.BeginTabBar('##psui_tabs') then

            -- ── Tab 1: Load ──────────────────────────────────────
            if imgui.BeginTabItem('Load##psui_load') then
                if (#ui.sets == 0) then
                    imgui.TextDisabled('No sets found.');
                    imgui.TextDisabled('(/psui refresh to rescan)');
                else
                    for _, setname in ipairs(ui.sets) do
                        if imgui.Button(setname .. '##psui_' .. setname, { -1, 26 }) then
                            AshitaCore:GetChatManager():QueueCommand(1, '/ps load ' .. setname);
                        end
                    end
                end

                imgui.Separator();
                if imgui.SmallButton('Refresh##psui_refresh') then
                    scan_sets();
                end
                imgui.EndTabItem();
            end

            -- ── Tab 2: Equip ──────────────────────────────────────
            if imgui.BeginTabItem('Equip##psui_equip') then
                if pup == nil then
                    imgui.TextDisabled('pup module not available.');
                    imgui.TextDisabled('Reload with pupsets loaded.');
                else
                    -- 現在のヘッド・フレーム ID を取得（名前比較ではなく ID 比較）
                    local attachments = T{};
                    local ok, result = pcall(pup.get_attachments);
                    if ok then attachments = result; end
                    local curHeadId  = attachments[1] or 0;
                    local curFrameId = attachments[2] or 0;

                    -- 現在の装備名を英語マッピングで表示
                    local curHeadName  = HEAD_EN[curHeadId]  or (curHeadId  > 0 and 'Head #'  .. curHeadId  or '(none)');
                    local curFrameName = FRAME_EN[curFrameId] or (curFrameId > 0 and 'Frame #' .. curFrameId or '(none)');

                    imgui.Text('Head:  ' .. curHeadName);
                    imgui.Text('Frame: ' .. curFrameName);
                    imgui.Separator();

                    -- ヘッド選択ボタン
                    imgui.TextDisabled('-- Head --');
                    for _, h in ipairs(headList) do
                        local isCurrent = (h.id == curHeadId);
                        if isCurrent then
                            imgui.PushStyleColor(ImGuiCol_Button,        { 0.15, 0.55, 0.15, 1.0 });
                            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.25, 0.70, 0.25, 1.0 });
                        end
                        if imgui.Button(h.name .. '##head_' .. h.id, { -1, 24 }) then
                            pup.set_attachment(1, h.id);
                        end
                        if isCurrent then imgui.PopStyleColor(2); end
                    end

                    imgui.Separator();

                    -- フレーム選択ボタン
                    imgui.TextDisabled('-- Frame --');
                    for _, f in ipairs(frameList) do
                        local isCurrent = (f.id == curFrameId);
                        if isCurrent then
                            imgui.PushStyleColor(ImGuiCol_Button,        { 0.15, 0.55, 0.15, 1.0 });
                            imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.25, 0.70, 0.25, 1.0 });
                        end
                        if imgui.Button(f.name .. '##frame_' .. f.id, { -1, 24 }) then
                            pup.set_attachment(2, f.id);
                        end
                        if isCurrent then imgui.PopStyleColor(2); end
                    end
                end
                imgui.EndTabItem();
            end

            -- ── Tab 3: Manage ─────────────────────────────────────
            if imgui.BeginTabItem('Manage##psui_mgr') then
                -- 現在のセットを名前をつけて保存
                imgui.Text('Save current set as:');
                imgui.SetNextItemWidth(-60);
                imgui.InputText('##psui_savename', ui.save_buf, 64);
                imgui.SameLine();
                if imgui.Button('Save##psui_savebtn') and ui.save_buf[1] ~= '' then
                    AshitaCore:GetChatManager():QueueCommand(1, '/ps save ' .. ui.save_buf[1]);
                    ui.save_buf[1] = '';
                    scan_sets();
                end

                imgui.Separator();

                -- セット削除
                imgui.Text('Delete set:');
                if (#ui.sets == 0) then
                    imgui.TextDisabled('No sets found.');
                else
                    for _, setname in ipairs(ui.sets) do
                        imgui.Text(setname);
                        imgui.SameLine(185);
                        if imgui.SmallButton('Del##del_' .. setname) then
                            AshitaCore:GetChatManager():QueueCommand(1, '/ps delete ' .. setname);
                            scan_sets();
                        end
                    end
                end
                imgui.EndTabItem();
            end

            imgui.EndTabBar();
        end

        imgui.End();
    else
        -- ウィンドウを閉じたとき次回オープン時に一覧を更新
        ui.dirty = true;
    end
end);

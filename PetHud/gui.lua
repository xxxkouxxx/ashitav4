-- PetHUD GUI（ドラッグ移動対応・ジョブタブ切り替え・設定メニュー）
local gui = T{};

local gConfig    = require('config');
local imgui      = require('imgui');
local settings   = require('settings');
local chat       = require('chat');
local gFunctions = require('helper');
local genPet     = require('petGeneric');
local pupPet     = require('petPUP');
local charmPet   = require('petBSTCharm');
local jugPet     = require('petBSTJug');
local smnPet     = require('petSMN');
local drgPet     = require('petDRG');
local geoPet     = require('petGEO');

-- ImGuiTabItemFlags_SetSelected = 1（Ashita ImGui 定数）
local TAB_SET_SELECTED = 1;

--------------------------------------------------------------------
-- 設定メニュー
--------------------------------------------------------------------
gui.renderMenu = function()
    imgui.SetNextWindowSize({ 500 }, ImGuiCond_Once);
    if imgui.Begin(string.format('PetHUD v%s Configuration', addon.version),
                   gConfig.params.configMenuOpen,
                   bit.bor(ImGuiWindowFlags_AlwaysAutoResize)) then

        imgui.Text('Display Options');
        imgui.Separator();

        imgui.SliderFloat('Window Scale',   gConfig.params.settings.window.scale,   0.1, 2.0, '%.2f');
        imgui.SliderFloat('Window Opacity', gConfig.params.settings.window.opacity, 0.1, 1.0, '%.2f');
        imgui.ColorEdit4('Text Color',       gConfig.params.settings.window.textColor);
        imgui.ColorEdit4('Border Color',     gConfig.params.settings.window.borderColor);
        imgui.ColorEdit4('Background Color', gConfig.params.settings.window.backgroundColor);

        imgui.Separator();
        imgui.Text('Components');

        imgui.Checkbox('Show pet name / level / distance', gConfig.params.settings.components.petName);
        imgui.Checkbox('Show pet duration',                gConfig.params.settings.components.petDuration);
        imgui.Checkbox('Show recast timers',               gConfig.params.settings.components.petRecasts);
        imgui.Checkbox('Show HP/MP/TP bars',               gConfig.params.settings.components.petStats);
        imgui.Checkbox('Show pet target',                  gConfig.params.settings.components.petTarget);
        imgui.Checkbox('Show stay heal ticks (BST)',       gConfig.params.settings.components.petStayCounter);
        imgui.Checkbox('Show maneuvers (PUP)',             gConfig.params.settings.components.maneuvers);
        imgui.Checkbox('Show overload status (PUP)',       gConfig.params.settings.components.overloadStatus);

        imgui.Separator();
        imgui.Text('Visibility');

        imgui.Checkbox('Hide when map is open',  gConfig.params.settings.components.hideMap);
        imgui.Checkbox('Hide when log is open',  gConfig.params.settings.components.hideLog);
        imgui.Checkbox('Always show window',     gConfig.params.settings.components.alwaysVisible);
        imgui.ShowHelp('Show PetHUD window even when no pet is active.');

        imgui.Separator();
        imgui.Separator();
        if imgui.Button('  Reset to Default  ') then
            settings.reset();
            print(chat.header(addon.name):append(chat.message('Settings reset to default.')));
        end
        imgui.Separator();
    end
    imgui.End();
end

--------------------------------------------------------------------
-- タブ選択フラグ: ペットタイプが変化したフレームだけ SetSelected を立てる
--------------------------------------------------------------------
local lastAutoSelectType = -99;

local function getTabFlags(tabPetType)
    local current = gConfig.params.mobInfo.petType;

    -- ペットタイプが変化したとき → lastAutoSelectType を更新
    if current ~= lastAutoSelectType then
        lastAutoSelectType = current;
    else
        return 0;  -- タイプ変化なし → 強制選択しない（手動切り替え可）
    end

    -- 現在タイプと合致するタブのみ SetSelected
    if current == tabPetType then
        return TAB_SET_SELECTED;
    end
    return 0;
end

--------------------------------------------------------------------
-- メインウィンドウ
--------------------------------------------------------------------
gui.renderMainWindow = function()
    local player = GetPlayerEntity();
    local pet    = (player ~= nil) and GetEntity(player.PetTargetIndex) or nil;

    local scale      = gConfig.params.settings.window.scale[1];
    local windowSize = gConfig.params.windowSize * scale;
    local posX       = gConfig.params.settings.window.posX[1];
    local posY       = gConfig.params.settings.window.posY[1];

    -- 初回（ロード直後）のみ保存位置を適用。以後はImGuiがドラッグを管理
    imgui.SetNextWindowPos({ posX, posY }, ImGuiCond_Once);
    imgui.SetNextWindowBgAlpha(gConfig.params.settings.window.opacity[1]);
    imgui.SetNextWindowSize({ windowSize, -1 }, ImGuiCond_Always);

    imgui.PushStyleColor(ImGuiCol_WindowBg,  gConfig.params.settings.window.backgroundColor);
    imgui.PushStyleColor(ImGuiCol_Border,    gConfig.params.settings.window.borderColor);
    imgui.PushStyleColor(ImGuiCol_Text,      gConfig.params.settings.window.textColor);

    local flags = bit.bor(
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoFocusOnAppearing
    );

    if imgui.Begin('PetHUD', nil, flags) then
        imgui.SetWindowFontScale(scale);

        -- タイトルバードラッグ後の位置をフレームごとに保存
        local wx, wy = imgui.GetWindowPos();
        gConfig.params.settings.window.posX[1] = wx;
        gConfig.params.settings.window.posY[1] = wy;

        -- ペットなし時の表示
        if pet == nil or pet.Name == nil then
            imgui.Text('No active pet');
            -- ペットタイプリセット
            gConfig.params.mobInfo.petType = gConfig.petType.NONE;
        end

        -- ジョブタブ（ペットあり / alwaysVisible 時のみ表示）
        if imgui.BeginTabBar('##job_tabs') then

            -- [PUP] タブ
            local pupFlag = 0;
            if gConfig.params.mobInfo.petType == gConfig.petType.PUPPET then
                pupFlag = getTabFlags(gConfig.petType.PUPPET);
            end
            if imgui.BeginTabItem('PUP', nil, pupFlag) then
                if pet ~= nil then
                    pupPet.gui(pet);
                else
                    imgui.Text('No automaton.');
                end
                imgui.EndTabItem();
            end

            -- [BST] タブ
            local bstFlag = 0;
            local bstType = gConfig.params.mobInfo.petType;
            if bstType == gConfig.petType.CHARMED or bstType == gConfig.petType.JUG then
                bstFlag = getTabFlags(bstType);
            end
            if imgui.BeginTabItem('BST', nil, bstFlag) then
                if pet ~= nil then
                    if gConfig.params.mobInfo.petType == gConfig.petType.CHARMED then
                        charmPet.gui(pet);
                    elseif gConfig.params.mobInfo.petType == gConfig.petType.JUG then
                        jugPet.gui(pet);
                    else
                        -- ペットはいるが petType 未確定
                        genPet.nameHeader(pet, 0);
                    end
                else
                    imgui.Text('No beast.');
                end
                imgui.EndTabItem();
            end

            -- [SMN] タブ
            local smnFlag = 0;
            if gConfig.params.mobInfo.petType == gConfig.petType.SUMMON then
                smnFlag = getTabFlags(gConfig.petType.SUMMON);
            end
            if imgui.BeginTabItem('SMN', nil, smnFlag) then
                if pet ~= nil then
                    smnPet.gui(pet);
                else
                    imgui.Text('No avatar.');
                end
                imgui.EndTabItem();
            end

            -- [DRG] タブ
            local drgFlag = 0;
            if gConfig.params.mobInfo.petType == gConfig.petType.DRAGON then
                drgFlag = getTabFlags(gConfig.petType.DRAGON);
            end
            if imgui.BeginTabItem('DRG', nil, drgFlag) then
                if pet ~= nil then
                    drgPet.gui(pet);
                else
                    imgui.Text('No wyvern.');
                end
                imgui.EndTabItem();
            end

            -- [GEO] タブ
            local geoFlag = 0;
            if gConfig.params.mobInfo.petType == gConfig.petType.LUOPAN then
                geoFlag = getTabFlags(gConfig.petType.LUOPAN);
            end
            if imgui.BeginTabItem('GEO', nil, geoFlag) then
                if pet ~= nil then
                    geoPet.gui(pet);
                else
                    imgui.Text('No luopan.');
                end
                imgui.EndTabItem();
            end

            imgui.EndTabBar();
        end

        -- 共通: HP/MP/TP バー
        if pet ~= nil and gConfig.params.settings.components.petStats[1] then
            genPet.statBars(pet);
        end

        -- 共通: ペットターゲット
        if pet ~= nil
           and gConfig.params.settings.components.petTarget[1]
           and gConfig.params.mobInfo.petTarget ~= nil
           and gConfig.params.mobInfo.petTarget ~= 0 then
            genPet.targetBar();
        end

        imgui.SetWindowFontScale(1.0);
    end
    imgui.PopStyleColor(3);
    imgui.End();
end

return gui;

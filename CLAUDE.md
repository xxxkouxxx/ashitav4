# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

Ashita v4 向け FF11 自作アドオン集。言語は Lua（Ashita v4 API）、UI は ImGui（Ashita 統合版）。

## 開発フロー

### 新アドオン作成時

1. `C:\Users\7xxxk\dev\ashitav4\<AddonName>\` にフォルダを作成してコードを書く
2. Junction でシンボリックリンクを貼り、Ashita に認識させる:
   ```
   mklink /J C:\Ashita-v4beta\addons\<AddonName> C:\Users\7xxxk\dev\ashitav4\<AddonName>
   ```
3. 実装完了後、GitHub に push して PR を作成する

### GitHub PR 作成ルール

- **ブランチ**: `feat/<addon-name>` または `fix/<addon-name>-<description>`
- **PR タイトル**: 機能概要を日本語で簡潔に（例: `PetHUD: マニューバーID修正 + デバウンス追加`）
- **PR 本文**: 変更内容・動作確認方法・スクリーンショット（あれば）を記載

```bash
git checkout -b feat/<AddonName>
git add <AddonName>/
git commit -m "feat: <AddonName> 初期実装"
git push -u origin feat/<AddonName>
gh pr create --title "<タイトル>" --body "<本文>"
```

### インゲームテスト（Ashita v4 起動中）

```
/addon load <AddonName>     # 読み込み
/addon unload <AddonName>   # 解除
/addon reload <AddonName>   # 再読み込み（コード変更後）
```

## アドオン構造の共通パターン

新アドオンはフォルダ名と同名の .lua ファイルがエントリポイント。

```
<AddonName>/
├── <AddonName>.lua        # メイン（addon宣言 + イベント登録）
├── <AddonName>_skills.lua # 技・定数定義（任意）
└── sounds/                # サウンドファイル（.gitignore対象）
```

### addon 宣言（全アドオン必須）

```lua
addon.name    = 'AddonName'
addon.author  = 'xxxkouxxx'
addon.version = '1.0.0'
addon.desc    = '説明'
```

### イベントハンドラ登録

```lua
ashita.events.register('load',        'name_load',    function() end)
ashita.events.register('unload',      'name_unload',  function() end)
ashita.events.register('d3d_present', 'name_render',  function() end)
ashita.events.register('command',     'name_command', function(e) end)
ashita.events.register('packet_in',   'name_pkt_in',  function(e) end)
ashita.events.register('packet_out',  'name_pkt_out', function(e) end)
```

### 設定管理（settings モジュール）

```lua
local settings = require('settings')

local defaults = T{ x = T{100}, y = T{100}, visible = T{true} }

-- ImGui 向けバインド: スカラー値は T{value} の1要素配列にする
-- → imgui.SliderFloat('label', cfg.x, 0, 100) で参照渡し可能
-- → cfg.x[1] で値を読む

settings.register('settings', 'name_settings_update', function(s)
    if s ~= nil then cfg = s end
    settings.save()
end)

-- load イベント内で
cfg = settings.load(defaults)
```

設定ファイルは `C:\Ashita-v4beta\settings\<AddonName>\` に保存される（.gitignore 対象）。

### ImGui 描画（d3d_present 内）

```lua
imgui.SetNextWindowPos({ cfg.x[1], cfg.y[1] }, ImGuiCond_Once)
imgui.SetNextWindowSize({ 400, -1 }, ImGuiCond_Always)
imgui.SetNextWindowBgAlpha(cfg.opacity[1])

local flags = bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollbar)
if imgui.Begin('Title', nil, flags) then
    local wx, wy = imgui.GetWindowPos()  -- 必ず多値返しで受ける
    cfg.x[1] = wx; cfg.y[1] = wy

    imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 0.3, 0.3, 1.0 })
    imgui.Text('赤テキスト')
    imgui.PopStyleColor(1)
end
imgui.End()  -- Begin が false でも必ず呼ぶ
```

**ImGui API の注意点**:
- `imgui.GetWindowPos()` → `local wx, wy = ...`（テーブルでなく多値返し）
- `imgui.CalcTextSize(str)` → `local w, h = ...`（同様に多値返し）
- `ImGuiWindowFlags_NoDecoration` は Ashita ImGui で未定義（使用不可）
- ウィンドウ移動は `ImGuiCond_Once` + `GetWindowPos()` 読み返しで実現（`NoMove` フラグは使わない）

### コマンドハンドラ

```lua
ashita.events.register('command', 'name_command', function(e)
    local args = e.command:args()
    if args[1] ~= '/addonname' then return end
    e.blocked = true

    local sub = args[2] and args[2]:lower() or ''
    if sub == 'show' then cfg.visible[1] = true
    elseif sub == 'hide' then cfg.visible[1] = false
    end
    settings.save()
end)
```

### パケット処理

```lua
ashita.events.register('packet_in', 'name_pkt_in', function(e)
    if e.id ~= 0x028 then return end  -- アクションパケット

    -- ビット抽出（struct.unpack + 1-indexed offset）
    local actor = struct.unpack('I', e.data, 0x05 + 0x01)
    -- e.blocked = true でパケットを遮断
end)
```

パケット offset は `0xNN + 0x01`（struct.unpack は 1-indexed）。

## Ashita API リファレンス（よく使うもの）

```lua
-- プレイヤー情報
local player = AshitaCore:GetMemoryManager():GetPlayer()
player:GetMainJob()        -- ジョブ ID（PUP=18, BST=9, SMN=15, DRG=17）
player:GetMainJobLevel()
player:GetStat(6)          -- CHR（0=STR,1=DEX,2=VIT,3=AGI,4=INT,5=MND,6=CHR）

-- エンティティ
local ent = GetPlayerEntity()          -- プレイヤーエンティティ
local pet = GetEntity(ent.PetTargetIndex)
pet.Name; pet.Distance; pet.ServerId

-- インベントリ（装備確認）
local inv = AshitaCore:GetMemoryManager():GetInventory()
local equip = inv:GetEquippedItem(slot)   -- slot 0-15
local item  = inv:GetContainerItem(container, index)

-- リキャスト
local rm = AshitaCore:GetMemoryManager():GetRecast()
rm:GetAbilityTimerByIndex(i)   -- アビリティ
rm:GetSpellTimerByIndex(i)

-- メモリ直接読み取り（pup.lua パターン）
ashita.memory.find('FFXiMain.dll', 0, 'pattern', offset, 0)
ashita.memory.read_uint32(ptr)
ashita.memory.read_array(ptr, size)

-- コマンド実行
AshitaCore:GetChatManager():QueueCommand(1, '/ws "Vorpal Blade" <t>')
```

## 既存アドオン一覧

| アドオン | 機能 | 主なイベント |
|---------|------|------------|
| **CorDice** | コルセア ファントムロール可視化 | packet_in(0x028), d3d_present |
| **BattleAssist** | PLD向け即死技アラート + バフ切れ警告 | packet_in, d3d_present |
| **PTChatLog** | PT/Allianceチャット + 戦闘ログ記録 | packet_in(0x017), d3d_present |
| **wscalc** | WS ダメージ計算ツール | d3d_present のみ |
| **MacroSwitcher** | ジョブチェンジ時マクロ自動切り替え | packet_in(0x01B) |
| **macro_export** | マクロデータのエクスポート | command のみ |

## 基本ルール

- コメントは日本語
- 設定ファイルは Ashita の settings/ 以下（.gitignore 対象）
- サウンドファイルは sounds/ 以下（.gitignore 対象）

## Notion（プロジェクト管理）

https://www.notion.so/32ce3079e9a981119a6dfe73ad9ebc9c
（Discord × Notion ゲームツール開発 > FF11 Ashitav4 アドオン開発）

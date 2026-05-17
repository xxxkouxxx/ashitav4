# DangerAlert アドオン 新規作成指示書

## 概要

BattleAssist v2.0 に含まれていた「即死技アラート」機能を、独立した新アドオンとして再実装する。
BattleAssist v3.0 はバフ監視のみに特化したため、危険技検知は本アドオンで担う。

---

## アドオン仕様

### 機能
- モンスターの危険技（即死技・状態異常技など）をパケットで検知
- 画面中央に赤文字で点滅アラート表示（ImGui オーバーレイ）
- 音声通知（`sounds/critical.wav`）
- HUD 上でスキルごとの有効/無効切り替え（チェックボックス）

### アドオン名候補
- `DangerAlert`（推奨）

### ファイル構成
```
ashitav4/
└── DangerAlert/
    ├── DangerAlert.lua          # メインスクリプト
    ├── DangerAlert_skills.lua   # 技ID定義テーブル
    └── sounds/
        └── critical.wav         # 警告音（.gitignore対象）
```

---

## 参考コード（BattleAssist v2.0 より）

旧実装は worktree に残っている:
```
C:\Users\7xxxk\dev\ashitav4\.claude\worktrees\condescending-cannon-c4ad1b\BattleAssist\battleassist.lua
```
主要ロジックの参照箇所:
- `packet_in` ハンドラ（0x028 アクションパケット解析）: 99〜156行
- 即死技アラート描画（画面中央・赤文字点滅）: 330〜378行
- `DangerAlert_skills.lua` の形式: `BattleAssist_skills.lua` をそのまま流用可

---

## 技ID定義テーブル（DangerAlert_skills.lua）

```lua
local M = {}

M.dangerous_skills = {
    -- 即死技
    [220]  = { name = "Doom",           level = "critical", phase = "cast" },
    [1928] = { name = "Death",          level = "critical", phase = "cast" },
    -- ボス技
    [749]  = { name = "AbsoluteTerror", level = "critical", phase = "cast" },
    [1246] = { name = "Terror",         level = "critical", phase = "cast" },
    -- 追加はここに続ける
}

return M
```

`phase` の意味:
- `"cast"` : 詠唱開始時に検知（category == 8 or 11）
- `"impact"` : 発動時に検知（category == 2）
- `"both"` : 両方

---

## パケット解析（0x028 Action Packet）

```lua
ashita.events.register('packet_in', 'dangeralert_packet_in', function(e)
    if e.id ~= 0x028 then return end

    local actor_id  = ashita.bits.unpack_be(e.data_raw, 0x04 * 8, 32)
    local action_id = ashita.bits.unpack_be(e.data_raw, 0x18 * 8, 16)
    local category  = ashita.bits.unpack_be(e.data_raw, 0x0A * 8, 8)

    -- パーティメンバーの行動は無視
    local party = AshitaCore:GetMemoryManager():GetParty()
    for i = 0, 5 do
        if party:GetMemberServerId(i) == actor_id then return end
    end

    local skill = skills_def.dangerous_skills[action_id]
    if skill then
        -- phase と category の照合でアラート発火
    end
end)
```

> **注意**: `action_id` と `category` のオフセット・値は要実測。
> `DEBUG_PACKET = true` にしてログで確認すること。

---

## ImGui 実装上の注意点（前セッションでのハマりポイント）

### 1. Checkbox は `{bool}` テーブルで渡す
```lua
-- NG: boolean を直接渡すとクラッシュ
-- imgui.Checkbox('label', enabled)

-- OK: テーブルで渡す
local val = { not cfg.disabled_skills[id] }
if imgui.Checkbox(skill.name, val) then
    cfg.disabled_skills[id] = (not val[1]) or nil
    settings.save()
end
```

### 2. ImGui に日本語フォントがない
- ラベル・スキル名は**すべて英語**にすること
- 日本語を渡すと `???` と表示される

### 3. `imgui.Begin` の第2引数は `true` を渡す
```lua
-- 第2引数を nil にするとフラグが無視される場合がある
if imgui.Begin('DangerAlert##alert', true, flags) then
```

### 4. `NoTitleBar` ウィンドウのドラッグ
- `ImGuiWindowFlags_NoTitleBar` を使うと、1クリック目はフォーカス取得、2クリック目+ドラッグで移動
- これは Ashita ImGui の仕様（コードの問題ではない）
- タイトルバーあり (`PetHud` 方式) にすれば1クリックでドラッグ可能

---

## アラート UI 仕様

画面中央・上寄りに点滅表示:
```lua
-- 点滅: 0.6秒周期（0.3秒ON / 0.3秒OFF）
alert.blink = alert.blink + dt
local visible = (alert.blink % 0.6) < 0.3

if visible then
    -- 画面中央に固定ウィンドウ
    imgui.SetNextWindowPos(
        { (io.DisplaySize.x - win_w) * 0.5, io.DisplaySize.y * 0.35 },
        ImGuiCond_Always
    )
    -- 赤文字 + フォント拡大
    imgui.SetWindowFontScale(1.6)
    imgui.Text(alert.message)
    -- タイマーバー
    imgui.ProgressBar(alert.timer / 5.0, { -1, 6 }, '')
end
```

---

## デバッグ方法（技IDの実測）

1. `DEBUG_PACKET = true` に設定してリロード
2. フィールドで敵に技を使わせる
3. チャットログの `[DangerAlert DEBUG] action_id=` の値を記録
4. `DangerAlert_skills.lua` に追記

ログ出力先: `<Ashita install>/logs/DangerAlert_debug.log`

---

## Ashita へのインストール

Ashita の稼働フォルダ:
```
C:\Ashita-v4beta\addons\DangerAlert\
```

開発フォルダ:
```
C:\Users\7xxxk\dev\ashitav4\DangerAlert\
```

**ハードリンク設定**（管理者コマンドプロンプトで実行）:
```cmd
mklink /H "C:\Ashita-v4beta\addons\DangerAlert\DangerAlert.lua" "C:\Users\7xxxk\dev\ashitav4\DangerAlert\DangerAlert.lua"
```
→ 開発ファイルを編集すると Ashita 側も即時反映される。

---

## 参考アドオン

| アドオン | 参照ポイント |
|----------|-------------|
| `BattleAssist` (v2.0 worktree) | packet_in / alert UI の元実装 |
| `PetHud` | Checkbox パターン・設定管理の正しい実装例 |
| `CorDice` | シンプルな ImGui HUD の構成例 |

---

## 作業ステータス

- [ ] DangerAlert フォルダ作成
- [ ] `DangerAlert_skills.lua` 作成（技ID定義）
- [ ] `DangerAlert.lua` 作成（packet_in + ImGui 描画）
- [ ] ハードリンク設定
- [ ] 実機でデバッグ（技ID実測）
- [ ] 音声ファイル配置（`sounds/critical.wav`）

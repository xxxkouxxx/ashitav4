# DangerAlert

危険技（即死技・状態異常技）をパケットで検知し、画面中央に赤文字アラートを表示する Ashita v4 アドオン。

## コマンド

| コマンド | 動作 |
|---------|------|
| `/da` または `/dangeralert` | HUD 表示/非表示トグル |
| `/da test` | テスト用アラートを発火（表示確認用） |
| `/da debug` | パケットログのON/OFFトグル（技ID実測時に使用） |

---

## 技の追加方法

`DangerAlert_skills.lua` を編集して追記する。

### 1. 技IDを調べる

インゲームで以下の手順:

1. `/da debug` でパケットログを有効化
2. フィールドで対象の敵に技を使わせる
3. チャットログに出力される `action_id=` の数値をメモする
   ```
   [DangerAlert DEBUG] actor=00XXXXXX action_id=220 category=8
   ```
4. `/da debug` でログを無効化

ログファイルにも記録される: `<Ashita install>/logs/DangerAlert_debug.log`

### 2. DangerAlert_skills.lua に追記する

```lua
M.dangerous_skills = {
    [220]  = { name = "Doom",     level = "critical", phase = "cast" },

    -- ここに追加する
    [技ID] = { name = "技名(英語)", level = "critical", phase = "cast" },
}
```

### phase の指定

| 値 | タイミング | category の値 |
|----|-----------|--------------|
| `"cast"` | 詠唱開始時 | 8 または 11 |
| `"impact"` | 発動時 | 2 |
| `"both"` | 詠唱開始＋発動の両方 | — |

即死技は詠唱開始で気づけるよう `"cast"` を推奨。

### 3. リロードして反映

```
/addon reload DangerAlert
```

---

## HUD でのスキル無効化

HUD のチェックボックスを外すと、その技のアラートが出なくなる。  
設定は `settings/` 以下に自動保存される。

---

## 技ID 一覧（実測済み）

> 実機で確認した値をここに記録していく。

| 技ID | 技名 | フィールド/ボス | 備考 |
|------|------|---------------|------|
| 220  | Doom | — | 仮定義・要実測 |
| 1928 | Death | — | 仮定義・要実測 |
| 749  | AbsoluteTerror | — | 仮定義・要実測 |
| 1246 | Terror | — | 仮定義・要実測 |

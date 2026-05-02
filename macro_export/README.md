# macro_export 使用手順

マクロ・装備セット・所持アイテムをCSVにエクスポートし、Excelで整理するツールです。

---

## 構成ファイル

| ファイル | 役割 |
|---|---|
| `macro_export.lua` | Ashita アドオン（ゲーム内でCSV出力） |
| `encoding.lua` | ShiftJIS ↔ UTF-8 変換ヘルパー |
| `ff11_excel.py` | CSVを読み込んでExcelに整形するスクリプト |

---

## Step 1: アドオンをインストール

```
C:\Ashita-v4beta\addons\macro_export\
    macro_export.lua
    encoding.lua
```

> **注意:** ファイルを書き換えた場合はハードリンクが切れるため再作成が必要  
> ```powershell
> Remove-Item 'C:\Ashita-v4beta\addons\macro_export\macro_export.lua' -Force
> New-Item -ItemType HardLink `
>     -Path   'C:\Ashita-v4beta\addons\macro_export\macro_export.lua' `
>     -Target 'C:\Users\7xxxk\dev\ashitav4\macro_export\macro_export.lua'
> ```

---

## Step 2: ゲーム内でCSV出力

FF11 を起動し、Ashita でキャラクターにログインした状態で実行します。

```
/addon load macro_export
/me export
```

| コマンド | 出力対象 |
|---|---|
| `/me export` | マクロ・装備セット・所持アイテム（全部） |
| `/me macros` | マクロのみ |
| `/me equipsets` | 装備セットのみ |
| `/me inventory` | 所持アイテムのみ |

出力先: `C:\Ashita-v4beta\export\`

出力ファイル例:
```
98c42d_macros_20260421_120000.csv
98c42d_equipsets_20260421_120000.csv
98c42d_inventory_20260421_120000.csv
```

---

## Step 3: Excelファイルを生成

`ff11_excel.py` を `C:\Ashita-v4beta\export\` にコピーしておくか、スクリプトのフォルダにCSVを置いて実行します。

### 自動検索モード（推奨）

```bash
cd C:\Ashita-v4beta\export
python ff11_excel.py
```

同フォルダ内の最新CSVを自動で読み込みます。

### ファイルを直接指定

```bash
python ff11_excel.py macros.csv equipsets.csv inventory.csv
```

### キャラ名でフィルタ

```bash
python ff11_excel.py --char 98c42d
```

出力: `FF11_macro_review.xlsx`（スクリプトと同じフォルダ）

---

## Excelの見方

| シート | 内容 |
|---|---|
| **サマリー** | 全体の統計とステータス内訳 |
| **整理チェック** | 装備セットをステータス別に並べた整理用シート ← メイン |
| **マクロ一覧** | マクロ全件・参照セット・所持確認 |
| **装備セット確認** | セット全件・スロット別所持確認 |
| **所持アイテム一覧** | バッグ別アイテム一覧 |

### ステータスの見方（整理チェックシート）

| ステータス | 意味 | 対応 |
|---|---|---|
| `✓ 正常` | マクロあり・装備揃い | そのまま |
| `⚠ 装備不足` | マクロあり・未所持装備あり | 装備を入手 or マクロを見直す |
| `📦 未参照` | 装備揃い・マクロから呼ばれていない | 不要なら削除 |
| `🗑 未参照+不足` | マクロなし・装備も不足 | 削除候補 |
| `（空）` | 空の装備セット枠 | 削除候補 |

---

## 出力されるマクロCSVの列

| 列 | 内容 |
|---|---|
| `ファイル` | 元ファイル名（`p1` = mcr1.dat、`p42` = mcr42.dat） |
| `ブックNo` | 1 = F1-F10 のマクロ、2 = Ctrl+F1-F10 のマクロ |
| `マクロNo` | 1〜10 |
| `タイトル` | マクロのタイトル |
| `行1〜行6` | マクロの各コマンド行 |

---

## 出力されるセットCSVの列

| 列 | 内容 |
|---|---|
| `セットNo` | 1〜200（es0.dat=1-20、es1.dat=21-40、…） |
| `セット名` | 装備セット名 |
| `Main`〜`Feet` | 各スロットのアイテム名（未解決の場合 `ID:XXXXX`） |

---

## 依存ライブラリ（Python）

```bash
pip install openpyxl
```

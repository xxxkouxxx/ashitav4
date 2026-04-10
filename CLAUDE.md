# ashitav4 開発ガイド

## プロジェクト概要
Ashita v4 向け FF11 自作アドオン集（主にナイト/PLD用）

## ファイル構成
```
ashitav4/
├── CLAUDE.md
├── README.md
└── <AddonName>/
    ├── <AddonName>.lua        # メインスクリプト
    ├── <AddonName>_skills.lua # 技・設定定義（任意）
    └── sounds/                # サウンドファイル（.gitignore対象）
```

## 技術スタック
- 言語: Lua（Ashita v4 API）
- UI: ImGui（Ashita統合版）
- パケット処理: ashita.bits / ashita.events

## Notion
プロジェクト管理・タスク・作業手順:
https://www.notion.so/32ce3079e9a981119a6dfe73ad9ebc9c
（Discord × Notion ゲームツール開発 > FF11 Ashitav4 アドオン開発）

## 基本ルール
- コメントは日本語
- 設定ファイルは settings/ 以下（.gitignore対象）
- サウンドファイルは sounds/ 以下（.gitignore対象）
- 新アドオンは専用フォルダを作り、メインLuaファイルをフォルダ名と同名にする

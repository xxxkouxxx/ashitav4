# ashitav4 addons

Ashita v4 向け 自作アドオン集（FF11 / ナイト）

## アドオン一覧

| フォルダ | 概要 |
|----------|------|
| [BattleAssist](./BattleAssist/) | PLD向け即死技アラート + バフ切れ警告 |

## インストール（共通）

各アドオンフォルダを `C:\Ashita-v4beta\addons\` 配下に配置する。  
開発時はシンボリックリンク（Junction）で直結すると便利：

```cmd
mklink /J "C:\Ashita-v4beta\addons\<AddonName>" "C:\Users\7xxxk\dev\ashitav4\<AddonName>"
```

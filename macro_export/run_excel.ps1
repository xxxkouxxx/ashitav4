<#
.SYNOPSIS
    FF11 全キャラの最新インベントリCSVをExcelに変換するバッチスクリプト
.DESCRIPTION
    C:\Ashita-v4beta\export\ 内の最新 *_inventory_*.csv を自動検索し
    ff11_excel.py --multi を呼び出してExcelを生成します。
.EXAMPLE
    .\run_excel.ps1
    .\run_excel.ps1 -ExportDir "D:\Ashita\export"
#>
param(
    [string]$ExportDir = "C:\Ashita-v4beta\export"
)

$ScriptDir    = $PSScriptRoot
$PythonScript = Join-Path $ScriptDir "ff11_excel.py"

if (-not (Test-Path $PythonScript)) {
    Write-Error "ff11_excel.py が見つかりません: $PythonScript"
    exit 1
}

if (-not (Test-Path $ExportDir)) {
    Write-Error "export ディレクトリが見つかりません: $ExportDir"
    exit 1
}

$invFiles = Get-ChildItem $ExportDir -Filter "*_inventory_*.csv" |
    Sort-Object LastWriteTime -Descending

if ($invFiles.Count -eq 0) {
    Write-Host "[警告] $ExportDir に *_inventory_*.csv が見つかりません" -ForegroundColor Yellow
    Write-Host "各キャラにログインして /me inventory を実行してください"
    Read-Host "Enterキーで終了"
    exit 1
}

Write-Host "=== 検出された inventory CSV ===" -ForegroundColor Cyan
$invFiles | ForEach-Object {
    Write-Host ("  {0}  {1}" -f $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $_.Name)
}
Write-Host ""

Write-Host "=== 環境確認 ===" -ForegroundColor Gray
Write-Host "  ScriptDir   : $ScriptDir"
Write-Host "  PythonScript: $PythonScript"
Write-Host ""

Write-Host "=== Excel 生成開始 ===" -ForegroundColor Green
python $PythonScript --multi --dir $ExportDir

if ($LASTEXITCODE -eq 0) {
    $OutFile = Join-Path $ExportDir "FF11_all_chars.xlsx"
    Write-Host ""
    Write-Host "完了: $OutFile" -ForegroundColor Green
    if (Test-Path $OutFile) {
        Start-Process $OutFile
    }
} else {
    Write-Host ""
    Write-Host "[エラー] Python スクリプトが失敗しました (exit code: $LASTEXITCODE)" -ForegroundColor Red
}

Read-Host "`nEnterキーで閉じる"

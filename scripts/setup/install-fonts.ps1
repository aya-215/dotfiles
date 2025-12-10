<#
.SYNOPSIS
    フォントインストーラー (Windows用)

.DESCRIPTION
    dotfilesで使用するフォントをインストールします。
    既にインストール済みのものはスキップされます（冪等性）。

    注意: Chocolateyが必要です。

.PARAMETER DryRun
    実際の変更を行わず、実行内容のみ表示

.EXAMPLE
    .\install-fonts.ps1
    フォントをインストール

.EXAMPLE
    .\install-fonts.ps1 -DryRun
    実行内容のみ表示
#>

param(
    [switch]$DryRun
)

# 共通関数を読み込み
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SCRIPT_DIR "common.ps1")

Write-Info "===================================="
Write-Info "  フォントインストーラー (Windows)"
Write-Info "===================================="
Write-Info ""

# インストールカウンター
$script:installedCount = 0
$script:skippedCount = 0
$script:errorCount = 0

# Chocolateyがインストールされているか確認
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Error "Chocolateyがインストールされていません"
    Write-Info ""
    Write-Info "Chocolateyのインストール方法:"
    Write-Info "  1. 管理者権限でPowerShellを起動"
    Write-Info "  2. 以下のコマンドを実行:"
    Write-Info ""
    Write-Info "Set-ExecutionPolicy Bypass -Scope Process -Force"
    Write-Info "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072"
    Write-Info "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    Write-Info ""
    Write-Info "詳細: https://chocolatey.org/install"
    exit 1
}

Write-Info "フォントをチェック中..."
Write-Info ""

# HackGen Nerd Font
Install-ChocoPackage -PackageName "font-hackgen-nerd" -DisplayName "HackGen Nerd Font"

Write-Info ""

# 結果サマリー
Show-ResultSummary -SuccessCount $installedCount -SkipCount $skippedCount -ErrorCount $errorCount

if ($DryRun) {
    Write-Info "[DryRun] 実際の変更は行われていません"
    Write-Info "実際にインストールするには、-DryRun オプションを外して実行してください"
} elseif ($errorCount -eq 0) {
    Write-Success "フォントのインストールが完了しました！"
    Write-Info ""
    Write-Info "次のステップ:"
    Write-Info "  1. ターミナルを再起動してフォントを反映してください"
    Write-Info "  2. WeZTermやNeovimでフォントが正しく表示されるか確認してください"
} else {
    Write-Warning "一部のフォントでエラーが発生しました"
    Write-Info "エラーメッセージを確認して、手動でインストールしてください"
}

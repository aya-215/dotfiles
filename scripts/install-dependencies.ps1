<#
.SYNOPSIS
    dotfiles 依存関係インストーラー (Windows用)

.DESCRIPTION
    dotfilesで使用するツールとモジュールをインストールします。
    既にインストール済みのものはスキップされます（冪等性）。

.PARAMETER SkipTools
    コマンドラインツール（fzf、neovim等）のインストールをスキップ

.PARAMETER SkipModules
    PowerShellモジュールのインストールをスキップ

.PARAMETER SkipFonts
    フォントのインストールをスキップ

.PARAMETER DryRun
    実際の変更を行わず、実行内容のみ表示

.EXAMPLE
    .\install-dependencies.ps1
    すべての依存関係をインストール

.EXAMPLE
    .\install-dependencies.ps1 -SkipModules
    コマンドラインツールとフォントのみインストール

.EXAMPLE
    .\install-dependencies.ps1 -SkipFonts
    フォント以外をインストール

.EXAMPLE
    .\install-dependencies.ps1 -DryRun
    実行内容のみ表示
#>

param(
    [switch]$SkipTools,
    [switch]$SkipModules,
    [switch]$SkipFonts,
    [switch]$DryRun
)

# 共通関数を読み込み
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SCRIPT_DIR "common.ps1")

Write-Info "===================================="
Write-Info "  依存関係インストーラー (Windows)"
Write-Info "===================================="
Write-Info ""

# インストールカウンター
$script:installedCount = 0
$script:skippedCount = 0
$script:errorCount = 0

# wingetでツールをインストールする関数
function Install-CliTool {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$CommandName,
        [switch]$Optional
    )

    Write-Info "[$Name] チェック中..."

    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        Write-Success "  既にインストール済み"
        $script:skippedCount++
        return
    }

    if ($Optional) {
        Write-Info "  未インストール（オプション）"
        Write-Info "  必要な場合は手動でインストールしてください:"
        Write-Info "    winget install $WingetId"
        return
    }

    if ($DryRun) {
        Write-Info "  [DryRun] インストール: winget install $WingetId"
        $script:installedCount++
    } else {
        try {
            winget install --id $WingetId --silent --accept-source-agreements --accept-package-agreements
            Write-Success "  インストール完了"
            $script:installedCount++
        } catch {
            Write-Error "  インストール失敗: $_"
            $script:errorCount++
        }
    }
}

# PowerShellモジュールをインストールする関数
function Install-PSModule {
    param(
        [string]$ModuleName
    )

    Write-Info "[$ModuleName] チェック中..."

    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-Success "  既にインストール済み"
        $script:skippedCount++
        return
    }

    if ($DryRun) {
        Write-Info "  [DryRun] インストール: Install-Module $ModuleName -Scope CurrentUser"
        $script:installedCount++
    } else {
        try {
            Install-Module $ModuleName -Scope CurrentUser -Force -AllowClobber
            Write-Success "  インストール完了"
            $script:installedCount++
        } catch {
            Write-Error "  インストール失敗: $_"
            $script:errorCount++
        }
    }
}

# コマンドラインツールのインストール
if (-not $SkipTools) {
    Write-Info "コマンドラインツールをチェック中..."
    Write-Info ""

    Install-CliTool -Name "fzf" -WingetId "junegunn.fzf" -CommandName "fzf"
    Install-CliTool -Name "Neovim" -WingetId "Neovim.Neovim" -CommandName "nvim"
    Install-CliTool -Name "kubectl" -WingetId "Kubernetes.kubectl" -CommandName "kubectl" -Optional

    Write-Info ""
}

# PowerShellモジュールのインストール
if (-not $SkipModules) {
    Write-Info "PowerShellモジュールをチェック中..."
    Write-Info ""

    Install-PSModule -ModuleName "PSFzf"
    Install-PSModule -ModuleName "ZLocation"
    Install-PSModule -ModuleName "BurntToast"

    Write-Info ""
}

# フォントのインストール
if (-not $SkipFonts) {
    Write-Info "フォントをチェック中..."
    Write-Info ""

    # Chocolateyがインストールされているか確認
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Warning "Chocolateyがインストールされていません"
        Write-Info "フォントのインストールにはChocolateyが必要です:"
        Write-Info "  https://chocolatey.org/install"
        Write-Info ""
    } else {
        Install-ChocoPackage -PackageName "font-hackgen-nerd" -DisplayName "HackGen Nerd Font"
        Write-Info ""
    }
}

# 結果サマリー
Show-ResultSummary -SuccessCount $installedCount -SkipCount $skippedCount -ErrorCount $errorCount

if ($DryRun) {
    Write-Info "[DryRun] 実際の変更は行われていません"
    Write-Info "実際にインストールするには、-DryRun オプションを外して実行してください"
} elseif ($errorCount -eq 0) {
    Write-Success "すべての依存関係のインストールが完了しました！"
    Write-Info ""
    Write-Info "次のステップ:"
    Write-Info "  1. ターミナルを再起動してください（PATHを反映するため）"
    Write-Info "  2. dotfilesをインストール: .\scripts\install.ps1"
} else {
    Write-Warning "一部の依存関係でエラーが発生しました"
    Write-Info "エラーメッセージを確認して、手動でインストールしてください"
}

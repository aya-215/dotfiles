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

.PARAMETER DryRun
    実際の変更を行わず、実行内容のみ表示

.EXAMPLE
    .\install-dependencies.ps1
    すべての依存関係をインストール

.EXAMPLE
    .\install-dependencies.ps1 -SkipModules
    コマンドラインツールのみインストール

.EXAMPLE
    .\install-dependencies.ps1 -DryRun
    実行内容のみ表示
#>

param(
    [switch]$SkipTools,
    [switch]$SkipModules,
    [switch]$DryRun
)

# エラー時に停止
$ErrorActionPreference = "Stop"

# 出力エンコーディングをUTF-8に設定
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# カラー出力関数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { Write-ColorOutput $args[0] "Green" }
function Write-Info { Write-ColorOutput $args[0] "Cyan" }
function Write-Warning { Write-ColorOutput $args[0] "Yellow" }
function Write-Error { Write-ColorOutput $args[0] "Red" }

Write-Info "===================================="
Write-Info "  依存関係インストーラー (Windows)"
Write-Info "===================================="
Write-Info ""

# インストールカウンター
$installedCount = 0
$skippedCount = 0
$errorCount = 0

# コマンドラインツールのインストール
if (-not $SkipTools) {
    Write-Info "コマンドラインツールをチェック中..."
    Write-Info ""

    # fzf
    Write-Info "[fzf] チェック中..."
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        if ($DryRun) {
            Write-Info "  [DryRun] インストール: winget install fzf"
            $installedCount++
        } else {
            try {
                winget install --id junegunn.fzf --silent --accept-source-agreements --accept-package-agreements
                Write-Success "  インストール完了"
                $installedCount++
            } catch {
                Write-Error "  インストール失敗: $_"
                $errorCount++
            }
        }
    }

    # Neovim
    Write-Info "[Neovim] チェック中..."
    if (Get-Command nvim -ErrorAction SilentlyContinue) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        if ($DryRun) {
            Write-Info "  [DryRun] インストール: winget install neovim"
            $installedCount++
        } else {
            try {
                winget install --id Neovim.Neovim --silent --accept-source-agreements --accept-package-agreements
                Write-Success "  インストール完了"
                $installedCount++
            } catch {
                Write-Error "  インストール失敗: $_"
                $errorCount++
            }
        }
    }

    # kubectl (オプション)
    Write-Info "[kubectl] チェック中..."
    if (Get-Command kubectl -ErrorAction SilentlyContinue) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        Write-Info "  未インストール（オプション）"
        Write-Info "  Kubernetesを使用する場合は手動でインストールしてください:"
        Write-Info "    winget install Kubernetes.kubectl"
    }

    Write-Info ""
}

# PowerShellモジュールのインストール
if (-not $SkipModules) {
    Write-Info "PowerShellモジュールをチェック中..."
    Write-Info ""

    # PSFzf
    Write-Info "[PSFzf] チェック中..."
    if (Get-Module -ListAvailable -Name PSFzf) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        if ($DryRun) {
            Write-Info "  [DryRun] インストール: Install-Module PSFzf -Scope CurrentUser"
            $installedCount++
        } else {
            try {
                Install-Module PSFzf -Scope CurrentUser -Force -AllowClobber
                Write-Success "  インストール完了"
                $installedCount++
            } catch {
                Write-Error "  インストール失敗: $_"
                $errorCount++
            }
        }
    }

    # ZLocation
    Write-Info "[ZLocation] チェック中..."
    if (Get-Module -ListAvailable -Name ZLocation) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        if ($DryRun) {
            Write-Info "  [DryRun] インストール: Install-Module ZLocation -Scope CurrentUser"
            $installedCount++
        } else {
            try {
                Install-Module ZLocation -Scope CurrentUser -Force -AllowClobber
                Write-Success "  インストール完了"
                $installedCount++
            } catch {
                Write-Error "  インストール失敗: $_"
                $errorCount++
            }
        }
    }

    # BurntToast
    Write-Info "[BurntToast] チェック中..."
    if (Get-Module -ListAvailable -Name BurntToast) {
        Write-Success "  既にインストール済み"
        $skippedCount++
    } else {
        if ($DryRun) {
            Write-Info "  [DryRun] インストール: Install-Module BurntToast -Scope CurrentUser"
            $installedCount++
        } else {
            try {
                Install-Module BurntToast -Scope CurrentUser -Force -AllowClobber
                Write-Success "  インストール完了"
                $installedCount++
            } catch {
                Write-Error "  インストール失敗: $_"
                $errorCount++
            }
        }
    }

    Write-Info ""
}

# 結果サマリー
Write-Info "===================================="
Write-Info "  インストール完了"
Write-Info "===================================="
if ($installedCount -gt 0) {
    Write-Success "インストール: $installedCount"
}
if ($skippedCount -gt 0) {
    Write-Info "スキップ: $skippedCount"
}
if ($errorCount -gt 0) {
    Write-Error "エラー: $errorCount"
}
Write-Info ""

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

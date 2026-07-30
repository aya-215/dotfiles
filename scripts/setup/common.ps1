<#
.SYNOPSIS
    dotfilesスクリプト共通関数

.DESCRIPTION
    install.ps1とinstall-dependencies.ps1で共有する関数を定義します。
#>

# エラー時に停止
$ErrorActionPreference = "Stop"

# 出力エンコーディングをUTF-8に設定
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ========================================
# カラー出力関数
# ========================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput $Message "Green"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput $Message "Cyan"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput $Message "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput $Message "Red"
}

# ========================================
# 結果サマリー表示
# ========================================

function Show-ResultSummary {
    param(
        [int]$SuccessCount,
        [int]$SkipCount,
        [int]$ErrorCount,
        [string]$Title = "インストール完了"
    )

    Write-Info ""
    Write-Info "===================================="
    Write-Info "  $Title"
    Write-Info "===================================="

    if ($SuccessCount -gt 0) {
        Write-Success "成功: $SuccessCount"
    }
    if ($SkipCount -gt 0) {
        Write-Info "スキップ: $SkipCount"
    }
    if ($ErrorCount -gt 0) {
        Write-Error "エラー: $ErrorCount"
    }

    Write-Info ""
}

# ========================================
# Chocolateyパッケージ管理
# ========================================

function Install-ChocoPackage {
    param(
        [string]$PackageName,
        [string]$DisplayName,
        [string]$CheckCommand,
        [switch]$Optional
    )

    Write-Info "[$DisplayName] チェック中..."

    # インストール済みチェック（コマンドで確認）
    if ($CheckCommand -and (Get-Command $CheckCommand -ErrorAction SilentlyContinue)) {
        Write-Success "  既にインストール済み"
        $script:skippedCount++
        return
    }

    # Chocolateyパッケージとしてインストール済みチェック
    $chocoList = choco list --local-only $PackageName --exact --limit-output 2>$null
    if ($chocoList) {
        Write-Success "  既にインストール済み"
        $script:skippedCount++
        return
    }

    if ($Optional) {
        Write-Info "  未インストール（オプション）"
        Write-Info "  必要な場合は手動でインストールしてください:"
        Write-Info "    choco install $PackageName"
        return
    }

    if ($DryRun) {
        Write-Info "  [DryRun] インストール: choco install $PackageName"
        $script:installedCount++
    } else {
        try {
            choco install $PackageName -y --no-progress
            Write-Success "  インストール完了"
            $script:installedCount++
        } catch {
            Write-Error "  インストール失敗: $_"
            $script:errorCount++
        }
    }
}

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
# 環境変数管理
# ========================================

function Set-EnvironmentVariableIfNeeded {
    param(
        [string]$Name,
        [string]$Value,
        [switch]$Force,
        [switch]$DryRun
    )

    Write-Info "環境変数 $Name を確認中..."
    $currentValue = [System.Environment]::GetEnvironmentVariable($Name, "User")

    if ($currentValue -eq $Value) {
        Write-Success "環境変数 $Name は既に設定されています: $currentValue"
        return $true
    }

    if ($null -eq $currentValue -or $currentValue -eq "") {
        if ($DryRun) {
            Write-Info "[DryRun] 環境変数を設定: $Name=$Value"
        } else {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
            Set-Item -Path "env:$Name" -Value $Value
            Write-Success "環境変数 $Name を設定しました: $Value"
        }
        return $true
    }

    # 既に別の値が設定されている場合
    Write-Warning "環境変数 $Name は既に別の値が設定されています: $currentValue"
    Write-Warning "推奨値: $Value"

    if (-not $Force -and -not $DryRun) {
        $response = Read-Host "上書きしますか? (y/N)"
        if ($response -eq "y" -or $response -eq "Y") {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
            Set-Item -Path "env:$Name" -Value $Value
            Write-Success "環境変数 $Name を上書きしました: $Value"
            return $true
        } else {
            Write-Info "環境変数の設定をスキップしました"
            return $false
        }
    }

    return $false
}

# ========================================
# シンボリックリンク管理
# ========================================

function New-SymbolicLinkSafe {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Target,
        [string]$BackupDir,
        [switch]$DryRun,
        [ref]$SuccessCount,
        [ref]$SkipCount,
        [ref]$ErrorCount
    )

    Write-Info "[$Name] 処理中..."

    # ソースの存在確認
    if (-not (Test-Path $Source)) {
        Write-Error "  エラー: ソースが見つかりません: $Source"
        $ErrorCount.Value++
        return
    }

    # ターゲットの親ディレクトリを作成
    $targetParent = Split-Path -Parent $Target
    if (-not (Test-Path $targetParent)) {
        if ($DryRun) {
            Write-Info "  [DryRun] ディレクトリを作成: $targetParent"
        } else {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            Write-Success "  ディレクトリを作成しました: $targetParent"
        }
    }

    # 既存のターゲットをチェック
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force

        # 既に正しいシンボリックリンクが存在する場合
        if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $Source) {
            Write-Success "  スキップ: 既に正しいシンボリックリンクが存在します"
            $SkipCount.Value++
            return
        }

        # バックアップ
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupName = "$(Split-Path -Leaf $Target)_$timestamp"
        $backupPath = Join-Path $BackupDir $backupName

        if ($DryRun) {
            Write-Info "  [DryRun] バックアップ: $Target -> $backupPath"
        } else {
            Move-Item -Path $Target -Destination $backupPath -Force
            Write-Warning "  バックアップしました: $backupPath"
        }
    }

    # シンボリックリンク作成
    if ($DryRun) {
        Write-Info "  [DryRun] シンボリックリンク作成: $Target -> $Source"
        $SuccessCount.Value++
    } else {
        try {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
            Write-Success "  シンボリックリンクを作成しました"
            $SuccessCount.Value++
        } catch {
            Write-Error "  エラー: シンボリックリンクの作成に失敗しました"
            Write-Error "  $_"
            $ErrorCount.Value++
        }
    }
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

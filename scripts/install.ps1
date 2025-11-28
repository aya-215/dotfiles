<#
.SYNOPSIS
    dotfiles インストーラー (Windows用)

.DESCRIPTION
    シンボリックリンクを作成してdotfilesをセットアップします。
    既存のファイル/ディレクトリは自動的にバックアップされます。

    注意: 管理者権限で実行してください。

.PARAMETER Force
    確認なしで実行します

.PARAMETER DryRun
    実際の変更を行わず、実行内容のみ表示します

.EXAMPLE
    .\install.ps1
    対話形式でインストール

.EXAMPLE
    .\install.ps1 -Force
    確認なしでインストール

.EXAMPLE
    .\install.ps1 -DryRun
    実行内容のみ表示
#>

param(
    [switch]$Force,
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

# dotfilesのルートディレクトリを取得
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$DOTFILES_DIR = Split-Path -Parent $SCRIPT_DIR
$BACKUP_DIR = "$env:USERPROFILE\.dotfiles_backup"

Write-Info "===================================="
Write-Info "  dotfiles インストーラー (Windows)"
Write-Info "===================================="
Write-Info ""
Write-Info "dotfilesディレクトリ: $DOTFILES_DIR"
Write-Info "バックアップディレクトリ: $BACKUP_DIR"
Write-Info ""

# シンボリックリンク設定
$links = @(
    @{
        Source = "$DOTFILES_DIR\.config\wezterm"
        Target = "$env:USERPROFILE\.config\wezterm"
        Name = "WezTerm"
    },
    @{
        Source = "$DOTFILES_DIR\.config\nvim"
        Target = "$env:USERPROFILE\.config\nvim"
        Name = "Neovim"
    },
    @{
        Source = "$DOTFILES_DIR\PowerShell"
        Target = "$env:USERPROFILE\Documents\PowerShell"
        Name = "PowerShell"
    }
)

# 環境変数の設定
Write-Info "環境変数を確認中..."
$xdgConfigHome = "$env:USERPROFILE\.config"
$currentXdg = [System.Environment]::GetEnvironmentVariable("XDG_CONFIG_HOME", "User")

if ($currentXdg -eq $xdgConfigHome) {
    Write-Success "環境変数 XDG_CONFIG_HOME は既に設定されています: $currentXdg"
} elseif ($null -eq $currentXdg -or $currentXdg -eq "") {
    if ($DryRun) {
        Write-Info "[DryRun] 環境変数を設定: XDG_CONFIG_HOME=$xdgConfigHome"
    } else {
        [System.Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", $xdgConfigHome, "User")
        $env:XDG_CONFIG_HOME = $xdgConfigHome
        Write-Success "環境変数 XDG_CONFIG_HOME を設定しました: $xdgConfigHome"
    }
} else {
    Write-Warning "環境変数 XDG_CONFIG_HOME は既に別の値が設定されています: $currentXdg"
    Write-Warning "推奨値: $xdgConfigHome"
    if (-not $Force -and -not $DryRun) {
        $response = Read-Host "上書きしますか? (y/N)"
        if ($response -eq "y" -or $response -eq "Y") {
            [System.Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", $xdgConfigHome, "User")
            $env:XDG_CONFIG_HOME = $xdgConfigHome
            Write-Success "環境変数 XDG_CONFIG_HOME を上書きしました: $xdgConfigHome"
        } else {
            Write-Info "環境変数の設定をスキップしました"
        }
    }
}
Write-Info ""

# バックアップディレクトリの作成
if (-not $DryRun) {
    if (-not (Test-Path $BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Success "バックアップディレクトリを作成しました: $BACKUP_DIR"
    }
}

# 確認プロンプト
if (-not $Force -and -not $DryRun) {
    Write-Info "以下のシンボリックリンクを作成します:"
    Write-Info ""
    foreach ($link in $links) {
        Write-Info "  [$($link.Name)]"
        Write-Info "    $($link.Target) -> $($link.Source)"
    }
    Write-Info ""
    $response = Read-Host "よろしいですか? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Info "中止しました。"
        exit 0
    }
    Write-Info ""
}

# シンボリックリンク作成
$successCount = 0
$skipCount = 0
$errorCount = 0

foreach ($link in $links) {
    Write-Info "[$($link.Name)] 処理中..."

    $source = $link.Source
    $target = $link.Target
    $targetParent = Split-Path -Parent $target

    # ソースの存在確認
    if (-not (Test-Path $source)) {
        Write-Error "  エラー: ソースが見つかりません: $source"
        $errorCount++
        continue
    }

    # ターゲットの親ディレクトリを作成
    if (-not (Test-Path $targetParent)) {
        if ($DryRun) {
            Write-Info "  [DryRun] ディレクトリを作成: $targetParent"
        } else {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            Write-Success "  ディレクトリを作成しました: $targetParent"
        }
    }

    # 既存のターゲットをチェック
    if (Test-Path $target) {
        $item = Get-Item $target -Force

        # 既に正しいシンボリックリンクが存在する場合
        if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $source) {
            Write-Success "  スキップ: 既に正しいシンボリックリンクが存在します"
            $skipCount++
            continue
        }

        # バックアップ
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupName = "$(Split-Path -Leaf $target)_$timestamp"
        $backupPath = Join-Path $BACKUP_DIR $backupName

        if ($DryRun) {
            Write-Info "  [DryRun] バックアップ: $target -> $backupPath"
        } else {
            Move-Item -Path $target -Destination $backupPath -Force
            Write-Warning "  バックアップしました: $backupPath"
        }
    }

    # シンボリックリンク作成
    if ($DryRun) {
        Write-Info "  [DryRun] シンボリックリンク作成: $target -> $source"
        $successCount++
    } else {
        try {
            New-Item -ItemType SymbolicLink -Path $target -Target $source -Force | Out-Null
            Write-Success "  シンボリックリンクを作成しました"
            $successCount++
        } catch {
            Write-Error "  エラー: シンボリックリンクの作成に失敗しました"
            Write-Error "  $_"
            $errorCount++
        }
    }
}

# 結果サマリー
Write-Info ""
Write-Info "===================================="
Write-Info "  インストール完了"
Write-Info "===================================="
Write-Success "成功: $successCount"
if ($skipCount -gt 0) {
    Write-Info "スキップ: $skipCount"
}
if ($errorCount -gt 0) {
    Write-Error "エラー: $errorCount"
}
Write-Info ""

if ($DryRun) {
    Write-Info "[DryRun] 実際の変更は行われていません"
    Write-Info "実際にインストールするには、-DryRun オプションを外して実行してください"
} else {
    Write-Success "dotfilesのインストールが完了しました！"
    Write-Info ""
    Write-Info "次のステップ:"
    Write-Info "  1. ターミナルを再起動してください"
    Write-Info "  2. Neovimを起動してプラグインをインストール: nvim"
    Write-Info "  3. WeZTermの設定が反映されているか確認してください"
}

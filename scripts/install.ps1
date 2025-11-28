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

.PARAMETER InstallAll
    依存関係とフォントをすべて自動インストールします

.EXAMPLE
    .\install.ps1
    対話形式でインストール（dotfilesのみ）

.EXAMPLE
    .\install.ps1 -InstallAll
    依存関係とフォントをすべてインストール（推奨）

.EXAMPLE
    .\install.ps1 -Force
    確認なしでインストール

.EXAMPLE
    .\install.ps1 -DryRun
    実行内容のみ表示
#>

param(
    [switch]$Force,
    [switch]$DryRun,
    [switch]$InstallAll
)

# 共通関数を読み込み
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SCRIPT_DIR "common.ps1")

# dotfilesのルートディレクトリを取得
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
$xdgConfigHome = "$env:USERPROFILE\.config"
Set-EnvironmentVariableIfNeeded -Name "XDG_CONFIG_HOME" -Value $xdgConfigHome -Force:$Force -DryRun:$DryRun | Out-Null
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
    New-SymbolicLinkSafe `
        -Name $link.Name `
        -Source $link.Source `
        -Target $link.Target `
        -BackupDir $BACKUP_DIR `
        -DryRun:$DryRun `
        -SuccessCount ([ref]$successCount) `
        -SkipCount ([ref]$skipCount) `
        -ErrorCount ([ref]$errorCount)
}

# 結果サマリー
Show-ResultSummary -SuccessCount $successCount -SkipCount $skipCount -ErrorCount $errorCount

if ($DryRun) {
    Write-Info "[DryRun] 実際の変更は行われていません"
    Write-Info "実際にインストールするには、-DryRun オプションを外して実行してください"
} else {
    Write-Success "dotfilesのインストールが完了しました！"

    # -InstallAllが指定された場合、依存関係とフォントをインストール
    if ($InstallAll) {
        Write-Info ""
        Write-Info "===================================="
        Write-Info "  依存関係をインストール中..."
        Write-Info "===================================="
        Write-Info ""

        $dependenciesScript = Join-Path $SCRIPT_DIR "install-dependencies.ps1"
        if (Test-Path $dependenciesScript) {
            & $dependenciesScript
        } else {
            Write-Error "依存関係インストールスクリプトが見つかりません: $dependenciesScript"
        }

        Write-Info ""
        Write-Info "===================================="
        Write-Info "  フォントをインストール中..."
        Write-Info "===================================="
        Write-Info ""

        $fontsScript = Join-Path $SCRIPT_DIR "install-fonts.ps1"
        if (Test-Path $fontsScript) {
            & $fontsScript
        } else {
            Write-Error "フォントインストールスクリプトが見つかりません: $fontsScript"
        }
    } else {
        Write-Info ""
        Write-Info "次のステップ:"
        Write-Info "  1. ターミナルを再起動してください"
        Write-Info "  2. 依存関係をインストール: .\scripts\install-dependencies.ps1"
        Write-Info "  3. フォントをインストール: .\scripts\install-fonts.ps1"
        Write-Info "  4. Neovimを起動してプラグインをインストール: nvim"
        Write-Info "  5. WeZTermの設定が反映されているか確認してください"
    }
}

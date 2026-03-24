#!/usr/bin/env pwsh
# Windows dotfiles 初回セットアップスクリプト
# 使い方（リポジトリクローン済みの場合）:
#   pwsh -ExecutionPolicy Bypass -File .\bootstrap\install.ps1
#
# 使い方（初回・リポジトリ未クローンの場合）:
#   まずSSHキーを設定してから:
#   git clone git@github-aya215:aya-215/dotfiles.git $env:USERPROFILE\.dotfiles
#   cd $env:USERPROFILE\.dotfiles
#   pwsh -ExecutionPolicy Bypass -File .\bootstrap\install.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== dotfiles Windows セットアップ ===" -ForegroundColor Cyan

# dotfilesリポジトリのルートパスを解決
$dotfilesPath = Split-Path -Parent $PSScriptRoot

# wingetでchezmoiをインストール（未インストールの場合のみ）
if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    Write-Host "chezmoiをインストール中..." -ForegroundColor Yellow
    winget install twpayne.chezmoi --silent
    # PATHを更新
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
} else {
    Write-Host "chezmoi は既にインストール済みです" -ForegroundColor Green
}

# Abbrをインストール（未インストールの場合のみ）
if (-not (Get-Module -ListAvailable -Name Abbr)) {
    Write-Host "Abbrをインストール中..." -ForegroundColor Yellow
    Install-Module Abbr -Scope CurrentUser -Force
}

# chezmoiでdotfilesを適用
Write-Host "dotfilesを適用中..." -ForegroundColor Yellow
chezmoi init --source "$dotfilesPath\chezmoi" --apply

Write-Host ""
Write-Host "=== セットアップ完了！ ===" -ForegroundColor Green

# OneDrive環境チェック
$actualProfile = $PROFILE
$expectedProfile = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
if ($actualProfile -ne $expectedProfile) {
    Write-Host ""
    Write-Host "注意: PowerShell profileのパスが想定と異なります。" -ForegroundColor Yellow
    Write-Host "  実際のパス: $actualProfile"
    Write-Host "  chezmoiの配置先: $expectedProfile"
    Write-Host "  OneDriveが有効な場合、以下のコマンドでシンボリックリンクを作成してください:"
    Write-Host "  New-Item -ItemType SymbolicLink -Path `"$actualProfile`" -Target `"$expectedProfile`"" -ForegroundColor Cyan
}

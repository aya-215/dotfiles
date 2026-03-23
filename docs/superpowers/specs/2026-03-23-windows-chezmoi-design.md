# Windows dotfiles 管理設計（chezmoi導入）

## 概要

WSL側はNix/Home Managerで管理済み。Windows側（PowerShell, AutoHotkey, WezTerm, Neovim共有）をchezmoiで管理し、1リポジトリに統合する。

## 方針

| 環境 | 管理ツール | 変更 |
|------|-----------|------|
| WSL/Linux | Nix/Home Manager | なし |
| Windows native | chezmoi | 新規追加 |
| Neovim設定 | chezmoi `.chezmoitemplates/` | WSL/Windows共通化 |

## ディレクトリ構造

```
dotfiles/
├── chezmoi/                          # chezmoiソースディレクトリ（新規）
│   ├── .chezmoi.toml.tmpl            # OS判定・初期設定テンプレート
│   ├── .chezmoiignore                # OS別ファイル除外設定
│   ├── .chezmoitemplates/
│   │   └── nvim/                     # Neovim設定本体（WSL/Windows共通）
│   ├── AppData/
│   │   └── Local/nvim/               # Windows向けNeovim（テンプレート参照）
│   ├── dot_config/
│   │   ├── nvim/                     # Linux/WSL向けNeovim（テンプレート参照）
│   │   └── wezterm/                  # WezTerm設定
│   ├── Documents/
│   │   └── PowerShell/               # PowerShell profile（既存から移行）
│   └── AutoHotkey/                   # AutoHotkeyスクリプト（既存から移行）
├── bootstrap/
│   └── install.ps1                   # Windows初期セットアップスクリプト（新規）
├── modules/                          # Nix modules（変更なし）
├── flake.nix                         # Nix flake（変更なし）
└── home.nix                          # Home Manager設定（変更なし）
```

## 主要ファイル設計

### `.chezmoi.toml.tmpl`

```toml
{{- $isWSL := false }}
{{- if eq .chezmoi.os "linux" }}
  {{- if contains "microsoft" (lower .chezmoi.kernel.osrelease) }}
    {{- $isWSL = true }}
  {{- end }}
{{- end }}

[data]
  isWSL = {{ $isWSL }}
  isWindows = {{ eq .chezmoi.os "windows" }}
```

### `.chezmoiignore`

```
{{- if ne .chezmoi.os "windows" }}
AppData
Documents/PowerShell
AutoHotkey
{{- end }}
{{- if eq .chezmoi.os "windows" }}
dot_config/nvim
dot_config/wezterm
{{- end }}
```

### Neovim設定共有の仕組み

`.chezmoitemplates/nvim/` に設定ファイル本体を置き、OS別ディレクトリから参照する。
編集は `.chezmoitemplates/nvim/` のみ行えばWSL/Windows両方に反映される。

```
# AppData/Local/nvim/init.lua.tmpl（Windows向け）
{{ template "nvim/init.lua" . }}

# dot_config/nvim/init.lua.tmpl（Linux/WSL向け）
{{ template "nvim/init.lua" . }}
```

### `bootstrap/install.ps1`

```powershell
#!/usr/bin/env pwsh
# Windows初期セットアップスクリプト
# 使い方: .\bootstrap\install.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== dotfiles Windows セットアップ ===" -ForegroundColor Cyan

# 1. wingetでchezmoiをインストール
Write-Host "chezmoiをインストール中..." -ForegroundColor Yellow
winget install twpayne.chezmoi --silent

# 2. chezmoiでdotfilesを適用
$dotfilesPath = Split-Path -Parent $PSScriptRoot
Write-Host "dotfilesを適用中..." -ForegroundColor Yellow
chezmoi init --source "$dotfilesPath\chezmoi" --apply

Write-Host "セットアップ完了！" -ForegroundColor Green
```

## 既存ファイルの移行方針

| 既存パス | 移行先 | 対応 |
|---------|--------|------|
| `PowerShell/Microsoft.PowerShell_profile.ps1` | `chezmoi/Documents/PowerShell/` | 移動 |
| `AutoHotkey/AutoHotkey.ahk` | `chezmoi/AutoHotkey/` | 移動 |
| `.config/wezterm/` | `chezmoi/dot_config/wezterm/` | コピー（WSL側はNixで別管理） |
| `.config/nvim/` | `chezmoi/.chezmoitemplates/nvim/` | 移動（共通テンプレート化） |

## 推奨追加ツール

新PCセットアップ時に `install.ps1` 経由で導入を検討：

| ツール | 用途 | wingetコマンド |
|--------|------|---------------|
| **GlazeWM** | タイリングWM（i3ライクなウィンドウ管理） | `winget install glaze-wm` |
| **PSReadLine** | PowerShellキーバインド強化 | PowerShell標準モジュール |
| **Scoop** | 管理者権限不要なパッケージ管理 | bootstrap経由 |

## 実装の注意点

- `chezmoi init` は Windows 側で実行する（`%USERPROFILE%` パスが必要）
- WezTerm設定は Windows/WSL で共通化できるが、WSL側はNixで管理しているため chezmoi 側は Windows専用にする
- 既存の `PowerShell/` `AutoHotkey/` ディレクトリは移行後に削除する
- Neovim設定の `.chezmoitemplates/` 化により、既存の `.config/nvim/` はWSL側ではNixの `home.nix` でのシンボリックリンク設定が不要になる可能性あり（要確認）

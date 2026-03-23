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

Neovim設定は多数のファイルを持つため、`.chezmoitemplates/` によるファイル単位のテンプレート参照は現実的でない。代わりに以下の方針を採用する。

**方針: `run_once_` スクリプトによるシンボリックリンク作成**

chezmoiの `run_once_` スクリプトでWindows側に `AppData\Local\nvim` → `chezmoi/.chezmoitemplates/nvim/` へのシンボリックリンクを作成する。

```powershell
# chezmoi/run_once_setup-nvim-symlink.ps1.tmpl（Windowsのみ実行）
{{- if eq .chezmoi.os "windows" -}}
$nvimConfig = "$env:LOCALAPPDATA\nvim"
$source = "{{ .chezmoi.sourceDir }}\.chezmoitemplates\nvim"
if (-not (Test-Path $nvimConfig)) {
    New-Item -ItemType SymbolicLink -Path $nvimConfig -Target $source
}
{{- end -}}
```

WSL側は `neovim.nix` の `mkOutOfStoreSymlink` が `~/.dotfiles/chezmoi/.chezmoitemplates/nvim` を指すよう更新する（移行時に対応）。

### `bootstrap/install.ps1`

```powershell
#!/usr/bin/env pwsh
# Windows初期セットアップスクリプト
# 使い方: iwr https://raw.githubusercontent.com/aya-215/dotfiles/main/bootstrap/install.ps1 | iex
#      または: git clone してから .\bootstrap\install.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== dotfiles Windows セットアップ ===" -ForegroundColor Cyan

# 1. リポジトリのクローン（未クローンの場合）
$dotfilesPath = "$env:USERPROFILE\.dotfiles"
if (-not (Test-Path $dotfilesPath)) {
    Write-Host "dotfilesをクローン中..." -ForegroundColor Yellow
    git clone git@github-aya215:aya-215/dotfiles.git $dotfilesPath
}

# 2. wingetでchezmoiをインストール
Write-Host "chezmoiをインストール中..." -ForegroundColor Yellow
winget install twpayne.chezmoi --silent

# 3. chezmoiでdotfilesを適用
Write-Host "dotfilesを適用中..." -ForegroundColor Yellow
chezmoi init --source "$dotfilesPath\chezmoi" --apply

Write-Host "セットアップ完了！" -ForegroundColor Green
```

## 既存ファイルの移行方針

| 既存パス | 移行先 | 対応 |
|---------|--------|------|
| `PowerShell/Microsoft.PowerShell_profile.ps1` | `chezmoi/Documents/PowerShell/` | 移動 |
| `PowerShell/Modules/` | `chezmoi/Documents/PowerShell/Modules/` | 移動（PSFzf等のモジュール） |
| `PowerShell/kubectl_completion.ps1` | `chezmoi/Documents/PowerShell/` | 移動 |
| `AutoHotkey/AutoHotkey.ahk` | `chezmoi/AutoHotkey/` | 移動 |
| `config/wezterm/` | `chezmoi/dot_config/wezterm/` | コピー（WSL側はNixで別管理） |
| `config/nvim/` | `chezmoi/.chezmoitemplates/nvim/` | 移動（共通テンプレート化）、`neovim.nix`のパスも更新 |

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
- Neovim設定を `chezmoi/.chezmoitemplates/nvim/` に移動後、`modules/neovim.nix` の `mkOutOfStoreSymlink` のパスを `~/.dotfiles/chezmoi/.chezmoitemplates/nvim` に更新すること
- OneDriveが有効な環境では `Documents/PowerShell/` パスが `OneDrive\Documents\PowerShell\` になる場合がある。その場合はchezmoi適用後にPowerShell profileのパスを確認すること（`$PROFILE` で確認可能）
- 初回セットアップ時はSSHキー設定が先に必要（`github-aya215` エイリアスを使用）。SSHキーがない場合は `install.ps1` のgit cloneをHTTPS URLに変更すること

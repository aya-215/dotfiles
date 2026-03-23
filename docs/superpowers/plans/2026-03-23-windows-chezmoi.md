# Windows chezmoi導入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows側のdotfiles（PowerShell, AutoHotkey, WezTerm, Neovim設定共有）をchezmoiで管理し、既存の1リポジトリに統合する。

**Architecture:** WSL側はNix/Home Manager管理を維持しつつ、`chezmoi/` サブディレクトリをchezmoiソースディレクトリとして追加する。Neovim設定は `chezmoi/.chezmoitemplates/nvim/` に移動し、`run_once_` スクリプトでWindows側にシンボリックリンクを作成。WSL側は `neovim.nix` のパスを更新して共有する。

**Tech Stack:** chezmoi, PowerShell 7+, winget, Nix/Home Manager

---

## 前提条件（作業開始前に確認）

- [ ] **管理者権限のPowerShell（pwsh）**で実行すること（シンボリックリンク作成に必要）
  - または Windows Developer Mode を有効にすること（設定 → プライバシーとセキュリティ → 開発者向け）
- [ ] `git` がWindowsにインストール済みであること（`git --version` で確認）
- [ ] SSHキー（`github-aya215` エイリアス）がWindowsに設定済みであること。未設定の場合はHTTPS cloneに切り替えること

---

## Task 1: WSL側 — chezmoiディレクトリ構造の作成と設定ファイルの追加

> WSL上で作業する。Nix管理ファイルには触らない。

**Files:**
- Create: `chezmoi/.chezmoi.toml.tmpl`
- Create: `chezmoi/.chezmoiignore`

- [ ] **Step 1: `chezmoi/` ディレクトリを作成する**

```bash
mkdir -p /home/aya/.dotfiles/chezmoi
```

- [ ] **Step 2: `.chezmoi.toml.tmpl` を作成する**

`/home/aya/.dotfiles/chezmoi/.chezmoi.toml.tmpl` に以下の内容で作成：

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

- [ ] **Step 3: `.chezmoiignore` を作成する**

`/home/aya/.dotfiles/chezmoi/.chezmoiignore` に以下の内容で作成：

```
# Windows専用ファイル（Linux/WSLでは無視）
{{- if ne .chezmoi.os "windows" }}
AppData
Documents/PowerShell
AutoHotkey
{{- end }}
# WezTerm設定はWindowsのみchezmoi管理（WSL側はNixで管理）
# dot_config/wezterm はWindowsでのみ適用、Linuxでは無視
{{- if ne .chezmoi.os "windows" }}
dot_config/wezterm
{{- end }}
```

> **注意:** `dot_config/nvim` は存在しない（Neovimは `run_once_` スクリプトでシンボリックリンクを作成するため、chezmoiソースには置かない）

- [ ] **Step 4: コミット**

```bash
cd /home/aya/.dotfiles
git add chezmoi/
git commit -m "feat: chezmoiディレクトリと設定ファイルを追加"
git push
```

---

## Task 2: WSL側 — Neovim設定を `.chezmoitemplates/nvim/` に移動

> この作業でWSL側のNeovim設定パスが変わる。`neovim.nix` の更新も同時に行う。

**Files:**
- Move: `config/nvim/` → `chezmoi/.chezmoitemplates/nvim/`
- Modify: `modules/neovim.nix`

- [ ] **Step 1: `.chezmoitemplates/nvim/` ディレクトリを作成してNeovim設定を移動する**

```bash
mkdir -p /home/aya/.dotfiles/chezmoi/.chezmoitemplates
mv /home/aya/.dotfiles/config/nvim /home/aya/.dotfiles/chezmoi/.chezmoitemplates/nvim
```

- [ ] **Step 2: `neovim.nix` のシンボリックリンクパスを更新する**

`/home/aya/.dotfiles/modules/neovim.nix` の以下の行を編集：

変更前：
```nix
home.file.".config/nvim".source =
  config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.dotfiles/config/nvim";
```

変更後：
```nix
home.file.".config/nvim".source =
  config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.dotfiles/chezmoi/.chezmoitemplates/nvim";
```

- [ ] **Step 3: Home Managerを再適用してWSL側のNeovimが動くか確認する**

```bash
cd /home/aya/.dotfiles
home-manager switch --flake .
```

期待結果: エラーなし。`ls -la ~/.config/nvim` がシンボリックリンクになっており、`nvim` で起動できること。

- [ ] **Step 4: コミット**

```bash
git add chezmoi/.chezmoitemplates/ modules/neovim.nix
git commit -m "feat: Neovim設定をchezmoitemplatesに移動しneovim.nixパスを更新"
git push
```

---

## Task 3: WSL側 — PowerShell・AutoHotkey・WezTerm設定をchezmoiに移行

> 既存の `PowerShell/` `AutoHotkey/` を `chezmoi/` 配下に移動する。

**Files:**
- Move: `PowerShell/` → `chezmoi/Documents/PowerShell/`
- Move: `AutoHotkey/` → `chezmoi/AutoHotkey/`
- Copy: `config/wezterm/` → `chezmoi/dot_config/wezterm/`

- [ ] **Step 1: PowerShell設定を移動する**

> `secrets.ps1` は `.gitignore` 対象のため移動しない（ローカルに残す）。
> `Modules/` はサードパーティモジュールだが、将来の自動インストール移行まで一旦chezmoi管理にする。

```bash
mkdir -p /home/aya/.dotfiles/chezmoi/Documents/PowerShell
mv /home/aya/.dotfiles/PowerShell/Microsoft.PowerShell_profile.ps1 \
   /home/aya/.dotfiles/chezmoi/Documents/PowerShell/
mv /home/aya/.dotfiles/PowerShell/kubectl_completion.ps1 \
   /home/aya/.dotfiles/chezmoi/Documents/PowerShell/
mv /home/aya/.dotfiles/PowerShell/Modules \
   /home/aya/.dotfiles/chezmoi/Documents/PowerShell/Modules
# secrets.ps1は.gitignore対象のため移動せず残す（手動で新PCにコピーする）
ls /home/aya/.dotfiles/PowerShell/  # secrets.ps1のみ残っていることを確認
```

- [ ] **Step 2: AutoHotkey設定を移動する**

```bash
mkdir -p /home/aya/.dotfiles/chezmoi/AutoHotkey
mv /home/aya/.dotfiles/AutoHotkey/AutoHotkey.ahk \
   /home/aya/.dotfiles/chezmoi/AutoHotkey/
rmdir /home/aya/.dotfiles/AutoHotkey
```

- [ ] **Step 3: WezTerm設定をコピーする（WSL側はNixで管理を継続するためコピー）**

> WezTermは `.config/wezterm/`（`.`付き）が実際のパス。`.env` は `.gitignore` 対象のためコピーしない。
> **注意:** WezTerm設定を変更した場合、`.config/wezterm/`（WSL用）と `chezmoi/dot_config/wezterm/`（Windows用）の両方を更新すること。

```bash
mkdir -p /home/aya/.dotfiles/chezmoi/dot_config/wezterm
# .envを除外してコピー
rsync -av --exclude='.env' \
      /home/aya/.dotfiles/.config/wezterm/ \
      /home/aya/.dotfiles/chezmoi/dot_config/wezterm/
```

- [ ] **Step 4: コミット**

```bash
cd /home/aya/.dotfiles
git add chezmoi/ PowerShell/ AutoHotkey/
git commit -m "feat: PowerShell・AutoHotkey・WezTermをchezmoi配下に移行"
git push
```

---

## Task 4: WSL側 — Neovim用 `run_once_` スクリプトを作成

> Windows側でchezmoi apply時にシンボリックリンクを自動作成するスクリプト。

**Files:**
- Create: `chezmoi/run_once_setup-nvim-symlink.ps1.tmpl`

- [ ] **Step 1: `run_once_` スクリプトを作成する**

`/home/aya/.dotfiles/chezmoi/run_once_setup-nvim-symlink.ps1.tmpl` に以下の内容で作成：

```powershell
{{- if eq .chezmoi.os "windows" -}}
# Neovim設定のシンボリックリンクを作成（AppData\Local\nvim → chezmoi source の nvim）
$nvimConfig = "$env:LOCALAPPDATA\nvim"
$source = "{{ .chezmoi.sourceDir }}\.chezmoitemplates\nvim"

if (Test-Path $nvimConfig) {
    Write-Host "既存のNeovim設定が見つかりました: $nvimConfig"
    Write-Host "スキップします。手動で確認してください。"
} else {
    New-Item -ItemType SymbolicLink -Path $nvimConfig -Target $source
    Write-Host "Neovimシンボリックリンクを作成しました: $nvimConfig -> $source"
}
{{- end -}}
```

- [ ] **Step 2: コミット**

```bash
cd /home/aya/.dotfiles
git add chezmoi/run_once_setup-nvim-symlink.ps1.tmpl
git commit -m "feat: Windows向けNeovimシンボリックリンク作成スクリプトを追加"
git push
```

---

## Task 5: WSL側 — bootstrap/install.ps1 を作成

> 新PC初回セットアップ用スクリプト。

**Files:**
- Create: `bootstrap/install.ps1`

- [ ] **Step 1: `bootstrap/` ディレクトリと `install.ps1` を作成する**

```bash
mkdir -p /home/aya/.dotfiles/bootstrap
```

`/home/aya/.dotfiles/bootstrap/install.ps1` に以下の内容で作成：

```powershell
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
```

- [ ] **Step 2: コミット**

```bash
cd /home/aya/.dotfiles
git add bootstrap/install.ps1
git commit -m "feat: Windows初回セットアップスクリプトを追加"
git push
```

---

## Task 6: Windows側 — chezmoiを初回適用する

> ここからWindowsのPowerShell（pwsh）で作業する。

- [ ] **Step 1: リポジトリをクローンする（未クローンの場合）**

SSHキーが設定済みの場合:
```powershell
git clone git@github-aya215:aya-215/dotfiles.git $env:USERPROFILE\.dotfiles
```

SSHキー未設定の場合（HTTPS）:
```powershell
git clone https://github.com/aya-215/dotfiles.git $env:USERPROFILE\.dotfiles
```

- [ ] **Step 2: install.ps1 を実行する**

```powershell
cd $env:USERPROFILE\.dotfiles
pwsh -ExecutionPolicy Bypass -File .\bootstrap\install.ps1
```

期待結果: エラーなし。以下が確認できること：
- `$env:APPDATA\..\Local\nvim` がシンボリックリンクになっている
- `$PROFILE` のパスにPowerShell profileが存在する

- [ ] **Step 3: 動作確認**

```powershell
# PowerShell profileが読み込まれているか確認
. $PROFILE

# Neovimが起動するか確認
nvim --version

# シンボリックリンクの確認
Get-Item "$env:LOCALAPPDATA\nvim" | Select-Object LinkType, Target
```

期待結果:
- PowerShellプロンプトが正常に動作する
- nvimが起動する
- `LinkType: SymbolicLink` で正しいTargetが表示される

- [ ] **Step 4: OneDrive環境の場合はPowerShell profileパスを確認**

```powershell
$PROFILE
# 出力例: C:\Users\368\OneDrive\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
# chezmoiが配置した場所と異なる場合、手動でコピーまたはシンボリックリンクを作成する
```

---

## Task 7: WSL側 — README.md にセットアップ手順を追記

> 将来の自分や新PC時のために手順を残す。

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README.md にWindows向けセットアップ手順を追記する**

`/home/aya/.dotfiles/README.md` の末尾（または適切なセクション）に以下を追記：

```markdown
## Windows セットアップ

### 前提条件
- Windows 11 + PowerShell 7+ (pwsh)
- winget が使えること
- SSHキー（github-aya215 エイリアス）が設定済みであること

### 手順

1. **SSHキーを設定する**（初回のみ）
2. **リポジトリをクローンする**
   ```powershell
   git clone git@github-aya215:aya-215/dotfiles.git $env:USERPROFILE\.dotfiles
   ```
3. **bootstrap スクリプトを実行する**
   ```powershell
   cd $env:USERPROFILE\.dotfiles
   pwsh -ExecutionPolicy Bypass -File .\bootstrap\install.ps1
   ```

### 管理対象ファイル

| ファイル | Windowsパス |
|---------|------------|
| PowerShell profile | `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |
| AutoHotkey | `%USERPROFILE%\AutoHotkey\AutoHotkey.ahk` |
| WezTerm | `%USERPROFILE%\.config\wezterm\` |
| Neovim | `%LOCALAPPDATA%\nvim\`（シンボリックリンク） |

### 設定を更新するとき

```powershell
cd $env:USERPROFILE\.dotfiles
chezmoi apply --source .\chezmoi
```

### WezTerm設定を変更するとき

WezTerm設定は2箇所に存在する（WSL/Windows二重管理）。**両方を更新すること：**
- WSL用: `~/.dotfiles/.config/wezterm/`
- Windows用: `~/.dotfiles/chezmoi/dot_config/wezterm/`
```

- [ ] **Step 2: コミット**

```bash
cd /home/aya/.dotfiles
git add README.md
git commit -m "docs: Windows chezmoiセットアップ手順をREADMEに追記"
git push
```

---

## Task 8: WSL側 — PowerShell profileにpwsh-abbrを追加

> zsh側のzeno.zshと同等のabbreviation機能をPowerShellに導入する。

**Files:**
- Modify: `PowerShell/Microsoft.PowerShell_profile.ps1`
- Modify: `bootstrap/install.ps1`（Task 5で作成済み）

- [ ] **Step 1: `bootstrap/install.ps1` に `Install-Module pwsh-abbr` を追加する**

Task 5で作成した `bootstrap/install.ps1` の `chezmoi init` の前に以下を追加：

```powershell
# pwsh-abbrをインストール（未インストールの場合のみ）
if (-not (Get-Module -ListAvailable -Name pwsh-abbr)) {
    Write-Host "pwsh-abbrをインストール中..." -ForegroundColor Yellow
    Install-Module pwsh-abbr -Scope CurrentUser -Force
}
```

- [ ] **Step 2: PowerShell profileの末尾にabbr設定を追加する**

`PowerShell/Microsoft.PowerShell_profile.ps1` の末尾に以下を追加：

```powershell
# ======================
# Abbreviations (pwsh-abbr)
# スペース/Enterで展開される（zsh zeno.zsh相当）
# ======================
if (Get-Module -ListAvailable -Name pwsh-abbr) {
    Import-Module pwsh-abbr

    # Git（既存fzf関数との重複を回避）
    # gs=git stash fzf関数、ga=git add fzf関数、gco=git checkout fzf関数のため別名使用
    New-Abbreviation -Name gst  -Value 'git status'
    New-Abbreviation -Name gd   -Value 'git diff'
    New-Abbreviation -Name gp   -Value 'git push'
    New-Abbreviation -Name gpl  -Value 'git pull'
    New-Abbreviation -Name gcm  -Value 'git commit -m'
    New-Abbreviation -Name gaa  -Value 'git add -A'

    # chezmoi
    New-Abbreviation -Name cza  -Value 'chezmoi apply --source .\chezmoi'
    New-Abbreviation -Name czd  -Value 'chezmoi diff --source .\chezmoi'

    # ナビゲーション
    New-Abbreviation -Name ..   -Value 'cd ..'
    New-Abbreviation -Name ...  -Value 'cd ../..'
}
```

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
git add PowerShell/Microsoft.PowerShell_profile.ps1 bootstrap/install.ps1
git commit -m "feat: PowerShell profileにpwsh-abbrを追加"
git push
```

---

## 完了チェックリスト

- [ ] WSL側でNeovimが正常に起動する（`nvim` コマンド）
- [ ] Windows側でNeovimが正常に起動する（シンボリックリンク経由）
- [ ] Windows側でPowerShell profileが読み込まれる
- [ ] Windows側でAutoHotkeyスクリプトが配置される
- [ ] Windows側でWezTerm設定が配置される
- [ ] `bootstrap/install.ps1` で新PCセットアップが一発で完了する
- [ ] Windows側で `gst` + スペースが `git status ` に展開される（pwsh-abbr動作確認）

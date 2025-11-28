# dotfiles

個人用dotfiles管理リポジトリ

## 構成

```
dotfiles/
├── .config/
│   ├── wezterm/    # WezTerm設定
│   └── nvim/       # Neovim設定
├── PowerShell/     # PowerShell設定
│   ├── Microsoft.PowerShell_profile.ps1  # プロファイル
│   ├── kubectl_completion.ps1            # kubectl補完
│   ├── Modules/                          # モジュール
│   └── Scripts/                          # スクリプト
├── scripts/        # インストールスクリプト
│   └── install.ps1                       # Windows用インストーラー
├── .gitignore
└── README.md
```

## セットアップ手順

### Windows

#### 方法1: 自動インストール（推奨）

**前提条件**: 管理者権限でPowerShellを実行

##### クイックスタート（依存関係も含めて一括インストール）

```powershell
# 1. リポジトリをクローン
cd D:\git
git clone git@github.com:aya-215/dotfiles.git

# 2. インストールスクリプトを実行（依存関係も含む）
cd dotfiles
.\scripts\install.ps1 -InstallDependencies
```

##### dotfilesのみインストール（依存関係は手動）

```powershell
# 1. リポジトリをクローン
cd D:\git
git clone git@github.com:aya-215/dotfiles.git

# 2. dotfilesのみインストール
cd dotfiles
.\scripts\install.ps1

# 3. 後から依存関係をインストール
.\scripts\install-dependencies.ps1
```

**インストーラーが自動的に実行すること:**
- 環境変数 `XDG_CONFIG_HOME` の設定
- シンボリックリンクの作成（WezTerm、Neovim、PowerShell）
- 既存ファイルのバックアップ（`~/.dotfiles_backup`に保存）
- 依存関係のインストール（`-InstallDependencies`指定時）
  - fzf、Neovim
  - PowerShellモジュール（PSFzf、ZLocation、BurntToast）
  - フォント（HackGen Nerd Font）※Chocolateyが必要

**その他のオプション:**
```powershell
# 実行内容を確認（実際の変更は行わない）
.\scripts\install.ps1 -DryRun
.\scripts\install-dependencies.ps1 -DryRun

# 確認なしで実行
.\scripts\install.ps1 -Force

# PowerShellモジュールのみスキップ
.\scripts\install-dependencies.ps1 -SkipModules

# フォントのみスキップ
.\scripts\install-dependencies.ps1 -SkipFonts
```

#### 方法2: 手動セットアップ

**前提条件**: 開発者モードを有効化（シンボリックリンクに管理者権限不要にするため）

##### 1. 環境変数の設定（Neovim用）

Windowsではデフォルトで`.config`ディレクトリを使用しないため、環境変数の設定が必要です。

1. `Win + R` → `sysdm.cpl` → `Enter`
2. 「詳細設定」タブ → 「環境変数」
3. ユーザー環境変数で「新規」
   - 変数名: `XDG_CONFIG_HOME`
   - 変数値: `C:\Users\<ユーザー名>\.config`（例: `C:\Users\368\.config`）
4. `OK` → PowerShellを再起動

##### 2. リポジトリをクローン

```powershell
cd D:\git
git clone git@github.com:aya-215/dotfiles.git
```

##### 3. シンボリックリンクを作成

```powershell
# WezTerm
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\wezterm" -Target "D:\git\dotfiles\.config\wezterm"

# Neovim
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\nvim" -Target "D:\git\dotfiles\.config\nvim"

# PowerShell
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\Documents\PowerShell" -Target "D:\git\dotfiles\PowerShell"
```

### macOS / Linux

#### 1. リポジトリをクローン

```bash
cd ~
git clone git@github.com:aya-215/dotfiles.git
```

#### 2. シンボリックリンクを作成

```bash
# WezTerm
ln -s ~/dotfiles/.config/wezterm ~/.config/wezterm

# Neovim
ln -s ~/dotfiles/.config/nvim ~/.config/nvim

# PowerShell（macOSの場合）
ln -s ~/dotfiles/PowerShell ~/.config/powershell
```

## 日常の使い方

### 設定を編集

どちらの場所で編集してもOK:
```bash
# パターン1: 実環境側で編集
nvim ~/.config/nvim/init.lua

# パターン2: dotfiles側で編集
cd ~/dotfiles
nvim .config/nvim/init.lua
```

### 変更をコミット

```bash
cd ~/dotfiles  # Windows: D:\git\dotfiles
git add .
git commit -m "設定を更新"
git push
```

## PowerShell設定の詳細

### 主な機能

- **超高速起動**: 遅延読み込み機構により、起動時間を最小化
- **fzf統合**: ファイル、ディレクトリ、Gitブランチなどの検索をfzfで実行
- **ZLocation**: ディレクトリジャンプ機能（`zf`または`Ctrl+D`）
- **kubectl補完**: Kubernetes操作の補完（初回使用時に自動読み込み）
- **WezTerm統合**: OSC 7シーケンスによるカレントディレクトリ通知

### 便利なエイリアス

```powershell
vim/vi/v → nvim    # Neovim起動
c        → claude  # Claude Code起動
cc       → claude -c  # Claude Code（会話モード）
cr       → claude -r  # Claude Code（リソース指定）
```

### fzf機能

| コマンド | 説明 | キーバインド |
|---------|------|-------------|
| `zf` / `zi` | ZLocation履歴からディレクトリ選択 | `Ctrl+D` |
| `gb` | Gitブランチを選択してチェックアウト | - |
| `fn` | ファイルを選択してnvimで開く | - |
| `fd` | ディレクトリを選択して移動 | - |
| `fe` | ファイルを選択してVS Codeで開く | - |
| `ga` | Gitステージングファイルを選択 | - |
| `gl` | Gitログを選択 | - |
| `gco` | コミットを選択してチェックアウト | - |
| `gs` | Gitスタッシュを選択して適用 | - |
| `pk` | プロセスを選択して終了 | - |
| `fenv` | 環境変数を検索 | - |
| `falias` | エイリアスを検索 | - |
| - | ファイル検索（パスを挿入） | `Ctrl+F` |
| - | コマンド履歴検索 | `Ctrl+R` |

### 必要な依存関係

プロファイルは以下のツールに依存していますが、遅延読み込みにより存在しなくてもエラーになりません:

```powershell
# 必須
winget install fzf
winget install neovim

# 推奨（PowerShellモジュール）
Install-Module PSFzf -Scope CurrentUser
Install-Module ZLocation -Scope CurrentUser
Install-Module BurntToast -Scope CurrentUser

# 推奨（フォント）
choco install font-hackgen-nerd  # WezTerm/Neovim用

# オプション
winget install kubectl  # Kubernetes使用時のみ
```

**一括インストール:**
```powershell
# すべて自動インストール（推奨）
.\scripts\install-dependencies.ps1
```

### 遅延読み込み機構

プロファイルは以下のモジュールを初回使用時のみ読み込むことで、起動時間を最小化しています:

- **PSFzf**: fzf関連機能を最初に使用した時
- **ZLocation**: `zf`コマンドまたは`Ctrl+D`を初めて押した時
- **kubectl補完**: `kubectl`コマンドを初めて実行した時

この仕組みにより、PowerShellの起動は通常0.5秒以下で完了します。

## 注意事項

- `.claude/settings.local.json`は`.gitignore`で除外しています
- シンボリックリンクは双方向で動作します（どちらから編集しても同じファイル）
- シンボリックリンク削除時は`Remove-Item`（Windows）または`rm`（Mac/Linux）で安全に削除できます
- Windows環境では`XDG_CONFIG_HOME`環境変数の設定が必須です
- PowerShellモジュールは必須ではありませんが、インストールすることで全機能が使えます

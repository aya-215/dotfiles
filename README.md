# dotfiles

個人用dotfiles管理リポジトリ - Nix/Home Manager による宣言的な環境構築

## 概要

このリポジトリは、WSL/Linux環境を **Nix Flakes + Home Manager** で宣言的に管理します。

### 主な特徴

- **宣言的管理**: `flake.nix`と`home.nix`で環境を定義
- **再現可能**: 同じ設定から同じ環境を構築可能
- **モジュール構成**: 機能ごとに分離された設定ファイル
- **自動シンボリックリンク**: Home Managerが設定ファイルを自動配置

## 構成

```
dotfiles/
├── flake.nix              # Nix Flake設定（エントリーポイント）
├── home.nix               # Home Manager メイン設定
├── modules/               # Nixモジュール（機能別）
│   ├── packages.nix      # インストールするパッケージ一覧
│   ├── git.nix           # Git設定
│   ├── zsh.nix           # Zsh設定（エイリアス、関数、プラグイン）
│   ├── starship.nix      # Starship設定
│   ├── lazygit.nix       # Lazygit設定
│   ├── neovim.nix        # Neovim設定
│   ├── nb.nix            # nb（ノート管理）設定
│   └── zeno.nix          # Zeno（スニペット/補完）設定
├── config/                # 設定ファイルのソース（Nixが管理）
│   ├── nvim/             # Neovim設定
│   ├── lazygit/          # Lazygit設定
│   ├── starship/         # Starship設定
│   ├── nb/               # nb関数（タスク管理・日報）
│   └── zeno/             # Zeno設定（スニペット定義）
├── .config/               # 実際の設定ファイル配置先
│   ├── nvim/             # → Home Managerがシンボリックリンク作成
│   ├── wezterm/          # WezTerm設定（手動管理）
│   ├── lazygit/          # → Home Managerがシンボリックリンク作成
│   └── starship.toml     # → Home Managerがシンボリックリンク作成
├── docs/                  # ドキュメント
│   └── nix-guide/        # Nix学習ガイド
├── PowerShell/            # PowerShell設定（Windows用）
│   ├── Modules/          # PowerShellモジュール
│   └── Scripts/          # PowerShellスクリプト
├── AutoHotkey/            # AutoHotkey設定（Windows用キーバインド）
├── scripts/               # 各種スクリプト
│   ├── setup/            # セットアップスクリプト
│   ├── backup/           # バックアップスクリプト
│   └── claude-sync/      # Claude同期ツール
├── .claude/               # Claude Code プロジェクト設定
├── .claude-global/        # Claude Code グローバルルール
└── README.md
```

## セットアップ手順

### WSL/Linux (推奨)

Nix/Home Managerを使用した宣言的セットアップ。

#### 1. Nixのインストール

```bash
# Nixインストール（マルチユーザーモード）
sh <(curl -L https://nixos.org/nix/install) --daemon

# インストール後、シェルを再起動
exec $SHELL
```

#### 2. Flakesを有効化

```bash
# Nix設定ディレクトリを作成
mkdir -p ~/.config/nix

# Flakes機能を有効化
cat > ~/.config/nix/nix.conf <<EOF
experimental-features = nix-command flakes
EOF
```

#### 3. dotfilesをクローン

```bash
cd ~
git clone git@github.com:aya-215/dotfiles.git .dotfiles
cd .dotfiles
```

#### 4. Home Managerで環境を構築

```bash
# Home Managerでシステムを構築（初回）
nix run home-manager/master -- switch --flake .

# 設定変更後の適用
home-manager switch --flake .
```

#### 5. WezTerm設定のシンボリックリンク作成（必要な場合）

```bash
# WeztermはHome Manager管理外なので手動でリンク
ln -s ~/.dotfiles/.config/wezterm ~/.config/wezterm
```

#### セットアップで自動的にインストールされるもの

- **CLIツール**: ripgrep, fd, fzf, bat, eza, jq, lazygit, zoxide, nb, delta, ghq, gh
- **開発ツール**: fnm, deno, bun, python3, pipx
- **Nix開発**: nixpkgs-fmt, statix, nil
- **Zshプラグイン**: Oh My Zsh, you-should-use, zsh-autosuggestions, fast-syntax-highlighting
- **設定ファイル**: Neovim, Zsh, Git, Starship, Lazygit, nb, zeno

---

### Windows

Windows向けセットアップ（PowerShell、WezTerm、Neovim等）。

詳細な手順は [`scripts/setup/`](scripts/setup/) を参照してください。

#### クイックスタート

```powershell
# 管理者権限のPowerShellで実行
cd D:\git
git clone git@github.com:aya-215/dotfiles.git
cd dotfiles
.\scripts\install.ps1 -InstallAll
```

**インストールされるもの:**
- シンボリックリンク（WezTerm、Neovim、PowerShell）
- fzf、Neovim
- PowerShellモジュール（PSFzf、ZLocation、BurntToast）
- HackGen Nerd Font

**オプション:**
```powershell
.\scripts\install.ps1 -DryRun      # 実行内容確認
.\scripts\install.ps1 -Force       # 確認なしで実行
```

詳細は [scripts/setup/README.md](scripts/setup/README.md) を参照。

---

## 日常の使い方

### 設定を編集

```bash
# 設定ファイルを編集（どちらでもOK）
nvim ~/.config/nvim/init.lua       # 実環境側
nvim ~/.dotfiles/config/nvim/init.lua  # dotfiles側

# Nixモジュールを編集
nvim ~/.dotfiles/modules/zsh.nix
```

### 変更を適用

```bash
cd ~/.dotfiles

# Home Managerで変更を適用
home-manager switch --flake .

# 変更をコミット
git add .
git commit -m "設定を更新"
git push
```

### パッケージを追加

```bash
# 1. modules/packages.nixを編集
nvim ~/.dotfiles/modules/packages.nix

# 2. パッケージを追加
# home.packages = with pkgs; [
#   新しいパッケージ名
# ];

# 3. 変更を適用
home-manager switch --flake .
```

---

## 主な機能

### 1. Zsh設定

#### エイリアス

```bash
# エディタ
vim/vi/v → nvim    # Neovim起動
c        → claude  # Claude Code起動

# バックアップ
bak      → ~/.dotfiles/scripts/backup/backup-wsl-to-windows.sh

# eza (ls代替)
ls       → eza --icons --group-directories-first
ll       → eza -l --icons --group-directories-first --git
la       → eza -la --icons --group-directories-first --git
lt       → eza --tree --level=2 --icons
lta      → eza --tree --level=2 --icons -a
lg       → eza -l --icons --group-directories-first --git --git-ignore

# npm
npmd     → npm run dev -- -H 0.0.0.0
npms     → npm run storybook -- --host 0.0.0.0
```

#### fzf関数

| コマンド | 説明 | キーバインド |
|---------|------|-------------|
| `fn` | ファイル検索→nvim | - |
| `fd` | ディレクトリ検索→cd | - |
| `fe` | ファイル検索→VS Code | - |
| `fbr` | Gitブランチ切替 | - |
| `fga` | Git add（複数選択） | - |
| `fgl` | Gitログ閲覧 | - |
| `fgco` | コミットcheckout | - |
| `fgs` | スタッシュ管理 | - |
| `pk` | プロセスkill | - |
| `fenv` | 環境変数閲覧 | - |
| `falias` | エイリアス閲覧 | - |
| `gj` | ghqリポジトリ選択→cd | `Ctrl+F` |

#### zeno.zsh（スニペット/補完エンジン）

高速なスニペット展開と補完機能。

**キーバインド:**
- `Ctrl+Space`: スニペット自動展開
- `Tab`: 補完
- `Ctrl+R`: 履歴検索（zeno版）
- `Ctrl+X` `Ctrl+S`: スニペット挿入

**設定ファイル:** `config/zeno/config.yml`

#### プラグイン

- **you-should-use**: エイリアスを使うべき時に通知
- **zsh-autosuggestions**: コマンド履歴から自動提案
- **fast-syntax-highlighting**: 高速シンタックスハイライト

### 2. nb（ノート管理）

CLIベースのノート・タスク管理ツール。

#### 基本コマンド

```bash
nb                  # ノート一覧
nb add              # ノート追加
nb edit 123         # ノート編集
nb show 123         # ノート表示
nb search "keyword" # 検索
```

#### カスタム関数（config/nb/functions.zsh）

```bash
nb-task-add         # タスク追加
nb-task-list        # タスク一覧
nb-task-done        # タスク完了
nb-daily            # 日報作成
nb-daily-view       # 日報閲覧
```

### 3. Neovim設定

- **プラグイン管理**: lazy.nvim
- **LSP**: nvim-lspconfig + Mason
- **補完**: nvim-cmp
- **Git統合**: gitsigns.nvim
- **ファイラー**: neo-tree.nvim

設定詳細: [config/nvim/README.md](config/nvim/README.md)

### 4. lazygit（Git TUI）

対話的なGit操作UI。

#### 起動

```bash
lazygit
```

#### diff表示切り替え

`|`キーで3つのモードを切り替え:

1. **通常表示**: コンパクトな差分
2. **side-by-side表示**: 左右2画面
3. **詳細表示**: side-by-side + クリック可能な行番号

#### 主なキーバインド

| キー | 動作 |
|------|------|
| `|` | diff表示モード切り替え |
| `?` | ヘルプ表示 |
| `1-5` | パネル切り替え |
| `space` | ステージング/アンステージング |
| `c` | コミット |
| `P` | プッシュ |
| `p` | プル |
| `q` | 終了 |

### 5. Starship（プロンプト）

高速でカスタマイズ可能なプロンプト。

設定ファイル: `config/starship/starship.toml`

---

## インストールされるパッケージ

Nix/Home Managerで自動的にインストールされるパッケージ一覧（`modules/packages.nix`で管理）。

### CLIツール

| ツール | 説明 |
|-------|------|
| ripgrep | 高速grep（`rg`） |
| fd | 高速find |
| fzf | ファジーファインダー |
| bat | cat代替（シンタックスハイライト） |
| eza | ls代替（モダン） |
| jq | JSON処理 |
| lazygit | Git TUI |
| zoxide | スマートcd |
| nb | ノート管理 |
| delta | Git diff viewer |
| ghq | リポジトリ管理 |
| gh | GitHub CLI |
| gcalcli | Googleカレンダー |
| wslu | WSL utilities（wslview等） |

### 開発ツール

| ツール | 説明 |
|-------|------|
| fnm | Node.jsバージョン管理 |
| deno | Deno JavaScript runtime |
| bun | Bun JavaScript runtime |
| python3 | Python 3.x |
| pipx | Pythonツール管理 |

### Nix開発

| ツール | 説明 |
|-------|------|
| nixpkgs-fmt | フォーマッタ |
| statix | Linter |
| nil | LSP |

---

## PowerShell設定（Windows）

### 主な機能

- **超高速起動**: 遅延読み込み機構
- **fzf統合**: ファイル、ディレクトリ、Gitブランチ検索
- **ZLocation**: ディレクトリジャンプ（`zf`または`Ctrl+D`）
- **kubectl補完**: 初回使用時に自動読み込み
- **WezTerm統合**: OSC 7によるディレクトリ通知

### エイリアス

```powershell
vim/vi/v → nvim    # Neovim起動
c        → claude  # Claude Code起動
cc       → claude -c  # 会話モード
cr       → claude -r  # リソース指定
```

### fzf関数

| コマンド | 説明 | キーバインド |
|---------|------|-------------|
| `zf` / `zi` | ZLocation履歴からディレクトリ選択 | `Ctrl+D` |
| `gb` | Gitブランチ選択→チェックアウト | - |
| `fn` | ファイル選択→nvim | - |
| `fd` | ディレクトリ選択→移動 | - |
| `fe` | ファイル選択→VS Code | - |
| `ga` | Gitステージング | - |
| `gl` | Gitログ | - |
| `gco` | コミット選択→チェックアウト | - |
| `gs` | スタッシュ選択→適用 | - |
| `pk` | プロセス選択→終了 | - |
| `fenv` | 環境変数検索 | - |
| `falias` | エイリアス検索 | - |
| - | ファイル検索（パス挿入） | `Ctrl+F` |
| - | コマンド履歴検索 | `Ctrl+R` |

詳細: [PowerShell/README.md](PowerShell/README.md)

---

## トラブルシューティング

### Home Managerの更新

```bash
# Home Managerチャンネルを更新
nix flake update

# 最新版で再構築
home-manager switch --flake .
```

### 設定の初期化

```bash
# Home Manager管理の設定を削除
rm -rf ~/.config/nvim ~/.config/lazygit ~/.config/starship.toml

# 再適用
home-manager switch --flake .
```

### Nixストアのクリーンアップ

```bash
# 古い世代を削除
nix-collect-garbage -d

# 特定の世代を残す
nix-collect-garbage --delete-older-than 30d
```

---

## 参考資料

- [Nix公式ドキュメント](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix学習ガイド（このリポジトリ内）](docs/nix-guide/)

---

## 注意事項

- `.claude/settings.local.json`は`.gitignore`で除外
- Home Managerがシンボリックリンクを自動管理（`.config/`配下）
- WezTerm設定は手動でシンボリックリンク作成が必要
- Windows環境では`XDG_CONFIG_HOME`環境変数の設定が必須
- Nix管理外のツール（WezTerm等）は手動セットアップ

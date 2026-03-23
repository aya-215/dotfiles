# Phase 2: Shell/スクリプト品質改善

## 目的

`shell-conventions.md` に定義された規約（ドキュメントコメント必須・エラーハンドリング等）をスクリプトに適用し、品質を統一する。コメントはすべて日本語で記述する。

## 対象ファイル一覧

| ファイル | 問題点 | 優先度 |
|---|---|---|
| `.config/zsh/functions.zsh` | 全関数にドキュメントコメントなし | 高 |
| `scripts/nb-sync.sh` | `cd` 失敗時のエラーハンドリングなし、ドキュメント不足 | 高 |
| `scripts/claude-prompt.sh` | ファイルヘッダーコメントなし | 中 |
| `PowerShell/Microsoft.PowerShell_profile.ps1` | 21関数にドキュメントコメントなし | 中 |

---

## 変更内容

### 1. `.config/zsh/functions.zsh`（238行）

各関数の直前に日本語の説明コメントを追加する。形式：

```zsh
# 関数名 - 機能の説明
function_name() {
  ...
}
```

対象関数一覧（全16関数）：

| 関数名 | 説明 |
|---|---|
| `zi` | zoxide + fzf でディレクトリ移動 |
| `gj` | ghq管理リポジトリをfzfで選択してcd |
| `fn` | fzfでファイル選択してNeovimで開く |
| `fd` | fzfでディレクトリ選択してcd |
| `fe` | fzfでファイル選択して$EDITORで開く |
| `fbr` | fzfでGitブランチ選択してcheckout |
| `fga` | fzfでGit管理ファイルを選択 |
| `fgl` | fzfでGitログを選択して表示 |
| `fgco` | fzfでGitコミット選択してcheckout |
| `fgs` | fzfでGit stashを選択してpop |
| `pk` | fzfでプロセス選択してkill |
| `tms` | fzfでtmuxセッション選択・作成 |
| `tsw` | fzfでtmuxウィンドウ選択 |
| `tsd` | tmuxセッション削除 |
| `yy` | yaziを起動し、終了後にcwdへ移動 |
| `gw3` / `gw3off` | Windows共有ドライブのマウント・アンマウント |

### 2. `scripts/nb-sync.sh`（23行）

**問題1: ファイルヘッダーコメントなし**

追加するヘッダー：
```bash
# nb-sync.sh - nbリポジトリをGitHubと同期するスクリプト
# 使用方法: ./nb-sync.sh
# 前提条件: nb が初期化済みで $NB_DIR が設定されていること
```

**問題2: `cd` 失敗時にスクリプトが続行する**

```bash
# 修正前
cd "$NB_DIR"

# 修正後
cd "$NB_DIR" || { echo "エラー: $NB_DIR に移動できません" >&2; exit 1; }
```

### 3. `scripts/claude-prompt.sh`（15行）

ファイルヘッダーコメントを追加：

```bash
# claude-prompt.sh - Claude Code定期プロンプト実行スクリプト
# 使用方法: このスクリプトはcronまたはtmuxから自動実行される
# 環境変数: CLAUDECODE が設定されていること
```

### 4. `PowerShell/Microsoft.PowerShell_profile.ps1`（252行）

各関数の直前にPowerShell形式のドキュメントコメントを追加：

```powershell
# 関数名 - 機能の説明
function FunctionName {
  ...
}
```

主要21関数すべてに追加する。

---

## 作業手順

```bash
# 1. 各ファイルを編集（Neovimで開いてコメント追加）
nvim ~/.dotfiles/.config/zsh/functions.zsh
nvim ~/.dotfiles/scripts/nb-sync.sh
nvim ~/.dotfiles/scripts/claude-prompt.sh
nvim ~/.dotfiles/PowerShell/Microsoft.PowerShell_profile.ps1

# 2. ShellCheckで静的解析
shellcheck ~/.dotfiles/scripts/nb-sync.sh
shellcheck ~/.dotfiles/scripts/claude-prompt.sh

# 3. zsh関数の動作確認（zshを再起動して確認）
source ~/.zshrc
type zi  # 関数が読み込まれていることを確認
```

## 検証

- `shellcheck` がエラーなしで通ること
- zsh再起動後に各関数が正常に動作すること
- nb-sync.sh を存在しないディレクトリで実行してエラーが出ることを確認

## 完了後

```bash
git add .config/zsh/functions.zsh scripts/nb-sync.sh scripts/claude-prompt.sh PowerShell/Microsoft.PowerShell_profile.ps1
git commit -m "chore: シェルスクリプト・関数のドキュメントコメントとエラーハンドリング追加"
git push
```

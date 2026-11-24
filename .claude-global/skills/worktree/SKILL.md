---
name: worktree
description: Git worktreeの作成・削除を対話的に行う
allowed-tools: Bash(git:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(npm install:*), Bash(pnpm install:*), Bash(yarn install:*), Bash(bun install:*), Bash(ls:*), Bash(pwd:*), Bash(head:*), Bash(cp:*), Bash(find:*), Bash(mkdir:*), Bash(python3 ~/.claude/skills/worktree/scripts/worktree_scan.py:*), Bash(python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py:*), AskUserQuestion
version: 1.1.0
---

# Git Worktree 管理コマンド

## 引数

- $1: 操作 (add または rm)
- $2: ブランチ名

## 実行手順

### 1. ユーザーへの質問（最初にまとめて行う）

引数が不足している場合、必要最小限のコマンドを実行し、AskUserQuestionで情報を収集する。
**質問はできるだけまとめて一度に行い、ユーザーの待ち時間を最小化すること。**

**$1, $2 両方が指定されていない場合:**
1. 質問に必要な情報を取得:
   - `git fetch --prune` (リモートの最新情報を取得＋削除済みリモートブランチを整理)
   - `git branch -r --sort=-committerdate` (ブランチ一覧)
   - `git worktree list` (worktree一覧)
   - rm時は下記「不要 worktree の検出」のスクリプトを実行する
2. AskUserQuestionで以下を**一度に**質問:
   - 操作 (add / rm)
   - ブランチ名（addの場合: リモートブランチ上位5個 + 新規作成、rmの場合: 下記「rm選択肢の作成」参照）

**$1 のみ指定されている場合:**
- add: `git fetch --prune` を実行後、`git branch -r --sort=-committerdate` を実行し、ブランチを質問
- rm: 下記「不要 worktree の検出」のスクリプトを実行し、削除対象を質問

**add のブランチ選択肢の作成:**
- 結果から HEAD を除外し、`origin/` プレフィックスを除去して最大5個を提示
- 「新しいブランチを作成」オプションも追加 → 選択されたら手動入力

**不要 worktree の検出（rm 時）:**

rm はカレントリポジトリに限らず、**全リポジトリの worktree** を対象にする。判定はスクリプトが決定的に行い、Claude は判定し直さない:

```bash
python3 ~/.claude/skills/worktree/scripts/worktree_scan.py          # 人が読む一覧
python3 ~/.claude/skills/worktree/scripts/worktree_scan.py --json   # 削除手順で使う詳細
```

- 対象: `ghq list -p` と `~/worktrees/*` から逆引きした本体リポジトリ（本体が `/mnt/d` 等にあっても拾う）。スクリプトは `git fetch --prune` 以外に何も変更しない
- `--no-size` でサイズ計測を省略、`--no-fetch` で fetch を省略できる
- 判定の要点（詳細はスクリプト冒頭の docstring）:
  - 取り込み済み = PR が MERGED、または HEAD が `origin/main`（無ければ `origin/master`）の祖先。ローカル `main` や `[gone]` 表示は使わない（ローカル main の遅れ・追跡先が origin/main のブランチで誤判定するため）
  - 祖先でも、そのブランチで一度もコミットしていない（reflog が作成時のみ）ものは「未着手」として外す
  - PR が OPEN のものは取り込み済みにしない
  - `AGENTS.md`（next dev が再生成）と `package-lock.json`（npm install が書き換え）だけの変更は「作業中」に数えず、「再生成ファイル変更」として別に出す
  - `gh` が使えない・GitHub 以外のリモート（GitBucket 等）は PR 判定なしで動く。PR 取得失敗と出たら `gh auth switch` して再実行

**分類**（スクリプトの `category`）:
- **まとめ削除候補** = `merged`（取り込み済み かつ 追跡ファイルの未コミット変更なし。未追跡 `??` と再生成ファイル変更は許容し、削除時に破棄されることを明示する）
- `dirty`（作業中）・`unstarted`（未着手）・`open`（未マージ）・`closed`（PR CLOSED）は個別選択のみ
- `prunable`（ディレクトリ消失）は `git -C <repo> worktree prune` で掃除する候補
- `locked` は触らない

**rm 選択肢の作成:**
- スクリプトの一覧をリポジトリ別に番号付きで表示する（AskUserQuestion の選択肢は4つまでなので、worktree を選択肢に並べない）
- AskUserQuestion の選択肢:
  1. 不要 worktree（取り込み済み）をまとめて削除 (N件) — 質問文に対象の worktree 名を列挙する
  2. 番号を指定して削除 — 「Other」で番号を入力してもらう
  3. prunable を掃除 (N件) — 該当があるときだけ
  4. 何もしない
- 表示例:
  ```
  ## ebase-portal-chat
   1. feat/976-conversation-image-persist — 取り込み済み / PR#1112 MERGED / リモートなし / 1.8G
   2. feat/985-maintenance-vehicle-grouping — 未マージ / PR#1160 OPEN / 再生成ファイル変更: apps/portal-ui/AGENTS.md
  ## eb-api-extended (/mnt/d/tomcat/webapps/eb-api-extended)
   3. feat/976-conversation-image — 取り込み済み / PR#123 MERGED / リモートなし
  ```

### 2. コンテキスト取得と事前確認

質問への回答を得た後、以下のコマンドを実行してコンテキストを取得（add のみ。rm はスクリプトの `--json` 出力を使い、カレントディレクトリに依存しない）:

1. `git rev-parse --show-toplevel` - gitリポジトリか確認（失敗したらエラー終了）
2. `git fetch --prune` - リモートの最新情報を取得＋削除済みリモートブランチを整理
3. `git branch --show-current` - 現在のブランチ
4. `git worktree list` - 既存のworktree一覧
5. `ls package.json pnpm-lock.yaml yarn.lock bun.lockb 2>/dev/null` - パッケージマネージャー判定用

### 3. 置き場所とブランチ名

置き場所とブランチ名は `~/.dotfiles/scripts/claude-worktree/worktree_hook.py` が決める（Claude Code の `claude -w` のフックと同じ決まり。詳細は `docs/superpowers/specs/2026-11-24-claude-worktree-hooks-design.md`）。Claude は決め直さない。

- 置き場所: `<本体>/.claude/worktrees/<スラッグ>`。本体が `/mnt/` の下なら `~/worktrees/<本体のフォルダ名>-<スラッグ>`（スラッグはブランチ名の `/` を `-` にしたもの）
- ブランチ: 既にあれば開く／`feat/`・`fix/` 等で始まればそのまま／個人リポジトリならそのまま／それ以外は `feat/<名前>`
- 名前は英数字・`.`・`_`・`-`・`/` だけ。日本語のブランチ名が決まりのリポジトリ（hankyu・pilot の GitBucket）は英数字で作り、push 前に `git -C <worktree> branch -m <決まりの名前>` で直す

### 5. 操作の実行

#### add (作成) の場合:

1. 作る:
   ```bash
   python3 -I ~/.dotfiles/scripts/claude-worktree/worktree_hook.py create --name <ブランチ名> --cwd <本体>
   ```
   - stdout の最後の行が worktree のパス。`.env.local`・`.env.keys` のコピーと、npm なら node_modules のハードリンクまで済んでいる（stderr に出る）
   - 失敗したら stderr の理由をそのまま伝える（例: そのブランチが別の場所で使用中）

2. 依存関係のインストール（スクリプトはしない）:
   - 本体に `package.json` があればロックファイルでパッケージマネージャーを決め、worktree にインストール:
     - `pnpm-lock.yaml` → `pnpm install --prefix <worktree-path>`
     - `yarn.lock` → `yarn install --cwd <worktree-path>`
     - `bun.lockb` → `bun install --cwd <worktree-path>`
     - それ以外（npm） → `npm install --prefix <worktree-path>`（node_modules はハードリンク済みなので差分だけ入る。`npm ci` は node_modules を丸ごと消すので使わない）

3. 成功メッセージ: 作成した worktree のパス、`cd` の例、消し方（`/worktree rm`）

#### rm (削除) の場合:

対象には `claude -w` が作った `<本体>/.claude/worktrees/*` と `~/worktrees/*`（`/mnt/` の本体の分）、前の置き場所 `../<略称>-<ブランチ>` が全部入る（`git worktree list` で拾う）。

対象ごとの `repo`（本体リポジトリのパス）・`path`・`branch` はスクリプトの `--json` 出力から取る。git 操作はすべて `git -C <repo>` で行い、カレントディレクトリに依存しない。本体が `/mnt/` 配下（Tomcat が直接読む eb-api-extended・hankyu 等）でも、worktree の削除とブランチ削除は本体の作業ツリーに触れない。本体側で checkout・pull はしない。

##### 番号を指定して削除した場合

1. 対象の状態を表示:
   - スクリプトの判定結果（分類・PR・リモート実在・未コミット変更・再生成ファイル変更・未追跡）
   - 追跡ファイルの変更がある場合は `git -C <path> status --porcelain` で中身を表示し、警告を強調
   - `git -C <path> stash list`（stash はリポジトリ全体で共有され worktree 削除では消えない。表示のみ）
2. AskUserQuestion で削除確認
3. 確認後に削除:
   - `git -C <repo> worktree remove <path>`（未コミット変更・未追跡・再生成ファイル変更がある場合は `--force` が必要。破棄してよいか確認済みのときのみ付与）
   - ブランチ削除（detached の worktree はブランチ削除なし）:
     - `category` が `merged`: `git -C <repo> branch -D <branch>`（`-d` はローカル main 基準で誤判定するため使わない）
     - それ以外: `git -C <repo> branch -d <branch>` を試行し、失敗したら警告して `-D` するか確認
   - リモートにブランチが残っている場合は通知し、`git -C <repo> push origin --delete <branch>` するか**別途確認**する（デフォルトでは削除しない）
4. 成功メッセージを表示

##### 「不要 worktree（取り込み済み）をまとめて削除」を選択した場合

対象は `category` が `merged` のもの。

1. 状態一覧を表示（未追跡ファイル・再生成ファイル変更が破棄されること、リモートにブランチが残っているものを明示）
2. AskUserQuestion で最終確認
3. 確認後にまとめて削除:
   - 未追跡ファイルか再生成ファイル変更があるもの: `git -C <repo> worktree remove --force <path>`、なければ `--force` なし
   - その後 `git -C <repo> branch -D <branch>`（detached はなし）
4. リモートに残っているブランチがあれば一覧で通知し、リモート削除するか**別途まとめて確認**する（デフォルトでは削除しない）
5. 削除結果のサマリーを表示

##### 「prunable を掃除」を選択した場合

該当する各リポジトリで `git -C <repo> worktree prune -v` を実行し、結果を表示する。

## エラーハンドリング

- gitリポジトリでない場合（add のみ）: エラーメッセージを表示して終了
- worktree作成先が既に存在する場合: 警告して確認
- 削除対象が存在しない場合: エラーメッセージを表示

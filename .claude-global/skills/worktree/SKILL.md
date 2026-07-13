---
name: worktree
description: Git worktreeの作成・削除を対話的に行う
allowed-tools: Bash(git:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(npm install:*), Bash(pnpm install:*), Bash(yarn install:*), Bash(bun install:*), Bash(ls:*), Bash(pwd:*), Bash(head:*), Bash(cp:*), Bash(find:*), Bash(mkdir:*), AskUserQuestion
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
   - rm時は下記「不要ブランチの検出」に従い、worktreeを持つ各ブランチの取り込み済み判定を行う
2. AskUserQuestionで以下を**一度に**質問:
   - 操作 (add / rm)
   - ブランチ名（addの場合: リモートブランチ上位5個 + 新規作成、rmの場合: 下記「rm選択肢の作成」参照）

**$1 のみ指定されている場合:**
- add: `git fetch --prune` を実行後、`git branch -r --sort=-committerdate` を実行し、ブランチを質問
- rm: `git fetch --prune` → `git worktree list` → 下記「不要ブランチの検出」を実行し、削除対象を質問

**add のブランチ選択肢の作成:**
- 結果から HEAD を除外し、`origin/` プレフィックスを除去して最大5個を提示
- 「新しいブランチを作成」オプションも追加 → 選択されたら手動入力

**不要ブランチの検出（rm 時の判定ロジック）:**

> **背景**: `git branch -vv` の `[origin/...: gone]` だけに頼ると検出漏れが起きる。`gone` は「**追跡先として設定したリモートブランチ**が消えたか」しか見ず、追跡先が `origin/main` 等に向いているブランチは、同名リモートが削除済みでも検出できない。また `git log main..<branch>` や `git branch -d` はローカル `main` 基準でマージ判定するため、ローカル `main` が `origin/main` より遅れていると取り込み済みでも「未マージ」と誤判定する。そのため **`origin/main` 基準の「取り込み済み」判定を主軸**にする。

ベースブランチを決定（`origin/main` があれば使用、なければ `origin/master`。以下 `<base>` と表記）。worktree を持つ各ブランチ（メイン worktree を除く）について以下を判定する:

1. **取り込み済み判定（一次・必須）**: `git merge-base --is-ancestor <branch> <base>` が真（= `git log <base>..<branch> --oneline` が空）なら「`<base>` に取り込み済み」。
2. **PR裏取り（GitHub かつ `gh` 利用可時のみ）**: 一次判定が真でも偽でも、`gh pr list --head <branch> --state all --json number,state,url --limit 1` で PR番号・状態を取得。`MERGED` であれば squash/rebase merge で一次判定が偽になるケースも「取り込み済み」と扱える。`gh` が無い・リモートが `github.com` でない場合はこのステップを省略し、一次判定のみで動作する（`git remote -v` で確認）。
3. **リモート実在確認**: `git ls-remote --heads origin <branch>` の出力有無で、リモートにブランチが残っているか判定（候補表示に併記する。`gone` 表示の穴を塞ぐ）。
4. **未コミット変更確認**: `git -C <worktree-path> status --porcelain` の出力を確認。`M`/`A`/`D` 等の**追跡ファイルの変更がある**ものは作業中とみなす。`??`（未追跡）のみは「未追跡あり」として扱う。

**分類**:
- **まとめ削除候補** = 「取り込み済み（一次 or PRマージ済み）」かつ「追跡ファイルの未コミット変更なし」（未追跡 `??` のみは許容）。
- **取り込み済みだが追跡ファイルに未コミット変更あり** → まとめ削除候補から**外し**、個別選択肢として残す（作業を誤って消さないため）。

**rm 選択肢の作成:**
- 既存 worktree（メイン worktree を除く）を個別選択肢として列挙
- 「まとめ削除候補」が1件以上あれば「不要ブランチ（取り込み済み）をまとめて削除 (N件)」を選択肢に追加
- 各選択肢には判定結果を併記する（PR番号/状態・リモート実在・未コミット変更の有無）
- 選択肢の表示例:
  ```
  1. feat/some-feature (worktree: ../epc-feat-some-feature) — 未マージ・作業中
  2. fix/bug-123 (worktree: ../epc-fix-bug-123) — PR#42 MERGED・リモート削除済み・クリーン
  3. 不要ブランチ（取り込み済み）をまとめて削除 (3件)
  ```

### 2. コンテキスト取得と事前確認

質問への回答を得た後、以下のコマンドを実行してコンテキストを取得:

1. `git rev-parse --show-toplevel` - gitリポジトリか確認（失敗したらエラー終了）
2. `git fetch --prune` - リモートの最新情報を取得＋削除済みリモートブランチを整理
3. `git branch --show-current` - 現在のブランチ
4. `git worktree list` - 既存のworktree一覧
5. `ls package.json pnpm-lock.yaml yarn.lock bun.lockb 2>/dev/null` - パッケージマネージャー判定用

### 3. ディレクトリ名の生成

リポジトリ名から略称を生成する。コマンドは使わず、以下の規則に従って略称を決定:

**規則**: リポジトリ名をハイフン `-` で分割し、各単語の頭文字を連結する

| リポジトリ名 | 略称 |
|-------------|------|
| `claude-code` | `cc` |
| `ebase-portal-chat` | `epc` |
| `my-awesome-app` | `maa` |
| `api` | `a` |

worktreeディレクトリは `../<略称>-<ブランチ名>` の形式にする。
**ブランチ名に `/` が含まれる場合は `-` に置換する。**

例:
- `feature-auth` → `../epc-feature-auth`
- `feat/41-implementation-page-layout` → `../epc-feat-41-implementation-page-layout`
- `fix/bug-123` → `../epc-fix-bug-123`

### 5. 操作の実行

#### add (作成) の場合:

1. ブランチが既に存在するか確認:
   ```bash
   git show-ref --verify --quiet refs/heads/<branch-name>
   ```

2. ブランチの存在に応じて実行:
   - **存在する場合**: `git worktree add ../<略称>-<ブランチ名> <ブランチ名>`
   - **存在しない場合**: ベースブランチを決定してから作成
     - `origin/main` が存在すれば使用、なければ `origin/master` を使用
     - `git worktree add ../<略称>-<ブランチ名> -b <ブランチ名> <ベースブランチ>`

3. worktree作成成功後、依存関係のインストール:
   - 現在のディレクトリに `package.json` が存在するか確認: `ls package.json`
   - 存在する場合、現在のディレクトリのロックファイルを確認: `ls pnpm-lock.yaml yarn.lock bun.lockb 2>/dev/null | head -1`
   - パッケージマネージャーを決定し、`--prefix` などで worktree にインストール:
     - `pnpm-lock.yaml` があれば → `pnpm install --prefix <worktree-path>`
     - `yarn.lock` があれば → `yarn install --cwd <worktree-path>`
     - `bun.lockb` があれば → `bun install --cwd <worktree-path>`
     - それ以外 → `npm install --prefix <worktree-path>`

4. 環境設定ファイルのコピー（モノレポ対応）:
   - リポジトリ内の `.env.local` と `.env.keys` ファイルを検索: `find . \( -name '.env.local' -o -name '.env.keys' \) -type f 2>/dev/null`
   - 見つかった各ファイルについて、同じ相対パスで新しいworktreeにコピー:
     - 相対パスからディレクトリ部分を抽出し、worktree内に同じディレクトリ構造を作成
     - 例: `./apps/portal-ui/.env.local` → `<worktree-path>/apps/portal-ui/.env.local`
     - 例: `./.env.keys` → `<worktree-path>/.env.keys`
     - コマンド例: `cp --parents ./apps/portal-ui/.env.local <worktree-path>/` または `mkdir -p` + `cp`
   - コピーした場合は、コピーしたファイルの相対パスをユーザーに通知

5. 成功メッセージと次のステップを表示:
   - 作成したworktreeのパス
   - `cd` コマンドの例
   - 削除方法の案内

#### rm (削除) の場合:

##### 既存 worktree を選択した場合

1. 対象のworktreeの状態を表示:
   - `git -C <worktree-path> status --porcelain` で未コミット変更一覧
   - `git -C <worktree-path> stash list` でstash一覧（**stash はリポジトリ全体で共有されるため、worktree削除では消えない**点に注意。表示するが削除判断材料には含めない）
   - 上記「不要ブランチの検出」の判定結果（取り込み済みか・PR状態・リモート実在）
2. 状態一覧を表示して AskUserQuestion で削除確認（追跡ファイルの未コミット変更がある場合は警告を強調）
3. 確認後に削除:
   - `git worktree remove <worktree-path>`（追跡ファイルの未コミット変更/未追跡ファイルがある場合は `--force` が必要。破棄してよいか確認済みのときのみ付与）
   - ブランチ削除はマージ状態に応じて分岐:
     - **`<base>` に取り込み済み（一次 or PRマージ済み）と確認できている場合**: `git branch -D <branch>` で削除（`git branch -d` はローカル `main` 基準で誤判定するため使わない）
     - **取り込み済みが確認できない場合**: `git branch -d <branch>` を試行し、失敗（未マージ）したら警告して `git branch -D` するか確認
   - リモートにブランチが残っている場合（`git ls-remote` で確認済み）: 「リモートにもブランチが残っています」と通知し、リモート削除（`git push origin --delete <branch>`）するか**別途確認**する（デフォルトでは削除しない）
4. 成功メッセージを表示

##### 「不要ブランチ（取り込み済み）をまとめて削除」を選択した場合

対象は「不要ブランチの検出」で**まとめ削除候補**に分類されたブランチ（取り込み済み かつ 追跡ファイルの未コミット変更なし）。

1. 各ブランチについて状態を表示（判定は `main` ではなく **`<base>`（= `origin/main`）基準**）:
   - worktree がある場合: `git -C <worktree-path> status --porcelain` で未追跡ファイル（`??`）の有無
   - 取り込み確認の根拠: 一次判定（`git log <base>..<branch>` が空）か、PR番号・MERGED状態
   - リモート実在: `git ls-remote --heads origin <branch>` の結果
   - 表示例:
     ```
     ## fix/old-feature (worktree: ../epc-fix-old-feature)
     取り込み済み: PR#42 MERGED / origin/main に取り込み済み
     リモート: 削除済み
     未追跡ファイル: docs/temp.md（worktree削除で破棄される）

     ## fix/resolved-bug (worktree: ../epc-fix-resolved-bug)
     取り込み済み: origin/main に取り込み済み（PRなし）
     リモート: ⚠️ まだ残っている
     未追跡ファイル: なし
     ```
2. 状態一覧を表示して AskUserQuestion で最終確認（未追跡ファイルが破棄される場合・リモートが残っている場合は明示）
3. 確認後にまとめて削除:
   - 未追跡ファイルがある worktree: 破棄してよいか確認した上で `git worktree remove --force <path>`、なければ `git worktree remove <path>`
   - その後 `git branch -D <branch>`（取り込み確認済みのため `-D` で安全）
   - worktree がないブランチ: `git branch -D <branch>`
4. リモートに残っているブランチがあれば一覧で通知し、リモート削除（`git push origin --delete <branch>`）するか**別途まとめて確認**する（デフォルトでは削除しない）
5. 削除結果のサマリーを表示

## エラーハンドリング

- gitリポジトリでない場合: エラーメッセージを表示して終了
- worktree作成先が既に存在する場合: 警告して確認
- 削除対象が存在しない場合: エラーメッセージを表示

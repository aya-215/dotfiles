---
name: worktree
description: Git worktreeの作成・削除を対話的に行う
allowed-tools: Bash(git:*), Bash(npm install:*), Bash(pnpm install:*), Bash(yarn install:*), Bash(bun install:*), Bash(ls:*), Bash(pwd:*), Bash(head:*), Bash(cp:*), Bash(find:*), Bash(mkdir:*), AskUserQuestion
version: 1.0.0
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
   - `git fetch origin` (リモートの最新情報を取得)
   - `git branch -r --sort=-committerdate` (ブランチ一覧)
   - `git worktree list` (worktree一覧)
2. AskUserQuestionで以下を**一度に**質問:
   - 操作 (add / rm)
   - ブランチ名（addの場合: リモートブランチ上位5個 + 新規作成、rmの場合: 既存worktree）

**$1 のみ指定されている場合:**
- add: `git fetch origin` を実行後、`git branch -r --sort=-committerdate` を実行し、ブランチを質問
- rm: `git worktree list` を実行し、削除対象を質問

**ブランチ選択肢の作成:**
- 結果から HEAD を除外し、`origin/` プレフィックスを除去して最大5個を提示
- 「新しいブランチを作成」オプションも追加 → 選択されたら手動入力

### 2. コンテキスト取得と事前確認

質問への回答を得た後、以下のコマンドを実行してコンテキストを取得:

1. `git rev-parse --show-toplevel` - gitリポジトリか確認（失敗したらエラー終了）
2. `git fetch origin` - リモートの最新情報を取得
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

1. 対象のworktreeディレクトリに未コミットの変更がないか確認:
   ```bash
   git -C <worktree-path> status --porcelain
   ```

2. 未コミットの変更がある場合、警告を表示してAskUserQuestionで続行するか確認

3. worktreeを削除:
   ```bash
   git worktree remove <worktree-path>
   ```

4. 成功メッセージを表示

## エラーハンドリング

- gitリポジトリでない場合: エラーメッセージを表示して終了
- worktree作成先が既に存在する場合: 警告して確認
- 削除対象が存在しない場合: エラーメッセージを表示

---
name: update-pr-body
description: Use when new commits have been added to a PR branch and the PR body needs to be updated to reflect them. Triggers on "PR本文更新", "PRの説明更新", "コミット追加後にPR更新", "update PR body", "PR body が古い".
allowed-tools: Bash, Read, Grep, AskUserQuestion
version: 1.0.0
---

# PR本文更新

新しいコミットが追加されたPRの本文を、既存フォーマットを維持したまま更新するスキル。

## 引数

$ARGUMENTS

- PR番号のみ: `123`
- PR番号＋リポジトリ: `123 owner/repo`
- 引数なし: カレントブランチのPRを自動検出。見つからなければAskUserQuestionで確認

## Iron Law

```
必ずPR本文を読んでフォーマットを把握してから更新案を作れ。
未反映コミット特定後は必ず詳細diffを見てから更新内容を決めろ。
既存のフォーマットを変えるな。AIの補完・推測を入れるな。
```

## Step 0: リモート判定・PR情報特定

```bash
git remote -v
```

| リモートURL | 使うツール |
|---|---|
| `github.com` | `gh` コマンド |
| 社内GitBucket URL | `mcp__gitbucket__*` ツール |

引数からPR番号・リポジトリを取得する。不足している場合はAskUserQuestionで確認する。

カレントブランチのPRを自動検出する場合：
```bash
gh pr view --json number,title
```

## Step 1: PR本文とコミット履歴を取得

```bash
# GitHub の場合
gh pr view <PR番号> --json title,body,baseRefName,headRefName

# ブランチの全コミット取得
git log origin/<base>..<head> --oneline
```

GitBucketの場合は `mcp__gitbucket__gitbucket_get_pr` でPR情報を取得する。

**ここで必ずPR本文を読んでフォーマットを把握すること。**
- セクション構成
- 言語（日本語 / 英語）
- 箇条書きスタイル
- コミット記載の形式

## Step 2: 未反映コミットの特定

`git log` で取得したコミット一覧とPR本文の記載内容を比較し、本文に反映されていないコミットを特定する。

判断基準: PR本文に該当コミットの内容（メッセージまたは変更内容）が記載されていない場合、未反映とみなす。

## Step 3: 未反映コミットの詳細diff取得

未反映コミットが1件以上ある場合、それぞれの詳細diffを取得する：

```bash
git show <SHA>
```

diffの内容を把握してから更新内容を決める。コミットメッセージだけで判断しない。

未反映コミットが0件の場合は「本文はすでに最新です」とユーザーに報告して終了する。

## Step 4: 更新案の生成

**厳守ルール：**
1. Step 1で把握したフォーマットを完全に維持する（セクション・言語・スタイル）
2. diffから読み取った変更内容のみを反映する
3. AIによる補完・推測・追記は一切しない
4. 既存の記述は変更しない（追記のみ）

更新前後の本文を並べて提示する。

## Step 5: ユーザーに確認

AskUserQuestionで確認する：
- このまま更新する
- 修正してから更新（修正内容を記述）
- キャンセル

## Step 6: PR本文を更新

### GitHub の場合

```bash
gh pr edit <PR番号> --body "$(cat <<'EOF'
（更新後の本文全体）
EOF
)"
```

別リポジトリの場合は `--repo owner/repo` を追加する。

### GitBucket の場合

GitBucketのMCPにはPR本文更新ツールがないため、更新後の本文をユーザーに提示してブラウザからの手動更新を案内する：

```
GitBucketのPR本文はMCPで更新できないため、以下の内容をブラウザからコピーしてください：
[PR URL]

--- 更新後の本文 ---
（本文内容）
```

## gh CLI Reference

```bash
# PR概要（本文含む）
gh pr view <PR番号> --json title,body,baseRefName,headRefName

# カレントブランチのPR
gh pr view --json number,title,body,baseRefName,headRefName

# PR本文を更新
gh pr edit <PR番号> --body "..."
```

認証エラーが出た場合は `gh auth switch` でアカウントを切り替える。

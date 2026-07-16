---
name: hunk-review
description: Use when the user wants to review any diff (working tree, commit, branch) interactively via a live Hunk TUI session. Triggers on "/hunk-review", "hunkでレビュー", "hunkで見て", "この差分をhunkで".
allowed-tools: Bash, Read, Grep, AskUserQuestion
version: 1.0.0
---

# hunk 連携レビュー（汎用）

hunkの生きたTUIセッションに接続し、任意のdiff（作業ツリー・commit・ブランチ間）を
ユーザーと一緒にレビューするスキル。PR文脈に限定しない軽量な入口。

## 連携手順の実体

**まず必ず** `review-pr/references/hunk-session.md` を読むこと。
接続フロー・ナビゲート・コメント・承認ガード・既知エラーの全手順はそこに集約されている。

（絶対パス: `/home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md`）

## 大原則

- **Claudeは `hunk diff` / `hunk show` を自分で実行しない。** TUIはユーザーが開く
- `navigate` は自由・`comment add`/`apply` は付けたら報告・`clear`/`rm` は承認必須

## フロー

### Step 1: セッション接続

`hunk session list --json` で確認。無ければ、ユーザーに開き方を案内して待つ:

- 作業ツリー全体: `hunk diff`（dotfiles等では `! hunk diff`）
- mainとの差分: `hunk diff main`
- ブランチの変更だけ（PR相当）: `hunk diff main...HEAD`
- 特定コミット: `hunk show HEAD~1`

「開いた」と言われたら再度 `hunk session list` で接続する。

### Step 2: 構造把握

`hunk session review --repo . --json` でファイル／hunk構造を把握する。
生diffが必要なファイルだけ `--include-patch` を追加。

### Step 3: レビュー先導

ユーザーの関心・変更の重要度に沿って:

1. `hunk session navigate` で該当箇所へ画面を動かす
2. 気づいた点を `hunk session comment add --focus` で添える（付けたら報告）
3. 複数まとめて付けるなら `comment apply --stdin` のbatch

一番わかりやすい順序で進める（ファイル順に縛られない）。全hunkにコメントせず、
ユーザーが自力で気づきにくい点を強調する。

### Step 4: まとめ

見終わったらレビュー内容を要約する。破壊的なコメント削除が要るなら承認を取る。

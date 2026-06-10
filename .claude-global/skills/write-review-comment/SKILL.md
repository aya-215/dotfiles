---
name: write-review-comment
description: Use when the user has finished reviewing a PR and needs to write a review comment. Triggers on "レビューコメント書いて", "Approveコメント作成", "Request Changesのコメント", "PRにコメント書きたい".
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion
version: 1.0.0
---

# PRレビューコメント作成

レビュー済みPRに対するコメント文章を生成し、`gh pr review`で投稿するスキル。
上司のPR向けに丁寧・控えめなトーンで書く。

## 重要な制約

- Step 4 のユーザー確認は絶対にスキップしない。コメント本文を一度も提示せずに投稿するのは禁止
- レビュー種別（Approve / Request Changes）・重大度タグ（Critical / Important / Nit 等）は AI が独断で決めず、必ずユーザーに確認する

## 引数

$ARGUMENTS

- PR番号のみ: `234`
- PR番号＋リポジトリ: `234 owner/repo`
- 引数なし: カレントブランチのPRを自動検出。見つからなければAskUserQuestionで確認

## ワークフロー

### Step 1: PR情報の自動取得

```bash
# PRメタ情報
gh pr view <PR番号> --json title,body,number,baseRefName,headRefName

# 変更の概要（git diffで取得）
git diff origin/<base>..HEAD --stat

# コミット履歴
git log origin/<base>..HEAD --oneline
```

認証エラーが出た場合は `gh auth switch` でアカウントを切り替える。

取得した情報から以下を整理し、ユーザーに簡潔に提示する：
- PR番号・タイトル
- 変更ファイル数・行数
- 主な変更領域

### Step 2: ユーザーの所感を収集

同一会話内で /review-pr を実行済みの場合、サマリー内容を引き継ぐ。ユーザーに「サマリーの内容で進めるか、修正があるか」を確認し、修正がなければそのまま Step 3 に進む。

/review-pr を実行していない場合は、AskUserQuestionで以下を確認する。**1メッセージ = 最大4質問**。

1. **レビュー種別**: Approve / Request Changes
2. **良いと感じた点**: 自由記述（必須）
3. **気になった点・質問**: 自由記述（任意）
4. **確認した点**: 手を動かして確認した内容を自由記述（任意。例: 「〜の動作を確認」「〜のテストを実行」等）

### Step 3: コメント生成

diff分析とユーザーの所感を組み合わせてMarkdownコメントを生成する。

**トーンガイドライン**: references/tone-guide.md を参照し、上司向けの丁寧な表現を使用する。

#### 判定の主導権（AIが独断で決めない項目）

以下は Step 2 でユーザーから明示的な指定がない限り、**AI が独断で付けない**。必要なら AskUserQuestion で確認してから反映する:

- レビュー種別（Approve / Request Changes）
- 重大度タグ（Critical / Important / Nit 等）
- 「修正をお願いしたい点」として強制力を持たせる項目の選定

#### 生成ルール

1. **良いと感じた点**: ユーザーの所感を軸に、変更前→変更後の構造変化レベルで記述する。特定の関数名・変数名・タグ名等の実装詳細には言及しない
2. **確認した点**: Step 2 でユーザーが申告した内容のみ記述する。申告がない場合はセクションごと省略。AIがdiffから推測した確認事項を勝手に追加しない
3. **質問**: ユーザーの「気になった点」を質問形式（「〜でしょうか？」「〜予定はありますか？」）に変換する。なければセクション省略
4. **Request Changes時**: 問題指摘も質問形式にする（「〜のように見えるのですが、意図的でしょうか？」）
5. コメント全体は**簡潔に**。良いと感じた点: 2-3項目、確認した点: ユーザー申告分のみ、質問: 1-2項目

### Step 4: コメント提示とユーザー承認

Step 4 は Step 5 への前提条件。以下を順に実行する。**この順序を崩して Step 5 に進むことは禁止**。

#### Step 4a: コメント本文の提示（投稿しない）

生成したコメント本文を Markdown ブロックで提示する。この時点で `gh pr review` は**絶対に実行しない**。PR コメントは他者に見える操作であり取り消しが困難なため、ユーザー承認前の投稿は禁止。

#### Step 4b: ユーザー承認の取得

AskUserQuestion で以下の選択肢を提示する：

- このまま投稿
- 修正してから投稿（修正内容を記述）
- キャンセル

#### Step 4c: 承認結果の判定

- 「このまま投稿」→ Step 5 に進む
- 「修正してから投稿」→ コメントを更新し、Step 4a から再実施
- 「キャンセル」→ 処理終了（Step 5 を実行しない）

### Step 5: CLI投稿

**前提**: Step 4c で「このまま投稿」が選択されていること。未確認の場合は Step 4 に戻る。

確認後、`gh pr review`コマンドを生成・実行する：

```bash
# Approve
gh pr review <PR番号> --approve --body "$(cat <<'EOF'
（コメント本文）
EOF
)"

# Request Changes
gh pr review <PR番号> --request-changes --body "$(cat <<'EOF'
（コメント本文）
EOF
)"
```

投稿成功後、PRのURLを表示する。

## 出力フォーマット

見出し（`##` `###`）は使用しない。改行と箇条書き（`- `）のみで構成する。

### Approve

```markdown
実装ありがとうございます！

良いと感じた点
- {変更前→変更後の構造変化に言及}だと思いました
- {設計方針の変化}が参考になりました

確認した点
- {ユーザーが実際に確認した内容}を確認しました

質問（マージには影響しません）
- {質問形式。なければセクション省略}
```

### Request Changes

```markdown
確認しました！

良いと感じた点
- {良い点を必ず先に}

修正をお願いしたい点
- {問題点を質問形式で} + 理由

質問
- {理解のための確認}
```

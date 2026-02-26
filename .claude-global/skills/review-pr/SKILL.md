---
name: review-pr
description: Use when the user wants to review a pull request interactively with Claude, focusing on deep code understanding. Triggers on "/review-pr", "PRレビュー", "コードレビューしたい", "PRを理解したい", "PRを一緒に読みたい".
allowed-tools: Bash, Read, AskUserQuestion
version: 1.0.0
---

# PR対話レビュー

PRをClaudeと一緒に読み、コードの理解を深めるためのスキル。
Claudeが能動的に進行役となり、各フェーズで必ず理解確認を行う。

## 引数

$ARGUMENTS

- PR番号のみ: `123`
- PR番号＋リポジトリ: `123 owner/repo`
- 引数なし: AskUserQuestionで確認する

## Iron Law

```
理解確認なしに次のフェーズへ進まない。
AskUserQuestionで確認を取るまで、絶対に先へ進むな。
```

## AskUserQuestion Rules

- **1メッセージ = 1質問のみ**
- 毎フェーズ終了後に必ずAskUserQuestionで確認する
- 理解できていない部分があれば、そこを深掘りしてから次へ進む

## The Process

### Step 0: PR情報の確認

引数からPR番号とリポジトリを取得する。
不足している場合はAskUserQuestionで聞く：

```
「どのPRをレビューする？PR番号を教えて（リポジトリが現在のディレクトリと違う場合は owner/repo も）」
```

### Step 1: PR情報取得

```bash
# カレントディレクトリのリポジトリの場合
gh pr view <PR番号>
gh pr diff <PR番号>

# リポジトリを指定する場合
gh pr view <PR番号> --repo <owner>/<repo>
gh pr diff <PR番号> --repo <owner>/<repo>
```

### Step 2: 全体概要の説明

以下を簡潔に説明する（箇条書き、3〜5行）：
- このPRが「なぜ」作られたか（背景・目的）
- 変更されたファイルの一覧
- 変更の大まかな規模感

→ **[AskUserQuestion]** 「全体像はつかめた？気になる点や先に聞きたいことはある？」

### Step 3: ファイル別の解説

変更されたファイルを1つずつ取り上げ、以下を説明する：
1. **なぜこのファイルが変わったか**（変更の意図）
2. **何をしているか**（コードの仕組みを丁寧に）
3. 注目すべき実装の工夫・判断

→ **[AskUserQuestion]** 「このファイルの変更、理解できた？分からないところはある？」

ファイルの数だけこのステップを繰り返す。次のファイルに進む前に必ず確認する。

### Step 4: 影響範囲の説明

- 他のコードへの波及
- 外部サービスやAPIへの影響
- 破壊的変更の有無

→ **[AskUserQuestion]** 「影響範囲についてはどう？気になる点はある？」

### Step 5: レビュー観点の整理

理解を踏まえた上で以下を提示する：
- 潜在的な問題点・エッジケースの漏れ
- 代替実装があればその比較
- 良い点（意図的な設計判断など）

→ **[AskUserQuestion]** 「レビュー観点として気になるものはあった？他に確認したいことは？」

### Step 6: まとめ

- このPRで理解したことの簡単なサマリー
- 全体を通じた感想・評価

## gh CLI Reference

```bash
# PR概要
gh pr view <PR番号>

# diff（全体）
gh pr diff <PR番号>

# 変更ファイル名のみ
gh pr diff <PR番号> --name-only
```

認証エラーが出た場合は `gh auth switch` でアカウントを切り替える。

# GitHub で人生管理 - 運用ガイド

## 概要

GitHub Issues + Projects で仕事・私生活のタスク・アイデア・メモを一元管理する。
nb日報との自動連携、マイクロブログ機能も実装済み。

- **リポジトリ**: https://github.com/aya-215/life (Private)
- **Project**: Life Dashboard
- **nbバックアップ**: https://github.com/aya-215/nb (Private)

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub (aya-215/nb) Private                    │
│  ~/.nb 全体をGit管理（cron で30分ごとに自動sync）                 │
│  daily/ tasks/ weekly/ notes/ claude/                           │
└───────────────────────────────┬─────────────────────────────────┘
                                │ GitHub Actions (翌日12:00)
                                ↓
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub (aya-215/life) Private                  │
│  Issues: タスク、日報Issue、アイデア                              │
│  Actions: 日報Issue自動作成、nb連携、ファイル化、週次レビュー     │
│  blog/: マイクロブログ（Issueコメントから自動生成）              │
└─────────────────────────────────────────────────────────────────┘
        ↑
   iPhone ショートカット / gh CLI
```

## 自動化スケジュール

| 時刻 (JST) | ワークフロー | 内容 |
|------------|-------------|------|
| **09:00 毎日** | `daily-issue.yml` | 今日の日報Issue作成 |
| **09:00 日曜** | `recurring-tasks.yml` | 週次レビューIssue作成 |
| **12:00 毎日** | `sync-nb-daily.yml` | 前日のnb日報サマリーをIssueに追加 |
| **13:00 毎日** | `daily-to-blog.yml` | 前日のIssueを`blog/YYYYMMDD.md`に変換 |
| **30分ごと** | `nb-sync.sh` (cron) | ~/.nb の変更をGitHubにpush |

## ラベル設計

### コンテキスト（必須・1つ選ぶ）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `work` | 青 | 仕事関連 |
| `personal` | 緑 | 私生活 |
| `study` | 紫 | 学習・自己投資 |

### 種類（必須・1つ選ぶ）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `task` | 黄 | やるべきこと（期限あり） |
| `idea` | 水色 | アイデア・いつかやりたい |
| `event` | オレンジ | ライフイベント（車検、更新等） |
| `memo` | グレー | メモ・ナレッジ |

### 優先度（任意）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `priority:high` | 赤 | 高優先度 |
| `priority:medium` | 黄 | 中優先度 |
| `priority:low` | 緑 | 低優先度 |

## 基本操作

### Issue 作成

```bash
# 仕事タスク（高優先度）
gh issue create --repo aya-215/life \
  --title "レビュー対応" \
  --label "work,task,priority:high"

# 私生活タスク
gh issue create --repo aya-215/life \
  --title "歯医者予約" \
  --label "personal,task"

# アイデア
gh issue create --repo aya-215/life \
  --title "ブログネタ: GitHub人生管理" \
  --label "personal,idea"

# ライフイベント
gh issue create --repo aya-215/life \
  --title "車検 2026/06" \
  --label "personal,event"

# メモ
gh issue create --repo aya-215/life \
  --title "おすすめのカフェリスト" \
  --label "personal,memo"
```

### Issue 一覧

```bash
# 全件
gh issue list --repo aya-215/life

# ラベルでフィルタ
gh issue list --repo aya-215/life --label work
gh issue list --repo aya-215/life --label "priority:high"
gh issue list --repo aya-215/life --label "personal,task"
```

### Issue 完了

```bash
gh issue close <番号> --repo aya-215/life
```

## マイクロブログ（日報Issue）

毎朝9時に自動作成される日報Issueにコメントを追加することで、その日の記録を残せる。

### コメント追加

```bash
# 今日の日報Issueを探してコメント追加
DATE=$(date +%Y-%m-%d)
ISSUE_NUM=$(gh issue list --repo aya-215/life --search "in:title ${DATE}" --json number --jq '.[0].number')
gh issue comment "$ISSUE_NUM" --repo aya-215/life --body "午後のミーティングでXXが決まった"
```

### iPhoneからの追加

GitHubアプリで日報Issueを開いてコメント追加、または後述のiPhoneショートカットを使用。

### 自動処理

1. **翌日12:00**: nb日報のサマリーセクションがIssueコメントに自動追加
2. **翌日13:00**: Issueのコメントが `blog/YYYYMMDD.md` にファイル化

## nb連携

### 仕組み

- `~/.nb` 全体がGitHub `aya-215/nb` リポジトリで管理
- 30分ごとにcronで自動sync（`~/.dotfiles/scripts/nb-sync.sh`）
- 翌日12時にGitHub Actionsがnb日報を読み取り、lifeリポジトリのIssueに追加

### cron設定（初回のみ）

```bash
crontab -e
# 以下を追加
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh
```

### 手動sync

```bash
~/.dotfiles/scripts/nb-sync.sh
```

### ログ確認

```bash
tail -20 ~/.local/log/nb-sync.log
```

## iPhoneショートカット設定

### タスク登録ショートカット

1. ショートカットアプリで新規作成
2. 「テキストを要求」アクション追加 → タイトル入力
3. 「メニューから選択」アクション追加 → ラベル選択
   - work,task
   - personal,task
   - study,task
   - personal,idea
4. 「URLの内容を取得」アクション追加
   - URL: `https://api.github.com/repos/aya-215/life/issues`
   - Method: POST
   - Headers:
     - Authorization: `Bearer YOUR_TOKEN`
     - Accept: `application/vnd.github+json`
   - Request Body: JSON
     ```json
     {"title": "[タイトル変数]", "labels": ["[ラベル変数]"]}
     ```

### マイクロブログ追加ショートカット

1. 「テキストを要求」または「テキストを音声入力」
2. 「現在の日付」を取得（フォーマット: YYYY-MM-dd）
3. 「URLの内容を取得」でIssue検索
   - URL: `https://api.github.com/repos/aya-215/life/issues?state=open`
   - Method: GET
4. JSONから今日の日付を含むIssue番号を抽出
5. 「URLの内容を取得」でコメント追加
   - URL: `https://api.github.com/repos/aya-215/life/issues/[番号]/comments`
   - Method: POST
   - Body: `{"body": "[入力テキスト]"}`

## Claude Code連携

### Issue内容を取得してナレッジ整理

```bash
gh issue view 123 --repo aya-215/life --comments
```

### 1週間分の完了Issueをサマリー

```bash
gh issue list --repo aya-215/life --state closed \
  --search "closed:>=$(date -d '7 days ago' +%Y-%m-%d)"
```

### アイデアを整理

```bash
gh issue list --repo aya-215/life --label idea --json title,body
```

## ビューの使い分け

| ビュー | 用途 |
|--------|------|
| **Board** | 日々のタスク管理（Todo → Doing → Done） |
| **Table** | 一覧表示、ソート・フィルタ |
| **Roadmap** | 期限付きタスクのスケジュール確認 |

## 運用フロー

### 朝のルーティン

```bash
# 日報作成（nbのまま）
nbd

# 今日のタスク確認
gh issue list --repo aya-215/life --label task --state open
```

### タスク追加時

1. コンテキスト（work/personal/study）を選ぶ
2. 種類（task/idea/event/memo）を選ぶ
3. 必要に応じて優先度を付ける

### 週次レビュー（日曜に自動Issue作成）

- GitHub Projects の Board ビューで Done を眺める
- 達成感を味わう
- 溜まった idea を見直す
- 未完了タスクの優先度を見直し

## トラブルシューティング

### nb-syncが動かない

```bash
# ログ確認
tail -20 ~/.local/log/nb-sync.log

# 手動実行
~/.dotfiles/scripts/nb-sync.sh

# cron確認
crontab -l | grep nb-sync
```

### GitHub Actionsが失敗する

1. https://github.com/aya-215/life/actions で確認
2. `NB_TOKEN` シークレットが設定されているか確認
3. トークンの有効期限を確認

### 日報Issueが重複作成される

既存チェックは日付文字列の検索で行うため、タイトルを手動で変更すると重複する可能性あり。

## 関連ドキュメント

- [nb 使用方法](./nb-usage.md) - 日報・週報は nb で継続

## 関連ファイル

| ファイル | 用途 |
|----------|------|
| `~/.dotfiles/scripts/nb-sync.sh` | nb自動sync |
| `life/.github/workflows/daily-issue.yml` | 日報Issue作成 |
| `life/.github/workflows/sync-nb-daily.yml` | nb→Issue連携 |
| `life/.github/workflows/daily-to-blog.yml` | Issue→ファイル化 |
| `life/.github/workflows/recurring-tasks.yml` | 週次レビュー |

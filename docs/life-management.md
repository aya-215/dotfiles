# GitHub人生管理 - リファレンス

> 詳細な設定・運用ガイド。サッと使いたいだけなら [クイックスタート](./life-management-quickstart.md) を参照。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub (aya-215/nb) Private                    │
│  ~/.nb 全体をGit管理（cron で30分ごとに自動sync）                 │
│  daily/ tasks/ weekly/ notes/ claude/                           │
└───────────────────────────┬─────────────────────────────────────┘
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

## リポジトリ構成

| リポジトリ | 用途 | 可視性 |
|-----------|------|--------|
| [aya-215/life](https://github.com/aya-215/life) | タスク・アイデア・日報Issue管理 | Private |
| [aya-215/nb](https://github.com/aya-215/nb) | ~/.nb 全体のバックアップ | Private |

## 自動化詳細

### スケジュール一覧

| 時刻 (JST) | ワークフロー | 内容 |
|------------|-------------|------|
| 09:00 毎日 | `daily-issue.yml` | 今日の日報Issue作成 |
| 09:00 日曜 | `recurring-tasks.yml` | 週次レビューIssue作成 |
| 09:00 毎月1日 | `monthly-review.yml` | 月次レビューIssue作成 |
| 12:00 毎日 | `sync-nb-daily.yml` | 前日のnb日報サマリーをIssueに追加 |
| 13:00 毎日 | `daily-to-blog.yml` | 前日のIssueを`blog/YYYYMMDD.md`に変換 |
| 30分ごと | `nb-sync.sh` (cron) | ~/.nb の変更をGitHubにpush |

### ワークフロー詳細

#### daily-issue.yml
毎朝9時に今日の日報Issueを作成。既存チェックあり（重複作成しない）。

- **トリガー**: `cron: '0 0 * * *'` (UTC 0:00 = JST 9:00)
- **ラベル**: `personal,memo`
- **タイトル**: `YYYY-MM-DD (Day) の記録`

#### sync-nb-daily.yml
前日のnb日報から「📝 今日のサマリー」セクションを抽出し、対応するIssueにコメント追加。

- **トリガー**: `cron: '0 3 * * *'` (UTC 3:00 = JST 12:00)
- **対象**: `~/.nb/daily/YYYY-MM-DD.md`
- **nbリポジトリ**: `aya-215/nb` を checkout して読み取り

#### daily-to-blog.yml
前日の日報Issueのコメントを `blog/YYYYMMDD.md` にファイル化。

- **トリガー**: `cron: '0 4 * * *'` (UTC 4:00 = JST 13:00)
- **出力**: `blog/YYYYMMDD.md`

#### recurring-tasks.yml
毎週日曜に週次レビューIssueを作成。チェックリスト付き。

- **トリガー**: `cron: '0 0 * * 0'` (毎週日曜)
- **ラベル**: `personal,task,priority:medium`

#### auto-add-to-project.yml
Issue作成時に自動でGitHub Projectに追加。

- **トリガー**: `issues: [opened]`
- **Project**: https://github.com/users/aya-215/projects/1

#### monthly-review.yml
毎月1日に月次レビューIssueを作成。アイデア棚卸しを促すチェックリスト付き。

- **トリガー**: `cron: '0 0 1 * *'` (毎月1日)
- **ラベル**: `personal,task,priority:medium`
- **内容**: 振り返り、アイデア棚卸し、来月の目標設定

### Secrets設定

| リポジトリ | Secret名 | 用途 | 必要な権限 |
|-----------|----------|------|-----------|
| life | `NB_TOKEN` | nbリポジトリ読み取り + Issue操作 | `repo`, `project` |
| life | `PROJECT_TOKEN` | Project自動追加用 | `project` |

## ラベル設計

### コンテキスト（必須・1つ選ぶ）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `work` | 青 #0052CC | 仕事関連 |
| `personal` | 緑 #0E8A16 | 私生活 |
| `study` | 紫 #5319E7 | 学習・自己投資 |

### 種類（必須・1つ選ぶ）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `task` | 黄 #FBCA04 | やるべきこと（期限あり） |
| `idea` | 水色 #C5DEF5 | アイデア・いつかやりたい |
| `event` | オレンジ #D93F0B | ライフイベント（車検、更新等） |
| `memo` | グレー #EDEDED | メモ・ナレッジ |

### 優先度（任意）

| ラベル | 色 | 用途 |
|--------|-----|------|
| `priority:high` | 赤 #B60205 | 高優先度 |
| `priority:medium` | 黄 #FBCA04 | 中優先度 |
| `priority:low` | 緑 #0E8A16 | 低優先度 |

## 基本操作

### Issue作成

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

# 本文付き
gh issue create --repo aya-215/life \
  --title "新機能実装" \
  --label "work,task" \
  --body "## 概要
詳細な説明をここに"
```

### Issue一覧・検索

```bash
# 全件
gh issue list --repo aya-215/life

# ラベルでフィルタ
gh issue list --repo aya-215/life --label work
gh issue list --repo aya-215/life --label "priority:high"
gh issue list --repo aya-215/life --label "personal,task"

# 状態でフィルタ
gh issue list --repo aya-215/life --state closed
gh issue list --repo aya-215/life --state all

# 検索クエリ
gh issue list --repo aya-215/life --search "in:title 歯医者"

# JSON出力
gh issue list --repo aya-215/life --json number,title,labels
```

### Issue操作

```bash
# 詳細表示
gh issue view 123 --repo aya-215/life

# コメント付きで表示
gh issue view 123 --repo aya-215/life --comments

# コメント追加
gh issue comment 123 --repo aya-215/life --body "進捗: 50%完了"

# 完了
gh issue close 123 --repo aya-215/life

# 再オープン
gh issue reopen 123 --repo aya-215/life

# ラベル追加
gh issue edit 123 --repo aya-215/life --add-label "priority:high"

# ラベル削除
gh issue edit 123 --repo aya-215/life --remove-label "priority:low"
```

## マイクロブログ機能

毎朝9時に自動作成される日報Issueにコメントを追加することで、その日の記録を残せる。

### コメント追加

```bash
# 今日の日報Issueを探してコメント追加
DATE=$(date +%Y-%m-%d)
ISSUE_NUM=$(gh issue list --repo aya-215/life --search "in:title ${DATE}" --json number --jq '.[0].number')
gh issue comment "$ISSUE_NUM" --repo aya-215/life --body "午後のミーティングでXXが決まった"
```

### ワンライナー版

```bash
gh issue comment $(gh issue list --repo aya-215/life --search "in:title $(date +%Y-%m-%d)" --json number -q '.[0].number') --repo aya-215/life --body "メモ内容"
```

### 自動処理フロー

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

### cron確認

```bash
crontab -l | grep nb-sync
```

### 手動sync

```bash
~/.dotfiles/scripts/nb-sync.sh
```

### ログ確認

```bash
tail -20 ~/.local/log/nb-sync.log
```

### nb-sync.sh の内容

```bash
#!/bin/bash
set -euo pipefail

NB_DIR="$HOME/.nb"
LOG_FILE="$HOME/.local/log/nb-sync.log"

mkdir -p "$(dirname "$LOG_FILE")"
cd "$NB_DIR"

if [[ -n $(git status --porcelain) ]]; then
    git add -A
    git commit -m "auto sync: $(date +%Y-%m-%d\ %H:%M)"
    git push
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Synced" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No changes" >> "$LOG_FILE"
fi
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

### 全アイデアをJSON取得

```bash
gh issue list --repo aya-215/life --label idea --state all --json number,title,body,createdAt
```

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

- Inbox → This Week にタスクを移動
- GitHub Projects の Board ビューで Done を眺める
- 達成感を味わう
- 未完了タスクの優先度を見直し

### 月次レビュー（毎月1日に自動Issue作成）

- `/monthly-idea-review` でアイデア棚卸し
  - **ナレッジ化**: nbに書き出し → Issueクローズ
  - **task昇格**: ideaラベル → taskラベルに変更
  - **保留**: 来月また確認
  - **クローズ**: もう不要
- 先月の振り返り
- 来月の目標設定

## GitHub Projects

### ステータス

```
Inbox → This Week → In Progress → Done
```

| ステータス | 用途 |
|-----------|------|
| **Inbox** | 新規Issue全部ここ。ideaも一旦ここ |
| **This Week** | 週次レビューで今週やるものを移動 |
| **In Progress** | 今取り組んでるもの |
| **Done** | 完了 |

### ビュー

| ビュー | 用途 |
|--------|------|
| **Board** | 日々のタスク管理（カンバン形式） |
| **Table** | 一覧表示、ソート・フィルタ |
| **Roadmap** | 期限付きタスクのスケジュール確認 |

## トラブルシューティング

### nb-syncが動かない

```bash
# ログ確認
tail -20 ~/.local/log/nb-sync.log

# 手動実行
~/.dotfiles/scripts/nb-sync.sh

# cron確認
crontab -l | grep nb-sync

# upstream未設定エラーの場合
cd ~/.nb && git push --set-upstream origin main
```

### GitHub Actionsが失敗する

1. https://github.com/aya-215/life/actions で確認
2. `NB_TOKEN` シークレットが設定されているか確認
3. トークンの有効期限を確認
4. トークンの権限（`repo`, `project`）を確認

### 日報Issueが重複作成される

既存チェックは日付文字列の検索で行うため、タイトルを手動で変更すると重複する可能性あり。

### ラベルアクセス権限エラー

`GITHUB_TOKEN` では `Resource not accessible by integration` エラーになる場合、`NB_TOKEN`（PAT）を使用。

## 関連ファイル

| ファイル | 用途 |
|----------|------|
| `~/.dotfiles/scripts/nb-sync.sh` | nb自動sync |
| `~/.dotfiles/docs/nb-usage.md` | nb使用方法 |
| `life/.github/workflows/daily-issue.yml` | 日報Issue作成 |
| `life/.github/workflows/sync-nb-daily.yml` | nb→Issue連携 |
| `life/.github/workflows/daily-to-blog.yml` | Issue→ファイル化 |
| `life/.github/workflows/recurring-tasks.yml` | 週次レビュー |
| `life/.github/workflows/monthly-review.yml` | 月次レビュー |
| `life/.github/workflows/auto-add-to-project.yml` | Project自動追加 |
| `~/.claude/skills/monthly-idea-review/` | アイデア棚卸しスキル |

## 参考記事

- https://zenn.dev/hand_dot/articles/85c9640b7dcc66 - Issue + Projects、画像アップロード、1年運用
- https://qiita.com/e99h2121/items/45c62307565458964b94 - ラベル分類、年間振り返り
- https://qiita.com/TaigoKuriyama/items/32f3ef128db2b9344e6a - GTD手法、iPhoneショートカット、GitHub Actions自動化

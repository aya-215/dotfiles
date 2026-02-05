# GitHub人生管理 - クイックスタート

> 5分で始められるクイックガイド。詳細は [life-management.md](./life-management.md) を参照。

## 30秒でわかる概要

```
┌─────────────────┐     自動連携      ┌─────────────────┐
│   ~/.nb         │ ─────────────────→│  aya-215/life   │
│  (日報・メモ)    │   翌日12:00       │  (Issues管理)    │
└─────────────────┘                   └─────────────────┘
       ↑                                     │
   30分ごと自動バックアップ                    ↓
       │                              毎朝9時 日報Issue作成
┌─────────────────┐                   毎週日曜 週次レビュー作成
│  aya-215/nb     │
│  (Gitバックアップ)│
└─────────────────┘
```

**できること**:
- 仕事・私生活のタスク/アイデア/メモをGitHub Issueで一元管理
- 毎朝自動で日報Issue作成 → コメントで1日の記録を残せる
- nbの日報が自動でIssueに連携
- 週次レビューIssueで振り返り

## よく使うコマンド

### Issue作成

```bash
# 仕事タスク
gh issue create --repo aya-215/life --title "PRレビュー対応" --label "work,task"

# 私生活タスク（高優先度）
gh issue create --repo aya-215/life --title "歯医者予約" --label "personal,task,priority:high"

# アイデア
gh issue create --repo aya-215/life --title "ブログネタ: Claude活用術" --label "personal,idea"

# メモ
gh issue create --repo aya-215/life --title "美味しかったラーメン屋" --label "personal,memo"

# ライフイベント
gh issue create --repo aya-215/life --title "車検 2026/06" --label "personal,event"
```

### Issue一覧

```bash
# 全件
gh issue list --repo aya-215/life

# ラベルでフィルタ
gh issue list --repo aya-215/life --label work
gh issue list --repo aya-215/life --label "priority:high"
gh issue list --repo aya-215/life --label "personal,task"
```

### Issue完了

```bash
gh issue close 123 --repo aya-215/life
```

### 今日の日報にコメント追加

```bash
# 今日の日付で日報Issueを検索してコメント
DATE=$(date +%Y-%m-%d)
ISSUE=$(gh issue list --repo aya-215/life --search "in:title ${DATE}" --json number -q '.[0].number')
gh issue comment "$ISSUE" --repo aya-215/life --body "午後のミーティングでXXが決定"
```

## ラベル早見表

| 分類 | ラベル | 使い分け |
|------|--------|----------|
| **コンテキスト** | `work` | 仕事関連 |
| | `personal` | 私生活 |
| | `study` | 学習・自己投資 |
| **種類** | `task` | やるべきこと（期限あり） |
| | `idea` | いつかやりたい・ネタ |
| | `event` | ライフイベント（車検、更新等） |
| | `memo` | メモ・ナレッジ |
| **優先度** | `priority:high` | 高（赤） |
| | `priority:medium` | 中（黄） |
| | `priority:low` | 低（緑） |

**組み合わせ例**: `work,task,priority:high` / `personal,idea` / `study,memo`

## 自動化一覧（何もしなくても動く）

| 時刻 | 内容 |
|------|------|
| **毎日 09:00** | 今日の日報Issue作成 |
| **毎日 12:00** | 前日のnb日報サマリー → Issue連携 |
| **毎日 13:00** | 前日のIssue → `blog/YYYYMMDD.md` ファイル化 |
| **毎週日曜 09:00** | 週次レビューIssue作成 |
| **毎月1日 09:00** | 月次レビューIssue作成 |
| **30分ごと** | `~/.nb` をGitHubに自動バックアップ |

## Projectステータス

```
Inbox → This Week → In Progress → Done
```

- **Inbox**: 新規Issue全部ここ。ideaも一旦ここ
- **This Week**: 週次レビューで今週やるものを移動
- **In Progress**: 今取り組んでるもの
- **Done**: 完了

## 運用フロー

### 朝

```bash
# nb日報作成（いつも通り）
nbd

# 今日のタスク確認
gh issue list --repo aya-215/life --label task --state open
```

### 日中

- タスク追加は `gh issue create`
- 気づいたことは日報Issueにコメント or nbに書く

### 週末（日曜）

- 自動作成される週次レビューIssueのチェックリストを消化
- Inbox → This Week にタスクを移動
- GitHub Projects の Board ビューで Done を眺めて達成感を得る

### 月初（1日）

- 自動作成される月次レビューIssueのチェックリストを消化
- `/monthly-idea-review` でアイデア棚卸し
  - ナレッジ化 → nbに書き出してクローズ
  - task昇格 → ラベル変更
  - 不要 → クローズ

## Web UI

- **Issues**: https://github.com/aya-215/life/issues
- **Project Board**: https://github.com/users/aya-215/projects/1
- **Actions**: https://github.com/aya-215/life/actions

## 詳細リファレンス

→ [life-management.md](./life-management.md) - アーキテクチャ、トラブルシューティング、iPhoneショートカット設定など

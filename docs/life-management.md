# GitHub で人生管理 - 運用ガイド

## 概要

GitHub Issues + Projects で仕事・私生活のタスク・アイデア・メモを一元管理する。

- **リポジトリ**: https://github.com/aya-215/life
- **Project**: Life Dashboard

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
  --title "車検 2025/06" \
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

# オープンのみ（デフォルト）
gh issue list --repo aya-215/life --state open

# ラベルでフィルタ
gh issue list --repo aya-215/life --label work
gh issue list --repo aya-215/life --label "priority:high"
gh issue list --repo aya-215/life --label "personal,task"
```

### Issue 完了

```bash
gh issue close <番号> --repo aya-215/life
```

### Issue 再オープン

```bash
gh issue reopen <番号> --repo aya-215/life
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

### 週次レビュー

- GitHub Projects の Board ビューで Done を眺める
- 達成感を味わう
- 溜まった idea を見直す

## 今後の拡張予定

- [ ] GitHub Actions で繰り返しタスク自動作成
- [ ] iPhone ショートカットで素早く Issue 作成
- [ ] 月次/年次の振り返りレポート生成

## 関連ドキュメント

- [nb 使用方法](./nb-usage.md) - 日報・週報は nb で継続

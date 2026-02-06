# Monthly Idea Review

月次のアイデア棚卸しスキル。ideaラベルのIssueを確認し、ナレッジ化・タスク昇格・クローズを対話的に行う。

## Trigger
- `/monthly-idea-review` または `/idea-review`
- 月次レビュー時に使用

## Workflow

### 1. ideaラベルのIssue一覧を取得

```bash
gh issue list --repo aya-215/life --label idea --state open --json number,title,body,createdAt
```

### 2. 各ideaについてユーザーに選択肢を提示

AskUserQuestionを使って、各ideaに対して以下の選択肢を提示：

- **ナレッジ化**: nbにメモとして書き出し → Issueクローズ
- **task昇格**: ideaラベルを削除してtaskラベルを追加 → This Weekに移動検討
- **保留**: 何もしない（来月また確認）
- **クローズ**: もう不要なのでクローズ

### 3. 選択に応じた処理

#### ナレッジ化の場合
```bash
# nbにノート追加
nb notes:add "アイデア: [タイトル]" --content "[本文]"

# Issueクローズ
gh issue close [番号] --repo aya-215/life --comment "ナレッジ化完了"
```

#### task昇格の場合
```bash
# ラベル変更
gh issue edit [番号] --repo aya-215/life --remove-label idea --add-label task

# 優先度を聞いて追加（任意）
gh issue edit [番号] --repo aya-215/life --add-label "priority:medium"
```

#### クローズの場合
```bash
gh issue close [番号] --repo aya-215/life --comment "月次レビューでクローズ"
```

### 4. サマリー表示

処理完了後、以下をサマリー表示：
- ナレッジ化: X件
- task昇格: X件
- 保留: X件
- クローズ: X件

## Example Output

```
## アイデア棚卸し結果

| # | タイトル | 処理 |
|---|---------|------|
| 12 | ブログネタ: Claude活用術 | ナレッジ化 |
| 15 | 新しいキーボード検討 | task昇格 |
| 18 | 旅行先候補 | 保留 |
| 20 | 古いアイデア | クローズ |

### サマリー
- ナレッジ化: 1件
- task昇格: 1件
- 保留: 1件
- クローズ: 1件
```

## Notes

- ideaが0件の場合は「アイデアはありません」と表示して終了
- 大量にある場合は10件ずつ処理することを提案
- ナレッジ化先は `nb notes:` ノートブックがデフォルト

---
name: daily-review
description: 日次レビュー - サマリー生成、会話レビュー、メモリ整理
allowed-tools: Read, Bash, Edit, AskUserQuestion
version: 2.0.0
model: opus
---

# 日次レビュー

毎日の振り返りを統合的に実行する。日報サマリーの生成、Claude会話のレビュー、agent-memoryの整理を一括で行う。

---

## 処理フロー

### フェーズ1: 日報サマリー生成

1. 今日の日報 Issue を特定（`aya-215/life` リポジトリ）
2. 対象日のgitコミットログを取得
3. 対象日の完了タスク（当日 close された task Issue）を取得
4. claude-nb-sync.py を手動実行して最新の会話を同期
5. 対象日のClaude会話履歴を取得
6. Work/Personalに分類してサマリー生成（Claude会話も含む）
7. ユーザーに確認表示
8. 承認後、日報 Issue の body の「📝 サマリー」セクションを更新（`gh issue edit`）
8.5. 日報 Issue の「💡 メモ」セクションに「調子: /5」が未記入（「調子: /5」のまま）の場合、ユーザーに「今日の調子は5段階で？」と質問し、回答を日報 Issue に反映する

### フェーズ2: メモリ整理

9. 既存メモリの一覧を取得
10. メモリ整理タスクを対話形式で実施
    - 新規メモリ候補の提案
    - 既存メモリの更新確認
    - 不要メモリの削除提案
    - メモリの整理・統合
11. ユーザー確認後、承認された整理作業を実行

---

## 入力ソース

| ソース | 取得先 | 用途 |
|--------|--------|------|
| 今日の日報 | `aya-215/life` の日報 Issue（`in:title YYYY-MM-DD の記録`） | 💡メモを取り込む |
| 既存サマリー | 日報 Issue body 内の「📝 サマリー」セクション | 入力ソースとして統合 |
| 完了タスク | `aya-215/life` の当日 close された Issue（label: `task`） | サマリーに反映 |
| gitログ（Work） | `~/src/github.com/ebase-dev/*` 配下 | サマリーに反映 |
| gitログ（Personal） | `~/.dotfiles`, `~/src/github.com/aya-215/*` | サマリーに反映 |
| Claude会話履歴 | `~/.nb/claude/YYYY-MM-DD.md` | サマリーに反映 + レビュー対象 |
| agent-memory | `~/.claude/skills/agent-memory/memories/` | 整理・更新確認 |

---

## gh CLI の認証

日報・タスクの操作は `aya-215` アカウントで実行する：

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```

以降のコマンド例では `$GH_TOKEN` を省略しているが、すべての `gh` コマンドに `GH_TOKEN="$GH_TOKEN"` を付与すること。

リポジトリ: `aya-215/life`

---

## コマンド例

### 今日の日報 Issue を特定

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
# issue_num は --jq で直接取得する（echo "$var" | jq は JSON内の\nを改行に展開してパースエラーになるため）
issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
  --search "in:title $(TZ=Asia/Tokyo date +%Y-%m-%d) の記録" \
  --label memo --json number --jq '.[0].number' 2>/dev/null)
# body が必要な場合は別途取得する
issue_body=$(GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life --json body --jq '.body' 2>/dev/null)
```

> **注意:** `echo "$json_var" | jq` は Issue body 内の `\n` をリテラル改行に展開してJSONパースエラーになる。
> シェル変数にJSON全体を入れて後でパースする場合は `printf '%s\n' "$json_var" | jq` を使うこと。

### 日報の💡メモ取得

```bash
# 日報 Issue body から💡メモセクションを抽出
GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life \
  --json body --jq '.body' | \
  sed -n '/^## 💡 メモ$/,$ { /^## 💡 メモ$/d; /^## /q; p }'
```

**説明:**
- Issue body を取得し、`sed` で💡メモセクションを抽出
- `/^## 💡 メモ$/d`: 見出し自体を削除
- `/^## /q`: 次のセクション見出しが出たら終了
- `p`: マッチした行を出力

### 対象日の完了タスク取得

```bash
# 当日 close された task ラベル付き Issue を取得
TARGET_DATE=$(TZ=Asia/Tokyo date +%Y-%m-%d)
GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
  --label task --state closed \
  --json title,closedAt --jq \
  '[.[] | select(.closedAt[:10] == "'"$TARGET_DATE"'")] | .[].title'
```

### gitログ取得（Work）

```bash
# 注: .gitがファイル（worktree/submodule）の場合があるため、-d .gitのチェックは行わない
bash -c 'for repo in ~/src/github.com/ebase-dev/*/; do
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  git -C "$repo" log --oneline --since="2026-01-15 00:00" --until="2026-01-16 00:00" --author="$author_email" 2>/dev/null
done'
```

### gitログ取得（Personal）

```bash
git -C ~/.dotfiles log --oneline --since="$DATE 00:00" --until="$NEXT_DATE 00:00" --author="$(git config user.email)" 2>/dev/null

for repo in ~/src/github.com/aya-215/*/; do
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  git -C "$repo" log --oneline --since="$DATE 00:00" --until="$NEXT_DATE 00:00" --author="$author_email" 2>/dev/null
done
```

### コミット数の集計

gitログ取得後、リポジトリ別のコミット数をカウントし、サマリーのセクションヘッダーに合計を記載する:

```bash
# Work側の集計例
for repo in ~/src/github.com/ebase-dev/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline --since="$DATE 00:00" --until="$NEXT_DATE 00:00" --author="$author_email" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$repo_name: $count commits"
done

# Personal側の集計例
count=$(git -C ~/.dotfiles log --oneline --since="$DATE 00:00" --until="$NEXT_DATE 00:00" --author="$(git config user.email)" 2>/dev/null | wc -l)
[ "$count" -gt 0 ] && echo "dotfiles: $count commits"

for repo in ~/src/github.com/aya-215/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline --since="$DATE 00:00" --until="$NEXT_DATE 00:00" --author="$author_email" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$repo_name: $count commits"
done
```

集計結果をサマリーに反映する形式:
- `### Work (N commits across M repos)`
- `### Personal (N commits across M repos)`
- 各プロジェクト行にも `(N commits)` を付与

### Claude会話同期の実行

```bash
python3 ~/.dotfiles/scripts/claude-sync/claude-nb-sync.py
```

### Claude会話履歴の取得（大きいファイル対応）

会話履歴は1日分でも数百KBになることがあるため、以下の手順で効率的に取得する：

**1. プロジェクト一覧の抽出（セッション数付き）**
```bash
# その日に作業した全プロジェクトを把握
for proj in $(grep -E "^## [a-z]+(-[a-z]+)*$" ~/.nb/claude/2026-01-15.md | sort -u | sed 's/^## //'); do
  count=$(sed -n "/^## $proj\$/,/^## [a-z]/p" ~/.nb/claude/2026-01-15.md | grep -c "^### [0-9]")
  echo "$proj ($count sessions)"
done
```

**2. 各プロジェクトの最初のUser質問を抽出**
```bash
# 各プロジェクトで何を始めたかを把握
for proj in $(grep -E "^## [a-z]+(-[a-z]+)*$" ~/.nb/claude/2026-01-15.md | sort -u | sed 's/^## //'); do
  echo "=== $proj ==="
  # プロジェクトセクションから最初のUser質問を5行取得
  sed -n "/^## $proj\$/,/^## [a-z]/p" ~/.nb/claude/2026-01-15.md | \
    grep -A4 -m1 '^\*\*User:\*\*' | head -5
done
```

**3. 結論マーカー検索 + フォールバック**
```bash
# 各プロジェクトの成果を把握
for proj in $(grep -E "^## [a-z]+(-[a-z]+)*$" ~/.nb/claude/2026-01-15.md | sort -u | sed 's/^## //'); do
  echo "=== $proj (結論) ==="
  # まず結論マーカーを探す
  results=$(sed -n "/^## $proj\$/,/^## [a-z]/p" ~/.nb/claude/2026-01-15.md | grep -E "(✅|完了|成功)" | tail -3)
  if [ -n "$results" ]; then
    echo "$results"
  else
    # フォールバック: 最後のUser-Claudeペア
    sed -n "/^## $proj\$/,/^## [a-z]/p" ~/.nb/claude/2026-01-15.md | tail -30 | grep -A2 '^\*\*Claude:\*\*' | tail -5
  fi
done
```

**4. 見出し・絵文字マーカー検索**
```bash
# 横断的な成果を把握
echo "=== 見出しレベルの成果 ==="
grep -E "^#+.*(完了|成功|解決|実装)" ~/.nb/claude/2026-01-15.md

echo ""
echo "=== 絵文字マーカーの成果 ==="
grep -E "^✅|^- ✅" ~/.nb/claude/2026-01-15.md | head -10
```

**注意:** `cat` でファイル全体を読むのは避ける。256KB以上のファイルは読み込みエラーになる。

### 既存メモリの一覧取得

```bash
rg "^summary:" ~/.claude/skills/agent-memory/memories/ --no-ignore --hidden
```

### 日報 Issue body の更新

```bash
# 1. 現在の body を取得
body=$(GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life --json body --jq '.body')

# 2. サマリーセクションを置換（awk スクリプトをtmpfileに書き出して実行。
#    !in_summary がシェルで展開されるのを回避するため）
awkscript=$(mktemp)
cat > "$awkscript" << 'AWKEOF'
BEGIN { in_summary=0 }
/^## 📝 サマリー/ || /^## 📝 今日のサマリー/ {
  in_summary=1; print; print ""; print new_summary; print ""; next
}
in_summary && /^---/ { in_summary=0 }
in_summary && /^## / { in_summary=0 }
!in_summary { print }
AWKEOF
new_body=$(echo "$body" | awk -v new_summary="$SUMMARY_TEXT" -f "$awkscript")
rm -f "$awkscript"

# 3. Issue を更新
GH_TOKEN="$GH_TOKEN" gh issue edit "$issue_num" --repo aya-215/life --body "$new_body"
```

---

## 分類ルール

| 条件 | 分類 |
|------|------|
| Issue のラベルに `work` あり | Work |
| `~/src/github.com/ebase-dev/*` のコミット | Work |
| その他すべて | Personal |

---

## サマリー形式

```markdown
## 📝 サマリー

### Work (12 commits across 3 repos)
- **ebase-middleware-mcp** (5 commits): LLMパラメータ修正、テスト追加
- **epc-feature-agent** (4 commits): プロンプト改善
- **ebase-portal-chat** (3 commits): worktree整理
- PRレビュー対応
- [プロジェクト名] に関する調査・実装（Claude会話）

### Personal (8 commits across 2 repos)
- **dotfiles** (6 commits): j-functions改善、WezTerm設定改善
- **claude-watch** (2 commits): PostToolUse hook追加
- [テーマ]についての学習（Claude会話）
```

---

## サマリー生成ロジック

すべての入力ソースを統合して新しいサマリーを生成：

- 既存サマリーの内容は失わない（入力として考慮）
- 日報の💡メモは作業内容の把握に参照する（ただし別セクションとして出力しない）
- Claude会話はプロジェクト単位でグルーピング
- 主要なトピック・解決した問題を1-2行で要約
- 重複する内容は統合
- Work/Personalに再分類
- 簡潔な箇条書きでまとめる
- **出力は `### Work` と `### Personal` の2セクションのみ**（気づき・感想などの追加セクションは作成しない）

---

## メモリ整理タスク

### a. 新規メモリ候補の提案

会話履歴から以下を「重要な発見」として抽出:
- 複数往復の調査を要した発見
- 「解決」「完了」「修正」などの結論を含む内容
- コードスニペットや設定例を含む回答
- アーキテクチャ決定

### b. 既存メモリの更新確認

- status変更（in-progress → resolved / abandoned）
- 内容の追記・修正
- updated日付の更新

### c. 不要メモリの削除提案

- 古くなった情報
- 解決済みで参照価値のないもの
- 重複しているもの

### d. メモリの整理・統合

- 関連する複数メモリの統合
- カテゴリ再編成の提案

---

## エラー処理

| 状況 | 対応 |
|------|------|
| 日報 Issue が見つからない | 「日報 Issue が見つかりません。daily-issue.yml で毎朝自動作成されます」と表示して終了 |
| gitリポジトリなし | スキップして他のソースで生成 |
| Claude会話履歴なし | スキップして他のソースで生成 |
| 入力ソースがすべて空 | 「サマリーを生成する情報がありません」と表示して終了 |

---

## 重要なルール

1. 既存の「📝 サマリー」セクションの内容は保持しつつ統合（冪等性確保）
2. 更新前に必ずユーザー確認を取る
3. 更新後は変更内容を表示
4. メモリ整理は対話形式で実施し、すべての操作に承認を得る

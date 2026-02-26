---
name: weekly-report
description: 週報生成
allowed-tools: Read, Bash, AskUserQuestion, Write
version: 2.0.0
---

# 週報生成

指定された週の日報を分析し、週報を生成してください。

## 引数

$ARGUMENTS

- 引数なし: 今週（月曜〜今日まで）
- `last`: 先週（前週の月曜〜日曜）
- `YYYY-MM-DD`: 指定日を含む週

## 手順

### Phase 0: 事前準備

`aya-215/life` リポジトリを最新化する：

```bash
git -C ~/src/github.com/aya-215/life pull
```

### Phase 1: 対象週の特定

引数に応じて対象週（月曜〜日曜）の日付リストを生成する。

```bash
# 引数なし: 今週の月曜〜今日
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
dow=$(TZ=Asia/Tokyo date +%u)  # 1=Mon, 7=Sun
monday=$(TZ=Asia/Tokyo date -d "$today -$((dow-1)) days" +%Y-%m-%d)

# last: 先週の月曜〜日曜
monday=$(TZ=Asia/Tokyo date -d "$today -$((dow+6)) days" +%Y-%m-%d)
sunday=$(TZ=Asia/Tokyo date -d "$monday +6 days" +%Y-%m-%d)
```

### Phase 2: 日報データ取得

各日付について以下の優先順でデータを取得する：

#### 優先1: blog/ ファイル

```bash
# ファイル名形式: YYYYMMDD.md（ハイフンなし）
blog_file=~/src/github.com/aya-215/life/blog/$(echo "$date" | tr -d '-').md
```

ファイルが存在すれば読み込む。

#### 優先2: GitHub Issue（フォールバック）

blog/ ファイルが存在しない日（金曜実行時の当日など、まだ Markdown 化されていない日）は GitHub Issue から取得する：

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)

# Issue を検索（closeされたものも含む）
issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
  --search "in:title ${date} の記録" \
  --state all --label memo \
  --json number --jq '.[0].number' 2>/dev/null)

# Issue body を取得
issue_body=$(GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" \
  --repo aya-215/life --json body --jq '.body' 2>/dev/null)
```

> **注意:** `echo "$json_var" | jq` は Issue body 内の `\n` をリテラル改行に展開してJSONパースエラーになる。
> `printf '%s\n' "$json_var" | jq` を使うこと。

データの欠落日は記録日数のカウントから除外し、その旨をサマリーに記載する。

### Phase 3: 前週の週報を確認

前週の Try 達成状況を評価するため、前週の週報を読み込む：

```bash
# 前週の月曜日を計算
prev_monday=$(TZ=Asia/Tokyo date -d "$monday -7 days" +%Y-%m-%d)
prev_weekly=~/src/github.com/aya-215/life/weekly/${prev_monday}-weekly.md
```

前週の週報が存在する場合、KPT の Try セクションを取得して今週の日報内容と照合する。
達成状況は Claude が判断して ✅/❌ で記載する。
前週の週報がない場合は「先週のTry達成状況」セクション自体を省略する。

### Phase 4: 週報生成

取得した日報データを分析し、以下の形式で週報を生成する。

```markdown
# YYYY/MM/DD週 週報

## サマリー
- 記録日数：X日間
- 主要トピック：
  - [日報から抽出した主要テーマ1]
  - [日報から抽出した主要テーマ2]
  - [日報から抽出した主要テーマ3]

## 重要な活動・決定事項

### #pj/[プロジェクト名]
- [そのプロジェクトに関する活動をまとめる]

（日報の内容に応じてプロジェクトセクションを動的に生成）

### その他
- [分類できない活動]

## 個人開発・環境整備
- [dotfiles、ツール設定など個人的な開発活動]

（Personalセクションの内容がある場合のみ表示）

## 今週の気づき・学び
- [日報の💡メモから抽出]

（内容がある場合のみ表示）

## 来週への引き継ぎ
- [未完了タスク、継続事項]

（内容がある場合のみ表示）

## KPT（振り返り）

### Keep（続けること）
- [日報のメモ・活動から抽出した良かった習慣や行動]

### Problem（課題）
- [繰り返し登場する問題や未達成目標]

### Try（次週試すこと）
- [Problemに対する具体的な小さい改善アクション]

（内容がある場合のみ表示）

---
*先週のTry達成状況:*（前週の週報がある場合のみ）
- ✅ [達成できた Try 項目]
- ❌ [達成できなかった Try 項目]
```

### Phase 5: ファイル保存 & push

```bash
WEEKLY_DIR=~/src/github.com/aya-215/life/weekly
OUTPUT_FILE="${WEEKLY_DIR}/${monday}-weekly.md"

# ファイルに書き込む（Write ツールを使用）

# git commit & push
git -C ~/src/github.com/aya-215/life add "weekly/${monday}-weekly.md"
git -C ~/src/github.com/aya-215/life commit -m "weekly: ${monday}週 週報"
git -C ~/src/github.com/aya-215/life push
```

保存後、生成した週報のパスを表示する。

---

## 重要なルール

1. **セクションの動的生成**: 日報の内容に基づいてプロジェクトセクションを自動判別
   - `ebase-portal-chat`, `PILOT` などのキーワードからプロジェクトを識別
   - 内容がないセクションは省略
2. **要約**: 日報の内容をそのまま転記せず、週単位で要約・統合
3. **プロジェクト識別**: Work セクションの内容からプロジェクト名を推測してグルーピング
4. **KPT生成ルール**:
   - Keep: その週に上手くいった行動・習慣をメモ欄やサマリーから抽出
   - Problem: メモ欄の反省・課題、繰り返し登場する未完了タスク
   - Try: Problemに対する具体的で小さい改善アクション（1週間で実行可能な粒度）
5. **Try達成状況の評価**: 前週の週報（`weekly/YYYY-MM-DD-weekly.md`）を読み込み、今週の日報と照合して Claude が ✅/❌ を判断する

---

## gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```

以降の `gh` コマンドには `GH_TOKEN="$GH_TOKEN"` を付与する。

---

## エラー処理

| 状況 | 対応 |
|------|------|
| life リポジトリの pull 失敗 | 警告を表示して続行（ローカルのファイルを使用） |
| 日報データが1日も取得できない | 「日報データが見つかりません」と表示して終了 |
| GitHub Issue も見つからない日 | その日をスキップし、記録日数のカウントから除外 |
| weekly/ ディレクトリが存在しない | エラーを表示して終了（事前に手動作成が必要） |

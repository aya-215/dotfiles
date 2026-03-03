---
name: monthly-report
description: 月報生成 - 月次サマリーと詳細分析の2ファイル出力
allowed-tools: Read, Bash, AskUserQuestion, Write, Edit
version: 1.0.0
---

# 月報生成

指定された月の日報・週報データを分析し、サマリーファイル（繰り返し閲覧用）と詳細ファイル（deep dive用）の2つを生成する。

## 引数

$ARGUMENTS

- 引数なし: 今月（3日以前の場合は先月）
- `last`: 先月
- `YYYY-MM`: 指定月
- `goals`: 今月の目標設定モード（月初に使用）

---

## 手順

### Phase 0: 事前準備

`aya-215/life` リポジトリを最新化する：

```bash
git -C ~/src/github.com/aya-215/life pull
```

### Phase 1: 対象月の特定

引数に応じて対象月の日付範囲を決定する。

```bash
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
day=$(TZ=Asia/Tokyo date +%d)

# 引数なし: 今月（3日以前なら先月）
if [ "$day" -le 3 ]; then
  target_month=$(TZ=Asia/Tokyo date -d "$today -1 month" +%Y-%m)
else
  target_month=$(TZ=Asia/Tokyo date +%Y-%m)
fi

# last: 先月
target_month=$(TZ=Asia/Tokyo date -d "$today -1 month" +%Y-%m)

# YYYY-MM: そのまま使用
target_month="$1"

# 月の範囲を算出
first_day="${target_month}-01"
last_day=$(TZ=Asia/Tokyo date -d "${first_day} +1 month -1 day" +%Y-%m-%d)
year_month_compact=$(echo "$target_month" | tr -d '-')  # e.g. 202602
```

引数が `goals` の場合は Phase 1.5 へ進む。それ以外は Phase 2 へ。

### Phase 1.5: goals モード（月初の目標設定）

引数が `goals` の場合のみ実行する。

1. 前月のサマリーファイルを読み込む:

```bash
MONTHLY_DIR=~/src/github.com/aya-215/life/monthly
prev_month=$(TZ=Asia/Tokyo date -d "$today -1 month" +%Y-%m)
prev_summary="${MONTHLY_DIR}/${prev_month}-summary.md"
```

2. 前月の「🎯 来月に向けて」セクションがあれば表示する
3. 前月の週報から Problem/Try を収集して目標候補を提示する
4. AskUserQuestion で今月の目標を対話的に収集する（3-5個）:
   - 仕事面（Work）で達成したいこと
   - 個人面（Personal）で達成したいこと
   - 生活習慣の改善目標
   - スキル・学習目標

5. 当月のサマリーファイルを作成し、「🎯 今月の目標」セクションのみ記録する:

```markdown
# YYYY年MM月 月報サマリー

## 🎯 今月の目標

| 目標 | 達成 | メモ |
|------|------|------|
| [目標1] | - | |
| [目標2] | - | |
| [目標3] | - | |
```

6. commit & push して終了:

```bash
mkdir -p "$MONTHLY_DIR"
git -C ~/src/github.com/aya-215/life add "monthly/"
git -C ~/src/github.com/aya-215/life commit -m "monthly: ${target_month} 月初目標設定"
git -C ~/src/github.com/aya-215/life push
```

**goals モードはここで終了。** 以降の Phase は実行しない。

---

### Phase 2: データ収集

#### 2-A: 日報データ取得

対象月の全日報ファイルを読み込む：

```bash
LIFE_DIR=~/src/github.com/aya-215/life
for blog_file in ${LIFE_DIR}/blog/${year_month_compact}*.md; do
  [ -f "$blog_file" ] && echo "$blog_file"
done
```

各日報から以下を抽出する：
- `就寝: HH:MM` — 時刻部分のみ（`就寝: :` は空データなのでスキップ）
- `起床: HH:MM` — 時刻部分のみ（`起床: :` は空データなのでスキップ）
- `調子: X/5` — 数値部分のみ（`調子: /5` は空データなのでスキップ）
- `### ルーティン` — チェックボックスの状態（セクションが存在しない場合はスキップ）
- `## 📝 サマリー` — Work/Personal の活動内容・コミット数
- `## 💡 メモ` — 自由記述メモ（感情、気づき、反省）
- `## 📋 未完了タスク` — タスク情報

**空データの判定:**
- `就寝: :`（コロンのみで時刻なし）→ スキップ
- `起床: :`（コロンのみで時刻なし）→ スキップ
- `調子: /5`（スラッシュの前に数値なし）→ スキップ
- `### ルーティン` セクションなし（テンプレート導入前）→ スキップ

#### 2-B: 週報データ取得

対象月に含まれる週の週報を読み込む：

```bash
# 対象月の範囲と重なる週報を特定
for weekly_file in ${LIFE_DIR}/weekly/*-weekly.md; do
  monday_date=$(basename "$weekly_file" | sed 's/-weekly.md//')
  sunday_date=$(TZ=Asia/Tokyo date -d "$monday_date +6 days" +%Y-%m-%d)
  # 週の範囲が対象月と重なるかチェック
  if [[ "$sunday_date" >= "$first_day" && "$monday_date" <= "$last_day" ]]; then
    echo "$weekly_file"
  fi
done
```

各週報から以下を抽出する：

**新形式（2026年2月〜、`## 今週の指標` あり）:**
- `## 今週の指標` — 記録日数、調子の傾向、平均就寝、平均起床
- `## プロジェクト別活動` — Work/Personal 別の活動詳細
- `## 今週の気づき・学び` — 気づき・学び
- `## 来週への引き継ぎ` — 引き継ぎタスク
- `## KPT（振り返り）` — Keep/Problem/Try
- `*先週のTry達成状況:*` — Try達成（✅/❌/△）

**旧形式（〜2026年1月、`## 今週の指標` なし）:**
- `## 重要な活動・決定事項` — 活動詳細（プロジェクト別活動の代わり）
- `## 個人開発・環境整備` — Personal 活動
- `## 今週の気づき・学び` — 気づき・学び
- KPT/指標セクションなし → KPTトレンド分析はスキップ

#### 2-C: Git コミットデータ取得

```bash
# Work コミット（月間合計）
for repo in ~/src/github.com/ebase-dev/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline \
    --since="${first_day} 00:00" \
    --until="$(TZ=Asia/Tokyo date -d "$last_day +1 day" +%Y-%m-%d) 00:00" \
    --author="$author_email" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$repo_name: $count"
done

# Personal コミット（月間合計）
# dotfiles
count=$(git -C ~/.dotfiles log --oneline \
  --since="${first_day} 00:00" \
  --until="$(TZ=Asia/Tokyo date -d "$last_day +1 day" +%Y-%m-%d) 00:00" \
  --author="$(git config user.email)" 2>/dev/null | wc -l)
[ "$count" -gt 0 ] && echo "dotfiles: $count"

for repo in ~/src/github.com/aya-215/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline \
    --since="${first_day} 00:00" \
    --until="$(TZ=Asia/Tokyo date -d "$last_day +1 day" +%Y-%m-%d) 00:00" \
    --author="$author_email" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "$repo_name: $count"
done
```

#### 2-D: GitHub タスク完了データ取得

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)

# 対象月に close された task ラベル付き Issue
GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
  --state closed --label task \
  --search "closed:${first_day}..${last_day}" \
  --json number,title,closedAt \
  --jq '.[] | "\(.number) \(.title) (\(.closedAt[:10]))"'
```

#### 2-E: Claude 会話セッション数

```bash
# 対象月の Claude 会話ファイルを列挙してセッション数を集計
for claude_file in ~/.nb/claude/${target_month}-*.md; do
  [ -f "$claude_file" ] || continue
  date_part=$(basename "$claude_file" .md)
  # プロジェクト数をカウント
  proj_count=$(grep -cE "^## [a-z]+(-[a-z]+)*$" "$claude_file" 2>/dev/null || echo 0)
  echo "$date_part: $proj_count projects"
done
```

**注意:** Claude 会話ファイルが存在しない場合は、このセクションをスキップする。

### Phase 3: データ分析（自動）

収集したデータを以下の観点で分析する。

#### 3-A: 量的指標の集計

- **日報記録率**: 記録日数 / 月の日数 × 100
- **調子**: 全体的な傾向をレンジで記述（例: 「だいたい3〜4」「概ね好調」）。特に良かった/悪かった日とその理由をピックアップ。データ件数を必ず併記
- **就寝時刻**: 平均、最早（日付付き）、最遅（日付付き）。データ件数を必ず併記
- **起床時刻**: 平均、最早（日付付き）、最遅（日付付き）。データ件数を必ず併記
- **ルーティン達成率**: 項目別の月間達成率、全項目完遂率。データ件数を必ず併記
- **コミット数**: Work合計、Personal合計、リポジトリ別内訳
- **Claude セッション**: 活動日数、推定総セッション数

#### 3-B: パターン分析

以下の分析は、十分なデータ（5日分以上）がある場合のみ実施する。データ不足の場合は注記して省略する。

- **曜日別パターン** — 曜日ごとの平均コミット数をテーブルで表示
- **週間推移** — 月の前半 vs 後半でコミット数に変化があるか

#### 3-C: KPT トレンド分析

週報のKPTセクションから以下を集約する（KPTがある週報のみ対象）:

- **Keep の持続性** — 月を通じて何週続いたか（🟢全週 / 🟡一部 / 🔴1週のみ）
- **Problem の再発** — 同じ課題が何週出現したか。状態を判定（🔴未解決 / 🟡改善傾向 / 🟢解決）
- **Try 達成率** — ✅/❌/△ の全体集計と、各Try項目の詳細

#### 3-D: プロジェクト活動ナラティブ

週報のプロジェクト別活動を時系列で統合し、月間でのプロジェクト進捗ストーリーを生成する。

### Phase 4: ユーザーインタラクション（対話）

AskUserQuestion を使って以下を収集する。

まず最初に「対話的に振り返りますか？スキップしてデータから自動生成もできます」と確認する。
スキップの場合は、すべての項目をデータから自動推定してサマリーに反映する（目標振り返りのみ省略）。

対話する場合、以下の順で質問する:

1. **振り返り**: 「今月を一言で表すと？」
2. **Top 3 成果**: データから候補を3-5個提示 → ユーザーが選択・修正
3. **Top 3 学び**: 週報の気づきから候補を提示 → ユーザーが選択・修正
4. **目標振り返り**（サマリーファイルに目標セクションが既にある場合）:
   - 各目標について達成度を確認（✅ 達成 / ❌ 未達成 / △ 部分達成）
   - 一言メモを添えてもらう
5. **来月の目標**: 今月のProblem/Tryから候補を提示 → ユーザーが選択・修正・追加

### Phase 5: サマリーファイル生成

出力先: `~/src/github.com/aya-215/life/monthly/YYYY-MM-summary.md`

**既存のサマリーファイル（goals モードで作成済み）がある場合は、目標セクションを保持しつつ他セクションを追記する。** 新規の場合は全体を生成する。

```markdown
# YYYY年MM月 月報サマリー

## 📊 月間ダッシュボード

| 指標 | 値 |
|------|-----|
| 日報記録率 | XX/YY日 (ZZ%) |
| 調子 | だいたいX〜Y（記録X日分） |
| 就寝平均 | HH:MM（記録X日分） |
| 起床平均 | HH:MM（記録X日分） |
| ルーティン完遂率 | XX%（記録X日分） |
| Work コミット | XXX commits / X repos |
| Personal コミット | XXX commits / X repos |

## 🎯 今月の目標

<!-- goals モードで月初に設定。月末レポート生成時に達成状況を追記 -->

| 目標 | 達成 | メモ |
|------|------|------|
| [目標1] | ✅/❌/△ | [一言メモ] |
| [目標2] | ✅/❌/△ | [一言メモ] |
| [目標3] | ✅/❌/△ | [一言メモ] |

（目標未設定の場合はこのセクションを省略）

## 🏆 Top 3 成果

1. [成果1]
2. [成果2]
3. [成果3]

## 💡 Top 3 学び

1. [学び1]
2. [学び2]
3. [学び3]

## 🔄 KPT サマリー

- **月間 Try 達成率**: X/Y (ZZ%)
- **継続できた Keep**: [月を通じて続いたこと]
- **繰り返した Problem**: [何度も出てきた課題]

（KPT データがない場合は省略）

## 📝 振り返り

[2-3文の月間振り返り]

## 🎯 来月に向けて

- [来月の意識事項1]
- [来月の意識事項2]
- [来月の意識事項3]
```

### Phase 6: 詳細ファイル生成

出力先: `~/src/github.com/aya-215/life/monthly/YYYY-MM-monthly.md`

```markdown
# YYYY年MM月 月報（詳細）

> データソース: 日報 XX件 / 週報 XX件 / git log
> 生成日: YYYY-MM-DD

---

## 1. 量的ダッシュボード

### 日報記録
- 記録日数: XX/YY日 (ZZ%)
- 調子記録率: XX日
- 就寝記録率: XX日
- 起床記録率: XX日

### 調子の傾向

- 全体: だいたいX〜Y（記録X日分）
- 特に良かった日: MM/DD（理由: [メモから推測]）
- 特に悪かった日: MM/DD（理由: [メモから推測]）

（特筆すべき日がない場合は「全体: 〜」のみ）

### 就寝時刻

- 平均: HH:MM
- 最早: HH:MM (MM/DD)
- 最遅: HH:MM (MM/DD)
- 24:00以前の日数: X日

### 起床時刻

- 平均: HH:MM
- 最早: HH:MM (MM/DD)
- 最遅: HH:MM (MM/DD)
- 8:00以前の日数: X日

### ルーティン達成率

| 項目 | 達成日数 | 達成率 |
|------|---------|--------|
| 🌙 筋トレ | X/Y日 | XX% |
| 🌅 朝食 | X/Y日 | XX% |
| 🌅 肌ケア（3点セット） | X/Y日 | XX% |
| 部屋の片づけ | X/Y日 | XX% |
| **全項目完遂** | X/Y日 | XX% |

（ルーティンデータがある場合のみ表示。Y=ルーティンセクションが存在する日数）

#### 週別推移

| 週 | 筋トレ | 朝食 | 肌ケア | 片づけ | 完遂 |
|----|--------|------|--------|--------|------|
| W1 | X/Y | X/Y | X/Y | X/Y | X/Y |
| W2 | X/Y | X/Y | X/Y | X/Y | X/Y |
| W3 | X/Y | X/Y | X/Y | X/Y | X/Y |
| W4 | X/Y | X/Y | X/Y | X/Y | X/Y |

### コミット活動

- Work: XXX commits across X repos
- Personal: XXX commits across X repos
- 合計: XXX commits

#### リポジトリ別コミット数

| リポジトリ | カテゴリ | コミット数 |
|-----------|----------|-----------|
| [repo1]   | Work     | XX        |
| [repo2]   | Personal | XX        |

### Claude セッション（データがある場合のみ）

- 活動日数: XX日
- 推定総セッション数: XX

---

## 2. パターン分析

### 曜日別パターン

| 曜日 | 平均コミット | 傾向 |
|------|------------|------|
| 月   | X.X        | [メモ] |
| 火   | X.X        | [メモ] |
| 水   | X.X        | [メモ] |
| 木   | X.X        | [メモ] |
| 金   | X.X        | [メモ] |
| 土   | X.X        | [メモ] |
| 日   | X.X        | [メモ] |

### 週間推移

| 週 | 就寝平均 | 起床平均 | Work commits | Personal commits |
|----|---------|---------|-------------|-----------------|
| W1 (MM/DD-) | HH:MM | HH:MM | XX | XX |
| W2 (MM/DD-) | HH:MM | HH:MM | XX | XX |
| W3 (MM/DD-) | HH:MM | HH:MM | XX | XX |
| W4 (MM/DD-) | HH:MM | HH:MM | XX | XX |
| W5 (MM/DD-) | HH:MM | HH:MM | XX | XX |

---

## 3. プロジェクト別活動詳細

### Work

#### [プロジェクト名1]
- 活動週: W1, W2, W3
- コミット数: XX
- 主な成果:
  - [週ごとの活動をまとめたナラティブ]

#### [プロジェクト名2]
...

### Personal

#### [プロジェクト名1]
...

---

## 4. KPT トレンド分析

（KPT データがある週報がない場合はこのセクション全体を省略）

### Keep（月を通じて続けたこと）

| Keep 項目 | 出現週 | 持続 |
|-----------|--------|------|
| [Keep1]   | W1, W2, W3, W4 | 🟢 全週 |
| [Keep2]   | W1, W2 | 🟡 前半のみ |

### Problem（繰り返し出現した課題）

| Problem 項目 | 出現週 | 状態 |
|-------------|--------|------|
| [Problem1]  | W1, W2, W3, W4 | 🔴 未解決 |
| [Problem2]  | W1, W3 | 🟡 改善傾向 |

### Try 達成率

- 全Try項目数: XX
- ✅ 達成: XX (XX%)
- ❌ 未達成: XX (XX%)
- △ 部分達成: XX (XX%)

#### Try 達成詳細

| 週 | Try 項目 | 結果 |
|----|---------|------|
| W1 | [Try1]  | ✅   |
| W1 | [Try2]  | ❌   |
| W2 | [Try3]  | △   |

---

## 5. タスク完了分析

### 完了タスク（X件）
- [タスク名] (完了日)
- ...

### 月末時点の未完了タスク
- [最終日報から抽出した未完了タスク]

---

## 6. 気づき・学びの集約

### 技術面
- [週報の「気づき・学び」から技術的な項目を集約]

### 生活・習慣面
- [生活面の項目を集約]

### 仕事の進め方・コミュニケーション
- [仕事の進め方に関する項目を集約]

---

## 7. 月間メモハイライト

[日報の💡メモから特に印象的なもの、感情の変化が見られるもの、重要な出来事をピックアップ]

---

*生成日: YYYY-MM-DD*
*データソース: 日報 XX件、週報 XX件、git log*
```

### Phase 7: ファイル保存 & push

```bash
MONTHLY_DIR=~/src/github.com/aya-215/life/monthly
mkdir -p "$MONTHLY_DIR"

# サマリーファイルと詳細ファイルを Write ツールで書き込む

# git commit & push
git -C ~/src/github.com/aya-215/life add "monthly/"
git -C ~/src/github.com/aya-215/life commit -m "monthly: ${target_month} 月報"
git -C ~/src/github.com/aya-215/life push
```

保存後、生成した2ファイルのパスを表示する。

---

## 重要なルール

1. **サマリーファイルは上書きではなく更新**: 既存のサマリーファイル（goalsモードで作成済みの目標セクションなど）がある場合は保持しつつ更新する
2. **週報が存在しない週はスキップ**: 日報データのみで集計する
3. **データ件数の併記**: 調子・起床などサンプルサイズが小さい指標は必ず「（記録X日分）」を付ける
4. **週の境界処理**: 月をまたぐ週は、その月に含まれる日のデータのみを集計する
5. **KPT分析の対象**: KPTセクションがある週報のみ。旧形式（KPTなし）は「気づき・学び」で代用
6. **goals セクションの保護**: goals モードで設定した目標は月末レポート生成時に上書きしない。達成状況のみ追記
7. **セクションの動的生成**: データが存在しないセクションは省略する（空テーブルを出さない）
8. **ルーティン集計のルール**:
   - `### ルーティン` セクションが存在しない日報（テンプレート導入前）はスキップ
   - 肌ケアは「化粧水・乳液・日焼け止め」の3項目すべて `[x]` で完遂
   - 週別推移テーブルは月の各週（月曜始まり）でグループ化
   - データが0日の場合はルーティン関連のセクション全体を省略
9. **就寝時刻の集計**: `就寝: HH:MM` を収集。`就寝: :` は空データとしてスキップ

---

## gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```

以降の `gh` コマンドには `GH_TOKEN="$GH_TOKEN"` を付与する。

> **注意:** `echo "$json_var" | jq` は Issue body 内の `\n` をリテラル改行に展開してJSONパースエラーになる。
> `printf '%s\n' "$json_var" | jq` を使うこと。

---

## エラー処理

| 状況 | 対応 |
|------|------|
| life リポジトリの pull 失敗 | 警告を表示して続行（ローカルのファイルを使用） |
| 日報データが1日も取得できない | 「日報データが見つかりません」と表示して終了 |
| 週報が0件 | 日報データのみで月報を生成し、注記を付ける |
| monthly/ ディレクトリが存在しない | `mkdir -p` で自動作成して続行 |
| 目標設定なし（goalsモード未実行） | 「🎯 今月の目標」セクションを省略 |
| Claude 会話履歴なし | スキップして他のソースで生成 |
| KPTデータなし（旧形式週報のみ） | KPTトレンド分析を省略し、「気づき・学び」で代用 |
| パターン分析のデータ不足（5日未満） | 「データ不足のため分析を省略」と記載 |

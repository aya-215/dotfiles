---
name: quarterly-dev-report
description: 四半期の開発状況報告や振り返りが必要なときに使う。複数リポジトリの活動調査、自分の貢献度の可視化、期末報告書の作成。
---

# 四半期開発状況調査・報告書生成

複数リポジトリの git log / PR / Issue を集計し、自分の貢献度を含む調査報告書を Markdown で出力する。

## 引数

`$ARGUMENTS` — `<四半期> <年度> <リポパス1> [リポパス2] ...`

例: `4Q 2025 ~/src/github.com/ebase-dev/ebase-middleware-mcp ~/src/github.com/ebase-dev/ebase-portal-chat`

**引数なし・不足時は AskUserQuestion で順番に収集する:**

1. 四半期を聞く（選択肢: 1Q, 2Q, 3Q, 4Q）
2. 年度を聞く（選択肢: 直近3年度を提示。例: 2025, 2024, 2023）
3. 対象リポジトリのパスを聞く（自由入力。複数ある場合はカンマまたはスペース区切り）

引数の一部だけ指定された場合は、不足分のみ聞く。

## 固定パラメータ

- **GitHubユーザー**: `eBASE-Mori`（git author フィルタ: `Mori`）
- **出力先**: `/home/aya/.dotfiles/docs/`
- **四半期定義（会計年度）**: 1Q:4-6月, 2Q:7-9月, 3Q:10-12月, 4Q:1-3月
- **日報・週報**: `~/src/github.com/aya-215/life/`（日報: `blog/YYYYMMDD.md`, 週報: `weekly/YYYY-MM-DD-weekly.md`）

## 手順

### Phase 0: パラメータ収集 & 日付算出

引数をパースし、四半期から日付範囲を算出する。

```bash
# 四半期→日付範囲の算出例
# 4Qは年度跨ぎ注意: 2025年度4Q = 2026/1/1〜2026/3/31
case "$QUARTER" in
  1Q) START="${YEAR}-04-01"; END="${YEAR}-07-01" ;;
  2Q) START="${YEAR}-07-01"; END="${YEAR}-10-01" ;;
  3Q) START="${YEAR}-10-01"; END="$((YEAR+1))-01-01" ;;
  4Q) START="$((YEAR+1))-01-01"; END="$((YEAR+1))-04-01" ;;
esac
# git log の --after/--before に使う（before は排他的）
```

gh CLI認証を切り替える:

```bash
gh auth switch --user eBASE-Mori 2>/dev/null || true
```

### Phase 1: データ収集（各リポに対して並行実行）

各リポジトリで以下を実行する。**リポジトリが複数ある場合は Task エージェントで並行実行する。**

#### 全体の活動

```bash
cd "$REPO_PATH"

# 全コミット一覧
git log --oneline --after="$AFTER" --before="$BEFORE" --all

# ファイル変更の詳細
git log --after="$AFTER" --before="$BEFORE" --all --stat

# メンバー別コミット数
git shortlog -sn --after="$AFTER" --before="$BEFORE" --all

# PR一覧（マージ済み含む全状態）
gh pr list --state all \
  --search "created:${START}..${END_INCLUSIVE}" \
  --limit 100 \
  --json number,title,state,createdAt,mergedAt,author,additions,deletions

# Issue一覧
gh issue list --state all \
  --search "created:${START}..${END_INCLUSIVE}" \
  --limit 100 \
  --json number,title,state,createdAt,closedAt,author,labels
```

#### 自分の貢献度

```bash
# 自分のコミット数
git log --oneline --author="Mori" --after="$AFTER" --before="$BEFORE" --all | wc -l

# 全体コミット数
git log --oneline --after="$AFTER" --before="$BEFORE" --all | wc -l

# 自分のマージ済みPR（行数付き）
gh pr list --state merged \
  --search "author:eBASE-Mori created:${START}..${END_INCLUSIVE}" \
  --json number,title,mergedAt,additions,deletions --limit 50
```

担当割合を算出する（自分のコミット数 / 全体コミット数）。

#### 日報・週報の収集

life リポジトリを最新化してから対象期間のファイルを読み込む。

```bash
git -C ~/src/github.com/aya-215/life pull

LIFE_DIR=~/src/github.com/aya-215/life

# 対象期間の日報ファイルを列挙（例: 3Q 2025 → 20251001〜20251231）
ls ${LIFE_DIR}/blog/ | grep -E "^2025(10|11|12)[0-9]{2}\.md$"

# 対象期間の週報ファイルを列挙
ls ${LIFE_DIR}/weekly/ | grep -E "^2025-(10|11|12)-[0-9]{2}-weekly\.md$"
```

各ファイルから以下のセクションを抽出する:
- 日報: `## 📝 今日のサマリー` の Work 部分、`## 💡 メモ`、`詰まったこと・解決策`
- 週報: `## 今週の気づき・学び`、`## 重要な活動・決定事項`

該当ファイルが存在しない期間はスキップする。

### Phase 2: 報告書生成

収集データを分析し、以下の構成で Markdown を生成する。
**テンプレートの詳細は `docs/3q-2025-development-report.md` を参照する。**

#### Part A: 調査データ

1. **全体サマリー** — 数値テーブル（コミット数/PR数/行数変更、担当割合）
2. **リポジトリ別 — 自分のPR一覧** — 時系列テーブル（PR番号、タイトル、マージ日、追加/削除行数）
3. **リポジトリ別 — テーマ別整理** — PR を内容に応じて自動グルーピング
4. **リポジトリ別 — 他メンバーの主な成果** — チーム全体像として記載
5. **未解決課題** — Open Issue の一覧
6. **主要テーマ** — 自分視点での四半期サマリー

#### Part B: 所感（下書き自動生成）

収集データから以下3セクションの下書きを推測・生成する。
あくまで下書きなので、ユーザーが後から加筆修正する前提で出力する。
各セクションの冒頭に `<!-- TODO: 加筆修正してください -->` を付ける。

**7. 担当割合**
- リポジトリごとのコミット比率をパーセンテージで記載
- 「案件全体の何%を担当したか」を数値で示す

**8. アピールしたい点**
以下の観点から推測して箇条書きで下書きする:
- 主体的に担当した領域（自分が author の PR テーマから推測）
- 技術的チャレンジ（アーキテクチャ変更、新技術導入等の大規模 PR から推測）
- チームへの貢献（レビュー、ドキュメント整備、基盤構築等）
- 週報の `重要な活動・決定事項` から技術的意思決定や成果を抽出

**9. 苦労したこと・難しかったこと・反省点**
以下の観点から推測して箇条書きで下書きする:
- 日報の `💡 メモ` `詰まったこと・解決策` から具体的なエピソードを抽出
- 週報の `今週の気づき・学び` から苦労の末の学びを抽出
- 大規模な変更行数の PR（複雑さの指標）
- Open Issue として残っている技術的負債

### Phase 3: 保存

```bash
OUTPUT="/home/aya/.dotfiles/docs/${QUARTER_LOWER}-${YEAR}-development-report.md"
# 例: docs/4q-2025-development-report.md
```

Write ツールでファイルに保存し、パスを表示する。

## エラー処理

| 状況 | 対応 |
|------|------|
| リポジトリパスが存在しない | エラー表示してスキップ |
| gh CLI認証エラー | `gh auth switch --user eBASE-Mori` 試行、ダメなら git log のみで続行 |
| PR/Issue が 0件 | 「該当なし」と記載して続行 |
| コミットが 0件 | 「該当期間のコミットなし」と記載 |
| 日報・週報が対象期間に存在しない | Part B を git/PR データのみで生成し、注記を付ける |
| life リポの pull 失敗 | 警告表示してローカルファイルで続行 |

# work-report skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 月・水・金の社内作業報告用に、対象期間（実行曜日に応じて自動決定）の作業内容を日報サマリー・gitログ（仕事関連リポジトリのみ）・Rocket Chat・Claudeセッション要約から集計し、「カテゴリ→サブプロジェクト→箇条書き」形式でチャット上にコピペ用テキストとして出力する `work-report` skillを新規作成する。個人リポジトリ（dotfiles・life等）は対象外。

**Architecture:** 既存の `daily-review`/`weekly-report` skillと同じ構成（`~/.claude/skills/<name>/SKILL.md` 1ファイルにMarkdown手順書＋bashコマンド例を記述）。実行時はClaudeがこのSKILL.mdの手順を読んで、bashコマンドでデータ取得→Claudeが分類・要約→チャットに整形出力、という流れ。自動テストは書けない（LLM手順書のため）ので、検証は「実際にskillを実行してサンプル出力が仕様通りの構造になっているか」を目視確認する形で行う。

**Tech Stack:** Markdown（SKILL.mdフォーマット）、bash、`gh` CLI、`mcp__rocketchat__*` ツール

## Global Constraints

- skillの配置先は `/home/aya/.claude/skills/work-report/SKILL.md`（既存skillと同じ階層構造）
- gh CLIの操作はすべて `aya-215` アカウントで実行する（`GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)` を先頭に置き、以降のコマンドに `GH_TOKEN="$GH_TOKEN"` を付与）
- 対象リポジトリ: `~/src/github.com/ebase-dev/*`（AIカテゴリ）、`/mnt/d/tomcat/webapps/eb-api-extended`（AIカテゴリ、`/mnt/`配下のため index.lock 注意）、`/mnt/d/tomcat/webapps/hankyu`（その他カテゴリ、GitBucketリポジトリ、`/mnt/`配下のため index.lock 注意）
- 個人リポジトリ（`~/.dotfiles`、`~/src/github.com/aya-215/*` など）は報告対象外。取得しない
- 上記gitログ対象以外の「その他（仕事関連・AI以外）」の作業は、日報📝サマリーとClaudeセッション要約（`~/.nb/claude/sessions/`）からのみ拾う（網羅的なgitログ探索はしない）
- ファイル保存・git commit・pushは一切行わない。出力はチャット上のプレーンテキストのみ
- `echo "$json_var" | jq` はIssue body内の `\n` がリテラル改行に展開されパースエラーになるため使わない。`printf '%s\n' "$json_var" | jq` を使う
- 設計書は `docs/superpowers/specs/2026-07-01-work-report-design.md`（このplanと矛盾があれば設計書を正とする）

---

### Task 1: 対象リポジトリの所在確認（調査済み・完了）

`eb-api-extended` の実パスは調査済み: **`/mnt/d/tomcat/webapps/eb-api-extended`**（`~/src/github.com/ebase-dev/` 配下ではなく `/mnt/d/tomcat/webapps/` 直下にある。`git remote -v` で GitHub `ebase-dev/eb-api-extended` を指していることを確認済み）。

`hankyu`（阪急キッチンエール）の実パスも調査済み: **`/mnt/d/tomcat/webapps/hankyu`**（`git remote -v` で社内GitBucket `http://192.168.208.80:8080/gitbucket/git/hankyu_kitchenyell/ebase-web.git` を指していることを確認済み。GitHubではなくGitBucketリポジトリだが、ローカルクローンへの読み取り専用 `git log` のみなので `mcp__gitbucket__*` ツールは不要）。

いずれも `/mnt/` 配下のリポジトリのため、ユーザーのCLAUDE.mdルールにより `index.lock` エラーが出た場合は「削除して即リトライ」対処が必要（SKILL.mdには通常のgit logのみでロックを取らない読み取り操作なのでリスクは低いが、念のためSKILL.md側にも一言注記する）。

`ebase-dev` 配下の一覧は以下（Task 3のgitログ取得コマンドは `~/src/github.com/ebase-dev/*/` のワイルドカードで全リポジトリを自動走査するため、個別列挙は不要）:

```bash
ls -d ~/src/github.com/ebase-dev/*/ 2>/dev/null
```

このタスクに実行ステップはない（調査完了、結果は上記の通りTask 3に反映済み）。

**Files:**
- なし

**Interfaces:**
- Produces: `eb-api-extended` の絶対パス = `/mnt/d/tomcat/webapps/eb-api-extended`、`hankyu` の絶対パス = `/mnt/d/tomcat/webapps/hankyu`（いずれもTask 3で使用）

---

### Task 2: SKILL.md の骨格・frontmatter・対象期間ロジックを作成

**Files:**
- Create: `/home/aya/.claude/skills/work-report/SKILL.md`

**Interfaces:**
- Consumes: Task 1で確定した `eb-api-extended` の絶対パス（`/mnt/d/tomcat/webapps/eb-api-extended`）
- Produces: SKILL.mdのfrontmatter（`name: work-report`）と「対象期間の決定」節。Task 3以降はこのファイルに追記していく

- [ ] **Step 1: SKILL.mdを新規作成し、frontmatterと概要、対象期間ロジックを書く**

```markdown
---
name: work-report
description: 週次の社内作業報告用に、対象期間の作業内容をカテゴリ別の箇条書きでまとめる
allowed-tools: Read, Bash, AskUserQuestion
version: 1.0.0
---

# 作業報告まとめ

月・水・金の社内向け作業報告のために、対象期間の作業内容を日報サマリー・gitログ・Rocket Chatから集計し、コピペしやすい箇条書き形式でチャットに出力する。

ファイル保存やgit commitは行わない。KPTや生産性指標などの追加集計もしない（`weekly-report` skillとは目的が異なる）。

---

## 対象期間の決定

実行日の曜日によって対象期間の起点が変わる。

| 実行曜日 | 対象期間 |
|---|---|
| 金曜 | 今週月曜 〜 今日 |
| 上記以外（月・水・その他任意の曜日） | 先週の同じ曜日 〜 今日 |

金曜だけ「今週月曜起点」にするのは、先週金曜の作業はすでに前回報告済みのため、今回の報告に紛れ込ませないようにするため。

```bash
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
dow=$(TZ=Asia/Tokyo date +%u)  # 1=Mon ... 5=Fri, 7=Sun

if [ "$dow" -eq 5 ]; then
  # 金曜: 今週月曜起点
  start_date=$(TZ=Asia/Tokyo date -d "$today -$((dow-1)) days" +%Y-%m-%d)
else
  # それ以外: 先週の同じ曜日起点
  start_date=$(TZ=Asia/Tokyo date -d "$today -7 days" +%Y-%m-%d)
fi
end_date="$today"

echo "対象期間: $start_date 〜 $end_date"
```

土日も対象期間に含める場合はデータ取得を試みるが、作業実績がないのが正常系のため、0件でもエラー扱いにしない。
```

- [ ] **Step 2: 動作確認（曜日ロジックが正しいか手計算で検証）**

Run:
```bash
TZ=Asia/Tokyo date -d "2026-07-06 -$(( $(TZ=Asia/Tokyo date -d "2026-07-06" +%u) - 1 )) days" +%Y-%m-%d
```
2026-07-06は月曜日。Expected: `2026-06-29`（先週月曜、上記テーブル通り「上記以外」ルールで先週同曜日起点）

```bash
TZ=Asia/Tokyo date -d "2026-07-08 -7 days" +%Y-%m-%d
```
2026-07-08は水曜日。Expected: `2026-07-01`（先週水曜）

```bash
TZ=Asia/Tokyo date -d "2026-07-10 -$(( $(TZ=Asia/Tokyo date -d "2026-07-10" +%u) - 1 )) days" +%Y-%m-%d
```
2026-07-10は金曜日（dow=5）。Expected: `2026-07-06`（今週月曜）

3つとも期待値と一致することを確認する。一致しなければ日付計算式を見直す。

- [ ] **Step 3: コミット不要（プロジェクトのgit管理下ではなく `~/.claude/skills/` 配下のため、dotfilesリポジトリのcommit対象外）**

`~/.claude/skills/` は `~/.dotfiles` の管理外ディレクトリなので、このタスクではgit commitを行わない。ファイル作成のみで完了とする。

---

### Task 3: データ取得コマンド（日報サマリー・gitログ・RocketChat・Claudeセッション要約）をSKILL.mdに追記

**Files:**
- Modify: `/home/aya/.claude/skills/work-report/SKILL.md`

**Interfaces:**
- Consumes: Task 2で定義した `$start_date` / `$end_date` 変数、Task 1で確定した対象リポジトリ一覧
- Produces: 「データソース」節・「コマンド例」節（Task 4のカテゴリ分類ロジックが参照する生データの取得手順）

- [ ] **Step 1: 「データソース」節を追記する**

Task 2で作成したSKILL.mdの末尾に追記:

```markdown
---

## データソース

個人リポジトリ（`~/.dotfiles`、`~/src/github.com/aya-215/*` など）は報告対象外のため取得しない。

| ソース | 取得先 | 用途 |
|---|---|---|
| 日報の📝サマリー（Work欄） | `aya-215/life` の日報 Issue（open）または `blog/YYYYMMDD.md`（close済み） | 対象期間内の各日からWork欄を抽出 |
| gitログ（AIカテゴリ） | `~/src/github.com/ebase-dev/*`、`/mnt/d/tomcat/webapps/eb-api-extended` | 日報の書き漏れを補完 |
| gitログ（その他カテゴリ） | `/mnt/d/tomcat/webapps/hankyu` | 日報の書き漏れを補完 |
| Rocket Chat（`mori.a-times`） | `mcp__rocketchat__*` ツール | 自分の作業・レビュー作業を対象期間で取得 |
| Claudeセッション要約 | `~/.nb/claude/sessions/YYYY-MM-DD/*.md` | git対象外の「その他」仕事関連作業（hankyu以外）を補完 |

## gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```

以降のコマンド例では `$GH_TOKEN` を省略しているが、すべての `gh` コマンドに `GH_TOKEN="$GH_TOKEN"` を付与すること。

## コマンド例

### 対象期間内の日報Issue一覧を特定する

対象期間の各日付についてループし、Issueまたはblog mdを取得する。

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
LIFE_REPO=~/src/github.com/aya-215/life

d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  blog_file="$LIFE_REPO/blog/$(echo "$d" | tr -d '-').md"
  if [ -f "$blog_file" ]; then
    echo "=== $d (blog md) ==="
    sed -n '/^## 📝 サマリー/,/^## /p' "$blog_file" | sed '$d'
  else
    issue_num=$(GH_TOKEN="$GH_TOKEN" gh issue list --repo aya-215/life \
      --search "in:title ${d} の記録" \
      --state all --label memo \
      --json number --jq '.[0].number' 2>/dev/null)
    if [ -n "$issue_num" ]; then
      echo "=== $d (issue #$issue_num) ==="
      GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life \
        --json body --jq '.body' 2>/dev/null | \
        sed -n '/^## 📝 サマリー/,/^## /p' | sed '$d'
    else
      echo "=== $d: 日報なし（スキップ） ==="
    fi
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

> **注意:** `echo "$json_var" | jq` はIssue body内の `\n` がリテラル改行に展開されパースエラーになるため使わない。`printf '%s\n' "$json_var" | jq` を使う。

### gitログ取得（AIカテゴリ対象リポジトリ）

Task 1で確定した実パスを使う（下記はすでに実パス）。

```bash
for repo in ~/src/github.com/ebase-dev/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== $repo_name ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
done

# eb-api-extended（/mnt/配下。index.lockエラーが出た場合は `rm -f "$repo/.git/index.lock"` してリトライ）
repo=/mnt/d/tomcat/webapps/eb-api-extended
if [ -d "$repo" ]; then
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== eb-api-extended ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
fi
```

### gitログ取得（その他カテゴリ: hankyu）

```bash
# hankyu（阪急キッチンエール、社内GitBucketリポジトリ。/mnt/配下のためindex.lockエラー時はrm -f "$repo/.git/index.lock"してリトライ）
repo=/mnt/d/tomcat/webapps/hankyu
if [ -d "$repo" ]; then
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  echo "=== hankyu ==="
  git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null
fi
```

### Claudeセッション要約の取得（その他カテゴリの補完用）

`hankyu` 以外の「その他（仕事関連・AI以外）」の作業はgitログでは網羅できないため、Claudeセッション要約から拾う。SessionEnd hookが自動生成済みのため手動同期は不要。

```bash
d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  if [ -d ~/.nb/claude/sessions/"$d" ]; then
    for sf in ~/.nb/claude/sessions/"$d"/*.md; do
      proj=$(sed -n 's/^project: //p' "$sf" | head -1)
      echo "=== $d: $proj ==="
      awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=3{print}' "$sf"
    done 2>/dev/null
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### Rocket Chat 取得

```bash
# room_id特定
# mcp__rocketchat__list_channels（filter: "mori.a-times"）を使う

# 対象期間の発言取得（oldest/latestで絞り込み、JST→UTC変換に注意）
# mcp__rocketchat__get_channel_history（room_id, oldest: "${start_date}T00:00:00.000Z", latest: "${end_date}T23:59:59.000Z"）
# username = mori.a の発言のみ抽出
# threadIdがあるメッセージは mcp__rocketchat__get_thread_messages でスレッド展開
```
```

- [ ] **Step 2: 動作確認（実際にコマンドを実行し、対象期間のデータが1件以上取れることを確認）**

```bash
today=$(TZ=Asia/Tokyo date +%Y-%m-%d)
dow=$(TZ=Asia/Tokyo date +%u)
if [ "$dow" -eq 5 ]; then
  start_date=$(TZ=Asia/Tokyo date -d "$today -$((dow-1)) days" +%Y-%m-%d)
else
  start_date=$(TZ=Asia/Tokyo date -d "$today -7 days" +%Y-%m-%d)
fi
end_date="$today"

for repo in ~/src/github.com/ebase-dev/*/; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null | wc -l)
  echo "$repo_name: $count commits"
done

for repo in /mnt/d/tomcat/webapps/eb-api-extended /mnt/d/tomcat/webapps/hankyu; do
  repo_name=$(basename "$repo")
  author_email=$(git -C "$repo" config user.email 2>/dev/null || git config user.email)
  count=$(git -C "$repo" log --oneline --since="$start_date 00:00" --until="$end_date 23:59" --author="$author_email" 2>/dev/null | wc -l)
  echo "$repo_name: $count commits"
done
```

Expected: エラーなく各リポジトリのコミット数が出力される（0件のリポジトリがあってもよい、直近の実データに依存するため合計が1件以上あればOK）

- [ ] **Step 3: 完了（ファイル編集のみ、commit不要）**

---

### Task 4: カテゴリ分類ロジックと出力形式をSKILL.mdに追記

**Files:**
- Modify: `/home/aya/.claude/skills/work-report/SKILL.md`

**Interfaces:**
- Consumes: Task 3で取得した生データ（日報Work欄テキスト、gitログ行、RocketChat発言、Claudeセッション要約）
- Produces: 「分類ロジック」節・「出力形式」節・「エラー処理」節（このタスクでSKILL.mdは完成する）

- [ ] **Step 1: 「分類ロジック」節を追記する**

```markdown
---

## 分類ロジック

出力は「カテゴリ → サブプロジェクト（=リポジトリ名 or 作業テーマ） → 箇条書き」の2階層構造にする。個人リポジトリ（dotfiles・life等）の作業はいずれのカテゴリにも含めない。

### カテゴリ判定

| カテゴリ | 対象 |
|---|---|
| AI | `ebase-dev` 配下の全リポジトリ ＋ `eb-api-extended` |
| その他 | 仕事関連かつAIカテゴリに属さないもの（`hankyu` のgitログ、および日報・Claudeセッション要約から判明したAI以外の仕事関連作業） |

### サブプロジェクト名（表示名マッピング）

原則リポジトリ名をそのまま使う。例外は以下の固定マッピングのみ。新規の例外が発生したらこの表に手動で追記する（自動推測はしない）。

| リポジトリ名 | 表示名 |
|---|---|
| `ebase-portal-chat` | `AI-search` |
| `hankyu` | 阪急キッチンエール |

gitログに紐づかない作業（日報・Claudeセッション要約のみから判明した作業）は、内容から推測できる作業テーマ名をサブプロジェクト名として使う。

### 統合ルール

- 日報サマリー・gitログ・Rocket Chat・Claudeセッション要約から集めた内容のうち、同一の作業を指すものは1項目に統合する（例: 「PR#24作成」という日報の記述と「セッション認証方式変更」というgitログのコミットメッセージが同じ作業を指すなら1つの箇条書きにまとめる）
- 活動がないカテゴリ・サブプロジェクトは出力しない
- 個人開発の話題（dotfiles等）が日報やClaudeセッション要約に含まれていても出力に含めない
```

- [ ] **Step 2: 「出力形式」節を追記する**

```markdown
## 出力形式

コピペしやすいプレーンテキストの箇条書きで、チャット上にそのまま出力する。ファイル保存・git commitは行わない。

```
- AI
    - MCP
        - 新規リソースの作成
    - AI-search
        - takashoブランドの作成
        - 検証環境の調整
        - 詳細画面URL対応
- その他
    - 阪急キッチンエール
        - 締め日マスタボタンの作成
```

- 各項目はタイトルのみ（説明文・PR番号などの付加情報なし）、名詞句で統一する
- KPTや所感、生産性指標などの追加セクションは作らない（`weekly-report` skillとの違い）
```

- [ ] **Step 3: 「エラー処理」節を追記する**

```markdown
## エラー処理

| 状況 | 対応 |
|---|---|
| 対象期間内の日報が1日も見つからない | gitログ・Rocket Chat・Claudeセッション要約のみで生成を続行 |
| gitリポジトリなし | スキップして他のソースで生成 |
| Rocket Chat発言が0件 | スキップして他のソースで生成 |
| Claudeセッション要約なし（`sessions/YYYY-MM-DD/` が空） | スキップして他のソースで生成 |
| 入力ソースがすべて空 | 「対象期間の作業内容が見つかりません」と表示して終了 |
| 土日にデータがない | 正常系として扱い、警告等は出さない |
```

- [ ] **Step 4: SKILL.md全体を読み直し、Task 2〜4で追記した内容に矛盾や重複がないか確認する**

Run: (Readツールで `/home/aya/.claude/skills/work-report/SKILL.md` 全文を読む)

Expected: frontmatter → 概要 → 対象期間の決定 → データソース → gh CLI認証 → コマンド例 → 分類ロジック → 出力形式 → エラー処理、の順で章立てが通っており、変数名（`$start_date`, `$end_date`）が全体で一貫していること

- [ ] **Step 5: 完了（ファイル編集のみ、commit不要）**

---

### Task 5: 実際にskillを実行してエンドツーエンド検証する

自動テストが書けないLLM手順書のため、この計画における「テスト」は実際にskillを1回実行し、出力が設計書通りの構造になっているかを目視確認することで代替する。

**Files:**
- なし（動作確認のみ）

**Interfaces:**
- Consumes: Task 2〜4で完成した `/home/aya/.claude/skills/work-report/SKILL.md`
- Produces: なし（検証結果をユーザーに報告するのみ）

- [ ] **Step 1: `/work-report` としてskillを呼び出す**

ユーザーに、実装が完了したので実際に呼び出して確認してよいか尋ねる。承認を得たら `Skill` ツールで `work-report` を実行する。

- [ ] **Step 2: 出力を確認する**

以下を目視でチェックする:
- 「AI」「その他」の2カテゴリ構造になっているか
- `ebase-portal-chat` の作業があれば `AI-search`、`hankyu` の作業があれば「阪急キッチンエール」という表示名に読み替えられているか
- `dotfiles`・`aya-215/life` など個人リポジトリの作業が出力に一切含まれていないか
- 各箇条書きが名詞句のタイトルのみで、説明文が付いていないか
- KPTや生産性指標などの余計なセクションが出力されていないか
- 対象期間が今日の曜日に対して正しいか（例えば今日が火曜なら「先週火曜〜今日」になっているか、Task 2 Step 2の検証式で計算した日付と一致するか）

- [ ] **Step 3: 問題があれば該当タスクのSKILL.md該当節を修正し、Step 1からやり直す**

問題なければ完了。ユーザーに最終出力を提示して確認を取る。

---

## Self-Review Notes

- **Spec coverage確認:** 設計書の「対象期間の決定ロジック」→Task 2、「データソース」→Task 3、「分類ロジック」→Task 4、「出力形式」→Task 4、「エラー処理」→Task 4でそれぞれ実装される。「未確定事項（skill名）」はTask 2で `work-report` として確定した。
- **プレースホルダ確認:** 当初 `eb-api-extended` の実パスが未確定でTask 3のコマンド例に山括弧プレースホルダが残っていたが、計画作成時点で実際に調査（`/mnt/d/tomcat/webapps/eb-api-extended` と確定）し、Task 1・Task 3双方を確定値に更新済み。最終計画にプレースホルダは残っていない。
- **型・命名の一貫性確認:** `$start_date` / `$end_date` という変数名をTask 2〜3で統一して使用している。
- **設計変更の反映（2026-07-01追記）:** ユーザーから「個人リポジトリ（dotfiles・life）は対象外」「その他カテゴリはAI以外の仕事関連のみ」という訂正があり、以下を修正した:
  - `hankyu`（阪急キッチンエール）の実パスを `/mnt/d/tomcat/webapps/hankyu` と確定（社内GitBucketリポジトリ、gitログのみ読み取り）
  - Task 3の「その他カテゴリ」データ取得を個人リポジトリのgitログから `hankyu` のgitログ＋Claudeセッション要約に置き換え
  - Task 4の分類ロジック・出力形式に `hankyu`→「阪急キッチンエール」の表示名マッピングとClaudeセッション要約由来のサブプロジェクト名推測ルールを追加
  - Task 5の検証項目に「個人リポジトリの作業が混入していないか」を追加
  - 設計書 `docs/superpowers/specs/2026-07-01-work-report-design.md` も同内容で更新が必要（別途対応）

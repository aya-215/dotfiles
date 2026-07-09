# effort-estimate skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 特定タスク1本（例「タカショーのデモ環境作成」）の工数を、日報サマリー・gitログ・Rocket Chat・Claudeセッション要約の一次データから逆算して人日ベースで見積もり、調査メモ形式でチャットに出力する `effort-estimate` skillを新規作成する。

**Architecture:** 既存 `work-report` skillと同じ構成（`.claude-global/skills/<name>/SKILL.md` 1ファイルにMarkdown手順書＋bashコマンド例）。データソース取得コマンドは `work-report/SKILL.md` から流用。実行時はClaudeがこのSKILL.mdを読み、タスク名でグリップ横断して期間を発見→データ収集→methodologyに沿って工数算出→チャット出力する流れ。自動テストは書けない（LLM手順書）ため、検証は「実際にskillを起動してサンプル出力が仕様通りか目視確認」で行う。

**Tech Stack:** Markdown（SKILL.mdフォーマット）、bash、`gh` CLI、`mcp__rocketchat__*` ツール

## Global Constraints

- skillの配置先は `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`（既存skillと同じ階層構造。`~/.claude/skills/` へはHome Manager等で反映される想定）
- gh CLIの操作はすべて `aya-215` アカウントで実行する（`GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)` を先頭に置き、以降のコマンドに `GH_TOKEN="$GH_TOKEN"` を付与）
- データソース対象は `work-report` と同一: `~/src/github.com/ebase-dev/*`、`/mnt/d/tomcat/webapps/eb-api-extended`、`/mnt/d/tomcat/webapps/hankyu`、日報（`aya-215/life`）、Claudeセッション要約（`~/.nb/claude/sessions/`）、Rocket Chat（`mori.a-times`）
- 個人リポジトリ（`~/.dotfiles`、`~/src/github.com/aya-215/*` 等）は対象外
- `/mnt/` 配下のリポジトリは `index.lock` エラー時「削除して即リトライ」（読み取り専用 git log なのでリスクは低い）
- `echo "$json_var" | jq` は使わず `printf '%s\n' "$json_var" | jq` を使う（Issue body内 `\n` のリテラル改行展開対策）
- ファイル保存・git commit・pushは一切行わない。出力はチャット上のプレーンテキストのみ（保存が必要ならユーザーが指示する）
- 工数算出は必ず methodology（後述）に従う。セッション時間の単純合算は禁止
- 設計書は `docs/superpowers/specs/2026-07-09-effort-estimate-design.md`（このplanと矛盾があれば設計書を正とする）

---

### Task 1: SKILL.md の骨格・frontmatter・目的とスコープを作成

**Files:**
- Create: `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`

**Interfaces:**
- Produces: skillの起動トリガー（description）、目的・スコープ・work-reportとの棲み分けの記述。以降のTaskはこのファイルに追記していく

- [ ] **Step 1: skillディレクトリとSKILL.mdの骨格を作成**

`work-report/SKILL.md` のfrontmatter形式を踏襲する。ファイル冒頭に以下を書く：

```markdown
---
name: effort-estimate
description: 特定タスク1本にかかった工数（人日）を、日報・gitログ・Rocket Chat・Claudeセッション要約の一次データから逆算して見積もる。「〇〇にどれくらいかかった？」「タカショー対応の工数まとめて」「あの作業の合計工数は」等で使用。work-report（期間まるごとのカテゴリ別報告）とは目的が異なる。
---

# 工数見積もり（effort-estimate）

タスク名を入力に、関連する作業期間を全ソース横断で発見し、並行作業を除外して人日ベースで工数を算出し、調査メモ形式でチャットに出力する。

`work-report`（期間まるごと→カテゴリ別箇条書き）とは目的・集計軸が直交する別スキル。ファイル保存やgit commitは行わない。

## 入力

タスク名のテキストのみ（例「タカショーのデモ環境作成」）。期間は入力しない — スキルが全ソースをグリップ横断して自動で発見する。

## やらないこと

- ファイル保存・git commit（チャット出力のみ。保存はユーザーが指示）
- 期間まるごとのカテゴリ別報告（それは work-report の役割）
- KPT・生産性指標などの追加集計
```

- [ ] **Step 2: 目視確認**

ファイルが作成され、frontmatterの `name`/`description` が正しいことを確認する。
Run: `head -20 /home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`
Expected: frontmatterと目的セクションが表示される

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "feat: effort-estimateスキルの骨格を追加"
```

---

### Task 2: 処理フローと期間発見の手順を追記

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`

**Interfaces:**
- Consumes: Task 1 のSKILL.md骨格
- Produces: 「処理フロー」「期間発見」「境界確認」セクション

- [ ] **Step 1: 処理フローと期間発見セクションを追記**

以下を SKILL.md の末尾に追記する：

````markdown
## 処理フロー

1. タスク名テキストを受け取る
2. **期間発見**: 全ソースをタスクのキーワードでグリップ横断し、ヒットした日付範囲を当たりとして特定
3. **境界確認**: 含める範囲の候補が複数あり一意に決まらないときだけ `AskUserQuestion` で確認。それ以外は広めに取る（迷ったら出す側）
4. **データ収集**: 期間内の日報・gitログ（タイムスタンプ付き）・Claudeセッション（start/end付き）・Rocket Chat を取得
5. **工数算出**: 「工数算出の方法論」に従う
6. **出力**: 調査メモ形式でチャットに出力（保存なし）

## 期間発見

タスクのキーワードで全ソースを横断検索し、ヒットした日付の範囲を作業期間の当たりとする。

```bash
# blog md と Claudeセッション要約からキーワードを含むファイルを探す
KEYWORD="タカショー"  # ← タスク名から抽出したキーワード（複数可: "タカショー\|デモ環境"）
LIFE_REPO=~/src/github.com/aya-215/life

echo "=== blog md ==="
grep -rl "$KEYWORD" "$LIFE_REPO/blog/" 2>/dev/null | sort

echo "=== Claudeセッション要約 ==="
grep -rl "$KEYWORD" ~/.nb/claude/sessions/ 2>/dev/null | sort
```

ヒットした日付の最小〜最大を作業期間とする。前後1日程度は関連作業がにじむため、範囲は広めに取る。
````

- [ ] **Step 2: 目視確認**

Run: `grep -n "期間発見\|境界確認\|処理フロー" /home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`
Expected: 各セクション見出しが存在する

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "feat: effort-estimateに処理フローと期間発見の手順を追加"
```

---

### Task 3: データ収集コマンド（gitログ・セッション・Rocket Chat・日報）を追記

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`

**Interfaces:**
- Consumes: Task 2 の期間発見で確定した `start_date`/`end_date`
- Produces: 「データ収集」セクション（4ソースの取得コマンド）

- [ ] **Step 1: データ収集セクションを追記**

`work-report/SKILL.md` のコマンド例を流用して以下を追記する。gitログはタイムスタンプ付き（工数算出のクロスチェック用）にする点がwork-reportと異なる：

````markdown
## データ収集

期間発見で確定した `start_date`〜`end_date` について、以下を取得する。

### gh CLI の認証

```bash
GH_TOKEN=$(gh auth token --user aya-215 2>/dev/null)
```
以降の `gh` コマンドには `GH_TOKEN="$GH_TOKEN"` を付与する。

### 日報サマリー（一次ソース・工数算出の主軸）

対象期間の各日について blog md（`blog/YYYYMMDD.md`）またはopen Issueから 📝 サマリーの Work欄を抽出する。

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
      --search "in:title ${d} の記録" --state all --label memo \
      --json number --jq '.[0].number' 2>/dev/null)
    if [ -n "$issue_num" ]; then
      echo "=== $d (issue #$issue_num) ==="
      GH_TOKEN="$GH_TOKEN" gh issue view "$issue_num" --repo aya-215/life \
        --json body --jq '.body' 2>/dev/null | \
        sed -n '/^## 📝 サマリー/,/^## /p' | sed '$d'
    fi
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### gitログ（タイムスタンプ付き・作業窓クロスチェック用）

コミット時刻で「その日の作業窓の下限」を裏取りする。対象タスクに関係するリポジトリを選んで実行する。

```bash
# ebase-dev配下 + eb-api-extended + hankyu
for repo in ~/src/github.com/ebase-dev/*/ /mnt/d/tomcat/webapps/eb-api-extended /mnt/d/tomcat/webapps/hankyu; do
  [ -d "$repo" ] || continue
  rm -f "$repo/.git/index.lock" 2>/dev/null
  repo_name=$(basename "$repo")
  ae=$(git -C "$repo" config user.email 2>/dev/null)
  echo "=== $repo_name ==="
  git -C "$repo" log --pretty="%ad %s" --date=format-local:'%m/%d %H:%M' \
    --since="$start_date 00:00" --until="$end_date 23:59" --author="$ae" --all 2>/dev/null | sort
done
```

### Claudeセッション要約（start/end付き・作業窓クロスチェック用）

各セッションの frontmatter に `session_id`/`start`/`end` がある。**start/endは合算に使わず、その日の作業窓の裏取りにのみ使う**（後述の方法論を厳守）。

```bash
d="$start_date"
while [ "$(date -d "$d" +%s)" -le "$(date -d "$end_date" +%s)" ]; do
  if [ -d ~/.nb/claude/sessions/"$d" ]; then
    for sf in ~/.nb/claude/sessions/"$d"/*.md; do
      proj=$(grep -m1 '^project:' "$sf" | sed 's/project: //')
      sid=$(grep -m1 'session_id:' "$sf" | sed 's/.*session_id: //')
      st=$(grep -m1 '^start:' "$sf" | sed 's/start: //')
      en=$(grep -m1 '^end:' "$sf" | sed 's/end: //')
      echo "=== $d $proj sid=${sid:0:8} start=$st end=$en ==="
      awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=3{print}' "$sf"
    done 2>/dev/null
  fi
  d=$(date -d "$d +1 day" +%Y-%m-%d)
done
```

### Rocket Chat（つまずき・進捗の実況）

`mcp__rocketchat__list_channels`（filter: "mori.a-times"）で room_id を特定し、`mcp__rocketchat__get_channel_history`（oldest/latest でJST→UTC変換に注意）で期間内を取得。username=mori.a の発言のみ、タスクのキーワードに関連するものを抽出する。出力が大きい場合はサブエージェントに抽出させる。
````

- [ ] **Step 2: 目視確認**

Run: `grep -n "日報サマリー\|gitログ\|Claudeセッション要約\|Rocket Chat" /home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`
Expected: 4ソースの見出しが存在する

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "feat: effort-estimateにデータ収集コマンドを追加"
```

---

### Task 4: 工数算出の方法論（4つ＋1の罠）を追記

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`

**Interfaces:**
- Consumes: Task 3 で収集したデータ
- Produces: 「工数算出の方法論」セクション（スキルの肝）

- [ ] **Step 1: 方法論セクションを追記**

このセクションがスキルの中核。設計docの methodology を決定的手順として書く：

````markdown
## 工数算出の方法論

セッション時間の単純合算は破綻するため、以下を必ず守る。

1. **人日ベースが主軸**: 日報の申告を一次ソースにする。各稼働日について「その日のうち対象タスクが占めた割合（0〜1人日）」を見積もる。

2. **セッションの start/end は合算しない**: 同一 session_id の重複要約・複数日またぎのコンテキストにより、合算すると実作業時間の2〜3倍に膨らむ。commit タイムスタンプとセッション時刻は「その日の作業窓の下限」を裏取りするクロスチェックにだけ使う。

3. **並行作業を各日から除外**: 対象タスクに無関係な別リポジトリ・別機能・個人リポの作業を各日の人日から差し引く。ここが精度を決める肝。除外例と採用例を、対象タスクの内容から具体的に判断する。

4. **レンジで出す**: 「37.5h」のような偽精度は禁止。「約6人日」「1人日 ≒ 7.5h 換算」のように推定であることを明示する。

5. **桁のサニティチェック**: 肌感とオーダーがずれたら二重計上を疑う（例: 一連の弧が肌感5〜6人日なのに30hや150hが出たら方法を疑う）。
````

- [ ] **Step 2: 目視確認**

Run: `grep -n "工数算出の方法論\|合算しない\|並行作業\|レンジ\|サニティ" /home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`
Expected: 方法論セクションと5項目のキーワードが存在する

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "feat: effort-estimateに工数算出の方法論を追加"
```

---

### Task 5: 出力形式とエラー処理を追記

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`

**Interfaces:**
- Consumes: Task 4 の算出結果
- Produces: 「出力形式」「エラー処理」セクション。SKILL.md 完成

- [ ] **Step 1: 出力形式とエラー処理を追記**

````markdown
## 出力形式（調査メモ・デフォルト）

チャット上に以下の構成で出力する。ファイル保存はしない。

- **合計工数（レンジ）** を先頭に置く（例「約6人日（≒45〜48時間）」）
- **作業カテゴリ別の内訳** ＋各人日（表形式）
- **日別クロスチェック表**（作業窓 JST・並行除外作業）
- **前提の明記**（推定である旨・除外したもの・1人日=7.5h換算）
- 範囲の線引きで工数が振れる場合は、狭い解釈と広い解釈の両方の人日を示す

上司報告用の簡潔版が必要なら、ユーザーの追加指示（「上司報告用にして」等）を受けて、詳細版からカジュアル表現・派生作業・Markdown記法を削って整形する。

## エラー処理

| 状況 | 対応 |
|---|---|
| タスク名でヒットするデータが1件もない | 「該当する作業が見つかりません」と表示して終了 |
| gitリポジトリなし | スキップして他ソースで算出 |
| Rocket Chat 発言0件 | スキップして他ソースで算出 |
| 日報が期間内に1日もない | gitログ・セッション要約のみで算出（精度低下を明記） |
````

- [ ] **Step 2: 目視確認（全体構成）**

Run: `grep -n "^## " /home/aya/.dotfiles/.claude-global/skills/effort-estimate/SKILL.md`
Expected: 入力 / やらないこと / 処理フロー / 期間発見 / データ収集 / 工数算出の方法論 / 出力形式 / エラー処理 が順に並ぶ

- [ ] **Step 3: コミット**

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "feat: effort-estimateに出力形式とエラー処理を追加"
```

---

### Task 6: 実起動による検証（受け入れテスト）

**Files:**
- なし（読み取り検証のみ）

**Interfaces:**
- Consumes: 完成した SKILL.md
- Produces: 検証結果（skillが今回の会話と同等の工数レンジを再現できるか）

- [ ] **Step 1: 既知タスクで実起動して再現性を確認**

新しいセッション（または `/effort-estimate タカショーのデモ環境作成` 相当）でskillを起動し、以下を満たすか目視確認する：

- 期間が 6/17〜6/25 付近に自動発見される
- 合計工数が **約5.5〜6.5人日** のレンジで出る（今回の手動集計と桁が一致）
- セッションspanの単純合算になっていない（方法論が効いている）
- 並行作業（hankyu・CSV汎用機能等）が除外されている
- 出力が調査メモ形式（合計→内訳→日別表→前提）になっている

- [ ] **Step 2: ずれがあれば SKILL.md を修正**

再現できない・桁がずれる場合は、原因（キーワード不足・除外判断の指示不足等）を特定して該当セクションを修正し、再度 Step 1 を実行する。修正したらコミットする。

```bash
cd /home/aya/.dotfiles
rm -f .git/index.lock
git add .claude-global/skills/effort-estimate/SKILL.md
git commit -m "fix: effort-estimateの検証で見つかった問題を修正"
```

- [ ] **Step 3: push**

```bash
cd /home/aya/.dotfiles
git remote -v  # origin が github-aya215 か確認
git push
```

---

## Self-Review

**1. Spec coverage:**
- 目的・スコープ → Task 1 ✅
- 処理フロー・期間発見・境界確認 → Task 2 ✅
- データソース定義（4ソース） → Task 3 ✅
- 工数算出 methodology（5項目） → Task 4 ✅
- 出力形式・エラー処理 → Task 5 ✅
- 検証（LLM手順書のため実起動確認） → Task 6 ✅
- ギャップなし

**2. Placeholder scan:** 各Stepに実際のコマンド・実際のMarkdown本文を記載済み。「TBD」「後で実装」等なし ✅

**3. Type consistency:** SKILL.md単一ファイルへの追記のみ。セクション見出し名は Task間で一貫（「工数算出の方法論」「期間発見」「データ収集」等）。Task 5 Step 2 の目視確認リストが全セクション名と一致 ✅

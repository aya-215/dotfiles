# retrospective学習機構 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cc-retrospective-learnerのカウント・昇格機構をagent-memory/SessionEnd要約の既存資産に統合し、週次の `/retrospective` スキルで失敗・成功パターンをルール/スキルに昇格させる。

**Architecture:** SessionEnd hookのHaiku要約（既存・全自動）をLv.0データソースとし、新設の `/retrospective` スキルが週次でサブエージェント分析→feedbackメモリのカウント更新→閾値3で `rules/learned-rules.md` への昇格提案を行う。全昇格はユーザー承認必須。

**Tech Stack:** Claude Code スキル/サブエージェント定義（Markdown + YAML frontmatter）、bash（summarize.sh）、agent-memory規約

**Spec:** `docs/superpowers/specs/2026-07-02-retrospective-learning-design.md`

## Global Constraints

- リポジトリ: `/home/aya/.dotfiles`（main直コミット、プレフィックス `feat:` / `docs:` / `fix:`。pushは最終タスクでまとめて実施）
- 閾値: 昇格候補 = `pain_count >= 3` または `success_count >= 3`。Lv.3候補 = `reinforce_count >= 3`
- カウント規律: 1セッション1回まで / reinforce_countは明確な証拠がある場合のみ / 新規feedbackは2セッション以上での出現が条件
- feedbackメモリ置き場: `.claude-global/skills/agent-memory/memories/feedback/`（gitignore対象・コミットしない）
- 前回実行日ファイル: `~/.nb/claude/last_retrospective.txt`（YYYY-MM-DD 1行、リポジトリ外）
- 日付は必ず `TZ=Asia/Tokyo` で算出
- エージェント定義はYAML frontmatter必須（frontmatterなしの `dotfiles-reviewer.md` は認識されていない実績あり）
- シェル変更は `bash -n` で構文確認。日本語コンテンツはUTF-8

---

### Task 1: summarize.sh に7項目目「フィードバック/承認」を追加

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh:63-71`（PROMPTヒアドキュメント）
- Modify: `.claude-global/skills/daily-review/SKILL.md:66,183`（「6項目」表記の整合）

**Interfaces:**
- Produces: セッション要約Markdownに `## フィードバック/承認` セクションが追加される。Task 4のサブエージェントとTask 5のスキルはこのセクション名を検索キーとして使う（表記は「フィードバック/承認」で完全一致）

- [ ] **Step 1: summarize.sh のプロンプトを7項目化**

`scripts/claude-summarize/summarize.sh` の以下2箇所をEditする。

変更1（62行目付近）:
```
旧: このセッションを日本語で要約し、**下記6項目の Markdown のみ**を出力してください。前置き・後置きは一切不要。
新: このセッションを日本語で要約し、**下記7項目の Markdown のみ**を出力してください。前置き・後置きは一切不要。
```

変更2（71行目 `## ナレッジ候補` の行の直後に追加）:
```
- ## フィードバック/承認 — ユーザーから修正・指摘された点（pain）と、ユーザーが明確に承認・称賛した進め方（success）。なければ「なし」
```

- [ ] **Step 2: 構文確認と変更の存在確認**

Run:
```bash
bash -n /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh && echo SYNTAX_OK
grep -c "フィードバック/承認" /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh
grep -c "下記7項目" /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh
```
Expected: `SYNTAX_OK` / `1` / `1`

- [ ] **Step 3: 実transcriptでの動作確認（出力先を隔離して実行）**

`SESSIONS_ROOT` と `SCRIPT_DIR` はreadonly固定なので、sedで差し替えたコピーをscratchpadに作って実行する（extract.py と redact.sh は実リポジトリを参照させる）。

Run:
```bash
SCRATCH="/tmp/claude-1000/-home-aya--dotfiles/60b56afa-d946-4fb5-a2ba-99d2adaae6a7/scratchpad"
mkdir -p "$SCRATCH/summarize-test"
sed -e 's|^readonly SCRIPT_DIR=.*|readonly SCRIPT_DIR="/home/aya/.dotfiles/scripts/claude-summarize"|' \
    -e "s|^readonly SESSIONS_ROOT=.*|readonly SESSIONS_ROOT=\"$SCRATCH/summarize-test\"|" \
    /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh > "$SCRATCH/summarize-test.sh"
T=$(find ~/.claude/projects -name '*.jsonl' -size +5k -size -200k -mtime -7 | head -1)
bash "$SCRATCH/summarize-test.sh" "$T" "$(basename "$T" .jsonl)"
grep -r "## フィードバック/承認" "$SCRATCH/summarize-test/" && echo E2E_OK
```
Expected: 生成された要約ファイルに `## フィードバック/承認` セクションが含まれ `E2E_OK` が出る（Haikuがサブスク枠で1回走る）

- [ ] **Step 4: daily-review SKILL.md の「6項目」表記を更新**

`.claude-global/skills/daily-review/SKILL.md` の2箇所をEditする。

変更1（66行目付近、入力ソース表内）:
```
旧: セッション単位の6項目要約、SessionEnd hook が自動生成
新: セッション単位の7項目要約、SessionEnd hook が自動生成
```

変更2（183行目付近）:
```
旧: 各セッションは既に6項目（意図・作業内容・結論・編集ファイル・実行コマンド・ナレッジ候補）で構造化済み。
新: 各セッションは既に7項目（意図・作業内容・結論・編集ファイル・実行コマンド・ナレッジ候補・フィードバック/承認）で構造化済み。
```

※ クラウドルーティン側（daily-review自動化）のプロンプトはリポジトリ外のため変更しない。セクション追加は後方互換であり実害なし。

- [ ] **Step 5: コミット**

```bash
git -C /home/aya/.dotfiles add scripts/claude-summarize/summarize.sh .claude-global/skills/daily-review/SKILL.md
git -C /home/aya/.dotfiles commit -m "feat: セッション要約に7項目目「フィードバック/承認」を追加"
```

---

### Task 2: rules/learned-rules.md の新設

**Files:**
- Create: `.claude-global/rules/learned-rules.md`

**Interfaces:**
- Produces: 昇格ルールの追記先。Task 5のスキルは `<!-- ルールはこの下に追記される -->` マーカーの下にルールを追記する

- [ ] **Step 1: テンプレートファイルを作成**

`.claude-global/rules/learned-rules.md` を以下の内容で作成:

```markdown
# 学習済みルール（retrospective昇格）

retrospective学習機構（`/retrospective` スキル）で pain_count / success_count が閾値（3）に達し、ユーザー承認を経て昇格したルール。`rules/` 配下のため全セッションに自動で読み込まれる。

- 由来: `.claude-global/skills/agent-memory/memories/feedback/` の各feedbackメモリ（`promoted_to: rules`）
- 形式: 1ルール = `##` 見出し + 本文数行 + 由来feedbackファイル名
- 手動編集可。ルールを削除する場合は由来feedbackの `promoted_to` を `null` に戻すこと

<!-- ルールはこの下に追記される -->
```

- [ ] **Step 2: 追記マーカーの存在確認**

Run:
```bash
grep -c "ルールはこの下に追記される" /home/aya/.dotfiles/.claude-global/rules/learned-rules.md
```
Expected: `1`

- [ ] **Step 3: コミット**

```bash
git -C /home/aya/.dotfiles add .claude-global/rules/learned-rules.md
git -C /home/aya/.dotfiles commit -m "feat: retrospective昇格ルールの置き場 learned-rules.md を新設"
```

---

### Task 3: agent-memory SKILL.md にfeedbackメモリ形式を追記

**Files:**
- Modify: `.claude-global/skills/agent-memory/SKILL.md`（`## Frontmatter` セクションの直後に新セクション追加、version 3.0.0 → 3.1.0）

**Interfaces:**
- Produces: feedbackメモリのfrontmatterフィールド定義。Task 4のサブエージェントとTask 5のスキルはこの形式（フィールド名 `pain_count` / `success_count` / `reinforce_count` / `promoted_to` / `scope` / `type: feedback`）に従う

- [ ] **Step 1: frontmatterのversionを更新**

```
旧: version: 3.0.0
新: version: 3.1.0
```

- [ ] **Step 2: 「## Search Workflow」セクションの直前に以下を挿入**

```markdown
## Feedback Memory（retrospective学習機構）

`memories/feedback/` には `/retrospective` スキルが管理するfeedbackメモリを置く。通常メモリのfrontmatterに加えて以下のフィールドを持つ:

```yaml
---
summary: "1-2行の説明（通常メモリと同じ規約）"
created: 2026-07-02
updated: 2026-07-09      # カウント更新時に更新
type: feedback           # feedbackメモリの識別子
pain_count: 0            # 失敗の繰り返し数（1セッション1回まで）
success_count: 0         # 成功の積み重ね数（同上）
reinforce_count: 0       # 昇格後の適用実績（要約に明確な証拠がある場合のみ）
promoted_to: null        # null | rules | skill
tags: [error-handling]
scope: global            # global | <プロジェクト名>（普遍/固有の分離）
---
```

本文は3部構成:

```markdown
**Why:** なぜこれが重要か
**How to apply:** いつ・どこで適用すべきか
**出現記録:** 2026-06-25 (ebase-web), 2026-07-01 (dotfiles)
```

カウント更新・昇格提案は `/retrospective` スキルが行う（閾値: count >= 3 で `rules/learned-rules.md` へ昇格提案、reinforce_count >= 3 でスキル化候補）。手動編集も可。
```

- [ ] **Step 3: 挿入の確認**

Run:
```bash
rg -c "Feedback Memory" /home/aya/.dotfiles/.claude-global/skills/agent-memory/SKILL.md
rg -c "version: 3.1.0" /home/aya/.dotfiles/.claude-global/skills/agent-memory/SKILL.md
```
Expected: 両方 `1`

- [ ] **Step 4: コミット**

```bash
git -C /home/aya/.dotfiles add .claude-global/skills/agent-memory/SKILL.md
git -C /home/aya/.dotfiles commit -m "feat: agent-memoryにfeedbackメモリ形式を追加（retrospective学習機構）"
```

---

### Task 4: retrospective-analyzer サブエージェント定義

**Files:**
- Create: `.claude-global/agents/retrospective-analyzer.md`
- Create (symlink): `~/.claude/agents/retrospective-analyzer.md` → 上記ファイル

**Interfaces:**
- Consumes: Task 1のセクション名 `## フィードバック/承認`、Task 3のfeedback形式
- Produces: subagent_type `retrospective-analyzer`。Task 5のスキルがAgentツールで起動する。返却サマリー形式は本タスクStep 1の「結果サマリー」節で定義

- [ ] **Step 1: エージェント定義を作成**

`.claude-global/agents/retrospective-analyzer.md` を以下の内容で作成（**frontmatter必須**。frontmatterがないと認識されない — dotfiles-reviewer.mdで実証済み）:

```markdown
---
name: retrospective-analyzer
description: 週次ふりかえり分析のサブエージェント。セッション要約群と既存feedbackメモリを照合してpain/success/reinforceカウントを更新し、新規パターンのfeedbackを作成、昇格候補を検出する。/retrospectiveスキルから起動される。
tools: ["Read", "Grep", "Glob", "Write", "Edit"]
---

# retrospective-analyzer

週次ふりかえり分析を行うサブエージェント。親（/retrospectiveスキル）からpromptで以下を受け取る:

- 対象セッション要約ファイルのパス一覧
- feedbackディレクトリのパス（`~/.claude/skills/agent-memory/memories/feedback/`）

## ツール使用ルール

- **Bashは使用できない。** ファイル操作は Read / Glob / Grep / Write / Edit のみ
- **書き込みはfeedbackディレクトリ配下の `.md` ファイルのみ。** それ以外への Write / Edit は禁止

## 実行手順

### 1. 既存feedbackの読み込み

feedbackディレクトリの `*.md` をGlobで列挙し、全件Readする（初回はディレクトリが空、または存在しない場合がある。その場合は既存feedbackゼロとして続行）。

### 2. セッション要約の分析

各要約ファイルをReadし、以下を抽出する:

- **pain**: `## フィードバック/承認` セクションの修正・指摘。旧形式（6項目）の要約では `## ナレッジ候補` と本文から失敗・手戻りの記述を読み取る
- **success**: 同セクションの承認・称賛された進め方
- 要約のfrontmatter `project:` をプロジェクト名として記録する

### 3. 既存feedbackとの照合とカウント更新

- 抽出したpain/successが既存feedbackと同種なら、該当ファイルの `pain_count` / `success_count` をインクリメントする
- **1セッション1回まで**（同一セッション内に複数回出現しても+1）
- `出現記録` に日付とプロジェクト名を追記し、`updated` を今日の日付にする
- `promoted_to: rules` のfeedbackは、要約に**そのルールを適用した明確な証拠**（承認セクションでの言及等）がある場合のみ `reinforce_count` をインクリメントする。推測でのカウントは禁止

### 4. 新規feedbackの作成

既存feedbackに該当しないパターンが**2セッション以上**で出現した場合のみ、新規feedbackを作成する:

- ファイル名: kebab-case（例: `null-config-fallback.md`）
- 形式: agent-memory SKILL.md の「Feedback Memory」節に従う（type: feedback、カウント初期値は出現セッション数、scopeは全プロジェクト共通なら `global`、特定プロジェクト固有なら `<プロジェクト名>`）

### 5. 昇格候補の検出

- `pain_count >= 3` または `success_count >= 3` かつ `promoted_to: null` → **rules昇格候補**
- `promoted_to: rules` かつ `reinforce_count >= 3` → **スキル化候補**

### 6. 結果サマリーの返却

最終テキストとして以下のみを返す（前置き不要）:

```
## 分析結果
- 対象セッション数: N
- カウント更新: <ファイル名>: pain 2→3 のように列挙（なければ「なし」）
- 新規feedback: <ファイル名>: <summary> を列挙（なければ「なし」）
- rules昇格候補: <ファイル名>: <summary> (pain_count: N) を列挙（なければ「なし」）
- スキル化候補: 同上（なければ「なし」）
- 警告: 読めなかったファイル等（なければ省略）
```

## エラーハンドリング

- 個別ファイルの読み込み失敗は警告に記録して続行する
- feedbackディレクトリに書き込めない場合はエラーとして親に報告する
```

- [ ] **Step 2: ~/.claude/agents/ にsymlinkを作成**

Run:
```bash
ln -s /home/aya/.dotfiles/.claude-global/agents/retrospective-analyzer.md ~/.claude/agents/retrospective-analyzer.md
ls -la ~/.claude/agents/retrospective-analyzer.md
```
Expected: symlinkが作成されリンク先が表示される

- [ ] **Step 3: frontmatterの妥当性確認**

Run:
```bash
head -6 ~/.claude/agents/retrospective-analyzer.md
```
Expected: `---` で始まり `name: retrospective-analyzer` と `tools:` が含まれる

- [ ] **Step 4: コミット**

```bash
git -C /home/aya/.dotfiles add .claude-global/agents/retrospective-analyzer.md
git -C /home/aya/.dotfiles commit -m "feat: retrospective-analyzerサブエージェント定義を追加"
```

---

### Task 5: retrospective スキル本体

**Files:**
- Create: `.claude-global/skills/retrospective/SKILL.md`

**Interfaces:**
- Consumes: Task 2のマーカー `<!-- ルールはこの下に追記される -->`、Task 3のfeedback形式、Task 4の subagent_type `retrospective-analyzer` と結果サマリー形式

- [ ] **Step 1: SKILL.md を作成**

`.claude-global/skills/retrospective/SKILL.md` を以下の内容で作成:

```markdown
---
name: retrospective
description: 週次のふりかえり学習。セッション要約からpain/successパターンを検出してfeedbackメモリのカウントを更新し、閾値到達でルール/スキルへの昇格を提案する。「/retrospective」「ふりかえり学習」「昇格チェック」「週次ふりかえり」で起動。
version: 1.0.0
---

# retrospective（週次ふりかえり学習）

SessionEnd要約（`~/.nb/claude/sessions/`）を一次資料として、繰り返される失敗（pain）と成功（success）を定量検出し、閾値到達でルール化・スキル化を提案する。

**全ての昇格にユーザーの明示的な承認が必要。自動昇格はしない。**

## 手順

### 1. 対象期間の決定

```bash
LAST_FILE=~/.nb/claude/last_retrospective.txt
if [ -f "$LAST_FILE" ]; then SINCE=$(cat "$LAST_FILE"); else SINCE=$(TZ=Asia/Tokyo date -d '14 days ago' +%Y-%m-%d); fi
TODAY=$(TZ=Asia/Tokyo date +%Y-%m-%d)
echo "対象期間: $SINCE の翌日 〜 $TODAY"
```

初回（ファイルなし）は直近14日のバックフィルになる。

### 2. 対象要約ファイルの列挙

```bash
for d in ~/.nb/claude/sessions/*/; do
  day=$(basename "$d")
  [[ "$day" > "$SINCE" ]] && find "$d" -maxdepth 1 -name '*.md'
done
```

0件なら「ふりかえり対象なし」と表示して終了する（last_retrospective.txt は更新する）。

### 3. feedbackディレクトリの準備

```bash
mkdir -p ~/.claude/skills/agent-memory/memories/feedback
```

### 4. サブエージェント分析

Agentツールで `subagent_type: "retrospective-analyzer"` をフォアグラウンドで起動する（`run_in_background` は指定しない）。promptに以下を含める:

- 手順2で列挙した要約ファイルのパス一覧（全パスを明記）
- feedbackディレクトリ: `~/.claude/skills/agent-memory/memories/feedback/`
- 今日の日付（`$TODAY`）

`retrospective-analyzer` が利用できない場合は `general-purpose` で代替し、promptに「Bashは使用禁止。書き込みはfeedbackディレクトリ配下のみ」と `.claude-global/agents/retrospective-analyzer.md` の実行手順を含める。

### 5. 結果サマリーの表示

サブエージェントの返却をそのままユーザーに表示する（対象セッション数・カウント更新・新規feedback・昇格候補・警告）。

### 6. rules昇格の承認と実行

rules昇格候補があれば、候補ごとにAskUserQuestionで承認を確認する。承認されたものについて:

1. `~/.dotfiles/.claude-global/rules/learned-rules.md` の `<!-- ルールはこの下に追記される -->` の下に追記:

```markdown
## <ルールの短いタイトル>

<ルール本文1-3行。「〜すること」形式>

由来: `feedback/<ファイル名>.md`（pain_count: N / 昇格日: YYYY-MM-DD）
```

2. 該当feedbackの `promoted_to` を `rules` に、`updated` を今日に更新する

### 7. スキル化候補の提示

`reinforce_count >= 3` の候補があれば「スキル化候補やで」と提示するだけに留める。スキル化の設計・実装は別セッションで行う（本スキルでは実装しない）。

### 8. コミットとプッシュ

learned-rules.md に変更があった場合のみ:

```bash
git -C ~/.dotfiles add .claude-global/rules/learned-rules.md
git -C ~/.dotfiles commit -m "feat: retrospective昇格 - <ルール概要>"
git -C ~/.dotfiles push
```

feedbackメモリ（memories/配下）はgitignore対象なのでコミットしない。

### 9. 実行日の記録

```bash
echo "$TODAY" > ~/.nb/claude/last_retrospective.txt
```

## カウント規律（サブエージェントと共有する原則）

- カウントは1セッション1回まで
- reinforce_countは要約に明確な証拠がある場合のみ（推測での水増し禁止）
- 新規feedbackは2セッション以上での出現が条件（1回きりの偶発をLv.1に上げない）

## 効果測定（導入2週間後）

- 継続: カウントが増えたfeedbackが1つ以上、かつ昇格提案が1回以上
- 撤退: カウントが一度も動かない → 本スキルを削除（feedbackメモリは通常メモリとして残す）
```

- [ ] **Step 2: スキル構造の確認**

Run:
```bash
head -6 /home/aya/.dotfiles/.claude-global/skills/retrospective/SKILL.md
ls ~/.claude/skills/retrospective/SKILL.md
```
Expected: frontmatterに `name: retrospective` があり、symlink経由（`~/.claude/skills` → `.claude-global/skills`）でも見える

- [ ] **Step 3: コミット**

```bash
git -C /home/aya/.dotfiles add .claude-global/skills/retrospective/SKILL.md
git -C /home/aya/.dotfiles commit -m "feat: retrospectiveスキルを追加（週次ふりかえり学習）"
```

---

### Task 6: E2Eバックフィル実験と仕上げ

**Files:**
- なし（動作確認と最終push）

**Interfaces:**
- Consumes: Task 1〜5の全成果物

- [ ] **Step 1: push**

```bash
git -C /home/aya/.dotfiles push
```
Expected: Task 1〜5のコミットがpushされる

- [ ] **Step 2: 新しいセッションで /retrospective を実行（ユーザー操作）**

スキル・エージェント定義はセッション開始時に読み込まれるため、**新しいClaude Codeセッション**で `/retrospective` を実行する。初回なので直近14日のバックフィルが走る。

Expected:
- retrospective-analyzer サブエージェントが起動する（利用不可ならgeneral-purposeフォールバックが動く）
- `~/.claude/skills/agent-memory/memories/feedback/` にfeedbackファイルが作成される（2セッション以上で出現したパターンがあれば）
- 結果サマリー（対象セッション数・新規feedback・昇格候補）が表示される
- `~/.nb/claude/last_retrospective.txt` に今日の日付が書かれる

- [ ] **Step 3: 結果の検証**

Run:
```bash
cat ~/.nb/claude/last_retrospective.txt
rg "^summary:" ~/.claude/skills/agent-memory/memories/feedback/ --no-ignore --hidden 2>/dev/null || echo "feedbackなし（パターン未検出）"
```
Expected: 日付が今日 / feedbackの一覧（またはパターン未検出メッセージ。14日分で2セッション以上の繰り返しがなければ0件も正常）

- [ ] **Step 4: トラブルシューティング（必要時のみ）**

- `retrospective-analyzer` がsubagent_typeとして認識されない場合: symlinkが原因の可能性がある。symlinkを実ファイルコピーに置き換えて再確認:
  ```bash
  rm ~/.claude/agents/retrospective-analyzer.md
  cp /home/aya/.dotfiles/.claude-global/agents/retrospective-analyzer.md ~/.claude/agents/retrospective-analyzer.md
  ```
  この場合、dotfiles側が原本・~/.claude側がコピーになる旨をfeedbackとして記録する
- 分析がコンテキストを圧迫する場合: 対象期間を7日に縮める（SINCEを調整）

- [ ] **Step 5: 効果測定のリマインダーをagent-memoryに記録**

`~/.claude/skills/agent-memory/memories/work-in-progress/retrospective-rollout.md` を作成:

```markdown
---
summary: "retrospective学習機構を2026-07-02に導入。2週間後（7/16頃）に効果測定 - カウントが動いたfeedback1つ以上+昇格提案1回以上で継続、ゼロなら撤退"
created: 2026-07-02
status: in-progress
tags: [retrospective, agent-memory, claude-code]
related: [docs/superpowers/specs/2026-07-02-retrospective-learning-design.md]
---

# retrospective学習機構の導入と効果測定

## 状態
- 導入日: 2026-07-02
- 効果測定予定: 2026-07-16頃（/retrospective を2回以上実行した後）

## 効果測定基準（設計書より）
- 継続: カウントが実際に増えたfeedbackが1つ以上、かつ昇格提案が1回以上
- 撤退: カウントが一度も動かない → retrospectiveスキルを削除（feedbackメモリは残す）

## 次のステップ
- 週1回 /retrospective を実行する
- 測定日にこのメモリを見たら効果判定を行い、statusを更新する
```

---

## Self-Review 結果

- **Spec coverage**: 変更対象5ファイル（retrospective SKILL / agent-memory SKILL / learned-rules.md / summarize.sh / last_retrospective.txt）→ Task 5 / 3 / 2 / 1 / 5-手順9 で全カバー。サブエージェント定義（スペックの「処理手順3」）→ Task 4。バックフィル実験 → Task 6
- **Placeholder scan**: TBD/TODO/「適切に」系なし。全ファイル内容と全コマンドを明記済み
- **整合性**: セクション名「フィードバック/承認」（Task 1=生成、Task 4=消費）、マーカー文字列（Task 2=定義、Task 5=消費）、subagent_type名（Task 4=定義、Task 5=消費）、閾値3・2セッション条件（Global Constraints=Task 4=Task 5）で一致を確認

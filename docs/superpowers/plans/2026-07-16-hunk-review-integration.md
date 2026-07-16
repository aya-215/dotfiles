# hunk連携レビュー skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** hunkのエージェント連携（`hunk session *`）を日常運用するため、汎用ラッパーskill `/hunk-review` を新規作成し、既存 `review-pr` skillにhunk視覚レビューをオプション追加する。

**Architecture:** 共通の連携手順を `review-pr/references/hunk-session.md` に一元化し、新規 `hunk-review/SKILL.md` と改訂版 `review-pr/SKILL.md` の両方から参照する。TUIはユーザーが開く原則を厳守し、Claudeは `hunk session *` で接続するのみ。

**Tech Stack:** Markdown（Claude Code skill定義）、hunk CLI（`hunk session list/review/navigate/comment/context`）、bash。

## Global Constraints

- 配置先ルート: `/home/aya/.dotfiles/.claude-global/skills/`（`~/.claude/skills/` はsymlink）
- **Claudeは絶対に `hunk diff` / `hunk show` を自分で実行しない**（TUIはユーザーが開く）
- 破壊的操作（`comment clear` / `comment rm`）は実行前にAskUserQuestion承認必須
- `navigate` は自由・`comment add`/`apply` は付けたら報告
- review-prの既存フロー（Iron Law・検証ガード・AskUserQuestionルール）を壊さない
- 連携ロジックの二重管理を避ける（実体は `references/hunk-session.md` の1ファイル）
- skill frontmatterは既存skill（sync-main等）の書式に合わせる: `name` / `description` / `allowed-tools` / `version`
- コミットは各タスク完了時。dotfilesリモートは `git@github-aya215:...`、全タスク完了後にpush

---

## File Structure

| ファイル | 責務 |
|---|---|
| `review-pr/references/hunk-session.md`（新規） | hunk session連携の全手順。両skillの実装層 |
| `hunk-review/SKILL.md`（新規） | 汎用ラッパー。任意diffをhunk連携でレビュー |
| `review-pr/SKILL.md`（改訂 v1.3.0→v1.4.0） | 既存PRフローにhunk連携分岐を1つ追加 |

`references/` は `review-pr/` 配下に置く（review-prが元の持ち主。hunk-reviewからは相対参照）。

---

## Task 1: 共通リファレンス references/hunk-session.md

**Files:**
- Create: `/home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md`

**Interfaces:**
- Produces: このファイルパス `review-pr/references/hunk-session.md`。Task 2・Task 3がこれを「読め」と参照する

- [ ] **Step 1: referencesディレクトリ作成とファイル作成**

以下の内容で作成する（設計書のコンポーネント①をそのまま実装）:

````markdown
# hunk session 連携リファレンス

hunk（review-first diff TUI）の生きたセッションに `hunk session *` CLIで接続し、
ナビゲート・コメントする手順。`/hunk-review` と `review-pr` の両skillが参照する実体。

## 最重要ガード: TUIはユーザーが開く

**Claudeは絶対に `hunk diff` / `hunk show` を自分で実行しない。**
実行してもClaudeのbashプロセス内で起動し、ユーザーの端末に映らず、
non-TTYで無意味になる。Claudeの役割は既存セッションへの接続と先導のみ。

## 接続フロー

1. `hunk session list --json` でセッション確認
2. セッションが無ければ、ユーザーに開き方を**案内して待つ**（コマンド文字列は提示、
   Enterを押すのはユーザー）:
   - PRブランチ: 「`hunk diff <base>...HEAD` を自分の端末で開いてな」
   - dotfiles等の環境: `! hunk diff ...`（`!`プレフィックスでこのセッション内実行）も選択肢
   - リモートPRのみ閲覧: `gh pr diff | hunk pager`
3. 「開いた」と言われたら `hunk session list` で再確認して接続
4. 複数セッションがマッチ → `<session-id>` を明示。単一なら自動解決

## セッション選択

多くのコマンドが受け付ける:
- `--repo <path>` — ロード中のrepo rootで一致（最も一般的）
- `<session-id>` — 正確なIDで一致（同一repoに複数セッションがある時）

## 構造把握

```bash
hunk session list [--json]
hunk session get (--repo . | <id>) [--json]      # Path/Repo/Source を表示
hunk session context (--repo . | <id>) [--json]  # 現在のフォーカス位置
hunk session review (--repo . | <id>) --json [--include-patch]
```

- `review --json` の戻りは **`review` キー配下にネスト**。ファイルは `review.files[]`、
  各ファイルの構造は `files[].hunks[]`（`index`, `header`, `oldRange`, `newRange`）
- patchは `--include-patch` を付けた時のみ、**`files[].patch`**（ファイル単位）に入る
- context中は情報を膨らませないため、まず `review --json`（patchなし）で構造把握し、
  本当に生diffが要るファイルだけ `--include-patch` を使う

## ナビゲート

絶対ナビは `--file` と、以下のうち**ちょうど1つ**が必要:

```bash
hunk session navigate --repo . --file src/App.tsx --hunk 2      # 1始まりのhunk番号
hunk session navigate --repo . --file src/App.tsx --new-line 372 # 新側の行番号
hunk session navigate --repo . --file src/App.tsx --old-line 355 # 旧側の行番号
```

コメント間ナビは `--file` 不要:

```bash
hunk session navigate --repo . --next-comment
hunk session navigate --repo . --prev-comment
```

- `--hunk` / `--new-line` / `--old-line` は同時指定不可（エラー「Specify exactly one navigation target」）
- `--next-comment` / `--prev-comment` も両方同時は不可
- **navigate は確認不要で自由に実行してよい**（レビュー先導の一部）

## コメント

### 読取（source別にスキーマが異なる — 重要な罠）

```bash
hunk session comment list --repo . --type user|ai|agent|all [--file X]
```

- **userコメント**: `body` キー（他に `newRange`, `source:"user"`, `noteId`, `editable`）
- **agentコメント**: `summary` + `rationale` キー（他に `line`, `side`, `commentId`, `author`）
- 種別を取り違えると `summary` が None になる。userの発言を読むなら `--type user` して `body` を見る

### 追加

```bash
# 単発
hunk session comment add --repo . --file README.md --new-line 103 \
  --summary "要約" [--rationale "理由"] [--author "claude"] [--focus]

# 一括（stdin JSON batch）
printf '%s\n' '{"comments":[{"filePath":"README.md","newLine":103,"summary":"要約"}]}' \
  | hunk session comment apply --repo . --stdin [--focus]
```

- `comment add` は `--file` + `--summary` + (`--old-line` か `--new-line` のどちらか1つ) が必須
- `comment apply` の各itemは `filePath` + `summary` + ターゲット1つ（`hunk`/`hunkNumber`/`oldLine`/`newLine`）
- `--focus` で追加箇所へ画面も移動
- **コメントを付けたら、付けた内容を必ずユーザーに報告する**

### 破壊的操作（承認必須）

```bash
hunk session comment rm --repo . <comment-id>
hunk session comment clear --repo . --yes [--file X]
```

- `rm` / `clear` は実行前に必ずAskUserQuestionでユーザー承認を取る

## reload（レビュー対象の差し替え）

```bash
hunk session reload --repo . -- diff              # 常に -- の後にhunkコマンド
hunk session reload --repo . -- diff main...HEAD
hunk session reload --repo . -- show HEAD~1
```

- ネストするhunkコマンドの前に必ず `--` を置く

## ブランチ間差分の開き方（ユーザーに案内する内容）

`hunk diff` は `git diff` と同じ構文でtargetを取る:

| 目的 | コマンド |
|---|---|
| mainとの差分（2点） | `hunk diff main` |
| ブランチの変更だけ（3点、PR相当） | `hunk diff main...HEAD` |
| 2ブランチ比較 | `hunk diff main feature` |
| ステージ済み | `hunk diff --staged` |
| ファイル絞り込み | `hunk diff main -- src/` |

PR相当の「自分が足した変更だけ」は3点ドット `main...HEAD`。

## 既知エラー

- **No active Hunk sessions**: hunkが見えてるのに出るならサンドボックスのlocalhost
  ブロック疑い（この環境では未発生を実地確認済み）。でなければユーザーに開いてもらう
- **Multiple active sessions match**: `<session-id>` を明示
- **No visible diff file matches**: 対象ファイルが未ロード。`context` 確認 → 必要なら `reload`
- **Pass the replacement Hunk command after `--`**: reload時に `--` を忘れている
- **Specify exactly one navigation target**: `--hunk`/`--old-line`/`--new-line` を1つに絞る
- 古いゾンビセッション: `session list` のpidで生存確認して見分ける
````

- [ ] **Step 2: 手動検証 — ファイルが存在し内容が正しいか**

Run:
```bash
ls -la /home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md
grep -c "hunk session" /home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md
```
Expected: ファイルが存在し、`hunk session` の言及が10箇所以上

- [ ] **Step 3: 手動検証 — 記載コマンドの構文が実在するか**

Run:
```bash
hunk session --help 2>&1 | grep -E "list|review|navigate|comment|context|reload|get"
```
Expected: list/review/navigate/comment/context/reload/get の各サブコマンドが実在する
（存在しないコマンドを書いていないことの裏取り）

- [ ] **Step 4: Commit**

```bash
cd /home/aya/.dotfiles; rm -f .git/index.lock
git add .claude-global/skills/review-pr/references/hunk-session.md
rm -f .git/index.lock
git commit -m "feat(review-pr): hunk session連携の共通リファレンスを追加"
```

---

## Task 2: 汎用ラッパー hunk-review/SKILL.md

**Files:**
- Create: `/home/aya/.dotfiles/.claude-global/skills/hunk-review/SKILL.md`

**Interfaces:**
- Consumes: Task 1の `review-pr/references/hunk-session.md`（相対パスで参照させる）
- Produces: skill `hunk-review`（`/hunk-review` で起動）

- [ ] **Step 1: SKILL.md作成**

以下の内容で作成する:

````markdown
---
name: hunk-review
description: Use when the user wants to review any diff (working tree, commit, branch) interactively via a live Hunk TUI session. Triggers on "/hunk-review", "hunkでレビュー", "hunkで見て", "この差分をhunkで".
allowed-tools: Bash, Read, Grep, AskUserQuestion
version: 1.0.0
---

# hunk 連携レビュー（汎用）

hunkの生きたTUIセッションに接続し、任意のdiff（作業ツリー・commit・ブランチ間）を
ユーザーと一緒にレビューするスキル。PR文脈に限定しない軽量な入口。

## 連携手順の実体

**まず必ず** `../review-pr/references/hunk-session.md` を読むこと。
接続フロー・ナビゲート・コメント・承認ガード・既知エラーの全手順はそこに集約されている。

（絶対パス: `/home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md`）

## 大原則

- **Claudeは `hunk diff` / `hunk show` を自分で実行しない。** TUIはユーザーが開く
- `navigate` は自由・`comment add`/`apply` は付けたら報告・`clear`/`rm` は承認必須

## フロー

### Step 1: セッション接続

`hunk session list --json` で確認。無ければ、ユーザーに開き方を案内して待つ:

- 作業ツリー全体: `hunk diff`（dotfiles等では `! hunk diff`）
- mainとの差分: `hunk diff main`
- ブランチの変更だけ（PR相当）: `hunk diff main...HEAD`
- 特定コミット: `hunk show HEAD~1`

「開いた」と言われたら再度 `session list` で接続する。

### Step 2: 構造把握

`hunk session review --repo . --json` でファイル／hunk構造を把握する。
生diffが必要なファイルだけ `--include-patch` を追加。

### Step 3: レビュー先導

ユーザーの関心・変更の重要度に沿って:
1. `hunk session navigate` で該当箇所へ画面を動かす
2. 気づいた点を `hunk session comment add --focus` で添える（付けたら報告）
3. 複数まとめて付けるなら `comment apply --stdin` のbatch

一番わかりやすい順序で進める（ファイル順に縛られない）。全hunkにコメントせず、
ユーザーが自力で気づきにくい点を強調する。

### Step 4: まとめ

見終わったらレビュー内容を要約する。破壊的なコメント削除が要るなら承認を取る。
````

- [ ] **Step 2: 手動検証 — frontmatterと参照パスが正しいか**

Run:
```bash
head -6 /home/aya/.dotfiles/.claude-global/skills/hunk-review/SKILL.md
grep -q "hunk-session.md" /home/aya/.dotfiles/.claude-global/skills/hunk-review/SKILL.md && echo "参照OK"
ls /home/aya/.dotfiles/.claude-global/skills/review-pr/references/hunk-session.md && echo "参照先実在OK"
```
Expected: frontmatterに `name: hunk-review` があり、参照先ファイルが実在する

- [ ] **Step 3: 手動検証 — symlink経由でskillが認識されるか**

Run:
```bash
ls -la ~/.claude/skills/hunk-review/SKILL.md
```
Expected: `~/.claude/skills/hunk-review/` がsymlink経由で `hunk-review/SKILL.md` を指す
（`.claude-global/skills/` がsymlink元。認識されない場合はhome-manager switchが必要か確認）

- [ ] **Step 4: Commit**

```bash
cd /home/aya/.dotfiles; rm -f .git/index.lock
git add .claude-global/skills/hunk-review/SKILL.md
rm -f .git/index.lock
git commit -m "feat(hunk-review): 汎用hunk連携レビューskillを新規追加"
```

---

## Task 3: review-pr/SKILL.md にhunk連携を追加（v1.3.0→v1.4.0）

**Files:**
- Modify: `/home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md`

**Interfaces:**
- Consumes: Task 1の `references/hunk-session.md`（同skill配下の相対参照）

- [ ] **Step 1: versionを1.3.0→1.4.0に更新**

`SKILL.md:5` の
```
version: 1.3.0
```
を
```
version: 1.4.0
```
に変更する。

- [ ] **Step 2: Step 1（PR情報取得）の直後にhunk連携分岐を挿入**

`SKILL.md` の「### Step 2: 全体概要の説明」の**直前**（現在の69行目「```」の後、
71行目「### Step 2」の前）に、以下の新セクションを挿入する:

````markdown
### Step 1.5: hunk連携（オプション）

PR情報を取得したら、hunkのTUIで視覚的にレビューするか確認する。

→ **[AskUserQuestion]** 「hunkのTUIで差分を見ながらレビューする？それともテキストで進める？」
- 選択肢: 「hunkで見る」/「テキストで進める（デフォルト）」

**「hunkで見る」が選ばれた場合のみ:**

1. 連携手順は `references/hunk-session.md` に従う（**必ず読むこと**）
2. **Claudeは `hunk diff` を自分で実行しない。** ユーザーに開いてもらう:
   「`hunk diff <base>...HEAD` を自分の端末で開いてな（`<base>` はPRのマージ先）」
   （ローカルにPRブランチがcheckout済みの前提。未checkoutなら `gh pr checkout <番号>` を案内）
3. 「開いた」と言われたら `hunk session list` で接続
4. 以降のStep 3（設計判断の解説）で、設計判断を説明するたびに
   `hunk session navigate` で該当hunkへ画面を動かし、所見を `hunk session comment add` で添える
5. `navigate` は自由・`comment` は付けたら報告・`clear`/`rm` は承認必須

**「テキストで進める」が選ばれた場合:**
従来通り `gh pr diff` のテキストベースで進行する（hunkは使わない）。
````

- [ ] **Step 3: 手動検証 — 既存フローが壊れていないか**

Run:
```bash
grep -c "AskUserQuestion" /home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md
grep -E "Iron Law|CONFIRMED|PLAUSIBLE|REFUTED" /home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md
grep "version: 1.4.0" /home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md
```
Expected: Iron Law・検証ガード（CONFIRMED/PLAUSIBLE/REFUTED）が残存、version 1.4.0、
AskUserQuestion言及が増えている（Step 1.5分）

- [ ] **Step 4: 手動検証 — Step番号の連続性と参照整合**

Run:
```bash
grep -E "^### Step" /home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md
grep -q "references/hunk-session.md" /home/aya/.dotfiles/.claude-global/skills/review-pr/SKILL.md && echo "参照OK"
```
Expected: Step 0→1→1.5→2→3→4→4.5→5→6 の順で並ぶ。references参照あり

- [ ] **Step 5: Commit**

```bash
cd /home/aya/.dotfiles; rm -f .git/index.lock
git add .claude-global/skills/review-pr/SKILL.md
rm -f .git/index.lock
git commit -m "feat(review-pr): hunk連携レビューをオプション追加 (v1.4.0)"
```

---

## Task 4: 統合検証とpush

**Files:** なし（検証とpushのみ）

- [ ] **Step 1: 3ファイルの存在と関係を確認**

Run:
```bash
cd /home/aya/.dotfiles
ls .claude-global/skills/hunk-review/SKILL.md \
   .claude-global/skills/review-pr/SKILL.md \
   .claude-global/skills/review-pr/references/hunk-session.md
```
Expected: 3ファイルすべて存在

- [ ] **Step 2: 実地スモークテスト — hunkセッションで一連の連携が動くか**

ユーザーに `hunk diff` を開いてもらった上で:
```bash
cd /home/aya/.dotfiles
hunk session list --json | head -5           # 接続確認
hunk session review --repo . --json | python3 -c "import json,sys; print('files:', len(json.load(sys.stdin)['review']['files']))"
```
Expected: セッションが見え、review構造が取れる（リファレンス記載の手順が実際に通ることの確認）

- [ ] **Step 3: push**

```bash
cd /home/aya/.dotfiles; rm -f .git/index.lock
git remote -v | grep -q github-aya215 || git remote set-url origin git@github-aya215:aya-215/dotfiles.git
rm -f .git/index.lock
git push
```
Expected: main へのpush成功

---

## Self-Review

- **Spec coverage:** ①references（Task1）②hunk-review（Task2）③review-pr改訂（Task3）＋統合検証（Task4）で設計書の3コンポーネント＋検証を網羅。設計書の非対象（tmux自動分割・TUI自動起動・テーマ連携）はタスク化せず＝正しい
- **Placeholder scan:** 各Stepに実content（skill全文・検証コマンド・期待結果）を記載。TBD/TODOなし
- **Type consistency:** 参照パス `references/hunk-session.md` は全タスクで一貫。frontmatter形式（name/description/allowed-tools/version）は既存skill準拠で統一

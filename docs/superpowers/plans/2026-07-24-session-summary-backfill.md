# セッション要約バックフィル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SessionEnd hook 非発火で取りこぼしたセッションを、cron で日次に拾って既存 summarize.sh に投入し要約する `backfill.sh` を作る。

**Architecture:** backfill.sh は要約ロジックを持たない薄い層。現存 jsonl（subagents 除外）を走査し、`sessions/**/*-<sid8>.md` の有無で未生成を判定、未生成だけを既存 `summarize.sh <jsonl> <full-session-id>` に投入する。薄いセッション判定・要約失敗ハンドリングは summarize.sh の既存ガードに一任（責務分離）。冪等・flock 多重起動ガード・`--dry-run` を持つ。

**Tech Stack:** bash（set -euo pipefail）、flock、crontab。テストは既存 `summarize-test.sh` と同じスタブ注入方式。

## Global Constraints

- shebang `#!/bin/bash`、`set -euo pipefail`、ShellCheck 準拠（shell-conventions.md）
- 環境変数 UPPER_SNAKE_CASE / ローカル変数 lower_snake_case / 関数は `local` 宣言・ドキュメントコメント必須
- ログは `~/.local/log/claude-summarize-backfill.log`
- テスト容易性のため走査ルートを環境変数で上書き可能にする: `PROJECTS_ROOT`（既定 `$HOME/.claude/projects`）、`SESSIONS_ROOT`（既定 `$HOME/.nb/claude/sessions`）、`SUMMARIZE_BIN`（既定 同ディレクトリの summarize.sh）
- 対象判定は sid8（session-id 先頭8桁）突合。これは summarize.sh の dedup キー（`*-${sid_short}.md`）と同一
- crontab は手動管理（既存 nb-sync.sh / fire-daily-review.sh と同流儀）。スクリプト本体のみ dotfiles 管理

---

## File Structure

- Create: `scripts/claude-summarize/backfill.sh` — バックフィル本体（対象選定＋summarize.sh 投入）
- Create: `scripts/claude-summarize/backfill-test.sh` — スタブ注入テスト（summarize.sh をスタブ化）
- Modify: crontab（`crontab -e` 相当。ファイルではないので手順で対応）

---

## Task 1: backfill.sh の対象選定ロジック（--dry-run）

未生成セッションを検出して sid のリストを出力する部分。まず `--dry-run` だけ動く状態にする。

**Files:**
- Create: `scripts/claude-summarize/backfill.sh`
- Test: `scripts/claude-summarize/backfill-test.sh`

**Interfaces:**
- Consumes: なし
- Produces:
  - `backfill.sh [--dry-run]` を実行可能
  - 環境変数 `PROJECTS_ROOT` / `SESSIONS_ROOT` / `SUMMARIZE_BIN` で注入可能
  - `--dry-run` 時: 未生成 jsonl のフルパスを1行1件で stdout に出力し summarize は呼ばない
  - 判定規則: `$PROJECTS_ROOT` 配下の `*.jsonl`（`*/subagents/*` 除外）のうち、ファイル名先頭8桁 sid8 に対応する `$SESSIONS_ROOT/**/*-<sid8>.md` が存在しないものが対象

- [ ] **Step 1: 失敗するテストを書く（backfill-test.sh を新規作成）**

```bash
#!/bin/bash
# backfill-test.sh - backfill.sh の動作確認テスト
# 使用方法: bash scripts/claude-summarize/backfill-test.sh （全部 ok なら ALL OK で exit 0）
# summarize.sh はスタブ（呼ばれた引数を calls.log に追記するだけ）に差し替えて検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# ---- スタブ summarize.sh ----
# 呼び出し毎に "引数1 引数2" を calls.log に追記する（要約は生成しない）
mkdir -p "$TMP/bin"
cat > "$TMP/bin/summarize.sh" <<'EOF'
#!/bin/bash
set -u
printf '%s %s\n' "$1" "$2" >> "$SUMMARIZE_CALLS"
EOF
chmod +x "$TMP/bin/summarize.sh"

# ---- fixture: projects と sessions を作る ----
# 3セッション: aaaaaaaa(未生成) / bbbbbbbb(生成済み) / cccccccc(未生成) + subagent(除外対象)
setup_fixture() {
  local root="$1"
  local proj="$root/projects/-home-aya-testproj"
  local sess="$root/sessions/2026-07-20"
  mkdir -p "$proj" "$sess" "$proj/subagents/workflows/wf_x"
  # jsonl は中身の有無を backfill は問わない（summarize.sh に委譲）ので最小限でよい
  echo '{"type":"user"}' > "$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/bbbbbbbb-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/cccccccc-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/subagents/workflows/wf_x/agent-dddddddd.jsonl"
  # bbbbbbbb だけ要約 md が既に存在する
  echo '# summary' > "$sess/testproj-0900-bbbbbbbb.md"
}

# assert_contains / assert_absent（summarize-test.sh と同型）
assert_line_count() {
  local desc="$1" file="$2" expected="$3"
  local got; got="$(wc -l < "$file" 2>/dev/null || echo 0)"
  if [ "$got" -eq "$expected" ]; then echo "ok: $desc"; else
    echo "NG: $desc → 期待 $expected 行 / 実際 $got 行"; fails=$((fails + 1)); fi
}
assert_grep() {
  local desc="$1" file="$2" pat="$3"
  if [ -f "$file" ] && grep -qE "$pat" "$file"; then echo "ok: $desc"; else
    echo "NG: $desc → file=$file pat=$pat"; fails=$((fails + 1)); fi
}
assert_not_grep() {
  local desc="$1" file="$2" pat="$3"
  if [ -f "$file" ] && grep -qE "$pat" "$file"; then
    echo "NG: $desc → 含んではいけない: $pat"; fails=$((fails + 1)); else echo "ok: $desc"; fi
}

# ==== case1: --dry-run は未生成2件だけを出力し subagent と生成済みを除外 ====
root1="$TMP/case1"; setup_fixture "$root1"
out1="$TMP/case1.out"
PROJECTS_ROOT="$root1/projects" SESSIONS_ROOT="$root1/sessions" \
  bash "$SCRIPT_DIR/backfill.sh" --dry-run > "$out1" 2>/dev/null || true
assert_line_count "case1: 未生成2件が出力される" "$out1" 2
assert_grep "case1: aaaaaaaa が対象" "$out1" 'aaaaaaaa-1111'
assert_grep "case1: cccccccc が対象" "$out1" 'cccccccc-1111'
assert_not_grep "case1: bbbbbbbb(生成済み)は除外" "$out1" 'bbbbbbbb'
assert_not_grep "case1: subagent は除外" "$out1" 'subagents'

# ==== 結果 ====
if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: FAIL（backfill.sh が存在しないため case1 が全部 NG、または実行エラー）

- [ ] **Step 3: backfill.sh を最小実装（--dry-run の対象選定のみ）**

```bash
#!/bin/bash
# backfill.sh - SessionEnd hook 非発火で取りこぼしたセッションを拾って要約する
#
# 現存 jsonl（subagents 除く）のうち要約 md が未生成のものを検出し、
# 既存 summarize.sh に投入する。薄いセッション判定・要約失敗は summarize.sh の
# 既存ガードに一任する（責務分離: backfill は決定的な対象選定のみ担う）。
# cron から日次で呼ぶ。同一 sid の md がある限り再投入しないため冪等。
#
# 使用方法:
#   ./backfill.sh            通常実行（未生成を summarize.sh に投入）
#   ./backfill.sh --dry-run  対象 jsonl パスを stdout に出すだけ（summarize は呼ばない）
# 環境変数（テスト用に上書き可能）:
#   PROJECTS_ROOT / SESSIONS_ROOT / SUMMARIZE_BIN
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/.claude/projects}"
SESSIONS_ROOT="${SESSIONS_ROOT:-$HOME/.nb/claude/sessions}"
SUMMARIZE_BIN="${SUMMARIZE_BIN:-$SCRIPT_DIR/summarize.sh}"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

# has_summary <sid8> — その sid8 の要約 md が既に存在するか
has_summary() {
  local sid8="$1"
  find "$SESSIONS_ROOT" -type f -name "*-${sid8}.md" -print -quit 2>/dev/null | grep -q .
}

# 現存 jsonl（subagents 除外）を走査し、未生成のものを処理する
find "$PROJECTS_ROOT" -type f -name '*.jsonl' ! -path '*/subagents/*' 2>/dev/null | while read -r jsonl; do
  fname="$(basename "$jsonl" .jsonl)"
  # ファイル名がフル session-id（UUID）でないものはスキップ
  case "$fname" in
    [0-9a-f]*-*-*-*-*) : ;;
    *) continue ;;
  esac
  sid8="${fname:0:8}"
  if has_summary "$sid8"; then
    continue
  fi
  if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' "$jsonl"
  else
    bash "$SUMMARIZE_BIN" "$jsonl" "$fname" || true
  fi
done
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: `ok: case1: ...` が4件 → `ALL OK`

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/backfill.sh scripts/claude-summarize/backfill-test.sh
git commit -m "feat(claude-summarize): 取りこぼしセッションを拾う backfill.sh を追加（--dry-run 対象選定）"
```

---

## Task 2: summarize.sh 投入と flock 多重起動ガード

通常実行時に summarize.sh を呼ぶ経路（Task 1 で実装済み）を検証し、cron 重複対策の flock を追加する。

**Files:**
- Modify: `scripts/claude-summarize/backfill.sh`
- Test: `scripts/claude-summarize/backfill-test.sh`

**Interfaces:**
- Consumes: Task 1 の `backfill.sh`（`SUMMARIZE_BIN` 注入、対象選定ロジック）
- Produces:
  - 通常実行時: 未生成 jsonl ごとに `summarize.sh <jsonl> <full-session-id>` を呼ぶ
  - flock により同時に2プロセス走らない（2重起動時、後発は何もせず終了）

- [ ] **Step 1: 失敗するテストを追加（backfill-test.sh の case1 の後、結果ブロックの前に挿入）**

```bash
# ==== case2: 通常実行は未生成2件だけ summarize.sh を呼ぶ（sid はフル session-id） ====
root2="$TMP/case2"; setup_fixture "$root2"
calls2="$TMP/case2.calls"; : > "$calls2"
PROJECTS_ROOT="$root2/projects" SESSIONS_ROOT="$root2/sessions" \
  SUMMARIZE_BIN="$TMP/bin/summarize.sh" SUMMARIZE_CALLS="$calls2" \
  bash "$SCRIPT_DIR/backfill.sh" > /dev/null 2>&1 || true
assert_line_count "case2: summarize.sh が2回呼ばれる" "$calls2" 2
assert_grep "case2: aaaaaaaa をフル session-id で渡す" "$calls2" 'aaaaaaaa-1111-2222-3333-444444444444 aaaaaaaa-1111-2222-3333-444444444444'
assert_not_grep "case2: bbbbbbbb(生成済み)は呼ばれない" "$calls2" 'bbbbbbbb'

# ==== case3: 冪等 — 全 md が既にあれば summarize.sh を1回も呼ばない ====
root3="$TMP/case3"; setup_fixture "$root3"
# aaaaaaaa と cccccccc の md も用意して全生成済みにする
echo '# s' > "$root3/sessions/2026-07-20/testproj-0901-aaaaaaaa.md"
echo '# s' > "$root3/sessions/2026-07-20/testproj-0902-cccccccc.md"
calls3="$TMP/case3.calls"; : > "$calls3"
PROJECTS_ROOT="$root3/projects" SESSIONS_ROOT="$root3/sessions" \
  SUMMARIZE_BIN="$TMP/bin/summarize.sh" SUMMARIZE_CALLS="$calls3" \
  bash "$SCRIPT_DIR/backfill.sh" > /dev/null 2>&1 || true
assert_line_count "case3: 冪等 — 呼び出し0回" "$calls3" 0
```

- [ ] **Step 2: テストを実行して case2/case3 を確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: case2 が通り case3 も通る（Task 1 の実装で summarize 投入は既に動くため、多くは PASS。flock 未実装でもこのテストは通る）。ここで一旦 `ALL OK` を確認。

- [ ] **Step 3: flock 多重起動ガードを追加（backfill.sh の対象走査を flock 配下に）**

`set -euo pipefail` と変数定義の後、`dry_run` 判定の後に以下を挿入。走査本体の `find ... | while ...` を関数化して flock 下で呼ぶ。dry-run 時は flock 不要（読み取りのみ）。

```bash
# run_backfill — 対象走査の本体（Task 1 の find...while をこの関数に移す）
run_backfill() {
  find "$PROJECTS_ROOT" -type f -name '*.jsonl' ! -path '*/subagents/*' 2>/dev/null | while read -r jsonl; do
    fname="$(basename "$jsonl" .jsonl)"
    case "$fname" in
      [0-9a-f]*-*-*-*-*) : ;;
      *) continue ;;
    esac
    sid8="${fname:0:8}"
    has_summary "$sid8" && continue
    if [ "$dry_run" -eq 1 ]; then
      printf '%s\n' "$jsonl"
    else
      bash "$SUMMARIZE_BIN" "$jsonl" "$fname" || true
    fi
  done
}

if [ "$dry_run" -eq 1 ]; then
  run_backfill
else
  # cron 重複・長引き対策: 多重起動を flock で防ぐ（後発は即終了）
  readonly LOCK_FILE="${TMPDIR:-/tmp}/claude-summarize-backfill.lock"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] 既に実行中のためスキップ"
    exit 0
  fi
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] backfill 開始"
  run_backfill
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] backfill 完了"
fi
```

（注: Task 1 の末尾にあった `find ... | while ...` 直書きブロックは削除し、上記 `run_backfill` 関数＋分岐に置き換える。`has_summary` 関数定義はそのまま残す。）

- [ ] **Step 4: テストを実行して全ケース成功を確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: case1〜case3 すべて `ok:` → `ALL OK`

- [ ] **Step 5: ShellCheck をかける**

Run: `shellcheck scripts/claude-summarize/backfill.sh`
Expected: 警告なし（あれば修正。`SC2155` 等が出たら宣言と代入を分ける）

- [ ] **Step 6: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/backfill.sh scripts/claude-summarize/backfill-test.sh
git commit -m "feat(claude-summarize): backfill に summarize 投入経路と flock 多重起動ガードを追加"
```

---

## Task 3: 実データ dry-run 検証と crontab 登録

実環境で対象件数が監査の実測（未生成387件近辺）と整合するか確認し、crontab に 21:00 登録する。

**Files:**
- Modify: crontab（`crontab -e`）

**Interfaces:**
- Consumes: Task 2 完成の `backfill.sh`
- Produces: crontab に `0 21 * * *` の1行

- [ ] **Step 1: 実データで dry-run し件数を確認**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run | wc -l`
Expected: 監査実測（387）に近い件数。大きくズレたら判定ロジックを再点検（sid8 突合・subagents 除外）。

- [ ] **Step 2: 実データで数本だけ生成してみる（安全確認）**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run | head -3`
で対象3本のパスを確認し、1本だけ手動で summarize にかけて md が出るか確認:
```bash
f="$(bash scripts/claude-summarize/backfill.sh --dry-run | head -1)"
sid="$(basename "$f" .jsonl)"
bash scripts/claude-summarize/summarize.sh "$f" "$sid"
find ~/.nb/claude/sessions -name "*-${sid:0:8}.md" -newermt "-2 min"
```
Expected: 新しい md が1本出る（薄いセッションなら出ないこともある。その場合は別の1本で確認）。

- [ ] **Step 3: crontab に登録**

Run: `crontab -e` で以下を既存2行の間（daily-review の前）に追加:
```
0 21 * * * /home/aya/.dotfiles/scripts/claude-summarize/backfill.sh >> /home/aya/.local/log/claude-summarize-backfill.log 2>&1
```

- [ ] **Step 4: 登録確認**

Run: `crontab -l`
Expected: nb-sync / backfill(0 21) / fire-daily-review(10 22) の3行が並ぶ

- [ ] **Step 5: 手動フル実行して初回387件をバックフィル（任意・時間がかかる）**

Run: `bash scripts/claude-summarize/backfill.sh`
Expected: ログに開始/完了が出て、`~/.nb/claude/sessions/` の md が大幅に増える。cron 初回を待ってもよいが、遡及分をすぐ埋めたい場合はここで流す。

- [ ] **Step 6: 完了確認（ドキュメント更新は不要、crontab はファイル管理外）**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run | wc -l`
Expected: Step 5 を実行した場合、件数が大きく減っている（生成済みが除外されるため）。冪等性の最終確認。

---

## 後続タスク（別プラン）
- ③ フェンス破損68本の後処理強化＋既存分の再生成

---

# 改訂（2026-07-24）: 自己参照ループ欠陥の修正と cli 絞り込み

## 背景（実装後に判明した事実）

Task 1-2 は完了・Approved 済み（commits 652220e..ee30e99）。Task 3 の実データ検証中に **2つの重大欠陥**が判明し、別セッションの原因究明（`docs/handoff-2026-07-24-sessionend-rootcause.md`）と本セッションの対照実験で以下を CONFIRMED:

- **欠陥X（ゴミ生成）**: summarize.sh が `claude -p`（フラグ無し）で要約するたびに、その呼び出し自体が新規セッション jsonl（`entrypoint=sdk-cli`）として `~/.claude/projects/` に永続化される。対照実験で実証: `--no-session-persistence` 付き→jsonl差分0 / 無し→+1。
- **欠陥Y（ゴミ収集）**: backfill の対象判定が entrypoint を見ないため、欠陥Xで生まれた要約由来 jsonl を「未要約セッション」として拾ってしまう（15本全て dry-run 対象化を確認）。→ 自己参照ループ。
- **精度の過大評価**: 「never-started 387件」の実体は sdk-cli 280 + sdk-py 83 + cli 17 + none 7。**要約すべき真の欠損は cli の最大16件（うち極小7件を除く実質約9件）**。363件は非対話の自動生成物（要約由来269＋security-review等94）で要約対象外。
- **entrypoint は信頼できる弁別子**: SessionEnd 発火済み（要約成功した真の対話）集合はサンプル 9/9 が全て `entrypoint=cli`、sdk 混入なし。

## 修正方針（多層防御）

決定的判定はコード側に置く（learned-rule: 決定的処理と非決定的処理の分離）。

- **X の根絶**: summarize.sh の `claude -p` に `--no-session-persistence` を付け、要約呼び出しが jsonl を残さないようにする（本命・根絶策。実機で差分0を実証済み）。
- **Y の防御**: extract.py と backfill.sh の両方で entrypoint フィルタを入れる（多層防御）。
  - extract.py(b): jsonl が sdk-cli/sdk-py なら空出力で終了（summarize.sh の「本文空なら要約しない」ガードに乗る）。hook 経由・backfill 経由の両入口をカバー。
  - backfill.sh(a): dry-run/通常の対象走査で sdk-cli/sdk-py を除外（無駄な summarize 呼び出しを未然に防ぐ）。

## Global Constraints（改訂タスク共通・verbatim厳守）

- **entrypoint 判定ルール**: jsonl の user/assistant/attachment 行に載る `entrypoint` 値を見て、**明示的に `sdk-cli` または `sdk-py` の時だけ除外する。`cli` および entrypoint 欠落（none）は必ず通す**。（欠落を除外にすると手作り fixture の既存テストが全滅し、実データの none 7件も取りこぼすため。安全側=include に倒す。）
- 上記は extract.py 側・backfill.sh 側の両方で同一ルール。
- 既存の Global Constraints（shebang/set -euo pipefail/ShellCheck/命名/sid8突合/環境変数注入）は引き続き全タスクに適用。
- 掃除（既存の要約由来 jsonl 363本の削除）は**本プランのスコープ外**。entrypoint フィルタが入れば無害化されるため correctness に不要であり、`~/.claude/projects/`（Claude 自身のセッション履歴領域）の不可逆削除はユーザー確認を要する別判断とする。

---

## Task 4: summarize.sh に --no-session-persistence を追加（欠陥X根絶）

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh:98`（`claude -p` 呼び出し行）
- Test: `scripts/claude-summarize/summarize-test.sh`（スタブなのでフラグ有無は透過。回帰は e2e で担保）

**Interfaces:**
- Consumes: なし
- Produces: summarize.sh の要約呼び出しが jsonl を永続化しない

- [ ] **Step 1: 現行の呼び出し行を確認**

Run: `grep -n 'disableAllHooks' scripts/claude-summarize/summarize.sh`
Expected: 98行目に `printf '%s' "$PROMPT" | "$CLAUDE_BIN" -p --model haiku --settings '{"disableAllHooks":true}' 2>"$claude_err"`

- [ ] **Step 2: --no-session-persistence を追加**

98行目を次に変更（`--model haiku` の直後にフラグを挿入）:

```bash
  if ! raw="$(printf '%s' "$PROMPT" | "$CLAUDE_BIN" -p --model haiku --no-session-persistence --settings '{"disableAllHooks":true}' 2>"$claude_err")"; then
```

- [ ] **Step 3: 既存テストが壊れていないこと（スタブなので透過）**

Run: `bash scripts/claude-summarize/summarize-test.sh`
Expected: `ALL OK`（スタブ claude はフラグを無視するため全ケース従来通り）

- [ ] **Step 4: e2e 検証（完了条件・スタブでは検証不能な本命確認）**

本物の transcript 1本を実 summarize.sh に通し、(a) md が生成される (b) jsonl が増えない の両方を確認:

```bash
CLAUDE_BIN="$HOME/.local/bin/claude"
PROJ="$HOME/.claude/projects"
# 未要約の実 transcript を1本選ぶ（cli のもの）
f="$(bash scripts/claude-summarize/backfill.sh --dry-run 2>/dev/null | head -1)"
sid="$(basename "$f" .jsonl)"
before=$(find "$PROJ" -maxdepth 2 -name '*.jsonl' | wc -l)
bash scripts/claude-summarize/summarize.sh "$f" "$sid"
after=$(find "$PROJ" -maxdepth 2 -name '*.jsonl' | wc -l)
echo "jsonl差分: $((after - before)) （0であること）"
find ~/.nb/claude/sessions -name "*-${sid:0:8}.md" -newermt "-3 min"
```
Expected: jsonl差分 0、かつ md が1本出る（薄いセッションなら出ない場合あり→別の1本で再確認）。**差分が0でなければこのタスクは未完了。**

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/summarize.sh
git commit -m "fix(claude-summarize): 要約呼び出しに --no-session-persistence を付与し自己参照jsonl生成を根絶"
```

---

## Task 5: extract.py に entrypoint フィルタ（欠陥Y防御・多層1段目）

**Files:**
- Modify: `scripts/claude-summarize/extract.py`
- Test: `scripts/claude-summarize/summarize-test.sh`（sdk-cli fixture で空出力→md非生成を検証）

**Interfaces:**
- Consumes: なし
- Produces: extract.py は sdk-cli/sdk-py の jsonl に対しヘッダのみ（本文空）を出力する。cli/欠落は従来通り本文を出力。

- [ ] **Step 1: 失敗するテストを summarize-test.sh に追加（case7）**

`summarize-test.sh` の「==== 結果 ====」ブロックの直前に挿入。sdk-cli の transcript を作り、summarize.sh が md を生成しないことを検証:

```bash
# ==== case7: entrypoint=sdk-cli のセッションは要約されない（自己参照ループ防止） ====
case7_dir="$TMP/case7"
mkdir -p "$case7_dir/stub" "$case7_dir/sessions"
good_body > "$case7_dir/stub/out"
cat > "$case7_dir/transcript.jsonl" <<JSONL
{"type":"user","sessionId":"$SID","cwd":"/home/aya/testproj","entrypoint":"sdk-cli","timestamp":"2026-07-13T01:00:00.000Z","message":{"content":"要約プロンプト本文"}}
{"type":"assistant","sessionId":"$SID","entrypoint":"sdk-cli","timestamp":"2026-07-13T02:34:56.000Z","message":{"content":[{"type":"text","text":"要約結果"}]}}
JSONL
CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$case7_dir/stub" SESSIONS_ROOT="$case7_dir/sessions" \
  bash "$SCRIPT_DIR/summarize.sh" "$case7_dir/transcript.jsonl" "$SID" > /dev/null 2>&1 || true
out7="$case7_dir/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_absent "case7: sdk-cli セッションは md 生成されない" "$out7"

# ==== case8: entrypoint 欠落（従来 fixture 相当）は従来通り要約される（回帰防止） ====
# ※ case1 が既に entrypoint 無し fixture で md 生成を検証済みなので、ここは明示の再確認は省略可。
#   万一 case1 が変わった場合の保険として本文コメントで意図を残す。
```

- [ ] **Step 2: テストを実行して case7 が失敗することを確認**

Run: `bash scripts/claude-summarize/summarize-test.sh`
Expected: case7 が NG（現状 extract.py は entrypoint を見ないため sdk-cli でも本文を出力し md が生成される）

- [ ] **Step 3: extract.py に entrypoint 判定を実装**

`main()` 内、行ループの中で最初に entrypoint を拾い、sdk-cli/sdk-py なら本文を出さずヘッダのみで終了する。`d.get("type") not in ("user","assistant")` の continue の**前**に entrypoint 収集を置く（attachment 行にも載るため）。実装例:

ループ内の冒頭付近（`d = json.loads(raw)` の直後、type チェックより前）に追加:

```python
            # entrypoint（対話/非対話の弁別子）を最初に見つけた値で確定する
            if not entrypoint:
                _ep = d.get("entrypoint")
                if isinstance(_ep, str) and _ep:
                    entrypoint = _ep
```

ループ変数の初期化（`lines_out: list[str] = []` の近く）に追加:

```python
    entrypoint = ""
```

ループを抜けた後、ヘッダ組み立ての前に判定を追加:

```python
    # sdk-cli(claude -p) / sdk-py(Python SDK) は非対話の自動生成実行。
    # 要約対象外（summarize.sh の自己参照ループ防止）。明示的にこの2値の時だけ弾き、
    # cli および entrypoint 欠落は通す（安全側=include）。
    if entrypoint in ("sdk-cli", "sdk-py"):
        # ヘッダのみ出力し本文は空にする → summarize.sh の「本文空なら要約しない」ガードに乗る
        lines_out = []
```

（`lines_out = []` により本文空。既存のヘッダ出力ロジックはそのまま流れる。）

- [ ] **Step 4: テストを実行して case7 が通ることを確認**

Run: `bash scripts/claude-summarize/summarize-test.sh`
Expected: 全ケース `ok:` → `ALL OK`（case7 含む。case1 の entrypoint 無し fixture が従来通り md 生成することも維持）

- [ ] **Step 5: ShellCheck は対象外（Python）だが構文確認**

Run: `python3 -c "import ast; ast.parse(open('scripts/claude-summarize/extract.py').read())"`
Expected: エラーなし（構文OK）

- [ ] **Step 6: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/extract.py scripts/claude-summarize/summarize-test.sh
git commit -m "fix(claude-summarize): extract.py で sdk-cli/sdk-py を要約対象外にする（多層防御1段目）"
```

---

## Task 6: backfill.sh に entrypoint フィルタ（欠陥Y防御・多層2段目）＋真の欠損への絞り込み

**Files:**
- Modify: `scripts/claude-summarize/backfill.sh`（run_backfill の対象走査）
- Test: `scripts/claude-summarize/backfill-test.sh`

**Interfaces:**
- Consumes: Task 1-2 の backfill.sh（run_backfill / has_summary / dry-run 分岐）
- Produces: backfill が sdk-cli/sdk-py の jsonl を対象から除外する（dry-run にも出さない）

- [ ] **Step 1: 失敗するテストを backfill-test.sh に追加（case5）**

`setup_fixture` に sdk-cli の jsonl を1本増やし、それが dry-run 対象に出ないことを検証。まず `setup_fixture` 内の fixture 追加（既存の3セッションの後に）:

```bash
  # eeeeeeee: entrypoint=sdk-cli の非対話セッション（要約対象外・除外されるべき）
  cat > "$proj/eeeeeeee-1111-2222-3333-444444444444.jsonl" <<'JSONL'
{"type":"user","entrypoint":"sdk-cli","message":{"content":"要約プロンプト"}}
JSONL
```

そして case1 の後（結果ブロックの前）に:

```bash
# ==== case5: entrypoint=sdk-cli は dry-run 対象から除外される（自己参照ループ防止） ====
root5="$TMP/case5"; setup_fixture "$root5"
out5="$TMP/case5.out"
PROJECTS_ROOT="$root5/projects" SESSIONS_ROOT="$root5/sessions" \
  bash "$SCRIPT_DIR/backfill.sh" --dry-run > "$out5" 2>/dev/null || true
assert_not_grep "case5: sdk-cli は対象外" "$out5" 'eeeeeeee'
assert_grep "case5: cli/欠落の未生成(aaaaaaaa)は従来通り対象" "$out5" 'aaaaaaaa-1111'
```

（注: 既存 case1 の期待「未生成2件」は、fixture に eeeeeeee を足しても sdk-cli 除外により2件のまま維持される。case1 の assert_line_count が 2 のままであることも確認すること。）

- [ ] **Step 2: テストを実行して case5 が失敗することを確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: case5 の `assert_not_grep` が NG（現状 backfill は entrypoint を見ないため eeeeeeee が対象に出る）。case1 の件数アサートも 2→3 にずれて NG になる可能性あり（eeeeeeee が混入するため）。両方が Step 3 実装で解消される。

- [ ] **Step 3: backfill.sh に entrypoint 判定を実装**

`run_backfill` 内、`has_summary "$sid8" && continue` の**前**に entrypoint 判定を追加。jsonl 先頭の限られた行だけ見て判定する（全行読むと重いので `head` で先頭数十行に限定）:

```bash
    # entrypoint=sdk-cli/sdk-py（claude -p / Python SDK の非対話実行）は要約対象外。
    # 明示的にこの2値の時だけ除外し、cli・欠落は通す（安全側=include）。
    ep="$(grep -m1 -oE '"entrypoint":"[^"]*"' "$jsonl" 2>/dev/null | head -1 | sed -E 's/.*:"([^"]*)"/\1/')"
    case "$ep" in
      sdk-cli|sdk-py) continue ;;
    esac
```

（`grep -m1` で最初の entrypoint 出現だけ取る。ファイル全体をパースせず高速。空＝欠落は case にマッチせず通過。）

- [ ] **Step 4: テストを実行して全ケース成功を確認**

Run: `bash scripts/claude-summarize/backfill-test.sh`
Expected: case1〜case5 すべて `ok:` → `ALL OK`

- [ ] **Step 5: ShellCheck**

Run: `shellcheck scripts/claude-summarize/backfill.sh scripts/claude-summarize/backfill-test.sh`
Expected: 警告なし

- [ ] **Step 6: 実データ dry-run で件数が激減することを確認（欠陥Yの解消実証）**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run | wc -l`
Expected: 従来の 414 前後から **cli の真の欠損（最大16件・実質約9件）程度に激減**。363件のノイズ（sdk由来）が除外されていること。件数が期待レンジ（概ね 20 件未満）に収まるか確認。大きく外れたら entrypoint 判定を再点検。

- [ ] **Step 7: コミット**

```bash
cd ~/.dotfiles
git add scripts/claude-summarize/backfill.sh scripts/claude-summarize/backfill-test.sh
git commit -m "fix(claude-summarize): backfill で sdk-cli/sdk-py を対象除外し真の欠損のみ拾う（多層防御2段目）"
```

---

## Task 7: 初回バックフィル実行と cron 再有効化

**Files:**
- Modify: crontab（`crontab -e`）

**Interfaces:**
- Consumes: Task 4-6 完成の summarize.sh / extract.py / backfill.sh
- Produces: cli の真の欠損が要約され、crontab の backfill 行が再有効化される

- [ ] **Step 1: 実データ dry-run で対象を最終確認**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run`
Expected: cli の未要約セッションのみ（最大16件程度）。パスを目視し、`entrypoint=sdk-cli` の要約由来 jsonl が混じっていないことを確認。

- [ ] **Step 2: backfill を実行して真の欠損を埋める（軽量なので前景で可）**

Run: `bash scripts/claude-summarize/backfill.sh`
Expected: ログに開始/完了。数件〜十数件の md が生成される。実行後に `~/.claude/projects/` の jsonl 数が**増えていない**ことも確認（Task 4 の --no-session-persistence が効いている証拠）:

```bash
before=$(find ~/.claude/projects -maxdepth 2 -name '*.jsonl' | wc -l)
bash scripts/claude-summarize/backfill.sh
after=$(find ~/.claude/projects -maxdepth 2 -name '*.jsonl' | wc -l)
echo "jsonl差分: $((after - before)) （0であること＝ゴミが湧かない）"
```

- [ ] **Step 3: 冪等確認 — 再実行で対象0**

Run: `bash scripts/claude-summarize/backfill.sh --dry-run | wc -l`
Expected: Step 2 実行後は 0 件に近い（生成済みが除外される）。

- [ ] **Step 4: crontab の backfill 行を再有効化**

現在コメントアウト中（`# [一時無効化 2026-07-24: ...] 0 21 * * * ...`）。`crontab -e` でコメントを外し、既存2行と合わせて3行が有効になるようにする:

```
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh
0 21 * * * /home/aya/.dotfiles/scripts/claude-summarize/backfill.sh >> /home/aya/.local/log/claude-summarize-backfill.log 2>&1
10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh >> /tmp/fire-daily-review-cron.log 2>&1
```

- [ ] **Step 5: 登録確認**

Run: `crontab -l`
Expected: nb-sync / backfill(0 21・コメントなし) / fire-daily-review(10 22) の3行が有効。

---

## 改訂後の後続タスク
- ③ フェンス破損68本の後処理強化＋既存分の再生成（別プラン）
- （任意・要ユーザー確認）既存の要約由来 jsonl 363本の掃除。entrypoint フィルタで無害化済みのため優先度低。

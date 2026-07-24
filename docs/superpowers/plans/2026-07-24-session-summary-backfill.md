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
- ① SessionEnd 非発火の原因究明（PLAUSIBLE→CONFIRMED）
- ③ フェンス破損68本の後処理強化＋既存分の再生成

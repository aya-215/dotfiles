#!/bin/bash
# slice-sessions-test.sh - day-window.sh / slice-sessions.sh の動作確認テスト
# 使用方法: bash scripts/daily-review/slice-sessions-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1)); fi
}

# ---- day_window ----
# shellcheck source=day-window.sh
source "$SCRIPT_DIR/day-window.sh"
check "day_window 通常" $'2026-11-03T22:10:00+09:00\t2026-11-04T22:10:00+09:00' "$(day_window 2026-11-04)"
check "day_window 月またぎ" $'2026-10-31T22:10:00+09:00\t2026-11-01T22:10:00+09:00' "$(day_window 2026-11-01)"

# ---- スタブ summarize ----
# aaaaaaaa: md を書く / bbbbbbbb: 何も書かない / cccccccc: exit 3
cat > "$TMP/stub.sh" <<'EOF2'
#!/bin/bash
set -u
printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$STUB_CALLS"
case "$2" in
  aaaaaaaa*) mkdir -p "$SLICES_ROOT/$4"; echo "# s" > "$SLICES_ROOT/$4/proj-${2:0:8}.md" ;;
  cccccccc*) exit 3 ;;
  ffffffff*) echo "boom" >&2; exit 2 ;;
  99999999*) mkdir -p "$SLICES_ROOT/$4"; echo "# h" > "$SLICES_ROOT/$4/.proj-${2:0:8}.md" ;;
esac
exit 0
EOF2
chmod +x "$TMP/stub.sh"

U="1111-2222-3333-444444444444"
R1="$TMP/r1/-proj"; R2="$TMP/r2/-proj"
mkdir -p "$R1/subagents" "$R2"
echo '{}' > "$R1/aaaaaaaa-$U.jsonl"
echo '{"x":"larger"}' > "$R2/aaaaaaaa-$U.jsonl"
echo '{}' > "$R1/bbbbbbbb-$U.jsonl"
echo '{}' > "$R1/cccccccc-$U.jsonl"
echo '{}' > "$R1/dddddddd-$U.jsonl"
echo '{}' > "$R1/subagents/eeeeeeee-$U.jsonl"
echo '{}' > "$R1/not-a-uuid.jsonl"
echo '{}' > "$R1/ffffffff-$U.jsonl"
echo '{}' > "$R1/99999999-$U.jsonl"
touch -d '2026-11-04 12:00' "$R1/ffffffff-$U.jsonl" "$R1/99999999-$U.jsonl"
touch -d '2026-11-01 12:00' "$R1/dddddddd-$U.jsonl"
touch -d '2026-11-04 12:00' "$R1/aaaaaaaa-$U.jsonl" "$R2/aaaaaaaa-$U.jsonl" "$R1/bbbbbbbb-$U.jsonl" \
  "$R1/cccccccc-$U.jsonl" "$R1/subagents/eeeeeeee-$U.jsonl" "$R1/not-a-uuid.jsonl"

mkdir -p "$TMP/tmpdir"
export TMPDIR="$TMP/tmpdir"
export STUB_CALLS="$TMP/calls.log" SLICES_ROOT="$TMP/slices" SUMMARIZE_BIN="$TMP/stub.sh"
export JSONL_ROOTS="$TMP/r1:$TMP/r2"
: > "$STUB_CALLS"

out="$(bash "$SCRIPT_DIR/slice-sessions.sh" 2026-11-04 2>"$TMP/stderr.log" | tail -1)"
check "最終行" "slices: written=2 failed=2 candidates=5" "$out"
check "終了コード2も stderr がログに出る" "[ffffffff] boom" "$(grep ffffffff "$TMP/stderr.log")"
check "一時ディレクトリが残らない" "0" "$(find "$TMP/tmpdir" -mindepth 1 | wc -l)"
check "隠しファイル名の md も数える" "yes" "$([ -e "$SLICES_ROOT/2026-11-04/.proj-99999999.md" ] && echo yes || echo no)"
check "古い jsonl は渡らない" "0" "$(grep -c dddddddd "$STUB_CALLS" || true)"
check "subagents は渡らない" "0" "$(grep -c eeeeeeee "$STUB_CALLS" || true)"
check "UUID 形式でないものは渡らない" "0" "$(grep -c not-a-uuid "$STUB_CALLS" || true)"
check "重複は大きいほうだけ" "$R2/aaaaaaaa-$U.jsonl" "$(grep aaaaaaaa "$STUB_CALLS" | cut -d'|' -f1)"
check "aaaaaaaa は1回だけ" "1" "$(grep -c aaaaaaaa "$STUB_CALLS")"
check "引数" "$R1/bbbbbbbb-$U.jsonl|bbbbbbbb-$U|--slice|2026-11-04|--since|2026-11-03T22:10:00+09:00|--until|2026-11-04T22:10:00+09:00" \
  "$(grep bbbbbbbb "$STUB_CALLS")"
check ".failed" "cccccccc
ffffffff" "$(sort "$SLICES_ROOT/2026-11-04/.failed")"

# 2回目: 前回の md と .failed が残らない（スタブが何も書かない状態で再実行）
echo "# stale" > "$SLICES_ROOT/2026-11-04/stale.md"
touch -d '2000-01-01' "$R1/aaaaaaaa-$U.jsonl" "$R2/aaaaaaaa-$U.jsonl" "$R1/cccccccc-$U.jsonl" \
  "$R1/ffffffff-$U.jsonl" "$R1/99999999-$U.jsonl"
out2="$(bash "$SCRIPT_DIR/slice-sessions.sh" 2026-11-04 | tail -1)"
check "再実行の最終行" "slices: written=0 failed=0 candidates=1" "$out2"
check "再実行で md が残らない" "0" "$(find "$SLICES_ROOT/2026-11-04" -name '*.md' | wc -l)"
check "再実行で .failed が残らない" "no" "$([ -e "$SLICES_ROOT/2026-11-04/.failed" ] && echo yes || echo no)"

[ "$fails" -eq 0 ] && { echo "ALL OK"; exit 0; } || { echo "$fails 件失敗"; exit 1; }

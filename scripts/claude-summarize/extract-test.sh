#!/bin/bash
# extract-test.sh - extract.py の時刻範囲指定の動作確認テスト
# 使用方法: bash scripts/claude-summarize/extract-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly EXTRACT="$SCRIPT_DIR/extract.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# make_transcript <path> [entrypoint] — JST 22:09 / 22:10 / 22:11 / 翌日 22:10 の4行を作る
make_transcript() {
  local path="$1" ep="${2:-cli}"
  cat > "$path" <<JSONL
{"type":"user","entrypoint":"$ep","sessionId":"s1","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:09:00.000Z","message":{"content":"LINE-A"}}
{"type":"assistant","sessionId":"s1","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:10:00.000Z","message":{"content":[{"type":"text","text":"LINE-B"}]}}
{"type":"user","sessionId":"s1","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:11:00.000Z","message":{"content":"LINE-C"}}
{"type":"assistant","sessionId":"s1","cwd":"/home/aya/testproj","timestamp":"2026-07-14T13:10:00.000Z","message":{"content":[{"type":"text","text":"LINE-D"}]}}
JSONL
}

# check <name> <actual> <expected> — 文字列一致を検証する
check() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    echo "  expected: $3"
    echo "  actual:   $2"
    fails=$((fails + 1))
  fi
}

# body_markers <output> — 本文中の LINE-X を連結して返す
body_markers() {
  printf '%s\n' "$1" | grep -o 'LINE-[A-Z]' | tr -d '\n' || true
}

T="$TMP/t.jsonl"
make_transcript "$T"

out="$(python3 "$EXTRACT" "$T" --since 2026-07-13T22:10:00+09:00 --until 2026-07-14T22:10:00+09:00)"
check "range: body" "$(body_markers "$out")" "LINE-BLINE-C"
check "range: start" "$(printf '%s\n' "$out" | grep '^start:')" "start: 2026-07-13T13:10:00.000Z"
check "range: end" "$(printf '%s\n' "$out" | grep '^end:')" "end: 2026-07-13T13:11:00.000Z"
check "range: session_start" "$(printf '%s\n' "$out" | grep '^session_start:')" "session_start: 2026-07-13T13:09:00.000Z"

out="$(python3 "$EXTRACT" "$T" --until 2026-07-13T22:10:00+09:00)"
check "until only: body" "$(body_markers "$out")" "LINE-A"

out="$(python3 "$EXTRACT" "$T" --since 2026-07-20T00:00:00Z --until 2026-07-21T00:00:00Z)"
check "empty range: body" "$(body_markers "$out")" ""
check "empty range: lines after header" "$(printf '%s\n' "$out" | sed '1,/^---$/d' | grep -c . || true)" "0"

out="$(python3 "$EXTRACT" "$T")"
check "no args: body" "$(body_markers "$out")" "LINE-ALINE-BLINE-CLINE-D"
check "no args: session_start" "$(printf '%s\n' "$out" | grep '^session_start:')" "session_start: 2026-07-13T13:09:00.000Z"

make_transcript "$T" sdk-cli
out="$(python3 "$EXTRACT" "$T" --since 2026-07-13T22:10:00+09:00 --until 2026-07-14T22:10:00+09:00)"
check "sdk-cli: body empty" "$(body_markers "$out")" ""

if [ "$fails" -eq 0 ]; then
  echo "ALL OK"
else
  echo "$fails FAILED" >&2
  exit 1
fi

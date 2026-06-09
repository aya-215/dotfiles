#!/bin/bash
# summarize-session.sh - SessionEnd hook の入口
#
# stdin で受け取る JSON（transcript_path, session_id, reason）を判定し、
# 対象セッションなら summarize.sh をバックグラウンド起動して即座に exit 0 する。
# 要約の成否に関わらず hook は常に成功扱い（セッション操作を妨げない）。
#
# 使用方法（hook から自動）:
#   echo '{"transcript_path":"...","session_id":"...","reason":"..."}' | summarize-session.sh
set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$HOME/.local/log/claude-summarize.log"
mkdir -p "$(dirname "$LOG_FILE")"

input="$(cat)"
transcript_path="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null || true)"
reason="$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("reason",""))' 2>/dev/null || true)"

# resume は「続きをやるだけ」なので要約しない
[ "$reason" = "resume" ] && exit 0
# 必須情報が欠けていたら何もしない
[ -n "$transcript_path" ] && [ -n "$session_id" ] || exit 0
[ -f "$transcript_path" ] || exit 0
# subagent セッションは除外（情報はメインに集約済み）
case "$transcript_path" in
  */subagents/*) exit 0 ;;
esac

# 要約をバックグラウンドで起動し、即座に制御を返す
{
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] summarize start: $session_id (reason=$reason)"
  bash "$SCRIPT_DIR/summarize.sh" "$transcript_path" "$session_id"
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] summarize done: $session_id"
} >> "$LOG_FILE" 2>&1 &

exit 0

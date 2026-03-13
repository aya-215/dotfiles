#!/bin/bash
# claude-prompt.sh - Claude Codeに定期プロンプトを送信してリセットサイクルを管理
set -euo pipefail

LOG_FILE="$HOME/.local/log/claude-prompt.log"
mkdir -p "$(dirname "$LOG_FILE")"

# cronからの実行時はCLAUDECODE環境変数がセットされてないので問題なし
# 手動テスト時はunsetして実行: unset CLAUDECODE && bash claude-prompt.sh
PROMPT="${1:-おはよう}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Sending: $PROMPT" >> "$LOG_FILE"
/home/aya/.local/bin/claude -p "$PROMPT" >> "$LOG_FILE" 2>&1
echo "[$TIMESTAMP] Done" >> "$LOG_FILE"

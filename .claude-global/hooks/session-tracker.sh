#!/bin/bash
# Claude Code セッション状態トラッカー
# hookから呼び出され、セッション情報をJSONファイルに記録

set -euo pipefail

# デバッグログ
LOG_FILE="$HOME/.claude/session-tracker.log"
exec 2>> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] session-tracker.sh started" >> "$LOG_FILE"

# JSON入力を読み取り（catで全入力を取得）
json_input=$(cat)
echo "[DEBUG] JSON input received: ${#json_input} bytes" >> "$LOG_FILE"
echo "[DEBUG] JSON content: $json_input" >> "$LOG_FILE"

# 基本情報を抽出
session_id=$(echo "$json_input" | jq -r '.session_id')
echo "[DEBUG] session_id: $session_id" >> "$LOG_FILE"

cwd=$(echo "$json_input" | jq -r '.cwd')
echo "[DEBUG] cwd: $cwd" >> "$LOG_FILE"

hook_event=$(echo "$json_input" | jq -r '.hook_event_name')
echo "[DEBUG] hook_event: $hook_event" >> "$LOG_FILE"

# Notificationイベント時の追加情報を抽出
notification_message=$(echo "$json_input" | jq -r '.message // empty')
notification_type=$(echo "$json_input" | jq -r '.notification_type // empty')
echo "[DEBUG] notification_message: $notification_message" >> "$LOG_FILE"
echo "[DEBUG] notification_type: $notification_type" >> "$LOG_FILE"

# WezTerm pane IDを取得
# cwdをfile://プレフィックス付きに変換（WezTermの形式に合わせる）
# ホスト名を小文字に変換
wezterm_cwd="file://$(hostname | tr '[:upper:]' '[:lower:]')${cwd}"
echo "[DEBUG] wezterm_cwd: $wezterm_cwd" >> "$LOG_FILE"

WEZTERM_CLI="/mnt/c/Program Files/WezTerm/wezterm.exe"
pane_id=$("$WEZTERM_CLI" cli list --format json 2>>"$LOG_FILE" | \
  jq -r --arg cwd "$wezterm_cwd" '.[] | select(.cwd == $cwd and .is_active == true) | .pane_id' | \
  head -1)

echo "[DEBUG] pane_id: $pane_id" >> "$LOG_FILE"

# pane_idが取得できない場合は"unknown"
if [ -z "$pane_id" ]; then
  pane_id="unknown"
  echo "[DEBUG] pane_id set to unknown" >> "$LOG_FILE"
fi

# フックイベントに応じて状態を設定
case "$hook_event" in
  "SessionStart")   status="active" ;;
  "Notification")   status="waiting" ;;
  "Stop")           status="stopped" ;;
  *)                status="unknown" ;;
esac

# セッションディレクトリを作成
sessions_dir="$HOME/.claude/sessions"
mkdir -p "$sessions_dir"

# JSONファイルに書き込み
# notification_message/notification_typeがある場合のみ追加
if [ -n "$notification_message" ] && [ "$notification_message" != "null" ]; then
  cat > "${sessions_dir}/${session_id}.json" << EOF
{
  "session_id": "${session_id}",
  "pane_id": "${pane_id}",
  "cwd": "${cwd}",
  "status": "${status}",
  "notification_message": "${notification_message}",
  "notification_type": "${notification_type}",
  "updated": $(date +%s)
}
EOF
else
  cat > "${sessions_dir}/${session_id}.json" << EOF
{
  "session_id": "${session_id}",
  "pane_id": "${pane_id}",
  "cwd": "${cwd}",
  "status": "${status}",
  "updated": $(date +%s)
}
EOF
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session file created: ${session_id}.json (pane_id: ${pane_id}, status: ${status})" >> "$LOG_FILE"
exit 0

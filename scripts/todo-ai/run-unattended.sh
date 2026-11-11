#!/bin/bash
# run-unattended.sh - /todo を claude -p で無人実行する（cron 用）
#
# 使用方法:
#   cron から: 0 7 * * 1-5 mkdir -p /home/aya/.local/log/todo-ai && /home/aya/.dotfiles/scripts/todo-ai/run-unattended.sh >> /home/aya/.local/log/todo-ai/cron.log 2>&1
#   手動確認:  bash run-unattended.sh --dry-run   # 実行するコマンドを表示するだけ
#
# 1回分の出力は ~/.local/log/todo-ai/<YYYY-MM-DD>/run-<HHMMSS>.log に残る。
# /todo 自体のログ（変更案・apply の結果）は同じ日付フォルダに /todo が書く。
set -euo pipefail

export LANG=C.UTF-8
# 無人の /todo が変更案に source user と書いても、apply.py が保護を外さないようにする
export TODO_AI_DENY_USER=1
# cron の PATH には claude（~/.local/bin）も Nix のコマンドも無い
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$PATH"

# 以下の差し替え口はテスト用（既定は本番の値）
readonly CLAUDE_BIN="${CLAUDE_BIN:-claude}"
readonly LOG_ROOT="${TODO_AI_LOG_ROOT:-$HOME/.local/log/todo-ai}"
readonly SKILL_FILE="${TODO_AI_SKILL_FILE:-$HOME/.claude/skills/todo/SKILL.md}"

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

# 承認ダイアログに答える人がいないので auto で動かす。外部への書き込みは /todo の手順に無く、ask ルールの操作は拒否される
cmd=("$CLAUDE_BIN" -p "/todo"
  --permission-mode auto
  --no-session-persistence
  --settings '{"disableAllHooks":true}')

if [ "$dry_run" -eq 1 ]; then
  printf '%q ' "${cmd[@]}"; echo
  exit 0
fi

# ~/.claude/skills はメイン checkout を指すので、そこが main 以外のブランチだと /todo が無い
if [ ! -f "$SKILL_FILE" ]; then
  echo "$(date '+%F %T') /todo のスキルが無い: $SKILL_FILE（~/.dotfiles が main 以外のブランチかもしれない）" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"
exec 9> "$LOG_ROOT/run-unattended.lock"
if ! flock -n 9; then
  echo "$(date '+%F %T') 前回の /todo がまだ実行中のため終了"
  exit 0
fi

day_dir="$LOG_ROOT/$(date +%Y-%m-%d)"
mkdir -p "$day_dir"
log="$day_dir/run-$(date +%H%M%S).log"

echo "$(date '+%F %T') 開始 → $log"
rc=0
(cd "$HOME" && "${cmd[@]}") > "$log" 2>&1 || rc=$?
echo "$(date '+%F %T') 終了 rc=$rc"
exit "$rc"

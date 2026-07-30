#!/usr/bin/env bash
# tmux-resurrect の復元コマンド (@resurrect-processes から呼ばれる)。
# 実行中のペイン座標に対応する Claude Code の session_id を引き当て、
# `claude -r <session_id>` でその会話を復元する。
#
# これが必要な理由:
#   `claude -c` は「そのディレクトリの直近の会話」を開くため、同じ
#   ディレクトリで複数ペインを開いていると全ペインが同一会話になる。
#   ペインごとに別の会話を復元するには session_id を指定する必要がある。
#   (`claude --session-id <既存UUID>` は "already in use" で再開不可なので
#    復元には使えない。再開は `-r` のみ)
#
# resurrect は send-keys でこのスクリプトをペイン内で実行するため、
# 実行時には TMUX_PANE と cwd が復元済みの正しい値になっている。
#
# fail-soft: 対応が見つからない/壊れている場合は必ず `claude -c` に
# フォールバックする。ペインが空のまま残ることはない。

set -uo pipefail

MAP_FILE="${CLAUDE_PANE_SESSION_MAP:-$HOME/.local/share/claude-pane-session/map.tsv}"

fallback() {
  exec claude -c
}

[[ -n "${TMUX_PANE:-}" ]] || fallback
[[ -r "$MAP_FILE" ]] || fallback
command -v tmux >/dev/null 2>&1 || fallback

coords=$(tmux display-message -p -t "$TMUX_PANE" \
  '#{session_name}	#{window_index}	#{pane_index}' 2>/dev/null) || fallback
[[ -n "$coords" ]] || fallback

# 同一座標の記録のうち最後の行(=最新)を採用する
sid=$(awk -F'\t' -v c="$coords" '
  { key = $1 "\t" $2 "\t" $3 }
  key == c { last = $4 }
  END { if (last != "") print last }
' "$MAP_FILE" 2>/dev/null) || fallback

# UUID形式でなければ壊れた記録として扱う
[[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fallback

# -r が失敗した場合(会話が削除された等)も -c で起動できるようにする。
# exec せず、失敗時にフォールバックできる形にする。
claude -r "$sid" || exec claude -c

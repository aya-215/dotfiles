#!/usr/bin/env bash
# Claude Code の SessionStart hook。
# tmuxペイン座標 → session_id の対応を追記し、tmux復元時に
# restore.sh が「そのペインで開いていた会話」を復元できるようにする。
#
# なぜペインID(%0等)ではなく座標(session名/window/pane_index)なのか:
#   tmux-resurrect が保存するのは session名・window_index・pane_index の
#   3つ組であり、ペインID(%0)は保存されない。復元後は別のペインIDが
#   割り当てられるため、ペインIDでは対応が取れない。
#
# 追記のみ(append-only)。同一座標で複数行になった場合は restore.sh 側で
# 最後の行を採用する(/clear や resume ごとに新しい session_id が発行される)。

set -uo pipefail

MAP_FILE="${CLAUDE_PANE_SESSION_MAP:-$HOME/.local/share/claude-pane-session/map.tsv}"

# hook の入力(JSON)は stdin から渡される
input=$(cat)

# tmux外で起動した場合は記録対象外
[[ -n "${TMUX_PANE:-}" ]] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
[[ -n "$session_id" ]] || exit 0

# TMUX_PANE から resurrect が保存するのと同じ座標を解決する
coords=$(tmux display-message -p -t "$TMUX_PANE" \
  '#{session_name}	#{window_index}	#{pane_index}' 2>/dev/null) || exit 0
[[ -n "$coords" ]] || exit 0

mkdir -p "$(dirname "$MAP_FILE")" || exit 0
printf '%s\t%s\n' "$coords" "$session_id" >> "$MAP_FILE"

# 際限なく増えないよう、行数が増えたら末尾のみ残す
# (末尾が最新 = latest-wins の探索順序を壊さない)
if [[ $(wc -l < "$MAP_FILE" 2>/dev/null || echo 0) -gt 2000 ]]; then
  tail -n 1000 "$MAP_FILE" > "$MAP_FILE.tmp" 2>/dev/null &&
    mv "$MAP_FILE.tmp" "$MAP_FILE"
fi

exit 0

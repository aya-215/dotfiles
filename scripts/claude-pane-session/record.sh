#!/usr/bin/env bash
# Claude Code の SessionStart hook。
# tmuxペイン座標 → session_id の対応を追記し、tmux復元時に
# restore.sh が「そのペインで開いていた会話」を復元できるようにする。
#
# 記録する識別子: session名 / window_index / pane_index / pane_current_path
#
# ペインID(%0等)を使わない理由:
#   tmux-resurrect が保存するのは座標(session名・window_index・pane_index)と
#   パスであり、ペインIDは保存されない。復元後は別のペインIDが割り当てられる。
#
# pane_index だけでなくパスも記録する理由:
#   pane_index は下位indexのペインを閉じると繰り上がってズレるため、座標だけを
#   キーにすると復元時に別ペインの会話を引いてしまう(実測で再現済み)。
#   restore.sh はパスを主キーにし、同一パスのペインが複数ある場合のみ
#   pane_index 順の並び(rank)で区別する。これにより index がズレても
#   パスが変わらなければ正しい会話に復元できる。
#
# パスは hook stdin の .cwd ではなく tmux の pane_current_path を使う。
# resurrect が保存・復元するのは pane_current_path であり、restore.sh が
# 実行時に参照できるのもそちらのため。
#
# 追記のみ(append-only)。同一(座標,パス)で複数行になった場合は restore.sh 側で
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

# TMUX_PANE から resurrect が保存するのと同じ座標・パスを解決する
# 形式: session名 \t window_index \t pane_index \t pane_current_path
coords=$(tmux display-message -p -t "$TMUX_PANE" \
  '#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}' 2>/dev/null) || exit 0
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

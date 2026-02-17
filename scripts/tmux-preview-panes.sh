#!/usr/bin/env bash
# tmux-preview-panes.sh - セッションの全paneを横並べでプレビュー表示
# Usage: tmux-preview-panes.sh <session_name> [preview_width]
set -euo pipefail

session="${1:?Usage: tmux-preview-panes.sh <session_name> [preview_width]}"
preview_width="${2:-${FZF_PREVIEW_COLUMNS:-80}}"

# セッションのアクティブウィンドウの全pane情報を取得
panes=($(tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null))
num_panes=${#panes[@]}

if [[ $num_panes -eq 0 ]]; then
  echo "No panes found"
  exit 0
fi

# 1paneの場合はそのままキャプチャ
if [[ $num_panes -eq 1 ]]; then
  tmux capture-pane -pt "$session" -e -p
  exit 0
fi

# 複数paneの場合: 横並べ表示
# 区切り線分を引いた幅を各paneに配分
local_separator="│"
pane_width=$(( (preview_width - num_panes + 1) / num_panes ))

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

for p in "${panes[@]}"; do
  tmux capture-pane -pt "$session":"${panes[0]/%*/}"."$p" -p | \
    cut -c1-"$pane_width" | \
    awk -v w="$pane_width" '{ printf "%-*s\n", w, $0 }' > "$tmpdir/pane_$p"
done

paste -d"$local_separator" "$tmpdir"/pane_*

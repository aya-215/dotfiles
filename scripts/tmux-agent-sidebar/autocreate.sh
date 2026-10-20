#!/usr/bin/env bash
# tmux-agent-sidebar の自動作成と、tmux-resurrect 復元時のサイドバー復元。
#
#   autocreate.sh window <window_id>   after-new-window / session-created から呼ぶ
#   autocreate.sh pre-restore          @resurrect-hook-pre-restore-all
#   autocreate.sh pre-processes        @resurrect-hook-pre-restore-pane-processes
#   autocreate.sh post-restore         @resurrect-hook-post-restore-all
#
# プラグイン標準の @sidebar_auto_create を使わない理由:
#   resurrect は2枚目以降のウィンドウを new-window で作るため after-new-window が
#   復元中に発火し、保存レイアウトに無いペインが割り込んで復元が崩れる。
#   また標準は session-created に掛からず、新規セッションの1枚目に出ない。
#
# 復元の流れ:
#   保存されたサイドバーは resurrect では素のシェル（跡地）として戻る。
#   pre-processes でその跡地を respawn-pane でサイドバーに入れ替える。
#   kill-pane しないのは、resurrect がこの後 pane_index 指定でプロセスを
#   戻すため、番号がずれると別ペインに claude を送ってしまうから。
#   cwd を $HOME にするのは、claude-pane-session/restore.sh が「同じパスの
#   ペイン内での順位」で会話を引き当てるため、サイドバーが Claude と同じ
#   パスにいると順位がずれて claude -c に落ちるから。

set -euo pipefail

RESTORING_OPT=@sidebar_restoring
# 復元が途中で落ちてフラグが残っても、自動作成が永久に止まらないようにする
RESTORING_TTL=120

# プラグインが tmux に登録したサイドバー本体のパスを返す
sidebar_bin() {
  tmux show -gv @agent_sidebar_bin 2>/dev/null || true
}

# resurrect の復元中なら真（フラグが TTL 内のときだけ）
is_restoring() {
  local since now
  since=$(tmux show -gv "$RESTORING_OPT" 2>/dev/null) || return 1
  [[ "$since" =~ ^[0-9]+$ ]] || return 1
  now=$(date +%s)
  (( now - since < RESTORING_TTL ))
}

# 指定ウィンドウにサイドバーが無ければ作る。失敗しても呼び出し元を止めない
create_in_window() {
  local bin
  bin=$(sidebar_bin)
  [[ -n "$bin" && -x "$bin" ]] || return 0
  "$bin" toggle --create-only "$1" "$HOME" || true
}

# 復元元の保存ファイルのパスを返す。resurrect の helpers.sh と同じ規則で決める
last_save_file() {
  local dir
  dir=$(tmux show -gv @resurrect-dir 2>/dev/null || true)
  if [[ -z "$dir" ]]; then
    if [[ -d "$HOME/.tmux/resurrect" ]]; then
      dir="$HOME/.tmux/resurrect"
    else
      dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    fi
  fi
  dir="${dir/#\~/$HOME}"
  printf '%s/last' "$dir"
}

# 保存時にサイドバーだったペインの跡地を、その場でサイドバーに入れ替える
respawn_saved_sidebars() {
  local bin save since now target pid role age
  bin=$(sidebar_bin)
  [[ -n "$bin" && -x "$bin" ]] || return 0
  save=$(last_save_file)
  [[ -r "$save" ]] || return 0
  since=$(tmux show -gv "$RESTORING_OPT" 2>/dev/null || true)
  [[ "$since" =~ ^[0-9]+$ ]] || return 0
  now=$(date +%s)

  # pane 行: pane session window active flags pane_index title :dir active command :full
  awk -F'\t' '$1 == "pane" && $10 == "tmux-agent-sidebar" { print $2 ":" $3 "." $6 }' "$save" |
    while IFS= read -r target; do
      IFS=$'\t' read -r pid role < <(tmux display -p -t "$target" \
        '#{pane_pid}	#{@pane_role}' 2>/dev/null) || continue
      [[ "$role" == sidebar ]] && continue
      # 復元開始より前から動いているペインは既存セッションのもの（claude 等）なので触らない。
      # pane_current_command で判定しないのは、作成直後はシェルの exec 前で名前が定まらないため
      age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ') || continue
      [[ "$age" =~ ^[0-9]+$ ]] || continue
      (( now - age >= since - 1 )) || continue
      tmux respawn-pane -k -t "$target" -c "$HOME" "$bin" &&
        tmux set -p -t "$target" @pane_role sidebar || true
    done
}

case "${1:-}" in
  window)
    [[ -n "${2:-}" ]] || exit 0
    is_restoring && exit 0
    create_in_window "$2"
    ;;
  pre-restore)
    tmux set -g "$RESTORING_OPT" "$(date +%s)"
    ;;
  pre-processes)
    respawn_saved_sidebars
    ;;
  post-restore)
    tmux list-windows -a -F '#{window_id}' 2>/dev/null |
      while IFS= read -r wid; do create_in_window "$wid"; done || true
    tmux set -gu "$RESTORING_OPT"
    ;;
esac
exit 0

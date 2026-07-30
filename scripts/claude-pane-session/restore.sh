#!/usr/bin/env bash
# tmux-resurrect の復元コマンド (@resurrect-processes から呼ばれる)。
# 実行中のペインに対応する Claude Code の session_id を引き当て、
# `claude -r <session_id>` でその会話を復元する。
#
# これが必要な理由:
#   `claude -c` は「そのディレクトリの直近の会話」を開くため、同じ
#   ディレクトリで複数ペインを開いていると全ペインが同一会話になる。
#   ペインごとに別の会話を復元するには session_id を指定する必要がある。
#   (`claude --session-id <既存UUID>` は "already in use" で再開不可なので
#    復元には使えない。再開は `-r` のみ)
#
# 引き当ての方針: パスを主キーにし、同一パス内の順位(rank)で区別する
#   1. 自分のパスと、同一ウィンドウ内で同じパスを持つペインのうち
#      pane_index 順で自分が何番目か(rank)を求める
#   2. マップから同じ (session名, window_index, パス) の記録を集め、
#      pane_index ごとに最新の session_id へ畳んでから pane_index 順に並べる
#   3. 同じ rank の記録を採用する
#
#   pane_index を直接キーにしない理由: 下位indexのペインを閉じると
#   pane_index が繰り上がってズレるため、別ペインの会話を引いてしまう。
#   パス主キー + 同一パス内 rank なら、index がズレてもパス構成が
#   変わらなければ正しい会話に復元できる。
#
# resurrect は send-keys でこのスクリプトをペイン内で実行するため、
# 実行時には TMUX_PANE と cwd が復元済みの正しい値になっている。
# 各ペインで独立に実行されるので、判定は自ペインから見える情報のみで行う。
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

# 自ペインの座標とパスを取得
self=$(tmux display-message -p -t "$TMUX_PANE" \
  '#{session_name}	#{window_index}	#{pane_index}	#{pane_current_path}' 2>/dev/null) || fallback
[[ -n "$self" ]] || fallback

IFS=$'\t' read -r s_name w_index p_index p_path <<< "$self"
[[ -n "$s_name" && -n "$w_index" && -n "$p_index" && -n "$p_path" ]] || fallback

# 同一ウィンドウ内で同じパスを持つペインのうち、自分が pane_index 順で何番目か
rank=$(tmux list-panes -t "$s_name:$w_index" \
  -F '#{pane_index}	#{pane_current_path}' 2>/dev/null |
  awk -F'\t' -v path="$p_path" -v me="$p_index" '
    $2 == path { idx[n++] = $1 + 0 }
    END {
      # pane_index の昇順に並べて自分の位置を返す
      for (i = 0; i < n; i++)
        for (j = i + 1; j < n; j++)
          if (idx[j] < idx[i]) { t = idx[i]; idx[i] = idx[j]; idx[j] = t }
      for (i = 0; i < n; i++) if (idx[i] == me + 0) { print i; exit }
    }') || fallback
[[ -n "$rank" ]] || fallback

# マップから同じ (session名, window_index, パス) の記録を集める。
# pane_index ごとに最新の session_id へ畳んでから pane_index 順に並べ、
# rank 番目を取る。畳む前に並べると、追記された世代違いの記録
# (同じ pane_index の複数行) が別ペインの枠を埋めてしまう。
sid=$(awk -F'\t' -v s="$s_name" -v w="$w_index" -v path="$p_path" -v want="$rank" '
  # 終了済み(tombstone)を集める。
  # 6列 END は座標つき: その枠の記録だけを無効化する。
  #   同じ会話を複数ペインで開いていた場合(claude -c 直後など)、片方が
  #   /resume で離脱しただけで両方の記録が死ぬのを防ぐ。
  # 2列 END は座標不明(tmux外での終了。旧形式も同じ扱い): 全枠に効かせる。
  $1 == "END" && NF >= 6 {
    if ($2 == s && $3 == w && $5 == path) deadslot[($4 + 0) SUBSEP $6] = 1
    next
  }
  $1 == "END" && NF >= 2 { dead[$2] = 1; next }
  NF >= 5 && $1 == s && $2 == w && $4 == path {
    pi = $3 + 0
    latest[pi] = $5          # 同じ pane_index は後の行(=最新)で上書き
    # 先行する無効化を打ち消す(復活)。END の後に同じ記録が来るのは
    # 会話を閉じて -c / -r で再開した場合であり、後の行が最新の事実。
    delete deadslot[pi SUBSEP $5]
    # 先行する END を打ち消す(復活)。同じ session_id が END された後に
    # 再度記録されることがあるため(終了→resume 等)、tombstone を永久扱いに
    # すると生きている会話を抑止してしまう。マップは追記のみなので
    # ファイル順 = 時系列であり、後に来た記録行が最新の事実になる。
    delete dead[$5]
  }
  END {
    # tombstone された session_id を持つ枠を落として詰める。
    # END行はファイル後方に来るため、ここで初めて全滅判定ができる。
    # 生存している枠だけを latest[] から集める。
    # 出現順を記録する配列を持たない理由: evict で枠を delete した後に
    # 同じ枠が再登録されると、出現順の配列に同じ枠が二重に入り、
    # 別々の rank が同じ枠を指してしまう(複数ペインが同一会話を引く)。
    # latest[] のキーは常に一意なので、ここから集めれば重複しない。
    cnt = 0
    for (pi in latest)
      if (latest[pi] != "" && !(latest[pi] in dead) &&
          !((pi + 0) SUBSEP latest[pi] in deadslot)) order[cnt++] = pi + 0
    for (i = 0; i < cnt; i++)
      for (j = i + 1; j < cnt; j++)
        if (order[j] < order[i]) { t = order[i]; order[i] = order[j]; order[j] = t }
    if (want + 0 < cnt) print latest[order[want + 0]]
  }' "$MAP_FILE" 2>/dev/null) || fallback

# UUID形式でなければ壊れた記録として扱う
[[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fallback

# 会話が実在するか先に確認し、claude は必ず exec で起動する。
#
# exec が必須な理由: exec しないと このスクリプトがプロセスツリーに残り、
# resurrect が次回の保存時にフルコマンドを
#   bash .../restore.sh
# として記録してしまう。restore.sh は ^claude にマッチしないため、
# 2回目以降の復元で claude が一切起動しなくなる(実測で再現)。
#
# そのため `claude -r || claude -c` というフォールバックは使えない。
# 代わりに会話ファイルの存在を事前に確認して分岐する。
# 履歴の場所は ~/.claude/projects/<パスの記号を-に置換>/<session_id>.jsonl
proj_dir="$HOME/.claude/projects/$(printf '%s' "$p_path" | sed 's/[^a-zA-Z0-9]/-/g')"
if [[ -f "$proj_dir/$sid.jsonl" ]]; then
  exec claude -r "$sid"
fi
fallback

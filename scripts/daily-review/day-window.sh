#!/bin/bash
# day-window.sh - 日報の「1日」の区切りを計算する（source して使う）
#
# 区切りは JST の「前日 DAY_CUTOFF（含む）〜 当日 DAY_CUTOFF（含まない）」。
# 送信した時刻ではなく対象日から決める。

readonly DAY_CUTOFF="22:10:00"

# day_window <YYYY-MM-DD> — 標準出力に "<since>\t<until>" を出す
day_window() {
  local d="$1" prev
  prev="$(date -d "$d -1 day" +%F)" || return 1
  printf '%sT%s+09:00\t%sT%s+09:00\n' "$prev" "$DAY_CUTOFF" "$d" "$DAY_CUTOFF"
}

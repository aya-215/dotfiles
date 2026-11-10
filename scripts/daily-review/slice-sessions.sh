#!/bin/bash
# slice-sessions.sh - 指定日の区切りで、各セッションの切り出し要約を作る
#
# 使用方法: slice-sessions.sh <YYYY-MM-DD>
# 環境変数: JSONL_ROOTS（コロン区切り）/ SLICES_ROOT / SUMMARIZE_BIN / SLICE_JOBS
# 切り出しが失敗しても送信側を止めないため、終了コードは常に 0。
# 最後に "slices: written=N failed=M candidates=K" を標準出力に出す。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=day-window.sh
source "$SCRIPT_DIR/day-window.sh"

SLICES_ROOT="${SLICES_ROOT:-$HOME/.nb/claude/daily-slices}"
SUMMARIZE_BIN="${SUMMARIZE_BIN:-$SCRIPT_DIR/../claude-summarize/summarize.sh}"
SLICE_JOBS="${SLICE_JOBS:-4}"
export SLICES_ROOT

# default_roots — JSONL_ROOTS 未指定時の探索先（コロン区切り）
default_roots() {
  local r="$HOME/.claude/projects"
  [ -d "$HOME/.local/share/daily-slice-replay/jsonl-backup" ] \
    && r="$r:$HOME/.local/share/daily-slice-replay/jsonl-backup"
  printf '%s' "$r"
}

# list_candidates <since> — "<sid>\t<size>\t<path>" を出す（sid ごとに最大サイズの1本）
list_candidates() {
  local since="$1" root IFS_SAVE="$IFS" f base
  local -a roots
  IFS=: read -r -a roots <<< "${JSONL_ROOTS:-$(default_roots)}"
  IFS="$IFS_SAVE"
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    find "$root" -type f -name '*.jsonl' ! -path '*/subagents/*' -newermt "$since" -print0 2>/dev/null
  done | while IFS= read -r -d '' f; do
    base="$(basename "$f" .jsonl)"
    [[ "$base" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || continue
    printf '%s\t%s\t%s\n' "$base" "$(stat -c %s "$f")" "$f"
  done | sort -t$'\t' -k1,1 -k2,2nr | awk -F'\t' '!seen[$1]++'
}

# main <YYYY-MM-DD>
main() {
  local date="${1:-}"
  if ! [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "usage: $0 <YYYY-MM-DD>" >&2
    return 0
  fi
  local window since until out_dir work cands
  window="$(day_window "$date")"
  since="${window%%$'\t'*}"
  until="${window##*$'\t'}"
  out_dir="$SLICES_ROOT/$date"
  mkdir -p "$out_dir"
  # 再実行で前回の結果が残らないようにする
  find "$out_dir" -maxdepth 1 \( -name '*.md' -o -name '.failed' \) -delete

  work="$(mktemp -d)"
  trap 'rm -rf "${work:-}"' EXIT
  cands="$work/cands.tsv"
  list_candidates "$since" > "$cands" || true

  export SUMMARIZE_BIN date since until work
  # 1件ずつ終了コードを $work/rc.<sid> に書く（並列でも混ざらない）
  cut -f1,3 "$cands" | tr '\n' '\0' | xargs -0 -r -n1 -P "$SLICE_JOBS" bash -c '
    sid="${1%%$'"'"'\t'"'"'*}"; path="${1#*$'"'"'\t'"'"'}"
    rc=0
    "$SUMMARIZE_BIN" "$path" "$sid" --slice "$date" --since "$since" --until "$until" \
      >/dev/null 2>"$work/err.$sid" || rc=$?
    echo "$rc" > "$work/rc.$sid"
  ' _

  local rcfile sid rc failed=0 candidates written
  candidates="$(wc -l < "$cands")"
  for rcfile in "$work"/rc.*; do
    [ -e "$rcfile" ] || continue
    sid="${rcfile##*/rc.}"
    rc="$(cat "$rcfile")"
    if [ "$rc" = "3" ]; then
      echo "${sid:0:8}" >> "$out_dir/.failed"
      failed=$((failed + 1))
    fi
  done
  written="$(find "$out_dir" -maxdepth 1 -name '*.md' | wc -l)"
  echo "slices: written=$written failed=$failed candidates=$candidates"
}

main "$@" || true
exit 0

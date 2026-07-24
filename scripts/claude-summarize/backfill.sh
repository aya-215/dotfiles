#!/bin/bash
# backfill.sh - SessionEnd hook 非発火で取りこぼしたセッションを拾って要約する
#
# 現存 jsonl（subagents 除く）のうち要約 md が未生成のものを検出し、
# 既存 summarize.sh に投入する。薄いセッション判定・要約失敗は summarize.sh の
# 既存ガードに一任する（責務分離: backfill は決定的な対象選定のみ担う）。
# cron から日次で呼ぶ。同一 sid の md がある限り再投入しないため冪等。
#
# 使用方法:
#   ./backfill.sh            通常実行（未生成を summarize.sh に投入）
#   ./backfill.sh --dry-run  対象 jsonl パスを stdout に出すだけ（summarize は呼ばない）
# 環境変数（テスト用に上書き可能）:
#   PROJECTS_ROOT / SESSIONS_ROOT / SUMMARIZE_BIN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/.claude/projects}"
SESSIONS_ROOT="${SESSIONS_ROOT:-$HOME/.nb/claude/sessions}"
SUMMARIZE_BIN="${SUMMARIZE_BIN:-$SCRIPT_DIR/summarize.sh}"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

# PROJECTS_ROOT が存在しないと find が無音で 0 件を返し、cron で気付けない no-op になる。
# ここで可視化する（本プロジェクトの発端バグと同じ轍を踏まないため）。
if [ ! -d "$PROJECTS_ROOT" ]; then
  echo "[警告] PROJECTS_ROOT が存在しません: $PROJECTS_ROOT" >&2
  exit 0
fi

# has_summary <sid8> — その sid8 の要約 md が既に存在するか
has_summary() {
  local sid8="$1"
  find "$SESSIONS_ROOT" -type f -name "*-${sid8}.md" -print -quit 2>/dev/null | grep -q .
}

# run_backfill — 対象走査の本体（現存 jsonl(subagents除外) を走査し未生成のものを処理する）
run_backfill() {
  find "$PROJECTS_ROOT" -type f -name '*.jsonl' ! -path '*/subagents/*' 2>/dev/null | while read -r jsonl; do
    fname="$(basename "$jsonl" .jsonl)"
    # ファイル名がフル session-id（UUID）でないものはスキップ
    case "$fname" in
      [0-9a-f]*-*-*-*-*) : ;;
      *) continue ;;
    esac
    sid8="${fname:0:8}"
    has_summary "$sid8" && continue
    if [ "$dry_run" -eq 1 ]; then
      printf '%s\n' "$jsonl"
    else
      bash "$SUMMARIZE_BIN" "$jsonl" "$fname" || true
    fi
  done
}

if [ "$dry_run" -eq 1 ]; then
  run_backfill
else
  # cron 重複・長引き対策: 多重起動を flock で防ぐ（後発は即終了）
  LOCK_FILE="${TMPDIR:-/tmp}/claude-summarize-backfill.lock"
  readonly LOCK_FILE
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] 既に実行中のためスキップ"
    exit 0
  fi
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] backfill 開始"
  run_backfill
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] backfill 完了"
fi

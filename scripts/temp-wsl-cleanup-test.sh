#!/bin/bash
# temp-wsl-cleanup-test.sh - temp-wsl-cleanup.sh の動作確認テスト
# 使用方法: bash scripts/temp-wsl-cleanup-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
fails=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ctime は過去に戻せないため、「現在時刻」を30日先にずらして古さを作る
now_epoch=$(($(date +%s) + 30 * 86400))
fresh_date="@$((now_epoch - 1 * 86400))"

# setup_fixture: 判定パターンごとの項目を作る
setup_fixture() {
  rm -rf "$work/temp" "$work/log"
  mkdir -p "$work/temp"
  local t="$work/temp"
  touch "$t/old-file.png"
  mkdir -p "$t/old-dir/sub" && touch "$t/old-dir/sub/a.txt"
  touch -d "$fresh_date" "$t/fresh-file.html"
  mkdir -p "$t/mixed-dir/sub" && touch "$t/mixed-dir/old.txt"
  touch -d "$fresh_date" "$t/mixed-dir/sub/new.txt"
  touch "$t/README.txt"
  touch "$t/old name with space.txt"
}

# run_cleanup [args...]: テスト用の環境変数で本体を実行する
run_cleanup() {
  TEMP_WSL_DIR="$work/temp" \
    TEMP_WSL_CLEANUP_LOG="$work/log/cleanup.log" \
    TEMP_WSL_NOW_EPOCH="$now_epoch" \
    bash "$SCRIPT_DIR/temp-wsl-cleanup.sh" "$@"
}

# check <説明> <条件コマンド...>: 条件が真なら ok
check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "ok: $desc"
  else
    echo "NG: $desc"
    fails=$((fails + 1))
  fi
}

# lacks <needle> <haystack>: 文字列に needle が含まれなければ真
lacks() {
  [[ "$2" != *"$1"* ]]
}

# cleanup_ok_without_dir: 対象フォルダが存在しなくても正常終了すれば真
cleanup_ok_without_dir() {
  TEMP_WSL_DIR="$work/nonexistent" TEMP_WSL_CLEANUP_LOG="$work/log/x.log" \
    bash "$SCRIPT_DIR/temp-wsl-cleanup.sh" >/dev/null
}

# --- dry-run は何も消さず、消す予定だけ出す ---
setup_fixture
out="$(run_cleanup --dry-run)"
check "dry-run: 古いファイルは残る" test -e "$work/temp/old-file.png"
check "dry-run: 古いファイルを予定に出す" grep -q "old-file.png" <<<"$out"
check "dry-run: 新しいファイルは予定に出さない" lacks "fresh-file.html" "$out"
check "dry-run: ログを書かない" test ! -e "$work/log/cleanup.log"

# --- 本番実行 ---
setup_fixture
run_cleanup >/dev/null
check "古いファイルを消す" test ! -e "$work/temp/old-file.png"
check "中身ごと古いフォルダを消す" test ! -e "$work/temp/old-dir"
check "空白を含む名前も消す" test ! -e "$work/temp/old name with space.txt"
check "新しいファイルは残す" test -e "$work/temp/fresh-file.html"
check "中に新しいファイルがあるフォルダは残す" test -e "$work/temp/mixed-dir/old.txt"
check "README.txt は古くても残す" test -e "$work/temp/README.txt"
check "ログに消した名前を残す" grep -q "old-dir" "$work/log/cleanup.log"
check "ログに残した名前は出さない" lacks "fresh-file.html" "$(cat "$work/log/cleanup.log")"

# --- 対象フォルダが無ければ何もせず正常終了（D: 未マウント時） ---
check "対象フォルダが無くても exit 0" cleanup_ok_without_dir

if ((fails == 0)); then
  echo "ALL OK"
else
  echo "FAILED: $fails"
  exit 1
fi

#!/usr/bin/env bash
# temp-wsl-cleanup.sh - Windows への受け渡し用フォルダ D:\temp_wsl から古い項目を削除する
# 使用方法: temp-wsl-cleanup.sh [--dry-run]
#   直下の項目ごとに、配下で最も新しい mtime/ctime が保持日数より古ければ削除する。
#   直下の README.txt は削除しない。cron で毎日実行する（README.md 参照）。
# 環境変数（テスト用の差し替え）:
#   TEMP_WSL_DIR               対象フォルダ（既定 /mnt/d/temp_wsl）
#   TEMP_WSL_RETENTION_DAYS    保持日数（既定 14）
#   TEMP_WSL_CLEANUP_LOG       削除ログ（既定 ~/.local/log/temp-wsl-cleanup.log）
#   TEMP_WSL_NOW_EPOCH         現在時刻の epoch 秒（既定 date +%s）

set -euo pipefail

TEMP_WSL_DIR="${TEMP_WSL_DIR:-/mnt/d/temp_wsl}"
TEMP_WSL_RETENTION_DAYS="${TEMP_WSL_RETENTION_DAYS:-14}"
TEMP_WSL_CLEANUP_LOG="${TEMP_WSL_CLEANUP_LOG:-$HOME/.local/log/temp-wsl-cleanup.log}"
TEMP_WSL_NOW_EPOCH="${TEMP_WSL_NOW_EPOCH:-$(date +%s)}"
readonly KEEP_NAME="README.txt"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
fi

# newest_epoch <path>: path 自身と配下すべての mtime/ctime のうち最も新しい epoch 秒を出す
# Windows でコピーした古いファイルは mtime が元のまま残り ctime だけが置いた日時になるため両方を見る
newest_epoch() {
  local path="$1"
  find "$path" -printf '%T@\n%C@\n' 2>/dev/null | cut -d. -f1 | sort -n | tail -1
}

# log_line <message>: 削除ログに日時付きで1行追記する
log_line() {
  local message="$1"
  mkdir -p "$(dirname "$TEMP_WSL_CLEANUP_LOG")"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >>"$TEMP_WSL_CLEANUP_LOG"
}

main() {
  if [[ ! -d "$TEMP_WSL_DIR" ]]; then
    echo "対象フォルダが無いためスキップ: $TEMP_WSL_DIR"
    return 0
  fi

  local cutoff=$((TEMP_WSL_NOW_EPOCH - TEMP_WSL_RETENTION_DAYS * 86400))
  local path name newest last_date count=0

  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    [[ "$name" == "$KEEP_NAME" ]] && continue
    newest="$(newest_epoch "$path")"
    [[ -z "$newest" ]] && continue
    ((newest < cutoff)) || continue

    last_date="$(date -d "@$newest" '+%Y-%m-%d')"
    count=$((count + 1))
    if [[ "$dry_run" == true ]]; then
      echo "[dry-run] 削除予定: $name (最終 $last_date)"
    else
      rm -rf -- "$path"
      log_line "deleted: $name (last $last_date)"
      echo "削除: $name (最終 $last_date)"
    fi
  done < <(find "$TEMP_WSL_DIR" -mindepth 1 -maxdepth 1 -print0)

  echo "対象 ${count} 件（保持 ${TEMP_WSL_RETENTION_DAYS} 日、dry-run=${dry_run}）"
}

main

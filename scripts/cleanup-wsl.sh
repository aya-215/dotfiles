#!/usr/bin/env bash
# WSL定期クリーンアップスクリプト
# キャッシュ・ログ・Nix storeの不要データを削除する

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# --- ユーティリティ ---

# 人間が読みやすいサイズ表示
human_size() {
  local bytes="$1"
  if ((bytes >= 1073741824)); then
    printf "%.1fG" "$(echo "scale=1; $bytes / 1073741824" | bc)"
  elif ((bytes >= 1048576)); then
    printf "%.1fM" "$(echo "scale=1; $bytes / 1048576" | bc)"
  elif ((bytes >= 1024)); then
    printf "%.1fK" "$(echo "scale=1; $bytes / 1024" | bc)"
  else
    printf "%dB" "$bytes"
  fi
}

# ディレクトリのサイズをバイトで取得（存在しなければ0）
dir_size_bytes() {
  local path="$1"
  if [[ -d "$path" ]]; then
    du -sb "$path" 2>/dev/null | awk '{print $1}'
  else
    echo 0
  fi
}

# ヘッダー表示
header() {
  printf "\n\033[1;36m=== %s ===\033[0m\n" "$1"
}

# 結果行表示
result() {
  local label="$1" size="$2"
  if [[ "$size" == "0" || "$size" == "0B" ]]; then
    printf "  %-25s \033[2mスキップ（なし）\033[0m\n" "$label"
  else
    printf "  %-25s \033[1;33m%s\033[0m\n" "$label" "$size"
  fi
}

# --- メイン ---

total_freed=0

echo ""
if $DRY_RUN; then
  printf "\033[1;33m[DRY RUN] 削除対象のサイズを表示します（実際の削除は行いません）\033[0m\n"
else
  printf "\033[1;32m[実行] クリーンアップを開始します\033[0m\n"
fi

# 実行前のディスク使用量
disk_before=$(df / --output=used -B1 | tail -1 | tr -d ' ')

header "パッケージキャッシュ"

# uv cache
if command -v uv &>/dev/null; then
  uv_size=$(dir_size_bytes "${HOME}/.cache/uv")
  if $DRY_RUN; then
    result "uv cache" "$(human_size "$uv_size")"
  else
    uv cache clean --force 2>/dev/null || true
    result "uv cache" "$(human_size "$uv_size")"
  fi
  total_freed=$((total_freed + uv_size))
else
  result "uv cache" "コマンドなし"
fi

# npm cache
if command -v npm &>/dev/null; then
  npm_size=$(dir_size_bytes "${HOME}/.npm/_cacache")
  if $DRY_RUN; then
    result "npm cache" "$(human_size "$npm_size")"
  else
    npm cache clean --force 2>/dev/null || true
    result "npm cache" "$(human_size "$npm_size")"
  fi
  total_freed=$((total_freed + npm_size))
else
  result "npm cache" "コマンドなし"
fi

# pip cache
if command -v pip &>/dev/null; then
  pip_size=$(dir_size_bytes "${HOME}/.cache/pip")
  if $DRY_RUN; then
    result "pip cache" "$(human_size "$pip_size")"
  else
    pip cache purge 2>/dev/null || true
    result "pip cache" "$(human_size "$pip_size")"
  fi
  total_freed=$((total_freed + pip_size))
else
  result "pip cache" "コマンドなし"
fi

header "Nix"

# Nix store GC
if command -v nix-collect-garbage &>/dev/null; then
  nix_before=$(dir_size_bytes "/nix/store")
  if $DRY_RUN; then
    # dead paths のサイズを概算
    dead_count=$(nix-store --gc --print-dead 2>/dev/null | wc -l || echo 0)
    result "Nix store (dead paths)" "${dead_count} パス"
  else
    nix-collect-garbage -d 2>/dev/null || true
    nix_after=$(dir_size_bytes "/nix/store")
    nix_freed=$((nix_before - nix_after))
    if ((nix_freed < 0)); then nix_freed=0; fi
    result "Nix store GC" "$(human_size "$nix_freed")"
    total_freed=$((total_freed + nix_freed))
  fi
else
  result "Nix store GC" "コマンドなし"
fi

# Nix cache (~/.cache/nix)
nix_cache_size=$(dir_size_bytes "${HOME}/.cache/nix")
if $DRY_RUN; then
  result "Nix cache (~/.cache/nix)" "$(human_size "$nix_cache_size")"
else
  rm -rf "${HOME}/.cache/nix"
  result "Nix cache (~/.cache/nix)" "$(human_size "$nix_cache_size")"
fi
total_freed=$((total_freed + nix_cache_size))

header "ログ"

# backup-logs
backup_size=$(dir_size_bytes "${HOME}/.backup-logs")
if $DRY_RUN; then
  result "backup-logs" "$(human_size "$backup_size")"
else
  rm -rf "${HOME}/.backup-logs"
  mkdir -p "${HOME}/.backup-logs"
  result "backup-logs" "$(human_size "$backup_size")"
fi
total_freed=$((total_freed + backup_size))

# --- サマリー ---

header "サマリー"

if $DRY_RUN; then
  printf "  削除可能量（概算）: \033[1;33m%s\033[0m\n" "$(human_size "$total_freed")"
  printf "  ※ Nix store GC の削減量は含まれていません\n"
else
  disk_after=$(df / --output=used -B1 | tail -1 | tr -d ' ')
  actual_freed=$((disk_before - disk_after))
  if ((actual_freed < 0)); then actual_freed=0; fi
  printf "  実際の削減量: \033[1;32m%s\033[0m\n" "$(human_size "$actual_freed")"
fi

# 現在のディスク使用量
printf "\n"
df -h / --output=source,size,used,avail,pcent | head -2
printf "\n"

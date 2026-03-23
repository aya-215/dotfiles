#!/bin/bash
# nb-sync.sh - nbリポジトリをGitHubと同期するスクリプト
# 使用方法: ./nb-sync.sh
# 前提条件: nb が初期化済みで $NB_DIR が設定されていること

set -euo pipefail

NB_DIR="$HOME/.nb"
LOG_FILE="$HOME/.local/log/nb-sync.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

cd "$NB_DIR" || { echo "エラー: $NB_DIR に移動できません" >&2; exit 1; }

# Check if there are changes
if [[ -n $(git status --porcelain) ]]; then
    git add -A
    git commit -m "auto sync: $(date +%Y-%m-%d\ %H:%M)"
    git push
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Synced" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No changes" >> "$LOG_FILE"
fi

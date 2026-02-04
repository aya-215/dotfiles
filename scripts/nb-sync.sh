#!/bin/bash
# nb-sync.sh - Automatically sync ~/.nb to GitHub
# Run via cron: */30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh

set -euo pipefail

NB_DIR="$HOME/.nb"
LOG_FILE="$HOME/.local/log/nb-sync.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

cd "$NB_DIR"

# Check if there are changes
if [[ -n $(git status --porcelain) ]]; then
    git add -A
    git commit -m "auto sync: $(date +%Y-%m-%d\ %H:%M)"
    git push
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Synced" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No changes" >> "$LOG_FILE"
fi

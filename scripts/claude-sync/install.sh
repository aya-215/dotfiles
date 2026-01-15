#!/bin/bash
# Claude Code to nb sync - セットアップスクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/claude-nb-sync.py"
CRON_INTERVAL="*/5"  # 5分ごと
LOG_FILE="/tmp/claude-nb-sync.log"

echo "=== Claude Code to nb Sync - Setup ==="
echo

# Python3のチェック
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed"
    exit 1
fi

echo "✓ Python3 found: $(python3 --version)"

# nbコマンドのチェック
if ! command -v nb &> /dev/null; then
    echo "Error: nb is not installed"
    echo "Please install nb: https://github.com/xwmx/nb"
    exit 1
fi

echo "✓ nb found: $(nb --version)"

# nbノートブックの確認・作成
if ! nb notebooks | grep -q "claude"; then
    echo "Creating nb notebook: claude"
    nb notebooks add claude
else
    echo "✓ nb notebook 'claude' already exists"
fi

# cronの確認
if ! command -v crontab &> /dev/null; then
    echo "Error: cron is not installed"
    exit 1
fi

# cronサービスの状態確認
if ! sudo service cron status &> /dev/null; then
    echo "Starting cron service..."
    sudo service cron start
fi

echo "✓ cron service is running"

# crontab設定
echo
echo "=== Setting up crontab ==="
CRON_ENTRY="$CRON_INTERVAL * * * * $SYNC_SCRIPT >> $LOG_FILE 2>&1"

# 既存のエントリをチェック
if crontab -l 2>/dev/null | grep -F "$SYNC_SCRIPT" &> /dev/null; then
    echo "⚠ Crontab entry already exists:"
    crontab -l | grep -F "$SYNC_SCRIPT"
    echo
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping crontab setup"
    else
        # 既存のエントリを削除して追加
        (crontab -l 2>/dev/null | grep -vF "$SYNC_SCRIPT"; echo "$CRON_ENTRY") | crontab -
        echo "✓ Crontab entry updated"
    fi
else
    # 新規追加
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "✓ Crontab entry added"
fi

echo
echo "Current crontab:"
crontab -l | grep -F "$SYNC_SCRIPT" || echo "(No entry found)"

# /etc/wsl.conf の確認
echo
echo "=== Checking /etc/wsl.conf ==="
WSL_CONF="/etc/wsl.conf"

if [[ -f "$WSL_CONF" ]] && grep -q "command.*cron" "$WSL_CONF"; then
    echo "✓ /etc/wsl.conf already configured for cron auto-start"
else
    echo "⚠ /etc/wsl.conf is not configured for cron auto-start"
    echo
    echo "To enable cron auto-start on WSL boot, add the following to $WSL_CONF:"
    echo
    echo "[boot]"
    echo "command = service cron start"
    echo
    read -p "Do you want to add this now? (requires sudo) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ ! -f "$WSL_CONF" ]]; then
            echo "[boot]" | sudo tee "$WSL_CONF" > /dev/null
            echo "command = service cron start" | sudo tee -a "$WSL_CONF" > /dev/null
        else
            if ! grep -q "^\[boot\]" "$WSL_CONF"; then
                echo "" | sudo tee -a "$WSL_CONF" > /dev/null
                echo "[boot]" | sudo tee -a "$WSL_CONF" > /dev/null
            fi
            if ! grep -q "command.*cron" "$WSL_CONF"; then
                echo "command = service cron start" | sudo tee -a "$WSL_CONF" > /dev/null
            fi
        fi
        echo "✓ /etc/wsl.conf updated"
        echo "Note: You need to restart WSL for this to take effect"
        echo "      Run: wsl.exe --shutdown (from Windows)"
    fi
fi

# テスト実行
echo
echo "=== Running test sync ==="
if python3 "$SYNC_SCRIPT"; then
    echo "✓ Test sync completed successfully"
else
    echo "⚠ Test sync failed. Check the output above for errors."
fi

# 結果確認
NB_CLAUDE_DIR="$HOME/.nb/claude"
if [[ -d "$NB_CLAUDE_DIR" ]]; then
    echo
    echo "Files in nb claude notebook:"
    ls -lh "$NB_CLAUDE_DIR"/*.md 2>/dev/null || echo "(No files yet)"
fi

echo
echo "=== Setup completed ==="
echo
echo "Next steps:"
echo "1. Check the log file: tail -f $LOG_FILE"
echo "2. View synced conversations: nb claude:list"
echo "3. Edit a conversation: nb claude:edit YYYY-MM-DD.md"
echo
echo "The sync script will run every 5 minutes via cron."

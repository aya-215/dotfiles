#!/bin/bash

##############################################################################
# WSL to Windows バックアップスクリプト
#
# 概要: /home/aya 配下のファイルを Windows の D:\WSL\backup\ に増分バックアップ
# 使用方法: ./backup-wsl-to-windows.sh
##############################################################################

# 設定
SOURCE_DIR="/home/aya"
BACKUP_DIR="/mnt/d/WSL/backup/home/aya"
EXCLUDE_FILE="$(dirname "$0")/backup-exclude.txt"
LOG_DIR="$HOME/.backup-logs"
LOG_FILE="$LOG_DIR/backup-$(date +%Y%m%d-%H%M%S).log"

# ログディレクトリの作成
mkdir -p "$LOG_DIR"

# カラー出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ログ出力関数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# バックアップ先ディレクトリの確認
if [ ! -d "/mnt/d" ]; then
    error "D:ドライブにアクセスできません。マウントされているか確認してください。"
    exit 1
fi

# バックアップ先ディレクトリの作成
log "バックアップ先ディレクトリを準備中..."
mkdir -p "$BACKUP_DIR"

# 除外ファイルの確認
if [ ! -f "$EXCLUDE_FILE" ]; then
    warning "除外ファイル ($EXCLUDE_FILE) が見つかりません。すべてのファイルをバックアップします。"
    EXCLUDE_OPTION=""
else
    log "除外ファイルを使用: $EXCLUDE_FILE"
    EXCLUDE_OPTION="--exclude-from=$EXCLUDE_FILE"
fi

# バックアップ前のサイズ確認
log "バックアップ前の状態を確認中..."
SOURCE_SIZE=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)
log "ソースディレクトリサイズ: $SOURCE_SIZE"

if [ -d "$BACKUP_DIR" ]; then
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    log "既存のバックアップサイズ: $BACKUP_SIZE"
fi

# rsync実行
log "バックアップを開始します..."
log "ソース: $SOURCE_DIR"
log "バックアップ先: $BACKUP_DIR"
echo ""

rsync -avh \
    --progress \
    --delete \
    --delete-excluded \
    $EXCLUDE_OPTION \
    --stats \
    "$SOURCE_DIR/" \
    "$BACKUP_DIR/" \
    2>&1 | tee -a "$LOG_FILE"

# 実行結果の確認
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log ""
    log "バックアップが正常に完了しました！"
    log "ログファイル: $LOG_FILE"

    # バックアップ後のサイズ
    NEW_BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    log "バックアップ後のサイズ: $NEW_BACKUP_SIZE"

    # 古いログの削除（30日以上前のログを削除）
    find "$LOG_DIR" -name "backup-*.log" -mtime +30 -delete 2>/dev/null

    exit 0
else
    error "バックアップ中にエラーが発生しました。"
    error "ログファイルを確認してください: $LOG_FILE"
    exit 1
fi

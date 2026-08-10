#!/bin/bash
# thunderbird-archive.sh - 整理済みメール履歴を life リポジトリへ保存する
#
# thunderbird-summarize.sh の出力を life/mail/YYYYMMDD.md に書き、commit & push する。
# 日報への入力とは別に、業務履歴そのものを検索可能な資産として残すのが目的。
# 案件のURL・資料の格納先・決定事項が後から追えるようにする。
#
# cron（fire-daily-review.sh）から呼ばれる。認証情報は redact.sh で落とす。
#
# 使用方法:
#   thunderbird-archive.sh 2026-08-06            # 保存して push
#   thunderbird-archive.sh 2026-08-06 --no-push  # ローカルに書くだけ（確認用）
#
# 環境変数:
#   LIFE_REPO  life リポジトリのパス（既定: ~/src/github.com/aya-215/life）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIFE_REPO="${LIFE_REPO:-$HOME/src/github.com/aya-215/life}"
readonly LOG_FILE="$HOME/.local/log/thunderbird-archive.log"

target_date="${1:?usage: thunderbird-archive.sh <YYYY-MM-DD> [--no-push]}"
no_push=0
[ "${2:-}" = "--no-push" ] && no_push=1

mkdir -p "$(dirname "$LOG_FILE")"
log() {
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

if [ ! -d "$LIFE_REPO/.git" ]; then
  log "ERROR: life リポジトリが見つかりません: $LIFE_REPO"
  exit 1
fi

# 先に最新化する。ここで失敗したら追記しない——古い状態にコミットすると
# push が非 fast-forward で弾かれ、以降の実行が毎回失敗し続けるため。
# エディタの git 統合がロックを掴むことがあるので lock を除いてから実行する。
#
# pull は内部で fetch するが、それでも最新にならない事象が実際に起きている
# （旧 daily-review スキルに fetch + merge --ff-only のフォールバックが
# 実装されていた）。そのため fetch を明示し、pull 後に origin/main が
# ローカルの先祖になっていることまで検証する。
rm -f "$LIFE_REPO/.git/index.lock"
if ! git -C "$LIFE_REPO" fetch --quiet origin 2>>"$LOG_FILE"; then
  log "ERROR: git fetch に失敗したため中断"
  exit 1
fi
rm -f "$LIFE_REPO/.git/index.lock"
if ! git -C "$LIFE_REPO" pull --rebase --quiet 2>>"$LOG_FILE"; then
  log "ERROR: git pull に失敗したため中断（リポジトリを最新化できず）"
  exit 1
fi
if ! git -C "$LIFE_REPO" merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
  log "ERROR: pull 後も origin/main に追いついていないため中断"
  exit 1
fi

content="$(bash "$SCRIPT_DIR/thunderbird-summarize.sh" "$target_date" 2>/dev/null || true)"
if [ -z "$content" ] || [ "$content" = "(業務メールなし)" ]; then
  log "skip: $target_date は業務メールなし"
  exit 0
fi

# 送信前ガードと同じ redaction をかける（life は private だが、認証情報を
# 平文で履歴に残さない）。
content="$(printf '%s' "$content" | bash "$SCRIPT_DIR/redact.sh")"

mail_dir="$LIFE_REPO/mail"
mkdir -p "$mail_dir"
mail_file="$mail_dir/$(printf '%s' "$target_date" | tr -d '-').md"

# 冪等にするため毎回書き直す（同日の再実行で追記が重複しない）
{
  echo "# $target_date のメール"
  echo
  echo "$content"
} > "$mail_file"

rm -f "$LIFE_REPO/.git/index.lock"
git -C "$LIFE_REPO" add "$mail_file"
if git -C "$LIFE_REPO" diff --cached --quiet -- "$mail_file"; then
  log "skip: $target_date は変更なし"
  exit 0
fi

rm -f "$LIFE_REPO/.git/index.lock"
git -C "$LIFE_REPO" commit -q -m "docs: $target_date のメール履歴を追加" 2>>"$LOG_FILE"

if [ "$no_push" -eq 1 ]; then
  log "committed (no-push): $mail_file"
  echo "$mail_file"
  exit 0
fi

rm -f "$LIFE_REPO/.git/index.lock"
if git -C "$LIFE_REPO" push --quiet 2>>"$LOG_FILE"; then
  log "pushed: $mail_file"
else
  # push 失敗はコミット済みなので次回の pull で解決する。日報を落とさない。
  log "WARN: push に失敗（コミットは済み。次回実行時に再試行される）"
fi
echo "$mail_file"

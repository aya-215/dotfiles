#!/bin/bash
# fire-daily-review.sh - daily-review ルーティンを text ペイロード付きで起動する
#
# cron から毎晩 22:10 に呼び出す。claude バイナリは使わない（Agent SDK クレジット消費ゼロ）。
# 当日のセッション要約と Rocket Chat 履歴を収集し、redaction をかけて
# ルーティンの /fire エンドポイントに POST する。日報生成本体はクラウド側で実行される。
#
# 必要な環境変数（.env.local に追記）: ROUTINE_FIRE_URL, ROUTINE_FIRE_TOKEN
#
# 使用方法:
#   cron から: 10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh
#   手動テスト: bash fire-daily-review.sh --dry-run   # POST せずペイロードを標準出力へ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env.local"
readonly LOG_FILE="$HOME/.local/log/fire-daily-review.log"
readonly SESSIONS_ROOT="$HOME/.nb/claude/sessions"
readonly REDACT="$SCRIPT_DIR/../lib/redact.sh"
# /fire の text 上限は 65,536 文字。余裕を見て 60,000 に抑える
readonly MAX_PAYLOAD_CHARS=60000
readonly MAX_RC_CHARS=15000

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

mkdir -p "$(dirname "$LOG_FILE")"

# ログ1行を JST タイムスタンプ付きで書く
log() {
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# shellcheck disable=SC1090
source "$ENV_FILE"
# dry-run はペイロード確認だけなので fire 用トークン未設定でも動かせる
if [ "$dry_run" -eq 0 ]; then
  : "${ROUTINE_FIRE_URL:?ROUTINE_FIRE_URL が .env.local に設定されていません}"
  : "${ROUTINE_FIRE_TOKEN:?ROUTINE_FIRE_TOKEN が .env.local に設定されていません}"
fi

target_date="$(TZ=Asia/Tokyo date +%Y-%m-%d)"

# Rocket Chat 当日履歴（失敗してもプレースホルダで続行）
rocketchat_log="$(bash "$SCRIPT_DIR/fetch-rocketchat.sh" "$target_date" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"
if [ "${#rocketchat_log}" -gt "$MAX_RC_CHARS" ]; then
  rocketchat_log="${rocketchat_log:0:$MAX_RC_CHARS}
（※ Rocket Chat 履歴が長いため切り詰め）"
fi

# 当日のセッション要約を新しい方から keep 件だけ連結する（古い方を落とす）
# daily-review-auto.sh の見出し形式（## <project> — <HH:MM>）を踏襲
build_sessions() {
  local keep="$1" out="" sf proj end_ts end_hm body
  local files=()
  while IFS= read -r sf; do files+=("$sf"); done \
    < <(find "$SESSIONS_ROOT/$target_date" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  local total="${#files[@]}"
  if [ "$total" -eq 0 ]; then
    echo "(本日のセッション要約なし)"
    return
  fi
  local start=$((total - keep))
  [ "$start" -lt 0 ] && start=0
  [ "$start" -gt 0 ] && out="（※ 容量制限のため古い ${start} セッションを省略）
"
  for sf in "${files[@]:$start}"; do
    proj="$(sed -n 's/^project: //p' "$sf" | head -1)"
    [ -z "$proj" ] && proj="unknown"
    end_ts="$(sed -n 's/^end: //p' "$sf" | head -1)"
    end_hm="$(TZ=Asia/Tokyo date -d "$end_ts" +%H:%M 2>/dev/null || echo "??:??")"
    # frontmatter は「project: 行より後の最初の ---」で終わる（先頭に余分な --- ブロックが
    # 付くファイルと標準形の両方に対応する。--- の個数には依存しない）
    body="$(awk '/^project: /{seen=1} /^---$/{if(seen && !body){body=1; next}} body{print}' "$sf")"
    # 本文が空の要約（薄いセッション等）は見出しごとスキップしてトークンを節約する
    if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
      continue
    fi
    out="${out}## ${proj} — ${end_hm}

${body}

---

"
  done
  printf '%s' "$out"
}

# 予算に収まるまで古いセッションから落とす
session_count="$(find "$SESSIONS_ROOT/$target_date" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
keep="$session_count"
[ "$keep" -eq 0 ] && keep=1
while :; do
  session_summaries="$(build_sessions "$keep")"
  payload="【対象日】${target_date}

【Rocket Chat 当日履歴（mori.a-times）】
${rocketchat_log}

【セッション要約（${target_date}・時刻順）】
${session_summaries}"
  [ "${#payload}" -le "$MAX_PAYLOAD_CHARS" ] && break
  if [ "$keep" -le 1 ]; then
    payload="${payload:0:$MAX_PAYLOAD_CHARS}"
    break
  fi
  keep=$((keep - 1))
done

# redaction（送信前の最終ガード）
payload="$(printf '%s' "$payload" | bash "$REDACT")"

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$payload"
  echo "--- (${#payload} chars, dry-run のため POST しません)" >&2
  exit 0
fi

body_json="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.dumps({"text": sys.stdin.read()}))')"

# POST（429/503 等に備えて 60 秒間隔で最大 3 回）
resp_file="$(mktemp /tmp/fire-daily-review-resp-XXXX.json)"
trap 'rm -f "$resp_file"' EXIT
for attempt in 1 2 3; do
  http_code="$(curl -sS -m 60 -o "$resp_file" -w '%{http_code}' \
    -X POST "$ROUTINE_FIRE_URL" \
    -H "Authorization: Bearer $ROUTINE_FIRE_TOKEN" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
    -H "Content-Type: application/json" \
    -d "$body_json" 2>>"$LOG_FILE" || echo "000")"
  if [ "$http_code" = "200" ]; then
    log "fired (attempt=$attempt, payload=${#payload}chars): $(cat "$resp_file")"
    exit 0
  fi
  log "fire failed (attempt=$attempt, http=$http_code): $(cat "$resp_file" 2>/dev/null || true)"
  [ "$attempt" -lt 3 ] && sleep 60
done
log "fire giving up after 3 attempts"
exit 1

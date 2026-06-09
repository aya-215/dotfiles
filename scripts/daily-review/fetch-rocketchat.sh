#!/bin/bash
# fetch-rocketchat.sh - 指定日の Rocket Chat times チャンネル履歴を整形して標準出力に出す
#
# daily-review-auto.sh から呼ばれ、当日分のチャンネル全メッセージを
# 「HH:MM ユーザー名: 本文」形式のプレーンテキストにして返す。
# 認証情報は同ディレクトリの .env.local から読む。
#
# 使用方法:
#   ./fetch-rocketchat.sh [YYYY-MM-DD]   # 省略時は当日(JST)
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="$SCRIPT_DIR/.env.local"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE が見つかりません（.env.example を参照して作成してください）" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

target_date="${1:-$(TZ=Asia/Tokyo date +%Y-%m-%d)}"
# 対象日 JST 00:00〜翌 00:00 を UTC ISO8601 に変換
oldest=$(TZ=Asia/Tokyo date -d "$target_date 00:00" -u +%Y-%m-%dT%H:%M:%S.000Z)
latest=$(TZ=Asia/Tokyo date -d "$target_date 00:00 +1 day" -u +%Y-%m-%dT%H:%M:%S.000Z)

# 認証ヘッダ付き curl のラッパー
rc_get() {
  curl -s -m 20 \
    -H "X-Auth-Token: $RC_TOKEN" \
    -H "X-User-Id: $RC_USER_ID" \
    "$@"
}

# チャンネル種別を判定して history エンドポイントと roomId を決める。
# public は channels.*、private は groups.* を使う。
room_id=$(rc_get "$RC_BASE_URL/api/v1/channels.info?roomName=$RC_CHANNEL" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("channel",{}).get("_id",""))' 2>/dev/null || true)

if [[ -n "$room_id" ]]; then
  history_path="channels.history"
else
  room_id=$(rc_get "$RC_BASE_URL/api/v1/groups.info?roomName=$RC_CHANNEL" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("group",{}).get("_id",""))' 2>/dev/null || true)
  history_path="groups.history"
fi

if [[ -z "$room_id" ]]; then
  echo "(Rocket Chat: チャンネル $RC_CHANNEL が見つからない、または取得失敗)" >&2
  exit 0
fi

# 当日分の全メッセージを取得し、時刻順に「HH:MM user: msg」で整形
rc_get "$RC_BASE_URL/api/v1/$history_path?roomId=$room_id&oldest=$oldest&latest=$latest&count=200" \
  | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("(Rocket Chat: レスポンスのパースに失敗)")
    sys.exit(0)
msgs = [m for m in d.get("messages", []) if m.get("msg", "").strip()]
if not msgs:
    print("(Rocket Chat: 対象日の発言なし)")
    sys.exit(0)
for m in reversed(msgs):  # history は新しい順なので古い順に直す
    ts = m.get("ts", "")[11:16]
    user = m.get("u", {}).get("username", "?")
    text = m.get("msg", "").replace("\n", " ")
    print(f"{ts} {user}: {text}")
'

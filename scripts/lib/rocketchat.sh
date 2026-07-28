#!/bin/bash
# rocketchat.sh - Rocket Chat の購読ルームから自分に関係するメッセージを収集して整形出力する
#
# 日報 cron（fire-daily-review.sh）と work-report skill の共通データ取得層。
# ルーム列挙・期間絞り込み・関連メッセージ抽出という決定的な処理を担い、
# 作業内容の分類のような非決定的な判断は呼び出し側（Claude）に委ねる。
#
# 設計: docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md
#
# 使用方法:
#   rocketchat.sh --from 2026-07-21 --to 2026-07-28 [--include-dm] [--budget N]
#   rocketchat.sh --from ... --to ... --list-rooms      # 採用ルームの一覧だけ出す（デバッグ用）
#
# 環境変数:
#   RC_ENV_FILE  認証情報ファイル（既定: scripts/daily-review/.env.local）
#   RC_ME        自分のユーザー名（既定: mori.a）
#   RC_CURL      curl の代替コマンド（テスト用フック）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_ENV_FILE="$SCRIPT_DIR/../daily-review/.env.local"
readonly WINDOW_SEC=1800   # 起点の前後30分

env_file="${RC_ENV_FILE:-$DEFAULT_ENV_FILE}"
me="${RC_ME:-mori.a}"
curl_cmd="${RC_CURL:-curl}"

from="" to="" include_dm=0 budget=0 list_rooms=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)       from="$2"; shift 2 ;;
    --to)         to="$2"; shift 2 ;;
    --include-dm) include_dm=1; shift ;;
    --budget)     budget="$2"; shift 2 ;;
    --list-rooms) list_rooms=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$from" ] && [ -n "$to" ] || { echo "--from と --to は必須" >&2; exit 2; }

if [ ! -f "$env_file" ]; then
  echo "(Rocket Chat: $env_file が見つかりません)" >&2
  exit 0
fi
# shellcheck disable=SC1090
source "$env_file"

# JST の日付範囲を UTC ISO8601 に変換する
oldest="$(TZ=Asia/Tokyo date -d "$from 00:00" -u +%Y-%m-%dT%H:%M:%S.000Z)"
latest="$(TZ=Asia/Tokyo date -d "$to 00:00 +1 day" -u +%Y-%m-%dT%H:%M:%S.000Z)"

# rc_api <path> [query-string]
rc_api() {
  local path="$1" qs="${2:-}"
  "$curl_cmd" -s -m 25 \
    -H "X-Auth-Token: $RC_TOKEN" \
    -H "X-User-Id: $RC_USER_ID" \
    "$RC_BASE_URL/api/v1/${path}?${qs}"
}

# 期間内に活動があった購読ルームを "_id<TAB>t<TAB>name" 形式で列挙する。
# lm（last message）で絞る。_updatedAt はトピック変更等でも更新されるため使わない。
list_active_rooms() {
  rc_api "rooms.get" | python3 -c '
import sys, json, os
oldest = os.environ["RC_OLDEST"]
include_dm = os.environ["RC_INCLUDE_DM"] == "1"
try:
    rooms = json.load(sys.stdin).get("update", [])
except Exception:
    sys.exit(0)
for r in rooms:
    t = r.get("t")
    if t == "d" and not include_dm:
        continue
    if (r.get("lm") or "") < oldest:
        continue
    if t == "d":
        others = [u for u in (r.get("usernames") or []) if u != os.environ["RC_ME"]]
        name = "DM:" + (",".join(others) or "self")
    else:
        name = r.get("name") or r.get("fname") or "(no-name)"
    print("\t".join([r["_id"], t, name]))
'
}

export RC_OLDEST="$oldest" RC_INCLUDE_DM="$include_dm" RC_ME="$me"

if [ "$list_rooms" -eq 1 ]; then
  list_active_rooms
  exit 0
fi

# 履歴取得・絞り込みは Task 2 以降で実装する
list_active_rooms

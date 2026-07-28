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
#   rocketchat.sh --from ... --to ... --print-window    # oldest/latest の計算結果だけ出す（デバッグ用）
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

from="" to="" include_dm=0 budget=0 list_rooms=0 print_window=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from)         from="$2"; shift 2 ;;
    --to)           to="$2"; shift 2 ;;
    --include-dm)   include_dm=1; shift ;;
    --budget)       budget="$2"; shift 2 ;;
    --list-rooms)   list_rooms=1; shift ;;
    --print-window) print_window=1; shift ;;
    *) echo "不明な引数: $1" >&2; exit 2 ;;
  esac
done
[ -n "$from" ] && [ -n "$to" ] || { echo "--from と --to は必須" >&2; exit 2; }

if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file が見つかりません" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$env_file"

# JST の日付範囲を UTC ISO8601 に変換する。
#
# 注意: `TZ=Asia/Tokyo date -d "..." -u ...` という書き方は使わないこと。
# GNU date は `-u`/`--utc` を「オプション解析時点で TZ=UTC0 を設定する」のと
# 等価に扱うため、-d の入力文字列の解釈自体が JST ではなく UTC になってしまう
# （出力だけでなく入力もUTC化される）。オフセットは入力文字列側に明示し、
# `-u` は出力フォーマットのみに効かせる。
# また "00:00 +1 day" のように書くと `+1` が数値UTCオフセットとして先に
# 消費され `day` だけが相対指定として残る誤動作があるため、オフセットは
# 必ず `T00:00:00+09:00` の形で日時側に付け、加算は " +1 day" のみにする。
oldest="$(date -u -d "${from}T00:00:00+09:00" +%Y-%m-%dT%H:%M:%S.000Z)"
latest="$(date -u -d "${to}T00:00:00+09:00 +1 day" +%Y-%m-%dT%H:%M:%S.000Z)"

if [ "$print_window" -eq 1 ]; then
  printf '%s\t%s\n' "$oldest" "$latest"
  exit 0
fi

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

# room_history <room_id> <t> : 期間内のメッセージ JSON を返す
#
# 1回の実行で数十ルーム分を叩くため、1ルームの失敗で全体を落とさない。
# curl が失敗した場合は空の messages を返してそのルームだけスキップさせる
# （set -e 下でも止まらないよう || で受ける）。
room_history() {
  local rid="$1" t="$2" path out
  case "$t" in
    c) path="channels.history" ;;
    p) path="groups.history" ;;
    d) path="im.history" ;;
    *) echo '{"messages":[]}'; return ;;
  esac
  out="$(rc_api "$path" "roomId=${rid}&oldest=${oldest}&latest=${latest}&count=200" || true)"
  # JSON として妥当かを検証する（HTMLエラーページ等が返る場合に備える）
  if printf '%s' "$out" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    printf '%s' "$out"
  else
    echo "(Rocket Chat: ルーム $rid の取得に失敗しスキップ)" >&2
    echo '{"messages":[]}'
  fi
}

# 1ルーム分を判定・整形する。採用されなければ何も出さない。
# stdin: 履歴 JSON / 引数: ルーム名, ルーム種別
render_room() {
  local name="$1" t="$2"
  RC_ROOM_NAME="$name" RC_ROOM_T="$t" python3 -c '
import sys, json, os
me = os.environ["RC_ME"]
name = os.environ["RC_ROOM_NAME"]
try:
    msgs = [m for m in json.load(sys.stdin).get("messages", []) if (m.get("msg") or "").strip()]
except Exception:
    sys.exit(0)
own = [m for m in msgs if m.get("u", {}).get("username") == me]
men = [m for m in msgs if "@" + me in (m.get("msg") or "")]
if not own and not men:
    sys.exit(0)          # 第1段階: 採用しない
why = []
if own: why.append(f"発言{len(own)}")
if men: why.append(f"@me{len(men)}")
# f-string 内にバックスラッシュを書くと環境によって SyntaxError になるため
# join は必ず変数に退避してから埋め込む
tag = ",".join(why)
print(f"===== {name} [{tag}] =====")
for m in sorted(msgs, key=lambda x: x.get("ts", "")):
    tstr = (m.get("ts") or "")[11:16]
    u = m.get("u", {}).get("username", "?")
    body = (m.get("msg") or "").replace("\n", " / ")
    print(f"  {tstr} {u}: {body}")
'
}

# メイン: 採用ルームを順に処理する
while IFS=$'\t' read -r rid t name; do
  [ -n "$rid" ] || continue
  room_history "$rid" "$t" | render_room "$name" "$t"
done < <(list_active_rooms)

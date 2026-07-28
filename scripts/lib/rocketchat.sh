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
#   RC_CHANNEL   自分の times チャンネル名（.env.local 由来。全メッセージ採用の
#                対象を決める。未設定・不一致だと自分の times が時間窓の対象に
#                なり尻尾が切れて黙って劣化するため、その場合は stderr に警告する）
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

# 1ルーム分を判定・絞り込み・整形する。採用されなければ何も出さない。
# stdin: 履歴 JSON / 引数: ルーム名, ルーム種別
render_room() {
  local name="$1" t="$2"
  RC_ROOM_NAME="$name" RC_ROOM_T="$t" RC_WINDOW_SEC="$WINDOW_SEC" \
  RC_MY_TIMES="${RC_CHANNEL:-}" python3 -c '
import sys, json, os, datetime
me      = os.environ["RC_ME"]
name    = os.environ["RC_ROOM_NAME"]
rtype   = os.environ["RC_ROOM_T"]
window  = int(os.environ["RC_WINDOW_SEC"])
mytimes = os.environ.get("RC_MY_TIMES", "")

def ts(m):
    return datetime.datetime.fromisoformat((m.get("ts") or "").replace("Z", "+00:00"))

try:
    msgs = [m for m in json.load(sys.stdin).get("messages", []) if (m.get("msg") or "").strip()]
except Exception:
    sys.exit(0)

# ts が壊れている（不正なISO8601）メッセージだけを除外する。room_history の
# JSON妥当性チェックはレスポンス全体の JSON としての妥当性しか見ておらず、
# 個々のメッセージの ts フィールドの中身までは検証していない。ts() は
# fromisoformat に失敗すると例外を投げるため、ここで弾かないと1件の不正な
# ts が render_room 全体をクラッシュさせ、Task 2 で確保した「1ルームの失敗が
# 全体を落とさない」耐性を迂回してしまう（room_history の防御はレスポンス
# 単位、これはメッセージ単位の防御）。
def ts_ok(m):
    try:
        ts(m)
        return True
    except Exception:
        return False

bad = [m for m in msgs if not ts_ok(m)]
if bad:
    print(f"(Rocket Chat: {name} の ts 不正メッセージ{len(bad)}件を除外)", file=sys.stderr)
msgs = [m for m in msgs if ts_ok(m)]

own = [m for m in msgs if m.get("u", {}).get("username") == me]
men = [m for m in msgs if "@" + me in (m.get("msg") or "")]
if not own and not men:
    sys.exit(0)                       # 第1段階: 採用しない

# 第2段階(a): 自分の times と DM は全メッセージ採用
if rtype == "d" or (mytimes and name == mytimes):
    sel = msgs
else:
    # 第2段階(b): 起点 + スレッド(親/兄弟) + 起点の前後 window 秒
    seeds = own + men
    tids  = {(m.get("tmid") or m.get("_id")) for m in seeds}
    keep  = {m["_id"] for m in msgs
             if m.get("_id") in tids or m.get("tmid") in tids}
    for s in seeds:
        st = ts(s)
        for m in msgs:
            if abs((ts(m) - st).total_seconds()) <= window:
                keep.add(m["_id"])
    sel = [m for m in msgs if m["_id"] in keep]

why = []
if own: why.append(f"発言{len(own)}")
if men: why.append(f"@me{len(men)}")
# f-string 内にバックスラッシュを書くと環境によって SyntaxError になるため
# join は必ず変数に退避してから埋め込む
tag = ",".join(why)
print(f"===== {name} [{tag}] {len(sel)}/{len(msgs)}件 =====")
for m in sorted(sel, key=lambda x: x.get("ts", "")):
    tstr = (m.get("ts") or "")[11:16]
    u = m.get("u", {}).get("username", "?")
    body = (m.get("msg") or "").replace("\n", " / ")
    print(f"  {tstr} {u}: {body}")
'
}

# メイン: 採用ルームを順に処理する。
#
# mytimes_seen は RC_CHANNEL が実際に列挙されたルーム名のいずれかと一致したかを
# 追跡する。未設定・不一致だと render_room の全採用分岐が発火せず、自分の times
# が時間窓の対象になって黙って尻尾が切れる（ユーザーが手で見つけた欠陥の設定
# ミスによる再発経路）ため、検出できる範囲で stderr に警告する。
mytimes_seen=0
while IFS=$'\t' read -r rid t name; do
  [ -n "$rid" ] || continue
  if [ -n "${RC_CHANNEL:-}" ] && [ "$name" = "${RC_CHANNEL}" ]; then
    mytimes_seen=1
  fi
  room_history "$rid" "$t" | render_room "$name" "$t"
done < <(list_active_rooms)

if [ -z "${RC_CHANNEL:-}" ]; then
  echo "WARN: RC_CHANNEL が未設定のため、自分の times が全採用されず時間窓の対象になっています" >&2
elif [ "$mytimes_seen" -eq 0 ]; then
  echo "WARN: RC_CHANNEL=$RC_CHANNEL が列挙されたルーム名のいずれとも一致しませんでした（設定ミスの可能性。対象期間に times への投稿が無い場合はこの警告は無視して構いません）" >&2
fi

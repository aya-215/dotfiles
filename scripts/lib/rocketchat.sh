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

# expand_threads : stdin の履歴 JSON に、含まれるスレッドの全返信をマージして返す
#
# history 系エンドポイントはスレッド返信を全件返さない（実測: 9返信中3件のみ）。
# tmid / tcount からスレッドIDを集め、chat.getThreadMessages で補完する。
expand_threads() {
  local rid="$1"
  local hist tids tid extra tresp sresp stids
  hist="$(cat)"
  # スレッドID = 返信の tmid ∪ 親の _id（tcount を持つもの）
  tids="$(printf '%s' "$hist" | python3 -c '
import sys, json
try:
    ms = json.load(sys.stdin).get("messages", [])
except Exception:
    sys.exit(0)
ids = set()
for m in ms:
    if m.get("tmid"):
        ids.add(m["tmid"])
    if m.get("tcount"):
        ids.add(m["_id"])
for i in sorted(ids):
    print(i)
')"
  # chat.syncThreadsList で「期間内に更新されたスレッド」の親IDを直接引く。
  #
  # history 系エンドポイントは tshow=None（通常のスレッド返信）を返さないため、
  # 「親が対象期間外・返信が期間内」のスレッドは tmid/tcount 収集では構造的に
  # 発見できない（実測: 7/27 の e食なび で7件を取り逃していた）。
  # syncThreadsList は各スレッドの tlm(thread last message) を返すので、
  # 親の ts が期間外でも tlm が期間内なら発見できる。
  #
  # 従来の tmid/tcount 由来と和集合を取る。updatedSince の厳密な意味論
  # （境界の開閉・サーバ側の更新判定）を確定できていないため、従来経路を
  # 残して片方が取りこぼしても現状より悪化しないようにしてある。
  # 重複は後段の _id ベース重複排除が吸収する。
  # count は付けないこと。chat.syncThreadsList は未知パラメータを拒否し
  # {"success":false,"error":"must NOT have additional properties"} を返す
  # （実API実測）。兄弟の history 系は count=200 を受けるが、この
  # エンドポイントだけは受け付けない。付けると全ルームが失敗扱いになり
  # スレッド発見が丸ごと無効化される。
  sresp="$(rc_api "chat.syncThreadsList" "rid=${rid}&updatedSince=${oldest}" || true)"
  # room_history と同じ防御: HTMLエラーページ等が返った場合に無音で
  # スレッド発見が消えないよう、JSON妥当性を検証して警告を出す。
  # さらに `{"success":false,"error":"..."}` のように JSON としては妥当でも
  # API 呼び出し自体が失敗している応答（トークン失効・権限エラー等）も
  # 同様に失敗として扱う。ここを見落とすと threads キーが単に存在しない
  # だけになり、無警告でスレッド発見が0件に戻ってしまう
  # （＝本ブランチが直そうとしているバグそのものが再発する）。
  # 失敗しても従来の tmid/tcount 経路は生きているため処理は継続する。
  if ! printf '%s' "$sresp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict) or d.get("success") is False or "threads" not in d:
    sys.exit(1)
' 2>/dev/null; then
    echo "(Rocket Chat: ルーム $rid のスレッド一覧取得に失敗しスキップ)" >&2
    sresp='{"threads":{"update":[]}}'
  fi
  stids="$(printf '%s' "$sresp" | RC_SYNC_OLDEST="$oldest" python3 -c '
import sys, json, os
oldest = os.environ["RC_SYNC_OLDEST"]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for th in (d.get("threads", {}) or {}).get("update", []) or []:
    # tlm が期間内のスレッドだけを対象にする。updatedSince が期待通り効かない
    # 場合でも、ここで絞れば古いスレッドを引き込まない。
    #
    # tlm が欠落/null の場合は fail-open で「期間内」とみなす（フォールバック
    # は空文字列ではなく oldest 自身にする）。サーバは既に updatedSince で
    # 絞り込んだ結果を返してきているため、tlm を持たずに返ってきたスレッドを
    # ここで弾くのはノイズ除去ではなくデータ損失になる。ここで誤って通しても、
    # このスレッドの全メッセージは後段の必須 ts 期間フィルタ（expand_threads
    # 末尾）を必ず通るため、期間外メッセージが最終出力に漏れることはない。
    if (th.get("tlm") or oldest) >= oldest and th.get("_id"):
        print(th["_id"])
' 2>/dev/null || true)"
  if [ -n "$stids" ]; then
    tids="$(printf '%s\n%s' "$tids" "$stids" | grep -v '^$' | sort -u)"
  fi
  [ -n "$tids" ] || { printf '%s' "$hist"; return; }

  extra="[]"
  while IFS= read -r tid; do
    [ -n "$tid" ] || continue
    # room_history と同じ形の防御: chat.getThreadMessages 単体の失敗（curl失敗・
    # HTMLエラーページ等）が無音で全メッセージ消失に繋がらないよう、JSON妥当性を
    # 検証し、失敗時は stderr に警告して空配列で継続する（Task 4 Fix round 1）。
    tresp="$(rc_api "chat.getThreadMessages" "tmid=${tid}&count=200" || true)"
    if ! printf '%s' "$tresp" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
      echo "(Rocket Chat: スレッド $tid の取得に失敗しスキップ)" >&2
      tresp='{"messages":[]}'
    fi
    # $acc（累積extra）と $tresp の受け渡しに改行区切りの printf '%s\n%s' を使うと、
    # メッセージ本文に改行を含むJSON（fromisoformat等ではなく通常の複数行メッセージ）
    # が来た際に split("\n", 1) がJSON片の途中で分断され、パースが無音で失敗して
    # メッセージが全消失する（Task 4 レビューで指摘、実測でも再現確認済み）。
    # \x1e（Record Separator, 0x1E）は RFC 8259 上 JSON 文字列中に生では出現し得ない
    # （U+0000-U+001Fは必ずエスケープされる）ため、区切り文字として安全に使える。
    extra="$(printf '%s\x1e%s' "$extra" "$tresp" \
      | python3 -c '
import sys, json
lines = sys.stdin.read().split("\x1e", 1)
try:
    acc = json.loads(lines[0])
except Exception as e:
    print(f"(Rocket Chat: スレッド累積データのパースに失敗: {e})", file=sys.stderr)
    acc = []
try:
    new = json.loads(lines[1]).get("messages", [])
except Exception as e:
    print(f"(Rocket Chat: スレッド応答のパースに失敗: {e})", file=sys.stderr)
    new = []
print(json.dumps(acc + new, ensure_ascii=False))
')"
  done <<< "$tids"

  # _id で重複排除してマージし、対象期間外のメッセージを落とす
  #
  # chat.getThreadMessages は oldest/latest を無視して全返信を返す（実測: 期間指定
  # ありだと0件になり、なしだと9件全部返る）。API 側で絞れないため取得後に ts で
  # 自前フィルタする。これを省くと、生きているスレッドの全履歴が毎日の日報に
  # 混入し続ける（例: 7/22 の日程調整が 7/27 の日報に入る）。
  #
  # ここも $hist（history側のJSON）と $extra（スレッド側のJSON）の結合に改行を
  # 使うと同じ理由で無音消失する。特にこちらは history 由来のメッセージも巻き
  # 込むため被害が最大（history由来・thread由来が両方消える）。\x1e で結合する。
  printf '%s\x1e%s' "$hist" "$extra" \
  | RC_OLDEST_F="$oldest" RC_LATEST_F="$latest" python3 -c '
import sys, json, os
oldest = os.environ["RC_OLDEST_F"]
latest = os.environ["RC_LATEST_F"]
raw = sys.stdin.read().split("\x1e", 1)
try:
    base = json.loads(raw[0]).get("messages", [])
except Exception as e:
    print(f"(Rocket Chat: history側データのパースに失敗: {e})", file=sys.stderr)
    base = []
try:
    extra = json.loads(raw[1])
except Exception as e:
    print(f"(Rocket Chat: スレッド展開データのパースに失敗: {e})", file=sys.stderr)
    extra = []
seen, out = set(), []
for m in base + extra:
    mid = m.get("_id")
    if not mid or mid in seen:
        continue
    ts = m.get("ts") or ""
    if ts < oldest or ts >= latest:   # 対象期間外は落とす
        continue
    seen.add(mid)
    out.append(m)
print(json.dumps({"messages": out}, ensure_ascii=False))
'
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

# メイン: 採用ルームをブロックごとに集め、予算に応じて落とす。
#
# rooms は list_active_rooms の結果を1回だけ取得してメインシェルの変数に
# 保持する。mytimes_seen の判定と collect_blocks 双方がこれを参照する。
# collect_blocks は `blocks="$(collect_blocks)"` のようにコマンド置換で
# 呼ばれるためサブシェルで実行される。もし collect_blocks の中で
# list_active_rooms を再度呼んで mytimes_seen を更新しようとすると、
# その更新はサブシェルの中だけで完結しメインシェルには伝わらない
# （Task 3 のレビューで指摘された、process substitution 依存の脆弱性と
# 同種の罠）。そのため mytimes_seen の判定はメインシェルの while ループで
# 完結させ、collect_blocks には rooms を渡すだけにする。
rooms="$(list_active_rooms)"

# mytimes_seen は RC_CHANNEL が実際に列挙されたルーム名のいずれかと一致したかを
# 追跡する。未設定・不一致だと render_room の全採用分岐が発火せず、自分の times
# が時間窓の対象になって黙って尻尾が切れる（ユーザーが手で見つけた欠陥の設定
# ミスによる再発経路）ため、検出できる範囲で stderr に警告する。
mytimes_seen=0
while IFS=$'\t' read -r _ _ name; do
  [ -n "$name" ] || continue
  if [ -n "${RC_CHANNEL:-}" ] && [ "$name" = "${RC_CHANNEL}" ]; then
    mytimes_seen=1
  fi
done <<<"$rooms"

if [ -z "${RC_CHANNEL:-}" ]; then
  echo "WARN: RC_CHANNEL が未設定のため、自分の times が全採用されず時間窓の対象になっています" >&2
elif [ "$mytimes_seen" -eq 0 ]; then
  echo "WARN: RC_CHANNEL=$RC_CHANNEL が列挙されたルーム名のいずれとも一致しませんでした（設定ミスの可能性。対象期間に times への投稿が無い場合はこの警告は無視して構いません）" >&2
fi

# 各ブロックは "優先度<TAB>ルーム名<TAB>本文(base64)" の1行にして扱う。
# 優先度: 1=自分の発言あり / 2=@meのみ / 3=それ以外
collect_blocks() {
  while IFS=$'\t' read -r rid t name; do
    [ -n "$rid" ] || continue
    local block prio
    # Task 4 で追加した expand_threads を必ず通す（外すとスレッド返信が欠落する）
    block="$(room_history "$rid" "$t" | expand_threads "$rid" | render_room "$name" "$t")"
    [ -n "$block" ] || continue
    if grep -q '\[発言' <<<"$block"; then prio=1
    elif grep -q '\[@me' <<<"$block"; then prio=2
    else prio=3; fi
    printf '%s\t%s\t%s\n' "$prio" "$name" "$(printf '%s' "$block" | base64 -w0)"
  done <<<"$rooms"
}

blocks="$(collect_blocks)"
[ -n "$blocks" ] || { echo "(Rocket Chat: 対象期間の該当メッセージなし)"; exit 0; }

# 優先度昇順に採用し、予算を超えたら以降を落とす。
#
# 予算はバイト数で比較する。fire-daily-review.sh（呼び出し側）は `${#var}`
# で判定するが、これは LANG が未設定の cron 環境ではバイト数になる
# （実測: LANG=ja_JP.UTF-8 だと文字数、LANG未設定だとバイト数で3倍程度
# 変わる）。rocketchat.sh 側が文字数で判定すると「こちらは収まっていると
# 思っているのに呼び出し側では超過判定される」というズレが起きるため、
# `wc -c` で環境に依存しないバイト数を明示的に測る。
#
# ソート済みの全行を配列に読み込んでから for で回す（while <(...) だと
# break した時点で未読の行がプロセス置換ごと破棄され、残りを dropped に
# 積めない）。超過を検出したら break で走査自体を止める（continue で次の
# ブロックを試すと、優先度は低いがサイズが小さい後続ブロックだけ拾えて
# しまい、「優先度の低い方から落とす」という仕様に反する。実際に
# quality-check-room のような小さい prio=1 ブロックが先に埋まり、同じ
# prio=1 でもサイズが大きい mori.a-times が後回しにされて先に弾かれる
# 逆転が起きた）。break した時点で未処理の行は同一優先度グループの残りか
# より低い優先度のグループなので、全部まとめて dropped に積む。
#
# `-s`（stable sort）が無いと、GNU sort は prio が同点の行を「行全体の
# 辞書式比較」で副次的に並べ替えてしまう（-k1,1n は第1キーの比較方法を
# 指定するだけで、同点時に他フィールドを見ないようにする指定ではない）。
# その結果、同じ prio=1 でも room 名の文字コード順（"DM:..." が "mori.a-
# times" や "quality-check-room" より前に来る等）でソートが決まってしまい、
# ルームサイズや採用順とは無関係な理由で入れ替わりが起きた。-s を付けると
# 同点時は入力順（= collect_blocks の処理順 = list_active_rooms の列挙順）
# を保つため、少なくとも実行のたびに結果が変わることはない。
mapfile -t sorted_blocks < <(printf '%s\n' "$blocks" | sort -t$'\t' -k1,1n -s)

dropped=()
out=""
budget_hit=0
for line in "${sorted_blocks[@]}"; do
  IFS=$'\t' read -r _ name b64 <<<"$line"
  [ -n "$b64" ] || continue
  if [ "$budget_hit" -eq 1 ]; then
    dropped+=("$name")
    continue
  fi
  block="$(printf '%s' "$b64" | base64 -d)"
  if [ "$budget" -gt 0 ]; then
    candidate="${out}${block}"$'\n\n'
    candidate_bytes="$(printf '%s' "$candidate" | wc -c)"
    if [ "$candidate_bytes" -gt "$budget" ] && [ -n "$out" ]; then
      dropped+=("$name")
      budget_hit=1
      continue
    fi
  fi
  out="${out}${block}"$'\n\n'
done

printf '%s' "$out"
if [ "${#dropped[@]}" -gt 0 ]; then
  printf '（※ 容量制限のため %d ルームを省略: %s）\n' \
    "${#dropped[@]}" "$(IFS=, ; echo "${dropped[*]}")"
fi

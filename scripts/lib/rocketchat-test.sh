#!/bin/bash
# rocketchat-test.sh - rocketchat.sh の動作確認テスト
# 使用方法: bash scripts/lib/rocketchat-test.sh （全部 ok なら ALL OK で exit 0）
# 実APIは叩かない。$RC_CURL にスタブを差し込み fixture JSON を返させる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# ---- ダミー .env.local（実認証情報は使わない） ----
cat > "$TMP/env.local" <<'EOF'
RC_BASE_URL=http://rc.test
RC_TOKEN=dummy-token
RC_USER_ID=dummy-user
RC_CHANNEL=mori.a-times
EOF

# ---- curl スタブ ----
# 引数の URL に応じて fixture を返す。rooms.get と *.history を出し分ける。
# history 系は URL 中の oldest=/latest= を実際に見て messages を絞り込む
# （range-aware）。rocketchat.sh 側が oldest/latest をクエリに渡し忘れる、
# または渡す値を間違えるバグを fixture 側で検出できるようにするため。
# Task 2 で追加（Task 1 時点では rooms.get の lm 絞り込みのみで足りていた）。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl-stub.sh" <<'EOF'
#!/bin/bash
set -u
url="${!#}"   # 最後の引数が URL

qparam() {
  local name="$1"
  if [[ "$url" =~ (^|[?\&])$name=([^\&]*) ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  fi
}

fx=""
case "$url" in
  *rooms.get*)           cat "$RC_FIXTURE_DIR/rooms.json"; exit 0 ;;
  *roomId=room-own*)     fx="$RC_FIXTURE_DIR/hist-own.json" ;;
  *roomId=room-other*)   fx="$RC_FIXTURE_DIR/hist-other.json" ;;
  *roomId=room-noise*)   fx="$RC_FIXTURE_DIR/hist-noise.json" ;;
  *roomId=room-dm*)      fx="$RC_FIXTURE_DIR/hist-dm.json" ;;
  *roomId=room-atall*)   fx="$RC_FIXTURE_DIR/hist-atall.json" ;;
  *roomId=room-badjson*) echo '<html>error</html>'; exit 0 ;;
  # curl コマンド自体が失敗するケース（ネットワークエラー等）を模擬する。
  # room_history の `|| true` がこれを受け止め、後続ルームの処理を止めない
  # ことを検証するための分岐。
  *roomId=room-curlfail*) echo 'connection refused' >&2; exit 7 ;;
  *)                     echo '{"messages":[]}'; exit 0 ;;
esac

RC_Q_OLDEST="$(qparam oldest)" RC_Q_LATEST="$(qparam latest)" python3 -c '
import sys, json, os
oldest = os.environ.get("RC_Q_OLDEST", "")
latest = os.environ.get("RC_Q_LATEST", "")
d = json.load(sys.stdin)
msgs = d.get("messages", [])
if oldest:
    msgs = [m for m in msgs if (m.get("ts") or "") >= oldest]
if latest:
    msgs = [m for m in msgs if (m.get("ts") or "") <= latest]
d["messages"] = msgs
print(json.dumps(d, ensure_ascii=False))
' < "$fx"
EOF
chmod +x "$TMP/bin/curl-stub.sh"

# ---- fixture ----
mkdir -p "$TMP/fixtures"
# 8ルーム: 障害注入用2件(curl失敗/不正JSON)を先頭に配置し、途中で処理が
# 中断されていないか（＝後続ルームが正常処理されるか）を検出できるようにする。
# 残りは既存通り: 自分のtimes / 他人のtimes / 自動投稿(ノイズ) / DM / @allのみ(ノイズ)
# lm は期間内(7/22)と期間外(7/10)を混ぜる
cat > "$TMP/fixtures/rooms.json" <<'EOF'
{"update":[
 {"_id":"room-curlfail","t":"c","name":"curl-fail-room","lm":"2026-07-22T04:00:00.000Z"},
 {"_id":"room-badjson","t":"c","name":"broken-room","lm":"2026-07-22T10:00:00.000Z"},
 {"_id":"room-own","t":"p","name":"mori.a-times","lm":"2026-07-22T05:00:00.000Z"},
 {"_id":"room-other","t":"p","name":"kawai.t-times","lm":"2026-07-22T06:00:00.000Z"},
 {"_id":"room-noise","t":"p","name":"grafana-alert","lm":"2026-07-22T07:00:00.000Z"},
 {"_id":"room-dm","t":"d","usernames":["mori.a","hatagami.y"],"lm":"2026-07-22T08:00:00.000Z"},
 {"_id":"room-stale","t":"c","name":"old-channel","lm":"2026-07-10T00:00:00.000Z"},
 {"_id":"room-atall","t":"p","name":"general","lm":"2026-07-22T09:00:00.000Z"}
]}
EOF

# hist-own: 自分のtimes。自分の発言2件 + 他人の反応3件（うち2件は自分の最終発言から30分超）
# o9 は期間外(番兵)メッセージ。--to 2026-07-28 の latest がどんな値になっても
# （現在の latest 計算に日付跨ぎ処理のバグがあっても）確実に latest より後になる
# よう 2026-08-01 にしている。room_history が latest をクエリに渡し忘れると
# このメッセージが漏れて混入する。自分以外・@mori.aメンション無しの発言にして
# 採用判定・[発言N]カウントに影響を与えないようにしてある。
cat > "$TMP/fixtures/hist-own.json" <<'EOF'
{"messages":[
 {"_id":"o1","ts":"2026-07-22T00:42:00.000Z","u":{"username":"mori.a"},"msg":"APIの利用上限に達しました"},
 {"_id":"o2","ts":"2026-07-22T00:45:00.000Z","u":{"username":"mori.a"},"msg":"ログです"},
 {"_id":"o3","ts":"2026-07-22T00:55:00.000Z","u":{"username":"matsumoto.h"},"msg":"自動支払いが止まってました"},
 {"_id":"o4","ts":"2026-07-22T01:47:00.000Z","u":{"username":"matsumoto.h"},"msg":"向こうの対応が変わったってことですかね"},
 {"_id":"o5","ts":"2026-07-22T01:56:00.000Z","u":{"username":"tanaka.k"},"msg":"はい、自分も同じ認識です"},
 {"_id":"o9","ts":"2026-08-01T00:00:00.000Z","u":{"username":"matsumoto.h"},"msg":"OUT-OF-RANGE-SENTINEL"}
]}
EOF

# hist-other: 他人のtimes。スレッドを使わないフラット会話。
# 自分の発言1件(07:37)の前後30分に議論があり、遠く離れた雑談もある。
cat > "$TMP/fixtures/hist-other.json" <<'EOF'
{"messages":[
 {"_id":"t1","ts":"2026-07-22T00:35:00.000Z","u":{"username":"kawai.t"},"msg":"殺人的な暑さ過ぎる"},
 {"_id":"t2","ts":"2026-07-22T07:21:00.000Z","u":{"username":"kawai.t"},"msg":"MCP化したがこれでよかったか分からん"},
 {"_id":"t3","ts":"2026-07-22T07:34:00.000Z","u":{"username":"sato.m"},"msg":"モデルが賢くなったのでCLIでいい"},
 {"_id":"t4","ts":"2026-07-22T07:37:00.000Z","u":{"username":"mori.a"},"msg":"自分で作る分には全てskillでいいと思ってます"},
 {"_id":"t5","ts":"2026-07-22T07:40:00.000Z","u":{"username":"kawai.t"},"msg":"確かに認証の有無が一番大きい違いですね"},
 {"_id":"t6","ts":"2026-07-22T09:45:00.000Z","u":{"username":"kawai.t"},"msg":"欠伸が止まらん"}
]}
EOF

# hist-noise: 自動投稿のみ。自分の発言もメンションも無い。
cat > "$TMP/fixtures/hist-noise.json" <<'EOF'
{"messages":[
 {"_id":"n1","ts":"2026-07-22T07:00:00.000Z","u":{"username":"grafana"},"msg":"[FIRING] disk usage high"},
 {"_id":"n2","ts":"2026-07-22T07:01:00.000Z","u":{"username":"grafana"},"msg":"[RESOLVED] disk usage high"}
]}
EOF

# hist-dm: DM。自分の発言1件と相手の発言1件。
cat > "$TMP/fixtures/hist-dm.json" <<'EOF'
{"messages":[
 {"_id":"d1","ts":"2026-07-22T06:05:00.000Z","u":{"username":"hatagami.y"},"msg":"先日の件どうでしょうか"},
 {"_id":"d2","ts":"2026-07-22T06:06:00.000Z","u":{"username":"mori.a"},"msg":"今週中に対応します"}
]}
EOF

# hist-atall: @all のみを含むルーム。自分の発言も @mori.a メンションも無い。
# @all/@here は採用条件に含めない設計（実データ検証でノイズしか拾わなかったため）
# の回帰を防ぐための fixture。
cat > "$TMP/fixtures/hist-atall.json" <<'EOF'
{"messages":[
 {"_id":"a1","ts":"2026-07-22T09:00:00.000Z","u":{"username":"suzuki.n"},"msg":"@all 新人紹介です、よろしくお願いします"},
 {"_id":"a2","ts":"2026-07-22T09:05:00.000Z","u":{"username":"yamada.k"},"msg":"@all 誰か教えてください"}
]}
EOF

run_rc() {
  RC_ENV_FILE="$TMP/env.local" \
  RC_CURL="$TMP/bin/curl-stub.sh" \
  RC_FIXTURE_DIR="$TMP/fixtures" \
  RC_ME=mori.a \
  bash "$SCRIPT_DIR/rocketchat.sh" "$@"
}

assert_grep() {
  local desc="$1" pattern="$2" text="$3"
  if grep -q -- "$pattern" <<<"$text"; then echo "ok: $desc"
  else echo "NG: $desc → '$pattern' が出力に無い"; fails=$((fails + 1)); fi
}
assert_absent() {
  local desc="$1" pattern="$2" text="$3"
  if grep -q -- "$pattern" <<<"$text"; then
    echo "NG: $desc → '$pattern' が出力に含まれている"; fails=$((fails + 1))
  else echo "ok: $desc"; fi
}
assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then echo "ok: $desc"
  else echo "NG: $desc → want=$want got=$got"; fails=$((fails + 1)); fi
}

# ===== Task 1: ルーム列挙 =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --list-rooms)"
assert_grep   "期間内のルームが列挙される(own)"   "mori.a-times"  "$out"
assert_grep   "期間内のルームが列挙される(other)" "kawai.t-times" "$out"
assert_absent "期間外のルームは除外される"        "old-channel"   "$out"
assert_absent "DMは既定で除外される"              "room-dm"       "$out"

out="$(run_rc --from 2026-07-21 --to 2026-07-28 --list-rooms --include-dm)"
assert_grep "--include-dm でDMが含まれる" "room-dm" "$out"
# usernames: ["mori.a","hatagami.y"] から RC_ME=mori.a を除いた相手のみが name に出ること。
# 自分が誤って混入する（例: DM:mori.a,hatagami.y になる）バグを検出するための検証。
assert_grep   "DM名から自分(RC_ME)が除外され相手のみになる" "DM:hatagami.y"     "$out"
assert_absent "DM名に自分(RC_ME)が混入しない"               "DM:mori.a"         "$out"

# ===== .env.local 不在時は ERROR: を出して exit 1（既存 fetch-rocketchat.sh の慣習に合わせる） =====
rc=0
out="$(RC_ENV_FILE="$TMP/no-such-env.local" \
  RC_CURL="$TMP/bin/curl-stub.sh" \
  RC_FIXTURE_DIR="$TMP/fixtures" \
  RC_ME=mori.a \
  bash "$SCRIPT_DIR/rocketchat.sh" --from 2026-07-21 --to 2026-07-28 --list-rooms 2>&1)" || rc=$?
assert_eq   ".env.local不在時はexit 1"          "1"      "$rc"
assert_grep ".env.local不在時にERROR:で始まるメッセージが出る" "ERROR:" "$out"

# ===== Task 2: ルーム採用判定 =====
# rooms.json の先頭2件（room-curlfail, room-badjson）は障害注入用。
# stdout/stderr を両方捕捉し、後続ルームが正常処理されることも合わせて検証する。
out="$(run_rc --from 2026-07-21 --to 2026-07-28 2>"$TMP/err.log")"
err="$(cat "$TMP/err.log")"
assert_grep   "自分の発言があるルームは採用"     "mori.a-times"   "$out"
assert_grep   "自分の発言があるルームは採用(他人times)" "kawai.t-times" "$out"
assert_absent "自動投稿のみのルームは除外"       "grafana-alert"  "$out"
assert_grep   "採用理由がヘッダに出る"           "発言"           "$out"
# room_history が latest をクエリに渡し忘れる（または渡す値が壊れる）と
# 期間外の番兵メッセージ(2026-08-01)が漏れて混入する。range-aware スタブが
# oldest/latest を実際に見て絞り込むことでこれを検出する。
assert_absent "期間外(latest超)のメッセージは含まれない" "OUT-OF-RANGE-SENTINEL" "$out"
# @all/@here は採用条件に含めない設計の回帰防止。将来 men の判定に @all を
# 足す変異が入っても、このテストが無いと気付けない（実データ検証で
# @all はノイズしか拾わないことが分かっているため、意図的に除外している）。
assert_absent "@allのみのルームは採用されない" "general" "$out"
# 1ルームの不正レスポンス(非JSON)が全体を落とさず、そのルームだけスキップされ、
# 他のルームは正常に処理され続けることを確認する（brief要求の耐性の本質）。
# room-badjson は rooms.json の先頭付近にあるため、ここで後続の mori.a-times /
# kawai.t-times が採用されていることが「途中で処理が止まっていない」ことの証拠になる
# （末尾に置くと、中断していても手前のルームは既に出力済みで見分けが付かない）。
assert_absent "不正JSON応答のルームはスキップされる"     "broken-room"    "$out"
assert_grep   "他のルームは不正JSON応答の影響を受けない" "mori.a-times"   "$out"
# room_history 内で JSON 妥当性チェックが機能したことは render_room 側の
# try/except でも見た目上の出力（スキップ）は同じになってしまい stdout だけでは
# 判別できない。room_history 自身が出す stderr メッセージを直接検証する。
assert_grep   "不正JSON応答はstderrに記録される" "ルーム room-badjson の取得に失敗しスキップ" "$err"
# curl コマンド自体の失敗（`|| true` で受ける経路）でも同様にスキップされ、
# 後続ルームの処理が止まらないことを確認する。
assert_absent "curl失敗のルームはスキップされる"         "curl-fail-room" "$out"
assert_grep   "curl失敗はstderrに記録される" "ルーム room-curlfail の取得に失敗しスキップ" "$err"
assert_grep   "curl失敗後も他のルームは正常処理される"   "mori.a-times"   "$out"

# ===== 日付変換バグ修正の検証 =====
# oldest/latest の計算結果そのものを --print-window で直接検証する。
# JST 00:00 境界が正しく UTC に変換されているか（TZ=Asia/Tokyo + `-u` の
# 組み合わせが入力解釈まで UTC 化してしまう、`+1 day` が数値オフセットとして
# 誤解釈される、という2つの独立したバグが無いこと）を確認する。
window="$(run_rc --from 2026-07-21 --to 2026-07-28 --print-window)"
assert_eq "oldestがJST 00:00の正しいUTC変換になる" \
  "2026-07-20T15:00:00.000Z" "$(cut -f1 <<<"$window")"
assert_eq "latestが翌日JST 00:00の正しいUTC変換になる" \
  "2026-07-28T15:00:00.000Z" "$(cut -f2 <<<"$window")"

# 単日指定（from=to）でも範囲がちょうど24時間であることを確認する
window_1day="$(run_rc --from 2026-07-27 --to 2026-07-27 --print-window)"
hours="$(python3 -c '
import sys
from datetime import datetime
o, l = sys.argv[1].split("\t")
fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
d = (datetime.strptime(l, fmt) - datetime.strptime(o, fmt)).total_seconds() / 3600
print(d)
' "$window_1day")"
assert_eq "単日指定の範囲がちょうど24時間になる" "24.0" "$hours"

# 年跨ぎでも正しく変換されることを確認する
window_ny="$(run_rc --from 2026-01-01 --to 2026-01-01 --print-window)"
assert_eq "年跨ぎでもoldestが正しいUTC変換になる" \
  "2025-12-31T15:00:00.000Z" "$(cut -f1 <<<"$window_ny")"
assert_eq "年跨ぎでもlatestが正しいUTC変換になる" \
  "2026-01-01T15:00:00.000Z" "$(cut -f2 <<<"$window_ny")"

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi

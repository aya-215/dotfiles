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

# RC_CHANNEL 未設定版（設定ミスによる無言劣化を検証するための env）
cat > "$TMP/env-no-channel.local" <<'EOF'
RC_BASE_URL=http://rc.test
RC_TOKEN=dummy-token
RC_USER_ID=dummy-user
EOF

# RC_CHANNEL が設定されているが実際のルーム名と一致しない版（typo相当）。
# 「未設定」と「列挙されたが不一致」は render_room の全採用分岐がどちらも
# 発火しないという点で同じ劣化が起きるが、警告メッセージの分岐(elif)が
# 別なので個別に検証する。
cat > "$TMP/env-wrong-channel.local" <<'EOF'
RC_BASE_URL=http://rc.test
RC_TOKEN=dummy-token
RC_USER_ID=dummy-user
RC_CHANNEL=mori.a-timez
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
  # chat.getThreadMessages は oldest/latest を無視して全件返す実物のAPI仕様を
  # 模擬するため、range-awareフィルタを通さず fixture をそのまま返す
  # （expand_threads 側の自前期間フィルタを検証するために必要）。
  *chat.getThreadMessages*tmid=thr-ejikunabi-1*) cat "$RC_FIXTURE_DIR/thread-ejikunabi-1.json"; exit 0 ;;
  *chat.getThreadMessages*tmid=thr-ejikunabi-2*) cat "$RC_FIXTURE_DIR/thread-ejikunabi-2.json"; exit 0 ;;
  *chat.getThreadMessages*tmid=thr-ejikunabi-3*) cat "$RC_FIXTURE_DIR/thread-ejikunabi-3.json"; exit 0 ;;
  # thread-newline.json は expand_threads の \x1e 区切り修正（Task 4 Fix round 1）
  # を検証するため、pretty-print（改行入り）のまま生で返す必要がある。他の
  # chat.getThreadMessages 分岐と同じく cat で生返しする。
  *chat.getThreadMessages*tmid=nl-parent*) cat "$RC_FIXTURE_DIR/thread-newline.json"; exit 0 ;;
  # room-tfail: history 自体は正常。chat.getThreadMessages だけが失敗する
  # ケースを模擬する（expand_threads 内の rc_api 呼び出しの無音失敗対策の検証用）。
  *chat.getThreadMessages*tmid=tf-parent*) echo 'thread fetch failed' >&2; exit 7 ;;
  *roomId=room-own*)     fx="$RC_FIXTURE_DIR/hist-own.json" ;;
  *roomId=room-other*)   fx="$RC_FIXTURE_DIR/hist-other.json" ;;
  *roomId=room-noise*)   fx="$RC_FIXTURE_DIR/hist-noise.json" ;;
  *roomId=room-dm*)      fx="$RC_FIXTURE_DIR/hist-dm.json" ;;
  *roomId=room-atall*)   fx="$RC_FIXTURE_DIR/hist-atall.json" ;;
  *roomId=room-badts*)   fx="$RC_FIXTURE_DIR/hist-badts.json" ;;
  *roomId=room-thread*)  fx="$RC_FIXTURE_DIR/hist-thread.json" ;;
  *roomId=room-ejikunabi*) fx="$RC_FIXTURE_DIR/hist-ejikunabi.json" ;;
  *roomId=room-mention*) fx="$RC_FIXTURE_DIR/hist-mention.json" ;;
  # room-newline: history 応答自体が pretty-print（改行入り）のまま来るケースを
  # 模擬する。range-awareフィルタ（後段のpython）を通すと json.dumps で
  # compact化され改行が消えてしまうため、他の fixture と違い生 cat する
  # （expand_threads の $hist ⇔ $extra マージ側の \x1e 修正を検証するため）。
  *roomId=room-newline*) cat "$RC_FIXTURE_DIR/hist-newline.json"; exit 0 ;;
  *roomId=room-tfail*)   fx="$RC_FIXTURE_DIR/hist-tfail.json" ;;
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
# 9ルーム: 障害/構造注入用3件(curl失敗/不正JSON/ts不正メッセージ)を先頭に
# 配置し、途中で処理が中断されていないか（＝後続ルームが正常処理されるか）を
# 検出できるようにする。room-badts は room-own より前に置くことで、ts不正の
# ガードが無いと後続の mori.a-times/kawai.t-times が処理されず中断が
# 可視化できる設計にしてある。
# room-mention（優先度2: @meのみ）は room-badts の直後、他の優先度1ルーム群
# より前に置く。予算処理の優先度ソートは -s (stable) で同点時に入力順を
# 保つ設計のため、room-mention がもともと列挙順の最後にあると「優先度
# ソートを丸ごと外しても入力順どおり最後に来る」という空証明になり、
# ソートが実際に効いているかを検出できない（Task 5 のレビューで発覚）。
# 優先度1ルーム群の間に置くことで、ソートを外す変異テストで確実に
# 検出できるようにしている。
# 残りは既存通り: 自分のtimes / 他人のtimes / 自動投稿(ノイズ) / DM / @allのみ(ノイズ) / スレッド検証用
# lm は期間内(7/22)と期間外(7/10)を混ぜる
#
# room-newline/room-tfail は Task 4 Fix round 1 で追加。どちらも末尾（room-thread
# の後）に置く。Task 5 の budget=600 テストは優先度1グループの列挙順先頭2ルーム
# （quality-check-room + mori.a-times = 418B）で break する前提のため、この2つを
# 先頭寄りに挿入すると budget を消費してしまい `優先度の高いルームが残る` が
# 壊れる（自分の申し送り事項）。末尾に置くことで Task 5 のテストに影響しない。
cat > "$TMP/fixtures/rooms.json" <<'EOF'
{"update":[
 {"_id":"room-curlfail","t":"c","name":"curl-fail-room","lm":"2026-07-22T04:00:00.000Z"},
 {"_id":"room-badjson","t":"c","name":"broken-room","lm":"2026-07-22T10:00:00.000Z"},
 {"_id":"room-badts","t":"p","name":"quality-check-room","lm":"2026-07-22T11:00:00.000Z"},
 {"_id":"room-mention","t":"p","name":"mention-only-room","lm":"2026-07-22T13:00:00.000Z"},
 {"_id":"room-own","t":"p","name":"mori.a-times","lm":"2026-07-22T05:00:00.000Z"},
 {"_id":"room-other","t":"p","name":"kawai.t-times","lm":"2026-07-22T06:00:00.000Z"},
 {"_id":"room-noise","t":"p","name":"grafana-alert","lm":"2026-07-22T07:00:00.000Z"},
 {"_id":"room-dm","t":"d","usernames":["mori.a","hatagami.y"],"lm":"2026-07-22T08:00:00.000Z"},
 {"_id":"room-ejikunabi","t":"c","name":"e食なび","lm":"2026-07-22T05:05:00.000Z"},
 {"_id":"room-stale","t":"c","name":"old-channel","lm":"2026-07-10T00:00:00.000Z"},
 {"_id":"room-atall","t":"p","name":"general","lm":"2026-07-22T09:00:00.000Z"},
 {"_id":"room-thread","t":"p","name":"thread-room","lm":"2026-07-22T12:00:00.000Z"},
 {"_id":"room-newline","t":"c","name":"newline-safe-room","lm":"2026-07-22T14:00:00.000Z"},
 {"_id":"room-tfail","t":"c","name":"thread-fetch-fail-room","lm":"2026-07-22T15:00:00.000Z"}
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

# hist-badts: ts が不正な(パース不能な)メッセージを含むルーム。room-badts は
# t="p" で RC_CHANNEL(mori.a-times) と名前が違うため時間窓分岐を通る。
# b2 の ts="...T99:99:99.000Z" は文字列比較では oldest<=ts<=latest の範囲内に
# 収まる（curlスタブのrange-awareフィルタを通過する）が、fromisoformatは
# hour=99でValueErrorになる。b1(mori.aの正常発言)がありルーム自体は採用される。
cat > "$TMP/fixtures/hist-badts.json" <<'EOF'
{"messages":[
 {"_id":"b1","ts":"2026-07-22T03:00:00.000Z","u":{"username":"mori.a"},"msg":"badtsルームでの正常発言"},
 {"_id":"b2","ts":"2026-07-22T99:99:99.000Z","u":{"username":"kawai.t"},"msg":"TS-BROKEN-SENTINEL"}
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

# hist-dm: DM。自分の発言1件と相手の発言2件（うち1件はhist-ownと同様に
# 74分後で±30分窓の外）。窓外のd3が残ることでDM全採用（rtype=="d"分岐）を
# 直接検証できる。d1(06:05)はd2(06:06)から1分後で窓内に収まってしまうため、
# 全採用ロジックを削除しても既存assertは空証明のまま通ってしまっていた。
cat > "$TMP/fixtures/hist-dm.json" <<'EOF'
{"messages":[
 {"_id":"d1","ts":"2026-07-22T06:05:00.000Z","u":{"username":"hatagami.y"},"msg":"先日の件どうでしょうか"},
 {"_id":"d2","ts":"2026-07-22T06:06:00.000Z","u":{"username":"mori.a"},"msg":"今週中に対応します"},
 {"_id":"d3","ts":"2026-07-22T07:20:00.000Z","u":{"username":"hatagami.y"},"msg":"承知しました、では来週改めて確認します"}
]}
EOF

# hist-ejikunabi: スレッドを持つルーム（Task 4: スレッド展開）。
# history はスレッド返信を一部しか返さない実物のAPI挙動を模擬する。
# room-ejikunabi/hist-ejikunabi.json/thread-ejikunabi-1.json という識別子は
# Task 3 fix round 1 で追加済みの room-thread/hist-thread.json（tmid/tcountの
# 集合演算検証。目的が異なる）と衝突しないよう意図的にリネームしてある。
# thr-ejikunabi-2/3 は tcount 由来・tmid 由来のスレッドID収集がそれぞれ
# 単独でも機能することを検証するための追加(ブリーフ範囲外の品質保証)。
# thr-ejikunabi-1 は tcount と tmid の両方から同じIDが得られてしまうため、
# どちらか一方を無効化する変異では検出できない（両者が同じ結果を導く空証明）
# ことが変異テストで判明したため追加した。
#   - thr-ejikunabi-2: tcount のみが手がかり。history内に tmid で指す返信が
#     無い（tcount経由でしか thread ID が収集できない）。ejk2-reply は
#     mori.a の発言なので render_room 自身の seed にもなり得るが、
#     tcount収集が無いと expand_threads が chat.getThreadMessages を
#     一切呼ばず ejk2-reply 自体が history に無いため出力に出ない。
#   - thr-ejikunabi-3: tmid のみが手がかり。ejk3-reply(mori.a, tmid指定)が
#     historyにあるが、親 thr-ejikunabi-3 自体は history に存在しない
#     （tcountを持つメッセージがどこにも無い）。
cat > "$TMP/fixtures/hist-ejikunabi.json" <<'EOF'
{"messages":[
 {"_id":"thr-ejikunabi-1","ts":"2026-07-22T00:30:00.000Z","u":{"username":"other.p"},"msg":"打ち合わせお願いします","tcount":3},
 {"_id":"th-a","ts":"2026-07-22T00:40:00.000Z","u":{"username":"mori.a"},"msg":"資料いただけますか","tmid":"thr-ejikunabi-1"},
 {"_id":"thr-ejikunabi-2","ts":"2026-07-22T06:00:00.000Z","u":{"username":"other.p"},"msg":"別スレッドの親","tcount":2},
 {"_id":"ejk3-reply","ts":"2026-07-22T10:00:00.000Z","u":{"username":"mori.a"},"msg":"ejk3への返信","tmid":"thr-ejikunabi-3"}
]}
EOF

# thread-ejikunabi-2: tcount 由来でのみ発見できるスレッド。親(thr-ejikunabi-2)
# 自体は mori.a の発言ではないが、返信 ejk2-reply が mori.a の発言のため
# render_room 自身の seed になり、tids に加わって残る。tcount収集が無いと
# chat.getThreadMessages 自体が呼ばれず ejk2-reply は出力に出ない。
cat > "$TMP/fixtures/thread-ejikunabi-2.json" <<'EOF'
{"messages":[
 {"_id":"thr-ejikunabi-2","ts":"2026-07-22T06:00:00.000Z","u":{"username":"other.p"},"msg":"別スレッドの親","tcount":2},
 {"_id":"ejk2-reply","ts":"2026-07-22T11:00:00.000Z","u":{"username":"mori.a"},"msg":"THREAD2-TCOUNT-ONLY-SENTINEL","tmid":"thr-ejikunabi-2"}
]}
EOF

# thread-ejikunabi-3: tmid 由来でのみ発見できるスレッド。親(thr-ejikunabi-3)は
# history に存在しない（tcountを持つメッセージがどこにも無い）ため、
# tmid収集が無いと chat.getThreadMessages 自体が呼ばれず兄弟返信が出ない。
cat > "$TMP/fixtures/thread-ejikunabi-3.json" <<'EOF'
{"messages":[
 {"_id":"ejk3-reply","ts":"2026-07-22T10:00:00.000Z","u":{"username":"mori.a"},"msg":"ejk3への返信","tmid":"thr-ejikunabi-3"},
 {"_id":"ejk3-sibling","ts":"2026-07-22T13:00:00.000Z","u":{"username":"other.p"},"msg":"THREAD3-TMID-ONLY-SENTINEL","tmid":"thr-ejikunabi-3"}
]}
EOF

# thread-ejikunabi-1: 同スレッドの全返信。
# history に無い th-b / th-c と、対象期間外(7/10)の th-old を含む。
# chat.getThreadMessages は oldest/latest を無視して全返信を返すため、
# 期間外が落ちることを検証する必要がある。
cat > "$TMP/fixtures/thread-ejikunabi-1.json" <<'EOF'
{"messages":[
 {"_id":"th-old","ts":"2026-07-10T00:00:00.000Z","u":{"username":"other.p"},"msg":"ずっと前の日程調整です","tmid":"thr-ejikunabi-1"},
 {"_id":"th-a","ts":"2026-07-22T00:40:00.000Z","u":{"username":"mori.a"},"msg":"資料いただけますか","tmid":"thr-ejikunabi-1"},
 {"_id":"th-b","ts":"2026-07-22T05:00:00.000Z","u":{"username":"other.p"},"msg":"これですかね（リンク）","tmid":"thr-ejikunabi-1"},
 {"_id":"th-c","ts":"2026-07-22T05:05:00.000Z","u":{"username":"mori.a"},"msg":"そちらです！助かります","tmid":"thr-ejikunabi-1"}
]}
EOF

# hist-thread: スレッド(tmid)の親・兄弟返信が時間窓の外でも残ることを検証する。
# render_room の tids/keep 集合演算の両半分を別々に踏む:
#   - 子/兄弟: シード th1(tmid無し, 07:00) に対し th2 が tmid=th1._id を持ち
#     103分後(08:43)。tmid in tids で拾われる。
#   - 親: シード th3(mori.aの発言, tmid="th-parent"を持つ)自体が返信であり、
#     tids には親のID("th-parent")が入る。親メッセージ th-parent 自体が
#     104分前(05:16)に投稿されている。_id in tids で拾われる。
# th4は窓外・スレッド無関係の雑談で、tids/keep どちらにも該当せず落ちるはず
# （169-171行の tids/keep 初期化を削除する変異では逆に残ってしまう対照点）。
cat > "$TMP/fixtures/hist-thread.json" <<'EOF'
{"messages":[
 {"_id":"th-parent","ts":"2026-07-22T05:16:00.000Z","u":{"username":"suzuki.n"},"msg":"THREAD-PARENT-FAR"},
 {"_id":"th1","ts":"2026-07-22T07:00:00.000Z","u":{"username":"mori.a"},"msg":"seed発言(tmid無し)"},
 {"_id":"th2","ts":"2026-07-22T08:43:00.000Z","tmid":"th1","u":{"username":"yamada.k"},"msg":"THREAD-CHILD-FAR"},
 {"_id":"th3","ts":"2026-07-22T07:02:00.000Z","tmid":"th-parent","u":{"username":"mori.a"},"msg":"親スレッドへの返信seed"},
 {"_id":"th4","ts":"2026-07-22T12:00:00.000Z","u":{"username":"kawai.t"},"msg":"THREAD-UNRELATED-NOISE"}
]}
EOF

# ===== Task 4 Fix round 1 =====
# hist-newline / thread-newline: expand_threads の $hist <-> $extra マージが
# 改行区切り(printf '%s\n%s')だと、応答JSONが pretty-print（改行入り）で
# 来た場合に split("\n", 1) がJSONの途中で分断されパース失敗 -> 無音で
# メッセージ全消失することを検証する。curl-stub.sh 側で room-newline と
# chat.getThreadMessages(tmid=nl-parent) の両方を「生 cat」にしてあり、
# range-awareフィルタ(python json.dumps によるcompact化)を経由させない
# ことで pretty-print のまま expand_threads に渡している。
# nl-parent は tcount を持つ親メッセージ。nl-reply(NEWLINE-SAFE-SENTINEL)は
# history には無く、chat.getThreadMessages 経由でのみ得られる（thread側の
# マージ = extra 蓄積ループの split 箇所を踏む）。nl-parent 自身の本文も
# history 側マージ（$hist <-> $extra の最終結合）を踏む。
cat > "$TMP/fixtures/hist-newline.json" <<'EOF'
{
  "messages": [
    {
      "_id": "nl-parent",
      "ts": "2026-07-22T02:00:00.000Z",
      "u": {
        "username": "mori.a"
      },
      "msg": "NEWLINE-PARENT-SENTINEL",
      "tcount": 1
    }
  ]
}
EOF

cat > "$TMP/fixtures/thread-newline.json" <<'EOF'
{
  "messages": [
    {
      "_id": "nl-parent",
      "ts": "2026-07-22T02:00:00.000Z",
      "u": {
        "username": "mori.a"
      },
      "msg": "NEWLINE-PARENT-SENTINEL",
      "tcount": 1
    },
    {
      "_id": "nl-reply",
      "ts": "2026-07-22T02:05:00.000Z",
      "u": {
        "username": "other.p"
      },
      "msg": "NEWLINE-SAFE-SENTINEL",
      "tmid": "nl-parent"
    }
  ]
}
EOF

# hist-tfail: history 応答自体は正常（compact JSON、通常どおり range-aware
# フィルタを経由）。tf-parent が tcount を持つため expand_threads が
# chat.getThreadMessages(tmid=tf-parent) を呼ぶが、curl-stub.sh 側でこの
# tmid だけ意図的に exit 7 で失敗させてある（room_history の room-curlfail
# と同じ考え方）。rc_api 呼び出しに `|| true` と JSON妥当性チェック +
# stderr警告が無いと、この失敗が無音になり、tf-parent 自身の採用判定にも
# 気づかれない劣化が起きる。
cat > "$TMP/fixtures/hist-tfail.json" <<'EOF'
{"messages":[
 {"_id":"tf-parent","ts":"2026-07-22T03:00:00.000Z","u":{"username":"mori.a"},"msg":"THREAD-FETCH-FAIL-PARENT","tcount":1}
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

# hist-mention: mori.a自身の発言は無いが @mori.a メンションのみで採用される
# ルーム（優先度2: [@meN] のみ）。Task 5 の予算処理で優先度ソートを検証する
# には prio=1 と prio=2 の両方が必要だが、既存fixtureは採用される全ルームに
# mori.aの発言が含まれておりどれも prio=1 になってしまう（優先度ソートが
# 空証明になる）ため追加した。
cat > "$TMP/fixtures/hist-mention.json" <<'EOF'
{"messages":[
 {"_id":"mtA","ts":"2026-07-22T14:00:00.000Z","u":{"username":"suzuki.n"},"msg":"@mori.a MENTION-ONLY-SENTINEL 確認お願いします"},
 {"_id":"mtB","ts":"2026-07-22T14:05:00.000Z","u":{"username":"yamada.k"},"msg":"確かに気になりますね"}
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

# ===== Task 3: メッセージ絞り込み =====
# stderr も捕捉する（room-curlfail/room-badjson のスキップメッセージが
# 標準出力に混ざらないようにするのと、RC_CHANNEL 警告の検証に使うため）。
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm 2>"$TMP/err3.log")"
err3="$(cat "$TMP/err3.log")"

# (a) 自分のtimesは全採用 → 自分の最終発言(00:45)から62分後の議論も残る
assert_grep "自分のtimesは尻尾が切れない(01:47)" "向こうの対応が変わった" "$out"
assert_grep "自分のtimesは尻尾が切れない(01:56)" "同じ認識です"           "$out"

# (b) 他人のtimesは時間窓で文脈を拾う（自分の発言07:37の前後30分）
assert_grep "起点前の問いが残る(07:21)"   "MCP化したがこれでよかったか" "$out"
assert_grep "起点前の議論が残る(07:34)"   "モデルが賢くなったので"       "$out"
assert_grep "起点後の反応が残る(07:40)"   "認証の有無が一番大きい違い"   "$out"

# (b) 窓外の雑談は落ちる
assert_absent "窓外の雑談は落ちる(00:35)" "殺人的な暑さ" "$out"
assert_absent "窓外の雑談は落ちる(09:45)" "欠伸が止まらん" "$out"

# (a) DMは全採用 → 相手の発言も残る
assert_grep "DMは相手の発言も残る" "先日の件どうでしょうか" "$out"
# d3(07:20)はd2(06:06)から74分後で±30分窓の外にあるが、DM全採用なので残るはず。
# これが無いと「DMは相手の発言も残る」assertは d1 が窓内に収まる偶然で
# 空証明のまま通ってしまう（d1は06:05でd2の1分前のため）。
assert_grep "DMは窓外の発言も全採用で残る(07:20)" "承知しました、では来週改めて確認します" "$out"

# (c) ts が不正なメッセージが1件あっても、そのメッセージだけが除外され、
# ルーム自体の処理・後続ルームの処理は継続する（Task 2 の「1ルームの失敗が
# 全体を落とさない」耐性を、render_room 側の新しい失敗モード(ts例外)からも
# 守れているかの検証）。room-badts は rooms.json で room-own より前にあるため、
# ここで mori.a-times/kawai.t-times が採用されていることが「中断していない」
# ことの直接的な証拠になる。
assert_absent "ts不正メッセージそのものは出力に含まれない" "TS-BROKEN-SENTINEL" "$out"
assert_grep   "ts不正メッセージがあってもルームの他の発言は残る" "badtsルームでの正常発言" "$out"
assert_grep   "ts不正メッセージ以降のルームも正常処理される(own)" "mori.a-times"   "$out"
assert_grep   "ts不正メッセージ以降のルームも正常処理される(other)" "kawai.t-times" "$out"
assert_grep   "ts不正メッセージの除外がstderrに記録される" "ts 不正メッセージ" "$err3"

# (d) スレッド(tmid)の親・兄弟返信は時間窓の外でも残る（brief第2段階(b)の
# 「スレッドの親と兄弟返信」の検証。既存fixtureにはtmid付きメッセージが
# 無かったため、tids/keep集合演算(169-171行)が実質未検証だった）。
assert_grep   "スレッド子/兄弟返信は窓外でも残る" "THREAD-CHILD-FAR"  "$out"
assert_grep   "スレッド親メッセージは窓外でも残る" "THREAD-PARENT-FAR" "$out"
assert_absent "スレッドと無関係な窓外雑談は落ちる" "THREAD-UNRELATED-NOISE" "$out"

# 正常運用（RC_CHANNEL が実際のルーム名と一致している）では WARN が出ないこと。
# mytimes_seen の永続化は process substitution（`done < <(...)`）が現在シェルで
# 実行されることに依存しており、将来 `list_active_rooms | while ...`（パイプ=
# サブシェル）に書き換えると mytimes_seen がループ外で0に戻り正常時でも誤発火
# する回帰経路がある。err3 を見ないと気付けないため明示的に検証する。
assert_absent "正常時はWARNが出ない" "WARN" "$err3"

# ===== RC_CHANNEL 未設定・不一致時の無言劣化防止 =====
# RC_CHANNEL が未設定だと mytimes が空になり、render_room の全採用分岐
# (rtype == "d" or (mytimes and name == mytimes)) が発火せず、自分のtimesが
# 黙って時間窓の対象に落ちる。これはユーザーが手で見つけた「尻尾が切れる」
# 欠陥が設定ミスで再発する経路であり、しかも無言なので気付けない。
# stderrに警告を出す実装にし、(a)警告そのもの (b)実際に尻尾が切れて劣化する
# ことの両方を検証する。(b)の方が本質的に重要（警告があっても劣化していない
# ことの確認にはならないため）。
out_nochannel="$(RC_ENV_FILE="$TMP/env-no-channel.local" \
  RC_CURL="$TMP/bin/curl-stub.sh" \
  RC_FIXTURE_DIR="$TMP/fixtures" \
  RC_ME=mori.a \
  bash "$SCRIPT_DIR/rocketchat.sh" --from 2026-07-21 --to 2026-07-28 --include-dm \
  2>"$TMP/err-nochannel.log")"
err_nochannel="$(cat "$TMP/err-nochannel.log")"
assert_grep   "RC_CHANNEL未設定時にWARNがstderrに出る" "WARN" "$err_nochannel"
assert_absent "RC_CHANNEL未設定だと自分のtimesの尻尾が黙って切れる(劣化の実証)" \
  "向こうの対応が変わった" "$out_nochannel"

# RC_CHANNEL が設定されているが実際のルーム名と一致しない場合（typo等）。
# メインループの elif 分岐（未設定ではなく「列挙されたが不一致」）を検証する。
out_wrongchannel="$(RC_ENV_FILE="$TMP/env-wrong-channel.local" \
  RC_CURL="$TMP/bin/curl-stub.sh" \
  RC_FIXTURE_DIR="$TMP/fixtures" \
  RC_ME=mori.a \
  bash "$SCRIPT_DIR/rocketchat.sh" --from 2026-07-21 --to 2026-07-28 --include-dm \
  2>"$TMP/err-wrongchannel.log")"
err_wrongchannel="$(cat "$TMP/err-wrongchannel.log")"
assert_grep   "RC_CHANNEL不一致時にWARNがstderrに出る(elif分岐)" "WARN" "$err_wrongchannel"
assert_absent "RC_CHANNEL不一致でも自分のtimesの尻尾が黙って切れる(劣化の実証)" \
  "向こうの対応が変わった" "$out_wrongchannel"

# ===== Task 4: スレッド展開 =====
out="$(run_rc --from 2026-07-21 --to 2026-07-28)"
assert_grep "history にあるスレッド返信は出る"   "資料いただけますか"     "$out"
assert_grep "history に無い返信も展開される(th-b)" "これですかね"         "$out"
assert_grep "history に無い返信も展開される(th-c)" "そちらです"           "$out"
assert_grep "スレッド親も出る"                   "打ち合わせお願いします" "$out"
# chat.getThreadMessages は期間指定を無視するため自前フィルタが必要
assert_absent "対象期間外のスレッド返信は落ちる" "ずっと前の日程調整" "$out"

# 日次実行でも期間外が混入しないこと（生きているスレッドの全履歴混入の回帰）
out_day="$(run_rc --from 2026-07-22 --to 2026-07-22)"
assert_absent "日次実行でも期間外は混入しない" "ずっと前の日程調整" "$out_day"

# thr-ejikunabi-1 は tcount と tmid の両方から同じスレッドIDが得られてしまう
# ため、どちらか一方の収集ロジックだけを無効化する変異では検出できない
# （もう片方が同じ結果を導いてしまう空証明）。tcount専用・tmid専用の
# スレッドをそれぞれ用意して、両方の収集経路を独立に検証する。
assert_grep "tcount由来のみで発見できるスレッドの返信が展開される" "THREAD2-TCOUNT-ONLY-SENTINEL" "$out"
assert_grep "tmid由来のみで発見できるスレッドの返信が展開される"   "THREAD3-TMID-ONLY-SENTINEL"    "$out"

# history と chat.getThreadMessages の両方に含まれるメッセージ(th-a)が
# _id による重複排除で1回だけ出力されること。assert_grep は1件でも2件でも
# 通ってしまうため、出現回数を数える。
assert_eq "historyとthreadの重複メッセージは1回だけ出力される" "1" "$(grep -c '資料いただけますか' <<<"$out")"

# ===== Task 5: 予算処理 =====
# 全ルーム分では収まらない小さな予算を与える。
# --budget はバイト数基準（fire-daily-review.sh の ${#var} は LANG 未設定の
# cron環境でバイト数になるため、rocketchat.sh 側もバイト数に合わせる。詳細は
# task-5-report.md 参照）。
#
# budget=400 だと、優先度1グループ内の先頭2ルームだけで
# quality-check-room(98B) + mori.a-times(418B累計) = 418B が既に400を
# 超えてしまい、「mori.a-times が残る」こと自体が算術的に成立しない
# （優先度1グループ内の順序は list_active_rooms の列挙順に従うだけで、
# spec は同一優先度内の順序を規定していない。個々のルームサイズと
# fixture の並び順から budget を逆算する必要がある）。
# quality-check-room + mori.a-times の2ルームがちょうど収まり、
# 3ルーム目(kawai.t-times)以降が確実に超過する 600 を使う。
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm --budget 600)"
len="$(printf '%s' "$out" | wc -c)"
if [ "$len" -le 800 ]; then   # 省略マーカー分の余裕を見て 800
  echo "ok: 予算内に収まる（${len}バイト）"
else
  echo "NG: 予算超過（${len}バイト）"; fails=$((fails + 1))
fi
assert_grep "省略マーカーが出る" "容量制限のため" "$out"
# 空証明の修正: 省略マーカー自体に落ちたルーム名が列挙されるため、
# "mori.a-times" という文字列だけを assert_grep すると、実際には
# mori.a-times が「落ちた側」としてマーカーに載っているだけでも一致して
# しまう。ヘッダの出現有無で判定する（ヘッダはマーカー内には出ない）。
assert_grep "優先度の高いルームが残る" "===== mori.a-times \[" "$out"
# 優先度2(mention-only-room, @meのみ)は優先度1のルーム群より先に落ちるはず。
# 全ルームがprio=1だと優先度ソート自体が何も並び替えないため検出力が無い
# （既存fixtureの採用ルームは全部mori.aの発言を含みprio=1になってしまう）。
# hist-mention.json(prio=2)を追加してこの空証明を解消した。
# さらに room-mention を rooms.json の優先度1グループの間（先頭寄り）に
# 配置してあるため、優先度ソートを丸ごと外す変異では mention-only-room が
# 本文に残ってしまい（budget=600だと 98+167=265 で採用される）、この
# assert が正しく落ちる。ソートが末尾のルームを末尾に残すだけの空証明を
# 避けている。
assert_absent "優先度の低いルームは先に落ちる" "===== mention-only-room \[" "$out"
assert_grep   "優先度の低いルームが省略マーカーに載る" "mention-only-room" "$out"

# 予算未指定なら省略マーカーは出ない
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm)"
assert_absent "予算未指定なら省略マーカーなし" "容量制限のため" "$out"

# ===== Task 4 Fix round 1: expand_threads の改行耐性・スレッド取得失敗の可視化 =====
# room-newline/room-tfail は budget を絡めず単体で検証したいので、budgetなしで
# 再実行する。stderr も別途捕捉し直す（"スレッド取得失敗がstderrに記録される"の
# 検証に必要。直近の $err は budget=600 実行時点のログのままで tf-parent の
# 警告を含まないため、ここで上書きしないと空証明になる）。
out="$(run_rc --from 2026-07-21 --to 2026-07-28 --include-dm 2>"$TMP/err-task4fix.log")"
err="$(cat "$TMP/err-task4fix.log")"
assert_grep "改行入りJSONでもhistory由来メッセージが残る"   "NEWLINE-PARENT-SENTINEL" "$out"
assert_grep "改行入りJSONでもthread由来メッセージが展開される" "NEWLINE-SAFE-SENTINEL"   "$out"
assert_grep "スレッド取得失敗でもhistory由来メッセージは残る" "THREAD-FETCH-FAIL-PARENT" "$out"
assert_grep "スレッド取得失敗がstderrに記録される" "スレッド tf-parent の取得に失敗しスキップ" "$err"

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi

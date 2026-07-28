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
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl-stub.sh" <<'EOF'
#!/bin/bash
set -u
url="${!#}"   # 最後の引数が URL
case "$url" in
  *rooms.get*)      cat "$RC_FIXTURE_DIR/rooms.json" ;;
  *roomId=room-own*)  cat "$RC_FIXTURE_DIR/hist-own.json" ;;
  *roomId=room-other*) cat "$RC_FIXTURE_DIR/hist-other.json" ;;
  *roomId=room-noise*) cat "$RC_FIXTURE_DIR/hist-noise.json" ;;
  *roomId=room-dm*)   cat "$RC_FIXTURE_DIR/hist-dm.json" ;;
  *)                echo '{"messages":[]}' ;;
esac
EOF
chmod +x "$TMP/bin/curl-stub.sh"

# ---- fixture ----
mkdir -p "$TMP/fixtures"
# 4ルーム: 自分のtimes / 他人のtimes / 自動投稿(ノイズ) / DM
# lm は期間内(7/22)と期間外(7/10)を混ぜる
cat > "$TMP/fixtures/rooms.json" <<'EOF'
{"update":[
 {"_id":"room-own","t":"p","name":"mori.a-times","lm":"2026-07-22T05:00:00.000Z"},
 {"_id":"room-other","t":"p","name":"kawai.t-times","lm":"2026-07-22T06:00:00.000Z"},
 {"_id":"room-noise","t":"p","name":"grafana-alert","lm":"2026-07-22T07:00:00.000Z"},
 {"_id":"room-dm","t":"d","usernames":["mori.a","hatagami.y"],"lm":"2026-07-22T08:00:00.000Z"},
 {"_id":"room-stale","t":"c","name":"old-channel","lm":"2026-07-10T00:00:00.000Z"}
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

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi

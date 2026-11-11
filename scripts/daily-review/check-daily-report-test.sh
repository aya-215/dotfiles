#!/bin/bash
# check-daily-report-test.sh - check-daily-report.sh の動作確認テスト
# 使用方法: bash scripts/daily-review/check-daily-report-test.sh （全部 ok なら ALL OK で exit 0）
# claude・トースト・GitHub はスタブに差し替える（ISSUE_BODY_FILE で日報を渡す）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
readonly DATE="2026-11-09"

# スタブ claude: 呼び出し回数と stdin を記録し、out.<n>（無ければ out）を返す
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF2'
#!/bin/bash
set -u
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/calls"
printf '%s\n' "$@" > "$STUB_DIR/args.$n"
cat > "$STUB_DIR/prompt.$n"
if [ -f "$STUB_DIR/out.$n" ]; then cat "$STUB_DIR/out.$n"; else cat "$STUB_DIR/out"; fi
EOF2
# スタブ toast: 呼ばれたら stdin を toast に追記
cat > "$TMP/bin/toast" <<'EOF2'
#!/bin/bash
cat >> "$STUB_DIR/toast"
EOF2
chmod +x "$TMP/bin/claude" "$TMP/bin/toast"

# check <ok|ng> <説明> <条件コマンド...>
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}

# setup_case <name> <summary_bullets: yes|no> <payload: yes|no> — ケース用ディレクトリを作る
setup_case() {
  local c="$TMP/$1"
  mkdir -p "$c/stub" "$c/slices/$DATE"
  if [ "$3" = yes ]; then printf '【対象日】%s\n【区切り】a 〜 b\n' "$DATE" > "$c/slices/$DATE/payload.txt"; fi
  {
    echo "# 日報"; echo "## 📝 サマリー"
    if [ "$2" = yes ]; then echo "- Work: 何かをした"; else echo ""; fi
    echo "## 次の節"; echo "- 無関係"
  } > "$c/body.md"
}

# run_check <name> — 終了コードを $TMP/<name>/rc に残す
run_check() {
  local c="$TMP/$1"
  set +e
  CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$c/stub" TOAST_CMD="$TMP/bin/toast" \
  SLICES_ROOT="$c/slices" CHECK_LOG_FILE="$c/check.log" ISSUE_BODY_FILE="$c/body.md" \
    bash "$SCRIPT_DIR/check-daily-report.sh" --date "$DATE" --no-wait >"$c/stdout" 2>"$c/stderr"
  echo $? > "$c/rc"
  set -e
}

calls() { cat "$1/stub/calls" 2>/dev/null || echo 0; }
jq_has() { jq -e "$2" "$1/slices/$DATE/check.json"; }

# ---- ケース1: 軽微・低だけ → 通知なし ----
setup_case minor yes yes
echo '{"missing":[{"text":"a","severity":"軽微"}],"unsupported":[{"text":"b","confidence":"低"}],"misclassified":[],"format":[]}' > "$TMP/minor/stub/out"
run_check minor
check "minor: exit 0" test "$(cat "$TMP/minor/rc")" = 0
check "minor: notify=false" jq_has "$TMP/minor" '.notify == false and .status == "ok"'
check "minor: トースト呼ばれない" test ! -e "$TMP/minor/stub/toast"
check "minor: ログ1行の形" grep -qE "^\[[^]]+\] $DATE status=ok missing=1\(重大0\) unsupported=1\(高0\) misclassified=0 notify=false$" "$TMP/minor/check.log"
check "minor: モデル指定" grep -qx 'claude-opus-5' "$TMP/minor/stub/args.1"
check "minor: ツール無効化" grep -qx -- '--tools' "$TMP/minor/stub/args.1"
check "minor: プロンプトにpayloadとサマリーが入る" grep -q '何かをした' "$TMP/minor/stub/prompt.1"
check "minor: 次の節は入らない" bash -c "! grep -q '無関係' '$TMP/minor/stub/prompt.1'"

# ---- ケース2: 重大 missing → 通知 ----
setup_case major yes yes
echo '```json
{"missing":[{"text":"大事","severity":"重大"}],"unsupported":[],"misclassified":[],"format":[]}
```' > "$TMP/major/stub/out"
run_check major
check "major: notify=true" jq_has "$TMP/major" '.notify == true'
check "major: トースト呼ばれタイトルに対象日" grep -q "$DATE" "$TMP/major/stub/toast"
check "major: ログ notify=true" grep -q "missing=1(重大1).*notify=true" "$TMP/major/check.log"

# ---- ケース2b: unsupported 高 → 通知 ----
setup_case unsup yes yes
echo '{"missing":[],"unsupported":[{"text":"x","confidence":"高"}],"misclassified":[],"format":[]}' > "$TMP/unsup/stub/out"
run_check unsup
check "unsup: notify=true" jq_has "$TMP/unsup" '.notify == true'

# ---- ケース3: JSON でない×2 → check_failed ----
setup_case bad yes yes
echo 'これはJSONではない' > "$TMP/bad/stub/out"
run_check bad
check "bad: exit 0" test "$(cat "$TMP/bad/rc")" = 0
check "bad: claude 2回" test "$(calls "$TMP/bad")" = 2
check "bad: status=check_failed" jq_has "$TMP/bad" '.status == "check_failed"'
check "bad: トースト呼ばれる" test -s "$TMP/bad/stub/toast"

# ---- ケース3b: 1回目だけ不正 → やり直しで ok ----
setup_case retry yes yes
echo 'ぶっ壊れ' > "$TMP/retry/stub/out.1"
echo '{"missing":[],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/retry/stub/out.2"
run_check retry
check "retry: status=ok" jq_has "$TMP/retry" '.status == "ok" and .notify == false'

# ---- ケース4: サマリー空 → report_missing ----
setup_case empty no yes
echo '{}' > "$TMP/empty/stub/out"
run_check empty
check "empty: claude 呼ばれない" test "$(calls "$TMP/empty")" = 0
check "empty: status=report_missing" jq_has "$TMP/empty" '.status == "report_missing"'
check "empty: トースト呼ばれる" test -s "$TMP/empty/stub/toast"
check "empty: exit 0" test "$(cat "$TMP/empty/rc")" = 0

# ---- ケース5: payload 無し → check_failed ----
setup_case nopayload yes no
echo '{}' > "$TMP/nopayload/stub/out"
run_check nopayload
check "nopayload: claude 呼ばれない" test "$(calls "$TMP/nopayload")" = 0
check "nopayload: status=check_failed" jq_has "$TMP/nopayload" '.status == "check_failed"'
check "nopayload: トースト呼ばれる" test -s "$TMP/nopayload/stub/toast"

# ---- ケース5b: payload 無し + skipped マーカー → skipped（通知なし・claude なし） ----
setup_case skipped yes no
: > "$TMP/skipped/slices/$DATE/skipped"
echo '{}' > "$TMP/skipped/stub/out"
run_check skipped
check "skipped: exit 0" test "$(cat "$TMP/skipped/rc")" = 0
check "skipped: claude 呼ばれない" test "$(calls "$TMP/skipped")" = 0
check "skipped: トーストなし" test ! -s "$TMP/skipped/stub/toast"
check "skipped: ログに status=skipped" grep -q "status=skipped" "$TMP/skipped/check.log"
check "skipped: notify=false" grep -q "notify=false" "$TMP/skipped/check.log"

# ---- ケース6: severity/confidence の typo は不正扱い → check_failed ----
setup_case typo yes yes
echo '{"missing":[{"text":"x","severity":"じゅうだい"}],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/typo/stub/out"
run_check typo
check "typo: claude 2回(やり直し)" test "$(calls "$TMP/typo")" = 2
check "typo: status=check_failed" jq_has "$TMP/typo" '.status == "check_failed"'
setup_case typo2 yes yes
echo '{"missing":[],"unsupported":[{"text":"x","confidence":"高い"}],"misclassified":[],"format":[]}' > "$TMP/typo2/stub/out"
run_check typo2
check "typo2: status=check_failed" jq_has "$TMP/typo2" '.status == "check_failed"'

# ---- ケース7: 待ちループ（空のまま規定回数で report_missing） ----
setup_case wait no yes
echo '{}' > "$TMP/wait/stub/out"
c="$TMP/wait"
CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$c/stub" TOAST_CMD="$TMP/bin/toast" SLICES_ROOT="$c/slices" CHECK_LOG_FILE="$c/check.log" ISSUE_BODY_FILE="$c/body.md" CHECK_WAIT_SEC=0 CHECK_WAIT_MAX=3   bash "$SCRIPT_DIR/check-daily-report.sh" --date "$DATE" >/dev/null 2>&1
check "wait: report_missing（3回確認）" jq_has "$c" '.status == "report_missing" and (.message | contains("3回"))'

# ---- ケース8: 想定外の失敗（check.json が書けない）でも exit 0 + check_failed ログ ----
setup_case crash yes yes
echo '{"missing":[],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/crash/stub/out"
chmod a-w "$TMP/crash/slices/$DATE"
run_check crash
chmod u+w "$TMP/crash/slices/$DATE"
check "crash: exit 0" test "$(cat "$TMP/crash/rc")" = 0
check "crash: status=check_failed がログに残る" grep -q "status=check_failed" "$TMP/crash/check.log"
check "crash: トースト呼ばれる" test -s "$TMP/crash/stub/toast"

# ---- ケース9: cron 相当の最小環境（PATH に jq/gh が無い）でも完走する ----
setup_case cron yes yes
echo '{"missing":[],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/cron/stub/out"
c="$TMP/cron"
mkdir -p "$c/home"
env -i HOME="$c/home" PATH=/usr/bin:/bin NIX_PROFILE_BIN="$(dirname "$(command -v jq)")" \
  CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$c/stub" TOAST_CMD="$TMP/bin/toast" SLICES_ROOT="$c/slices" \
  CHECK_LOG_FILE="$c/check.log" ISSUE_BODY_FILE="$c/body.md" \
  bash "$SCRIPT_DIR/check-daily-report.sh" --date "$DATE" --no-wait >/dev/null 2>&1
check "cron: ログ1行が残る status=ok" grep -q "status=ok" "$c/check.log"

# ---- ケース10: 区切り内にマージされた PR の決定的な照合 ----
# set_pr_case <name> <PR 節の本文（改行区切り。空なら節なし）> <日報サマリーの箇条書き>
set_pr_case() {
  local c="$TMP/$1"
  setup_case "$1" yes yes
  { printf '【対象日】%s\n【区切り】a 〜 b\n' "$DATE"
    if [ -n "$2" ]; then printf '【区切り内にマージされたPR】\n%s\n' "$2"; fi
    printf '【次の節】\nx\n'
  } > "$c/slices/$DATE/payload.txt"
  { echo "## 📝 サマリー"; printf '%s\n' "$3"; echo "## 次の節"; echo "- 無関係"; } > "$c/body.md"
  echo '{"missing":[],"unsupported":[],"misclassified":[],"format":[]}' > "$c/stub/out"
  run_check "$1"
}
PR_LIST='- aya-215/dotfiles #1202（aya-215/feat-x、11/09 10:00）
- hankyu_kitchenyell/ebase-web #128（aya/fix-y、11/09 11:00）'

set_pr_case prmiss "$PR_LIST" '- Work: PR#1202 をマージ、#1280 も対応'
check "pr: #128 だけ重大で足される" jq_has "$TMP/prmiss" '(.missing | length) == 1 and .missing[0].severity == "重大" and (.missing[0].text | contains("hankyu_kitchenyell/ebase-web #128 が日報に無い"))'
check "pr: notify=true・トースト" jq_has "$TMP/prmiss" '.notify == true and .status == "ok"'
check "pr: ログ件数は足した後" grep -q "status=ok missing=1(重大1).*notify=true$" "$TMP/prmiss/check.log"
check "pr: ログは1行" test "$(wc -l < "$TMP/prmiss/check.log")" = 1

set_pr_case prok "$PR_LIST" '- Work: PR #128 と #1202 をマージ'
check "pr: 空白入りの PR #128 と #1202 は何も足さない" jq_has "$TMP/prok" '(.missing | length) == 0 and .notify == false'

set_pr_case prnohash "$PR_LIST" '- Work: 1202 と 128 をマージ'
check "pr: # 無しは足される(2件)" jq_has "$TMP/prnohash" '(.missing | length) == 2'

set_pr_case prnone '(なし)' '- Work: 何か'
check "pr: (なし) は何も足さない" jq_has "$TMP/prnone" '(.missing | length) == 0 and .notify == false'

set_pr_case prabsent '' '- Work: 何か'
check "pr: 節が無い payload は何も足さない" jq_has "$TMP/prabsent" '(.missing | length) == 0 and .notify == false'

set_pr_case prllm2 "$PR_LIST" '- Work: PR#1202'
echo '{"missing":[{"text":"#128 が無い","severity":"重大"}],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/prllm2/stub/out"
run_check prllm2
check "pr: LLM の missing と重ねて足される" jq_has "$TMP/prllm2" '(.missing | length) == 2'

set_pr_case prfail "$PR_LIST" '- Work: 何か'
echo 'JSONではない' > "$TMP/prfail/stub/out"
run_check prfail
check "pr: check_failed のときは照合しない" jq_has "$TMP/prfail" '.status == "check_failed" and (.missing | length) == 0'

# PR 照合の jq だけ失敗させても、LLM の結果で ok のまま（ログ1行）
set_pr_case prjq "$PR_LIST" '- Work: 何か'
mkdir -p "$TMP/prjq/fakebin"
cat > "$TMP/prjq/fakebin/jq" <<EOF2
#!/bin/bash
case "\$*" in *'.missing += '*) exit 1 ;; esac
exec "$(command -v jq)" "\$@"
EOF2
chmod +x "$TMP/prjq/fakebin/jq"
echo '{"missing":[{"text":"llm","severity":"軽微"}],"unsupported":[],"misclassified":[],"format":[]}' > "$TMP/prjq/stub/out"
rm -f "$TMP/prjq/check.log"
NIX_PROFILE_BIN="$TMP/prjq/fakebin" run_check prjq
check "prjq: status=ok で LLM の missing が残る" jq_has "$TMP/prjq" '.status == "ok" and (.missing | length) == 1 and .missing[0].text == "llm" and .notify == false'
check "prjq: ログ1行 status=ok" test "$(grep -c 'status=ok' "$TMP/prjq/check.log")" = 1 -a "$(wc -l < "$TMP/prjq/check.log")" = 1
check "prjq: 警告が stderr に出る" grep -q 'PR照合に失敗' "$TMP/prjq/stderr"

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "$fails 件失敗"; exit 1; fi

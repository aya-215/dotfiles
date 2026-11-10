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

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "$fails 件失敗"; exit 1; fi

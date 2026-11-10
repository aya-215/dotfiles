#!/bin/bash
# check-daily-report.sh - 生成された日報を、送信したペイロードと毎晩ローカルで照合する
#
# fire-daily-review.sh が保存した payload.txt と life リポジトリの日次 Issue の
# 「## 📝 サマリー」を claude に突き合わせさせ、重大な問題があるときだけトースト通知する。
# 通知の要否は LLM ではなくこのスクリプトが決定的に判定する。
#
# 使用方法:
#   cron から: 40 22 * * * /home/aya/.dotfiles/scripts/daily-review/check-daily-report.sh
#   手動:      bash check-daily-report.sh --date 2026-11-09 [--no-wait]
#   --no-wait: サマリーが空でも待たず1回で判定する（既定は60秒おきに最大20回取り直す）
#
# 差し替え口（主にテスト用）:
#   CLAUDE_BIN / CHECK_MODEL / TOAST_CMD / SLICES_ROOT / CHECK_LOG_FILE
#   ISSUE_BODY_FILE（指定時は GitHub の代わりにこのファイルを Issue 本文として読む）
#   CHECK_WAIT_SEC / CHECK_WAIT_MAX / CHECK_TIMEOUT_SEC
set -euo pipefail

export LANG=C.UTF-8

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
readonly CHECK_MODEL="${CHECK_MODEL:-claude-opus-5}"
readonly SLICES_ROOT="${SLICES_ROOT:-$HOME/.nb/claude/daily-slices}"
readonly LOG_FILE="${CHECK_LOG_FILE:-$HOME/.local/log/daily-review-check.log}"
readonly WAIT_SEC="${CHECK_WAIT_SEC:-60}"
readonly WAIT_MAX="${CHECK_WAIT_MAX:-20}"
readonly CHECK_TIMEOUT_SEC="${CHECK_TIMEOUT_SEC:-900}"
readonly REPO="aya-215/life"
readonly TOAST_PS1="$HOME/.claude/hooks/toast.ps1"
readonly PWSH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

DATE=""
NO_WAIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --date) DATE="${2:?--date に日付が必要}"; shift 2 ;;
    --no-wait) NO_WAIT=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DATE" ] || DATE="$(TZ=Asia/Tokyo date +%Y-%m-%d)"
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "invalid date: $DATE" >&2; exit 2; }

readonly OUT_DIR="$SLICES_ROOT/$DATE"
readonly PAYLOAD_FILE="$OUT_DIR/payload.txt"
readonly CHECK_JSON="$OUT_DIR/check.json"

# 日報の判定の注意点。verify-daily-report スキルの「判定の注意点」と揃える（根拠の範囲だけ payload 基準）
read -r -d '' NOTES <<'EON' || true
- 薄いセッションの脱落は問題ない。調査だけ・編集ファイルなしのセッションが日報に無くても取りこぼしに数えない。実際に何かを成した作業のみ計上する。
- 根拠不明の判定は慎重に。根拠は payload の【区切り】範囲の要約・git・Rocket Chat・メールすべて。セッション要約に無いだけで捏造と断定せず、確信度（高/中/低）を必ず添える。RC 由来と推定できるものは確信度・低とする。
- 自分の PR への指摘対応は「自分の作業」が正しい。要約に【レビュー作業】と付いていても要約側のラベルの粗さであり、日報側が「自分の作業」に置いていれば誤分類ではない。
- Work/Personal は「会社に提出・共有するか」で判定する。コミット先のリポジトリでは判断しない。dotfiles の整備は Personal、社内雑務・発表準備・タスク整理は Work。
- 見出しが「（全期間の要約・補完）」で終わるセッションは、区切りより前の作業も含みうる全期間の要約である。日報の項目がその区切り前の部分にしか裏付けが無くても、確信度・高の根拠不明にしない。区切り前の作業が日報に無くても取りこぼしに数えない。
- 日報の項目が payload の【区切り】範囲に実体を持たないだけなら、確信度は中以下にする。
EON

# log_line <status> <missing> <missing_major> <unsup> <unsup_high> <misc> <notify>
log_line() {
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '[%s] %s status=%s missing=%s(重大%s) unsupported=%s(高%s) misclassified=%s notify=%s\n' \
    "$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')" "$DATE" "$@" >> "$LOG_FILE"
}

# toast <title> <one line> — 失敗してもスクリプトは落とさない
toast() {
  if [ -n "${TOAST_CMD:-}" ]; then
    printf '%s\n%s\n' "$1" "$2" | "$TOAST_CMD" >/dev/null 2>&1 || true
  else
    printf '%s\n%s\n' "$1" "$2" | "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$TOAST_PS1")" >/dev/null 2>&1 || true
  fi
}

# finish_simple <status> <message> — LLM 照合なしで終了する（report_missing / check_failed）
finish_simple() {
  local status="$1" msg="$2"
  mkdir -p "$OUT_DIR"
  jq -n --arg s "$status" --arg m "$msg" \
    '{missing:[],unsupported:[],misclassified:[],format:[],notify:true,status:$s,message:$m}' > "$CHECK_JSON"
  log_line "$status" 0 0 0 0 0 true
  toast "日報チェック $DATE: $status" "$msg"
  exit 0
}

# fetch_issue_body — 対象日の日次 Issue 本文を標準出力へ。無ければ空
fetch_issue_body() {
  if [ -n "${ISSUE_BODY_FILE:-}" ]; then cat "$ISSUE_BODY_FILE" 2>/dev/null || true; return 0; fi
  local token num
  token="$(gh auth token --user aya-215 2>/dev/null)" || return 0
  num="$(GH_TOKEN="$token" gh api -X GET search/issues -f q="repo:$REPO is:issue \"$DATE\" in:title" --jq '.items[0].number // empty' 2>/dev/null)" || return 0
  [ -n "$num" ] || return 0
  GH_TOKEN="$token" gh api "repos/$REPO/issues/$num" --jq .body 2>/dev/null || true
}

# extract_summary — 標準入力の Issue 本文から「## 📝 サマリー」節だけを取り出す
extract_summary() {
  awk '/^## 📝 サマリー/ {f=1; print; next} f && /^## / {exit} f {print}'
}

# validate_json — 標準入力から JSON オブジェクトを取り出して検証し、正規化して標準出力へ
validate_json() {
  python3 -I -c '
import json, sys
t = sys.stdin.read()
a, b = t.find("{"), t.rfind("}")
if a < 0 or b < a: sys.exit(1)
try: d = json.loads(t[a:b+1])
except Exception: sys.exit(1)
if not isinstance(d, dict): sys.exit(1)
out = {}
for k in ("missing", "unsupported", "misclassified", "format"):
    v = d.get(k, [])
    if not isinstance(v, list): sys.exit(1)
    out[k] = v
for k in ("missing", "unsupported", "misclassified"):
    if not all(isinstance(x, dict) for x in out[k]): sys.exit(1)
print(json.dumps(out, ensure_ascii=False))
'
}

if [ ! -s "$PAYLOAD_FILE" ]; then
  finish_simple check_failed "payload.txt が無い（$PAYLOAD_FILE）"
fi

# サマリーに箇条書きが出るまで待つ（クラウド側の生成完了待ち）
summary=""
attempt=0
while :; do
  attempt=$((attempt + 1))
  summary="$(fetch_issue_body | extract_summary || true)"
  if printf '%s\n' "$summary" | grep -qE '^[[:space:]]*[-*] '; then break; fi
  if [ "$NO_WAIT" -eq 1 ] || [ "$attempt" -ge "$WAIT_MAX" ]; then
    finish_simple report_missing "日報のサマリーが空（${attempt}回確認）"
  fi
  sleep "$WAIT_SEC"
done

prompt="$(cat <<EOP
あなたは日報の品質検証者です。読み取り専用で、次の【ペイロード】（日報生成への入力）と【日報サマリー】を照合してください。

# 判定の注意点（必ず守る）
$NOTES

# 検出する観点
- missing: ペイロードに実体ある作業があるのに日報に無い。severity は「重大」か「軽微」。
- unsupported: 日報にあるがペイロードのどこにも根拠が無い。confidence は「高」「中」「低」。
- misclassified: Work/Personal や自分の作業/レビュー作業の振り分け誤り。
- format: 件数表記の揺れ、Personal への件数付与、「なし」断定などの書式ドリフト（文字列の配列）。

# 出力
次の JSON だけを出力する。前置き・コードフェンス・説明は付けない。
{"missing":[{"text":"...","severity":"重大|軽微"}],"unsupported":[{"text":"...","confidence":"高|中|低"}],"misclassified":[{"text":"..."}],"format":["..."]}
問題が無い観点は空配列にする。

【ペイロード】
$(cat "$PAYLOAD_FILE")

【日報サマリー】
$summary
EOP
)"

result=""
for try in 1 2; do
  raw=""
  if raw="$(printf '%s' "$prompt" | timeout "$CHECK_TIMEOUT_SEC" "$CLAUDE_BIN" -p --model "$CHECK_MODEL" --no-session-persistence --setting-sources '' --settings '{"disableAllHooks":true}' 2>/dev/null)"; then
    if result="$(printf '%s' "$raw" | validate_json)"; then break; fi
  fi
  result=""
done
[ -n "$result" ] || finish_simple check_failed "claude の出力が JSON として読めない（または失敗・タイムアウト）"

# 通知判定は決定的に行う: 重大な取りこぼし、または確信度・高の根拠不明
final="$(printf '%s' "$result" | jq '
  . + {notify: (any(.missing[]; .severity == "重大") or any(.unsupported[]; .confidence == "高")), status: "ok"}')"
printf '%s\n' "$final" > "$CHECK_JSON"

n_missing="$(jq '.missing | length' <<<"$final")"
n_major="$(jq '[.missing[] | select(.severity == "重大")] | length' <<<"$final")"
n_unsup="$(jq '.unsupported | length' <<<"$final")"
n_high="$(jq '[.unsupported[] | select(.confidence == "高")] | length' <<<"$final")"
n_misc="$(jq '.misclassified | length' <<<"$final")"
notify="$(jq -r '.notify' <<<"$final")"
log_line ok "$n_missing" "$n_major" "$n_unsup" "$n_high" "$n_misc" "$notify"

if [ "$notify" = true ]; then
  toast "日報チェック $DATE: 要確認" "取りこぼし重大${n_major}件・根拠不明(高)${n_high}件。${CHECK_JSON} を確認"
fi
exit 0

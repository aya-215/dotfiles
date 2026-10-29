#!/usr/bin/env bash
# 手順8 の判定結果を1件1行で findings.jsonl に足す。セッションをまたいで判定を読み返すため。
#
# 値の検証はここで決定的に行う。書式のずれを Claude の注意力に任せないため。
# 1件でも不正なら1件も書かない。周回の記録が歯抜けになるのを防ぐ。
#
# 使い方: record-finding.sh < finding.json
#   標準入力: 指摘1件の JSON オブジェクト、またはその配列
#   PR を作る前の手元レビューは pr の代わりに branch で記録する
#   書き込み先: $REVIEW_FINDINGS_FILE（既定 ~/.nb/claude/review-findings/findings.jsonl）
#   ※ ~/.nb/claude/sessions/ の中には置かない。日報のクラウドルーティンに送られるため
set -euo pipefail

readonly FINDINGS_FILE="${REVIEW_FINDINGS_FILE:-$HOME/.nb/claude/review-findings/findings.jsonl}"

# 1件ごとの検証。エラー文の配列を返す（空なら妥当）。
# shellcheck disable=SC2016  # jq の $ 変数を bash に展開させない
readonly VALIDATE='
def required: ["repo","round","reviewer","file","claim","stage1","destination","basis"];
def optional: ["pr","branch","symbol","severity","verdict","in_diff","callers","has_test","reason","measured","rejected_fix","user_override","from_own_fix"];
def stage1s: ["壊れている","主張が嘘になる","該当なし"];
def reasons: ["到達不能","安全側","設計判断","理論上のみ"];
def destinations: ["何もしない","コメントで判断を残す","このPRで対応","issue化"];
def posint: type == "number" and . == floor and . >= 1;
def errors_of($i):
  . as $f
  | if type != "object" then ["\($i): オブジェクトではない"] else
    [ (required[] | select(($f[.] // "") == "") | "\($i): \(.) が無い"),
      (keys[] | select(. as $k | (required + optional) | index($k) | not) | "\($i): 知らない項目 \(.)"),
      (select($f.pr == null and (($f.branch // "") == "")) | "\($i): pr か branch のどちらかが要る"),
      (select(($f.pr // 1) | posint | not) | "\($i): pr は1以上の整数"),
      (select(($f.round // 1) | posint | not) | "\($i): round は1以上の整数"),
      (select($f.reviewer != null and ($f.reviewer | tostring | test("^(claude\\[bot\\]|code-review:(low|medium|high|xhigh|max)|human:.+)$") | not))
        | "\($i): reviewer は claude[bot] / code-review:<level> / human:<login> のどれか"),
      (select($f.stage1 != null and (stage1s | index($f.stage1) | not)) | "\($i): stage1 は \(stage1s | join(" / "))"),
      (select($f.destination != null and (destinations | index($f.destination) | not)) | "\($i): destination は \(destinations | join(" / "))"),
      (select($f.reason != null and (reasons | index($f.reason) | not)) | "\($i): reason は \(reasons | join(" / "))"),
      (select($f.stage1 == "該当なし" and $f.reason == null) | "\($i): stage1 が該当なしなら reason が要る"),
      (select($f.verdict != null and (["CONFIRMED","PLAUSIBLE"] | index($f.verdict) | not)) | "\($i): verdict は CONFIRMED / PLAUSIBLE"),
      (select($f.measured != null and ($f.measured | tostring | test("^\\+[0-9]+/[-−][0-9]+$") | not)) | "\($i): measured は +N/-M の形"),
      (select($f.from_own_fix != null and ($f.from_own_fix | type) != "boolean") | "\($i): from_own_fix は true / false"),
      (select($f.user_override != null and (
          ($f.user_override | type) != "object"
          or (destinations | index($f.user_override.before) | not)
          or (destinations | index($f.user_override.after) | not)
          or $f.user_override.before == $f.user_override.after))
        | "\($i): user_override は {before, after} で、どちらも destination の値かつ別の値")
    ] end;
(if type == "array" then . else [.] end) as $all
| [range(0; $all | length) as $i | $all[$i] | errors_of($i)] | add // []
'

# 同じ指摘を同じ周回で二度数えないための識別子。
readonly KEY='[.repo, (.pr // null), (.branch // ""), .round, .reviewer, .file, (.symbol // ""), .claim]'

# fail <メッセージ...>
# 標準エラーに出して終了する。
fail() {
	printf '%s\n' "$@" >&2
	exit 1
}

main() {
	local input errors
	input=$(cat)
	jq -e . >/dev/null 2>&1 <<<"$input" || fail "標準入力が JSON ではない"

	errors=$(jq -r "$VALIDATE | .[]" <<<"$input")
	[[ -z "$errors" ]] || fail "記録しなかった（1件も書いていない）:" "$errors"

	if [[ -z "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
		echo "警告: CLAUDE_CODE_SESSION_ID が無いため session_id は null で記録する" >&2
	fi

	mkdir -p "$(dirname "$FINDINGS_FILE")"
	# 並行セッションの追記が混ざらないよう、読み取り（重複判定）から書き込みまでをロックする
	exec 9>>"$FINDINGS_FILE"
	flock 9

	local existing_keys stamp new_lines total written
	existing_keys=$(jq -c "$KEY" "$FINDINGS_FILE" | jq -sc .)
	stamp=$(date +%s%N)
	new_lines=$(jq -c \
		--argjson seen "$existing_keys" \
		--arg now "$(date -Iseconds)" \
		--arg sid "${CLAUDE_CODE_SESSION_ID:-}" \
		--arg stamp "$stamp" \
		"(if type == \"array\" then . else [.] end)
		| to_entries[]
		| .key as \$n | .value
		| select(($KEY) as \$k | \$seen | index([\$k]) | not)
		| {id: \"\(\$stamp)-\(\$n)\", recorded_at: \$now, session_id: (if \$sid == \"\" then null else \$sid end)} + ." \
		<<<"$input")

	total=$(jq 'if type == "array" then length else 1 end' <<<"$input")
	if [[ -n "$new_lines" ]]; then
		printf '%s\n' "$new_lines" >&9
		written=$(wc -l <<<"$new_lines")
	else
		written=0
	fi
	echo "記録した: ${written}件 / 記録済みで飛ばした: $((total - written))件 → $FINDINGS_FILE"
}

main

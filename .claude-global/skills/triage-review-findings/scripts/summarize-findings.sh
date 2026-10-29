#!/usr/bin/env bash
# findings.jsonl を読み出す。判断はしない。数字と過去の判定を出すだけ。
#
# 使い方:
#   summarize-findings.sh [--pr <repo>#<番号>] [--branch <repo>:<ブランチ>] [--next-round]
#                                             その PR・ブランチの過去の判定を周回順に出す（手順8 用）
#                                             両方渡すとどちらかに当たる記録を出す（PR 作成前の周回も拾える）
#                                             --next-round は今回の周回番号だけを出す
#   summarize-findings.sh [--since YYYY-MM-DD] [--json]
#                                             レビュアー別に4分類の件数とノイズ率を出す
#
# 4分類は記録に持たず、最終の行き先（user_override があれば変更後）と reason から導く:
#   対応 = このPRで対応 / issue化、わざと = 設計判断、間違い = 到達不能 / 理論上のみ、どうでもええ = 残り
set -euo pipefail

readonly FINDINGS_FILE="${REVIEW_FINDINGS_FILE:-$HOME/.nb/claude/review-findings/findings.jsonl}"

# shellcheck disable=SC2016  # jq の $ 変数を bash に展開させない
readonly CLASSIFY='
def final_destination: .user_override.after // .destination;
def class:
  final_destination as $d | .reason as $r
  | if (["このPRで対応","issue化"] | index($d)) then "対応"
    elif $r == "設計判断" then "わざと"
    elif (["到達不能","理論上のみ"] | index($r)) then "間違い"
    else "どうでもええ" end;
'

# usage
# 使い方を標準エラーに出して終了する。
usage() {
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

# select_target <repo> <pr> <branch> <jq の後段>
# repo が一致し、pr かブランチのどちらかが一致する記録だけを後段に渡す。
select_target() {
	local repo="$1" pr="$2" branch="$3" rest="$4"
	jq -sr --arg repo "$repo" --arg pr "$pr" --arg branch "$branch" "$CLASSIFY"'
		[.[] | select(.repo == $repo and (
			($pr != "" and .pr == ($pr | tonumber)) or ($branch != "" and .branch == $branch)))]
		| sort_by(.round, .recorded_at) | '"$rest" "$FINDINGS_FILE"
}

# show_target <repo> <pr> <branch>
# 対象の記録を周回順に出す。
show_target() {
	select_target "$1" "$2" "$3" '
		if length == 0 then "この対象の記録は無い" else .[] |
		  "R\(.round) \(.reviewer) \(.file)\(if .symbol then ":" + .symbol else "" end) — \(.claim)\n"
		  + "    判定: \(.stage1)\(if .reason then "（" + .reason + "）" else "" end) → \(.destination)"
		  + (if .user_override then " → \(.user_override.after)（判定を変更）" else "" end)
		  + "\n    根拠: \(.basis)"
		  + (if .rejected_fix then "\n    却下した修正案: \(.rejected_fix)" else "" end)
		  end'
}

# next_round <repo> <pr> <branch>
# 記録済みの最大周回 + 1 を出す。記録が無ければ 1。
next_round() {
	select_target "$1" "$2" "$3" '(map(.round) | max // 0) + 1'
}

# aggregate <since> <json:0|1>
# レビュアー別に4分類・ノイズ率・判定を変えた件数を出す。
aggregate() {
	local since="$1" as_json="$2" result
	result=$(jq -s --arg since "$since" "$CLASSIFY"'
		[.[] | select($since == "" or .recorded_at >= $since)]
		| group_by(.reviewer)
		| map({key: .[0].reviewer, value: (
			(map(class) | group_by(.) | map({key: .[0], value: length}) | from_entries) as $c
			| {total: length, "対応": ($c["対応"] // 0), "間違い": ($c["間違い"] // 0),
			   "わざと": ($c["わざと"] // 0), "どうでもええ": ($c["どうでもええ"] // 0),
			   override: (map(select(.user_override)) | length)}
			| . + {noise_rate: (if .total == 0 then 0 else ((.total - .["対応"]) / .total * 100 | round) end)}
		  )})
		| from_entries' "$FINDINGS_FILE")
	if [[ "$as_json" -eq 1 ]]; then
		echo "$result"
		return
	fi
	jq -r '
		if length == 0 then "対象期間の記録は無い" else
		(["reviewer","件数","対応","間違い","わざと","どうでもええ","ノイズ率","判定変更"] | @tsv),
		(to_entries[] | [.key, .value.total, .value["対応"], .value["間違い"], .value["わざと"],
		  .value["どうでもええ"], "\(.value.noise_rate)%", .value.override] | @tsv)
		end' <<<"$result"
}

main() {
	local repo="" pr="" branch="" since="" as_json=0 want_next=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--pr)
			[[ "${2:-}" =~ ^(.+)#([0-9]+)$ ]] || usage
			[[ -z "$repo" || "$repo" == "${BASH_REMATCH[1]}" ]] || usage
			repo="${BASH_REMATCH[1]}"
			pr="${BASH_REMATCH[2]}"
			shift 2
			;;
		--branch)
			# git の ref 名は ':' を含めないので、最初の ':' で repo と分けられる
			[[ "${2:-}" =~ ^([^:]+):(.+)$ ]] || usage
			[[ -z "$repo" || "$repo" == "${BASH_REMATCH[1]}" ]] || usage
			repo="${BASH_REMATCH[1]}"
			branch="${BASH_REMATCH[2]}"
			shift 2
			;;
		--next-round) want_next=1; shift ;;
		--since) since="${2:-}"; shift 2 || usage ;;
		--json) as_json=1; shift ;;
		*) usage ;;
		esac
	done
	[[ "$want_next" -eq 0 || -n "$repo" ]] || usage

	if [[ ! -s "$FINDINGS_FILE" ]]; then
		if [[ "$want_next" -eq 1 ]]; then
			echo 1
		elif [[ "$as_json" -eq 1 ]]; then
			echo '{}'
		else
			echo "まだ記録が無い: $FINDINGS_FILE"
		fi
		return 0
	fi

	if [[ "$want_next" -eq 1 ]]; then
		next_round "$repo" "$pr" "$branch"
	elif [[ -n "$repo" ]]; then
		show_target "$repo" "$pr" "$branch"
	else
		aggregate "$since" "$as_json"
	fi
}

main "$@"

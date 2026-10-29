#!/usr/bin/env bash
# @claude 宛てに投稿した PR コメントへの claude[bot] の返事を待ち、終わったら本文を出す。
# 返事は「作業中」のコメントが先に作られ、終わると同じコメントが書き換わる。
# 作られた時点で拾うと作業中の文面を読んでしまうため、本文の書き出しで完了を判定する。
#
# 使い方: wait-claude-reply.sh <@claude コメントの URL> [--interval 秒] [--timeout 秒]
#   URL     : https://github.com/<owner>/<repo>/pull/<番号>#issuecomment-<id>（gh pr comment が出す URL）
#   --interval: 取得の間隔（既定 15 秒）
#   --timeout : 待つ上限（既定 600 秒）
#   gh の認証は呼び出し側の GH_TOKEN / アクティブアカウントを使う
#   WAIT_CLAUDE_FETCH: テスト用。設定するとコメント一覧（JSON 配列）をこのコマンドの出力から読む
#
# 終了コード: 0 返事が完了 / 3 返事がエラーで終了 / 124 時間切れ / 2 引数・依頼コメント・取得の異常
set -euo pipefail

readonly FINISHED_PREFIX='**Claude finished'
readonly ERROR_PREFIX='**Claude encountered an error'
readonly BOT_LOGIN='claude[bot]'
readonly MAX_FETCH_FAILURES=3

url="${1:-}"
interval=15
timeout=600
shift || true
while [[ $# -gt 0 ]]; do
	case "$1" in
	--interval) interval="$2"; shift 2 ;;
	--timeout) timeout="$2"; shift 2 ;;
	*) echo "不明な引数: $1" >&2; exit 2 ;;
	esac
done

if [[ ! "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)#issuecomment-([0-9]+)$ ]]; then
	echo "usage: wait-claude-reply.sh <https://github.com/<owner>/<repo>/pull/<番号>#issuecomment-<id>> [--interval 秒] [--timeout 秒]" >&2
	exit 2
fi
readonly OWNER="${BASH_REMATCH[1]}" REPO="${BASH_REMATCH[2]}" PR="${BASH_REMATCH[3]}" MENTION_ID="${BASH_REMATCH[4]}"

# fetch_comments
# PR の会話欄のコメントを全件、1つの JSON 配列で出す。
fetch_comments() {
	if [[ -n "${WAIT_CLAUDE_FETCH:-}" ]]; then
		bash -c "$WAIT_CLAUDE_FETCH" | jq -s 'add // []'
	else
		gh api --paginate "repos/$OWNER/$REPO/issues/$PR/comments?per_page=100" | jq -s 'add // []'
	fi
}

# find_reply <comments JSON> <依頼の created_at>
# 依頼より後に claude[bot] が作ったコメントを、新しいものから1件出す。無ければ空。
find_reply() {
	local comments="$1" since="$2"
	jq -c --arg bot "$BOT_LOGIN" --arg since "$since" --argjson mention "$MENTION_ID" '
		[.[] | select(.user.login == $bot and .created_at >= $since and .id != $mention)]
		| sort_by(.created_at) | last // empty' <<<"$comments"
}

start=$SECONDS
fetch_failures=0
mention_at=""
while :; do
	if comments=$(fetch_comments 2>/dev/null); then
		fetch_failures=0
		if [[ -z "$mention_at" ]]; then
			mention=$(jq -c --argjson id "$MENTION_ID" '.[] | select(.id == $id)' <<<"$comments")
			if [[ -z "$mention" ]]; then
				echo "依頼コメント #$MENTION_ID が PR #$PR に見つかりません" >&2
				exit 2
			fi
			if ! jq -e '.body | contains("@claude")' <<<"$mention" >/dev/null; then
				echo "依頼コメントに @claude が無いため claude は起動しません" >&2
				exit 2
			fi
			mention_at=$(jq -r '.created_at' <<<"$mention")
		fi

		reply=$(find_reply "$comments" "$mention_at")
		if [[ -n "$reply" ]]; then
			body=$(jq -r '.body' <<<"$reply")
			reply_url="https://github.com/$OWNER/$REPO/pull/$PR#issuecomment-$(jq -r '.id' <<<"$reply")"
			if [[ "$body" == "$FINISHED_PREFIX"* ]]; then
				printf '返事: %s\n\n%s\n' "$reply_url" "$body"
				exit 0
			fi
			if [[ "$body" == "$ERROR_PREFIX"* ]]; then
				printf '返事（エラーで終了）: %s\n\n%s\n' "$reply_url" "$body"
				exit 3
			fi
		fi
	else
		fetch_failures=$((fetch_failures + 1))
		if [[ $fetch_failures -ge $MAX_FETCH_FAILURES ]]; then
			echo "コメントの取得に ${MAX_FETCH_FAILURES} 回続けて失敗しました（gh の認証・アカウントを確認）" >&2
			exit 2
		fi
	fi

	if [[ $((SECONDS - start)) -ge $timeout ]]; then
		state="返事のコメントはまだ作られていません"
		[[ -n "${reply:-}" ]] && state="作業中のまま: $(jq -r '.body | split("\n")[0]' <<<"$reply")"
		echo "${timeout} 秒待ちましたが返事が完了しませんでした（${state}）" >&2
		exit 124
	fi
	sleep "$interval"
done

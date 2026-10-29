#!/usr/bin/env bash
# wait-claude-reply.sh のテスト。GitHub には繋がず、WAIT_CLAUDE_FETCH で用意したコメント一覧を返す。
# 使い方: test-wait-claude-reply.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly WAIT="$SCRIPT_DIR/wait-claude-reply.sh"
readonly URL="https://github.com/ebase-dev/eb-api-extended/pull/126#issuecomment-200"

work_dir=$(mktemp -d) || exit 2
trap 'rm -rf "$work_dir"' EXIT

passed=0
failed=0

# check <テスト名> <条件コマンド...>
check() {
	local name="$1"
	shift
	if "$@"; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		echo "FAIL: $name" >&2
	fi
}

# contains <文字列> <部分文字列>
# 部分文字列を含めば成功する。
contains() {
	[[ "$1" == *"$2"* ]]
}

# comment <id> <login> <created_at> <body>
# GitHub の issue comment と同じ形の JSON を1件出す。
comment() {
	jq -cn --argjson id "$1" --arg login "$2" --arg at "$3" --arg body "$4" \
		'{id: $id, user: {login: $login}, created_at: $at, body: $body}'
}

MENTION=$(comment 200 eBASE-Mori 2026-10-29T06:59:53Z '@claude レビューありがとうございます。')
OLD_REVIEW=$(comment 100 'claude[bot]' 2026-10-29T06:51:42Z '## レビュー: 前の周回')
OLD_FINISHED=$(comment 150 'claude[bot]' 2026-10-29T06:40:00Z '**Claude finished @eBASE-Mori'"'"'s task in 20s** —— 前の周回の返事')
WORKING=$(comment 201 'claude[bot]' 2026-10-29T07:00:09Z 'Claude Code is working…')
FINISHED=$(comment 201 'claude[bot]' 2026-10-29T07:00:09Z '**Claude finished @eBASE-Mori'"'"'s task in 39s** —— このままマージして問題ありません')
ERRORED=$(comment 201 'claude[bot]' 2026-10-29T07:00:09Z '**Claude encountered an error after 12s** —— 失敗')

# fixture <名前> <コメント JSON...>
# コメント一覧（JSON 配列）を書いたファイルを作り、そのパスを出す。
fixture() {
	local path="$work_dir/$1.json"
	shift
	printf '%s\n' "$@" | jq -s . >"$path"
	echo "$path"
}

# run <fixture のパス> [追加の引数...]
# 標準出力と終了コードを out / code に入れる。待ち時間は最小にする。
run() {
	local path="$1"
	shift
	out=$(WAIT_CLAUDE_FETCH="cat $path" "$WAIT" "$URL" --interval 0 --timeout 0 "$@" 2>&1)
	code=$?
}

# 1. 返事が完了していれば本文を出して 0
run "$(fixture finished "$OLD_REVIEW" "$MENTION" "$FINISHED")"
check "完了した返事で exit 0" [ "$code" -eq 0 ]
check "完了した返事の本文を出す" contains "$out" "このままマージして問題ありません"

# 2. 作業中のままなら完了扱いにせず、時間切れで 124
run "$(fixture working "$MENTION" "$WORKING")"
check "作業中のままなら exit 124" [ "$code" -eq 124 ]

# 3. エラーで終わった返事は 3
run "$(fixture errored "$MENTION" "$ERRORED")"
check "エラーの返事で exit 3" [ "$code" -eq 3 ]
check "エラーの本文を出す" contains "$out" "encountered an error"

# 4. 依頼より前の返事（前の周回）は拾わない
run "$(fixture old "$OLD_FINISHED" "$MENTION")"
check "依頼より前の返事は拾わず exit 124" [ "$code" -eq 124 ]

# 5. 依頼コメントが一覧に無ければ 2
run "$(fixture nomention "$OLD_REVIEW")"
check "依頼コメントが見つからなければ exit 2" [ "$code" -eq 2 ]

# 6. 依頼コメントに @claude が無ければ起動しないので 2
NO_AT=$(comment 200 eBASE-Mori 2026-10-29T06:59:53Z 'レビューありがとうございます。')
run "$(fixture noat "$NO_AT" "$FINISHED")"
check "@claude の無い依頼は exit 2" [ "$code" -eq 2 ]
check "@claude が無いことを伝える" contains "$out" "@claude"

# 7. URL の形が違えば 2
out=$(WAIT_CLAUDE_FETCH="cat /dev/null" "$WAIT" "https://github.com/ebase-dev/eb-api-extended/pull/126" --interval 0 --timeout 0 2>&1)
code=$?
check "コメント URL でなければ exit 2" [ "$code" -eq 2 ]

# 8. 作業中 → 完了 と書き換わったら拾う（取得のたびに中身が進む）
working_path=$(fixture step1 "$MENTION" "$WORKING")
finished_path=$(fixture step2 "$MENTION" "$FINISHED")
counter="$work_dir/counter"
echo 0 >"$counter"
stepper="$work_dir/stepper.sh"
cat >"$stepper" <<EOF
#!/usr/bin/env bash
n=\$(cat "$counter"); echo \$((n + 1)) >"$counter"
if [ "\$n" -lt 2 ]; then cat "$working_path"; else cat "$finished_path"; fi
EOF
chmod +x "$stepper"
out=$(WAIT_CLAUDE_FETCH="$stepper" "$WAIT" "$URL" --interval 0 --timeout 30 2>&1)
code=$?
check "作業中から完了に変わったら exit 0" [ "$code" -eq 0 ]
check "書き換わった後の本文を出す" contains "$out" "このままマージして問題ありません"

# 9. 取得に失敗し続けたら 2（待ち続けない）
out=$(WAIT_CLAUDE_FETCH="false" "$WAIT" "$URL" --interval 0 --timeout 30 2>&1)
code=$?
check "取得失敗が続いたら exit 2" [ "$code" -eq 2 ]

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]

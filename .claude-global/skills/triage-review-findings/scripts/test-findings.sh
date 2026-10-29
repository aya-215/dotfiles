#!/usr/bin/env bash
# record-finding.sh / summarize-findings.sh のテスト。実データを汚さないよう一時ファイルに書く。
# 使い方: test-findings.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RECORD="$SCRIPT_DIR/record-finding.sh"
readonly SUMMARIZE="$SCRIPT_DIR/summarize-findings.sh"

work_dir=$(mktemp -d) || exit 2
trap 'rm -rf "$work_dir"' EXIT
export REVIEW_FINDINGS_FILE="$work_dir/sub/findings.jsonl"
export CLAUDE_CODE_SESSION_ID="11111111-2222-3333-4444-555555555555"

passed=0
failed=0

# check <テスト名> <条件コマンド...>
# 条件コマンドが成功すれば pass、失敗すれば fail として数える。
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

# not_contains <文字列> <部分文字列>
# 部分文字列を含まなければ成功する。
not_contains() {
	[[ "$1" != *"$2"* ]]
}

# line_count
# 記録ファイルの行数を出す。ファイルが無ければ 0。
line_count() {
	if [[ -f "$REVIEW_FINDINGS_FILE" ]]; then
		wc -l <"$REVIEW_FINDINGS_FILE"
	else
		echo 0
	fi
}

# finding [jq フィルタ]
# 妥当な指摘1件の JSON を出す。引数の jq フィルタで一部を書き換えられる。
finding() {
	jq -cn '{
		repo: "ebase-portal-chat", pr: 100, round: 1, reviewer: "claude[bot]",
		file: "apps/a.ts", symbol: "foo", claim: "null で落ちる",
		severity: "HIGH", verdict: "CONFIRMED",
		in_diff: "yes", callers: "3", has_test: "yes",
		stage1: "壊れている", destination: "このPRで対応",
		basis: "呼び出し元3件・再現した", measured: "+4/-1"
	}' | jq -c "${1:-.}"
}

# --- record-finding.sh ---

finding | "$RECORD" >/dev/null
check "1件を記録できる" test "$(line_count)" -eq 1
check "時刻・セッションID・id が付く" jq -e 'select(.recorded_at and .id and .session_id == env.CLAUDE_CODE_SESSION_ID)' "$REVIEW_FINDINGS_FILE" >/dev/null

jq -cn --argjson a "$(finding '.file="b.ts"')" --argjson b "$(finding '.file="c.ts" | .stage1="該当なし" | .reason="到達不能" | .destination="何もしない"')" '[$a, $b]' | "$RECORD" >/dev/null
check "配列で複数件を記録できる" test "$(line_count)" -eq 3

finding | "$RECORD" >/dev/null 2>&1
check "同じ指摘の二重記録は飛ばす" test "$(line_count)" -eq 3

jq -cn --argjson a "$(finding '.file="d.ts"')" --argjson b "$(finding '.file="e.ts" | .destination="直す"')" '[$a, $b]' | "$RECORD" >/dev/null 2>&1
rc=$?
check "決められた値以外は拒否する" test "$rc" -ne 0
check "1件でも不正なら1件も書かない" test "$(line_count)" -eq 3

finding '.file="f.ts" | del(.claim)' | "$RECORD" >/dev/null 2>&1
check "必須項目が欠けたら拒否する" test $? -ne 0

finding '.file="g.ts" | .stage1="該当なし" | .destination="何もしない"' | "$RECORD" >/dev/null 2>&1
check "該当なしで reason が無ければ拒否する" test $? -ne 0

finding '.file="h.ts" | .reviewer="someone"' | "$RECORD" >/dev/null 2>&1
check "reviewer の形式違いを拒否する" test $? -ne 0

finding '.file="i.ts" | .rejected_fix="専用エラークラスを足す案。構造変更になるため" | .user_override={before: "このPRで対応", after: "何もしない"}' | "$RECORD" >/dev/null
check "user_override を記録できる" test "$(line_count)" -eq 4

finding '.file="j.ts" | .user_override={before: "このPRで対応", after: "やめる"}' | "$RECORD" >/dev/null 2>&1
check "user_override の値も検証する" test $? -ne 0

echo '{壊れたJSON' | "$RECORD" >/dev/null 2>&1
check "JSON でない入力を拒否する" test $? -ne 0

# --- summarize-findings.sh ---

finding '.pr=200 | .round=2 | .reviewer="code-review:high" | .file="k.ts" | .stage1="該当なし" | .reason="設計判断" | .destination="何もしない"' | "$RECORD" >/dev/null

pr_out=$("$SUMMARIZE" --pr "ebase-portal-chat#100")
check "--pr はその PR の指摘だけを出す" contains "$pr_out" "a.ts"
check "--pr は他の PR を出さない" not_contains "$pr_out" "k.ts"
check "--pr は判定を変えた指摘に印を付ける" contains "$pr_out" "→ 何もしない（判定を変更）"
check "--pr は却下した修正案を出す" contains "$pr_out" "却下した修正案: 専用エラークラス"

agg=$("$SUMMARIZE" --json)
# a.ts と b.ts は対応、c.ts は到達不能で間違い、i.ts は override 後の「何もしない」(reason 無し) でどうでもええ
check "判定を変えた後の行き先で4分類する" jq -e '.["claude[bot]"] | .total == 4 and .["対応"] == 2 and .["間違い"] == 1 and .["どうでもええ"] == 1 and .override == 1' <<<"$agg" >/dev/null
check "レビュアー別に分ける" jq -e '.["code-review:high"] | .total == 1 and .["わざと"] == 1' <<<"$agg" >/dev/null

# --- PR を作る前の周回と周回番号 ---

finding 'del(.pr) | .branch="feat/x" | .reviewer="code-review:medium" | .file="m.ts"' | "$RECORD" >/dev/null
check "PR が無くても branch で記録できる" test $? -eq 0

finding 'del(.pr) | .file="n.ts"' | "$RECORD" >/dev/null 2>&1
check "pr も branch も無ければ拒否する" test $? -ne 0

check "--next-round は記録済みの最大周回 + 1" test "$("$SUMMARIZE" --next-round --pr "ebase-portal-chat#100")" -eq 2
check "--next-round は branch でも数える" test "$("$SUMMARIZE" --next-round --branch "ebase-portal-chat:feat/x")" -eq 2
check "--next-round は記録が無ければ 1" test "$("$SUMMARIZE" --next-round --pr "ebase-portal-chat#999")" -eq 1

finding '.pr=300 | .branch="feat/x" | .round=2 | .file="o.ts"' | "$RECORD" >/dev/null
both_out=$("$SUMMARIZE" --pr "ebase-portal-chat#300" --branch "ebase-portal-chat:feat/x")
check "--pr と --branch を両方渡すと PR 作成前の周回も出す" contains "$both_out" "m.ts"
check "--pr と --branch を両方渡すと PR 作成後の周回も出す" contains "$both_out" "o.ts"
check "--next-round は PR 作成前後をまたいで数える" test "$("$SUMMARIZE" --next-round --pr "ebase-portal-chat#300" --branch "ebase-portal-chat:feat/x")" -eq 3

export REVIEW_FINDINGS_FILE="$work_dir/none.jsonl"
"$SUMMARIZE" >/dev/null
check "記録が無くても落ちない" test $? -eq 0
check "記録が無ければ --next-round は 1" test "$("$SUMMARIZE" --next-round --pr "r#1")" -eq 1

echo "passed: $passed / failed: $failed"
[[ "$failed" -eq 0 ]]

#!/usr/bin/env bash
# 手順6 問い1 の実測値を出す。「やるべきか」は判断しない。数字を出すだけ。
#
# 試作が無いときは exit 1 で突き返す。
# このスキルが最も防ぎたい失敗は「実測せず見積もりで却下する」ことであり、
# 指示文だけではそれを止められないため、決定的なゲートとして分離する。
#
# 使い方: measure-cost.sh [base-ref]
#   base-ref: 試作前の状態（既定 HEAD）。作業ツリーとの差分を測る
# -e は付けない。git diff の no-match や numstat 空を正常系として扱うため。
set -uo pipefail

BASE_REF="${1:-HEAD}"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "git リポジトリの外では測れない" >&2
	exit 2
}
cd "$REPO_ROOT" || exit 2

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
	echo "base-ref が見つからない: $BASE_REF" >&2
	exit 2
fi

# 未追跡ファイルも試作の一部。ただし index を書き換えると呼び出し側の
# ステージ済みの変更を巻き込むため、一時 index にコピーして測る。
tmp_index=$(mktemp) || exit 2
trap 'rm -f "$tmp_index"' EXIT
if [[ -f "$REPO_ROOT/.git/index" ]]; then
	cp "$REPO_ROOT/.git/index" "$tmp_index" 2>/dev/null
fi
numstat=$(GIT_INDEX_FILE="$tmp_index" git add -AN >/dev/null 2>&1; GIT_INDEX_FILE="$tmp_index" git diff --numstat "$BASE_REF" 2>/dev/null)
ins=$(printf '%s\n' "$numstat" | awk '{i+=$1} END{print i+0}')
del=$(printf '%s\n' "$numstat" | awk '{d+=$2} END{print d+0}')

echo "## 問い1: コストの実測値"
echo ""
if [[ -z "$numstat" ]]; then
	echo "- 試作の差分: **なし** → まだ試作していない"
	echo ""
	echo "  ※ 実測値なしで「規模が大きい」と却下してはいけない。試作してから測ること"
	exit 1
fi

echo "- 試作の差分: **+${ins}/−${del}行**"
printf '%s\n' "$numstat" | sed 's/^/    /'
echo ""
echo "この数字を記録してから問い2に答える。数字を見ずに「PRの一部ではない」と判断しないこと。"

#!/usr/bin/env bash
# レビュー指摘1件について、機械的に判定できる事実だけを出力する。
# 「直すべきか」の判断はしない。LLM が判断するための材料を確定させるのが役割。
#
# 判定できないときは断定せず「判定不可」を出す。
# 沈黙して間違えると、SKILL.md の「機械判定を優先」指示が誤判定を追認してしまう。
#
# 使い方: check-finding.sh <file> [symbol] [base-ref]
#   file   : 指摘されたファイルのパス（リポジトリ相対でなくてよい）
#   symbol : 指摘の中心にある関数・メソッド名（省略可）
#   base-ref: 差分の基準（既定 origin/main）
# -e は付けない。grep の no-match(exit 1) や `[[ -n ]] && break` を正常系として扱うため。
set -uo pipefail

FILE="${1:-}"
SYMBOL="${2:-}"
BASE_REF="${3:-origin/main}"

if [[ -z "$FILE" ]]; then
	echo "usage: check-finding.sh <file> [symbol] [base-ref]" >&2
	exit 2
fi

# 以降の grep・パス比較はすべてリポジトリルート基準で行う。
# git の出力がルート相対のため、cwd を揃えないと突き合わせが静かに失敗する。
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "git リポジトリの外では判定できない" >&2
	exit 2
}
orig_file="$FILE"
FILE=$(realpath --relative-to="$REPO_ROOT" "$FILE" 2>/dev/null) || FILE="$orig_file"
[[ -z "$FILE" ]] && FILE="$orig_file"
cd "$REPO_ROOT" || exit 2

# 呼び出し元検索が対応する言語。ここに無い言語は数えず「判定不可」を返す。
SEARCH_GLOBS=('*.ts' '*.tsx' '*.js')

echo "## 機械判定の結果"
echo ""
echo "対象ファイル: \`$FILE\`"
[[ -n "$SYMBOL" ]] && echo "対象シンボル: \`$SYMBOL\`"
echo ""

# --- 1. 指摘箇所がこのPRの差分内か ---
# 差分外なら「既存の問題」。このPRで直す義務はない。
# 未追跡・ステージ済みも「このPRが触った」側。三点diffだけ見ると新規追加が全部差分外に落ちる。
if git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
	touched=$(
		{
			git diff "${BASE_REF}...HEAD" --name-only 2>/dev/null
			git diff --cached --name-only 2>/dev/null
			git diff --name-only 2>/dev/null
			git ls-files --others --exclude-standard 2>/dev/null
		} | sort -u
	)
	if printf '%s\n' "$touched" | grep -qxF -- "$FILE"; then
		echo "- PR差分内: **はい**（このPRが触ったファイル）"
	elif [[ ! -e "$FILE" ]]; then
		echo "- PR差分内: **判定不可**（\`$FILE\` が存在しない。パスを確認）"
	else
		echo "- PR差分内: **いいえ** → 既存の問題。このPRのスコープ外の可能性が高い"
	fi
else
	echo "- PR差分内: 判定不可（$BASE_REF が見つからない）"
fi

# --- 2. 対象シンボルに本番の呼び出し元があるか ---
# 0件なら到達不能。到達不能なコードの不具合は「今壊れていない」。
# ただし対応言語のファイルが無いリポジトリでは 0件 と 検索不能 が区別できないため判定を降りる。
if [[ -n "$SYMBOL" ]]; then
	# 対象ファイル自身が検索対応言語かを見る。リポジトリ内の総数では判定できない。
	# 例: lua 40件 + js 2件のリポジトリで lua を指摘されると、js を検索して「0件」と誤答する。
	target_searchable=0
	for glob in "${SEARCH_GLOBS[@]}"; do
		# shellcheck disable=SC2053  # 右辺は glob として評価させる
		if [[ "$FILE" == $glob ]]; then
			target_searchable=1
			break
		fi
	done
	if [[ "$target_searchable" -eq 0 ]]; then
		echo "- 本番の呼び出し元: **判定不可**（\`$FILE\` は呼び出し元検索の対応言語 ${SEARCH_GLOBS[*]} ではない）"
		echo ""
		echo "  ※ 到達可能性は LLM が実際にコードを読んで判断すること。0件ではない"
	else
		# シンボル名・パスを正規表現メタ文字ごとエスケープする。
		# 未エスケープだと options.lua の . が任意文字に化け、別ファイルを誤除外する。
		esc_symbol=$(printf '%s' "$SYMBOL" | sed 's/[][\.*^$/]/\\&/g')
		esc_file=$(printf '%s' "$FILE" | sed 's/[][\.*^$/]/\\&/g')
		# レシーバ有無の両方を拾う。同名の別物を含みうるので件数は上限値として扱う。
		hits=$(
			git grep -n -I --untracked -E -- "(^|[^A-Za-z0-9_])${esc_symbol}[[:space:]]*\(" \
				-- "${SEARCH_GLOBS[@]}" 2>/dev/null |
				grep -v node_modules |
				grep -v '\.test\.' | grep -v '\.spec\.' |
				grep -vE '(^|/)(__tests__|tests?)/' |
				grep -v "^${esc_file}:" || true
		)
		if [[ -z "$hits" ]]; then
			refs=0
		else
			refs=$(printf '%s\n' "$hits" | wc -l)
		fi
		if [[ "$refs" -eq 0 ]]; then
			echo "- 本番の呼び出し元: **0件** → 到達不能。据え置き候補"
			echo ""
			echo "  ※ 公開APIとして外部に提供している場合はこの判定が当てにならない。要確認"
		else
			echo "- 本番の呼び出し元: **${refs}件以下**（同名シンボルを含む可能性あり）→ 到達可能"
			printf '%s\n' "$hits" | head -5 | sed 's/^/    /'
			if [[ "$refs" -gt 5 ]]; then
				echo "    …他 $((refs - 5)) 件"
			fi
		fi
	fi
fi

# --- 3. このファイルにテストがあるか ---
# テストが無い箇所への修正は、回帰を検出できない
base=$(basename "$FILE"); stem="${base%.*}"; ext="${base##*.}"
# git ls-files は pathspec の順ではなくソート順に出すため、グロブごとに順に引いて優先順位を決める。
test_file=""
for cand in "__tests__/${base}" "*/__tests__/${base}" \
	"test/${base}" "*/test/${base}" "tests/${base}" "*/tests/${base}" \
	"${stem}.test.${ext}" "*/${stem}.test.${ext}" \
	"${stem}.spec.${ext}" "*/${stem}.spec.${ext}"; do
	test_file=$(git ls-files -- "$cand" 2>/dev/null | grep -vxF -- "$FILE" | head -1)
	[[ -n "$test_file" ]] && break
done
if [[ -n "$test_file" ]]; then
	cases=$(grep -c "^[[:space:]]*\(it\|test\)(" "$test_file" 2>/dev/null)
	echo "- 対応するテスト: \`$test_file\`（${cases}ケース）"
else
	echo "- 対応するテスト: **判定不可**（既知の命名規約に一致するテストが無い）"
	echo ""
	echo "  ※ 別の配置規約を使っている可能性がある。「テスト無し」と断定しないこと"
fi

echo ""
echo "## 判断はこの結果を材料に行う。機械判定は「直すべきか」を答えない"

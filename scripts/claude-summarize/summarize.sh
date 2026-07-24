#!/bin/bash
# summarize.sh - セッション JSONL 1本を Haiku で7項目要約し、sessions/ に保存する
#
# extract.py で前処理（text + ツールメタ抽出）してから claude -p --model haiku に渡す。
# frontmatter と出力ファイルの構造はスクリプトが決定的に組み立て、Haiku には本文のみ生成させる
# （LLM に構造を任せると frontmatter 欠落・フェンス混入が起きるため）。
# サブスク枠で動くため API 課金はなく、要約は軽いタスクなので Haiku で十分。
#
# 使用方法:
#   ./summarize.sh <transcript.jsonl> <session_id>
# 環境変数（テスト用に上書き可能）:
#   CLAUDE_BIN / SESSIONS_ROOT / MAX_CHARS
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
SESSIONS_ROOT="${SESSIONS_ROOT:-$HOME/.nb/claude/sessions}"
# ★ Haiku 200K コンテキストへの安全弁（文字数上限）。超えたら切り詰める。
#   日本語混在で概ね 1.5 文字/トークンと見て、約12万文字 ≒ 8万トークン程度に抑える。
MAX_CHARS="${MAX_CHARS:-120000}"

transcript="${1:?usage: summarize.sh <transcript.jsonl> <session_id>}"
session_id="${2:?usage: summarize.sh <transcript.jsonl> <session_id>}"

# 前処理（失敗したら何もせず終了）
extracted="$(python3 "$SCRIPT_DIR/extract.py" "$transcript" 2>/dev/null)" || exit 0
# 中身が実質空（ヘッダのみ）なら要約しない
body_lines="$(printf '%s\n' "$extracted" | sed -n '/^---$/,$p' | tail -n +2 | grep -c .)" || body_lines=0
[ "$body_lines" -gt 0 ] || exit 0

# ガードA: 薄いセッション（ツール使用なし＆本文が極端に短い）は要約しない
tool_count="$(printf '%s\n' "$extracted" | grep -c '\[tool:')" || tool_count=0
body_chars="$(printf '%s\n' "$extracted" | sed -n '/^---$/,$p' | tail -n +2 | wc -m)"
if [ "$tool_count" -eq 0 ] && [ "$body_chars" -lt 200 ]; then
  exit 0
fi

# ヘッダ値を決定的にパース（frontmatter は Haiku に転記させず、この値から自前で組み立てる）
header="$(printf '%s\n' "$extracted" | sed -n '1,/^---$/p')"
get_header() {
  local key="$1"
  printf '%s\n' "$header" | sed -n "s/^${key}: //p" | head -1
}
proj_name="$(get_header project)"
[ -z "$proj_name" ] && proj_name="unknown"
cwd_val="$(get_header cwd)"
start_ts="$(get_header start)"
end_ts="$(get_header end)"

# ★ 上限ガード: extracted が極端に大きい場合は先頭2/3+末尾1/3を残す（セッションの結論・フィードバックは末尾に集中するため）
# ロケールを固定し文字単位の切り詰めを保証する
export LANG=ja_JP.UTF-8
# 超過時は先頭2/3 + 末尾1/3 を残す（セッションの結論・フィードバックは末尾に集中するため）
if [ "${#extracted}" -gt "$MAX_CHARS" ]; then
  head_n=$((MAX_CHARS * 2 / 3))
  tail_n=$((MAX_CHARS / 3))
  extracted="${extracted:0:$head_n}
（※ 会話が長いため、中略しています）
${extracted: -$tail_n}"
fi

# 対象日・時刻は end タイムスタンプ（JST）から決める。取れなければ今日/現在時刻。
target_date="$(TZ=Asia/Tokyo date -d "$end_ts" +%Y-%m-%d 2>/dev/null || TZ=Asia/Tokyo date +%Y-%m-%d)"
end_hhmm="$(TZ=Asia/Tokyo date -d "$end_ts" +%H%M 2>/dev/null || TZ=Asia/Tokyo date +%H%M)"
sid_short="${session_id:0:8}"
# ファイル名に使えない文字を念のためサニタイズ（スラッシュ等をハイフンに）
safe_proj="$(printf '%s' "$proj_name" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-')"

out_dir="$SESSIONS_ROOT/$target_date"
out_file="$out_dir/${safe_proj}-${end_hhmm}-${sid_short}.md"

read -r -d '' PROMPT <<EOF || true
以下は Claude Code の1セッションの会話ログ（前処理済み: 会話テキストとツール使用メタのみ）です。
このセッションを日本語で要約し、**下記7項目の Markdown 本文のみ**を出力してください。
前置き・後置き・frontmatter・コードフェンス（\`\`\`）は一切不要。出力は必ず「## 意図」の行から始めること。

各項目の書き方:
- ## 意図 — このセッションで何をしようとしたか（1〜2行）。冒頭で必ず「【レビュー作業】」または「【実装作業】」を明記すること（レビュー作業=他者のPRやコードを読んで指摘・確認する作業。実装作業=自分でコードを書く・修正する作業。両方を含む場合は主たる方を選び、もう一方も触れる）
- ## 作業内容 — 実際に行ったステップ（箇条書き）。レビュー作業なら「何をレビューし、どう指摘したか」を書く。実装作業なら「自分が何を書き換えたか」を書く。レビューで読んだだけ・調査で開いただけのコードを、自分が実装したかのように書かないこと
- ## 結論 — 何が分かった・何ができたか（1〜2行）
- ## 編集/作成ファイル — [tool:Edit/Write] で自分が実際に編集・作成したファイルのパスのみ。レビューや調査で [tool:Read] しただけのファイルは含めない。編集がなければ「なし（レビュー・調査のみ）」
- ## 実行した主なコマンド — [tool:Bash] の特徴的なコマンド。なければ省略
- ## ナレッジ候補 — memory に残す価値のある発見。なければ「なし」
- ## フィードバック/承認 — ユーザーから修正・指摘された点（pain）と、ユーザーが明確に承認・称賛した進め方（success）。なければ「なし」

=== 会話ログ ===
${extracted}
EOF

# Haiku で要約生成（不正出力なら1回だけリトライ）。
# 出力は「最初の ## 意図 以降を採用 → フェンス行除去 → 必須見出し検証」で決定的に整形・検証する。
# ★ プロンプトは stdin で渡す（引数渡しはツール使用の多い長セッションで ARG_MAX 超過 = E2BIG で即死するため）。
# ★ stderr は捨てず一時ファイルに残し、失敗時にログへ転記する（無音の失敗で原因追跡不能になるのを防ぐ）。
body=""
claude_err="$(mktemp)"
trap 'rm -f "$claude_err"' EXIT
for attempt in 1 2; do
  if ! raw="$(printf '%s' "$PROMPT" | "$CLAUDE_BIN" -p --model haiku --no-session-persistence --settings '{"disableAllHooks":true}' 2>"$claude_err")"; then
    echo "discarded(attempt=$attempt): claude 実行失敗: $session_id"
    sed 's/^/  claude stderr: /' "$claude_err"
    continue
  fi
  # 前置き除去（frontmatter・フェンス開始行の混入をここで捨てる）→ 残ったフェンス行を除去
  cand="$(printf '%s\n' "$raw" | sed -n '/^## 意図/,$p' | sed '/^```/d')"
  if printf '%s\n' "$cand" | grep -q '^## 作業内容' \
     && printf '%s\n' "$cand" | grep -q '^## 結論'; then
    body="$cand"
    break
  fi
  echo "discarded(attempt=$attempt): 必須見出し不足: $session_id"
done
[ -n "$body" ] || exit 0

# redaction: 会話にシークレットが混入していても要約ファイルに残さない（二重ガードの1段目）
body="$(printf '%s\n' "$body" | bash "$SCRIPT_DIR/../lib/redact.sh")" || exit 0

# 同一セッションの旧要約を削除（再開セッションは最新の要約が全期間をカバーするため1本に保つ）
find "$SESSIONS_ROOT" -type f -name "*-${sid_short}.md" ! -path "$out_file" -delete 2>/dev/null || true

# 組み立てはアトミックに: tmp に全て書いてから mv（途中失敗で壊れたファイルを残さない）
mkdir -p "$out_dir"
{
  printf -- '---\n'
  printf 'project: %s\n' "$proj_name"
  printf 'session_id: %s\n' "$session_id"
  printf 'start: %s\n' "$start_ts"
  printf 'end: %s\n' "$end_ts"
  printf 'cwd: %s\n' "$cwd_val"
  printf -- '---\n\n'
  printf '%s\n' "$body"
} > "${out_file}.tmp"
mv "${out_file}.tmp" "$out_file"

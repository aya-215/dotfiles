#!/bin/bash
# summarize.sh - セッション JSONL 1本を Haiku で6項目要約し、sessions/ に保存する
#
# extract.py で前処理（text + ツールメタ抽出）してから claude -p --model haiku に渡す。
# サブスク枠で動くため API 課金はなく、要約は軽いタスクなので Haiku で十分。
#
# 使用方法:
#   ./summarize.sh <transcript.jsonl> <session_id>
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_BIN="$HOME/.local/bin/claude"
readonly SESSIONS_ROOT="$HOME/.nb/claude/sessions"
# ★ Haiku 200K コンテキストへの安全弁（文字数またはバイト数の上限）。これを超えたら末尾を切り詰める。
#   日本語混在で概ね 1.5 文字/トークンと見て、約12万文字（LC_ALL=C 等では約12万バイト）≒ 8万トークン程度に抑える。
#   LANG=ja_JP.UTF-8 設定後は文字単位になる。
readonly MAX_CHARS=120000

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

# ★ 上限ガード: extracted が極端に大きい場合は先頭 MAX_CHARS 文字に切り詰める
#   （会話が長大でも Haiku の 200K を超えないようにする安全弁）
if [ "${#extracted}" -gt "$MAX_CHARS" ]; then
  extracted="${extracted:0:$MAX_CHARS}
（※ 会話が長いため、ここで切り詰めています）"
fi

# 対象日を JSONL の最終 timestamp（JST）から決める。取れなければ今日。
target_date="$(printf '%s\n' "$extracted" \
  | sed -n 's/^end: //p' | head -1 \
  | { read -r ts; [ -n "$ts" ] && TZ=Asia/Tokyo date -d "$ts" +%Y-%m-%d 2>/dev/null || TZ=Asia/Tokyo date +%Y-%m-%d; })"

out_dir="$SESSIONS_ROOT/$target_date"
mkdir -p "$out_dir"
out_file="$out_dir/$session_id.md"

read -r -d '' PROMPT <<EOF || true
以下は Claude Code の1セッションの会話ログ（前処理済み: 会話テキストとツール使用メタのみ）です。
このセッションを日本語で要約し、**下記6項目の Markdown のみ**を出力してください。前置き・後置きは一切不要。

各項目の書き方:
- ## 意図 — このセッションで何をしようとしたか（1〜2行）
- ## 作業内容 — 実際に行った調査・実装のステップ（箇条書き）
- ## 結論 — 何が分かった・何ができたか（1〜2行）
- ## 編集/作成ファイル — [tool:Edit/Write] のファイルパス。なければ「調査のみ」
- ## 実行した主なコマンド — [tool:Bash] の特徴的なコマンド。なければ省略
- ## ナレッジ候補 — memory に残す価値のある発見。なければ「なし」

冒頭に必ず以下の frontmatter を付けること（会話ログのヘッダの値を転記）:
---
project: <project>
session_id: <session_id>
start: <start>
end: <end>
cwd: <cwd>
---

=== 会話ログ ===
${extracted}
EOF

# ★ 上限ガード: 切り詰めブロックの前後でロケールを固定し文字単位を保証する
export LANG=ja_JP.UTF-8

# Haiku で要約生成（失敗したら中途半端なファイルを残さない）
# --settings '{"disableAllHooks":true}' で、この claude -p 実行が SessionEnd hook を
# 再発火させないようにする（さもないと「要約用 claude の終了 → また要約」の自己増殖ループになる）。
# --bare は hook を切れるが認証(OAuth/keychain)も読まなくなるため使わない。disableAllHooks は認証を保つ。
if ! "$CLAUDE_BIN" -p "$PROMPT" --model haiku --settings '{"disableAllHooks":true}' > "$out_file" 2>/dev/null; then
  rm -f "$out_file"
  exit 0
fi

# 空ファイル（claude が exit 0 で空出力を返したケース等）は残さない
[ -s "$out_file" ] || { rm -f "$out_file"; exit 0; }

# 後処理: frontmatter（最初の ---）より前の前置きを除去。--- が無ければ不正として削除。
if grep -q '^---' "$out_file"; then
  sed -i -n '/^---/,$p' "$out_file"
else
  rm -f "$out_file"
  exit 0
fi

# sed 後の空ファイル確認（念のため）
[ -s "$out_file" ] || { rm -f "$out_file"; exit 0; }

# ガードB: Haiku が要約せず聞き返した応答（「ログを提供してください」等）は不正として破棄
if grep -qE "提供してください|ご提供ください|セッションログには|必要な要素|実際の会話ログ|お知らせください" "$out_file"; then
  rm -f "$out_file"
  exit 0
fi

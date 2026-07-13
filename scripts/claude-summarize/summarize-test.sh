#!/bin/bash
# summarize-test.sh - summarize.sh の動作確認テスト
# 使用方法: bash scripts/claude-summarize/summarize-test.sh （全部 ok なら ALL OK で exit 0）
# claude 本体は呼ばず、スタブ（STUB_DIR/out.<n> を出力するだけのスクリプト）に差し替えて検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# ---- スタブ claude ----
# 呼び出し毎に calls をインクリメントし、受け取ったプロンプト($2)を prompt.<n> に保存、
# out.<n> があればそれを、なければ out を標準出力に返す。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/bash
set -u
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/calls"
printf '%s\n' "$2" > "$STUB_DIR/prompt.$n"
if [ -f "$STUB_DIR/out.$n" ]; then cat "$STUB_DIR/out.$n"; else cat "$STUB_DIR/out"; fi
EOF
chmod +x "$TMP/bin/claude"

# ---- fixture ----
readonly SID="aabbccdd-1111-2222-3333-444455556666"
readonly SID_SHORT="aabbccdd"

# make_transcript <path> — 最小限の transcript JSONL を作る
# end=2026-07-13T02:34:56Z → JST 11:34 → 出力ファイルは 2026-07-13/testproj-1134-aabbccdd.md
make_transcript() {
  local path="$1"
  cat > "$path" <<JSONL
{"type":"user","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-13T01:00:00.000Z","message":{"content":"テスト用の依頼です。設定ファイルを直してください。"}}
{"type":"assistant","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-13T02:34:56.000Z","message":{"content":[{"type":"text","text":"直しました"},{"type":"tool_use","name":"Edit","input":{"file_path":"/home/aya/testproj/a.conf"}}]}}
JSONL
}

# Haiku の正常な本文出力（frontmatter なし・本文のみ）
good_body() {
  cat <<'EOF'
## 意図
【実装作業】テスト用の設定修正

## 作業内容
- a.conf を修正

## 結論
完了

## 編集/作成ファイル
- /home/aya/testproj/a.conf

## 実行した主なコマンド
なし

## ナレッジ候補
なし

## フィードバック/承認
なし
EOF
}

# run_summarize <case_name> — ケース専用の STUB_DIR / SESSIONS_ROOT で summarize.sh を実行
# 呼ぶ前に $TMP/<case_name>/stub/out* を用意しておくこと。標準出力を返す。
run_summarize() {
  local case_name="$1"
  local case_dir="$TMP/$case_name"
  mkdir -p "$case_dir/stub" "$case_dir/sessions"
  make_transcript "$case_dir/transcript.jsonl"
  CLAUDE_BIN="$TMP/bin/claude" \
  STUB_DIR="$case_dir/stub" \
  SESSIONS_ROOT="$case_dir/sessions" \
    bash "$SCRIPT_DIR/summarize.sh" "$case_dir/transcript.jsonl" "$SID" 2>&1 || true
}

# assert_contains <説明> <ファイル> <含まれるべきパターン(grep -E)>
assert_contains() {
  local desc="$1" file="$2" pat="$3"
  if [ -f "$file" ] && grep -qE "$pat" "$file"; then
    echo "ok: $desc"
  else
    echo "NG: $desc → file=$file pat=$pat"
    fails=$((fails + 1))
  fi
}

# assert_absent <説明> <ファイルパス>
assert_absent() {
  local desc="$1" file="$2"
  if [ ! -e "$file" ]; then
    echo "ok: $desc"
  else
    echo "NG: $desc → 存在してはいけないファイルがある: $file"
    fails=$((fails + 1))
  fi
}

# ==== case1: 正常系（本文のみの出力から、frontmatter はスクリプトが組み立てる） ====
mkdir -p "$TMP/case1/stub"
good_body > "$TMP/case1/stub/out"
run_summarize case1 > /dev/null
out1="$TMP/case1/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_contains "case1: ファイルが生成される" "$out1" '^## 意図'
assert_contains "case1: project 転記" "$out1" '^project: testproj$'
assert_contains "case1: session_id 転記" "$out1" "^session_id: $SID\$"
assert_contains "case1: start 転記" "$out1" '^start: 2026-07-13T01:00:00\.000Z$'
assert_contains "case1: end 転記" "$out1" '^end: 2026-07-13T02:34:56\.000Z$'
assert_contains "case1: cwd 転記" "$out1" '^cwd: /home/aya/testproj$'
if [ -f "$out1" ] && [ "$(grep -c '^---$' "$out1")" -eq 2 ]; then
  echo "ok: case1: frontmatter 区切りがちょうど2本"
else
  echo "NG: case1: frontmatter 区切りが2本でない"
  fails=$((fails + 1))
fi
assert_absent "case1: tmp ファイルが残らない" "$out1.tmp"

# ==== 結果 ====
if [ "$fails" -eq 0 ]; then
  echo "ALL OK"
else
  echo "${fails} 件失敗"
  exit 1
fi

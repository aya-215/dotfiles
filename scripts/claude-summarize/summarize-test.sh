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

# ==== case2: コードフェンス包み・frontmatter混入の救済 ====
mkdir -p "$TMP/case2/stub"
{
  echo '```markdown'
  echo '---'
  echo 'project: testproj'
  echo '---'
  good_body
  echo '```'
} > "$TMP/case2/stub/out"
run_summarize case2 > /dev/null
out2="$TMP/case2/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_contains "case2: フェンス包みでもファイル生成される" "$out2" '^## 意図'
if [ -f "$out2" ] && ! grep -q '^```' "$out2"; then
  echo "ok: case2: フェンス行が残らない"
else
  echo "NG: case2: フェンス行が残っている"
  fails=$((fails + 1))
fi
if [ -f "$out2" ] && [ "$(grep -c '^---$' "$out2")" -eq 2 ]; then
  echo "ok: case2: frontmatter が二重にならない"
else
  echo "NG: case2: frontmatter 区切りが2本でない"
  fails=$((fails + 1))
fi

# ==== case3: 見出し不足が2回続いたら破棄してログを残す ====
mkdir -p "$TMP/case3/stub"
echo "要約できませんでした。会話ログを提供してください。" > "$TMP/case3/stub/out"
log3="$(run_summarize case3)"
out3="$TMP/case3/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_absent "case3: 不正出力はファイルを残さない" "$out3"
if printf '%s\n' "$log3" | grep -q "discarded(attempt=2)"; then
  echo "ok: case3: 破棄理由がログに出る"
else
  echo "NG: case3: 破棄ログがない → got: $log3"
  fails=$((fails + 1))
fi
if [ "$(cat "$TMP/case3/stub/calls")" -eq 2 ]; then
  echo "ok: case3: リトライ含め2回呼ばれる"
else
  echo "NG: case3: 呼び出し回数が2でない → $(cat "$TMP/case3/stub/calls")"
  fails=$((fails + 1))
fi

# ==== case4: 1回目不正 → 2回目正常でリトライ成功 ====
mkdir -p "$TMP/case4/stub"
echo "garbage" > "$TMP/case4/stub/out.1"
good_body > "$TMP/case4/stub/out.2"
run_summarize case4 > /dev/null
out4="$TMP/case4/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_contains "case4: リトライで復旧してファイル生成" "$out4" '^## 結論'
if [ "$(cat "$TMP/case4/stub/calls")" -eq 2 ]; then
  echo "ok: case4: ちょうど2回呼ばれる"
else
  echo "NG: case4: 呼び出し回数が2でない → $(cat "$TMP/case4/stub/calls")"
  fails=$((fails + 1))
fi

# ==== case5: 同一 session_id の旧要約は削除される（再開セッションの重複対策） ====
mkdir -p "$TMP/case5/stub" "$TMP/case5/sessions/2026-07-01"
good_body > "$TMP/case5/stub/out"
old5="$TMP/case5/sessions/2026-07-01/testproj-0900-$SID_SHORT.md"
echo "old summary" > "$old5"
# 別セッションのファイルは消えないことも確認する
other5="$TMP/case5/sessions/2026-07-01/testproj-0930-99999999.md"
echo "other session" > "$other5"
run_summarize case5 > /dev/null
out5="$TMP/case5/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_contains "case5: 新しい要約が生成される" "$out5" '^## 意図'
assert_absent "case5: 同一sidの旧要約が消える" "$old5"
assert_contains "case5: 別セッションのファイルは残る" "$other5" 'other session'

# ==== case6: 長い会話は先頭2/3+末尾1/3を残す（末尾の結論を捨てない） ====
case6_dir="$TMP/case6"
mkdir -p "$case6_dir/stub" "$case6_dir/sessions"
good_body > "$case6_dir/stub/out"
# HEADMARK を先頭付近、TAILMARK を末尾に置いた長い transcript（中間は詰め物で MAX_CHARS 超過させる）
filler="$(printf 'x%.0s' {1..2000})"
{
  printf '{"type":"user","sessionId":"%s","cwd":"/home/aya/testproj","timestamp":"2026-07-13T01:00:00.000Z","message":{"content":"HEADMARK 依頼開始"}}\n' "$SID"
  printf '{"type":"assistant","sessionId":"%s","timestamp":"2026-07-13T01:10:00.000Z","message":{"content":[{"type":"text","text":"%s"},{"type":"tool_use","name":"Edit","input":{"file_path":"/home/aya/testproj/a.conf"}}]}}\n' "$SID" "$filler"
  printf '{"type":"assistant","sessionId":"%s","timestamp":"2026-07-13T02:34:56.000Z","message":{"content":[{"type":"text","text":"TAILMARK 完了報告"}]}}\n' "$SID"
} > "$case6_dir/transcript.jsonl"
CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$case6_dir/stub" SESSIONS_ROOT="$case6_dir/sessions" MAX_CHARS=900 \
  bash "$SCRIPT_DIR/summarize.sh" "$case6_dir/transcript.jsonl" "$SID" > /dev/null 2>&1 || true
prompt6="$case6_dir/stub/prompt.1"
assert_contains "case6: 先頭側が残る" "$prompt6" 'HEADMARK'
assert_contains "case6: 末尾側が残る" "$prompt6" 'TAILMARK'
assert_contains "case6: 中略マーカーが入る" "$prompt6" '中略'

# ==== 結果 ====
if [ "$fails" -eq 0 ]; then
  echo "ALL OK"
else
  echo "${fails} 件失敗"
  exit 1
fi

#!/bin/bash
# backfill-test.sh - backfill.sh の動作確認テスト
# 使用方法: bash scripts/claude-summarize/backfill-test.sh （全部 ok なら ALL OK で exit 0）
# summarize.sh はスタブ（呼ばれた引数を calls.log に追記するだけ）に差し替えて検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# ---- スタブ summarize.sh ----
# 呼び出し毎に "引数1 引数2" を calls.log に追記する（要約は生成しない）
mkdir -p "$TMP/bin"
cat > "$TMP/bin/summarize.sh" <<'EOF'
#!/bin/bash
set -u
printf '%s %s\n' "$1" "$2" >> "$SUMMARIZE_CALLS"
EOF
chmod +x "$TMP/bin/summarize.sh"

# ---- fixture: projects と sessions を作る ----
# 3セッション: aaaaaaaa(未生成) / bbbbbbbb(生成済み) / cccccccc(未生成) + subagent(除外対象)
setup_fixture() {
  local root="$1"
  local proj="$root/projects/-home-aya-testproj"
  local sess="$root/sessions/2026-07-20"
  mkdir -p "$proj" "$sess" "$proj/subagents/workflows/wf_x"
  # jsonl は中身の有無を backfill は問わない（summarize.sh に委譲）ので最小限でよい
  echo '{"type":"user"}' > "$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/bbbbbbbb-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/cccccccc-1111-2222-3333-444444444444.jsonl"
  echo '{"type":"user"}' > "$proj/subagents/workflows/wf_x/agent-dddddddd.jsonl"
  # bbbbbbbb だけ要約 md が既に存在する
  echo '# summary' > "$sess/testproj-0900-bbbbbbbb.md"
}

# assert_contains / assert_absent（summarize-test.sh と同型）
assert_line_count() {
  local desc="$1" file="$2" expected="$3"
  local got; got="$(wc -l < "$file" 2>/dev/null || echo 0)"
  if [ "$got" -eq "$expected" ]; then echo "ok: $desc"; else
    echo "NG: $desc → 期待 $expected 行 / 実際 $got 行"; fails=$((fails + 1)); fi
}
assert_grep() {
  local desc="$1" file="$2" pat="$3"
  if [ -f "$file" ] && grep -qE "$pat" "$file"; then echo "ok: $desc"; else
    echo "NG: $desc → file=$file pat=$pat"; fails=$((fails + 1)); fi
}
assert_not_grep() {
  local desc="$1" file="$2" pat="$3"
  if [ -f "$file" ] && grep -qE "$pat" "$file"; then
    echo "NG: $desc → 含んではいけない: $pat"; fails=$((fails + 1)); else echo "ok: $desc"; fi
}

# ==== case1: --dry-run は未生成2件だけを出力し subagent と生成済みを除外 ====
root1="$TMP/case1"; setup_fixture "$root1"
out1="$TMP/case1.out"
PROJECTS_ROOT="$root1/projects" SESSIONS_ROOT="$root1/sessions" \
  bash "$SCRIPT_DIR/backfill.sh" --dry-run > "$out1" 2>/dev/null || true
assert_line_count "case1: 未生成2件が出力される" "$out1" 2
assert_grep "case1: aaaaaaaa が対象" "$out1" 'aaaaaaaa-1111'
assert_grep "case1: cccccccc が対象" "$out1" 'cccccccc-1111'
assert_not_grep "case1: bbbbbbbb(生成済み)は除外" "$out1" 'bbbbbbbb'
assert_not_grep "case1: subagent は除外" "$out1" 'subagents'

# ==== 結果 ====
if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "${fails} 件失敗"; exit 1; fi

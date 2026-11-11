#!/bin/bash
# run-unattended-test.sh - run-unattended.sh の動作確認テスト（claude はスタブ）
# 使用方法: bash scripts/todo-ai/run-unattended-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly RUN="$SCRIPT_DIR/run-unattended.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1)); fi
}
has() {
  if grep -qF -- "$3" "$2" 2>/dev/null; then echo "ok   $1"; else echo "FAIL $1 (missing: $3)"; fails=$((fails + 1)); fi
}

# スタブ: 呼ばれた引数を記録し、STUB_RC で終了する
cat > "$TMP/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_ARGS"
echo "STUB OUTPUT"
exit "${STUB_RC:-0}"
EOF
chmod +x "$TMP/claude"
mkdir -p "$TMP/skill"
: > "$TMP/skill/SKILL.md"

export CLAUDE_BIN="$TMP/claude"
export TODO_AI_LOG_ROOT="$TMP/log"
export TODO_AI_SKILL_FILE="$TMP/skill/SKILL.md"
export STUB_ARGS="$TMP/args"
day="$(date +%Y-%m-%d)"

# --dry-run: コマンドを表示するだけで claude を呼ばない
rm -f "$STUB_ARGS"
bash "$RUN" --dry-run > "$TMP/dry.out"
has "dry-run に /todo" "$TMP/dry.out" "/todo"
has "dry-run に disableAllHooks" "$TMP/dry.out" "disableAllHooks"
has "dry-run に permission-mode" "$TMP/dry.out" "--permission-mode"
check "dry-run は claude を呼ばない" "no" "$([ -e "$STUB_ARGS" ] && echo yes || echo no)"

# 本実行: スタブが呼ばれ、ログが日付フォルダに残る
rm -f "$STUB_ARGS"
rc=0; bash "$RUN" > /dev/null 2>&1 || rc=$?
check "本実行は exit 0" "0" "$rc"
has "claude に -p" "$STUB_ARGS" "-p"
has "claude に /todo" "$STUB_ARGS" "/todo"
has "claude に disableAllHooks" "$STUB_ARGS" '{"disableAllHooks":true}'
log="$(ls "$TODO_AI_LOG_ROOT/$day"/run-*.log 2>/dev/null | head -1)"
has "ログにスタブの出力" "$log" "STUB OUTPUT"

# claude の失敗は終了コードで返す
rc=0; STUB_RC=7 bash "$RUN" > /dev/null 2>&1 || rc=$?
check "claude の終了コードを返す" "7" "$rc"

# スキルが無い（メイン checkout が main 以外）ときは claude を呼ばずに exit 1
rm -f "$STUB_ARGS"
rc=0; TODO_AI_SKILL_FILE="$TMP/none/SKILL.md" bash "$RUN" > "$TMP/noskill.out" 2>&1 || rc=$?
check "スキルが無いと exit 1" "1" "$rc"
check "スキルが無いと claude を呼ばない" "no" "$([ -e "$STUB_ARGS" ] && echo yes || echo no)"
has "スキルが無い理由を出す" "$TMP/noskill.out" "SKILL.md"

# 実行中なら二重起動しない
rm -f "$STUB_ARGS"
mkdir -p "$TODO_AI_LOG_ROOT"
exec 9> "$TODO_AI_LOG_ROOT/run-unattended.lock"
flock -n 9
rc=0; bash "$RUN" > "$TMP/locked.out" 2>&1 || rc=$?
exec 9>&-
check "実行中なら exit 0" "0" "$rc"
check "実行中なら claude を呼ばない" "no" "$([ -e "$STUB_ARGS" ] && echo yes || echo no)"
has "実行中である旨を出す" "$TMP/locked.out" "実行中"

if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "$fails FAILED"; exit 1; fi

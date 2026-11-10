#!/bin/bash
# fire-daily-review-test.sh - fire-daily-review.sh の動作確認テスト（RC・メール・切り出しはスタブ）
# 使用方法: bash scripts/daily-review/fire-daily-review-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1)); fi
}

# has <name> <file> <needle> / lacks — ファイルに固定文字列が含まれる／含まれないこと
has() {
  if grep -qF -- "$3" "$2" 2>/dev/null; then echo "ok   $1"; else echo "FAIL $1 (missing: $3)"; fails=$((fails + 1)); fi
}
lacks() {
  if grep -qF -- "$3" "$2" 2>/dev/null; then echo "FAIL $1 (unexpected: $3)"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

# ---- スタブ ----
: > "$TMP/env"
printf '#!/bin/bash\necho "RCSTUB"\n' > "$TMP/rc.sh"
printf '#!/bin/bash\nexit 0\n' > "$TMP/mail.sh"
# 切り出しスタブ: $STUB_SLICES_SRC/<date> があれば $SLICES_ROOT/<date> へ複製する
cat > "$TMP/slice.sh" <<'EOF2'
#!/bin/bash
src="${STUB_SLICES_SRC:-}/$1"
if [ -d "$src" ]; then
  mkdir -p "$SLICES_ROOT/$1"
  cp -a "$src/." "$SLICES_ROOT/$1/"
fi
echo "slices: written=0 failed=0 candidates=0"
echo "[stubsid] stub stderr line" >&2
EOF2

# mk_md <path> <project> <sid> <end> <body>
mk_md() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nproject: %s\nsession_id: %s\nstart: 2026-11-04T09:00:00+09:00\nend: %s\n---\n%s\n' "$2" "$3" "$4" "$5" > "$1"
}

# run_case <name> <args...> — ケース別に環境を作り直して fire を --dry-run 以外の引数付きで走らせる
# 事前に $C（ケースのルート）下へ fixtures を置く。終了コードを RC に入れる。
run_fire() {
  C="$1"; shift
  set +e
  HOME="$C/home" FIRE_ENV_FILE="$TMP/env" ROCKETCHAT_BIN="$TMP/rc.sh" MAIL_ARCHIVE_BIN="$TMP/mail.sh" \
    SLICE_BIN="$TMP/slice.sh" SESSIONS_ROOT="$C/sessions" SLICES_ROOT="$C/slices" \
    FIRE_LOG_FILE="$C/fire.log" STUB_SLICES_SRC="$C/src" \
    bash "$SCRIPT_DIR/fire-daily-review.sh" "$@" > "$C/stdout" 2> "$C/stderr"
  RC=$?
  set -e
}

# ---- ケース1: 切り出し2本 ----
C="$TMP/c1"; mkdir -p "$C/home"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
mk_md "$C/src/2026-11-04/.dotfiles-bbbbbbbb.md" .dotfiles bbbbbbbb-1 2026-11-04T11:00:00+09:00 "SLICE_B_BODY"
mk_md "$C/sessions/2026-11-04/projA-zzzzzzzz.md" projA zzzzzzzz-1 2026-11-04T12:00:00+09:00 "OLD_SESSION_BODY"
run_fire "$C" --dry-run --date 2026-11-04
check "c1 exit 0" 0 "$RC"
P="$C/slices/2026-11-04/payload.txt"
has "c1 切り出しA" "$P" "SLICE_A_BODY"
has "c1 切り出しB（隠しファイル）" "$P" "SLICE_B_BODY"
has "c1 区切り行" "$P" "【区切り】2026-11-03T22:10:00+09:00 〜 2026-11-04T22:10:00+09:00（セッション要約はこの範囲のやりとりだけを要約済み）"
lacks "c1 既存要約は入らない" "$P" "OLD_SESSION_BODY"
lacks "c1 上書きモード行なし" "$P" "【再生成モード】"
has "c1 見出しは end の時刻" "$P" "## projA — 10:00"
has "c1 切り出しスタブ出力がログに残る" "$C/fire.log" "slices: written=0"
has "c1 切り出しstderrもログに残る" "$C/fire.log" "[stubsid] stub stderr line"
check "c1 1行目は対象日" "【対象日】2026-11-04" "$(sed -n 1p "$P")"
check "c1 区切り行の位置（対象日の次の行）" 1 "$(sed -n 2p "$P" | grep -c '^【区切り】')"

# ---- ケース2: .failed の sid は既存要約で埋める ----
C="$TMP/c2"; mkdir -p "$C/home"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
printf 'cccccccc\n' > "$C/src/2026-11-04/.failed"
mk_md "$C/sessions/2026-11-05/projC-cccccccc.md" projC cccccccc-1 2026-11-05T01:00:00+09:00 "FALLBACK_C_BODY"
mk_md "$C/sessions/2026-11-04/projD-dddddddd.md" projD dddddddd-1 2026-11-04T12:00:00+09:00 "UNRELATED_D_BODY"
run_fire "$C" --dry-run --date 2026-11-04
P="$C/slices/2026-11-04/payload.txt"
check "c2 exit 0" 0 "$RC"
has "c2 切り出し" "$P" "SLICE_A_BODY"
has "c2 失敗sidの既存要約" "$P" "FALLBACK_C_BODY"
lacks "c2 無関係の既存要約は入らない" "$P" "UNRELATED_D_BODY"

# ---- ケース3: 切り出し0本・sessions あり（今の方式） ----
C="$TMP/c3"; mkdir -p "$C/home"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SESSIONS_ONLY_BODY"
run_fire "$C" --dry-run --date 2026-11-04
check "c3 exit 0" 0 "$RC"
has "c3 既存要約が入る" "$C/slices/2026-11-04/payload.txt" "SESSIONS_ONLY_BODY"

# ---- ケース4: 両方0本 ----
C="$TMP/c4"; mkdir -p "$C/home"
run_fire "$C" --dry-run --date 2026-11-04
check "c4 exit 0" 0 "$RC"
check "c4 payload.txt は作られない" "no" "$([ -e "$C/slices/2026-11-04/payload.txt" ] && echo yes || echo no)"
has "c4 skip ログ" "$C/fire.log" "skip:"

# ---- ケース5: --overwrite ----
C="$TMP/c5"; mkdir -p "$C/home"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
run_fire "$C" --dry-run --date 2026-11-04 --overwrite
check "c5 exit 0" 0 "$RC"
has "c5 上書きモード行" "$C/slices/2026-11-04/payload.txt" "【再生成モード】上書き（既存の「📝 サマリー」は引き継がず、このペイロードだけで作り直す）"
C="$TMP/c6"; mkdir -p "$C/home"
run_fire "$C" --dry-run --overwrite
check "c6 --overwrite 単独は exit 2" 2 "$RC"

echo
if [ "$fails" -eq 0 ]; then echo "ALL OK"; else echo "$fails FAILED"; exit 1; fi

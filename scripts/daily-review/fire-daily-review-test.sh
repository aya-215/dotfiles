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

# run_fire <ケースのルート> <fire の引数...> — 事前に $C 下へ fixtures を置いておく。終了コードを RC に入れる。
run_fire() {
  C="$1"; shift
  set +e
  HOME="$C/home" FIRE_ENV_FILE="$TMP/env" ROCKETCHAT_BIN="$TMP/rc.sh" MAIL_ARCHIVE_BIN="$TMP/mail.sh" \
    SLICE_BIN="${SLICE_BIN:-$TMP/slice.sh}" SESSIONS_ROOT="$C/sessions" SLICES_ROOT="$C/slices" \
    FIRE_LOG_FILE="$C/fire.log" STUB_SLICES_SRC="$C/src" FIRE_GIT_ROOTS="${FIRE_GIT_ROOTS:-$C/home/.dotfiles}" \
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
has "c2 補完の印" "$P" "## projC — 01:00（全期間の要約・補完）"
lacks "c2 切り出しに印は付かない" "$P" "## projA — 10:00（全期間"
lacks "c2 無関係の既存要約は入らない" "$P" "UNRELATED_D_BODY"

# ---- ケース3: 切り出し0本・sessions あり（今の方式） ----
C="$TMP/c3"; mkdir -p "$C/home"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SESSIONS_ONLY_BODY"
run_fire "$C" --dry-run --date 2026-11-04
check "c3 exit 0" 0 "$RC"
has "c3 既存要約が入る" "$C/slices/2026-11-04/payload.txt" "SESSIONS_ONLY_BODY"
has "c3 旧方式にも補完の印" "$C/slices/2026-11-04/payload.txt" "## projA — 10:00（全期間の要約・補完）"

# ---- ケース4: 両方0本 ----
C="$TMP/c4"; mkdir -p "$C/home"
run_fire "$C" --dry-run --date 2026-11-04
check "c4 exit 0" 0 "$RC"
check "c4 payload.txt は作られない" "no" "$([ -e "$C/slices/2026-11-04/payload.txt" ] && echo yes || echo no)"
has "c4 skip ログ" "$C/fire.log" "skip:"
check "c4 skipped マーカーが作られる" "yes" "$([ -e "$C/slices/2026-11-04/skipped" ] && echo yes || echo no)"

# ---- ケース7: .failed だけあって切り出し md が0本 → 旧方式 ----
C="$TMP/c7"; mkdir -p "$C/home" "$C/src/2026-11-04"
printf 'cccccccc\n' > "$C/src/2026-11-04/.failed"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "OLDPATH_BODY"
run_fire "$C" --dry-run --date 2026-11-04
has "c7 .failed のみでも旧方式で送る" "$C/slices/2026-11-04/payload.txt" "OLDPATH_BODY"

# ---- ケース8: 切り出しがタイムアウト ----
cp "$TMP/slice.sh" "$TMP/slice-ok.sh"
printf '#!/bin/bash\nsleep 30\n' > "$TMP/slice-hang.sh"
C="$TMP/c8"; mkdir -p "$C/home"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "TIMEOUT_FALLBACK_BODY"
SLICE_BIN="$TMP/slice-hang.sh" SLICE_TIMEOUT=2 run_fire "$C" --dry-run --date 2026-11-04
check "c8 exit 0" 0 "$RC"
has "c8 payload は作られる" "$C/slices/2026-11-04/payload.txt" "TIMEOUT_FALLBACK_BODY"
has "c8 timeout ログ" "$C/fire.log" "slice: timeout"

# ---- ケース9: 切り出しが異常終了／存在しない ----
printf '#!/bin/bash\necho boom >&2\nexit 5\n' > "$TMP/slice-fail.sh"
C="$TMP/c9"; mkdir -p "$C/home"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "FAILSLICE_BODY"
SLICE_BIN="$TMP/slice-fail.sh" run_fire "$C" --dry-run --date 2026-11-04
check "c9 exit 0" 0 "$RC"
has "c9 旧方式で送る" "$C/slices/2026-11-04/payload.txt" "FAILSLICE_BODY"
C="$TMP/c10"; mkdir -p "$C/home"
mk_md "$C/sessions/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "NOSLICE_BODY"
SLICE_BIN="$TMP/does-not-exist.sh" run_fire "$C" --dry-run --date 2026-11-04
check "c10 exit 0" 0 "$RC"
has "c10 SLICE_BIN 不在でも旧方式で送る" "$C/slices/2026-11-04/payload.txt" "NOSLICE_BODY"

# ---- ケース11: payload.txt を書けなくても送信は止まらない / fallback なしログ ----
C="$TMP/c11"; mkdir -p "$C/home" "$C/slices"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
printf 'dddddddd\n' > "$C/src/2026-11-04/.failed"
mkdir -p "$C/slices/2026-11-04/payload.txt"   # ディレクトリにして書き込みを失敗させる
run_fire "$C" --dry-run --date 2026-11-04
check "c11 保存失敗でも exit 0" 0 "$RC"
has "c11 保存失敗の警告" "$C/fire.log" "warn: payload.txt 保存失敗"
has "c11 fallback なしログ" "$C/fire.log" "slice: fallback なし dddddddd"
has "c11 ペイロードは標準出力へ出る" "$C/stdout" "SLICE_A_BODY"

# ---- ケース12: git 行は月日付き ----
C="$TMP/c12"; mkdir -p "$C/home/.dotfiles"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
G="$C/home/.dotfiles"
git -C "$G" init -q
GIT_AUTHOR_DATE="2026-11-03T23:00:00+09:00" GIT_COMMITTER_DATE="2026-11-03T23:00:00+09:00" \
  git -C "$G" -c user.name=t -c user.email=mori.a@ebase.co.jp commit -q --allow-empty -m "GITLINE_X" --author="t <mori.a@ebase.co.jp>"
run_fire "$C" --dry-run --date 2026-11-04
has "c12 git 行に月日" "$C/slices/2026-11-04/payload.txt" "11/03 23:00"
has "c12 git 見出し" "$C/slices/2026-11-04/payload.txt" "【git活動（区切り内のコミット"

# ---- ケース13: リポジトリ名とラベルは origin で決まる ----
C="$TMP/c13"; mkdir -p "$C/home" "$C/roots"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
# mkcommit <repo> <msg> <author-email>
mkcommit() {
  GIT_AUTHOR_DATE="2026-11-03T23:00:00+09:00" GIT_COMMITTER_DATE="2026-11-03T23:00:00+09:00" \
    git -C "$1" -c user.name=t -c user.email="$3" commit -q --allow-empty -m "$2" --author="t <$3>"
}
ME=mori.a@ebase.co.jp
R="$C/roots"
git init -q "$R/dotfiles" && git -C "$R/dotfiles" remote add origin git@github-aya215:aya-215/dotfiles.git
mkcommit "$R/dotfiles" PERS_COMMIT $ME
git init -q --bare "$C/bare.git"
git init -q "$R/main-clone" && git -C "$R/main-clone" remote add origin "$C/bare/eb-api-extended.git"
mkcommit "$R/main-clone" SHARED_COMMIT $ME
mkcommit "$R/main-clone" OTHER_AUTHOR_COMMIT someone@example.com
git -C "$R/main-clone" worktree add -q "$R/wt-feat" -b feat >/dev/null 2>&1
git clone -q "$R/main-clone" "$R/eae-docs-x" 2>/dev/null
git -C "$R/eae-docs-x" remote set-url origin "$C/bare/eb-api-extended.git"
git init -q "$R/gb" && git -C "$R/gb" remote add origin http://192.168.208.80:8080/gitbucket/git/eBASE/release-skills-repo.git
mkcommit "$R/gb" GB_COMMIT $ME
git init -q "$R/localonly"
mkcommit "$R/localonly" LOCAL_COMMIT $ME
mkdir -p "$R/notarepo"
# 壊れた gitfile（存在しない gitdir）があっても他は収集される
mkdir -p "$R/broken" && printf 'gitdir: /nonexistent/xx/.git/worktrees/y\n' > "$R/broken/.git"
FIRE_GIT_ROOTS="$R/*/
$C/missing/*/" run_fire "$C" --dry-run --date 2026-11-04
P="$C/slices/2026-11-04/payload.txt"
check "c13 exit 0" 0 "$RC"
has "c13 個人 GitHub は Personal" "$P" "### [Personal] dotfiles"
has "c13 origin 名で集約（Work）" "$P" "### [Work] eb-api-extended"
check "c13 同名見出しは1つ" 1 "$(grep -c '^### \[Work\] eb-api-extended' "$P")"
check "c13 同じコミットは1行" 1 "$(grep -c SHARED_COMMIT "$P")"
has "c13 GitBucket は Work" "$P" "### [Work] eBASE/release-skills-repo"
has "c13 origin 無しはディレクトリ名で Work" "$P" "### [Work] localonly"
lacks "c13 他人の author は入らない" "$P" "OTHER_AUTHOR_COMMIT"
lacks "c13 clone 名の見出しは出ない" "$P" "eae-docs-x"
check "c13 Personal が Work より先" 1 "$([ "$(grep -n '\[Personal\]' "$P" | head -1 | cut -d: -f1)" -lt "$(grep -n '\[Work\]' "$P" | head -1 | cut -d: -f1)" ] && echo 1 || echo 0)"

# ---- ケース14: 同名の GitBucket リポジトリは group で分かれる ----
C="$TMP/c14"; mkdir -p "$C/home" "$C/roots"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
for g in groupA groupB; do
  git init -q "$C/roots/$g" && git -C "$C/roots/$g" remote add origin "http://192.168.208.80:8080/gitbucket/git/$g/ebase-web.git"
  mkcommit "$C/roots/$g" "COMMIT_$g" $ME
done
FIRE_GIT_ROOTS="$C/roots/*/" run_fire "$C" --dry-run --date 2026-11-04
P="$C/slices/2026-11-04/payload.txt"
has "c14 groupA は別見出し" "$P" "### [Work] groupA/ebase-web"
has "c14 groupB は別見出し" "$P" "### [Work] groupB/ebase-web"

# ---- ケース15: マージ一覧と、要約から外す3節 ----
C="$TMP/c15"; mkdir -p "$C/home" "$C/roots"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "## 作業内容
WORK_BODY
## 実行した主なコマンド
CMD_BODY
## ナレッジ候補
KNOW_BODY
## フィードバック/承認
FB_BODY
## 結論
CONCL_BODY"
git init -q "$C/roots/ebase-portal-chat" && git -C "$C/roots/ebase-portal-chat" remote add origin git@github.com:ebase-dev/ebase-portal-chat.git
mkcommit "$C/roots/ebase-portal-chat" "Merge pull request #1202 from ebase-dev/feat/1013-x" $ME
FIRE_GIT_ROOTS="$C/roots/*/" run_fire "$C" --dry-run --date 2026-11-04
P="$C/slices/2026-11-04/payload.txt"
has "c15 マージ節の見出し" "$P" "【区切り内にマージされたPR】"
has "c15 マージ行" "$P" "- ebase-portal-chat #1202（ebase-dev/feat/1013-x、11/03 23:00）"
has "c15 作業内容は残る" "$P" "## 作業内容"
has "c15 結論は残る" "$P" "CONCL_BODY"
lacks "c15 コマンド節の見出し" "$P" "## 実行した主なコマンド"
lacks "c15 コマンド節の中身" "$P" "CMD_BODY"
lacks "c15 ナレッジ節" "$P" "KNOW_BODY"
lacks "c15 フィードバック節" "$P" "FB_BODY"
has "c15 切り出し md 自体は不変" "$C/src/2026-11-04/projA-aaaaaaaa.md" "CMD_BODY"
C="$TMP/c16"; mkdir -p "$C/home"
mk_md "$C/src/2026-11-04/projA-aaaaaaaa.md" projA aaaaaaaa-1 2026-11-04T10:00:00+09:00 "SLICE_A_BODY"
run_fire "$C" --dry-run --date 2026-11-04
check "c16 マージ無しは (なし)" "(なし)" "$(grep -A1 '^【区切り内にマージされたPR】' "$C/slices/2026-11-04/payload.txt" | tail -1)"

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

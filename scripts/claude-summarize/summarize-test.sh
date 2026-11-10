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
# 呼び出し毎に calls をインクリメントし、受け取ったプロンプト（stdin）を prompt.<n> に保存、
# out.<n> があればそれを、なければ out を標準出力に返す。
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/bin/bash
set -u
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/calls"
# 受け取った引数を1行1個で記録（フラグ検証用）
printf '%s\n' "$@" > "$STUB_DIR/args.$n"
cat > "$STUB_DIR/prompt.$n"
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

# ==== case1b: clean config 遮断フラグが claude に渡っている ====
# 要約サブプロセスがユーザーの CLAUDE.md/output-style（会話ペルソナ）を継承すると、
# 要約プロンプトを会話の続きと誤解して質問返しし、必須見出し不足で discard される
# （実データ 6件で確認）。これを決定的に防ぐため、要約専用の system-prompt と
# 設定ソース遮断が claude 呼び出しに必ず付くことを検証する。
args1="$TMP/case1/stub/args.1"
assert_contains "case1b: --system-prompt が渡る" "$args1" '^--system-prompt$'
assert_contains "case1b: --setting-sources が渡る" "$args1" '^--setting-sources$'
assert_contains "case1b: --no-session-persistence が渡る（自己参照ループ防止・回帰ガード）" "$args1" '^--no-session-persistence$'
# 値まで検証（真因が「設定源の継承」なので、将来 user,project 等に書き換わったら検知したい）。
# args.1 は1引数1行。--setting-sources の次行が空（＝''）であることを確認する。
if awk '/^--setting-sources$/{getline nxt; exit (nxt=="" ? 0 : 1)}' "$args1"; then
  echo "ok: case1b: --setting-sources の値が空（ユーザー設定源を継承しない）"
else
  echo "NG: case1b: --setting-sources の値が空でない（設定源が継承され得る）"
  fails=$((fails + 1))
fi
# --system-prompt の値が要約専用 system（対話禁止指示）であることを確認する。
if awk '/^--system-prompt$/{getline nxt; exit (index(nxt,"summarization tool")>0 ? 0 : 1)}' "$args1"; then
  echo "ok: case1b: --system-prompt が要約専用 system に置き換わっている"
else
  echo "NG: case1b: --system-prompt の値が要約専用 system でない"
  fails=$((fails + 1))
fi

# ==== case1c: 質問終わり継続モードのエスカレーション救済 ====
# 会話ログ末尾が質問で終わると Haiku が要約せず会話継続することがある（実データ 5a736154）。
# attempt1 で会話返し（見出し無し）→ discard、attempt2 でエスカレーション版プロンプトで
# 再要求し正常な7項目が返る、という救済フローを検証する。
mkdir -p "$TMP/case1c/stub"
# attempt1 の出力: 要約でなく会話への応答（必須見出し無し）
cat > "$TMP/case1c/stub/out.1" <<'OUT1'
承知しました。どの形式でまとめるのが良いか、ご希望をお聞かせください。
OUT1
# attempt2 の出力: 正常な7項目本文
good_body > "$TMP/case1c/stub/out.2"
log1c="$(run_summarize case1c)"
out1c="$TMP/case1c/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
# 1発目 discard→2発目で救済され md が生成される
assert_contains "case1c: エスカレーション再試行で md 生成される" "$out1c" '^## 意図'
assert_contains "case1c: 救済後に必須見出しが揃う" "$out1c" '^## 結論'
# attempt1 のプロンプトに構造修正（終端デリミタ）が入っている
assert_contains "case1c: attempt1 に終端デリミタ" "$TMP/case1c/stub/prompt.1" 'TRANSCRIPT_END'
# attempt2 のプロンプトにエスカレーション前置きが入っている
assert_contains "case1c: attempt2 にエスカレーション前置き" "$TMP/case1c/stub/prompt.2" '前回の出力は要約になっていませんでした'
# 1発目の discard がログに出る
if printf '%s\n' "$log1c" | grep -q 'discarded(attempt=1): 必須見出し不足'; then
  echo "ok: case1c: attempt1 の discard がログに出る"
else
  echo "NG: case1c: attempt1 の discard がログに出ない"
  fails=$((fails + 1))
fi

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

# ==== case7: entrypoint=sdk-cli のセッションは要約されない（自己参照ループ防止） ====
case7_dir="$TMP/case7"
mkdir -p "$case7_dir/stub" "$case7_dir/sessions"
good_body > "$case7_dir/stub/out"
# entrypoint フィルタが無ければガードA（tool_count==0 かつ本文200字未満）をすり抜けて
# md 生成される十分な内容にする（tool_use あり・本文200字以上）。
# これにより「フィルタが実際に効いて本文を空にしている」ことを検証できる。
case7_filler="$(printf 'あ%.0s' {1..250})"
cat > "$case7_dir/transcript.jsonl" <<JSONL
{"type":"user","sessionId":"$SID","cwd":"/home/aya/testproj","entrypoint":"sdk-cli","timestamp":"2026-07-13T01:00:00.000Z","message":{"content":"要約プロンプト本文 $case7_filler"}}
{"type":"assistant","sessionId":"$SID","cwd":"/home/aya/testproj","entrypoint":"sdk-cli","timestamp":"2026-07-13T02:34:56.000Z","message":{"content":[{"type":"text","text":"要約結果 $case7_filler"},{"type":"tool_use","name":"Edit","input":{"file_path":"/home/aya/testproj/a.conf"}}]}}
JSONL
CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$case7_dir/stub" SESSIONS_ROOT="$case7_dir/sessions" \
  bash "$SCRIPT_DIR/summarize.sh" "$case7_dir/transcript.jsonl" "$SID" > /dev/null 2>&1 || true
out7="$case7_dir/sessions/2026-07-13/testproj-1134-$SID_SHORT.md"
assert_absent "case7: sdk-cli セッションは md 生成されない" "$out7"

# ==== case8: entrypoint 欠落（従来 fixture 相当）は従来通り要約される（回帰防止） ====
# ※ case1 が既に entrypoint 無し fixture で md 生成を検証済みなので、ここは明示の再確認は省略可。
#   万一 case1 が変わった場合の保険として本文コメントで意図を残す。

# ==== 切り出しモード（case9〜12） ====
# 22:09(範囲前) / 22:10(範囲内・Edit あり) / 22:11 / 翌日22:10(範囲外) の4行
make_slice_transcript() {
  local path="$1"
  cat > "$path" <<JSONL
{"type":"user","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:09:00.000Z","message":{"content":"LINE-A 前日の経緯"}}
{"type":"assistant","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:10:00.000Z","message":{"content":[{"type":"text","text":"LINE-B 範囲内"},{"type":"tool_use","name":"Edit","input":{"file_path":"/home/aya/testproj/a.conf"}}]}}
{"type":"user","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-13T13:11:00.000Z","message":{"content":"LINE-C 範囲内"}}
{"type":"assistant","sessionId":"$SID","cwd":"/home/aya/testproj","timestamp":"2026-07-14T13:10:00.000Z","message":{"content":[{"type":"text","text":"LINE-D 範囲外"}]}}
JSONL
}

# run_slice <case_name> — 切り出しモードで実行し、終了コードを $slice_rc に入れる
slice_rc=0
run_slice() {
  local case_name="$1"
  local case_dir="$TMP/$case_name"
  mkdir -p "$case_dir/stub" "$case_dir/sessions" "$case_dir/slices"
  make_slice_transcript "$case_dir/transcript.jsonl"
  slice_rc=0
  CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$case_dir/stub" \
  SESSIONS_ROOT="$case_dir/sessions" SLICES_ROOT="$case_dir/slices" \
    bash "$SCRIPT_DIR/summarize.sh" "$case_dir/transcript.jsonl" "$SID" \
      --slice 2026-07-14 --since 2026-07-13T22:10:00+09:00 --until 2026-07-14T22:10:00+09:00 \
      > "$case_dir/log" 2>&1 || slice_rc=$?
}

# ==== case9: 切り出しモードの正常系 ====
mkdir -p "$TMP/case9/stub"
good_body > "$TMP/case9/stub/out"
run_slice case9
out9="$TMP/case9/slices/2026-07-14/testproj-$SID_SHORT.md"
assert_contains "case9: 切り出し要約が生成される" "$out9" '^## 意図'
assert_contains "case9: window_since" "$out9" '^window_since: 2026-07-13T22:10:00\+09:00$'
assert_contains "case9: window_until" "$out9" '^window_until: 2026-07-14T22:10:00\+09:00$'
assert_contains "case9: session_start は範囲外を含む全体の先頭" "$out9" '^session_start: 2026-07-13T13:09:00\.000Z$'
assert_contains "case9: start は範囲内の先頭" "$out9" '^start: 2026-07-13T13:10:00\.000Z$'
assert_contains "case9: end は範囲内の末尾" "$out9" '^end: 2026-07-13T13:11:00\.000Z$'
assert_contains "case9: スタブに claude-sonnet-5 が渡る" "$TMP/case9/stub/args.1" '^claude-sonnet-5$'
if [ "$slice_rc" -eq 0 ]; then echo "ok: case9: 終了コード 0"; else echo "NG: case9: 終了コード $slice_rc"; fails=$((fails + 1)); fi
assert_absent "case9: sessions/ には書かない" "$TMP/case9/sessions/2026-07-13"

# ==== case10: 範囲前の発言は CONTEXT、範囲内の発言は TRANSCRIPT にだけ入る ====
prompt10="$TMP/case9/stub/prompt.1"
transcript_part="$(sed -n '/^<<<TRANSCRIPT_START>>>$/,/^<<<TRANSCRIPT_END>>>$/p' "$prompt10")"
context_part="$(sed -n '/^<<<CONTEXT_START>>>$/,/^<<<CONTEXT_END>>>$/p' "$prompt10")"
if ! printf '%s' "$transcript_part" | grep -q 'LINE-A' && printf '%s' "$transcript_part" | grep -q 'LINE-B' \
   && ! printf '%s' "$transcript_part" | grep -q 'LINE-D'; then
  echo "ok: case10: TRANSCRIPT に範囲前後の発言が無く範囲内の発言がある"
else
  echo "NG: case10: TRANSCRIPT の中身が不正 → $transcript_part"; fails=$((fails + 1))
fi
if printf '%s' "$context_part" | grep -q 'LINE-A' && ! printf '%s' "$context_part" | grep -q 'LINE-B'; then
  echo "ok: case10: CONTEXT に範囲前の発言だけがある"
else
  echo "NG: case10: CONTEXT の中身が不正 → $context_part"; fails=$((fails + 1))
fi

# ==== case11: 切り出しモードは sessions/ の既存要約を消さない ====
mkdir -p "$TMP/case11/stub" "$TMP/case11/sessions/2026-07-13"
good_body > "$TMP/case11/stub/out"
old11="$TMP/case11/sessions/2026-07-13/testproj-2209-$SID_SHORT.md"
echo "old summary" > "$old11"
run_slice case11
assert_contains "case11: 切り出し要約が生成される" "$TMP/case11/slices/2026-07-14/testproj-$SID_SHORT.md" '^## 意図'
assert_contains "case11: 同一sidの sessions/ 要約が残る" "$old11" 'old summary'

# ==== case12: 2回とも不正出力 → 切り出しは 3、hook モードは 0（回帰） ====
mkdir -p "$TMP/case12/stub"
echo "要約できませんでした。" > "$TMP/case12/stub/out"
run_slice case12
if [ "$slice_rc" -eq 3 ]; then echo "ok: case12: 切り出しモードは生成失敗で 3"; else echo "NG: case12: 終了コード $slice_rc"; fails=$((fails + 1)); fi
assert_absent "case12: 失敗時はファイルを残さない" "$TMP/case12/slices/2026-07-14/testproj-$SID_SHORT.md"
mkdir -p "$TMP/case12h/stub"
echo "要約できませんでした。" > "$TMP/case12h/stub/out"
hook_rc=0
CLAUDE_BIN="$TMP/bin/claude" STUB_DIR="$TMP/case12h/stub" SESSIONS_ROOT="$TMP/case12h/sessions" \
  bash "$SCRIPT_DIR/summarize.sh" "$TMP/case9/transcript.jsonl" "$SID" > /dev/null 2>&1 || hook_rc=$?
if [ "$hook_rc" -eq 0 ]; then echo "ok: case12: hook モードは生成失敗でも 0"; else echo "NG: case12: hook 終了コード $hook_rc"; fails=$((fails + 1)); fi

# ==== 結果 ====
if [ "$fails" -eq 0 ]; then
  echo "ALL OK"
else
  echo "${fails} 件失敗"
  exit 1
fi

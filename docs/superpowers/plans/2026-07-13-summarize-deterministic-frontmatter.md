# SessionEnd要約の決定的フォーマット化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SessionEnd要約の frontmatter・構造生成を Haiku（LLM）からスクリプト側の決定的処理に移し、壊れた要約ファイル（frontmatter欠落・コードフェンス混入・断片）を構造的に排除する。

**Architecture:** `summarize.sh` が extract.py のヘッダから frontmatter を自前で組み立て、Haiku には本文7項目のみ生成させる。出力はフェンス除去→見出しバリデーション（失敗時1回リトライ）→redact→tmpファイル組み立て→`mv` のパイプラインで確定する。テストは既存 `redact-test.sh` と同じ素朴な bash アサート方式で、`claude` バイナリをスタブに差し替えて end-to-end 検証する。

**Tech Stack:** bash (set -euo pipefail, ShellCheck準拠), python3 (extract.py は無変更), 既存 `scripts/lib/redact.sh`

## Global Constraints

- shell規約: `#!/bin/bash`, `set -euo pipefail`（summarize.sh は既存通り）, ローカル変数 lower_snake_case, ShellCheck 準拠
- hook から呼ばれるため、いかなる失敗でも壊れたファイルを残さず `exit 0` で終了すること（summarize-session.sh 側が常に exit 0 を保証しているが、summarize.sh 単体でも中途半端なファイルを残さない）
- `extract.py` のヘッダ形式（`project:` / `session_id:` / `cwd:` / `start:` / `end:` の後に `---`）は変更しない
- 要約本文の7項目見出し（`## 意図` `## 作業内容` `## 結論` `## 編集/作成ファイル` `## 実行した主なコマンド` `## ナレッジ候補` `## フィードバック/承認`）は既存のまま
- コミットメッセージは `fix:` / `feat:` プレフィックス、コミット後は push（全タスク完了後にまとめて1回）
- リポジトリ: `/home/aya/.dotfiles`、ブランチ: main 直コミット（このリポジトリの運用通り）

## 対象ファイル一覧

- Modify: `scripts/claude-summarize/summarize.sh` — 全タスクの主対象
- Create: `scripts/claude-summarize/summarize-test.sh` — テストハーネス（Task 1 で作成、以降のタスクでケース追加）
- 無変更: `scripts/claude-summarize/extract.py`, `scripts/claude-summarize/summarize-session.sh`, `scripts/lib/redact.sh`

---

### Task 1: 決定的 frontmatter 生成 + アトミック書き込み + テストハーネス

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`
- Test: `scripts/claude-summarize/summarize-test.sh`（新規作成）

**Interfaces:**
- Consumes: `extract.py` のヘッダ（`project:` 等5行 + `---`）、`scripts/lib/redact.sh`（stdin→stdout フィルタ）
- Produces:
  - `summarize.sh` は環境変数 `CLAUDE_BIN` / `SESSIONS_ROOT` / `MAX_CHARS` で上書き可能になる（後続タスクのテストが依存）
  - テストヘルパー `make_transcript <path>` / `run_summarize <case_name>` / stub claude（`STUB_DIR/out.<n>` を出力し `STUB_DIR/calls` に呼び出し回数、`STUB_DIR/prompt.<n>` に受信プロンプトを記録）

- [ ] **Step 1: テストハーネスと正常系テストを書く**

`scripts/claude-summarize/summarize-test.sh` を新規作成:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: FAIL。現行 summarize.sh は `CLAUDE_BIN` が readonly ハードコードのためスタブが呼ばれず、`case1: ファイルが生成される` 等が NG になる（もしくは本物の claude が呼ばれず失敗）。

- [ ] **Step 3: summarize.sh を書き換える（決定的 frontmatter + アトミック書き込み + env 上書き）**

`scripts/claude-summarize/summarize.sh` の全体を以下に置き換える:

```bash
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

# ★ 上限ガード: extracted が極端に大きい場合は先頭 MAX_CHARS 文字に切り詰める
# ロケールを固定し文字単位の切り詰めを保証する
export LANG=ja_JP.UTF-8
if [ "${#extracted}" -gt "$MAX_CHARS" ]; then
  extracted="${extracted:0:$MAX_CHARS}
（※ 会話が長いため、ここで切り詰めています）"
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

# Haiku で要約生成。
# --settings '{"disableAllHooks":true}' で、この claude -p 実行が SessionEnd hook を
# 再発火させないようにする（さもないと「要約用 claude の終了 → また要約」の自己増殖ループになる）。
# --bare は hook を切れるが認証(OAuth/keychain)も読まなくなるため使わない。disableAllHooks は認証を保つ。
raw="$("$CLAUDE_BIN" -p "$PROMPT" --model haiku --settings '{"disableAllHooks":true}' 2>/dev/null)" || exit 0

# 前置き除去: 最初の「## 意図」以降だけを採用（frontmatter やフェンスの混入をここで捨てる）
body="$(printf '%s\n' "$raw" | sed -n '/^## 意図/,$p')"
[ -n "$body" ] || exit 0

# redaction: 会話にシークレットが混入していても要約ファイルに残さない（二重ガードの1段目）
body="$(printf '%s\n' "$body" | bash "$SCRIPT_DIR/../lib/redact.sh")" || exit 0

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
```

現行版からの主な差分: `CLAUDE_BIN`/`SESSIONS_ROOT`/`MAX_CHARS` の env 上書き化、frontmatter のスクリプト生成、プロンプトから frontmatter 指示を削除し「## 意図から始める」を明示、`sed -n '/^## 意図/,$p'` による前置き除去、tmp→mv のアトミック書き込み。旧ガードB（聞き返しフレーズの grep）は「## 意図が無ければ body が空になり exit 0」で代替されるため削除。フェンス除去・リトライ・見出しバリデーションは Task 2 で入れる。

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `ALL OK`（case1 の全アサートが ok）

Run: `shellcheck ~/.dotfiles/scripts/claude-summarize/summarize.sh ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: エラーなし（info/style は許容）

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add scripts/claude-summarize/summarize.sh scripts/claude-summarize/summarize-test.sh
git -C ~/.dotfiles commit -m "fix: 要約のfrontmatterをスクリプト側で決定的に生成（アトミック書き込み・テスト追加）"
```

---

### Task 2: フェンス救済 + 見出しバリデーション + 1回リトライ + 破棄理由ログ

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`（Task 1 適用後の claude 呼び出し〜redact の区間）
- Test: `scripts/claude-summarize/summarize-test.sh`（case2〜4 を追加）

**Interfaces:**
- Consumes: Task 1 のスタブ claude（`out.<n>` で呼び出し回数別の出力、`calls` で回数記録）、`run_summarize` / `assert_contains` / `assert_absent` / `good_body`
- Produces: 破棄時にログ行 `discarded(attempt=N): <理由>: <session_id>` を標準出力に出す（summarize-session.sh 経由で `~/.local/log/claude-summarize.log` に載る）

- [ ] **Step 1: 失敗するテスト3ケースを追加**

`summarize-test.sh` の `# ==== 結果 ====` の直前に追加:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: case2 の「フェンス行が残らない」（末尾 ``` が本文末に残る）、case3 の「破棄理由がログに出る」「2回呼ばれる」、case4 の「リトライで復旧」が NG。case1 は引き続き ok。

- [ ] **Step 3: claude 呼び出し部をリトライループに書き換える**

Task 1 で入れた以下のブロック:

```bash
raw="$("$CLAUDE_BIN" -p "$PROMPT" --model haiku --settings '{"disableAllHooks":true}' 2>/dev/null)" || exit 0

# 前置き除去: 最初の「## 意図」以降だけを採用（frontmatter やフェンスの混入をここで捨てる）
body="$(printf '%s\n' "$raw" | sed -n '/^## 意図/,$p')"
[ -n "$body" ] || exit 0
```

をこれに置き換える:

```bash
# Haiku で要約生成（不正出力なら1回だけリトライ）。
# 出力は「最初の ## 意図 以降を採用 → フェンス行除去 → 必須見出し検証」で決定的に整形・検証する。
body=""
for attempt in 1 2; do
  if ! raw="$("$CLAUDE_BIN" -p "$PROMPT" --model haiku --settings '{"disableAllHooks":true}' 2>/dev/null)"; then
    echo "discarded(attempt=$attempt): claude 実行失敗: $session_id"
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
```

注: `sed '/^```/d'` は行頭フェンスを全て落とす。本文は箇条書き主体でフェンス付きコードブロックを含まない想定（プロンプトでもフェンス禁止を明示済み）。

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `ALL OK`（case1〜4 全て ok）

Run: `shellcheck ~/.dotfiles/scripts/claude-summarize/summarize.sh ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: エラーなし

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add scripts/claude-summarize/summarize.sh scripts/claude-summarize/summarize-test.sh
git -C ~/.dotfiles commit -m "fix: 要約出力のフェンス救済・見出しバリデーション・リトライ・破棄ログを追加"
```

---

### Task 3: 同一 session_id の旧要約ファイル削除（再開セッションの重複対策）

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`（`mkdir -p "$out_dir"` の直前）
- Test: `scripts/claude-summarize/summarize-test.sh`（case5 を追加）

**Interfaces:**
- Consumes: Task 1 の `run_summarize` / `assert_contains` / `assert_absent` / `good_body`、変数 `sid_short` / `SESSIONS_ROOT` / `out_file`
- Produces: なし（最終タスク群への影響なし）

- [ ] **Step 1: 失敗するテストを追加**

`summarize-test.sh` の `# ==== 結果 ====` の直前に追加:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `case5: 同一sidの旧要約が消える` が NG。他は ok。

- [ ] **Step 3: 旧ファイル削除を実装**

`summarize.sh` の `# 組み立てはアトミックに` コメントの直前に追加:

```bash
# 同一セッションの旧要約を削除（再開セッションは最新の要約が全期間をカバーするため1本に保つ）
find "$SESSIONS_ROOT" -type f -name "*-${sid_short}.md" ! -path "$out_file" -delete 2>/dev/null || true
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `ALL OK`（case1〜5 全て ok）

- [ ] **Step 5: コミット**

```bash
git -C ~/.dotfiles add scripts/claude-summarize/summarize.sh scripts/claude-summarize/summarize-test.sh
git -C ~/.dotfiles commit -m "fix: 再開セッションで同一session_idの旧要約を削除して1本に保つ"
```

---

### Task 4: 切り詰めを「先頭2/3 + 末尾1/3」に変更（結論の欠落防止）

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh`（`MAX_CHARS` 切り詰めブロック）
- Test: `scripts/claude-summarize/summarize-test.sh`（case6 を追加）

**Interfaces:**
- Consumes: スタブ claude が保存する `STUB_DIR/prompt.1`（受信プロンプト全文）、`MAX_CHARS` の env 上書き
- Produces: なし

- [ ] **Step 1: 失敗するテストを追加**

`summarize-test.sh` の `# ==== 結果 ====` の直前に追加。長い transcript は `run_summarize` を使わず個別に組み立てる:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `case6: 末尾側が残る`（現行は末尾切り捨てのため TAILMARK が消える）と `case6: 中略マーカーが入る` が NG。

- [ ] **Step 3: 切り詰めブロックを書き換える**

`summarize.sh` の以下のブロック:

```bash
if [ "${#extracted}" -gt "$MAX_CHARS" ]; then
  extracted="${extracted:0:$MAX_CHARS}
（※ 会話が長いため、ここで切り詰めています）"
fi
```

をこれに置き換える:

```bash
# 超過時は先頭2/3 + 末尾1/3 を残す（セッションの結論・フィードバックは末尾に集中するため）
if [ "${#extracted}" -gt "$MAX_CHARS" ]; then
  head_n=$((MAX_CHARS * 2 / 3))
  tail_n=$((MAX_CHARS / 3))
  extracted="${extracted:0:$head_n}
（※ 会話が長いため、中略しています）
${extracted: -$tail_n}"
fi
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: `ALL OK`（case1〜6 全て ok）

Run: `shellcheck ~/.dotfiles/scripts/claude-summarize/summarize.sh ~/.dotfiles/scripts/claude-summarize/summarize-test.sh`
Expected: エラーなし

- [ ] **Step 5: コミットとプッシュ（全タスク完了）**

```bash
git -C ~/.dotfiles add scripts/claude-summarize/summarize.sh scripts/claude-summarize/summarize-test.sh
git -C ~/.dotfiles commit -m "fix: 長い会話の切り詰めを先頭2/3+末尾1/3に変更（結論の欠落防止）"
git -C ~/.dotfiles push
```

push が SSH エラーで失敗した場合: `git -C ~/.dotfiles remote set-url origin git@github-aya215:aya-215/dotfiles.git` を実行してから再 push する。

---

## 実運用での最終確認（Task 4 の後、任意の1回）

実際の transcript で end-to-end を1回流して目視確認する:

```bash
# 直近の実 transcript を1本選ぶ
ls -t ~/.claude/projects/-home-aya--dotfiles/*.jsonl | head -1
# それを手動で要約に通す（本物の claude/Haiku が動く）
bash ~/.dotfiles/scripts/claude-summarize/summarize.sh <上のパス> <そのファイル名のUUID部分>
# 生成物の frontmatter 6行と本文見出しを確認
head -20 ~/.nb/claude/sessions/$(TZ=Asia/Tokyo date +%Y-%m-%d)/*.md
```

Expected: frontmatter に project/session_id/start/end/cwd が全て入り、本文が `## 意図` から始まりフェンスが無いこと。

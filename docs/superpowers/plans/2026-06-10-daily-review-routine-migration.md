# daily-review クラウドルーティン移行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 毎晩22時の日報生成（claude -p / Opus）を、APIトリガー専用クラウドルーティン＋ローカル軽量POSTスクリプトに置き換え、6/15以降のAgent SDKクレジット消費を回避する。

**Architecture:** ローカルcron（22:10、claude不使用）が当日のセッション要約とRocket Chat履歴を収集・redaction・64KB内に整形し、ルーティンの `/fire` エンドポイントへ `text` ペイロードとしてPOST。クラウド側はAPIトリガーでのみ起動し、dotfiles/lifeをcloneしてGitHub APIでgit活動を収集、日報Issueを更新する。会話由来データはGitHubに一切上げない（nbの `claude/` gitignore運用は不変）。

**Tech Stack:** bash（ShellCheck準拠）、curl、python3（JSONエスケープ）、RemoteTriggerツール（ルーティンAPI）、gh / GitHub REST API

**Spec:** `docs/superpowers/specs/2026-06-10-claude-p-migration-design.md`

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| Create: `scripts/lib/redact.sh` | stdin→stdoutのシークレット置換フィルタ（共通部品） |
| Create: `scripts/lib/redact-test.sh` | redact.shのテスト |
| Create: `scripts/daily-review/fire-daily-review.sh` | 収集→redaction→切り詰め→/fire POST |
| Modify: `scripts/claude-summarize/summarize.sh` | 要約書き出し後にredact適用（二重ガード） |
| Delete: `scripts/daily-review/daily-review-auto.sh` | 検証完了後に削除 |
| 変更なし: `scripts/daily-review/fetch-rocketchat.sh` | fire-daily-review.shから引き続き使用 |

---

### Task 1: redact.sh（共通redactionフィルタ）

**Files:**
- Create: `scripts/lib/redact.sh`
- Test: `scripts/lib/redact-test.sh`

- [ ] **Step 1: テストを書く**

`scripts/lib/redact-test.sh` を以下の内容で作成:

```bash
#!/bin/bash
# redact-test.sh - redact.sh の動作確認テスト
# 使用方法: bash scripts/lib/redact-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0

# assert_redacted <説明> <入力> <出力に含まれるべき文字列> <出力に含まれてはいけない文字列>
assert_redacted() {
  local desc="$1" input="$2" want="$3" forbid="$4" got
  got="$(printf '%s' "$input" | bash "$SCRIPT_DIR/redact.sh")"
  if [[ "$got" == *"$want"* && "$got" != *"$forbid"* ]]; then
    echo "ok: $desc"
  else
    echo "NG: $desc → got: $got"
    fails=$((fails + 1))
  fi
}

# ダミーキーは実在キーと衝突しないよう機械生成する（リポジトリに実キー形式を残さない）
ghp_dummy="ghp_$(printf 'a%.0s' {1..36})"
pat_dummy="github_pat_$(printf 'b%.0s' {1..30})"
skant_dummy="sk-ant-$(printf 'c%.0s' {1..30})"
sk_dummy="sk-$(printf 'd%.0s' {1..40})"
akia_dummy="AKIA$(printf 'E%.0s' {1..16})"
slack_dummy="xoxb-$(printf '1%.0s' {1..20})"
bearer_dummy="Bearer $(printf 'f%.0s' {1..30})"
xauth_dummy="X-Auth-Token: $(printf 'g%.0s' {1..30})"

assert_redacted "ghp" "token=$ghp_dummy end" "[REDACTED:ghp]" "$ghp_dummy"
assert_redacted "github_pat" "$pat_dummy" "[REDACTED:github_pat]" "$pat_dummy"
assert_redacted "sk-ant" "$skant_dummy" "[REDACTED:sk-ant]" "$skant_dummy"
assert_redacted "sk generic" "$sk_dummy" "[REDACTED:sk]" "$sk_dummy"
assert_redacted "akia" "$akia_dummy" "[REDACTED:akia]" "$akia_dummy"
assert_redacted "slack" "$slack_dummy" "[REDACTED:slack]" "$slack_dummy"
assert_redacted "bearer" "$bearer_dummy" "Bearer [REDACTED]" "$bearer_dummy"
assert_redacted "x-auth-token" "$xauth_dummy" "X-Auth-Token: [REDACTED]" "$xauth_dummy"
assert_redacted "通常テキストは無変化" "hello ghp_short sk-abc world" "hello ghp_short sk-abc world" "[REDACTED"

if [ "$fails" -eq 0 ]; then
  echo "ALL OK"
else
  echo "${fails} 件失敗"
  exit 1
fi
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bash /home/aya/.dotfiles/scripts/lib/redact-test.sh`
Expected: FAIL（`redact.sh: No such file or directory` 系のエラー）

- [ ] **Step 3: redact.sh を実装**

`scripts/lib/redact.sh` を以下の内容で作成:

```bash
#!/bin/bash
# redact.sh - stdin のテキストからシークレットらしき文字列を [REDACTED:*] に置換して stdout へ出す
#
# summarize.sh（要約ファイル書き出し後）と fire-daily-review.sh（送信前）の
# 二重ガードとして使う。パターンは設計書の redaction 仕様に従う:
# docs/superpowers/specs/2026-06-10-claude-p-migration-design.md
set -euo pipefail

# 注意: sk-ant- は汎用 sk- より先に評価する（順序依存）
sed -E \
  -e 's/ghp_[A-Za-z0-9]{36}/[REDACTED:ghp]/g' \
  -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED:github_pat]/g' \
  -e 's/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED:sk-ant]/g' \
  -e 's/sk-[A-Za-z0-9]{32,}/[REDACTED:sk]/g' \
  -e 's/AKIA[0-9A-Z]{16}/[REDACTED:akia]/g' \
  -e 's/xox[bporas]-[A-Za-z0-9-]{10,}/[REDACTED:slack]/g' \
  -e 's/Bearer [A-Za-z0-9._=-]{25,}/Bearer [REDACTED]/g' \
  -e 's/X-Auth-Token: [^[:space:]]{20,}/X-Auth-Token: [REDACTED]/g'
```

- [ ] **Step 4: テストが通ることを確認**

Run: `chmod +x /home/aya/.dotfiles/scripts/lib/redact.sh /home/aya/.dotfiles/scripts/lib/redact-test.sh && bash /home/aya/.dotfiles/scripts/lib/redact-test.sh`
Expected: 9行の `ok:` と `ALL OK`

- [ ] **Step 5: ShellCheck**

Run: `shellcheck /home/aya/.dotfiles/scripts/lib/redact.sh /home/aya/.dotfiles/scripts/lib/redact-test.sh`
Expected: 警告なし（SC1090系が出たら directive で抑制してよい）

- [ ] **Step 6: コミット**

```bash
git -C /home/aya/.dotfiles add scripts/lib/redact.sh scripts/lib/redact-test.sh
git -C /home/aya/.dotfiles commit -m "feat: シークレットredactionフィルタを追加（要約・fireペイロードの二重ガード用）"
```

### Task 2: summarize.sh に redaction を適用

**Files:**
- Modify: `scripts/claude-summarize/summarize.sh:107`（frontmatter後処理の直後）

- [ ] **Step 1: redaction処理を挿入**

`summarize.sh` の以下の箇所（後処理: frontmatter除去の直後、ガードBの前）:

```bash
# sed 後の空ファイル確認（念のため）
[ -s "$out_file" ] || { rm -f "$out_file"; exit 0; }
```

の**直後**に以下を挿入:

```bash
# redaction: 会話にシークレットが混入していても要約ファイルに残さない（二重ガードの1段目）
if ! bash "$SCRIPT_DIR/../lib/redact.sh" < "$out_file" > "${out_file}.tmp"; then
  rm -f "$out_file" "${out_file}.tmp"
  exit 0
fi
mv "${out_file}.tmp" "$out_file"
```

- [ ] **Step 2: 動作確認（ダミーキー入りファイルで検証）**

Run:
```bash
tmpf=$(mktemp /tmp/redact-check-XXXX.md)
printf -- '---\nproject: test\n---\n## 意図\nキーは ghp_%s です\n' "$(printf 'a%.0s' {1..36})" > "$tmpf"
bash /home/aya/.dotfiles/scripts/lib/redact.sh < "$tmpf"
rm -f "$tmpf"
```
Expected: 出力に `[REDACTED:ghp]` が含まれ、`ghp_aaa...` が含まれない

- [ ] **Step 3: 構文チェック**

Run: `bash -n /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh && shellcheck /home/aya/.dotfiles/scripts/claude-summarize/summarize.sh`
Expected: エラーなし（既存の disable directive はそのまま）

- [ ] **Step 4: コミット**

```bash
git -C /home/aya/.dotfiles add scripts/claude-summarize/summarize.sh
git -C /home/aya/.dotfiles commit -m "feat: セッション要約の書き出し後にredactionを適用"
```

### Task 3: fire-daily-review.sh（収集→POST スクリプト）

**Files:**
- Create: `scripts/daily-review/fire-daily-review.sh`

- [ ] **Step 1: スクリプト作成**

`scripts/daily-review/fire-daily-review.sh` を以下の内容で作成:

```bash
#!/bin/bash
# fire-daily-review.sh - daily-review ルーティンを text ペイロード付きで起動する
#
# cron から毎晩 22:10 に呼び出す。claude バイナリは使わない（Agent SDK クレジット消費ゼロ）。
# 当日のセッション要約と Rocket Chat 履歴を収集し、redaction をかけて
# ルーティンの /fire エンドポイントに POST する。日報生成本体はクラウド側で実行される。
#
# 必要な環境変数（.env.local に追記）: ROUTINE_FIRE_URL, ROUTINE_FIRE_TOKEN
#
# 使用方法:
#   cron から: 10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh
#   手動テスト: bash fire-daily-review.sh --dry-run   # POST せずペイロードを標準出力へ
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="$SCRIPT_DIR/.env.local"
readonly LOG_FILE="$HOME/.local/log/fire-daily-review.log"
readonly SESSIONS_ROOT="$HOME/.nb/claude/sessions"
readonly REDACT="$SCRIPT_DIR/../lib/redact.sh"
# /fire の text 上限は 65,536 文字。余裕を見て 60,000 に抑える
readonly MAX_PAYLOAD_CHARS=60000
readonly MAX_RC_CHARS=15000

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

mkdir -p "$(dirname "$LOG_FILE")"

# ログ1行を JST タイムスタンプ付きで書く
log() {
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# shellcheck disable=SC1090
source "$ENV_FILE"
# dry-run はペイロード確認だけなので fire 用トークン未設定でも動かせる
if [ "$dry_run" -eq 0 ]; then
  : "${ROUTINE_FIRE_URL:?ROUTINE_FIRE_URL が .env.local に設定されていません}"
  : "${ROUTINE_FIRE_TOKEN:?ROUTINE_FIRE_TOKEN が .env.local に設定されていません}"
fi

target_date="$(TZ=Asia/Tokyo date +%Y-%m-%d)"

# Rocket Chat 当日履歴（失敗してもプレースホルダで続行）
rocketchat_log="$(bash "$SCRIPT_DIR/fetch-rocketchat.sh" "$target_date" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"
if [ "${#rocketchat_log}" -gt "$MAX_RC_CHARS" ]; then
  rocketchat_log="${rocketchat_log:0:$MAX_RC_CHARS}
（※ Rocket Chat 履歴が長いため切り詰め）"
fi

# 当日のセッション要約を新しい方から keep 件だけ連結する（古い方を落とす）
# daily-review-auto.sh の見出し形式（## <project> — <HH:MM>）を踏襲
build_sessions() {
  local keep="$1" out="" sf proj end_ts end_hm body
  local files=()
  while IFS= read -r sf; do files+=("$sf"); done \
    < <(ls "$SESSIONS_ROOT/$target_date"/*.md 2>/dev/null | sort)
  local total="${#files[@]}"
  if [ "$total" -eq 0 ]; then
    echo "(本日のセッション要約なし)"
    return
  fi
  local start=$((total - keep))
  [ "$start" -lt 0 ] && start=0
  [ "$start" -gt 0 ] && out="（※ 容量制限のため古い ${start} セッションを省略）
"
  for sf in "${files[@]:$start}"; do
    proj="$(sed -n 's/^project: //p' "$sf" | head -1)"
    [ -z "$proj" ] && proj="unknown"
    end_ts="$(sed -n 's/^end: //p' "$sf" | head -1)"
    end_hm="$(TZ=Asia/Tokyo date -d "$end_ts" +%H:%M 2>/dev/null || echo "??:??")"
    body="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=3{print}' "$sf")"
    out="${out}## ${proj} — ${end_hm}

${body}

---

"
  done
  printf '%s' "$out"
}

# 予算に収まるまで古いセッションから落とす
session_count="$(ls "$SESSIONS_ROOT/$target_date"/*.md 2>/dev/null | wc -l)"
keep="$session_count"
[ "$keep" -eq 0 ] && keep=1
while :; do
  session_summaries="$(build_sessions "$keep")"
  payload="【対象日】${target_date}

【Rocket Chat 当日履歴（mori.a-times）】
${rocketchat_log}

【セッション要約（${target_date}・時刻順）】
${session_summaries}"
  [ "${#payload}" -le "$MAX_PAYLOAD_CHARS" ] && break
  if [ "$keep" -le 1 ]; then
    payload="${payload:0:$MAX_PAYLOAD_CHARS}"
    break
  fi
  keep=$((keep - 1))
done

# redaction（送信前の最終ガード）
payload="$(printf '%s' "$payload" | bash "$REDACT")"

if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$payload"
  echo "--- (${#payload} chars, dry-run のため POST しません)" >&2
  exit 0
fi

body_json="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.dumps({"text": sys.stdin.read()}))')"

# POST（429/503 等に備えて 60 秒間隔で最大 3 回）
resp_file="$(mktemp /tmp/fire-daily-review-resp-XXXX.json)"
trap 'rm -f "$resp_file"' EXIT
for attempt in 1 2 3; do
  http_code="$(curl -sS -m 60 -o "$resp_file" -w '%{http_code}' \
    -X POST "$ROUTINE_FIRE_URL" \
    -H "Authorization: Bearer $ROUTINE_FIRE_TOKEN" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
    -H "Content-Type: application/json" \
    -d "$body_json" 2>>"$LOG_FILE" || echo "000")"
  if [ "$http_code" = "200" ]; then
    log "fired (attempt=$attempt, payload=${#payload}chars): $(cat "$resp_file")"
    exit 0
  fi
  log "fire failed (attempt=$attempt, http=$http_code): $(cat "$resp_file" 2>/dev/null || true)"
  [ "$attempt" -lt 3 ] && sleep 60
done
log "fire giving up after 3 attempts"
exit 1
```

- [ ] **Step 2: dry-runで動作確認**

Run: `chmod +x /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh && bash /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh --dry-run | head -30`
Expected: `【対象日】`、`【Rocket Chat 当日履歴（mori.a-times）】`、`【セッション要約（...・時刻順）】` の3セクションが出力される（dry-runはROUTINE_FIRE_URL/TOKEN未設定でも動く）

- [ ] **Step 3: ShellCheck**

Run: `shellcheck /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh`
Expected: 警告なし

- [ ] **Step 4: コミット**

```bash
git -C /home/aya/.dotfiles add scripts/daily-review/fire-daily-review.sh
git -C /home/aya/.dotfiles commit -m "feat: daily-reviewルーティンをfireするローカルスクリプトを追加"
```

### Task 4: daily-review ルーティン作成（クラウド側）

**Files:** なし（RemoteTriggerツールでクラウド操作）

- [ ] **Step 1: UUID生成**

Run: `uuidgen | tr 'A-Z' 'a-z'`

- [ ] **Step 2: ルーティン作成**

`RemoteTrigger` を `action: "create"` で呼ぶ。`run_once_at` はダミー（作成APIはトリガー必須のため。後でユーザーがWeb UIで削除し、APIトリガーだけにする）。body:

```json
{
  "name": "daily-review",
  "run_once_at": "2026-12-31T15:00:00Z",
  "enabled": true,
  "job_config": {
    "ccr": {
      "environment_id": "env_01X9JcJWqdgPvER4JA37Gt1U",
      "session_context": {
        "model": "claude-opus-4-8",
        "sources": [
          {"git_repository": {"url": "https://github.com/aya-215/dotfiles"}},
          {"git_repository": {"url": "https://github.com/aya-215/life"}}
        ]
      },
      "events": [
        {"data": {
          "uuid": "<Step 1のUUID>",
          "session_id": "",
          "type": "user",
          "parent_tool_use_id": null,
          "message": {"content": "<Step 3のプロンプト全文>", "role": "user"}
        }}
      ]
    }
  }
}
```

- [ ] **Step 3: ルーティンのプロンプト（上記bodyのcontentに入れる全文）**

```text
あなたは無人実行の日報生成エージェントです。APIトリガーのtextペイロード（このメッセージに付随する追加コンテキスト）に【対象日】【Rocket Chat 当日履歴】【セッション要約】が含まれています。以下を厳守してください。

【無人モードの制約】
- ユーザーへの質問は一切行わない。応答できる人間はいない。
- このセッションはクラウド環境で実行されており、ローカルファイルは存在しない。aya-215/dotfiles と aya-215/life がクローン済み。

【手順】
1. クローン済み dotfiles の .claude-global/skills/daily-review/SKILL.md を読み、その「フェーズ1（サマリー生成）」の形式に従う。対話ステップ（調子・ルーティン・就寝時刻）とフェーズ2（メモリ整理）は実行しない。「ユーザー確認後に更新」は確認なしで更新してよい（承認は事前に与えられている）。
2. 対象日はペイロードの【対象日】を使う。ペイロードが無い場合は TZ=Asia/Tokyo の今日。
3. 対象日の日報 Issue を特定: GH_TOKEN="$GH_TOKEN_AYA215" gh issue list --repo aya-215/life --search "<対象日> in:title"（ghが無ければ curl で api.github.com を直接叩く）。
4. git活動を GitHub API で収集する（ローカルclone の git log は使わない）:
   - Personal: GH_TOKEN="$GH_TOKEN_AYA215" gh api "search/commits?q=author:aya-215+committer-date:<対象日>" --jq '.items[] | .repository.full_name + " " + .commit.message' 
   - Work: GH_TOKEN="$GH_TOKEN_EBASE" gh api "search/commits?q=author:eBASE-Mori+org:ebase-dev+committer-date:<対象日>" --jq '.items[] | .repository.full_name + " " + .commit.message'
5. 対象日に close された task Issue を収集: GH_TOKEN="$GH_TOKEN_AYA215" gh issue list --repo aya-215/life --state closed --label task --search "closed:<対象日>"
6. ペイロードの【セッション要約】を Claude 会話履歴の入力として使う（各セッションは6項目で要約済み）。【Rocket Chat 当日履歴】を当日の発言として使う（MCPは使わない）。
7. Work/Personal に分類し、SKILL.md の「サマリー形式」に従って「📝 サマリー」を生成する。Workセクション内では「自分の作業」と「レビュー作業」を区別する。セッション要約の「## 意図」冒頭の【レビュー作業】【実装作業】の明記に従い、レビューで見た内容を自分の実装成果として記録しない。
8. 日報 Issue が open なら GH_TOKEN="$GH_TOKEN_AYA215" gh issue edit で body のサマリーセクションを更新。close 済みなら life リポジトリ内の対応する blog md を編集して commit & push する。
9. 最後に、更新したサマリーの全文を出力する。

【ペイロードが無い/空の場合】
gh で収集できる情報（git活動・Issue）のみでサマリーを生成し、冒頭に「(セッション要約・RC履歴なしで生成)」と明記する。
```

- [ ] **Step 4: MCPコネクタを外す**

`RemoteTrigger` を `action: "update"`、`trigger_id` に作成されたID、body `{"clear_mcp_connections": true}` で呼ぶ（作成時に自動アタッチされるため。挨拶ルーティンで実証済みの挙動）。

Expected: レスポンスの `mcp_connections` が `[]`

- [ ] **Step 5: 作成結果の記録**

ルーティンID（`trig_...`）を控え、ユーザーに `https://claude.ai/code/routines` のURLとともに提示する。

### Task 5: ユーザー作業（チェックポイント — ここで一時停止）

**Files:** なし（ユーザーがWeb UI・GitHub・ローカルで実施）

- [ ] **Step 1: 以下の作業依頼を提示して、完了の返事を待つ**

1. **GitHub fine-grained PAT 2枚発行**（github.com → Settings → Developer settings → Fine-grained tokens）:
   - aya-215アカウント: Repository access = life（Issues: Read/Write, Contents: Read/Write）+ 自分のリポジトリのメタデータ。有効期限は90日程度を推奨
   - eBASE-Moriアカウント: Resource owner = ebase-dev、対象リポジトリ read-only（Contents: Read, Metadata: Read）
2. **claude.ai の環境変数登録**: https://claude.ai/code/routines → daily-review → 環境（Default）の設定 → Environment variables に `GH_TOKEN_AYA215` と `GH_TOKEN_EBASE` を追加
3. **APIトリガー追加**: daily-review の編集画面 → Select a trigger → Add another trigger → API → URLをコピー → Generate token（**一度しか表示されない**）
4. **ダミーのスケジュールトリガー（2026-12-31の一回限り実行）を削除**: 同じ編集画面のトリガー一覧から削除
5. **lifeリポジトリの「Allow unrestricted branch pushes」を有効化**（close済み日報のblog push用）。dotfilesはデフォルトのまま
6. **GitHub接続の確認**: private の aya-215/life をcloneするため、claude.ai に aya-215 の GitHub アカウントが接続されているか確認（routines画面でリポジトリが選べていればOK）
7. **ローカルの .env.local に追記**:

```bash
# scripts/daily-review/.env.local に追記（このファイルはgitignore済み）
ROUTINE_FIRE_URL='<手順3でコピーしたURL>'
ROUTINE_FIRE_TOKEN='<手順3で生成したトークン>'
```

- [ ] **Step 2: ユーザー完了後、設定を確認**

Run: `grep -c 'ROUTINE_FIRE' /home/aya/.dotfiles/scripts/daily-review/.env.local`
Expected: `2`

### Task 6: 手動fire検証

**Files:** なし

- [ ] **Step 1: dry-runでredactionと整形を最終確認**

Run: `bash /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh --dry-run | head -40`
Expected: 3セクション構成。シークレット形式の文字列が含まれない

- [ ] **Step 2: 本番fire（ルーティン実行1回ぶん消費する）**

Run: `bash /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh && tail -3 ~/.local/log/fire-daily-review.log`
Expected: ログに `fired (attempt=1, ...)` と `claude_code_session_url` を含むレスポンス

- [ ] **Step 3: セッションURLをユーザーに提示して結果確認を依頼**

ログ中の `claude_code_session_url` を提示。確認ポイント:
- 日報Issue（aya-215/life）の「📝 サマリー」が更新されている
- Work/Personal分類とレビュー/実装の区別がされている
- 失敗していたらセッションのトランスクリプトから原因を特定して修正（プロンプト修正は `RemoteTrigger update`、スクリプト修正はローカル）

### Task 7: cron切替

**Files:** crontab（ファイル外）

- [ ] **Step 1: バックアップして切替**

```bash
crontab -l > /tmp/crontab-backup-$(date +%Y%m%d)-dr.txt
crontab -l | sed 's|^0 22 \* \* \* /home/aya/.dotfiles/scripts/daily-review/daily-review-auto.sh.*|10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh >> /tmp/fire-daily-review-cron.log 2>\&1|' | crontab -
crontab -l
```

Expected: 残りは以下の2行（nb-syncは不変）:

```
*/30 * * * * /home/aya/.dotfiles/scripts/nb-sync.sh
10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh >> /tmp/fire-daily-review-cron.log 2>&1
```

※ 22:10 にしたのは nb-sync（毎時00/30分）の直後にして当日要約の取りこぼしを減らすため。

### Task 8: 掃除とpush

**Files:**
- Delete: `scripts/daily-review/daily-review-auto.sh`
- ローカルのみ: `~/.nb/claude/2026-*.md`（旧生ログ、gitignore済みのためgit操作なし）

- [ ] **Step 1: 旧スクリプト削除**

```bash
git -C /home/aya/.dotfiles rm scripts/daily-review/daily-review-auto.sh
```

- [ ] **Step 2: 旧生ログのローカル削除（シークレット残留ファイル）**

```bash
ls ~/.nb/claude/*.md   # 削除対象を目視（sessions/ ディレクトリは対象外）
rm ~/.nb/claude/*.md
ls ~/.nb/claude/        # sessions/ だけ残ることを確認
```

Expected: `sessions` ディレクトリのみ残る

- [ ] **Step 3: 計画書込みでコミットしてpush**

```bash
git -C /home/aya/.dotfiles add docs/superpowers/plans/2026-06-10-daily-review-routine-migration.md
git -C /home/aya/.dotfiles commit -m "refactor: daily-reviewをclaude -pからクラウドルーティンに移行"
git -C /home/aya/.dotfiles push
```

### Task 9: 翌日検証とメモリ更新

**Files:**
- Modify: `~/.claude/skills/agent-memory/memories/automation/daily-review-skill-integration.md`
- Modify: `~/.claude/skills/agent-memory/memories/automation/claude-session-summary-system.md`
- Modify: `~/.claude/skills/agent-memory/memories/automation/greeting-routine-migration.md`

- [ ] **Step 1: 翌日22:15以降に自動実行を確認**

- `tail ~/.local/log/fire-daily-review.log` に当日の `fired` 行がある
- https://claude.ai/code/routines の daily-review Runs に実行記録がある
- 日報Issueのサマリーが更新されている

- [ ] **Step 2: agent-memoryを新構成に更新**

- `daily-review-skill-integration.md`: 無人版を「cron→claude -p」から「cron(fire-daily-review.sh 22:10)→APIトリガールーティン」に書き換え。ルーティンID・トラブル時の見方（claude.ai/code/routines、~/.local/log/fire-daily-review.log）を記載
- `claude-session-summary-system.md`: redaction層（scripts/lib/redact.sh、書き出し後適用）を追記
- `greeting-routine-migration.md`: status を resolved に変更（翌朝確認が済んでいれば）

- [ ] **Step 3: 問題があった場合のロールバック**

```bash
# crontabを復元（22:00のdaily-review-auto行が戻る）
crontab /tmp/crontab-backup-<日付>-dr.txt
# スクリプトを復元
git -C /home/aya/.dotfiles revert <Task8のコミットhash>
git -C /home/aya/.dotfiles push
```

※ 6/15までは claude -p がサブスク枠のまま動くため、ロールバックしても当面の実害はない。

---

## 補足メモ

- **モデルID**: ルーティンは `claude-opus-4-8`（現行 `--model opus` 相当）。品質を落とす判断をする場合は `RemoteTrigger update` で `claude-sonnet-4-6` に変更可能
- **ルーティン実行回数**: 挨拶2回＋daily-review1回 = 3回/日。アカウントの日次上限内（残数は claude.ai/code/routines で確認可能）
- **summarize.sh のクレジット消費**: 6/15以降、月$6前後の見込み。7月頭に claude.ai/settings/usage で実績確認を推奨
- **fire時刻とstaggerの注意**: APIトリガーは即時起動（staggerなし）。22:10のセッションは5時間ウィンドウを消費する点は現行と同じ

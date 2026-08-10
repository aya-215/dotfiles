#!/bin/bash
# fire-daily-review.sh - daily-review ルーティンを text ペイロード付きで起動する
#
# cron から毎晩 22:10 に呼び出す。当日のセッション要約と Rocket Chat 履歴を収集し、
# redaction をかけてルーティンの /fire エンドポイントに POST する。
# 日報生成本体はクラウド側で実行される。
#
# 注: メール整理のみ claude バイナリを使う（thunderbird-archive.sh 経由）。
# スレッド全体を読ませてから圧縮する必要があり、ペイロード予算内では生データを
# 載せきれないため。それ以外の収集はシェルで完結する。
#
# 必要な環境変数（.env.local に追記）: ROUTINE_FIRE_URL, ROUTINE_FIRE_TOKEN
#
# 使用方法:
#   cron から: 10 22 * * * /home/aya/.dotfiles/scripts/daily-review/fire-daily-review.sh
#   手動テスト: bash fire-daily-review.sh --dry-run   # POST せずペイロードを標準出力へ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly ENV_FILE="$SCRIPT_DIR/.env.local"
readonly LOG_FILE="$HOME/.local/log/fire-daily-review.log"
readonly SESSIONS_ROOT="$HOME/.nb/claude/sessions"
readonly REDACT="$SCRIPT_DIR/../lib/redact.sh"
# /fire の text 上限は 65,536 文字。余裕を見て 60,000 に抑える
readonly MAX_PAYLOAD_CHARS=60000
readonly MAX_RC_CHARS=15000
readonly MAX_GIT_CHARS=8000
# メールは整理済み（要約層通過後）で日次実測 0〜3,600 文字。余裕を見て 6,000 に抑える。
readonly MAX_MAIL_CHARS=6000
# 自分のコミットを特定する author 正規表現（work / personal の両メール）
readonly GIT_AUTHOR_RE='mori\.a@ebase\.co\.jp\|aya\.chr928@gmail\.com'
# POST のリトライ設定。指数バックオフで 60→120→240→480 秒（待機総量 約15分）。
# 旧実装は 60秒固定×3回=最大2分しか粘らず、2026-07-17 の一時的 401 で日報を1日落とした。
readonly MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
readonly INITIAL_BACKOFF="${INITIAL_BACKOFF:-60}"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

mkdir -p "$(dirname "$LOG_FILE")"

# ログ1行を JST タイムスタンプ付きで書く
log() {
  echo "[$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# is_permanent_error <http_code> <response_body>
# リトライしても回復しない恒久エラーなら 0 を返す。
# 判定は保守的に行う（一時エラーを恒久と誤判定すると、粘れば成功したはずの日報を
# 落とすため）。401 は明示的に一時扱いとする — 同一トークンで直後に成功した実績があり
# トークン失効ではないと確認済み（2026-07-13）。
is_permanent_error() {
  local code="$1" body="$2"
  case "$code" in
    # 再認可・権限系。人間が設定を直すまで何度叩いても同じ結果になる
    400|403|404)
      case "$body" in
        *github_repo_access_denied*|*re-authorize*|*permission*|*not_found*) return 0 ;;
      esac
      ;;
  esac
  return 1
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
# 購読ルーム全体から自分の発言・メンションに関係するものを収集する。
# DM は外部送信のため含めない（設計: docs/superpowers/specs/2026-07-28-rocketchat-multiroom-design.md）。
# 文字数制御は rocketchat.sh 側の --budget（ルーム単位ドロップ）に委ねるため、
# ここでのバイト位置切り詰めは行わない。
rocketchat_log="$(bash "$SCRIPT_DIR/../lib/rocketchat.sh" \
  --from "$target_date" --to "$target_date" \
  --budget "$MAX_RC_CHARS" 2>/dev/null || echo "(Rocket Chat: 取得失敗)")"

# 当日の自分のコミットをローカルリポジトリから収集する
# ローカル収集なので push 前のコミットも拾える（GitHub API より新鮮）うえ、
# GitHub に無い社内 GitBucket リポジトリ（/mnt/d/tomcat/webapps/*）もカバーできる。
# HEAD のみを見る（--all は worktree 間の重複と entire-cli のチェックポイント
# コミットを拾ってしまうため使わない）。
collect_git_log() {
  local out="" label repo name lines branch
  for label in Personal Work; do
    local repos=()
    if [ "$label" = "Personal" ]; then
      repos=("$HOME/.dotfiles" "$HOME"/src/github.com/aya-215/*/)
    else
      repos=("$HOME"/src/github.com/ebase-dev/*/ /mnt/d/tomcat/webapps/*/)
    fi
    for repo in "${repos[@]}"; do
      [ -e "$repo/.git" ] || continue
      # 時刻+件名+変更量を1コミット1行に整形する。--shortstat の統計行は
      # awk で直前の件名行へ「（N files +A -D）」として畳み込む。
      # 注意: TZ=Asia/Tokyo を付けると git が zoneinfo を解決できず UTC に
      # 落ちる環境のため、システムローカル時刻（JST）に任せる
      lines="$(git -C "$repo" log \
        --author="$GIT_AUTHOR_RE" \
        --since="${target_date}T00:00:00+09:00" \
        --until="${target_date}T23:59:59+09:00" \
        --date=format-local:'%H:%M' \
        --pretty=format:'- %ad %s' --shortstat 2>/dev/null \
        | sed -E 's/ Entire-Checkpoint: [0-9a-f]+//' \
        | awk '
            /^- / { if (prev != "") print prev; prev = $0; next }
            /files? changed/ {
              ins = 0; del = 0
              for (i = 1; i <= NF; i++) {
                if ($i ~ /insertion/) ins = $(i-1)
                if ($i ~ /deletion/)  del = $(i-1)
              }
              prev = prev "（" $1 " files +" ins " -" del "）"
            }
            END { if (prev != "") print prev }
          ')" || continue
      [ -n "$lines" ] || continue
      name="$(basename "$repo")"
      branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
      [ -z "$branch" ] && branch="detached"
      out="${out}### [${label}] ${name} (branch: ${branch})
${lines}

"
    done
  done
  if [ -n "$out" ]; then
    printf '%s' "$out"
  else
    echo "(本日のコミットなし)"
  fi
}

# Thunderbird 当日メール（失敗してもプレースホルダで続行）
# gitログにも Rocket Chat にも現れない社外・他部署とのやりとりを補う。
#
# 整理済みメールは life リポジトリにも保存し、業務履歴そのものを資産として残す。
# archive 側が要約を生成するので、その出力をそのままペイロードにも使う
# （同じ内容を二度生成しない）。archive が失敗しても日報は続行する。
mail_file="$(bash "$SCRIPT_DIR/../lib/thunderbird-archive.sh" "$target_date" 2>/dev/null || true)"
if [ -n "$mail_file" ] && [ -f "$mail_file" ]; then
  # 見出し行（"# YYYY-MM-DD のメール"）を除いた本文を使う
  mail_log="$(tail -n +2 "$mail_file" | sed '/^[[:space:]]*$/d')"
else
  mail_log="(業務メールなし)"
fi
if [ "${#mail_log}" -gt "$MAX_MAIL_CHARS" ]; then
  mail_log="${mail_log:0:$MAX_MAIL_CHARS}
（※ メールが長いため切り詰め。全文は life リポジトリの mail/ を参照）"
fi

git_log="$(collect_git_log)"
if [ "${#git_log}" -gt "$MAX_GIT_CHARS" ]; then
  git_log="${git_log:0:$MAX_GIT_CHARS}
（※ git活動が長いため切り詰め）"
fi

# 当日のセッション要約を新しい方から keep 件だけ連結する（古い方を落とす）
# daily-review-auto.sh の見出し形式（## <project> — <HH:MM>）を踏襲
build_sessions() {
  local keep="$1" out="" sf proj end_ts end_hm body
  local files=()
  while IFS= read -r sf; do files+=("$sf"); done \
    < <(find "$SESSIONS_ROOT/$target_date" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
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
    # frontmatter は「project: 行より後の最初の ---」で終わる（先頭に余分な --- ブロックが
    # 付くファイルと標準形の両方に対応する。--- の個数には依存しない）
    body="$(awk '/^project: /{seen=1} /^---$/{if(seen && !body){body=1; next}} body{print}' "$sf")"
    # 本文が空の要約（薄いセッション等）は見出しごとスキップしてトークンを節約する
    if [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
      continue
    fi
    out="${out}## ${proj} — ${end_hm}

${body}

---

"
  done
  printf '%s' "$out"
}

# 予算に収まるまで古いセッションから落とす
session_count="$(find "$SESSIONS_ROOT/$target_date" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
keep="$session_count"
[ "$keep" -eq 0 ] && keep=1
while :; do
  session_summaries="$(build_sessions "$keep")"
  payload="【対象日】${target_date}

【git活動（当日コミット・ローカル収集）】
${git_log}

【Rocket Chat 当日履歴（購読ルーム横断・DM除く）】
${rocketchat_log}

【メール（当日・自分が関与したスレッドのみ）】
${mail_log}

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

# POST（429/503/一時的な401 等に備えて指数バックオフで最大 MAX_ATTEMPTS 回）
# 恒久エラー（再認可待ち等）と判定できた場合は待たずに中断する
resp_file="$(mktemp /tmp/fire-daily-review-resp-XXXX.json)"
trap 'rm -f "$resp_file"' EXIT
backoff="$INITIAL_BACKOFF"
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
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
  resp_body="$(cat "$resp_file" 2>/dev/null || true)"
  log "fire failed (attempt=$attempt/$MAX_ATTEMPTS, http=$http_code): $resp_body"

  # 恒久エラーは即中断する。再認可・権限系はリトライしても永久に成功しないため
  # （実データ: 2026-06-11 に github_repo_access_denied で 3回×2セット=6回を無駄打ち）。
  # 401（認証の一時失敗）はリトライ対象に含める。同一トークンで1分後に成功した実績があり
  # （2026-07-13 attempt=1 が 401 → attempt=2 で成功）、トークン失効ではないと判断できる。
  if is_permanent_error "$http_code" "$resp_body"; then
    log "fire aborting: 恒久エラーと判定（リトライしても回復しないため中断）"
    exit 1
  fi

  # 指数バックオフ（60→120→240→480秒）。一時的な認証エラーが数分続いても
  # 拾えるよう、旧実装の「60秒固定×3回=最大2分」から待機総量を約15分へ広げる。
  if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
    log "retrying in ${backoff}s"
    sleep "$backoff"
    backoff=$((backoff * 2))
  fi
done
log "fire giving up after $MAX_ATTEMPTS attempts"
exit 1

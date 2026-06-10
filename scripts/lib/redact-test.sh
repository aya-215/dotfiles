#!/bin/bash
# redact-test.sh - redact.sh の動作確認テスト
# 使用方法: bash scripts/lib/redact-test.sh （全部 ok なら ALL OK で exit 0）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
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

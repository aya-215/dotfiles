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

#!/bin/bash
# run.sh - Rocket Chat MCP（mcp-remote）を .env.local の認証情報で起動する
#
# Claude Code の user スコープ MCP の command として登録し、全リポジトリから使う。
# 公開リポジトリのため、社内 URL と認証情報はこのファイルにも ~/.claude.json にも書かず
# .env.local（gitignore 済み、rocketchat.sh と共用）だけに置く。
#
# 登録:
#   claude mcp add --scope user rocketchat -- ~/.dotfiles/scripts/rocketchat-mcp/run.sh
#
# 環境変数:
#   RC_ENV_FILE  認証情報ファイル（既定: scripts/daily-review/.env.local）
#                必要なキー: RC_MCP_URL / RC_TOKEN / RC_USER_ID
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${RC_ENV_FILE:-$SCRIPT_DIR/../daily-review/.env.local}"

if [ ! -f "$env_file" ]; then
  echo "ERROR: $env_file が見つかりません" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$env_file"

missing=()
for key in RC_MCP_URL RC_TOKEN RC_USER_ID; do
  [ -n "${!key:-}" ] || missing+=("$key")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: $env_file に ${missing[*]} がありません" >&2
  exit 1
fi

exec npx mcp-remote "$RC_MCP_URL" \
  --header "rocketchat-auth-token:$RC_TOKEN" \
  --header "rocketchat-user-id:$RC_USER_ID" \
  --allow-http

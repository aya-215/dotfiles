#!/usr/bin/env bash
# gitbucket-mcp を stdio で起動し、tools/list で返ってきたツール名を1行ずつ出す。
#   bash scripts/gitbucket-mcp/smoke.sh | wc -l
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# stdin をすぐ閉じると返事の前にサーバが終わるため、sleep で開けておく
{
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 4
} | timeout 60 uv --directory "$DIR" run server.py 2>/dev/null | jq -r 'select(.id == 2) | .result.tools[].name'

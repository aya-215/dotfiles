#!/usr/bin/env bash
# afk 中に後回しにすべき操作（permissions.ask）を、全スコープの settings から列挙する。
# remote-settings.json は env にトークンを含むため、permissions.ask 以外は出力しない。
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

sources=(
  "org:$HOME/.claude/remote-settings.json"
  "managed:/etc/claude-code/managed-settings.json"
  "user:$HOME/.claude/settings.json"
  "user-local:$HOME/.claude/settings.local.json"
  "project:$repo_root/.claude/settings.json"
  "project-local:$repo_root/.claude/settings.local.json"
)

for entry in "${sources[@]}"; do
  label=${entry%%:*}
  file=${entry#*:}
  [[ -r $file ]] || continue
  jq -r --arg label "$label" '(.permissions.ask // [])[] | "\($label)\t\(.)"' "$file" 2>/dev/null || true
done | sort -u -k2

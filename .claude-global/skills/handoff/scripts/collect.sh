#!/usr/bin/env bash
# Print the facts a handoff note records about the current directory, one key=value per line:
# cwd, remote, branch, pr_url, pr_number, created. A field that cannot be read is left empty.
set -euo pipefail

cwd=$(pwd)
remote=$(git remote get-url origin 2>/dev/null || true)
branch=$(git branch --show-current 2>/dev/null || true)
pr_url=""
pr_number=""
# The github-<account> SSH aliases in ~/.ssh/config hide github.com, so match "github" alone.
if [[ "$remote" == *github* ]] && [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
  pr_json=$(gh pr view --json url,number 2>/dev/null || true)
  if [ -n "$pr_json" ]; then
    pr_url=$(jq -r '.url // empty' <<<"$pr_json" 2>/dev/null || true)
    pr_number=$(jq -r '.number // empty' <<<"$pr_json" 2>/dev/null || true)
  fi
fi

printf 'cwd=%s\nremote=%s\nbranch=%s\npr_url=%s\npr_number=%s\ncreated=%s\n' \
  "$cwd" "$remote" "$branch" "$pr_url" "$pr_number" "$(date '+%Y-%m-%d %H:%M')"

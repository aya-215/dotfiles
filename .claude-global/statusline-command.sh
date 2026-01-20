#!/bin/bash
input=$(cat)

# Nerd Font icons
icon_folder=$'\U000F024B'   # 󰉋 nf-md-folder
icon_branch=$'\UF126'       #  nf-fa-code_fork
icon_model=$'\U000F06A9'    # 󰚩 nf-md-robot
icon_context=$'\U000F01BC'  # 󰆼 nf-md-database

# Extract current directory
current_dir=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | head -1 | sed 's/"current_dir":"//;s/"//')
current_dir=$(basename "$current_dir")

# Extract model display_name using grep/sed (no jq required)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | sed 's/"display_name":"//;s/"//')

# Extract context window values
context_size=$(echo "$input" | grep -o '"context_window_size":[0-9]*' | sed 's/"context_window_size"://')
input_tokens=$(echo "$input" | grep -o '"input_tokens":[0-9]*' | head -1 | sed 's/"input_tokens"://')
cache_creation=$(echo "$input" | grep -o '"cache_creation_input_tokens":[0-9]*' | sed 's/"cache_creation_input_tokens"://')
cache_read=$(echo "$input" | grep -o '"cache_read_input_tokens":[0-9]*' | sed 's/"cache_read_input_tokens"://')

# Format number as K (e.g., 35000 -> 35K)
format_k() {
  local n=$1
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    echo "$((n / 1000))K"
  else
    echo "${n:-0}"
  fi
}

# Calculate context usage percentage (until autocompact)
# Autocompact buffer is ~22.5% of context, so effective max is 77.5%
AUTOCOMPACT_RATIO=775  # 77.5% as integer (775/1000)

if [ -n "$context_size" ] && [ "$context_size" -gt 0 ] 2>/dev/null; then
  current=$((${input_tokens:-0} + ${cache_creation:-0} + ${cache_read:-0}))
  effective_max=$((context_size * AUTOCOMPACT_RATIO / 1000))
  compact_pct=$((current * 100 / effective_max))
  current_k=$(format_k $current)
  effective_k=$(format_k $effective_max)
  context_info="${compact_pct}% (${current_k}/${effective_k})"
else
  context_info="0%"
fi

# Get git branch
git_branch=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git branch --show-current 2>/dev/null)
fi

printf "%s %s | %s %s | %s %s | %s %s" \
  "$icon_folder" "$current_dir" \
  "$icon_branch" "$git_branch" \
  "$icon_model" "$model" \
  "$icon_context" "$context_info"

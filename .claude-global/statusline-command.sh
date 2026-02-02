#!/bin/bash
input=$(cat)

# Nerd Font icons
icon_folder=$'\U000F024B'   # 󰉋 nf-md-folder
icon_branch=$'\UF126'       #  nf-fa-code_fork
icon_model=$'\U000F06A9'    # 󰚩 nf-md-robot
icon_context=$'\U000F01BC'  # 󰆼 nf-md-database
icon_todo=$'\U2611'          # ☑ ballot box with check

# ANSI colors (Catppuccin Mocha)
# Rule: location=cool, status=warm, meta=mid
B='\033[38;2;137;180;250m'  # Blue #89B4FA - folder/path
L='\033[38;2;180;190;254m'  # Lavender #B4BEFE - git branch
Y='\033[38;2;249;226;175m'  # Yellow #F9E2AF - dirty status
P='\033[38;2;250;179;135m'  # Peach #FAB387 - model
S='\033[38;2;108;112;134m'  # Overlay0 #6C7086 - separator
M='\033[38;2;203;166;247m'  # Mauve #CBA6F7 - context
G='\033[38;2;166;227;161m'  # Green #A6E3A1 - todo
R='\033[0m'                  # Reset

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

# Extract transcript path
transcript=$(echo "$input" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')

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

# Get git branch and dirty status
git_branch=""
git_dirty=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git branch --show-current 2>/dev/null)
  if [ -n "$git_branch" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git_dirty="*"
  fi
fi

# Count pending TODOs from transcript (created - completed - deleted)
todo_count=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  created=$(grep -c '"name":"TaskCreate"' "$transcript" 2>/dev/null) || created=0
  completed=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"completed"') || completed=0
  deleted=$(grep '"name":"TaskUpdate"' "$transcript" 2>/dev/null | grep -c '"deleted"') || deleted=0
  todo_count=$((created - completed - deleted))
  [ "$todo_count" -lt 0 ] && todo_count=0
fi

# Output with colors
printf "${B}%s %s${R}" "$icon_folder" "$current_dir"
printf " ${S}|${R} "
printf "${L}%s %s${R}${Y}%s${R}" "$icon_branch" "$git_branch" "$git_dirty"
printf " ${S}|${R} "
printf "${P}%s %s${R}" "$icon_model" "$model"
printf " ${S}|${R} "
printf "${M}%s %s${R}" "$icon_context" "$context_info"
if [ "$todo_count" -gt 0 ] 2>/dev/null; then
  printf " ${S}|${R} "
  printf "${G}%s %s${R}" "$icon_todo" "$todo_count"
fi
echo

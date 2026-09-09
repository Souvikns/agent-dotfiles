#!/bin/bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

# --- Prompt segment: replicates the Oh My Zsh "sunrise" theme prompt ---
# (--- <last 2 path segments> <git branch><*if dirty> » )
BOLD=$'\033[1m'
RESET_C=$'\033[0m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'

home="$HOME"
case "$cwd" in
  "$home") rel="~" ;;
  "$home"/*) rel="~${cwd#$home}" ;;
  *) rel="$cwd" ;;
esac

IFS='/' read -ra parts <<< "$rel"
n=${#parts[@]}
if [ "$n" -ge 2 ]; then
  dir_display="${parts[$((n-2))]}/${parts[$((n-1))]}"
else
  dir_display="$rel"
fi

branch_display=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ref=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    dirty=""
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      dirty="${RED}*"
    fi
    branch_display=" ${YELLOW}<${ref}${dirty}${YELLOW}>${RESET_C}"
  fi
fi

prompt_line=$(printf '%s' "${BOLD}--- ${dir_display}${branch_display} ${MAGENTA}»${RESET_C}")

# --- Context usage segment (kept from previous status line) ---
USED=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
REM_PCT=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)

USED_K=$(( USED / 1000 ))
TOTAL_K=$(( TOTAL / 1000 ))

if [ "$REM_PCT" -le 15 ]; then
    COLOR="\033[31m"
elif [ "$REM_PCT" -le 35 ]; then
    COLOR="\033[33m"
else
    COLOR="\033[32m"
fi
RESET="\033[0m"

printf "%s  ${COLOR}session-context: ${USED_K}k/${TOTAL_K}k (${REM_PCT}%% remaining)${RESET}\n" "$prompt_line"

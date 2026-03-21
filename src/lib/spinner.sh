#!/usr/bin/env bash
# =============================================================================
#  lib/spinner.sh — Braille spinner with cleanup for cwf
# =============================================================================

# Guard against double-sourcing
[[ -n "${_CWF_SPINNER_LOADED:-}" ]] && return 0
_CWF_SPINNER_LOADED=1

SPINNER_PID=""

start_spinner() {
  local msg="$1"
  local frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  tput civis >&2 2>/dev/null  # hide cursor
  (
    i=0
    while true; do
      printf "\r\033[36m  %s\033[0m %s" "${frames:i%${#frames}:1}" "$msg" >&2
      i=$((i + 1))
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
    printf "\r\033[K" >&2  # clear line
    tput cnorm >&2 2>/dev/null  # restore cursor
  fi
}

cleanup_spinner() {
  stop_spinner
  tput cnorm >&2 2>/dev/null
}

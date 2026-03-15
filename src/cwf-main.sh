#!/usr/bin/env bash
# =============================================================================
#  cwf-main.sh — CLI router for claude-workflow
#  This file contains ALL command routing logic.
#  The cwf wrapper just calls: exec bash this-file "$@"
# =============================================================================

INSTALL_DIR="$HOME/.claude-workflow"

# ── Colors & helpers ────────────────────────────────────────────────────────
BOLD='\033[1m'  RESET='\033[0m'
CYAN='\033[36m' RED='\033[31m' BLUE='\033[34m' GREEN='\033[32m'

print_header() { printf "\n${BOLD}${BLUE}  ══════════════════════════════════════════${RESET}\n${BOLD}    %s${RESET}\n${BOLD}${BLUE}  ══════════════════════════════════════════${RESET}\n\n" "$1"; }
print_error()  { printf "${RED}  ✗ %s${RESET}\n" "$1"; }

# ── Spinner ─────────────────────────────────────────────────────────────────
SPINNER_PID=""

start_spinner() {
  local msg="$1"
  local frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  tput civis 2>/dev/null  # hide cursor
  (
    i=0
    while true; do
      printf "\r${CYAN}  %s${RESET} %s" "${frames:i%${#frames}:1}" "$msg"
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
    printf "\r\033[K"  # clear line
    tput cnorm 2>/dev/null  # restore cursor
  fi
}

cleanup_spinner() {
  stop_spinner
  tput cnorm 2>/dev/null
}
trap cleanup_spinner EXIT INT TERM

# ── Run claude non-interactively ────────────────────────────────────────────
run_claude() {
  local cmd_file="$1"   # e.g. "cwf-status"
  local args="$2"       # arguments to substitute for $ARGUMENTS
  local label="$3"      # e.g. "status" or "issue 42"
  local spinner_msg="$4" # e.g. "Analyzing project status..."

  local cmd_path=".claude/commands/${cmd_file}.md"

  # Check command file exists (project must be initialized)
  if [ ! -f "$cmd_path" ]; then
    print_error "Command file not found: $cmd_path"
    print_error "Run 'cwf init' first to configure this project."
    exit 1
  fi

  # Check claude is available
  if ! command -v claude &>/dev/null; then
    print_error "claude CLI not found on PATH."
    print_error "Install it from https://docs.anthropic.com/en/docs/claude-code"
    exit 1
  fi

  # --interactive flag → fallback to TUI mode
  if [[ "$args" == *"--interactive"* ]]; then
    args="${args//--interactive/}"
    args="$(echo "$args" | xargs)"  # trim whitespace
    exec claude "/${cmd_file} $args"
  fi

  # Read the command file, strip YAML frontmatter, replace $ARGUMENTS
  local prompt
  prompt=$(sed '/^---$/,/^---$/d' "$cmd_path")
  prompt="${prompt//\$ARGUMENTS/$args}"

  # Display header and start spinner
  print_header "cwf $label"
  start_spinner "$spinner_msg"

  # Run claude in non-interactive mode
  local output exit_code
  output=$(claude -p --output-format text "$prompt" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}

  stop_spinner

  if [ "$exit_code" -ne 0 ]; then
    print_error "Claude exited with code $exit_code"
    printf "\n%s\n" "$output"
    exit "$exit_code"
  fi

  printf "%s\n" "$output"
}

# ── Update check (background) ───────────────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --silent &
fi

# ── Show update notice if available ──────────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --notice
fi

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  echo "Usage: cwf <command>"
  echo ""
  echo "Commands:"
  echo "  init                    Configure claude-workflow in current project"
  echo "  status                  Show issues, branches, and MR status"
  echo "  issues                  Analyze all issues and propose a plan"
  echo "  issues start            Start working after plan validation"
  echo "  issue <n>               Work on a specific issue"
  echo "  issue <n> --interactive Work on issue with terminal questions"
  echo "  update                  Update cwf to latest version"
  echo "  uninstall               Uninstall cwf"
  echo ""
  echo "  cwf --help              Show this help"
}

# ── Command routing ──────────────────────────────────────────────────────────
case "$1" in
  init)
    exec bash "$INSTALL_DIR/install-claude-workflow.sh"
    ;;
  status)
    run_claude "cwf-status" "" "status" "Analyzing project status..."
    ;;
  issues)
    shift
    run_claude "cwf-issues" "$*" "issues" "Analyzing issues..."
    ;;
  issue)
    shift
    run_claude "cwf-issue" "$*" "issue $*" "Working on issue..."
    ;;
  update)
    exec bash "$INSTALL_DIR/update.sh" --update
    ;;
  uninstall)
    exec bash "$INSTALL_DIR/update.sh" --uninstall
    ;;
  ""|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo ""
    show_help
    exit 1
    ;;
esac

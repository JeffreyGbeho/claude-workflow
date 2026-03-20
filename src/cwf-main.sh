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

print_header() { printf "\n${BOLD}${BLUE}  ══════════════════════════════════════════${RESET}\n${BOLD}    %s${RESET}\n${BOLD}${BLUE}  ══════════════════════════════════════════${RESET}\n\n" "$1" >&2; }
print_error()  { printf "${RED}  ✗ %s${RESET}\n" "$1" >&2; }

# ── Spinner & process management ────────────────────────────────────────────
SPINNER_PID=""
CLAUDE_PID=""
CLAUDE_TMPFILE=""

start_spinner() {
  local msg="$1"
  local frames="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  tput civis >&2 2>/dev/null  # hide cursor
  (
    i=0
    while true; do
      printf "\r${CYAN}  %s${RESET} %s" "${frames:i%${#frames}:1}" "$msg" >&2
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

cleanup() {
  stop_spinner
  if [ -n "$CLAUDE_PID" ]; then
    kill "$CLAUDE_PID" 2>/dev/null
    wait "$CLAUDE_PID" 2>/dev/null
    CLAUDE_PID=""
  fi
  [ -n "$CLAUDE_TMPFILE" ] && rm -f "$CLAUDE_TMPFILE"
  tput cnorm >&2 2>/dev/null
}
trap 'cleanup; exit 130' INT TERM
trap 'cleanup' EXIT

# ── Run claude non-interactively ────────────────────────────────────────────
run_claude() {
  local cmd_file="$1"    # e.g. "cwf-status"
  local args="$2"        # arguments to substitute for $ARGUMENTS
  local label="$3"       # e.g. "status" or "issue 42"
  local spinner_msg="$4" # e.g. "Analyzing project status..."
  local prompt_prefix="$5" # optional: prepended to prompt for disambiguation

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
    args="${args#"${args%%[![:space:]]*}"}"  # trim leading whitespace
    args="${args%"${args##*[![:space:]]}"}"  # trim trailing whitespace
    exec claude "/${cmd_file} $args"
  fi

  # Read the command file, strip YAML frontmatter, replace $ARGUMENTS
  local prompt
  prompt=$(sed '/^---$/,/^---$/d' "$cmd_path")
  prompt="${prompt//\$ARGUMENTS/$args}"
  [ -n "$prompt_prefix" ] && prompt="${prompt_prefix}"$'\n\n'"${prompt}"

  # Display header and start spinner
  print_header "cwf $label"
  start_spinner "$spinner_msg"

  # Run claude in background so Ctrl+C can kill it
  CLAUDE_TMPFILE=$(mktemp)
  claude -p --output-format text "$prompt" > "$CLAUDE_TMPFILE" 2>&1 &
  CLAUDE_PID=$!

  wait "$CLAUDE_PID" 2>/dev/null
  local exit_code=$?
  CLAUDE_PID=""

  stop_spinner

  if [ "$exit_code" -ne 0 ]; then
    print_error "Claude exited with code $exit_code"
    cat "$CLAUDE_TMPFILE" >&2
    rm -f "$CLAUDE_TMPFILE"
    CLAUDE_TMPFILE=""
    exit "$exit_code"
  fi

  cat "$CLAUDE_TMPFILE"
  rm -f "$CLAUDE_TMPFILE"
  CLAUDE_TMPFILE=""
}

# ── Update check (background, silent) ───────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --silent >/dev/null 2>&1 &
fi

# ── Show update notice if available ──────────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --notice >&2
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
    if [ ! -f "$INSTALL_DIR/install-claude-workflow.sh" ]; then
      print_error "Installer not found. Reinstall cwf:"
      print_error "  curl -fsSL https://raw.githubusercontent.com/JeffreyGbeho/claude-workflow/main/bootstrap.sh | bash"
      exit 1
    fi
    exec bash "$INSTALL_DIR/install-claude-workflow.sh" init
    ;;
  status)
    run_claude "cwf-status" "" "status" "Analyzing project status..."
    ;;
  issues)
    shift
    if [ "$1" = "start" ]; then
      run_claude "cwf-issues" "$*" "issues start" "Starting implementation..." \
        "IMPORTANT: Skip Steps 1-5 entirely. Go directly to the section that handles the 'start' argument. Read the latest validation comment, then implement each issue in the validated order by creating branches, coding, committing, and opening PRs."
    else
      run_claude "cwf-issues" "$*" "issues${*:+ $*}" "Analyzing issues..."
    fi
    ;;
  issue)
    shift
    if [ -z "$1" ] || [[ "$1" == -* ]]; then
      print_error "Missing issue number. Usage: cwf issue <number>"
      exit 1
    fi
    run_claude "cwf-issue" "$*" "issue $*" "Working on issue..."
    ;;
  update)
    if [ ! -f "$INSTALL_DIR/update.sh" ]; then
      print_error "Update script not found. Reinstall cwf:"
      print_error "  curl -fsSL https://raw.githubusercontent.com/JeffreyGbeho/claude-workflow/main/bootstrap.sh | bash"
      exit 1
    fi
    exec bash "$INSTALL_DIR/update.sh" --update
    ;;
  uninstall)
    if [ ! -f "$INSTALL_DIR/update.sh" ]; then
      print_error "Uninstall script not found. Remove manually:"
      print_error "  rm -rf ~/.claude-workflow && rm -f \$(which cwf)"
      exit 1
    fi
    exec bash "$INSTALL_DIR/update.sh" --uninstall
    ;;
  ""|--help|-h)
    show_help
    ;;
  *)
    print_error "Unknown command: $1"
    echo "" >&2
    show_help >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
# =============================================================================
#  watch.sh — cwf watch: poll for events and act on issues
# =============================================================================

set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.claude-workflow}"

# ── Source shared libraries ───────────────────────────────────────────────────
source "$INSTALL_DIR/lib/colors.sh"
source "$INSTALL_DIR/lib/api.sh"

# ── State management ─────────────────────────────────────────────────────────
STATE_DIR=".claude-workflow"
STATE_FILE="$STATE_DIR/.watch-state"

init_state() {
  mkdir -p "$STATE_DIR"
  [ -f "$STATE_FILE" ] || touch "$STATE_FILE"
}

# Read a state value: state_get "issue" "12" "last_comment_id"
state_get() {
  local type="$1" id="$2" key="$3"
  while IFS='|' read -r stype sid rest; do
    if [ "$stype" = "$type" ] && [ "$sid" = "$id" ]; then
      # Parse key=value pairs from rest
      local IFS='|'
      for pair in $rest; do
        local k="${pair%%=*}"
        local v="${pair#*=}"
        if [ "$k" = "$key" ]; then
          echo "$v"
          return 0
        fi
      done
    fi
  done < "$STATE_FILE"
  echo ""
}

# Write/update a state value: state_set "issue" "12" "last_comment_id" "987654"
state_set() {
  local type="$1" id="$2" key="$3" value="$4"
  local tmpfile
  tmpfile=$(mktemp)
  local found=0

  while IFS= read -r line; do
    local stype sid rest
    IFS='|' read -r stype sid rest <<< "$line"
    if [ "$stype" = "$type" ] && [ "$sid" = "$id" ]; then
      found=1
      # Update or add the key in this line
      local new_rest=""
      local key_found=0
      local IFS_SAVE="$IFS"
      IFS='|'
      for pair in $rest; do
        local k="${pair%%=*}"
        if [ "$k" = "$key" ]; then
          new_rest="${new_rest:+${new_rest}|}${key}=${value}"
          key_found=1
        else
          new_rest="${new_rest:+${new_rest}|}${pair}"
        fi
      done
      IFS="$IFS_SAVE"
      if [ "$key_found" -eq 0 ]; then
        new_rest="${new_rest:+${new_rest}|}${key}=${value}"
      fi
      echo "${type}|${id}|${new_rest}" >> "$tmpfile"
    else
      echo "$line" >> "$tmpfile"
    fi
  done < "$STATE_FILE"

  if [ "$found" -eq 0 ]; then
    echo "${type}|${id}|${key}=${value}" >> "$tmpfile"
  fi

  mv "$tmpfile" "$STATE_FILE"
}

state_set_last_poll() {
  local tmpfile
  tmpfile=$(mktemp)
  local found=0
  while IFS= read -r line; do
    local stype rest
    IFS='|' read -r stype rest <<< "$line"
    if [ "$stype" = "last_poll" ]; then
      echo "last_poll|$1" >> "$tmpfile"
      found=1
    else
      echo "$line" >> "$tmpfile"
    fi
  done < "$STATE_FILE"
  if [ "$found" -eq 0 ]; then
    echo "last_poll|$1" >> "$tmpfile"
  fi
  mv "$tmpfile" "$STATE_FILE"
}

state_get_last_poll() {
  while IFS='|' read -r stype rest; do
    if [ "$stype" = "last_poll" ]; then
      echo "$rest"
      return 0
    fi
  done < "$STATE_FILE"
  echo ""
}

# ── Job tracking ─────────────────────────────────────────────────────────────
declare -A RUNNING_PIDS=()
declare -A STREAM_PIDS=()

is_issue_running() {
  local issue_number="$1"
  local pid="${RUNNING_PIDS[$issue_number]:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ── "Go" detection ───────────────────────────────────────────────────────────
is_go_comment() {
  local body
  body=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$body" in
    "go"|"go!"|"lgtm"|"approved"|"ship it") return 0 ;;
    *) return 1 ;;
  esac
}

# ── Timestamp helpers ─────────────────────────────────────────────────────────
now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_display() {
  date +"%H:%M:%S"
}

# ── Event display ─────────────────────────────────────────────────────────────
log_event() {
  local issue="$1" emoji="$2" msg="$3"
  printf "  ${DIM}%s${RESET}  #%s · %s %s\n" "$(now_display)" "$issue" "$emoji" "$msg"
}

log_action() {
  local msg="$1"
  printf "            → %s\n" "$msg"
}

# ── Poll cycle functions ─────────────────────────────────────────────────────

# NOTE: All loops use `< <(json_extract_array ...)` instead of
# `json_extract_array ... | while` to avoid subshells. This ensures
# modifications to RUNNING_PIDS/STREAM_PIDS propagate to the parent scope.

check_new_comments() {
  local issues_json="$1"
  local since
  since=$(state_get_last_poll)

  while IFS= read -r issue_json; do
    local issue_number
    if [ "$PLATFORM" = "GitHub" ]; then
      issue_number=$(json_extract_raw "$issue_json" "number")
    else
      issue_number=$(json_extract_raw "$issue_json" "iid")
    fi
    [ -z "$issue_number" ] && continue

    local comments_json
    comments_json=$(api_get_comments "$issue_number" "$since")
    [ -z "$comments_json" ] || [ "$comments_json" = "[]" ] && continue

    while IFS= read -r comment_json; do
      local comment_id body author
      comment_id=$(json_extract_raw "$comment_json" "id")
      body=$(json_extract "$comment_json" "body")
      if [ "$PLATFORM" = "GitHub" ]; then
        author=$(echo "$comment_json" | sed -n 's/.*"login" *: *"\([^"]*\)".*/\1/p' | head -1)
      else
        author=$(echo "$comment_json" | sed -n 's/.*"username" *: *"\([^"]*\)".*/\1/p' | head -1)
      fi

      # Skip empty comments
      [ -z "$body" ] && continue

      local last_seen
      last_seen=$(state_get "issue" "$issue_number" "last_comment_id")
      [ "$comment_id" = "$last_seen" ] && continue

      state_set "issue" "$issue_number" "last_comment_id" "$comment_id"

      if is_go_comment "$body"; then
        log_event "$issue_number" "💬" "@${author}: \"${body}\""
        handle_go "$issue_number"
      else
        log_event "$issue_number" "💬" "@${author} commented"
        # Check if this looks like an answer to questions
        local had_questions
        had_questions=$(state_get "issue" "$issue_number" "has_questions")
        if [ "$had_questions" = "1" ]; then
          log_action "Issue #${issue_number} may be ready for 'go'"
          state_set "issue" "$issue_number" "has_questions" "0"
        fi
      fi
    done < <(json_extract_array "$comments_json")
  done < <(json_extract_array "$issues_json")
}

check_pr_merges() {
  local prs_json
  prs_json=$(api_get_prs)
  [ -z "$prs_json" ] || [ "$prs_json" = "[]" ] && return 0

  while IFS= read -r pr_json; do
    local pr_number state merged
    if [ "$PLATFORM" = "GitHub" ]; then
      pr_number=$(json_extract_raw "$pr_json" "number")
      state=$(json_extract "$pr_json" "state")
      merged=$(json_extract_raw "$pr_json" "merged")
    else
      pr_number=$(json_extract_raw "$pr_json" "iid")
      state=$(json_extract "$pr_json" "state")
      merged=$(json_extract "$pr_json" "merged_at")
    fi

    local prev_state
    prev_state=$(state_get "pr" "$pr_number" "state")

    if [ "$state" = "closed" ] || [ "$state" = "merged" ]; then
      if [ "$prev_state" != "merged" ] && [ "$prev_state" != "closed" ]; then
        # Extract linked issue from PR body/title
        local title
        title=$(json_extract "$pr_json" "title")
        local linked_issue
        linked_issue=$(echo "$title" | sed -n 's/.*#\([0-9]*\).*/\1/p' | head -1)

        if [ -n "$linked_issue" ]; then
          log_event "$linked_issue" "✅" "PR #${pr_number} merged"
          state_set "pr" "$pr_number" "state" "merged"
        fi
      fi
    else
      state_set "pr" "$pr_number" "state" "$state"
    fi
  done < <(json_extract_array "$prs_json")
}

check_new_issues() {
  local issues_json="$1"

  while IFS= read -r issue_json; do
    local issue_number title
    if [ "$PLATFORM" = "GitHub" ]; then
      issue_number=$(json_extract_raw "$issue_json" "number")
    else
      issue_number=$(json_extract_raw "$issue_json" "iid")
    fi
    title=$(json_extract "$issue_json" "title")
    [ -z "$issue_number" ] && continue

    local known
    known=$(state_get "issue" "$issue_number" "known")
    if [ -z "$known" ]; then
      state_set "issue" "$issue_number" "known" "1"
      # Don't fire on first run — mark existing issues as known
      if [ -n "$(state_get_last_poll)" ]; then
        log_event "$issue_number" "🆕" "New issue: ${title}"
        handle_new_issue "$issue_number" "$title"
      fi
    fi
  done < <(json_extract_array "$issues_json")
}

# ── Action handlers ──────────────────────────────────────────────────────────

handle_go() {
  local issue_number="$1"

  case "$WATCH_MODE" in
    notify)
      log_action "Ready to implement (run: cwf issue $issue_number)"
      ;;
    semi-auto)
      printf "            → Start implementation? [Y/n] "
      local answer
      read -r -t 30 answer </dev/tty 2>/dev/null || answer="n"
      answer="${answer:-y}"
      if [[ "$answer" =~ ^[Yy] ]]; then
        launch_issue "$issue_number"
      else
        log_action "Skipped"
      fi
      ;;
    full-auto)
      launch_issue "$issue_number"
      ;;
  esac
}

handle_new_issue() {
  local issue_number="$1" title="$2"

  case "$WATCH_MODE" in
    notify)
      log_action "Analyze with: cwf issue $issue_number"
      ;;
    semi-auto)
      log_action "New issue detected. Run 'cwf issue $issue_number' to analyze."
      ;;
    full-auto)
      log_action "Auto-analyzing issue #${issue_number}..."
      launch_issue "$issue_number"
      ;;
  esac
}

launch_issue() {
  local issue_number="$1"

  # Don't launch if already running
  if is_issue_running "$issue_number"; then
    log_action "Issue #${issue_number} already running"
    return
  fi

  log_action "Launching cwf issue ${issue_number}..."

  local logfile="$STATE_DIR/issue-${issue_number}.log"
  : > "$logfile"

  # Run the command in background
  bash "$INSTALL_DIR/cwf-main.sh" issue "$issue_number" > "$logfile" 2>&1 &
  local cmd_pid=$!
  RUNNING_PIDS[$issue_number]=$cmd_pid
  state_set "issue" "$issue_number" "pid" "$cmd_pid"

  # Stream logs in real-time, prefixed with issue number
  # tail --pid exits when the command finishes; sed -u flushes per line
  tail -n +1 -f --pid="$cmd_pid" "$logfile" 2>/dev/null \
    | sed -u "s/^/  [#${issue_number}] /" &
  STREAM_PIDS[$issue_number]=$!

  log_action "Running (PID $cmd_pid)"
}

# ── Job completion detection ─────────────────────────────────────────────────

check_running_jobs() {
  for issue_number in "${!RUNNING_PIDS[@]}"; do
    local pid="${RUNNING_PIDS[$issue_number]}"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null
      local exit_code=$?

      # Let the log streamer flush remaining output
      sleep 0.5
      local stream_pid="${STREAM_PIDS[$issue_number]:-}"
      if [ -n "$stream_pid" ] && kill -0 "$stream_pid" 2>/dev/null; then
        kill "$stream_pid" 2>/dev/null
        wait "$stream_pid" 2>/dev/null
      fi

      unset "RUNNING_PIDS[$issue_number]"
      unset "STREAM_PIDS[$issue_number]"
      state_set "issue" "$issue_number" "pid" ""

      if [ "$exit_code" -eq 0 ]; then
        log_event "$issue_number" "✅" "Implementation complete"
      else
        log_event "$issue_number" "❌" "Failed (exit code $exit_code)"
      fi
    fi
  done
}

# ── Main poll cycle ──────────────────────────────────────────────────────────

poll_cycle() {
  # Check if any background jobs have finished
  check_running_jobs

  local issues_json
  issues_json=$(api_get_issues 2>/dev/null || echo "")

  if [ -z "$issues_json" ] || [ "$issues_json" = "[]" ]; then
    return 0
  fi

  check_new_issues "$issues_json"
  check_new_comments "$issues_json"
  check_pr_merges

  state_set_last_poll "$(now_iso)"
}

# ── Cleanup & signal handling ────────────────────────────────────────────────

watch_cleanup() {
  echo ""
  # Kill all running issue commands
  for issue_number in "${!RUNNING_PIDS[@]}"; do
    local pid="${RUNNING_PIDS[$issue_number]}"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done
  # Kill all log streamers
  for issue_number in "${!STREAM_PIDS[@]}"; do
    local pid="${STREAM_PIDS[$issue_number]}"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
    fi
  done
  print_info "Saving state and stopping..."
  state_set_last_poll "$(now_iso)"
  exit 0
}

# ── Entry point ───────────────────────────────────────────────────────────────

main() {
  # Load project config
  if ! load_config; then
    print_error "Cannot start watch without project configuration."
    print_error "Run 'cwf init' first."
    exit 1
  fi

  # Parse CLI overrides
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode=*)
        WATCH_MODE="${1#--mode=}"
        ;;
      --interval=*)
        POLL_INTERVAL="${1#--interval=}"
        ;;
      *)
        print_error "Unknown option: $1"
        echo ""
        echo "Usage: cwf watch [--mode=notify|semi-auto|full-auto] [--interval=N]"
        exit 1
        ;;
    esac
    shift
  done

  # Defaults from config or fallback
  WATCH_MODE="${WATCH_MODE:-semi-auto}"
  POLL_INTERVAL="${POLL_INTERVAL:-30}"

  # Validate mode
  case "$WATCH_MODE" in
    notify|semi-auto|full-auto) ;;
    *)
      print_error "Invalid watch mode: $WATCH_MODE"
      print_error "Valid modes: notify, semi-auto, full-auto"
      exit 1
      ;;
  esac

  # Validate interval
  if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [ "$POLL_INTERVAL" -lt 5 ]; then
    print_error "Invalid poll interval: $POLL_INTERVAL (minimum 5 seconds)"
    exit 1
  fi

  # Initialize state
  init_state
  trap 'watch_cleanup' INT TERM

  # Header
  echo ""
  echo -e "${BOLD}${CYAN}cwf watch${RESET} · polling every ${POLL_INTERVAL}s · mode: ${BOLD}${WATCH_MODE}${RESET}"
  echo ""

  # Initial discovery (mark existing issues as known without firing events)
  local initial_issues
  initial_issues=$(api_get_issues 2>/dev/null || echo "")
  if [ -z "$initial_issues" ] || [ "$initial_issues" = "[]" ]; then
    print_warn "No open issues found (or API unreachable)"
  else
    # Mark all existing issues as known
    while IFS= read -r issue_json; do
      local issue_number
      if [ "$PLATFORM" = "GitHub" ]; then
        issue_number=$(json_extract_raw "$issue_json" "number")
      else
        issue_number=$(json_extract_raw "$issue_json" "iid")
      fi
      [ -n "$issue_number" ] && state_set "issue" "$issue_number" "known" "1"
    done < <(json_extract_array "$initial_issues")
    local count
    count=$(json_extract_array "$initial_issues" | wc -l)
    print_info "Tracking ${count} open issue(s)"
  fi

  state_set_last_poll "$(now_iso)"
  echo ""
  print_info "Ctrl+C to stop"
  echo ""

  # Main loop
  while true; do
    poll_cycle || true
    sleep "$POLL_INTERVAL"
  done
}

main "$@"

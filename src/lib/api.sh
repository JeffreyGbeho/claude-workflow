#!/usr/bin/env bash
# =============================================================================
#  lib/api.sh — Platform-agnostic API wrappers for GitHub/GitLab
# =============================================================================

# Guard against double-sourcing
[[ -n "${_CWF_API_LOADED:-}" ]] && return 0
_CWF_API_LOADED=1

# ── Config loading ────────────────────────────────────────────────────────────

load_config() {
  local config_path="${1:-.claude/config}"
  if [ ! -f "$config_path" ]; then
    print_error "Config not found: $config_path"
    print_error "Run 'cwf init' first to configure this project."
    return 1
  fi
  # shellcheck disable=SC1090
  source "$config_path"

  # Validate required variables
  if [ -z "${PLATFORM:-}" ]; then
    print_error "PLATFORM not set in $config_path"
    return 1
  fi
  if [ -z "${TOKEN:-}" ]; then
    print_error "TOKEN not set in $config_path"
    return 1
  fi

  # Platform-specific validation
  if [ "$PLATFORM" = "GitHub" ]; then
    if [ -z "${GITHUB_USERNAME:-}" ] || [ -z "${GITHUB_REPO:-}" ]; then
      print_error "GITHUB_USERNAME and GITHUB_REPO must be set in $config_path"
      return 1
    fi
  elif [ "$PLATFORM" = "GitLab" ]; then
    if [ -z "${GITLAB_URL:-}" ] || [ -z "${GITLAB_NAMESPACE:-}" ] || [ -z "${GITLAB_PROJECT:-}" ]; then
      print_error "GITLAB_URL, GITLAB_NAMESPACE, and GITLAB_PROJECT must be set in $config_path"
      return 1
    fi
  fi
}

# ── JSON parsing (sed-based, no jq required) ─────────────────────────────────

# Extract a string value for a given key from JSON
# Usage: json_extract "$json" "key"
json_extract() {
  local json="$1" key="$2"
  echo "$json" | sed -n 's/.*"'"$key"'" *: *"\([^"]*\)".*/\1/p' | head -1
}

# Extract a numeric/boolean value for a given key from JSON
# Usage: json_extract_raw "$json" "key"
json_extract_raw() {
  local json="$1" key="$2"
  echo "$json" | sed -n 's/.*"'"$key"'" *: *\([^,}]*\).*/\1/p' | head -1 | tr -d ' '
}

# Split a JSON array into individual top-level objects (one per line)
# Tracks brace depth and string boundaries to handle nested objects correctly
# Usage: json_extract_array "$json_array"
json_extract_array() {
  printf '%s\n' "$1" | awk '
  BEGIN { depth=0; in_str=0; esc=0; obj="" }
  {
    for (i=1; i<=length($0); i++) {
      c = substr($0, i, 1)
      if (esc)    { esc=0; obj = obj c; continue }
      if (c == "\\") { esc=1; obj = obj c; continue }
      if (c == "\"") { in_str = !in_str; obj = obj c; continue }
      if (in_str) { obj = obj c; continue }
      if (c == "{") { depth++; obj = obj c; continue }
      if (c == "}") {
        depth--
        obj = obj c
        if (depth == 0) { print obj; obj = "" }
        continue
      }
      if (depth > 0) { obj = obj c }
    }
  }'
}

# ── GitHub API helpers ────────────────────────────────────────────────────────

github_api() {
  local endpoint="$1" method="${2:-GET}" body="${3:-}"
  local url="https://api.github.com/repos/${GITHUB_USERNAME}/${GITHUB_REPO}${endpoint}"
  local args=(-s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json")

  if [ "$method" != "GET" ]; then
    args+=(-X "$method")
  fi
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  curl "${args[@]}" "$url" 2>/dev/null
}

github_get_issues() {
  github_api "/issues?state=open&per_page=100&sort=created&direction=asc"
}

github_get_issue() {
  github_api "/issues/$1"
}

github_get_comments() {
  local issue_number="$1" since="${2:-}"
  local endpoint="/issues/${issue_number}/comments?per_page=100"
  [ -n "$since" ] && endpoint="${endpoint}&since=${since}"
  github_api "$endpoint"
}

github_post_comment() {
  local issue_number="$1" body="$2"
  github_api "/issues/${issue_number}/comments" "POST" "{\"body\":$(json_escape "$body")}"
}

github_get_prs() {
  github_api "/pulls?state=open&per_page=100"
}

github_get_pr() {
  github_api "/pulls/$1"
}

github_create_pr() {
  local title="$1" head="$2" base="$3" body="$4"
  github_api "/pulls" "POST" \
    "{\"title\":$(json_escape "$title"),\"head\":$(json_escape "$head"),\"base\":$(json_escape "$base"),\"body\":$(json_escape "$body")}"
}

# ── GitLab API helpers ────────────────────────────────────────────────────────

gitlab_api() {
  local endpoint="$1" method="${2:-GET}" body="${3:-}"
  local project_encoded="${GITLAB_NAMESPACE}%2F${GITLAB_PROJECT}"
  local url="${GITLAB_URL}/api/v4/projects/${project_encoded}${endpoint}"
  local args=(-s --header "PRIVATE-TOKEN: $TOKEN")

  if [ "$method" != "GET" ]; then
    args+=(-X "$method")
  fi
  if [ -n "$body" ]; then
    args+=(--header "Content-Type: application/json" -d "$body")
  fi

  curl "${args[@]}" "$url" 2>/dev/null
}

gitlab_get_issues() {
  gitlab_api "/issues?state=opened&per_page=100&order_by=created_at&sort=asc"
}

gitlab_get_issue() {
  gitlab_api "/issues/$1"
}

gitlab_get_comments() {
  local issue_number="$1" since="${2:-}"
  local endpoint="/issues/${issue_number}/notes?per_page=100&order_by=created_at&sort=asc"
  gitlab_api "$endpoint"
}

gitlab_post_comment() {
  local issue_number="$1" body="$2"
  gitlab_api "/issues/${issue_number}/notes" "POST" "{\"body\":$(json_escape "$body")}"
}

gitlab_get_prs() {
  gitlab_api "/merge_requests?state=opened&per_page=100"
}

gitlab_get_pr() {
  gitlab_api "/merge_requests/$1"
}

gitlab_create_pr() {
  local title="$1" head="$2" base="$3" body="$4"
  gitlab_api "/merge_requests" "POST" \
    "{\"title\":$(json_escape "$title"),\"source_branch\":$(json_escape "$head"),\"target_branch\":$(json_escape "$base"),\"description\":$(json_escape "$body")}"
}

# ── Platform-agnostic dispatchers ─────────────────────────────────────────────

api_get_issues() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_get_issues
  else
    gitlab_get_issues
  fi
}

api_get_issue() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_get_issue "$1"
  else
    gitlab_get_issue "$1"
  fi
}

api_get_comments() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_get_comments "$1" "${2:-}"
  else
    gitlab_get_comments "$1" "${2:-}"
  fi
}

api_post_comment() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_post_comment "$1" "$2"
  else
    gitlab_post_comment "$1" "$2"
  fi
}

api_get_prs() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_get_prs
  else
    gitlab_get_prs
  fi
}

api_get_pr() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_get_pr "$1"
  else
    gitlab_get_pr "$1"
  fi
}

api_create_pr() {
  if [ "$PLATFORM" = "GitHub" ]; then
    github_create_pr "$1" "$2" "$3" "$4"
  else
    gitlab_create_pr "$1" "$2" "$3" "$4"
  fi
}

# ── Utility ───────────────────────────────────────────────────────────────────

# Escape a string for JSON embedding
json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"      # backslash
  str="${str//\"/\\\"}"      # double quote
  str="${str//$'\n'/\\n}"    # newline
  str="${str//$'\r'/\\r}"    # carriage return
  str="${str//$'\t'/\\t}"    # tab
  echo "\"$str\""
}

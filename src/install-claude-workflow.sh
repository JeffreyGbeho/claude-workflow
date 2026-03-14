#!/usr/bin/env bash
# =============================================================================
#  install-claude-workflow.sh
#  Automatically configures Claude Code workflow on GitHub or GitLab
# =============================================================================

set -e

# Restore cursor and exit cleanly on interrupt
cleanup() { tput cnorm 2>/dev/null || true; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# ── Colors ───────────────────────────────────────────────────────────────────
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"

# ── Helpers ──────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${BLUE}${BOLD}  $1${RESET}"
  echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo ""
}

print_step() {
  echo -e "${CYAN}${BOLD}▶ $1${RESET}"
}

print_ok() {
  echo -e "${GREEN}  ✓ $1${RESET}"
}

print_warn() {
  echo -e "${YELLOW}  ⚠ $1${RESET}"
}

print_error() {
  echo -e "${RED}  ✗ $1${RESET}"
}

print_info() {
  echo -e "${DIM}  $1${RESET}"
}

ask() {
  # ask "Question" VAR_NAME [default]
  local prompt="$1"
  local varname="$2"
  local default="$3"
  if [ -n "$default" ]; then
    echo -ne "${BOLD}  $prompt ${DIM}[$default]${RESET}: "
  else
    echo -ne "${BOLD}  $prompt${RESET}: "
  fi
  read -r input
  if [ -z "$input" ] && [ -n "$default" ]; then
    input="$default"
  fi
  eval "$varname=\"$input\""
}

ask_secret() {
  local prompt="$1"
  local varname="$2"
  echo -ne "${BOLD}  $prompt${RESET}: "
  read -rs input
  echo ""
  eval "$varname=\"$input\""
}

ask_choice() {
  # ask_choice "Question" VAR_NAME "Option1" "Option2" ...
  local prompt="$1"
  local varname="$2"
  shift 2
  local options=("$@")
  local selected=0
  local total=${#options[@]}

  printf "\n\033[1m  %s\033[0m\n" "$prompt"
  printf "  \033[2m(↑↓ arrows, Enter to confirm)\033[0m\n"
  printf "\033[?25l" # hide cursor

  for i in "${!options[@]}"; do
    if [ "$i" -eq "$selected" ]; then
      printf "  \033[36;1m❯ %s\033[0m\n" "${options[$i]}"
    else
      printf "    \033[2m%s\033[0m\n" "${options[$i]}"
    fi
  done

  while true; do
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.5 rest
      key="${key}${rest}"
    fi

    case "$key" in
      $'\x1b[A') [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
      $'\x1b[B') [ "$selected" -lt $((total - 1)) ] && selected=$((selected + 1)) ;;
      "") break ;;
      *) continue ;;
    esac

    printf "\033[%dA" "$total"
    for i in "${!options[@]}"; do
      printf "\r\033[2K"
      if [ "$i" -eq "$selected" ]; then
        printf "  \033[36;1m❯ %s\033[0m\n" "${options[$i]}"
      else
        printf "    \033[2m%s\033[0m\n" "${options[$i]}"
      fi
    done
  done

  printf "\033[?25h" # show cursor
  eval "$varname=\"${options[$selected]}\""
  print_ok "${options[$selected]}"
}

confirm() {
  local prompt="$1"
  local selected=0 # 0=Yes, 1=No

  printf "\033[1m  %s\033[0m\n" "$prompt"
  printf "\033[?25l" # hide cursor

  if [ "$selected" -eq 0 ]; then
    printf "  \033[36;1m❯ Yes\033[0m    \033[2mNo\033[0m"
  else
    printf "    \033[2mYes\033[0m  \033[36;1m❯ No\033[0m"
  fi

  while true; do
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.5 rest
      key="${key}${rest}"
    fi

    case "$key" in
      $'\x1b[A'|$'\x1b[B'|$'\x1b[C'|$'\x1b[D')
        selected=$(( 1 - selected ))
        ;;
      "") break ;;
      *) continue ;;
    esac

    printf "\r\033[2K"
    if [ "$selected" -eq 0 ]; then
      printf "  \033[36;1m❯ Yes\033[0m    \033[2mNo\033[0m"
    else
      printf "    \033[2mYes\033[0m  \033[36;1m❯ No\033[0m"
    fi
  done

  printf "\n"
  printf "\033[?25h" # show cursor

  [ "$selected" -eq 0 ]
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    print_error "$1 is not installed"
    return 1
  fi
  print_ok "$1 detected"
  return 0
}

# ── Credentials store ────────────────────────────────────────────────────────
CREDENTIALS_FILE="$HOME/.claude-workflow/credentials"

mask_token() {
  local token="$1"
  local len=${#token}
  if [ "$len" -le 4 ]; then
    echo "$token"
  else
    echo "***${token: -4}"
  fi
}

save_credential() {
  # save_credential platform username token
  local platform="$1"
  local username="$2"
  local token="$3"
  mkdir -p "$(dirname "$CREDENTIALS_FILE")"
  touch "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
  # Remove existing entry for this platform+username
  local tmp
  tmp=$(grep -v "^${platform}|${username}|" "$CREDENTIALS_FILE" 2>/dev/null || true)
  echo "$tmp" > "$CREDENTIALS_FILE"
  # Append new entry
  echo "${platform}|${username}|${token}" >> "$CREDENTIALS_FILE"
  # Remove empty lines
  sed -i '/^$/d' "$CREDENTIALS_FILE"
}

# select_or_create_token platform
# Sets: TOKEN_VALUE, TOKEN_USERNAME
select_or_create_token() {
  local platform="$1"

  # Load saved tokens for this platform
  local entries=()
  local usernames=()
  local tokens=()
  if [ -f "$CREDENTIALS_FILE" ]; then
    while IFS='|' read -r p u t; do
      if [ "$p" = "$platform" ] && [ -n "$u" ] && [ -n "$t" ]; then
        entries+=("$u ($(mask_token "$t"))")
        usernames+=("$u")
        tokens+=("$t")
      fi
    done < "$CREDENTIALS_FILE"
  fi

  if [ ${#entries[@]} -eq 0 ]; then
    # No saved tokens — go straight to creation
    create_new_token "$platform"
    return
  fi

  # Show saved tokens + option to add new
  local options=("${entries[@]}" "Add a new token")

  ask_choice "Select a $platform account:" SELECTED_ACCOUNT "${options[@]}"

  # Check if user chose "Add a new token"
  if [ "$SELECTED_ACCOUNT" = "Add a new token" ]; then
    create_new_token "$platform"
    return
  fi

  # Find the selected token
  for i in "${!entries[@]}"; do
    if [ "${entries[$i]}" = "$SELECTED_ACCOUNT" ]; then
      TOKEN_VALUE="${tokens[$i]}"
      TOKEN_USERNAME="${usernames[$i]}"
      return
    fi
  done
}

create_new_token() {
  local platform="$1"

  echo ""
  if [ "$platform" = "GitHub" ]; then
    print_info "You'll need a GitHub Personal Access Token."
    print_info "To create one: https://github.com/settings/tokens"
    print_info "Type: Fine-grained token"
    print_info "Permissions: Contents (R&W), Issues (R&W), Pull Requests (R&W)"
  else
    print_info "You'll need a GitLab Personal Access Token."
    print_info "To create one: ${GITLAB_URL:-https://gitlab.com}/-/user_settings/personal_access_tokens"
    print_info "Required scopes: api, read_repository, write_repository"
  fi
  echo ""

  ask "Your $platform Personal Access Token" TOKEN_VALUE

  # Verify token
  print_step "Verifying $platform token..."
  local response

  if [ "$platform" = "GitHub" ]; then
    response=$(curl -sf -H "Authorization: Bearer $TOKEN_VALUE" "https://api.github.com/user" 2>/dev/null || echo "ERROR")
  else
    response=$(curl -sf --header "PRIVATE-TOKEN: $TOKEN_VALUE" "$GITLAB_URL/api/v4/user" 2>/dev/null || echo "ERROR")
  fi

  if [ "$response" = "ERROR" ]; then
    print_error "Invalid token or instance unreachable"
    if confirm "Do you want to try again?"; then
      create_new_token "$platform"
      return
    else
      exit 1
    fi
  fi

  if [ "$platform" = "GitHub" ]; then
    TOKEN_USERNAME=$(echo "$response" | sed -n 's/.*"login" *: *"\([^"]*\)".*/\1/p' | head -1)
  else
    TOKEN_USERNAME=$(echo "$response" | sed -n 's/.*"username" *: *"\([^"]*\)".*/\1/p' | head -1)
  fi

  if [ -z "$TOKEN_USERNAME" ]; then
    print_error "Could not extract username from API response"
    if confirm "Do you want to try again?"; then
      create_new_token "$platform"
      return
    else
      exit 1
    fi
  fi

  print_ok "Logged in as: $TOKEN_USERNAME"

  # Save credential
  save_credential "$platform" "$TOKEN_USERNAME" "$TOKEN_VALUE"
  print_ok "Token saved for next time"
}

# ── Check prerequisites ──────────────────────────────────────────────────────
check_prerequisites() {
  print_header "Checking prerequisites"

  local missing=0

  check_command git     || missing=1
  check_command curl    || missing=1
  check_command node    || { print_warn "Node.js not detected (required for Claude Code)"; }

  # Claude Code
  if command -v claude &>/dev/null; then
    print_ok "Claude Code detected ($(claude --version 2>/dev/null | head -1))"
  else
    print_warn "Claude Code not detected"
    echo ""
    print_info "To install Claude Code:"
    print_info "  npm install -g @anthropic-ai/claude-code"
    echo ""
    if confirm "Do you want to install it now?"; then
      npm install -g @anthropic-ai/claude-code
      print_ok "Claude Code installed"
    else
      print_warn "Continuing without Claude Code — you'll need to install it manually"
    fi
  fi

  if [ "$missing" -eq 1 ]; then
    echo ""
    print_error "Some prerequisites are missing. Install them and re-run the script."
    exit 1
  fi
}

# ── Project detection ─────────────────────────────────────────────────────────
detect_project() {
  print_header "Project detection"

  # Find the right directory
  if [ -f ".git/config" ]; then
    PROJECT_DIR="$(pwd)"
    print_ok "Git repo detected in current directory"
  else
    # Check if we're in a parent directory with sub-repos
    local sub_repos=()
    for d in */; do
      if [ -d "${d}.git" ]; then
        sub_repos+=("$d")
      fi
    done

    if [ ${#sub_repos[@]} -gt 0 ]; then
      print_ok "Multi-repo directory detected — sub-repos found:"
      for r in "${sub_repos[@]}"; do
        print_info "  • ${r%/}"
      done
      PROJECT_DIR="$(pwd)"
      IS_MULTI_REPO=true
    else
      print_warn "No git repo found in current directory"
      ask "Path to your project" PROJECT_DIR "$(pwd)"
      cd "$PROJECT_DIR" || { print_error "Directory not found"; exit 1; }
    fi
  fi

  echo ""
  print_info "Project directory: $PROJECT_DIR"
}

# ── Platform selection ────────────────────────────────────────────────────────
choose_platform() {
  print_header "Git Platform"

  ask_choice "Which platform is your project on?" PLATFORM \
    "GitLab" \
    "GitHub"

  echo ""

  if [ "$PLATFORM" = "GitLab" ]; then
    configure_gitlab
  else
    configure_github
  fi
}

# ── GitLab configuration ─────────────────────────────────────────────────────
configure_gitlab() {
  print_step "GitLab Configuration"
  echo ""

  ask_choice "Which GitLab instance are you using?" GITLAB_TYPE \
    "GitLab.com (cloud)" \
    "GitLab self-hosted"

  if [ "$GITLAB_TYPE" = "GitLab.com (cloud)" ]; then
    GITLAB_URL="https://gitlab.com"
  else
    ask "URL of your GitLab instance" GITLAB_URL "https://gitlab.mycompany.com"
  fi

  echo ""
  select_or_create_token "GitLab"
  GITLAB_TOKEN="$TOKEN_VALUE"
  GITLAB_USERNAME="$TOKEN_USERNAME"
  echo ""

  # Detect namespace from git remote
  local detected_namespace=""
  local detected_project=""

  if [ -f ".git/config" ]; then
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$remote_url" ]; then
      # Extract namespace/project from URL
      detected_namespace=$(echo "$remote_url" | sed 's|.*[:/]\([^/]*\)/[^/]*\.git|\1|')
      detected_project=$(echo "$remote_url" | sed 's|.*[:/][^/]*/\([^/]*\)\.git|\1|')
    fi
  elif [ "$IS_MULTI_REPO" = "true" ]; then
    # Use the first sub-repo to detect
    for d in */; do
      if [ -d "${d}.git" ]; then
        local remote_url
        remote_url=$(git -C "${d%/}" remote get-url origin 2>/dev/null || echo "")
        if [ -n "$remote_url" ]; then
          detected_namespace=$(echo "$remote_url" | sed 's|.*[:/]\([^/]*\)/[^/]*\.git|\1|')
          break
        fi
      fi
    done
  fi

  ask "Your GitLab namespace (username or group)" GITLAB_NAMESPACE "${detected_namespace:-$GITLAB_USERNAME}"
  ask "GitLab project name" GITLAB_PROJECT "${detected_project:-my-project}"

  # Multi-repo mode?
  echo ""
  if [ "$IS_MULTI_REPO" = "true" ]; then
    WORKFLOW_MODE="multi-repo"
    print_ok "Multi-repo mode detected automatically"
  else
    ask_choice "Project structure?" WORKFLOW_MODE \
      "Single repo" \
      "Multi-repo (multiple repos in a GitLab group)"
  fi
}

# ── GitHub configuration ─────────────────────────────────────────────────────
configure_github() {
  print_step "GitHub Configuration"
  echo ""

  select_or_create_token "GitHub"
  GITHUB_TOKEN="$TOKEN_VALUE"
  GITHUB_USERNAME="$TOKEN_USERNAME"
  echo ""

  ask_choice "Visibility mode?" GITHUB_MODE \
    "Private repo only" \
    "Private repo + sync to public repo"

  echo ""

  # Detect repo from remote
  local detected_repo=""
  if [ -f ".git/config" ]; then
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    detected_repo=$(echo "$remote_url" | sed 's|.*github.com[:/][^/]*/\([^/]*\)\.git|\1|')
  fi

  ask "Name of your private GitHub repo" GITHUB_REPO "${detected_repo:-my-project}"

  if [ "$GITHUB_MODE" = "Private repo + sync to public repo" ]; then
    ask "Name of your public GitHub repo" GITHUB_PUBLIC_REPO "${GITHUB_REPO}-public"
    configure_github_sync_token
  fi

  WORKFLOW_MODE="single-repo"
}

configure_github_sync_token() {
  echo ""
  print_info "For syncing to the public repo, you need a second token"
  print_info "with write access only to the public repo."
  print_info "https://github.com/settings/tokens → Fine-grained → public repo only"
  echo ""
  ask_secret "Sync token for public repo" GITHUB_SYNC_TOKEN
}

# ── Setup GitLab MCP ─────────────────────────────────────────────────────────
setup_gitlab_mcp() {
  print_header "GitLab MCP Configuration"

  if ! command -v claude &>/dev/null; then
    print_warn "Claude Code not available — MCP configured manually in files"
    return
  fi

  print_step "Adding GitLab MCP server to Claude Code..."

  # Check if already configured
  if claude mcp list 2>/dev/null | grep -qi "gitlab"; then
    print_ok "GitLab MCP already configured"
  else
    claude mcp add --transport http GitLab "$GITLAB_URL/api/v4/mcp" 2>/dev/null && \
      print_ok "GitLab MCP added: $GITLAB_URL/api/v4/mcp" || \
      print_warn "Unable to add MCP automatically — do it manually:"
    print_info "  claude mcp add --transport http GitLab $GITLAB_URL/api/v4/mcp"
  fi

  echo ""
  print_info "On first Claude Code launch, your browser will open"
  print_info "for OAuth authorization. Approve the request."
}

# ── Create workflow files ─────────────────────────────────────────────────────
create_workflow_files() {
  print_header "Creating workflow files"

  mkdir -p .claude/commands
  print_ok ".claude/commands directory created"

  # ── CLAUDE.md ──
  cat > CLAUDE.md << CLAUDEMD
# Claude Code Instructions

## Project
- Platform: ${PLATFORM}
$([ "$PLATFORM" = "GitLab" ] && echo "- GitLab URL: ${GITLAB_URL}" || echo "")
$([ "$PLATFORM" = "GitLab" ] && echo "- Namespace: ${GITLAB_NAMESPACE}" || echo "")
$([ "$PLATFORM" = "GitLab" ] && echo "- Project: ${GITLAB_PROJECT}" || echo "")
$([ "$PLATFORM" = "GitHub" ] && echo "- Repo: ${GITHUB_USERNAME}/${GITHUB_REPO}" || echo "")
- Mode: ${WORKFLOW_MODE}

## Absolute rules
- Never commit directly to \`main\` or \`master\`
- Always create a branch per issue: \`feature/42-short-title\` or \`fix/42-title\`
- Never modify CLAUDE.md or files in \`.claude/\`
- Never include \`.env\` files or secrets in a commit

## Communication
- By default: all questions and updates as COMMENTS in the issue
- Never ask questions in the terminal unless \`--interactive\` is passed
- Always post the plan and wait for \`go\` before coding
- Post a summary + MR link as a comment when work is done

## Branches and commits
- Branch: \`feature/<number>-<short-title>\` or \`fix/<number>-<title>\`
- Commit: \`feat: description (closes #<number>)\`
- Always include \`Closes #<number>\` in the MR/PR description

## Issue processing order
- Analyze dependencies between issues before starting
- Foundations first (models, configs, structure)
- Then core features
- Then features that depend on previous ones
$([ "$WORKFLOW_MODE" = "multi-repo" ] && echo "
## Multi-repo
- Identify which sub-repo is concerned by each issue
- Use \`git -C <sub-repo> <command>\` to work in a sub-repo
- List sub-repos with \`ls\` if needed" || echo "")
CLAUDEMD
  print_ok "CLAUDE.md created"

  # ── .claude/config ──
  cat > .claude/config << CONFIG
PLATFORM=${PLATFORM}
$([ "$PLATFORM" = "GitLab" ] && cat << GITLABCONF
GITLAB_URL=${GITLAB_URL}
GITLAB_NAMESPACE=${GITLAB_NAMESPACE}
GITLAB_PROJECT=${GITLAB_PROJECT}
GITLABCONF
)
$([ "$PLATFORM" = "GitHub" ] && cat << GITHUBCONF
GITHUB_USERNAME=${GITHUB_USERNAME}
GITHUB_REPO=${GITHUB_REPO}
$([ -n "$GITHUB_PUBLIC_REPO" ] && echo "GITHUB_PUBLIC_REPO=${GITHUB_PUBLIC_REPO}" || echo "")
GITHUBCONF
)
WORKFLOW_MODE=${WORKFLOW_MODE}
CONFIG
  print_ok ".claude/config created"

  # ── /status command ──
  cat > .claude/commands/status.md << 'STATUSMD'
---
description: Shows the status of current issues and open MRs/PRs
allowed-tools: mcp__gitlab__*, Bash(git *), Bash(ls *), Read
---

# /status

Read the `.claude/config` file to determine the platform and project.

Then:
1. Via MCP, retrieve open issues, issues with associated MRs, and open MRs
2. For each sub-repo (if multi-repo), list active branches with `git -C <repo> branch`
3. Display a clear summary in the terminal with:
   - Open issues (number, title, concerned repo)
   - Issues in development with their MR
   - MRs awaiting review

Desired display format:
```
═══════════════════════════════════════════
  Project Status
═══════════════════════════════════════════

📋 OPEN ISSUES
  #12 · Issue title         [repo-backend]
  #15 · Issue title         [repo-frontend]

🔧 IN PROGRESS
  #8  · Issue title         → MR/PR open

✅ AWAITING REVIEW
  MR/PR · feat: description

Use /issues to plan · /issue <n> for a specific issue
═══════════════════════════════════════════
```
STATUSMD
  print_ok ".claude/commands/status.md created"

  # ── /issues command ──
  cat > .claude/commands/issues.md << 'ISSUESMD'
---
description: Read all issues, propose a prioritized order, wait for approval
allowed-tools: mcp__gitlab__*, mcp__github__*, Bash(git *), Bash(ls *), Bash(cat *), Bash(grep *), Bash(find *), Read, Edit, Write, MultiEdit
---

# /issues $ARGUMENTS

Read `.claude/config` to determine the platform, project, and mode.

## Step 1 — Retrieve all open issues
Via MCP, retrieve all open issues with their number, title, description, and labels.

## Step 2 — Analyze dependencies
For each issue, identify:
- Issues mentioned in its description (dependencies)
- The concerned repo(s) (infer from content)
- Its nature: foundation / feature / bugfix / improvement

## Step 3 — Propose a logical order
Sort by priority:
1. Foundations first (data models, configs, base structures)
2. Then independent features
3. Finally features that depend on previous ones

## Step 4 — Post the plan as a comment on the oldest issue
Comment format:

---
**📋 Processing plan — awaiting validation**

I've analyzed **X open issues**. Here's the order I propose:

| # | Issue | Repo | Reason |
|---|-------|------|--------|
| 1 | #12 · Title | repo-backend | Foundation for #15 |
| 2 | #8 · Title | repo-frontend | Independent |
| 3 | #15 · Title | repo-backend | Depends on #12 |

To start, reply to this comment:
- `go` → I'll begin in this order
- `go 8,12,15` → custom order
- `skip #8` → skip this issue
---

## Step 5 — Wait without writing anything in the terminal
After posting the comment, stop completely.

---

## If $ARGUMENTS contains "start"
Read the latest validation comment in the issue.
Process each issue in the validated order:
1. Re-read the description and comments
2. Identify the concerned repo
3. Create the branch: `git -C <repo> checkout -b feature/<n>-<short-title>`
4. Develop, commit, push
5. Open the MR/PR with `Closes #<n>` in the description
6. Post in the issue: "✅ Development complete. MR: <link>"
7. Next issue

---

## If $ARGUMENTS contains "--interactive"
You may ask your questions in the terminal instead of comments.
ISSUESMD
  print_ok ".claude/commands/issues.md created"

  # ── /issue command ──
  cat > .claude/commands/issue.md << 'ISSUEMD'
---
description: Work on a specific issue. Usage: /issue 42 or /issue 42 --interactive
allowed-tools: mcp__gitlab__*, mcp__github__*, Bash(git *), Bash(ls *), Bash(cat *), Bash(grep *), Bash(find *), Read, Edit, Write, MultiEdit
---

# /issue $ARGUMENTS

Read `.claude/config` to determine the platform and project.
Extract the issue number from: $ARGUMENTS

## Step 1 — Read the issue
Via MCP, retrieve the issue with its number, full description, and comments.

## Step 2 — Explore the codebase
Identify the concerned repo. Explore its structure. Don't write any code yet.

## Step 3 — Post the plan as a comment on the issue
Format:

---
**🔍 Analysis of issue #<n>**

**Concerned repo:** `<repo-name>`

**My understanding:** <summary>

**My plan:**
1. <step 1>
2. <step 2>
3. <step 3>

**Questions if any:** <or "No questions, ready to start">

Reply `go` for me to begin.
---

## Step 4 — Wait for go
Don't write anything in the terminal. Wait for a `go` comment in the issue.

## Step 5 — Develop
1. `git -C <repo> checkout -b feature/<n>-<short-title>`
2. Develop the solution
3. `git -C <repo> add -A && git -C <repo> commit -m "feat: <desc> (closes #<n>)"`
4. `git -C <repo> push origin feature/<n>-<short-title>`
5. Open the MR/PR
6. Post in the issue: "✅ MR opened: <link>"

---

## If $ARGUMENTS contains "--interactive"
Ask your questions in the terminal instead of GitLab/GitHub comments.
ISSUEMD
  print_ok ".claude/commands/issue.md created"
}

# ── Save secrets locally (optional) ──────────────────────────────────────────
save_secrets() {
  print_header "Secrets and environment variables"

  if confirm "Do you want to save tokens in a local .env file (never committed)?"; then
    cat > .env.claude << ENVFILE
# Claude Workflow Tokens — DO NOT COMMIT
$([ "$PLATFORM" = "GitLab" ] && echo "GITLAB_TOKEN=${GITLAB_TOKEN}" || echo "")
$([ "$PLATFORM" = "GitLab" ] && echo "GITLAB_URL=${GITLAB_URL}" || echo "")
$([ "$PLATFORM" = "GitHub" ] && echo "GITHUB_TOKEN=${GITHUB_TOKEN}" || echo "")
$([ -n "$GITHUB_SYNC_TOKEN" ] && echo "GITHUB_SYNC_TOKEN=${GITHUB_SYNC_TOKEN}" || echo "")
ENVFILE
    chmod 600 .env.claude
    print_ok ".env.claude created (permissions 600)"

    # Add to .gitignore
    if [ -f ".gitignore" ]; then
      if ! grep -q ".env.claude" .gitignore; then
        echo ".env.claude" >> .gitignore
        print_ok ".env.claude added to .gitignore"
      fi
    else
      echo ".env.claude" > .gitignore
      echo ".env" >> .gitignore
      echo "_private/" >> .gitignore
      print_ok ".gitignore created"
    fi
  fi

}

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary() {
  print_header "Installation complete ✓"

  echo -e "${GREEN}${BOLD}  Files created:${RESET}"
  echo -e "  • CLAUDE.md"
  echo -e "  • .claude/config"
  echo -e "  • .claude/commands/status.md"
  echo -e "  • .claude/commands/issues.md"
  echo -e "  • .claude/commands/issue.md"
  echo ""

  echo -e "${CYAN}${BOLD}  Available commands in Claude Code:${RESET}"
  echo -e "  ${BOLD}/status${RESET}              → issue and MR status"
  echo -e "  ${BOLD}/issues${RESET}              → analyze and plan all issues"
  echo -e "  ${BOLD}/issues start${RESET}        → start after plan validation"
  echo -e "  ${BOLD}/issue 42${RESET}            → work on issue #42"
  echo -e "  ${BOLD}/issue 42 --interactive${RESET} → with questions in the terminal"
  echo ""

  if [ "$PLATFORM" = "GitLab" ]; then
    echo -e "${CYAN}${BOLD}  Next step:${RESET}"
    echo -e "  Run ${BOLD}claude${RESET} in this directory"
    echo -e "  Type ${BOLD}/mcp${RESET} to verify the GitLab connection"
    echo -e "  If not connected: ${BOLD}claude mcp add --transport http GitLab ${GITLAB_URL}/api/v4/mcp${RESET}"
  fi

  if [ "$PLATFORM" = "GitHub" ]; then
    echo -e "${CYAN}${BOLD}  Next step:${RESET}"
    echo -e "  Run ${BOLD}claude${RESET} in this directory and try ${BOLD}/status${RESET}"
  fi

  echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
  clear
  echo ""
  echo -e "${BLUE}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════╗"
  echo "  ║       Claude Code Workflow Installation           ║"
  echo "  ║           GitHub · GitLab · Multi-repo            ║"
  echo "  ╚═══════════════════════════════════════════════════╝"
  echo -e "${RESET}"
  echo ""

  check_prerequisites
  detect_project
  choose_platform

  if [ "$PLATFORM" = "GitLab" ]; then
    setup_gitlab_mcp
  fi

  create_workflow_files
  save_secrets
  print_summary
}

main "$@"

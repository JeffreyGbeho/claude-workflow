#!/usr/bin/env bash
# =============================================================================
#  install-claude-workflow.sh
#  Automatically configures Claude Code workflow on GitHub or GitLab
# =============================================================================

set -e

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
  echo -e "${BOLD}  $prompt${RESET}"
  for i in "${!options[@]}"; do
    echo -e "    ${CYAN}$((i+1))${RESET}) ${options[$i]}"
  done
  while true; do
    echo -ne "  ${BOLD}Your choice [1-${#options[@]}]${RESET}: "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
      eval "$varname=\"${options[$((choice-1))]}\""
      break
    fi
    print_warn "Invalid choice, enter a number between 1 and ${#options[@]}"
  done
}

confirm() {
  local prompt="$1"
  echo -ne "${BOLD}  $prompt ${DIM}[y/n]${RESET}: "
  read -r answer
  [[ "$answer" =~ ^[yY] ]]
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    print_error "$1 is not installed"
    return 1
  fi
  print_ok "$1 detected"
  return 0
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
  print_info "You'll need a GitLab Personal Access Token."
  print_info "To create one: $GITLAB_URL/-/user_settings/personal_access_tokens"
  print_info "Required scopes: api, read_repository, write_repository"
  echo ""

  ask_secret "Your GitLab Personal Access Token" GITLAB_TOKEN

  # Verify token
  print_step "Verifying GitLab token..."
  local response
  response=$(curl -sf --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/user" 2>/dev/null || echo "ERROR")

  if [ "$response" = "ERROR" ]; then
    print_error "Invalid token or instance unreachable"
    if confirm "Do you want to try again?"; then
      configure_gitlab
      return
    else
      exit 1
    fi
  fi

  GITLAB_USERNAME=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
  print_ok "Logged in as: $GITLAB_USERNAME"
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

  ask_choice "Visibility mode?" GITHUB_MODE \
    "Private repo only" \
    "Private repo + sync to public repo"

  echo ""
  print_info "You'll need a GitHub Personal Access Token."
  print_info "To create one: https://github.com/settings/tokens"
  print_info "Type: Fine-grained token"
  print_info "Permissions: Contents (R&W), Issues (R&W), Pull Requests (R&W)"
  echo ""

  ask_secret "Your GitHub Personal Access Token" GITHUB_TOKEN

  # Verify token
  print_step "Verifying GitHub token..."
  local response
  response=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/user" 2>/dev/null || echo "ERROR")

  if [ "$response" = "ERROR" ]; then
    print_error "Invalid token"
    if confirm "Do you want to try again?"; then
      configure_github
      return
    else
      exit 1
    fi
  fi

  GITHUB_USERNAME=$(echo "$response" | grep -o '"login":"[^"]*"' | cut -d'"' -f4)
  print_ok "Logged in as: $GITHUB_USERNAME"
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

# ── Setup GitHub Actions (if GitHub) ──────────────────────────────────────────
setup_github_actions() {
  if [ "$PLATFORM" != "GitHub" ]; then
    return
  fi

  print_header "GitHub Actions Configuration"

  mkdir -p .github/workflows

  # Main Claude workflow
  cat > .github/workflows/claude.yml << CLAUDEYML
name: Claude Code Workflow

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      github.actor != 'claude[bot]' &&
      github.actor != 'github-actions[bot]' &&
      (
        (github.event_name == 'issue_comment' &&
         contains(github.event.comment.body, '@claude')) ||
        (github.event_name == 'pull_request_review_comment' &&
         contains(github.event.comment.body, '@claude')) ||
        (github.event_name == 'pull_request_review' &&
         contains(github.event.review.body, '@claude')) ||
        (github.event_name == 'issues' &&
         contains(github.event.issue.body, '@claude'))
      )

    runs-on: ubuntu-latest

    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: \${{ secrets.ANTHROPIC_API_KEY }}
          allowed_tools: |
            Bash(git *)
            Bash(ls *)
            Bash(cat *)
            Bash(grep *)
            Bash(find *)
            Read
            Edit
            Write
            MultiEdit
          claude_args: '--max-turns 20'
CLAUDEYML
  print_ok ".github/workflows/claude.yml created"

  # Sync workflow if public mode
  if [ "$GITHUB_MODE" = "Private repo + sync to public repo" ]; then
    cat > .github/workflows/sync-public.yml << SYNCYML
name: Sync to public repo

on:
  push:
    branches:
      - main

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Remove private files
        run: |
          git rm --cached CLAUDE.md 2>/dev/null || true
          git rm --cached .github/workflows/claude.yml 2>/dev/null || true
          git rm --cached -r _private/ 2>/dev/null || true

      - name: Push to public repo
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email 'github-actions[bot]@users.noreply.github.com'
          git remote add public https://x-access-token:\${{ secrets.PUBLIC_REPO_TOKEN }}@github.com/${GITHUB_USERNAME}/${GITHUB_PUBLIC_REPO}.git
          git push public main --force
SYNCYML
    print_ok ".github/workflows/sync-public.yml created"
  fi
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

  # Instructions for GitHub Secrets if GitHub
  if [ "$PLATFORM" = "GitHub" ]; then
    echo ""
    print_step "For GitHub Actions, you need to add these secrets to your repo:"
    print_info "  GitHub → Settings → Secrets and variables → Actions"
    echo ""
    print_info "  Secrets to add:"
    print_info "    ANTHROPIC_API_KEY  →  your Anthropic API key"
    if [ -n "$GITHUB_SYNC_TOKEN" ]; then
      print_info "    PUBLIC_REPO_TOKEN  →  $GITHUB_SYNC_TOKEN"
    fi
    echo ""
    if confirm "Do you want to open the GitHub secrets page in your browser?"; then
      local secrets_url="https://github.com/${GITHUB_USERNAME}/${GITHUB_REPO}/settings/secrets/actions"
      if command -v xdg-open &>/dev/null; then
        xdg-open "$secrets_url"
      elif command -v open &>/dev/null; then
        open "$secrets_url"
      else
        print_info "Open manually: $secrets_url"
      fi
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
  [ "$PLATFORM" = "GitHub" ] && echo -e "  • .github/workflows/claude.yml"
  [ -n "$GITHUB_PUBLIC_REPO" ] && echo -e "  • .github/workflows/sync-public.yml"
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
    echo -e "  Add ${BOLD}ANTHROPIC_API_KEY${RESET} to GitHub secrets"
    echo -e "  Run ${BOLD}/install-github-app${RESET} in Claude Code to activate the action"
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
  setup_github_actions
  save_secrets
  print_summary
}

main "$@"

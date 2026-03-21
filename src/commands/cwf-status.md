---
description: Shows the status of current issues, branches, and open MRs/PRs
allowed-tools: Bash(curl *), Bash(git *), Bash(ls *), Read
---

# /cwf-status

Read `.claude/config` to get PLATFORM, TOKEN, and project details.

## Fetch data using curl

**If PLATFORM=GitHub:**
- Open issues: `curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues?state=open&per_page=100"`
- Open PRs: `curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/pulls?state=open"`

**If PLATFORM=GitLab:**
- Open issues: `curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues?state=opened&per_page=100"`
- Open MRs: `curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/merge_requests?state=opened"`

## Also check local git state
- `git branch` to list local branches
- For each feature/fix branch, check if it has a corresponding open PR/MR
- `git log main..branch --oneline` to see how far ahead each branch is

## Display format
```
═══════════════════════════════════════════
  Project Status
═══════════════════════════════════════════

📋 OPEN ISSUES
  #12 · Issue title
  #15 · Issue title

🔧 IN PROGRESS (local branches)
  feature/8-auth  → #8 · Issue title  (3 commits ahead, PR open)
  feature/12-api  → #12 · Issue title (1 commit ahead, no PR)

✅ AWAITING REVIEW
  PR #23 · feat: auth system (from feature/8-auth)

Use /cwf-issues to plan · /cwf-issue <n> for a specific issue
═══════════════════════════════════════════
```

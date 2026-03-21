---
description: Analyze all issues, post individual plans, wait for per-issue approval
allowed-tools: Bash(curl *), Bash(git *), Bash(ls *), Read, Edit, Write
---

# /cwf-issues $ARGUMENTS

Read `.claude/config` to get PLATFORM, TOKEN, and project details.

## Step 1 — Retrieve all open issues

**If PLATFORM=GitHub:**
```
curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues?state=open&per_page=100"
```
**IMPORTANT:** GitHub's issues API also returns pull requests. Skip any item that has a `"pull_request"` key in the JSON — those are PRs, not issues.

**If PLATFORM=GitLab:**
```
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues?state=opened&per_page=100"
```

For each issue, extract: number, title, description, labels.

## Step 2 — Analyze dependencies and determine order
For each issue, identify:
- Issues mentioned in its description (dependencies like "depends on #12", "after #8", "blocked by #3")
- Its nature: foundation / feature / bugfix / improvement
- Check `git branch -a` to see if a branch already exists for this issue (pattern: `feature/<n>-*` or `fix/<n>-*`)
- If a branch exists, check its PR/MR status via curl

Sort by priority:
1. Foundations first (data models, configs, base structures)
2. Then independent features
3. Finally features that depend on previous ones
4. Skip issues that already have a merged PR/MR

For each issue, determine:
- **Base branch**: `main` if independent, or `feature/<dep>-*` if it depends on an unmerged issue
- **Status**: new / in progress / PR open / merged

## Step 3 — Explore the codebase
Explore the project structure and understand existing code to be able to write a relevant implementation plan for each issue.

## Step 4 — Post an individual comment on EACH issue (only if not already planned)

For each issue (in priority order):

**First, check if this issue already has a planning comment.** Fetch existing comments:

**If PLATFORM=GitHub:**
```
curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments"
```

**If PLATFORM=GitLab:**
```
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues/$ISSUE_NUMBER/notes"
```

Look for a comment that starts with `🔍 **Analyse de l'issue #` or `🔍 **Analysis of issue #`.

**If a planning comment already exists:**
- Do NOT post a new comment
- But DO verify that the dependencies listed in the existing plan are still correct (check if blocking PRs have been merged since, or if new dependencies have appeared)
- If dependencies have changed, post a SHORT update comment:
  ```
  📋 **Mise à jour des dépendances pour #<n>**

  <what changed: e.g. "#12 is now merged, this issue is unblocked" or "New dependency on #20 detected">

  Le plan reste valide. Répondez `go` pour lancer l'implémentation.
  ```
- If nothing changed, skip this issue entirely (no comment)
- Mark this issue as "already planned" in the terminal summary

**If no planning comment exists:** Post a new planning comment on that issue.

**If PLATFORM=GitHub:**
```
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"body": "..."}' \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments"
```

**If PLATFORM=GitLab:**
```
curl -s -X POST --header "PRIVATE-TOKEN: $TOKEN" --header "Content-Type: application/json" \
  -d '{"body": "..."}' \
  "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues/$ISSUE_NUMBER/notes"
```

### Comment format for issues WITHOUT unanswered questions:

```
🔍 **Analyse de l'issue #<n> — <title>**

**Priorité :** <order>/<total> — <type: Foundation / Feature / Bugfix / Improvement>
**Branche :** `feature/<n>-<short-title>` depuis `<base_branch>`
<if no dependencies>
**Dépendances :** Aucune
<if has dependencies>
**⛔ Bloqué par #<dep>** — cette issue doit être terminée et mergée avant de commencer celle-ci.

**Mon plan :**
1. <step 1>
2. <step 2>
3. <step 3>

**Questions :** Aucune, prêt à commencer.

Répondez `go` pour lancer l'implémentation.
```

### Comment format for issues WITH questions:

```
🔍 **Analyse de l'issue #<n> — <title>**

**Priorité :** <order>/<total> — <type>
**Branche :** `feature/<n>-<short-title>` depuis `<base_branch>`
<dependencies same as above>

**Mon plan :**
1. <step 1>
2. <step 2>
3. <step 3>

**❓ Questions :**
- <question 1>
- <question 2>

⚠️ Cette issue nécessite des clarifications avant implémentation. Répondez aux questions ci-dessus puis écrivez `go` pour valider.
```

Think like a senior developer joining the project: ask questions when the issue description is vague, ambiguous, or missing important details (tech choices, edge cases, expected behavior, design decisions). If the issue is clear enough, don't force questions.

## Step 5 — Output terminal summary

After posting all comments, output a summary table to stdout (this will be displayed in the user's terminal):

```
  #     Issue                          Status                Dépendances
  #12   Tic tac toe initialisation     ✅ Planifié (go?)      —
  #15   Scoreboard                     📋 Déjà planifié       #12 (non mergé)
  #18   Settings du game               🆕 Nouveau plan posté  #12 (non mergé)
  #20   Bug fix login                  ⛔ Bloqué par #15     needs clarification
```

Status legend:
- 🆕 Nouveau plan posté — planning comment just posted
- 📋 Déjà planifié — planning comment already existed, no changes needed
- 📋 Deps mises à jour — planning existed, dependency update posted
- ✅ Planifié (go?) — ready for `go`
- ⛔ Bloqué par #X — waiting for dependency

Then stop. Do not write code.

---

## If $ARGUMENTS contains "start"

This mode implements validated issues. For each issue (in priority order):

1. Read comments on the issue via curl
2. Check if there is a `go` reply — if not, skip this issue
3. Check if there were questions (❓) — if unanswered, skip this issue
4. Check dependencies — if the blocking issue's PR is not yet merged, skip this issue

For each validated and unblocked issue:
1. Determine the base branch (main or dependency branch)
2. `git fetch origin` and create branch from base
3. Develop the solution (read the plan from the comment you posted earlier)
4. Commit with descriptive messages: `git add -A && git commit -m "feat: <desc> (closes #<n>)"`
5. Rebase on base branch if needed, push
6. Open PR/MR via curl (set base to dependency branch if not merged, otherwise main)
7. Post completion comment on the issue: "✅ PR opened: <link>"
8. Move to next issue

Output a terminal summary at the end:
```
  #     Issue                          Result
  #12   Tic tac toe initialisation     ✅ PR #4 opened
  #15   Scoreboard                     ⏭️  Skipped (no go)
  #18   Settings du game               ⏭️  Skipped (blocked by #12)
```

---

## If $ARGUMENTS contains "--interactive"
You may ask your questions in the terminal instead of posting comments.

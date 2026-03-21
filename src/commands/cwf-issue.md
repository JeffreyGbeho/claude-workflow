---
description: Work on a specific issue. Usage: /cwf-issue 42 or /cwf-issue 42 --interactive
allowed-tools: Bash(curl *), Bash(git *), Bash(ls *), Read, Edit, Write
---

# /cwf-issue $ARGUMENTS

Read `.claude/config` to get PLATFORM, TOKEN, and project details.
Extract the issue number from: $ARGUMENTS

## Step 1 — Read the issue

**If PLATFORM=GitHub:**
```
curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues/$ISSUE_NUMBER"
```
For comments:
```
curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments"
```

**If PLATFORM=GitLab:**
```
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues/$ISSUE_NUMBER"
```
For comments:
```
curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$GITLAB_NAMESPACE%2F$GITLAB_PROJECT/issues/$ISSUE_NUMBER/notes"
```

## Step 2 — Analyze dependencies and determine base branch

1. Read the issue description for dependency mentions (e.g. "depends on #12", "after #8", "blocked by #3")
2. Check if a branch already exists: `git branch --list "feature/$ISSUE_NUMBER-*" "fix/$ISSUE_NUMBER-*"`
3. If the issue depends on another issue:
   - Check if the dependency branch exists locally: `git branch --list "feature/<dep>-*"`
   - Check if the dependency PR/MR is already merged
   - If merged → base on `main`
   - If not merged → base on the dependency branch
4. If no dependencies → base on `main`

## Step 3 — Explore the codebase
Explore the project structure. Understand existing code. Don't write any code yet.

## Step 4 — Post the plan as a comment on the issue

**First, check if this issue already has a planning comment.** Look in the existing comments for one starting with `🔍 **Analyse de l'issue #` or `🔍 **Analysis of issue #`.

**If a planning comment already exists:** Do NOT post a new one. Just verify dependencies are still correct. If dependencies changed, post a short update. Then output a terminal summary and stop.

**If no planning comment exists:** Post the plan using curl:

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

Comment format:

```
🔍 **Analyse de l'issue #<n> — <title>**

**Branche :** `feature/<n>-<short-title>` depuis `<base_branch>`
<if no dependencies>
**Dépendances :** Aucune
<if has dependencies>
**⛔ Bloqué par #<dep>** — cette issue doit être terminée et mergée avant de commencer celle-ci.

**Mon plan :**
1. <step 1>
2. <step 2>
3. <step 3>

**Questions :** Aucune, prêt à commencer. (or list questions with ❓)

Répondez `go` pour lancer l'implémentation.
```

Then output a terminal summary and stop. Do not write any code.
Do NOT proceed to implementation. Wait for a `go` comment.

---

## If $ARGUMENTS contains "start"

This mode skips planning — the plan has already been posted and validated with `go`.

1. Read `.claude/config` for PLATFORM, TOKEN, project details
2. Extract the issue number from $ARGUMENTS
3. Fetch the issue and ALL its comments via curl
4. Find the planning comment (starts with `🔍`) — read it to understand the plan
5. Read any subsequent comments (answers to questions, additional context from the user)
6. Use all this context to understand what to implement

**CRITICAL — Check dependencies before implementing:**
- If the planning comment mentions `⛔ Bloqué par #<dep>`, check if the blocking issue's PR/MR has been merged
- Check for open PRs via curl: look for a PR whose title or body contains `#<dep>` and whose state is `merged`
- If the blocking PR is NOT merged yet → do NOT implement. Post a comment:
  ```
  ⏸️ L'implémentation de #<n> est en attente : #<dep> n'est pas encore mergé.
  ```
  Then stop.
- If the blocking PR IS merged (or there are no dependencies) → proceed with implementation

Then implement:
1. `git fetch origin`
2. Determine base branch from the plan (main or dependency branch — if dependency PR is merged, use main)
3. Create branch: `git checkout -b feature/<n>-<short-title> <base>`
4. Develop the solution following the plan
5. `git add -A && git commit -m "feat: <desc> (closes #<n>)"`
6. `git rebase origin/<base>` if needed, then push
7. Open PR/MR via curl (base is always `main` if dependency is merged)
8. Post completion comment on the issue: "✅ PR ouvert: <link to PR/MR>"

Do NOT re-post a planning comment. Go straight to implementation.

---

## If $ARGUMENTS contains "respond"

This mode handles a new comment on an already-planned issue. Someone replied (probably answering questions or asking for plan changes).

1. Read `.claude/config` for PLATFORM, TOKEN, project details
2. Extract the issue number from $ARGUMENTS
3. Fetch the issue and ALL its comments via curl
4. Find the planning comment (starts with `🔍`) — understand the current plan
5. Read the NEW comments after the plan — understand what the user said

Then analyze:
- If the user answered questions from the plan → acknowledge their answers and update/confirm the plan
- If the user requested changes to the plan → adjust and post an updated plan
- If the user asked new questions → answer them based on your understanding of the codebase

Post a response comment on the issue. Format:

```
📝 **Mise à jour du plan pour #<n>**

<acknowledge what the user said>

<updated plan if needed, or confirmation that the plan is unchanged>

Répondez `go` pour lancer l'implémentation.
```

Do NOT implement anything. Only respond to comments and update the plan if needed.

---

## If $ARGUMENTS contains "--interactive"
Ask your questions in the terminal instead of posting comments.

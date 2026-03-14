# claude-workflow

Configure Claude Code on GitHub or GitLab with a single command.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/JeffreyGbeho/claude-workflow/main/bootstrap.sh | bash
```

Then reload your terminal, and in any project:

```bash
cwf
```

The script asks all the questions and configures everything automatically.

---

## What it does

- Detects whether you're on **GitHub** or **GitLab**
- Configures the **MCP server** so Claude Code talks to your platform
- Creates the **CLAUDE.md** file with instructions for Claude
- Creates the **`/issues`, `/issue`, `/status` commands** in Claude Code
- Handles **multi-repo** projects (GitLab group with multiple repos)
- Configures **sync to a public repo** if desired (GitHub)

---

## Available commands after installation

| Command | Description |
|---------|-------------|
| `/cwf-status` | Status of issues, branches, and MRs |
| `/cwf-issues` | Analyze all issues, suggest an order, wait for approval |
| `/cwf-issues start` | Start working after validation |
| `/cwf-issue 42` | Work on a specific issue |
| `/cwf-issue 42 --interactive` | Same but with questions in the terminal |

---

## Updates

Updates are checked automatically in the background.

To force an update:
```bash
cwf --update
```

To uninstall:
```bash
cwf --uninstall
```

---

## Repository structure

```
claude-workflow/
├── bootstrap.sh          ← installation script (one-liner)
├── VERSION               ← current version
├── src/
│   ├── install-claude-workflow.sh  ← project configuration script
│   └── update.sh                   ← update manager
└── README.md
```

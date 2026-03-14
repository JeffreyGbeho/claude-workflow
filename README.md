# claude-workflow

Configure Claude Code on GitHub or GitLab with a single command.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/JeffreyGbeho/claude-workflow/main/bootstrap.sh | bash
```

Then reload your terminal, and in any project:

```bash
cwf init
```

The script asks all the questions and configures everything automatically.

---

## Usage

| Command | Description |
|---------|-------------|
| `cwf init` | Configure claude-workflow in current project |
| `cwf status` | Show issues, branches, and MR status |
| `cwf issues` | Analyze all issues, propose a plan, wait for approval |
| `cwf issues start` | Start working after plan validation |
| `cwf issue 42` | Work on a specific issue |
| `cwf issue 42 --interactive` | Same but with questions in the terminal |

---

## What it does

- Detects whether you're on **GitHub** or **GitLab**
- Saves your token securely for future use
- Creates **CLAUDE.md** with workflow rules for Claude
- Creates **slash commands** (`cwf-status`, `cwf-issues`, `cwf-issue`)
- Configures **permissions** so Claude can work autonomously (but never touch main)
- Uses **curl + token** to communicate with GitHub/GitLab APIs

---

## Updates

Updates are checked automatically in the background.

```bash
cwf --update      # Force update
cwf --uninstall   # Uninstall
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

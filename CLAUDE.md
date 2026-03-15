# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-workflow is a CLI tool that configures Claude Code integration on GitHub or GitLab projects with a single command. It installs as `cwf` and sets up CLAUDE.md instructions and slash commands (`/cwf-status`, `/cwf-issues`, `/cwf-issue`) for issue-driven development workflows.

## Architecture

The project is four bash scripts forming an install pipeline:

1. **`bootstrap.sh`** — Entry point run via `curl | bash`. Downloads scripts to `~/.claude-workflow/`, creates a thin `cwf` wrapper in the user's PATH (just `exec bash cwf-main.sh "$@"`).

2. **`src/cwf-main.sh`** — CLI router. Contains ALL command routing logic (help, init, status, issues, issue, update, uninstall) plus background update check. This is the single source of truth for command handling — the `cwf` wrapper just delegates to this file.

3. **`src/install-claude-workflow.sh`** — Interactive project configurator. Detects git platform (GitHub/GitLab), collects tokens, verifies API access, then generates: `CLAUDE.md`, `.claude/config`, `.claude/settings.json`, `.claude/commands/{cwf-status,cwf-issues,cwf-issue}.md`.

4. **`src/update.sh`** — Version checker/updater. Compares local `VERSION` against remote. Supports `--silent` (background), `--notice`, `--update`, and `--uninstall` modes. Updates also download the latest `cwf-main.sh` and migrate old wrappers.

## Key Design Patterns

- **Platform abstraction**: `install-claude-workflow.sh` branches on `$PLATFORM` (GitHub/GitLab) with separate `configure_*` and `setup_*` functions, but generates unified command files that read `.claude/config` at runtime.
- **Multi-repo support**: Detects GitLab group structures (parent dir with multiple `.git` subdirs) and adjusts generated commands to use `git -C <sub-repo>`.
- **Generated files use `$VARIABLE` placeholders**: The CLAUDE.md template and command files embed project-specific values (namespace, repo name, URLs) at generation time via heredocs.
- **Thin wrapper pattern**: The `cwf` binary in PATH is a 2-line script that just `exec`s `cwf-main.sh`. All routing logic lives in `cwf-main.sh` which gets updated normally alongside other scripts. This avoids the need to rewrite the wrapper during updates.

## Development

No build step, linting, or tests exist. The scripts are pure bash (`#!/usr/bin/env bash`, `set -e`). To test locally:

```bash
# Run the installer interactively in a test project directory
bash src/install-claude-workflow.sh

# Test the bootstrap (downloads from GitHub, so needs the repo published first)
bash bootstrap.sh

# Test update check
bash src/update.sh
bash src/update.sh --silent
```

## Conventions

- All user-facing output uses ANSI color helpers: `print_ok`, `print_err`/`print_error`, `print_warn`, `print_info`, `print_step`, `print_header`
- Interactive prompts use `ask`, `ask_secret`, `ask_choice`, `confirm` helpers (defined in `install-claude-workflow.sh`)
- Version is tracked in the `VERSION` file (semver)

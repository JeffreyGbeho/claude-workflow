# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-workflow is a CLI tool that configures Claude Code integration on GitHub or GitLab projects with a single command. It installs as `cwf` and sets up MCP servers, CLAUDE.md instructions, and slash commands (`/status`, `/issues`, `/issue`) for issue-driven development workflows.

## Architecture

The project is three bash scripts forming an install pipeline:

1. **`bootstrap.sh`** — Entry point run via `curl | bash`. Downloads the other scripts to `~/.claude-workflow/`, creates the `cwf` wrapper in the user's PATH, and sets up background auto-updates.

2. **`src/install-claude-workflow.sh`** — Interactive project configurator. Detects git platform (GitHub/GitLab), collects tokens, verifies API access, then generates: `CLAUDE.md`, `.claude/config`, `.claude/commands/{status,issues,issue}.md`, and optionally `.github/workflows/claude.yml` + sync workflow.

3. **`src/update.sh`** — Version checker/updater. Compares local `VERSION` against remote. Supports `--silent` (background), `--force`, and `--uninstall` modes.

## Key Design Patterns

- **Platform abstraction**: `install-claude-workflow.sh` branches on `$PLATFORM` (GitHub/GitLab) with separate `configure_*` and `setup_*` functions, but generates unified command files that read `.claude/config` at runtime.
- **Multi-repo support**: Detects GitLab group structures (parent dir with multiple `.git` subdirs) and adjusts generated commands to use `git -C <sub-repo>`.
- **Generated files use `$VARIABLE` placeholders**: The CLAUDE.md template and command files embed project-specific values (namespace, repo name, URLs) at generation time via heredocs.
- **`YOUR_USERNAME/claude-workflow`** is a placeholder in `REPO=` variables across all three scripts — must be replaced with the actual GitHub username/org before publishing.

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
- Version is tracked in the `VERSION` file (semver, currently `1.0.0`)

#!/usr/bin/env bash
# =============================================================================
#  cwf-main.sh — CLI router for claude-workflow
#  This file contains ALL command routing logic.
#  The cwf wrapper just calls: exec bash this-file "$@"
# =============================================================================

INSTALL_DIR="$HOME/.claude-workflow"

# ── Update check (background) ───────────────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --silent &
fi

# ── Show update notice if available ──────────────────────────────────────────
if [ -f "$INSTALL_DIR/update.sh" ]; then
  bash "$INSTALL_DIR/update.sh" --notice
fi

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  echo "Usage: cwf <command>"
  echo ""
  echo "Commands:"
  echo "  init                    Configure claude-workflow in current project"
  echo "  status                  Show issues, branches, and MR status"
  echo "  issues                  Analyze all issues and propose a plan"
  echo "  issues start            Start working after plan validation"
  echo "  issue <n>               Work on a specific issue"
  echo "  issue <n> --interactive Work on issue with terminal questions"
  echo "  update                  Update cwf to latest version"
  echo "  uninstall               Uninstall cwf"
  echo ""
  echo "  cwf --help              Show this help"
}

# ── Command routing ──────────────────────────────────────────────────────────
case "$1" in
  init)
    exec bash "$INSTALL_DIR/install-claude-workflow.sh"
    ;;
  status)
    exec claude "/cwf-status"
    ;;
  issues)
    shift
    exec claude "/cwf-issues $*"
    ;;
  issue)
    shift
    exec claude "/cwf-issue $*"
    ;;
  update)
    exec bash "$INSTALL_DIR/update.sh" --update
    ;;
  uninstall)
    exec bash "$INSTALL_DIR/update.sh" --uninstall
    ;;
  ""|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo ""
    show_help
    exit 1
    ;;
esac

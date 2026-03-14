#!/usr/bin/env bash
# =============================================================================
#  update.sh — Checks and applies claude-workflow updates
# =============================================================================

REPO="JeffreyGbeho/claude-workflow"
INSTALL_DIR="$HOME/.claude-workflow"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
SILENT=false

[ "$1" = "--silent" ] && SILENT=true

print() { [ "$SILENT" = false ] && echo -e "$1"; }
print_ok()   { print "\033[32m  ✓ $1\033[0m"; }
print_info() { print "\033[2m  $1\033[0m"; }
print_step() { print "\033[36m\033[1m▶ $1\033[0m"; }

check_update() {
  # Fetch remote version
  local remote_version
  remote_version=$(curl -fsSL --max-time 5 "${RAW_BASE}/VERSION" 2>/dev/null || echo "")

  # If no connection or error, exit silently
  [ -z "$remote_version" ] && return 0

  local local_version
  local_version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "0.0.0")

  if [ "$remote_version" = "$local_version" ]; then
    print_info "Already up to date (v$local_version)"
    return 0
  fi

  # An update is available
  if [ "$SILENT" = true ]; then
    # In silent mode (background): download without asking
    apply_update "$remote_version"
  else
    echo ""
    echo -e "\033[33m\033[1m  Update available: v$local_version → v$remote_version\033[0m"
    echo -ne "  Update now? [y/n]: "
    read -r answer
    if [[ "$answer" =~ ^[yY] ]]; then
      apply_update "$remote_version"
    fi
  fi
}

apply_update() {
  local new_version="$1"

  [ "$SILENT" = false ] && print_step "Updating to v${new_version}..."

  # Download new files
  curl -fsSL "${RAW_BASE}/src/install-claude-workflow.sh" -o "$INSTALL_DIR/install-claude-workflow.sh" && \
    chmod +x "$INSTALL_DIR/install-claude-workflow.sh"

  curl -fsSL "${RAW_BASE}/src/update.sh" -o "$INSTALL_DIR/update.sh" && \
    chmod +x "$INSTALL_DIR/update.sh"

  echo "$new_version" > "$INSTALL_DIR/VERSION"

  [ "$SILENT" = false ] && print_ok "Updated to v${new_version}"
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
uninstall() {
  echo ""
  echo -e "\033[1m  Uninstalling claude-workflow...\033[0m"
  echo ""

  # Remove install directory
  rm -rf "$INSTALL_DIR"
  print_ok "$INSTALL_DIR directory removed"

  # Remove global command
  for dir in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
    if [ -f "$dir/cwf" ]; then
      rm -f "$dir/cwf"
      print_ok "Command removed from $dir"
    fi
  done

  echo ""
  echo -e "\033[2m  Files created in your projects (CLAUDE.md, .claude/) were not removed.\033[0m"
  echo ""
  print_ok "Uninstall complete"
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
  case "$1" in
    --uninstall) uninstall ;;
    --force)     SILENT=false; apply_update "$(curl -fsSL "${RAW_BASE}/VERSION" 2>/dev/null)" ;;
    *)           check_update ;;
  esac
}

main "$@"

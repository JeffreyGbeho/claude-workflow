#!/usr/bin/env bash
# =============================================================================
#  update.sh — Checks and applies claude-workflow updates
# =============================================================================

REPO="JeffreyGbeho/claude-workflow"
INSTALL_DIR="$HOME/.claude-workflow"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
UPDATE_FLAG="$INSTALL_DIR/.update-available"

# ── Source shared colors library (with inline fallback for old installs) ─────
if [ -f "$INSTALL_DIR/lib/colors.sh" ]; then
  source "$INSTALL_DIR/lib/colors.sh"
else
  print_ok()   { echo -e "\033[32m  ✓ $1\033[0m"; }
  print_info() { echo -e "\033[2m  $1\033[0m"; }
  print_step() { echo -e "\033[36m\033[1m▶ $1\033[0m"; }
  print_error(){ echo -e "\033[31m  ✗ $1\033[0m"; }
fi

# ── Silent check (background) — just write a flag if update available ────────
check_silent() {
  local remote_version
  remote_version=$(curl -fsSL --max-time 5 "${RAW_BASE}/VERSION" 2>/dev/null || echo "")
  [ -z "$remote_version" ] && return 0

  local local_version
  local_version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "0.0.0")

  if [ "$remote_version" != "$local_version" ]; then
    echo "$remote_version" > "$UPDATE_FLAG"
  else
    rm -f "$UPDATE_FLAG"
  fi
}

# ── Show update notice (called by wrapper) ───────────────────────────────────
show_notice() {
  if [ -f "$UPDATE_FLAG" ]; then
    local new_version
    new_version=$(cat "$UPDATE_FLAG")
    local local_version
    local_version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "0.0.0")
    echo -e "\033[33m  ⚡ Update available: v$local_version → v$new_version — run \033[1mcwf update\033[0;33m to update\033[0m"
    echo ""
  fi
}

# ── Apply update ─────────────────────────────────────────────────────────────
apply_update() {
  local remote_version
  remote_version=$(curl -fsSL --max-time 10 "${RAW_BASE}/VERSION" 2>/dev/null || echo "")

  if [ -z "$remote_version" ]; then
    print_error "Could not reach update server"
    return 1
  fi

  local local_version
  local_version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "0.0.0")

  if [ "$remote_version" = "$local_version" ]; then
    print_ok "Already up to date (v$local_version)"
    return 0
  fi

  print_step "Updating v${local_version} → v${remote_version}..."

  # Download core scripts
  curl -fsSL "${RAW_BASE}/src/install-claude-workflow.sh" -o "$INSTALL_DIR/install-claude-workflow.sh" && \
    chmod +x "$INSTALL_DIR/install-claude-workflow.sh"

  curl -fsSL "${RAW_BASE}/src/update.sh" -o "$INSTALL_DIR/update.sh" && \
    chmod +x "$INSTALL_DIR/update.sh"

  curl -fsSL "${RAW_BASE}/src/cwf-main.sh" -o "$INSTALL_DIR/cwf-main.sh" && \
    chmod +x "$INSTALL_DIR/cwf-main.sh"

  # Download shared libraries
  mkdir -p "$INSTALL_DIR/lib"

  curl -fsSL "${RAW_BASE}/src/lib/colors.sh" -o "$INSTALL_DIR/lib/colors.sh" && \
    chmod +x "$INSTALL_DIR/lib/colors.sh"

  curl -fsSL "${RAW_BASE}/src/lib/spinner.sh" -o "$INSTALL_DIR/lib/spinner.sh" && \
    chmod +x "$INSTALL_DIR/lib/spinner.sh"

  curl -fsSL "${RAW_BASE}/src/lib/api.sh" -o "$INSTALL_DIR/lib/api.sh" && \
    chmod +x "$INSTALL_DIR/lib/api.sh"

  # Download watch module
  curl -fsSL "${RAW_BASE}/src/watch.sh" -o "$INSTALL_DIR/watch.sh" && \
    chmod +x "$INSTALL_DIR/watch.sh"

  # Migrate old fat wrapper to thin launcher
  for dir in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
    if [ -f "$dir/cwf" ]; then
      echo '#!/usr/bin/env bash' > "$dir/cwf"
      echo 'exec bash "$HOME/.claude-workflow/cwf-main.sh" "$@"' >> "$dir/cwf"
      chmod +x "$dir/cwf"
      print_ok "Wrapper migrated to thin launcher"
      break
    fi
  done

  echo "$remote_version" > "$INSTALL_DIR/VERSION"
  rm -f "$UPDATE_FLAG"

  print_ok "Updated to v${remote_version}"
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
uninstall() {
  echo ""
  echo -e "\033[1m  Uninstalling claude-workflow...\033[0m"
  echo ""

  rm -rf "$INSTALL_DIR"
  print_ok "$INSTALL_DIR directory removed"

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
case "$1" in
  --silent)  check_silent ;;
  --notice)  show_notice ;;
  --update)  apply_update ;;
  --uninstall) uninstall ;;
  *)         apply_update ;;
esac

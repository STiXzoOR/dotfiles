#!/usr/bin/env bash
#
# Claude Code bootstrap — idempotent installer
# Called by: dotfiles install --claude
#
# Installs Claude Code native binary, registers marketplaces,
# installs plugins, copies rules/hooks, merges settings, and
# sets up QMD + Obsidian vault.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="$ROOT_DIR/claude"
CLAUDE_HOME="$HOME/.claude"
VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
CLAUDE_INSTALL_LOG="/tmp/dotfiles-claude-install.log"
FAILURES=()

source "$ROOT_DIR/scripts/echos.sh"
source "$ROOT_DIR/scripts/requirers.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

try_or_track() {
  local label="$1"
  shift
  if ! "$@"; then
    FAILURES+=("$label")
  fi
}

report_failures() {
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    warn "${#FAILURES[@]} items failed:"
    for f in "${FAILURES[@]}"; do
      echo "  - $f"
    done
    echo "  See $CLAUDE_INSTALL_LOG for details."
  fi
}

# ─── 1. Install Claude Code native binary ────────────────────────────────────

install_claude_binary() {
  if command -v claude &>/dev/null; then
    ok "Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
    return
  fi

  action "Installing Claude Code native binary"
  local tmpfile
  tmpfile=$(mktemp)
  if curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o "$tmpfile"; then
    if bash "$tmpfile"; then
      ok "Claude Code installed"
    else
      error "Claude Code installer failed"
      rm -f "$tmpfile"
      return 1
    fi
  else
    error "Failed to download Claude Code installer"
    rm -f "$tmpfile"
    return 1
  fi
  rm -f "$tmpfile"
}

# ─── 2. Register marketplaces ────────────────────────────────────────────────

register_marketplaces() {
  if [[ ! -f "$CLAUDE_DIR/marketplaces.list" ]]; then
    warn "No marketplaces.list found, skipping"
    return
  fi

  action "Registering Claude Code marketplaces"

  # Cache marketplace list once before the loop
  export CLAUDE_MARKETPLACES_CACHE
  CLAUDE_MARKETPLACES_CACHE="$(claude plugin marketplace list --json 2>/dev/null || echo "")"

  local total count=0
  total=$(grep -cvE '^[[:space:]]*(#|$)' "$CLAUDE_DIR/marketplaces.list" || echo 0)

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    running "[$count/$total] marketplace $line"
    try_or_track "marketplace: $line" require_claude_marketplace "$line"
  done <"$CLAUDE_DIR/marketplaces.list"
}

# ─── 3. Install plugins ──────────────────────────────────────────────────────

install_plugins() {
  if [[ ! -f "$CLAUDE_DIR/plugins.list" ]]; then
    warn "No plugins.list found, skipping"
    return
  fi

  action "Installing Claude Code plugins"

  # Cache installed plugins list once before the loop
  export CLAUDE_PLUGINS_CACHE
  CLAUDE_PLUGINS_CACHE="$(claude plugin list --json 2>/dev/null || echo "")"

  local total count=0 skipped=0
  total=$(grep -cvE '^[[:space:]]*(#|$)' "$CLAUDE_DIR/plugins.list" || echo 0)

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    local plugin_name="${line%%@*}"

    # Skip already-installed plugins silently
    if echo "$CLAUDE_PLUGINS_CACHE" | grep -q "$plugin_name"; then
      skipped=$((skipped + 1))
      continue
    fi

    running "[$count/$total] plugin $line"
    try_or_track "plugin: $line" require_claude_plugin "$line"
  done <"$CLAUDE_DIR/plugins.list"

  if [[ $skipped -gt 0 ]]; then
    ok "$skipped plugins already installed, skipped"
  fi
}

# ─── 4. Copy rules ───────────────────────────────────────────────────────────

copy_rules() {
  if [[ ! -d "$CLAUDE_DIR/rules" ]]; then
    warn "No rules directory found, skipping"
    return
  fi

  action "Copying Claude Code rules"
  mkdir -p "$CLAUDE_HOME/rules"
  for rule_file in "$CLAUDE_DIR"/rules/*.md; do
    [[ -f "$rule_file" ]] || continue
    local name
    name="$(basename "$rule_file")"
    cp "$rule_file" "$CLAUDE_HOME/rules/$name"
    ok "rules/$name"
  done
}

# ─── 5. Copy hooks ───────────────────────────────────────────────────────────

copy_hooks() {
  if [[ ! -d "$CLAUDE_DIR/hooks" ]]; then
    warn "No hooks directory found, skipping"
    return
  fi

  action "Copying Claude Code hooks"
  mkdir -p "$CLAUDE_HOME/hooks"
  for hook_file in "$CLAUDE_DIR"/hooks/*; do
    [[ -f "$hook_file" ]] || continue
    local name
    name="$(basename "$hook_file")"
    cp "$hook_file" "$CLAUDE_HOME/hooks/$name"
    chmod +x "$CLAUDE_HOME/hooks/$name"
    ok "hooks/$name"
  done
}

# ─── 6. Merge settings template ──────────────────────────────────────────────

merge_settings() {
  local template="$CLAUDE_DIR/settings.template.json"
  local target="$CLAUDE_HOME/settings.json"

  if [[ ! -f "$template" ]]; then
    warn "No settings.template.json found, skipping"
    return
  fi

  action "Merging Claude Code settings"

  # Expand $HOME in template
  local expanded
  expanded=$(sed "s|\\\$HOME|$HOME|g" "$template")

  if [[ ! -f "$target" ]]; then
    # Fresh install — write expanded template directly
    echo "$expanded" > "$target"
    ok "settings.json created from template"
  else
    # Existing install — deep merge: template provides defaults, existing overrides
    if ! command -v jq &>/dev/null; then
      warn "jq not available — skipping settings merge (install jq via brew)"
      return
    fi

    # Validate existing settings
    if ! jq empty "$target" 2>/dev/null; then
      warn "Invalid JSON in existing settings, backing up and replacing"
      cp "$target" "${target}.backup.$(date +%s)"
      echo "$expanded" > "$target"
      return
    fi

    local tmpfile
    tmpfile=$(mktemp)
    if echo "$expanded" | jq -s '.[0] * .[1]' - "$target" > "$tmpfile"; then
      mv "$tmpfile" "$target"
      ok "settings.json merged (existing values preserved)"
    else
      rm -f "$tmpfile"
      error "JSON merge failed"
      return 1
    fi
  fi
}

# ─── 7. Setup Obsidian vault ─────────────────────────────────────────────────

setup_vault() {
  action "Setting up Obsidian vault structure"

  local dirs=(
    "$VAULT_DIR"
    "$VAULT_DIR/Claude-Sessions"
    "$VAULT_DIR/Resources"
    "$VAULT_DIR/Inbox"
    "$VAULT_DIR/Projects"
  )

  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir"
      ok "created $dir"
    fi
  done
  ok "vault structure ready"
}

# ─── 8. Setup QMD ────────────────────────────────────────────────────────────

setup_qmd() {
  if ! command -v qmd &>/dev/null; then
    warn "QMD not installed — add 'qmd' to packages/npm.list and run 'dotfiles install --packages'"
    return
  fi

  ok "QMD already installed ($(qmd --version 2>/dev/null))"

  # Update QMD index (fast — only processes changed files)
  action "Updating QMD index"
  if timeout 60 qmd update 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD index updated"
  else
    warn "QMD update timed out or failed (run 'qmd update' manually)"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local start_time
  start_time=$(date +%s)

  bot "Claude Code Bootstrap\n"

  # Reset log
  : > "$CLAUDE_INSTALL_LOG"

  install_claude_binary
  register_marketplaces
  install_plugins
  copy_rules
  copy_hooks
  merge_settings
  setup_vault
  setup_qmd

  report_failures

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  echo ""
  bot "Claude Code bootstrap complete! (${elapsed}s)"
  echo ""
  echo "Next steps:"
  echo "  1. Run 'claude' to authenticate (if first install)"
  echo "  2. Restart your shell to pick up changes"
  echo ""
}

main "$@"

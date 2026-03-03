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
CLAUDE_INSTALL_LOG="$HOME/.cache/dotfiles/claude-install.log"
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
  trap 'rm -f "$tmpfile"' RETURN

  if curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o "$tmpfile"; then
    if bash "$tmpfile"; then
      ok "Claude Code installed"
    else
      error "Claude Code installer failed"
      return 1
    fi
  else
    error "Failed to download Claude Code installer"
    return 1
  fi
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
    if echo "$CLAUDE_PLUGINS_CACHE" | grep -Fq "$plugin_name"; then
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

# ─── 4. Copy rules and hooks ─────────────────────────────────────────────────

copy_claude_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local label="$3"
  local make_exec="${4:-false}"

  if [[ ! -d "$src_dir" ]]; then
    warn "No $label directory found, skipping"
    return
  fi

  action "Copying Claude Code $label"
  mkdir -p "$dest_dir"
  for file in "$src_dir"/*; do
    [[ -f "$file" ]] || continue
    local name
    name="$(basename "$file")"
    cp "$file" "$dest_dir/$name"
    [[ "$make_exec" == "true" ]] && chmod +x "$dest_dir/$name"
    ok "$label/$name"
  done
}

# ─── 5. Merge settings template ──────────────────────────────────────────────

merge_settings() {
  local template="$CLAUDE_DIR/settings.template.json"
  local target="$CLAUDE_HOME/settings.json"

  if [[ ! -f "$template" ]]; then
    warn "No settings.template.json found, skipping"
    return
  fi

  action "Merging Claude Code settings"

  # Expand $HOME in template using envsubst (safe against metacharacters)
  local expanded
  if command -v envsubst &>/dev/null; then
    # shellcheck disable=SC2016
    expanded=$(HOME="$HOME" envsubst '$HOME' < "$template")
  else
    # Fallback to sed with escaped replacement
    local escaped_home
    escaped_home=$(printf '%s\n' "$HOME" | sed 's/[&/\]/\\&/g')
    expanded=$(sed "s|\\\$HOME|$escaped_home|g" "$template")
  fi

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

# ─── 6. Setup Obsidian vault ─────────────────────────────────────────────────

setup_vault() {
  action "Setting up Obsidian vault structure"
  mkdir -p "$VAULT_DIR"/{Claude-Sessions,Resources,Inbox,Projects,Daily,Polaris}
  ok "vault directories ready"

  # Copy starter templates (only if they don't already exist)
  local templates_dir="$CLAUDE_DIR/vault-templates"
  if [[ -d "$templates_dir" ]]; then
    for template in "$templates_dir"/*; do
      [[ -f "$template" ]] || continue
      local name
      name="$(basename "$template")"
      local dest="$VAULT_DIR/Polaris/$name"
      if [[ ! -f "$dest" ]]; then
        cp "$template" "$dest"
        ok "vault template: Polaris/$name"
      fi
    done
  fi
}

# ─── 7. Setup QMD ────────────────────────────────────────────────────────────

setup_qmd() {
  if ! command -v qmd &>/dev/null; then
    warn "QMD not installed — add 'qmd' to packages/npm.list and run 'dotfiles install --packages'"
    return
  fi

  ok "QMD already installed ($(qmd --version 2>/dev/null))"

  # Register collections (idempotent — qmd ignores duplicates)
  action "Configuring QMD collections"

  if qmd collection add notes "$VAULT_DIR" 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD collection: notes -> $VAULT_DIR"
  else
    warn "QMD collection 'notes' setup failed"
  fi

  local sessions_dir="$HOME/.claude/projects"
  if [[ -d "$sessions_dir" ]]; then
    if qmd collection add sessions "$sessions_dir" 2>>"$CLAUDE_INSTALL_LOG"; then
      ok "QMD collection: sessions -> $sessions_dir"
    else
      warn "QMD collection 'sessions' setup failed"
    fi
  fi

  # Add context descriptions for collections
  qmd context add notes "Obsidian vault — notes, resources, projects, daily logs" 2>>"$CLAUDE_INSTALL_LOG" || true
  qmd context add sessions "Claude Code session transcripts and conversation history" 2>>"$CLAUDE_INSTALL_LOG" || true

  # Update index (fast — only processes changed files)
  action "Updating QMD index"
  if timeout 60 qmd update 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD index updated"
  else
    warn "QMD update timed out or failed (run 'qmd update' manually)"
  fi

  # Run embedding if models are available (first run downloads ~2GB)
  action "Building QMD embeddings (may take a moment on first run)"
  if timeout 120 qmd embed 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD embeddings ready"
  else
    warn "QMD embed timed out or failed (run 'qmd embed' manually)"
  fi

  # Register QMD MCP server with Claude Code (stored in ~/.claude.json)
  if command -v claude &>/dev/null; then
    action "Registering QMD MCP server"
    if claude mcp add --transport stdio qmd -- qmd mcp 2>>"$CLAUDE_INSTALL_LOG"; then
      ok "QMD MCP server registered"
    else
      warn "QMD MCP registration failed (run 'claude mcp add --transport stdio qmd -- qmd mcp' manually)"
    fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local start_time
  start_time=$(date +%s)

  # Ensure log directory exists (private to user)
  mkdir -p "$(dirname "$CLAUDE_INSTALL_LOG")"
  : > "$CLAUDE_INSTALL_LOG"

  install_claude_binary
  register_marketplaces
  install_plugins
  copy_claude_files "$CLAUDE_DIR/rules" "$CLAUDE_HOME/rules" "rules"
  copy_claude_files "$CLAUDE_DIR/hooks" "$CLAUDE_HOME/hooks" "hooks" "true"
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

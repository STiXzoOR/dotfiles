#!/usr/bin/env bash
#
# Codex bootstrap — idempotent installer
# Called by: dotfiles install --codex
#
# Codex itself is installed by mise (npm:@openai/codex in
# config/mise/config.toml). This seeds ~/.codex/config.toml, registers the
# marketplaces in codex/marketplaces.list, installs the plugins in
# codex/plugins.list and registers the MCP servers from claude/mcp.list.
#
# Runs as `bash scripts/install_codex.sh`, so it resolves its own repo root and
# puts the mise shims and ~/.local/bin on PATH itself.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CODEX_DIR="$ROOT_DIR/codex"
CLAUDE_DIR="$ROOT_DIR/claude"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_INSTALL_LOG="$HOME/.cache/dotfiles/codex-install.log"
# mcp.sh logs its uv install here too.
CLAUDE_INSTALL_LOG="$CODEX_INSTALL_LOG"
FAILURES=()

for _dir in "$HOME/.local/share/mise/shims" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$_dir:"*) ;;
    *) PATH="$_dir:$PATH" ;;
  esac
done
unset _dir
export PATH

source "$ROOT_DIR/scripts/echos.sh"
source "$ROOT_DIR/scripts/lib/lists.sh"
source "$ROOT_DIR/scripts/lib/mcp.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

report_failures() {
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    warn "${#FAILURES[@]} items failed:"
    for f in "${FAILURES[@]}"; do
      echo "  - $f"
    done
    echo "  See $CODEX_INSTALL_LOG for details."
  fi
}

# `codex plugin marketplace list` and `codex plugin list` need the network for
# the remote catalogue and may fail; a failed listing reads as "nothing
# installed", which only costs a redundant (idempotent) add.
CODEX_MARKETPLACES_CACHE=""
CODEX_PLUGINS_CACHE=""

# ─── 1. codex on PATH ────────────────────────────────────────────────────────

require_codex() {
  if command -v codex >/dev/null 2>&1; then
    ok "codex found ($(codex --version 2>/dev/null | head -1))"
    return 0
  fi
  error "codex not found on PATH: it is declared as 'npm:@openai/codex' in config/mise/config.toml; run 'dotfiles install --node' first"
  return 1
}

# ─── 2. Seed config.toml ─────────────────────────────────────────────────────

# Only when it does not exist. Nothing is replaced, so nothing is backed up.
seed_config() {
  local src="$CODEX_DIR/config.template.toml" dest="$CODEX_HOME/config.toml"

  if [[ -e "$dest" ]]; then
    ok "config.toml already present, left untouched"
    return 0
  fi
  if [[ ! -f "$src" ]]; then
    warn "No config.template.toml found, skipping"
    return 0
  fi
  mkdir -p "$CODEX_HOME" && cp "$src" "$dest" || return 1
  ok "config.toml seeded from the template"
}

# ─── 3. Marketplaces ─────────────────────────────────────────────────────────

register_marketplaces() {
  local line
  if [[ ! -f "$CODEX_DIR/marketplaces.list" && ! -f "$CODEX_DIR/marketplaces.local.list" ]]; then
    warn "No marketplaces.list found, skipping"
    return 0
  fi

  action "Registering Codex marketplaces"
  CODEX_MARKETPLACES_CACHE="$(codex plugin marketplace list --json 2>>"$CODEX_INSTALL_LOG" || true)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue
    if printf '%s' "$CODEX_MARKETPLACES_CACHE" | grep -Fq "$line"; then
      ok "marketplace $line already added"
    elif codex plugin marketplace add "$line" >>"$CODEX_INSTALL_LOG" 2>&1; then
      ok "marketplace $line"
    else
      warn "failed to add marketplace $line"
      FAILURES+=("marketplace: $line")
    fi
  done < <(read_list "$CODEX_DIR" marketplaces)
}

# ─── 4. Plugins ──────────────────────────────────────────────────────────────

# `codex plugin add` has no already-installed guard, so ask first.
plugin_installed() { # plugin_installed <plugin@marketplace>
  printf '%s' "$CODEX_PLUGINS_CACHE" | grep -Fq "\"$1\""
}

install_plugins() {
  local line
  if [[ ! -f "$CODEX_DIR/plugins.list" && ! -f "$CODEX_DIR/plugins.local.list" ]]; then
    warn "No plugins.list found, skipping"
    return 0
  fi

  action "Installing Codex plugins"
  CODEX_PLUGINS_CACHE="$(codex plugin list --json 2>>"$CODEX_INSTALL_LOG" || true)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue
    if plugin_installed "$line"; then
      ok "plugin $line already installed"
      continue
    fi
    if codex plugin add "$line" >>"$CODEX_INSTALL_LOG" 2>&1; then
      ok "plugin $line"
    elif [[ "$line" == *@openai-curated ]] &&
      codex plugin add "${line}-remote" >>"$CODEX_INSTALL_LOG" 2>&1; then
      # A fresh machine has not synced the curated marketplace yet.
      ok "plugin ${line}-remote (curated marketplace not synced yet)"
    else
      warn "failed to add plugin $line"
      FAILURES+=("plugin: $line")
    fi
  done < <(read_list "$CODEX_DIR" plugins)
}

# ─── 5. MCP servers ──────────────────────────────────────────────────────────

# The same servers as Claude: claude/mcp.list is the one list. `codex mcp add`
# takes the same `-- command args` tail as `claude mcp add`.
register_mcp_servers() {
  local line rc name
  local -a cmd

  action "Registering Codex MCP servers"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue
    if ! parse_mcp_entry "$line"; then
      warn "mcp.list: ignoring '$line' (expected: name command [args...])"
      continue
    fi
    name="$MCP_NAME"
    cmd=("${MCP_CMD[@]}")

    if codex mcp get "$name" >>"$CODEX_INSTALL_LOG" 2>&1; then
      ok "MCP server $name already registered"
      continue
    fi

    prepare_mcp_server "$name"
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      continue
    elif [[ "$rc" -ne 0 ]]; then
      FAILURES+=("mcp server: $name")
      continue
    fi

    if codex mcp add "$name" -- "${cmd[@]}" >>"$CODEX_INSTALL_LOG" 2>&1; then
      ok "MCP server $name registered"
    else
      warn "failed to register MCP server $name"
      FAILURES+=("mcp server: $name")
    fi
  done < <(read_list "$CLAUDE_DIR" mcp)
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local start_time end_time elapsed
  start_time=$(date +%s)

  mkdir -p "$(dirname "$CODEX_INSTALL_LOG")"
  : > "$CODEX_INSTALL_LOG"

  # Nothing below can work without the binary; say so once and stop.
  if ! require_codex; then
    echo ""
    error "Codex bootstrap aborted: codex is not installed"
    echo ""
    return 1
  fi

  seed_config || FAILURES+=("config.toml")
  register_marketplaces
  install_plugins
  register_mcp_servers

  report_failures

  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  echo ""
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    error "Codex bootstrap finished with ${#FAILURES[@]} failures (${elapsed}s)"
    echo ""
    return 1
  fi

  bot "Codex bootstrap complete! (${elapsed}s)"
  echo ""
  echo "Next steps:"
  echo "  1. Run 'codex' to sign in (if first install)"
  echo "  2. Plugin hooks (warp, cc-safety-net) are not trusted on install:"
  echo "     open codex, run /hooks and press t on each hook to trust it"
  echo ""
}

# `source scripts/install_codex.sh --lib` loads the functions without running
# the bootstrap, so tests can exercise them directly.
if [[ "${1:-}" == "--lib" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

main "$@"

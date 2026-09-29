#!/usr/bin/env bash
#
# mcp.sh - Shared helpers for the MCP server list (claude/mcp.list) used by
# both scripts/install_claude.sh and scripts/install_codex.sh.
#
# Sourceable with no side effects. Expects echos.sh (ok/warn/action) and
# lists.sh (read_list) to be sourced already. bash 3.2 safe.

BLENDER_MCP_VERSION="1.0.3"
BLENDER_MCP_SOURCE="git+https://projects.blender.org/lab/blender_mcp.git@v${BLENDER_MCP_VERSION}#subdirectory=mcp"

# Split one mcp.list line into MCP_NAME and the MCP_CMD array, expanding a
# literal $HOME in each word. Words are split first and expanded second, so a
# HOME containing a space still yields one argument. Returns 1 for a line that
# lacks a command.
parse_mcp_entry() { # parse_mcp_entry <line>
  local word
  MCP_NAME=""
  MCP_CMD=()
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  [[ $# -ge 2 ]] || return 1
  MCP_NAME="$1"
  shift
  for word in "$@"; do
    MCP_CMD+=("${word//\$HOME/$HOME}")
  done
}

# Some servers need their binary installed before they can be registered.
# Returns 0 when the server is ready to register, 1 when it must not be
# (registering a path that does not exist leaves a dead server), 2 on a real
# failure. Servers with nothing to prepare succeed.
prepare_mcp_server() { # prepare_mcp_server <name>
  case "$1" in
    blender) install_blender_mcp ;;
    *) return 0 ;;
  esac
}

# Blender Foundation's official MCP server. PyPI's `blender-mcp` is an
# unrelated project, so this installs from the tagged git source only.
install_blender_mcp() {
  local bin="$HOME/.local/bin/blender-mcp"

  if [[ ! -x "$bin" ]]; then
    if ! command -v uv >/dev/null 2>&1; then
      warn "uv not found: skipping the blender MCP server (mise installs uv; re-run after 'dotfiles install --node')"
      return 1
    fi
    action "Installing the Blender MCP server ($BLENDER_MCP_VERSION)"
    if ! uv tool install --force "$BLENDER_MCP_SOURCE" >>"${CLAUDE_INSTALL_LOG:-/dev/null}" 2>&1; then
      error "uv tool install of the Blender MCP server failed"
      return 2
    fi
    if [[ ! -x "$bin" ]]; then
      error "the Blender MCP install finished but $bin is missing"
      return 2
    fi
    ok "blender-mcp installed to ~/.local/bin"
  fi

  warn "Blender add-on: install mcp-${BLENDER_MCP_VERSION}.zip (from the v${BLENDER_MCP_VERSION} release at projects.blender.org/lab/blender_mcp, Blender 5.1+) from inside Blender: Preferences > Extensions > Install from Disk"
  return 0
}

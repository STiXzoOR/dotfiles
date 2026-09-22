#!/bin/bash
#
# Run the sync-claude-sessions plugin's `claude-sessions sync`, which exports
# session transcripts into $VAULT_DIR/Claude-Sessions. That directory is what
# setup_qmd registers as the QMD "sessions" collection, so this hook is what
# keeps recall working.
#
# Why this file exists at all: the settings template used to invoke
#   $HOME/.claude/skills/recall/.venv/bin/python3
#   $HOME/.claude/skills/sync-claude-sessions/scripts/claude-sessions sync
# and `claude plugin install` creates neither path. Plugins land under
# ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/. Those two
# directories existed on one machine only because they had been placed there by
# hand, so a fresh bootstrap wired a hook to an interpreter that did not exist.
#
# Resolution happens here, at run time, rather than being baked into the
# settings file at install time: the cache path carries the plugin version, so
# any path written once goes stale on the very next plugin update.
#
# This runs on UserPromptSubmit, whose stdout is injected into the model's
# context. It must therefore print nothing on success and never fail the turn:
# everything goes to a log and the exit status is always 0.
#
# CLAUDE_HOOK_DRY_RUN=1 reports what it resolved and exits. `dotfiles claude
# verify` uses it.

LOG="$HOME/.claude/hooks/sync-sessions.log"

# Newest-first so a plugin upgrade is picked up without any other change.
find_plugin_script() {
  local candidate

  if [ -n "${CLAUDE_SESSIONS_BIN:-}" ] && [ -f "$CLAUDE_SESSIONS_BIN" ]; then
    printf '%s' "$CLAUDE_SESSIONS_BIN"
    return 0
  fi

  local newest=""
  for candidate in "$HOME"/.claude/plugins/cache/*/sync-claude-sessions*/*/scripts/claude-sessions; do
    [ -f "$candidate" ] || continue
    if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then newest="$candidate"; fi
  done
  if [ -n "$newest" ]; then
    printf '%s' "$newest"
    return 0
  fi

  # Hand-placed skills directory, still in use on older machines.
  candidate="$HOME/.claude/skills/sync-claude-sessions/scripts/claude-sessions"
  [ -f "$candidate" ] && printf '%s' "$candidate" && return 0

  # Last resort: ask the CLI. Costs a process, so it only runs when the cheap
  # lookups have already missed.
  if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    candidate=$(claude plugin list --json 2>/dev/null |
      jq -r '.[]? | select(.name // "" | test("sync-claude-sessions")) | .installPath // empty' |
      head -1)
    if [ -n "$candidate" ] && [ -f "$candidate/scripts/claude-sessions" ]; then
      printf '%s' "$candidate/scripts/claude-sessions"
      return 0
    fi
  fi

  return 1
}

# The plugin script carries a `#!/usr/bin/env python3` shebang, so prefer
# executing it directly; fall back to an interpreter that exists on a stock
# macOS, since a hook does not inherit an interactive shell's PATH.
find_python() {
  local candidate
  for candidate in "$HOME/.claude/skills/recall/.venv/bin/python3" /usr/bin/python3 /opt/homebrew/bin/python3; do
    [ -x "$candidate" ] && printf '%s' "$candidate" && return 0
  done
  command -v python3 2>/dev/null
}

script=$(find_plugin_script)

if [ "${CLAUDE_HOOK_DRY_RUN:-}" = "1" ]; then
  echo "sync-sessions: script=${script:-none} python=$(find_python 2>/dev/null || echo none)"
  exit 0
fi

[ -n "$script" ] || exit 0

mkdir -p "$(dirname "$LOG")" 2>/dev/null
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') sync via $script ==="
  if [ -x "$script" ]; then
    "$script" sync
  else
    python_bin=$(find_python)
    [ -n "$python_bin" ] && "$python_bin" "$script" sync
  fi
  echo "sync exit: $?"
} >> "$LOG" 2>&1

exit 0

#!/bin/bash
# Auto-index QMD sessions into the vault.
#
# Wired to SessionEnd, not Stop: Stop fires at the end of every assistant turn,
# SessionEnd once per session, and this work is far too expensive to pay for
# per turn. SessionEnd hooks also share a 1.5s budget, so the first invocation
# re-execs itself detached and returns immediately. Running detached means it
# no longer inherits the hook system's timeout kill, so it enforces its own
# bounds instead:
#   - an atomic single-instance lock, so concurrent session-ends cannot race
#     qmd's sqlite index
#   - a hard timeout on each expensive step, so nothing can hang forever
#   - log rotation, so the log file cannot grow without limit
#
# Hooks run non-interactively. They never source .zshrc, so there is no
# GNU-first PATH and no toolchain on PATH. The tool-resolution block below
# re-establishes one; everything outside it is resolved by absolute path
# rather than trusted to `command -v`.
#
# CLAUDE_HOOK_DRY_RUN=1 reports which dependencies it would use and exits
# without doing any work -- and without writing anything, which is what lets
# `dotfiles claude verify` call itself read-only.

LOCK="$HOME/.claude/hooks/.index-sessions.lock"
LOG="$HOME/.claude/hooks/index-sessions.log"
VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
PYTHON="$HOME/.claude/skills/recall/.venv/bin/python3"
EXTRACT_SCRIPT="$HOME/.claude/skills/recall/scripts/extract-sessions.py"

# GNU timeout. Not in a default macOS PATH at all, and coreutils installs it
# under two different names depending on whether the gnubin dir is present.
TIMEOUT_BIN=""
for candidate in /opt/homebrew/bin/gtimeout /opt/homebrew/opt/coreutils/libexec/gnubin/timeout; do
  [ -x "$candidate" ] && TIMEOUT_BIN="$candidate" && break
done

run_bounded() { # run_bounded <seconds> <cmd...>
  local secs="$1"
  shift
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$secs" "$@"; else "$@"; fi
}

# --- tool resolution --------------------------------------------------------
# Re-establish the Node toolchain for a shell that inherited a bare PATH.
# Kept between these markers, and free of anything defined elsewhere in this
# file, so that tests/mise.sh can source exactly this block and check what it
# puts on PATH.
#
# Shims first: a fixed path, one prepend, no subprocess, and each shim asks
# mise at exec time which version the directory wants -- so a hook, a GUI app
# and a login shell all resolve the same way. `mise env` covers the machine
# where mise is installed but `mise install` has not built the shims yet.
#
# `fnm env` is last, and is the pre-migration path. Unlike the other two it is
# not a read: it materialises a per-PID multishell directory under
# ~/.local/runtime, which this repo ships a pruner for. `dotfiles claude
# verify` runs this hook with CLAUDE_HOOK_DRY_RUN=1 and promises to touch
# nothing, so that branch is skipped there.
if [ -d "$HOME/.local/share/mise/shims" ]; then
  PATH="$HOME/.local/share/mise/shims:$PATH"
  export PATH
elif command -v mise > /dev/null 2>&1; then
  eval "$(mise env -s bash 2>/dev/null)"
elif [ "${CLAUDE_HOOK_DRY_RUN:-}" != "1" ] && command -v fnm > /dev/null 2>&1; then
  eval "$(fnm env 2>/dev/null)"
fi
# --- end tool resolution ----------------------------------------------------

# qmd. npm installed it into whichever fnm multishell was active at the time --
# a per-PID path no hook ever inherits -- and mise installs it into the shim
# directory the block above just put on PATH. The explicit candidates are
# checked first so that resolution does not depend on PATH having been fixed.
QMD_BIN=""
QMD_SOURCE=""
resolve_qmd() {
  local candidate
  QMD_BIN=""
  for candidate in "$HOME/.local/bin/qmd" "$HOME/.local/share/mise/shims/qmd"; do
    if [ -x "$candidate" ]; then
      QMD_BIN="$candidate"
      QMD_SOURCE="$candidate"
      return 0
    fi
  done

  QMD_BIN="$(command -v qmd 2>/dev/null)"
  if [ -n "$QMD_BIN" ]; then
    QMD_SOURCE="PATH ($QMD_BIN)"
    return 0
  fi
  QMD_SOURCE="none"
  return 1
}

if [ "${CLAUDE_HOOK_DRY_RUN:-}" = "1" ]; then
  resolve_qmd
  echo "index-sessions: python=${PYTHON} exists=$([ -x "$PYTHON" ] && echo yes || echo no)"
  echo "index-sessions: extract=${EXTRACT_SCRIPT} exists=$([ -f "$EXTRACT_SCRIPT" ] && echo yes || echo no)"
  echo "index-sessions: timeout=${TIMEOUT_BIN:-none} qmd=${QMD_BIN:-${QMD_SOURCE:-none}}"
  exit 0
fi

# Detach and return, so the 1.5s SessionEnd budget is never at risk.
if [ "${INDEX_SESSIONS_DETACHED:-}" != "1" ] && [ -r "$0" ]; then
  INDEX_SESSIONS_DETACHED=1 "${BASH:-/bin/bash}" "$0" >/dev/null 2>&1 &
  disown 2>/dev/null
  exit 0
fi

# Single-instance lock. macOS has no flock(1); mkdir is atomic, so it works as
# a portable mutex. Reclaim the lock if a previous run died holding it.
mkdir -p "$(dirname "$LOCK")" 2>/dev/null
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0 # another run is in flight; skip this one
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

# Rotate past 5MB in place. wc -c sidesteps the BSD/GNU stat flag split (to GNU
# stat, -f means *filesystem*, so a BSD-first probe never reaches its fallback).
# Rotating in place rather than to a .1 file means no orphan can survive; an
# earlier version of this hook left an 11MB one behind, so clean that up too.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
  tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi
rm -f "$LOG.1" 2>/dev/null

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') SessionEnd index run (pid $$) ==="

  # Keep the 3-day window: this runs once per session end rather than on every
  # turn, so a wider window is the catch-up net for anything missed.
  if [ -x "$PYTHON" ] && [ -f "$EXTRACT_SCRIPT" ]; then
    run_bounded 120 "$PYTHON" "$EXTRACT_SCRIPT" --days 3 --output "$VAULT_DIR/Claude-Sessions"
    echo "extract exit: $?"
  else
    echo "extract skipped: $PYTHON or $EXTRACT_SCRIPT missing"
  fi

  if resolve_qmd; then
    run_bounded 180 "$QMD_BIN" update
    echo "qmd update exit: $?"
  else
    echo "qmd update skipped: no qmd on any known path"
  fi

  echo "=== done ==="
} >> "$LOG" 2>&1

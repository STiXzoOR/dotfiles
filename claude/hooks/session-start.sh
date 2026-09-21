#!/bin/bash
#
# SessionStart hook: surface the vault's "top of mind" note as session context.
#
# Output on stdout is added to the session's context, so this stays short and
# silent when there is nothing useful to say -- an empty or template-only note
# is worse than no note, because it burns context to say nothing.

set -uo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
NOTE="$VAULT_DIR/top-of-mind.md"

[[ -f "$NOTE" ]] || exit 0

# Skip the unedited template: every checkbox still empty.
if ! grep -qE '^\s*-\s*\[[ x]\]\s*\S' "$NOTE"; then
  exit 0
fi
if ! grep -vqE '^\s*(#|>|\s*-\s*\[[ x]\]\s*\.\.\.\s*$|$)' "$NOTE"; then
  exit 0
fi

echo "## Top of mind (from $NOTE)"
echo
# Cap it: this is context every single session pays for.
head -c 2000 "$NOTE"

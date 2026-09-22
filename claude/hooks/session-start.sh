#!/bin/bash
#
# SessionStart hook: surface the vault's "top of mind" note as session context.
#
# Everything this script writes to stdout is injected verbatim into the model's
# context for the whole session, at the same trust level as CLAUDE.md. The note
# is user-authored in the user's own vault, which is what makes that acceptable;
# never widen this to a file the user does not control.
#
# It also costs tokens on every single session, so it stays short and stays
# silent when there is nothing useful to say -- an empty or template-only note
# is worse than no note, because it burns context to say nothing.
#
# CLAUDE_HOOK_DRY_RUN=1 reports what it would read and exits. `dotfiles claude
# verify` uses it.

set -uo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"

# setup_vault copies claude/vault-templates/* into $VAULT_DIR/Polaris, so the
# note lives there, not at the vault root.
NOTE="$VAULT_DIR/Polaris/top-of-mind.md"

if [ "${CLAUDE_HOOK_DRY_RUN:-}" = "1" ]; then
  echo "session-start: note=$NOTE exists=$([ -f "$NOTE" ] && echo yes || echo no)"
  exit 0
fi

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

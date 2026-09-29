#!/usr/bin/env bash
#
# Where the Obsidian vault lives, and whether iCloud has finished downloading it.
#
# ~/Vault stays the path everything uses (QMD, the hooks, the skills). On a Mac
# that shares the vault through iCloud Drive it is a symlink to the vault folder
# in iCloud Drive; `dotfiles vault migrate` makes it one, `install --claude`
# creates it on a second Mac. Sourced by scripts/install_claude.sh and
# bin/dotfiles-vault; no side effects on load. BSD-safe tools only.

# The vault folder inside iCloud Drive. DOTFILES_VAULT_ICLOUD overrides it (the
# tests use a sandbox stand-in for iCloud Drive).
dotfiles_vault_icloud() {
  printf '%s' "${DOTFILES_VAULT_ICLOUD:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Vault}"
}

# The .icloud placeholder files still under <dir> (a symlinked <dir> is
# followed). Prints nothing when the folder is fully downloaded.
dotfiles_vault_placeholders() {
  [ -d "$1" ] && find "$1/" -name '*.icloud' 2>/dev/null
  return 0
}

# Is <dir> (resolving symlinks) inside the iCloud vault folder?
dotfiles_vault_in_icloud() {
  local real icloud
  real=$(cd -P "$1" 2>/dev/null && pwd) || return 1
  icloud=$(cd -P "$(dotfiles_vault_icloud)" 2>/dev/null && pwd) || return 1
  case "$real/" in "$icloud"/*) return 0 ;; esac
  return 1
}

# Ask iCloud to download <dir> and wait (DOTFILES_VAULT_DL_WAIT seconds,
# default 60) until no placeholder remains. Returns 1, listing the first few
# placeholders on stderr, when some remain.
dotfiles_vault_materialise() {
  local dir="$1" wait="${DOTFILES_VAULT_DL_WAIT:-60}" waited=0 left real
  real=$(cd -P "$dir" 2>/dev/null && pwd) || real="$dir"
  command -v brctl >/dev/null 2>&1 && brctl download "$real" >/dev/null 2>&1
  while :; do
    left=$(dotfiles_vault_placeholders "$dir")
    [ -z "$left" ] && return 0
    [ "$waited" -ge "$wait" ] && break
    sleep 2
    waited=$((waited + 2))
  done
  printf '%s\n' "$left" | head -n 5 >&2
  return 1
}

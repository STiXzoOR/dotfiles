#!/usr/bin/env bash
#
# lists.sh - Shared helpers for reading dotfiles package/plugin lists.
#
# Sourceable with no side effects, so it can be unit-tested.

# Read a list file plus its gitignored .local companion.
#
# This repo is public, so anything private (work marketplaces, internal
# plugins) belongs in <name>.local.list, which is gitignored. Both are
# read at install time; only the public one is committed.
#
# Usage: read_list <dir> <name>
# Emits one entry per line, comments and blank lines removed.
read_list() {
  local dir="$1" name="$2" file
  for file in "$dir/$name.list" "$dir/$name.local.list"; do
    [[ -f "$file" ]] || continue
    grep -vE '^[[:space:]]*(#|$)' "$file" || true
  done
}

# Count the entries read_list would emit.
# Usage: count_list <dir> <name>
count_list() {
  read_list "$1" "$2" | grep -c . || true
}

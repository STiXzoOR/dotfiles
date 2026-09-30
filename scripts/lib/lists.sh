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

# Does <haystack> (a JSON listing, say) contain <token> as a whole name?
# A plain `grep -F` also matched "safety-net" inside "cc-safety-net" and
# "org/tools" inside "org/tools-extras". The token may be preceded by anything
# but a name character (a "/" is fine: it is the owner/repo form inside a URL)
# and followed by anything but one, or by a ".git" suffix.
# Usage: list_has_token <haystack> <token>
list_has_token() {
  local esc
  esc=$(printf '%s' "$2" | sed 's/[][\.*^$+?(){}|]/\\&/g')
  grep -Eq "(^|[^[:alnum:]_.-])${esc}(\\.git)?([^[:alnum:]_.-]|\$)" <<<"$1"
}

# Drop the two lines the VS Code CLI prints on every call (Node's url.parse
# deprecation and its "--trace-deprecation" hint) and pass everything else
# through, so a real error still shows.
# Usage: some-code-cli-call 2>&1 | filter_code_noise
filter_code_noise() {
  # shellcheck disable=SC2016
  grep -vE '^\(node:[0-9]+\) \[DEP0169\]|^\(Use `[^`]*--trace-deprecation' || true
}

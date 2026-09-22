#!/usr/bin/env bash
#
# zsh -n over every zsh file in the repo, with the file list derived from
# what each file declares rather than from a hand-written list. The old list
# named system/.fix, which does not exist; it was guarded by [[ -f ]], so it
# skipped silently and nobody noticed the gap.
#
# Shared by the Ubuntu syntax job and the macOS test job so both check the
# same set with their own zsh build. Bash 3.2 compatible: no mapfile.
set -uo pipefail

# One repo-relative path per line. `--list` prints this and nothing else, so
# bin/dotfiles-test can check the same set with its own per-file reporting
# instead of keeping a second list that drifts -- the one it had named
# system/.fix, which does not exist, and was missing system/.editor,
# system/.atuin and system/.pay-respects.
discover() {
  local file first

  while IFS= read -r file; do
    [ -f "$file" ] || continue

    first=$(head -1 "$file" 2> /dev/null)
    case "$first" in
      '#!'*zsh*) ;;
      '#!'*) continue ;;
      *)
        # No shebang. Only the files the zsh startup chain actually sources
        # count as zsh fragments. A blanket runcom/.* rule swept in
        # runcom/.vimrc and runcom/.vim/**, which are vimscript and fail
        # zsh -n, and .gemrc and .mackup.cfg, which happen to parse as zsh
        # and so were being "checked" by accident.
        case "$file" in
          runcom/.z* | runcom/.profile) ;;
          system/.*/*) continue ;;
          system/.*) ;;
          *) continue ;;
        esac
        ;;
    esac

    printf '%s\n' "$file"
  done < <(git ls-files 'runcom/*' 'system/*' 'bin/*')
}

# Before the zsh check: listing is discovery, and a caller may want the list
# on a machine with no zsh.
case "${1:-}" in
  --list)
    discover
    exit 0
    ;;
esac

if ! command -v zsh > /dev/null 2>&1; then
  echo "zsh not installed" >&2
  exit 1
fi

rc=0
checked=0

while IFS= read -r file; do
  echo "Checking $file..."
  checked=$((checked + 1))
  zsh -n "$file" || rc=1
done < <(discover)

printf 'checked %d zsh files with %s\n' "$checked" "$(zsh --version)"
[ "$checked" -gt 0 ] || {
  echo "no zsh files found -- the discovery is broken" >&2
  exit 1
}
exit "$rc"

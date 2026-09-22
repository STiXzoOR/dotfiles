#!/usr/bin/env zsh

setopt EXTENDED_GLOB

PREZTO_DIR="${ZDOTDIR:-$DOTFILES_DIR}/modules/prezto"

# The glob below carries the N (nullglob) qualifier, so an uninitialised
# submodule matches nothing, the loop runs zero times and this script still
# exits 0 -- which the caller reported as a successful prezto install. Fail
# loudly instead; bin/dotfiles initialises the submodule before calling us.
if [[ ! -f "$PREZTO_DIR/init.zsh" ]]; then
  print -u2 "prezto is not checked out: $PREZTO_DIR/init.zsh is missing."
  print -u2 "Initialise it with: git submodule update --init --depth 1 -- modules/prezto"
  exit 1
fi

for rcfile in "$PREZTO_DIR"/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}" 2>/dev/null
done

exit 0

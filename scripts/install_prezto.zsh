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

# Link only the runcoms this repo does not ship. runcom/ carries its own
# zshrc, zprofile, zpreztorc and zlogin; linking Prezto's copies as well made
# `dotfiles link` back them up straight away. zlogout is never linked: it
# prints a fortune-style quote on every shell exit.
RUNCOM_DIR="${DOTFILES_DIR:-${PREZTO_DIR:h:h}}/runcom"
for rcfile in "$PREZTO_DIR"/runcoms/^README.md(.N); do
  [[ "${rcfile:t}" == zlogout ]] && continue
  [[ -e "$RUNCOM_DIR/.${rcfile:t}" ]] && continue
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}" 2>/dev/null
done

exit 0

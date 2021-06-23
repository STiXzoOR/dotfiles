#!/bin/zsh

setopt EXTENDED_GLOB

for rcfile in "${ZDOTDIR:-$DOTFILES_DIR}"/plugins/prezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}" 2>/dev/null
done

exit 0

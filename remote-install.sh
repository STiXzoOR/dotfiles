#!/usr/bin/env bash

SOURCE="https://github.com/STiXzoOR/dotfiles"
TARGET="$HOME/.dotfiles"
CMD="git clone --recurse-submodules $SOURCE $TARGET"

is_executable() {
  type "$1" >/dev/null 2>&1
}

if [ ! is_executable "git" ]; then
  echo "Git is not available. Aborting."
else
  mkdir -p "$TARGET"
  eval "$CMD"
  $(builtin cd "$TARGET" && ./bin/dotfiles install)
fi

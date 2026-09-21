#!/usr/bin/env bash
#
# Bootstrap entry point for a bare machine.

set -euo pipefail

SOURCE="https://github.com/STiXzoOR/dotfiles"
TARGET="$HOME/.dotfiles"

# /usr/bin/git is a Command Line Tools *shim*: it exists on a bare Mac even
# with no CLT installed, so `type git` or `command -v git` both succeed and the
# first real git call then pops the GUI installer. Probe the actual binary.
if ! git --version >/dev/null 2>&1; then
  echo "Git is not usable yet. Install the Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

if [ -e "$TARGET" ]; then
  echo "$TARGET already exists. Aborting."
  exit 1
fi

# Not --recurse-submodules: that pulls every submodule up front (~2.3 GB, most
# of it the stevenblack-hosts history). The installer initialises the shallow
# ones it actually needs, when it needs them.
git clone "$SOURCE" "$TARGET"
(cd "$TARGET" && ./bin/dotfiles install)

#!/usr/bin/env bash
#
# Bootstrap entry point for a bare machine.

set -euo pipefail

SOURCE="https://github.com/STiXzoOR/dotfiles"
TARGET="$HOME/.dotfiles"

if [ "$(uname -m)" != "arm64" ]; then
  echo "This repo supports Apple silicon only (Homebrew drops Intel in Sept 2027)." >&2
  exit 1
fi

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

# Not --recurse-submodules: that ignores the `shallow = true` in .gitmodules
# unless --shallow-submodules is added too, and pulls every submodule up front
# whether or not this machine needs it. dotfiles_ensure_submodule (in
# scripts/lib/fs.sh) initialises each one shallowly at the point of use.
git clone "$SOURCE" "$TARGET"
(cd "$TARGET" && ./bin/dotfiles install)

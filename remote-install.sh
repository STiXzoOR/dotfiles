#!/usr/bin/env bash
#
# Bootstrap entry point for a bare machine. Safe to re-run: it installs the
# Command Line Tools itself, and continues an existing checkout instead of
# refusing to start.

set -euo pipefail

SOURCE="https://github.com/STiXzoOR/dotfiles"
TARGET="$HOME/.dotfiles"
# The ref clt.sh is fetched from. Pin it to a tag or commit to bootstrap from
# something other than the main branch.
REF="${DOTFILES_REF:-main}"

if [ "$(uname -m)" != "arm64" ]; then
  echo "This repo supports Apple silicon only (Homebrew drops Intel in Sept 2027)." >&2
  exit 1
fi

# One password prompt up front; the Command Line Tools install needs root.
sudo -v

# `xcode-select -p` is the probe, never `git --version`: /usr/bin/git is a
# Command Line Tools *shim*, present on a bare Mac, and running it pops the
# GUI installer. scripts/lib/clt.sh is fetched on its own because there is no
# clone yet, and it depends on nothing else in the repo.
if ! xcode-select -p >/dev/null 2>&1; then
  clt_lib=$(mktemp "${TMPDIR:-/tmp}/dotfiles-clt.XXXXXX")
  if ! curl -fsSL --proto '=https' \
    "https://raw.githubusercontent.com/STiXzoOR/dotfiles/${REF}/scripts/lib/clt.sh" \
    -o "$clt_lib"; then
    rm -f "$clt_lib"
    echo "Could not download scripts/lib/clt.sh (ref: $REF). Install the tools by hand:" >&2
    echo "  xcode-select --install" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$clt_lib"
  rm -f "$clt_lib"
  dotfiles_install_clt || exit 1
fi

if [ -e "$TARGET/.git" ]; then
  echo "$TARGET is already a checkout; continuing with it."
elif [ -e "$TARGET" ]; then
  echo "$TARGET already exists and is not a git checkout. Aborting."
  exit 1
else
  # Not --recurse-submodules: that ignores the `shallow = true` in .gitmodules
  # unless --shallow-submodules is added too, and pulls every submodule up front
  # whether or not this machine needs it. dotfiles_ensure_submodule (in
  # scripts/lib/fs.sh) initialises each one shallowly at the point of use.
  git clone "$SOURCE" "$TARGET"
fi

cd "$TARGET" && ./bin/dotfiles install

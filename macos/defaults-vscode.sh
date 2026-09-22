#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Visual Studio Code"
###############################################################################

running "Install settings"
if [ ! -d "$HOME/Library/Application Support/Code/User" ]; then
  mkdir -p "$HOME/Library/Application Support/Code/User"
fi

rm -f "$HOME/Library/Application Support/Code/User/settings.json" 2>/dev/null
if ln -sf "$DOTFILES_DIR/apps/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"; then
  ok
else
  error "could not link the VS Code settings"
fi

killall "Code" >/dev/null 2>&1

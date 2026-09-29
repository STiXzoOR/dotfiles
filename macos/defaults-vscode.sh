#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Visual Studio Code"
###############################################################################

VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
if [ ! -d "$VSCODE_USER_DIR" ]; then
  mkdir -p "$VSCODE_USER_DIR"
fi

for _vscode_file in settings keybindings; do
  running "Install $_vscode_file"
  rm -f "$VSCODE_USER_DIR/$_vscode_file.json" 2>/dev/null
  if ln -sf "$DOTFILES_DIR/apps/vscode/$_vscode_file.json" "$VSCODE_USER_DIR/$_vscode_file.json"; then
    ok
  else
    error "could not link the VS Code $_vscode_file"
  fi
done
unset _vscode_file

killall "Code" >/dev/null 2>&1

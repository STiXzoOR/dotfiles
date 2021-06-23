###############################################################################
bot "Visual Studio Code"
###############################################################################

running "Install settings"
if [ ! -d "$HOME/Library/Application Support/Code/User" ]; then
  mkdir -p "$HOME/Library/Application Support/Code/User"
fi

ln -sf "$DOTFILES_DIR/apps/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json" 2>/dev/null
ok

killall "Code" >/dev/null 2>&1

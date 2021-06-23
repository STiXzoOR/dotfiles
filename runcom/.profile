#############################################################
# Generic configuration that applies to all shells
#############################################################

if [[ -d "$HOME/.dotfiles" ]]; then
  DOTFILES_DIR="$HOME/.dotfiles"
else
  echo "Unable to find dotfiles, exiting."
  return
fi

PATH="$DOTFILES_DIR/bin:$PATH"

for DOTFILE in "$DOTFILES_DIR"/system/.{env,bindings,function,function_*,path,alias,grep,iterm}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

eval "$(dircolors -b "$DOTFILES_DIR"/system/.dir_colors)"

unset DOTFILE
export DOTFILES_DIR

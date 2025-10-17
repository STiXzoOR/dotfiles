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

for DOTFILE in "$DOTFILES_DIR"/system/.{function,function_*,path,env,alias,starship,fnm,fzf,grep,fix,pnpm}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

eval "$(dircolors -b "$DOTFILES_DIR"/system/.dir_colors)"

unset DOTFILE
export DOTFILES_DIR

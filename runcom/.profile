# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/profile.pre.bash" ]] && builtin source "$HOME/.fig/shell/profile.pre.bash"
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

for DOTFILE in "$DOTFILES_DIR"/system/.{env,bindings,function,function_*,path,alias,fnm,grep,iterm}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

eval "$(dircolors -b "$DOTFILES_DIR"/system/.dir_colors)"

unset DOTFILE
export DOTFILES_DIR

# Fig post block. Keep at the bottom of this file.
[[ -f "$HOME/.fig/shell/profile.post.bash" ]] && builtin source "$HOME/.fig/shell/profile.post.bash"

#############################################################
# Generic configuration that applies to all shells
#############################################################

if [[ -d "$HOME/.dotfiles" ]]; then
  DOTFILES_DIR="$HOME/.dotfiles"
else
  echo "Unable to find dotfiles, exiting."
  return
fi

for DOTFILE in "$DOTFILES_DIR"/system/.{function,function_*,path,env,alias,fnm,fzf,grep,thefuck,pnpm}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

# dircolors - cached for performance
_dircolors_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dircolors.zsh"
_dircolors_src="$DOTFILES_DIR/system/.dir_colors"
if [[ ! -f "$_dircolors_cache" ]] || [[ "$_dircolors_src" -nt "$_dircolors_cache" ]]; then
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
  dircolors -b "$_dircolors_src" > "$_dircolors_cache" 2>/dev/null
fi
[[ -f "$_dircolors_cache" ]] && source "$_dircolors_cache"
unset _dircolors_cache _dircolors_src

unset DOTFILE
export DOTFILES_DIR

# Load machine-specific profile
[[ -f "$DOTFILES_DIR/system/.profile_loader" ]] && source "$DOTFILES_DIR/system/.profile_loader"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

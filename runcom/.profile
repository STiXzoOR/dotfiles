#############################################################
# Generic configuration that applies to all shells
#############################################################

if [[ -d "$HOME/.dotfiles" ]]; then
  DOTFILES_DIR="$HOME/.dotfiles"
else
  echo "Unable to find dotfiles, exiting."
  return
fi

# Core system files (bash + zsh compatible).
#
# Order is load-bearing in three places. .env comes first: it exports
# XDG_CACHE_HOME, which .path needs to place the brew shellenv cache.
# .function comes before .path because .path calls prepend-path (audit
# shell#8). .editor comes after .path because it looks for nvim, which lives
# in the Homebrew prefix that .path adds (WS-C review 1, finding 1). .mise
# comes after .path too, and before the zsh-only block that sources .fnm: it
# calls prepend-path, and putting the shims in front of what .path prepended
# is the point. It is in this loop rather than the zsh-only one because a
# non-interactive bash login shell needs the shims just as much.
for DOTFILE in "$DOTFILES_DIR"/system/.{env,function,function_*,path,mise,editor,grep}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

# Files using zsh-only features ($+commands, alias -g, alias -s).
#
# Anything that installs a key binding is NOT loaded here: prezto's editor
# module runs `bindkey -d`, which resets every keymap to its defaults and
# discards whatever was bound before it. .fzf and .atuin are therefore sourced
# from .zshrc, after prezto.
if [[ -n "$ZSH_VERSION" ]]; then
  for DOTFILE in "$DOTFILES_DIR"/system/.{alias,fnm,pay-respects,pnpm}; do
    [[ -f "$DOTFILE" ]] && . "$DOTFILE"
  done
fi

# dircolors - cached per TERM.
#
# `dircolors -b` emits an empty LS_COLORS when $TERM matches none of the TERM
# lines in .dir_colors. A cache that is not keyed on TERM can therefore be
# poisoned once, from one dumb-terminal shell, and stay empty forever after
# (audit shell#6). Regenerating costs well under a millisecond.
_dircolors_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dircolors-${TERM:-dumb}.zsh"
_dircolors_src="$DOTFILES_DIR/system/.dir_colors"
if command -v dircolors >/dev/null 2>&1; then
  if [[ ! -s "$_dircolors_cache" ]] || [[ "$_dircolors_src" -nt "$_dircolors_cache" ]]; then
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
    dircolors -b "$_dircolors_src" >| "$_dircolors_cache" 2>/dev/null
  fi
fi
[[ -s "$_dircolors_cache" ]] && . "$_dircolors_cache"
unset _dircolors_cache _dircolors_src

unset DOTFILE
export DOTFILES_DIR

# Load machine-specific profile
[[ -f "$DOTFILES_DIR/system/.profile_loader" ]] && source "$DOTFILES_DIR/system/.profile_loader"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

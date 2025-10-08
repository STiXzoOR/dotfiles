# zmodload zsh/zprof # Enable for debugging
#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

##################################################################################################
# Enable Instant Prompt
##################################################################################################
# if [[ -s "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

##################################################################################################
# Hide Username from Prompt
##################################################################################################

export DEFAULT_USER=$(whoami)

##################################################################################################
# Source Powerlevel Settings
##################################################################################################

[[ -f "$DOTFILES_DIR/system/.prompt" ]] && . "$DOTFILES_DIR/system/.prompt"

##################################################################################################
# Source Prezto
##################################################################################################

[[ -s "$DOTFILES_DIR/modules/prezto/init.zsh" ]] && . "$DOTFILES_DIR/modules/prezto/init.zsh"

##################################################################################################
# Completion settings
##################################################################################################

source "$DOTFILES_DIR/system/.completion"
fpath+="$DOTFILES_DIR/completions"
compinit
source "$DOTFILES_DIR/system/.zoxide"

##################################################################################################
# Recursive globbing with "**"
##################################################################################################

setopt GLOB_STAR_SHORT

# zprof # Enable for debugging

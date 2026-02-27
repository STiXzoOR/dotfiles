# zmodload zsh/zprof # Enable for debugging

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

##################################################################################################
# Hide Username from Prompt
##################################################################################################

export DEFAULT_USER="$USER"

##################################################################################################
# Source Prezto
##################################################################################################

# Add completions to fpath BEFORE compinit (Prezto handles compinit)
fpath=("$DOTFILES_DIR/completions" $fpath)

[[ -s "$DOTFILES_DIR/modules/prezto/init.zsh" ]] && . "$DOTFILES_DIR/modules/prezto/init.zsh"

##################################################################################################
# Prompt configuration (Powerlevel10k)
##################################################################################################

# Source p10k config if it exists
[[ -f "$DOTFILES_DIR/system/.prompt" ]] && source "$DOTFILES_DIR/system/.prompt"

##################################################################################################
# Completion settings
##################################################################################################

# Source completion config (without redundant compinit)
source "$DOTFILES_DIR/system/.completion"

# Zoxide (lazy-loaded in .zoxide for performance)
source "$DOTFILES_DIR/system/.zoxide"

##################################################################################################
# Key bindings (must be after Prezto for history-substring-search)
##################################################################################################

source "$DOTFILES_DIR/system/.bindings"

##################################################################################################
# Recursive globbing with "**"
##################################################################################################

setopt GLOB_STAR_SHORT

# zprof # Enable for debugging

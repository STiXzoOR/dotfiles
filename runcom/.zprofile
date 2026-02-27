##############################################################################
#Import the shell-agnostic (Bash or Zsh) environment config
##############################################################################
source "$HOME/.profile"

##############################################################################
# History Configuration
##############################################################################
HISTSIZE=32768
HISTFILE=~/.zsh_history
SAVEHIST=32768
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

# OrbStack: load from profiles/local.zsh if needed
# source ~/.orbstack/shell/init.zsh 2>/dev/null || :

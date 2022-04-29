# Fig pre block. Keep at the top of this file.
. "$HOME/.fig/shell/zprofile.pre.zsh"
##############################################################################
#Import the shell-agnostic (Bash or Zsh) environment config
##############################################################################
source "$HOME/.profile"

##############################################################################
# History Configuration
##############################################################################
HISTSIZE=32768             #How many lines of history to keep in memory
HISTFILESIZE="${HISTSIZE}" #How big the history file will be
HISTFILE=~/.zsh_history    #Where to save history to disk
SAVEHIST=4096              #Number of history entries to save to disk
HISTDUP=erase              #Erase duplicates in the history file
setopt appendhistory       #Append history to the history file (no overwriting)
setopt sharehistory        #Share history across terminals
setopt incappendhistory    #Immediately append to the history file, not just when a term is killed

##############################################################################
# zsh-nvm Setup
##############################################################################
export NVM_LAZY_LOAD=false
export NVM_AUTO_USE=true
export NVM_COMPLETION=true

# Fig post block. Keep at the bottom of this file.
. "$HOME/.fig/shell/zprofile.post.zsh"

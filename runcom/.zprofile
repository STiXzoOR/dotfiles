##############################################################################
#Import the shell-agnostic (Bash or Zsh) environment config
##############################################################################
source "$HOME/.profile"

##############################################################################
# PATH normalisation
##############################################################################
# Has to run after .profile, because .profile sources ~/.local/bin/env last and
# that file prepends $HOME/.local/share/../bin -- a non-normalised spelling of
# $HOME/.local/bin that `typeset -U` cannot recognise as a duplicate, since it
# compares strings. Stale fnm_multishells entries inherited from a parent shell
# survive for the same reason. (N-/) also drops entries that no longer exist,
# and :a normalises without resolving symlinks, so Homebrew opt paths are not
# pinned to a Cellar version (audit shell#10).
path=(${^path}(N-/:a))
typeset -U path

##############################################################################
# History Configuration
##############################################################################
# HISTSIZE and SAVEHIST do not belong here: /etc/zshrc runs after .zprofile and
# resets both, and prezto's history module then sets its own defaults. They are
# set through `zstyle ':prezto:module:history'` in .zpreztorc instead
# (audit shell#4). HISTFILE survives because prezto honours a pre-set value.
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

# OrbStack: load from profiles/local.zsh if needed
# source ~/.orbstack/shell/init.zsh 2>/dev/null || :

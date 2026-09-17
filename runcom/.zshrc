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
# SSH agent + macOS Keychain
##################################################################################################

# Must run BEFORE Prezto's ssh module. That module prompts for a passphrase on a
# terminal whenever the agent is empty, because plain `ssh-add` does not consult
# the Keychain. Handing it an already-populated agent makes it a no-op.
#
# Passphrase is stored once with: ssh-add --apple-use-keychain ~/.ssh/id_ed25519
if [[ "$OSTYPE" == darwin* ]]; then
  _ssh_agent_env="${XDG_CACHE_HOME:-$HOME/.cache}/prezto/ssh-agent.env"

  # ssh-add -l: 0 = has keys, 1 = agent up but empty, 2 = no agent reachable.
  ssh-add -l &>/dev/null; _ssh_state=$?

  if (( _ssh_state == 2 )); then
    source "$_ssh_agent_env" &>/dev/null
    ssh-add -l &>/dev/null; _ssh_state=$?
  fi

  if (( _ssh_state == 2 )); then
    mkdir -p "${_ssh_agent_env:h}"
    eval "$(ssh-agent | sed '/^echo /d' | tee "$_ssh_agent_env")" &>/dev/null
    ssh-add -l &>/dev/null; _ssh_state=$?
  fi

  # Agent reachable but empty: pull keys whose passphrases live in the Keychain.
  # Unlike plain `ssh-add`, this never prompts.
  (( _ssh_state == 1 )) && ssh-add --apple-load-keychain &>/dev/null

  unset _ssh_agent_env _ssh_state
fi

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

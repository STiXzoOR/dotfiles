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
# Key-binding plugins (must be after prezto: its editor module runs `bindkey -d`)
##################################################################################################

# Order matters. `fzf --zsh` binds ctrl-R to its own history widget, so atuin
# has to be sourced second to take that key.
source "$DOTFILES_DIR/system/.fzf"
source "$DOTFILES_DIR/system/.atuin"

##################################################################################################
# fzf-tab (after compinit, which prezto's completion module runs, and after
# .fzf, whose own completion binding it replaces)
##################################################################################################

# Replaces the completion menu with the finder already configured for ctrl-T
# and ctrl-R. Guarded on the file so that a checkout whose submodules have not
# been initialised still gets a working shell.
[[ -s "$DOTFILES_DIR/modules/fzf-tab/fzf-tab.plugin.zsh" ]] &&
  source "$DOTFILES_DIR/modules/fzf-tab/fzf-tab.plugin.zsh"

##################################################################################################
# Key bindings (must be after Prezto for history-substring-search)
##################################################################################################

source "$DOTFILES_DIR/system/.bindings"

##################################################################################################
# Recursive globbing with "**"
##################################################################################################

setopt GLOB_STAR_SHORT

##################################################################################################
# mise activation (opt-in, off by default)
##################################################################################################

# The login path gets mise's shims and nothing else (system/.mise). Shims cost
# one PATH entry and resolve the per-directory version at exec time; they are
# also a fixed path, so git hooks, SessionEnd hooks, launchd jobs and GUI apps
# inherit them, and none of those read this file.
#
# Activation adds a precmd hook that re-resolves the environment on every
# prompt. It buys two things shims cannot: [env] blocks from a mise.toml, and
# tool changes that apply without a new exec. It costs roughly 80 ms at the
# first prompt and ~15 ms at each one after. Set DOTFILES_MISE_ACTIVATE=1 in
# profiles/local.zsh to take that trade.
if [[ "${DOTFILES_MISE_ACTIVATE:-0}" == 1 ]] && (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi

##################################################################################################
# Post-profile machine hooks
##################################################################################################

# profiles/*.zsh load from .zprofile, long before prezto runs compinit. Anything
# that needs compdef -- gcloud's completion.zsh.inc, a tool's `init zsh` that
# registers completions -- has to go in a .post.zsh file instead. Sourced from
# .zprofile, gcloud's inc file found no compdef, ran a second full compinit and
# built a second dump, for 40 ms on every login shell (audit shell#2).
#
# The machine profile goes first and local.post.zsh last, matching the order
# system/.profile_loader uses for the pre-prezto files.
for _post_profile in "$DOTFILES_LOADED_PROFILE" local; do
  [[ -n "$_post_profile" && -f "$DOTFILES_DIR/profiles/$_post_profile.post.zsh" ]] &&
    source "$DOTFILES_DIR/profiles/$_post_profile.post.zsh"
done
unset _post_profile

# zprof # Enable for debugging

#
# Executes commands at login post-zshrc.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Execute code that does not affect the current session in the background.
{
  # Compile the completion dump to increase startup speed. Prezto keeps its
  # dump under $XDG_CACHE_HOME/prezto; ${ZDOTDIR:-$HOME}/.zcompdump was a
  # second dump that only existed because gcloud ran its own compinit from
  # .zprofile (audit shell#5).
  zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/prezto/zcompdump"
  if [[ -s "$zcompdump" && (! -s "${zcompdump}.zwc" || "$zcompdump" -nt "${zcompdump}.zwc") ]]; then
    zcompile "$zcompdump"
  fi
} &!

# Execute code only if STDERR is bound to a TTY.
# [[ -o INTERACTIVE && -t 2 ]] && {
#   neofetch
# } >&2

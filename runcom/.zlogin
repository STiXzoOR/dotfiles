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

  # Rebuild the dump here, not in the foreground. Prezto regenerates it inside
  # the shell that finds it older than 20 h, which costs about 315 ms before
  # the first prompt (and every first shell on a new Mac). Rebuilding at 8 h
  # keeps it younger than that, so Prezto only ever takes the cached path. A
  # detached `zsh -f` does the work, given this shell's fpath through FPATH; it
  # writes a temp file that replaces the dump in one mv, so a shell starting
  # meanwhile reads the old dump or the new one, never half of one. The result
  # matches the foreground dump apart from comments. Plain compinit, not
  # `compinit -C`: the function check is the point.
  if [[ -s "$zcompdump" && -n "$zcompdump"(#qN.mh+8) ]]; then
    _zcompdump_tmp="$zcompdump.$$.tmp"
    FPATH="${(j.:.)fpath}" zsh -f -c 'autoload -Uz compinit && compinit -i -d "$1"' _ "$_zcompdump_tmp" &>/dev/null
    [[ -s "$_zcompdump_tmp" ]] && command mv -f "$_zcompdump_tmp" "$zcompdump"
    command rm -f "$_zcompdump_tmp"
    unset _zcompdump_tmp
  fi

  if [[ -s "$zcompdump" && (! -s "${zcompdump}.zwc" || "$zcompdump" -nt "${zcompdump}.zwc") ]]; then
    zcompile "$zcompdump"
  fi
} &!

# Execute code only if STDERR is bound to a TTY.
# [[ -o INTERACTIVE && -t 2 ]] && {
#   neofetch
# } >&2

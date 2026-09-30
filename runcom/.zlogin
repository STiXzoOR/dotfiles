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
  # The (#qN.mh+8) age test is a glob qualifier and needs EXTENDED_GLOB, which
  # only Prezto's modules set: without it the test is a plain string test and
  # the dump is rebuilt on every login. Set it here, local to this function.
  _zcompdump_stale() { setopt localoptions extendedglob; [[ -n "$zcompdump"(#qN.mh+8) ]]; }
  # Two logins opening together would both rebuild; a mkdir lock lets one do it.
  # A lock older than 5 minutes belongs to a shell that was killed mid-rebuild
  # (the rebuild takes about a second), so it is taken over.
  _zcompdump_lock() {
    setopt localoptions extendedglob
    [[ -d "$zcompdump.lock"(#qN/mm+5) ]] && command rmdir "$zcompdump.lock" 2>/dev/null
    command mkdir "$zcompdump.lock" 2>/dev/null
  }
  if [[ -s "$zcompdump" ]] && _zcompdump_stale && _zcompdump_lock; then
    _zcompdump_tmp="$zcompdump.$$.tmp"
    FPATH="${(j.:.)fpath}" zsh -f -c 'autoload -Uz compinit && compinit -i -d "$1"' _ "$_zcompdump_tmp" &>/dev/null
    [[ -s "$_zcompdump_tmp" ]] && command mv -f "$_zcompdump_tmp" "$zcompdump"
    command rm -f "$_zcompdump_tmp"
    command rmdir "$zcompdump.lock" 2>/dev/null
    unset _zcompdump_tmp
  fi
  unfunction _zcompdump_stale _zcompdump_lock

  if [[ -s "$zcompdump" && (! -s "${zcompdump}.zwc" || "$zcompdump" -nt "${zcompdump}.zwc") ]]; then
    zcompile "$zcompdump"
  fi
} &!

# Execute code only if STDERR is bound to a TTY.
# [[ -o INTERACTIVE && -t 2 ]] && {
#   neofetch
# } >&2

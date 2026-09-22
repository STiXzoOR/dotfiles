#!/usr/bin/env bash
#
# tests/shell.sh -- regression tests for the login path: the 2026-09-21
# audit's shell workstream (the C sections) and the zsh 2026 host seam (H).
#
# Assertions are single-quoted strings evaluated by t(); they must not expand
# where they are written, hence the blanket SC2016 disable.
#
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# zsh sandbox
#
# A login+interactive zsh whose $HOME is a throwaway directory. runcom/ is
# copied in as $ZDOTDIR and $HOME/.dotfiles is assembled from symlinks to the
# repo's own directories -- every directory EXCEPT profiles/, which is rebuilt
# with default.zsh alone. profiles/local.zsh is the user's private file: it
# reads the login keychain and the network, so a sandbox that linked it would
# be neither hermetic nor side-effect free.
#
# $HOME/.local/bin/env reproduces the un-normalised PATH entry that uv's env
# file adds on the real machine (audit shell#10) -- without it the PATH
# normalisation tests would pass vacuously -- and puts $HOME/.stubs at the
# front of PATH. ssh-add is stubbed there so that the agent block in .zshrc
# sees a populated agent and never reaches the real agent or the Keychain.
#
# Every tool whose init the login path evaluates -- starship, fzf, atuin,
# zoxide -- is stubbed too (write_tool_stubs), so that what a sandboxed shell
# loads depends on this repo alone: the CI macOS runner has none of them and
# the author's machine has all of them.
# ---------------------------------------------------------------------------

_zsh_sandbox() {
  local h
  h=$(sandbox) || return 1
  mkdir -p "$h/.cache" "$h/.dotfiles/profiles" "$h/.local/bin" "$h/.stubs" || return 1
  cp runcom/.profile runcom/.zprofile runcom/.zshrc runcom/.zlogin runcom/.zpreztorc "$h/" || return 1
  local d
  for d in modules system completions bin config; do
    [ -e "$ROOT_DIR/$d" ] && ln -s "$ROOT_DIR/$d" "$h/.dotfiles/$d"
  done
  cp profiles/default.zsh "$h/.dotfiles/profiles/" || return 1
  # Records whether the post-profile hook ran at all and whether compdef --
  # the thing the hook exists for -- was defined by then.
  cat >"$h/.dotfiles/profiles/local.post.zsh" <<'POSTEOF'
if (( $+functions[compdef] )); then
  DOTFILES_POST_HOOK_RAN=with-compdef
else
  DOTFILES_POST_HOOK_RAN=no-compdef
fi
POSTEOF
  # zshrun also puts .stubs on PATH so that system/.env, which runs long
  # before this file, can see a stubbed binary. The prepend here is what keeps
  # the stubs ahead of the real binaries once system/.path has had its say.
  cat >"$h/.local/bin/env" <<'ENVEOF'
export PATH="$HOME/.stubs:$PATH"
case ":${PATH}:" in
  *:"$HOME/.local/share/../bin":*) ;;
  *) export PATH="$HOME/.local/share/../bin:$PATH" ;;
esac
ENVEOF
  # zprof on request, so that a probe can count compinit calls. runcom/ has no
  # .zshenv, and zsh reads this one before any file under test.
  printf '%s\n' '[[ -n $DOTFILES_TEST_ZPROF ]] && zmodload zsh/zprof' >"$h/.zshenv"
  write_tool_stubs "$h" || return 1
  local s
  for s in ssh-add ssh-agent ${ZSHRUN_STUBS:-}; do
    printf '#!/bin/sh\nexit 0\n' >"$h/.stubs/$s"
    chmod +x "$h/.stubs/$s"
  done
  printf '%s' "$h"
}

# _zsh_login <home> <zsh code> -- the one way this suite starts a sandboxed
# login shell. The host class is pinned rather than detected:
#   ZSHRUN_TERM_HOST  warp | rich | dumb. Default rich, the full stack. Set it
#                     empty to leave the class to system/.term_host.
#   ZSHRUN_ENV        extra NAME=value words, e.g. TERM_PROGRAM=WarpTerminal.
# stdin is /dev/null, so a detected class is never rich.
_zsh_login() {
  # shellcheck disable=SC2086 # ZSHRUN_ENV is a list of NAME=value words
  env -u LC_ALL -u TERM_PROGRAM -u DOTFILES_TERM_HOST \
    HOME="$1" ZDOTDIR="$1" XDG_CACHE_HOME="$1/.cache" PATH="$1/.stubs:$PATH" \
    DOTFILES_TERM_HOST="${ZSHRUN_TERM_HOST-rich}" ${ZSHRUN_ENV:-} \
    zsh -l -i -c "$2" </dev/null
}

# zshrun <zsh code> -- run it in the sandbox, print stdout, discard stderr.
# Set ZSHRUN_HOME to an existing sandbox to reuse it, so that two shells can
# run in sequence against the same caches.
zshrun() {
  local h
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  _zsh_login "$h" "$1" 2>/dev/null
}

# zshrun_all <zsh code> -- same, but stderr is merged into stdout so that
# startup noise shows up in the result.
zshrun_all() {
  local h
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  _zsh_login "$h" "$1" 2>&1
}

# ptyrun <command...> -- run it with a pseudo-terminal for stdin, stdout and
# stderr: the only way a test reaches the `[[ -t 0 ]]` branch of
# system/.term_host, since the suite has no terminal of its own in CI. BSD
# script(1) echoes the EOF it forwards as "^D" and ends lines with \r\n; both
# are stripped. stderr arrives mixed into stdout.
ptyrun() {
  /usr/bin/script -q /dev/null "$@" </dev/null | tr -d '\r\b' | sed 's/\^D//g'
}

# pty_zshrun <zsh code> -- a sandboxed login shell on a pseudo-terminal, with
# the class left to system/.term_host. ZSHRUN_ENV says which host it is in.
pty_zshrun() {
  local h
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  # shellcheck disable=SC2086 # ZSHRUN_ENV is a list of NAME=value words
  ptyrun env -u LC_ALL -u TERM_PROGRAM -u DOTFILES_TERM_HOST \
    HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" PATH="$h/.stubs:$PATH" \
    ${ZSHRUN_ENV:-} zsh -l -i -c "$1"
}

# term_host_of [NAME=value...] -- source system/.term_host in a bare zsh with
# exactly that environment and no terminal; print "class:type", where type is
# scalar, or scalar-export if the class would leak into child shells.
# pty_term_host_of: the same on a pseudo-terminal.
_term_host_code='. "$ROOT/system/.term_host"; print -r -- "OUT=$DOTFILES_TERM_HOST:${(t)DOTFILES_TERM_HOST}"'
term_host_of() {
  env -i PATH=/usr/bin:/bin ROOT="$ROOT_DIR" "$@" zsh -f -c "$_term_host_code" </dev/null |
    sed -n 's/^.*OUT=//p'
}
pty_term_host_of() {
  ptyrun env -i PATH=/usr/bin:/bin ROOT="$ROOT_DIR" "$@" zsh -f -c "$_term_host_code" |
    sed -n 's/^.*OUT=//p'
}

# bound_to <bindkey output> <widget>: the key is bound to <widget>.
# bound_elsewhere <bindkey output> <widget>: the shell answered, and the key
# is bound to something else. An empty answer fails instead of passing.
bound_to()        { [ "${1#\"*\" }" = "$2" ]; }
bound_elsewhere() { [ -n "$1" ] && [ "${1#\"*\" }" != "$2" ]; }

# Stubs for the tools whose init the login path evaluates. Each emits a
# miniature of the real init: enough to see that it ran, with which flags, and
# what it bound.
write_tool_stubs() {
  cat >"$1/.stubs/starship" <<'STUBEOF'
#!/bin/sh
[ "$1" = init ] || exit 0
cat <<'ZSHEOF'
prompt_starship_precmd() { :; }
autoload -Uz add-zsh-hook
add-zsh-hook precmd prompt_starship_precmd
ZSHEOF
STUBEOF
  cat >"$1/.stubs/fzf" <<'STUBEOF'
#!/bin/sh
[ "$1" = --zsh ] || exit 0
cat <<'ZSHEOF'
fzf-stub-widget() { :; }
zle -N fzf-stub-widget
bindkey '^T' fzf-stub-widget
ZSHEOF
STUBEOF
  # Like the real atuin: the recording hook always, the ctrl-R binding unless
  # --disable-ctrl-r.
  cat >"$1/.stubs/atuin" <<'STUBEOF'
#!/bin/sh
[ "$1" = init ] || exit 0
echo "ATUIN_STUB_ARGS='$*'"
cat <<'ZSHEOF'
_atuin_precmd() { :; }
autoload -Uz add-zsh-hook
add-zsh-hook precmd _atuin_precmd
ZSHEOF
case " $* " in *" --disable-ctrl-r "*) exit 0 ;; esac
cat <<'ZSHEOF'
atuin-stub-viins() { :; }
zle -N atuin-stub-viins
bindkey -M viins "^r" atuin-stub-viins
bindkey -M emacs "^r" atuin-stub-viins
ZSHEOF
STUBEOF
  cat >"$1/.stubs/zoxide" <<'STUBEOF'
#!/bin/sh
[ "$1" = init ] || exit 0
echo 'z() { :; }'
STUBEOF
  chmod +x "$1/.stubs/starship" "$1/.stubs/fzf" "$1/.stubs/atuin" "$1/.stubs/zoxide"
}

# nvim on $HOME/bin -- a PATH entry that only system/.path adds. Neither the
# clean-machine PATH below nor ~/.local/bin/env can reach it, so an assertion
# that finds nvim there is an assertion that EDITOR was resolved after .path.
write_nvim_stub() {
  mkdir -p "$1/bin"
  printf '#!/bin/sh\nexit 0\n' >"$1/bin/nvim"
  chmod +x "$1/bin/nvim"
}

# EDITOR the way a clean Apple-silicon Mac resolves it: the real
# runcom/.profile, and the PATH a fresh machine has before any bootstrap has
# run. No /etc/paths.d, no inherited PATH.
editor_through_profile() {
  env -i HOME="$1" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    zsh -f -c '. "$HOME/.profile"; print -r -- "$EDITOR"' 2>/dev/null
}

# EDITOR from system/.editor alone, against a PATH we control completely.
editor_isolated() {
  env -i HOME="$1" PATH="$2" zsh -f -c \
    '. "'"$ROOT_DIR"'/system/.editor"; print -r -- "$EDITOR"' 2>/dev/null
}

# ---------------------------------------------------------------------------
# One login shell per host answers most of the questions this suite asks.
# Starting a shell per assertion costs seconds on a loaded machine, so the
# values are collected once here and read back with pv <KEY> [host], where
# host is rich (the default), warp or dumb.
# ---------------------------------------------------------------------------

ENV_STATE='
  print -r -- "HISTSIZE=$HISTSIZE"
  print -r -- "SAVEHIST=$SAVEHIST"
  print -r -- "LANG=$LANG"
  print -r -- "LC_CTYPE=$LC_CTYPE"
  print -r -- "LC_ALL=${LC_ALL-<unset>}"
  print -r -- "AUTOSUGGEST=$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"
  print -r -- "KEYTIMEOUT=$KEYTIMEOUT"
  print -r -- "EDITOR=$EDITOR"
  print -r -- "WHENCE_FUNCTIONS=$(whence -w functions)"
  print -r -- "WHENCE_PATH=$(whence -w path 2>/dev/null)"
  print -r -- "WHENCE_ALIASES=$(whence -w aliases 2>/dev/null)"
  typeset -a _u _d
  _u=(${(u)path}); _d=(${(M)path:#*/../*})
  print -r -- "PATH_ENTRIES=${#path}"
  print -r -- "PATH_UNIQUE=${#_u}"
  print -r -- "PATH_DOTDOT=${#_d}"
  print -r -- "POST_HOOK=${DOTFILES_POST_HOOK_RAN:-<unset>}"
  print -r -- "HOST=$DOTFILES_TERM_HOST"
  print -r -- "COMPINIT_CALLS=$(zprof | awk "\$NF == \"compinit\" {print \$2; exit}")"
  print -r -- "COMPDEF=$+functions[compdef]"
  print -r -- "ALIAS_G=$(whence -w g)"
  print -r -- "FUNC_DATAURL=$(whence -w dataurl)"
  print -r -- "ZOXIDE=$(whence -w z)"
'
# The prompt: the Starship hook or "none", whether Powerlevel10k defined
# itself, and the theme prezto was asked for.
PROMPT_STATE='print -r -- "PROMPT=${precmd_functions[(r)prompt_starship_precmd]:-none} p10k=$+functions[p10k] theme=$(zstyle -s ":prezto:module:prompt" theme t && print -r -- $t)"'
# Prezto modules marked loaded: the four line-editor ones, whether their
# widgets' functions exist, and the other thirteen. "none" when empty, so a
# missing line cannot pass for an empty one.
ZLE_STATE='
  _m=(); for _p in editor syntax-highlighting history-substring-search autosuggestions; do
    zstyle -t ":prezto:module:$_p" loaded && _m+=($_p); done
  print -r -- "ZLE_MODULES=${_m:-none}"
  print -r -- "ZLE_FUNCS=$+functions[_zsh_autosuggest_start]$+functions[_zsh_highlight]"
  _m=(); for _p in environment terminal history directory spectrum utility git homebrew osx ssh python completion prompt; do
    zstyle -t ":prezto:module:$_p" loaded && _m+=($_p); done
  print -r -- "CORE_MODULES=${_m:-none}"
'
# Key bindings and atuin.
KEY_STATE='
  print -r -- "KEY_R=$(bindkey "^R")"
  print -r -- "KEY_TAB=$(bindkey "^I")"
  print -r -- "KEY_T=$(bindkey "^T")"
  print -r -- "ATUIN_HOOK=${precmd_functions[(r)_atuin_precmd]:-none}"
  print -r -- "ATUIN_ARGS=${ATUIN_STUB_ARGS:-none}"
'
PROBE_CODE="$ENV_STATE
$PROMPT_STATE
$ZLE_STATE
$KEY_STATE"

PROBE_DIR=$(sandbox)
for _host in rich warp dumb; do
  ZSHRUN_TERM_HOST=$_host ZSHRUN_ENV=DOTFILES_TEST_ZPROF=1 zshrun "$PROBE_CODE" \
    >"$PROBE_DIR/$_host.env" 2>/dev/null
done
unset _host

pv() { sed -n "s/^$1=//p" "$PROBE_DIR/${2:-rich}.env"; }

# Wall time is useless as a gate on a machine running two dozen agents, so the
# startup budget is measured in CPU (user+sys), which load does not inflate.
login_shell_cpu_ms() {
  local h o
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  _zsh_login "$h" true >/dev/null 2>&1   # warm the caches
  # The environment of _zsh_login, spelled out: /usr/bin/time needs a
  # program, not a shell function.
  o=$( { /usr/bin/time -p env -u LC_ALL -u TERM_PROGRAM -u DOTFILES_TERM_HOST \
           HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" PATH="$h/.stubs:$PATH" \
           DOTFILES_TERM_HOST="${ZSHRUN_TERM_HOST-rich}" \
           zsh -l -i -c true </dev/null; } 2>&1 >/dev/null )
  printf '%s\n' "$o" | awk '/^(user|sys)/ {s += $2} END {printf "%d", s * 1000}'
}

section "C0 — a login shell starts silently"
t "C0.1" "login shell prints only the command output" \
  '[ "$(zshrun_all "echo ok")" = ok ]'
t "C0.2" "prezto draws no prompt in any host: one theme line, and it is off" \
  '[ "$(code_of runcom/.zpreztorc | grep -c "prezto:module:prompt. theme")" -eq 1 ] &&
   [ "$(code_of runcom/.zpreztorc | grep -c "prezto:module:prompt. theme .off.")" -eq 1 ]'
t "C0.3" "fzf key bindings load on a real rich terminal only" \
  'bound_to "$(pty_zshrun "$KEY_STATE" | sed -n "s/^KEY_T=//p")" fzf-stub-widget &&
   bound_elsewhere "$(ZSHRUN_ENV=TERM_PROGRAM=WarpTerminal pty_zshrun "$KEY_STATE" | sed -n "s/^KEY_T=//p")" fzf-stub-widget &&
   bound_elsewhere "$(pv KEY_T rich)" fzf-stub-widget'

section "C1 — history, compdump, dircolors, load order"
t "C1.1" "HISTSIZE is 32768 in a login shell" \
  '[ "$(pv HISTSIZE)" = 32768 ]'
t "C1.2" "SAVEHIST is 32768" \
  '[ "$(pv SAVEHIST)" = 32768 ]'
t "C1.3" ".zlogin compiles the prezto dump" \
  'grep -q "prezto/zcompdump" runcom/.zlogin'
t "C1.4" "a shell under a TERM with no dircolors entry cannot poison the next one" \
  'H=$(_zsh_sandbox) && TERM=dumb ZSHRUN_HOME="$H" zshrun true >/dev/null 2>&1;
   [ "$(TERM=xterm-256color ZSHRUN_HOME="$H" zshrun "echo \${#LS_COLORS}")" -gt 500 ]'
t "C1.5" "dircolors cache is keyed on TERM or not cached" \
  '[ "$(grep -c "dircolors" runcom/.profile)" -eq 0 ] || grep -q "TERM" runcom/.profile'
t "C1.6" "autosuggest style is not empty in a rich terminal" \
  '[ -n "$(pv AUTOSUGGEST)" ]'
t "C1.7" ".env is sourced before .path" \
  'grep -q "\.{env,function" runcom/.profile'
t "C1.8" "LC_ALL is not exported" \
  '[ "$(grep -c "export LC_ALL" system/.env)" -eq 0 ] && [ "$(pv LC_ALL)" = "<unset>" ]'
t "C1.9" "LC_CTYPE is UTF-8 in a login shell" \
  '[ "$(pv LC_CTYPE)" = en_US.UTF-8 ]'

section "C2 — aliases, completion, PATH"
t "C2.1" "the functions builtin is not shadowed by an alias" \
  '[ "$(pv WHENCE_FUNCTIONS)" = "functions: builtin" ]'
t "C2.1b" "path and aliases are not shadowed by aliases" \
  '[ "$(pv WHENCE_PATH)" = "path: none" ] && [ "$(pv WHENCE_ALIASES)" = "aliases: none" ]'
t "C2.2" "dotfiles completion lists the commands that exist today" \
  '( for c in cheatsheet doctor hooks profiler secrets setup test baseline; do
       grep -q "$c" system/.completion || exit 1
     done ) && [ "$(grep -cE "\bdock\b|\bmacos\b" system/.completion)" -eq 0 ]'
t "C2.3" "vendored _fnm removed" \
  '[ ! -e completions/_fnm ]'
t "C2.4" "PATH has no duplicate entries in a login shell" \
  '[ -n "$(pv PATH_ENTRIES)" ] && [ "$(pv PATH_ENTRIES)" = "$(pv PATH_UNIQUE)" ]'
t "C2.5" "PATH entries are normalised (no /../)" \
  '[ "$(pv PATH_DOTDOT)" = 0 ]'
t "C2.6" "cache writes use >| so they survive noclobber" \
  '[ "$(code_of system/.path system/.fzf system/.pay-respects system/.completion |
        grep -cF -e '"'"'> "$_'"'"')" -eq 0 ]'
t "C2.7" "npm completion is guarded and stale-checked" \
  'grep -q "commands\[npm\]" system/.completion && grep -q -- "-nt " system/.completion'
t "C2.8" "dataurl text pattern is unquoted" \
  '[ "$(grep -cF -e '"'"'"text/*"'"'"' system/.function_fs)" -eq 0 ]'
t "C2.8b" "dataurl tags a text file with a charset" \
  'f=$(sandbox)/a.txt; printf hello >"$f";
   case "$(zshrun "dataurl $f")" in *charset=utf-8*) true ;; *) false ;; esac'
t "C2.9" "no Intel prefix branch in system/.path" \
  '[ "$(grep -c "/usr/local/bin/brew" system/.path)" -eq 0 ]'
t "C2.10" "weather() fetches over https" \
  'grep -q "https://wttr.in" system/.function'
t "C2.11" "ipinfo() fetches over https" \
  'grep -q "https://ipinfo.io" system/.function_network'
t "C2.12" "the ip alias fetches over https" \
  'grep -q "https://ipinfo.io" system/.alias'
t "C2.13" "srv() drives a webserver that is actually installed" \
  '[ "$(code_of system/.function_network | grep -c superstatic)" -eq 0 ]'

section "C3 — keys, locale, prezto config"
t "C3.1" "KEYTIMEOUT is 1" \
  '[ "$(pv KEYTIMEOUT)" = 1 ]'
t "C3.2" "no chruby zstyle without the ruby module" \
  '[ "$(grep -c "ruby:chruby" runcom/.zpreztorc)" -eq 0 ]'
t "C3.3" "pmodule-dirs no longer lists prezto-contrib or modules/zsh" \
  '[ "$(grep -cE "prezto-contrib|modules/zsh" runcom/.zpreztorc)" -eq 0 ]'
t "C3.4" "histsize zstyle present" \
  'grep -q "module:history. histsize" runcom/.zpreztorc'
t "C3.5" "terminfo lookups cannot silently bind an empty key" \
  '[ "$(code_of system/.bindings |
        grep -cF -e '"'"'bindkey "$terminfo'"'"' -e '"'"'bindkey "${terminfo'"'"')" -eq 0 ]'

section "C4 — post-profile hook and EDITOR"
t "C4.1" ".zshrc sources local.post.zsh after prezto" \
  'awk "/prezto\/init.zsh/{p=1} p && /local.post.zsh/{f=1} END{exit !f}" runcom/.zshrc'
t "C4.2" "EDITOR prefers nvim when present" \
  'grep -q "commands\[nvim\]" system/.editor'
t "C4.2b" "system/.editor picks nvim when it is on PATH, vim when it is not" \
  'd=$(sandbox); printf "#!/bin/sh\\nexit 0\\n" >"$d/nvim"; chmod +x "$d/nvim";
   [ "$(editor_isolated "$d" /usr/bin:/bin)" = vim ] &&
   [ "$(editor_isolated "$d" "$d:/usr/bin:/bin")" = nvim ]'
t "C4.2c" "EDITOR finds an nvim that only system/.path puts on PATH" \
  'H=$(_zsh_sandbox); write_nvim_stub "$H";
   [ "$(editor_through_profile "$H")" = nvim ]'
t "C4.3" "README documents local.post.zsh" \
  'grep -q "local.post.zsh" profiles/README.md'
t "C4.4" "the post-profile hook runs, and compdef exists by then" \
  '[ "$(pv POST_HOOK)" = with-compdef ]'
t "C4.5" "personal.zsh.example shows a lazy secret accessor" \
  'grep -q "dotfiles-secrets get" profiles/personal.zsh.example'
t "C4.6" "the README does not tell users to source path.zsh.inc from a post hook" \
  '[ "$(grep -cE "^[[:space:]]*([.]|source) .*path[.]zsh[.]inc" profiles/README.md)" -eq 0 ] &&
   grep -q "path.zsh.inc" profiles/README.md'

section "C5 — pay-respects replaces thefuck; mackup config removed"
t "C5.1" "thefuck init is gone" \
  '[ ! -e system/.thefuck ] && [ "$(grep -c thefuck runcom/.profile)" -eq 0 ]'
t "C5.2" "pay-respects is guarded" \
  'grep -q "commands\[pay-respects\]" system/.pay-respects'
t "C5.3" "mackup cfg removed" \
  '[ ! -e runcom/.mackup.cfg ]'
t "C5.4" "a login shell defines the fix alias when pay-respects is installed" \
  'H=$(_zsh_sandbox);
   printf "#!/bin/sh\necho alias fix=true\n" >"$H/.stubs/pay-respects";
   chmod +x "$H/.stubs/pay-respects";
   [ "$(ZSHRUN_HOME="$H" zshrun "whence -w fix")" = "fix: alias" ]'
t "C5.5" "a login shell without pay-respects still starts silently" \
  '[ "$(zshrun_all "echo ok")" = ok ]'

section "C6 — fzf-tab and atuin"
t "C6.1" "fzf-tab is sourced after prezto, in rich terminals only" \
  '[ "$(_first_line fzf-tab.plugin.zsh runcom/.zshrc)" -gt "$(_first_line prezto/init.zsh runcom/.zshrc)" ] &&
   bound_elsewhere "$(pv KEY_TAB warp)" fzf-tab-complete &&
   bound_elsewhere "$(pv KEY_TAB dumb)" fzf-tab-complete'
t "C6.2" "atuin init is guarded, and Warp gets its recording hooks without bindings" \
  '[ "$(code_of system/.atuin | grep -c "commands\[atuin\]")" -eq 1 ] &&
   [ "$(pv ATUIN_HOOK warp)" = _atuin_precmd ] &&
   a=" $(pv ATUIN_ARGS warp) " &&
   case "$a" in *" --disable-ctrl-r "*) ;; *) false ;; esac &&
   case "$a" in *" --disable-ai "*) ;; *) false ;; esac'
t "C6.3" "a login shell stays under 600 ms of CPU" \
  'ms=$(login_shell_cpu_ms); [ -n "$ms" ] && [ "$ms" -gt 0 ] && [ "$ms" -lt 600 ]'
t "C6.4" "ctrl-R reaches atuin in a rich terminal, and not in Warp" \
  'bound_to "$(pv KEY_R rich)" atuin-stub-viins &&
   bound_elsewhere "$(pv KEY_R warp)" atuin-stub-viins'
t "C6.5" "tab reaches fzf-tab in a rich terminal" \
  'bound_to "$(pv KEY_TAB rich)" fzf-tab-complete'
t "C6.6" "key-binding plugins load after prezto, which runs bindkey -d" \
  'awk "/prezto\/init.zsh/{p=1} p && /system\/.fzf/{f=1} p && /system\/.atuin/{a=1}
        END{exit !(f && a)}" runcom/.zshrc &&
   [ "$(grep -cE "system/[.](fzf|atuin)" runcom/.profile)" -eq 0 ]'

section "H0 — every host starts silently, with completion and the environment"
t "H0.1" "every host starts silently" \
  '[ "$(ZSHRUN_TERM_HOST=rich zshrun_all "echo ok")" = ok ] &&
   [ "$(ZSHRUN_TERM_HOST=warp zshrun_all "echo ok")" = ok ] &&
   [ "$(ZSHRUN_TERM_HOST=dumb zshrun_all "echo ok")" = ok ] &&
   [ "$(pty_zshrun "echo ok")" = ok ] &&
   [ "$(ZSHRUN_ENV=TERM_PROGRAM=WarpTerminal pty_zshrun "echo ok")" = ok ]'
t "H0.2" "every host runs compinit exactly once" \
  '[ "$(pv COMPINIT_CALLS rich)" = 1 ] && [ "$(pv COMPINIT_CALLS warp)" = 1 ] &&
   [ "$(pv COMPINIT_CALLS dumb)" = 1 ]'
t "H0.3" "every host has aliases, functions, compdef, zoxide and the post-profile hook" \
  '( for h in rich warp dumb; do
       [ "$(pv ALIAS_G $h)" = "g: alias" ] && [ "$(pv FUNC_DATAURL $h)" = "dataurl: function" ] &&
       [ "$(pv COMPDEF $h)" = 1 ] && [ "$(pv ZOXIDE $h)" = "z: function" ] &&
       [ "$(pv POST_HOOK $h)" = with-compdef ] || exit 1
     done )'
t "H0.4" "every host gets the same PATH" \
  '[ -n "$(pv PATH_ENTRIES rich)" ] &&
   [ "$(pv PATH_ENTRIES warp)" = "$(pv PATH_ENTRIES rich)" ] &&
   [ "$(pv PATH_ENTRIES dumb)" = "$(pv PATH_ENTRIES rich)" ]'

section "H1 — host classification (system/.term_host)"
t "H1.0" "ptyrun gives a test a terminal" \
  '[ "$(ptyrun zsh -f -c "[[ -t 0 ]] && print -r -- TTY=yes" | sed -n "s/^TTY=//p")" = yes ]'
t "H1.1" "Warp on a terminal is warp" \
  '[ "$(pty_term_host_of TERM_PROGRAM=WarpTerminal)" = warp:scalar ]'
t "H1.2" "a terminal that sets no TERM_PROGRAM is rich (JetBrains sets none)" \
  '[ "$(pty_term_host_of)" = rich:scalar ]'
t "H1.3" "an unrecognised terminal is rich" \
  '[ "$(pty_term_host_of TERM_PROGRAM=SomeTerminalFrom2030)" = rich:scalar ]'
t "H1.4" "tmux is rich, even inside Warp: it sets TERM_PROGRAM itself" \
  '[ "$(pty_term_host_of TERM_PROGRAM=tmux)" = rich:scalar ]'
t "H1.5" "no terminal is dumb, even under Warp (an agent's zsh -l -i -c)" \
  '[ "$(term_host_of TERM_PROGRAM=WarpTerminal)" = dumb:scalar ] &&
   [ "$(term_host_of)" = dumb:scalar ]'
t "H1.6" "a value already set wins over detection" \
  '[ "$(term_host_of TERM_PROGRAM=WarpTerminal DOTFILES_TERM_HOST=rich | cut -d: -f1)" = rich ] &&
   [ "$(pty_term_host_of DOTFILES_TERM_HOST=dumb | cut -d: -f1)" = dumb ]'
t "H1.7" "an unknown value is discarded, and the detected class is not exported" \
  '[ "$(pty_term_host_of TERM_PROGRAM=WarpTerminal DOTFILES_TERM_HOST=fancy)" = warp:scalar ]'
t "H1.8" ".zshrc classifies before prezto reads .zpreztorc" \
  '[ "$(_first_line system/.term_host runcom/.zshrc)" -gt 0 ] &&
   [ "$(_first_line system/.term_host runcom/.zshrc)" -lt "$(_first_line prezto/init.zsh runcom/.zshrc)" ]'
t "H1.9" "a login shell classifies itself" \
  '[ "$(ZSHRUN_TERM_HOST= ZSHRUN_ENV=TERM_PROGRAM=WarpTerminal zshrun "print -r -- \$DOTFILES_TERM_HOST")" = dumb ] &&
   [ "$(ZSHRUN_ENV=TERM_PROGRAM=WarpTerminal pty_zshrun "print -r -- HOST=\$DOTFILES_TERM_HOST" | sed -n "s/^HOST=//p")" = warp ]'

section "H2 — Starship replaces Powerlevel10k"
t "H2.1" "a real terminal gets Starship, and prezto draws no prompt" \
  '[ "$(pty_zshrun "$PROMPT_STATE" | sed -n "s/^PROMPT=//p")" = "prompt_starship_precmd p10k=0 theme=off" ]'
t "H2.2" "Warp gets no prompt at all" \
  '[ "$(ZSHRUN_ENV=TERM_PROGRAM=WarpTerminal pty_zshrun "$PROMPT_STATE" | sed -n "s/^PROMPT=//p")" = "none p10k=0 theme=off" ]'
t "H2.3" "the pinned hosts agree: Starship in rich, nothing in warp or dumb" \
  '[ "$(pv PROMPT rich)" = "prompt_starship_precmd p10k=0 theme=off" ] &&
   [ "$(pv PROMPT warp)" = "none p10k=0 theme=off" ] &&
   [ "$(pv PROMPT dumb)" = "none p10k=0 theme=off" ]'
t "H2.4" "no Powerlevel10k anywhere in the login path" \
  '[ "$(code_of runcom/.zshrc runcom/.zpreztorc system/.starship | grep -ciE "p10k|powerlevel|system/[.]prompt|DEFAULT_USER")" -eq 0 ]'
t "H2.5" "Starship is sourced after prezto, whose zle-keymap-select it wraps" \
  '[ "$(_first_line system/.starship runcom/.zshrc)" -gt "$(_first_line prezto/init.zsh runcom/.zshrc)" ]'
t "H2.6" "no doc still names Powerlevel10k as the prompt" \
  '[ "$(cat README.md AGENTS.md docs/agents/*.md | grep -ciE "powerlevel|p10k")" -eq 0 ]'

section "H3 — prezto's line-editor modules load in rich terminals only"
t "H3.1" "a rich terminal loads all four, and their widgets exist" \
  '[ "$(pv ZLE_MODULES rich)" = "editor syntax-highlighting history-substring-search autosuggestions" ] &&
   [ "$(pv ZLE_FUNCS rich)" = 11 ]'
t "H3.2" "Warp and a shell with no terminal load none of them" \
  '( for h in warp dumb; do
       [ "$(pv ZLE_MODULES $h)" = none ] && [ "$(pv ZLE_FUNCS $h)" = 00 ] || exit 1
     done )'
t "H3.3" "every host loads the other thirteen modules" \
  '( for h in rich warp dumb; do
       [ "$(pv CORE_MODULES $h)" = "environment terminal history directory spectrum utility git homebrew osx ssh python completion prompt" ] || exit 1
     done )'

section "H4 — key bindings and atuin, per host"
t "H4.1" "a shell with no terminal loads no atuin at all" \
  '[ "$(pv ATUIN_HOOK dumb)" = none ] && [ "$(pv ATUIN_ARGS dumb)" = none ]'
t "H4.2" "a rich terminal keeps atuin exactly as before" \
  '[ "$(pv ATUIN_ARGS rich)" = "init zsh --disable-up-arrow" ] &&
   [ "$(pv ATUIN_HOOK rich)" = _atuin_precmd ]'
t "H4.3" ".bindings loads in rich terminals only" \
  '[ "$(pv KEYTIMEOUT rich)" = 1 ] &&
   [ -n "$(pv KEYTIMEOUT warp)" ] && [ "$(pv KEYTIMEOUT warp)" != 1 ] &&
   [ -n "$(pv KEYTIMEOUT dumb)" ] && [ "$(pv KEYTIMEOUT dumb)" != 1 ]'

section "H5 — Powerlevel10k retired"
t "H5.1" "the Powerlevel10k config is gone" \
  '[ ! -e system/.prompt ]'

finish

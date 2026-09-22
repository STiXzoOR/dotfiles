#!/usr/bin/env bash
#
# tests/shell.sh -- regression tests for the 2026-09-21 audit, shell workstream.
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
  local s
  for s in ssh-add ssh-agent ${ZSHRUN_STUBS:-}; do
    printf '#!/bin/sh\nexit 0\n' >"$h/.stubs/$s"
    chmod +x "$h/.stubs/$s"
  done
  printf '%s' "$h"
}

# zshrun <zsh code> -- run it in the sandbox, print stdout, discard stderr.
# Set ZSHRUN_HOME to an existing sandbox to reuse it, so that two shells can
# run in sequence against the same caches.
zshrun() {
  local h
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  env -u LC_ALL HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" \
    PATH="$h/.stubs:$PATH" zsh -l -i -c "$1" 2>/dev/null
}

# zshrun_all <zsh code> -- same, but stderr is merged into stdout so that
# startup noise shows up in the result.
zshrun_all() {
  local h
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  env -u LC_ALL HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" \
    PATH="$h/.stubs:$PATH" zsh -l -i -c "$1" 2>&1
}

# A stub atuin whose `init zsh` output binds ctrl-R the way the real one does.
# C6.4 has to measure this repo's load order, not whether the host happens to
# have atuin: the CI macOS runner installs only shellcheck, coreutils and
# gitleaks.
write_atuin_stub() {
  cat >"$1/.stubs/atuin" <<'STUBEOF'
#!/bin/sh
cat <<'ZSHEOF'
atuin-stub-viins() { :; }
zle -N atuin-stub-viins
bindkey -M viins "^r" atuin-stub-viins
bindkey -M emacs "^r" atuin-stub-viins
ZSHEOF
STUBEOF
  chmod +x "$1/.stubs/atuin"
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
# One login shell answers most of the questions this suite asks. Starting a
# shell per assertion costs seconds on a loaded machine, so the values are
# collected once here and read back with pv.
# ---------------------------------------------------------------------------

PROBE_FILE=$(sandbox)/probe.env
zshrun '
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
' >"$PROBE_FILE" 2>/dev/null

pv() { sed -n "s/^$1=//p" "$PROBE_FILE"; }

# Wall time is useless as a gate on a machine running two dozen agents, so the
# startup budget is measured in CPU (user+sys), which load does not inflate.
login_shell_cpu_ms() {
  local h o
  h=${ZSHRUN_HOME:-$(_zsh_sandbox)} || return 1
  env -u LC_ALL HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" \
    PATH="$h/.stubs:$PATH" zsh -l -i -c true >/dev/null 2>&1   # warm the caches
  o=$( { /usr/bin/time -p env -u LC_ALL HOME="$h" ZDOTDIR="$h" \
           XDG_CACHE_HOME="$h/.cache" PATH="$h/.stubs:$PATH" \
           zsh -l -i -c true; } 2>&1 >/dev/null )
  printf '%s\n' "$o" | awk '/^(user|sys)/ {s += $2} END {printf "%d", s * 1000}'
}

section "C0 — a login shell starts silently"
t "C0.1" "login shell prints only the command output" \
  '[ "$(zshrun_all "echo ok")" = ok ]'
t "C0.2" "prompt theme is off when there is no terminal" \
  'grep -q "prezto:module:prompt. theme .off." runcom/.zpreztorc'
t "C0.3" "fzf keybindings are only loaded with a terminal" \
  'grep -q -- "-t 0" system/.fzf'

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
t "C1.6" "autosuggest style is not empty" \
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
t "C6.1" "fzf-tab is sourced after prezto when present" \
  'grep -q "fzf-tab/fzf-tab.plugin.zsh" runcom/.zshrc'
t "C6.2" "atuin init is guarded" \
  'grep -q "commands\[atuin\]" system/.atuin'
t "C6.3" "a login shell stays under 600 ms of CPU" \
  'ms=$(login_shell_cpu_ms); [ -n "$ms" ] && [ "$ms" -gt 0 ] && [ "$ms" -lt 600 ]'
t "C6.4" "ctrl-R reaches atuin in a login shell" \
  'H=$(_zsh_sandbox); write_atuin_stub "$H";
   [ "$(ZSHRUN_HOME="$H" zshrun "bindkey \"^R\"")" = "\"^R\" atuin-stub-viins" ]'
t "C6.5" "tab reaches fzf-tab in a login shell" \
  'case "$(zshrun "bindkey \"^I\"")" in *fzf-tab*) true ;; *) false ;; esac'
t "C6.6" "key-binding plugins load after prezto, which runs bindkey -d" \
  'awk "/prezto\/init.zsh/{p=1} p && /system\/.fzf/{f=1} p && /system\/.atuin/{a=1}
        END{exit !(f && a)}" runcom/.zshrc &&
   [ "$(grep -cE "system/[.](fzf|atuin)" runcom/.profile)" -eq 0 ]'

finish

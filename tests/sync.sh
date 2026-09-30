#!/usr/bin/env bash
#
# tests/sync.sh -- Task 7 of the 2026-09-29 new-Mac readiness work: the machine
# role, `dotfiles sync`, the daily sync agent and the vault in iCloud Drive.
#
# HERMETIC. Every run uses a sandbox HOME, a sandbox stand-in for iCloud Drive
# (DOTFILES_VAULT_ICLOUD), bare git remotes created inside the sandbox, and
# stubs on a sandbox PATH for stow, brew, mise, mas, code, osascript, pmset,
# scutil, brctl, pgrep, sudo, gh, security and ditto (where a failure is being
# simulated) that log their argv. Nothing here reaches the real machine, the
# real iCloud Drive, the real private repo or launchd.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# SYNC_ONLY="S V": run only the tests whose id starts with one of these
# (the git-heavy S tests are slow on a busy machine).
if [ -n "${SYNC_ONLY:-}" ]; then
  eval "$(declare -f t | sed '1s/^t /_t_real /')"
  t() { local p; for p in $SYNC_ONLY; do case "$1" in "$p"*) _t_real "$@"; return ;; esac; done; }
fi

# stub <bindir> <name> [body]: an executable that logs "<name> <argv>" to
# $STUB_LOG and then runs body.
stub() {
  mkdir -p "$1"
  { printf '#!/bin/bash\n'
    printf 'printf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n' "$2"
    printf '%s\n' "${3:-}"
  } >"$1/$2"
  chmod +x "$1/$2"
}

#############################################################################
section "M -- machine role and name (scripts/lib/machine.sh)"
#############################################################################
# role_of <pmset-output|-> [VAR=val ...]: the role with a stub pmset printing
# the given text (or a pmset that fails when "-").
role_of() {
  local w out="$1"; shift
  w=$(sandbox); mkdir -p "$w/bin"; : >"$w/log"
  if [ "$out" = - ]; then stub "$w/bin" pmset 'exit 1'; else stub "$w/bin" pmset 'printf "%s\n" "${STUB_BATT:-}"'; fi
  env -i HOME="$w" PATH="$w/bin:/usr/bin:/bin" STUB_LOG="$w/log" STUB_BATT="$out" "$@" \
    /bin/bash -c 'source "$1/scripts/lib/machine.sh"; dotfiles_machine_role' _ "$ROOT_DIR"
}
BATT="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234)	87%; discharging; 4:10 remaining present: true"
AC="Now drawing from 'AC Power'"

t "M1.1" "no InternalBattery in pmset -g batt is a desktop" \
  '[ "$(role_of "$AC")" = desktop ]'
t "M1.2" "an InternalBattery is a laptop" \
  '[ "$(role_of "$BATT")" = laptop ]'
t "M1.3" "DOTFILES_MACHINE_ROLE overrides the detection either way" \
  '[ "$(role_of "$AC" DOTFILES_MACHINE_ROLE=laptop)" = laptop ] && [ "$(role_of "$BATT" DOTFILES_MACHINE_ROLE=desktop)" = desktop ]'
t "M1.4" "an override that is neither desktop nor laptop is ignored" \
  '[ "$(role_of "$BATT" DOTFILES_MACHINE_ROLE=server)" = laptop ]'
t "M1.5" "pmset missing: the conservative answer (laptop) so nothing power-related is forced" \
  '[ "$(role_of -)" = laptop ]'
t "M1.7" "pmset exiting 0 with empty output is a laptop (no positive desktop marker)" \
  '[ "$(role_of "")" = laptop ]'
t "M1.8" "garbled pmset output is a laptop" \
  '[ "$(role_of "garbage ?? 42")" = laptop ]'
t "M1.9" "Now drawing from without an InternalBattery is a desktop; with one it is a laptop" \
  '[ "$(role_of "Now drawing from Something")" = desktop ] && [ "$(role_of "Now drawing from Battery Power
 -InternalBattery-0")" = laptop ]'
t "M1.10" "an invalid DOTFILES_MACHINE_ROLE warns once and falls back to detection" \
  'o=$(role_of "$AC" DOTFILES_MACHINE_ROLE=Desktop 2>&1); [ "$(printf "%s\n" "$o" | grep -c "DOTFILES_MACHINE_ROLE")" -eq 1 ] && [ "$(printf "%s\n" "$o" | tail -1)" = desktop ] &&
   o=$(role_of "$BATT" DOTFILES_MACHINE_ROLE=Desktop 2>&1) && [ "$(printf "%s\n" "$o" | tail -1)" = laptop ]'
t "M1.6" "the role is asked of pmset -g batt" \
  'W=$(sandbox); mkdir -p "$W/bin"; : >"$W/log"; stub "$W/bin" pmset "echo AC"
   env -i HOME="$W" PATH="$W/bin:/usr/bin:/bin" STUB_LOG="$W/log" /bin/bash -c "source scripts/lib/machine.sh; dotfiles_machine_role" >/dev/null
   grep -qx "pmset -g batt" "$W/log"'

# name_of [VAR=val ...]: the machine name with a stub scutil printing $HOST.
name_of() {
  local w; w=$(sandbox); mkdir -p "$w/bin"; : >"$w/log"
  stub "$w/bin" scutil 'printf "%s\n" "${HOST-}"'
  env -i HOME="$w" PATH="$w/bin:/usr/bin:/bin" STUB_LOG="$w/log" "$@" \
    /bin/bash -c 'source "$1/scripts/lib/machine.sh"; dotfiles_machine_name' _ "$ROOT_DIR"
}
t "M2.1" "DOTFILES_MACHINE_NAME wins" \
  '[ "$(name_of DOTFILES_MACHINE_NAME=mini HOST=other)" = mini ]'
t "M2.2" "LocalHostName is sanitised to [A-Za-z0-9-]" \
  '[ "$(name_of "HOST=My Mac_mini.local")" = "My-Mac-mini-local" ]'
t "M2.3" "no name at all is an error naming the override" '
  out=$(name_of HOST= 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c DOTFILES_MACHINE_NAME)" -ge 1 ]'
t "M2.4" "dotfiles-apps uses the shared helper, not its own copy" '
  [ "$(code_of bin/dotfiles-apps | grep -c "scutil")" -eq 0 ] &&
  [ "$(code_of bin/dotfiles-apps | grep -c "lib/machine.sh")" -ge 1 ]'

#############################################################################
section "S -- dotfiles sync (bin/dotfiles-sync)"
#############################################################################
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# _mkrepo <W> <name> <file:content>...: bare remote <name>.git, a checkout
# <name> with one commit holding the files, pushed with upstream set.
_mkrepo() {
  local w="$1" n="$2" f; shift 2
  git init -q --bare -b main "$w/$n.git" &&
  git clone -q "$w/$n.git" "$w/$n" 2>/dev/null || return 1
  for f in "$@"; do mkdir -p "$w/$n/$(dirname "${f%%:*}")"; printf '%s\n' "${f#*:}" >"$w/$n/${f%%:*}"; done
  git -C "$w/$n" checkout -q -b main 2>/dev/null
  git -C "$w/$n" add -A && git -C "$w/$n" commit -q -m init && git -C "$w/$n" push -q -u origin main 2>/dev/null
}
# senv: a sandbox with a public and a private repo (each with a bare remote), a
# HOME, stubs and package state. Prints the path.
senv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home" "$w/bin" "$w/state"; : >"$w/log"
  _mkrepo "$w" pub "Brewfile:brew \"wget\"
cask \"iterm2\"
mas \"Xcode\", id: 497799835" "config/mise/config.toml:[tools]" "claude/rules.md:r" "packages/code.list:ms-python.python" "README.md:r" "runcom/.zshrc:z" || return 1
  _mkrepo "$w" priv "macos/local.sh:DOTFILES_LOCALE=en_GB" "Brewfile.local:brew \"fzf\"" || return 1
  cp "$w/priv/Brewfile.local" "$w/pub/Brewfile.local"
  local n
  for n in stow mise sudo osascript dotfiles-stub; do stub "$w/bin" "$n" ':'; done
  stub "$w/bin" mas 'case "$1" in list) cat "$STUB_STATE/mas" 2>/dev/null ;; esac'
  stub "$w/bin" code 'case "$1" in --list-extensions) cat "$STUB_STATE/vscode" 2>/dev/null ;; esac'
  stub "$w/bin" brew 'case "$*" in
  "leaves --installed-on-request") cat "$STUB_STATE/leaves" 2>/dev/null ;;
  "list --cask -1") cat "$STUB_STATE/casks" 2>/dev/null ;;
  "desc "*) n="${!#}"; printf "%s: Description of %s\n" "$n" "$n" ;;
  "uses --installed "*) cat "$STUB_STATE/uses-$3" 2>/dev/null ;;
  "bundle check"*) [ -f "$STUB_STATE/unsatisfied" ] && exit 1 ;;
esac
exit 0'
  printf 'wget\nfzf\n' >"$w/state/leaves"; printf 'iterm2\n' >"$w/state/casks"
  printf '497799835  Xcode  (16.0)\n' >"$w/state/mas"; printf 'ms-python.python\n' >"$w/state/vscode"
  printf '%s' "$w"
}
# push_change <W> <pub|priv> <file> <content>: a commit from "the other Mac".
push_change() {
  local w="$1" n="$2" c
  c=$(sandbox); git clone -q "$w/$n.git" "$c/x" 2>/dev/null
  mkdir -p "$c/x/$(dirname "$3")"; printf '%s\n' "$4" >"$c/x/$3"
  git -C "$c/x" add -A && git -C "$c/x" commit -q -m change && git -C "$c/x" push -q origin main 2>/dev/null
}
# syn <args>: dotfiles-sync against the sandbox in $W; $SYNENV adds VAR=val
# pairs (no spaces); stdin is closed, so an unanswered confirm is a "no".
syn() {
  # shellcheck disable=SC2086
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/pub" DOTFILES_PRIVATE_DIR="$W/priv" \
    DOTFILES_BIN="$W/bin/dotfiles-stub" XDG_CONFIG_HOME="$W/home/.config" STUB_LOG="$W/log" STUB_STATE="$W/state" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid DOTFILES_JEV=off \
    ${SYNENV:-} bash "$ROOT_DIR/bin/dotfiles-sync" "$@" </dev/null
}
sy_env() { local SYNENV="$1"; shift; "$@"; }
_calls() { grep -c -- "$1" "$W/log"; }
_head() { git -C "$W/$1" rev-parse HEAD; }
_remote() { git -C "$W/$1.git" rev-parse main; }

t "S1.1" "behind and clean: fast-forwards the public repo" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ] && [ "$(command cat "$W/pub/README.md")" = new ]'
t "S1.2" "after a move both stow packages are simulated first, then restowed, ignoring .DS_Store" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1
   grep -qxF -- "stow -n --restow --ignore=\\.DS_Store\$ -t $W/home runcom" "$W/log" &&
   grep -qxF -- "stow -n --restow --ignore=\\.DS_Store\$ -t $W/home/.config config" "$W/log" &&
   grep -qxF -- "stow --restow --ignore=\\.DS_Store\$ -t $W/home runcom" "$W/log" &&
   grep -qxF -- "stow --restow --ignore=\\.DS_Store\$ -t $W/home/.config config" "$W/log"'
t "S1.2b" "the simulation runs before any real stow" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1
   [ "$(grep "^stow" "$W/log" | sed -n "1p;2p" | grep -c -- "^stow -n")" -eq 2 ]'
t "S1.2c" "a conflict in the simulation: no real stow, the attention item is recorded, the run carries on" '
  W=$(senv); push_change "$W" pub README.md new
  stub "$W/bin" stow "case \"\$*\" in -n*) printf \"WARNING! stowing runcom would cause conflicts:\\n  * cannot stow x/.zshrc over existing target .zshrc since neither a link nor a directory\\n\"; exit 1;; esac"
  syn --scheduled >/dev/null 2>&1; [ "$(_calls "^stow --restow")" -eq 0 ] &&
  grep -q "^osascript .*stow conflict: cannot stow x/.zshrc over existing target .zshrc.* -- run dotfiles link" "$W/log" &&
  [ -L "$W/pub/macos/local.sh" ]'
t "S1.2d" "a conflict leaves the existing links exactly as they were (real stow)" '
  command -v stow >/dev/null 2>&1 || return 0
  W=$(senv); real=$(command -v stow); rm "$W/bin/stow"; ln -s "$real" "$W/bin/stow"
  mkdir -p "$W/pub/runcom" "$W/pub/config"; echo z >"$W/pub/runcom/.zshrc"; echo y >"$W/pub/runcom/.zprofile"
  (cd "$W/pub" && stow --restow -t "$W/home" runcom); rm "$W/home/.zprofile"; echo MINE >"$W/home/.zprofile"
  ln -sfn /elsewhere "$W/home/.zprofile"
  before=$(readlink "$W/home/.zshrc"); push_change "$W" pub README.md new
  syn --scheduled >/dev/null 2>&1; [ "$(readlink "$W/home/.zshrc")" = "$before" ] && [ "$(readlink "$W/home/.zprofile")" = /elsewhere ] &&
  grep -q "^osascript .*stow conflict:" "$W/log"'
t "S1.3" "after a move dotfiles private link runs (the private files are linked in)" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1; [ -L "$W/pub/macos/local.sh" ]'
t "S1.4" "nothing moved: no restow, no link" \
  'W=$(senv); syn >/dev/null 2>&1; [ "$(_calls "^stow")" -eq 0 ] && [ ! -e "$W/pub/macos/local.sh" ]'
t "S1.5" "the private repo is fast-forwarded too, and that alone restows" \
  'W=$(senv); push_change "$W" priv macos/local.sh "DOTFILES_LOCALE=fr_FR"; syn >/dev/null 2>&1
   [ "$(_head priv)" = "$(_remote priv)" ] && [ "$(_calls "^stow --restow")" -eq 2 ]'
t "S1.6" "up to date says so and reports everything in sync" \
  'W=$(senv); out=$(syn 2>&1); printf "%s\n" "$out" | grep -q "up to date" && printf "%s\n" "$out" | grep -q "Everything is in sync"'
t "S1.7" "no private repo yet: says how to get it and carries on" \
  'W=$(senv); out=$(sy_env "DOTFILES_PRIVATE_DIR=$W/none" syn 2>&1); rc=$?; [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "dotfiles private clone"'

t "S2.1" "behind but dirty: the tree and HEAD are not touched" '
  W=$(senv); push_change "$W" pub README.md new; printf "mine\n" >"$W/pub/README.md"; h=$(_head pub)
  syn >/dev/null 2>&1; [ "$(_head pub)" = "$h" ] && [ "$(command cat "$W/pub/README.md")" = mine ] && [ -z "$(git -C "$W/pub" stash list)" ]'
t "S2.2" "behind but dirty: the exact command to resolve it is printed, and nothing is restowed" '
  W=$(senv); push_change "$W" pub README.md new; printf "mine\n" >"$W/pub/README.md"
  out=$(syn 2>&1); printf "%s\n" "$out" | grep -q "uncommitted changes, so it was left alone" &&
  printf "%s\n" "$out" | grep -q "git -C \"$W/pub\" pull --ff-only" && [ "$(_calls "^stow")" -eq 0 ]'
t "S2.4" "behind, and dirty in a file the upstream change does not touch: still left alone (clean means clean)" '
  W=$(senv); push_change "$W" pub README.md new; printf "brew \"wget\"\nbrew \"extra\"\n" >"$W/pub/Brewfile"; h=$(_head pub)
  syn >/dev/null 2>&1; [ "$(_head pub)" = "$h" ] && [ "$(_calls "^stow")" -eq 0 ]'
t "S2.3" "an untracked file does not count as dirty" \
  'W=$(senv); push_change "$W" pub README.md new; printf "x\n" >"$W/pub/scratch.txt"; syn >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ]'
t "S3.1" "ahead: the unpushed commits and the push command are reported, and nothing is pushed" '
  W=$(senv); r=$(_remote pub); printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  out=$(syn 2>&1); [ "$(_remote pub)" = "$r" ] && printf "%s\n" "$out" | grep -q "1 unpushed" && printf "%s\n" "$out" | grep -q "git -C \"$W/pub\" push"'
t "S3.2" "diverged: reported with both commands, and history is left exactly as it was" '
  W=$(senv); push_change "$W" pub README.md new; printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  h=$(_head pub); out=$(syn 2>&1)
  [ "$(_head pub)" = "$h" ] && printf "%s\n" "$out" | grep -q "diverged" && printf "%s\n" "$out" | grep -q "rebase" &&
  printf "%s\n" "$out" | grep -q "merge" && [ -z "$(git -C "$W/pub" stash list)" ] && [ "$(_calls "^stow")" -eq 0 ]'
t "S3.3" "the private repo with uncommitted new files is reported" \
  'W=$(senv); printf "x\n" >"$W/priv/new.txt"; out=$(syn 2>&1); printf "%s\n" "$out" | grep -q "uncommitted"'
t "S3.4" "a failed fetch (offline) is reported, and is not an error" '
  W=$(senv); command mv "$W/pub.git" "$W/gone.git"; out=$(syn 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "could not fetch"'

# Three changes that each call for an action.
_actions() { # _actions <W>: mise, Brewfile and claude/ change on the remote
  push_change "$1" pub config/mise/config.toml "[tools]
node = \"1\""
  push_change "$1" pub Brewfile "brew \"wget\"
brew \"jq\""
  push_change "$1" pub claude/rules.md "r2"
  : >"$1/state/unsatisfied"
}
t "S4.1" "interactive, confirmed: mise install, brew bundle install and install --claude run" '
  W=$(senv); _actions "$W"; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1
  grep -qx "mise install" "$W/log" && grep -qx "brew bundle install --file=$W/pub/Brewfile" "$W/log" &&
  grep -qx "dotfiles-stub install --claude" "$W/log" && [ "$(_calls "install --codex")" -eq 0 ]'
t "S4.2" "interactive, declined (no answer): nothing is installed and the actions are listed as pending" '
  W=$(senv); _actions "$W"; out=$(syn 2>&1)
  [ "$(_calls "^mise")" -eq 0 ] && [ "$(_calls "bundle install")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ] &&
  printf "%s\n" "$out" | grep -q "still pending"'
t "S4.3" "a Brewfile change that is already satisfied installs nothing" '
  W=$(senv); push_change "$W" pub Brewfile "brew \"wget\""; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; [ "$(_calls "bundle install")" -eq 0 ]'
t "S4.4" "an action that ran is no longer pending: the next run does not repeat it" '
  W=$(senv); _actions "$W"; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; : >"$W/log"; command rm -f "$W/state/unsatisfied"
  sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; [ "$(_calls "^mise")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ]'
t "S4.5" "a failing action is reported and keeps the exit status non-zero" '
  W=$(senv); _actions "$W"; stub "$W/bin" mise "exit 1"; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; [ "$?" -ne 0 ]'
t "S4.6" "secrets.age changing upstream is only reported: no import, no prompt" '
  W=$(senv); push_change "$W" priv secrets.age "age"; out=$(sy_env "DOTFILES_YES=1" syn 2>&1)
  printf "%s\n" "$out" | grep -q "dotfiles secrets import" && [ "$(_calls "secrets")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ]'
t "S4.7" "the private repo changing claude/*.local.list calls for install --claude" '
  W=$(senv); push_change "$W" priv claude/work.local.list "m"; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; grep -qx "dotfiles-stub install --claude" "$W/log"'

t "S5.1" "scheduled: never sudo, never mise, never brew bundle or install, never dotfiles install" '
  W=$(senv); _actions "$W"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^sudo")" -eq 0 ] && [ "$(_calls "^mise")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ] &&
  [ "$(grep "^brew" "$W/log" | grep -vc "^brew leaves\|^brew list --cask")" -eq 0 ]'
t "S5.2" "scheduled: exactly one notification, naming the pending actions" '
  W=$(senv); _actions "$W"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "display notification" && grep "^osascript" "$W/log" | grep -q "pending"'
t "S5.3" "scheduled: prints nothing and logs to ~/Library/Logs/dotfiles-sync.log" '
  W=$(senv); _actions "$W"; out=$(syn --scheduled 2>&1); [ -z "$out" ] &&
  grep -q "dotfiles sync (scheduled)" "$W/home/Library/Logs/dotfiles-sync.log" && grep -q "pending: mise install" "$W/home/Library/Logs/dotfiles-sync.log"'
t "S5.4" "scheduled with nothing to do: no notification, but a log entry" '
  W=$(senv); syn --scheduled >/dev/null 2>&1; [ "$(_calls "^osascript")" -eq 0 ] && [ -s "$W/home/Library/Logs/dotfiles-sync.log" ]'
t "S5.5" "scheduled: unpushed commits notify once" '
  W=$(senv); printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  syn --scheduled >/dev/null 2>&1; [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "unpushed"'
t "S5.6" "scheduled: divergence notifies" '
  W=$(senv); push_change "$W" pub README.md new; printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  syn --scheduled >/dev/null 2>&1; grep "^osascript" "$W/log" | grep -q "diverged"'
t "S5.7" "scheduled and offline: no notification, exit 0" '
  W=$(senv); command mv "$W/pub.git" "$W/gone.git"; syn --scheduled >/dev/null 2>&1; rc=$?; [ "$rc" -eq 0 ] && [ "$(_calls "^osascript")" -eq 0 ]'
t "S5.8" "scheduled still fast-forwards and restows" \
  'W=$(senv); push_change "$W" pub README.md new; syn --scheduled >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ] && [ "$(_calls "^stow --restow")" -eq 2 ]'
t "S5.9" "pending actions survive to the next scheduled run, until an interactive run does them" '
  W=$(senv); push_change "$W" pub config/mise/config.toml "[tools]
node = \"1\""
  syn --scheduled >/dev/null 2>&1; : >"$W/log"
  syn --scheduled >/dev/null 2>&1; a=$(_calls "^osascript")
  sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; : >"$W/log"
  syn --scheduled >/dev/null 2>&1; [ "$a" -eq 1 ] && [ "$(_calls "^osascript")" -eq 0 ]'
t "S5.10" "scheduled never waits at a git or ssh prompt" \
  '[ "$(code_of bin/dotfiles-sync | grep -c "GIT_TERMINAL_PROMPT=0")" -ge 1 ] && [ "$(code_of bin/dotfiles-sync | grep -c "BatchMode=yes")" -ge 1 ]'
t "S5.12" "the fetches use an ssh that accepts a first-seen host key (scheduled adds BatchMode)" '
  W=$(senv); stub "$W/bin" git '"'"'echo "GSC=${GIT_SSH_COMMAND:-}" >>"$STUB_LOG"; exec /usr/bin/git "$@"'"'"'
  syn >/dev/null 2>&1; a=$(grep "^GSC=" "$W/log" | grep -c "StrictHostKeyChecking=accept-new"); : >"$W/log"
  syn --scheduled >/dev/null 2>&1; b=$(grep "^GSC=" "$W/log" | grep -c "StrictHostKeyChecking=accept-new.*BatchMode=yes")
  [ "$a" -ge 2 ] && [ "$b" -ge 2 ]'
t "S5.11" "scheduled sets its own PATH: Homebrew when brew is not resolvable, then the mise shims" \
  '[ "$(code_of bin/dotfiles-sync | grep -c "/opt/homebrew/bin")" -ge 1 ] && [ "$(code_of bin/dotfiles-sync | grep -c "mise/shims")" -ge 1 ]'

t "S6.1" "drift lists an undeclared brew leaf with the line to add, and not the declared ones" '
  W=$(senv); printf "wget\nfzf\njq\n" >"$W/state/leaves"; out=$(syn 2>&1)
  printf "%s\n" "$out" | grep -qF "brew \"jq\"" && [ "$(printf "%s\n" "$out" | grep -cF "brew \"wget\"")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -cF "brew \"fzf\"")" -eq 0 ]'
t "S6.2" "drift lists undeclared casks, App Store apps and VS Code extensions" '
  W=$(senv); printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  printf "ms-python.python\nFoo.Bar\n" >"$W/state/vscode"; out=$(syn 2>&1)
  printf "%s\n" "$out" | grep -qF "cask \"slack\"" && printf "%s\n" "$out" | grep -qF "mas \"Amphetamine\", id: 111" &&
  printf "%s\n" "$out" | grep -qF "Foo.Bar" && [ "$(printf "%s\n" "$out" | grep -cF "Xcode")" -eq 0 ]'
t "S6.3" "a tap formula is matched by its short name" '
  W=$(senv); printf "wget\nsomeone/tap/fzf\n" >"$W/state/leaves"; out=$(syn 2>&1); [ "$(printf "%s\n" "$out" | grep -cF "fzf")" -eq 0 ]'
t "S6.4" "nothing undeclared: none" \
  'W=$(senv); out=$(syn 2>&1); printf "%s\n" "$out" | grep -A1 "^== drift" | grep -q "none"'
t "S6.5" "scheduled: drift notifies once" '
  W=$(senv); printf "wget\nfzf\njq\n" >"$W/state/leaves"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "declared nowhere"'
t "S6.6" "the extra Brewfile.local entries count as declared" \
  'W=$(senv); printf "fzf\n" >"$W/state/leaves"; out=$(syn 2>&1); [ "$(printf "%s\n" "$out" | grep -cF "brew \"fzf\"")" -eq 0 ]'
t "S7.1" "an unknown argument is a usage error" \
  'W=$(senv); out=$(syn --frobnicate 2>&1); rc=$?; [ "$rc" -eq 2 ] && printf "%s\n" "$out" | grep -q "Usage"'

# The daily vault scan (Task 12.2). vault_of <W>: the sandbox vault's
# Claude-Sessions folder. jevstub <W> <exit> [output line]: a dotfiles-jev that
# logs its argv and JEV_SCHEDULED, prints the line and exits with <exit>.
vault_of() { mkdir -p "$1/home/Vault/Claude-Sessions"; printf '%s' "$1/home/Vault/Claude-Sessions"; }
jevstub() {
  stub "$1/bin" dotfiles-jev-stub 'echo "JEV_SCHEDULED=${JEV_SCHEDULED:-}" >>"$STUB_LOG"; [ -n "'"${3:-}"'" ] && printf "%s\n" "'"${3:-}"'"; exit '"$2"
}
JEVSTUB_ENV() { printf 'DOTFILES_JEV_BIN=%s/bin/dotfiles-jev-stub' "$1"; }
stampf() { printf '%s/home/.local/state/dotfiles/vault-scan-last' "$1"; }

t "S8.1" "scheduled: a real scan of a vault with a pasted token notifies once with file and line, never the value" '
  W=$(senv); d=$(vault_of "$W"); tok="ghp_$(rand_chars 36 A-Za-z0-9)"
  printf "notes\nexport GH_TOKEN=%s\nmore\n" "$tok" >"$d/session-1.md"; printf "fine\n" >"$d/session-2.md"
  syn --scheduled >/dev/null 2>&1; l=$(command cat "$W/home/Library/Logs/dotfiles-sync.log")
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "session-1.md:2" &&
  [ "$(grep "^osascript" "$W/log" | grep -c "$tok")" -eq 0 ] && [ "$(printf "%s\n" "$l" | grep -c "$tok")" -eq 0 ] &&
  [ "$(printf "%s\n" "$l" | grep -c "FOUND session-1.md:2")" -eq 1 ]'
t "S8.2" "scheduled: a clean vault does not notify, is logged, and is not scanned again the same day" '
  W=$(senv); d=$(vault_of "$W"); printf "fine\n" >"$d/s.md"; jevstub "$W" 0 "no credentials found"; E=$(JEVSTUB_ENV "$W")
  with_x() { local SYNENV="$E"; syn --scheduled >/dev/null 2>&1; }; with_x; with_x
  [ "$(_calls "^osascript")" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub scan-vault")" -eq 1 ] &&
  [ "$(cat "$(stampf "$W")")" = "$(date +%Y-%m-%d)" ] && grep -q "no credentials found" "$W/home/Library/Logs/dotfiles-sync.log"'
t "S8.3" "scheduled: a stamp from an earlier day scans again" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 0; E=$(JEVSTUB_ENV "$W")
  mkdir -p "$(dirname "$(stampf "$W")")"; printf "2020-01-01\n" >"$(stampf "$W")"
  SYNENV="$E" syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^dotfiles-jev-stub scan-vault")" -eq 1 ] && [ "$(cat "$(stampf "$W")")" = "$(date +%Y-%m-%d)" ]'
t "S8.4" "scheduled: the scan runs with the scheduled timeout and gets the Claude-Sessions folder" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 0; E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn --scheduled >/dev/null 2>&1
  grep -q "^JEV_SCHEDULED=1$" "$W/log" && grep -qx "dotfiles-jev-stub scan-vault $d" "$W/log"'
t "S8.5" "an interactive sync does not scan the vault" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 1 "FOUND s.md:2: a credential"; E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn >/dev/null 2>&1
  [ "$(_calls "^dotfiles-jev-stub")" -eq 0 ] && [ ! -e "$(stampf "$W")" ]'
t "S8.6" "no vault folder: nothing to scan, no notification, no stamp, exit 0" '
  W=$(senv); jevstub "$W" 1 "FOUND s.md:2: x"; E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn --scheduled >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub")" -eq 0 ] && [ "$(_calls "^osascript")" -eq 0 ] && [ ! -e "$(stampf "$W")" ]'
t "S8.7" "a scan that cannot run notifies, and is retried the next run (no stamp)" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 3 "boom"; E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "vault scan could not run" && [ ! -e "$(stampf "$W")" ]'
t "S8.8" "hits are listed by file and line, at most three, and counted; ambiguous ones count too" '
  W=$(senv); d=$(vault_of "$W")
  jevstub "$W" 1 "FOUND a.md:2: a credential (pattern, name=-, length 40)
FOUND b.md:5: a credential (pattern, name=-, length 40)
WARN  c.md:7: a high-entropy value in x (length 40) looks like a credential
FOUND d.md:9: flagged by gitleaks"
  E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn --scheduled >/dev/null 2>&1; n=$(grep "^osascript" "$W/log")
  [ "$(_calls "^osascript")" -eq 1 ] && printf "%s\n" "$n" | grep -q "4 possible credential" && printf "%s\n" "$n" | grep -q "a.md:2" &&
  printf "%s\n" "$n" | grep -q "c.md:7" && printf "%s\n" "$n" | grep -q "+1 more" && [ "$(printf "%s\n" "$n" | grep -c "d.md:9")" -eq 0 ]'
t "S8.10" "a note whose name holds a colon is still reported, by its whole path" '
  W=$(senv); d=$(vault_of "$W"); tok="ghp_$(rand_chars 36 A-Za-z0-9)"
  printf "x=%s\n" "$tok" >"$d/Session 12:30 x.md"
  syn --scheduled >/dev/null 2>&1; n=$(grep "^osascript" "$W/log")
  [ "$(_calls "^osascript")" -eq 1 ] && printf "%s\n" "$n" | grep -q "1 possible credential" && printf "%s\n" "$n" | grep -q "Session 12:30 x.md:1" &&
  [ "$(printf "%s\n" "$n" | grep -c "$tok")" -eq 0 ]'
t "S8.11" "a scan that exits 1 always notifies, even when no hit line can be parsed" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 1 "something unexpected"; E=$(JEVSTUB_ENV "$W"); SYNENV="$E" syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "possible credential(s) in the vault" && grep "^osascript" "$W/log" | grep -q "log"'
t "S8.9" "the scan is report-only: it never edits, deletes or moves anything in the vault" '
  W=$(senv); d=$(vault_of "$W"); tok="ghp_$(rand_chars 36 A-Za-z0-9)"; printf "x=%s\n" "$tok" >"$d/s.md"
  a=$(shasum "$d/s.md"); syn --scheduled >/dev/null 2>&1; [ "$(shasum "$d/s.md")" = "$a" ] && [ "$(ls "$d" | wc -l | tr -d " ")" -eq 1 ]'


#############################################################################
section "D -- Task 13: drift that notices itself (Jev classifies the undeclared)"
#############################################################################
# dstub <W> [mode]: a private-repo-independent jev.conf (drift=<mode>, default
# on), a dotfiles-jev that records its stdin (the facts) per kind and prints
# $STUB_STATE/suggest-<kind>, a dotfiles-baseline that prints
# $STUB_STATE/changed, and a defaults that only answers read-type.
dstub() {
  printf 'drift=%s\n' "${2:-on}" >"$1/jev.conf"
  stub "$1/bin" dotfiles-jev-stub 'case "$1" in drift) echo "JEV_SCHEDULED=${JEV_SCHEDULED:-} JEV_TIMEOUT=${JEV_TIMEOUT:-}" >>"$STUB_LOG"; cat >"$STUB_STATE/facts-$2"; cat "$STUB_STATE/suggest-$2" 2>/dev/null ;; esac; exit ${JEVSTUB_RC:-0}'
  stub "$1/bin" dotfiles-baseline-stub 'cat "$STUB_STATE/changed" 2>/dev/null'
  stub "$1/bin" defaults 'case "$1" in read-type) printf "Type is %s\n" "$(cat "$STUB_STATE/deftype" 2>/dev/null || echo boolean)" ;; esac'
}
# dsyn <args>: syn with Jev switched on and pointed at the stubs. $DX adds VAR=val.
dsyn() {
  local ans=""
  # DXY=1 answers "y" to every strict prompt, DXA=1 uses the answers already in
  # $W/yes. The strict prompt ignores DOTFILES_YES; a test has no terminal, so
  # the harness marks its sandbox (see tests/lib.sh) and names an answers file
  # inside it.
  local xa="${DXA:-}"
  if [ -n "${DXY:-}" ]; then printf 'y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n' >"$W/yes"; xa=1; fi
  [ -n "$xa" ] && ans="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$W/yes"
  local SYNENV="$ans DOTFILES_JEV= DOTFILES_JEV_CONFIG=$W/jev.conf DOTFILES_JEV_BIN=$W/bin/dotfiles-jev-stub DOTFILES_BASELINE_BIN=$W/bin/dotfiles-baseline-stub ${DX:-}"
  syn "$@"
}
_suggest() { printf 'SUGGEST\t%s\t%s\t0.9\t0.9\n' "$2" "$3" >>"$W/state/suggest-$1"; }
_facts() { command cat "$W/state/facts-$1" 2>/dev/null; }
_lines() { command cat "$W/$1" 2>/dev/null; }
_undeclared() { printf 'wget\nfzf\njq\n' >"$W/state/leaves"; }

t "D1.1" "an undeclared formula goes to Jev as one fact line: name, description, dependency, first-seen date" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1
  f=$(_facts pkg); today=$(date +%Y-%m-%d)
  [ "$(printf "%s\n" "$f" | grep -c "^brew:jq	")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "description=Description of jq")" -eq 1 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "dependency=no")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "first seen $today")" -eq 1 ]'
t "D1.2" "formulae, casks and App Store apps are one batched request, not one each" '
  W=$(senv); dstub "$W"; _undeclared; printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  dsyn >/dev/null 2>&1; f=$(_facts pkg)
  [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 3 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^cask:slack	")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "^mas:111	.*Amphetamine")" -eq 1 ]'
t "D1.3" "a formula another installed formula needs is marked as a dependency" '
  W=$(senv); dstub "$W"; _undeclared; printf "ffmpeg\n" >"$W/state/uses-jq"; dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "dependency=yes")" -eq 1 ]'
t "D1.4" "the first-seen date is remembered: an item seen earlier keeps its old date" '
  W=$(senv); dstub "$W"; _undeclared; mkdir -p "$W/home/.local/state/dotfiles"
  printf "brew:jq\t2026-01-05\n" >"$W/home/.local/state/dotfiles/drift-first-seen"
  dsyn >/dev/null 2>&1; dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "first seen 2026-01-05")" -eq 1 ] && [ "$(grep -c "^brew:jq" "$W/home/.local/state/dotfiles/drift-first-seen")" -eq 1 ]'
t "D1.9" "a first sighting is recorded with today's date, once, for the next run" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1; dsyn >/dev/null 2>&1
  [ "$(grep -c "^brew:jq$(printf "\t")$(date +%Y-%m-%d)$" "$W/home/.local/state/dotfiles/drift-first-seen")" -eq 1 ]'
t "D1.5" "nothing undeclared: Jev is not asked" '
  W=$(senv); dstub "$W"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 0 ]'
t "D1.6" "with Jev switched off (the master switch or the point) nothing is asked and no fact is gathered" '
  W=$(senv); dstub "$W"; _undeclared; DX="DOTFILES_JEV=off" dsyn >/dev/null 2>&1; a=$(_calls "^dotfiles-jev-stub drift")
  W2=$(senv); W=$W2; dstub "$W" off; _undeclared; dsyn >/dev/null 2>&1
  [ "$a" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub drift")" -eq 0 ] && [ "$(_calls "^brew desc")" -eq 0 ]'
t "D1.7" "a Jev that fails changes nothing: the deterministic report is complete, and the exit status is 0" '
  W=$(senv); dstub "$W"; _undeclared; out=$(DX="JEVSTUB_RC=3" dsyn 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -qF "brew \"jq\"" && printf "%s\n" "$out" | grep -q "declared nowhere\|^== drift"'
t "D1.8" "on: interactive requests get 6 s; shadow keeps the 2 s default; scheduled ones mark JEV_SCHEDULED for the 10 s" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1; a=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; dsyn --scheduled >/dev/null 2>&1; b=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; dstub "$W" shadow; dsyn >/dev/null 2>&1; c=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  [ "$a" = "JEV_SCHEDULED= JEV_TIMEOUT=6" ] && [ "$b" = "JEV_SCHEDULED=1 JEV_TIMEOUT=" ] && [ "$c" = "JEV_SCHEDULED= JEV_TIMEOUT=" ]'

t "D2.1" "on, confirmed: a public suggestion appends the exact line to the public Brewfile, and nothing is committed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; h=$(_head pub)
  DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile | tail -n 1)" = "brew \"jq\"" ] && [ "$(_lines pub/Brewfile.local | grep -c jq)" -eq 0 ] && [ "$(_head pub)" = "$h" ]'
t "D2.2" "a private suggestion goes to Brewfile.local, a cask and an App Store app as their own lines" '
  W=$(senv); dstub "$W"; _undeclared; printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  _suggest pkg brew:jq private; _suggest pkg cask:slack public; _suggest pkg mas:111 private
  DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile.local | grep -c "^brew \"jq\"$")" -eq 1 ] && [ "$(_lines pub/Brewfile | grep -c "^cask \"slack\"$")" -eq 1 ] &&
  [ "$(_lines pub/Brewfile.local | grep -c "^mas \"Amphetamine\", id: 111$")" -eq 1 ]'
t "D2.3" "interactive and not confirmed (no answer): the line is offered and nothing is written" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile"); out=$(dsyn 2>&1)
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && printf "%s\n" "$out" | grep -qF "Jev suggests public: brew \"jq\"      (add to Brewfile)"'
t "D2.4" "a private suggestion names Brewfile.local as the file" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq private
  out=$(dsyn 2>&1); printf "%s\n" "$out" | grep -qF "Jev suggests private: brew \"jq\"      (add to Brewfile.local)"'
t "D2.5" "an ignore suggestion is reported and writes nothing, even confirmed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq ignore; b=$(shasum "$W/pub/Brewfile" "$W/pub/Brewfile.local")
  out=$(DXY=1 dsyn 2>&1); [ "$(shasum "$W/pub/Brewfile" "$W/pub/Brewfile.local")" = "$b" ] && printf "%s\n" "$out" | grep -q "ignore"'
t "D2.6" "a remove suggestion prints the uninstall command and never runs it, even confirmed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq remove; b=$(shasum "$W/pub/Brewfile")
  out=$(DXY=1 dsyn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "brew uninstall jq")" -ge 1 ] && [ "$(_calls "^brew uninstall")" -eq 0 ] && [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D2.7" "a suggestion for something that was not in the facts is ignored: Jev never invents a line" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg "brew:evil; touch $W/pwned" public; _suggest pkg brew:wget public
  b=$(shasum "$W/pub/Brewfile"); DXY=1 dsyn >/dev/null 2>&1
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ ! -e "$W/pwned" ]'
t "D2.8" "an item already declared by an earlier confirm is not appended twice" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; DXY=1 dsyn >/dev/null 2>&1
  DXY=1 dsyn >/dev/null 2>&1; [ "$(_lines pub/Brewfile | grep -c "^brew \"jq\"$")" -eq 1 ]'
t "D2.9" "shadow mode: Jev is asked, but even a SUGGEST line from it is not acted on" '
  W=$(senv); dstub "$W" shadow; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  out=$(DXY=1 dsyn 2>&1); [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 1 ] && [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ "$(printf "%s\n" "$out" | grep -c "Add brew")" -eq 0 ]'
t "D2.10" "scheduled: no prompt, no write, and the single notification says Jev has suggestions" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  DXY=1 dsyn --scheduled >/dev/null 2>&1
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "Jev suggests"'

t "D3.1" "changed defaults go to Jev as one batch: domain and key, old and new value, first-seen date" '
  W=$(senv); dstub "$W"; printf "com.example.a\tAlpha\t1\t0\ncom.example.a\tBeta\t5\t6\n" >"$W/state/changed"; dsyn >/dev/null 2>&1
  f=$(_facts defaults)
  [ "$(_calls "^dotfiles-jev-stub drift defaults")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 2 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^com.example.a Alpha	.*was 1.*now 0.*first seen $(date +%Y-%m-%d)")" -eq 1 ]'
t "D3.2" "no changed defaults: Jev is not asked" '
  W=$(senv); dstub "$W"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift defaults")" -eq 0 ]'
t "D3.3" "public: the defaults write line, typed by defaults read-type, is appended to macos/defaults.sh on confirm" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"
  _suggest defaults "com.example.a Alpha" public; DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/macos/defaults.sh | tail -n 1)" = "defaults write com.example.a Alpha -bool false" ]'
t "D3.4" "local-only is printed for you to place by hand: nothing is written to macos/local.sh or machine.local.sh, even confirmed" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; printf "com.example.a\tBeta\t5\t6\n" >"$W/state/changed"; printf "integer" >"$W/state/deftype"
  _suggest defaults "com.example.a Beta" local-only; out=$(DXY=1 dsyn 2>&1)
  [ ! -e "$W/pub/macos/local.sh" ] && [ ! -e "$W/pub/macos/machine.local.sh" ] &&
  printf "%s\n" "$out" | grep -qF "Jev suggests local-only: defaults write com.example.a Beta -int 6" && printf "%s\n" "$out" | grep -q "place it by hand"'
t "D3.5" "a value that cannot be written safely (a string with a quote or a dollar) is shown, never appended" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tPath\told\t\$HOME/x\n" >"$W/state/changed"; printf "string" >"$W/state/deftype"
  _suggest defaults "com.example.a Path" public; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && printf "%s\n" "$out" | grep -q "by hand"'
t "D3.6" "transient is reported and writes nothing" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"
  _suggest defaults "com.example.a Alpha" transient; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && printf "%s\n" "$out" | grep -q "transient"'

t "D4.1" "unmanaged ~/.config directories go to Jev: real dirs the repo has no config/<name> for, not links, not managed ones" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config/newtool/sub" "$W/home/.config/managed" "$W/pub/config/managed" "$W/elsewhere"
  printf "a\n" >"$W/home/.config/newtool/a.conf"; printf "b\n" >"$W/home/.config/newtool/sub/b"; ln -s "$W/elsewhere" "$W/home/.config/linked"; printf "x\n" >"$W/home/.config/loose-file"
  dsyn >/dev/null 2>&1; f=$(_facts config)
  [ "$(_calls "^dotfiles-jev-stub drift config")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 1 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^newtool	.*files=2.*first seen $(date +%Y-%m-%d)")" -eq 1 ]'
t "D4.2" "capture: the exact move-and-link command is printed and nothing is moved, even confirmed" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config/newtool"; printf "a\n" >"$W/home/.config/newtool/a.conf"; _suggest config newtool capture
  out=$(DXY=1 dsyn 2>&1)
  [ -f "$W/home/.config/newtool/a.conf" ] && [ ! -e "$W/pub/config/newtool" ] && printf "%s\n" "$out" | grep -qF "mv \"$W/home/.config/newtool\" \"$W/pub/config/newtool\"" && printf "%s\n" "$out" | grep -q "dotfiles link"'
t "D4.3" "no unmanaged directory: Jev is not asked" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift config")" -eq 0 ]'

t "D6.1" "DOTFILES_YES=1 with no terminal and no seam appends nothing: the model never edits a file unattended" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  out=$(DX="DOTFILES_YES=1" dsyn 2>&1); [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && printf "%s\n" "$out" | grep -qF "Jev suggests public: brew \"jq\""'
t "D6.2" "an answer that is not y or yes appends nothing" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile"); printf "n\nyep\n" >"$W/yes"
  DXA=1 dsyn >/dev/null 2>&1; [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D6.3" "a hostile App Store name (quote, Ruby interpolation) is never written into a Brewfile; it is shown to add by hand" '
  W=$(senv); dstub "$W"; printf "111  Evil\"App #{system(1)}  (5.0)\n222  Fine App  (1.0)\n" >"$W/state/mas"
  _suggest pkg mas:111 public; _suggest pkg mas:222 public; out=$(DXY=1 dsyn 2>&1)
  [ "$(_lines pub/Brewfile | grep -c "Evil")" -eq 0 ] && [ "$(_lines pub/Brewfile | grep -c "^mas \"Fine App\", id: 222$")" -eq 1 ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.4" "a hostile formula or cask name is not written either" '
  W=$(senv); dstub "$W"; printf "wget\nfzf\nx\"y\n" >"$W/state/leaves"; printf "iterm2\nbad#{z}\n" >"$W/state/casks"
  _suggest pkg "brew:x\"y" public; _suggest pkg "cask:bad#{z}" public; out=$(DXY=1 dsyn 2>&1)
  [ "$(_lines pub/Brewfile | grep -c "x\"y\|bad")" -eq 0 ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.5" "a failed Jev request stops the other kinds: one request, not three" '
  W=$(senv); dstub "$W"; _undeclared; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"; mkdir -p "$W/home/.config/newtool"; printf "a\n" >"$W/home/.config/newtool/a"
  DX="JEVSTUB_RC=3" dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift")" -eq 1 ]'
t "D6.6" "one 401 is one request across all three kinds (real dotfiles-jev, fake curl)" '
  W=$(senv); dstub "$W"; _undeclared; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"; mkdir -p "$W/home/.config/newtool" "$W/rec"; printf "a\n" >"$W/home/.config/newtool/a"
  cp "$ROOT_DIR/tests/fixtures/jev/fake-curl" "$W/bin/curl"
  DX="DOTFILES_JEV_BIN=$ROOT_DIR/bin/dotfiles-jev TYPESAFE_API_KEY=k1 FAKE_CURL_DIR=$W/rec FAKE_CURL_FIXDIR=$ROOT_DIR/tests/fixtures/jev FAKE_CURL_SEQ=401 JEV_BACKOFF=0" dsyn >/dev/null 2>&1
  [ "$(command cat "$W/rec/count" 2>/dev/null || echo 0)" -eq 1 ]'
t "D6.7" "fact gathering stops at JEV_DRIFT_MAX_ITEMS: brew is asked about at most that many formulae" '
  W=$(senv); dstub "$W"; printf "wget\nfzf\na1\na2\na3\na4\na5\na6\n" >"$W/state/leaves"
  DX="JEV_DRIFT_MAX_ITEMS=3" dsyn >/dev/null 2>&1
  [ "$(_calls "^brew desc")" -eq 3 ] && [ "$(_facts pkg | grep -c .)" -eq 3 ]'
t "D6.8" "an undeclared VS Code extension is classified too: public to packages/code.list, private to code.local.list" '
  W=$(senv); dstub "$W"; printf "ms-python.python\nFoo.Bar\nBaz.Qux\n" >"$W/state/vscode"
  _suggest pkg code:Foo.Bar public; _suggest pkg code:Baz.Qux private; DXY=1 dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "^code:Foo.Bar	.*VS Code extension")" -eq 1 ] && [ "$(_lines pub/packages/code.list | grep -c "^Foo.Bar$")" -eq 1 ] &&
  [ "$(_lines pub/packages/code.local.list | grep -c "^Baz.Qux$")" -eq 1 ]'
t "D6.9" "an extension id outside publisher.name is not written" '
  W=$(senv); dstub "$W"; printf "ms-python.python\nx;touch.pwned\n" >"$W/state/vscode"; b=$(shasum "$W/pub/packages/code.list")
  _suggest pkg "code:x;touch.pwned" public; out=$(DXY=1 dsyn 2>&1); [ "$(shasum "$W/pub/packages/code.list")" = "$b" ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.10" "a defaults integer like 5-3 and a domain with a shell metacharacter are shown, never appended" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "integer" >"$W/state/deftype"
  printf "com.example.a\tBeta\t5\t5-3\nevil;dom\tK\t1\t2\n" >"$W/state/changed"
  _suggest defaults "com.example.a Beta" public; _suggest defaults "evil;dom K" public; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && [ "$(printf "%s\n" "$out" | grep -c "by hand")" -eq 2 ]'

t "D6.11" "an exported answers file without the sandbox marker is ignored: a real run appends nothing" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; printf "y\ny\n" >"$W/yes"; b=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_STRICT_ANSWERS=$W/yes" dsyn >/dev/null 2>&1; [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D6.12" "with the marker, an answers file outside the sandbox root, or reached through .., is ignored" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  o=$(mktemp -d "${TMPDIR:-/tmp}/dfout.XXXXXX"); printf "y\ny\n" >"$o/yes"; printf "y\ny\n" >"$W/yes"
  DX="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$o/yes" dsyn >/dev/null 2>&1; a=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$DOTFILES_TEST_SANDBOX/../$(basename "$o")/yes" dsyn >/dev/null 2>&1; c=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_TEST_SANDBOX= DOTFILES_STRICT_ANSWERS=$W/yes" dsyn >/dev/null 2>&1; d=$(shasum "$W/pub/Brewfile")
  command rm -f "$o/yes"; rmdir "$o"
  [ "$a" = "$b" ] && [ "$c" = "$b" ] && [ "$d" = "$b" ]'
t "D6.13" "the answers descriptor the seam opens is closed again, and the seam is not advertised in the docs" '
  [ "$(code_of bin/dotfiles-sync | grep -c "exec 4<&-")" -ge 1 ] && [ "$(grep -c "STRICT_ANSWERS" docs/agents/jev.md docs/agents/two-mac-sync.md | grep -vc ":0$")" -eq 0 ]'

t "D5.1" "sync never writes to a Brewfile or a defaults file without going through confirm" '
  c=$(code_of bin/dotfiles-sync)
  [ "$(printf "%s\n" "$c" | grep -c "strict_confirm \"Add ")" -ge 1 ] && [ "$(printf "%s\n" "$c" | grep -c "[^_]confirm \"Add ")" -eq 0 ] && [ "$(printf "%s\n" "$c" | grep -c "^[[:space:]]*brew uninstall")" -eq 0 ]'

#############################################################################
section "V -- dotfiles vault migrate (bin/dotfiles-vault)"
#############################################################################
# venv: a sandbox HOME with a real local vault and a fake iCloud Drive
# ($W/icloud is the CloudDocs folder; the vault goes to $W/icloud/Vault). Real
# /usr/bin/ditto does the copying unless a test puts a stub in front.
venv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home/Vault/Notes/Sub dir" "$w/home/Vault/.obsidian" "$w/home/Vault/Empty" "$w/bin" "$w/icloud"; : >"$w/log"
  printf 'one\n' >"$w/home/Vault/Notes/a.md"
  printf 'two two\n' >"$w/home/Vault/Notes/Sub dir/b c.md"
  printf '{"a":1}\n' >"$w/home/Vault/.obsidian/app.json"
  printf 'top\n' >"$w/home/Vault/index.md"
  # pgrep: Obsidian is "running" while $W/obsidian exists.
  stub "$w/bin" pgrep '[ "$1" = "-x" ] && [ "$2" = Obsidian ] && [ -f "$STUB_RUNNING" ]'
  stub "$w/bin" brctl ':'
  printf '%s' "$w"
}
# vmig [VAR=val ...]: dotfiles-vault migrate against the sandbox in $W.
vmig() {
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_VAULT_ICLOUD="$W/icloud/Vault" \
    STUB_LOG="$W/log" STUB_RUNNING="$W/obsidian" "$@" bash "$ROOT_DIR/bin/dotfiles-vault" migrate 2>&1 </dev/null
}
# untouched: ~/Vault is still the original real directory, complete, and no
# staging folder or half copy is left in iCloud Drive.
untouched() {
  [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] && [ "$(command cat "$W/home/Vault/Notes/a.md")" = one ] &&
  [ -f "$W/home/Vault/Notes/Sub dir/b c.md" ] && [ -f "$W/home/Vault/.obsidian/app.json" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ] &&
  [ "$(find "$W/icloud" -mindepth 1 | wc -l | tr -d " ")" -eq 0 ]
}

t "V1.1" "migrate copies the vault to iCloud, leaves a symlink at ~/Vault and keeps the original as a backup" '
  W=$(venv); out=$(vmig); rc=$?
  [ "$rc" -eq 0 ] && [ -L "$W/home/Vault" ] && [ "$(readlink "$W/home/Vault")" = "$W/icloud/Vault" ] &&
  [ "$(command cat "$W/icloud/Vault/Notes/Sub dir/b c.md")" = "two two" ] && [ -d "$W/icloud/Vault/Empty" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 1 ]'
t "V1.2" "the backup is the untouched original, and the iCloud copy is identical to it" '
  W=$(venv); vmig >/dev/null; b=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*")
  [ -f "$b/.obsidian/app.json" ] && diff -r "$b" "$W/icloud/Vault" >/dev/null'
t "V1.3" "no staging folder is left behind after a good run" \
  'W=$(venv); vmig >/dev/null; [ "$(find "$W/icloud" -maxdepth 1 -name "*.migrating.*" | wc -l | tr -d " ")" -eq 0 ]'
t "V1.4" "the output says how to undo it, and to use Keep Downloaded" '
  W=$(venv); out=$(vmig); printf "%s\n" "$out" | grep -q "To undo" && printf "%s\n" "$out" | grep -q "Vault.local-backup-" &&
  printf "%s\n" "$out" | grep -q "Keep Downloaded"'
t "V1.5" "the undo command as printed puts the original back" '
  W=$(venv); vmig >/dev/null; b=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*")
  rm "$W/home/Vault" && mv "$b" "$W/home/Vault" && [ ! -L "$W/home/Vault" ] && [ -f "$W/home/Vault/Notes/a.md" ]'
t "V2.1" "a running Obsidian refuses, and nothing changes" '
  W=$(venv); : >"$W/obsidian"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "Obsidian is running" && untouched'
t "V2.2" "a non-empty iCloud vault folder refuses, and nothing changes" '
  W=$(venv); mkdir -p "$W/icloud/Vault"; printf "x\n" >"$W/icloud/Vault/other.md"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "not empty" && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ] && [ "$(ls "$W/icloud/Vault")" = other.md ]'
t "V2.3" "an existing but empty iCloud vault folder is fine" \
  'W=$(venv); mkdir -p "$W/icloud/Vault"; vmig >/dev/null && [ -L "$W/home/Vault" ] && [ -f "$W/icloud/Vault/index.md" ]'
t "V2.4" "no iCloud Drive at all refuses, and nothing changes" '
  W=$(venv); command rmdir "$W/icloud"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "iCloud Drive is not available" && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ]'
t "V2.5" "already migrated is a no-op that succeeds" '
  W=$(venv); vmig >/dev/null; n=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")
  out=$(vmig); rc=$?; [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "already" &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq "$n" ]'
t "V2.6" "no vault to migrate is an error" \
  'W=$(venv); command mv "$W/home/Vault" "$W/home/elsewhere"; out=$(vmig); rc=$?; [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "no vault"'
t "V2.7" "a ~/Vault symlink to somewhere else is refused" '
  W=$(venv); command mv "$W/home/Vault" "$W/home/elsewhere"; ln -s "$W/home/elsewhere" "$W/home/Vault"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && [ "$(readlink "$W/home/Vault")" = "$W/home/elsewhere" ]'

# A failure at any step leaves the original vault untouched.
t "V3.1" "a failing ditto: non-zero, the original is untouched, no partial copy is left" '
  W=$(venv); stub "$W/bin" ditto "exit 1"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "copy failed" && untouched'
t "V3.2" "a ditto that leaves a partial copy: the partial copy is removed" '
  W=$(venv); stub "$W/bin" ditto "mkdir -p \"\$2\"; cp \"\$1/index.md\" \"\$2/\"; exit 1"; vmig >/dev/null; untouched'
t "V3.3" "a copy that silently drops a file fails the count check: the original is untouched, the copy is removed" '
  W=$(venv); stub "$W/bin" ditto "/usr/bin/ditto \"\$@\" || exit 1; rm -f \"\$2/index.md\""; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "entry count differs" && untouched'
t "V3.4" "a copy with the same names but different content fails the checksum check" '
  W=$(venv); stub "$W/bin" ditto "/usr/bin/ditto \"\$@\" || exit 1; printf \"ONE\\n\" >\"\$2/Notes/a.md\""; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "does not match" && untouched'
t "V3.5" "a failing symlink step puts the original back" '
  W=$(venv); stub "$W/bin" ln "exit 1"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] && [ "$(command cat "$W/home/Vault/Notes/a.md")" = one ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ]'
t "V3.6" "the only rm in the migrate code removes the staging folder it made" \
  '[ "$(code_of bin/dotfiles-vault | grep -E "(^|[;&|])[[:space:]]*rm " | grep -vcF "\"\$1\"")" -eq 0 ] &&
   [ "$(code_of bin/dotfiles-vault | grep -cE "(^|[;&|])[[:space:]]*rm ")" -ge 1 ]'
t "V4.1" "an unknown subcommand is a usage error" \
  'W=$(venv); out=$(env -i HOME="$W/home" PATH="/usr/bin:/bin" bash bin/dotfiles-vault frob 2>&1); rc=$?; [ "$rc" -eq 2 ] && printf "%s\n" "$out" | grep -q Usage'

#############################################################################
section "A -- the daily sync agent (launchagents/com.stixzoor.dotfiles-sync.plist)"
#############################################################################
PLIST=launchagents/com.stixzoor.dotfiles-sync.plist
t "A1.1" "the agent is a top-level plist, so install --launchagents loads it" \
  '[ -f "$PLIST" ] && [ "$(dirname "$PLIST")" = launchagents ]'
t "A1.2" "the plist is valid and its label matches the file name" \
  '{ ! command -v plutil >/dev/null 2>&1 || plutil -lint "$PLIST" >/dev/null; } &&
   grep -A1 "<key>Label</key>" "$PLIST" | grep -q "<string>com.stixzoor.dotfiles-sync</string>"'
t "A1.3" "it runs dotfiles-sync --scheduled through bash -c" \
  'body=$(command cat "$PLIST"); printf "%s\n" "$body" | grep -qF "exec \"\$HOME/.dotfiles/bin/dotfiles-sync\" --scheduled" &&
   printf "%s\n" "$body" | grep -A1 "<key>ProgramArguments</key>" | grep -q "<array>" && printf "%s\n" "$body" | grep -q "<string>/bin/bash</string>"'
t "A1.4" "daily at 09:30, not at load, background priority" \
  'body=$(command cat "$PLIST")
   printf "%s\n" "$body" | grep -A1 "<key>Hour</key>" | grep -q "<integer>9</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>Minute</key>" | grep -q "<integer>30</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>RunAtLoad</key>" | grep -q "<false/>" &&
   printf "%s\n" "$body" | grep -A1 "<key>ProcessType</key>" | grep -q "<string>Background</string>"'
t "A1.5" "no StandardOutPath or StandardErrorPath (the script logs itself under ~/Library/Logs)" \
  '[ "$(grep -c "<key>Standard\(Out\|Error\)Path</key>" "$PLIST")" -eq 0 ] && grep -q "Library/Logs" bin/dotfiles-sync'
t "A1.6" "the plist carries no absolute home path" \
  '[ "$(grep -c "/Users/" "$PLIST")" -eq 0 ]'

finish

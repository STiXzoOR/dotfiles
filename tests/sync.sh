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
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
    ${SYNENV:-} bash "$ROOT_DIR/bin/dotfiles-sync" "$@" </dev/null
}
sy_env() { local SYNENV="$1"; shift; "$@"; }
_calls() { grep -c -- "$1" "$W/log"; }
_head() { git -C "$W/$1" rev-parse HEAD; }
_remote() { git -C "$W/$1.git" rev-parse main; }

t "S1.1" "behind and clean: fast-forwards the public repo" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ] && [ "$(command cat "$W/pub/README.md")" = new ]'
t "S1.2" "after a move both stow packages are restowed" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1
   grep -qx "stow --restow -t $W/home runcom" "$W/log" && grep -qx "stow --restow -t $W/home/.config config" "$W/log"'
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

finish

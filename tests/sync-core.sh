#!/usr/bin/env bash
#
# tests/sync-core.sh -- machine role and name (M) and dotfiles sync pull/drift/actions (S1-S4).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

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

t "S1.1" "behind and clean: fast-forwards the public repo" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ] && [ "$(command cat "$W/pub/README.md")" = new ]'
t "S1.2" "after a move both stow packages are simulated first, then restowed, ignoring .DS_Store" \
  'W=$(senv); push_change "$W" pub README.md new; syn >/dev/null 2>&1
   grep -qxF -- "stow -n --restow --ignore=^\\.DS_Store\$ -d $W/pub -t $W/home runcom" "$W/log" &&
   grep -qxF -- "stow -n --restow --ignore=^\\.DS_Store\$ -d $W/pub -t $W/home/.config config" "$W/log" &&
   grep -qxF -- "stow --restow --ignore=^\\.DS_Store\$ -d $W/pub -t $W/home runcom" "$W/log" &&
   grep -qxF -- "stow --restow --ignore=^\\.DS_Store\$ -d $W/pub -t $W/home/.config config" "$W/log"'
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
t "S4.10" "a raycast Mac: the sync bundle check and bundle install see HOMEBREW_DOTFILES_LAUNCHER=raycast" '
  W=$(senv); _actions "$W"; mkdir -p "$W/pub/macos"; printf "DOTFILES_LAUNCHER=raycast\n" >"$W/pub/macos/machine.local.sh"
  stub "$W/bin" brew "case \"\$*\" in
  \"bundle check\"*) echo \"seen-check \${HOMEBREW_DOTFILES_LAUNCHER-unset}\" >>\"\$STUB_LOG\"; [ -f \"\$STUB_STATE/unsatisfied\" ] && exit 1 ;;
  \"bundle install\"*) echo \"seen-install \${HOMEBREW_DOTFILES_LAUNCHER-unset}\" >>\"\$STUB_LOG\" ;;
esac
exit 0"
  sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1
  grep -qx "seen-check raycast" "$W/log" && grep -qx "seen-install raycast" "$W/log" &&
  [ "$(grep -c "seen-.* tinycast\|seen-.* unset" "$W/log")" -eq 0 ]'
t "S4.6" "secrets.age changing upstream is only reported: no import, no prompt" '
  W=$(senv); push_change "$W" priv secrets.age "age"; out=$(sy_env "DOTFILES_YES=1" syn 2>&1)
  printf "%s\n" "$out" | grep -q "dotfiles secrets import" && [ "$(_calls "secrets")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ]'
t "S4.7" "the private repo changing claude/*.local.list calls for install --claude" '
  W=$(senv); push_change "$W" priv claude/work.local.list "m"; sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; grep -qx "dotfiles-stub install --claude" "$W/log"'

finish

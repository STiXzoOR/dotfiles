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

finish

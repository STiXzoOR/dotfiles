#!/usr/bin/env bash
#
# Machine identity: what kind of Mac this is, what it is called, its launcher.
#
# Sourced by macos/defaults.sh, bin/dotfiles, bin/dotfiles-apps and bin/dotfiles-sync. No
# side effects on load. Both helpers use only tools the BSD userland has, so
# they work under launchd and `bash script.sh`.

# desktop | laptop.
#
# `desktop` needs a positive marker: pmset -g batt must say `AC Power` or `Now
# drawing from` and must not list an InternalBattery. Anything else (empty or
# garbled output, pmset missing or failing) is `laptop`, the role whose
# settings are never forced, so a failed probe cannot switch on Remote Login
# or change power settings. DOTFILES_MACHINE_ROLE=desktop|laptop overrides;
# any other value warns once and detection runs.
dotfiles_machine_role() {
  case "${DOTFILES_MACHINE_ROLE:-}" in
    desktop | laptop)
      printf '%s\n' "$DOTFILES_MACHINE_ROLE"
      return 0
      ;;
    "") ;;
    *)
      printf 'warning: ignoring DOTFILES_MACHINE_ROLE=%s (use desktop or laptop); detecting the role\n' "$DOTFILES_MACHINE_ROLE" >&2
      ;;
  esac

  local batt
  if ! batt=$(pmset -g batt 2>/dev/null); then
    printf 'laptop\n'
    return 0
  fi
  case "$batt" in
    *InternalBattery*) printf 'laptop\n' ;;
    *"AC Power"* | *"Now drawing from"*) printf 'desktop\n' ;;
    *) printf 'laptop\n' ;;
  esac
}

# This Mac's name, for per-machine folders. DOTFILES_MACHINE_NAME wins, else
# LocalHostName; anything outside [A-Za-z0-9-] becomes '-'.
dotfiles_machine_name() {
  local n="${DOTFILES_MACHINE_NAME:-}"
  [ -n "$n" ] || n=$(scutil --get LocalHostName 2>/dev/null)
  n=$(printf '%s' "$n" | tr -c 'A-Za-z0-9-' '-')
  if [ -z "$n" ]; then
    printf "cannot work out this Mac's name; set DOTFILES_MACHINE_NAME\n" >&2
    return 1
  fi
  printf '%s' "$n"
}

# tinycast | raycast: which launcher this Mac uses.
#
# DOTFILES_LAUNCHER from the environment, else from macos/machine.local.sh
# (per Mac, gitignored, never synced), else from macos/local.sh (shared through
# the private repo), else tinycast. Any other value warns once and becomes
# tinycast, which is also what the Brewfile does with an unknown value.
# Takes the dotfiles dir as $1, else DOTFILES_DIR, else ~/.dotfiles. The files
# are read in a subshell, so nothing they set leaks into the caller.
dotfiles_launcher() {
  local dir="${1:-${DOTFILES_DIR:-$HOME/.dotfiles}}" v="${DOTFILES_LAUNCHER:-}" f
  for f in machine.local.sh local.sh; do
    [ -n "$v" ] && break
    [ -f "$dir/macos/$f" ] || continue
    # shellcheck disable=SC1090
    v=$(unset DOTFILES_LAUNCHER; . "$dir/macos/$f" >/dev/null 2>&1; printf '%s' "${DOTFILES_LAUNCHER:-}")
  done
  case "$v" in
    tinycast | raycast) printf '%s\n' "$v" ;;
    "") printf 'tinycast\n' ;;
    *)
      printf 'warning: ignoring DOTFILES_LAUNCHER=%s (use tinycast or raycast); using tinycast\n' "$v" >&2
      printf 'tinycast\n'
      ;;
  esac
}

# Export the resolved launcher where `brew bundle` can see it. brew hides every
# variable that does not start with HOMEBREW_ from the Brewfile, so this is
# HOMEBREW_DOTFILES_LAUNCHER. Call it before any `brew bundle check|install`.
dotfiles_export_launcher() {
  HOMEBREW_DOTFILES_LAUNCHER=$(dotfiles_launcher "$@")
  export HOMEBREW_DOTFILES_LAUNCHER
}

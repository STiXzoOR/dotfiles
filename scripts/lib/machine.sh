#!/usr/bin/env bash
#
# Machine identity: what kind of Mac this is and what it is called.
#
# Sourced by macos/defaults.sh, bin/dotfiles-apps and bin/dotfiles-sync. No
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

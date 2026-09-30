#!/usr/bin/env bash
#
# macos/dock.sh - rebuild the Dock from a declared list of applications.
#
# Sourced by `dotfiles configure --dock`, so it carries no `set -e` and no
# bare `return`: a return here would return out of the calling function and
# skip its own completion message.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"
# Prefix for the app paths; empty on a real Mac, a sandbox in the tests.
DOCK_ROOT="${DOTFILES_DOCK_ROOT:-}"
# Seconds to wait (bounded) for the Dock to come back and stop rewriting its
# preferences after a restart.
DOCK_SETTLE_TIMEOUT="${DOTFILES_DOCK_SETTLE_TIMEOUT:-10}"
# Set to 1 when the Dock could not be brought to the declared state; the
# caller turns it into a non-zero status.
DOTFILES_DOCK_FAILED=0

source "$DOTFILES_DIR/scripts/echos.sh"

# Apps.app replaced Launchpad in macOS 26 Tahoe. Notion was dropped because it
# is not installed; dockutil exits non-zero on a missing bundle and the old
# loop swallowed that, leaving a Dock short while the run still reported
# success. Spark Mail comes from Setapp (the `setapp` cask), so it lives under
# /Applications/Setapp. An app that is not installed yet is an info line, not a
# warning: re-run `dotfiles configure --dock` once it is.
Icons=(
  "/System/Applications/Apps.app"
  "/Applications/Brave Browser.app"
  "/Applications/Google Chrome.app"
  "/Applications/Slack.app"
  "/System/Applications/Calendar.app"
  "/System/Applications/Notes.app"
  "/Applications/Figma.app"
  "/Applications/WebStorm.app"
  "/Applications/Warp.app"
  "/System/Applications/System Settings.app"
  "/Applications/Setapp/Spark Mail.app"
)

# Wait until the Dock process is running and its list has stopped changing.
# defaults.sh restarts the Dock just before this runs, and a relaunching Dock
# writes its old state back over any edit made while it comes up: that is how
# the Dock ended up with only Apps and Brave on a fresh Mac. Bounded by
# DOCK_SETTLE_TIMEOUT seconds; returns 1 if the Dock never settled.
_dock_settle() {
  local i=0 prev="" cur="" have_prev=0
  while [ "$i" -lt "$DOCK_SETTLE_TIMEOUT" ]; do
    if pgrep -x Dock >/dev/null 2>&1; then
      cur=$(dockutil --list 2>/dev/null)
      # An empty list is fine as long as it is stable.
      [ "$have_prev" -eq 1 ] && [ "$cur" = "$prev" ] && return 0
      prev="$cur"
      have_prev=1
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

# Build the Dock once (no restart). Fills dock_expected with the labels of the
# installed apps that were added, and dock_absent with the ones not installed.
_dock_build() {
  local icon
  dock_expected=()
  dock_absent=()

  running "Clearing the Dock"
  if dockutil --no-restart --remove all >/dev/null 2>&1; then
    ok
  else
    error "dockutil could not clear the Dock"
    DOTFILES_DOCK_FAILED=1
  fi

  for icon in "${Icons[@]}"; do
    if [ ! -d "$DOCK_ROOT$icon" ]; then
      dock_absent+=("$(basename "$icon" .app)")
      continue
    fi

    running "Adding $(basename "$icon" .app)"
    if dockutil --no-restart --add "$DOCK_ROOT$icon" >/dev/null 2>&1; then
      ok
      dock_expected+=("$(basename "$icon" .app)")
    else
      error "dockutil could not add $icon"
      DOTFILES_DOCK_FAILED=1
    fi
  done

  running "Adding the Downloads stack"
  if dockutil --no-restart --add "$HOME/Downloads" --view fan --display stack >/dev/null 2>&1; then
    ok
  else
    error "dockutil could not add $HOME/Downloads"
    DOTFILES_DOCK_FAILED=1
  fi
}

# Restart the Dock, wait for it, and set dock_lost to the expected apps that
# `dockutil --list` does not show.
_dock_restart_and_check() {
  local label listing
  killall "Dock" >/dev/null 2>&1
  _dock_settle || warn "the Dock did not settle within ${DOCK_SETTLE_TIMEOUT}s"
  listing=$(dockutil --list 2>/dev/null)
  dock_lost=()
  for label in ${dock_expected[@]+"${dock_expected[@]}"}; do
    grep -q "^$label"$'\t' <<<"$listing" || dock_lost+=("$label")
  done
}

if ! command -v dockutil >/dev/null 2>&1; then
  error "dockutil is not installed, so the Dock was left alone (brew bundle install)"
  DOTFILES_DOCK_FAILED=1
else
  dock_expected=()
  dock_absent=()
  dock_lost=()

  _dock_settle || warn "the Dock did not settle within ${DOCK_SETTLE_TIMEOUT}s; editing it anyway"
  _dock_build
  _dock_restart_and_check
  if [ "${#dock_lost[@]}" -gt 0 ]; then
    warn "the Dock lost entries after restarting (${dock_lost[*]}); rebuilding once"
    _dock_build
    _dock_restart_and_check
  fi

  for label in ${dock_absent[@]+"${dock_absent[@]}"}; do
    skip "skipped (not installed yet): $label: run \`dotfiles configure --dock\` after installing it"
  done
  if [ "${#dock_lost[@]}" -gt 0 ]; then
    error "the Dock is missing ${#dock_lost[@]} expected entries: ${dock_lost[*]}; run \`dotfiles configure --dock\` again"
    DOTFILES_DOCK_FAILED=1
  fi
fi

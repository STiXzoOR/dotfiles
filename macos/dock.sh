#!/usr/bin/env bash
#
# macos/dock.sh - rebuild the Dock from a declared list of applications.
#
# Sourced by `dotfiles configure --dock`, so it carries no `set -e` and no
# bare `return`: a return here would return out of the calling function and
# skip its own completion message.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"

# Apps.app replaced Launchpad in macOS 26 Tahoe. Spark and Notion were dropped
# because neither is installed; dockutil exits non-zero on a missing bundle and
# the old loop swallowed that, leaving a Dock short three icons while the run
# still reported success.
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
)

if ! command -v dockutil >/dev/null 2>&1; then
  error "dockutil is not installed, so the Dock was left alone (brew bundle install)"
else
  dock_missing=0

  running "Clearing the Dock"
  if dockutil --no-restart --remove all >/dev/null 2>&1; then
    ok
  else
    error "dockutil could not clear the Dock"
  fi

  for icon in "${Icons[@]}"; do
    if [ ! -d "$icon" ]; then
      warn "not installed, skipped: $icon"
      dock_missing=$((dock_missing + 1))
      continue
    fi

    running "Adding $(basename "$icon" .app)"
    if dockutil --no-restart --add "$icon" >/dev/null 2>&1; then
      ok
    else
      error "dockutil could not add $icon"
      dock_missing=$((dock_missing + 1))
    fi
  done

  running "Adding the Downloads stack"
  if dockutil --no-restart --add "$HOME/Downloads" --view fan --display stack >/dev/null 2>&1; then
    ok
  else
    error "dockutil could not add $HOME/Downloads"
  fi

  if [ "$dock_missing" -gt 0 ]; then
    warn "$dock_missing Dock entries could not be added; see the lines above"
  fi

  killall "Dock" >/dev/null 2>&1
fi

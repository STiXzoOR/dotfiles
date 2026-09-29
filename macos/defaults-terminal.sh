#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.
# Warp has its own file, defaults-warp.sh.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Terminal"
###############################################################################

running "Only use UTF-8 in Terminal.app"
defaults write com.apple.terminal StringEncodings -array 4
ok

# The theme is a git submodule. When it has not been checked out there is
# nothing to open, and selecting a profile that was never imported would leave
# Terminal.app on a profile that does not exist.
TERM_THEME_SRC="$DOTFILES_DIR/apps/terminal/nord_theme/src/xml/Nord.terminal"
TERM_THEME_OK=0

running "Install nord theme in Terminal.app"
if [ ! -f "$TERM_THEME_SRC" ]; then
  warn "Nord theme not found at $TERM_THEME_SRC (git submodule update --init --recursive); skipped"
else
  open "$TERM_THEME_SRC"
  sleep 1
  TERM_THEME_OK=1
  ok
fi

running "Use nord theme by default in Terminal.app"
if [ "$TERM_THEME_OK" = 1 ]; then
  TERM_PROFILE='Nord'
  CURRENT_PROFILE="$(defaults read com.apple.terminal 'Default Window Settings')"
  if [ "${CURRENT_PROFILE}" != "${TERM_PROFILE}" ]; then
    defaults write com.apple.terminal 'Default Window Settings' -string "${TERM_PROFILE}"
    defaults write com.apple.terminal 'Startup Window Settings' -string "${TERM_PROFILE}"
  fi
  ok
else
  skip "the theme is not installed"
fi

running "Enable 'focus follows mouse' for Terminal.app and all X11 apps"
defaults write com.apple.terminal FocusFollowsMouse -bool true
ok

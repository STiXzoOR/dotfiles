#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "VLC"
###############################################################################

running "Install vlcrc"
# stderr is no longer discarded: a failed copy used to print [ok] over an
# unchanged VLC configuration.
#
# Only vlcrc is shipped. apps/vlc/org.videolan.vlc.plist was deliberately
# untracked in ef649e6, so copying it made this step fail on every run.
if mkdir -p "$HOME/Library/Preferences/org.videolan.vlc" &&
  cp -f "$DOTFILES_DIR/apps/vlc/vlcrc" "$HOME/Library/Preferences/org.videolan.vlc/"; then
  ok
else
  error "could not install vlcrc into ~/Library/Preferences/org.videolan.vlc"
fi

killall "VLC" >/dev/null 2>&1

#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Spotify"
###############################################################################

running "Change theme to nord"
spicetify config current_theme Nord 2>/dev/null
spicetify backup apply 2>/dev/null
ok

killall "Spotify" >/dev/null 2>&1

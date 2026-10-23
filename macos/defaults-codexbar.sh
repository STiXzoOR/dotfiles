#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "CodexBar"
###############################################################################
# CodexBar's iCloud sync carries most of its settings; bin/dotfiles-codexbar
# writes the rest (provider data sources, menu-bar layout, the iCloud Sync
# switch) from apps/codexbar/settings.json. It prints its own status. Exit 2
# means CodexBar has never run here, so it has no config to write into yet:
# that is a fresh Mac, not a failure.
"$DOTFILES_DIR/bin/dotfiles-codexbar" apply
case $? in
  0 | 2) ;;
  *) DOTFILES_DEFAULTS_FAILURES=$((${DOTFILES_DEFAULTS_FAILURES:-0} + 1)) ;;
esac

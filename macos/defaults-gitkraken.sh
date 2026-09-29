#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "GitKraken"
###############################################################################
GITKRAKEN_DIR="$HOME/.gitkraken"

# The theme is a git submodule. When it has not been checked out the source is
# missing, and linking to it would create a dangling symlink that reports ok.
GITKRAKEN_THEME_SRC="$DOTFILES_DIR/apps/gitkraken/themes/Themes/Nord/nord-dark.jsonc"

running "Install nord theme"
# mkdir first: without it the link fails whenever GitKraken has not created
# its themes directory yet, which would make this step red for a reason the
# script can fix itself.
if [ ! -f "$GITKRAKEN_THEME_SRC" ]; then
  warn "Nord theme not found at $GITKRAKEN_THEME_SRC (git submodule update --init --recursive); skipped"
else
  rm -f "$GITKRAKEN_DIR/themes/nord-dark.jsonc" 2>/dev/null
  if mkdir -p "$GITKRAKEN_DIR/themes" &&
    ln -sf "$GITKRAKEN_THEME_SRC" "$GITKRAKEN_DIR/themes/nord-dark.jsonc"; then
    ok
  else
    error "could not link the Nord theme into $GITKRAKEN_DIR/themes"
  fi
fi

running "Seed profile(s) from template"
# The live profile is untracked: it holds userEmail/userName and every local
# repo path, and this repo is public. Seed it from the sanitized template only
# when it is missing, so an existing profile is never clobbered.
GITKRAKEN_PROFILE_TEMPLATE="$DOTFILES_DIR/apps/gitkraken/profile.template"
for _gk_profile_dir in "$DOTFILES_DIR"/apps/gitkraken/profiles/*/; do
  [ -d "$_gk_profile_dir" ] || continue
  if [ ! -f "$_gk_profile_dir/profile" ] && [ -f "$GITKRAKEN_PROFILE_TEMPLATE" ]; then
    cp "$GITKRAKEN_PROFILE_TEMPLATE" "$_gk_profile_dir/profile"
  fi
done
unset _gk_profile_dir
ok

running "Link profile(s)"
# Only replace the live profiles directory when there is something to link to.
if [ ! -d "$DOTFILES_DIR/apps/gitkraken/profiles" ]; then
  warn "$DOTFILES_DIR/apps/gitkraken/profiles not found; the existing profiles were left alone"
else
  rm -rf "$GITKRAKEN_DIR/profiles" 2>/dev/null
  if mkdir -p "$GITKRAKEN_DIR" &&
    ln -sf "$DOTFILES_DIR/apps/gitkraken/profiles" "$GITKRAKEN_DIR/profiles"; then
    ok
  else
    error "could not link the GitKraken profiles"
  fi
fi

killall "GitKraken" >/dev/null 2>&1

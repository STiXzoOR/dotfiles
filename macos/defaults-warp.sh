#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Warp"
###############################################################################

WARP_DIR="$HOME/.warp"
WARP_THEME_DIR="$WARP_DIR/themes"
WARP_THEME_SRC="$DOTFILES_DIR/apps/warp/themes"

running "Create warp custom theme folder"
if mkdir -p "$WARP_THEME_DIR/"; then
  ok
else
  error "could not create $WARP_THEME_DIR"
fi

# _warp_has_yaml <dir> -- does the directory hold at least one theme?
_warp_has_yaml() {
  local f
  for f in "$1"/*.yaml; do
    [ -f "$f" ] && return 0
  done
  return 1
}

# The themes are a git submodule. Copy them into a staging directory first and
# only then replace the installed ones, so a missing or half-checked-out source
# can never leave Warp with fewer themes than it had.
running "Install themes for Warp"
if ! _warp_has_yaml "$WARP_THEME_SRC/standard" || ! _warp_has_yaml "$WARP_THEME_SRC/base16"; then
  warn "Warp themes not found under $WARP_THEME_SRC (git submodule update --init --recursive); the installed themes were left alone"
else
  _warp_stage=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-warp.XXXXXX")
  if [ -n "$_warp_stage" ] &&
    cp "$WARP_THEME_SRC/standard"/*.yaml "$_warp_stage/" &&
    cp "$WARP_THEME_SRC/base16"/*.yaml "$_warp_stage/" &&
    rm -f "$WARP_THEME_DIR"/*.yaml &&
    cp "$_warp_stage"/*.yaml "$WARP_THEME_DIR/"; then
    ok
  else
    error "could not install the Warp themes"
  fi
  [ -n "$_warp_stage" ] && rm -rf "$_warp_stage"
  unset _warp_stage
fi

# Settings. apps/warp/settings.toml names the theme as ~/.warp/themes/..., which
# Warp is not known to expand, so the path is rendered to this machine's HOME
# here. An existing settings file is never overwritten: Warp rewrites it
# itself, so anything that differs is the owner's and is left alone.
running "Install Warp settings"
WARP_SETTINGS_SRC="$DOTFILES_DIR/apps/warp/settings.toml"
WARP_SETTINGS="$WARP_DIR/settings.toml"
if [ ! -f "$WARP_SETTINGS_SRC" ]; then
  warn "$WARP_SETTINGS_SRC not found; Warp settings skipped"
else
  _warp_home=$(printf '%s' "$HOME" | sed 's/[|&\\]/\\&/g')
  _warp_render=$(mktemp "${TMPDIR:-/tmp}/dotfiles-warp-settings.XXXXXX")
  sed "s|\"~/|\"$_warp_home/|g" "$WARP_SETTINGS_SRC" >"$_warp_render"
  if [ ! -e "$WARP_SETTINGS" ]; then
    if mkdir -p "$WARP_DIR" && cp "$_warp_render" "$WARP_SETTINGS"; then
      ok
    else
      error "could not install $WARP_SETTINGS"
    fi
  elif cmp -s "$_warp_render" "$WARP_SETTINGS"; then
    ok "already up to date"
  else
    warn "$WARP_SETTINGS differs from the repo copy and was left alone (compare with apps/warp/settings.toml)"
  fi
  rm -f "$_warp_render"
  unset _warp_home _warp_render
fi

killall "Warp" >/dev/null 2>&1

#!/usr/bin/env bash
# scripts/lib/xcode.sh -- keep brew usable on a Mac that gets Xcode mid-install.
#
# The Brewfile's `mas "Xcode"` installs Xcode part way through a bundle and
# xcode-select then switches to it. From that moment every brew command exits
# with "You have not agreed to the Xcode license" until someone runs
# `sudo xcodebuild -license accept`, so the rest of the bundle, brew cleanup
# and every later step fail. Xcode is therefore installed and licensed first,
# and the licence is re-checked before anything else that shells out to brew.
#
# Sourced by bin/dotfiles. Bash 3.2; nothing here may end the step, a failure
# only warns (callers provide warn/action from scripts/echos.sh).

# DOTFILES_XCODE_APP exists so the tests never touch the real Xcode.
dotfiles_xcode_app() { printf '%s' "${DOTFILES_XCODE_APP:-/Applications/Xcode.app}"; }

# Every xcodebuild call names the app through DEVELOPER_DIR: with only the
# Command Line Tools selected a bare `xcodebuild -license check` fails with
# "requires Xcode", which would prompt for sudo for nothing. This is right
# whichever developer directory xcode-select has selected.
_dfx_xcodebuild() { DEVELOPER_DIR="$(dotfiles_xcode_app)/Contents/Developer" xcodebuild "$@"; }
_dfx_sudo_xcodebuild() { sudo env DEVELOPER_DIR="$(dotfiles_xcode_app)/Contents/Developer" xcodebuild "$@"; }

# Accept the licence if Xcode is installed and has not been accepted yet.
# Returns non-zero only when an accept was needed and failed.
dotfiles_xcode_accept_license() {
  [ -d "$(dotfiles_xcode_app)" ] || return 0
  _dfx_xcodebuild -license check >/dev/null 2>&1 && return 0
  action "accepting the Xcode licence (sudo)"
  _dfx_sudo_xcodebuild -license accept || {
    warn "could not accept the Xcode licence; run: sudo xcodebuild -license accept"
    return 1
  }
}

# First launch installs the components Xcode needs; done once.
dotfiles_xcode_first_launch() {
  [ -d "$(dotfiles_xcode_app)" ] || return 0
  _dfx_xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 && return 0
  action "running Xcode first launch (sudo)"
  _dfx_sudo_xcodebuild -runFirstLaunch || warn "xcodebuild -runFirstLaunch failed"
  return 0
}

# dotfiles_xcode_prepare <Brewfile>... -- install Xcode first when a Brewfile
# declares it through mas, then make sure its licence is accepted and first
# launch is done. On a fresh Mac mas itself comes from the Brewfile, so it is
# installed first (brew still works while Xcode is absent).
dotfiles_xcode_prepare() {
  _dfx_id=$(sed -n -E 's/^mas "Xcode", id: ([0-9]+).*/\1/p' "$@" 2>/dev/null | sed -n 1p)
  if [ -n "$_dfx_id" ] && [ ! -d "$(dotfiles_xcode_app)" ]; then
    if ! command -v mas >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
      action "installing mas first, to install Xcode before the bundle"
      brew install mas || warn "could not install mas"
    fi
    if command -v mas >/dev/null 2>&1; then
      action "installing Xcode first, so its licence can be accepted before brew runs"
      mas install "$_dfx_id" ||
        warn "mas could not install Xcode (App Store sign-in, or the download); the licence step is deferred until after the bundle"
    else
      warn "mas is not available; the Xcode licence step is deferred until after the bundle"
    fi
  fi
  if [ -d "$(dotfiles_xcode_app)" ] && dotfiles_xcode_accept_license; then
    dotfiles_xcode_first_launch
  fi
  unset _dfx_id
  return 0
}

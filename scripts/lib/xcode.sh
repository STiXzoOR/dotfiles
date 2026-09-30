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

# Accept the licence if Xcode is installed and has not been accepted yet.
dotfiles_xcode_accept_license() {
  [ -d "$(dotfiles_xcode_app)" ] || return 0
  xcodebuild -license check >/dev/null 2>&1 && return 0
  action "accepting the Xcode licence (sudo)"
  sudo xcodebuild -license accept || {
    warn "could not accept the Xcode licence; run: sudo xcodebuild -license accept"
    return 1
  }
}

# dotfiles_xcode_prepare <Brewfile>... -- install Xcode first when a Brewfile
# declares it through mas, then make sure its licence is accepted.
dotfiles_xcode_prepare() {
  _dfx_id=$(sed -n -E 's/^mas "Xcode", id: ([0-9]+).*/\1/p' "$@" 2>/dev/null | sed -n 1p)
  if [ -n "$_dfx_id" ] && [ ! -d "$(dotfiles_xcode_app)" ]; then
    if command -v mas >/dev/null 2>&1; then
      action "installing Xcode first, so its licence can be accepted before brew runs"
      mas install "$_dfx_id" || warn "mas could not install Xcode; sign in to the App Store and re-run"
    else
      warn "mas is not installed yet; Xcode will come with the bundle"
    fi
    if [ -d "$(dotfiles_xcode_app)" ]; then
      dotfiles_xcode_accept_license
      sudo xcodebuild -runFirstLaunch || warn "xcodebuild -runFirstLaunch failed"
    fi
  else
    dotfiles_xcode_accept_license
  fi
  unset _dfx_id
  return 0
}

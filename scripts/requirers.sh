#!/usr/bin/env bash

###
# convenience methods for requiring installed software
# @author Adam Eivy
###

function source_brew() {
  if [[ -z "${HOMEBREW_PREFIX}" ]]; then
    if [[ "$(uname -m)" == "arm64" ]]; then
      HOMEBREW_PREFIX="/opt/homebrew"
    else
      HOMEBREW_PREFIX="/usr/local"
    fi
  fi

  eval "$("$HOMEBREW_PREFIX"/bin/brew shellenv)"
}

function require_tap() {
  running "tap $1"
  if [[ $(brew tap | grep -x "$1") != "$1" ]]; then
    action "brew tap $1"
    if ! brew tap "$1"; then
      error "failed to tap $1!"
    fi
  fi
  ok
}

function require_cask() {
  running "cask $1"
  if ! brew list --cask "$1" >/dev/null 2>&1; then
    action "brew install --cask $1"
    if ! brew install --cask "$1"; then
      error "failed to install $1!"
    fi
  fi
  ok
}

function require_brew() {
  running "brew $1 $2"
  if ! brew list "$1" >/dev/null 2>&1; then
    action "brew install $1 $2"
    if ! brew install "$1" "$2"; then
      error "failed to install $1!"
    fi
  fi
  ok
}

function require_code() {
  command-exists code || code="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  running "code $1"
  if [[ $(code --list-extensions | grep -x "$1") != "$1" ]]; then
    action "code --install-extension $1"
    code --install-extension "$1"
  fi
  ok
}

function require_mas() {
  running "mas $1"
  if [[ $(mas list | grep "$1" | head -1 | cut -d' ' -f1) != "$1" ]]; then
    action "mas install $1"
    mas install "$1"
  fi
  ok
}

function source_fnm() {
  eval "$(fnm env)"
}

function require_fnm() {
  running "fnm $1"
  source_fnm
  action "fnm install $1"
  fnm install "$1"
  ok
}

function require_npm() {
  source_fnm
  fnm use default >/dev/null 2>&1
  running "npm $*"
  if ! npm list -g --depth 0 | grep "$1"@ >/dev/null; then
    action "npm install -g $*"
    npm install -g "$@"
  fi
  ok
}

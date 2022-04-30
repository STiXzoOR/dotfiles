#!/usr/bin/env bash

###
# convienience methods for requiring installed software
# @author Adam Eivy
###

function source_brew() {
  if ! test -v "HOMEBREW_PREFIX"; then
    if is-apple-silicon; then
      HOMEBREW_PREFIX="/opt/homebrew"
    else
      HOMEBREW_PREFIX="/usr/local"
    fi
  fi

  command-exists brew && eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
}

function require_tap() {
  running "tap $1"
  if [[ $(brew tap | grep -x $1) != $1 ]]; then
    action "brew tap $1"
    brew tap $1
    if [[ $? != 0 ]]; then
      error "failed to tap $1!"
    fi
  fi
  ok
}

function require_cask() {
  running "cask $1"
  brew list --cask $1 >/dev/null 2>&1 | true
  if [[ ${PIPESTATUS[0]} != 0 ]]; then
    action "brew install --cask $1 $2"
    brew install --cask $1
    if [[ $? != 0 ]]; then
      error "failed to install $1!"
    fi
  fi
  ok
}

function require_brew() {
  running "brew $1 $2"
  brew list $1 >/dev/null 2>&1 | true
  if [[ ${PIPESTATUS[0]} != 0 ]]; then
    action "brew install $1 $2"
    brew install $1 $2
    if [[ $? != 0 ]]; then
      error "failed to install $1!"
    fi
  fi
  ok
}

function require_code() {
  command-exists code || code="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  running "code $1"
  if [[ $(code --list-extensions | grep -x $1) != $1 ]]; then
    action "code --install-extension $1"
    code --install-extension $1
  fi
  ok
}

function require_mas() {
  running "mas $1"
  if [[ $(mas list | grep $1 | head -1 | cut -d' ' -f1) != $1 ]]; then
    action "mas install $1"
    mas install $1
  fi
  ok
}

function require_gem() {
  running "gem $1"
  if [[ $(gem list --local | grep $1 | head -1 | cut -d' ' -f1) != $1 ]]; then
    action "gem install $1"
    gem install $1
  fi
  ok
}

function require_npm() {
  source_nvm
  nvm use default &>/dev/null
  running "npm $*"
  npm list -g --depth 0 | grep $1@ >/dev/null
  if [[ $? != 0 ]]; then
    action "npm install -g $*"
    npm install -g $@
  fi
  ok
}

# taken from: https://github.com/lukechilds/zsh-nvm
install_nvm() {
  [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"

  latest_release_tag() {
    echo $(builtin cd "$NVM_DIR" && git fetch --quiet --tags origin && git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1))
  }

  git clone --quiet https://github.com/nvm-sh/nvm.git "$NVM_DIR"
  $(builtin cd "$NVM_DIR" && git checkout --quiet "$(latest_release_tag)")
}

function source_nvm() {
  [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
  [[ -f "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
}

function require_nvm() {
  running "nvm $1"
  source_nvm
  action "nvm install $1"
  nvm install $1
  if [[ $? != 0 ]]; then
    action "installing nvm..."
    install_nvm
    source_nvm
    action "nvm install $1"
    nvm install $1
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
  fnm install $1
  ok
}

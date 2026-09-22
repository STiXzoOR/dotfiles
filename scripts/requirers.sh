#!/usr/bin/env bash

###
# convenience methods for requiring installed software
# @author Adam Eivy
###

# Apple silicon only: the prefix is fixed. See the arch guard in bin/dotfiles.
function source_brew() {
  HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
  eval "$("$HOMEBREW_PREFIX"/bin/brew shellenv)"
}

###
# One contract for every require_* helper: print `ok` only on the success
# path, return 0 when the thing is present or was just installed, non-zero
# otherwise. They used to end in an unconditional `ok`, so a failed install
# printed `[error] failed to install X!` immediately followed by `[ok]` and
# still returned success to the caller.
###

function require_tap() {
  running "tap $1"
  if [[ "$(brew tap | grep -x "$1")" == "$1" ]]; then
    ok
    return 0
  fi

  action "brew tap $1"
  if brew tap "$1"; then
    ok
    return 0
  fi

  error "failed to tap $1!"
  return 1
}

function require_cask() {
  running "cask $1"
  if brew list --cask "$1" >/dev/null 2>&1; then
    ok
    return 0
  fi

  action "brew install --cask $1"
  if brew install --cask "$1"; then
    ok
    return 0
  fi

  error "failed to install cask $1!"
  return 1
}

# "$@", never "$1" "$2": called with one argument the old body ran
# `brew install stow ""`, and brew rejects the empty path outright -- so every
# single-argument call failed on exactly the fresh machine this exists for.
function require_brew() {
  running "brew $*"
  if brew list "$1" >/dev/null 2>&1; then
    ok
    return 0
  fi

  action "brew install $*"
  if brew install "$@"; then
    ok
    return 0
  fi

  error "failed to install $1!"
  return 1
}

function require_code() {
  # The fallback used to be `command-exists code || code="/Applications/..."`,
  # which set a shell *variable* named code while the next line still invoked
  # the code *command*, so the fallback never applied.
  local code_bin
  code_bin=$(command -v code || echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")

  running "code $1"
  if [[ ! -x "$code_bin" ]]; then
    error "no VS Code CLI found at $code_bin"
    return 1
  fi

  if [[ "$("$code_bin" --list-extensions | grep -x "$1")" == "$1" ]]; then
    ok
    return 0
  fi

  action "code --install-extension $1"
  if "$code_bin" --install-extension "$1"; then
    ok
    return 0
  fi

  error "failed to install extension $1!"
  return 1
}

function require_mas() {
  running "mas $1"
  if [[ "$(mas list | grep "$1" | head -1 | cut -d' ' -f1)" == "$1" ]]; then
    ok
    return 0
  fi

  action "mas install $1"
  if mas install "$1"; then
    ok
    return 0
  fi

  error "failed to install $1 from the App Store (mas needs you signed in)!"
  return 1
}

# mise replaces both of the helpers that used to live here: require_fnm, which
# installed one Node version, and require_npm, which ran `npm install -g` once
# per line of packages/npm.list. Everything either of them managed is now
# declared in config/mise/config.toml and installed by one `mise install`.
#
# There is no require_mise_tool: adding a CLI means editing that file and
# committing the regenerated lockfile, not calling an installer per package.

# Put the shims on PATH for the rest of this script. Idempotent, because
# install subcommands call it more than once, and silent when mise has never
# run -- the caller decides whether a missing shims dir is an error.
function source_mise() {
  local shims="$HOME/.local/share/mise/shims"
  case ":$PATH:" in
    *":$shims:"*) return 0 ;;
  esac
  if [[ -d "$shims" ]]; then
    PATH="$shims:$PATH"
    export PATH
  fi
}

function require_mise() {
  running "mise"

  if command -v mise > /dev/null 2>&1; then
    ok
    source_mise
    return 0
  fi

  action "brew install mise"
  if brew install mise; then
    ok
    source_mise
    return 0
  fi

  error "failed to install mise!"
  return 1
}

function require_claude_marketplace() {
  running "marketplace $1"
  if echo "$CLAUDE_MARKETPLACES_CACHE" | grep -Fq "$1"; then
    ok
  else
    if claude plugin marketplace add "$1" 2>>"${CLAUDE_INSTALL_LOG:-/dev/null}"; then
      ok
    else
      warn "failed to add marketplace $1"
      return 1
    fi
  fi
}

function require_claude_plugin() {
  local plugin_name="${1%%@*}"
  running "plugin $1"
  if echo "$CLAUDE_PLUGINS_CACHE" | grep -Fq "$plugin_name"; then
    ok
  else
    if claude plugin install "$1" 2>>"${CLAUDE_INSTALL_LOG:-/dev/null}"; then
      ok
    elif [[ "$1" == *@* ]] &&
      claude plugin install "$plugin_name" 2>>"${CLAUDE_INSTALL_LOG:-/dev/null}"; then
      # A marketplace's id comes from its own marketplace.json and can change
      # upstream, which would otherwise break a pinned plugin@marketplace id.
      ok "resolved $plugin_name without a marketplace qualifier"
    else
      warn "failed to install $1"
      return 1
    fi
  fi
}

#!/usr/bin/env bash
#
# clt.sh - Headless Command Line Tools installer.
#
# Shared by bin/dotfiles (install --clt), bin/dotfiles-setup and
# remote-install.sh. remote-install.sh fetches this file on its own, on a Mac
# that has no git and no clone yet, so it must not depend on echos.sh or any
# other file in the repo. Messages go through the echos helpers when the
# caller already defined them and fall back to plain stderr otherwise.
#
# Sourceable with no side effects, bash 3.2 safe.
#
# Test seams (production values are the defaults):
#   DOTFILES_CLT_SENTINEL      the on-demand sentinel path
#   DOTFILES_CLT_RETRY_SLEEP   seconds between `softwareupdate --list` retries
#   DOTFILES_CLT_KEEPALIVE_INTERVAL  seconds between sudo timestamp refreshes

_dotfiles_clt_say() { # _dotfiles_clt_say <ok|error|action|warn> <message>
  if declare -F "$1" >/dev/null 2>&1; then
    "$1" "$2"
  else
    printf '%s\n' "$2" >&2
  fi
}

# Read `softwareupdate --list` output on stdin and print the Command Line
# Tools label with the highest version. softwareupdate lists labels in no
# fixed order (26.5, 27.0, 26.6 and 27.0, 26.6, 26.5 have both been seen), so
# taking the last line picks the wrong one. A stable label wins over a beta
# of the same version. Prints nothing and returns 1 when there is none.
dotfiles_clt_pick_label() {
  local line label ver entries="" best_ver stable="" beta=""
  local tab=$'\t'

  while IFS= read -r line || [[ -n "$line" ]]; do
    # "* Label: Command Line Tools for Xcode 27.0-27.0" (current) or
    # "* Command Line Tools for Xcode-15.3" (older).
    label=$(printf '%s\n' "$line" |
      sed -E -n 's/^[[:space:]]*\*[[:space:]]*(Label:[[:space:]]*)?(Command Line Tools.*)$/\2/p')
    [[ -n "$label" ]] || continue
    label=$(printf '%s' "$label" | sed -E 's/[[:space:]]+$//')
    # The version is the trailing number after the last "-" or space:
    # "...Xcode 27.0-27.0" and "...Xcode-27.0" both give 27.0. A trailing
    # "beta 3" counter is dropped first, or it would read as version 3.
    ver=$(printf '%s' "$label" |
      sed -E -e 's/[[:space:]-]*[Bb]eta[[:space:]-]*[0-9]*$//' \
        -n -e 's/.*[- ]([0-9]+(\.[0-9]+)*)$/\1/p')
    [[ -n "$ver" ]] || ver=0
    entries="${entries}${ver}${tab}${label}"$'\n'
  done

  [[ -n "$entries" ]] || return 1

  best_ver=$(printf '%s' "$entries" | cut -f1 | /usr/bin/sort -V | tail -n 1)
  while IFS=$'\t' read -r ver label; do
    [[ "$ver" == "$best_ver" ]] || continue
    case "$label" in
      *[Bb]eta*) [[ -n "$beta" ]] || beta="$label" ;;
      *) [[ -n "$stable" ]] || stable="$label" ;;
    esac
  done <<<"$entries"

  if [[ -n "$stable" ]]; then
    printf '%s\n' "$stable"
  else
    printf '%s\n' "$beta"
  fi
}

# Install the Command Line Tools without the GUI dialog. Success when they are
# already there. Returns non-zero, naming `xcode-select --install` as the
# manual fallback, on any failure. The sentinel is removed on every path,
# including an interrupt, and sudo is kept alive meanwhile: a long download can
# outlast the sudo timestamp and stall on a password prompt nobody sees.
_DOTFILES_CLT_SENTINEL_PATH=""
_DOTFILES_CLT_KEEPALIVE_PID=""

_dotfiles_clt_cleanup() {
  if [[ -n "$_DOTFILES_CLT_KEEPALIVE_PID" ]]; then
    kill "$_DOTFILES_CLT_KEEPALIVE_PID" 2>/dev/null || true
    wait "$_DOTFILES_CLT_KEEPALIVE_PID" 2>/dev/null || true
    _DOTFILES_CLT_KEEPALIVE_PID=""
  fi
  if [[ -n "$_DOTFILES_CLT_SENTINEL_PATH" ]]; then
    sudo rm -f "$_DOTFILES_CLT_SENTINEL_PATH"
    _DOTFILES_CLT_SENTINEL_PATH=""
  fi
}

_dotfiles_clt_on_signal() { # _dotfiles_clt_on_signal <signal>
  _dotfiles_clt_cleanup
  # This function owns INT/TERM while it runs and replaces any caller trap.
  trap - INT TERM
  kill -s "$1" "$$"
}

dotfiles_install_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    _dotfiles_clt_say ok "Command Line Tools already installed"
    return 0
  fi

  _dotfiles_clt_say action "installing the Command Line Tools"

  # softwareupdate only offers the Command Line Tools while this file exists.
  local sentinel="${DOTFILES_CLT_SENTINEL:-/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress}"
  local rc=0
  sudo touch "$sentinel" || {
    _dotfiles_clt_say error "could not create $sentinel; run: xcode-select --install"
    return 1
  }
  _DOTFILES_CLT_SENTINEL_PATH="$sentinel"
  # dotfiles_install_clt owns INT/TERM for its duration and replaces any
  # caller trap (none exist in this repo).
  trap '_dotfiles_clt_on_signal INT' INT
  trap '_dotfiles_clt_on_signal TERM' TERM
  # stdio is detached so a caller's `$(...)` does not wait on the sleep, and
  # TERM takes the sleep down with the loop. It also ends when the parent is
  # gone (SIGKILL runs no trap), or it would keep sudo warm forever.
  local parent=$$
  (
    nap=""
    trap 'kill "$nap" 2>/dev/null; exit 0' TERM
    while :; do
      sleep "${DOTFILES_CLT_KEEPALIVE_INTERVAL:-30}" &
      nap=$!
      wait "$nap"
      kill -0 "$parent" 2>/dev/null || exit 0
      sudo -n true 2>/dev/null || exit 0
    done
  ) >/dev/null 2>&1 </dev/null &
  _DOTFILES_CLT_KEEPALIVE_PID=$!
  _dotfiles_clt_install_locked || rc=1
  _dotfiles_clt_cleanup
  trap - INT TERM # restores the default: see the note at the traps above
  return "$rc"
}

_dotfiles_clt_install_locked() {
  local label="" attempt=1 xc_path

  # The first listing after a fresh boot often comes back empty.
  while [[ $attempt -le 3 ]]; do
    label=$(softwareupdate --list 2>/dev/null | dotfiles_clt_pick_label)
    [[ -n "$label" ]] && break
    attempt=$((attempt + 1))
    [[ $attempt -le 3 ]] && sleep "${DOTFILES_CLT_RETRY_SLEEP:-3}"
  done

  if [[ -z "$label" ]]; then
    _dotfiles_clt_say error "softwareupdate offered no Command Line Tools package; run: xcode-select --install"
    return 1
  fi

  if ! sudo softwareupdate --install "$label" --agree-to-license; then
    _dotfiles_clt_say error "Command Line Tools install failed; run: xcode-select --install"
    return 1
  fi

  if ! sudo xcode-select -s /Library/Developer/CommandLineTools ||
    ! xcode-select -p >/dev/null 2>&1; then
    _dotfiles_clt_say error "Command Line Tools are not selected; run: xcode-select --install"
    return 1
  fi
  _dotfiles_clt_say ok "Command Line Tools installed"

  # xcodebuild needs full Xcode. With only the Command Line Tools it is a shim
  # that errors out, so the licence is accepted only for a real Xcode.app.
  xc_path=$(xcode-select -p 2>/dev/null)
  if [[ "$xc_path" == *"Xcode.app"* ]]; then
    if sudo xcodebuild -license accept; then
      _dotfiles_clt_say ok "Xcode licence accepted"
    else
      _dotfiles_clt_say error "could not accept the Xcode licence"
      return 1
    fi
  fi
  return 0
}

#!/usr/bin/env bash
#
# Shared by macos/defaults.sh and macos/defaults-remote-access.sh, which are
# both sourced by `dotfiles configure`. Source scripts/echos.sh first. Defines
# the step helpers and the one firewall routine, so the two files cannot drift.

# Absolute-path binary, overridable so the tests can stub it.
FIREWALL_CTL="${DOTFILES_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"

# scripts/echos.sh prints a bare "[error]" when print_result has no message.
# Here every error line names the step that failed and says what to do, so
# running() remembers its title and print_result uses it.
DOTFILES_STEP=""
running() {
  DOTFILES_STEP="${1:-}"
  echo -en "${COL_YELLOW} ⇒ ${COL_RESET}${1:-}: "
}
print_result() {
  if [[ "${1:-1}" -eq 0 ]]; then
    ok "${2:-}"
  else
    error "${2:-"${DOTFILES_STEP:-a step} failed (exit ${1:-1}); fix what the output above says, then run \`dotfiles configure --defaults\` again"}"
  fi
}

# The application firewall on, stealth mode on, both read back. Each failed
# read-back adds one to DOTFILES_DEFAULTS_FAILURES.
#
# /Library/Preferences/com.apple.alf.plist was removed in macOS 15, so
# `defaults write com.apple.alf ...` is dead code and socketfilterfw is the only
# supported control. The setters exit 0 even when they change nothing (no Full
# Disk Access), so each result is read back.
dotfiles_firewall_on() {
  running "Turn the application firewall on"
  sudo "$FIREWALL_CTL" --setglobalstate on >/dev/null 2>&1
  print_result $?

  running "Turn stealth mode on (no reply to unsolicited probes)"
  sudo "$FIREWALL_CTL" --setstealthmode on >/dev/null 2>&1
  print_result $?

  # State = 1 is on and State = 2 is "block all incoming connections", which is
  # on with a stricter filter; only State = 0 (or no answer) is a failure.
  running "Verify the firewall is really on"
  if "$FIREWALL_CTL" --getglobalstate 2>/dev/null | grep -qE "State = [12]"; then
    ok
  else
    error "the application firewall is still off: grant Full Disk Access to this terminal and run again"
    DOTFILES_DEFAULTS_FAILURES=$((DOTFILES_DEFAULTS_FAILURES + 1))
  fi

  running "Verify stealth mode is really on"
  # macOS 26 and earlier print "Stealth mode enabled"; macOS 27 prints "Firewall
  # stealth mode is on". Off reads "disabled" or "is off", neither of which matches.
  if "$FIREWALL_CTL" --getstealthmode 2>/dev/null | grep -qiE "stealth mode (is )?(enabled|on)"; then
    ok
  else
    error "stealth mode is still off: grant Full Disk Access to this terminal and run again"
    DOTFILES_DEFAULTS_FAILURES=$((DOTFILES_DEFAULTS_FAILURES + 1))
  fi
}

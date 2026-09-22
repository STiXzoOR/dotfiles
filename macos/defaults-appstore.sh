#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Mac App Store"
###############################################################################

running "Enable the automatic update check"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
ok

running "Turn on app auto-update"
defaults write com.apple.commerce AutoUpdate -bool true
ok

# The keys above are the user domain. The keys that actually govern update
# behaviour live in /Library/Preferences and need sudo, which is why this
# machine's posture was incidental rather than declared.
#
# ConfigDataInstall and CriticalUpdateInstall are the two that matter most:
# they drive the XProtect, XProtect Remediator and system data file feeds, the
# out-of-band malware signature updates Apple ships between OS releases. The
# earlier note here claimed ConfigDataInstall was deprecated since Catalina.
# It is not; disabling it silently freezes malware definitions.
running "Apply the system-wide software update policy"
if sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ScheduleFrequency -int 1 &&
  sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -int 1; then
  ok
else
  error "could not write the system software update policy"
fi

killall "App Store" >/dev/null 2>&1

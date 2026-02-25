source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Mac App Store"
###############################################################################

running "Enable the automatic update check"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
ok

# ConfigDataInstall: Removed — deprecated since Catalina.
# Security data updates (XProtect, Gatekeeper) are now automatic via Rapid Security Responses.

running "Turn on app auto-update"
defaults write com.apple.commerce AutoUpdate -bool true
ok

killall "App Store" >/dev/null 2>&1

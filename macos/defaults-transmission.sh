#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Transmission"
###############################################################################

running "Use ~/Documents/Torrents to store incomplete downloads"
defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
defaults write org.m0k.transmission IncompleteDownloadFolder -string "${HOME}/Documents/Torrents"
ok

running "Use ~/Downloads to store completed downloads"
defaults write org.m0k.transmission DownloadLocationConstant -bool true
ok

# A magnet: link on any web page starts a download the moment it is clicked
# when these are false. Confirming first is the whole point of the dialog.
running "Prompt for confirmation before downloading"
defaults write org.m0k.transmission DownloadAsk -bool true
defaults write org.m0k.transmission MagnetOpenAsk -bool true
ok

running "Don’t prompt for confirmation before removing non-downloading active transfers"
defaults write org.m0k.transmission CheckRemoveDownloading -bool true
ok

running "Trash original torrent files"
defaults write org.m0k.transmission DeleteOriginalTorrent -bool true
ok

running "Enabling queue"
defaults write org.m0k.transmission Queue -bool true
ok

running "Setting queue maximum downloads"
defaults write org.m0k.transmission QueueDownloadNumber -integer 1
ok

running "Hide the donate message"
defaults write org.m0k.transmission WarningDonate -bool false
ok

running "Hide the legal disclaimer"
defaults write org.m0k.transmission WarningLegal -bool false
ok

# IP blocklist removed. It pointed BlocklistURL at a third-party GitHub raw
# .gz and turned BlocklistAutoUpdate on, which is a standing trust relationship
# with a repository nobody here controls: whoever can push to it can hand this
# machine a new blocklist on a timer. Set a blocklist by hand in Transmission,
# Preferences, Peers if you want one.

running "Randomize port on launch"
defaults write org.m0k.transmission RandomPort -bool true
ok

killall "Transmission" >/dev/null 2>&1

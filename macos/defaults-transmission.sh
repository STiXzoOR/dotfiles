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

running "Don’t prompt for confirmation before downloading"
defaults write org.m0k.transmission DownloadAsk -bool false
defaults write org.m0k.transmission MagnetOpenAsk -bool false
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

running "Setting IP block list"
# Source: https://giuliomac.wordpress.com/2014/02/19/best-blocklist-for-transmission/
defaults write org.m0k.transmission BlocklistNew -bool true
defaults write org.m0k.transmission BlocklistURL -string "http://john.bitsurge.net/public/biglist.p2p.gz"
defaults write org.m0k.transmission BlocklistAutoUpdate -bool true
ok

running "Randomize port on launch"
defaults write org.m0k.transmission RandomPort -bool true
ok

killall "Transmission" >/dev/null 2>&1

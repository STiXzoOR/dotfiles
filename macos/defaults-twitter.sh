source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Twitter"
###############################################################################

running "Disable smart quotes as it’s annoying for code tweets"
defaults write com.twitter.twitter-mac AutomaticQuoteSubstitutionEnabled -bool false
ok

running "Show the app window when clicking the menu bar icon"
defaults write com.twitter.twitter-mac MenuItemBehavior -int 1
ok

running "Enable the hidden ‘Develop’ menu"
defaults write com.twitter.twitter-mac ShowDevelopMenu -bool true
ok

running "Open links in the background"
defaults write com.twitter.twitter-mac openLinksInBackground -bool true
ok

running "Allow closing the ‘new tweet’ window by pressing $(Esc)"
defaults write com.twitter.twitter-mac ESCClosesComposeWindow -bool true
ok

running "Show full names rather than Twitter handles"
defaults write com.twitter.twitter-mac ShowFullNames -bool true
ok

running "Hide the app in the background if it’s not the front-most window"
defaults write com.twitter.twitter-mac HideInBackground -bool true
ok

###############################################################################
bot "Tweetbot"
###############################################################################

running "Bypass the annoyingly slow t.co URL shortener"
defaults write com.tapbots.TweetbotMac OpenURLsDirectly -bool true
ok

killall "Twitter" >/dev/null 2>&1
killall "Tweetbot" >/dev/null 2>&1

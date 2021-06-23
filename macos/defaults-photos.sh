###############################################################################
bot "Photos"
###############################################################################

running "Prevent Photos from opening automatically when devices are plugged in"
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
ok

killall "Photos" >/dev/null 2>&1

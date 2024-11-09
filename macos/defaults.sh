DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"
COMPUTER_NAME="STiXzoOR-MB"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until this script has finished
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

###############################################################################
bot "Configuring System"
###############################################################################
# Close any open System Preferences panes, to prevent them from overriding
# settings we’re about to change
running "closing any system preferences to prevent issues with automated changes"
osascript -e 'tell application "System Preferences" to quit'
ok

###############################################################################
bot "Security"
###############################################################################
running "Enable install from Anywhere"
sudo spctl --master-disable
ok

running "Disable remote apple events"
sudo systemsetup -setremoteappleevents off
ok

running "Disable remote login"
sudo systemsetup -setremotelogin off
ok

running "Disable wake-on modem"
sudo systemsetup -setwakeonmodem off
ok

running "Disable guest account login"
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
ok

################################################
bot "General UI/UX"
################################################
running "Set computer name (as done via System Preferences → Sharing)"
sudo scutil --set ComputerName $COMPUTER_NAME
sudo scutil --set HostName $COMPUTER_NAME
sudo scutil --set LocalHostName $COMPUTER_NAME
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string $COMPUTER_NAME
ok

running "Disable the sound effects on boot"
sudo nvram SystemAudioVolume=" "
ok

running "Set highlight color to steel blue"
defaults write NSGlobalDomain AppleHighlightColor -string "0.172549019607843 0.349019607843137 0,501960784313725"
ok

running "Set sidebar icon size to medium"
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2
ok

running "Always show scrollbars"
defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"
ok
# Possible values: `WhenScrolling`, `Automatic` and `Always`

running "Disable the over-the-top focus ring animation"
defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false
ok

running "Adjust toolbar title rollover delay"
defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0
ok

running "Increase window resize speed for Cocoa applications"
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
ok

running "Expand save panel by default"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
ok

running "Expand print panel by default"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
ok

running "Save to disk (not to iCloud) by default"
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
ok

running "Automatically quit printer app once the print jobs complete"
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true
ok

running "Disable the “Are you sure you want to open this application?” dialog"
defaults write com.apple.LaunchServices LSQuarantine -bool false
ok

running "Remove duplicates in the “Open With” menu (also see 'lscleanup' alias)"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
ok

defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true
ok

running "Disable Resume system-wide"
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
ok

running "Disable automatic termination of inactive apps"
defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true
ok

running "Set Help Viewer windows to non-floating mode"
defaults write com.apple.helpviewer DevMode -bool true
ok

running "Reveal IP, hostname, OS, etc. when clicking clock in login window"
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
ok

running "Disable automatic capitalization as it’s annoying when typing code"
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
ok

running "Disable smart dashes as they’re annoying when typing code"
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
ok

running "Disable automatic period substitution as it’s annoying when typing code"
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
ok

running "Disable smart quotes as they’re annoying when typing code"
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
ok

running "Disable auto-correct"
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
ok

###############################################################################
bot "Trackpad, mouse, keyboard, Bluetooth accessories, and input"
###############################################################################

# running "Trackpad: enable tap to click for this user and for the login screen"
# defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
# defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
# defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1;ok

# running "Trackpad: map bottom right corner to right-click"
# defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
# defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
# defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
# defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true;ok

#running "Increase sound quality for Bluetooth headphones/headsets"
#defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40
#ok

running "Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
ok

running "Use scroll gesture with the Ctrl (^) modifier key to zoom"
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
ok

running "Follow the keyboard focus while zoomed in"
defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
ok

running "Disable press-and-hold for keys in favor of key repeat"
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
ok

running "Set a blazingly fast keyboard repeat rate"
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 10
ok

running "Set language and text formats (english/CY)"
defaults write NSGlobalDomain AppleLanguages -array "en-CY" "el-CY"
defaults write NSGlobalDomain AppleLocale -string "en_CY@currency=EUR"
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
defaults write NSGlobalDomain AppleMetricUnits -bool true
ok

running "Set timezone to Europe/Athens;" #see `sudo systemsetup -listtimezones` for other values
sudo systemsetup -settimezone "Europe/Athens" >/dev/null
ok

###############################################################################
bot "Energy saving"
###############################################################################

running "Disable auto power off"
sudo pmset -a autopoweroff 0
ok

running "Disable auto restart on power loss"
sudo pmset -a autorestart 0
ok

running "Sleep the display after 60 minutes"
sudo pmset -a displaysleep 60
ok

running "Set standby delay to 24 hours (default is 1 hour)"
sudo pmset -a standbydelay 86400
ok

running "Disable wake from iPhone/Watch (eg. When iPhone or Apple Watch come near)"
sudo pmset -a proximitywake 0
ok

running "Disable periodically wake of machine for network and updates"
sudo pmset -a powernap 0
ok

# Hibernation mode
# 0: Disable hibernation (speeds up entering sleep mode)
# 3: Copy RAM to disk so the system state can still be restored in case of a
#    power failure.
running "Disable hibernation (speeds up entering sleep mode)"
sudo pmset -a hibernatemode 0
ok

running "Remove the sleep image file to save disk space"
sudo rm /private/var/vm/sleepimage
ok

running "Create a zero-byte file instead…"
sudo touch /private/var/vm/sleepimage
ok

running "…and make sure it can’t be rewritten"
sudo chflags uchg /private/var/vm/sleepimage
ok

###############################################################################
bot "Screen"
###############################################################################

running "Require password immediately after sleep or screen saver begins"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
ok

running "Save screenshots to the desktop"
defaults write com.apple.screencapture location -string "${HOME}/Desktop"
ok

running "Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)"
defaults write com.apple.screencapture type -string "png"
ok

running "Disable shadow in screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
ok

running "Enable subpixel font rendering on non-Apple LCDs"
# Reference: https://github.com/kevinSuttle/macOS-Defaults/issues/17#issuecomment-266633501
defaults write NSGlobalDomain AppleFontSmoothing -int 1
ok

running "Enable HiDPI display modes (requires restart)"
sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
ok

###############################################################################
bot "Finder"
###############################################################################

running "Allow quitting via ⌘ + Q; doing so will also hide desktop icons"
defaults write com.apple.finder QuitMenuItem -bool true
ok

running "Disable window animations and Get Info animations"
defaults write com.apple.finder DisableAllAnimations -bool true
ok

running "Set Desktop as the default location for new Finder windows"
# For other paths, use 'PfLo' and 'file:///full/path/here/'
defaults write com.apple.finder NewWindowTarget -string "PfDe"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"
ok

running "Show icons for hard drives, servers, and removable media on the desktop"
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
ok

running "Show hidden files by default"
defaults write com.apple.finder AppleShowAllFiles -bool true
ok

running "Show all filename extensions"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
ok

running "Show status bar"
defaults write com.apple.finder ShowStatusBar -bool true
ok

running "Show path bar"
defaults write com.apple.finder ShowPathbar -bool true
ok

running "Keep folders on top when sorting by name"
defaults write com.apple.finder _FXSortFoldersFirst -bool true

running "When performing a search, search the current folder by default"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
ok

running "Disable the warning when changing a file extension"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
ok

running "Enable spring loading for directories"
defaults write NSGlobalDomain com.apple.springing.enabled -bool true
ok

running "Remove the spring loading delay for directories"
defaults write NSGlobalDomain com.apple.springing.delay -float 0
ok

running "Avoid creating .DS_Store files on network or USB volumes"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
ok

running "Disable disk image verification"
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true
ok

running "Automatically open a new Finder window when a volume is mounted"
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
ok

running "Show item info near icons on the desktop and in other icon views"
plistbuddy "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
ok

running "Show item info to the right of the icons on the desktop"
plistbuddy "Set DesktopViewSettings:IconViewSettings:labelOnBottom false" ~/Library/Preferences/com.apple.finder.plist
ok

running "Enable snap-to-grid for icons on the desktop and in other icon views"
plistbuddy "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
ok

running "Increase grid spacing for icons on the desktop and in other icon views"
plistbuddy "Set :DesktopViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
ok

running "Increase the size of icons on the desktop and in other icon views"
plistbuddy "Set :DesktopViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :FK_StandardViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
plistbuddy "Set :StandardViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
ok

running "Use column list view in all Finder windows by default"
# Four-letter codes for the other view modes: `icnv`, `clmv`, `Flwv`
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
ok

running "Use sort by Application in all Finder windows by default"
defaults write com.apple.finder FXPreferredGroupBy -string "Application"
ok

running "Disable the warning before emptying the Trash"
defaults write com.apple.finder WarnOnEmptyTrash -bool false
ok

running "Empty Trash securely by default"
defaults write com.apple.finder EmptyTrashSecurely -bool true
ok

running "Show the ~/Library folder"
chflags nohidden ~/Library && xattr -d com.apple.FinderInfo ~/Library
ok

running "Show the /Volumes folder"
sudo chflags nohidden /Volumes
ok

running "Expand the following File Info panes: “General”, “Open with”, and “Sharing & Permissions”"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
  General -bool true \
  OpenWith -bool true \
  Privileges -bool true
ok

###############################################################################
bot "Dock & Dashboard"
###############################################################################

running "Set the icon size of Dock items to 36 pixels"
defaults write com.apple.dock tilesize -int 36
ok

running "Change minimize/maximize window effect to scale"
defaults write com.apple.dock mineffect -string "scale"
ok

running "Enable magnification"
defaults write com.apple.dock magnification -bool true
ok

running "Minimize windows into their application’s icon"
defaults write com.apple.dock minimize-to-application -bool true
ok

running "Enable spring loading for all Dock items"
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
ok

running "Show indicator lights for open applications in the Dock"
defaults write com.apple.dock show-process-indicators -bool true
ok

running "Speed up Mission Control animations"
defaults write com.apple.dock expose-animation-duration -float 0.1
ok

running "Remove the auto-hiding Dock delay"
defaults write com.apple.dock autohide-delay -float 0
ok

running "Make Dock icons of hidden applications translucent"
defaults write com.apple.dock showhidden -bool true
ok

running "Reset Launchpad, but keep the desktop wallpaper intact"
find "${HOME}/Library/Application Support/Dock" -name "*-*.db" -maxdepth 1 -delete
ok

running "Add iOS & Watch Simulator to Launchpad"
sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" "/Applications/Simulator.app"
sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator (Watch).app" "/Applications/Simulator (Watch).app"
ok

bot "Hot corners"
# Possible values:
#  0: no-op
#  2: Mission Control
#  3: Show application windows
#  4: Desktop
#  5: Start screen saver
#  6: Disable screen saver
#  7: Dashboard
# 10: Put display to sleep
# 11: Launchpad
# 12: Notification Center
# 13: Lock Screen
running "Top left screen corner → Mission Control"
defaults write com.apple.dock wvous-tl-corner -int 2
defaults write com.apple.dock wvous-tl-modifier -int 0
running "Top right screen corner → Desktop"
defaults write com.apple.dock wvous-tr-corner -int 4
defaults write com.apple.dock wvous-tr-modifier -int 0
running "Bottom left screen corner → Start screen saver"
defaults write com.apple.dock wvous-bl-corner -int 5
defaults write com.apple.dock wvous-bl-modifier -int 0

###############################################################################
# bot "Spotlight"
###############################################################################

# running "Hide Spotlight tray-icon (and subsequent helper)"
# sudo chmod 600 /System/Library/CoreServices/Search.bundle/Contents/MacOS/Search;ok

# Issue on macOS Mojave:
# Rich Trouton covers the move of /Volumes to no longer being world writable as of Sierra (10.12)
# https://derflounder.wordpress.com/2016/09/21/macos-sierras-volumes-folder-is-no-longer-world-writable
# running "Disable Spotlight indexing for any volume that gets mounted and has not yet been indexed"
# Use `sudo mdutil -i off "/Volumes/foo"` to stop indexing any volume.
# sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes";ok
# running "Change indexing order and disable some file types from being indexed"
# defaults write com.apple.spotlight orderedItems -array \
#   '{"enabled" = 1;"name" = "APPLICATIONS";}' \
#   '{"enabled" = 1;"name" = "SYSTEM_PREFS";}' \
#   '{"enabled" = 1;"name" = "DIRECTORIES";}' \
#   '{"enabled" = 1;"name" = "PDF";}' \
#   '{"enabled" = 1;"name" = "FONTS";}' \
#   '{"enabled" = 0;"name" = "DOCUMENTS";}' \
#   '{"enabled" = 0;"name" = "MESSAGES";}' \
#   '{"enabled" = 0;"name" = "CONTACT";}' \
#   '{"enabled" = 0;"name" = "EVENT_TODO";}' \
#   '{"enabled" = 0;"name" = "IMAGES";}' \
#   '{"enabled" = 0;"name" = "BOOKMARKS";}' \
#   '{"enabled" = 0;"name" = "MUSIC";}' \
#   '{"enabled" = 0;"name" = "MOVIES";}' \
#   '{"enabled" = 0;"name" = "PRESENTATIONS";}' \
#   '{"enabled" = 0;"name" = "SPREADSHEETS";}' \
#   '{"enabled" = 0;"name" = "SOURCE";}' \
#   '{"enabled" = 0;"name" = "MENU_DEFINITION";}' \
#   '{"enabled" = 0;"name" = "MENU_OTHER";}' \
#   '{"enabled" = 0;"name" = "MENU_CONVERSION";}' \
#   '{"enabled" = 0;"name" = "MENU_EXPRESSION";}' \
#   '{"enabled" = 0;"name" = "MENU_WEBSEARCH";}' \
#   '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}'
# ok

# running "Load new settings before rebuilding the index"
# killall mds >/dev/null 2>&1
# ok

# running "Make sure indexing is enabled for the main volume"
# sudo mdutil -i on / >/dev/null
# ok

# running "Rebuild the index from scratch"
# sudo mdutil -E / >/dev/null
# ok

# Spotlight is replaced by Raycast, nothing to do.

###############################################################################
bot "Time Machine"
###############################################################################

running "Prevent Time Machine from prompting to use new hard drives as backup volume"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
ok

running "Disable local Time Machine backups"
hash tmutil &>/dev/null && sudo tmutil disablelocal
ok

###############################################################################
bot "Address Book, Dashboard, iCal, TextEdit, and Disk Utility"
###############################################################################

running "Enable the debug menu in Address Book"
defaults write com.apple.addressbook ABShowDebugMenu -bool true
ok

running "Enable Dashboard dev mode (allows keeping widgets on the desktop)"
defaults write com.apple.dashboard devmode -bool true
ok

running "Use plain text mode for new TextEdit documents"
defaults write com.apple.TextEdit RichText -int 0
ok

running "Open and save files as UTF-8 in TextEdit"
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
ok

running "Use Meslo LGS Nerd Font in TextEdit"
defaults write com.apple.TextEdit NSFixedPitchFont "MesloLGSNer-Regular"
defaults write com.apple.TextEdit NSFixedPitchFontSize 14
ok

running "Enable the debug menu in Disk Utility"
defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
defaults write com.apple.DiskUtility advanced-image-options -bool true
ok

running "Auto-play videos when opened with QuickTime Player"
defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true
ok

for app in "Address Book" "Calendar" "Contacts" "cfprefsd" "Dock" "Finder" "SystemUIServer" "Karabiner-Menu"; do
  killall "${app}" >/dev/null 2>&1
done

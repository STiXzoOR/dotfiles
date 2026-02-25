DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"
COMPUTER_NAME="STiXzoOR-MB"
LANGUAGES=("en-CY" "el-CY")
LOCALE="en_CY@currency=EUR"
TIMEZONE="Europe/Athens"
MEASUREMENT_UNITS="Centimeters"
SCREENSHOTS_FOLDER="${HOME}/Desktop/Screenshots"

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
# Use "System Settings" for macOS Ventura+ or fall back to "System Preferences"
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || osascript -e 'tell application "System Preferences" to quit' 2>/dev/null
ok

###############################################################################
bot "Security"
###############################################################################
running "Enable install from Anywhere"
# On macOS 15+ (Sequoia), this requires manual confirmation in System Settings > Privacy & Security
if [[ $(sw_vers -productVersion | cut -d. -f1) -lt 15 ]]; then
  sudo spctl --master-disable
else
  echo "  NOTE: On macOS 15+, enable 'Anywhere' manually in System Settings > Privacy & Security"
fi
ok

running "Disable remote apple events"
sudo systemsetup -setremoteappleevents off 2>/dev/null || true
ok

running "Disable remote login"
sudo systemsetup -setremotelogin off 2>/dev/null || true
ok

running "Disable wake-on LAN"
sudo pmset -a womp 0
ok

running "Disable guest account login"
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
ok

################################################
bot "General UI/UX"
################################################
running "Set computer name (as done via System Preferences → Sharing)"
sudo scutil --set ComputerName "$COMPUTER_NAME"
sudo scutil --set HostName "$COMPUTER_NAME"
sudo scutil --set LocalHostName "$COMPUTER_NAME"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$COMPUTER_NAME"
ok

running "Set language and text formats (english/CY)"
defaults write NSGlobalDomain AppleLanguages -array "${LANGUAGES[@]}"
defaults write NSGlobalDomain AppleLocale -string "$LOCALE"
defaults write NSGlobalDomain AppleMeasurementUnits -string "$MEASUREMENT_UNITS"
defaults write NSGlobalDomain AppleMetricUnits -bool true
ok

running "Set timezone to $TIMEZONE;" #see `sudo systemsetup -listtimezones` for other values
sudo systemsetup -settimezone "$TIMEZONE" >/dev/null
ok

# Boot sound: On macOS 11+ (Big Sur), control via System Settings > Sound > "Play sound on startup"
# The nvram commands only worked on Intel Macs running macOS 10.15 or earlier

running "Restart automatically if the computer freezes"
sudo systemsetup -setrestartfreeze on 2>/dev/null || true
ok

running "Set standby delay to 24 hours (default is 1 hour)"
sudo pmset -a standbydelay 86400
ok

# Note: Sudden Motion Sensor (sms) setting removed - only relevant for HDDs, not SSDs
# All modern Macs use SSDs, so this setting is obsolete

running "Disable audio feedback when volume is changed"
defaults write com.apple.sound.beep.feedback -bool false
ok

# Note: Battery percentage setting removed - deprecated in macOS Big Sur+
# Now controlled via System Settings > Control Center > Battery

running "Set highlight color to steel blue"
defaults write NSGlobalDomain AppleHighlightColor -string "0.172549019607843 0.349019607843137 0.501960784313725"
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

running "Disable the 'Are you sure you want to open this application?' dialog"
defaults write com.apple.LaunchServices LSQuarantine -bool false
ok

running "Remove duplicates in the 'Open With' menu (also see 'lscleanup' alias)"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
ok

running "Show control characters"
defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true
ok

running "Disable Resume system-wide"
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
ok

# Note: NSDisableAutomaticTermination removed - disabling automatic termination
# prevents macOS from freeing RAM and negatively impacts system performance

running "Set Help Viewer windows to non-floating mode"
defaults write com.apple.helpviewer DevMode -bool true
ok

running "Reveal IP, hostname, OS, etc. when clicking clock in login window"
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
ok

running "Disable the crash reporter"
defaults write com.apple.CrashReporter DialogType -string "none"
ok

###############################################################################
bot "Keyboard & Input"
###############################################################################

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

running "Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
ok

running "Disable press-and-hold for keys in favor of key repeat"
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
ok

running "Set a blazingly fast keyboard repeat rate"
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 15
ok

# Note: BezelServices keyboard illumination settings removed - deprecated in modern macOS
# Keyboard backlight is now managed automatically by the system

###############################################################################
bot "Trackpad, mouse, Bluetooth accessories"
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

running "Use scroll gesture with the Ctrl (^) modifier key to zoom"
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
ok

running "Follow the keyboard focus while zoomed in"
defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true
ok

running "Auto-play videos when opened with QuickTime Player"
defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true
ok

###############################################################################
bot "Screen"
###############################################################################

# Screen lock password: Broken since macOS 10.13 (High Sierra).
# Use System Settings > Lock Screen to configure, or:
#   sysadminctl -screenLock immediate -password -
# (requires interactive password entry)

running "Save screenshots to the desktop"
mkdir -p "${SCREENSHOTS_FOLDER}"
defaults write com.apple.screencapture location -string "$SCREENSHOTS_FOLDER"
ok

running "Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)"
defaults write com.apple.screencapture type -string "png"
ok

running "Disable shadow in screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
ok

# Note: AppleFontSmoothing (subpixel rendering) removed - deprecated since macOS Mojave
# Retina displays don't benefit from subpixel antialiasing

#running "Enable HiDPI display modes (requires restart)"
#sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true
#ok

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

# Note: QLEnableTextSelection removed - text selection is now enabled by default in Quick Look

# POSIX path in title: Broken on Sequoia (Finder title bar redesign).
# Use ShowPathbar instead (enabled above).

running "Keep folders on top when sorting by name"
defaults write com.apple.finder _FXSortFoldersFirst -bool true
ok

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

# Note: EmptyTrashSecurely removed - secure delete was removed in El Capitan
# SSDs don't benefit from secure erase due to wear leveling

running "Show the ~/Library folder"
chflags nohidden ~/Library && xattr -d com.apple.FinderInfo ~/Library
ok

running "Show the /Volumes folder"
sudo chflags nohidden /Volumes
ok

running "Expand the following File Info panes: General, Open with, and Sharing & Permissions"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
  General -bool true \
  OpenWith -bool true \
  Privileges -bool true
ok

###############################################################################
bot "Dock"
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

# Mission Control animation speed: Unreliable since Sierra (animations moved to WindowServer)

running "Remove the auto-hiding Dock delay"
defaults write com.apple.dock autohide-delay -float 0
ok

running "Make Dock icons of hidden applications translucent"
defaults write com.apple.dock showhidden -bool true
ok

running "Reset Launchpad, but keep the desktop wallpaper intact"
find "${HOME}/Library/Application Support/Dock" -name "*-*.db" -maxdepth 1 -delete
ok

running "Add iOS Simulator to Launchpad"
if [[ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]]; then
  sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" "/Applications/Simulator.app"
fi
ok

bot "Hot corners"
# Possible values:
#  0: no-op
#  2: Mission Control
#  3: Show application windows
#  4: Desktop
#  5: Start screen saver
#  6: Disable screen saver
# 10: Put display to sleep
# 11: Launchpad
# 12: Notification Center
# 13: Lock Screen
# 14: Quick Note (added in Monterey)
running "Top left screen corner → Mission Control"
defaults write com.apple.dock wvous-tl-corner -int 2
defaults write com.apple.dock wvous-tl-modifier -int 0
ok
running "Top right screen corner → Desktop"
defaults write com.apple.dock wvous-tr-corner -int 4
defaults write com.apple.dock wvous-tr-modifier -int 0
ok
running "Bottom left screen corner → Start screen saver"
defaults write com.apple.dock wvous-bl-corner -int 5
defaults write com.apple.dock wvous-bl-modifier -int 0
ok

###############################################################################
bot "Spotlight"
###############################################################################

running "Load new settings before rebuilding the index"
killall mds >/dev/null 2>&1
ok

running "Make sure indexing is enabled for the main volume"
sudo mdutil -i on / >/dev/null
ok

###############################################################################
bot "Time Machine"
###############################################################################

running "Prevent Time Machine from prompting to use new hard drives as backup volume"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
ok

#running "Disable local Time Machine backups"
#hash tmutil &>/dev/null && sudo tmutil disablelocal
#ok

for app in "Calendar" "Contacts" "cfprefsd" "Dock" "Finder" "SystemUIServer" "Karabiner-Menu"; do
  killall "${app}" >/dev/null 2>&1
done

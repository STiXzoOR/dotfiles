#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"
SCREENSHOTS_FOLDER="${HOME}/Desktop/Screenshots"

# Personal values (this machine's name, languages, locale, units, timezone) do
# not live here: this repo is public. Copy macos/local.sh.example to
# macos/local.sh (gitignored) and set DOTFILES_COMPUTER_NAME, DOTFILES_LANGUAGES
# (space-separated), DOTFILES_LOCALE, DOTFILES_MEASUREMENT_UNITS and
# DOTFILES_TIMEZONE. A block whose variable is unset is skipped, so a machine
# without a local file keeps whatever it already has.
# shellcheck disable=SC1091
[ -f "$DOTFILES_DIR/macos/local.sh" ] && source "$DOTFILES_DIR/macos/local.sh"

# Absolute-path binaries, overridable so the tests can stub them.
FIREWALL_CTL="${DOTFILES_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
ACTIVATE_SETTINGS="${DOTFILES_ACTIVATE_SETTINGS:-/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings}"
LSREGISTER="${DOTFILES_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"
source "$DOTFILES_DIR/scripts/lib/machine.sh"

# desktop or laptop (scripts/lib/machine.sh). Remote Login and the power
# settings below are desktop-only: the laptop keeps its own, and this script
# neither turns them on nor off there.
DOTFILES_ROLE=$(dotfiles_machine_role)

# `ok` is an unconditional echo, so every step used to report success whether
# or not it did anything. print_result takes the command's exit status instead.
# It lives in scripts/echos.sh; this fallback keeps the file honest when it is
# sourced against an older copy.
if ! type print_result >/dev/null 2>&1; then
  print_result() {
    if [ "$1" -eq 0 ]; then ok "${2:-}"; else error "${2:-}"; fi
  }
fi

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
osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 ||
  osascript -e 'tell application "System Preferences" to quit' >/dev/null 2>&1
print_result $?

###############################################################################
bot "Security"
###############################################################################
# Gatekeeper: kept enabled for security
# To allow individual unsigned apps, use: sudo xattr -r -d com.apple.quarantine /path/to/app

# `systemsetup` and the firewall control both need Full Disk Access for the
# terminal that runs this script. Without it they exit 0 or fail silently
# while changing nothing. Grant it in System Settings, Privacy & Security,
# Full Disk Access, and revoke it afterwards: a standing grant lets every
# script run from that terminal bypass TCC.
warn "systemsetup and the firewall need Full Disk Access for the terminal running this install (System Settings, Privacy & Security, Full Disk Access). Without it they fail or silently change nothing."

running "Disable remote apple events"
sudo systemsetup -setremoteappleevents off >/dev/null 2>&1
print_result $?

if [ "$DOTFILES_ROLE" = desktop ]; then
  # Remote Login (SSH) is ON: this machine is reached remotely. -f suppresses the
  # confirmation prompt, which would otherwise block forever because it is
  # written to a stream that goes to /dev/null while stdin is still the
  # terminal. See `man systemsetup`, -setremotelogin [-f] on | off.
  running "Enable remote login"
  sudo systemsetup -setremotelogin -f on >/dev/null 2>&1
  print_result $?

  # Power. Apple silicon ignores `standbydelay` (it reads back absent), so it is
  # not written.
  running "Restart automatically after a power failure"
  sudo pmset -a autorestart 1
  print_result $?

  running "Disable Power Nap"
  sudo pmset -a powernap 0
  print_result $?

  running "Never sleep the disks"
  sudo pmset -a disksleep 0
  print_result $?
else
  skip "Remote Login and power settings: left as they are on a laptop (role: $DOTFILES_ROLE)"
fi

running "Disable wake-on LAN"
sudo pmset -a womp 0
print_result $?

running "Disable guest account login"
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
print_result $?

# The application firewall. /Library/Preferences/com.apple.alf.plist was
# removed in macOS 15, so `defaults write com.apple.alf ...` is dead code and
# socketfilterfw is the only supported control. The setters exit 0 even when
# they change nothing (no Full Disk Access), so each result is read back.
#
# Adding and removing individual applications through socketfilterfw has been
# unreliable since macOS 15 and --listapps no longer prints paths, so do not
# build per-app firewall rules on top of this.

running "Turn the application firewall on"
sudo "$FIREWALL_CTL" --setglobalstate on >/dev/null 2>&1
print_result $?

running "Turn stealth mode on (no reply to unsolicited probes)"
sudo "$FIREWALL_CTL" --setstealthmode on >/dev/null 2>&1
print_result $?

running "Let built-in signed software receive incoming connections"
sudo "$FIREWALL_CTL" --setallowsigned on >/dev/null 2>&1
print_result $?

running "Do not auto-allow downloaded signed software"
sudo "$FIREWALL_CTL" --setallowsignedapp off >/dev/null 2>&1
print_result $?

running "Verify the firewall is really on"
if "$FIREWALL_CTL" --getglobalstate 2>/dev/null | grep -q "State = 1"; then
  ok
else
  error "the application firewall is still off: grant Full Disk Access to this terminal and run again"
fi

running "Verify stealth mode is really on"
if "$FIREWALL_CTL" --getstealthmode 2>/dev/null | grep -q "enabled"; then
  ok
else
  error "stealth mode is still off: grant Full Disk Access to this terminal and run again"
fi

# Lock the screen with a password immediately after sleep or the screensaver.
# The defaults keys below are the declarative half; on current macOS they are
# not reliably honoured, and `sysadminctl -screenLock` is the supported way.
# It asks for the account password (`-password -` reads it from the terminal),
# so it only runs when a person is there to type it.
running "Require a password immediately after sleep or screen saver"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
ok

if [ -t 0 ] && [ "${DOTFILES_YES:-0}" != "1" ]; then
  running "Set the screen lock delay to immediate (sysadminctl asks for your account password)"
  sysadminctl -screenLock immediate -password -
  print_result $?
else
  warn "not run here (no terminal, or DOTFILES_YES is set). To finish the screen lock, run: sysadminctl -screenLock immediate -password -"
fi

################################################
bot "General UI/UX"
################################################
# Each block below runs only when its variable is set (see macos/local.sh).
if [ -n "${DOTFILES_COMPUTER_NAME:-}" ]; then
  running "Set computer name (as done via System Preferences → Sharing)"
  sudo scutil --set ComputerName "$DOTFILES_COMPUTER_NAME" &&
    sudo scutil --set HostName "$DOTFILES_COMPUTER_NAME" &&
    sudo scutil --set LocalHostName "$DOTFILES_COMPUTER_NAME" &&
    sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$DOTFILES_COMPUTER_NAME"
  print_result $?
else
  skip "computer name: DOTFILES_COMPUTER_NAME is not set (macos/local.sh)"
fi

if [ -n "${DOTFILES_LANGUAGES:-}" ]; then
  running "Set languages"
  # Unquoted on purpose: the list is space-separated.
  # shellcheck disable=SC2086
  defaults write NSGlobalDomain AppleLanguages -array $DOTFILES_LANGUAGES
  print_result $?
fi

if [ -n "${DOTFILES_LOCALE:-}" ]; then
  running "Set text formats (locale)"
  defaults write NSGlobalDomain AppleLocale -string "$DOTFILES_LOCALE"
  print_result $?
fi

if [ -n "${DOTFILES_MEASUREMENT_UNITS:-}" ]; then
  running "Set measurement units"
  defaults write NSGlobalDomain AppleMeasurementUnits -string "$DOTFILES_MEASUREMENT_UNITS"
  if [ "$DOTFILES_MEASUREMENT_UNITS" = "Centimeters" ]; then
    defaults write NSGlobalDomain AppleMetricUnits -bool true
  else
    defaults write NSGlobalDomain AppleMetricUnits -bool false
  fi
  print_result $?
fi

if [ -n "${DOTFILES_TIMEZONE:-}" ]; then
  running "Set timezone to $DOTFILES_TIMEZONE;" #see `sudo systemsetup -listtimezones` for other values
  sudo systemsetup -settimezone "$DOTFILES_TIMEZONE" >/dev/null 2>&1
  print_result $?
fi

# Boot sound: On macOS 11+ (Big Sur), control via System Settings > Sound > "Play sound on startup"
# The nvram commands only worked on Intel Macs running macOS 10.15 or earlier

running "Restart automatically if the computer freezes"
sudo systemsetup -setrestartfreeze on >/dev/null 2>&1
print_result $?

# Note: `pmset standbydelay` is not written: Apple silicon ignores it (it reads
# back absent). Power settings live in the Security block above.

# Note: Sudden Motion Sensor (sms) setting removed - only relevant for HDDs, not SSDs
# All modern Macs use SSDs, so this setting is obsolete

running "Disable audio feedback when volume is changed"
defaults write NSGlobalDomain com.apple.sound.beep.feedback -bool false
ok

# Note: Battery percentage setting removed - deprecated in macOS Big Sur+
# Now controlled via System Settings > Control Center > Battery

# Note: AppleHighlightColor removed - it has had no effect since macOS Tahoe.

running "Use the dark appearance"
defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
ok

running "Use 24-hour time, do not minimize on title-bar double-click, enable the Web Inspector"
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
defaults write NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
ok

running "Use the Blow sound as the alert beep"
defaults write NSGlobalDomain com.apple.sound.beep.sound -string "/System/Library/Sounds/Blow.aiff"
ok

running "Set sidebar icon size to medium"
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2
ok

running "Show scrollbars only while scrolling"
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

# Quarantine dialog: kept enabled for security
# To bypass for a specific app: xattr -d com.apple.quarantine /path/to/app

running "Remove duplicates in the 'Open With' menu (also see 'lscleanup' alias)"
"$LSREGISTER" -kill -r -domain local -domain system -domain user
print_result $?

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
# Deliberate information disclosure: this puts the hostname, IP address and OS
# version on the login window, where anyone with physical access to the locked
# machine can read them. Kept because this machine is not left unattended in
# public. Remove this step if that is not true of yours.
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
print_result $?

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
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
ok

running "Disable press-and-hold for keys in favor of key repeat"
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
ok

running "Set a blazingly fast keyboard repeat rate"
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
ok

# Symbolic hotkeys. Disabled because other apps take these over: Spotlight
# (64, Cmd-Space) and Finder search (65) by Raycast, the built-in screenshot
# shortcuts (28-31) by Shottr. Raycast's own hotkey is set inside Raycast, not
# here. Arguments per key: id, ascii code, key code, modifier mask.
_disable_hotkey() {
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
    "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>$2</integer><integer>$3</integer><integer>$4</integer></array><key>type</key><string>standard</string></dict></dict>"
}

running "Disable the Spotlight, Finder search and screenshot keyboard shortcuts"
_disable_hotkey 64 32 49 1048576
_disable_hotkey 65 32 49 1572864
_disable_hotkey 28 51 20 1179648
_disable_hotkey 29 51 20 1441792
_disable_hotkey 30 52 21 1179648
_disable_hotkey 31 52 21 1441792
# Apply without a logout.
if [ -x "$ACTIVATE_SETTINGS" ]; then
  "$ACTIVATE_SETTINGS" -u
fi
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

# macOS 26 Tahoe's Liquid Glass redesign makes translucent chrome hard to read
# over busy backgrounds. reduceTransparency is unset by default rather than
# removed, so writing it is still the supported way to tone it down.
running "Reduce transparency"
defaults write com.apple.universalaccess reduceTransparency -bool true
ok

# These three closeView keys read back ABSENT on both macOS 15.6.1 and 26.6.1
# on the audited machine: the accessibility daemon rewrites the plist and the
# writes do not survive. They are kept so the baseline keeps tracking them, but
# set zoom from System Settings, Accessibility, Zoom if it does not take.
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

running "Save screenshots to the desktop"
mkdir -p "${SCREENSHOTS_FOLDER}" &&
  defaults write com.apple.screencapture location -string "$SCREENSHOTS_FOLDER"
print_result $?

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

running "Show the full POSIX path in the Finder title bar"
# Live and working on the current macOS, alongside the path bar above.
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
ok

running "Empty the Trash automatically after 30 days"
defaults write com.apple.finder FXRemoveOldTrashItems -bool true
ok

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

# Disk image verification: kept enabled for security

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
# The FinderInfo attribute is usually absent, and `xattr -d` exits non-zero
# when it is, so deleting unconditionally made this step red on every run after
# the first. Only delete what is there.
chflags nohidden ~/Library &&
  { xattr -p com.apple.FinderInfo ~/Library >/dev/null 2>&1 &&
    xattr -d com.apple.FinderInfo ~/Library >/dev/null 2>&1 || true; }
print_result $?

running "Show the /Volumes folder"
sudo chflags nohidden /Volumes
print_result $?

# -dict-add, not -dict: a whole-dict write replaces the panes already open.
running "Expand every File Info pane: General, Open with, Sharing & Permissions, Comments, More Info, Name"
defaults write com.apple.finder FXInfoPanesExpanded -dict-add \
  General -bool true \
  OpenWith -bool true \
  Privileges -bool true \
  Comments -bool true \
  MetaData -bool true \
  Name -bool true
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

running "Group Mission Control windows by application, and speed up the animation"
defaults write com.apple.dock expose-group-apps -bool true
defaults write com.apple.dock expose-animation-duration -float 0.1
ok

running "Make Dock icons of hidden applications translucent"
defaults write com.apple.dock showhidden -bool true
ok

###############################################################################
bot "Window tiling (macOS 26)"
###############################################################################
# Window tiling is the UI area Tahoe changed most. All four keys were verified
# present in com.apple.WindowManager on macOS 26.6.1.

running "Remove the margins between tiled windows"
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
ok

# Declared at the value the audited machine already had (both off), so that a
# rebuilt machine reproduces this one. The audit named a value for the margins
# and widget keys but only described these two, so no value is invented here.
# Flip either to true if you want drag-to-edge or drag-to-top tiling.
running "Declare drag-to-edge and drag-to-top tiling"
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false
ok

running "Show desktop widgets, hide desktop items"
defaults write com.apple.WindowManager StandardHideWidgets -bool false
defaults write com.apple.WindowManager HideDesktop -bool true
ok

# Launchpad reset removed: macOS 26 Tahoe replaced Launchpad with Apps.app and
# ~/Library/Application Support/Dock no longer exists, so the old `find -delete`
# had nothing to act on.

# The iOS Simulator symlink into /Applications is gone: Xcode 27 no longer ships
# the app at that path, so the block could only report "Xcode is not installed".

bot "Hot corners"
# Possible values:
#  0: no-op
#  2: Mission Control
#  3: Show application windows
#  4: Desktop
#  5: Start screen saver
#  6: Disable screen saver
# 10: Put display to sleep
# 11: Apps (Launchpad on macOS 25 and earlier)
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
# mds is root-owned, so an unprivileged killall never matches it and always
# exits non-zero. launchd restarts the daemon immediately.
sudo killall mds >/dev/null 2>&1
print_result $?

running "Make sure indexing is enabled for the main volume"
sudo mdutil -i on / >/dev/null 2>&1
print_result $?

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

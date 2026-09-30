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
# macos/machine.local.sh holds per-Mac choices (DOTFILES_LAUNCHER); it is read
# by dotfiles_launcher below, not sourced here. local.sh may set the launcher
# too, so the caller's value is put back after sourcing it: the environment
# outranks both files, and a value leaked from local.sh would outrank the
# per-Mac file.
_launcher_env="${DOTFILES_LAUNCHER:-}"
# shellcheck disable=SC1091
[ -f "$DOTFILES_DIR/macos/local.sh" ] && source "$DOTFILES_DIR/macos/local.sh"
# Per-Mac values (a computer name of its own, the launcher) come after the
# shared file and win over it.
# shellcheck disable=SC1091
[ -f "$DOTFILES_DIR/macos/machine.local.sh" ] && source "$DOTFILES_DIR/macos/machine.local.sh"
unset DOTFILES_LAUNCHER
[ -z "$_launcher_env" ] || DOTFILES_LAUNCHER="$_launcher_env"

# Absolute-path binaries, overridable so the tests can stub them.
FIREWALL_CTL="${DOTFILES_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
ACTIVATE_SETTINGS="${DOTFILES_ACTIVATE_SETTINGS:-/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings}"
LSREGISTER="${DOTFILES_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"
source "$DOTFILES_DIR/scripts/lib/machine.sh"

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

# desktop or laptop (scripts/lib/machine.sh). Remote Login and the power
# settings below are desktop-only: the laptop keeps its own, and this script
# neither turns them on nor off there.
DOTFILES_ROLE=$(dotfiles_machine_role)

# Failed read-backs (firewall, stealth mode, Remote Login) are counted here;
# `dotfiles configure --defaults` turns a non-zero count into a non-zero status.
DOTFILES_DEFAULTS_FAILURES=0
# Only real system settings count as failures. Anything with a documented GUI
# fallback (the Tinycast hotkey, Spotlight indexing, the Open With rebuild, the
# reduce-transparency reset) is a warning that names the fallback.

# Ask for the administrator password upfront
sudo -v

# Keep-alive: refresh the `sudo` time stamp until this script has finished.
# `sudo -n -v` runs no command, so sudo never puts the terminal in raw mode for
# a relayed command; a background `sudo -n true` racing the foreground sudo
# calls left the tty raw, and every later line printed as a staircase. All three
# streams are redirected so nothing in the background touches the terminal.
while true; do
  sudo -n -v </dev/null >/dev/null 2>&1
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
# Only warn when the terminal really lacks it: reading the TCC database
# directory succeeds only with Full Disk Access.
if ! /bin/ls "${DOTFILES_FDA_PROBE:-$HOME/Library/Application Support/com.apple.TCC}" >/dev/null 2>&1; then
  warn "systemsetup and the firewall need Full Disk Access for the terminal running this install (System Settings, Privacy & Security, Full Disk Access). Without it they fail or silently change nothing."
fi

running "Disable remote apple events"
sudo systemsetup -setremoteappleevents off >/dev/null 2>&1
print_result $?

if [ "$DOTFILES_ROLE" = desktop ]; then
  # Remote Login (SSH) is ON: this machine is reached remotely. -f suppresses the
  # confirmation prompt, which would otherwise block forever because it is
  # written to a stream that goes to /dev/null while stdin is still the
  # terminal. See `man systemsetup`, -setremotelogin [-f] on | off.
  #
  # The state is read first and the setter only runs when it is off: without
  # Full Disk Access the setter errors even when Remote Login is already on
  # (enabled by hand), and `-getremotelogin` needs Full Disk Access too, reading
  # Off while sshd runs. So the state is read from systemsetup, from launchd's
  # disabled list and from sshd listening on port 22; the last two need no Full
  # Disk Access.
  _remote_login_on() {
    sudo systemsetup -getremotelogin 2>/dev/null | grep -q "Remote Login: On" ||
      sudo launchctl print-disabled system 2>/dev/null | grep -q '"com.openssh.sshd" => enabled' ||
      nc -z 127.0.0.1 22 >/dev/null 2>&1
  }
  running "Enable remote login"
  if _remote_login_on; then
    ok "already on"
  else
    sudo systemsetup -setremotelogin -f on >/dev/null 2>&1
    if _remote_login_on; then
      ok
    else
      error "Remote Login is off: turn it on in System Settings, General, Sharing, Remote Login (or grant Full Disk Access to this terminal), then run \`dotfiles configure --defaults\` again"
      DOTFILES_DEFAULTS_FAILURES=$((DOTFILES_DEFAULTS_FAILURES + 1))
    fi
  fi

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

  # Reachable over SSH (and Tailscale) at all times: on AC power the machine
  # never system-sleeps, and only the display goes to sleep, after 10 minutes.
  running "Never sleep the system on AC power"
  sudo pmset -c sleep 0
  print_result $?

  running "Sleep the display after 10 minutes on AC power"
  sudo pmset -c displaysleep 10
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

# Lock the screen with a password immediately after sleep or the screensaver.
# The defaults keys below are the declarative half; on current macOS they are
# not reliably honoured, and `sysadminctl -screenLock` is the supported way.
# It asks for the account password (`-password -` reads it from the terminal),
# so it only runs when a person is there to type it.
running "Require a password immediately after sleep or screen saver"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
ok

# DOTFILES_YES_INTERNAL is set by sub_configure for its own prompts only; an
# owner's unattended DOTFILES_YES still skips, a terminal with the internal one
# does not.
if [ -t 0 ] && { [ "${DOTFILES_YES:-0}" != "1" ] || [ "${DOTFILES_YES_INTERNAL:-0}" = "1" ]; }; then
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
  skip "computer name: DOTFILES_COMPUTER_NAME is not set (set it in macos/local.sh, or per Mac in macos/machine.local.sh)"
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

# An older configure wrote reduceTransparency true, which tints Liquid Glass
# fully. It is no longer set, so undo it where it was: only when it reads 1.
if [ "$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null)" = 1 ]; then
  running "Turn the old Reduce transparency setting back off"
  defaults write com.apple.universalaccess reduceTransparency -bool false
  if [ "$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null)" = 0 ]; then
    ok
  else
    warn "could not turn Reduce transparency off (writing it may need Full Disk Access); turn it off in System Settings, Accessibility, Display, Reduce transparency"
  fi
fi

running "Use the dark appearance"
defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
ok

# macOS 26+ appearance: dark icons and Clear Liquid Glass. Icon style and glass
# changes fully apply after a logout. Override in macos/local.sh:
#   DOTFILES_ICON_STYLE  {Regular,Clear,Tinted}{Automatic,Light,Dark}
#   DOTFILES_GLASS       clear | tinted
# Transparency is left at the system default.
: "${DOTFILES_ICON_STYLE:=RegularDark}"
case "$DOTFILES_ICON_STYLE" in
  RegularAutomatic | RegularLight | RegularDark | ClearAutomatic | ClearLight | ClearDark | TintedAutomatic | TintedLight | TintedDark) ;;
  *)
    warn "DOTFILES_ICON_STYLE='$DOTFILES_ICON_STYLE' is not one of {Regular,Clear,Tinted}{Automatic,Light,Dark}; using RegularDark"
    DOTFILES_ICON_STYLE=RegularDark
    ;;
esac
: "${DOTFILES_GLASS:=clear}"
DOTFILES_OS_MAJOR=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
# _appearance_check <key> <expected> -- read the key back; a mismatch is counted.
_appearance_check() {
  local got
  got=$(defaults read -g "$1" 2>/dev/null)
  if awk -v a="$got" -v b="$2" 'BEGIN { exit !(a != "" && a == b) }' 2>/dev/null || [ "$got" = "$2" ]; then
    ok
  else
    error "$1 reads back as '${got:-nothing}', expected '$2'; set it in System Settings, Appearance, then log out and back in"
    DOTFILES_DEFAULTS_FAILURES=$((DOTFILES_DEFAULTS_FAILURES + 1))
  fi
}
if [ "${DOTFILES_OS_MAJOR:-0}" -ge 26 ] 2>/dev/null; then
  running "Use dark icons ($DOTFILES_ICON_STYLE)"
  defaults write -g AppleIconAppearanceTheme -string "$DOTFILES_ICON_STYLE"
  _appearance_check AppleIconAppearanceTheme "$DOTFILES_ICON_STYLE"

  case "$DOTFILES_GLASS" in
    clear) glass_int=0 glass_float=0 ;;
    tinted) glass_int=1 glass_float=0.86 ;;
    *) glass_int="" glass_float="" ;;
  esac
  if [ -z "$glass_int" ]; then
    warn "DOTFILES_GLASS='$DOTFILES_GLASS' is not clear or tinted; Liquid Glass left alone"
  elif [ "$DOTFILES_OS_MAJOR" -ge 27 ]; then
    # macOS 27 tints by a float strength; it does not use NSGlassDiffusionSetting.
    running "Liquid Glass: $DOTFILES_GLASS (NSGlassTintAmount $glass_float)"
    defaults write -g NSGlassTintAmount -float "$glass_float"
    _appearance_check NSGlassTintAmount "$glass_float"
  else
    # macOS 26: 0 is Clear, 1 is Tinted; a fresh Mac has the key unset (Clear).
    running "Liquid Glass: $DOTFILES_GLASS (NSGlassDiffusionSetting $glass_int)"
    defaults write -g NSGlassDiffusionSetting -int "$glass_int"
    _appearance_check NSGlassDiffusionSetting "$glass_int"
  fi
fi

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

# lsregister -kill was removed (macOS 27 prints a notice and does nothing). The
# supported rebuild is to register the applications again and garbage-collect
# the stale entries, which is what removes the duplicates.
running "Remove duplicates in the 'Open With' menu"
if "$LSREGISTER" -r -apps local,system,user >/dev/null 2>&1 && "$LSREGISTER" -gc >/dev/null 2>&1; then
  ok
else
  warn "lsregister could not rebuild the Open With list; log out and back in, or run: $LSREGISTER -r -apps local,system,user && $LSREGISTER -gc"
fi

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
# (64, Cmd-Space) and Finder search (65) by the launcher (Tinycast or Raycast),
# the built-in screenshot shortcuts (28-31) by Shottr. Raycast's own hotkey is
# set inside Raycast, not here; Tinycast's is written by the launcher block
# below. Arguments per key: id, ascii code, key code, modifier mask.
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

# The launcher (scripts/lib/machine.sh: dotfiles_launcher). Spotlight's Cmd-Space
# is disabled above either way; on a Tinycast Mac Tinycast takes the key. The
# hotkey and the settings-file switch are UserDefaults keys of Tinycast
# (docs/features/hotkeys.md and settings-file.md upstream). The hotkey's JSON is
# documented as not a stable format, so it is read back and a mismatch is
# reported; the GUI (Settings > General) is the fallback. Tinycast caches its
# defaults, so it is written only while the app is not running.
DOTFILES_LAUNCHER=$(dotfiles_launcher "$DOTFILES_DIR")
TINYCAST_HOTKEY='{"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}'
RAYCAST_APP="${DOTFILES_RAYCAST_APP:-/Applications/Raycast.app}"
TINYCAST_APP="${DOTFILES_TINYCAST_APP:-/Applications/Tinycast.app}"
# _tinycast_get <key> -- the raw stored value, or nothing. `defaults read`
# prints a string quoted and escaped, so the domain is exported to a plist and
# read with PlistBuddy (":" is its path separator, so a dotted key is one key).
_tinycast_get() {
  local tmp v
  tmp=$(mktemp "${TMPDIR:-/tmp}/tinycast.XXXXXX") || return 1
  defaults export com.tinycast.app "$tmp" >/dev/null 2>&1
  v=$(/usr/libexec/PlistBuddy -c "Print :$1" "$tmp" 2>/dev/null)
  rm -f "$tmp"
  printf '%s' "$v"
}
if [ "$DOTFILES_LAUNCHER" = tinycast ] && [ ! -d "$TINYCAST_APP" ]; then
  skip "Tinycast is not installed yet; run \`dotfiles configure --defaults\` after \`dotfiles install --packages\`"
elif [ "$DOTFILES_LAUNCHER" = tinycast ]; then
  running "Tinycast: Cmd-Space as the summon hotkey, settings file on"
  if [ "$(_tinycast_get hotkey.togglePalette)" = "$TINYCAST_HOTKEY" ] &&
    [ "$(_tinycast_get settingsFileEnabled)" = true ]; then
    ok "already set"
  else
    if pgrep -x Tinycast >/dev/null 2>&1; then
      action "quitting Tinycast to set its hotkey (it caches its settings while running)"
      osascript -e 'quit app "Tinycast"' >/dev/null 2>&1
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x Tinycast >/dev/null 2>&1 || break
        sleep 0.5
      done
    fi
    if pgrep -x Tinycast >/dev/null 2>&1; then
      warn "Tinycast is still running, so its hotkey was not set; quit it and re-run configure, or set Cmd-Space in Tinycast > Settings > General"
    else
      # -string: without a type, `defaults` parses a value starting with "{" as
      # an old-style plist dictionary and fails with "Could not parse".
      defaults write com.tinycast.app hotkey.togglePalette -string "$TINYCAST_HOTKEY" ||
        warn "defaults could not write the Tinycast hotkey; set Cmd-Space in Tinycast > Settings > General"
      defaults write com.tinycast.app settingsFileEnabled -bool true
      got=$(_tinycast_get hotkey.togglePalette)
      sfe=$(_tinycast_get settingsFileEnabled)
      if [ "$got" != "$TINYCAST_HOTKEY" ]; then
        warn "Tinycast hotkey read back as '$got', expected '$TINYCAST_HOTKEY'; set Cmd-Space in Tinycast > Settings > General"
      elif [ "$sfe" != true ]; then
        warn "Tinycast settingsFileEnabled read back as '$sfe', expected 'true'; switch on Tinycast > Settings > Backup > Settings File"
      else
        ok
      fi
    fi
  fi
  if [ -d "$RAYCAST_APP" ]; then
    warn "Raycast is still installed and may claim Cmd-Space; remove it with: brew uninstall --cask raycast"
  fi
fi

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

# `mdutil -i on /` errors on some macOS 27 setups even with indexing already on,
# so it only runs when `mdutil -s /` says indexing is off, and a failure is a
# warning that says what to do.
running "Make sure indexing is enabled for the main volume"
md_state=$(mdutil -s / 2>&1)
if printf '%s\n' "$md_state" | grep -qi "indexing enabled"; then
  ok "already enabled"
else
  if md_out=$(sudo mdutil -i on / 2>&1); then
    ok
  else
    warn "could not turn Spotlight indexing on (${md_out:-no output}); enable it in System Settings, Spotlight, or run: sudo mdutil -i on /"
  fi
fi

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

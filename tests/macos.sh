#!/usr/bin/env bash
#
# tests/macos.sh -- regression tests for the 2026-09-21 audit, macOS workstream.
#
# Covers bin/dotfiles-baseline, macos/defaults*.sh, macos/dock.sh and
# launchagents/. Every assertion is static: nothing here reads or writes a
# real preference domain, so the suite is safe on a live machine.
#
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "B1 -- baseline extractor"
#############################################################################
# A throwaway DOTFILES_DIR holding one macos/defaults-x.sh with a single line.
mk() {
  local w
  w=$(sandbox)
  mkdir -p "$w/macos"
  printf "%s\n" "$1" >"$w/macos/defaults-x.sh"
  printf '%s' "$w"
}

t "B1.1" "keys with spaces survive" \
  'W=$(mk "defaults write com.apple.print.PrintingPrefs \"Quit When Finished\" -bool true"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "Quit When Finished"'
t "B1.2" "indented writes are captured" \
  'W=$(mk "  defaults write com.apple.terminal \"Default Window Settings\" -string Nord"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "Default Window Settings"'
t "B1.3" "sudo writes are captured with their domain path" \
  'W=$(mk "sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "GuestEnabled"'
t "B1.4" "-currentHost writes are captured" \
  'W=$(mk "defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "disableHotPlug"'
t "B1.5" "a write with no key is rejected, not recorded as domain=-bool" \
  'W=$(mk "defaults write com.apple.sound.beep.feedback -bool false"); [ "$(DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -c -- "-bool")" -eq 0 ]'

#############################################################################
section "B2 -- defaults bugs"
#############################################################################
# grep -q on the right of a pipe kills a chatty writer with SIGPIPE, which
# pipefail turns into a non-zero pipeline and a leading `!` then turns into a
# false pass. Count instead, so the whole input is always read. See tests/lib.sh.
t "B2.1" "beep feedback key is in the global domain" \
  'grep -q "NSGlobalDomain com.apple.sound.beep.feedback" macos/defaults.sh'
t "B2.2" "no Launchpad references" \
  '[ "$(code_of macos/defaults.sh macos/dock.sh | grep -ci launchpad)" -eq 0 ]'
t "B2.3" "dock adds Apps.app" \
  'grep -q "/System/Applications/Apps.app" macos/dock.sh'
t "B2.4" "scrollbar comment matches value" \
  '[ "$(grep -B2 "WhenScrolling" macos/defaults.sh | grep -ci "always show")" -eq 0 ]'

#############################################################################
section "B3 -- Dock robustness"
#############################################################################
# The brief's B3.1 counted `dockutil --add` call sites, which the file never
# had (every call carries --no-restart) and which therefore passed before the
# fix. What the audit actually asked for is the existence guard, so that is
# what is asserted here.
t "B3.1" "each app is checked for existence before it is added" \
  'grep -q -- "-d \"\$icon\"" macos/dock.sh'
t "B3.2" "missing apps are reported, not silently skipped" \
  'grep -q "warn" macos/dock.sh'
t "B3.3" "dock.sh has a shebang line for shellcheck" \
  'head -1 macos/dock.sh | grep -q "^#"'
t "B3.4" "apps that are not installed are off the list" \
  '[ "$(grep -cE "Spark\.app|Notion\.app" macos/dock.sh)" -eq 0 ]'
t "B3.5" "dockutil itself is checked for before the dock is rebuilt" \
  'grep -q "command -v dockutil" macos/dock.sh'

#############################################################################
section "B4 -- ok only after success"
#############################################################################
# `exit 1` inside a t() assertion would kill this whole suite: t runs its
# third argument through eval in the current shell, not a subshell. Count into
# a variable and compare instead.
t "B4.1" "no '|| true' after systemsetup" \
  '! grep -E "systemsetup.*\|\| true" macos/defaults.sh'
# The brief spelled this `grep -q DOTFILES_DIR`, which every file already
# satisfied by merely mentioning the variable in its source line. What the
# audit asked for is that each file SETS it, so it works when sourced alone.
t "B4.2" "every defaults file sets DOTFILES_DIR before sourcing echos" '
  bad=0
  for f in macos/defaults*.sh; do
    grep -q "^DOTFILES_DIR=" "$f" || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "B4.3" "no theme dir variable leaks between two sourced files" \
  '[ "$(grep -l "^CUSTOM_THEME_DIR=" macos/defaults-*.sh | wc -l | tr -d " ")" -le 1 ]'
t "B4.4" "every macos script has a shebang so shellcheck reads it as bash" '
  bad=0
  for f in macos/*.sh; do
    head -1 "$f" | grep -q "^#!" || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "B4.5" "the security block reports the real exit status" \
  'grep -q "print_result" macos/defaults.sh'

#############################################################################
section "B5 -- security defaults and Tahoe additions"
#############################################################################
t "B5.1" "firewall on + stealth" \
  'grep -q -- "--setglobalstate on" macos/defaults.sh && grep -q -- "--setstealthmode on" macos/defaults.sh'
# The brief's plain grep already matched the comment that documented the
# command without running it, which is exactly the state the audit flagged.
# code_of strips whole-line comments, so this asks for real code.
t "B5.2" "screen lock is enforced (owner decision 2026-09-29: password immediately after sleep)" \
  '[ "$(code_of macos/defaults.sh | grep -cE "sysadminctl -screenLock|askForPasswordDelay")" -ge 2 ]'
t "B5.3" "software update keys in /Library/Preferences" \
  'grep -q "/Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall" macos/defaults-appstore.sh && grep -q "ConfigDataInstall" macos/defaults-appstore.sh'
t "B5.4" "mail defaults gated on the container" \
  'grep -q "Containers/com.apple.mail" macos/defaults-mail.sh'
t "B5.5" "transmission does not ask before downloading (live setting)" \
  'grep -q "DownloadAsk -bool false" macos/defaults-transmission.sh'
t "B5.6" "WindowManager tiling keys declared" \
  'grep -q "EnableTiledWindowMargins" macos/defaults.sh'
# The audit named a value for two of the four WindowManager keys and only
# described the other two. Both drag-tiling keys read 0 on the audited machine,
# so they are declared at that value rather than at one nobody chose.
t "B5.11" "drag-tiling keys are declared at the audited value, not an invented one" \
  'grep -q "EnableTilingByEdgeDrag -bool false" macos/defaults.sh && grep -q "EnableTopTilingByEdgeDrag -bool false" macos/defaults.sh'
t "B5.7" "reduceTransparency declared" \
  'grep -q "reduceTransparency" macos/defaults.sh'
t "B5.8" "no AdminHostInfo without a comment explaining it" \
  '[ "$(grep -B1 AdminHostInfo macos/defaults.sh | grep -c "#")" -ge 1 ]'
# code_of, so the comment recording why the blocklist was removed does not
# count as the blocklist still being there. Verified against the pre-fix file:
# the code-only count was 1.
t "B5.9" "no auto-updating third-party torrent blocklist" \
  '[ "$(code_of macos/defaults-transmission.sh | grep -c "BlocklistAutoUpdate")" -eq 0 ]'
t "B5.10" "magnet links open without asking too (live setting)" \
  'grep -q "MagnetOpenAsk -bool false" macos/defaults-transmission.sh'

#############################################################################
section "B6 -- LaunchAgents"
#############################################################################
PLIST=launchagents/disabled/com.stixzoor.mackup-auto.plist
t "B6.1" "plist does not log into world-writable /tmp" \
  '! grep -q "/tmp/mackup" "$PLIST"'
t "B6.2" "plist logs under ~/Library/Logs" \
  'grep -q "Library/Logs" "$PLIST"'
t "B6.3" "README records mackup's real maintenance status" \
  'grep -q "0.11.2" launchagents/disabled/README.md'
t "B6.4" "README says to copy a plist rather than symlink it" \
  '[ "$(grep -ci "symlink" launchagents/disabled/README.md)" -ge 1 ] && grep -qi "copy" launchagents/disabled/README.md'

#############################################################################
section "B7 -- pre-macOS-27 baseline"
#############################################################################
t "B7.1" "26.6.1 baseline committed" \
  '[ -f macos/baselines/26.6.1.tsv ]'
t "B7.2" "no baseline carries an absolute home path" \
  '! grep -rq "/Users/" macos/baselines/'
t "B7.3" "home paths are recorded as \$HOME so two machines diff cleanly" \
  'grep -q "HOME" macos/baselines/26.6.1.tsv'

#############################################################################
section "F1 -- review round 1: no invisible prompts, no guaranteed errors"
#############################################################################
# `systemsetup -setremotelogin off` prompts for confirmation. Both streams now
# go to /dev/null, so without -f the run blocks at a question nobody can see.
t "F1.1" "remote login is turned on without an invisible confirmation prompt" \
  'grep -q -- "-setremotelogin -f on" macos/defaults.sh'
# `xattr -d` on an absent attribute exits non-zero, so after the first
# successful run this step reported error forever.
t "F1.2" "the Library unhide step checks the attribute before deleting it" \
  'grep -q "xattr -p com.apple.FinderInfo" macos/defaults.sh'
# mds is root-owned, so an unprivileged killall always exits non-zero.
t "F1.3" "the Spotlight reload step can actually signal the root-owned daemon" \
  '[ "$(code_of macos/defaults.sh | grep -cE "^[[:space:]]*killall mds")" -eq 0 ]'

#############################################################################
section "F2 -- review round 1: no hostname in a tracked baseline"
#############################################################################
t "F2.1" "the committed baseline redacts the machine name" \
  'grep -q "NetBIOSName.\$COMPUTER_NAME$" macos/baselines/26.6.1.tsv'
t "F2.2" "capture redacts host-identifying keys rather than recording them" '
  W=$(mk "sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string x")
  O=$(sandbox)
  DOTFILES_DIR="$W" DOTFILES_BASELINE_DIR="$O" bash bin/dotfiles-baseline capture t >/dev/null 2>&1
  v=$(cut -f3 "$O/t.tsv")
  [ "$v" = "\$COMPUTER_NAME" ] || [ "$v" = "ABSENT" ]'

#############################################################################
section "F3 -- review round 1: B4 across every defaults file"
#############################################################################
# The brief's B4 named every macos/defaults*.sh, not just defaults.sh. A link
# or copy followed by a bare `ok` is the exact pattern B4 set out to remove.
# The sed blanks out link and copy lines that are already part of a condition,
# i.e. ones ending in `&&` or `; then`. What is left is an unguarded command
# whose next line is a bare `ok`.
t "F3.1" "no defaults file reports ok straight after an unchecked link or copy" '
  bad=0
  for f in macos/defaults-*.sh; do
    n=$(sed -E "s/^[[:space:]]*(ln|cp) .*(&&|then)[[:space:]]*$/GUARDED/" "$f" |
      grep -A1 -E "^[[:space:]]*(ln|cp) " | grep -cE "^[[:space:]]*ok$")
    [ "$n" -eq 0 ] || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "F3.2" "the four files the review named report a real status" '
  bad=0
  for f in defaults-xcode defaults-vlc defaults-vscode defaults-gitkraken; do
    grep -q "error " "macos/$f.sh" || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'

#############################################################################
section "F4 -- review round 2: every referenced repo path exists"
#############################################################################
# apps/vlc/org.videolan.vlc.plist was deliberately untracked by WS-D in
# ef649e6. Copying a file that is not there made the VLC block fail on every
# run, which is the defect class F1.2 and F1.3 removed.
# code_of, so the comment recording why the plist went does not read as the
# plist still being copied.
t "F4.1" "no macos script copies the untracked VLC plist" \
  '[ "$(code_of macos/*.sh | grep -c "org.videolan.vlc.plist")" -eq 0 ]'
# The general form of the same bug: a step that references a repo file which no
# longer exists can only ever report failure. The re-reviewer checked this by
# hand; this makes it a standing assertion.
# The dollar is written as [$] rather than \$: inside the double quotes this
# assertion is eval'd through, a bare $ is an end-of-line anchor and the grep
# silently matches nothing, which made the first version of this test pass over
# the very file it was written to catch.
t "F4.2" "every repo-relative path the macos scripts reference exists on disk" '
  missing=0
  # macos/local.sh is an optional, gitignored override: defaults.sh
  # sources it only when present, so it is not expected to exist.
  for p in $(grep -hoE "[\$]DOTFILES_DIR/[A-Za-z0-9_./-]+" macos/*.sh |
    sed "s|[\$]DOTFILES_DIR/||" | sort -u | grep -vx "macos/local.sh"); do
    [ -e "$p" ] || missing=$((missing + 1))
  done
  [ "$missing" -eq 0 ]'


#############################################################################
section "G0 -- harness: run a macos script against stub binaries"
#############################################################################
# Every command the scripts call is a stub on a sandbox PATH that appends
# "<name> <argv>" to $STUB_LOG; `sudo` logs itself and then runs the stub it was
# handed. The three absolute-path binaries (socketfilterfw, activateSettings,
# lsregister) are reached through DOTFILES_* seam variables. HOME is a sandbox,
# so nothing here reads or writes a real preference domain.
_stub() { # _stub <bindir> <name> [body]
  { printf '#!/bin/bash\n'
    printf 'printf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n' "$2"
    printf '%s\n' "${3:-}"
  } >"$1/$2"
  chmod +x "$1/$2"
}

# _g_env -- a fresh sandbox: home, stub bin, a DOTFILES_DIR holding only the
# helper scripts (so theme sources are absent unless a test adds them).
_g_env() {
  local W n
  W=$(sandbox) || return 1
  mkdir -p "$W/home" "$W/bin" "$W/df/macos" "$W/fw"
  cp -R "$ROOT_DIR/scripts" "$W/df/scripts"
  : >"$W/log"
  for n in defaults scutil pmset sysadminctl killall osascript chflags mdutil open \
    activateSettings lsregister dockutil; do
    _stub "$W/bin" "$n"
  done
  _stub "$W/bin" sudo 'exec "$@"'
  _stub "$W/bin" systemsetup 'exit ${SYSTEMSETUP_RC:-0}'
  _stub "$W/bin" xattr 'exit 1'
  _stub "$W/bin" sleep ''
  _stub "$W/bin" sysctl 'echo 8'
  # The firewall: setters only take effect when FW_TAKES is set, which is what
  # the owner's current Mac does without Full Disk Access (exit 0, no change).
  _stub "$W/bin" socketfilterfw '
case "$1" in
  --setglobalstate) [ -n "${FW_TAKES:-}" ] && echo "$2" >"$FW_STATE/global" ;;
  --setstealthmode) [ -n "${FW_TAKES:-}" ] && echo "$2" >"$FW_STATE/stealth" ;;
  --getglobalstate)
    if [ "$(cat "$FW_STATE/global" 2>/dev/null)" = on ]; then
      echo "Firewall is enabled. (State = 1)"; else echo "Firewall is disabled. (State = 0)"; fi ;;
  --getstealthmode)
    if [ "$(cat "$FW_STATE/stealth" 2>/dev/null)" = on ]; then
      echo "Stealth mode enabled"; else echo "Stealth mode disabled"; fi ;;
esac
exit 0'
  printf '%s' "$W"
}

# _g_run <W> <macos-file> [VAR=val ...] -- run one macos script under bash 3.2
# with stdin closed. The sudo keep-alive loop in defaults.sh is cut out: it
# would outlive the run. Output lands in $W/out.
_g_run() {
  local W=$1 f=$2
  shift 2
  awk '/^# Ask for the administrator password upfront/ { skip = 1 }
       !skip { print }
       skip && /^done 2>\/dev\/null &/ { skip = 0 }' "$ROOT_DIR/macos/$f" >"$W/df/macos/$f"
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/df" \
    STUB_LOG="$W/log" FW_STATE="$W/fw" TMPDIR="$W" \
    DOTFILES_SOCKETFILTERFW="$W/bin/socketfilterfw" \
    DOTFILES_ACTIVATE_SETTINGS="$W/bin/activateSettings" \
    DOTFILES_LSREGISTER="$W/bin/lsregister" \
    "$@" /bin/bash "$W/df/macos/$f" </dev/null >"$W/out" 2>&1
}

# _logged <W> <exact line> -- did a stub see exactly that command line?
_logged() { grep -qxF -- "$2" "$1/log"; }
# _logcount <W> <fixed string> -- how many logged lines contain it.
_logcount() { grep -cF -- "$2" "$1/log"; }

t "G0.1" "the harness runs defaults.sh and its stubs see the calls" '
  W=$(_g_env) && _g_run "$W" defaults.sh && _logged "$W" "defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2"'

#############################################################################
section "G1 -- personal values live in a gitignored macos/local.sh"
#############################################################################
DEF=$(_g_env); _g_run "$DEF" defaults.sh
LOC=$(_g_env)
cat >"$LOC/df/macos/local.sh" <<'FIXTURE'
DOTFILES_COMPUTER_NAME="fixture-mac"
DOTFILES_LANGUAGES="xx-YY zz-YY"
DOTFILES_LOCALE="xx_YY@currency=EUR"
DOTFILES_MEASUREMENT_UNITS="Inches"
DOTFILES_TIMEZONE="Etc/Fixture"
FIXTURE
_g_run "$LOC" defaults.sh

t "G1.1" "no local file: the computer is not renamed" \
  '[ "$(_logcount "$DEF" "scutil")" -eq 0 ] && [ "$(_logcount "$DEF" "NetBIOSName")" -eq 0 ]'
t "G1.2" "no local file: no timezone call" \
  '[ "$(_logcount "$DEF" "-settimezone")" -eq 0 ]'
t "G1.3" "no local file: languages, locale and units are left alone" \
  '[ "$(_logcount "$DEF" "AppleLanguages")" -eq 0 ] && [ "$(_logcount "$DEF" "AppleLocale")" -eq 0 ] && [ "$(_logcount "$DEF" "AppleMeasurementUnits")" -eq 0 ]'
t "G1.4" "local file: all four names carry the fixture value" '
  _logged "$LOC" "scutil --set ComputerName fixture-mac" &&
  _logged "$LOC" "scutil --set HostName fixture-mac" &&
  _logged "$LOC" "scutil --set LocalHostName fixture-mac" &&
  _logged "$LOC" "defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string fixture-mac"'
t "G1.5" "local file: languages, locale, units and timezone carry the fixture values" '
  _logged "$LOC" "defaults write NSGlobalDomain AppleLanguages -array xx-YY zz-YY" &&
  _logged "$LOC" "defaults write NSGlobalDomain AppleLocale -string xx_YY@currency=EUR" &&
  _logged "$LOC" "defaults write NSGlobalDomain AppleMeasurementUnits -string Inches" &&
  _logged "$LOC" "systemsetup -settimezone Etc/Fixture"'
t "G1.6" "Inches does not also declare metric units" \
  '_logged "$LOC" "defaults write NSGlobalDomain AppleMetricUnits -bool false"'
t "G1.7" "defaults.sh carries no computer name, locale or timezone literal" \
  '[ "$(code_of macos/defaults.sh | grep -cE "STiXzoOR|en_CY|el-CY|Europe/Athens")" -eq 0 ]'
t "G1.8" "local.sh is gitignored and only the example is tracked" \
  'git check-ignore -q macos/local.sh && [ ! -e macos/local.sh ] && [ -f macos/local.sh.example ]'
t "G1.9" "the example sets every variable the script reads" '
  bad=0
  for v in DOTFILES_COMPUTER_NAME DOTFILES_LANGUAGES DOTFILES_LOCALE DOTFILES_MEASUREMENT_UNITS DOTFILES_TIMEZONE; do
    grep -q "^$v=" macos/local.sh.example || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "G1.10" "the example holds placeholders, not a real name" \
  '[ "$(grep -ci "stix" macos/local.sh.example)" -eq 0 ] && grep -q "^DOTFILES_COMPUTER_NAME=\"my-mac\"" macos/local.sh.example'

#############################################################################
section "G2 -- the repo reproduces the owner's live settings"
#############################################################################
# Each line is the exact argv a `defaults write` must carry.
_g_missing() { # _g_missing <W> <expected-lines-file>
  local n=0 l
  while IFS= read -r l; do
    _logged "$1" "$l" || { n=$((n + 1)); printf "missing: %s\n" "$l" >&2; }
  done <"$2"
  printf '%s' "$n"
}
EXP=$(sandbox)/g2.txt
cat >"$EXP" <<'LINES'
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
defaults write com.apple.WindowManager StandardHideWidgets -bool false
defaults write com.apple.WindowManager HideDesktop -bool true
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
defaults write NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
defaults write NSGlobalDomain com.apple.sound.beep.sound -string /System/Library/Sounds/Blow.aiff
defaults write com.apple.finder FXRemoveOldTrashItems -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.dock expose-group-apps -bool true
defaults write com.apple.dock expose-animation-duration -float 0.1
LINES
t "G2.1" "defaults.sh writes the live values and the new tweaks" \
  '[ "$(_g_missing "$DEF" "$EXP")" -eq 0 ]'
t "G2.2" "the old values are gone" '
  ! _logged "$DEF" "defaults write NSGlobalDomain KeyRepeat -int 1" &&
  ! _logged "$DEF" "defaults write NSGlobalDomain AppleKeyboardUIMode -int 2" &&
  ! _logged "$DEF" "defaults write com.apple.WindowManager StandardHideWidgets -bool true"'
t "G2.3" "File Info panes are added one by one, all six open, never as a whole dict" '
  bad=0
  for p in General OpenWith Privileges Comments MetaData Name; do
    [ "$(grep -F "FXInfoPanesExpanded -dict-add" "$DEF/log" | grep -cF "$p -bool true")" -ge 1 ] || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ] && [ "$(grep -cF "FXInfoPanesExpanded -dict " "$DEF/log")" -eq 0 ]'
t "G2.4" "Activity Monitor icon type is 3" '
  W=$(_g_env) && _g_run "$W" defaults-activitymonitor.sh && _logged "$W" "defaults write com.apple.ActivityMonitor IconType -int 3"'
t "G2.5" "Transmission no longer asks before downloading or opening magnets" '
  W=$(_g_env) && _g_run "$W" defaults-transmission.sh &&
  _logged "$W" "defaults write org.m0k.transmission DownloadAsk -bool false" &&
  _logged "$W" "defaults write org.m0k.transmission MagnetOpenAsk -bool false"'
t "G2.6" "the Dock lists Spark Mail after the other apps, behind the existence guard" '
  [ "$(_first_line "/Applications/Setapp/Spark Mail.app" macos/dock.sh)" -gt "$(_first_line "System Settings.app" macos/dock.sh)" ] &&
  grep -q -- "-d \"\$icon\"" macos/dock.sh'

# Symbolic hotkeys: 64 Spotlight, 65 Finder search (Raycast), 28-31 screenshots
# (Shottr). id, ascii, keycode, modifiers.
_hk() { printf 'defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add %s <dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>%s</integer><integer>%s</integer><integer>%s</integer></array><key>type</key><string>standard</string></dict></dict>\n' "$1" "$2" "$3" "$4"; }
HKX=$(sandbox)/hk.txt
{ _hk 64 32 49 1048576; _hk 65 32 49 1572864; _hk 28 51 20 1179648
  _hk 29 51 20 1441792; _hk 30 52 21 1179648; _hk 31 52 21 1441792; } >"$HKX"
t "G2.7" "the six symbolic hotkeys are disabled with their exact parameters" \
  '[ "$(_g_missing "$DEF" "$HKX")" -eq 0 ]'
t "G2.8" "the hotkey change is activated without a logout" \
  '_logged "$DEF" "activateSettings -u"'
t "G2.9" "a missing activateSettings is skipped, not an error" '
  W=$(_g_env) && command rm -f "$W/bin/activateSettings" && _g_run "$W" defaults.sh &&
  [ "$(_logcount "$W" "activateSettings")" -eq 0 ]'
t "G2.10" "activateSettings is guarded by an executable test" \
  'code_of macos/defaults.sh | grep -qE "\[ -x .*ACTIVATE_SETTINGS"'

#############################################################################
section "G3 -- security and power"
#############################################################################
FWOK=$(_g_env); _g_run "$FWOK" defaults.sh FW_TAKES=1
# DEF ran without FW_TAKES: the firewall setters exit 0 and change nothing.
t "G3.1" "firewall setters carry the declared values" '
  _logged "$FWOK" "socketfilterfw --setglobalstate on" && _logged "$FWOK" "socketfilterfw --setstealthmode on" &&
  _logged "$FWOK" "socketfilterfw --setallowsigned on" && _logged "$FWOK" "socketfilterfw --setallowsignedapp off"'
t "G3.2" "the firewall state is read back after it is set" '
  _logged "$FWOK" "socketfilterfw --getglobalstate" && _logged "$FWOK" "socketfilterfw --getstealthmode"'
t "G3.3" "a firewall that took effect prints no error naming Full Disk Access" \
  '[ "$(grep -c "error.*Full Disk Access" "$FWOK/out")" -eq 0 ]'
t "G3.4" "an unchanged firewall state is an error naming Full Disk Access" \
  '[ "$(grep -c "error.*Full Disk Access" "$DEF/out")" -ge 1 ]'
t "G3.5" "stealth and global state are checked separately" \
  '[ "$(grep -c "error.*Full Disk Access" "$DEF/out")" -ge 2 ]'
t "G3.6" "the Full Disk Access notice comes first in the security block" '
  a=$(grep -n "Full Disk Access" "$FWOK/out" | head -1 | cut -d: -f1)
  b=$(grep -n "remote apple events" "$FWOK/out" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] &&
  [ "$(grep "Full Disk Access" "$FWOK/out" | grep -c warning)" -ge 1 ]'
t "G3.7" "Remote Login is turned on, without the confirmation prompt" \
  '_logged "$DEF" "systemsetup -setremotelogin -f on" && [ "$(_logcount "$DEF" "-setremotelogin -f off")" -eq 0 ]'
t "G3.8" "a failing systemsetup is reported as an error" '
  W=$(_g_env) && _g_run "$W" defaults.sh SYSTEMSETUP_RC=1 &&
  grep -A0 "remote login" "$W/out" | grep -q "error"'
t "G3.9" "power settings: restart after power loss, no powernap, no disk sleep, no wake-on-LAN" '
  _logged "$DEF" "sudo pmset -a autorestart 1" && _logged "$DEF" "sudo pmset -a powernap 0" &&
  _logged "$DEF" "sudo pmset -a disksleep 0" && _logged "$DEF" "sudo pmset -a womp 0"'
t "G3.10" "the dead standbydelay write is gone" \
  '[ "$(_logcount "$DEF" "standbydelay")" -eq 0 ]'
t "G3.11" "the screen locks with a password immediately" \
  '_logged "$DEF" "defaults write com.apple.screensaver askForPassword -int 1" && _logged "$DEF" "defaults write com.apple.screensaver askForPasswordDelay -int 0"'
t "G3.12" "no terminal: sysadminctl is printed for the owner, not run" \
  '[ "$(_logcount "$DEF" "sysadminctl")" -eq 0 ] && grep -q "sysadminctl -screenLock immediate -password -" "$DEF/out"'
# Real terminal: BSD script(1) allocates a pty, which is what `[ -t 0 ]` needs.
_g_run_tty() { # _g_run_tty <W> [VAR=val ...]
  local W=$1
  shift
  awk '/^# Ask for the administrator password upfront/ { skip = 1 }
       !skip { print }
       skip && /^done 2>\/dev\/null &/ { skip = 0 }' "$ROOT_DIR/macos/defaults.sh" >"$W/df/macos/defaults.sh"
  script -q "$W/out" env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/df" \
    STUB_LOG="$W/log" FW_STATE="$W/fw" TMPDIR="$W" \
    DOTFILES_SOCKETFILTERFW="$W/bin/socketfilterfw" \
    DOTFILES_ACTIVATE_SETTINGS="$W/bin/activateSettings" \
    DOTFILES_LSREGISTER="$W/bin/lsregister" \
    "$@" /bin/bash "$W/df/macos/defaults.sh" </dev/null >/dev/null 2>&1
}
if command -v script >/dev/null 2>&1; then
  t "G3.13" "on a terminal, sysadminctl sets the lock (it prompts for the password itself)" '
    W=$(_g_env) && _g_run_tty "$W" && _logged "$W" "sysadminctl -screenLock immediate -password -"'
  t "G3.14" "on a terminal with DOTFILES_YES, sysadminctl is not run" '
    W=$(_g_env) && _g_run_tty "$W" DOTFILES_YES=1 && [ "$(_logcount "$W" "sysadminctl")" -eq 0 ]'
fi
t "G3.15" "the comment that said the screen lock is never run is gone" \
  '[ "$(grep -ci "never run\|leave the lock delay alone" macos/defaults.sh)" -eq 0 ]'

#############################################################################
section "G4 -- dead and fragile bits"
#############################################################################
t "G4.1" "the Xcode Simulator symlink block is gone" \
  '[ "$(code_of macos/defaults.sh | grep -c "Simulator")" -eq 0 ] && [ "$(_logcount "$DEF" "Simulator")" -eq 0 ]'
t "G4.2" "the ineffective highlight colour is gone" \
  '[ "$(code_of macos/defaults.sh | grep -c "AppleHighlightColor")" -eq 0 ]'

# _theme_env <file> <source-relpath...> -- sandbox, optionally with theme sources.
XC_DEST=Library/Developer/Xcode/UserData/FontAndColorThemes/Nord.xccolortheme
t "G4.3" "xcode: theme source absent -> no link, warning, existing theme untouched, theme not selected" '
  W=$(_g_env) && mkdir -p "$W/home/$(dirname "$XC_DEST")" && echo old >"$W/home/$XC_DEST" &&
  _g_run "$W" defaults-xcode.sh &&
  [ ! -L "$W/home/$XC_DEST" ] && [ "$(cat "$W/home/$XC_DEST")" = old ] &&
  grep -q "warning" "$W/out" && [ "$(_logcount "$W" "XCFontAndColorCurrentTheme")" -eq 0 ]'
t "G4.4" "xcode: theme source present -> linked and selected" '
  W=$(_g_env) && mkdir -p "$W/df/apps/xcode/nord_theme/src" && echo new >"$W/df/apps/xcode/nord_theme/src/Nord.xccolortheme" &&
  _g_run "$W" defaults-xcode.sh &&
  [ "$(cat "$W/home/$XC_DEST")" = new ] && [ -L "$W/home/$XC_DEST" ] && [ "$(_logcount "$W" "XCFontAndColorCurrentTheme")" -eq 1 ]'

GK_DEST=.gitkraken/themes/nord-dark.jsonc
t "G4.5" "gitkraken: theme source absent -> no link, warning, existing theme untouched" '
  W=$(_g_env) && mkdir -p "$W/home/.gitkraken/themes" && echo old >"$W/home/$GK_DEST" &&
  _g_run "$W" defaults-gitkraken.sh &&
  [ ! -L "$W/home/$GK_DEST" ] && [ "$(cat "$W/home/$GK_DEST")" = old ] && grep -q "warning" "$W/out"'
t "G4.6" "gitkraken: profiles source absent -> the existing profiles are not replaced by a dangling link" '
  W=$(_g_env) && mkdir -p "$W/home/.gitkraken/profiles" && echo keep >"$W/home/.gitkraken/profiles/p" &&
  _g_run "$W" defaults-gitkraken.sh &&
  [ ! -L "$W/home/.gitkraken/profiles" ] && [ "$(cat "$W/home/.gitkraken/profiles/p")" = keep ]'
t "G4.7" "gitkraken: theme source present -> linked" '
  W=$(_g_env) && mkdir -p "$W/df/apps/gitkraken/themes/Themes/Nord" && echo new >"$W/df/apps/gitkraken/themes/Themes/Nord/nord-dark.jsonc" &&
  _g_run "$W" defaults-gitkraken.sh && [ -L "$W/home/$GK_DEST" ] && [ "$(cat "$W/home/$GK_DEST")" = new ]'

t "G4.8" "terminal: theme file absent -> not opened, not selected, warning" '
  W=$(_g_env) && _g_run "$W" defaults-terminal.sh &&
  [ "$(_logcount "$W" "open ")" -eq 0 ] && [ "$(_logcount "$W" "Default Window Settings -string Nord")" -eq 0 ] &&
  grep -q "warning" "$W/out"'
t "G4.9" "terminal: theme file present -> opened and selected" '
  W=$(_g_env) && mkdir -p "$W/df/apps/terminal/nord_theme/src/xml" && : >"$W/df/apps/terminal/nord_theme/src/xml/Nord.terminal" &&
  _g_run "$W" defaults-terminal.sh &&
  [ "$(_logcount "$W" "open ")" -eq 1 ] && [ "$(_logcount "$W" "Default Window Settings -string Nord")" -eq 1 ]'
t "G4.10" "terminal.sh no longer carries the Warp block" \
  '[ "$(code_of macos/defaults-terminal.sh | grep -ci "warp")" -eq 0 ]'

t "G4.11" "warp: theme sources absent -> installed themes are not removed, warning" '
  W=$(_g_env) && mkdir -p "$W/home/.warp/themes" && echo keep >"$W/home/.warp/themes/mine.yaml" &&
  _g_run "$W" defaults-warp.sh &&
  [ "$(cat "$W/home/.warp/themes/mine.yaml")" = keep ] && grep -q "warning" "$W/out"'
t "G4.12" "warp: theme sources present -> copied, and the old ones replaced" '
  W=$(_g_env) && mkdir -p "$W/home/.warp/themes" "$W/df/apps/warp/themes/standard" "$W/df/apps/warp/themes/base16" &&
  echo old >"$W/home/.warp/themes/stale.yaml" && echo a >"$W/df/apps/warp/themes/standard/nord.yaml" && echo b >"$W/df/apps/warp/themes/base16/b16.yaml" &&
  _g_run "$W" defaults-warp.sh &&
  [ "$(cat "$W/home/.warp/themes/nord.yaml")" = a ] && [ "$(cat "$W/home/.warp/themes/b16.yaml")" = b ] && [ ! -e "$W/home/.warp/themes/stale.yaml" ]'
t "G4.13" "warp: only one theme source present -> nothing is removed" '
  W=$(_g_env) && mkdir -p "$W/home/.warp/themes" "$W/df/apps/warp/themes/standard" &&
  echo keep >"$W/home/.warp/themes/mine.yaml" && echo a >"$W/df/apps/warp/themes/standard/nord.yaml" &&
  _g_run "$W" defaults-warp.sh && [ "$(cat "$W/home/.warp/themes/mine.yaml")" = keep ]'

#############################################################################
section "G5 -- captured app configs"
#############################################################################
t "G5.1" "the captured Warp settings name the theme by ~, never an absolute home path" \
  '[ -f apps/warp/settings.toml ] && [ "$(grep -c "/Users/" apps/warp/settings.toml)" -eq 0 ] && grep -q "~/.warp/themes/nord.yaml" apps/warp/settings.toml'
t "G5.2" "warp: settings absent -> installed with the theme path rendered to this HOME" '
  W=$(_g_env) && mkdir -p "$W/df/apps/warp" && command cp apps/warp/settings.toml "$W/df/apps/warp/settings.toml" &&
  _g_run "$W" defaults-warp.sh &&
  grep -qF "path = \"$W/home/.warp/themes/nord.yaml\"" "$W/home/.warp/settings.toml"'
t "G5.3" "warp: an existing different settings file is never overwritten" '
  W=$(_g_env) && mkdir -p "$W/df/apps/warp" "$W/home/.warp" && command cp apps/warp/settings.toml "$W/df/apps/warp/settings.toml" &&
  echo "mine = true" >"$W/home/.warp/settings.toml" &&
  _g_run "$W" defaults-warp.sh &&
  [ "$(cat "$W/home/.warp/settings.toml")" = "mine = true" ] && grep -q "warning" "$W/out"'
t "G5.4" "warp: an identical settings file is left as it is, without a warning about it" '
  W=$(_g_env) && mkdir -p "$W/df/apps/warp" && command cp apps/warp/settings.toml "$W/df/apps/warp/settings.toml" &&
  _g_run "$W" defaults-warp.sh && command cp "$W/home/.warp/settings.toml" "$W/first" &&
  _g_run "$W" defaults-warp.sh && cmp -s "$W/first" "$W/home/.warp/settings.toml" &&
  [ "$(grep -c "settings.*warning\|warning.*settings" "$W/out")" -eq 0 ]'
t "G5.5" "the captured Warp settings hold no token or account identifier" \
  '[ "$(grep -ciE "(api[_-]?key|token|secret|password|email)[a-z_]* *= *\"" apps/warp/settings.toml)" -eq 0 ]'
t "G5.6" "atuin config sets enter_accept and is a valid, minimal file" \
  'grep -q "^enter_accept = true" config/atuin/config.toml && [ "$(head -1 config/atuin/config.toml | cut -c1)" = "#" ]'
t "G5.7" "gh config: https protocol and the co alias" \
  'grep -q "^git_protocol: https" config/gh/config.yml && grep -q "co: pr checkout" config/gh/config.yml'
t "G5.8" "gh hosts.yml (holds the login) is gitignored and not tracked" \
  'git check-ignore -q config/gh/hosts.yml && [ -z "$(git ls-files config/gh/hosts.yml)" ]'
t "G5.9" "gh config carries no token" \
  '[ "$(grep -ciE "oauth_token|ghp_|gho_|github_pat" config/gh/config.yml)" -eq 0 ]'
t "G5.10" "the VS Code keybindings are valid JSON with the two ctrl+d bindings" \
  'jq -e "map(select(.key == \"ctrl+d\")) | length == 2" <(sed "/^[[:space:]]*\/\//d" apps/vscode/keybindings.json) >/dev/null'
t "G5.11" "the VS Code installer links keybindings.json beside settings.json" '
  W=$(_g_env) && mkdir -p "$W/df/apps/vscode" && echo "{}" >"$W/df/apps/vscode/settings.json" && echo "[]" >"$W/df/apps/vscode/keybindings.json" &&
  _g_run "$W" defaults-vscode.sh &&
  [ -L "$W/home/Library/Application Support/Code/User/keybindings.json" ] && [ -L "$W/home/Library/Application Support/Code/User/settings.json" ]'
t "G5.12" "config/atuin and config/gh stow into a sandbox ~/.config, and hosts.yml is not part of it" \
  '! command -v stow >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/xdg" &&
     stow -d "$ROOT_DIR" -t "$W/xdg" config >/dev/null 2>&1 &&
     [ -f "$W/xdg/atuin/config.toml" ] && [ -f "$W/xdg/gh/config.yml" ] && [ ! -e "$W/xdg/gh/hosts.yml" ]
   }'

finish

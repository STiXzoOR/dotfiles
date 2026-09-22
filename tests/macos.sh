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
  'grep -q "socketfilterfw --setglobalstate on" macos/defaults.sh && grep -q "setstealthmode on" macos/defaults.sh'
# The brief's plain grep already matched the comment that documented the
# command without running it, which is exactly the state the audit flagged.
# code_of strips whole-line comments, so this asks for real code.
t "B5.2" "no screen-lock enforcement (user decision 2026-09-21: leave the lock delay alone)" \
  '[ "$(code_of macos/defaults.sh | grep -cE "sysadminctl -screenLock|askForPasswordDelay")" -eq 0 ]'
t "B5.3" "software update keys in /Library/Preferences" \
  'grep -q "/Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall" macos/defaults-appstore.sh && grep -q "ConfigDataInstall" macos/defaults-appstore.sh'
t "B5.4" "mail defaults gated on the container" \
  'grep -q "Containers/com.apple.mail" macos/defaults-mail.sh'
t "B5.5" "transmission asks before downloading" \
  'grep -q "DownloadAsk -bool true" macos/defaults-transmission.sh'
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
t "B5.10" "magnet links ask too" \
  'grep -q "MagnetOpenAsk -bool true" macos/defaults-transmission.sh'

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
t "F1.1" "remote login is turned off without an invisible confirmation prompt" \
  'grep -q -- "-setremotelogin -f off" macos/defaults.sh'
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
  for p in $(grep -hoE "[\$]DOTFILES_DIR/[A-Za-z0-9_./-]+" macos/*.sh |
    sed "s|[\$]DOTFILES_DIR/||" | sort -u); do
    [ -e "$p" ] || missing=$((missing + 1))
  done
  [ "$missing" -eq 0 ]'

finish

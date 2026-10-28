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
  'W=$(mk "defaults write com.apple.print.PrintingPrefs \"Quit When Finished\" -bool true"); out=$(DOTFILES_DIR="$W" bash bin/dotfiles-baseline list); [ "$(printf "%s\n" "$out" | grep -c "Quit When Finished")" -ge 1 ]'
t "B1.2" "indented writes are captured" \
  'W=$(mk "  defaults write com.apple.terminal \"Default Window Settings\" -string Nord"); out=$(DOTFILES_DIR="$W" bash bin/dotfiles-baseline list); [ "$(printf "%s\n" "$out" | grep -c "Default Window Settings")" -ge 1 ]'
t "B1.3" "sudo writes are captured with their domain path" \
  'W=$(mk "sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"); out=$(DOTFILES_DIR="$W" bash bin/dotfiles-baseline list); [ "$(printf "%s\n" "$out" | grep -c "GuestEnabled")" -ge 1 ]'
t "B1.4" "-currentHost writes are captured" \
  'W=$(mk "defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true"); out=$(DOTFILES_DIR="$W" bash bin/dotfiles-baseline list); [ "$(printf "%s\n" "$out" | grep -c "disableHotPlug")" -ge 1 ]'
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
  'grep -q -- "-d \"\$DOCK_ROOT\$icon\"" macos/dock.sh'
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
  '[ "$(code_of scripts/lib/defaults-common.sh | grep -c -- "--setglobalstate on")" -ge 1 ] && [ "$(code_of scripts/lib/defaults-common.sh | grep -c -- "--setstealthmode on")" -ge 1 ] &&
   [ "$(code_of macos/defaults.sh | grep -c "dotfiles_firewall_on")" -ge 1 ]'
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
# Liquid Glass came out fully tinted on the Mac mini; the owner wants the system look.
t "B5.7" "reduceTransparency is never turned on, and increaseContrast and reduceMotion are not set" \
  '[ "$(cat macos/defaults*.sh | grep -ci "reduceTransparency -bool true\|increaseContrast\|reduceMotion")" -eq 0 ]'
t "B5.7b" "the dark appearance is still declared" \
  'grep -q "AppleInterfaceStyle -string Dark" macos/defaults.sh'
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
PLIST=launchagents/com.stixzoor.dotfiles-apps-backup.plist
t "B6.1" "the app-settings agent is enabled: a top-level plist, the old one is gone" \
  '[ -f "$PLIST" ] && [ ! -e launchagents/disabled/com.stixzoor.mackup-auto.plist ]'
t "B6.2" "the plist is valid and logs nowhere in /tmp (the script logs itself under ~/Library/Logs)" \
  '[ "$(grep -c "/tmp" "$PLIST")" -eq 0 ] && [ "$(grep -c "<key>StandardOutPath</key>" "$PLIST")" -eq 0 ] &&
   grep -q "Library/Logs" bin/dotfiles-apps &&
   { ! command -v plutil >/dev/null 2>&1 || plutil -lint "$PLIST" >/dev/null; }'
t "B6.3" "README records mackup's real maintenance status" \
  'grep -q "0.11.2" launchagents/disabled/README.md'
t "B6.4" "README says to copy a plist rather than symlink it" \
  '[ "$(grep -ci "symlink" launchagents/disabled/README.md)" -ge 1 ] && grep -qi "copy" launchagents/disabled/README.md'
t "B6.5" "the agent runs dotfiles-apps backup --scheduled through bash -c, daily at 12:30, not at load" \
  'body=$(command cat "$PLIST")
   printf "%s\n" "$body" | grep -qF "exec \"\$HOME/.dotfiles/bin/dotfiles-apps\" backup --scheduled" &&
   printf "%s\n" "$body" | grep -A1 "<key>Hour</key>" | grep -q "<integer>12</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>Minute</key>" | grep -q "<integer>30</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>RunAtLoad</key>" | grep -q "<false/>" &&
   printf "%s\n" "$body" | grep -A1 "<key>ProcessType</key>" | grep -q "<string>Background</string>"'

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
  'grep -q -- "-setremotelogin -f on" macos/defaults-remote-access.sh'
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
# _macos_missing_paths <file>... -- the repo-relative paths those scripts
# mention through $DOTFILES_DIR that neither exist nor are gitignored. A
# gitignored path (apps/gitkraken/profiles, created at run time by
# defaults-gitkraken.sh) is absent in every fresh clone, so it cannot be
# required; a tracked path that is missing is a real bug.
# macos/local.sh is an optional, gitignored override: defaults.sh sources it
# only when present.
_macos_missing_paths() {
  local p
  while IFS= read -r p; do
    [ -e "$p" ] && continue
    git check-ignore -q "$p" && continue
    printf '%s\n' "$p"
  done < <(grep -hoE "[\$]DOTFILES_DIR/[A-Za-z0-9_./-]+" "$@" |
    sed "s|[\$]DOTFILES_DIR/||" | sort -u | grep -vx "macos/local.sh")
}
t "F4.2" "every repo-relative path the macos scripts reference exists on disk, or is gitignored" '
  [ -z "$(_macos_missing_paths macos/*.sh)" ]'
t "F4.2b" "a tracked path that is missing is still reported, and a gitignored one is not" '
  W=$(sandbox) && printf "%s\n" "source \"\$DOTFILES_DIR/apps/nonexistent-tracked/x\"" >"$W/a.sh" &&
  printf "%s\n" "x=\"\$DOTFILES_DIR/apps/gitkraken/profiles\"" >"$W/b.sh" &&
  [ "$(_macos_missing_paths "$W/a.sh")" = "apps/nonexistent-tracked/x" ] &&
  [ -z "$(_macos_missing_paths "$W/b.sh")" ]'


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
  _stub "$W/bin" sudo 'case "${1:-}" in -v | -n) exit 0 ;; esac; exec "$@"'
  # `defaults` for com.tinycast.app: write records into $HK_STATE / $SFE_STATE,
  # `export <domain> <file>` writes a real plist holding them (what the script
  # reads through PlistBuddy), and `read` prints the value the way the real tool
  # does: quoted, inner quotes escaped. HK_FORCE replaces the stored hotkey.
  _stub "$W/bin" defaults '
if [ "$1 $2" = "write com.tinycast.app" ]; then
  case "$3" in
    # Like the real tool: an untyped value starting with "{" is parsed as an
    # old-style plist dictionary and rejected.
    hotkey.togglePalette)
      [ -z "${HK_WRITEFAIL:-}" ] || { echo "write failed" >&2; exit 1; }
      case "$4" in
        -string) printf "%s" "$5" >"$HK_STATE" ;;
        "{"*) echo "Could not parse: $4.  Try single-quoting it." >&2; exit 1 ;;
        *) printf "%s" "$4" >"$HK_STATE" ;;
      esac ;;
    settingsFileEnabled) [ "$4" = "-bool" ] && printf "%s" "$5" >"$SFE_STATE" ;;
  esac
fi
# universalaccess reduceTransparency: RT_INIT seeds it (unset = absent), RT_STUCK
# makes a write to false not stick.
if [ "$1 $2 $3" = "write com.apple.universalaccess reduceTransparency" ]; then
  [ ! -f "$W_STATE/rt" ] && [ -n "${RT_INIT:-}" ] && printf %s "$RT_INIT" >"$W_STATE/rt"
  [ -n "${RT_STUCK:-}" ] || { [ "$5" = false ] && printf 0 >"$W_STATE/rt" || printf 1 >"$W_STATE/rt"; }
fi
if [ "$1 $2 $3" = "read com.apple.universalaccess reduceTransparency" ]; then
  if [ -f "$W_STATE/rt" ]; then cat "$W_STATE/rt"; echo
  elif [ -n "${RT_INIT:-}" ]; then echo "$RT_INIT"
  else echo "The domain/default pair of (com.apple.universalaccess, reduceTransparency) does not exist" >&2; exit 1; fi
fi
# Global domain: writes are stored per key, reads print them (G_WRONG makes
# every read come back wrong, G_ABSENT makes it fail like a missing key).
if [ "$1 $2" = "write -g" ]; then printf "%s\n" "$5" >"$W_STATE/g.$3"; fi
if [ "$1 $2" = "read -g" ]; then
  [ -z "${G_ABSENT:-}" ] || exit 1
  if [ -n "${G_WRONG:-}" ]; then echo wrong; else cat "$W_STATE/g.$3" 2>/dev/null || exit 1; fi
fi
if [ "$1 $2" = "export com.tinycast.app" ]; then
  {
    printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\n"
    if [ -n "${HK_FORCE:-}" ]; then printf "<key>hotkey.togglePalette</key><string>%s</string>\n" "$HK_FORCE"
    elif [ -f "$HK_STATE" ]; then printf "<key>hotkey.togglePalette</key><string>%s</string>\n" "$(cat "$HK_STATE")"; fi
    if [ -n "${SFE_FORCE:-}" ]; then printf "<key>settingsFileEnabled</key><%s/>\n" "$SFE_FORCE"
    elif [ -f "$SFE_STATE" ]; then printf "<key>settingsFileEnabled</key><%s/>\n" "$(cat "$SFE_STATE")"; fi
    printf "</dict></plist>\n"
  } >"$3"
fi
if [ "$1 $2 $3" = "read com.tinycast.app hotkey.togglePalette" ]; then
  v=$(cat "$HK_STATE" 2>/dev/null); printf "\"%s\"\n" "$(printf "%s" "$v" | sed "s/\"/\\\\\"/g")"
fi
exit 0'
  _stub "$W/bin" pgrep '[ -e "$W_STATE/running" ] && [ "$1 $2" = "-x Tinycast" ]'
  _stub "$W/bin" osascript '
case "$*" in *"quit app \"Tinycast\""*) [ -n "${HK_STUCK:-}" ] || command rm -f "$W_STATE/running" ;; esac
exit 0'
  # A desktop unless a test says otherwise: a positive AC Power marker.
  _stub "$W/bin" pmset 'case "$*" in "-g batt") printf "%s\n" "Now drawing from '"'"'AC Power'"'"'" ;; esac'
  # Remote Login: the setter only takes effect when RL_TAKES is set (without
  # Full Disk Access systemsetup prints success and changes nothing).
  _stub "$W/bin" systemsetup '
case "$1" in
  -setremotelogin) [ -n "${RL_TAKES:-}" ] && [ "${SYSTEMSETUP_RC:-0}" -eq 0 ] && echo "${3:-$2}" >"$FW_STATE/rl" ;;
  -getremotelogin)
    if [ "$(cat "$FW_STATE/rl" 2>/dev/null)" = on ]; then echo "Remote Login: On"; else echo "Remote Login: Off"; fi
    exit 0 ;;
esac
exit ${SYSTEMSETUP_RC:-0}'
  # Remote Login fallbacks that work without Full Disk Access: launchd's
  # disabled list and sshd listening. RL_LAUNCHD / RL_PORT turn them on.
  _stub "$W/bin" launchctl '
if [ "$1" = bootout ] && [ -n "${LC_BOOTOUT_FAIL:-}" ]; then exit 1; fi
if [ "$1" = bootstrap ]; then [ -z "${LC_BOOTSTRAP_FAIL:-}" ] && : >"$FW_STATE/pfloaded" || exit 1; fi
if [ "$1" = print-disabled ]; then
  if [ -n "${RL_LAUNCHD:-}" ]; then echo "	\"com.openssh.sshd\" => enabled"; else echo "	\"com.openssh.sshd\" => disabled"; fi
fi
exit 0'
  _stub "$W/bin" nc 'case "$*" in *5900*) [ -n "${SS_PORT:-}" ] ;; *) [ -n "${RL_PORT:-}" ] ;; esac'
  mkdir -p "$W/Tinycast.app"
  # Remote access: the root-owned paths are seams that point into the sandbox.
  mkdir -p "$W/etc/ssh/sshd_config.d" "$W/etc/pf.anchors" "$W/Library/LaunchDaemons"
  [ ! -d "$ROOT_DIR/macos/remote-access" ] || cp -R "$ROOT_DIR/macos/remote-access" "$W/df/macos/remote-access"
  # install copies the last two arguments (ownership flags are for root only).
  _stub "$W/bin" install '
[ -z "${INSTALL_FAIL:-}" ] || exit 1
for a in "$@"; do p2=${p1:-}; p1=$a; done
cp "$p2" "$p1"'
  # sshd -t fails like a Mac that never ran Remote Login (no host keys yet)
  # when SSHD_RC is non-zero; ssh-keygen -A is the step that generates them.
  _stub "$W/bin" sshd '
[ "$1" = -t ] || exit 0
[ "${SSHD_RC:-0}" -eq 0 ] || echo "sshd: no hostkeys available -- exiting." >&2
exit ${SSHD_RC:-0}'
  _stub "$W/bin" ssh-keygen 'exit ${SSHKEYGEN_RC:-0}'
  # pfctl -sr lists rules once the daemon has loaded them (PF_EMPTY: never;
  # PF_LATE: not on the first look, as when launchd has not run the job yet).
  # -s info says pf is enabled unless PF_DISABLED is set.
  _stub "$W/bin" pfctl '
case "$*" in
  *" -sr")
    [ -f "$FW_STATE/pfloaded" ] && [ -z "${PF_EMPTY:-}" ] || exit ${PF_RC:-0}
    if [ -n "${PF_LATE:-}" ] && [ ! -e "$FW_STATE/pfseen" ]; then : >"$FW_STATE/pfseen"; exit 0; fi
    echo "block drop in quick proto tcp from any to any port = ssh" ;;
  "-s info") if [ -n "${PF_DISABLED:-}" ]; then echo "Status: Disabled"; else echo "Status: Enabled for 0 days 00:00:01"; fi ;;
esac
exit ${PF_RC:-0}'
  # dseditgroup: groups are files in $FW_STATE (GRP_EXIST=1 starts both empty,
  # as seen on a real Mac); members are one per line.
  _stub "$W/bin" dseditgroup '
for g; do :; done
f="$FW_STATE/grp.$g"
[ -z "${GRP_EXIST:-}" ] || [ -e "$f" ] || : >"$f"
case "$2" in
  read) [ -e "$f" ] ;;
  create) [ -z "${DSE_CREATE_FAIL:-}" ] && : >"$f" ;;
  edit) [ -z "${DSE_EDIT_FAIL:-}" ] && [ -e "$f" ] && echo "$4" >>"$f" ;;
  checkmember) [ -e "$f" ] && grep -qx "$4" "$f" ;;
esac'
  _stub "$W/bin" sw_vers 'echo "${SW_VERS:-27.0.1}"'
  # mdutil: -s reports MDUTIL_OFF; -i on fails like macOS 27 when MDUTIL_FAIL is set.
  _stub "$W/bin" mdutil '
case "$1" in
  -s) if [ -n "${MDUTIL_OFF:-}" ]; then printf "/:\n\tIndexing disabled.\n"; else printf "/:\n\tIndexing enabled. \n"; fi ;;
  -i) [ -z "${MDUTIL_FAIL:-}" ] || { echo "Error: unable to perform operation. (-400)" >&2; exit 1; } ;;
esac
exit 0'
  # lsregister: -kill was removed and fails like the real tool.
  _stub "$W/bin" lsregister '
[ -z "${LSR_FAIL:-}" ] || exit 1
for a in "$@"; do [ "$a" != -kill ] || { echo "# The -kill option has been removed because it was dangerous and no longer useful." >&2; exit 1; }; done
exit 0'
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
      if [ -n "${FW_BLOCKALL:-}" ]; then echo "Firewall is enabled. (State = 2)"; else echo "Firewall is enabled. (State = 1)"; fi
    else echo "Firewall is disabled. (State = 0)"; fi ;;
  --getstealthmode)
    if [ "$(cat "$FW_STATE/stealth" 2>/dev/null)" = on ]; then
      if [ -n "${FW_NEWWORD:-}" ]; then echo "Firewall stealth mode is on"; else echo "Stealth mode enabled"; fi
    else
      if [ -n "${FW_NEWWORD:-}" ]; then echo "Firewall stealth mode is off"; else echo "Stealth mode disabled"; fi
    fi ;;
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
  # G_TAIL: a line appended to the copy, to read variables the script leaves set.
  [ -z "${G_TAIL:-}" ] || printf '\n%s\n' "$G_TAIL" >>"$W/df/macos/$f"
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/df" \
    STUB_LOG="$W/log" FW_STATE="$W/fw" TMPDIR="$W" USER=tester \
    DOTFILES_SOCKETFILTERFW="$W/bin/socketfilterfw" \
    DOTFILES_ACTIVATE_SETTINGS="$W/bin/activateSettings" \
    DOTFILES_LSREGISTER="$W/bin/lsregister" \
    DOTFILES_SSHD="$W/bin/sshd" DOTFILES_SSH_KEYGEN="$W/bin/ssh-keygen" DOTFILES_SSHD_CONF_DIR="$W/etc/ssh/sshd_config.d" \
    DOTFILES_PF_ANCHOR_DIR="$W/etc/pf.anchors" DOTFILES_LAUNCHDAEMONS_DIR="$W/Library/LaunchDaemons" \
    DOTFILES_VNC_SETTINGS="$W/vnc.txt" \
    HK_STATE="$W/hk" SFE_STATE="$W/sfe" W_STATE="$W" DOTFILES_RAYCAST_APP="$W/Raycast.app" DOTFILES_TINYCAST_APP="$W/Tinycast.app" \
    "$@" /bin/bash "$W/df/macos/$f" </dev/null >"$W/out" 2>&1
}

# _logged <W> <exact line> -- did a stub see exactly that command line?
_logged() { grep -qxF -- "$2" "$1/log"; }
# _logcount <W> <fixed string> -- how many logged lines contain it.
_logcount() { grep -cF -- "$2" "$1/log"; }

# _ra_env -- a sandbox with a key in authorized_keys. _ra_run <W> [VAR=val ...]
# runs the remote access file with remote access on and every system change
# taking effect; later VAR=val arguments win.
_ra_env() {
  local W
  W=$(_g_env) || return 1
  mkdir -p "$W/home/.ssh"
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA phone" >"$W/home/.ssh/authorized_keys"
  printf '%s' "$W"
}
_ra_run() {
  local W=$1
  shift
  _g_run "$W" defaults-remote-access.sh DOTFILES_REMOTE_ACCESS=on FW_TAKES=1 RL_TAKES=1 SS_PORT=1 "$@"
}
# _ra_tally <W> [VAR=val ...] -- the failure count the file leaves behind.
_ra_tally() { G_TAIL='echo "TALLY=${DOTFILES_DEFAULTS_FAILURES:-0}"' _ra_run "$@"; sed -n 's/^TALLY=//p' "$1/out"; }

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
# Structural, so this file never has to name the private values it keeps out:
# every write of a personal value must take its DOTFILES_* variable.
_g_personal_bad() { # prints "<writes lacking their variable> <writes seen>"
  code_of macos/defaults.sh | awk '
    /scutil --set/ || /NetBIOSName/ { n++; if ($0 !~ /"\$DOTFILES_COMPUTER_NAME"/) bad++ }
    /AppleLanguages/                 { n++; if ($0 !~ /\$DOTFILES_LANGUAGES/) bad++ }
    /AppleLocale/                    { n++; if ($0 !~ /"\$DOTFILES_LOCALE"/) bad++ }
    /AppleMeasurementUnits/          { n++; if ($0 !~ /"\$DOTFILES_MEASUREMENT_UNITS"/) bad++ }
    /-settimezone/                   { n++; if ($0 !~ /"\$DOTFILES_TIMEZONE"/) bad++ }
    END { print bad + 0, n + 0 }'
}
t "G1.7" "every personal-value write in defaults.sh takes its DOTFILES_* variable, never a literal" \
  '[ "$(_g_personal_bad)" = "0 8" ]'
t "G1.8" "local.sh is gitignored and local.sh.example is tracked" \
  'git -c core.excludesFile=/dev/null check-ignore -q macos/local.sh && [ -n "$(git ls-files macos/local.sh.example)" ]'
t "G1.9" "the example sets every variable the script reads" '
  bad=0
  for v in DOTFILES_COMPUTER_NAME DOTFILES_LANGUAGES DOTFILES_LOCALE DOTFILES_MEASUREMENT_UNITS DOTFILES_TIMEZONE; do
    grep -q "^$v=" macos/local.sh.example || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "G1.10" "the example computer name is the generic placeholder" \
  'grep -q "^DOTFILES_COMPUTER_NAME=\"my-mac\"" macos/local.sh.example'

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
  grep -q -- "-d \"\$DOCK_ROOT\$icon\"" macos/dock.sh'

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
  '[ "$(code_of macos/defaults.sh | grep -cE "\[ -x .*ACTIVATE_SETTINGS")" -ge 1 ]'

#############################################################################
section "G3 -- security and power"
#############################################################################
FWOK=$(_g_env); _g_run "$FWOK" defaults.sh FW_TAKES=1 RL_TAKES=1
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
t "G3.5" "stealth and global state are each reported by name" \
  '[ "$(grep -c "error.*application firewall is still off" "$DEF/out")" -ge 1 ] &&
   [ "$(grep -c "error.*stealth mode is still off" "$DEF/out")" -ge 1 ]'
# State = 2 is "block all incoming connections": the firewall is on, more so.
BLK=$(_g_env); _g_run "$BLK" defaults.sh FW_TAKES=1 FW_BLOCKALL=1
t "G3.5b" "a firewall reading back State = 2 (block all) is on, not an error" \
  '[ "$(grep -c "error.*application firewall" "$BLK/out")" -eq 0 ]'
# The failed read-backs are tallied in DOTFILES_DEFAULTS_FAILURES, which
# `configure --defaults` turns into a non-zero status.
_tally() { G_TAIL='echo "TALLY=${DOTFILES_DEFAULTS_FAILURES:-0}"' _g_run "$1" defaults.sh "${@:2}"; sed -n 's/^TALLY=//p' "$1/out"; }
t "G3.5c" "unchanged firewall and stealth read-backs are tallied as failures" \
  'W=$(_g_env) && [ "$(_tally "$W")" -ge 2 ]'
t "G3.5d" "a firewall that took effect leaves the failure tally at zero" \
  'W=$(_g_env) && [ "$(_tally "$W" FW_TAKES=1 RL_TAKES=1)" -eq 0 ]'

t "G3.6" "the Full Disk Access notice comes first in the security block" '
  a=$(grep -n "Full Disk Access" "$FWOK/out" | head -1 | cut -d: -f1)
  b=$(grep -n "remote apple events" "$FWOK/out" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] &&
  [ "$(grep "Full Disk Access" "$FWOK/out" | grep -c warning)" -ge 1 ]'
t "G3.7" "Remote Login is turned on, without the confirmation prompt" \
  'W=$(_ra_env) && _ra_run "$W" && _logged "$W" "systemsetup -setremotelogin -f on" && [ "$(_logcount "$W" "-setremotelogin -f off")" -eq 0 ]'
t "G3.8" "a failing systemsetup is reported as an error" '
  W=$(_ra_env) && _ra_run "$W" RL_TAKES= SYSTEMSETUP_RC=1 &&
  grep -A0 "remote login" "$W/out" | grep -q "error"'
t "G3.8b" "Remote Login is read back after it is set" \
  'W=$(_ra_env) && _ra_run "$W" && _logged "$W" "systemsetup -getremotelogin"'
t "G3.8c" "Remote Login that took effect prints no Full Disk Access error" \
  'W=$(_ra_env) && _ra_run "$W" && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 0 ]'
t "G3.8d" "Remote Login left off is an error naming Full Disk Access" \
  'W=$(_ra_env) && _ra_run "$W" RL_TAKES= && grep -qE "error.*Remote Login.*Full Disk Access" "$W/out"'
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
  'git -c core.excludesFile=/dev/null check-ignore -q config/gh/hosts.yml && [ -z "$(git ls-files config/gh/hosts.yml)" ]'
t "G5.9" "gh config carries no token" \
  '[ "$(grep -ciE "oauth_token|ghp_|gho_|github_pat" config/gh/config.yml)" -eq 0 ]'
t "G5.10" "the VS Code keybindings are valid JSON with the two ctrl+d bindings" \
  'jq -e "map(select(.key == \"ctrl+d\")) | length == 2" <(sed "/^[[:space:]]*\/\//d" apps/vscode/keybindings.json) >/dev/null'
t "G5.10b" "the VS Code keybindings end with a newline" \
  '[ "$(tail -c 1 apps/vscode/keybindings.json | od -An -c | tr -d " ")" = "\\n" ]'
t "G5.11" "the VS Code installer links keybindings.json beside settings.json" '
  W=$(_g_env) && mkdir -p "$W/df/apps/vscode" && echo "{}" >"$W/df/apps/vscode/settings.json" && echo "[]" >"$W/df/apps/vscode/keybindings.json" &&
  _g_run "$W" defaults-vscode.sh &&
  [ -L "$W/home/Library/Application Support/Code/User/keybindings.json" ] && [ -L "$W/home/Library/Application Support/Code/User/settings.json" ]'
# Stowed from a copy of the tracked files only: on a Mac logged in to gh, the
# gitignored config/gh/hosts.yml sits in the checkout (~/.config/gh is folded
# into it), and it would be stowed from there although the repo never ships it.
t "G5.12" "config/atuin and config/gh stow into a sandbox ~/.config, and hosts.yml is not part of it" \
  '! command -v stow >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/xdg" "$W/repo" &&
     (cd "$ROOT_DIR" && git ls-files config | while IFS= read -r f; do
        mkdir -p "$W/repo/$(dirname "$f")" && cp "$f" "$W/repo/$f" || exit 1
      done) &&
     stow -d "$W/repo" -t "$W/xdg" config >/dev/null 2>&1 &&
     [ -f "$W/xdg/atuin/config.toml" ] && [ -f "$W/xdg/gh/config.yml" ] && [ ! -e "$W/xdg/gh/hosts.yml" ]
   }'

#############################################################################
section "G6 -- role gate: power is desktop only, Remote Login follows remote access"
#############################################################################
# _g_battery <W>: make the stub pmset answer like a laptop's `pmset -g batt`.
_g_battery() {
  _stub "$1/bin" pmset 'case "$*" in "-g batt") printf "%s\n" "Now drawing from Battery Power" " -InternalBattery-0 (id=1)	87%; discharging" ;; esac'
}
_g_touched() { # the desktop-only settings, as logged lines: count of any call
  _logcount "$1" "systemsetup -setremotelogin"; }
LAP=$(_g_env); _g_run "$LAP" defaults.sh DOTFILES_MACHINE_ROLE=laptop FW_TAKES=1
BAT=$(_g_env); _g_battery "$BAT"; _g_run "$BAT" defaults.sh FW_TAKES=1
DSK=$(_g_env); _g_battery "$DSK"; _g_run "$DSK" defaults.sh DOTFILES_MACHINE_ROLE=desktop FW_TAKES=1
# The same three Macs through the remote access file, with no explicit setting:
# the role alone decides.
LAPR=$(_ra_env); _g_run "$LAPR" defaults-remote-access.sh DOTFILES_MACHINE_ROLE=laptop FW_TAKES=1 RL_TAKES=1
BATR=$(_ra_env); _g_battery "$BATR"; _g_run "$BATR" defaults-remote-access.sh FW_TAKES=1 RL_TAKES=1
DSKR=$(_ra_env); _g_battery "$DSKR"; _g_run "$DSKR" defaults-remote-access.sh DOTFILES_MACHINE_ROLE=desktop FW_TAKES=1 RL_TAKES=1

t "G6.1" "laptop: Remote Login is left alone, neither turned on nor off" \
  '[ "$(_g_touched "$LAP")" -eq 0 ] && [ "$(_g_touched "$LAPR")" -eq 0 ]'
t "G6.2" "laptop: autorestart, powernap and disksleep are left alone" \
  '[ "$(_logcount "$LAP" "pmset -a autorestart")" -eq 0 ] && [ "$(_logcount "$LAP" "pmset -a powernap")" -eq 0 ] &&
   [ "$(_logcount "$LAP" "pmset -a disksleep")" -eq 0 ]'
t "G6.3" "laptop: firewall, stealth mode and the screen-lock password still apply" \
  '_logged "$LAP" "socketfilterfw --setglobalstate on" && _logged "$LAP" "socketfilterfw --setstealthmode on" &&
   _logged "$LAP" "defaults write com.apple.screensaver askForPassword -int 1" &&
   _logged "$LAP" "defaults write com.apple.screensaver askForPasswordDelay -int 0"'
t "G6.4" "laptop: the run says what it skipped and reports no error" \
  '[ "$(grep -ci "laptop" "$LAP/out")" -ge 1 ] && [ "$(grep -c "error" "$LAP/out")" -eq 0 ]'
t "G6.5" "a Mac whose pmset reports an InternalBattery is a laptop without any override" \
  '[ "$(_g_touched "$BATR")" -eq 0 ] && [ "$(_logcount "$BAT" "pmset -a autorestart")" -eq 0 ]'
t "G6.6" "DOTFILES_MACHINE_ROLE=desktop wins over the battery" \
  '_logged "$DSKR" "systemsetup -setremotelogin -f on" && _logged "$DSK" "sudo pmset -a autorestart 1" &&
   _logged "$DSK" "sudo pmset -a powernap 0" && _logged "$DSK" "sudo pmset -a disksleep 0"'
t "G6.7" "wake-on-LAN off is a security setting and applies to both roles" \
  '_logged "$LAP" "sudo pmset -a womp 0" && _logged "$DSK" "sudo pmset -a womp 0"'
t "G6.9" "desktop: never system-sleep on AC power, display sleeps after 10 minutes (the Mac stays reachable over SSH)" \
  '_logged "$DSK" "sudo pmset -c sleep 0" && _logged "$DSK" "sudo pmset -c displaysleep 10" &&
   _logged "$DEF" "sudo pmset -c sleep 0" && _logged "$DEF" "sudo pmset -c displaysleep 10"'
t "G6.10" "laptop: sleep and displaysleep are left alone, by override and by battery" \
  '[ "$(_logcount "$LAP" "pmset -c sleep")" -eq 0 ] && [ "$(_logcount "$LAP" "displaysleep")" -eq 0 ] &&
   [ "$(_logcount "$BAT" "pmset -c sleep")" -eq 0 ] && [ "$(_logcount "$BAT" "displaysleep")" -eq 0 ]'
t "G6.11" "the sleep settings are set for AC power only (-c), never for every power source" \
  '[ "$(_logcount "$DSK" "pmset -a sleep")" -eq 0 ] && [ "$(_logcount "$DSK" "pmset -a displaysleep")" -eq 0 ] &&
   [ "$(_logcount "$DSK" "pmset -b ")" -eq 0 ]'
t "G6.12" "a pmset that says nothing is a laptop: Remote Login and the power settings are not forced" '
  W=$(_ra_env); _stub "$W/bin" pmset ":"
  _g_run "$W" defaults.sh; cp "$W/log" "$W/log.defaults"; : >"$W/log"
  _g_run "$W" defaults-remote-access.sh FW_TAKES=1 RL_TAKES=1
  [ "$(_g_touched "$W")" -eq 0 ] && cat "$W/log.defaults" >>"$W/log" &&
  [ "$(_logcount "$W" "pmset -a autorestart")" -eq 0 ] && [ "$(_logcount "$W" "pmset -c sleep")" -eq 0 ]'
t "G6.8" "nothing in defaults.sh or the remote access file ever turns Remote Login off" \
  '[ "$(code_of macos/defaults.sh macos/defaults-remote-access.sh | grep -c -- "-setremotelogin.* off")" -eq 0 ] &&
   [ "$(code_of macos/defaults-remote-access.sh | grep -c -- "-setremotelogin")" -ge 1 ]'

#############################################################################
section "G8 -- the launcher block: Tinycast's Cmd-Space, or Raycast left alone"
#############################################################################
# The stubs are in _g_env. `defaults` remembers the hotkey it is asked to write
# and reads it back (HK_FORCE overrides the read-back); `pgrep` says Tinycast is
# running while $W/running exists; `osascript` quitting Tinycast removes it
# (HK_STUCK makes the quit fail). Nothing touches a real domain.
HK='{"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}'
_g_launch_run() { # _g_launch_run <W> [VAR=val ...]
  local W=$1
  shift
  _g_run "$W" defaults.sh "$@"
}

TC=$(_g_env); _g_launch_run "$TC"
t "G8.1" "default (no launcher configured): Tinycast's summon hotkey is set to Cmd-Space" \
  '_logged "$TC" "defaults write com.tinycast.app hotkey.togglePalette -string $HK"'
t "G8.2" "the Tinycast settings-file switch is turned on (the documented settingsFileEnabled default)" \
  '_logged "$TC" "defaults write com.tinycast.app settingsFileEnabled -bool true"'
t "G8.3" "the hotkey is read back after the write, as the raw value (not through defaults read, which quotes it)" \
  '[ "$(_first_line "defaults write com.tinycast.app hotkey.togglePalette" "$TC/log")" -gt 0 ] &&
   [ "$(sed -n "/defaults write com.tinycast.app hotkey.togglePalette/,\$p" "$TC/log" | grep -c "defaults export com.tinycast.app")" -ge 1 ] &&
   [ "$(_logcount "$TC" "defaults read com.tinycast.app")" -eq 0 ]'
t "G8.4" "a matching read-back reports no error and no warning about Tinycast (the real defaults read output is quoted and escaped, and must not matter)" \
  '! grep -qiE "tinycast.*(read back|still running)" "$TC/out" && ! grep -q "hotkey read back" "$TC/out"'
t "G8.5" "Spotlight Cmd-Space stays disabled (symbolic hotkey 64)" \
  '_logged "$TC" "$(_hk 64 32 49 1048576)"'

MM=$(_g_env); _g_launch_run "$MM" HK_FORCE=bogus
t "G8.6" "a read-back that differs is reported, not ignored" \
  'grep -qi "read back" "$MM/out" && grep -q "bogus" "$MM/out"'
t "G8.7" "a mismatch does not stop the rest of defaults.sh" \
  '_logged "$MM" "activateSettings -u"'

RUN=$(_g_env); : >"$RUN/running"; _g_launch_run "$RUN"
t "G8.8" "a running Tinycast is quit, then the hotkey is written" \
  '[ "$(_first_line "osascript -e quit app \"Tinycast\"" "$RUN/log")" -gt 0 ] &&
   [ "$(_first_line "osascript -e quit app \"Tinycast\"" "$RUN/log")" -lt "$(_first_line "defaults write com.tinycast.app hotkey.togglePalette" "$RUN/log")" ]'
t "G8.9" "a Tinycast that is not running is not quit" \
  '[ "$(_logcount "$TC" "quit app \"Tinycast\"")" -eq 0 ]'
STK=$(_g_env); : >"$STK/running"; _g_launch_run "$STK" HK_STUCK=1
t "G8.10" "a Tinycast that will not quit is skipped with a clear message, and nothing is written" \
  '[ "$(_logcount "$STK" "defaults write com.tinycast.app")" -eq 0 ] && grep -qi "still running" "$STK/out"'

RC=$(_g_env); mkdir -p "$RC/Raycast.app"; _g_launch_run "$RC" DOTFILES_LAUNCHER=raycast
t "G8.11" "launcher=raycast: Tinycast's domain is never touched" \
  '[ "$(_logcount "$RC" "com.tinycast.app")" -eq 0 ]'
t "G8.12" "launcher=raycast: no warning about Raycast holding Cmd-Space" \
  '! grep -q "brew uninstall --cask raycast" "$RC/out"'
t "G8.13" "launcher=raycast: the rest of defaults.sh still runs (hotkey activation)" \
  '_logged "$RC" "activateSettings -u"'

RP=$(_g_env); mkdir -p "$RP/Raycast.app"; _g_launch_run "$RP"
t "G8.14" "tinycast with Raycast.app present: one warning with the exact removal command" \
  '[ "$(grep -c "brew uninstall --cask raycast" "$RP/out")" -eq 1 ]'
t "G8.15" "the warning is only a warning: Raycast is never uninstalled and Tinycast is still set up" \
  '[ "$(_logcount "$RP" "uninstall")" -eq 0 ] && _logged "$RP" "defaults write com.tinycast.app hotkey.togglePalette -string $HK"'
t "G8.16" "tinycast without Raycast.app: no Raycast warning" \
  '! grep -q "brew uninstall --cask raycast" "$TC/out"'

PM=$(_g_env); printf "DOTFILES_LAUNCHER=raycast\n" >"$PM/df/macos/local.sh"; printf "DOTFILES_LAUNCHER=tinycast\n" >"$PM/df/macos/machine.local.sh"; _g_launch_run "$PM"
t "G8.17" "macos/machine.local.sh beats macos/local.sh (sourcing local.sh must not hide it)" \
  '_logged "$PM" "defaults write com.tinycast.app hotkey.togglePalette -string $HK"'
PL=$(_g_env); printf "DOTFILES_LAUNCHER=raycast\n" >"$PL/df/macos/local.sh"; _g_launch_run "$PL"
t "G8.18" "a launcher set only in macos/local.sh is honoured" \
  '[ "$(_logcount "$PL" "com.tinycast.app")" -eq 0 ]'
t "G8.19" "the environment beats both files" '
  W=$(_g_env); printf "DOTFILES_LAUNCHER=tinycast\n" >"$W/df/macos/machine.local.sh"; _g_launch_run "$W" DOTFILES_LAUNCHER=raycast
  [ "$(_logcount "$W" "com.tinycast.app")" -eq 0 ]'

ALR=$(_g_env); printf '%s' "$HK" >"$ALR/hk"; printf true >"$ALR/sfe"; : >"$ALR/running"; _g_run "$ALR" defaults.sh
t "G8.20" "hotkey and settings switch already right: a running Tinycast is left running and nothing is written" \
  '[ "$(_logcount "$ALR" "quit app")" -eq 0 ] && [ "$(_logcount "$ALR" "defaults write com.tinycast.app")" -eq 0 ] && [ -e "$ALR/running" ]'
t "G8.21" "already right: the run says so and reports no error" \
  'grep -qi "already set" "$ALR/out" && ! grep -q "hotkey read back" "$ALR/out"'
SFO=$(_g_env); printf '%s' "$HK" >"$SFO/hk"; _g_run "$SFO" defaults.sh
t "G8.22" "hotkey right but the settings switch off: both are written again" \
  '_logged "$SFO" "defaults write com.tinycast.app settingsFileEnabled -bool true"'
t "G8.23" "a running Tinycast that must be quit is announced first" '
  grep -qi "quitting tinycast" "$RUN/out"'
t "G8.24" "a Tinycast that is not running is not announced as quit" \
  '! grep -qi "quitting tinycast" "$TC/out"'

SFM=$(_g_env); _g_run "$SFM" defaults.sh SFE_FORCE=false
t "G8.25" "a settings switch that reads back off is reported, not ignored" \
  'grep -q "settingsFileEnabled read back" "$SFM/out"'
t "G8.26" "a settings switch that reads back on is not reported" \
  '! grep -q "settingsFileEnabled read back" "$TC/out"'
section "K -- Task 13: baseline changed (defaults that moved since the snapshot)"
#############################################################################
# kenv: a DOTFILES_DIR declaring three keys, a snapshot "t" and a stub
# `defaults` that reads live values from $W/live (domain<TAB>key<TAB>value).
kenv() {
  local w
  w=$(sandbox); mkdir -p "$w/macos" "$w/bin" "$w/snap"
  printf 'defaults write com.example.a Alpha -bool true\ndefaults write com.example.a Beta -int 5\ndefaults write com.example.b Gone -bool true\ndefaults write com.example.b Same -string x\n' >"$w/macos/defaults-x.sh"
  printf 'com.example.a\tAlpha\t1\ncom.example.a\tBeta\t5\ncom.example.b\tGone\t1\ncom.example.b\tSame\tx\n' >"$w/snap/t.tsv"
  printf '#!/bin/sh\n[ "$1" = read ] || exit 1\nawk -F"\\t" -v d="$2" -v k="$3" '"'"'$1 == d && $2 == k { print $3; f = 1 } END { exit !f }'"'"' "$LIVE"\n' >"$w/bin/defaults"
  chmod +x "$w/bin/defaults"
  printf 'com.example.a\tAlpha\t0\ncom.example.a\tBeta\t5\ncom.example.b\tSame\tx\n' >"$w/live"
  printf '%s' "$w"
}
kchanged() { PATH="$W/bin:$PATH" LIVE="$W/live" DOTFILES_DIR="$W" DOTFILES_BASELINE_DIR="$W/snap" bash bin/dotfiles-baseline changed "$@"; }

t "K1" "changed prints domain, key, old and new for a key whose live value differs from the snapshot, and nothing for the rest" '
  W=$(kenv); out=$(kchanged t 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "$(printf "com.example.a\tAlpha\t1\t0")" ]'
t "K2" "a key the OS no longer honours is BROKE territory, not a change" '
  W=$(kenv); out=$(kchanged t 2>/dev/null); [ "$(printf "%s\n" "$out" | grep -c "Gone")" -eq 0 ]'
t "K3" "no snapshot for the label: exit 0, nothing on stdout, a note on stderr" '
  W=$(kenv); out=$(kchanged nosuch 2>/dev/null); rc=$?; err=$(kchanged nosuch 2>&1 >/dev/null)
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(printf "%s\n" "$err" | grep -c "no baseline")" -eq 1 ]'
t "K4" "changed only reads: the stub defaults saw no write" '
  W=$(kenv); printf "#!/bin/sh\necho \"\$*\" >>\"%s/calls\"\nexec \"%s/defaults.real\" \"\$@\"\n" "$W" "$W/bin" >"$W/wrap"
  command mv "$W/bin/defaults" "$W/bin/defaults.real"; command cp "$W/wrap" "$W/bin/defaults"; chmod +x "$W/bin/defaults"
  kchanged t >/dev/null 2>&1; [ "$(grep -vc "^read " "$W/calls")" -eq 0 ] && [ "$(grep -c "^read " "$W/calls")" -ge 1 ]'

#############################################################################
section "G9 -- Remote Login read-back works without Full Disk Access"
#############################################################################
# Without Full Disk Access `systemsetup -getremotelogin` says Off while sshd is
# really running. launchd's disabled list or port 22 tell the truth.
t "G9.1" "systemsetup blind, launchd says sshd is enabled: no error, no failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" RL_TAKES= RL_LAUNCHD=1)" -eq 0 ] && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 0 ]'
t "G9.2" "systemsetup blind, sshd listening on port 22: no error, no failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" RL_TAKES= RL_PORT=1)" -eq 0 ] && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 0 ]'
t "G9.3" "really off (systemsetup, launchd and port 22 all say off): one failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" RL_TAKES=)" -eq 1 ] && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 1 ]'
t "G9.4" "the Remote Login failure says exactly what to do" \
  'W=$(_ra_env) && _ra_run "$W" RL_TAKES= && grep -qE "error.*Remote Login.*System Settings.*Sharing" "$W/out"'
t "G9.5" "launchd is asked through sudo about the system domain" \
  'W=$(_ra_env) && _ra_run "$W" RL_TAKES= && _logged "$W" "sudo launchctl print-disabled system"'

#############################################################################
section "G10 -- the Tinycast block says what happened when the app is absent"
#############################################################################
t "G10.1" "Tinycast.app absent: an info line naming the exact commands, no error" '
  W=$(_g_env); rmdir "$W/Tinycast.app"; _g_run "$W" defaults.sh FW_TAKES=1 RL_TAKES=1
  grep -qF "Tinycast is not installed yet; run \`dotfiles configure --defaults\` after \`dotfiles install --packages\`" "$W/out" &&
  [ "$(grep -c "error.*Tinycast" "$W/out")" -eq 0 ]'
t "G10.2" "Tinycast.app absent: nothing is written and the tally stays zero" '
  W=$(_g_env); rmdir "$W/Tinycast.app"
  [ "$(_tally "$W" FW_TAKES=1 RL_TAKES=1)" -eq 0 ] && [ "$(_logcount "$W" "com.tinycast.app")" -eq 0 ]'
t "G10.3" "Tinycast.app present and not running: written, read back, no info line" '
  W=$(_g_env); _g_run "$W" defaults.sh
  _logged "$W" "defaults write com.tinycast.app hotkey.togglePalette -string $HK" &&
  [ "$(sed -n "/defaults write com.tinycast.app hotkey.togglePalette/,\$p" "$W/log" | grep -c "defaults export")" -ge 1 ] &&
  [ "$(grep -c "not installed yet" "$W/out")" -eq 0 ]'
t "G10.4" "launcher=raycast: no Tinycast info line" '
  W=$(_g_env); rmdir "$W/Tinycast.app"; _g_run "$W" defaults.sh DOTFILES_LAUNCHER=raycast; [ "$(grep -c "Tinycast is not installed" "$W/out")" -eq 0 ]'

#############################################################################
section "G11 -- dock.sh survives the Dock relaunching over its edits"
#############################################################################
# A virtual clock ticks on every stub call. The Dock is "down" until the clock
# reaches down_until; when it comes back it writes its OLD state over whatever
# dockutil did meanwhile (the revert marker). `killall Dock` takes it down again
# and, DOCK_LOSE_KILLS times, makes that relaunch revert as well.
_d_env() {
  local W n tick
  W=$(sandbox) || return 1
  mkdir -p "$W/bin" "$W/root/Applications" "$W/root/System/Applications" "$W/home/Downloads"
  : >"$W/log"; printf 0 >"$W/clock"; printf 3 >"$W/down_until"; : >"$W/revert"
  printf 'Safari\nMail\n' >"$W/old"; cp "$W/old" "$W/state"
  for n in "Brave Browser" "Google Chrome" Slack Figma WebStorm Warp; do mkdir -p "$W/root/Applications/$n.app"; done
  for n in Apps Calendar Notes "System Settings"; do mkdir -p "$W/root/System/Applications/$n.app"; done
  tick='
c=$(($(cat "$W_STATE/clock") + 1)); printf %s "$c" >"$W_STATE/clock"
if [ -e "$W_STATE/down_until" ] && [ "$c" -ge "$(cat "$W_STATE/down_until")" ] && [ -z "${DOCK_NEVER:-}" ]; then
  rm -f "$W_STATE/down_until"
  if [ -e "$W_STATE/revert" ]; then rm -f "$W_STATE/revert"; cp "$W_STATE/old" "$W_STATE/state"; fi
fi'
  _stub "$W/bin" sleep "$tick"
  _stub "$W/bin" pgrep "$tick"'
[ ! -e "$W_STATE/down_until" ]'
  _stub "$W/bin" killall "$tick"'
if [ "$1" = Dock ]; then
  printf "%s" "$(($(cat "$W_STATE/clock") + 3))" >"$W_STATE/down_until"
  n=$(cat "$W_STATE/kills" 2>/dev/null || echo "${DOCK_LOSE_KILLS:-0}")
  if [ "$n" -gt 0 ]; then : >"$W_STATE/revert"; printf %s "$((n - 1))" >"$W_STATE/kills"; fi
fi'
  _stub "$W/bin" dockutil "$tick"'
[ -z "${DOCK_REMOVE_FAIL:-}" ] || case "$*" in *"--remove"*) exit 1 ;; esac
case "$1" in
  --list) while IFS= read -r l; do printf "%s\tfile:///x/%s.app/\tpersistent-apps\n" "$l" "$l"; done <"$W_STATE/state" ;;
  *)
    while [ $# -gt 0 ]; do
      case "$1" in
        --remove) : >"$W_STATE/state"; break ;;
        --add) b=$(basename "$2" .app); grep -qxF "$b" "$W_STATE/state" || printf "%s\n" "$b" >>"$W_STATE/state"; break ;;
      esac
      shift
    done ;;
esac
exit 0'
  printf '%s' "$W"
}
# _d_run <W> [VAR=val ...] -- source the real dock.sh, then print FAILED=<n>.
_d_run() {
  local W=$1
  shift
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$ROOT_DIR" STUB_LOG="$W/log" W_STATE="$W" \
    DOTFILES_DOCK_ROOT="$W/root" DOTFILES_DOCK_SETTLE_TIMEOUT=10 "$@" \
    /bin/bash -c '. "$DOTFILES_DIR/macos/dock.sh"; echo "FAILED=${DOTFILES_DOCK_FAILED:-0}"' >"$W/out" 2>&1
}
_d_has() { grep -qxF "$2" "$1/state"; }
_d_failed() { sed -n 's/^FAILED=//p' "$1/out"; }

#############################################################################
section "G12 -- what the real macOS 27 tools do: wording, refusals, removed flags"
#############################################################################
OK_ENV="FW_TAKES=1 RL_TAKES=1"
t "G12.1" "macOS 27 stealth wording (Firewall stealth mode is on) is on, not an error" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV FW_NEWWORD=1)" -eq 0 ] && [ "$(grep -c "stealth mode is still off" "$W/out")" -eq 0 ]'
t "G12.2" "macOS 27 stealth wording off (Firewall stealth mode is off) is still an error" '
  W=$(_g_env) && _g_run "$W" defaults.sh RL_TAKES=1 FW_NEWWORD=1 && [ "$(grep -c "stealth mode is still off" "$W/out")" -ge 1 ]'
t "G12.3" "Remote Login already on: the setter is never called" '
  W=$(_ra_env) && _ra_run "$W" RL_TAKES= RL_LAUNCHD=1 && [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ] && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 0 ]'
t "G12.4" "Remote Login off and the setter works: setter called once, no error" '
  W=$(_ra_env) && [ "$(_ra_tally "$W")" -eq 0 ] && [ "$(grep -cxF "systemsetup -setremotelogin -f on" "$W/log")" -eq 1 ]'
t "G12.5" "Remote Login off and the setter fails: one failure with the Sharing instruction" '
  W=$(_ra_env) && [ "$(_ra_tally "$W" RL_TAKES= SYSTEMSETUP_RC=1)" -eq 1 ] && grep -qE "error.*Remote Login.*Sharing" "$W/out"'
t "G12.6" "the Tinycast hotkey is written typed, so the real defaults does not refuse it" '
  W=$(_g_env) && _g_run "$W" defaults.sh && [ "$(grep -c "Could not parse" "$W/out")" -eq 0 ] && [ "$(grep -c "error.*Tinycast" "$W/out")" -eq 0 ]'
t "G12.7" "the untyped write is refused by the stub exactly as the real tool does (harness check)" '
  W=$(_g_env); ! PATH="$W/bin:$PATH" STUB_LOG="$W/log" HK_STATE="$W/hk" defaults write com.tinycast.app hotkey.togglePalette "{\"a\":1}"'
t "G12.8" "lsregister is never called with -kill, and garbage-collects instead" '
  W=$(_g_env) && _g_run "$W" defaults.sh && [ "$(_logcount "$W" "lsregister -kill")" -eq 0 ] && [ "$(_logcount "$W" "lsregister -gc")" -eq 1 ] && [ "$(grep -c "# The -kill option" "$W/out")" -eq 0 ]'
t "G12.9" "a failing lsregister is a warning naming the command, not an error and not a failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV LSR_FAIL=1)" -eq 0 ] && grep -q "warning.*lsregister" "$W/out" && [ "$(grep -c "error.*lsregister" "$W/out")" -eq 0 ]'
t "G12.10" "indexing already on: mdutil -i on is not called" '
  W=$(_g_env) && _g_run "$W" defaults.sh && [ "$(_logcount "$W" "mdutil -i on")" -eq 0 ] && _logged "$W" "mdutil -s /"'
t "G12.11" "indexing off: mdutil -i on / runs" '
  W=$(_g_env) && _g_run "$W" defaults.sh MDUTIL_OFF=1 && _logged "$W" "sudo mdutil -i on /"'
t "G12.12" "indexing off and mdutil fails: a warning with the error text and the manual command, not a failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV MDUTIL_OFF=1 MDUTIL_FAIL=1)" -eq 0 ] &&
  grep "warning" "$W/out" | grep -q "unable to perform operation" && grep "warning" "$W/out" | grep -qF "sudo mdutil -i on /"'
t "G12.13" "print_result with no message names the step that failed (never a bare [error])" '
  W=$(_g_env); G_TAIL="running \"Step Alpha\"; print_result 3" _g_run "$W" defaults.sh; grep -q "error.*Step Alpha failed" "$W/out"'
t "G12.14" "no bare [error] line in a run where everything fails" '
  W=$(_g_env); _g_run "$W" defaults.sh MDUTIL_OFF=1 MDUTIL_FAIL=1 LSR_FAIL=1 SYSTEMSETUP_RC=1; [ "$(grep "error" "$W/out" | grep -cE "error[^a-z]*\]?[[:space:]]*\$")" -eq 0 ]'

#############################################################################
section "G13 -- macOS 26+ appearance: dark icons and Clear Liquid Glass"
#############################################################################
t "G13.1" "macOS 27: dark icons and NSGlassTintAmount 0; never NSGlassDiffusionSetting" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV SW_VERS=27.0.1)" -eq 0 ] &&
  _logged "$W" "defaults write -g AppleIconAppearanceTheme -string RegularDark" &&
  _logged "$W" "defaults write -g NSGlassTintAmount -float 0" && [ "$(_logcount "$W" "NSGlassDiffusionSetting")" -eq 0 ]'
t "G13.2" "macOS 26.6.1: NSGlassDiffusionSetting 0; never NSGlassTintAmount" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV SW_VERS=26.6.1)" -eq 0 ] &&
  _logged "$W" "defaults write -g AppleIconAppearanceTheme -string RegularDark" &&
  _logged "$W" "defaults write -g NSGlassDiffusionSetting -int 0" && [ "$(_logcount "$W" "NSGlassTintAmount")" -eq 0 ]'
t "G13.3" "macOS 15: no icon or glass keys" '
  W=$(_g_env) && _g_run "$W" defaults.sh SW_VERS=15.6.1 && [ "$(_logcount "$W" "AppleIconAppearanceTheme")" -eq 0 ] &&
  [ "$(_logcount "$W" "NSGlass")" -eq 0 ] && _logged "$W" "defaults write NSGlobalDomain AppleInterfaceStyle -string Dark"'
t "G13.4" "DOTFILES_GLASS=tinted: 0.86 on 27, 1 on 26" '
  W=$(_g_env); X=$(_g_env); _g_run "$W" defaults.sh SW_VERS=27.0.1 DOTFILES_GLASS=tinted; _g_run "$X" defaults.sh SW_VERS=26.6.1 DOTFILES_GLASS=tinted
  _logged "$W" "defaults write -g NSGlassTintAmount -float 0.86" && _logged "$X" "defaults write -g NSGlassDiffusionSetting -int 1"'
t "G13.5" "DOTFILES_ICON_STYLE overrides the icon style" '
  W=$(_g_env) && _g_run "$W" defaults.sh DOTFILES_ICON_STYLE=TintedDark && _logged "$W" "defaults write -g AppleIconAppearanceTheme -string TintedDark"'
t "G13.6" "a value that reads back wrong is a counted failure naming the key" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV SW_VERS=27.0.1 G_WRONG=1)" -ge 2 ] && grep -qE "error.*NSGlassTintAmount.*expected" "$W/out"'
t "G13.7" "a value that cannot be read back at all is a counted failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV SW_VERS=26.6.1 G_ABSENT=1)" -ge 2 ]'
t "G13.8" "an unknown DOTFILES_GLASS warns and writes no glass key" '
  W=$(_g_env) && _g_run "$W" defaults.sh DOTFILES_GLASS=frosted && grep -q "warning.*DOTFILES_GLASS" "$W/out" && [ "$(_logcount "$W" "NSGlass")" -eq 0 ]'
t "G13.9" "reduceTransparency is never written at runtime" '
  W=$(_g_env) && _g_run "$W" defaults.sh && [ "$(_logcount "$W" "reduceTransparency -bool true")" -eq 0 ]'
t "G13.10" "local.sh.example documents both variables" \
  'grep -q DOTFILES_ICON_STYLE macos/local.sh.example && grep -q DOTFILES_GLASS macos/local.sh.example'

t "G11.1" "a Dock that relaunches over the first edits still ends with every installed app" '
  W=$(_d_env); _d_run "$W"
  for a in Apps "Brave Browser" "Google Chrome" Slack Calendar Notes Figma WebStorm Warp "System Settings"; do
    _d_has "$W" "$a" || exit 1
  done; [ "$(_d_failed "$W")" = 0 ]'
t "G11.2" "an app that is not installed is a quiet skipped line with the exact follow-up command" '
  W=$(_d_env); _d_run "$W"
  grep -qF "skipped" "$W/out" && grep -qF "not installed yet" "$W/out" && grep -q "Spark Mail" "$W/out" && grep -qF "dotfiles configure --dock" "$W/out"'
t "G11.3" "a missing app is never a warning or an error, and never a failure" '
  W=$(_d_env); _d_run "$W"; [ "$(grep -c "warning\|error" "$W/out")" -eq 0 ] && [ "$(_d_failed "$W")" = 0 ]'
t "G11.4" "the final restart losing the edits once: the Dock is rebuilt and ends right" '
  W=$(_d_env); _d_run "$W" DOCK_LOSE_KILLS=1
  _d_has "$W" Slack && _d_has "$W" Warp && [ "$(_d_failed "$W")" = 0 ] &&
  [ "$(grep -c "^dockutil --no-restart --remove all" "$W/log")" -eq 2 ]'
t "G11.5" "a Dock that keeps losing the edits: an error naming the missing entries, and a failure" '
  W=$(_d_env); _d_run "$W" DOCK_LOSE_KILLS=9
  [ "$(grep "error" "$W/out" | grep -c Slack)" -ge 1 ] && [ "$(_d_failed "$W")" = 1 ]'
t "G11.6" "a Dock that never comes back: the wait is bounded, the run ends, and it says the Dock did not settle" '
  W=$(_d_env); _d_run "$W" DOCK_NEVER=1 DOTFILES_DOCK_SETTLE_TIMEOUT=3; [ -n "$(_d_failed "$W")" ] && [ "$(_logcount "$W" "sleep 1")" -le 12 ] && grep -q "did not settle" "$W/out"'
t "G11.7" "the Dock process is waited for before the first edit" '
  W=$(_d_env); _d_run "$W"; a=$(_first_line "pgrep -x Dock" "$W/log"); b=$(_first_line "dockutil --no-restart --remove all" "$W/log"); [ "$a" -gt 0 ] && [ "$a" -lt "$b" ]'

#############################################################################
section "G14 -- review round: undo reduceTransparency, Tinycast is a warning, validation"
#############################################################################
t "G14.1" "reduceTransparency set to 1 by an older configure: reset to false" '
  W=$(_g_env) && _g_run "$W" defaults.sh RT_INIT=1 && _logged "$W" "defaults write com.apple.universalaccess reduceTransparency -bool false" &&
  [ "$(grep -c "warning.*Reduce transparency" "$W/out")" -eq 0 ]'
t "G14.2" "reduceTransparency already 0: not written" '
  W=$(_g_env) && _g_run "$W" defaults.sh RT_INIT=0 && [ "$(_logcount "$W" "write com.apple.universalaccess reduceTransparency")" -eq 0 ]'
t "G14.3" "reduceTransparency absent: not written" '
  W=$(_g_env) && _g_run "$W" defaults.sh && [ "$(_logcount "$W" "write com.apple.universalaccess reduceTransparency")" -eq 0 ]'
t "G14.4" "a reset that does not stick warns with the System Settings step and is not a counted failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV RT_INIT=1 RT_STUCK=1)" -eq 0 ] &&
  grep "warning" "$W/out" | grep -q "Accessibility.*Display.*Reduce transparency"'
t "G14.5" "a Tinycast hotkey read-back mismatch is a warning with the GUI fallback, not a counted failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV HK_FORCE=bogus)" -eq 0 ] && grep "warning" "$W/out" | grep -q "Tinycast > Settings > General" &&
  [ "$(grep -c "error.*Tinycast" "$W/out")" -eq 0 ]'
t "G14.6" "a Tinycast hotkey write failure is a warning, not a counted failure" '
  W=$(_g_env) && [ "$(_tally "$W" $OK_ENV HK_WRITEFAIL=1)" -eq 0 ] && grep "warning" "$W/out" | grep -q "Tinycast" && [ "$(grep -c "error.*Tinycast" "$W/out")" -eq 0 ]'
t "G14.7" "an invalid DOTFILES_ICON_STYLE warns and falls back to RegularDark" '
  W=$(_g_env) && _g_run "$W" defaults.sh DOTFILES_ICON_STYLE=Bogus && grep -q "warning.*DOTFILES_ICON_STYLE" "$W/out" &&
  _logged "$W" "defaults write -g AppleIconAppearanceTheme -string RegularDark"'
t "G14.8" "all nine icon styles are accepted" '
  for a in Regular Clear Tinted; do for b in Automatic Light Dark; do
    W=$(_g_env); _g_run "$W" defaults.sh DOTFILES_ICON_STYLE=$a$b; _logged "$W" "defaults write -g AppleIconAppearanceTheme -string $a$b" || exit 1
  done; done'
t "G14.9" "a failed dockutil --remove all is a Dock failure" '
  W=$(_d_env); _d_run "$W" DOCK_REMOVE_FAIL=1; [ "$(_d_failed "$W")" = 1 ] && grep -q "error.*clear the Dock" "$W/out"'
t "G14.10" "an empty but stable Dock list settles at once, without burning the timeout" '
  W=$(_d_env); : >"$W/old"; : >"$W/state"; _d_run "$W"; [ "$(grep -c "did not settle" "$W/out")" -eq 0 ]'

#############################################################################
section "G15 -- real-run fixes: tty-safe keep-alive, FDA probe, screen lock, per-Mac file"
#############################################################################
t "G15.1" "no background keep-alive runs a command under sudo (sudo -n true leaves the tty raw)" '
  [ "$(code_of macos/defaults.sh bin/dotfiles scripts/lib/clt.sh | grep -cE "sudo -n true|sudo .*[[:space:]]true([[:space:]]|\$)")" -eq 0 ]'
t "G15.2" "the keep-alives only refresh the ticket: sudo -n -v with stdin, stdout and stderr redirected" '
  [ "$(code_of macos/defaults.sh bin/dotfiles scripts/lib/clt.sh | grep -c "sudo -n -v </dev/null >/dev/null 2>&1")" -eq 3 ]'
t "G15.3" "the keep-alive in a real pty leaves onlcr on (runs without a password: no ticket just fails)" '
  command -v script >/dev/null || exit 0
  o=$(script -q /dev/null /bin/bash -c "sudo -n -v </dev/null >/dev/null 2>&1; stty -a" </dev/null 2>&1 | grep -c "[^-]onlcr")
  [ "$o" -ge 1 ]'

FDA=$(_g_env); mkdir -p "$FDA/tcc"
t "G15.4" "Full Disk Access present (probe succeeds): no Full Disk Access warning" '
  _g_run "$FDA" defaults.sh FW_TAKES=1 RL_TAKES=1 DOTFILES_FDA_PROBE="$FDA/tcc"; [ "$(grep -c "warning.*Full Disk Access" "$FDA/out")" -eq 0 ]'
t "G15.5" "Full Disk Access absent (probe fails): the warning is printed" '
  W=$(_g_env); _g_run "$W" defaults.sh DOTFILES_FDA_PROBE="$W/nope"; [ "$(grep -c "warning.*Full Disk Access" "$W/out")" -ge 1 ]'
t "G15.6" "the probe reads a TCC directory, not through sudo" \
  '[ "$(code_of macos/defaults.sh | grep -c "com.apple.TCC")" -ge 1 ] && [ "$(code_of macos/defaults.sh | grep -c "sudo .*com.apple.TCC")" -eq 0 ]'
t "G15.6b" "the warning says this terminal does not appear to have Full Disk Access" '
  W=$(_g_env); _g_run "$W" defaults.sh DOTFILES_FDA_PROBE="$W/nope"; grep -q "this terminal does not appear to have Full Disk Access" "$W/out"'

if command -v script >/dev/null 2>&1; then
  t "G15.7" "on a terminal, the DOTFILES_YES that configure sets for itself does not stop the screen lock" '
    W=$(_g_env) && _g_run_tty "$W" DOTFILES_YES=1 DOTFILES_YES_INTERNAL=1 && _logged "$W" "sysadminctl -screenLock immediate -password -"'
fi
t "G15.8" "sub_configure marks its own DOTFILES_YES as internal, only when the owner had not set one" '
  b=$(sed -n "/^sub_configure() {/,/^}/p" bin/dotfiles)
  printf "%s\n" "$b" | grep -q "DOTFILES_YES_INTERNAL" && printf "%s\n" "$b" | grep -q "unset DOTFILES_YES_INTERNAL"'

t "G15.9" "macos/machine.local.sh is sourced: a per-Mac computer name reaches scutil" '
  W=$(_g_env); printf "DOTFILES_COMPUTER_NAME=per-mac\n" >"$W/df/macos/machine.local.sh"; _g_run "$W" defaults.sh
  _logged "$W" "scutil --set ComputerName per-mac"'
t "G15.10" "machine.local.sh wins over local.sh for the computer name" '
  W=$(_g_env); printf "DOTFILES_COMPUTER_NAME=shared\n" >"$W/df/macos/local.sh"; printf "DOTFILES_COMPUTER_NAME=per-mac\n" >"$W/df/macos/machine.local.sh"; _g_run "$W" defaults.sh
  _logged "$W" "scutil --set ComputerName per-mac" && [ "$(_logcount "$W" "ComputerName shared")" -eq 0 ]'
t "G15.11" "the unset-name skip line mentions machine.local.sh" '
  W=$(_g_env); _g_run "$W" defaults.sh; grep "computer name" "$W/out" | grep -q "machine.local.sh"'
t "G15.12" "machine.local.sh.example documents DOTFILES_COMPUTER_NAME" \
  'grep -q DOTFILES_COMPUTER_NAME macos/machine.local.sh.example'
t "G15.13" "a launcher in machine.local.sh still behaves (raycast: Tinycast untouched)" '
  W=$(_g_env); printf "DOTFILES_LAUNCHER=raycast\n" >"$W/df/macos/machine.local.sh"; _g_run "$W" defaults.sh; [ "$(_logcount "$W" "com.tinycast.app")" -eq 0 ]'
t "G15.14" "the environment launcher still beats machine.local.sh" '
  W=$(_g_env); printf "DOTFILES_LAUNCHER=raycast\n" >"$W/df/macos/machine.local.sh"; _g_run "$W" defaults.sh DOTFILES_LAUNCHER=tinycast; [ "$(_logcount "$W" "com.tinycast.app")" -ge 1 ]'

#############################################################################
section "G16 -- Ghostty and cmux share one terminal config"
#############################################################################
# cmux renders with libghostty and reads ~/.config/ghostty/config too, so the
# one stowed file sets the terminal for both apps.
t "G16.1" "the Ghostty config sets SSH terminfo, left Option as Alt and a quick terminal" \
  'f=config/ghostty/config && grep -q "^shell-integration-features = .*ssh-terminfo" "$f" &&
   grep -q "^macos-option-as-alt = left$" "$f" && grep -q "^keybind = global:.*=toggle_quick_terminal$" "$f"'
# The look follows Warp's (apps/warp/settings.toml): Nord always, a blinking bar
# cursor, Hack (Warp's font), and padding around the text.
t "G16.5" "the Ghostty config matches Warp's look: Nord, a blinking bar cursor, Hack, padding" \
  'f=config/ghostty/config && grep -q "^theme = Nord$" "$f" &&
   grep -q "^cursor-style = bar$" "$f" && grep -q "^cursor-style-blink = true$" "$f" &&
   grep -q "^font-family = Hack Nerd Font Mono$" "$f" && grep -q "^window-padding-x = " "$f"'
# Ghostty's CLI lives inside the app bundle; the check skips where it is not installed (CI).
t "G16.2" "the Ghostty config passes ghostty +validate-config where Ghostty is installed" \
  'g=$(command -v ghostty || echo /Applications/Ghostty.app/Contents/MacOS/ghostty)
   [ ! -x "$g" ] || "$g" +validate-config --config-file="$ROOT_DIR/config/ghostty/config" </dev/null >/dev/null 2>&1'
t "G16.3" "config/ghostty stows into a sandbox ~/.config/ghostty" \
  '! command -v stow >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/xdg" "$W/repo" &&
     (cd "$ROOT_DIR" && git ls-files --cached --others --exclude-standard config/ghostty | while IFS= read -r f; do
        mkdir -p "$W/repo/$(dirname "$f")" && cp "$f" "$W/repo/$f" || exit 1
      done) &&
     stow -d "$W/repo" -t "$W/xdg" config >/dev/null 2>&1 && [ -f "$W/xdg/ghostty/config" ]
   }'
t "G16.4" "dotfiles doctor checks that ~/.config/ghostty is linked" \
  'grep -qE "config_dirs=\(.*\"ghostty\"" bin/dotfiles-doctor'

#############################################################################
section "R1 -- dotfiles_remote_access: per-Mac, never from the shared local.sh"
#############################################################################
# _ra_fn <dir> [VAR=val ...] -- what dotfiles_remote_access prints (stdout).
_ra_fn() {
  local d=$1
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_remote_access "$2"' _ "$ROOT_DIR" "$d" 2>/dev/null
}
# Stderr only (2>&1 before >/dev/null swaps the streams on purpose).
# shellcheck disable=SC2069
_ra_fn_err() {
  local d=$1
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_remote_access "$2"' _ "$ROOT_DIR" "$d" 2>&1 >/dev/null
}
_ra_dir() { local d; d=$(sandbox) && mkdir -p "$d/macos" && printf '%s' "$d"; }

t "R1.1" "a desktop defaults to on" \
  'D=$(_ra_dir) && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop)" = on ]'
t "R1.2" "a laptop defaults to off" \
  'D=$(_ra_dir) && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=laptop)" = off ]'
t "R1.3" "DOTFILES_REMOTE_ACCESS from the environment beats the role, both ways" \
  'D=$(_ra_dir) && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=laptop DOTFILES_REMOTE_ACCESS=on)" = on ] &&
   [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop DOTFILES_REMOTE_ACCESS=off)" = off ]'
t "R1.4" "macos/machine.local.sh beats the role, both ways" \
  'D=$(_ra_dir) && echo "DOTFILES_REMOTE_ACCESS=on" >"$D/macos/machine.local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=laptop)" = on ] &&
   echo "DOTFILES_REMOTE_ACCESS=off" >"$D/macos/machine.local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop)" = off ]'
t "R1.5" "the environment beats machine.local.sh" \
  'D=$(_ra_dir) && echo "DOTFILES_REMOTE_ACCESS=off" >"$D/macos/machine.local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop DOTFILES_REMOTE_ACCESS=on)" = on ]'
t "R1.6" "macos/local.sh (shared between Macs) is NOT read" \
  'D=$(_ra_dir) && echo "DOTFILES_REMOTE_ACCESS=off" >"$D/macos/local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop)" = on ] &&
   echo "DOTFILES_REMOTE_ACCESS=on" >"$D/macos/local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=laptop)" = off ]'
t "R1.7" "a bad value warns once and falls back to the role default" \
  'D=$(_ra_dir) && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=laptop DOTFILES_REMOTE_ACCESS=maybe)" = off ] &&
   [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop DOTFILES_REMOTE_ACCESS=maybe)" = on ] &&
   [ "$(_ra_fn_err "$D" DOTFILES_MACHINE_ROLE=desktop DOTFILES_REMOTE_ACCESS=maybe | grep -c "warning.*DOTFILES_REMOTE_ACCESS=maybe")" -eq 1 ]'
t "R1.8" "a bad value in machine.local.sh warns and falls back too" \
  'D=$(_ra_dir) && echo "DOTFILES_REMOTE_ACCESS=sure" >"$D/macos/machine.local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop)" = on ] &&
   [ "$(_ra_fn_err "$D" DOTFILES_MACHINE_ROLE=desktop | grep -c "warning")" -eq 1 ]'
t "R1.9" "a machine.local.sh with a syntax error warns and is ignored" \
  'D=$(_ra_dir) && echo "if then (" >"$D/macos/machine.local.sh" && [ "$(_ra_fn "$D" DOTFILES_MACHINE_ROLE=desktop)" = on ] &&
   [ "$(_ra_fn_err "$D" DOTFILES_MACHINE_ROLE=desktop | grep -c "warning")" -eq 1 ]'
t "R1.10" "nothing the file sets leaks into the caller" \
  'D=$(_ra_dir) && printf "DOTFILES_REMOTE_ACCESS=on\nLEAK=yes\n" >"$D/macos/machine.local.sh" &&
   [ "$(env -i PATH=/usr/bin:/bin DOTFILES_MACHINE_ROLE=laptop bash -c ". \"$ROOT_DIR/scripts/lib/machine.sh\"; dotfiles_remote_access \"$D\" >/dev/null; echo \"\${LEAK:-none}\${DOTFILES_REMOTE_ACCESS:-none}\"")" = nonenone ]'
t "R1.11" "machine.local.sh.example documents it, commented out" \
  '[ "$(grep -c "^# DOTFILES_REMOTE_ACCESS=" macos/machine.local.sh.example)" -eq 1 ] && [ "$(grep -c "^DOTFILES_REMOTE_ACCESS=" macos/machine.local.sh.example)" -eq 0 ]'

#############################################################################
section "R2 -- remote access: off changes nothing"
#############################################################################
ROFF=$(_ra_env); _ra_run "$ROFF" DOTFILES_REMOTE_ACCESS=off
t "R2.1" "off: one skip line, and not a single sudo call or system change" '
  [ "$(grep -c "skipped" "$ROFF/out")" -eq 1 ] && [ "$(grep -c "^sudo " "$ROFF/log")" -eq 0 ] &&
  [ "$(grep -c "" "$ROFF/log")" -eq 0 ] && [ -z "$(ls -A "$ROFF/etc/ssh/sshd_config.d")$(ls -A "$ROFF/etc/pf.anchors")$(ls -A "$ROFF/Library/LaunchDaemons")" ]'
t "R2.2" "off: no error and a zero failure tally" \
  '[ "$(grep -c "error" "$ROFF/out")" -eq 0 ] && [ "$(_ra_tally "$ROFF" DOTFILES_REMOTE_ACCESS=off)" -eq 0 ]'
t "R2.3" "a laptop with no setting is off: nothing changes" \
  '[ "$(grep -c "" "$LAPR/log")" -eq 0 ] && [ "$(grep -c "skipped" "$LAPR/out")" -eq 1 ]'
t "R2.4" "a desktop with no setting is on" \
  '_logged "$DSKR" "systemsetup -setremotelogin -f on"'
t "R2.5" "machine.local.sh turns it on for a laptop" '
  W=$(_ra_env) && echo "DOTFILES_REMOTE_ACCESS=on" >"$W/df/macos/machine.local.sh" &&
  _g_run "$W" defaults-remote-access.sh DOTFILES_MACHINE_ROLE=laptop FW_TAKES=1 RL_TAKES=1 SS_PORT=1 && _logged "$W" "systemsetup -setremotelogin -f on"'
t "R2.6" "the code never switches anything off (Remote Login, firewall, stealth, group members)" '
  [ "$(code_of macos/defaults-remote-access.sh | grep -cE -- "-setremotelogin.* off|--set[a-z]+ off|dseditgroup.* -d |launchctl (disable|unload)")" -eq 0 ]'

#############################################################################
section "R3 -- remote access: the steps"
#############################################################################
RON=$(_ra_env); _ra_run "$RON"
t "R3.1" "the firewall and stealth mode are set and read back" \
  '_logged "$RON" "socketfilterfw --setglobalstate on" && _logged "$RON" "socketfilterfw --setstealthmode on" &&
   _logged "$RON" "socketfilterfw --getglobalstate" && _logged "$RON" "socketfilterfw --getstealthmode"'
t "R3.2" "the firewall steps are one shared function, not copied: both files call it, only the lib sets it" '
  [ "$(code_of macos/defaults.sh | grep -c "dotfiles_firewall_on")" -ge 1 ] &&
  [ "$(code_of macos/defaults-remote-access.sh | grep -c "dotfiles_firewall_on")" -ge 1 ] &&
  [ "$(code_of macos/defaults.sh macos/defaults-remote-access.sh | grep -c -- "--setglobalstate\|--setstealthmode")" -eq 0 ] &&
  [ "$(code_of scripts/lib/defaults-common.sh | grep -c -- "--setglobalstate on")" -eq 1 ]'
t "R3.3" "an unchanged firewall is a counted failure in the remote access file too" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" FW_TAKES=)" -ge 2 ] && grep -q "error.*application firewall is still off" "$W/out"'
t "R3.4" "a good run has no error and a zero tally" \
  '[ "$(grep -c "error" "$RON/out")" -eq 0 ] && [ "$(_ra_tally "$(_ra_env)")" -eq 0 ]'
t "R3.5" "the steps run in order: firewall, groups, sshd, pf, then Remote Login, then Screen Sharing" '
  f=macos/defaults-remote-access.sh
  a=$(_first_line dotfiles_firewall_on $f); b=$(_first_line "-setremotelogin -f on" $f); c=$(_first_line dseditgroup $f)
  d=$(_first_line 010-dotfiles.conf $f); e=$(_first_line dotfiles.remote $f); g=$(_first_line "127.0.0.1 5900" $f)
  [ "$a" -gt 0 ] && [ "$a" -lt "$c" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$e" ] && [ "$e" -lt "$b" ] && [ "$b" -lt "$g" ]'
t "R3.5b" "at run time Remote Login is switched on only after sshd.conf and the pf daemon are installed" '
  W=$(_ra_env) && _ra_run "$W" && l=$(_first_line "-setremotelogin -f on" "$W/log") && [ "$l" -gt 0 ] &&
  [ "$(_first_line 010-dotfiles.conf "$W/log")" -lt "$l" ] && [ "$(_first_line bootstrap "$W/log")" -lt "$l" ]'

# Groups.
t "R3.6" "missing groups are created, the user is added and membership is read back" '
  bad=0
  for g in com.apple.access_ssh com.apple.access_screensharing; do
    _logged "$RON" "dseditgroup -o create -q $g" && _logged "$RON" "dseditgroup -o edit -a tester -t user $g" &&
    _logged "$RON" "dseditgroup -o checkmember -m tester $g" || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "R3.7" "a group that exists with no members is not created again, and the user is added" '
  W=$(_ra_env) && _ra_run "$W" GRP_EXIST=1 && [ "$(_logcount "$W" "dseditgroup -o create")" -eq 0 ] &&
  _logged "$W" "dseditgroup -o edit -a tester -t user com.apple.access_ssh" && [ "$(grep -c "error" "$W/out")" -eq 0 ] &&
  grep -qx tester "$W/fw/grp.com.apple.access_ssh"'
t "R3.8" "a user who cannot be added is an error and a counted failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" DSE_EDIT_FAIL=1)" -ge 2 ] && grep -q "error.*access_ssh" "$W/out"'
t "R3.9" "a group that cannot be created is an error and a counted failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" DSE_CREATE_FAIL=1)" -ge 2 ] && grep -q "error.*access_ssh" "$W/out"'

# sshd hardening.
SSHC=$RON/etc/ssh/sshd_config.d/010-dotfiles.conf
_inst_line() { grep -E "^install .*$2\$" "$1/log"; }
_inst_flags() { # _inst_flags <W> <dest-name> -- installed 0644 root:wheel
  local l
  l=$(_inst_line "$1" "$2")
  case "$l" in *"-m 0644"*) ;; *) return 1 ;; esac
  case "$l" in *"-o root"*) ;; *) return 1 ;; esac
  case "$l" in *"-g wheel"*) ;; *) return 1 ;; esac
}
t "R3.10" "sshd.conf is installed root:wheel 0644 as 010-dotfiles.conf, identical to the tracked file" \
  'cmp -s macos/remote-access/sshd.conf "$SSHC" && _inst_flags "$RON" 010-dotfiles.conf'
t "R3.11" "010-dotfiles.conf sorts before macOS 100-macos.conf (sshd keeps the first value it reads)" '
  [ "$(printf "%s\n%s\n" 100-macos.conf 010-dotfiles.conf | LC_ALL=C sort | head -1)" = 010-dotfiles.conf ] &&
  [ "$(code_of macos/defaults-remote-access.sh | grep -c "010-dotfiles.conf")" -ge 1 ]'
t "R3.12" "sshd.conf turns off passwords, keyboard-interactive and root, and allows publickey only" '
  f=macos/remote-access/sshd.conf; bad=0
  for l in "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "AuthenticationMethods publickey" \
    "PermitEmptyPasswords no" "MaxAuthTries 3" "LoginGraceTime 20" "DisableForwarding yes" "PermitTunnel no" "PermitUserEnvironment no" \
    "PubkeyAcceptedAlgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com,ecdsa-sha2-nistp256,sk-ecdsa-sha2-nistp256@openssh.com"; do
    grep -qxF "$l" "$f" || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ] && [ "$(code_of "$f" | grep -ciE "^(PasswordAuthentication|KbdInteractiveAuthentication|PermitRootLogin|PermitEmptyPasswords)[[:space:]]+yes")" -eq 0 ]'
t "R3.13" "sshd -t runs after the file is installed" \
  '_logged "$RON" "sshd -t" && [ "$(_first_line "install" "$RON/log")" -lt "$(_first_line "sshd -t" "$RON/log")" ]'
t "R3.14" "a failing sshd -t removes the file again, errors and counts a failure" '
  W=$(_ra_env) && [ "$(_ra_tally "$W" SSHD_RC=1)" -ge 1 ] && [ ! -e "$W/etc/ssh/sshd_config.d/010-dotfiles.conf" ] &&
  grep -q "error.*sshd" "$W/out"'
t "R3.14b" "missing host keys are generated with the system ssh-keygen -A before sshd -t (a Mac that never ran Remote Login has none)" '
  _logged "$RON" "ssh-keygen -A" && [ "$(_first_line "ssh-keygen -A" "$RON/log")" -lt "$(_first_line "sshd -t" "$RON/log")" ] &&
  [ "$(code_of macos/defaults-remote-access.sh | grep -c "DOTFILES_SSH_KEYGEN:-/usr/bin/ssh-keygen")" -ge 1 ]'
t "R3.14c" "a failing sshd -t shows sshd own message, not just that it failed" \
  'W=$(_ra_env) && _ra_run "$W" SSHD_RC=1 && grep -q "error.*no hostkeys available" "$W/out"'
t "R3.15" "no authorized_keys: nothing installed, an error naming the phone key, a counted failure" '
  W=$(_ra_env) && rm -f "$W/home/.ssh/authorized_keys" && [ "$(_ra_tally "$W")" -ge 1 ] &&
  [ ! -e "$W/etc/ssh/sshd_config.d/010-dotfiles.conf" ] && [ "$(_logcount "$W" "sshd -t")" -eq 0 ] &&
  grep -qE "error.*(phone|public key).*authorized_keys" "$W/out"'
t "R3.16" "authorized_keys with only blanks and comments counts as no key" '
  W=$(_ra_env) && printf "# a comment\n\n   \n  # indented comment\n" >"$W/home/.ssh/authorized_keys" && [ "$(_ra_tally "$W")" -ge 1 ] &&
  [ ! -e "$W/etc/ssh/sshd_config.d/010-dotfiles.conf" ]'
t "R3.17" "a key line among comments is enough" '
  W=$(_ra_env) && printf "# c\n\nssh-ed25519 AAAA phone\n" >"$W/home/.ssh/authorized_keys" && _ra_run "$W" && [ -e "$W/etc/ssh/sshd_config.d/010-dotfiles.conf" ]'
t "R3.18" "the missing-key guard only blocks sshd: groups and pf still apply" '
  W=$(_ra_env) && rm -f "$W/home/.ssh/authorized_keys" && _ra_run "$W" && _logged "$W" "dseditgroup -o edit -a tester -t user com.apple.access_ssh" &&
  [ -e "$W/etc/pf.anchors/dotfiles.remote" ]'

# pf.
PFR=macos/remote-access/pf.rules
PLIST=macos/remote-access/com.stixzoor.dotfiles-pf-remote.plist
t "R3.19" "pf.rules passes both Tailscale ranges and loopback to 22 and 5900, then blocks them for everyone else" '
  c=$(code_of $PFR | grep -v "^[[:space:]]*$")
  printf "%s\n" "$c" | grep -q "^table <dotfiles_tailnet> const { 100.64.0.0/10, fd7a:115c:a1e0::/48 }$" &&
  printf "%s\n" "$c" | grep -q "^pass in quick on lo0 proto { tcp udp } to any port { 22 5900 }$" &&
  printf "%s\n" "$c" | grep -q "^pass in quick proto { tcp udp } from <dotfiles_tailnet> to any port { 22 5900 }$" &&
  [ "$(printf "%s\n" "$c" | tail -1)" = "block drop in quick proto { tcp udp } to any port { 22 5900 }" ] &&
  [ "$(printf "%s\n" "$c" | grep -c "^pass ")" -eq 2 ] && [ "$(printf "%s\n" "$c" | grep -c "^block ")" -eq 1 ]'
t "R3.20" "pf.rules and the daemon are installed root:wheel 0644 into the system directories" '
  cmp -s $PFR "$RON/etc/pf.anchors/dotfiles.remote" && cmp -s $PLIST "$RON/Library/LaunchDaemons/com.stixzoor.dotfiles-pf-remote.plist" &&
  _inst_flags "$RON" dotfiles.remote && _inst_flags "$RON" com.stixzoor.dotfiles-pf-remote.plist'
t "R3.21" "the daemon plist is valid, labelled, runs at load and every 300 seconds" '
  plutil -lint $PLIST >/dev/null && [ "$(plutil -extract Label raw $PLIST)" = com.stixzoor.dotfiles-pf-remote ] &&
  [ "$(plutil -extract RunAtLoad raw $PLIST)" = true ] && [ "$(plutil -extract StartInterval raw $PLIST)" = 300 ]'
t "R3.22" "SECURITY: the root daemon references only root-owned system paths, nothing under the repo or HOME" '
  txt=$(sed -E "s/<[^>]*>/ /g" $PLIST | tr "\047\042" "  ")
  paths=$(printf "%s\n" "$txt" | grep -oE "(^|[[:space:];|])/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]*)*" | tr -d " ;|")
  bad=0
  for p in $paths; do
    case "$p" in /bin/* | /sbin/* | /usr/bin/* | /etc/pf.anchors/*) ;; *) bad=$((bad + 1)) ;; esac
  done
  [ -n "$paths" ] && [ "$bad" -eq 0 ] &&
  [ "$(printf "%s\n" "$txt" | grep -ciE "/Users|[$]HOME|~|/[.]dotfiles|/private/var")" -eq 0 ]'
t "R3.23" "the daemon loads the anchor com.apple/900.dotfiles-remote and enables pf if it is off" '
  txt=$(sed -E "s/<[^>]*>/ /g" $PLIST)
  case "$txt" in *"/sbin/pfctl -q -a com.apple/900.dotfiles-remote -f /etc/pf.anchors/dotfiles.remote"*"pfctl -q -E"*) true ;; *) false ;; esac'
t "R3.24" "the old daemon is booted out (failure ignored), then bootstrapped, then the rules are read back" '
  L=com.stixzoor.dotfiles-pf-remote
  _logged "$RON" "sudo launchctl bootout system/$L" && _logged "$RON" "sudo launchctl bootstrap system $RON/Library/LaunchDaemons/$L.plist" &&
  _logged "$RON" "sudo pfctl -a com.apple/900.dotfiles-remote -sr" &&
  [ "$(_first_line bootout "$RON/log")" -lt "$(_first_line bootstrap "$RON/log")" ] &&
  [ "$(_first_line bootstrap "$RON/log")" -lt "$(_first_line "-sr" "$RON/log")" ]'
t "R3.25" "a failing bootout is ignored" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" LC_BOOTOUT_FAIL=1)" -eq 0 ] && _logged "$W" "sudo launchctl bootstrap system $W/Library/LaunchDaemons/com.stixzoor.dotfiles-pf-remote.plist"'
t "R3.26" "rules that do not show up afterwards are an error and a counted failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" PF_EMPTY=1 DOTFILES_PF_WAIT=0)" -ge 1 ] && grep -q "error.*pf" "$W/out"'
t "R3.27" "a failing bootstrap is an error and a counted failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" LC_BOOTSTRAP_FAIL=1)" -ge 1 ]'
t "R3.28" "/etc/pf.conf is never touched" \
  '[ "$(code_of macos/defaults-remote-access.sh | grep -c "pf\.conf")" -eq 0 ] && [ "$(grep -c "pf\.conf" "$RON/log")" -eq 0 ]'
t "R3.39" "rules pf cannot parse are an error, and nothing is installed or loaded" '
  W=$(_ra_env) && [ "$(_ra_tally "$W" PF_RC=1)" -ge 1 ] && [ ! -e "$W/etc/pf.anchors/dotfiles.remote" ] &&
  [ ! -e "$W/Library/LaunchDaemons/com.stixzoor.dotfiles-pf-remote.plist" ] && [ "$(_logcount "$W" "bootstrap")" -eq 0 ]'
t "R3.40" "rules loaded while pf itself is disabled are an error and a counted failure" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" PF_DISABLED=1 DOTFILES_PF_WAIT=0)" -ge 1 ] && _logged "$W" "sudo pfctl -s info" && grep -q "error.*pf" "$W/out"'
t "R3.41" "rules that show up a moment after bootstrap (launchd runs the job on its own time) are fine" \
  'W=$(_ra_env) && [ "$(_ra_tally "$W" PF_LATE=1)" -eq 0 ] && [ "$(grep -c "error" "$W/out")" -eq 0 ]'
t "R3.42" "a disabled pf with unchanged files still gets the daemon bootstrapped again" '
  W=$(_ra_env) && _ra_run "$W" && : >"$W/log" && _ra_run "$W" PF_DISABLED=1 DOTFILES_PF_WAIT=0 &&
  _logged "$W" "sudo launchctl bootstrap system $W/Library/LaunchDaemons/com.stixzoor.dotfiles-pf-remote.plist"'

# Remote Login is switched on last, and only onto a hardened, Tailscale-only sshd.
t "R3.43" "no key in authorized_keys: Remote Login is left off, with an error saying why" '
  W=$(_ra_env) && rm -f "$W/home/.ssh/authorized_keys" && _ra_run "$W" &&
  [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ] && grep -qE "error.*Remote Login.*(keys only|Tailscale)" "$W/out"'
t "R3.44" "sshd rejecting the config: Remote Login is left off" \
  'W=$(_ra_env) && _ra_run "$W" SSHD_RC=1 && [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ]'
t "R3.45" "pf not restricting (bootstrap fails, or no rules): Remote Login is left off" '
  W=$(_ra_env) && _ra_run "$W" LC_BOOTSTRAP_FAIL=1 && [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ] &&
  W=$(_ra_env) && _ra_run "$W" PF_EMPTY=1 DOTFILES_PF_WAIT=0 && [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ]'
t "R3.46" "Remote Login already on is left on when the hardening fails (nothing is ever turned off)" '
  W=$(_ra_env) && rm -f "$W/home/.ssh/authorized_keys" && _ra_run "$W" RL_LAUNCHD=1 &&
  [ "$(_logcount "$W" "-setremotelogin")" -eq 0 ] && [ "$(grep -c "error.*Remote Login" "$W/out")" -eq 0 ]'

# Screen Sharing.
t "R3.29" "Screen Sharing listening: no action line, and it was probed on 5900" \
  '[ "$(grep -c "Only these users" "$RON/out")" -eq 0 ] && _logged "$RON" "nc -z 127.0.0.1 5900"'
t "R3.30" "Screen Sharing off: an action line with the exact path, and it is not a failure" '
  W=$(_ra_env) && [ "$(_ra_tally "$W" SS_PORT=)" -eq 0 ] && grep -q "System Settings > General > Sharing > Screen Sharing" "$W/out" &&
  grep -q "Only these users" "$W/out"'
t "R3.31" "the legacy VNC password setting present: a warning to turn it off" '
  W=$(_ra_env) && : >"$W/vnc.txt" && _ra_run "$W" && grep -q "warning.*VNC viewers may control screen with password" "$W/out"'
t "R3.32" "no legacy VNC file: no VNC warning" \
  '[ "$(grep -c "VNC viewers" "$RON/out")" -eq 0 ]'
t "R3.33" "Screen Sharing is never switched on from the CLI" \
  '[ "$(code_of macos/defaults-remote-access.sh | grep -ci "kickstart\|launchctl.*screensharing")" -eq 0 ]'

# Idempotence.
t "R3.34" "a second run installs nothing, says already set, and is clean" '
  W=$(_ra_env) && _ra_run "$W" && : >"$W/log" && [ "$(_ra_tally "$W")" -eq 0 ] &&
  [ "$(_logcount "$W" "install")" -eq 0 ] && [ "$(_logcount "$W" "bootstrap")" -eq 0 ] && [ "$(_logcount "$W" "sshd -t")" -eq 0 ] &&
  [ "$(grep -c "already set" "$W/out")" -ge 2 ] && [ "$(grep -c "error" "$W/out")" -eq 0 ]'
t "R3.35" "a changed installed file is replaced on the next run" '
  W=$(_ra_env) && _ra_run "$W" && echo "PasswordAuthentication yes" >"$W/etc/ssh/sshd_config.d/010-dotfiles.conf" && : >"$W/log" &&
  _ra_run "$W" && cmp -s macos/remote-access/sshd.conf "$W/etc/ssh/sshd_config.d/010-dotfiles.conf"'
t "R3.36" "files are compared with cmp, not just checked for existing" \
  '[ "$(code_of macos/defaults-remote-access.sh | grep -c "cmp -s")" -ge 1 ]'
t "R3.37" "the file works alone: it sets DOTFILES_DIR and sources the shared helpers itself" \
  'grep -q "^DOTFILES_DIR=" macos/defaults-remote-access.sh && [ "$(code_of macos/defaults-remote-access.sh | grep -c "defaults-common.sh")" -ge 1 ]'
t "R3.38" "the tracked files carry no home path and no private address" \
  'ips=$(cat macos/remote-access/* macos/defaults-remote-access.sh | grep -oE "[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}(/[0-9]+)?" | grep -vxE "127[.]0[.]0[.]1|100[.]64[.]0[.]0/10")
   homes=$(cat macos/remote-access/* macos/defaults-remote-access.sh | grep -F "/Users/")
   [ -z "$ips" ] && [ -z "$homes" ]'

#############################################################################
section "R4 — LAN peers: the other Mac on the local network, besides Tailscale"
#############################################################################

# _lan_fn <dir> [VAR=val ...] -- what dotfiles_remote_lan_peers prints; _lan_err
# its stderr. Addresses are from the documentation range 192.0.2.0/24.
_lan_fn() {
  local d=$1
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_remote_lan_peers "$2"' _ "$ROOT_DIR" "$d" 2>/dev/null
}
# shellcheck disable=SC2069
_lan_err() {
  local d=$1
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_remote_lan_peers "$2"' _ "$ROOT_DIR" "$d" 2>&1 >/dev/null
}

t "R4.1" "none configured: prints nothing" \
  'D=$(_ra_dir) && [ -z "$(_lan_fn "$D")" ]'
t "R4.2" "the environment wins, and addresses and /prefixes are kept in order" \
  'D=$(_ra_dir) && echo "DOTFILES_REMOTE_LAN_PEERS=192.0.2.9" >"$D/macos/local.sh" &&
   [ "$(_lan_fn "$D" DOTFILES_REMOTE_LAN_PEERS="192.0.2.10 192.0.2.20 192.0.2.0/24")" = "192.0.2.10 192.0.2.20 192.0.2.0/24" ]'
t "R4.3" "machine.local.sh beats local.sh, and local.sh (shared by both Macs) is read" '
  D=$(_ra_dir) && echo "DOTFILES_REMOTE_LAN_PEERS=\"192.0.2.10 192.0.2.20\"" >"$D/macos/local.sh" &&
  [ "$(_lan_fn "$D")" = "192.0.2.10 192.0.2.20" ] &&
  echo "DOTFILES_REMOTE_LAN_PEERS=192.0.2.30" >"$D/macos/machine.local.sh" && [ "$(_lan_fn "$D")" = "192.0.2.30" ]'
t "R4.4" "anything that is not an IPv4 address with an optional /0-32 is dropped with a warning" '
  D=$(_ra_dir) && v="192.0.2.10 300.1.1.1 192.0.2.0/33 any 192.0.2.5;pass 1.2.3 * 192.0.2.20/32" &&
  [ "$(_lan_fn "$D" DOTFILES_REMOTE_LAN_PEERS="$v")" = "192.0.2.10 192.0.2.20/32" ] &&
  [ "$(_lan_err "$D" DOTFILES_REMOTE_LAN_PEERS="$v" | grep -c "warning")" -eq 6 ]'
t "R4.5" "nothing the files set leaks into the caller" \
  'D=$(_ra_dir) && printf "DOTFILES_REMOTE_LAN_PEERS=192.0.2.10\nLEAK=yes\n" >"$D/macos/local.sh" &&
   [ "$(env -i PATH=/usr/bin:/bin bash -c ". \"$ROOT_DIR/scripts/lib/machine.sh\"; dotfiles_remote_lan_peers \"$D\" >/dev/null; echo \"\${LEAK:-none}\${DOTFILES_REMOTE_LAN_PEERS:-none}\"")" = nonenone ]'

ANCH=etc/pf.anchors/dotfiles.remote
LANLINE="pass in quick proto { tcp udp } from { 192.0.2.10, 192.0.2.20 } to any port { 22 5900 }"
RLAN=$(_ra_env); _ra_run "$RLAN" DOTFILES_REMOTE_LAN_PEERS="192.0.2.10 192.0.2.20"
t "R4.6" "with LAN peers the installed rules are the tracked ones plus one pass line for them, before the block" '
  grep -qxF "$LANLINE" "$RLAN/$ANCH" && [ "$(tail -1 "$RLAN/$ANCH")" = "$(tail -1 macos/remote-access/pf.rules)" ] &&
  [ "$(grep -vxF "$LANLINE" "$RLAN/$ANCH" | cmp -s - macos/remote-access/pf.rules && echo same)" = same ] &&
  [ "$(grep -c "error" "$RLAN/out")" -eq 0 ]'
t "R4.7" "without LAN peers the installed rules are exactly the tracked file" \
  'cmp -s macos/remote-access/pf.rules "$RON/$ANCH"'
t "R4.8" "an injection attempt never reaches the root-loaded rules" '
  W=$(_ra_env) && _ra_run "$W" DOTFILES_REMOTE_LAN_PEERS="192.0.2.10 } pass in all {" &&
  [ "$(grep -c "pass in all" "$W/$ANCH")" -eq 0 ] && grep -qxF "pass in quick proto { tcp udp } from { 192.0.2.10 } to any port { 22 5900 }" "$W/$ANCH"'
t "R4.9" "a re-run with the same LAN peers changes nothing" '
  : >"$RLAN/log" && _ra_run "$RLAN" DOTFILES_REMOTE_LAN_PEERS="192.0.2.10 192.0.2.20" &&
  [ "$(_logcount "$RLAN" "install")" -eq 0 ] && [ "$(_logcount "$RLAN" "bootstrap")" -eq 0 ] && grep -q "Tailscale.*already set" "$RLAN/out"'
t "R4.10" "changing the LAN peers reinstalls and reloads the rules" '
  : >"$RLAN/log" && _ra_run "$RLAN" DOTFILES_REMOTE_LAN_PEERS="192.0.2.30" &&
  grep -qxF "pass in quick proto { tcp udp } from { 192.0.2.30 } to any port { 22 5900 }" "$RLAN/$ANCH" && _logged "$RLAN" "sudo launchctl bootout system/com.stixzoor.dotfiles-pf-remote"'
t "R4.11" "the rules are parsed (pfctl -n) as built, LAN line included, before anything is installed" '
  W=$(_ra_env) && _ra_run "$W" DOTFILES_REMOTE_LAN_PEERS="192.0.2.10" PF_RC=1 && [ ! -e "$W/$ANCH" ]'
t "R4.12" "macos/local.sh.example documents it, commented out, with documentation addresses only" \
  '[ "$(grep -c "^# DOTFILES_REMOTE_LAN_PEERS=\"192[.]0[.]2[.]" macos/local.sh.example)" -eq 1 ] && [ "$(grep -c "^DOTFILES_REMOTE_LAN_PEERS=" macos/local.sh.example)" -eq 0 ]'

finish

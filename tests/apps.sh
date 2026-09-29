#!/usr/bin/env bash
#
# tests/apps.sh -- bin/dotfiles-apps: app-settings backup with mackup in copy
# mode (Task 6 of the 2026-09-29 new-Mac readiness work).
#
# HERMETIC. Every run uses a sandbox HOME (with XDG_CONFIG_HOME inside it,
# because mackup refuses one outside $HOME), a sandbox stand-in for iCloud
# Drive (DOTFILES_APPS_STORE), and stubs on PATH for mackup, pgrep, killall,
# brctl, scutil and plutil that log their argv. Nothing here touches the real
# HOME, the real iCloud Drive, cfprefsd or launchd. A real mackup is used only
# for the read-only `check` of the shipped allowlist, and only when installed.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# APPS_ONLY="H R": run only the tests whose id starts with one of these.
if [ -n "${APPS_ONLY:-}" ]; then
  eval "$(declare -f t | sed '1s/^t /_t_real /')"
  t() { local p; for p in $APPS_ONLY; do case "$1" in "$p"*) _t_real "$@"; return ;; esac; done; }
fi

APPS=bin/dotfiles-apps

# Real mackup is only used for the read-only `check` of the shipped allowlist.
# Without it those two tests pass vacuously, so say so out loud.
HAVE_PLUTIL=0
[ -x /usr/bin/plutil ] && HAVE_PLUTIL=1
[ "$HAVE_PLUTIL" -eq 1 ] || printf '%sSKIP%s H26 needs the real /usr/bin/plutil\n' "$RED" "$RESET"
# The real mackup is slow to start (Python) and reads a real install, so tests
# that run it are opt-in: DOTFILES_TEST_REAL_MACKUP=1.
HAVE_MACKUP=0
if [ "${DOTFILES_TEST_REAL_MACKUP:-}" != 1 ]; then
  printf '%sSKIP%s tests that run the real mackup (G2.16, C12): set DOTFILES_TEST_REAL_MACKUP=1 to include them\n' "$RED" "$RESET"
elif [ -x /opt/homebrew/bin/mackup ]; then
  HAVE_MACKUP=1
else
  printf '%sSKIP%s tests that need a real mackup (G2.16, C12): /opt/homebrew/bin/mackup is not installed\n' "$RED" "$RESET"
fi
PLIST_OK='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><string>v</string></dict></plist>'

# shared_stubs: the stub binaries, written once per run into $SHARED_STUBS and
# symlinked into every sandbox. macOS scans an executable the first time it is
# run, about a second each; a fresh copy of six stubs per test made this suite
# take over ten minutes. A symlink to an already-run file is not scanned again.
SHARED_STUBS="$_sandbox_root/shared-stubs"
shared_stubs() {
  [ -x "$SHARED_STUBS/plutil" ] && return 0
  mkdir -p "$SHARED_STUBS" || return 1
  cp tests/fixtures/mackup-stub "$SHARED_STUBS/mackup"
  printf '#!/bin/sh\necho "pgrep $*" >>"$STUB_LOG"\n[ "$1" = "-x" ] && [ -f "$STUB_RUNNING" ] && grep -Fxq -- "$2" "$STUB_RUNNING"\n' >"$SHARED_STUBS/pgrep"
  printf '#!/bin/sh\necho "killall $*" >>"$STUB_LOG"\n' >"$SHARED_STUBS/killall"
  printf '#!/bin/sh\necho "brctl $*" >>"$STUB_LOG"\n[ "${STUB_BRCTL_MATERIALIZE:-}" = 1 ] && find "$2" -name "*.icloud" -exec rm -f {} + 2>/dev/null\nexit 0\n' >"$SHARED_STUBS/brctl"
  printf '#!/bin/sh\nprintf "%%s\\n" "${STUB_HOSTNAME:-My Mac_mini.local}"\n' >"$SHARED_STUBS/scutil"
  printf '#!/bin/sh\necho "plutil $*" >>"$STUB_LOG"\n[ -n "${STUB_PLUTIL_LAX:-}" ] && [ -s "$2" ] && exit 0\n[ -s "$2" ] && grep -q "<plist" "$2"\n' >"$SHARED_STUBS/plutil"
  chmod +x "$SHARED_STUBS/"*
}

# mkenv <W>: a sandbox HOME, stubs, fixture app definitions and a fixture
# allowlist (alpha, beta). Everything the tool reads or writes lives under W.
mkenv() {
  local w="$1" h="$1/home"
  mkdir -p "$h/Library/Preferences" "$h/Library/Application Support/Beta" \
    "$h/.config" "$w/stubs" "$w/defs" "$w/cfg" "$w/icloud"
  printf '%s\n' "$PLIST_OK" >"$h/Library/Preferences/com.example.alpha.plist"
  printf '{"a":1}\n' >"$h/Library/Application Support/Beta/settings.json"
  local n
  shared_stubs
  for n in mackup pgrep killall brctl scutil plutil; do ln -s "$SHARED_STUBS/$n" "$w/stubs/$n"; done
  add_app "$w" alpha "Library/Preferences/com.example.alpha.plist"
  add_app "$w" beta "Library/Application Support/Beta"
  set_allow "$w" alpha beta
}

# add_app <W> <name> <relative path>...: a fixture app definition.
add_app() {
  local w="$1" name="$2"; shift 2
  { printf '[application]\nname = %s\n\n[configuration_files]\n' "$name"; printf '%s\n' "$@"; } >"$w/defs/$name.cfg"
}

# set_allow <W> <app>...: the fixture allowlist plus a process mapping for each.
set_allow() {
  local w="$1" a; shift
  { printf '[storage]\nengine = file_system\npath = x\ndirectory = Mackup\n\n[applications_to_sync]\n'; printf '%s\n' "$@"; } >"$w/cfg/mackup.cfg"
  : >"$w/cfg/processes.list"
  for a in "$@"; do printf '%s|%sProc\n' "$a" "$a" >>"$w/cfg/processes.list"; done
}

# run_apps <args>: run the tool against the sandbox in $W. $APPS_ENV adds
# VAR=value pairs (no spaces) and $APPS_DF points DOTFILES_DIR elsewhere.
run_apps() {
  # shellcheck disable=SC2086
  env -i HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" PATH="$W/stubs:/usr/bin:/bin" \
    DOTFILES_DIR="${APPS_DF:-$ROOT_DIR}" DOTFILES_APPS_STORE="$W/icloud" \
    DOTFILES_MACHINE_NAME=macA DOTFILES_APPS_CFG="$W/cfg/mackup.cfg" \
    DOTFILES_APPS_DL_WAIT=0 DOTFILES_APPS_DL_POLL=0 STUB_LOG="$W/log" STUB_DEFS="$W/defs" STUB_RUNNING="$W/running" \
    ${APPS_ENV:-} bash "$ROOT_DIR/$APPS" "$@"
}

# refused <pattern> <args>: the tool exits non-zero AND says <pattern>. A bare
# `! run_apps ...` also passes when the script is missing or crashes.
refused() {
  local pat="$1" out rc; shift
  out=$(run_apps "$@" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf '%s\n' "$out" | grep -c -- "$pat")" -ge 1 ]
}

# newenv: a fresh sandbox with the fixture environment; prints its path.
newenv() { local w; w=$(sandbox) || return 1; mkenv "$w"; printf '%s' "$w"; }

#############################################################################
section "G1 -- the shipped allowlist (config/mackup)"
#############################################################################
CFG=config/mackup/mackup.cfg
allow_of() { awk '/^\[/ { s = ($0 == "[applications_to_sync]"); next } s && NF && $0 !~ /^#/ { print }' "$CFG"; }

t "G1.1" "file_system engine, staging path relative to HOME" \
  '[ "$(sed -n "s/^engine *= *//p" $CFG)" = file_system ] &&
   p=$(sed -n "s/^path *= *//p" $CFG) && [ -n "$p" ] && [ "${p#/}" = "$p" ] && [ "${p#~}" = "$p" ]'
t "G1.2" "allowlist is not empty (an empty one makes mackup sync every app)" \
  '[ "$(allow_of | wc -l | tr -d " ")" -ge 1 ]'
t "G1.3" "every allowlisted app has a process mapping for the restore guard" \
  '(for a in $(allow_of); do grep -q "^$a|" config/mackup/processes.list || exit 1; done)'
t "G1.4" "every custom definition has a name and a configuration_files section" \
  '(for f in config/mackup/applications/*.cfg; do
     grep -q "^\[application\]" "$f" && grep -q "^name = " "$f" && grep -q "^\[configuration_files\]" "$f" || exit 1
   done)'
t "G1.5" "Shottr has a definition for its preferences plist" \
  'grep -q "^Library/Preferences/cc.ffitch.shottr.plist$" config/mackup/applications/shottr.cfg'
t "G1.6" "no definition or config carries an absolute home path" \
  '[ "$(grep -rl "/Users/" config/mackup | wc -l | tr -d " ")" -eq 0 ]'
t "G1.7" "the proxyman definition copies preferences only (certificates stay local)" \
  'body=$(code_of config/mackup/applications/proxyman-setapp.cfg); [ "$(printf "%s\n" "$body" | grep -c "Application Support")" -eq 0 ]'

#############################################################################
section "G2 -- overlap guard (dotfiles-apps check)"
#############################################################################
t "G2.1" "the fixture allowlist passes" \
  'W=$(newenv); run_apps check'
t "G2.2" "an app covering a stowed runcom file fails, naming app and path" \
  'W=$(newenv); add_app "$W" zshapp ".zshrc"; set_allow "$W" alpha zshapp
   out=$(run_apps check 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "zshapp" && printf "%s\n" "$out" | grep -q "\.zshrc"'
t "G2.3" "an app covering a stowed config/ directory fails" \
  'W=$(newenv); add_app "$W" gitapp ".config/git/config"; set_allow "$W" alpha gitapp
   out=$(run_apps check 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "gitapp"'
t "G2.4" "an app covering a parent of a stowed path fails too" \
  'W=$(newenv); add_app "$W" cfgapp ".config"; set_allow "$W" alpha cfgapp
   refused OVERLAP check'
t "G2.5" "an app covering a claude/ target fails" \
  'W=$(newenv); add_app "$W" claudeapp ".claude/settings.json"; set_allow "$W" alpha claudeapp
   refused OVERLAP check'
t "G2.6" "an app covering a codex/ target fails" \
  'W=$(newenv); add_app "$W" codexapp ".codex/config.toml"; set_allow "$W" alpha codexapp
   refused OVERLAP check'
t "G2.7" "an app covering an apps/ target (warp, vlc, vscode, gitkraken, xcode) fails" \
  'W=$(newenv); rc=0
   for p in ".warp/settings.toml" "Library/Preferences/org.videolan.vlc/vlcrc" "Library/Application Support/Code/User/settings.json" ".gitkraken/profiles" "Library/Developer/Xcode/UserData/FontAndColorThemes/Nord.xccolortheme"; do
     add_app "$W" appsapp "$p"; set_allow "$W" alpha appsapp
     refused OVERLAP check || rc=1
   done; [ "$rc" -eq 0 ]'
t "G2.8" "an app whose plist is a domain macos/defaults*.sh writes fails" \
  'W=$(newenv); add_app "$W" domapp "Library/Preferences/com.apple.dock.plist"; set_allow "$W" alpha domapp
   out=$(run_apps check 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "domapp" && printf "%s\n" "$out" | grep -q "com.apple.dock"'
t "G2.9" "domain matching is case-insensitive (COM.APPLE.TERMINAL.plist vs com.apple.terminal)" \
  'W=$(newenv); add_app "$W" termapp "Library/Preferences/COM.APPLE.TERMINAL.plist"; set_allow "$W" alpha termapp
   refused OVERLAP check'
t "G2.10" "the global domain plist is protected" \
  'W=$(newenv); add_app "$W" globapp "Library/Preferences/.GlobalPreferences.plist"; set_allow "$W" alpha globapp
   refused OVERLAP check'
t "G2.11" "an apps/ directory with no entry in the maintained target list fails" \
  'W=$(newenv); mkdir -p "$W/df/apps/newthing"
   for d in runcom config macos claude codex bin; do ln -s "$ROOT_DIR/$d" "$W/df/$d"; done
   mkdir -p "$W/df/apps"; for d in gitkraken terminal vlc vscode warp xcode; do mkdir -p "$W/df/apps/$d"; done
   out=$(APPS_DF="$W/df" run_apps check 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "newthing"'
t "G2.12" "the real apps/ layout is fully mapped (control for G2.11)" \
  'W=$(newenv); run_apps check'
t "G2.13" "an allowlist with no entries is refused" \
  'W=$(newenv); set_allow "$W"; refused "empty" check'
t "G2.14" "an unknown app is refused" \
  'W=$(newenv); set_allow "$W" alpha nosuchapp; refused "unknown app" check'
t "G2.15" "an allowlisted app without a process mapping is refused" \
  'W=$(newenv); grep -v "^beta|" "$W/cfg/processes.list" >"$W/cfg/p2" && mv "$W/cfg/p2" "$W/cfg/processes.list"
   out=$(run_apps check 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q beta'
t "G2.16" "the shipped allowlist passes against real mackup (skipped, visibly, when not installed)" \
  '[ "$HAVE_MACKUP" -eq 0 ] || {
   W=$(sandbox); mkdir -p "$W/home/.config/mackup" "$W/stubs"
   cp -R config/mackup/applications "$W/home/.config/mackup/applications"
   env -i HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" PATH="/opt/homebrew/bin:/usr/bin:/bin" \
     DOTFILES_DIR="$ROOT_DIR" DOTFILES_APPS_STORE="$W/icloud" bash "$APPS" check; }'

#############################################################################
section "H -- backup: stage, validate, publish, rotate (6.3)"
#############################################################################
snaps() { local d; for d in "$W/icloud/${1:-macA}/snapshots"/[0-9]*; do [ -e "$d" ] && basename "$d"; done; }
nsnaps() { snaps "$@" | grep -c .; }
latest_of() { command cat "$W/icloud/${1:-macA}/latest" 2>/dev/null; }
mk_snap() { mkdir -p "$W/icloud/$1/snapshots/$2/Mackup"; } # mk_snap <machine> <name>
wipe() { find "$@" -delete 2>/dev/null; }                  # remove files or trees inside the sandbox
lock_dir() { printf '%s' "$W/home/.local/state/dotfiles/mackup/lock.d"; }

t "H1" "backup publishes a snapshot holding the app files, and latest names it" \
  'W=$(newenv); run_apps backup && n=$(latest_of) && [ -n "$n" ] && [ "$(nsnaps)" -eq 1 ] &&
   cmp -s "$W/home/Library/Preferences/com.example.alpha.plist" "$W/icloud/macA/snapshots/$n/Mackup/Library/Preferences/com.example.alpha.plist" &&
   cmp -s "$W/home/Library/Application Support/Beta/settings.json" "$W/icloud/macA/snapshots/$n/Mackup/Library/Application Support/Beta/settings.json"'
t "H2" "the snapshot name is a UTC timestamp and latest is a plain file" \
  'W=$(newenv); run_apps backup && n=$(latest_of) &&
   printf "%s\n" "$n" | grep -Eq "^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$" && [ -f "$W/icloud/macA/latest" ] && [ ! -L "$W/icloud/macA/latest" ]'
t "H3" "no symlink exists anywhere in the store after a backup" \
  'W=$(newenv); run_apps backup && [ "$(find "$W/icloud" -type l | wc -l | tr -d " ")" -eq 0 ]'
t "H4" "every mackup call passes -c, and none is link" \
  'W=$(newenv); run_apps backup && grep -q " backup\$" "$W/log" &&
   [ "$(grep -E "^(-c |plutil |pgrep |killall |brctl )" -v "$W/log" | grep -c .)" -eq 0 ] && [ "$(grep -c "link" "$W/log")" -eq 0 ]'
t "H5" "an invalid plist blocks publishing and the previous snapshot is untouched" \
  'W=$(newenv); run_apps backup && before=$(latest_of) &&
   printf "garbage\n" >"$W/home/Library/Preferences/com.example.alpha.plist" &&
   refused "com.example.alpha.plist" backup && [ "$(nsnaps)" -eq 1 ] && [ "$(latest_of)" = "$before" ] &&
   grep -q "<plist" "$W/icloud/macA/snapshots/$before/Mackup/Library/Preferences/com.example.alpha.plist"'
t "H6" "a zero-byte plist blocks publishing" \
  'W=$(newenv); : >"$W/home/Library/Preferences/com.example.alpha.plist"
   refused "zero-byte plist" backup && [ "$(nsnaps)" -eq 0 ]'
t "H7" "a staged symlink is refused" \
  'W=$(newenv); APPS_ENV="STUB_PLANT_LINK=1" refused "symlink" backup && [ "$(nsnaps)" -eq 0 ]'
t "H8" "a TCC denial is reported by app and nothing is published" \
  'W=$(newenv); out=$(APPS_ENV="STUB_DENY=beta" run_apps backup 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "beta" && printf "%s\n" "$out" | grep -qi "not permitted\|permission" && [ "$(nsnaps)" -eq 0 ]'
t "H9" "rotation keeps the newest 14 snapshots per machine" \
  'W=$(newenv); i=0; while [ $i -lt 15 ]; do mk_snap macA "20200101T0000$(printf %02d $i)Z"; i=$((i + 1)); done
   [ "$(nsnaps)" -eq 15 ] && run_apps backup && [ "$(nsnaps)" -eq 14 ] &&
   [ "$(snaps | grep -c "^2020")" -eq 13 ] && [ "$(snaps | grep -c "T000000Z\|T000001Z")" -eq 0 ]'
t "H10" "rotation never touches another machine's snapshots" \
  'W=$(newenv); mk_snap mini 20200101T000000Z; i=0; while [ $i -lt 20 ]; do mk_snap macA "20210101T0000$(printf %02d $i)Z"; i=$((i + 1)); done
   run_apps backup && [ "$(nsnaps mini)" -eq 1 ]'
t "H11" "two Macs back up into their own folders and never overwrite each other" \
  'W=$(newenv); run_apps backup && a=$(latest_of macA) &&
   printf "changed\n" >"$W/home/Library/Application Support/Beta/settings.json" &&
   APPS_ENV="DOTFILES_MACHINE_NAME=mini" run_apps backup && b=$(latest_of mini) &&
   [ "$(latest_of macA)" = "$a" ] && [ "$(nsnaps macA)" -eq 1 ] && [ "$(nsnaps mini)" -eq 1 ] &&
   grep -q ":1" "$W/icloud/macA/snapshots/$a/Mackup/Library/Application Support/Beta/settings.json" &&
   grep -q changed "$W/icloud/mini/snapshots/$b/Mackup/Library/Application Support/Beta/settings.json"'
t "H12" "the machine folder falls back to the sanitised LocalHostName" \
  'W=$(newenv); APPS_ENV="DOTFILES_MACHINE_NAME=" run_apps backup && [ -d "$W/icloud/My-Mac-mini-local/snapshots" ]'
t "H13" "a fresh lock refuses a concurrent run" \
  'W=$(newenv); mkdir -p "$(lock_dir)"; refused "lock" backup && [ "$(nsnaps)" -eq 0 ]'
t "H14" "a lock older than an hour is stale and is taken over" \
  'W=$(newenv); mkdir -p "$(lock_dir)"; touch -t 202001010000 "$(lock_dir)"
   run_apps backup && [ "$(nsnaps)" -eq 1 ]'
t "H15" "the lock is released after success and after failure" \
  'W=$(newenv); run_apps backup && [ ! -e "$(lock_dir)" ] &&
   printf "garbage\n" >"$W/home/Library/Preferences/com.example.alpha.plist"; run_apps backup; [ ! -e "$(lock_dir)" ]'
t "H16" "no temp snapshot is left behind after a successful backup" \
  'W=$(newenv); run_apps backup && [ "$(ls -A "$W/icloud/macA/snapshots" | grep -c "^[.]tmp")" -eq 0 ]'
t "H17" "a backup with nothing to back up refuses instead of publishing an empty snapshot" \
  'W=$(newenv); wipe "$W/home/Library/Preferences/com.example.alpha.plist" "$W/home/Library/Application Support/Beta"
   refused "nothing to back up" backup && [ "$(nsnaps)" -eq 0 ]'
t "H18" "staging is cleared between runs: a file deleted locally leaves the next snapshot" \
  'W=$(newenv); run_apps backup && wipe "$W/home/Library/Application Support/Beta" && sleep 1 && run_apps backup &&
   n=$(latest_of) && [ ! -e "$W/icloud/macA/snapshots/$n/Mackup/Library/Application Support/Beta" ]'
t "H19" "backup refuses on an overlap and publishes nothing" \
  'W=$(newenv); add_app "$W" zshapp ".zshrc"; set_allow "$W" alpha zshapp
   refused OVERLAP backup && [ "$(nsnaps)" -eq 0 ]'
t "H20" "without iCloud Drive (default store) backup refuses and creates nothing" \
  'W=$(newenv); APPS_ENV="DOTFILES_APPS_STORE=" refused "iCloud Drive is not" backup &&
   [ ! -e "$W/home/Library/Mobile Documents" ]'
t "H21" "--scheduled prints nothing on success and logs to ~/Library/Logs/dotfiles-apps.log" \
  'W=$(newenv); out=$(run_apps backup --scheduled 2>&1); rc=$?
   [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -s "$W/home/Library/Logs/dotfiles-apps.log" ] && [ "$(nsnaps)" -eq 1 ]'
t "H22" "--scheduled failure is logged and exits non-zero" \
  'W=$(newenv); printf "garbage\n" >"$W/home/Library/Preferences/com.example.alpha.plist"
   out=$(run_apps backup --scheduled 2>&1); rc=$?
   [ "$rc" -ne 0 ] && grep -q "com.example.alpha.plist" "$W/home/Library/Logs/dotfiles-apps.log"'
t "H23" "the wrapper checks plists with plutil -lint" \
  'W=$(newenv); run_apps backup && grep -q "^plutil -lint" "$W/log"'

# The real plutil -lint accepts a file holding just the word "garbage": it
# parses as an old-style ASCII plist string. STUB_PLUTIL_LAX mimics that.
t "H25" "text that plutil -lint accepts but that is not an XML or binary plist is refused" \
  'W=$(newenv); printf "garbage\n" >"$W/home/Library/Preferences/com.example.alpha.plist"
   APPS_ENV="STUB_PLUTIL_LAX=1" refused "com.example.alpha.plist" backup && [ "$(nsnaps)" -eq 0 ]'
t "H26" "the same refusal with the real plutil (skipped, visibly, when it is not installed)" \
  '[ "$HAVE_PLUTIL" -eq 0 ] || {
   W=$(newenv); command rm -f "$W/stubs/plutil"; printf "garbage\n" >"$W/home/Library/Preferences/com.example.alpha.plist"
   refused "com.example.alpha.plist" backup && [ "$(nsnaps)" -eq 0 ]; }'
t "H24" "a failed copy into the store publishes nothing and keeps latest" \
  'W=$(newenv); run_apps backup && before=$(latest_of) && chmod 555 "$W/icloud/macA/snapshots"
   refused "nothing was published" backup; rc=$?; chmod 755 "$W/icloud/macA/snapshots"
   [ "$rc" -eq 0 ] && [ "$(latest_of)" = "$before" ] && [ "$(nsnaps)" -eq 1 ]'

#############################################################################
section "S -- never symlink mode (6.5)"
#############################################################################
t "S1" "backup refuses when a covered path is a symlink into the storage folder" \
  'W=$(newenv); ln -sf "$W/icloud/Mackup/Library/Preferences/com.example.alpha.plist" "$W/home/Library/Preferences/com.example.alpha.plist.new" &&
   mv "$W/home/Library/Preferences/com.example.alpha.plist.new" "$W/home/Library/Preferences/com.example.alpha.plist"
   out=$(run_apps backup 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "symlink" && printf "%s\n" "$out" | grep -q "com.example.alpha.plist" && [ "$(nsnaps)" -eq 0 ]'
t "S2" "the refusal happens before mackup is asked to copy anything" \
  'W=$(newenv); ln -sf "$W/icloud/Mackup/x" "$W/home/Library/Preferences/com.example.alpha.plist.new" &&
   mv "$W/home/Library/Preferences/com.example.alpha.plist.new" "$W/home/Library/Preferences/com.example.alpha.plist"
   refused symlink backup && [ "$(grep -c " backup\$\| restore\$" "$W/log" 2>/dev/null)" -eq 0 ]'
t "S3" "a symlink inside a covered directory pointing into storage is refused too" \
  'W=$(newenv); ln -s "$W/icloud/Mackup/y" "$W/home/Library/Application Support/Beta/link"
   refused symlink backup'
t "S4" "a symlink elsewhere (not into storage) does not trip the guard" \
  'W=$(newenv); printf "x\n" >"$W/other"; ln -s "$W/other" "$W/home/Library/Application Support/Beta/ok"
   run_apps backup'
t "S5" "the refusal tells how to fix it" \
  'W=$(newenv); ln -sf "$W/icloud/Mackup/x" "$W/home/Library/Preferences/com.example.alpha.plist.new" &&
   mv "$W/home/Library/Preferences/com.example.alpha.plist.new" "$W/home/Library/Preferences/com.example.alpha.plist"
   out=$(run_apps backup 2>&1); printf "%s\n" "$out" | grep -qi "cp -R"'
t "S6" "the wrapper never calls mackup link (code)" \
  '[ "$(code_of bin/dotfiles-apps | grep -cE "run_mackup +link|mackup .* link")" -eq 0 ]'

#############################################################################
section "R -- restore: download, verify, rescue, apply, flush (6.4)"
#############################################################################
PLIST_THIRD='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><string>third</string></dict></plist>'
PLIST_ALT='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><string>changed</string></dict></plist>'
alpha_plist() { printf '%s' "$W/home/Library/Preferences/com.example.alpha.plist"; }
chg() { printf '%s\n' "${1:-$PLIST_ALT}" >"$(alpha_plist)"; }
rescue_dirs() { local d; for d in "$W/home/.local/state/dotfiles/mackup/Mackup/rescue"/[0-9]*; do [ -e "$d" ] && printf '%s\n' "$d"; done; }
mackup_calls() { grep -c " $1\$" "$W/log"; }

t "R1" "restore puts the snapshot back, then flushes cfprefsd after mackup restore" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && chg && run_apps restore &&
   [ "$(command cat "$(alpha_plist)")" = "$orig" ] &&
   [ "$(_first_line "killall cfprefsd" "$W/log")" -gt "$(_first_line " restore" "$W/log")" ] &&
   [ "$(_first_line " restore" "$W/log")" -gt 0 ]'
t "R2" "restore names its snapshot: an older one can be chosen explicitly" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && first=$(latest_of) &&
   chg && run_apps backup && [ "$(latest_of)" != "$first" ] && chg "$PLIST_THIRD" &&
   run_apps restore "$first" && [ "$(command cat "$(alpha_plist)")" = "$orig" ]'
t "R3" "a placeholder blocks restore, brctl download was asked for, and nothing local changed" \
  'W=$(newenv); run_apps backup && n=$(latest_of) && : >"$W/icloud/macA/snapshots/$n/Mackup/.settings.json.icloud" && chg &&
   refused "placeholder" restore && [ "$(command cat "$(alpha_plist)")" = "$PLIST_ALT" ] &&
   grep -q "^brctl download $W/icloud/macA/snapshots/$n\$" "$W/log" && [ "$(mackup_calls restore)" -eq 0 ]'
t "R4" "once iCloud has materialised the files (brctl download) restore goes ahead" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && n=$(latest_of) &&
   : >"$W/icloud/macA/snapshots/$n/Mackup/.settings.json.icloud" && chg &&
   APPS_ENV="STUB_BRCTL_MATERIALIZE=1" run_apps restore && [ "$(command cat "$(alpha_plist)")" = "$orig" ]'
t "R5" "a running allowlisted app blocks restore and is named; nothing changes" \
  'W=$(newenv); run_apps backup && chg && printf "alphaProc\n" >"$W/running" &&
   out=$(run_apps restore 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "alpha" && printf "%s\n" "$out" | grep -qi "quit" &&
   [ "$(command cat "$(alpha_plist)")" = "$PLIST_ALT" ] && [ "$(mackup_calls restore)" -eq 0 ] && ! grep -q "^killall" "$W/log"'
t "R6" "the running check uses pgrep -x on the mapped process name" \
  'W=$(newenv); run_apps backup && run_apps restore && grep -q "^pgrep -x alphaProc\$" "$W/log" && grep -q "^pgrep -x betaProc\$" "$W/log"'
t "R7" "the rescue copy holds the pre-restore files, locally, never in iCloud" \
  'W=$(newenv); run_apps backup && chg && run_apps restore && d=$(rescue_dirs | tail -n 1) && [ -n "$d" ] &&
   [ "$(command cat "$d/Mackup/Library/Preferences/com.example.alpha.plist")" = "$PLIST_ALT" ] &&
   [ "$(find "$W/icloud" -name "rescue*" | wc -l | tr -d " ")" -eq 0 ]'
t "R8" "undo puts the pre-restore files back" \
  'W=$(newenv); run_apps backup && chg && run_apps restore && run_apps undo &&
   [ "$(command cat "$(alpha_plist)")" = "$PLIST_ALT" ]'
t "R9" "undo takes its own rescue copy, so a second undo toggles back" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && chg && run_apps restore && run_apps undo && run_apps undo &&
   [ "$(command cat "$(alpha_plist)")" = "$orig" ]'
t "R10" "undo with no rescue copy refuses" \
  'W=$(newenv); refused "no rescue" undo'
t "R11" "restore --from pulls the other Mac deliberately; default stays on this Mac" \
  'W=$(newenv); printf "%s\n" "$PLIST_ALT" >"$(alpha_plist)"; APPS_ENV="DOTFILES_MACHINE_NAME=mini" run_apps backup &&
   chg "$PLIST_OK" && refused "no snapshots for" restore && run_apps restore --from mini &&
   [ "$(command cat "$(alpha_plist)")" = "$PLIST_ALT" ]'
t "R12" "a snapshot or machine name that could escape the store is refused" \
  'W=$(newenv); run_apps backup && refused "invalid snapshot" restore "../x" && refused "invalid machine" restore --from "../etc"'
t "R13" "an unknown snapshot is refused" \
  'W=$(newenv); run_apps backup && refused "no such snapshot" restore 20200101T000000Z'
t "R14" "an invalid plist in the snapshot blocks restore and local files stay" \
  'W=$(newenv); run_apps backup && n=$(latest_of) && printf "garbage\n" >"$W/icloud/macA/snapshots/$n/Mackup/Library/Preferences/com.example.alpha.plist" && chg &&
   refused "not a valid plist" restore && [ "$(command cat "$(alpha_plist)")" = "$PLIST_ALT" ] && [ "$(mackup_calls restore)" -eq 0 ]'
t "R15" "a symlink inside the snapshot blocks restore" \
  'W=$(newenv); run_apps backup && n=$(latest_of) && ln -s /etc/hosts "$W/icloud/macA/snapshots/$n/Mackup/planted" &&
   refused "symlink" restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "R16" "a restored path that ends up a symlink is reported, pointing at undo" \
  'W=$(newenv); run_apps backup && out=$(APPS_ENV="STUB_RESTORE_LINK=1" run_apps restore 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "symlink" && printf "%s\n" "$out" | grep -q "undo"'
t "R17" "restore refuses on an overlap" \
  'W=$(newenv); run_apps backup && add_app "$W" zshapp ".zshrc" && set_allow "$W" alpha zshapp &&
   refused OVERLAP restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "R18" "restore refuses when a covered path is a symlink into the storage folder" \
  'W=$(newenv); run_apps backup && ln -sf "$W/icloud/Mackup/x" "$W/home/Library/Preferences/com.example.alpha.plist.new" &&
   mv "$W/home/Library/Preferences/com.example.alpha.plist.new" "$(alpha_plist)" && refused symlink restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "R19" "restore takes the lock too" \
  'W=$(newenv); run_apps backup && mkdir -p "$(lock_dir)" && refused "lock" restore'
t "R20" "on a fresh Mac (nothing local yet) restore works and needs no rescue copy" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && wipe "$W/home/Library/Preferences/com.example.alpha.plist" "$W/home/Library/Application Support/Beta" &&
   run_apps restore && [ "$(command cat "$(alpha_plist)")" = "$orig" ] && [ -f "$W/home/Library/Application Support/Beta/settings.json" ]'
t "R21" "restore without iCloud Drive refuses" \
  'W=$(newenv); APPS_ENV="DOTFILES_APPS_STORE=" refused "iCloud Drive is not" restore'
t "R26" "a corrupt local plist does not block restore: it is rescued as it is, then replaced" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && printf "garbage\n" >"$(alpha_plist)" &&
   run_apps restore && [ "$(command cat "$(alpha_plist)")" = "$orig" ] &&
   d=$(rescue_dirs | tail -n 1) && [ "$(command cat "$d/Mackup/Library/Preferences/com.example.alpha.plist")" = "garbage" ]'
t "R27" "a zero-byte local plist does not block restore either" \
  'W=$(newenv); orig=$(command cat "$(alpha_plist)"); run_apps backup && : >"$(alpha_plist)" && run_apps restore && [ "$(command cat "$(alpha_plist)")" = "$orig" ]'
t "R28" "undo puts back a rescued corrupt file too (the user's own bytes)" \
  'W=$(newenv); run_apps backup && printf "garbage\n" >"$(alpha_plist)" && run_apps restore && run_apps undo &&
   [ "$(command cat "$(alpha_plist)")" = "garbage" ]'
t "R25" "a store folder that does not exist is refused and not created" \
  'W=$(newenv); APPS_ENV="DOTFILES_APPS_STORE=$W/nowhere" refused "nothing to restore from" restore && [ ! -e "$W/nowhere" ]'
t "R22" "a restore never publishes anything into the store" \
  'W=$(newenv); run_apps backup && before=$(find "$W/icloud" | wc -l | tr -d " ") && chg && run_apps restore && [ "$(find "$W/icloud" | wc -l | tr -d " ")" -eq "$before" ]'
t "R23" "list shows every machine and marks the latest snapshot" \
  'W=$(newenv); run_apps backup && APPS_ENV="DOTFILES_MACHINE_NAME=mini" run_apps backup && out=$(run_apps list 2>&1) &&
   printf "%s\n" "$out" | grep -q "macA" && printf "%s\n" "$out" | grep -q "mini" && printf "%s\n" "$out" | grep -q "$(latest_of macA).*latest"'
t "R24" "restore never calls mackup link and passes -c" \
  'W=$(newenv); run_apps backup && run_apps restore && [ "$(grep -c "link" "$W/log")" -eq 0 ] && grep -q "^-c .* -f restore\$" "$W/log"'

#############################################################################
section "F -- fix round 1: guard fails closed, legacy store, manifest, flush"
#############################################################################
# mkdf <W> <empty>: a DOTFILES_DIR fixture whose runcom/config/macos are the
# real ones except the named one, which is an empty directory.
mkdf() {
  local w="$1" x d
  mkdir -p "$w/df/apps"
  for d in gitkraken terminal vlc vscode warp xcode; do mkdir -p "$w/df/apps/$d"; done
  for x in runcom config macos claude codex; do
    if [ "$x" = "$2" ]; then mkdir -p "$w/df/$x"; else ln -s "$ROOT_DIR/$x" "$w/df/$x"; fi
  done
}
t "F1" "check fails when dotfiles-baseline exits non-zero" \
  'W=$(newenv); printf "#!/bin/sh\necho boom >&2\nexit 1\n" >"$W/badbase"; chmod +x "$W/badbase"
   APPS_ENV="DOTFILES_APPS_BASELINE=$W/badbase" refused "baseline failed" check'
t "F2" "check fails when dotfiles-baseline yields no domains" \
  'W=$(newenv); printf "#!/bin/sh\nexit 0\n" >"$W/emptybase"; chmod +x "$W/emptybase"
   APPS_ENV="DOTFILES_APPS_BASELINE=$W/emptybase" refused "no defaults domains" check'
t "F3" "check fails with an empty macos/ (real baseline finds nothing)" \
  'W=$(newenv); mkdf "$W" macos; APPS_DF="$W/df" refused "defaults domains" check'
t "F4" "check fails when runcom/ owns nothing" \
  'W=$(newenv); mkdf "$W" runcom; APPS_DF="$W/df" refused "runcom" check'
t "F5" "check fails when config/ owns nothing" \
  'W=$(newenv); mkdf "$W" config; APPS_DF="$W/df" refused "config" check'
t "F5b" "control: the fixture with nothing emptied passes" \
  'W=$(newenv); mkdf "$W" none; APPS_DF="$W/df" run_apps check'
t "F5c" "backup is gated by the same failure (no snapshot)" \
  'W=$(newenv); mkdf "$W" macos; APPS_DF="$W/df" refused "defaults domains" backup && [ "$(nsnaps)" -eq 0 ]'

legacy() { mkdir -p "$W/icloud/.gitkraken" "$W/icloud/.gnupg" "$W/icloud/.ngrok" "$W/icloud/Library/Preferences" "$W/icloud/bad name/snapshots/20200101T000000Z"; printf x >"$W/icloud/Library/Preferences/a"; }
t "F6" "list ignores legacy Mackup/ entries and non-machine names" \
  'W=$(newenv); legacy; run_apps backup && out=$(run_apps list 2>&1) && printf "%s\n" "$out" | grep -q "^macA" &&
   [ "$(printf "%s\n" "$out" | grep -c "Library\|gitkraken\|gnupg\|ngrok\|bad")" -eq 0 ]'
t "F7" "restore --from a legacy folder is refused" \
  'W=$(newenv); legacy; run_apps backup && refused "no snapshots for" restore --from Library'
t "F8" "restore --from a folder name outside [A-Za-z0-9-] is refused" \
  'W=$(newenv); legacy; refused "invalid machine" restore --from "bad name"'
t "F9" "legacy entries are never modified by backup, restore or list" \
  'W=$(newenv); legacy; before=$(cd "$W/icloud" && find .gitkraken .gnupg .ngrok Library "bad name" | sort; find .gitkraken .gnupg .ngrok Library "bad name" -type f -exec cksum {} +)
   run_apps backup && run_apps list && run_apps restore && after=$(cd "$W/icloud" && find .gitkraken .gnupg .ngrok Library "bad name" | sort; find .gitkraken .gnupg .ngrok Library "bad name" -type f -exec cksum {} +) && [ "$before" = "$after" ]'

snapdir() { printf '%s' "$W/icloud/macA/snapshots/$(latest_of)"; }
t "F10" "backup writes a MANIFEST with sha256, size and path for every staged file" \
  'W=$(newenv); run_apps backup && m="$(snapdir)/MANIFEST" && [ -f "$m" ] &&
   [ "$(grep -c . "$m")" -eq 2 ] && grep -q "Library/Preferences/com.example.alpha.plist" "$m" &&
   h=$(shasum -a 256 "$W/home/Library/Preferences/com.example.alpha.plist" | cut -d" " -f1) && grep -q "^$h" "$m"'
t "F11" "restore refuses a file whose size differs (dataless or truncated), listing it" \
  'W=$(newenv); run_apps backup && chg2() { printf "x" >"$(snapdir)/Mackup/Library/Application Support/Beta/settings.json"; }; chg2
   out=$(run_apps restore 2>&1); rc=$?
   [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "settings.json" && printf "%s\n" "$out" | grep -qi "manifest" && [ "$(mackup_calls restore)" -eq 0 ]'
t "F12" "restore refuses a file with the same size but a different hash" \
  'W=$(newenv); run_apps backup && printf "{\"a\":2}\n" >"$(snapdir)/Mackup/Library/Application Support/Beta/settings.json"
   refused "settings.json" restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "F13" "restore refuses a file missing from the snapshot" \
  'W=$(newenv); run_apps backup && wipe "$(snapdir)/Mackup/Library/Application Support/Beta/settings.json"
   refused "is missing from the snapshot" restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "F14" "a snapshot without a MANIFEST is refused" \
  'W=$(newenv); run_apps backup && wipe "$(snapdir)/MANIFEST" && refused "no MANIFEST" restore && [ "$(mackup_calls restore)" -eq 0 ]'
t "F15" "the manifest is verified against the copy before the snapshot is renamed into place" \
  'W=$(newenv); printf "#!/bin/sh\nfor a in \"\$@\"; do case \"\$a\" in *.tmp-*) echo 0000 x; exit 0 ;; esac; done\nexec /usr/bin/shasum \"\$@\"\n" >"$W/stubs/shasum"; chmod +x "$W/stubs/shasum"
   refused "nothing was published" backup && [ "$(nsnaps)" -eq 0 ]'
t "F16" "undo verifies the rescue copy's manifest too" \
  'W=$(newenv); run_apps backup && chg && run_apps restore && d=$(rescue_dirs | tail -n 1) && wipe "$d/MANIFEST" && refused "no MANIFEST" undo'
t "F17" "a failed mackup restore still flushes cfprefsd and points at undo" \
  'W=$(newenv); run_apps backup && out=$(APPS_ENV="STUB_RESTORE_FAIL=1" run_apps restore 2>&1); rc=$?
   [ "$rc" -ne 0 ] && grep -q "^killall cfprefsd" "$W/log" && printf "%s\n" "$out" | grep -q "undo" && printf "%s\n" "$out" | grep -qi "cfprefsd"'
t "F18" "a refused post-restore symlink check still flushes cfprefsd" \
  'W=$(newenv); run_apps backup && APPS_ENV="STUB_RESTORE_LINK=1" run_apps restore; grep -q "^killall cfprefsd" "$W/log"'
t "F19" "a refusal before anything was touched does not flush" \
  'W=$(newenv); run_apps backup && printf "alphaProc\n" >"$W/running"; run_apps restore; [ "$(grep -c "^killall" "$W/log")" -eq 0 ]'

#############################################################################
section "C -- CLI routing, install flow and docs (6.6, 6.7)"
#############################################################################
t "C1" "dotfiles help lists the apps command" \
  'out=$(bash bin/dotfiles help 2>&1); printf "%s\n" "$out" | grep -q "^   apps  .*mackup"'
t "C2" "dotfiles apps passes straight through to bin/dotfiles-apps" \
  'W=$(sandbox); mkdir -p "$W/h"; out=$(HOME="$W/h" bash bin/dotfiles apps bogus 2>&1); rc=$?
   [ "$rc" -eq 2 ] && printf "%s\n" "$out" | grep -q "dotfiles-apps: unknown command"'
t "C3" "the routing line and function exist" \
  'grep -q "\"apps\")" <(code_of bin/dotfiles) && grep -q "^sub_apps()" <(code_of bin/dotfiles)'
t "C4" "install --all does not back up or restore app settings (restore is deliberate)" \
  'body=$(sed -n "/^sub_install_all()/,/^}/p" <(code_of bin/dotfiles)); [ "$(printf "%s\n" "$body" | grep -c "apps")" -eq 0 ]'
t "C5" "the install summary points at apps restore" \
  'body=$(sed -n "/^sub_install()/,/^}/p" <(code_of bin/dotfiles)); printf "%s\n" "$body" | grep -q "apps restore"'
t "C6" "the daily agent is a top-level plist (installed by --launchagents), the old hourly one is gone" \
  '[ -f launchagents/com.stixzoor.dotfiles-apps-backup.plist ] && [ ! -e launchagents/disabled/com.stixzoor.mackup-auto.plist ]'
t "C7" "docs: app-settings.md exists and is in the AGENTS.md table" \
  '[ -f docs/agents/app-settings.md ] && grep -q "app-settings.md" AGENTS.md'
t "C8" "docs describe restore, undo and the ownership rule" \
  '(for w in "dotfiles apps restore" "dotfiles apps undo" "ownership rule" "copy mode" "never .mackup link."; do grep -qi -- "$w" docs/agents/app-settings.md || exit 1; done)'
t "C9" "the README no longer promises an hourly mackup backup" \
  '[ "$(grep -c "mackup auto-backup every hour" README.md)" -eq 0 ] && grep -q "dotfiles apps" README.md'
t "C10" "no tracked mackup config remains at runcom/.mackup.cfg" \
  '[ ! -e runcom/.mackup.cfg ]'
t "C11" "the wrapper sets its own PATH for launchd (/opt/homebrew/bin first)" \
  'code_of bin/dotfiles-apps | grep -q "PATH=\"/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH\""'
t "C12" "minimal PATH (as under launchd) still finds mackup when installed (skipped, visibly, when not installed)" \
  '[ "$HAVE_MACKUP" -eq 0 ] || {
   W=$(sandbox); mkdir -p "$W/home/.config/mackup"; cp -R config/mackup/applications "$W/home/.config/mackup/applications"
   env -i HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" PATH="/usr/bin:/bin:/usr/sbin:/sbin" DOTFILES_DIR="$ROOT_DIR" \
     DOTFILES_APPS_STORE="$W/icloud" bash "$APPS" check; }'

finish

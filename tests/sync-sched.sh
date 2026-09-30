#!/usr/bin/env bash
#
# tests/sync-sched.sh -- dotfiles sync scheduled runs, drift listing (S5-S7) and the sync agent plist (A).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

t "S5.1" "scheduled: never sudo, never mise, never brew bundle or install, never dotfiles install" '
  W=$(senv); _actions "$W"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^sudo")" -eq 0 ] && [ "$(_calls "^mise")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ] &&
  [ "$(grep "^brew" "$W/log" | grep -vc "^brew leaves\|^brew list --cask")" -eq 0 ]'
t "S5.2" "scheduled: exactly one notification, naming the pending actions" '
  W=$(senv); _actions "$W"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "display notification" && grep "^osascript" "$W/log" | grep -q "pending"'
t "S5.3" "scheduled: prints nothing and logs to ~/Library/Logs/dotfiles-sync.log" '
  W=$(senv); _actions "$W"; out=$(syn --scheduled 2>&1); [ -z "$out" ] &&
  grep -q "dotfiles sync (scheduled)" "$W/home/Library/Logs/dotfiles-sync.log" && grep -q "pending: mise install" "$W/home/Library/Logs/dotfiles-sync.log"'
t "S5.4" "scheduled with nothing to do: no notification, but a log entry" '
  W=$(senv); syn --scheduled >/dev/null 2>&1; [ "$(_calls "^osascript")" -eq 0 ] && [ -s "$W/home/Library/Logs/dotfiles-sync.log" ]'
t "S5.5" "scheduled: unpushed commits notify once" '
  W=$(senv); printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  syn --scheduled >/dev/null 2>&1; [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "unpushed"'
t "S5.6" "scheduled: divergence notifies" '
  W=$(senv); push_change "$W" pub README.md new; printf "l\n" >"$W/pub/local.txt"; git -C "$W/pub" add -A; git -C "$W/pub" commit -q -m l
  syn --scheduled >/dev/null 2>&1; grep "^osascript" "$W/log" | grep -q "diverged"'
t "S5.7" "scheduled and offline: no notification, exit 0" '
  W=$(senv); command mv "$W/pub.git" "$W/gone.git"; syn --scheduled >/dev/null 2>&1; rc=$?; [ "$rc" -eq 0 ] && [ "$(_calls "^osascript")" -eq 0 ]'
t "S5.8" "scheduled still fast-forwards and restows" \
  'W=$(senv); push_change "$W" pub README.md new; syn --scheduled >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ] && [ "$(_calls "^stow --restow")" -eq 2 ]'
t "S5.9" "pending actions survive to the next scheduled run, until an interactive run does them" '
  W=$(senv); push_change "$W" pub config/mise/config.toml "[tools]
node = \"1\""
  syn --scheduled >/dev/null 2>&1; : >"$W/log"
  syn --scheduled >/dev/null 2>&1; a=$(_calls "^osascript")
  sy_env "DOTFILES_YES=1" syn >/dev/null 2>&1; : >"$W/log"
  syn --scheduled >/dev/null 2>&1; [ "$a" -eq 1 ] && [ "$(_calls "^osascript")" -eq 0 ]'
t "S5.10" "scheduled never waits at a git or ssh prompt" \
  '[ "$(code_of bin/dotfiles-sync | grep -c "GIT_TERMINAL_PROMPT=0")" -ge 1 ] && [ "$(code_of bin/dotfiles-sync | grep -c "BatchMode=yes")" -ge 1 ]'
t "S5.12" "the fetches use an ssh that accepts a first-seen host key (scheduled adds BatchMode)" '
  W=$(senv); stub "$W/bin" git '"'"'echo "GSC=${GIT_SSH_COMMAND:-}" >>"$STUB_LOG"; exec /usr/bin/git "$@"'"'"'
  syn >/dev/null 2>&1; a=$(grep "^GSC=" "$W/log" | grep -c "StrictHostKeyChecking=accept-new"); : >"$W/log"
  syn --scheduled >/dev/null 2>&1; b=$(grep "^GSC=" "$W/log" | grep -c "StrictHostKeyChecking=accept-new.*BatchMode=yes")
  [ "$a" -ge 2 ] && [ "$b" -ge 2 ]'
t "S5.11" "scheduled sets its own PATH: Homebrew when brew is not resolvable, then the mise shims" \
  '[ "$(code_of bin/dotfiles-sync | grep -c "/opt/homebrew/bin")" -ge 1 ] && [ "$(code_of bin/dotfiles-sync | grep -c "mise/shims")" -ge 1 ]'

t "S6.1" "drift lists an undeclared brew leaf with the line to add, and not the declared ones" '
  W=$(senv); printf "wget\nfzf\njq\n" >"$W/state/leaves"; out=$(syn 2>&1)
  printf "%s\n" "$out" | grep -qF "brew \"jq\"" && [ "$(printf "%s\n" "$out" | grep -cF "brew \"wget\"")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -cF "brew \"fzf\"")" -eq 0 ]'
t "S6.2" "drift lists undeclared casks, App Store apps and VS Code extensions" '
  W=$(senv); printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  printf "ms-python.python\nFoo.Bar\n" >"$W/state/vscode"; out=$(syn 2>&1)
  printf "%s\n" "$out" | grep -qF "cask \"slack\"" && printf "%s\n" "$out" | grep -qF "mas \"Amphetamine\", id: 111" &&
  printf "%s\n" "$out" | grep -qF "Foo.Bar" && [ "$(printf "%s\n" "$out" | grep -cF "Xcode")" -eq 0 ]'
t "S6.3" "a tap formula is matched by its short name" '
  W=$(senv); printf "wget\nsomeone/tap/fzf\n" >"$W/state/leaves"; out=$(syn 2>&1); [ "$(printf "%s\n" "$out" | grep -cF "fzf")" -eq 0 ]'
t "S6.4" "nothing undeclared: none" \
  'W=$(senv); out=$(syn 2>&1); printf "%s\n" "$out" | grep -A1 "^== drift" | grep -q "none"'
t "S6.5" "scheduled: drift notifies once" '
  W=$(senv); printf "wget\nfzf\njq\n" >"$W/state/leaves"; syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "declared nowhere"'
t "S6.6" "the extra Brewfile.local entries count as declared" \
  'W=$(senv); printf "fzf\n" >"$W/state/leaves"; out=$(syn 2>&1); [ "$(printf "%s\n" "$out" | grep -cF "brew \"fzf\"")" -eq 0 ]'
t "S7.1" "an unknown argument is a usage error" \
  'W=$(senv); out=$(syn --frobnicate 2>&1); rc=$?; [ "$rc" -eq 2 ] && printf "%s\n" "$out" | grep -q "Usage"'

#############################################################################
section "A -- the daily sync agent (launchagents/com.stixzoor.dotfiles-sync.plist)"
#############################################################################
PLIST=launchagents/com.stixzoor.dotfiles-sync.plist
t "A1.1" "the agent is a top-level plist, so install --launchagents loads it" \
  '[ -f "$PLIST" ] && [ "$(dirname "$PLIST")" = launchagents ]'
t "A1.2" "the plist is valid and its label matches the file name" \
  '{ ! command -v plutil >/dev/null 2>&1 || plutil -lint "$PLIST" >/dev/null; } &&
   grep -A1 "<key>Label</key>" "$PLIST" | grep -q "<string>com.stixzoor.dotfiles-sync</string>"'
t "A1.3" "it runs dotfiles-sync --scheduled through bash -c" \
  'body=$(command cat "$PLIST"); printf "%s\n" "$body" | grep -qF "exec \"\$HOME/.dotfiles/bin/dotfiles-sync\" --scheduled" &&
   printf "%s\n" "$body" | grep -A1 "<key>ProgramArguments</key>" | grep -q "<array>" && printf "%s\n" "$body" | grep -q "<string>/bin/bash</string>"'
t "A1.4" "daily at 09:30, not at load, background priority" \
  'body=$(command cat "$PLIST")
   printf "%s\n" "$body" | grep -A1 "<key>Hour</key>" | grep -q "<integer>9</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>Minute</key>" | grep -q "<integer>30</integer>" &&
   printf "%s\n" "$body" | grep -A1 "<key>RunAtLoad</key>" | grep -q "<false/>" &&
   printf "%s\n" "$body" | grep -A1 "<key>ProcessType</key>" | grep -q "<string>Background</string>"'
t "A1.5" "no StandardOutPath or StandardErrorPath (the script logs itself under ~/Library/Logs)" \
  '[ "$(grep -c "<key>Standard\(Out\|Error\)Path</key>" "$PLIST")" -eq 0 ] && grep -q "Library/Logs" bin/dotfiles-sync'
t "A1.6" "the plist carries no absolute home path" \
  '[ "$(grep -c "/Users/" "$PLIST")" -eq 0 ]'

t "S8.1" "scheduled: the vault is not scanned (no scan-vault call, no vault notification), a token in it is ignored" '
  W=$(senv); d=$(vault_of "$W"); tok="ghp_$(rand_chars 36 A-Za-z0-9)"
  printf "export GH_TOKEN=%s\n" "$tok" >"$d/session-1.md"; jevstub "$W" 1 "FOUND session-1.md:1: a credential"
  SYNENV="$(JEVSTUB_ENV "$W")" syn --scheduled >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub scan-")" -eq 0 ] && [ "$(_calls "^osascript")" -eq 0 ] &&
  [ ! -e "$W/home/.local/state/dotfiles/vault-scan-last" ]'

finish

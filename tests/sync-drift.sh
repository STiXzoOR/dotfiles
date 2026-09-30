#!/usr/bin/env bash
#
# tests/sync-drift.sh -- Jev drift classification of undeclared packages (D1, D2).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

#############################################################################
section "D -- Task 13: drift that notices itself (Jev classifies the undeclared)"
#############################################################################

t "D1.1" "an undeclared formula goes to Jev as one fact line: name, description, dependency, first-seen date" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1
  f=$(_facts pkg); today=$(date +%Y-%m-%d)
  [ "$(printf "%s\n" "$f" | grep -c "^brew:jq	")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "description=Description of jq")" -eq 1 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "dependency=no")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "first seen $today")" -eq 1 ]'
t "D1.2" "formulae, casks and App Store apps are one batched request, not one each" '
  W=$(senv); dstub "$W"; _undeclared; printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  dsyn >/dev/null 2>&1; f=$(_facts pkg)
  [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 3 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^cask:slack	")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c "^mas:111	.*Amphetamine")" -eq 1 ]'
t "D1.3" "a formula another installed formula needs is marked as a dependency" '
  W=$(senv); dstub "$W"; _undeclared; printf "ffmpeg\n" >"$W/state/uses-jq"; dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "dependency=yes")" -eq 1 ]'
t "D1.4" "the first-seen date is remembered: an item seen earlier keeps its old date" '
  W=$(senv); dstub "$W"; _undeclared; mkdir -p "$W/home/.local/state/dotfiles"
  printf "brew:jq\t2026-01-05\n" >"$W/home/.local/state/dotfiles/drift-first-seen"
  dsyn >/dev/null 2>&1; dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "first seen 2026-01-05")" -eq 1 ] && [ "$(grep -c "^brew:jq" "$W/home/.local/state/dotfiles/drift-first-seen")" -eq 1 ]'
t "D1.9" "a first sighting is recorded with today's date, once, for the next run" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1; dsyn >/dev/null 2>&1
  [ "$(grep -c "^brew:jq$(printf "\t")$(date +%Y-%m-%d)$" "$W/home/.local/state/dotfiles/drift-first-seen")" -eq 1 ]'
t "D1.5" "nothing undeclared: Jev is not asked" '
  W=$(senv); dstub "$W"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 0 ]'
t "D1.6" "with Jev switched off (the master switch or the point) nothing is asked and no fact is gathered" '
  W=$(senv); dstub "$W"; _undeclared; DX="DOTFILES_JEV=off" dsyn >/dev/null 2>&1; a=$(_calls "^dotfiles-jev-stub drift")
  W2=$(senv); W=$W2; dstub "$W" off; _undeclared; dsyn >/dev/null 2>&1
  [ "$a" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub drift")" -eq 0 ] && [ "$(_calls "^brew desc")" -eq 0 ]'
t "D1.7" "a Jev that fails changes nothing: the deterministic report is complete, and the exit status is 0" '
  W=$(senv); dstub "$W"; _undeclared; out=$(DX="JEVSTUB_RC=3" dsyn 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -qF "brew \"jq\"" && printf "%s\n" "$out" | grep -q "declared nowhere\|^== drift"'
t "D1.8" "on: interactive requests get 6 s; shadow keeps the 2 s default; scheduled ones mark JEV_SCHEDULED for the 10 s" '
  W=$(senv); dstub "$W"; _undeclared; dsyn >/dev/null 2>&1; a=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; dsyn --scheduled >/dev/null 2>&1; b=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; dstub "$W" shadow; dsyn >/dev/null 2>&1; c=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  [ "$a" = "JEV_SCHEDULED= JEV_TIMEOUT=6" ] && [ "$b" = "JEV_SCHEDULED=1 JEV_TIMEOUT=" ] && [ "$c" = "JEV_SCHEDULED= JEV_TIMEOUT=" ]'

t "D2.1" "on, confirmed: a public suggestion appends the exact line to the public Brewfile, and nothing is committed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; h=$(_head pub)
  DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile | tail -n 1)" = "brew \"jq\"" ] && [ "$(_lines pub/Brewfile.local | grep -c jq)" -eq 0 ] && [ "$(_head pub)" = "$h" ]'
t "D2.2" "a private suggestion goes to Brewfile.local, a cask and an App Store app as their own lines" '
  W=$(senv); dstub "$W"; _undeclared; printf "iterm2\nslack\n" >"$W/state/casks"; printf "497799835  Xcode  (16.0)\n111  Amphetamine  (5.0)\n" >"$W/state/mas"
  _suggest pkg brew:jq private; _suggest pkg cask:slack public; _suggest pkg mas:111 private
  DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile.local | grep -c "^brew \"jq\"$")" -eq 1 ] && [ "$(_lines pub/Brewfile | grep -c "^cask \"slack\"$")" -eq 1 ] &&
  [ "$(_lines pub/Brewfile.local | grep -c "^mas \"Amphetamine\", id: 111$")" -eq 1 ]'
t "D2.3" "interactive and not confirmed (no answer): the line is offered and nothing is written" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile"); out=$(dsyn 2>&1)
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && printf "%s\n" "$out" | grep -qF "Jev suggests public: brew \"jq\"      (add to Brewfile)"'
t "D2.4" "a private suggestion names Brewfile.local as the file" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq private
  out=$(dsyn 2>&1); printf "%s\n" "$out" | grep -qF "Jev suggests private: brew \"jq\"      (add to Brewfile.local)"'
t "D2.5" "an ignore suggestion is reported and writes nothing, even confirmed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq ignore; b=$(shasum "$W/pub/Brewfile" "$W/pub/Brewfile.local")
  out=$(DXY=1 dsyn 2>&1); [ "$(shasum "$W/pub/Brewfile" "$W/pub/Brewfile.local")" = "$b" ] && printf "%s\n" "$out" | grep -q "ignore"'
t "D2.6" "a remove suggestion prints the uninstall command and never runs it, even confirmed" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq remove; b=$(shasum "$W/pub/Brewfile")
  out=$(DXY=1 dsyn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "brew uninstall jq")" -ge 1 ] && [ "$(_calls "^brew uninstall")" -eq 0 ] && [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D2.7" "a suggestion for something that was not in the facts is ignored: Jev never invents a line" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg "brew:evil; touch $W/pwned" public; _suggest pkg brew:wget public
  b=$(shasum "$W/pub/Brewfile"); DXY=1 dsyn >/dev/null 2>&1
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ ! -e "$W/pwned" ]'
t "D2.8" "an item already declared by an earlier confirm is not appended twice" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; DXY=1 dsyn >/dev/null 2>&1
  DXY=1 dsyn >/dev/null 2>&1; [ "$(_lines pub/Brewfile | grep -c "^brew \"jq\"$")" -eq 1 ]'
t "D2.9" "shadow mode: Jev is asked, but even a SUGGEST line from it is not acted on" '
  W=$(senv); dstub "$W" shadow; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  out=$(DXY=1 dsyn 2>&1); [ "$(_calls "^dotfiles-jev-stub drift pkg")" -eq 1 ] && [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ "$(printf "%s\n" "$out" | grep -c "Add brew")" -eq 0 ]'
t "D2.10" "scheduled: no prompt, no write, and the single notification says Jev has suggestions" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  DXY=1 dsyn --scheduled >/dev/null 2>&1
  [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "Jev suggests"'

#############################################################################
section "D -- Setapp drift: /Applications/Setapp apps declared in no list"
#############################################################################

t "D2.1" "an app in the Setapp dir that no list names is reported with the line to add" '
  W=$(senv); mkdir -p "$W/setapp/Paste.app" "$W/setapp/Tripsy.app"; printf "Paste\n" >"$W/pub/packages/setapp.list"
  out=$(syn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -cF "Tripsy")" -ge 1 ] && printf "%s\n" "$out" | grep -F Tripsy | grep -qF "packages/setapp.list" &&
  [ "$(printf "%s\n" "$out" | grep -F "Paste" | grep -c "setapp.list")" -eq 0 ]'
t "D2.2" "setapp.local.list also declares an app, and names match case-insensitively" '
  W=$(senv); mkdir -p "$W/setapp/Tripsy.app" "$W/setapp/Paste.app"; printf "paste\n" >"$W/pub/packages/setapp.list"; printf "Tripsy\n" >"$W/pub/packages/setapp.local.list"
  out=$(syn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "add to packages/setapp")" -eq 0 ]'
t "D2.3" "no Setapp dir: nothing reported and no error" '
  W=$(senv); out=$(syn 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "packages/setapp")" -eq 0 ]'


finish

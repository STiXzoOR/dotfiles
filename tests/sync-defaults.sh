#!/usr/bin/env bash
#
# tests/sync-defaults.sh -- Jev drift for changed defaults, config dirs, unattended answers (D3-D6).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

t "D3.1" "changed defaults go to Jev as one batch: domain and key, old and new value, first-seen date" '
  W=$(senv); dstub "$W"; printf "com.example.a\tAlpha\t1\t0\ncom.example.a\tBeta\t5\t6\n" >"$W/state/changed"; dsyn >/dev/null 2>&1
  f=$(_facts defaults)
  [ "$(_calls "^dotfiles-jev-stub drift defaults")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 2 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^com.example.a Alpha	.*was 1.*now 0.*first seen $(date +%Y-%m-%d)")" -eq 1 ]'
t "D3.2" "no changed defaults: Jev is not asked" '
  W=$(senv); dstub "$W"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift defaults")" -eq 0 ]'
t "D3.3" "public: the defaults write line, typed by defaults read-type, is appended to macos/defaults.sh on confirm" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"
  _suggest defaults "com.example.a Alpha" public; DXY=1 dsyn >/dev/null 2>&1
  [ "$(_lines pub/macos/defaults.sh | tail -n 1)" = "defaults write com.example.a Alpha -bool false" ]'
t "D3.4" "local-only is printed for you to place by hand: nothing is written to macos/local.sh or machine.local.sh, even confirmed" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; printf "com.example.a\tBeta\t5\t6\n" >"$W/state/changed"; printf "integer" >"$W/state/deftype"
  _suggest defaults "com.example.a Beta" local-only; out=$(DXY=1 dsyn 2>&1)
  [ ! -e "$W/pub/macos/local.sh" ] && [ ! -e "$W/pub/macos/machine.local.sh" ] &&
  printf "%s\n" "$out" | grep -qF "Jev suggests local-only: defaults write com.example.a Beta -int 6" && printf "%s\n" "$out" | grep -q "place it by hand"'
t "D3.5" "a value that cannot be written safely (a string with a quote or a dollar) is shown, never appended" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tPath\told\t\$HOME/x\n" >"$W/state/changed"; printf "string" >"$W/state/deftype"
  _suggest defaults "com.example.a Path" public; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && printf "%s\n" "$out" | grep -q "by hand"'
t "D3.6" "transient is reported and writes nothing" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"
  _suggest defaults "com.example.a Alpha" transient; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && printf "%s\n" "$out" | grep -q "transient"'

t "D4.1" "unmanaged ~/.config directories go to Jev: real dirs the repo has no config/<name> for, not links, not managed ones" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config/newtool/sub" "$W/home/.config/managed" "$W/pub/config/managed" "$W/elsewhere"
  printf "a\n" >"$W/home/.config/newtool/a.conf"; printf "b\n" >"$W/home/.config/newtool/sub/b"; ln -s "$W/elsewhere" "$W/home/.config/linked"; printf "x\n" >"$W/home/.config/loose-file"
  dsyn >/dev/null 2>&1; f=$(_facts config)
  [ "$(_calls "^dotfiles-jev-stub drift config")" -eq 1 ] && [ "$(printf "%s\n" "$f" | grep -c .)" -eq 1 ] &&
  [ "$(printf "%s\n" "$f" | grep -c "^newtool	.*files=2.*first seen $(date +%Y-%m-%d)")" -eq 1 ]'
t "D4.2" "capture: the exact move-and-link command is printed and nothing is moved, even confirmed" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config/newtool"; printf "a\n" >"$W/home/.config/newtool/a.conf"; _suggest config newtool capture
  out=$(DXY=1 dsyn 2>&1)
  [ -f "$W/home/.config/newtool/a.conf" ] && [ ! -e "$W/pub/config/newtool" ] && printf "%s\n" "$out" | grep -qF "mv \"$W/home/.config/newtool\" \"$W/pub/config/newtool\"" && printf "%s\n" "$out" | grep -q "dotfiles link"'
t "D4.3" "no unmanaged directory: Jev is not asked" '
  W=$(senv); dstub "$W"; mkdir -p "$W/home/.config"; dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift config")" -eq 0 ]'

t "D6.1" "DOTFILES_YES=1 with no terminal and no seam appends nothing: the model never edits a file unattended" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  out=$(DX="DOTFILES_YES=1" dsyn 2>&1); [ "$(shasum "$W/pub/Brewfile")" = "$b" ] && printf "%s\n" "$out" | grep -qF "Jev suggests public: brew \"jq\""'
t "D6.2" "an answer that is not y or yes appends nothing" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile"); printf "n\nyep\n" >"$W/yes"
  DXA=1 dsyn >/dev/null 2>&1; [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D6.3" "a hostile App Store name (quote, Ruby interpolation) is never written into a Brewfile; it is shown to add by hand" '
  W=$(senv); dstub "$W"; printf "111  Evil\"App #{system(1)}  (5.0)\n222  Fine App  (1.0)\n" >"$W/state/mas"
  _suggest pkg mas:111 public; _suggest pkg mas:222 public; out=$(DXY=1 dsyn 2>&1)
  [ "$(_lines pub/Brewfile | grep -c "Evil")" -eq 0 ] && [ "$(_lines pub/Brewfile | grep -c "^mas \"Fine App\", id: 222$")" -eq 1 ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.4" "a hostile formula or cask name is not written either" '
  W=$(senv); dstub "$W"; printf "wget\nfzf\nx\"y\n" >"$W/state/leaves"; printf "iterm2\nbad#{z}\n" >"$W/state/casks"
  _suggest pkg "brew:x\"y" public; _suggest pkg "cask:bad#{z}" public; out=$(DXY=1 dsyn 2>&1)
  [ "$(_lines pub/Brewfile | grep -c "x\"y\|bad")" -eq 0 ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.5" "a failed Jev request stops the other kinds: one request, not three" '
  W=$(senv); dstub "$W"; _undeclared; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"; mkdir -p "$W/home/.config/newtool"; printf "a\n" >"$W/home/.config/newtool/a"
  DX="JEVSTUB_RC=3" dsyn >/dev/null 2>&1; [ "$(_calls "^dotfiles-jev-stub drift")" -eq 1 ]'
t "D6.6" "one 401 is one request across all three kinds (real dotfiles-jev, fake curl)" '
  W=$(senv); dstub "$W"; _undeclared; printf "com.example.a\tAlpha\t1\t0\n" >"$W/state/changed"; mkdir -p "$W/home/.config/newtool" "$W/rec"; printf "a\n" >"$W/home/.config/newtool/a"
  cp "$ROOT_DIR/tests/fixtures/jev/fake-curl" "$W/bin/curl"
  DX="DOTFILES_JEV_BIN=$ROOT_DIR/bin/dotfiles-jev TYPESAFE_API_KEY=k1 FAKE_CURL_DIR=$W/rec FAKE_CURL_FIXDIR=$ROOT_DIR/tests/fixtures/jev FAKE_CURL_SEQ=401 JEV_BACKOFF=0" dsyn >/dev/null 2>&1
  [ "$(command cat "$W/rec/count" 2>/dev/null || echo 0)" -eq 1 ]'
t "D6.7" "fact gathering stops at JEV_DRIFT_MAX_ITEMS: brew is asked about at most that many formulae" '
  W=$(senv); dstub "$W"; printf "wget\nfzf\na1\na2\na3\na4\na5\na6\n" >"$W/state/leaves"
  DX="JEV_DRIFT_MAX_ITEMS=3" dsyn >/dev/null 2>&1
  [ "$(_calls "^brew desc")" -eq 3 ] && [ "$(_facts pkg | grep -c .)" -eq 3 ]'
t "D6.8" "an undeclared VS Code extension is classified too: public to packages/code.list, private to code.local.list" '
  W=$(senv); dstub "$W"; printf "ms-python.python\nFoo.Bar\nBaz.Qux\n" >"$W/state/vscode"
  _suggest pkg code:Foo.Bar public; _suggest pkg code:Baz.Qux private; DXY=1 dsyn >/dev/null 2>&1
  [ "$(_facts pkg | grep -c "^code:Foo.Bar	.*VS Code extension")" -eq 1 ] && [ "$(_lines pub/packages/code.list | grep -c "^Foo.Bar$")" -eq 1 ] &&
  [ "$(_lines pub/packages/code.local.list | grep -c "^Baz.Qux$")" -eq 1 ]'
t "D6.9" "an extension id outside publisher.name is not written" '
  W=$(senv); dstub "$W"; printf "ms-python.python\nx;touch.pwned\n" >"$W/state/vscode"; b=$(shasum "$W/pub/packages/code.list")
  _suggest pkg "code:x;touch.pwned" public; out=$(DXY=1 dsyn 2>&1); [ "$(shasum "$W/pub/packages/code.list")" = "$b" ] && printf "%s\n" "$out" | grep -q "add by hand"'
t "D6.10" "a defaults integer like 5-3 and a domain with a shell metacharacter are shown, never appended" '
  W=$(senv); dstub "$W"; mkdir -p "$W/pub/macos"; : >"$W/pub/macos/defaults.sh"; printf "integer" >"$W/state/deftype"
  printf "com.example.a\tBeta\t5\t5-3\nevil;dom\tK\t1\t2\n" >"$W/state/changed"
  _suggest defaults "com.example.a Beta" public; _suggest defaults "evil;dom K" public; out=$(DXY=1 dsyn 2>&1)
  [ ! -s "$W/pub/macos/defaults.sh" ] && [ "$(printf "%s\n" "$out" | grep -c "by hand")" -eq 2 ]'

t "D6.11" "an exported answers file without the sandbox marker is ignored: a real run appends nothing" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; printf "y\ny\n" >"$W/yes"; b=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_STRICT_ANSWERS=$W/yes" dsyn >/dev/null 2>&1; [ "$(shasum "$W/pub/Brewfile")" = "$b" ]'
t "D6.12" "with the marker, an answers file outside the sandbox root, or reached through .., is ignored" '
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; b=$(shasum "$W/pub/Brewfile")
  o=$(mktemp -d "${TMPDIR:-/tmp}/dfout.XXXXXX"); printf "y\ny\n" >"$o/yes"; printf "y\ny\n" >"$W/yes"
  DX="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$o/yes" dsyn >/dev/null 2>&1; a=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$DOTFILES_TEST_SANDBOX/../$(basename "$o")/yes" dsyn >/dev/null 2>&1; c=$(shasum "$W/pub/Brewfile")
  DX="DOTFILES_TEST_SANDBOX= DOTFILES_STRICT_ANSWERS=$W/yes" dsyn >/dev/null 2>&1; d=$(shasum "$W/pub/Brewfile")
  command rm -f "$o/yes"; rmdir "$o"
  [ "$a" = "$b" ] && [ "$c" = "$b" ] && [ "$d" = "$b" ]'
t "D6.13" "the answers descriptor the seam opens is closed again, and the seam is not advertised in the docs" '
  [ "$(code_of bin/dotfiles-sync | grep -c "exec 4<&-")" -ge 1 ] && [ "$(grep -c "STRICT_ANSWERS" docs/agents/jev.md docs/agents/two-mac-sync.md | grep -vc ":0$")" -eq 0 ]'

t "D5.1" "sync never writes to a Brewfile or a defaults file without going through confirm" '
  c=$(code_of bin/dotfiles-sync)
  [ "$(printf "%s\n" "$c" | grep -c "strict_confirm \"Add ")" -ge 1 ] && [ "$(printf "%s\n" "$c" | grep -c "[^_]confirm \"Add ")" -eq 0 ] && [ "$(printf "%s\n" "$c" | grep -c "^[[:space:]]*brew uninstall")" -eq 0 ]'

finish

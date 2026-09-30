#!/usr/bin/env bash
# tests/launcher.sh -- Task 11: Tinycast as the launcher on new Macs, Raycast
# kept per machine. Covers dotfiles_launcher (scripts/lib/machine.sh), the
# conditional Brewfile entry, the tap trust in sub_install_packages and
# config/tinycast/settings.json. The Cmd-Space block in macos/defaults.sh is
# tested in tests/macos.sh (it needs that suite's stub harness).
#
# Nothing here touches real Homebrew, preferences or $HOME: brew is a stub on
# a sandbox PATH, and the helper is pointed at a sandbox dotfiles dir.
#
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# _lc <dotfiles-dir> [VAR=val ...] -- what dotfiles_launcher prints, stdout only.
_lc() {
  local d="$1"
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_launcher "$2"' _ "$ROOT_DIR" "$d" 2>/dev/null
}
# _lc_err -- the same, stderr only (2>&1 before >/dev/null swaps the streams on purpose).
# shellcheck disable=SC2069
_lc_err() {
  local d="$1"
  shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_launcher "$2"' _ "$ROOT_DIR" "$d" 2>&1 >/dev/null
}
_lc_dir() { local d; d=$(sandbox) && mkdir -p "$d/macos" && printf '%s' "$d"; }

section "L1 -- dotfiles_launcher"
t "L1.1" "nothing configured: tinycast" \
  'D=$(_lc_dir); [ "$(_lc "$D")" = tinycast ]'
t "L1.2" "DOTFILES_LAUNCHER=raycast in the environment" \
  'D=$(_lc_dir); [ "$(_lc "$D" DOTFILES_LAUNCHER=raycast)" = raycast ]'
t "L1.3" "macos/machine.local.sh sets it" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/machine.local.sh"; [ "$(_lc "$D")" = raycast ]'
t "L1.4" "macos/local.sh sets it when machine.local.sh does not" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; [ "$(_lc "$D")" = raycast ]'
t "L1.5" "machine.local.sh beats local.sh" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=tinycast\n" >"$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; [ "$(_lc "$D")" = tinycast ]'
t "L1.6" "the environment beats both files" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=tinycast\n" >"$D/macos/machine.local.sh"; [ "$(_lc "$D" DOTFILES_LAUNCHER=raycast)" = raycast ]'
t "L1.7" "a machine.local.sh that leaves it unset falls through to local.sh" \
  'D=$(_lc_dir); printf "X=1\n" >"$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; [ "$(_lc "$D")" = raycast ]'
t "L1.8" "an unknown value warns and falls back to tinycast" \
  'D=$(_lc_dir); [ "$(_lc "$D" DOTFILES_LAUNCHER=alfred)" = tinycast ] && case "$(_lc_err "$D" DOTFILES_LAUNCHER=alfred)" in *DOTFILES_LAUNCHER=alfred*) true ;; *) false ;; esac'
t "L1.9" "the warning is printed once, not per read" \
  'D=$(_lc_dir); [ "$(_lc_err "$D" DOTFILES_LAUNCHER=alfred | grep -c warning)" -eq 1 ]'
t "L1.10" "a valid value prints no warning" \
  'D=$(_lc_dir); [ -z "$(_lc_err "$D" DOTFILES_LAUNCHER=raycast)" ]'
t "L1.11" "sourcing machine.sh has no side effects" \
  '[ -z "$(env -i PATH=/usr/bin:/bin bash -c ". \"$ROOT_DIR/scripts/lib/machine.sh\"" 2>&1)" ]'
t "L1.12" "a file value does not leak into the caller's shell" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\nLEAK=1\n" >"$D/macos/machine.local.sh"
   [ "$(env -i PATH=/usr/bin:/bin bash -c ". \"$ROOT_DIR/scripts/lib/machine.sh\"; dotfiles_launcher \"$D\" >/dev/null; echo \"\${LEAK:-none}\"")" = none ]'
t "L1.13" "a machine.local.sh with a syntax error warns once, naming the file, and the next file still counts" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\nif then fi (\n" >"$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"
   e=$(_lc_err "$D"); [ "$(_lc "$D")" = raycast ] && [ "$(printf "%s\n" "$e" | grep -c "machine.local.sh")" -eq 1 ]'
t "L1.14" "a broken file and nothing else: tinycast, with the warning" \
  'D=$(_lc_dir); printf "if then fi (\n" >"$D/macos/machine.local.sh"; [ "$(_lc "$D")" = tinycast ] && case "$(_lc_err "$D")" in *machine.local.sh*) true ;; *) false ;; esac'
t "L1.15" "an unreadable file warns and does not stop the lookup" \
  '[ "$(id -u)" -eq 0 ] || { D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/machine.local.sh"; chmod 000 "$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"
   r=$(_lc "$D"); e=$(_lc_err "$D"); chmod 600 "$D/macos/machine.local.sh"; [ "$r" = raycast ] && case "$e" in *machine.local.sh*) true ;; *) false ;; esac; }'
t "L1.16" "a file that merely ends on a failing command is not a warning" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\n[ -f /nonexistent ] && true\n" >"$D/macos/machine.local.sh"; [ -z "$(_lc_err "$D")" ] && [ "$(_lc "$D")" = raycast ]'

if ! command -v brew >/dev/null 2>&1; then
  printf '%sSKIP%s L2/L6 need Homebrew (brew bundle list); the Brewfile launcher tests below pass vacuously\n' "$RED" "$RESET"
fi
section "L2 -- the Brewfile installs exactly one launcher"
# `brew bundle list` is read-only (it prints the cask without its tap).
# HOMEBREW_NO_AUTO_UPDATE keeps it offline. Only HOMEBREW_* variables reach the
# Brewfile, hence HOMEBREW_DOTFILES_LAUNCHER. The Brewfile is read from a
# sandbox copy: the one in the repo falls back to this Mac's own gitignored
# macos/machine.local.sh, which would decide "unset" for the test (see L6).
_bl() {
  local d
  d=$(_lc_dir) && cp Brewfile "$d/Brewfile" &&
    env HOMEBREW_NO_AUTO_UPDATE=1 "$@" brew bundle list --cask --file="$d/Brewfile" 2>/dev/null
}
t "L2.1" "unset: Tinycast, not Raycast" \
  '! command -v brew >/dev/null || { o=$(_bl X=1); printf "%s\n" "$o" | grep -qx tinycast && ! printf "%s\n" "$o" | grep -qx raycast; }'
t "L2.2" "DOTFILES_LAUNCHER=tinycast: Tinycast, not Raycast" \
  '! command -v brew >/dev/null || { o=$(_bl HOMEBREW_DOTFILES_LAUNCHER=tinycast); printf "%s\n" "$o" | grep -qx tinycast && ! printf "%s\n" "$o" | grep -qx raycast; }'
t "L2.3" "DOTFILES_LAUNCHER=raycast: Raycast, not Tinycast" \
  '! command -v brew >/dev/null || { o=$(_bl HOMEBREW_DOTFILES_LAUNCHER=raycast); printf "%s\n" "$o" | grep -qx raycast && ! printf "%s\n" "$o" | grep -q tinycast; }'
t "L2.4" "an unknown value gets Tinycast, matching dotfiles_launcher" \
  '! command -v brew >/dev/null || { o=$(_bl HOMEBREW_DOTFILES_LAUNCHER=alfred); printf "%s\n" "$o" | grep -qx tinycast; }'
t "L2.5" "the Blender cask is declared (the blender MCP needs Blender 5.1+)" \
  '[ "$(code_of Brewfile | grep -c "^cask \"blender\"")" -ge 1 ]'
t "L2.6" "the Tinycast cask is fully qualified and its tap declared in the Brewfile" \
  '[ "$(code_of Brewfile | grep -c "tap \"abue-ammar/tinycast\"")" -ge 1 ] && [ "$(code_of Brewfile | grep -c "cask \"abue-ammar/tinycast/tinycast\"")" -ge 1 ]'

section "L3 -- sub_install_packages trusts the Tinycast tap only for Tinycast"
fn_of() { sed -n "/^$1()/,/^}/p" "${2:-bin/dotfiles}"; }
# _pk <W> [env...] -- run the real function against the real Brewfile and a stub
# brew that logs argv and, for `bundle`, the launcher it was handed.
_pk() {
  local W="$1"; shift
  mkdir -p "$W/repo/packages" "$W/repo/scripts/lib" "$W/repo/macos" "$W/bin" "$W/h"
  cp scripts/lib/lists.sh scripts/lib/machine.sh scripts/lib/xcode.sh "$W/repo/scripts/lib/"
  cp Brewfile "$W/repo/Brewfile"
  : >"$W/repo/packages/code.list"
  cat >"$W/bin/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >>"$SW/log"
[ "$1" = bundle ] && echo "bundle-launcher ${HOMEBREW_DOTFILES_LAUNCHER-unset}" >>"$SW/log"
exit 0
STUB
  printf '#!/bin/bash\nexit 0\n' >"$W/bin/code"
  chmod +x "$W/bin/brew" "$W/bin/code"
  fn_of sub_install_packages >"$W/fn.sh"
  cat >"$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; ROOT_DIR="$W/repo"; DOTFILES_YES=1
DOTFILES_CODE_BIN_FALLBACK="$W/no-such-code"; DOTFILES_XCODE_APP="$W/Xcode.app"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/requirers.sh; . "$W/fn.sh"
sub_install_packages
RUN
  : >"$W/log"
  timeout 30 env SW="$W" "$@" bash "$W/run.sh" </dev/null >"$W/out" 2>&1
}
t "L3.1" "tinycast: the tap is tapped, then trusted, then bundled" '
  W=$(sandbox); _pk "$W" DOTFILES_LAUNCHER=tinycast
  a=$(_first_line "brew tap abue-ammar/tinycast" "$W/log"); b=$(_first_line "brew trust --tap abue-ammar/tinycast" "$W/log"); c=$(_first_line "brew bundle install" "$W/log")
  [ "$a" -gt 0 ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]'
t "L3.2" "default (nothing configured) is tinycast" '
  W=$(sandbox); _pk "$W"; grep -qx "brew trust --tap abue-ammar/tinycast" "$W/log" && grep -qx "bundle-launcher tinycast" "$W/log"'
t "L3.3" "raycast: the Tinycast tap is neither tapped nor trusted" '
  W=$(sandbox); _pk "$W" DOTFILES_LAUNCHER=raycast
  [ "$(grep -c "abue-ammar" "$W/log")" -eq 0 ] && grep -q "brew bundle install" "$W/log"'
t "L3.4" "raycast: bundle gets DOTFILES_LAUNCHER=raycast so the Brewfile picks the Raycast cask" '
  W=$(sandbox); _pk "$W" DOTFILES_LAUNCHER=raycast; grep -qx "bundle-launcher raycast" "$W/log"'
t "L3.5" "a machine.local.sh choice is honoured and exported to bundle" '
  W=$(sandbox); mkdir -p "$W/repo/macos"; _pk "$W" >/dev/null 2>&1; printf "DOTFILES_LAUNCHER=raycast\n" >"$W/repo/macos/machine.local.sh"
  _pk "$W"; grep -qx "bundle-launcher raycast" "$W/log" && [ "$(grep -c "abue-ammar" "$W/log")" -eq 0 ]'
t "L3.6" "the taps the Brewfile declares unconditionally are still trusted" '
  W=$(sandbox); _pk "$W" DOTFILES_LAUNCHER=raycast; grep -qx "brew trust --tap goreleaser/tap" "$W/log"'

section "L4 -- config/tinycast/settings.json"
t "L4.1" "strict JSON" 'jq -e . config/tinycast/settings.json >/dev/null'
t "L4.2" "clipboard history is on" \
  '[ "$(jq -r .clipboard.enabled config/tinycast/settings.json)" = true ]'
# Only sections and keys named in upstream docs/features/settings-file.md.
t "L4.3" "only documented sections and keys" \
  '[ "$(jq -r "[paths(scalars) | map(tostring) | join(\".\")] | map(select(. as \$p | [\"general.showInMenuBar\",\"general.popToRootSeconds\",\"general.escapeKeyBehavior\",\"general.autoSwitchInputSource\",\"general.supportReminders\",\"clipboard.enabled\",\"clipboard.retentionDays\",\"clipboard.defaultAction\"] | index(\$p) | not)) | length" config/tinycast/settings.json)" -eq 0 ]'
t "L4.4" "no personal paths or secrets" \
  '! grep -qiE "/Users/|@|token|key|secret" config/tinycast/settings.json'
t "L4.5" "the machine-local launcher file is gitignored, its example is tracked" \
  'git -c core.excludesFile=/dev/null check-ignore -q macos/machine.local.sh && ! git -c core.excludesFile=/dev/null check-ignore -q macos/machine.local.sh.example && [ -f macos/machine.local.sh.example ]'
t "L4.6" "dotfiles private never links or syncs machine.local.sh" \
  '[ "$(code_of bin/dotfiles-private | grep -c "machine.local")" -eq 0 ]'

section "L5 -- dotfiles_export_launcher"
_el() { # _el <dir> [VAR=val...] -- the exported HOMEBREW_DOTFILES_LAUNCHER, seen by a child process
  local d="$1"; shift
  env -i PATH="/usr/bin:/bin" HOME="$d" "$@" bash -c '. "$1/scripts/lib/machine.sh"; dotfiles_export_launcher "$2" 2>/dev/null; env | grep "^HOMEBREW_DOTFILES_LAUNCHER=" || echo none' _ "$ROOT_DIR" "$d"
}
t "L5.1" "exports the resolved launcher to child processes" \
  'D=$(_lc_dir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/machine.local.sh"; [ "$(_el "$D")" = HOMEBREW_DOTFILES_LAUNCHER=raycast ]'
t "L5.2" "nothing configured exports tinycast" \
  'D=$(_lc_dir); [ "$(_el "$D")" = HOMEBREW_DOTFILES_LAUNCHER=tinycast ]'
t "L5.3" "an invalid value exports tinycast" \
  'D=$(_lc_dir); [ "$(_el "$D" DOTFILES_LAUNCHER=alfred)" = HOMEBREW_DOTFILES_LAUNCHER=tinycast ]'

section "L6 -- a bare brew bundle falls back to the machine files"
# HOMEBREW_DOTFILES_LAUNCHER unset: the Brewfile reads the first DOTFILES_LAUNCHER=
# assignment in macos/machine.local.sh, then macos/local.sh, next to itself.
_bare() { # _bare <dir> [VAR=val...] -- brew bundle list --cask against <dir>/Brewfile
  local d="$1"; shift
  env HOMEBREW_NO_AUTO_UPDATE=1 "$@" brew bundle list --cask --file="$d/Brewfile" 2>/dev/null
}
_bdir() { local d; d=$(_lc_dir) && cp Brewfile "$d/Brewfile" && printf '%s' "$d"; }
t "L6.1" "machine.local.sh says raycast: Raycast, no Tinycast" \
  '! command -v brew >/dev/null || { D=$(_bdir); printf "DOTFILES_LAUNCHER=\"raycast\"\n" >"$D/macos/machine.local.sh"; o=$(_bare "$D"); printf "%s\n" "$o" | grep -qx raycast && ! printf "%s\n" "$o" | grep -q tinycast; }'
t "L6.2" "only local.sh says raycast: Raycast" \
  '! command -v brew >/dev/null || { D=$(_bdir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; o=$(_bare "$D"); printf "%s\n" "$o" | grep -qx raycast; }'
t "L6.3" "machine.local.sh beats local.sh" \
  '! command -v brew >/dev/null || { D=$(_bdir); printf "DOTFILES_LAUNCHER=tinycast\n" >"$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; o=$(_bare "$D"); printf "%s\n" "$o" | grep -qx tinycast; }'
t "L6.4" "an unknown value is tinycast" \
  '! command -v brew >/dev/null || { D=$(_bdir); printf "DOTFILES_LAUNCHER=alfred\n" >"$D/macos/machine.local.sh"; o=$(_bare "$D"); printf "%s\n" "$o" | grep -qx tinycast; }'
t "L6.5" "HOMEBREW_DOTFILES_LAUNCHER beats the files" \
  '! command -v brew >/dev/null || { D=$(_bdir); printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/machine.local.sh"; o=$(_bare "$D" HOMEBREW_DOTFILES_LAUNCHER=tinycast); printf "%s\n" "$o" | grep -qx tinycast; }'
t "L6.7" "an unreadable machine.local.sh gives no value and no crash" \
  '! command -v brew >/dev/null || [ "$(id -u)" -eq 0 ] || { D=$(_bdir); printf "DOTFILES_LAUNCHER=tinycast\n" >"$D/macos/machine.local.sh"; chmod 000 "$D/macos/machine.local.sh"; printf "DOTFILES_LAUNCHER=raycast\n" >"$D/macos/local.sh"; o=$(_bare "$D"); chmod 600 "$D/macos/machine.local.sh"; printf "%s\n" "$o" | grep -qx raycast; }'
t "L6.6" "no files at all: tinycast" \
  '! command -v brew >/dev/null || { D=$(_bdir); o=$(_bare "$D"); printf "%s\n" "$o" | grep -qx tinycast; }'

finish

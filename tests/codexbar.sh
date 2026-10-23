#!/usr/bin/env bash
# tests/codexbar.sh -- bin/dotfiles-codexbar: the CodexBar settings its own
# iCloud sync leaves on each Mac (provider data sources, menu-bar layout).
#
# Every run uses a sandbox HOME, a defaults "domain" that is a plain plist file
# in the sandbox, and stub pgrep/osascript/open that log their argv to $W/log.
# The real CodexBar app, its config and its preferences are never touched.
#
# shellcheck disable=SC2016,SC2030,SC2031
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# cbenv: a sandbox with a CodexBar config (one secret in it), a settings file
# and stubs. CodexBar counts as running while $W/running exists. Prints the path.
cbenv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home/.config/codexbar" "$w/bin" "$w/apps/codexbar" "$w/prefs"
  : >"$w/log"
  printf '%s\n' '{"version":1,"providers":[{"id":"claude","enabled":true,"apiKey":"sk-ant-secret"},{"id":"codex","enabled":true}]}' \
    >"$w/home/.config/codexbar/config.json"
  chmod 600 "$w/home/.config/codexbar/config.json"
  printf '%s\n' '{"providers":{"claude":{"source":"web","cookieSource":"auto","claudeDesktopCookiesEnabled":true}},"defaults":{"mergeIcons":false,"multiAccountMenuLayout":"stacked","menuBarLayoutV6":{"lines":[[{"icon":{}},{"percent":{"window":"weekly"}}]]}}}' \
    >"$w/apps/codexbar/settings.json"
  ln -s "$(command -v jq)" "$w/bin/jq"
  _cbstub "$w" pgrep '[ -f "$STUB_STATE/running" ]'
  _cbstub "$w" osascript 'rm -f "$STUB_STATE/running"'
  _cbstub "$w" killall 'rm -f "$STUB_STATE/running"'
  _cbstub "$w" open ':'
  printf '%s' "$w"
}
_cbstub() { # _cbstub <W> <name> <body>
  { printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n' "$2"; printf '%s\n' "$3"; } >"$1/bin/$2"
  chmod +x "$1/bin/$2"
}
# cb <args>: dotfiles-codexbar against the sandbox in $W; $CBENV adds VAR=val.
cb() {
  # shellcheck disable=SC2086
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" STUB_LOG="$W/log" STUB_STATE="$W" \
    DOTFILES_CODEXBAR_SETTINGS="$W/apps/codexbar/settings.json" DOTFILES_CODEXBAR_DOMAIN="$W/prefs/codexbar" \
    ${CBENV:-} bash "$ROOT_DIR/bin/dotfiles-codexbar" "$@"
}
cfg_of() { printf '%s' "$W/home/.config/codexbar/config.json"; }
claude_of() { jq -c '.providers[] | select(.id == "claude")' "$1"; }

section "C1 -- apply: provider data sources"
t "C1.1" "apply sets the provider fields and keeps every other field and provider" '
  W=$(cbenv); cb apply >/dev/null 2>&1 && c=$(claude_of "$(cfg_of)") &&
  [ "$(printf "%s" "$c" | jq -r ".source,.cookieSource,.claudeDesktopCookiesEnabled,.enabled,.apiKey" | tr "\n" " ")" = "web auto true true sk-ant-secret " ] &&
  [ "$(jq -r ".providers[] | select(.id == \"codex\") | .enabled" "$(cfg_of)")" = true ]'
t "C1.2" "the config stays private (0600) after a write" '
  W=$(cbenv); cb apply >/dev/null 2>&1; [ "$(/usr/bin/stat -f %Lp "$(cfg_of)")" = 600 ]'
t "C1.3" "a provider the config lacks is added with only its id and the repo fields" '
  W=$(cbenv); jq ".providers.zai = {\"source\": \"api\"}" "$W/apps/codexbar/settings.json" >"$W/s" && command mv -f "$W/s" "$W/apps/codexbar/settings.json"
  cb apply >/dev/null 2>&1 && [ "$(jq -c ".providers[] | select(.id == \"zai\")" "$(cfg_of)")" = "{\"id\":\"zai\",\"source\":\"api\"}" ]'
t "C1.4" "a second apply changes nothing and makes no backup" '
  W=$(cbenv); cb apply >/dev/null 2>&1; before=$(command ls "$W/home/.config/codexbar" | wc -l | tr -d " ")
  cb apply >/dev/null 2>&1 && [ "$(command ls "$W/home/.config/codexbar" | wc -l | tr -d " ")" = "$before" ]'
t "C1.5" "a changed config is backed up first" '
  W=$(cbenv); cb apply >/dev/null 2>&1; b=$(command ls "$W/home/.config/codexbar" | grep "config.json.bak.")
  [ -n "$b" ] && [ "$(claude_of "$W/home/.config/codexbar/$b" | jq -r ".source // \"none\"")" = none ]'
t "C1.6" "no config yet: exit 2, nothing created" '
  W=$(cbenv); command rm -f "$(cfg_of)"; cb apply >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$(cfg_of)" ] && [ ! -e "$W/home/.codexbar/config.json" ]'
t "C1.7" "the legacy ~/.codexbar/config.json is used when there is no XDG config, as CodexBar does" '
  W=$(cbenv); mkdir -p "$W/home/.codexbar"; command mv "$(cfg_of)" "$W/home/.codexbar/config.json"
  cb apply >/dev/null 2>&1 && [ "$(claude_of "$W/home/.codexbar/config.json" | jq -r .source)" = web ] && [ ! -e "$(cfg_of)" ]'
t "C1.8" "CODEXBAR_CONFIG wins over both default paths" '
  W=$(cbenv); cp "$(cfg_of)" "$W/other.json"
  CBENV="CODEXBAR_CONFIG=$W/other.json" cb apply >/dev/null 2>&1 &&
  [ "$(claude_of "$W/other.json" | jq -r .source)" = web ] && [ "$(claude_of "$(cfg_of)" | jq -r ".source // \"none\"")" = none ]'
t "C1.9" "a config CodexBar rejects after the merge is rolled back" '
  W=$(cbenv); before=$(cat "$(cfg_of)"); _cbstub "$W" codexbar "exit 1"
  ! cb apply >/dev/null 2>&1 && [ "$(cat "$(cfg_of)")" = "$before" ]'
t "C1.10" "apply takes the CodexBar config lock and gives up without writing while it is held" '
  W=$(cbenv); before=$(cat "$(cfg_of)")
  /usr/bin/lockf -k "$(cfg_of).lock" /bin/sh -c "touch \"$W/locked\"; sleep 3" &
  n=0; while [ ! -e "$W/locked" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  CBENV="DOTFILES_CODEXBAR_LOCK_TIMEOUT=1" cb apply >/dev/null 2>&1; rc=$?; wait
  [ "$rc" -ne 0 ] && [ "$(cat "$(cfg_of)")" = "$before" ]'
t "C1.11" "a field outside the allowlist is refused and nothing is written" '
  W=$(cbenv); before=$(cat "$(cfg_of)")
  jq ".providers.claude.apiKey = \"x\"" "$W/apps/codexbar/settings.json" >"$W/s" && command mv -f "$W/s" "$W/apps/codexbar/settings.json"
  ! cb apply >/dev/null 2>&1 && [ "$(cat "$(cfg_of)")" = "$before" ] && [ ! -e "$W/prefs/codexbar.plist" ]'

section "C2 -- apply: preferences"
t "C2.1" "bool, string and the menu-bar layout (JSON data) are written" '
  W=$(cbenv); cb apply >/dev/null 2>&1 && p="$W/prefs/codexbar.plist" &&
  [ "$(plutil -extract mergeIcons raw -o - "$p")" = false ] &&
  [ "$(plutil -extract multiAccountMenuLayout raw -o - "$p")" = stacked ] &&
  [ "$(plutil -type menuBarLayoutV6 "$p")" = data ] &&
  [ "$(plutil -extract menuBarLayoutV6 raw -o - "$p" | base64 -d | jq -c .)" = "{\"lines\":[[{\"icon\":{}},{\"percent\":{\"window\":\"weekly\"}}]]}" ]'
t "C2.2" "a key outside the allowlist is refused" '
  W=$(cbenv); jq ".defaults.launchAtLogin = true" "$W/apps/codexbar/settings.json" >"$W/s" && command mv -f "$W/s" "$W/apps/codexbar/settings.json"
  ! cb apply >/dev/null 2>&1 && [ ! -e "$W/prefs/codexbar.plist" ]'
t "C2.3" "a running CodexBar is quit before the write and reopened after" '
  W=$(cbenv); : >"$W/running"; cb apply >/dev/null 2>&1 &&
  [ "$(grep -E "^(osascript|open)" "$W/log" | cut -d" " -f1 | tr "\n" " ")" = "osascript open " ] && [ ! -e "$W/running" ]'
t "C2.3b" "a CodexBar that ignores the quit request is stopped with killall" '
  W=$(cbenv); : >"$W/running"; _cbstub "$W" osascript ":"; cb apply >/dev/null 2>&1 &&
  grep -q "^killall CodexBar" "$W/log" && grep -q "^open" "$W/log"'
t "C2.4" "CodexBar is left alone when the preferences already match" '
  W=$(cbenv); cb apply >/dev/null 2>&1; : >"$W/running"; : >"$W/log"
  cb apply >/dev/null 2>&1 && [ "$(grep -cE "^(osascript|open)" "$W/log")" -eq 0 ]'
t "C2.5" "a provider-only change never quits CodexBar (it watches its config file)" '
  W=$(cbenv); jq "del(.defaults)" "$W/apps/codexbar/settings.json" >"$W/s" && command mv -f "$W/s" "$W/apps/codexbar/settings.json"
  : >"$W/running"; cb apply >/dev/null 2>&1 && [ "$(grep -cE "^(osascript|open)" "$W/log")" -eq 0 ]'
t "C2.6" "a CodexBar that was not running is not opened" '
  W=$(cbenv); cb apply >/dev/null 2>&1 && [ "$(grep -c "^open" "$W/log")" -eq 0 ]'

section "C3 -- diff and capture"
t "C3.1" "diff after apply is clean" 'W=$(cbenv); cb apply >/dev/null 2>&1; cb diff >/dev/null 2>&1'
t "C3.2" "diff exits 1 and names a field that differs" '
  W=$(cbenv); cb apply >/dev/null 2>&1
  jq "(.providers[] | select(.id == \"claude\") | .source) = \"oauth\"" "$(cfg_of)" >"$W/c" && command mv -f "$W/c" "$(cfg_of)"
  out=$(cb diff 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s\n" "$out" | grep -q "claude.source"'
t "C3.3" "diff flags a setting made on this Mac that the repo does not record" '
  W=$(cbenv); cb apply >/dev/null 2>&1; defaults write "$W/prefs/codexbar" terminalApp -string ghostty
  out=$(cb diff 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s\n" "$out" | grep -q "terminalApp"'
t "C3.4" "diff with no config yet exits 2" 'W=$(cbenv); command rm -f "$(cfg_of)"; cb diff >/dev/null 2>&1; [ "$?" -eq 2 ]'
t "C3.5" "capture records this Mac, and diff is then clean" '
  W=$(cbenv); jq "(.providers[] | select(.id == \"codex\")) += {\"cookieSource\": \"off\"}" "$(cfg_of)" >"$W/c" && command mv -f "$W/c" "$(cfg_of)"
  defaults write "$W/prefs/codexbar" terminalApp -string warp
  cb capture >/dev/null 2>&1 && s="$W/apps/codexbar/settings.json" &&
  [ "$(jq -r ".providers.codex.cookieSource, .defaults.terminalApp" "$s" | tr "\n" " ")" = "off warp " ] && cb diff >/dev/null 2>&1'
t "C3.6" "capture never records a secret or a field CodexBar syncs itself" '
  W=$(cbenv); cb apply >/dev/null 2>&1; cb capture >/dev/null 2>&1 &&
  ! grep -qE "sk-ant|apiKey|enabled\"" "$W/apps/codexbar/settings.json"'
t "C3.7" "capture keeps only the newest menu-bar layout key" '
  W=$(cbenv); defaults write "$W/prefs/codexbar" menuBarLayoutV5 -data "$(printf "{}" | od -An -tx1 | tr -d " \n")"
  cb apply >/dev/null 2>&1; cb capture >/dev/null 2>&1 &&
  [ "$(jq -r ".defaults | keys | map(select(startswith(\"menuBarLayout\"))) | join(\" \")" "$W/apps/codexbar/settings.json")" = menuBarLayoutV6 ]'

section "C4 -- the repo copy"
t "C4.1" "apps/codexbar/settings.json passes the allowlist" '
  W=$(cbenv); cp apps/codexbar/settings.json "$W/apps/codexbar/settings.json"; cb check >/dev/null 2>&1'
t "C4.2" "the script is shellcheck clean" 'shellcheck -e SC1090,SC1091 -s bash bin/dotfiles-codexbar macos/defaults-codexbar.sh'
t "C4.3" "bash 3.2: no mapfile, no associative arrays, no case-modifying expansions" '
  [ "$(code_of bin/dotfiles-codexbar | grep -cE "mapfile|readarray|declare -A|local -A|\\$\\{[a-zA-Z_]+(,,|\\^\\^)")" -eq 0 ]'

finish

#!/usr/bin/env bash
#
# tests/sync-vault.sh -- dotfiles vault migrate (V) and app-backup suggestions (E).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

#############################################################################
section "V -- dotfiles vault migrate (bin/dotfiles-vault)"
#############################################################################
# venv: a sandbox HOME with a real local vault and a fake iCloud Drive
# ($W/icloud is the CloudDocs folder; the vault goes to $W/icloud/Vault). Real
# /usr/bin/ditto does the copying unless a test puts a stub in front.
venv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home/Vault/Notes/Sub dir" "$w/home/Vault/.obsidian" "$w/home/Vault/Empty" "$w/bin" "$w/icloud"; : >"$w/log"
  printf 'one\n' >"$w/home/Vault/Notes/a.md"
  printf 'two two\n' >"$w/home/Vault/Notes/Sub dir/b c.md"
  printf '{"a":1}\n' >"$w/home/Vault/.obsidian/app.json"
  printf 'top\n' >"$w/home/Vault/index.md"
  # pgrep: Obsidian is "running" while $W/obsidian exists.
  stub "$w/bin" pgrep '[ "$1" = "-x" ] && [ "$2" = Obsidian ] && [ -f "$STUB_RUNNING" ]'
  stub "$w/bin" brctl ':'
  printf '%s' "$w"
}
# vmig [VAR=val ...]: dotfiles-vault migrate against the sandbox in $W.
vmig() {
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_VAULT_ICLOUD="$W/icloud/Vault" \
    STUB_LOG="$W/log" STUB_RUNNING="$W/obsidian" "$@" bash "$ROOT_DIR/bin/dotfiles-vault" migrate 2>&1 </dev/null
}
# untouched: ~/Vault is still the original real directory, complete, and no
# staging folder or half copy is left in iCloud Drive.
untouched() {
  [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] && [ "$(command cat "$W/home/Vault/Notes/a.md")" = one ] &&
  [ -f "$W/home/Vault/Notes/Sub dir/b c.md" ] && [ -f "$W/home/Vault/.obsidian/app.json" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ] &&
  [ "$(find "$W/icloud" -mindepth 1 | wc -l | tr -d " ")" -eq 0 ]
}

t "V1.1" "migrate copies the vault to iCloud, leaves a symlink at ~/Vault and keeps the original as a backup" '
  W=$(venv); out=$(vmig); rc=$?
  [ "$rc" -eq 0 ] && [ -L "$W/home/Vault" ] && [ "$(readlink "$W/home/Vault")" = "$W/icloud/Vault" ] &&
  [ "$(command cat "$W/icloud/Vault/Notes/Sub dir/b c.md")" = "two two" ] && [ -d "$W/icloud/Vault/Empty" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 1 ]'
t "V1.2" "the backup is the untouched original, and the iCloud copy is identical to it" '
  W=$(venv); vmig >/dev/null; b=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*")
  [ -f "$b/.obsidian/app.json" ] && diff -r "$b" "$W/icloud/Vault" >/dev/null'
t "V1.3" "no staging folder is left behind after a good run" \
  'W=$(venv); vmig >/dev/null; [ "$(find "$W/icloud" -maxdepth 1 -name "*.migrating.*" | wc -l | tr -d " ")" -eq 0 ]'
t "V1.4" "the output says how to undo it, and to use Keep Downloaded" '
  W=$(venv); out=$(vmig); printf "%s\n" "$out" | grep -q "To undo" && printf "%s\n" "$out" | grep -q "Vault.local-backup-" &&
  printf "%s\n" "$out" | grep -q "Keep Downloaded"'
t "V1.5" "the undo command as printed puts the original back" '
  W=$(venv); vmig >/dev/null; b=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*")
  rm "$W/home/Vault" && mv "$b" "$W/home/Vault" && [ ! -L "$W/home/Vault" ] && [ -f "$W/home/Vault/Notes/a.md" ]'
t "V2.1" "a running Obsidian refuses, and nothing changes" '
  W=$(venv); : >"$W/obsidian"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "Obsidian is running" && untouched'
t "V2.2" "a non-empty iCloud vault folder refuses, and nothing changes" '
  W=$(venv); mkdir -p "$W/icloud/Vault"; printf "x\n" >"$W/icloud/Vault/other.md"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "not empty" && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ] && [ "$(ls "$W/icloud/Vault")" = other.md ]'
t "V2.3" "an existing but empty iCloud vault folder is fine" \
  'W=$(venv); mkdir -p "$W/icloud/Vault"; vmig >/dev/null && [ -L "$W/home/Vault" ] && [ -f "$W/icloud/Vault/index.md" ]'
t "V2.4" "no iCloud Drive at all refuses, and nothing changes" '
  W=$(venv); command rmdir "$W/icloud"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "iCloud Drive is not available" && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ]'
t "V2.5" "already migrated is a no-op that succeeds" '
  W=$(venv); vmig >/dev/null; n=$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")
  out=$(vmig); rc=$?; [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "already" &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq "$n" ]'
t "V2.6" "no vault to migrate is an error" \
  'W=$(venv); command mv "$W/home/Vault" "$W/home/elsewhere"; out=$(vmig); rc=$?; [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "no vault"'
t "V2.7" "a ~/Vault symlink to somewhere else is refused" '
  W=$(venv); command mv "$W/home/Vault" "$W/home/elsewhere"; ln -s "$W/home/elsewhere" "$W/home/Vault"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && [ "$(readlink "$W/home/Vault")" = "$W/home/elsewhere" ]'

# A failure at any step leaves the original vault untouched.
t "V3.1" "a failing ditto: non-zero, the original is untouched, no partial copy is left" '
  W=$(venv); stub "$W/bin" ditto "exit 1"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "copy failed" && untouched'
t "V3.2" "a ditto that leaves a partial copy: the partial copy is removed" '
  W=$(venv); stub "$W/bin" ditto "mkdir -p \"\$2\"; cp \"\$1/index.md\" \"\$2/\"; exit 1"; vmig >/dev/null; untouched'
t "V3.3" "a copy that silently drops a file fails the count check: the original is untouched, the copy is removed" '
  W=$(venv); stub "$W/bin" ditto "/usr/bin/ditto \"\$@\" || exit 1; rm -f \"\$2/index.md\""; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "entry count differs" && untouched'
t "V3.4" "a copy with the same names but different content fails the checksum check" '
  W=$(venv); stub "$W/bin" ditto "/usr/bin/ditto \"\$@\" || exit 1; printf \"ONE\\n\" >\"\$2/Notes/a.md\""; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -q "does not match" && untouched'
t "V3.5" "a failing symlink step puts the original back" '
  W=$(venv); stub "$W/bin" ln "exit 1"; out=$(vmig); rc=$?
  [ "$rc" -ne 0 ] && [ -d "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] && [ "$(command cat "$W/home/Vault/Notes/a.md")" = one ] &&
  [ "$(find "$W/home" -maxdepth 1 -name "Vault.local-backup-*" | wc -l | tr -d " ")" -eq 0 ]'
t "V3.6" "the only rm in the migrate code removes the staging folder it made" \
  '[ "$(code_of bin/dotfiles-vault | grep -E "(^|[;&|])[[:space:]]*rm " | grep -vcF "\"\$1\"")" -eq 0 ] &&
   [ "$(code_of bin/dotfiles-vault | grep -cE "(^|[;&|])[[:space:]]*rm ")" -ge 1 ]'
t "V4.1" "an unknown subcommand is a usage error" \
  'W=$(venv); out=$(env -i HOME="$W/home" PATH="/usr/bin:/bin" bash bin/dotfiles-vault frob 2>&1); rc=$?; [ "$rc" -eq 2 ] && printf "%s\n" "$out" | grep -q Usage'


#############################################################################
section "E -- Task 14: app-backup suggestions (Jev, mackup-supported apps)"
#############################################################################
t "E1" "the candidates go to Jev as one batched request, and the declined list is the private repo's" '
  W=$(senv); estub "$W"; esyn >/dev/null 2>&1
  [ "$(_calls "^dotfiles-jev-stub apps")" -eq 1 ] && [ "$(_facts apps | grep -c .)" -eq 2 ] && [ "$(_facts apps | grep -c "^gamma	")" -eq 1 ] &&
  [ "$(_calls "^DECLINED=$W/priv/jev/apps-declined.list$")" -eq 1 ]'
t "E2" "shadow mode: asked, but a SUGGEST from Jev is neither printed nor acted on, even answered yes" '
  W=$(senv); estub "$W" shadow; _asuggest gamma backup; out=$(EA="y y" esyn 2>&1)
  [ "$(_calls "^dotfiles-jev-stub apps")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "gamma")" -eq 0 ] && [ ! -e "$(DECL)" ]'
t "E3" "master switch off, or the point off: nothing is gathered and nothing is asked" '
  W=$(senv); estub "$W"; DX="DOTFILES_JEV=off" esyn >/dev/null 2>&1; a=$(_calls "^dotfiles-apps-stub")
  W=$(senv); estub "$W" off; esyn >/dev/null 2>&1
  [ "$a" -eq 0 ] && [ "$(_calls "^dotfiles-apps-stub")" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub apps")" -eq 0 ]'
t "E4" "on, backup: the allowlist line and the process-list hint are shown; a yes writes nothing, a no is remembered in the private repo" '
  W=$(senv); estub "$W"; _asuggest gamma backup; c=$(shasum "$W/pub/config/mackup/mackup.cfg" 2>/dev/null); out=$(EA="y" esyn 2>&1)
  a=$([ -e "$(DECL)" ] && echo declined || echo none)
  W=$(senv); estub "$W"; _asuggest gamma backup; EA="n" esyn >/dev/null 2>&1
  [ "$(printf "%s\n" "$out" | grep -c "Jev suggests backup: gamma")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "mackup.cfg")" -ge 1 ] && [ "$(printf "%s\n" "$out" | grep -c "processes.list")" -ge 1 ] &&
  [ "$a" = none ] && [ "$(shasum "$W/pub/config/mackup/mackup.cfg" 2>/dev/null)" = "$c" ] && [ "$(grep -cx gamma "$(DECL)")" -eq 1 ]'
t "E5" "on, own-sync and not-worth-it: agreeing (yes) remembers the app, disagreeing does not" '
  W=$(senv); estub "$W"; _asuggest gamma own-sync; _asuggest delta not-worth-it; EA="y n" esyn >/dev/null 2>&1
  [ "$(grep -cx gamma "$(DECL)")" -eq 1 ] && [ "$(grep -cx delta "$(DECL)")" -eq 0 ]'
t "E6" "interactive without a terminal or an answer: offered, nothing is decided, so nothing is remembered" '
  W=$(senv); estub "$W"; _asuggest gamma backup; out=$(esyn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "Jev suggests backup: gamma")" -eq 1 ] && [ ! -e "$(DECL)" ]'
t "E7" "DOTFILES_YES does not answer the prompt: nothing is remembered" '
  W=$(senv); estub "$W"; _asuggest gamma own-sync; DX="DOTFILES_YES=1" esyn >/dev/null 2>&1; [ ! -e "$(DECL)" ]'
t "E8" "scheduled: no prompt, no write, one notification that names the apps" '
  W=$(senv); estub "$W"; _asuggest gamma backup; EA="n" esyn --scheduled >/dev/null 2>&1
  [ ! -e "$(DECL)" ] && [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "app"'
t "E9" "a name Jev returns that was not in the facts is ignored, and an unsafe candidate name is never sent or offered" '
  W=$(senv); estub "$W"; printf "evil;touch pwned\tpaths=1\n" >>"$W/state/apps-candidates"; _asuggest zzz backup; _asuggest "evil;touch pwned" backup
  out=$(EA="n n n" esyn 2>&1)
  [ "$(_facts apps | grep -c "evil")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "zzz\|evil")" -eq 0 ] && [ ! -e "$(DECL)" ]'
t "E10" "no private repo: the no is not remembered anywhere and nothing is created" '
  W=$(senv); estub "$W"; _asuggest gamma backup; command mv "$W/priv" "$W/priv-gone"; out=$(EA="n" esyn 2>&1)
  [ ! -e "$W/priv" ] && [ "$(printf "%s\n" "$out" | grep -c "not remembered")" -eq 1 ]'
t "E11" "a failed drift request stops the run: apps is not asked; a failed apps request changes nothing, exit 0" '
  W=$(senv); estub "$W"; printf "wget\nfzf\njq\n" >"$W/state/leaves"; DX="JEVSTUB_RC=3" esyn >/dev/null 2>&1; a=$(_calls "^dotfiles-jev-stub apps")
  W=$(senv); estub "$W"; _asuggest gamma backup; out=$(DX="JEVAPPS_RC=3" EA="n" esyn 2>&1); rc=$?
  [ "$a" -eq 0 ] && [ "$rc" -eq 0 ] && [ ! -e "$(DECL)" ]'
t "E12" "interactive on gets 6 s; shadow keeps the 2 s default; scheduled marks JEV_SCHEDULED for the 10 s" '
  W=$(senv); estub "$W"; esyn >/dev/null 2>&1; a=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; esyn --scheduled >/dev/null 2>&1; b=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  : >"$W/log"; estub "$W" shadow; esyn >/dev/null 2>&1; c=$(grep "^JEV_SCHEDULED=" "$W/log" | head -n 1)
  [ "$a" = "JEV_SCHEDULED= JEV_TIMEOUT=6" ] && [ "$b" = "JEV_SCHEDULED=1 JEV_TIMEOUT=" ] && [ "$c" = "JEV_SCHEDULED= JEV_TIMEOUT=" ]'
t "E13" "the apps suggestion goes only through strict_confirm, and no fact list exceeds the cap" '
  c=$(code_of bin/dotfiles-sync)
  W=$(senv); estub "$W"; i=1; while [ "$i" -le 9 ]; do printf "app%s\tpaths=1\n" "$i" >>"$W/state/apps-candidates"; i=$((i + 1)); done
  DX="JEV_APPS_MAX_ITEMS=4" esyn >/dev/null 2>&1
  [ "$(printf "%s\n" "$c" | grep -c "strict_\(confirm\|answer\) \"")" -ge 3 ] && [ "$(printf "%s\n" "$c" | grep -c "[^_]confirm \"\(Will you\|Agree\)")" -eq 0 ] &&
  [ "$(_facts apps | grep -c .)" -eq 4 ]'

t "E14" "EOF or an empty answers file is not a decision: nothing is declined, and it says it will ask again" '
  W=$(senv); estub "$W"; _asuggest gamma backup; _asuggest delta own-sync; : >"$W/empty"
  out=$(DX="DOTFILES_STRICT_ANSWERS=$W/empty" esyn 2>&1)
  [ ! -e "$(DECL)" ] && [ "$(printf "%s\n" "$out" | grep -c "not decided, will ask again")" -eq 2 ]'
t "E15" "an empty answer (just Enter) is not a decision either; an explicit n still is" '
  W=$(senv); estub "$W"; _asuggest gamma backup; printf "\n" >"$W/blank"
  DX="DOTFILES_STRICT_ANSWERS=$W/blank" esyn >/dev/null 2>&1; a=$([ -e "$(DECL)" ] && echo declined || echo none)
  W=$(senv); estub "$W"; _asuggest gamma backup; EA="no" esyn >/dev/null 2>&1
  [ "$a" = none ] && [ "$(grep -cx gamma "$(DECL)")" -eq 1 ]'
t "E16" "a backup suggestion prints the exact allowlist line and processes.list line; without a safe process name it says by hand" '
  W=$(senv); estub "$W"; _asuggest gamma backup; _asuggest delta backup; out=$(esyn 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "^    add to config/mackup/mackup.cfg under \[applications_to_sync\]:  gamma$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^    add to config/mackup/processes.list:  gamma|GammaExec$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^    add to config/mackup/mackup.cfg under \[applications_to_sync\]:  delta$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "delta|")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "process name.*by hand")" -eq 1 ]'
t "E17" "the declined list alone does not make the private repo dirty: no notification, and a behind pull still fast-forwards" '
  W=$(senv); estub "$W"; mkdir -p "$W/priv/jev"; printf "x\n" >"$W/priv/jev/apps-declined.list"
  syn --scheduled >/dev/null 2>&1; a=$(_calls "^osascript")
  printf "y\n" >"$W/priv/other.txt"; : >"$W/log"; syn --scheduled >/dev/null 2>&1; b=$(_calls "^osascript")
  W=$(senv); estub "$W"
  push_change "$W" priv jev/apps-declined.list "a"; git -C "$W/priv" pull -q --ff-only 2>/dev/null
  printf "b\n" >>"$W/priv/jev/apps-declined.list"; push_change "$W" priv Brewfile.local2 "z"; h=$(_remote priv)
  esyn >/dev/null 2>&1
  [ "$a" -eq 0 ] && [ "$b" -eq 1 ] && [ "$(_head priv)" = "$h" ] && [ "$(grep -cx b "$W/priv/jev/apps-declined.list")" -eq 1 ]'



finish

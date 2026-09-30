#!/usr/bin/env bash
# tests/setapp.sh -- Setapp app installs (scripts/lib/setapp.sh, install --setapp).
# HERMETIC: a fixture Apps.sqlite, stubbed open/launchctl/pgrep on a sandbox
# PATH, a fake /Applications/Setapp via DOTFILES_SETAPP_APPS_DIR, a stub log
# dir. Nothing touches the real Setapp.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# _sa_env <W> -- lay out the sandbox: catalogue, apps dir, log dir, stubs.
_sa_env() {
  local W="$1"
  mkdir -p "$W/bin" "$W/apps" "$W/logs" "$W/db" "$W/h"
  : >"$W/log"
  sqlite3 "$W/db/Apps.sqlite" <<'SQL'
create table ZAPP (Z_PK integer primary key, ZNAME varchar, ZPUBLICID blob);
insert into ZAPP (ZNAME, ZPUBLICID) values ('Bartender', x'00112233445566778899aabbccddeeff');
insert into ZAPP (ZNAME, ZPUBLICID) values ('Paste', x'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf');
insert into ZAPP (ZNAME, ZPUBLICID) values ('Spark Mail', x'10111213141516171819101112131415');
insert into ZAPP (ZNAME, ZPUBLICID) values ('Bob''s Tool', x'20212223242526272829202122232425');
insert into ZAPP (ZNAME, ZPUBLICID) values ('NoId', null);
SQL
  # open: records the link; "installs" by creating the .app unless told not to.
  cat >"$W/bin/open" <<STUB
#!/bin/bash
echo "open \$*" >>"$W/log"
[ -e "$W/noinstall" ] && exit 0
if [ -e "$W/busy-always" ]; then
  echo "Rejected install request: another installation is in progress" >>"$W/logs/Setapp.log"
  exit 0
fi
if [ -e "$W/busy-once" ]; then
  rm -f "$W/busy-once"
  echo "Rejected install request: another installation is in progress" >>"$W/logs/Setapp.log"
  exit 0
fi
id=\${1#*app_id=}
name=\$(sqlite3 -readonly "$W/db/Apps.sqlite" "select ZNAME from ZAPP where lower(hex(ZPUBLICID)) = lower(replace('\$id','-',''))")
[ -n "\$name" ] && mkdir -p "$W/apps/\$name.app"
exit 0
STUB
  printf '#!/bin/bash\necho "launchctl $*" >>"%s"\n' "$W/log" >"$W/bin/launchctl"
  printf '#!/bin/bash\nexit 0\n' >"$W/bin/pgrep"
  chmod +x "$W/bin/open" "$W/bin/launchctl" "$W/bin/pgrep"
}

# _sa_run <W> <names...> -- setapp_install_list in a clean bash.
_sa_run() {
  local W="$1"; shift
  env PATH="$W/bin:$PATH" HOME="$W/h" DOTFILES_SETAPP_APPS_DIR="$W/apps" \
    DOTFILES_SETAPP_DB="$W/db/Apps.sqlite" DOTFILES_SETAPP_LOG_DIR="$W/logs" \
    SETAPP_TIMEOUT="${SETAPP_TIMEOUT:-3}" SETAPP_POLL=0.1 SETAPP_SETTLE=0 \
    bash -c 'source scripts/echos.sh; source scripts/lib/setapp.sh; setapp_install_list "$@"' _ "$@"
}
_count() { grep -c "$2" "$1" || true; }

section "S1 -- catalogue lookup"
t "S1.1" "the uuid is the 16-byte blob formatted 8-4-4-4-12, lower case" '
  W=$(sandbox); _sa_env "$W"
  [ "$(bash -c "source scripts/lib/setapp.sh; DOTFILES_SETAPP_DB=$W/db/Apps.sqlite setapp_uuid Bartender")" = "00112233-4455-6677-8899-aabbccddeeff" ]'
t "S1.2" "the name match is case-insensitive" '
  W=$(sandbox); _sa_env "$W"
  [ "$(bash -c "source scripts/lib/setapp.sh; DOTFILES_SETAPP_DB=$W/db/Apps.sqlite setapp_uuid pAsTe")" = "a0a1a2a3-a4a5-a6a7-a8a9-aaabacadaeaf" ]'
t "S1.3" "a name with a single quote is looked up, not a syntax error" '
  W=$(sandbox); _sa_env "$W"
  [ "$(bash -c "source scripts/lib/setapp.sh; DOTFILES_SETAPP_DB=$W/db/Apps.sqlite setapp_uuid \"Bob'"'"'s Tool\"")" = "20212223-2425-2627-2829-202122232425" ]'
t "S1.4" "an unknown name, or one with no public id, gives nothing and fails" '
  W=$(sandbox); _sa_env "$W"
  ! bash -c "source scripts/lib/setapp.sh; DOTFILES_SETAPP_DB=$W/db/Apps.sqlite setapp_uuid Nope" &&
  ! bash -c "source scripts/lib/setapp.sh; DOTFILES_SETAPP_DB=$W/db/Apps.sqlite setapp_uuid NoId"'

section "S2 -- installing a list"
t "S2.1" "an app already in the apps dir is skipped: no link, no agent restart" '
  W=$(sandbox); _sa_env "$W"; mkdir "$W/apps/Bartender.app"
  _sa_run "$W" Bartender >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ ! -s "$W/log" ]'
t "S2.2" "a missing app: agent restarted, link opened with its uuid, app installed, status 0" '
  W=$(sandbox); _sa_env "$W"
  out=$(_sa_run "$W" Bartender 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -d "$W/apps/Bartender.app" ] &&
  [ "$(_count "$W/log" "^open setapp://install?app_id=00112233-4455-6677-8899-aabbccddeeff$")" -eq 1 ] &&
  [ "$(_count "$W/log" "^launchctl kickstart -k gui/$(id -u)/com.setapp.DesktopClient.SetappAgent$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "Setapp: click Install in the alert for Bartender")" -eq 1 ]'
t "S2.3" "the agent is restarted before the link is opened" '
  W=$(sandbox); _sa_env "$W"; _sa_run "$W" Bartender >/dev/null 2>&1
  [ "$(sed -n 1p "$W/log" | cut -d" " -f1)" = launchctl ] && [ "$(sed -n 2p "$W/log" | cut -d" " -f1)" = open ]'
t "S2.4" "apps go one at a time, each with its own restart" '
  W=$(sandbox); _sa_env "$W"; _sa_run "$W" Bartender Paste >/dev/null 2>&1
  [ "$(cut -d" " -f1 "$W/log" | tr "\n" " ")" = "launchctl open launchctl open " ]'
t "S2.5" "a name not in the catalogue is reported unknown, not opened, and fails the list" '
  W=$(sandbox); _sa_env "$W"
  out=$(_sa_run "$W" Nope 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_count "$W/log" "^open")" -eq 0 ] && printf "%s\n" "$out" | grep -qi "unknown.*Nope\|Nope.*unknown"'
t "S2.6" "one unknown app does not stop the next" '
  W=$(sandbox); _sa_env "$W"; _sa_run "$W" Nope Bartender >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ -d "$W/apps/Bartender.app" ]'
t "S2.7" "a busy rejection in the log restarts the agent and retries the link" '
  W=$(sandbox); _sa_env "$W"; : >"$W/busy-once"
  _sa_run "$W" Bartender >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ -d "$W/apps/Bartender.app" ] &&
  [ "$(_count "$W/log" "^open")" -eq 2 ] && [ "$(_count "$W/log" "^launchctl")" -eq 2 ]'
t "S2.8" "an old rejection already in the log is not mistaken for a new one" '
  W=$(sandbox); _sa_env "$W"; echo "Rejected install request: another installation is in progress" >"$W/logs/Setapp.log"
  _sa_run "$W" Bartender >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_count "$W/log" "^open")" -eq 1 ]'
t "S2.9" "retries stop after 3 tries and the app is reported failed" '
  W=$(sandbox); _sa_env "$W"
  : >"$W/busy-always"
  out=$(_sa_run "$W" Bartender 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_count "$W/log" "^open")" -eq 3 ]'
t "S2.10" "an install never clicked is reported timed out after SETAPP_TIMEOUT, status non-zero" '
  W=$(sandbox); _sa_env "$W"; : >"$W/noinstall"
  out=$(SETAPP_TIMEOUT=1 _sa_run "$W" Bartender 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s\n" "$out" | grep -qi "timed out.*Bartender\|Bartender.*timed out"'
t "S2.11" "a name with a quote installs" '
  W=$(sandbox); _sa_env "$W"; _sa_run "$W" "Bob'"'"'s Tool" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ -d "$W/apps/Bob'"'"'s Tool.app" ]'
t "S2.12" "installed apps are remembered for the caller (SETAPP_INSTALLED)" '
  W=$(sandbox); _sa_env "$W"; mkdir "$W/apps/Paste.app"
  env PATH="$W/bin:$PATH" HOME="$W/h" DOTFILES_SETAPP_APPS_DIR="$W/apps" DOTFILES_SETAPP_DB="$W/db/Apps.sqlite" \
    DOTFILES_SETAPP_LOG_DIR="$W/logs" SETAPP_POLL=0.1 SETAPP_SETTLE=0 \
    bash -c "source scripts/echos.sh; source scripts/lib/setapp.sh; setapp_install_list Bartender Paste >/dev/null 2>&1; [ \"\$SETAPP_INSTALLED\" = Bartender ]"'

section "S3 -- readiness and the install step"
_sa_list() { # _sa_list <W> <names...> -- a repo copy with its own packages/setapp.list
  local W="$1"; shift
  mkdir -p "$W/repo"; cp -R bin scripts macos "$W/repo/"; mkdir -p "$W/repo/packages"
  printf '%s\n' "$@" >"$W/repo/packages/setapp.list"
}
_sa_step_repo() {
  local W="$1"; shift
  env PATH="$W/bin:$PATH" HOME="$W/h" DOTFILES_DIR="$W/repo" DOTFILES_SETAPP_APPS_DIR="$W/apps" DOTFILES_SETAPP_APP="$W/Setapp.app" \
    DOTFILES_SETAPP_DB="$W/db/Apps.sqlite" DOTFILES_SETAPP_LOG_DIR="$W/logs" DOTFILES_YES=1 \
    SETAPP_TIMEOUT="${SETAPP_TIMEOUT:-2}" SETAPP_POLL=0.1 SETAPP_SETTLE=0 bash "$W/repo/bin/dotfiles" install --setapp </dev/null
}
MSG='open Setapp and sign in, then run `dotfiles install --setapp`'
t "S3.1" "Setapp.app missing: one skip line, status 0, nothing opened" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender
  out=$(_sa_step_repo "$W" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(_count "$W/log" "^open")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -cF "Setapp: $MSG")" -eq 1 ]'
t "S3.2" "catalogue DB missing (never opened): skip, status 0" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender; mkdir "$W/Setapp.app"; command rm "$W/db/Apps.sqlite"
  out=$(_sa_step_repo "$W" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(_count "$W/log" "^open")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -cF "Setapp: $MSG")" -eq 1 ]'
t "S3.3" "agent not running: skip, status 0" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender; mkdir "$W/Setapp.app"; printf "#!/bin/bash\nexit 1\n" >"$W/bin/pgrep"
  out=$(_sa_step_repo "$W" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(_count "$W/log" "^open")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -cF "Setapp: $MSG")" -eq 1 ]'
t "S3.4" "ready: the list (public plus local) is installed and the step succeeds" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender; printf "Paste\n" >"$W/repo/packages/setapp.local.list"; mkdir "$W/Setapp.app"
  _sa_step_repo "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ -d "$W/apps/Bartender.app" ] && [ -d "$W/apps/Paste.app" ]'
t "S3.5" "a timed-out app fails the step" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender; mkdir "$W/Setapp.app"; : >"$W/noinstall"
  ! SETAPP_TIMEOUT=1 _sa_step_repo "$W" >/dev/null 2>&1'
t "S3.6" "installing a Dock-listed app prints the dock hint; installing none does not" '
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" "Spark Mail"; mkdir "$W/Setapp.app"
  a=$(_sa_step_repo "$W" 2>&1)
  W=$(sandbox); _sa_env "$W"; _sa_list "$W" Bartender; mkdir "$W/Setapp.app"
  b=$(_sa_step_repo "$W" 2>&1)
  [ "$(printf "%s\n" "$a" | grep -cF "dotfiles configure --dock")" -eq 1 ] && [ "$(printf "%s\n" "$b" | grep -cF "dotfiles configure --dock")" -eq 0 ]'
t "S3.7" "the install help lists --setapp" \
  'out=$(bash bin/dotfiles install --help 2>&1); case "$out" in *"--setapp"*) true ;; *) false ;; esac'

section "S4 -- the lists"
t "S4.1" "packages/setapp.list exists with the owner apps, one per line" '
  [ -f packages/setapp.list ] && [ "$(grep -vcE "^[[:space:]]*(#|$)" packages/setapp.list)" -eq 15 ] && grep -qx "CleanShot X" packages/setapp.list && grep -qx "Spark Mail" packages/setapp.list'
t "S4.2" "packages/setapp.local.list is gitignored" 'git check-ignore -q packages/setapp.local.list'
t "S4.3" "every name in setapp.list matches the .app naming (no trailing space, no .app)" '
  ! grep -E "(^[[:space:]]|[[:space:]]$|\.app$)" packages/setapp.list'

finish

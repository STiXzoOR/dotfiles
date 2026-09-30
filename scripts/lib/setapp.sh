#!/usr/bin/env bash
# scripts/lib/setapp.sh -- install Setapp apps from a list, the way mas apps are.
#
# Setapp has no CLI. The one supported way in is its URL scheme:
# `open "setapp://install?app_id=<uuid>"` makes Setapp show its own "Install
# <App> from Setapp?" alert, and the user clicks Install (nothing can click it
# for us: System Events cannot see the alert). Each app's id is the
# ZPUBLICID blob in the catalogue database Setapp keeps once it has been opened.
#
# Setapp bug worked around here: after a link install its agent stays "busy" and
# rejects the next request ("another installation is in progress" in its log).
# Restarting the agent clears that, so it is restarted before every app and
# again whenever the log shows the rejection.
#
# Sourced by bin/dotfiles. Bash 3.2, BSD tools. Callers provide warn/action/ok/
# error from scripts/echos.sh. Every path and wait has an env seam for the tests.

setapp_apps_dir() { printf '%s' "${DOTFILES_SETAPP_APPS_DIR:-/Applications/Setapp}"; }
setapp_app() { printf '%s' "${DOTFILES_SETAPP_APP:-/Applications/Setapp.app}"; }
setapp_db() { printf '%s' "${DOTFILES_SETAPP_DB:-$HOME/Library/Application Support/Setapp/Default/Databases/Apps.sqlite}"; }
setapp_log_dir() { printf '%s' "${DOTFILES_SETAPP_LOG_DIR:-$HOME/Library/Logs/Setapp}"; }

# The Setapp UUID of an app, by its catalogue name (case-insensitive).
# Prints nothing and fails when the name is unknown or has no public id.
# Usage: setapp_uuid <name>
setapp_uuid() {
  local q="'" name id
  name=${1//$q/$q$q}
  id=$(sqlite3 -readonly "$(setapp_db)" "select lower(substr(h,1,8)||'-'||substr(h,9,4)||'-'||substr(h,13,4)||'-'||substr(h,17,4)||'-'||substr(h,21)) from (select hex(ZPUBLICID) h from ZAPP where ZNAME = '$name' collate nocase and ZPUBLICID is not null limit 1)" 2>/dev/null) || return 1
  [ -n "$id" ] || return 1
  printf '%s' "$id"
}

setapp_agent_running() { pgrep -f "SetappAgent -xpcServer" >/dev/null 2>&1; }

# Is Setapp ready to be driven? Prints nothing; the caller says why not.
setapp_ready() {
  [ -d "$(setapp_app)" ] && [ -f "$(setapp_db)" ] && setapp_agent_running
}

# Restart the agent and wait until it is back. SETAPP_SETTLE seconds more
# (default 4) let it finish starting; SETAPP_POLL is the poll step (default 3
# for installs, 1 here).
setapp_restart_agent() {
  local waited=0
  launchctl kickstart -k "gui/$(id -u)/com.setapp.DesktopClient.SetappAgent" >/dev/null 2>&1 || true
  while ! setapp_agent_running && [ "$waited" -lt 30 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  sleep "${SETAPP_SETTLE:-4}"
}

# How many busy rejections the Setapp logs hold right now.
_setapp_busy_count() {
  local f n=0 c
  for f in "$(setapp_log_dir)"/*.log; do
    [ -f "$f" ] || continue
    c=$(grep -c "Rejected install request.*another installation is in progress" "$f" 2>/dev/null || true)
    n=$((n + ${c:-0}))
  done
  printf '%s' "$n"
}

# Install one app. Returns 0 installed, 1 unknown, 2 timed out or rejected.
# Usage: _setapp_install_one <name>
_setapp_install_one() {
  local name="$1" id attempt=0 base waited result
  local timeout="${SETAPP_TIMEOUT:-300}" poll="${SETAPP_POLL:-3}" app
  app="$(setapp_apps_dir)/$name.app"
  id=$(setapp_uuid "$name") || return 1
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    setapp_restart_agent
    base=$(_setapp_busy_count)
    open "setapp://install?app_id=$id"
    action "Setapp: click Install in the alert for $name"
    # Seconds are counted in whole poll steps; awk does the float arithmetic
    # so a fractional SETAPP_POLL (the tests use 0.1) works in bash 3.2.
    waited=0
    result=timeout
    while :; do
      if [ -d "$app" ]; then
        result=ok
        break
      fi
      if [ "$(_setapp_busy_count)" -gt "$base" ]; then
        result=busy
        break
      fi
      if awk -v w="$waited" -v t="$timeout" 'BEGIN { exit !(w >= t) }'; then
        break
      fi
      sleep "$poll"
      waited=$(awk -v w="$waited" -v p="$poll" 'BEGIN { print w + p }')
    done
    case "$result" in
      ok) return 0 ;;
      timeout) return 2 ;;
    esac
    warn "Setapp was busy; restarting its agent and retrying $name ($attempt/3)"
  done
  return 2
}

# Install every named app that is not already in the Setapp apps dir, one at a
# time. Reports ok / skipped / unknown / timed out per app; returns non-zero if
# any app failed. SETAPP_INSTALLED holds the names installed by this call
# (newline separated), for the caller.
# Usage: setapp_install_list <name>...
setapp_install_list() {
  local name rc=0 r
  SETAPP_INSTALLED=""
  for name in "$@"; do
    [ -n "$name" ] || continue
    if [ -d "$(setapp_apps_dir)/$name.app" ]; then
      ok "Setapp: $name already installed, skipped"
      continue
    fi
    r=0
    _setapp_install_one "$name" || r=$?
    case "$r" in
      0)
        ok "Setapp: $name installed"
        SETAPP_INSTALLED="${SETAPP_INSTALLED:+$SETAPP_INSTALLED
}$name"
        ;;
      1)
        warn "Setapp: $name is unknown (not in the Setapp catalogue)"
        rc=1
        ;;
      *)
        warn "Setapp: $name timed out (no install seen; run dotfiles install --setapp again)"
        rc=1
        ;;
    esac
  done
  return $rc
}

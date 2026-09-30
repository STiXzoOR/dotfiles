#!/usr/bin/env bash
#
# tests/sync-gate.sh -- Jev skip gate in the scheduled run (G) and the final review fixes (F).
# Split from the former tests/sync.sh so the suites run in parallel; the shared
# fixtures live in tests/sync-lib.sh. HERMETIC: see the notes there and in
# tests/lib.sh (sandbox HOME, bare remotes in the sandbox, stubs on a sandbox PATH).
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/sync-lib.sh"

#############################################################################
section "G -- Jev skip gate in the scheduled run (Task 15)"
#############################################################################
# gate_env <W> <answer line>: a stub dotfiles-jev that logs its argv and
# answers the gate; the lock hash is primed so only a real fact counts as work.
gate_env() {
  local w="$1"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$STUB_LOG.jev"\nprintf "%%s\\n" "$STUB_GATE"\n' >"$w/bin/jev-stub"; chmod +x "$w/bin/jev-stub"
  mkdir -p "$w/home/.local/state/dotfiles"
  printf '' | shasum | cut -d' ' -f1 >"$w/home/.local/state/dotfiles/skip-sync.lockhash"
}
gsyn() { SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub STUB_GATE=$1" syn --scheduled; }
jevlog() { command cat "$W/log.jev" 2>/dev/null; }

t "G1" "SKIP from the gate ends the scheduled run before any git work" '
  W=$(senv); gate_env "$W"
  gsyn SKIP_low >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_calls "^stow")" -eq 0 ] && [ "$(_calls "^dotfiles-stub")" -eq 0 ] &&
  [ "$(jevlog | grep -c "^skip sync$")" -eq 1 ] &&
  [ "$(grep -c "skipped (Jev gate)" "$W/home/Library/Logs/dotfiles-sync.log")" -eq 1 ]'
t "G2" "RUN from the gate does the work as before" '
  W=$(senv); gate_env "$W"; push_change "$W" pub README.md new
  gsyn RUN_shadow >/dev/null 2>&1; [ "$(_head pub)" = "$(_remote pub)" ]'
t "G3" "upstream touching a package list is a deterministic fact, passed as --work" '
  W=$(senv); gate_env "$W"; push_change "$W" pub Brewfile "brew \"jq\""
  gsyn RUN_x >/dev/null 2>&1
  [ "$(jevlog | grep -c -- "--work upstream public commits touch Brewfile")" -eq 1 ]'
t "G4" "unpushed commits are deterministic work too" '
  W=$(senv); gate_env "$W"; git -C "$W/pub" commit -q --allow-empty -m local
  gsyn RUN_x >/dev/null 2>&1; [ "$(jevlog | grep -c -- "--work public repo has unpushed commits")" -eq 1 ]'
t "G5" "a first run (no lock hash yet) is work" '
  W=$(senv); gate_env "$W"; command rm -f "$W/home/.local/state/dotfiles/skip-sync.lockhash"
  gsyn RUN_x >/dev/null 2>&1; [ "$(jevlog | grep -c -- "--work lockfiles changed or first run")" -eq 1 ]'
t "G6" "quiet upstream, primed hash: no --work; the facts carry the upstream counts" '
  W=$(senv); gate_env "$W"; gsyn RUN_x >/dev/null 2>&1
  [ "$(jevlog | grep -c -- "--work")" -eq 0 ] && [ "$(jevlog | grep -c "^skip sync$")" -eq 1 ]'
t "G7" "an interactive run never asks the gate" '
  W=$(senv); gate_env "$W"; SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub STUB_GATE=SKIP" syn >/dev/null 2>&1
  [ "$(jevlog | grep -c .)" -eq 0 ]'
t "G8" "master switch off: the gate is never asked, the run proceeds" '
  W=$(senv); gate_env "$W"; push_change "$W" pub README.md new
  SYNENV="DOTFILES_JEV=off DOTFILES_JEV_BIN=$W/bin/jev-stub STUB_GATE=SKIP" syn --scheduled >/dev/null 2>&1
  [ "$(jevlog | grep -c .)" -eq 0 ] && [ "$(_head pub)" = "$(_remote pub)" ]'
t "G9" "a gate that fails runs the job (fail open)" '
  W=$(senv); gate_env "$W"; push_change "$W" pub README.md new
  printf "#!/bin/bash\nexit 3\n" >"$W/bin/jev-stub"
  SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub" syn --scheduled >/dev/null 2>&1
  [ "$(_head pub)" = "$(_remote pub)" ]'

t "G10" "the work scan sees the whole upstream diff: Brewfile as the 41st path is still work, with no request" '
  W=$(senv); gate_env "$W"; c=$(sandbox); git clone -q "$W/pub.git" "$c/x" 2>/dev/null
  i=0; while [ "$i" -lt 40 ]; do i=$((i + 1)); printf "x\n" >"$c/x/A$(printf %02d "$i")"; done; printf "brew \"jq\"\n" >>"$c/x/Brewfile"
  git -C "$c/x" add -A && git -C "$c/x" commit -q -m many && git -C "$c/x" push -q origin main 2>/dev/null
  gsyn SKIP_low >/dev/null 2>&1
  [ "$(jevlog | grep -c -- "--work upstream public commits touch Brewfile")" -eq 1 ] &&
  [ "$(jevlog | sed -n 1p | wc -w | tr -d " ")" -le 20 ]'
t "G11" "a failed fetch is work: the job runs, --work fetch failed" '
  W=$(senv); gate_env "$W"; command mv "$W/pub.git" "$W/gone.git"
  gsyn SKIP_low >/dev/null 2>&1
  [ "$(jevlog | grep -c -- "--work public fetch failed")" -eq 1 ]'
t "G12" "the lock hash is stamped only after a successful run" '
  W=$(senv); gate_env "$W"; h="$W/home/.local/state/dotfiles/skip-sync.lockhash"; command rm -f "$h"
  push_change "$W" pub README.md new; stub "$W/bin" stow "case \"\$*\" in -n*) printf \"cannot stow x\\n\"; exit 1;; esac"
  gsyn RUN_x >/dev/null 2>&1; [ ! -e "$h" ] &&
  stub "$W/bin" stow ":" && push_change "$W" pub README.md newer && { gsyn RUN_x >/dev/null 2>&1; [ -s "$h" ]; }'
t "G13" "the gate fetch has a connect timeout and keepalives" '
  [ "$(code_of bin/dotfiles-sync | grep -c "ConnectTimeout=10")" -ge 1 ] && [ "$(code_of bin/dotfiles-sync | grep -c "http.lowSpeedTime")" -ge 1 ] &&
  [ "$(code_of bin/dotfiles-sync | grep -c "ServerAliveInterval=15 -o ServerAliveCountMax=2")" -ge 1 ]'

#############################################################################
section "F -- final review fixes (strict prompts on a terminal, no-key precheck, vault watchdog, private paths)"
#############################################################################
# psyn: dsyn (Jev on, stubs) under a real pty (BSD script), typing the contents of $W/in. The
# pipe stays open until the run ends (script stops the child as soon as its own
# stdin reaches EOF); the wait is bounded at 30 s.
psyn() {
  local i=0
  { command cat "$W/in"; while [ ! -e "$W/done" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; } |
    { local rc; SYNWRAP="script -q /dev/null" SYNIN=/dev/stdin dsyn "$@"; rc=$?; : >"$W/done"; return "$rc"; }
}

t "F1.1" "on a real terminal the strict prompt reads the terminal, not the loop's heredoc: a typed y appends the line" '
  command -v script >/dev/null 2>&1 || return 0
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; printf "y\n" >"$W/in"
  psyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile | grep -c "^brew \"jq\"$")" -eq 1 ]'
t "F1.2" "on a real terminal a typed n adds nothing" '
  command -v script >/dev/null 2>&1 || return 0
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; printf "n\n" >"$W/in"
  psyn >/dev/null 2>&1
  [ "$(_lines pub/Brewfile | grep -c "jq")" -eq 0 ]'
t "F1.3" "a scheduled run under a terminal still never prompts" '
  command -v script >/dev/null 2>&1 || return 0
  W=$(senv); dstub "$W"; _undeclared; _suggest pkg brew:jq public; printf "y\ny\n" >"$W/in"
  psyn --scheduled >/dev/null 2>&1
  [ "$(_lines pub/Brewfile | grep -c "jq")" -eq 0 ]'
t "F1.4" "the terminal is captured once at startup of an interactive run only" '
  c=$(code_of bin/dotfiles-sync)
  [ "$(printf "%s\n" "$c" | grep -c "exec 5<&0")" -eq 1 ] && [ "$(printf "%s\n" "$c" | grep -c "<&5")" -ge 1 ]'

t "F3.1" "no API key: drift gathers no facts and asks nothing (no brew desc/uses, no Jev call)" '
  W=$(senv); dstub "$W"; stub "$W/bin" security "exit 44"; _undeclared
  DX="TYPESAFE_API_KEY=" dsyn >/dev/null 2>&1
  [ "$(_calls "^brew desc")" -eq 0 ] && [ "$(_calls "^brew uses")" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub drift")" -eq 0 ] && [ "$(_calls "^security")" -ge 1 ]'
t "F3.2" "no API key: apps gathers nothing" '
  W=$(senv); estub "$W"; stub "$W/bin" security "exit 44"; _asuggest gamma backup
  DX="TYPESAFE_API_KEY=" esyn >/dev/null 2>&1
  [ "$(_calls "^dotfiles-apps-stub")" -eq 0 ] && [ "$(_calls "^dotfiles-jev-stub apps")" -eq 0 ]'
t "F3.3" "no API key: the skip gate does no fetch of its own and no fact gathering, and the job still runs" '
  W=$(senv); gate_env "$W"; stub "$W/bin" security "exit 44"; stub "$W/bin" git "exec /usr/bin/git \"\$@\""; push_change "$W" pub README.md new
  SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub STUB_GATE=SKIP TYPESAFE_API_KEY=" syn --scheduled >/dev/null 2>&1
  [ "$(_calls "http.lowSpeedLimit")" -eq 0 ] && [ "$(jevlog | grep -c .)" -eq 0 ] && [ "$(_head pub)" = "$(_remote pub)" ]'
t "F3.4" "shadow mode gathers at most 10 package facts; on keeps the larger cap" '
  W=$(senv); dstub "$W" shadow; i=0; : >"$W/state/leaves"; while [ "$i" -lt 15 ]; do i=$((i + 1)); echo "pkg$i" >>"$W/state/leaves"; done
  dsyn >/dev/null 2>&1; a=$(_calls "^brew desc"); n=$(_facts pkg | grep -c .)
  W=$(senv); dstub "$W" on; i=0; : >"$W/state/leaves"; while [ "$i" -lt 15 ]; do i=$((i + 1)); echo "pkg$i" >>"$W/state/leaves"; done
  dsyn >/dev/null 2>&1
  [ "$a" -eq 10 ] && [ "$n" -eq 10 ] && [ "$(_calls "^brew desc")" -eq 15 ]'
t "F3.5" "shadow mode gathers at most 10 app candidates" '
  W=$(senv); estub "$W" shadow; i=0; while [ "$i" -lt 14 ]; do i=$((i + 1)); printf "app%s\tpaths=1\n" "$i" >>"$W/state/apps-candidates"; done
  esyn >/dev/null 2>&1; [ "$(_facts apps | grep -c .)" -eq 10 ]'

t "F4.1" "a vault scan that hangs is killed after the timeout, notifies, and writes no stamp; the run finishes" '
  W=$(senv); d=$(vault_of "$W"); stub "$W/bin" dotfiles-jev-stub "exec sleep 30"
  SYNENV="$(JEVSTUB_ENV "$W") DOTFILES_VAULT_SCAN_TIMEOUT=1" syn --scheduled >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "vault scan timed out" && [ ! -e "$(stampf "$W")" ]'
t "F4.2" "a scan that exits 2 is a failure: notified, no stamp" '
  W=$(senv); d=$(vault_of "$W"); jevstub "$W" 2 "cannot list"; SYNENV="$(JEVSTUB_ENV "$W")" syn --scheduled >/dev/null 2>&1
  [ "$(_calls "^osascript")" -eq 1 ] && grep "^osascript" "$W/log" | grep -q "vault scan could not run" && [ ! -e "$(stampf "$W")" ]'
t "F4.3" "a hung scan does not stop the notification or the lock-hash stamp" '
  W=$(senv); d=$(vault_of "$W"); h="$W/home/.local/state/dotfiles/skip-sync.lockhash"; mkdir -p "$(dirname "$h")"
  stub "$W/bin" dotfiles-jev-stub "case \"\$1\" in skip) echo RUN_x ;; scan-vault) exec sleep 30 ;; esac"
  SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/dotfiles-jev-stub DOTFILES_VAULT_SCAN_TIMEOUT=1" syn --scheduled >/dev/null 2>&1
  [ -s "$h" ] && grep "^osascript" "$W/log" | grep -q "timed out"'

t "F5.1" "the private repo contributes a count, never a path, to the gate facts and the work reason" '
  W=$(senv); stub "$W/bin" jev-stub '"'"'cat >>"$STUB_LOG.body"; echo RUN_x'"'"'
  mkdir -p "$W/home/.local/state/dotfiles"; printf "" | shasum | cut -d" " -f1 >"$W/home/.local/state/dotfiles/skip-sync.lockhash"
  push_change "$W" priv clients/acme.txt "x"; push_change "$W" priv claude/acme.md "y"
  SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub" syn --scheduled >/dev/null 2>&1
  b=$(command cat "$W/log.body"); a=$(grep "^jev-stub" "$W/log")
  [ "$(printf "%s\n" "$b" | grep -c "private repo: upstream commits since last run: 2")" -eq 1 ] &&
  [ "$(printf "%s\n%s\n" "$b" "$a" | grep -c acme)" -eq 0 ] && [ "$(printf "%s\n" "$a" | grep -c -- "--work upstream private")" -eq 1 ]'
t "F5.2" "the public repo still sends its paths" '
  W=$(senv); stub "$W/bin" jev-stub '"'"'cat >>"$STUB_LOG.body"; echo RUN_x'"'"'
  mkdir -p "$W/home/.local/state/dotfiles"; printf "" | shasum | cut -d" " -f1 >"$W/home/.local/state/dotfiles/skip-sync.lockhash"
  push_change "$W" pub docs/x.md "x"
  SYNENV="DOTFILES_JEV=shadow DOTFILES_JEV_BIN=$W/bin/jev-stub" syn --scheduled >/dev/null 2>&1
  [ "$(command cat "$W/log.body" | grep -c "public repo: paths touched upstream: docs/x.md")" -eq 1 ]'

t "F7.1" "behind upstream (either repo) is deterministic work: a pending pull is never skipped" '
  W=$(senv); gate_env "$W"; push_change "$W" pub README.md new
  gsyn SKIP_low >/dev/null 2>&1; a=$(jevlog | grep -c -- "--work public repo is behind upstream")
  W=$(senv); gate_env "$W"; push_change "$W" priv README.md new
  gsyn SKIP_low >/dev/null 2>&1
  [ "$a" -eq 1 ] && [ "$(jevlog | grep -c -- "--work private repo is behind upstream")" -eq 1 ]'

finish

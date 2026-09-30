#!/usr/bin/env bash
#
# Runs every tests/*.sh except lib.sh and this file, TEST_JOBS at a time.
# Exit non-zero if any suite failed. Arguments are passed through to each suite.
# shellcheck disable=SC2329  # _cleanup and _abort run via trap
set -uo pipefail

# lib.sh supplies the `timeout` shim (no GNU timeout on stock macOS or CI).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GitHub's macOS runner ignores SIGPIPE, which turns any endless producer piped
# into `head` into a hang. Ignored signals survive exec, so every suite inherits
# it: a local run now catches that class of bug. TEST_SUITE_TIMEOUT (seconds,
# default 900) bounds each suite; one that expires is named and the rest run.
trap "" PIPE

# TEST_JOBS suites run at once (default: hw.ncpu, at least 2; 1 is serial).
# bash 3.2 has no `wait -n`, so the pool polls recorded PIDs with `kill -0`.
# Each suite writes to its own file and is printed as one block, in
# alphabetical order, as soon as every earlier suite has finished.
suite_args=("$@")
jobs_max=${TEST_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null)}
case "$jobs_max" in '' | *[!0-9]*) jobs_max=2 ;; esac
if [ -z "${TEST_JOBS:-}" ] && [ "$jobs_max" -lt 2 ]; then jobs_max=2; fi
[ "$jobs_max" -ge 1 ] || jobs_max=1

suites=()
for f in tests/*.sh; do
  case "$(basename "$f")" in lib.sh | run.sh) continue ;; esac
  suites+=("$f")
done
total=${#suites[@]}

# Start order: the slowest suites first, so the pool does not end waiting on
# one long straggler. Serial runs keep alphabetical order (streams as it goes).
order=()
if [ "$jobs_max" -gt 1 ]; then
  for name in shell cli sync jev macos apps claude; do
    for ((i = 0; i < total; i++)); do
      [ "${suites[$i]}" = "tests/$name.sh" ] && order+=("$i")
    done
  done
fi
for ((i = 0; i < total; i++)); do
  case " ${order[*]:-} " in *" $i "*) ;; *) order+=("$i") ;; esac
done

outdir=$(mktemp -d "${TMPDIR:-/tmp}/dftests.XXXXXX") || exit 1
pids=()
running=()

# Kill a process and its descendants; only PIDs this script started.
_kill_tree() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do _kill_tree "$c"; done
  kill -TERM "$1" 2>/dev/null
}
_cleanup() { rm -rf "$outdir"; _sandbox_cleanup; }
_abort() {
  local i
  for i in ${running[@]+"${running[@]}"}; do _kill_tree "${pids[$i]}"; done
  _cleanup
  exit 130
}
trap _cleanup EXIT
trap _abort INT TERM

_start() { # _start <index>
  local i=$1 f=${suites[$1]}
  (
    started=$(date +%s)
    timeout "${TEST_SUITE_TIMEOUT:-900}" bash "$f" ${suite_args[@]+"${suite_args[@]}"}
    echo $? >"$outdir/$i.rc"
    echo $(($(date +%s) - started)) >"$outdir/$i.secs"
  ) >"$outdir/$i.out" 2>&1 &
  pids[i]=$!
  running+=("$i")
}

rc=0
ran=0
failed=()
printed=0
next=0
done_flags=()
while [ "$printed" -lt "$total" ]; do
  # reap finished suites
  still=()
  for i in ${running[@]+"${running[@]}"}; do
    if kill -0 "${pids[$i]}" 2>/dev/null; then
      still+=("$i")
    else
      wait "${pids[$i]}" 2>/dev/null
      done_flags[i]=1
    fi
  done
  running=(${still[@]+"${still[@]}"})
  # top up the pool
  while [ "$next" -lt "$total" ] && [ "${#running[@]}" -lt "$jobs_max" ]; do
    _start "${order[$next]}"
    next=$((next + 1))
  done
  # print blocks whose predecessors are all printed
  while [ "$printed" -lt "$total" ] && [ "${done_flags[$printed]:-}" = 1 ]; do
    i=$printed
    f=${suites[$i]}
    suite_rc=$(command cat "$outdir/$i.rc" 2>/dev/null || echo 1)
    secs=$(command cat "$outdir/$i.secs" 2>/dev/null || echo 0)
    printf '\n=== %s\n' "$f"
    command cat "$outdir/$i.out"
    printf -- '--- %s: %d s\n' "$f" "$secs"
    if [ "$suite_rc" -eq 124 ]; then
      printf 'TIMEOUT: %s exceeded %ss\n' "$f" "${TEST_SUITE_TIMEOUT:-900}"
      rc=1
      failed+=("$f (timeout)")
    elif [ "$suite_rc" -ne 0 ]; then
      rc=1
      failed+=("$f")
    fi
    ran=$((ran + 1))
    printed=$((printed + 1))
  done
  [ "$printed" -lt "$total" ] && sleep 0.2
done

printf '\n%s\n' "════════════════════════════════════════"
printf 'suites=%d failed_suites=%d\n' "$ran" "${#failed[@]}"
[ "$rc" -eq 0 ] || printf '  %s\n' "${failed[@]}"
exit "$rc"

#!/usr/bin/env bash
#
# Runs every tests/*.sh except lib.sh and this file. Exit non-zero if any
# suite failed. Arguments are passed through to each suite.
set -uo pipefail

# lib.sh supplies the `timeout` shim (no GNU timeout on stock macOS or CI).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# GitHub's macOS runner ignores SIGPIPE, which turns any endless producer piped
# into `head` into a hang. Ignored signals survive exec, so every suite inherits
# it: a local run now catches that class of bug. TEST_SUITE_TIMEOUT (seconds,
# default 600) bounds each suite; one that expires is named and the rest run.
trap "" PIPE

rc=0; ran=0; failed=()
for f in tests/*.sh; do
  case "$(basename "$f")" in lib.sh | run.sh) continue ;; esac
  printf '\n=== %s\n' "$f"
  timeout "${TEST_SUITE_TIMEOUT:-600}" bash "$f" "$@"
  suite_rc=$?
  if [ "$suite_rc" -eq 124 ]; then
    printf 'TIMEOUT: %s exceeded %ss\n' "$f" "${TEST_SUITE_TIMEOUT:-600}"
    rc=1; failed+=("$f (timeout)")
  elif [ "$suite_rc" -ne 0 ]; then
    rc=1; failed+=("$f")
  fi
  ran=$((ran + 1))
done

printf '\n%s\n' "════════════════════════════════════════"
printf 'suites=%d failed_suites=%d\n' "$ran" "${#failed[@]}"
[ "$rc" -eq 0 ] || printf '  %s\n' "${failed[@]}"
exit "$rc"

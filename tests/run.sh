#!/usr/bin/env bash
#
# Runs every tests/*.sh except lib.sh and this file. Exit non-zero if any
# suite failed. Arguments are passed through to each suite.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

rc=0; ran=0; failed=()
for f in tests/*.sh; do
  case "$(basename "$f")" in lib.sh | run.sh) continue ;; esac
  printf '\n=== %s\n' "$f"
  if ! bash "$f" "$@"; then rc=1; failed+=("$f"); fi
  ran=$((ran + 1))
done

printf '\n%s\n' "════════════════════════════════════════"
printf 'suites=%d failed_suites=%d\n' "$ran" "${#failed[@]}"
[ "$rc" -eq 0 ] || printf '  %s\n' "${failed[@]}"
exit "$rc"

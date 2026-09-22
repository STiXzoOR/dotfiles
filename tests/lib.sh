# tests/lib.sh -- shared harness for the bash test files under tests/.
#
# Source it, then call section/t, and end with finish. Assertions are
# single-quoted strings handed to eval inside t(), so they must NOT expand
# where they are written (SC2016 in callers is by design).
#
# pipefail is on. Never put `grep -q` (or head) on the right of a pipe fed by
# a chatty command: grep exits on the first match, the writer dies of SIGPIPE,
# and the pipeline reports non-zero -- which a leading `!` then turns into a
# false pass. Capture the output first, or use `grep -c` and compare.
#
# shellcheck shell=bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0; fail=0; failed_names=()

# Every sandbox lives under one per-run root so that `W=$(sandbox)` -- which
# runs sandbox in a subshell -- still gets cleaned up. Removed by finish and,
# if the suite dies early, by the EXIT trap.
_sandbox_root=$(mktemp -d "${TMPDIR:-/tmp}/dftest.XXXXXX") || exit 1
_sandbox_cleanup() { [ -n "${_sandbox_root:-}" ] && rm -rf "$_sandbox_root"; }
trap _sandbox_cleanup EXIT

t() { # t <id> <description> <shell expression>
  if eval "$3" >/dev/null 2>&1; then
    printf "  %s✓%s %s %s%s%s\n" "$GREEN" "$RESET" "$1" "$DIM" "$2" "$RESET"
    pass=$((pass + 1))
  else
    printf "  %s✗%s %s %s\n" "$RED" "$RESET" "$1" "$2"
    fail=$((fail + 1)); failed_names+=("$1 $2")
  fi
}

section() { printf "\n%s\n" "$1"; }

# Strip whole-line comments: assertions are about what the code does, not
# about whether a comment happens to name the thing it replaced.
code_of() { sed -E 's/^[[:space:]]*#.*$//' "$@"; }

# _first_line <pattern> <file> -- the line number of the first line of <file>
# containing <pattern> as a fixed string, or 0 if none does.
#
# Reads through code_of, so an ordering assertion cannot be satisfied by a
# comment that names the thing. code_of blanks rather than deletes, so line
# numbers still line up with the file.
_first_line() {
  code_of "$2" | awk -v p="$1" 'index($0, p) && !n { n = NR } END { print n + 0 }'
}

# A throwaway directory under $TMPDIR, removed by finish. Never under $HOME.
sandbox() {
  local d
  d=$(mktemp -d "$_sandbox_root/XXXXXX") || return 1
  printf '%s' "$d"
}

finish() {
  _sandbox_cleanup
  printf "\n%s\n" "────────────────────────────────────────"
  printf "passed=%d failed=%d\n" "$pass" "$fail"
  if [ "$fail" -gt 0 ]; then
    printf "\nfailing:\n"; printf "  %s\n" "${failed_names[@]}"
  fi
  [ "$fail" -eq 0 ]
}

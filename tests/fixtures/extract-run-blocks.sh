#!/usr/bin/env bash
#
# Splits the `run: |` blocks out of a GitHub Actions workflow into one bash
# script per block, under a directory of the caller's choosing.
#
# GitHub hands each block to bash. A block that parses only under bash 4+ is
# a trap that surfaces as a red run rather than as a test failure -- and it
# did: the zsh discovery step carried a one-line `case ... esac` inside a
# process substitution, which bash 3.2 cannot parse at all.
#
# Usage: extract-run-blocks.sh <workflow.yml> <outdir>
set -uo pipefail

file="${1:?workflow path required}"
outdir="${2:?output directory required}"
mkdir -p "$outdir" || exit 1

awk -v outdir="$outdir" '
  function indent_of(line) {
    match(line, /^[ \t]*/)
    return RLENGTH
  }
  # `run: |` or `run: |-` opens a block scalar.
  /^[ \t]*run:[ \t]*\|-?[ \t]*$/ {
    n += 1
    out = sprintf("%s/block-%03d.sh", outdir, n)
    print "#!/usr/bin/env bash" > out
    key_indent = indent_of($0)
    body_indent = -1
    inblock = 1
    next
  }
  inblock {
    if ($0 ~ /^[ \t]*$/) { print "" > out; next }
    this_indent = indent_of($0)
    if (body_indent < 0) {
      if (this_indent <= key_indent) { inblock = 0; next }
      body_indent = this_indent
    }
    if (this_indent < body_indent) { inblock = 0; next }
    print substr($0, body_indent + 1) > out
  }
  END { if (n == 0) exit 1 }
' "$file"

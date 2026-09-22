#!/usr/bin/env bash
#
# Install the bundled fonts into the user font directory.

set -euo pipefail

FONTS_SRC_DIR=$(cd "$(dirname "$0")" && pwd)
FONT_DIR="$HOME/Library/Fonts"

mkdir -p "$FONT_DIR"

echo "Copying fonts..."

# Was built as a string and run through `eval`, which needed an unquoted
# expansion to work at all. The glob also read '*.[o,t]tf' -- a character class
# that matches a literal comma as well as o and t.
find "$FONTS_SRC_DIR" \
  \( -name '*.[ot]tf' -o -name '*.pcf.gz' \) \
  -type f -print0 |
  xargs -0 -I {} cp "{}" "$FONT_DIR/"

echo "All fonts installed to $FONT_DIR"

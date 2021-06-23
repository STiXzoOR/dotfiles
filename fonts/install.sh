#!/usr/bin/env bash

# Set source and target directories
POWERLINE_FONTS_DIR=$(cd "$(dirname "$0")" && pwd)
FONT_DIR="$HOME/Library/Fonts"
FIND_COMMAND="find \"$POWERLINE_FONTS_DIR\" \( -name '*.[o,t]tf' -or -name '*.pcf.gz' \) -type f -print0"

echo "Copying fonts..."
eval $FIND_COMMAND | xargs -0 -I % cp "%" "$FONT_DIR/"

echo "All Powerline fonts installed to $FONT_DIR"

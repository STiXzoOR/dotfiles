#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults`, never executed: no `set -e`.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Xcode"
###############################################################################

running "Create xcode custom theme folder"
XCODE_THEME_DIR="$HOME/Library/Developer/Xcode/UserData/FontAndColorThemes"
if mkdir -p "$XCODE_THEME_DIR/"; then
  ok
else
  error "could not create $XCODE_THEME_DIR"
fi

# The theme is a git submodule. When it has not been checked out the source is
# missing, and linking to it would create a dangling symlink that reports ok.
XCODE_THEME_SRC="$DOTFILES_DIR/apps/xcode/nord_theme/src/Nord.xccolortheme"
XCODE_THEME_OK=0

running "Install nord theme"
if [ ! -f "$XCODE_THEME_SRC" ]; then
  warn "Nord theme not found at $XCODE_THEME_SRC (git submodule update --init --recursive); skipped"
else
  rm -f "$XCODE_THEME_DIR/Nord.xccolortheme" 2>/dev/null
  if ln -sf "$XCODE_THEME_SRC" "$XCODE_THEME_DIR/Nord.xccolortheme"; then
    XCODE_THEME_OK=1
    ok
  else
    error "could not link the Nord theme into $XCODE_THEME_DIR"
  fi
fi

running "Change theme to nord"
if [ "$XCODE_THEME_OK" = 1 ]; then
  defaults write com.apple.dt.Xcode XCFontAndColorCurrentTheme -string Nord.xccolortheme
  ok
else
  skip "the theme is not installed"
fi

running "Trim trailing whitespace"
defaults write com.apple.dt.Xcode DVTTextEditorTrimTrailingWhitespace -bool true
ok

running "Trim whitespace only lines"
defaults write com.apple.dt.Xcode DVTTextEditorTrimWhitespaceOnlyLines -bool true
ok

running "Show line numbers"
defaults write com.apple.dt.Xcode DVTTextShowLineNumbers -bool true
ok

# Note: IDEIndexDisable removed - disabling indexing breaks code completion and navigation
# If you need faster builds, use derived data RAM disk instead

running "Show ruler at 80 chars"
defaults write com.apple.dt.Xcode DVTTextShowPageGuide -bool true
defaults write com.apple.dt.Xcode DVTTextPageGuideLocation -int 80
ok

running "Map ⌃⌘L to show last change for the current line"
defaults write com.apple.dt.Xcode NSUserKeyEquivalents -dict-add "Show Last Change For Line" "@^l"
ok

running "Show build time"
defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool YES
ok

running "Improve performance by leveraging multi-core CPU"
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks "$(sysctl -n hw.ncpu)"
ok

killall "Xcode" >/dev/null 2>&1

###############################################################################
bot "Xcode"
###############################################################################

running "Create xcode custom theme folder"
CUSTOM_THEME_DIR="$HOMR/Library/Developer/Xcode/UserData/FontAndColorThemes"
mkdir -p "$CUSTOM_THEME_DIR/"
ok

running "Install nord theme"
ln -s "$DOTFILES_DIR/apps/xcode/nord_theme/src/Nord.xccolortheme $CUSTOM_THEME_DIR/Nord.xccolortheme"
ok

running "Change theme to nord"
defaults write com.apple.dt.Xcode XCFontAndColorCurrentTheme -string Nord.xccolortheme
ok

running "Trim trailing whitespace"
defaults write com.apple.dt.Xcode DVTTextEditorTrimTrailingWhitespace -bool true
ok

running "Trim whitespace only lines"
defaults write com.apple.dt.Xcode DVTTextEditorTrimWhitespaceOnlyLines -bool true
ok

running "Show line numbers"
defaults write com.apple.dt.Xcode DVTTextShowLineNumbers -bool true
ok

running "Reduce the number of compile tasks and stop indexing"
defaults write com.apple.dt.XCode IDEIndexDisable 1
ok

running "Show all devices and their information you have plugged in before"
defaults read com.apple.dt.XCode DVTSavediPhoneDevices
ok

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

running "Improve performance"
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks 5
ok

running "Improve performance by leveraging multi-core CPU"
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks $(sysctl -n hw.ncpu)
ok

running "Delete these settings"
defaults delete com.apple.dt.XCode IDEIndexDisable
ok

killall "Xcode" >/dev/null 2>&1

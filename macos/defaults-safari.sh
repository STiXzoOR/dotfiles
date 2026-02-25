source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Safari & WebKit"
###############################################################################

# NOTE: Since Safari 13 (Catalina), Safari is sandboxed. All `defaults write`
# commands require Terminal to have Full Disk Access, otherwise writes go to
# ~/Library/Preferences/ (which Safari ignores) instead of the container at
# ~/Library/Containers/com.apple.Safari/Data/Library/Preferences/
# Grant access in: System Settings > Privacy & Security > Full Disk Access
if ! ls ~/Library/Containers/com.apple.Safari/ &>/dev/null; then
  error "Terminal lacks Full Disk Access — Safari defaults will NOT take effect"
  error "Grant access in: System Settings > Privacy & Security > Full Disk Access"
fi

running "Don’t send search queries to Apple"
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true
ok

running "Press Tab to highlight each item on a web page"
defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks -bool true
ok

running "Show the full URL in the address bar (note: this still hides the scheme)"
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
ok

running "Set Safari’s home page to ‘about:blank’ for faster loading"
defaults write com.apple.Safari HomePage -string "about:blank"
ok

running "Prevent Safari from opening ‘safe’ files automatically after downloading"
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
ok

# For Mojave and up enable the keyboard shortcut but it requires to disable system integrity
# For High Sierra and below enable the default one
running "Allow hitting the Backspace key to go to the previous page in history"
defaults write com.apple.Safari NSUserKeyEquivalents -dict-add Back "\U232b"
ok

running "Hide Safari’s bookmarks bar by default"
defaults write com.apple.Safari ShowFavoritesBar -bool false
ok

# ShowSidebarInTopSites: Removed — "Top Sites" was replaced by "Start Page" in Safari 14 (Big Sur)

running "Disable Safari’s thumbnail cache for History and Top Sites"
defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
ok

# IncludeInternalDebugMenu: Non-functional since Safari 15+. The Develop menu
# (IncludeDevelopMenu below) is what most people want.

running "Make Safari’s search banners default to Contains instead of Starts With"
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
ok

running "Remove useless icons from Safari’s bookmarks bar"
defaults write com.apple.Safari ProxiesInBookmarksBar "()"
ok

running "Enable the Develop menu and the Web Inspector in Safari"
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
ok

running "Add a context menu item for showing the Web Inspector in web views"
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true
ok

running "Enable continuous spellchecking"
defaults write com.apple.Safari WebContinuousSpellCheckingEnabled -bool true
ok

running "Disable auto-correct"
defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled -bool false
ok

running "Disable AutoFill"
defaults write com.apple.Safari AutoFillFromAddressBook -bool false
defaults write com.apple.Safari AutoFillPasswords -bool false
defaults write com.apple.Safari AutoFillCreditCardData -bool false
defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false
ok

running "Warn about fraudulent websites"
defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true
ok

# Plugins and Java removed from Safari since macOS Catalina

running "Block pop-up windows"
defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false
ok

# Do Not Track removed from Safari since macOS Monterey

running "Update extensions automatically"
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true
ok

killall "Safari" >/dev/null 2>&1

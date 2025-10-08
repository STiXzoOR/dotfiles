source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Mail"
###############################################################################
running "Disable send and reply animations in Mail.app"
defaults write com.apple.mail DisableReplyAnimations -bool true
defaults write com.apple.mail DisableSendAnimations -bool true
ok

running "Copy email addresses as 'foo@example.com' instead of 'Foo Bar <foo@example.com>' in Mail.app"
defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
ok

running "Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app"
defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" -string "@\\U21a9"
ok

running "Display emails in threaded mode, sorted by date (oldest at the top)"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"
ok

running "Disable inline attachments (just show the icons)"
defaults write com.apple.mail DisableInlineAttachmentViewing -bool true
ok

running "Disable automatic spell checking"
defaults write com.apple.mail SpellCheckingBehavior -string "NoSpellCheckingEnabled"
ok

running "Disable includings results from trash in search"
defaults write com.apple.mail IndexTrash -bool false
ok

running "Automatically check for new message (not every 5 minutes)"
defaults write com.apple.mail AutoFetch -bool true
defaults write com.apple.mail PollTime -string "-1"
ok

running "Show most recent message at the top in conversations"
defaults write com.apple.mail ConversationViewSortDescending -bool true
ok

killall "Mail" >/dev/null 2>&1

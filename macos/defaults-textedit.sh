source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "TextEdit and Disk Utility"
###############################################################################
running "Use plain text mode for new documents"
defaults write com.apple.TextEdit RichText -int 0
ok

running "Open and save files as UTF-8"
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
ok

running "Use Meslo LGS Nerd Font"
defaults write com.apple.TextEdit NSFixedPitchFont "MesloLGSNer-Regular"
defaults write com.apple.TextEdit NSFixedPitchFontSize 14
ok

killall TextEdit >/dev/null 2>&1

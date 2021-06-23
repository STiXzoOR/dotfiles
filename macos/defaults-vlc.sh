###############################################################################
bot "VLC"
###############################################################################

running "Install settings"
if [ ! -d ~/Library/Preferences/org.videolan.vlc ]; then
  mkdir -p ~/Library/Preferences/org.videolan.vlc
fi

cp -f "$DOTFILES_DIR/apps/vlc/vlcrc" "$HOME/Library/Preferences/org.videolan.vlc/" 2>/dev/null
cp -f "$DOTFILES_DIR/apps/vlc/org.videolan.vlc.plist" "$HOME/Library/Preferences/org.videolan.vlc.plist" 2>/dev/null
ok

killall "VLC" >/dev/null 2>&1

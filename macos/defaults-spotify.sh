source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Spotify"
###############################################################################

running "Change theme to nord"
spicetify config current_theme Nord 2>/dev/null
spicetify backup apply 2>/dev/null
ok

killall "Spotify" >/dev/null 2>&1

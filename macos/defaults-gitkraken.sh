DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "GitKraken"
###############################################################################
GITKRAKEN_DIR="$HOME/.gitkraken"

running "Install nord theme"
ln -s "$DOTFILES_DIR/apps/gitkraken/themes/Themes/Nord/nord-dark.jsonc" "$GITKRAKEN_DIR/themes/nord-dark.jsonc" 2>/dev/null
ok

running "Link profile(s)"
ln -s "$DOTFILES_DIR/apps/gitkraken/profiles" "$GITKRAKEN_DIR/profiles" 2>/dev/null
ok

killall "GitKraken" >/dev/null 2>&1

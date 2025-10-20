DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "GitKraken"
###############################################################################
GITKRAKEN_DIR="$HOME/.gitkraken"

running "Install nord theme"
rm -f "$GITKRAKEN_DIR/themes/nord-dark.jsonc" 2>/dev/null
ln -sf "$DOTFILES_DIR/apps/gitkraken/themes/Themes/Nord/nord-dark.jsonc" "$GITKRAKEN_DIR/themes/nord-dark.jsonc" 2>/dev/null
ok

running "Link profile(s)"
rm -rf "$GITKRAKEN_DIR/profiles" 2>/dev/null
ln -sf "$DOTFILES_DIR/apps/gitkraken/profiles" "$GITKRAKEN_DIR/profiles" 2>/dev/null
ok

killall "GitKraken" >/dev/null 2>&1

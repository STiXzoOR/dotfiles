DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/requirers.sh"

###############################################################################
bot "Terminal"
###############################################################################

running "Only use UTF-8 in Terminal.app"
defaults write com.apple.terminal StringEncodings -array 4
ok

running "Install nord theme in Terminal.app"
open "$DOTFILES_DIR/apps/terminal/nord_theme/src/xml/Nord.terminal"
sleep 1
ok

running "Use nord theme by default in Terminal.app"
TERM_PROFILE='Nord'
CURRENT_PROFILE="$(defaults read com.apple.terminal 'Default Window Settings')"
if [ "${CURRENT_PROFILE}" != "${TERM_PROFILE}" ]; then
  defaults write com.apple.terminal 'Default Window Settings' -string "${TERM_PROFILE}"
  defaults write com.apple.terminal 'Startup Window Settings' -string "${TERM_PROFILE}"
fi
ok

running "Enable “focus follows mouse” for Terminal.app and all X11 apps"
defaults write com.apple.terminal FocusFollowsMouse -bool true
ok

###############################################################################
bot "Warp"
###############################################################################

running "Create warp custom theme folder"
CUSTOM_THEME_DIR="$HOME/.warp/themes"
mkdir -p "$CUSTOM_THEME_DIR/" 2>/dev/null
ok

running "Install themes for Warp"
rm -rf "$CUSTOM_THEME_DIR/*.yaml" 2>/dev/null
cp "$DOTFILES_DIR/apps/warp/themes/standard"/*.yaml "$CUSTOM_THEME_DIR/" 2>/dev/null
cp "$DOTFILES_DIR/apps/warp/themes/base16"/*.yaml "$CUSTOM_THEME_DIR/" 2>/dev/null
ok

killall "Warp" >/dev/null 2>&1

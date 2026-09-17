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

running "Seed profile(s) from template"
# The live profile is untracked: it holds userEmail/userName and every local
# repo path, and this repo is public. Seed it from the sanitized template only
# when it is missing, so an existing profile is never clobbered.
GITKRAKEN_PROFILE_TEMPLATE="$DOTFILES_DIR/apps/gitkraken/profile.template"
for _gk_profile_dir in "$DOTFILES_DIR"/apps/gitkraken/profiles/*/; do
  [ -d "$_gk_profile_dir" ] || continue
  if [ ! -f "$_gk_profile_dir/profile" ] && [ -f "$GITKRAKEN_PROFILE_TEMPLATE" ]; then
    cp "$GITKRAKEN_PROFILE_TEMPLATE" "$_gk_profile_dir/profile"
  fi
done
unset _gk_profile_dir
ok

running "Link profile(s)"
rm -rf "$GITKRAKEN_DIR/profiles" 2>/dev/null
ln -sf "$DOTFILES_DIR/apps/gitkraken/profiles" "$GITKRAKEN_DIR/profiles" 2>/dev/null
ok

killall "GitKraken" >/dev/null 2>&1

#!/usr/bin/env bash
#
# Regression tests for the 2026-09 audit findings.
#
# Each test names the finding it guards. They are written to fail against the
# pre-fix tree, so a regression re-breaks them rather than passing silently.
#
# Usage: tests/audit-regressions.sh [--verbose]
#
# Assertions are single-quoted strings handed to `eval` inside t(), so they
# must NOT expand where they are written. SC2016 flags exactly that, by design.
# shellcheck disable=SC2016

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0; fail=0; failed_names=()

t() { # t <id> <description> <shell expression>
  if eval "$3" >/dev/null 2>&1; then
    printf "  %s✓%s %s %s%s%s\n" "$GREEN" "$RESET" "$1" "$DIM" "$2" "$RESET"
    pass=$((pass + 1))
  else
    printf "  %s✗%s %s %s\n" "$RED" "$RESET" "$1" "$2"
    fail=$((fail + 1)); failed_names+=("$1 $2")
  fi
}

section() { printf "\n%s\n" "$1"; }

# Strip whole-line comments: these assertions are about what the code does,
# not about whether a comment happens to name the thing it replaced.
code_of() { sed -E 's/^[[:space:]]*#.*$//' "$@"; }

#############################################################################
section "S1.1 — dotfiles unlink must restore, not destroy the backup"
#############################################################################

# Replays sub_unlink's loop against a sandbox. Pre-fix this deleted the backup
# copy and left the $HOME symlink in place.
unlink_sandbox() {
  local w h b d
  w=$(mktemp -d); h="$w/home"; b="$h/.dotfiles_backup/2026.01.01"; d="$w/df/runcom"
  mkdir -p "$b" "$d"
  echo "REPO" >"$d/.testrc"
  ln -s "$d/.testrc" "$h/.testrc"
  echo "ORIGINAL" >"$b/.testrc"

  HOME="$h" bash -c '
    source "'"$ROOT_DIR"'/scripts/lib/fs.sh" 2>/dev/null || exit 3
    dotfiles_restore_backup "'"$b"'" || exit 4
  ' >/dev/null 2>&1 || { echo "$w"; return 1; }
  echo "$w"
}

W=$(unlink_sandbox) || true
t "S1.1a" "backup contents are restored into \$HOME" \
  '[ "$(cat "$W/home/.testrc" 2>/dev/null)" = "ORIGINAL" ]'
t "S1.1b" "\$HOME entry is no longer a symlink" \
  '[ ! -L "$W/home/.testrc" ]'
t "S1.1c" "sub_unlink uses the shared helper, not a bare unlink" \
  '! grep -qE "^\s+unlink \"\\\$file\"" bin/dotfiles'

#############################################################################
section "S1.2/S1.3 — secrets list and export must see the keychain"
#############################################################################

t "S1.3a" "keychain_list no longer parses legacy dump-keychain" \
  '! code_of bin/dotfiles-secrets | grep -q "security dump-keychain"'
t "S1.3b" "secrets list round-trips a real secret" '
  ./bin/dotfiles secrets set __audit_rt "v1" >/dev/null 2>&1
  out=$(./bin/dotfiles secrets list 2>/dev/null | grep -c "__audit_rt")
  ./bin/dotfiles secrets delete __audit_rt >/dev/null 2>&1
  [ "$out" -ge 1 ]'
t "S1.2"  "export refuses to exit 0 when it exported nothing" '
  ! grep -qE "No secrets to export\"?\s*$" bin/dotfiles-secrets || grep -q "exit 1" bin/dotfiles-secrets'
t "S1.4"  "secrets are piped to openssl, not staged in a temp file" \
  '! grep -qE "echo \"\\\$\{name\}=\\\$\{value\}\" >> \"\\\$temp_file\"" bin/dotfiles-secrets'

#############################################################################
section "S2 — the GNU/BSD stat trap"
#############################################################################

t "S2.0a" "scripts/lib/fs.sh provides dotfiles_mtime" \
  'grep -q "dotfiles_mtime()" scripts/lib/fs.sh'
t "S2.0b" "dotfiles_mtime returns an integer under this shell" '
  . scripts/lib/fs.sh
  m=$(dotfiles_mtime /etc/hosts); [ -n "$m" ] && [ "$m" -gt 0 ] 2>/dev/null'
t "S2.0c" "dotfiles_mtime works under zsh too" '
  zsh -c ". scripts/lib/fs.sh; m=\$(dotfiles_mtime /etc/hosts); [[ \$m -gt 0 ]]"'
# The BSD form must stay as a fallback (a bare Mac has no GNU stat); what
# matters is that GNU is probed FIRST, or that the shared helper is used.
for f in bin/dotfiles-doctor bin/dotfiles-profiler claude/hooks/index-sessions.sh; do
  t "S2.1" "GNU stat probed before BSD in $f" \
    'grep -qE "dotfiles_(mtime|filesize|age_days)" '"$f"' || grep -qE "stat -c[^|]*\|\|[^|]*stat -f" '"$f"''
done
t "S2.2" "doctor runs past Cache Status with GNU coreutils on PATH" '
  n=$(./bin/dotfiles-doctor 2>/dev/null | grep -c "━━━"); [ "$n" -ge 9 ]'

#############################################################################
section "S3 — fresh-install blockers"
#############################################################################

t "S3.1" "remote-install.sh probes git for real, not via 'type'" \
  'grep -qE "git --version|xcode-select -p" remote-install.sh'
t "S3.2a" "heavy submodules are shallow" \
  '[ "$(git config -f .gitmodules --get submodule.modules/stevenblack-hosts.shallow)" = "true" ]'
t "S3.2b" "spicetify themes are shallow" \
  '[ "$(git config -f .gitmodules --get submodule.config/spicetify/Themes.shallow)" = "true" ]'
t "S3.2c" "bootstrap clone is not unconditionally recursive" \
  '! code_of remote-install.sh | grep -q -- "--recurse-submodules"'
t "S3.4" "Brewfile uses quicklook-video, not the renamed qlvideo" \
  '! grep -qE "^cask \"qlvideo\"" Brewfile'

#############################################################################
section "S4 — CI and lint coverage"
#############################################################################

t "S4.3a" "CI lints scripts/lib" \
  'grep -q "scripts/lib" .github/workflows/ci.yml'
t "S4.4"  "pre-commit derives zsh scripts from the shebang" \
  'grep -qE "head -1.*zsh|shebang" .githooks/pre-commit'
t "S4.6"  "fonts/install.sh is shellcheck-clean" \
  'shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 fonts/install.sh'

#############################################################################
section "S5 — privacy and portability on a public repo"
#############################################################################

t "S5.1a" "git config carries no hardcoded identity" \
  '! grep -qiE "neostixz|Neoptolemos" config/git/config'
t "S5.1b" "git config includes a local override" \
  'grep -q "config.local" config/git/config'
t "S5.2a" "the live spicetify config is not tracked" \
  '[ -z "$(git ls-files config/spicetify/config-xpui.ini)" ]'
t "S5.2b" "its tracked template carries no hardcoded home path" \
  '[ -f config/spicetify/config-xpui.ini.template ] && ! grep -q "/Users/" config/spicetify/config-xpui.ini.template'
t "S5.3"  "macOS baseline has no hardcoded home path" \
  '! grep -q "/Users/stix" macos/baselines/15.6.1.tsv'
t "S5.4"  "repo gitignore covers .claude logs itself" \
  'git check-ignore -q .claude/command-history.log'

#############################################################################
section "S6 — drift and dead references"
#############################################################################

t "S6.1" "legacy packages/*.list path is gone" \
  '[ ! -f packages/brew.list ] && ! grep -q "brew.list" bin/dotfiles'
t "S6.2" "no references to non-existent system files" '
  ! code_of bin/dotfiles-profiler bin/dotfiles-cheatsheet .github/workflows/ci.yml \
    | grep -qE "system/\.(fix|function_macos)"'
t "S6.4" "zpreztorc does not load a non-existent identity" \
  '! grep -q "id_github" runcom/.zpreztorc'
# S6.5 withdrawn: com.apple.mail keys are valid (defaults write creates a
# missing domain) and the BluetoothAudioAgent line was already commented out.
# What is worth guarding is the shape that mistake would have produced -- a
# defaults script that prints ok without performing any write.
t "S6.5" "no defaults script reports ok without doing any work" '
  bad=0
  for f in macos/defaults-*.sh; do
    w=$(grep -cE "defaults write|PlistBuddy|osascript|chflags|killall" "$f")
    o=$(grep -cE "^[[:space:]]*ok\b" "$f")
    if [ "$o" -gt 0 ] && [ "$w" -eq 0 ]; then bad=1; fi
  done
  [ "$bad" -eq 0 ]'

#############################################################################
section "S7 / Claude bootstrap"
#############################################################################

t "S7.1" "XDG_RUNTIME_DIR does not accumulate fnm multishells forever" \
  'grep -qE "TMPDIR|fnm_multishells" system/.env scripts/lib/*.sh bin/dotfiles 2>/dev/null'
t "CB.1" "exactly two marketplaces are bootstrapped" '
  n=$(grep -cvE "^\s*(#|$)" claude/marketplaces.list); [ "$n" -eq 2 ]'
t "CB.2" "superpowers marketplace is present" \
  'grep -q "superpowers-marketplace" claude/marketplaces.list'
t "CB.3" "compound engineering marketplace is present" \
  'grep -qi "compound-engineering" claude/marketplaces.list'
t "CB.4" "every plugin resolves to one of those two marketplaces" '
  bad=$(grep -vE "^[[:space:]]*(#|$)" claude/plugins.list \
        | grep -vE "@(superpowers-marketplace|compound-engineering-plugin)$" | wc -l)
  [ "$bad" -eq 0 ]'
t "CB.5" "exactly two plugins" '
  n=$(grep -cvE "^[[:space:]]*(#|$)" claude/plugins.list); [ "$n" -eq 2 ]'
t "CB.6" "the status line script the settings reference is tracked" \
  '[ -n "$(git ls-files claude/statusline.sh)" ]'
t "CB.7" "every hook the settings template references exists in the repo" '
  ok=1
  for h in $(grep -oE "\\$HOME/\.claude/hooks/[a-z-]+\.sh" claude/settings.template.json | sort -u); do
    [ -f "claude/hooks/$(basename "$h")" ] || ok=0
  done
  [ "$ok" -eq 1 ]'
t "CB.8" "installer verifies settings references" \
  'grep -q "verify_settings_refs" scripts/install_claude.sh'

#############################################################################
printf "\n%s\n" "────────────────────────────────────────"
printf "passed=%d failed=%d\n" "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf "\nfailing:\n"; printf "  %s\n" "${failed_names[@]}"
fi
[ "$fail" -eq 0 ]

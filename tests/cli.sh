#!/usr/bin/env bash
#
# tests/cli.sh -- regression tests for the 2026-09-21 audit, CLI workstream
# (WS-A: bin/dotfiles, bin/dotfiles-setup, bin/dotfiles-doctor,
# bin/dotfiles-profiler, scripts/echos.sh, scripts/requirers.sh,
# scripts/lib/*.sh, scripts/install_prezto.zsh, remote-install.sh).
#
# Assertions are single-quoted strings evaluated by t(); they must not expand
# where they are written.
#
# Source greps read `<(code_of ...)` rather than `code_of ... | grep`. The
# harness runs under pipefail, so when grep -q exits on its first match the
# writing sed can die of SIGPIPE and the pipeline reports 141 -- which flips
# both plain and negated assertions at random under load.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "A0 — scripts/echos.sh helpers"
#############################################################################

# Every one of these is routinely called bare (`ok`, `skip`), and the helpers
# read $1 directly. Under a caller with `set -u` -- which bin/dotfiles-setup,
# remote-install.sh and fonts/install.sh all use -- that aborts the caller
# with "$1: unbound variable" at the moment it reports success.
t "A0.1" "helpers tolerate a missing argument under set -u" \
  '(set -u; source scripts/echos.sh; bot; ok; skip; running; action; warn; error) >/dev/null 2>&1'

#############################################################################
section "A1 — confirm() anchored, non-interactive aware"
#############################################################################

t "A1.1" "Nay is not yes" '! (source scripts/echos.sh; printf "Nay\n" | confirm "q")'
t "A1.2" "absolutely not is not yes" '! (source scripts/echos.sh; printf "absolutely not\n" | confirm "q")'
t "A1.3" "yes is yes" '(source scripts/echos.sh; printf "yes\n" | confirm "q")'
t "A1.4" "Y is yes" '(source scripts/echos.sh; printf "Y\n" | confirm "q")'
t "A1.5" "EOF is no" '! (source scripts/echos.sh; confirm "q" </dev/null)'
t "A1.6" "DOTFILES_YES=1 skips the prompt" '(source scripts/echos.sh; DOTFILES_YES=1 confirm "q" </dev/null)'
t "A1.7" "no unanchored yes-regex remains in bin/dotfiles" \
  '! grep -qE "=~ \(yes\|y\|Y\)|=~ \(y\|yes\|Y\)|=~ \^\(y\|Y\)" <(code_of bin/dotfiles)'
t "A1.8" "install --all sets DOTFILES_YES" 'grep -qE "DOTFILES_YES=1" <(code_of bin/dotfiles)'

#############################################################################
section "A2 — require_* helpers report real status"
#############################################################################

t "A2.1" "require_brew passes only real args" \
  '! grep -q "brew install \"\$1\" \"\$2\"" <(code_of scripts/requirers.sh)'
t "A2.2" "require_brew fails when brew install fails" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; [ \"\$1\" = install ] && exit 9; exit 0\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  ! (PATH="$W/bin:$PATH"; source scripts/echos.sh; source scripts/requirers.sh; require_brew nonesuch >/dev/null 2>&1)'
# Capture, never pipe. The brief spelled this
# `! ( … require_brew … ) | grep -q "ok"`, which cannot fail: under the
# harness pipefail the subshell exit status 1 sinks the pipeline whatever grep
# does, and the leading `!` turns that into a pass. Demonstrated:
# `! (echo "[ok]"; exit 1) | grep -q ok` succeeds.
t "A2.3" "require_brew does not print ok after failure" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; exit 9\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  out=$( (PATH="$W/bin:$PATH"; source scripts/echos.sh; source scripts/requirers.sh; require_brew nonesuch) 2>&1 || true )
  case "$out" in *ok*) false ;; *) true ;; esac'
t "A2.4" "no homebrew/cask-fonts tap anywhere" \
  '! grep -q "cask-fonts" <(code_of bin/dotfiles scripts/requirers.sh)'
t "A2.5" "require_code resolves a code binary, not a variable" \
  '! grep -qE "\|\| code=\"" <(code_of scripts/requirers.sh)'

#############################################################################
section "A3 — submodules are initialised on demand"
#############################################################################

t "A3.1" "ensure_submodule is a no-op on an initialised module" '
  W=$(sandbox); mkdir -p "$W/repo/mod"; touch "$W/repo/mod/.git"
  (DOTFILES_DIR="$W/repo"; source scripts/lib/fs.sh; dotfiles_ensure_submodule mod)'
t "A3.2" "ensure_submodule initialises a missing module shallowly" '
  W=$(sandbox); git init -q "$W/up"; (cd "$W/up" && git commit -q --allow-empty -m a && git commit -q --allow-empty -m b)
  git init -q "$W/repo"; (cd "$W/repo" && git -c protocol.file.allow=always submodule add -q "$W/up" mod >/dev/null 2>&1 && git commit -q -m add && git submodule deinit -f -q mod)
  (DOTFILES_DIR="$W/repo"; source scripts/lib/fs.sh; git -C "$W/repo" config protocol.file.allow always; dotfiles_ensure_submodule mod) && [ -e "$W/repo/mod/.git" ]'
t "A3.3" "install_prezto.zsh fails when prezto is absent" '
  W=$(sandbox); mkdir -p "$W/df/modules"; ! (DOTFILES_DIR="$W/df" HOME="$W/h" zsh scripts/install_prezto.zsh)'
t "A3.4" "sub_install_prezto calls the helper" \
  'grep -q "dotfiles_ensure_submodule modules/prezto" <(code_of bin/dotfiles)'

#############################################################################
section "A4 — fnm prune protects directories a live process uses"
#############################################################################

t "A4.1" "a dir referenced by a running process env is spared even with a dead pid" '
  W=$(sandbox); mkdir -p "$W/fnm_multishells"
  live="$W/fnm_multishells/99999996_1700000000"; mkdir -p "$live"; touch -t 202001010000 "$live"
  ( FNM_MULTISHELL_PATH="$live" sleep 20 ) & sp=$!
  disown "$sp" 2>/dev/null || true
  # Give the process table time to show the child even on a loaded machine.
  sleep 1
  ( . scripts/lib/fs.sh; XDG_RUNTIME_DIR="$W" dotfiles_prune_fnm_multishells )
  r=$?; kill $sp 2>/dev/null; [ -e "$live" ]'

#############################################################################
section "A5 — no NOPASSWD sudoers writer"
#############################################################################

t "A5.1" "sub_install_passwordless is gone" \
  '! grep -q "sub_install_passwordless" <(code_of bin/dotfiles)'
t "A5.2" "nothing writes /etc/sudoers" \
  '! grep -q "/etc/sudoers" <(code_of bin/dotfiles bin/dotfiles-setup)'
t "A5.3" "doctor checks sudo_local for pam_tid" \
  'grep -q "pam_tid" <(code_of bin/dotfiles-doctor)'
t "A5.4" "doctor checks the update-proof sudo_local, not just /etc/pam.d/sudo" \
  'grep -q "pam.d/sudo_local" <(code_of bin/dotfiles-doctor)'
t "A5.5" "the --passwordless help line is gone" \
  '! grep -q -- "--passwordless" <(code_of bin/dotfiles)'

#############################################################################
section "A6 — hosts installs the prebuilt file"
#############################################################################

t "A6.1" "no python venv or submodule in the hosts flow" \
  '! grep -qE "venv|updateHostsFile|stevenblack-hosts" <(code_of bin/dotfiles)'
t "A6.2" "hosts URL is https raw StevenBlack" \
  'grep -q "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" <(code_of bin/dotfiles)'
t "A6.3" "whitelist filter removes listed domains" '
  W=$(sandbox); printf "0.0.0.0 amplitude.com\n0.0.0.0 evil.example\n" > "$W/hosts"; printf "amplitude.com\n" > "$W/wl"
  (source scripts/lib/fs.sh; dotfiles_hosts_apply_whitelist "$W/hosts" "$W/wl" > "$W/out"); ! grep -q amplitude.com "$W/out" && grep -q evil.example "$W/out"'
t "A6.4" "downloaded file is validated before install" \
  'grep -q "StevenBlack/hosts" <(code_of bin/dotfiles) && grep -qE "wc -l|Number of unique domains" <(code_of bin/dotfiles)'
t "A6.5" "the hosts prompt says NextDNS users can skip it" \
  'grep -q "NextDNS" <(code_of bin/dotfiles)'
t "A6.6" "whitelist filter keeps comments and blank lines" '
  W=$(sandbox); printf "# Title: StevenBlack/hosts\n\n0.0.0.0 evil.example\n" > "$W/hosts"; printf "amplitude.com\n" > "$W/wl"
  (source scripts/lib/fs.sh; dotfiles_hosts_apply_whitelist "$W/hosts" "$W/wl" > "$W/out")
  grep -q "# Title: StevenBlack/hosts" "$W/out"'

#############################################################################
section "A7 — Homebrew 7 tap trust"
#############################################################################

t "A7.1" "every declared tap is trusted before bundle" \
  'grep -q "brew trust --tap" <(code_of bin/dotfiles)'
# The brief spelled this as `! grep -A1 "brew bundle install" | grep "^ *ok"`,
# which cannot tell a guarded ok from an unguarded one -- `if brew bundle
# install; then ok ...` matches it too. Exercise the function instead.
t "A7.2" "brew bundle install failure is not reported as ok" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = bundle ] && exit 9\nexit 0\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/code"; chmod +x "$W/bin/code"
  sed -n "/^sub_install_packages()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:$PATH"; ROOT_DIR="$PWD"; DOTFILES_YES=1; DOTFILES_CODE_BIN_FALLBACK="$W/none"
     source scripts/echos.sh; source "$W/fn.sh"; sub_install_packages >/dev/null 2>&1)'
t "A7.2b" "a successful bundle still reports ok" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/npm"; chmod +x "$W/bin/npm"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/fnm"; chmod +x "$W/bin/fnm"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/code"; chmod +x "$W/bin/code"
  sed -n "/^sub_install_packages()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  (PATH="$W/bin:$PATH"; ROOT_DIR="$PWD"; DOTFILES_YES=1
   source scripts/echos.sh; source scripts/requirers.sh; source "$W/fn.sh"
   sub_install_packages >/dev/null 2>&1)'
t "A7.3" "doctor requires Homebrew 7" \
  'grep -qE "brew --version|HOMEBREW_VERSION" <(code_of bin/dotfiles-doctor)'
t "A7.4" "doctor names the minimum major version, not just the version string" \
  'grep -q "BREW_MIN_MAJOR" <(code_of bin/dotfiles-doctor)'
t "A7.5" "no unguarded recursive delete of the Homebrew system cache" \
  '! grep -q "rm -f -r /Library/Caches/Homebrew" <(code_of bin/dotfiles)'
t "A7.6" "no blanket quarantine stripping of QuickLook plugins" \
  '! grep -qE "QuickLook|xattr[^|]* -[a-zA-Z]*r" <(code_of bin/dotfiles)'
t "A7.7" "the packages step warns that mas entries need an App Store login" \
  'grep -q "mas entries need" <(code_of bin/dotfiles)'

#############################################################################
section "A8 — Apple silicon only, headless Command Line Tools"
#############################################################################

t "A8.1" "no /usr/local prefix branch in bin/" \
  '! grep -q "/usr/local" <(code_of bin/dotfiles bin/dotfiles-setup bin/dotfiles-doctor)'
t "A8.1b" "no /usr/local prefix branch in scripts/" \
  '! grep -q "/usr/local" <(code_of scripts/requirers.sh scripts/echos.sh scripts/lib/fs.sh scripts/lib/ssh.sh)'
t "A8.2" "is-apple-silicon is deleted" '[ ! -e bin/is-apple-silicon ]'
# Capture rather than pipe: the guard exits 1 by design, and under pipefail
# that status would sink the pipeline however the grep went.
t "A8.3" "non-arm64 exits early with a message" '
  W=$(sandbox); mkdir -p "$W/bin"; printf "#!/bin/bash\necho x86_64\n" > "$W/bin/uname"; chmod +x "$W/bin/uname"
  out=$(PATH="$W/bin:$PATH" bash bin/dotfiles help 2>&1 || true)
  case "$out" in *"Apple silicon only"*) true ;; *) false ;; esac'
t "A8.3b" "the arch guard exits non-zero" '
  W=$(sandbox); mkdir -p "$W/bin"; printf "#!/bin/bash\necho x86_64\n" > "$W/bin/uname"; chmod +x "$W/bin/uname"
  ! (PATH="$W/bin:$PATH" bash bin/dotfiles help >/dev/null 2>&1)'
t "A8.3c" "arm64 is not blocked" 'out=$(bash bin/dotfiles help 2>&1); [ "$(printf "%s\n" "$out" | grep -c "Usage:")" -ge 1 ]'
t "A8.3d" "remote-install.sh guards the architecture too" \
  'grep -q "Apple silicon only" <(code_of remote-install.sh)'
t "A8.4" "print_result is defined" \
  '(source scripts/echos.sh; declare -F print_result >/dev/null)'
t "A8.4b" "print_result reports failure as an error" \
  '(source scripts/echos.sh; print_result 1 boom) | grep -q "error"'
t "A8.4c" "print_result reports success as ok" \
  '(source scripts/echos.sh; print_result 0 fine) | grep -q "ok"'
t "A8.5" "CLT install is headless via softwareupdate" \
  'grep -q "softwareupdate" <(code_of scripts/lib/clt.sh) && grep -q "xcode-select -s" <(code_of scripts/lib/clt.sh)'
t "A8.6" "xcode wait loop is bounded" \
  '! grep -q "until xcode-select" <(code_of bin/dotfiles scripts/lib/clt.sh)'
t "A8.6b" "xcodebuild -license only runs against a real Xcode" \
  '! grep -qE "^[[:space:]]*sudo xcodebuild -license$" <(code_of bin/dotfiles scripts/lib/clt.sh)'
t "A8.7" "closing advice uses -- flags" \
  '! grep -qE "BIN_NAME install (hosts|prezto|vim|fonts|packages|launchagents)\b" <(code_of bin/dotfiles)'
t "A8.8" "install never killalls Terminal" \
  '! grep -q "killall \"Terminal\"" <(code_of bin/dotfiles)'
t "A8.8b" "install does not open an app that packages has not installed yet" \
  '! grep -q "open /Applications/Warp.app" <(code_of bin/dotfiles)'

#############################################################################
section "A9 (link/unlink/ssh) — both stow targets are backed up and restorable"
#############################################################################

# The brief spelled A9.1 as a grep for "XDG_CONFIG_HOME/$file" or for
# "stow --restow --adopt". --adopt is not used here: it absorbs whatever is in
# the way into the tracked tree, which would silently overwrite the repo's own
# copy with the machine's. The backup sweep below makes it unnecessary, so the
# assertion exercises the behaviour instead of a spelling.
t "A9.1" "link backs up ~/.config targets too" '
  W=$(sandbox); mkdir -p "$W/pkg/git" "$W/target/git" "$W/backup"
  echo MINE > "$W/target/git/config"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/pkg" "$W/target" "$W/backup")
  [ -f "$W/backup/git/config" ] && [ ! -e "$W/target/git" ]'
# The backup-side checks use -L, not -e: a relative link moved into the
# backup directory usually dangles from there, so -e would report it absent
# however the sweep classified it.
#
# Relative, because that is what stow creates: on this machine
# `readlink ~/.zshrc` is `.dotfiles/runcom/.zshrc` and `readlink ~/.config/git`
# is `../.dotfiles/config/git`. The absolute link this used to build is a case
# that does not arise, so it hid a dead own-link branch.
t "A9.1b" "a relative symlink into the package is left in place, not backed up" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/target" "$W/backup"
  echo REPO > "$W/df/runcom/.testrc"
  ln -s "../df/runcom/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/runcom" "$W/target" "$W/backup")
  [ -L "$W/target/.testrc" ] && [ ! -L "$W/backup/.testrc" ]'
t "A9.1e" "an absolute symlink into the package is left in place too" '
  W=$(sandbox); mkdir -p "$W/pkg" "$W/target" "$W/backup"
  echo REPO > "$W/pkg/.testrc"; ln -s "$W/pkg/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/pkg" "$W/target" "$W/backup")
  [ -L "$W/target/.testrc" ] && [ ! -L "$W/backup/.testrc" ]'
t "A9.1f" "a relative symlink pointing outside the package is still backed up" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/target" "$W/backup" "$W/elsewhere"
  echo THEIRS > "$W/elsewhere/.testrc"; : > "$W/df/runcom/.testrc"
  ln -s "../elsewhere/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/runcom" "$W/target" "$W/backup")
  [ -L "$W/backup/.testrc" ]'
t "A9.1g" "a nested relative link, as stow makes under ~/.config, is left in place" '
  W=$(sandbox); mkdir -p "$W/df/config/git" "$W/target/xdg" "$W/backup"
  echo REPO > "$W/df/config/git/config"
  ln -s "../../df/config/git" "$W/target/xdg/git"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/config" "$W/target/xdg" "$W/backup")
  [ -L "$W/target/xdg/git" ] && [ ! -L "$W/backup/git" ]'
t "A9.1c" "a foreign symlink is preserved in the backup" '
  W=$(sandbox); mkdir -p "$W/pkg" "$W/target" "$W/backup" "$W/elsewhere"
  echo THEIRS > "$W/elsewhere/.testrc"; : > "$W/pkg/.testrc"
  ln -s "$W/elsewhere/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/pkg" "$W/target" "$W/backup")
  [ -L "$W/backup/.testrc" ]'
t "A9.1d" "link stows config against XDG_CONFIG_HOME through the shared helper" \
  'grep -q "dotfiles_stow_all - \"\$ROOT_DIR\" \"\$HOME\" \"\$XDG_CONFIG_HOME\"" <(code_of bin/dotfiles) && grep -q "dotfiles_stow \"\$1\" \"\$4\" config" <(code_of scripts/lib/fs.sh)'
t "A9.2" "unlink on an empty backup does not claim success" '
  W=$(sandbox); mkdir -p "$W/h/.dotfiles_backup/2026.01.01"
  out=$(HOME="$W/h" bash bin/dotfiles unlink 2026.01.01 2>&1 || true)
  case "$out" in *"restored into"*) false ;; *) true ;; esac'
# XDG_CONFIG_HOME deliberately points somewhere other than $HOME/.config:
# bin/dotfiles used to export it unconditionally, so a caller that set it was
# ignored and this assertion would have passed without restoring anything.
t "A9.2b" "unlink restores a .config bucket into XDG_CONFIG_HOME" '
  W=$(sandbox); mkdir -p "$W/h/.dotfiles_backup/2026.01.01/.config/git" "$W/xdg"
  echo ORIGINAL > "$W/h/.dotfiles_backup/2026.01.01/.config/git/config"
  HOME="$W/h" XDG_CONFIG_HOME="$W/xdg" bash bin/dotfiles unlink 2026.01.01 >/dev/null 2>&1
  [ "$(cat "$W/xdg/git/config" 2>/dev/null)" = "ORIGINAL" ]'
t "A9.2d" "XDG_CONFIG_HOME set by the caller is respected" \
  'grep -q "XDG_CONFIG_HOME:-" <(code_of bin/dotfiles)'
t "A9.2c" "restore_backup still defaults to \$HOME" '
  W=$(sandbox); mkdir -p "$W/h" "$W/b"
  echo ORIGINAL > "$W/b/.testrc"
  (HOME="$W/h"; source scripts/lib/fs.sh; dotfiles_restore_backup "$W/b")
  [ "$(cat "$W/h/.testrc" 2>/dev/null)" = "ORIGINAL" ]'
t "A9.3" "no eval ssh-agent in install --ssh" \
  '! grep -q "eval \"\$(ssh-agent -s)\"" <(code_of bin/dotfiles)'
t "A9.17" "ssh config helper checks for the Host * block, not IdentityFile" \
  '! grep -q "grep -q \"IdentityFile" <(code_of scripts/lib/ssh.sh)'
t "A9.17b" "a config with IdentityFile but no Host * block still gets the block" '
  W=$(sandbox); mkdir -p "$W/h/.ssh"
  printf "Host github.com\n  IdentityFile ~/.ssh/id_ed25519\n" > "$W/h/.ssh/config"
  (HOME="$W/h"; source scripts/lib/ssh.sh; dotfiles_ensure_ssh_config)
  grep -q "UseKeychain" "$W/h/.ssh/config"'
t "A9.17c" "the helper stays idempotent once the block is there" '
  W=$(sandbox); mkdir -p "$W/h/.ssh"
  (HOME="$W/h"; source scripts/lib/ssh.sh; dotfiles_ensure_ssh_config; dotfiles_ensure_ssh_config)
  [ "$(grep -c "^Host \*" "$W/h/.ssh/config")" = "1" ]'
t "A9.18" "link no longer seeds spicetify" \
  '! grep -q spicetify <(code_of bin/dotfiles)'

#############################################################################
section "A9 (dispatch/update/launchagents) — routing, status, modern launchctl"
#############################################################################

t "A9.4" "submodule update uses --init and no --remote" \
  'grep -q "submodule update --init" <(code_of bin/dotfiles) && ! grep -q "submodule update --remote" <(code_of bin/dotfiles)'
t "A9.5" "no git submodule init --recursive" \
  '! grep -q "submodule init --recursive" <(code_of bin/dotfiles)'
t "A9.7" "dispatch uses declare -F, not exit 127" \
  '! grep -q "= 127" <(code_of bin/dotfiles)'
t "A9.7b" "an unknown command is reported once, not as a command-not-found" '
  out=$(bash bin/dotfiles definitely-not-a-command 2>&1 || true)
  case "$out" in *"command not found"*) false ;; *"is not a known command"*) true ;; *) false ;; esac'
t "A9.7c" "an unknown subcommand is reported once" '
  out=$(bash bin/dotfiles install --definitely-not-a-flag 2>&1 || true)
  case "$out" in *"command not found"*) false ;; *"is not a known command"*) true ;; *) false ;; esac'
t "A9.7d" "link --help prints usage instead of two command-not-found lines" '
  out=$(bash bin/dotfiles link --help 2>&1 || true)
  case "$out" in *"command not found"*) false ;; *) true ;; esac'
t "A9.8" "dotfiles edit has a default IDE" \
  'grep -q "DOTFILES_IDE:-" <(code_of bin/dotfiles)'
t "A9.9" "baseline is routed" \
  'grep -q "\"baseline\"" <(code_of bin/dotfiles)'
t "A9.9b" "baseline appears in the top-level help" \
  'out=$(bash bin/dotfiles help 2>&1); case "$out" in *baseline*) true ;; *) false ;; esac'
t "A9.10" "doctor --help prints usage" \
  'out=$(zsh bin/dotfiles-doctor --help 2>&1 || true); case "$out" in *Usage*) true ;; *) false ;; esac'
t "A9.10b" "doctor --help does not run a full diagnostic" \
  'out=$(zsh bin/dotfiles-doctor --help 2>&1 || true); case "$out" in *"Symlink Status"*) false ;; *) true ;; esac'
t "A9.15" "clean help text matches behaviour" \
  '! grep -q "nvm, gem" <(code_of bin/dotfiles)'
t "A9.19" "lastupdate goes to config.local" \
  'grep -qE "config.local.*dotfiles.lastupdate|dotfiles.lastupdate.*config.local" <(code_of bin/dotfiles)'
t "A9.19b" "lastupdate never touches the global or the tracked git config" \
  '! grep -q "git config --global dotfiles.lastupdate" <(code_of bin/dotfiles)'
t "A9.20" "install --claude propagates failure" \
  '[ "$(sed -n "/^sub_install_claude()/,/^}/p" <(code_of bin/dotfiles) | grep -cE "\|\| return 1|return \$\?")" -ge 1 ]'
# The brief spelled the first grep as "launchctl bootstrap gui"; the domain
# target is quoted here ("gui/$UID"), so match the two parts separately.
t "A9.21" "launchagents use bootstrap/bootout and copy" \
  'grep -q "launchctl bootstrap" <(code_of bin/dotfiles) && grep -q "gui/\$UID" <(code_of bin/dotfiles) && ! grep -q "ln -sf \"\$plist\"" <(code_of bin/dotfiles)'
t "A9.21c" "the plist is copied into ~/Library/LaunchAgents" \
  'grep -q "cp -f \"\$plist\" \"\$target\"" <(code_of bin/dotfiles)'
t "A9.21b" "launchagents no longer use the legacy load/unload verbs" \
  '! grep -qE "launchctl (load|unload)" <(code_of bin/dotfiles)'

#############################################################################
section "A9 (dead code) — unreachable functions, Vim, wizard log"
#############################################################################

t "A9.6" "doctor sources fs.sh after the DOTFILES_DIR fallback" '
  src=$(grep -n "scripts/lib/fs.sh" bin/dotfiles-doctor | head -1 | cut -d: -f1)
  fb=$(grep -n "dirname \"\$0\")/\.\." bin/dotfiles-doctor | head -1 | cut -d: -f1)
  [ -n "$src" ] && [ -n "$fb" ] && [ "$src" -gt "$fb" ]'
t "A9.6b" "a bogus DOTFILES_DIR does not break the fs.sh source" '
  out=$(DOTFILES_DIR=/nonexistent-xyz zsh bin/dotfiles-doctor </dev/null 2>&1 | head -12 || true)
  case "$out" in
    *"scripts/lib/fs.sh"*) false ;;
    *"dotfiles_age_days"*) false ;;
    *) true ;;
  esac'
t "A9.11" "dead install_packages removed from bin/dotfiles" \
  '! grep -q "^install_packages()" <(code_of bin/dotfiles)'
t "A9.12" "profile_detailed removed" \
  '! grep -q "profile_detailed" <(code_of bin/dotfiles-profiler)'
t "A9.12b" "--detailed still reaches a real profiler" \
  'grep -q "profile_files" <(code_of bin/dotfiles-profiler)'
t "A9.13" "unused wizard helpers removed" \
  '! grep -qE "^(ask_menu|ask_checklist|ask_input|start_spinner|stop_spinner|progress_bar)\(\)" <(code_of bin/dotfiles-setup)'
t "A9.13b" "the wizard still defines the helpers it calls" \
  '(source /dev/null; grep -q "^ask_yes_no()" <(code_of bin/dotfiles-setup))'
t "A9.14" "install --vim is gone" \
  '! grep -q "sub_install_vim" <(code_of bin/dotfiles)'
t "A9.14b" "the wizard no longer offers a Vim step" \
  '! grep -q "install --vim" <(code_of bin/dotfiles-setup)'
t "A9.16" "setup log lives under TMPDIR" \
  'grep -q "TMPDIR:-" <(code_of bin/dotfiles-setup)'
t "A9.16b" "the setup log path is not the predictable /tmp one" \
  '! grep -q "LOG_FILE=\"/tmp/dotfiles-setup.log\"" <(code_of bin/dotfiles-setup)'

#############################################################################
section "A10 — configure asks once, claude is routed"
#############################################################################

t "A10.1" "configure prompts once" \
  '[ "$(sed -n "/^sub_configure()/,/^}/p" <(code_of bin/dotfiles) | grep -c confirm)" = "1" ]'
t "A10.1b" "configure calls the functions directly, not through a subprocess" \
  '[ "$(sed -n "/^sub_configure()/,/^}/p" <(code_of bin/dotfiles) | grep -c "\$0 configure")" -eq 0 ]'
t "A10.1c" "configure restores DOTFILES_YES afterwards" \
  '[ "$(sed -n "/^sub_configure()/,/^}/p" <(code_of bin/dotfiles) | grep -c "_prev_yes")" -ge 1 ]'
t "A10.2" "claude subcommand routes to bin/dotfiles-claude" \
  'grep -q "\"claude\"" <(code_of bin/dotfiles) && grep -q "dotfiles-claude" <(code_of bin/dotfiles)'
t "A10.2b" "claude appears in the top-level help" \
  'out=$(bash bin/dotfiles help 2>&1); case "$out" in *"claude "*) true ;; *) false ;; esac'
t "A10.2c" "dotfiles claude reaches the real tool" \
  'out=$(bash bin/dotfiles claude --help 2>&1 || true)
   case "$out" in *"is not a known command"*) false ;; *) true ;; esac'

#############################################################################
section "A11 — no duplicated help text, no unconditional ok"
#############################################################################

# Every one of these commands is forwarded straight to its own binary, which
# handles --help itself, so these wrappers were unreachable duplicates of help
# text that lives next to the code it describes.
t "A11.1" "unreachable delegate help wrappers are gone" \
  '! grep -qE "^sub_(test|doctor|profiler|cheatsheet|secrets|setup)_help\(\)" <(code_of bin/dotfiles)'
# The loop runs in a subshell: t() evaluates this in the harness shell, so a
# bare `exit 1` would end the suite process outright -- no failure line, no
# summary, no later sections -- instead of recording one failure.
t "A11.1b" "each delegate still answers --help itself" '
  (
    for c in doctor profiler cheatsheet setup; do
      out=$(bash bin/dotfiles "$c" --help 2>&1 || true)
      case "$out" in *Usage*) ;; *) exit 1 ;; esac
    done
  )'
# Two arms since the node step went through mise. The original stubbed brew
# and left $PATH otherwise intact, which stopped reaching the failure path the
# moment mise was installed on the machine running the suite: require_mise
# found the real binary, returned 0, and the step went on to run a real
# `mise install`. The first arm removes mise from PATH entirely so the
# install-the-manager branch is exercised; the second stubs a mise that fails.
t "A11.2" "the node step fails when the manager cannot be installed" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/xdg"; ln -s "$PWD/config/mise" "$W/xdg/mise"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; exit 9\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  sed -n "/^sub_install_node()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:/usr/bin:/bin"; ROOT_DIR="$PWD"; XDG_CONFIG_HOME="$W/xdg"; source scripts/echos.sh; source scripts/requirers.sh; source "$W/fn.sh"
     sub_install_node >/dev/null 2>&1)'

t "A11.2b" "the node step does not print ok after a failed install" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/xdg"; ln -s "$PWD/config/mise" "$W/xdg/mise"
  printf "#!/bin/bash\nexit 3\n" > "$W/bin/mise"; chmod +x "$W/bin/mise"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  sed -n "/^sub_install_node()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:$PATH"; ROOT_DIR="$PWD"; XDG_CONFIG_HOME="$W/xdg"; source scripts/echos.sh; source scripts/requirers.sh; source "$W/fn.sh"
     sub_install_node >/dev/null 2>&1)'

#############################################################################
section "A12 — doctor's cache table tracks what the shell actually writes"
#############################################################################

t "A12.1" "doctor no longer mentions thefuck" \
  '! grep -qi thefuck bin/dotfiles-doctor'
# A drift guard, not a spelling check: a cache the doctor watches but nothing
# writes is reported "missing (will be created on next shell start)" forever.
t "A12.2" "every cache the doctor checks is one the shell config writes" '
  bad=""
  while IFS= read -r entry; do
    file="${entry%:*}"
    stem="${file%%\$*}"; stem="${stem%.zsh}"
    [ -n "$stem" ] || continue
    grep -rq -- "$stem" system/ runcom/ || bad="$bad $file"
  done < <(sed -n "/local caches=(/,/^  )/p" bin/dotfiles-doctor | sed -n "s/^ *\"\(.*\)\" *$/\1/p")
  [ -z "$bad" ]'
t "A12.3" "the dircolors cache is checked per TERM, as the shell names it" \
  'grep -q "dircolors-" bin/dotfiles-doctor'

#############################################################################
section "A13 — install --all really is unattended"
#############################################################################

# Every one of these runs the function against stub binaries in a sandbox
# HOME, under `timeout` with stdin closed: a surviving `read` would either
# hang until the timeout kills it (failing the assertion) or take the
# interactive branch (which the assertions detect).

t "A13.1" "DOTFILES_YES leaves an existing SSH key alone" '
  W=$(sandbox); mkdir -p "$W/h/.ssh" "$W/bin"
  printf "KEY\n" > "$W/h/.ssh/id_ed25519"; printf "PUB\n" > "$W/h/.ssh/id_ed25519.pub"
  for b in ssh-add ssh-keygen; do printf "#!/bin/bash\nexit 0\n" > "$W/bin/$b"; chmod +x "$W/bin/$b"; done
  sed -n "/^sub_install_ssh()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; ROOT_DIR="$PWD"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/ssh.sh; . "$W/fn.sh"
sub_install_ssh
RUN
  timeout 20 bash "$W/run.sh" </dev/null >/dev/null 2>&1
  [ "$(cat "$W/h/.ssh/id_ed25519")" = "KEY" ] &&
  [ -z "$(find "$W/h/.ssh" -name "*.bak.*" 2>/dev/null)" ]'

t "A13.2" "DOTFILES_YES derives the key comment instead of prompting for it" '
  W=$(sandbox); mkdir -p "$W/h/.ssh" "$W/bin" "$W/df/config/git"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/ssh-add"; chmod +x "$W/bin/ssh-add"
  printf "#!/bin/bash\nprintf \"%%s\\n\" \"\$@\" > \"$W/keygen.args\"\nexit 0\n" > "$W/bin/ssh-keygen"
  chmod +x "$W/bin/ssh-keygen"
  sed -n "/^sub_install_ssh()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/ssh.sh; . "$W/fn.sh"
sub_install_ssh
RUN
  timeout 20 bash "$W/run.sh" </dev/null >/dev/null 2>&1
  grep -q "@" "$W/keygen.args"'

t "A13.3" "the derived comment prefers config.local user.email" '
  W=$(sandbox); mkdir -p "$W/h/.ssh" "$W/bin" "$W/df/config/git"
  printf "[user]\n\temail = someone@example.invalid\n" > "$W/df/config/git/config.local"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/ssh-add"; chmod +x "$W/bin/ssh-add"
  printf "#!/bin/bash\nprintf \"%%s\\n\" \"\$@\" > \"$W/keygen.args\"\nexit 0\n" > "$W/bin/ssh-keygen"
  chmod +x "$W/bin/ssh-keygen"
  sed -n "/^sub_install_ssh()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/ssh.sh; . "$W/fn.sh"
sub_install_ssh
RUN
  timeout 20 bash "$W/run.sh" </dev/null >/dev/null 2>&1
  grep -q "someone@example.invalid" "$W/keygen.args"'

t "A13.4" "DOTFILES_YES skips the git identity prompt and warns instead" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/df/config/git" "$W/h" "$W/xdg" "$W/bin"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/stow"; chmod +x "$W/bin/stow"
  sed -n "/^sub_link()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; XDG_CONFIG_HOME="$W/xdg"; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
echo \$\$ >"$W/pid"
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_link
RUN
  out=$(timeout 20 bash "$W/run.sh" </dev/null 2>&1)
  [ ! -f "$W/df/config/git/config.local" ] &&
  case "$out" in *"Git identity"*) false ;; *unattended*) true ;; *) false ;; esac'

t "A13.5" "without DOTFILES_YES the git identity prompt is still offered" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/df/config/git" "$W/h" "$W/xdg" "$W/bin"
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/stow"; chmod +x "$W/bin/stow"
  sed -n "/^sub_link()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; XDG_CONFIG_HOME="$W/xdg"; ROOT_DIR="$W/df"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
printf "y\n" | sub_link
RUN
  out=$(timeout 20 bash "$W/run.sh" </dev/null 2>&1)
  case "$out" in *"Git identity"*) true ;; *) false ;; esac'

#############################################################################
section "A14 — the /etc/hosts write is checked"
#############################################################################

# A stub sudo and a stub curl keep this entirely inside the sandbox: the real
# /etc/hosts is never read, written or backed up.
t "A14.1" "a failed write to /etc/hosts is reported and returns non-zero" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/df/system"
  printf "#!/bin/bash\nfor a in \"\$@\"; do case \"\$a\" in -o) shift; o=\"\$1\";; esac; shift; done\nexit 0\n" > /dev/null
  cat > "$W/bin/curl" <<CURL
#!/bin/bash
o=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then o="\$2"; shift 2; else shift; fi
done
{ echo "# Title: StevenBlack/hosts"
  awk "BEGIN{for(i=0;i<10001;i++) print \"0.0.0.0 e\" i \".example\"}"
} > "\$o"
CURL
  cat > "$W/bin/sudo" <<SUDO
#!/bin/bash
if [ "\$1" = "cp" ] && [ "\$3" = "$W/hosts" ]; then exit 1; fi
exit 0
SUDO
  chmod +x "$W/bin/curl" "$W/bin/sudo"
  sed -n "/^sub_install_hosts()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1; DOTFILES_HOSTS_FILE="$W/hosts"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  out=$(timeout 60 bash "$W/run.sh" </dev/null 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *error*) true ;; *) false ;; esac'

t "A14.2" "a failed backup of /etc/hosts aborts before the write" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/df/system"
  cat > "$W/bin/curl" <<CURL
#!/bin/bash
o=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then o="\$2"; shift 2; else shift; fi
done
{ echo "# Title: StevenBlack/hosts"
  awk "BEGIN{for(i=0;i<10001;i++) print \"0.0.0.0 e\" i \".example\"}"
} > "\$o"
CURL
  cat > "$W/bin/sudo" <<SUDO
#!/bin/bash
printf "%s\n" "\$*" >> "$W/sudo.log"
if [ "\$1" = "cp" ] && [ "\$3" = "$W/hosts.backup" ]; then exit 1; fi
exit 0
SUDO
  chmod +x "$W/bin/curl" "$W/bin/sudo"
  sed -n "/^sub_install_hosts()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1; DOTFILES_HOSTS_FILE="$W/hosts"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  timeout 60 bash "$W/run.sh" </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ! grep -qE "cp .* $W/hosts\$" "$W/sudo.log"'

t "A14.3" "the happy path still returns 0" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/df/system"
  cat > "$W/bin/curl" <<CURL
#!/bin/bash
o=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then o="\$2"; shift 2; else shift; fi
done
{ echo "# Title: StevenBlack/hosts"
  awk "BEGIN{for(i=0;i<10001;i++) print \"0.0.0.0 e\" i \".example\"}"
} > "\$o"
CURL
  printf "#!/bin/bash\nexit 0\n" > "$W/bin/sudo"
  chmod +x "$W/bin/curl" "$W/bin/sudo"
  sed -n "/^sub_install_hosts()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1; DOTFILES_HOSTS_FILE="$W/hosts"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  timeout 60 bash "$W/run.sh" </dev/null >/dev/null 2>&1'


#############################################################################
section "N0 — helpers for the new-Mac install-flow tests"
#############################################################################

# fn_of <name> [file] -- print one top-level function of a script.
fn_of() { sed -n "/^$1()/,/^}/p" "${2:-bin/dotfiles}"; }
# stub <dir> <name> <body...> -- write an executable stub into <dir>.
stub() { local d="$1" n="$2"; shift 2; mkdir -p "$d"; printf '#!/bin/bash\n%s\n' "$*" > "$d/$n"; chmod +x "$d/$n"; }

#############################################################################
section "N1 — SSH key on a clean machine (1.1)"
#############################################################################

# The keygen stub mirrors the real one: it cannot save a key into a
# directory that does not exist.
_ssh_keygen_stub='f=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && f="$2"; shift; done
[ -d "$(dirname "$f")" ] || { echo "Saving key \"$f\" failed: No such file or directory" >&2; exit 1; }
: > "$f"; : > "$f.pub"; exit 0'
_ssh_run() { # _ssh_run <W> -- run sub_install_ssh in a sandbox HOME with no .ssh
  local W="$1"
  fn_of sub_install_ssh > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; USER=tester; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/ssh.sh; . "$W/fn.sh"
sub_install_ssh
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
t "N1.1" "a clean HOME with no .ssh still gets a key, in a 700 directory" '
  W=$(sandbox); mkdir -p "$W/h" "$W/bin" "$W/df"
  stub "$W/bin" ssh-keygen "$_ssh_keygen_stub"; stub "$W/bin" ssh-add "exit 0"
  stub "$W/bin" hostname "echo box"; stub "$W/bin" xcode-select "exit 1"
  _ssh_run "$W" >/dev/null 2>&1
  [ -f "$W/h/.ssh/id_ed25519" ] && [ "$(ls -ld "$W/h/.ssh" | cut -c1-10)" = "drwx------" ]'
t "N1.2" "a failing ssh-keygen returns non-zero and prints no ok" '
  W=$(sandbox); mkdir -p "$W/h" "$W/bin" "$W/df"
  stub "$W/bin" ssh-keygen "exit 1"; stub "$W/bin" ssh-add "exit 0"
  stub "$W/bin" hostname "echo box"; stub "$W/bin" xcode-select "exit 1"
  out=$(_ssh_run "$W" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *"01mok"*) false ;; *) true ;; esac'
t "N1.3" "git is never called for the key comment while the CLT are missing" '
  W=$(sandbox); mkdir -p "$W/h" "$W/bin" "$W/df/config/git"
  stub "$W/bin" ssh-keygen "$_ssh_keygen_stub"; stub "$W/bin" ssh-add "exit 0"
  stub "$W/bin" hostname "echo box"; stub "$W/bin" xcode-select "exit 1"
  stub "$W/bin" git "echo called >> \"$W/git.log\""
  _ssh_run "$W" >/dev/null 2>&1
  [ ! -e "$W/git.log" ] && [ -f "$W/h/.ssh/id_ed25519" ]'
t "N1.4" "with the CLT present the key comment still comes from git config" '
  W=$(sandbox); mkdir -p "$W/h" "$W/bin" "$W/df/config/git"
  printf "[user]\n\temail = someone@example.invalid\n" > "$W/df/config/git/config.local"
  stub "$W/bin" ssh-keygen "printf \"%s\\n\" \"\$@\" > \"$W/keygen.args\"; f=\"\"; while [ \$# -gt 0 ]; do [ \"\$1\" = -f ] && f=\"\$2\"; shift; done; : > \"\$f\""
  stub "$W/bin" ssh-add "exit 0"; stub "$W/bin" hostname "echo box"; stub "$W/bin" xcode-select "echo /Library/Developer/CommandLineTools"
  ln -s "$(command -v git)" "$W/bin/git"
  _ssh_run "$W" >/dev/null 2>&1
  grep -q "someone@example.invalid" "$W/keygen.args"'


#############################################################################
section "N2 — shared Command Line Tools installer (1.2)"
#############################################################################

_clt_line() { printf '* Label: %s\n\tTitle: x, Version: 1, Size: 1KiB, Recommended: YES,\n' "$1"; }
_clt_pick() { # _clt_pick <label>... -- feed labels to the picker, print its answer
  local l
  for l in "$@"; do _clt_line "$l"; done | bash -c '. scripts/lib/clt.sh; dotfiles_clt_pick_label'
}
t "N2.1" "picks 27.0 from an ascending, a descending and a shuffled listing" '
  a="Command Line Tools for Xcode 26.5-26.5"; b="Command Line Tools for Xcode 27.0-27.0"; c="Command Line Tools for Xcode 26.6-26.6"
  [ "$(_clt_pick "$a" "$b" "$c")" = "$b" ] && [ "$(_clt_pick "$b" "$c" "$a")" = "$b" ] && [ "$(_clt_pick "$c" "$a" "$b")" = "$b" ]'
t "N2.2" "a stable label beats a beta of the same version" '
  s="Command Line Tools for Xcode 27.0-27.0"; b="Command Line Tools beta 3 for Xcode-27.0"
  [ "$(_clt_pick "$b" "$s")" = "$s" ] && [ "$(_clt_pick "$s" "$b")" = "$s" ]'
t "N2.3" "a beta is still picked when it is the only thing offered" '
  b="Command Line Tools beta 3 for Xcode-27.0"
  [ "$(_clt_pick "$b" "Command Line Tools for Xcode 26.6-26.6")" = "$b" ]'
t "N2.4" "the older listing form without Label: is parsed" '
  out=$(printf "   * Command Line Tools for Xcode-15.3\n   * Command Line Tools for Xcode-16.0\n" | bash -c ". scripts/lib/clt.sh; dotfiles_clt_pick_label")
  [ "$out" = "Command Line Tools for Xcode-16.0" ]'
t "N2.5" "empty input prints nothing and fails" '
  out=$(printf "" | bash -c ". scripts/lib/clt.sh; dotfiles_clt_pick_label"); rc=$?
  [ -z "$out" ] && [ "$rc" -ne 0 ]'
t "N2.6" "unrelated updates are ignored" '
  out=$(printf "* Label: macOS Tahoe 27.0.1-99\n" | bash -c ". scripts/lib/clt.sh; dotfiles_clt_pick_label")
  [ -z "$out" ]'
t "N2.7" "clt.sh has no dependency on echos.sh" '
  W=$(sandbox); out=$(env -i PATH=/usr/bin:/bin bash -c ". scripts/lib/clt.sh; declare -F dotfiles_install_clt" 2>&1) &&
  [ "$out" = "dotfiles_install_clt" ]'

# Stubs read $SW at run time, so they are written once.
_clt_stubs() {
  local W="$1"; mkdir -p "$W/bin"
  cat > "$W/bin/xcode-select" <<'STUB'
#!/bin/bash
case "$1" in
  -p | --print-path) [ -e "$SW/clt-installed" ] || exit 1; echo "${CLT_PATH:-/Library/Developer/CommandLineTools}" ;;
  -s) echo "xcode-select $*" >> "$SW/log"; : > "$SW/clt-installed" ;;
esac
STUB
  cat > "$W/bin/softwareupdate" <<'STUB'
#!/bin/bash
case "$1" in
  --list)
    n=$(($(cat "$SW/list.n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$SW/list.n"
    echo "softwareupdate --list (sentinel: $([ -e "$DOTFILES_CLT_SENTINEL" ] && echo present || echo absent))" >> "$SW/log"
    [ -f "$SW/list.$n" ] && cat "$SW/list.$n" ;;
  --install) echo "softwareupdate $*" >> "$SW/log"; [ -e "$SW/install.sleep" ] && sleep "$(cat "$SW/install.sleep")"; exit "$(cat "$SW/install.rc" 2>/dev/null || echo 0)" ;;
esac
STUB
  cat > "$W/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$SW/log"
case "$1" in -v) exit 0 ;; -n) shift ;; esac
exec "$@"
STUB
  cat > "$W/bin/xcodebuild" <<'STUB'
#!/bin/bash
echo "xcodebuild $*" >> "$SW/log"
STUB
  chmod +x "$W/bin/"*
}
_clt_run() { # _clt_run <W> <shell code> -- run code with clt.sh sourced against the stubs
  local W="$1"
  SW="$W" DOTFILES_CLT_SENTINEL="$W/sentinel" DOTFILES_CLT_RETRY_SLEEP=0 PATH="$W/bin:/usr/bin:/bin" \
    bash -c ". scripts/lib/clt.sh; $2" </dev/null
}
_clt_offer() { # _clt_offer <W> <list-call-number> <label>...
  local W="$1" n="$2" l; shift 2
  for l in "$@"; do _clt_line "$l"; done > "$W/list.$n"
}
t "N2.8" "already installed is a no-op success" '
  W=$(sandbox); _clt_stubs "$W"; : > "$W/clt-installed"
  _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1 && [ ! -e "$W/log" ]'
t "N2.9" "the highest label reaches softwareupdate --install and xcode-select -s runs" '
  W=$(sandbox); _clt_stubs "$W"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 26.5-26.5" "Command Line Tools for Xcode 27.0-27.0" "Command Line Tools for Xcode 26.6-26.6"
  _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1 &&
  grep -q "^softwareupdate --install Command Line Tools for Xcode 27.0-27.0 --agree-to-license" "$W/log" &&
  grep -q "^sudo xcode-select -s /Library/Developer/CommandLineTools" "$W/log"'
t "N2.10" "the sentinel exists while softwareupdate lists and is gone afterwards" '
  W=$(sandbox); _clt_stubs "$W"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1
  grep -q "sentinel: present" "$W/log" && [ ! -e "$W/sentinel" ]'
t "N2.11" "an empty first listing is retried" '
  W=$(sandbox); _clt_stubs "$W"
  _clt_offer "$W" 3 "Command Line Tools for Xcode 27.0-27.0"
  _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1 &&
  [ "$(grep -c "softwareupdate --list" "$W/log")" -eq 3 ] && grep -q "softwareupdate --install" "$W/log"'
t "N2.12" "no label after three listings fails, names the manual fallback, removes the sentinel" '
  W=$(sandbox); _clt_stubs "$W"
  out=$(_clt_run "$W" dotfiles_install_clt 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(grep -c "softwareupdate --list" "$W/log")" -eq 3 ] && [ ! -e "$W/sentinel" ] &&
  case "$out" in *"xcode-select --install"*) true ;; *) false ;; esac'
t "N2.13" "a failed install fails, removes the sentinel and skips xcode-select -s" '
  W=$(sandbox); _clt_stubs "$W"; echo 1 > "$W/install.rc"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  out=$(_clt_run "$W" dotfiles_install_clt 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$W/sentinel" ] && [ "$(grep -c "xcode-select -s" "$W/log")" -eq 0 ] &&
  case "$out" in *"xcode-select --install"*) true ;; *) false ;; esac'
t "N2.14" "no Xcode licence prompt when only the Command Line Tools are selected" '
  W=$(sandbox); _clt_stubs "$W"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1 && [ "$(grep -c xcodebuild "$W/log")" -eq 0 ]'
t "N2.15" "the licence is accepted when the selected path is inside Xcode.app" '
  W=$(sandbox); _clt_stubs "$W"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  CLT_PATH=/Applications/Xcode.app/Contents/Developer _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1
  grep -q "^sudo xcodebuild -license accept" "$W/log"'
t "N2.16" "sub_install_clt is a thin wrapper over dotfiles_install_clt" '
  [ "$(fn_of sub_install_clt | grep -c "dotfiles_install_clt")" -eq 1 ] && [ "$(fn_of sub_install_clt | grep -c softwareupdate)" -eq 0 ]'

t "N2.17" "a trailing beta counter is not read as the version" '
  b="Command Line Tools for Xcode 27.0 beta 3"; s="Command Line Tools for Xcode 26.6-26.6"
  [ "$(_clt_pick "$b" "$s")" = "$b" ] && [ "$(_clt_pick "$s" "$b")" = "$b" ]'
t "N2.18" "sudo is kept alive while softwareupdate runs and stops afterwards" '
  W=$(sandbox); _clt_stubs "$W"; echo 1 > "$W/install.sleep"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  DOTFILES_CLT_KEEPALIVE_INTERVAL=0.1 _clt_run "$W" dotfiles_install_clt >/dev/null 2>&1 &&
  [ "$(grep -c "^sudo -n true" "$W/log")" -ge 2 ] &&
  n=$(grep -c "^sudo -n true" "$W/log") && sleep 0.5 && [ "$(grep -c "^sudo -n true" "$W/log")" -eq "$n" ]'
t "N2.19" "a TERM during the install removes the sentinel and stops the keep-alive" '
  W=$(sandbox); _clt_stubs "$W"; echo 2 > "$W/install.sleep"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  DOTFILES_CLT_KEEPALIVE_INTERVAL=0.1 _clt_run "$W" "echo \$\$ > \"\$SW/pid\"; dotfiles_install_clt" >/dev/null 2>&1 &
  bgpid=$!
  i=0; while [ ! -e "$W/sentinel" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$W/sentinel" ]; kill -TERM "$(cat "$W/pid")"; wait "$bgpid" 2>/dev/null
  [ ! -e "$W/sentinel" ] &&
  n=$(grep -c "^sudo -n true" "$W/log") && sleep 0.5 && [ "$(grep -c "^sudo -n true" "$W/log")" -eq "$n" ]'

t "N2.20" "a SIGKILLed parent does not leave the keep-alive holding sudo warm" '
  W=$(sandbox); _clt_stubs "$W"; echo 3 > "$W/install.sleep"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
  DOTFILES_CLT_KEEPALIVE_INTERVAL=0.1 _clt_run "$W" "echo \$\$ > \"\$SW/pid\"; dotfiles_install_clt" >/dev/null 2>&1 &
  bgpid=$!
  i=0; while [ ! -e "$W/sentinel" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.3; kill -KILL "$(command cat "$W/pid")"; wait "$bgpid" 2>/dev/null
  sleep 0.4
  n=$(grep -c "^sudo -n true" "$W/log"); sleep 0.6
  [ "$n" -ge 1 ] && [ "$(grep -c "^sudo -n true" "$W/log")" -eq "$n" ]'


#############################################################################
section "N3 — remote-install.sh on a bare Mac (1.3)"
#############################################################################

_ri_stubs() {
  local W="$1"; _clt_stubs "$W"; mkdir -p "$W/h"
  cat > "$W/bin/uname" <<'STUB'
#!/bin/bash
[ "$1" = "-m" ] && echo arm64 || echo Darwin
STUB
  cat > "$W/bin/curl" <<'STUB'
#!/bin/bash
echo "curl $*" >> "$SW/log"
o=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && o="$2"; shift; done
cp "$REPO/scripts/lib/clt.sh" "$o"
STUB
  cat > "$W/bin/git" <<'STUB'
#!/bin/bash
echo "git $*" >> "$SW/log"
if [ "$1" = "clone" ]; then
  mkdir -p "$3/.git" "$3/bin"
  printf '#!/bin/bash\necho "dotfiles $*" >> "%s/log"\n' "$SW" > "$3/bin/dotfiles"
  chmod +x "$3/bin/dotfiles"
fi
STUB
  chmod +x "$W/bin/"*
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
}
_ri_run() { # _ri_run <W> [extra env...] -- run remote-install.sh in an empty environment
  local W="$1"; shift
  env -i HOME="$W/h" PATH="$W/bin:/usr/bin:/bin" TMPDIR="$W" SW="$W" REPO="$PWD" \
    DOTFILES_CLT_SENTINEL="$W/sentinel" DOTFILES_CLT_RETRY_SLEEP=0 "$@" \
    bash remote-install.sh </dev/null
}
t "N3.1" "with no CLT it installs them headlessly before anything calls git" '
  W=$(sandbox); _ri_stubs "$W"
  _ri_run "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && grep -q "softwareupdate --install" "$W/log" &&
  [ "$(grep -c "^git --version" "$W/log")" -eq 0 ] &&
  [ "$(_first_line "softwareupdate --install" "$W/log")" -lt "$(_first_line "git clone" "$W/log")" ]'
t "N3.2" "clt.sh is fetched over https from the pinned ref" '
  W=$(sandbox); _ri_stubs "$W"
  _ri_run "$W" DOTFILES_REF=abc123 >/dev/null 2>&1
  grep -q -- "--proto =https" "$W/log" &&
  grep -q "https://raw.githubusercontent.com/STiXzoOR/dotfiles/abc123/scripts/lib/clt.sh" "$W/log"'
t "N3.3" "the ref defaults to main" '
  W=$(sandbox); _ri_stubs "$W"
  _ri_run "$W" >/dev/null 2>&1
  grep -q "STiXzoOR/dotfiles/main/scripts/lib/clt.sh" "$W/log"'
t "N3.4" "the clone is followed by dotfiles install" '
  W=$(sandbox); _ri_stubs "$W"
  _ri_run "$W" >/dev/null 2>&1
  grep -q "^git clone https://github.com/STiXzoOR/dotfiles $W/h/.dotfiles" "$W/log" && grep -q "^dotfiles install$" "$W/log"'
t "N3.5" "with the CLT present nothing is downloaded or installed" '
  W=$(sandbox); _ri_stubs "$W"; : > "$W/clt-installed"
  _ri_run "$W" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ "$(grep -c "^curl\|softwareupdate" "$W/log")" -eq 0 ] && grep -q "^git clone" "$W/log"'
t "N3.6" "a second run continues the existing checkout: no clone, install still runs" '
  W=$(sandbox); _ri_stubs "$W"; : > "$W/clt-installed"
  _ri_run "$W" >/dev/null 2>&1
  : > "$W/log"
  out=$(_ri_run "$W" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(grep -c "^git clone" "$W/log")" -eq 0 ] && grep -q "^dotfiles install$" "$W/log" &&
  case "$out" in *"continuing"*) true ;; *) false ;; esac'
t "N3.7" "a target that is not a checkout aborts" '
  W=$(sandbox); _ri_stubs "$W"; : > "$W/clt-installed"; mkdir -p "$W/h/.dotfiles"
  ! _ri_run "$W" >/dev/null 2>&1 && [ "$(grep -c "^dotfiles install" "$W/log" 2>/dev/null)" -eq 0 ]'
t "N3.8" "a failed Command Line Tools install aborts before the clone" '
  W=$(sandbox); _ri_stubs "$W"; echo 1 > "$W/install.rc"
  ! _ri_run "$W" >/dev/null 2>&1 && [ "$(grep -c "^git clone" "$W/log")" -eq 0 ]'
t "N3.9" "the script asks for sudo up front" '
  W=$(sandbox); _ri_stubs "$W"; : > "$W/clt-installed"
  _ri_run "$W" >/dev/null 2>&1
  [ "$(head -1 "$W/log")" = "sudo -v" ]'
t "N3.10" "the script never probes with git --version" \
  '[ "$(code_of remote-install.sh | grep -c "git --version")" -eq 0 ]'


#############################################################################
section "N4 — install order, failures and summary (1.4)"
#############################################################################

# A sandbox copy of the repo whose step functions are replaced by stubs that
# append their name to $LOG. The overrides are spliced in just before the
# dispatcher, so `$0 install --prezto` re-executes the copy and reaches the
# stub. FAIL=<step> makes that one step return 1.
_mk_repo() { # _mk_repo <W> <step>... -- steps listed are NOT stubbed
  local W="$1"; shift
  mkdir -p "$W/repo/bin" "$W/h"
  cp -R scripts "$W/repo/scripts"
  {
    echo '_log() { echo "$*" >> "$LOG"; }'
    echo 'sudo() { :; }'
    echo 'dotfiles_sudo_keepalive() { _log keepalive; }'
    echo 'require_brew() { _log "brew:$*"; }'
    local s keep
    for s in install_clt install_homebrew install_ssh install_prezto install_private install_node install_packages install_fonts \
      install_launchagents install_claude install_codex install_hosts link configure hooks; do
      keep=0; for k in "$@"; do [ "$k" = "$s" ] && keep=1; done
      [ "$keep" = 1 ] && continue
      echo "sub_$s() { _log ${s#install_}; case \",\${FAIL:-},\" in *,${s#install_},*) return 1 ;; esac; return 0; }"
    done
  } > "$W/ov.sh"
  awk -v f="$W/ov.sh" '/^# Routing\./ { while ((getline l < f) > 0) print l } { print }' bin/dotfiles > "$W/repo/bin/dotfiles"
  chmod +x "$W/repo/bin/dotfiles"
}
_run_repo() { # _run_repo <W> <args...>
  local W="$1"; shift
  env HOME="$W/h" XDG_CONFIG_HOME="$W/h/.config" LOG="$W/log" FAIL="${FAIL:-}" bash "$W/repo/bin/dotfiles" "$@" </dev/null
}
_log_line() { tr '\n' ' ' < "$1" | sed -E 's/ +$//'; }

t "N4.1" "plain install runs keep-alive, CLT, Homebrew, stow, then SSH, and no node" '
  W=$(sandbox); _mk_repo "$W"; _run_repo "$W" install >/dev/null 2>&1
  [ "$(_log_line "$W/log")" = "keepalive clt hooks homebrew brew:stow ssh" ]'
t "N4.2" "plain install with every step green prints the banner and the complementary commands" '
  W=$(sandbox); _mk_repo "$W"; out=$(_run_repo "$W" install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && case "$out" in *"All done"*"install --node"*"install --codex"*"install --all"*) true ;; *) false ;; esac'
t "N4.3" "a failed CLT step aborts before Homebrew" '
  W=$(sandbox); _mk_repo "$W"; FAIL=clt _run_repo "$W" install >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ "$(_log_line "$W/log")" = "keepalive clt" ]'
t "N4.4" "a failed SSH step is named, there is no success banner, and the status is non-zero" '
  W=$(sandbox); _mk_repo "$W"; out=$(FAIL=ssh _run_repo "$W" install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *"All done"*) false ;; *ssh*) true ;; *) false ;; esac'
t "N4.5" "a failed Homebrew step does not stop stow and SSH from being tried" '
  W=$(sandbox); _mk_repo "$W"; out=$(FAIL=homebrew _run_repo "$W" install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_log_line "$W/log")" = "keepalive clt hooks homebrew brew:stow ssh" ] &&
  case "$out" in *"All done"*) false ;; *homebrew*) true ;; *) false ;; esac'
t "N4.6" "install --all runs the steps in the documented order with hosts last" '
  W=$(sandbox); _mk_repo "$W"; _run_repo "$W" install --all >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] &&
  [ "$(_log_line "$W/log")" = "keepalive prezto private link node packages fonts launchagents claude codex configure hosts" ]'
t "N4.7" "install --all keeps going after a failure, names it and returns non-zero" '
  W=$(sandbox); _mk_repo "$W"; out=$(FAIL=packages _run_repo "$W" install --all 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_log_line "$W/log")" = "keepalive prezto private link node packages fonts launchagents claude codex configure hosts" ] &&
  case "$out" in *"packages"*) true ;; *) false ;; esac'
t "N4.8" "install --all names every failed step" '
  W=$(sandbox); _mk_repo "$W"
  out=$(FAIL=node,hosts _run_repo "$W" install --all 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *node*hosts*) true ;; *) false ;; esac'
t "N4.9" "install --all with every step green reports success" '
  W=$(sandbox); _mk_repo "$W"; out=$(_run_repo "$W" install --all 2>&1)
  case "$out" in *"All done"*) true ;; *) false ;; esac'
t "N4.10" "install --all starts its own sudo keep-alive before the first step" '
  W=$(sandbox); _mk_repo "$W"; _run_repo "$W" install --all >/dev/null 2>&1
  [ "$(head -1 "$W/log")" = "keepalive" ]'
t "N4.11" "the install help lists --codex" \
  'out=$(bash bin/dotfiles install --help 2>&1); case "$out" in *"--codex"*) true ;; *) false ;; esac'
t "N4.12" "install --codex errors clearly when scripts/install_codex.sh is missing" '
  W=$(sandbox); _mk_repo "$W" install_codex; command rm -f "$W/repo/scripts/install_codex.sh"
  out=$(DOTFILES_YES=1 _run_repo "$W" install --codex 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *"install_codex.sh is missing"*) true ;; *) false ;; esac'
t "N4.13" "install --codex runs scripts/install_codex.sh and propagates its status" '
  W=$(sandbox); _mk_repo "$W" install_codex
  printf "#!/bin/bash\necho ran >> \"$W/codex.log\"\nexit 0\n" > "$W/repo/scripts/install_codex.sh"
  DOTFILES_YES=1 _run_repo "$W" install --codex >/dev/null 2>&1 && [ -f "$W/codex.log" ] &&
  printf "#!/bin/bash\nexit 4\n" > "$W/repo/scripts/install_codex.sh" &&
  ! DOTFILES_YES=1 _run_repo "$W" install --codex >/dev/null 2>&1'

#############################################################################
section "N5 — mise runs after link, with gpg (1.5)"
#############################################################################

_node_run() { # _node_run <W> -- run sub_install_node against stubs
  local W="$1"
  fn_of sub_install_node > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; XDG_CONFIG_HOME="$W/xdg"; ROOT_DIR="$PWD"; BIN_NAME=dotfiles
unset MISE_GLOBAL_CONFIG_FILE
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/requirers.sh; . "$W/fn.sh"
sub_install_node
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
_node_stubs() { # _node_stubs <W> <brew-list-exit>
  local W="$1"
  stub "$W/bin" mise 'echo "mise $* GLOBAL=${MISE_GLOBAL_CONFIG_FILE-unset}" >> "'"$W"'/log"'
  stub "$W/bin" brew '[ "$1" = list ] && exit '"$2"'; echo "brew $*" >> "'"$W"'/log"; exit 0'
  mkdir -p "$W/h" "$W/xdg"
}
t "N5.1" "unlinked: fails, says to run link, and never calls mise" '
  W=$(sandbox); _node_stubs "$W" 0
  out=$(_node_run "$W" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$W/log" ] && case "$out" in *"link"*) true ;; *) false ;; esac'
t "N5.2" "a copied (not symlinked) ~/.config/mise does not count as linked" '
  W=$(sandbox); _node_stubs "$W" 0; cp -R config/mise "$W/xdg/mise"
  ! _node_run "$W" >/dev/null 2>&1 && [ ! -e "$W/log" ]'
t "N5.3" "linked: mise install runs without MISE_GLOBAL_CONFIG_FILE" '
  W=$(sandbox); _node_stubs "$W" 0; ln -s "$PWD/config/mise" "$W/xdg/mise"
  _node_run "$W" >/dev/null 2>&1 && grep -q "^mise install GLOBAL=unset$" "$W/log"'
t "N5.4" "gnupg is installed when brew does not have it" '
  W=$(sandbox); _node_stubs "$W" 1; ln -s "$PWD/config/mise" "$W/xdg/mise"
  _node_run "$W" >/dev/null 2>&1; grep -q "^brew install gnupg" "$W/log"'
t "N5.5" "gnupg is left alone when brew already has it" '
  W=$(sandbox); _node_stubs "$W" 0; ln -s "$PWD/config/mise" "$W/xdg/mise"
  _node_run "$W" >/dev/null 2>&1; [ "$(grep -c "^brew install" "$W/log")" -eq 0 ]'
t "N5.6" "a failing gnupg install stops the step before mise runs" '
  W=$(sandbox); _node_stubs "$W" 1; stub "$W/bin" brew "[ \"\$1\" = list ] && exit 1; exit 9"
  ln -s "$PWD/config/mise" "$W/xdg/mise"
  ! _node_run "$W" >/dev/null 2>&1 && [ ! -e "$W/log" ]'
t "N5.7" "plain install no longer runs the node step" \
  '[ "$(fn_of sub_install | grep -c "sub_install_node")" -eq 0 ]'


#############################################################################
section "N4b — the Homebrew step reports, and never exits the whole run"
#############################################################################

_brew_step_run() { # _brew_step_run <W> -- run sub_install_homebrew against stubs, print "after" if it returned
  local W="$1"
  fn_of sub_install_homebrew > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:$PWD/bin:/usr/bin:/bin"; HOME="$W/h"; HOMEBREW_PREFIX="$W"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/requirers.sh; . "$W/fn.sh"
sub_install_homebrew; rc=\$?
echo "after rc=\$rc"
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
t "N4b.1" "brew doctor warnings do not fail the Homebrew step" '
  W=$(sandbox); mkdir -p "$W/h"; stub "$W/bin" brew "[ \"\$1\" = doctor ] && exit 1; exit 0"
  out=$(_brew_step_run "$W" 2>&1); case "$out" in *"after rc=0"*) true ;; *) false ;; esac'
t "N4b.2" "a failed Homebrew install returns to the caller instead of exiting the script" '
  W=$(sandbox); mkdir -p "$W/h"; stub "$W/bin" curl "echo exit 1"
  out=$(_brew_step_run "$W" 2>&1); case "$out" in *"after rc=0"*) false ;; *"after rc="*) true ;; *) false ;; esac'

#############################################################################
section "N6 — the packages step never aborts halfway (1.6)"
#############################################################################

_pk_setup() { # _pk_setup <W> -- repo with a Brewfile, code.list and stub brew/code
  local W="$1"; mkdir -p "$W/repo/packages" "$W/repo/scripts/lib" "$W/bin" "$W/h"; cp scripts/lib/lists.sh "$W/repo/scripts/lib/"
  printf 'tap "acme/tools"\nbrew "thing"\nmas "Some App", id: 1\n' > "$W/repo/Brewfile"
  printf '# editors\na.one\nb.two\nc.three\n' > "$W/repo/packages/code.list"
  cat > "$W/bin/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >> "$SW/log"
[ "$1" = bundle ] && exit "${BUNDLE_RC:-0}"
[ "$1" = tap ] && [ -n "${TAP_EATS_STDIN:-}" ] && cat >/dev/null
if [ "$1" = trust ] && [ -n "${TRUST_FAIL:-}" ]; then echo "Error: trust nope" >&2; exit 1; fi
exit 0
STUB
  cat > "$W/bin/code" <<'STUB'
#!/bin/bash
echo "code $*" >> "$SW/log"
case "$1" in
  --list-extensions) printf 'a.one\nB.Two\n' ;;
  --install-extension) [ "$2" = "${FAILEXT:-}" ] && exit 1; exit 0 ;;
esac
STUB
  chmod +x "$W/bin/brew" "$W/bin/code"
}
_pk_run() { # _pk_run <W> [env...] -- run sub_install_packages; env assignments follow
  local W="$1"; shift
  fn_of sub_install_packages > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; ROOT_DIR="$W/repo"; DOTFILES_YES=1
DOTFILES_CODE_BIN_FALLBACK="$W/no-such-code"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/requirers.sh; . "$W/fn.sh"
sub_install_packages
RUN
  timeout 30 env SW="$W" "$@" bash "$W/run.sh" </dev/null
}
t "N6.1" "each tap is tapped and then trusted" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" >/dev/null 2>&1
  [ "$(_first_line "brew tap acme/tools" "$W/log")" -gt 0 ] &&
  [ "$(_first_line "brew tap acme/tools" "$W/log")" -lt "$(_first_line "brew trust --tap acme/tools" "$W/log")" ]'
t "N6.2" "a failed tap trust shows the brew message and the step carries on" '
  W=$(sandbox); _pk_setup "$W"; out=$(_pk_run "$W" TRUST_FAIL=1 2>&1)
  case "$out" in *"trust nope"*) grep -q "bundle install" "$W/log" ;; *) false ;; esac'
t "N6.3" "the extension step still runs after a failed bundle, and the step returns non-zero" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" BUNDLE_RC=1 >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && grep -q "code --install-extension c.three" "$W/log"'
t "N6.4" "the installed extensions are listed exactly once" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" >/dev/null 2>&1
  [ "$(grep -c "code --list-extensions" "$W/log")" -eq 1 ]'
t "N6.5" "only the missing extensions are installed (ids compare case-insensitively)" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" >/dev/null 2>&1
  [ "$(grep -c "code --install-extension" "$W/log")" -eq 1 ] && grep -q "code --install-extension c.three" "$W/log"'
t "N6.6" "a failed extension install is counted, named and fails the step" '
  W=$(sandbox); _pk_setup "$W"; out=$(_pk_run "$W" FAILEXT=c.three 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *"c.three"*) true ;; *) false ;; esac'
t "N6.7" "Brewfile.local is bundled after Brewfile when it exists" '
  W=$(sandbox); _pk_setup "$W"; printf "brew \"private-thing\"\n" > "$W/repo/Brewfile.local"
  _pk_run "$W" >/dev/null 2>&1
  [ "$(_first_line "bundle install --file=Brewfile" "$W/log")" -gt 0 ] &&
  [ "$(_first_line "bundle install --file=Brewfile" "$W/log")" -lt "$(_first_line "bundle install --file=Brewfile.local" "$W/log")" ]'
t "N6.8" "Brewfile.local is not bundled when absent" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" >/dev/null 2>&1
  [ "$(grep -c "Brewfile.local" "$W/log")" -eq 0 ]'
t "N6.9" "a Brewfile.local tap is trusted too" '
  W=$(sandbox); _pk_setup "$W"; printf "tap \"private/tap\"\n" > "$W/repo/Brewfile.local"
  _pk_run "$W" >/dev/null 2>&1; grep -q "brew trust --tap private/tap" "$W/log"'
t "N6.10" "packages/code.local.list extensions are installed too" '
  W=$(sandbox); _pk_setup "$W"; printf "d.four\n" > "$W/repo/packages/code.local.list"
  _pk_run "$W" >/dev/null 2>&1; grep -q "code --install-extension d.four" "$W/log"'
t "N6.11" "the mas sign-in warning is printed even when the bundle failed" '
  W=$(sandbox); _pk_setup "$W"; out=$(_pk_run "$W" BUNDLE_RC=1 2>&1)
  case "$out" in *"mas entries need"*) true ;; *) false ;; esac'
t "N6.12" "brew cleanup still runs after a failed bundle" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" BUNDLE_RC=1 >/dev/null 2>&1; grep -q "brew cleanup" "$W/log"'
t "N6.13" "a missing code CLI fails the step and does not claim the extensions were installed" '
  W=$(sandbox); _pk_setup "$W"; command rm -f "$W/bin/code"
  out=$(_pk_run "$W" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && case "$out" in *"extensions installed"*) false ;; *"VS Code"*) true ;; *) false ;; esac'
t "N6.14" "the happy path returns 0" '
  W=$(sandbox); _pk_setup "$W"; _pk_run "$W" >/dev/null 2>&1'
t "N6.15" "declining the Brewfile prompt skips the step without failing" '
  W=$(sandbox); _pk_setup "$W"
  fn_of sub_install_packages > "$W/fn.sh"
  printf "PATH=\"%s/bin:/usr/bin:/bin\"; HOME=\"%s/h\"; ROOT_DIR=\"%s/repo\"\ncd \"%s\" || exit 1\n. scripts/echos.sh; . \"%s/fn.sh\"\nsub_install_packages\n" "$W" "$W" "$W" "$PWD" "$W" > "$W/run2.sh"
  SW="$W" bash "$W/run2.sh" </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && [ ! -e "$W/log" ]'

t "N6.16" "a brew that reads stdin cannot swallow the taps still to come" '
  W=$(sandbox); _pk_setup "$W"; printf "tap \"acme/tools\"\ntap \"beta/tools\"\n" > "$W/repo/Brewfile"
  _pk_run "$W" TAP_EATS_STDIN=1 >/dev/null 2>&1; grep -q "brew tap beta/tools" "$W/log"'


#############################################################################
section "N7 — submodules and Prezto runcoms (1.7)"
#############################################################################

# Runs one bin/dotfiles function with dotfiles_ensure_submodule replaced by a
# logger, so no submodule is ever fetched.
_sm_run() { # _sm_run <W> <function> -- ROOT_DIR/DOTFILES_DIR are $W/df
  local W="$1" fn="$2"
  fn_of "$fn" > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="/usr/bin:/bin"; HOME="$W/h"; ROOT_DIR="$W/df"; DOTFILES_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh
dotfiles_ensure_submodule() { echo "ensure \$1" >> "$W/log"; [ "\$1" != "\${FAIL_SM:-}" ]; }
. "$W/fn.sh"
$fn
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
t "N7.1" "install --prezto also initialises modules/fzf-tab" '
  W=$(sandbox); mkdir -p "$W/df/scripts" "$W/h"; printf "exit 0\n" > "$W/df/scripts/install_prezto.zsh"
  _sm_run "$W" sub_install_prezto >/dev/null 2>&1
  grep -q "^ensure modules/prezto$" "$W/log" && grep -q "^ensure modules/fzf-tab$" "$W/log"'
t "N7.2" "configure --defaults initialises every apps/* submodule listed in .gitmodules, and only those" '
  W=$(sandbox); mkdir -p "$W/df/macos" "$W/h"
  printf "[submodule \"apps/a/one\"]\n\tpath = apps/a/one\n[submodule \"apps/b/two\"]\n\tpath = apps/b/two\n[submodule \"modules/prezto\"]\n\tpath = modules/prezto\n" > "$W/df/.gitmodules"
  printf "echo defaults >> \"%s/log\"\n" "$W" > "$W/df/macos/defaults-x.sh"
  _sm_run "$W" sub_configure_defaults >/dev/null 2>&1
  grep -q "^ensure apps/a/one$" "$W/log" && grep -q "^ensure apps/b/two$" "$W/log" &&
  [ "$(grep -c "modules/" "$W/log")" -eq 0 ]'
t "N7.3" "the submodules are initialised before the defaults scripts run" '
  W=$(sandbox); mkdir -p "$W/df/macos" "$W/h"
  printf "[submodule \"apps/a/one\"]\n\tpath = apps/a/one\n" > "$W/df/.gitmodules"
  printf "echo defaults >> \"%s/log\"\n" "$W" > "$W/df/macos/defaults-x.sh"
  _sm_run "$W" sub_configure_defaults >/dev/null 2>&1
  [ "$(_first_line "ensure apps/a/one" "$W/log")" -gt 0 ] &&
  [ "$(_first_line "ensure apps/a/one" "$W/log")" -lt "$(_first_line defaults "$W/log")" ]'
t "N7.4" "a submodule that cannot be initialised warns and the defaults still run" '
  W=$(sandbox); mkdir -p "$W/df/macos" "$W/h"
  printf "[submodule \"apps/a/one\"]\n\tpath = apps/a/one\n[submodule \"apps/b/two\"]\n\tpath = apps/b/two\n" > "$W/df/.gitmodules"
  printf "echo defaults >> \"%s/log\"\n" "$W" > "$W/df/macos/defaults-x.sh"
  out=$(FAIL_SM=apps/a/one _sm_run "$W" sub_configure_defaults 2>&1); rc=$?
  [ "$rc" -eq 0 ] && grep -q "^defaults$" "$W/log" && grep -q "^ensure apps/b/two$" "$W/log" &&
  case "$out" in *warning*"apps/a/one"*) true ;; *) false ;; esac'
t "N7.5" "no apps/* path is hardcoded in bin/dotfiles" \
  '[ "$(code_of bin/dotfiles | grep -c "ensure_submodule apps/")" -eq 0 ]'

_pz_setup() { # _pz_setup <W> -- fake DOTFILES_DIR with a prezto runcoms dir and the runcoms the repo ships
  local W="$1"; mkdir -p "$W/df/modules/prezto/runcoms" "$W/df/runcom" "$W/h"
  : > "$W/df/modules/prezto/init.zsh"
  local f; for f in zshenv zlogout zshrc zprofile zpreztorc zlogin zextra README.md; do : > "$W/df/modules/prezto/runcoms/$f"; done
  for f in .zshrc .zprofile .zpreztorc .zlogin; do : > "$W/df/runcom/$f"; done
}
_pz_run() { env -u ZDOTDIR DOTFILES_DIR="$1/df" HOME="$1/h" zsh scripts/install_prezto.zsh; }
t "N7.6" "install_prezto.zsh links the runcoms the repo does not ship" '
  W=$(sandbox); _pz_setup "$W"; _pz_run "$W" >/dev/null 2>&1
  [ -L "$W/h/.zshenv" ] && [ -L "$W/h/.zextra" ]'
t "N7.7" "install_prezto.zsh leaves alone every runcom the repo ships" '
  W=$(sandbox); _pz_setup "$W"; _pz_run "$W" >/dev/null 2>&1
  [ ! -e "$W/h/.zshrc" ] && [ ! -e "$W/h/.zprofile" ] && [ ! -e "$W/h/.zpreztorc" ] && [ ! -e "$W/h/.zlogin" ]'
t "N7.8" "install_prezto.zsh never links zlogout (it prints a quote on every shell exit)" '
  W=$(sandbox); _pz_setup "$W"; _pz_run "$W" >/dev/null 2>&1
  [ ! -e "$W/h/.zlogout" ] && [ ! -L "$W/h/.zlogout" ]'
t "N7.9" "install_prezto.zsh does not link README.md" '
  W=$(sandbox); _pz_setup "$W"; _pz_run "$W" >/dev/null 2>&1; [ ! -e "$W/h/.README.md" ]'

#############################################################################
section "N8 — /etc/hosts is backed up once (1.8)"
#############################################################################

_hosts_setup() { # _hosts_setup <W> -- stubs for a run against a sandbox hosts file
  local W="$1"; mkdir -p "$W/bin" "$W/df/system"
  cat > "$W/bin/curl" <<'STUB'
#!/bin/bash
o=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && o="$2"; shift; done
{ echo "# Title: StevenBlack/hosts"; echo "# BLOCKLIST"; awk "BEGIN{for(i=0;i<10001;i++) print \"0.0.0.0 e\" i \".example\"}"; } > "$o"
STUB
  cat > "$W/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$SW/log"
exec "$@"
STUB
  printf '#!/bin/bash\nexit 0\n' > "$W/bin/dscacheutil"; printf '#!/bin/bash\nexit 0\n' > "$W/bin/killall"
  chmod +x "$W/bin/"*
  printf '127.0.0.1 localhost\n# PRISTINE\n' > "$W/hosts"
}
_hosts_run() { # _hosts_run <W>
  local W="$1"
  fn_of sub_install_hosts > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; ROOT_DIR="$W/df"; DOTFILES_YES=1; DOTFILES_HOSTS_FILE="$W/hosts"; TMPDIR="$W"
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  SW="$W" timeout 60 bash "$W/run.sh" </dev/null
}
t "N8.1" "the first run backs up the pristine hosts file" '
  W=$(sandbox); _hosts_setup "$W"; _hosts_run "$W" >/dev/null 2>&1
  grep -q PRISTINE "$W/hosts.backup" && grep -q BLOCKLIST "$W/hosts"'
t "N8.2" "a re-run does not overwrite the backup with the blocklist" '
  W=$(sandbox); _hosts_setup "$W"; _hosts_run "$W" >/dev/null 2>&1; _hosts_run "$W" >/dev/null 2>&1
  grep -q PRISTINE "$W/hosts.backup" && ! grep -q BLOCKLIST "$W/hosts.backup"'
t "N8.3" "a re-run does not even attempt the backup copy" '
  W=$(sandbox); _hosts_setup "$W"; _hosts_run "$W" >/dev/null 2>&1; : > "$W/log"; _hosts_run "$W" >/dev/null 2>&1
  [ "$(grep -c "^sudo cp $W/hosts $W/hosts.backup" "$W/log")" -eq 0 ]'

#############################################################################
section "N9 — LaunchAgents lose their quarantine attribute (1.9)"
#############################################################################

_la_run() { # _la_run <W> -- install one plist against stub xattr/launchctl
  local W="$1"; mkdir -p "$W/bin" "$W/df/launchagents" "$W/h"
  : > "$W/df/launchagents/com.example.job.plist"
  printf '#!/bin/bash\necho "xattr $*" >> "%s/log"\nexit "${XATTR_RC:-0}"\n' "$W" > "$W/bin/xattr"
  printf '#!/bin/bash\necho "launchctl $*" >> "%s/log"\nexit 0\n' "$W" > "$W/bin/launchctl"
  chmod +x "$W/bin/xattr" "$W/bin/launchctl"
  fn_of sub_install_launchagents > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; DOTFILES_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . "$W/fn.sh"
sub_install_launchagents
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
t "N9.1" "the copied plist has com.apple.quarantine removed before launchctl bootstrap" '
  W=$(sandbox); _la_run "$W" >/dev/null 2>&1
  grep -q "^xattr -d com.apple.quarantine $W/h/Library/LaunchAgents/com.example.job.plist$" "$W/log" &&
  [ "$(_first_line "xattr -d" "$W/log")" -lt "$(_first_line "launchctl bootstrap" "$W/log")" ]'
t "N9.2" "a plist without the attribute (xattr fails) is not an error" '
  W=$(sandbox); XATTR_RC=1 _la_run "$W" >/dev/null 2>&1 && grep -q "launchctl bootstrap" "$W/log"'


#############################################################################
section "N10 — the doctor tells the truth (1.10)"
#############################################################################

_has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# A sandbox repo and HOME the doctor can inspect without touching the real
# ones. xcode-select and git are stubs: git logs every call, so a test can
# see whether the doctor ran it while the Command Line Tools were missing.
_doc_setup() { # _doc_setup <W> <clt: yes|no>
  local W="$1" clt="$2"; mkdir -p "$W/bin" "$W/h/.config" "$W/df/modules/prezto" "$W/df/modules/fzf-tab" "$W/df/apps/x/y" "$W/df/runcom" "$W/df/config/mise"
  : > "$W/df/modules/prezto/init.zsh"; : > "$W/df/modules/fzf-tab/f"
  printf '[submodule "modules/prezto"]\n\tpath = modules/prezto\n[submodule "modules/fzf-tab"]\n\tpath = modules/fzf-tab\n[submodule "apps/x/y"]\n\tpath = apps/x/y\n' > "$W/df/.gitmodules"
  : > "$W/df/runcom/.zshrc"; : > "$W/df/runcom/.zprofile"
  ln -s "$W/df/runcom/.zshrc" "$W/h/.zshrc"; ln -s "$W/df/runcom/.zprofile" "$W/h/.zprofile"
  ln -s "$W/df/config/mise" "$W/h/.config/mise"
  if [ "$clt" = yes ]; then stub "$W/bin" xcode-select 'echo /Library/Developer/CommandLineTools'; else stub "$W/bin" xcode-select 'exit 1'; fi
  stub "$W/bin" git 'echo "git $*" >> "$SW/log"; case "$*" in *core.hooksPath*) [ -n "${HP:-}" ] && echo "$HP" ;; esac; exit 0'
  stub "$W/bin" brew 'case "$1" in --version) echo "Homebrew 7.0.0" ;; esac; exit 0'
}
_doc_run() { # _doc_run <W> [doctor args...]
  local W="$1"; shift
  env SW="$W" HP="${HP:-}" HOME="$W/h" XDG_CONFIG_HOME="$W/h/.config" DOTFILES_DIR="$W/df" PATH="$W/bin:/usr/bin:/bin" SHELL=/bin/zsh XDG_CACHE_HOME="$W/cache" TERM=dumb \
    zsh bin/dotfiles-doctor "$@" </dev/null
}
t "N10.1" "no phantom submodules: prezto-contrib and stevenblack-hosts are never mentioned" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(_doc_run "$W" 2>&1)
  case "$out" in *prezto-contrib*|*stevenblack*) false ;; *) true ;; esac'
t "N10.2" "the submodule list comes from .gitmodules: an uninitialised one is named, initialised ones pass" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(_doc_run "$W" 2>&1)
  _has "$out" "apps/x/y not initialized" && _has "$out" "modules/fzf-tab initialized"'
t "N10.3" "with every submodule initialised the doctor reports no error at all" '
  W=$(sandbox); _doc_setup "$W" yes; : > "$W/df/apps/x/y/f"
  _doc_run "$W" >/dev/null 2>&1'
t "N10.4" "no warning about ~/.vimrc or ~/.gitconfig, which runcom/ does not ship" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(_doc_run "$W" 2>&1)
  case "$out" in *.vimrc*|*.gitconfig*) false ;; *) true ;; esac'
t "N10.5" "expected symlinks come from runcom/: a shipped file that is not linked is reported" '
  W=$(sandbox); _doc_setup "$W" yes; : > "$W/df/runcom/.zlogin"; out=$(_doc_run "$W" 2>&1)
  case "$out" in *".zlogin not found"*) true ;; *) false ;; esac'
t "N10.6" "a linked runcom file is reported as linked" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(_doc_run "$W" 2>&1)
  case "$out" in *".zshrc →"*) true ;; *) false ;; esac'
t "N10.7" "without the Command Line Tools git is never run" '
  W=$(sandbox); _doc_setup "$W" no; _doc_run "$W" >/dev/null 2>&1; [ ! -e "$W/log" ]'
t "N10.8" "without the Command Line Tools git is not reported as installed" '
  W=$(sandbox); _doc_setup "$W" no; out=$(_doc_run "$W" 2>&1)
  case "$out" in *"git (Version control)"*) false ;; *) true ;; esac'
t "N10.9" "with the Command Line Tools the git identity is still checked" '
  W=$(sandbox); _doc_setup "$W" yes; _doc_run "$W" >/dev/null 2>&1; grep -q "^git config" "$W/log"'
t "N10.10" "an unlinked ~/.config/mise is a warning, a linked one is ok" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(_doc_run "$W" 2>&1)
  _has "$out" "mise config is linked" &&
  { command rm -f "$W/h/.config/mise"; out=$(_doc_run "$W" 2>&1); _has "$out" "mise config is not linked"; }'
t "N10.11" "--fix initialises submodules shallowly" '
  W=$(sandbox); _doc_setup "$W" yes; _doc_run "$W" --fix >/dev/null 2>&1
  grep -q "^git submodule update --init --depth 1" "$W/log"'
t "N10.12" "--fix does not init recursively without a depth" \
  '[ "$(code_of bin/dotfiles-doctor | grep -c "submodule update --init --recursive")" -eq 0 ]'

#############################################################################
section "N11 — the setup wizard (1.11)"
#############################################################################

# The wizard runs from a sandbox repo copy whose bin/dotfiles is a stub, so
# every delegated step is only logged.
_wiz_setup() { # _wiz_setup <W> <clt: yes|no>
  local W="$1" clt="$2"; _clt_stubs "$W"; mkdir -p "$W/repo/bin" "$W/repo/scripts/lib" "$W/h"
  cp bin/dotfiles-setup "$W/repo/bin/dotfiles-setup"; cp scripts/lib/clt.sh "$W/repo/scripts/lib/clt.sh"
  stub "$W/repo/bin" dotfiles 'echo "dotfiles $*" >> "$SW/log"; [ "$*" = "link" ] && exit "${LINK_RC:-0}"; exit 0'
  cat > "$W/bin/uname" <<'STUB'
#!/bin/bash
case "$1" in -m) echo arm64 ;; *) echo Darwin ;; esac
STUB
  stub "$W/bin" git 'echo "git $*" >> "$SW/log"; echo "git version 9.9.9"'
  stub "$W/bin" clear 'exit 0'
  chmod +x "$W/bin/uname"
  [ "$clt" = yes ] && : > "$W/clt-installed"
  _clt_offer "$W" 1 "Command Line Tools for Xcode 27.0-27.0"
}
_wiz_run() { # _wiz_run <W> <answers> -- feed answers, one per prompt
  local W="$1"
  printf '%b' "$2" | env SW="$W" HOME="$W/h" TMPDIR="$W" SHELL=/bin/zsh PATH="$W/bin:/usr/bin:/bin" TERM=dumb \
    DOTFILES_CLT_SENTINEL="$W/sentinel" DOTFILES_CLT_RETRY_SLEEP=0 bash "$W/repo/bin/dotfiles-setup"
}
# Prompts, in order: Ready?, Prezto?, Link?, macOS defaults?, Dock?, Node?
_wiz_yes_link="y\nn\ny\nn\nn\nn\n"
_wiz_no_link="y\nn\nn\nn\nn\nn\n"
t "N11.1" "the Command Line Tools are installed first, before any delegated step" '
  W=$(sandbox); _wiz_setup "$W" no; _wiz_run "$W" "$_wiz_yes_link" >/dev/null 2>&1
  [ "$(_first_line "softwareupdate --install" "$W/log")" -gt 0 ] &&
  [ "$(_first_line "softwareupdate --install" "$W/log")" -lt "$(_first_line "dotfiles " "$W/log")" ]'
t "N11.2" "a failed Command Line Tools install stops the wizard before git or any step runs" '
  W=$(sandbox); _wiz_setup "$W" no; echo 1 > "$W/install.rc"
  ! _wiz_run "$W" "$_wiz_yes_link" >/dev/null 2>&1 &&
  [ "$(grep -c "^git \|^dotfiles " "$W/log")" -eq 0 ]'
t "N11.3" "with the tools present nothing is installed and the wizard carries on" '
  W=$(sandbox); _wiz_setup "$W" yes; _wiz_run "$W" "$_wiz_yes_link" >/dev/null 2>&1
  [ "$(grep -c "softwareupdate" "$W/log")" -eq 0 ] && grep -q "^dotfiles install --ssh" "$W/log"'
t "N11.4" "an accepted, successful link is reported as linked" '
  W=$(sandbox); _wiz_setup "$W" yes; out=$(_wiz_run "$W" "$_wiz_yes_link" 2>&1)
  case "$out" in *"Configuration linked"*) true ;; *) false ;; esac'
t "N11.5" "a declined link is not reported as linked" '
  W=$(sandbox); _wiz_setup "$W" yes; out=$(_wiz_run "$W" "$_wiz_no_link" 2>&1)
  case "$out" in *"Configuration linked"*) false ;; *"Setup Complete"*) true ;; *) false ;; esac'
t "N11.6" "a failed link is not reported as linked" '
  W=$(sandbox); _wiz_setup "$W" yes; out=$(LINK_RC=1 _wiz_run "$W" "$_wiz_yes_link" 2>&1)
  case "$out" in *"Configuration linked"*) false ;; *"Setup Complete"*) true ;; *) false ;; esac'

#############################################################################
section "W1 — the harness timeout works without GNU timeout"
#############################################################################

t "W1.1" "the fallback returns 124 when the command outlives the limit, and quickly" '
  s=$SECONDS
  bash -c "source tests/lib.sh; _timeout_fallback 1 sleep 8" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 124 ] && [ $((SECONDS - s)) -lt 6 ]'
t "W1.2" "the fallback passes the command exit status through" '
  bash -c "source tests/lib.sh; _timeout_fallback 5 bash -c \"exit 7\"" >/dev/null 2>&1; [ $? -eq 7 ]'
t "W1.3" "the fallback passes stdout and stdin through" '
  out=$(printf hello | bash -c "source tests/lib.sh; _timeout_fallback 5 cat" 2>/dev/null); [ "$out" = hello ]'
t "W1.4" "the fallback returns promptly when the command finishes early" '
  s=$SECONDS; bash -c "source tests/lib.sh; _timeout_fallback 30 true" >/dev/null 2>&1
  [ $((SECONDS - s)) -lt 10 ]'
t "W1.5" "timeout works under a stock PATH with no GNU timeout" '
  s=$SECONDS
  env PATH=/usr/bin:/bin _TEST_FORCE_TIMEOUT_FALLBACK=1 bash -c "source tests/lib.sh; timeout 1 sleep 8" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 124 ] && [ $((SECONDS - s)) -lt 6 ]'
t "W1.6" "timeout runs a shell function-free command normally under a stock PATH" '
  out=$(env PATH=/usr/bin:/bin bash -c "source tests/lib.sh; timeout 5 echo ok" 2>/dev/null); [ "$out" = ok ]'

#############################################################################
section "W2 — dotfiles-test hands its repo path to the tools it runs"
#############################################################################

# CI has no ~/.dotfiles: the runner checks the repo out elsewhere. Without an
# exported DOTFILES_DIR, dotfiles-baseline fell back to $HOME/.dotfiles, listed
# 0 keys and failed, and set -e then skipped tests/run.sh.
t "W2.1" "the baseline check passes with an empty HOME and the repo elsewhere" '
  W=$(sandbox); mkdir -p "$W/h"
  out=$(env -u DOTFILES_DIR HOME="$W/h" DOTFILES_TEST_ONLY=test_defaults_baseline "$PWD/bin/dotfiles-test" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && case "$out" in *"Captures all"*) true ;; *) false ;; esac'
t "W2.2" "DOTFILES_TEST_ONLY refuses a name that is not a test function" '
  W=$(sandbox); mkdir -p "$W/h"
  ! env HOME="$W/h" DOTFILES_TEST_ONLY=rm "$PWD/bin/dotfiles-test" >/dev/null 2>&1 &&
  ! env HOME="$W/h" DOTFILES_TEST_ONLY=test_nonesuch "$PWD/bin/dotfiles-test" >/dev/null 2>&1'

#############################################################################
section "W3 — hooks, unattended Homebrew, ignored files kept across link"
#############################################################################

t "W3.1" "install sets the repo-local git hooks after the Command Line Tools and before Homebrew" '
  W=$(sandbox); _mk_repo "$W"; _run_repo "$W" install >/dev/null 2>&1
  [ "$(_first_line clt "$W/log")" -lt "$(_first_line hooks "$W/log")" ] &&
  [ "$(_first_line hooks "$W/log")" -lt "$(_first_line homebrew "$W/log")" ]'
t "W3.2" "a failed hooks step is reported and does not stop the rest" '
  W=$(sandbox); _mk_repo "$W"; out=$(FAIL=hooks _run_repo "$W" install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_log_line "$W/log")" = "keepalive clt hooks homebrew brew:stow ssh" ]'
t "W3.3" "sub_hooks sets a repo-local core.hooksPath, twice without harm, and never a global one" '
  W=$(sandbox); mkdir -p "$W/repo" "$W/h"; git init -q "$W/repo"
  fn_of sub_hooks > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
export HOME="$W/h" GIT_CONFIG_GLOBAL="$W/h/gitconfig" GIT_CONFIG_NOSYSTEM=1
DOTFILES_DIR="$W/repo"
cd "$PWD" || exit 1
. scripts/echos.sh; . "$W/fn.sh"
sub_hooks && sub_hooks
RUN
  bash "$W/run.sh" </dev/null >/dev/null 2>&1 &&
  [ "$(git -C "$W/repo" config --local core.hooksPath)" = .githooks ] &&
  [ ! -s "$W/h/gitconfig" ]'
t "W3.4" "the doctor warns when core.hooksPath is not set for the repo" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(HP="" _doc_run "$W" 2>&1)
  _has "$out" "Git hooks are not enabled"'
t "W3.5" "the doctor is quiet about hooks when core.hooksPath is set" '
  W=$(sandbox); _doc_setup "$W" yes; out=$(HP=.githooks _doc_run "$W" 2>&1)
  ! _has "$out" "Git hooks are not enabled" && _has "$out" "Git hooks path: .githooks"'

_hb_run() { # _hb_run <W> <yes|no> -- sub_install_homebrew with a curl stub that records NONINTERACTIVE
  local W="$1" yes="$2"
  mkdir -p "$W/h"
  stub "$W/bin" curl "echo \"echo \\\"NI=\\\${NONINTERACTIVE:-}\\\" > \\\"\$SW/ni\\\"\""
  fn_of sub_install_homebrew > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:/usr/bin:/bin"; HOME="$W/h"; HOMEBREW_PREFIX="$W"; export SW="$W"
[ "$yes" = yes ] && export DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/requirers.sh; . "$W/fn.sh"
sub_install_homebrew
RUN
  timeout 20 bash "$W/run.sh" </dev/null
}
t "W3.6" "with DOTFILES_YES=1 the Homebrew installer runs with NONINTERACTIVE=1" '
  W=$(sandbox); _hb_run "$W" yes >/dev/null 2>&1; [ "$(cat "$W/ni")" = "NI=1" ]'
t "W3.7" "without DOTFILES_YES the Homebrew installer is not forced non-interactive" '
  W=$(sandbox); _hb_run "$W" no >/dev/null 2>&1; [ "$(cat "$W/ni")" = "NI=" ]'

# A sandbox repo (real git, for check-ignore) whose config/ has one tracked
# file and one ignored file, plus a backup bucket holding what link moved aside.
_ig_repo() { # _ig_repo <W>
  local W="$1"
  mkdir -p "$W/repo/config/gh" "$W/backup/.config/gh" "$W/backup/.config/atuin"
  git init -q "$W/repo"
  printf 'config/gh/hosts.yml\nconfig/atuin/*.db\n' > "$W/repo/.gitignore"
  printf 'tracked\n' > "$W/repo/config/gh/config.yml"
  printf 'user: me\nprotocol: ssh\n' > "$W/backup/.config/gh/hosts.yml"
  printf 'old\n' > "$W/backup/.config/gh/config.yml"
}
_ig_call() { # _ig_call <W> -- run the restore helper
  (source scripts/echos.sh; source scripts/lib/fs.sh; dotfiles_restore_ignored_from_backup "$1/repo" config "$1/backup/.config")
}
t "W3.8" "an ignored file missing from the repo is copied in from the backup, and reported" '
  W=$(sandbox); _ig_repo "$W"; out=$(_ig_call "$W" 2>&1)
  [ "$(cat "$W/repo/config/gh/hosts.yml")" = "$(printf "user: me\nprotocol: ssh")" ] &&
  _has "$out" "hosts.yml"'
t "W3.9" "a tracked file is left as the repo has it" '
  W=$(sandbox); _ig_repo "$W"; _ig_call "$W" >/dev/null 2>&1
  [ "$(cat "$W/repo/config/gh/config.yml")" = tracked ]'
t "W3.10" "an existing ignored file in the repo is never overwritten" '
  W=$(sandbox); _ig_repo "$W"; printf "keep\n" > "$W/repo/config/gh/hosts.yml"; _ig_call "$W" >/dev/null 2>&1
  [ "$(cat "$W/repo/config/gh/hosts.yml")" = keep ]'
t "W3.11" "an unignored file the repo does not have is not copied in" '
  W=$(sandbox); _ig_repo "$W"; printf "x\n" > "$W/backup/.config/gh/stray.txt"; _ig_call "$W" >/dev/null 2>&1
  [ ! -e "$W/repo/config/gh/stray.txt" ]'
t "W3.12" "files in a directory the repo has not got yet are restored too (atuin)" '
  W=$(sandbox); _ig_repo "$W"; mkdir -p "$W/repo/config/atuin"; printf "d\n" > "$W/backup/.config/atuin/history.db"
  _ig_call "$W" >/dev/null 2>&1; [ "$(cat "$W/repo/config/atuin/history.db")" = d ]'
t "W3.13" "no backup bucket is a no-op that succeeds" '
  W=$(sandbox); _ig_repo "$W"; (source scripts/echos.sh; source scripts/lib/fs.sh; dotfiles_restore_ignored_from_backup "$W/repo" config "$W/nonesuch")'
t "W3.14" "sub_link restores gh/hosts.yml so it is live at ~/.config/gh through the stow link" '
  W=$(sandbox); mkdir -p "$W/h/.config/gh" "$W/bin" "$W/repo/runcom" "$W/repo/config/git" "$W/repo/config/gh"
  git init -q "$W/repo"; printf "config/gh/hosts.yml\n" > "$W/repo/.gitignore"
  : > "$W/repo/config/git/config.local"; printf "tracked\n" > "$W/repo/config/gh/config.yml"
  printf "user: me\n" > "$W/h/.config/gh/hosts.yml"; printf "old\n" > "$W/h/.config/gh/config.yml"
  # a stow stand-in: link every directory of the package into the target
  cat > "$W/bin/stow" <<STOW
#!/bin/bash
while [ \$# -gt 0 ]; do case "\$1" in -t) t=\$2; shift ;; --restow) ;; *) pkg=\$1 ;; esac; shift; done
for d in "\$PWD/\$pkg"/*; do [ -d "\$d" ] && ln -sfn "\$d" "\$t/\$(basename "\$d")"; done
exit 0
STOW
  chmod +x "$W/bin/stow"
  fn_of sub_link > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; XDG_CONFIG_HOME="$W/h/.config"; ROOT_DIR="$W/repo"; DOTFILES_YES=1
cd "$PWD" || exit 1
echo \$\$ >"$W/pid"
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_link
RUN
  bash "$W/run.sh" </dev/null >"$W/out" 2>&1 &&
  [ -L "$W/h/.config/gh" ] &&
  [ "$(cat "$W/h/.config/gh/hosts.yml")" = "user: me" ] &&
  [ "$(cat "$W/h/.config/gh/config.yml")" = tracked ]'

#############################################################################
section "T7 — two-Mac sync: routing, help and install --all (Task 7)"
#############################################################################
# _t7 <args...>: the real bin/dotfiles against a sandbox HOME. Only commands
# that fail early (no private repo) or print help are routed this way.
_t7() {
  local W="$1"; shift
  mkdir -p "$W/h"
  env -i HOME="$W/h" PATH="/usr/bin:/bin" DOTFILES_PRIVATE_DIR="$W/none" bash bin/dotfiles "$@" 2>&1
}
t "T7.1" "the top-level help lists private" \
  'out=$(bash bin/dotfiles help 2>&1); case "$out" in *"   private "*) true ;; *) false ;; esac'
t "T7.2" "install --help lists --private" \
  'out=$(bash bin/dotfiles install --help 2>&1); case "$out" in *"--private"*) true ;; *) false ;; esac'
t "T7.3" "dotfiles private is routed to bin/dotfiles-private (status with no repo says what to run)" '
  W=$(sandbox); out=$(_t7 "$W" private status); case "$out" in *"dotfiles private clone"*) true ;; *) false ;; esac'
t "T7.1b" "the top-level help lists sync and vault" \
  'out=$(bash bin/dotfiles help 2>&1); case "$out" in *"   sync "*) case "$out" in *"   vault "*) true ;; *) false ;; esac ;; *) false ;; esac'
t "T7.3b" "dotfiles sync is routed to bin/dotfiles-sync" \
  'W=$(sandbox); out=$(_t7 "$W" sync --help); case "$out" in *"--scheduled"*) true ;; *) false ;; esac'
t "T7.3c" "dotfiles vault is routed to bin/dotfiles-vault" \
  'W=$(sandbox); out=$(_t7 "$W" vault --help); case "$out" in *"vault migrate"*) true ;; *) false ;; esac'
t "T7.4" "the private step runs after prezto and right before link in install --all" '
  W=$(sandbox); _mk_repo "$W"; _run_repo "$W" install --all >/dev/null 2>&1
  a=$(_first_line private "$W/log"); b=$(_first_line link "$W/log"); [ "$a" -gt 0 ] && [ "$b" -eq $((a + 1)) ]'
t "T7.5" "a failed private clone is named, does not stop install --all, and the status is non-zero" '
  W=$(sandbox); _mk_repo "$W"; out=$(FAIL=private _run_repo "$W" install --all 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(_log_line "$W/log")" = "keepalive prezto private link node packages fonts launchagents claude codex configure hosts" ] &&
  case "$out" in *private*) true ;; *) false ;; esac'
t "T7.6" "install --private runs bin/dotfiles-private install after a confirm" '
  W=$(sandbox); mkdir -p "$W/df/bin" "$W/h"
  fn_of sub_install_private > "$W/fn.sh"
  printf "#!/bin/bash\necho \"private \$*\" >> \"%s/log\"\n" "$W" > "$W/df/bin/dotfiles-private"; chmod +x "$W/df/bin/dotfiles-private"
  ( DOTFILES_DIR="$W/df"; DOTFILES_YES=1; bot() { :; }; confirm() { return 0; }; skip() { :; }
    source "$W/fn.sh"; sub_install_private ) >/dev/null 2>&1 &&
  [ "$(command cat "$W/log")" = "private install" ]'

#############################################################################
section "L — link is all-or-nothing and stow never sees Finder litter"
#############################################################################
# Incident: runcom/.DS_Store (Finder, gitignored) made `stow --restow` abort
# AFTER the backup sweep had dropped every owned link, leaving $HOME with no
# shell config. These run the real sub_link against a sandbox HOME and repo.
_have_stow() { command -v stow >/dev/null 2>&1; }
# _lk_env <W> [stow-wrapper-body]: sandbox repo (runcom + config), HOME, runner.
# The wrapper, when given, runs first with "$@" and may exit; otherwise real stow.
_lk_env() {
  local W="$1" real; real=$(command -v stow)
  mkdir -p "$W/repo/runcom" "$W/repo/config/git" "$W/h/.config" "$W/bin"
  local f; for f in .zshrc .zprofile .zlogin .gemrc .hushlogin; do echo "repo $f" >"$W/repo/runcom/$f"; done
  echo repo >"$W/repo/config/git/config"; : >"$W/repo/config/git/config.local"
  printf '#!/bin/bash\n%s\nexec "%s" "$@"\n' "${2:-:}" "$real" >"$W/bin/stow"; chmod +x "$W/bin/stow"
  fn_of sub_link >"$W/fn.sh"
  cat >"$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; HOME="$W/h"; XDG_CONFIG_HOME="$W/h/.config"; ROOT_DIR="$W/repo"; DOTFILES_YES=1
cd "$PWD" || exit 1
echo \$\$ >"$W/pid"
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_link
RUN
}
_lk_run() { bash "$1/run.sh" </dev/null >"$1/out" 2>&1; }
# _lk_state <W>: every entry directly in HOME and XDG with what it points at.
_lk_state() {
  local f; for f in "$1"/h/.[a-z]* "$1"/h/.config/*; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -e "$f" ]; then printf '%s %s\n' "$f" "$(command cat "$f" 2>/dev/null | head -c 40)"; fi
  done | LC_ALL=C sort
}

t "L1.1" "a runcom/.DS_Store and a ~/.DS_Store do not stop link: every runcom link exists" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W"; : >"$W/repo/runcom/.DS_Store"; : >"$W/h/.DS_Store"
  _lk_run "$W" && for f in .zshrc .zprofile .zlogin .gemrc .hushlogin; do [ -L "$W/h/$f" ] || return 1; done &&
  [ -L "$W/h/.config/git" ] && [ ! -L "$W/h/.DS_Store" ]'

t "L2.1" "a failed dry-run leaves HOME exactly as found and link returns non-zero" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W" "case \"\$*\" in *-n*config*) echo \"WARNING! cannot stow config/git over existing target git\"; exit 1;; esac"
  (cd "$W/repo" && command stow --restow -t "$W/h" runcom && command stow --restow -t "$W/h/.config" config)
  rm "$W/h/.hushlogin"; echo MINE >"$W/h/.hushlogin"   # a real file the sweep will move
  before=$(_lk_state "$W")
  _lk_run "$W"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(_lk_state "$W")" = "$before" ] && [ "$(command cat "$W/h/.hushlogin")" = MINE ] &&
  grep -q "cannot stow config/git" "$W/out" && grep -qi "error" "$W/out"'

t "L2.2" "a real stow that fails after a good dry-run is rolled back too" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W" "case \"\$*\" in *-n*) ;; *config*) echo \"stow: real run failed\"; exit 1;; esac"
  (cd "$W/repo" && command stow --restow -t "$W/h" runcom && command stow --restow -t "$W/h/.config" config)
  rm "$W/h/.hushlogin"; echo MINE >"$W/h/.hushlogin"
  before=$(_lk_state "$W")
  _lk_run "$W"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(_lk_state "$W")" = "$before" ] && [ "$(command cat "$W/h/.hushlogin")" = MINE ] &&
  grep -q "real run failed" "$W/out"'

t "L3.1" "the sweep no longer drops links the repo already owns" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/target" "$W/backup"
  echo REPO >"$W/df/runcom/.testrc"; ln -s "../df/runcom/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/runcom" "$W/target" "$W/backup")
  [ -L "$W/target/.testrc" ] && [ ! -e "$W/backup" -o -z "$(ls -A "$W/backup")" ]'

t "L4.1" "the shared helper passes the .DS_Store ignore to stow, simulated or not" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/repo/runcom" "$W/repo/config"; : >"$W/log"
  printf "#!/bin/bash\necho \"\$*\" >>\"$W/log\"\n" >"$W/bin/stow"; chmod +x "$W/bin/stow"
  (PATH="$W/bin:$PATH"; source scripts/lib/fs.sh; dotfiles_stow_all -n "$W/repo" "$W/h" "$W/x"; dotfiles_stow_all - "$W/repo" "$W/h" "$W/x")
  [ "$(grep -cF -- "--ignore=^\\.DS_Store\$" "$W/log")" -eq 4 ] && [ "$(grep -c -- "^-n " "$W/log")" -eq 2 ]'

t "L4.2" "link and sync both go through the helper (no bare stow --restow left)" '
  ! grep -q "stow --restow" <(code_of bin/dotfiles bin/dotfiles-sync) &&
  grep -q dotfiles_stow_all <(code_of bin/dotfiles) && grep -q dotfiles_stow_all <(code_of bin/dotfiles-sync)'


t "L5.1" "a Finder-litter lookalike is linked: the ignore matches the whole name" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W"; : >"$W/repo/runcom/keep.DS_Store"; : >"$W/repo/runcom/.DS_Store"
  _lk_run "$W" && [ -L "$W/h/keep.DS_Store" ] && [ ! -e "$W/h/.DS_Store" ]'

t "L5.2" "a real directory nested under ~/.config is put back when the real stow fails" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W" "case \"\$*\" in *-n*) ;; *config*) echo \"stow: real run failed\"; exit 1;; esac"
  (cd "$W/repo" && command stow --restow -t "$W/h" runcom)
  mkdir -p "$W/h/.config/git/sub/deep"; echo MINE >"$W/h/.config/git/sub/deep/file"
  before=$(_lk_state "$W")
  _lk_run "$W"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(_lk_state "$W")" = "$before" ] &&
  [ "$(command cat "$W/h/.config/git/sub/deep/file")" = MINE ] && [ ! -e "$W/h/.dotfiles_backup" ]'

t "L5.3" "a TERM while stow runs rolls back what the sweep moved and stops link" '
  _have_stow || return 0
  W=$(sandbox); _lk_env "$W" "case \"\$*\" in *-n*) ;; *) kill -TERM \$(command cat $W/pid); sleep 1; exit 0;; esac"
  (cd "$W/repo" && command stow --restow -t "$W/h" runcom && command stow --restow -t "$W/h/.config" config)
  rm "$W/h/.hushlogin"; echo MINE >"$W/h/.hushlogin"
  before=$(_lk_state "$W")
  _lk_run "$W"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(_lk_state "$W")" = "$before" ] && [ "$(command cat "$W/h/.hushlogin")" = MINE ] &&
  [ "$(ls "$W"/dotfiles-link.* 2>/dev/null | wc -l)" -eq 0 ]'

finish

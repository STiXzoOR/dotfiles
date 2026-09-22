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
  sed -n "/^sub_install_packages()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:$PATH"; ROOT_DIR="$PWD"; DOTFILES_YES=1
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
  '! grep -q "com.apple.quarantine" <(code_of bin/dotfiles)'
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
t "A8.3c" "arm64 is not blocked" 'bash bin/dotfiles help 2>&1 | grep -q "Usage:"'
t "A8.3d" "remote-install.sh guards the architecture too" \
  'grep -q "Apple silicon only" <(code_of remote-install.sh)'
t "A8.4" "print_result is defined" \
  '(source scripts/echos.sh; declare -F print_result >/dev/null)'
t "A8.4b" "print_result reports failure as an error" \
  '(source scripts/echos.sh; print_result 1 boom) | grep -q "error"'
t "A8.4c" "print_result reports success as ok" \
  '(source scripts/echos.sh; print_result 0 fine) | grep -q "ok"'
t "A8.5" "CLT install is headless via softwareupdate" \
  'grep -q "softwareupdate" <(code_of bin/dotfiles) && grep -q "xcode-select -s" <(code_of bin/dotfiles)'
t "A8.6" "xcode wait loop is bounded" \
  '! grep -q "until xcode-select" <(code_of bin/dotfiles)'
t "A8.6b" "xcodebuild -license only runs against a real Xcode" \
  '! grep -qE "^[[:space:]]*sudo xcodebuild -license$" <(code_of bin/dotfiles)'
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
t "A9.1b" "a relative symlink into the package is just dropped, not backed up" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/target" "$W/backup"
  echo REPO > "$W/df/runcom/.testrc"
  ln -s "../df/runcom/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/runcom" "$W/target" "$W/backup")
  [ ! -e "$W/target/.testrc" ] && [ ! -L "$W/backup/.testrc" ]'
t "A9.1e" "an absolute symlink into the package is dropped too" '
  W=$(sandbox); mkdir -p "$W/pkg" "$W/target" "$W/backup"
  echo REPO > "$W/pkg/.testrc"; ln -s "$W/pkg/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/pkg" "$W/target" "$W/backup")
  [ ! -e "$W/target/.testrc" ] && [ ! -L "$W/backup/.testrc" ]'
t "A9.1f" "a relative symlink pointing outside the package is still backed up" '
  W=$(sandbox); mkdir -p "$W/df/runcom" "$W/target" "$W/backup" "$W/elsewhere"
  echo THEIRS > "$W/elsewhere/.testrc"; : > "$W/df/runcom/.testrc"
  ln -s "../elsewhere/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/runcom" "$W/target" "$W/backup")
  [ -L "$W/backup/.testrc" ]'
t "A9.1g" "a nested relative link, as stow makes under ~/.config, is dropped" '
  W=$(sandbox); mkdir -p "$W/df/config/git" "$W/target/xdg" "$W/backup"
  echo REPO > "$W/df/config/git/config"
  ln -s "../../df/config/git" "$W/target/xdg/git"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/df/config" "$W/target/xdg" "$W/backup")
  [ ! -e "$W/target/xdg/git" ] && [ ! -L "$W/backup/git" ]'
t "A9.1c" "a foreign symlink is preserved in the backup" '
  W=$(sandbox); mkdir -p "$W/pkg" "$W/target" "$W/backup" "$W/elsewhere"
  echo THEIRS > "$W/elsewhere/.testrc"; : > "$W/pkg/.testrc"
  ln -s "$W/elsewhere/.testrc" "$W/target/.testrc"
  (source scripts/lib/fs.sh; dotfiles_backup_stow_targets "$W/pkg" "$W/target" "$W/backup")
  [ -L "$W/backup/.testrc" ]'
t "A9.1d" "link stows config against XDG_CONFIG_HOME with a restow" \
  'grep -q "stow --restow -t \"\$XDG_CONFIG_HOME\" config" <(code_of bin/dotfiles)'
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
  'sed -n "/^sub_install_claude()/,/^}/p" <(code_of bin/dotfiles) | grep -qE "\|\| return 1|return \$\?"'
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
  'sed -n "/^sub_configure()/,/^}/p" <(code_of bin/dotfiles) | grep -q "_prev_yes"'
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
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; exit 9\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  sed -n "/^sub_install_node()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:/usr/bin:/bin"; source scripts/echos.sh; source scripts/requirers.sh; source "$W/fn.sh"
     sub_install_node >/dev/null 2>&1)'

t "A11.2b" "the node step does not print ok after a failed install" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\nexit 3\n" > "$W/bin/mise"; chmod +x "$W/bin/mise"
  sed -n "/^sub_install_node()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  ! (PATH="$W/bin:$PATH"; source scripts/echos.sh; source scripts/requirers.sh; source "$W/fn.sh"
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
if [ "\$1" = "cp" ] && [ "\$3" = "/etc/hosts" ]; then exit 1; fi
exit 0
SUDO
  chmod +x "$W/bin/curl" "$W/bin/sudo"
  sed -n "/^sub_install_hosts()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1
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
if [ "\$1" = "cp" ] && [ "\$3" = "/etc/hosts.backup" ]; then exit 1; fi
exit 0
SUDO
  chmod +x "$W/bin/curl" "$W/bin/sudo"
  sed -n "/^sub_install_hosts()/,/^}/p" bin/dotfiles > "$W/fn.sh"
  cat > "$W/run.sh" <<RUN
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  timeout 60 bash "$W/run.sh" </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ! grep -qE "cp .* /etc/hosts\$" "$W/sudo.log"'

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
PATH="$W/bin:\$PATH"; ROOT_DIR="$W/df"; DOTFILES_YES=1
cd "$PWD" || exit 1
. scripts/echos.sh; . scripts/lib/fs.sh; . "$W/fn.sh"
sub_install_hosts
RUN
  timeout 60 bash "$W/run.sh" </dev/null >/dev/null 2>&1'

finish

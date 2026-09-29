#!/usr/bin/env bash
#
# tests/private.sh -- bin/dotfiles-private: the private companion repo that
# carries the gitignored personal files between the MacBook and the Mac mini
# (Task 7 of the 2026-09-29 new-Mac readiness work).
#
# HERMETIC. A sandbox HOME, a sandbox public repo (DOTFILES_DIR), a sandbox
# private dir (DOTFILES_PRIVATE_DIR) and a bare "remote" created inside the
# sandbox (DOTFILES_PRIVATE_REMOTE). gh is a stub. The owner's real private
# repo is never named, cloned or fetched: every run sets the remote explicitly.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PRIV_BIN="$ROOT_DIR/bin/dotfiles-private"

# penv: a fresh sandbox; prints its path. $W/pub is a public repo holding some
# gitignored personal files, $W/remote.git is an empty bare remote.
penv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home" "$w/bin" "$w/pub/profiles" "$w/pub/config/git" "$w/pub/claude" "$w/pub/macos" "$w/pub/packages"
  : >"$w/log"
  git init -q -b main "$w/pub" || return 1
  printf 'export WORK=1\n' >"$w/pub/profiles/local.zsh"
  printf '[user]\n\tname = T\n' >"$w/pub/config/git/config.local"
  printf 'work-marketplace\n' >"$w/pub/claude/work.local.list"
  printf 'brew "wget"\n' >"$w/pub/Brewfile.local"
  printf 'DOTFILES_LOCALE=en_GB\n' >"$w/pub/macos/local.sh"
  git init -q --bare -b main "$w/remote.git" || return 1
  # gh: authenticated unless STUB_GH_AUTH=no; `repo clone <slug> <dir>` clones $STUB_BARE.
  stub "$w/bin" gh 'case "$1 $2" in
  "auth status") [ "${STUB_GH_AUTH:-yes}" = yes ] ;;
  "repo clone") git clone -q "$STUB_BARE" "$4" ;;
esac'
  printf '%s' "$w"
}

stub() { # stub <bindir> <name> <body>: logs argv to $STUB_LOG, then runs body
  mkdir -p "$1"
  { printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n%s\n' "$2" "${3:-}"; } >"$1/$2"
  chmod +x "$1/$2"
}

# priv <args>: run dotfiles-private against the sandbox in $W. $PENV adds
# VAR=value pairs (no spaces).
priv() {
  # shellcheck disable=SC2086
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/pub" \
    DOTFILES_PRIVATE_DIR="$W/priv" DOTFILES_PRIVATE_REMOTE="$W/remote.git" \
    STUB_LOG="$W/log" STUB_BARE="$W/remote.git" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
    ${PENV:-} bash "$PRIV_BIN" "$@"
}
# with_env "<VAR=val ...>" <command...>: run one command with extra sandbox env
# (dynamic scope: priv reads PENV, and nothing leaks into the next test).
with_env() { local PENV="$1"; shift; "$@"; }
# said <pattern> <args>: the command's output (both streams) contains <pattern>.
said() { local pat="$1" out; shift; out=$(priv "$@" 2>&1); printf '%s\n' "$out" | grep -q -- "$pat"; }
# refused <pattern> <args>: exits non-zero AND says <pattern>.
refused() {
  local pat="$1" out rc; shift
  out=$(priv "$@" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf '%s\n' "$out" | grep -c -- "$pat")" -ge 1 ]
}
# seeded: init the private repo, push it to the sandbox remote. A second Mac
# then clones it (see other_mac).
seeded() {
  priv init >/dev/null 2>&1 &&
    git -C "$W/priv" remote add origin "$W/remote.git" &&
    git -C "$W/priv" push -q -u origin main 2>/dev/null
}

#############################################################################
section "P1 -- init: move the gitignored files in, leave links behind"
#############################################################################
t "P1.1" "each gitignored file moves to the same relative path in the private dir" \
  'W=$(penv); priv init >/dev/null 2>&1 &&
   [ "$(command cat "$W/priv/profiles/local.zsh")" = "export WORK=1" ] &&
   [ -f "$W/priv/config/git/config.local" ] && [ -f "$W/priv/claude/work.local.list" ] &&
   [ -f "$W/priv/Brewfile.local" ] && [ -f "$W/priv/macos/local.sh" ]'
t "P1.2" "a symlink to the private copy is left where each file was" \
  'W=$(penv); priv init >/dev/null 2>&1 &&
   [ -L "$W/pub/profiles/local.zsh" ] && [ "$(readlink "$W/pub/profiles/local.zsh")" = "$W/priv/profiles/local.zsh" ] &&
   [ -L "$W/pub/Brewfile.local" ] && [ "$(command cat "$W/pub/Brewfile.local")" = "brew \"wget\"" ]'
t "P1.3" "the private dir is a git repo with a .gitignore and a first commit holding the files" \
  'W=$(penv); priv init >/dev/null 2>&1 &&
   [ -f "$W/priv/.gitignore" ] && [ "$(git -C "$W/priv" rev-list --count HEAD)" -eq 1 ] &&
   git -C "$W/priv" ls-files | grep -qx "profiles/local.zsh" && git -C "$W/priv" ls-files | grep -qx ".gitignore"'
t "P1.4" "init never creates the GitHub repo: gh is not run, the command is printed" '
  W=$(penv); out=$(priv init 2>&1)
  [ "$(grep -c "^gh" "$W/log")" -eq 0 ] &&
  printf "%s\n" "$out" | grep -q "gh repo create .*/dotfiles-private --private --source .* --push"'
t "P1.5" "init refuses to run over an existing private repo and changes nothing" '
  W=$(penv); priv init >/dev/null 2>&1; h=$(git -C "$W/priv" rev-parse HEAD)
  refused "already" init && [ "$(git -C "$W/priv" rev-parse HEAD)" = "$h" ]'
t "P1.6" "a file that is already a symlink is not moved" '
  W=$(penv); ln -s /nonexistent "$W/pub/profiles/local.post.zsh"; priv init >/dev/null 2>&1 &&
  [ ! -e "$W/priv/profiles/local.post.zsh" ] && [ "$(readlink "$W/pub/profiles/local.post.zsh")" = /nonexistent ]'
t "P1.7" "the ssh config is not taken from ~/.ssh by init" '
  W=$(penv); mkdir -p "$W/home/.ssh"; printf "Host x\n" >"$W/home/.ssh/config"; priv init >/dev/null 2>&1 &&
  [ ! -e "$W/priv/ssh/config" ] && [ ! -L "$W/home/.ssh/config" ]'
t "P1.8" "the private remote default names the owner repo, and the override is honoured" \
  '[ "$(code_of bin/dotfiles-private | grep -c "git@github.com:STiXzoOR/dotfiles-private.git")" -eq 1 ]'

#############################################################################
section "P2 -- clone"
#############################################################################
t "P2.1" "clone fetches the private repo into the private dir" '
  W=$(penv); seeded && command rm -rf "$W/priv" && priv clone >/dev/null 2>&1 &&
  [ -f "$W/priv/profiles/local.zsh" ] && [ -d "$W/priv/.git" ]'
t "P2.2" "clone over an existing repo does nothing and succeeds" '
  W=$(penv); seeded; h=$(git -C "$W/priv" rev-parse HEAD)
  priv clone >/dev/null 2>&1 && [ "$(git -C "$W/priv" rev-parse HEAD)" = "$h" ]'
t "P2.3" "a failed clone returns non-zero and says what to set up" '
  W=$(penv); E="DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no"
  with_env "$E" refused "gh auth login" clone && [ "$(with_env "$E" priv clone 2>&1 | grep -c "SSH key")" -ge 1 ] && [ ! -e "$W/priv/.git" ]'
t "P2.4" "with gh authenticated, a failed git clone falls back to gh repo clone" '
  W=$(penv); seeded && command rm -rf "$W/priv"
  E="DOTFILES_PRIVATE_REMOTE=git@github.com:someone/dotfiles-private.git GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.$W/nowhere.insteadOf GIT_CONFIG_VALUE_0=git@github.com:someone/"
  with_env "$E" priv clone >/dev/null 2>&1 && grep -qx "gh repo clone someone/dotfiles-private $W/priv" "$W/log" && [ -f "$W/priv/profiles/local.zsh" ]'
t "P2.5" "with gh not authenticated the fallback is not tried" '
  W=$(penv); E="DOTFILES_PRIVATE_REMOTE=git@github.com:someone/dotfiles-private.git GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.$W/nowhere.insteadOf GIT_CONFIG_VALUE_0=git@github.com:someone/ STUB_GH_AUTH=no"
  ! with_env "$E" priv clone >/dev/null 2>&1 && [ "$(grep -c "^gh repo clone" "$W/log")" -eq 0 ]'

#############################################################################
section "P3 -- link: every private file gets a symlink at its public path"
#############################################################################
# second_mac: a fresh public repo + home that clones the seeded private repo.
second_mac() {
  local w2; w2=$(sandbox)
  mkdir -p "$w2/home" "$w2/pub"
  git init -q -b main "$w2/pub"
  printf '%s' "$w2"
}
t "P3.1" "on a fresh Mac, link puts a symlink at each public path" '
  W=$(penv); seeded; W1=$W; W=$(second_mac)
  with_env "DOTFILES_PRIVATE_REMOTE=$W1/remote.git DOTFILES_PRIVATE_DIR=$W/priv" priv clone >/dev/null 2>&1 &&
  with_env "DOTFILES_PRIVATE_DIR=$W/priv" priv link >/dev/null 2>&1 &&
  [ -L "$W/pub/profiles/local.zsh" ] && [ "$(readlink "$W/pub/claude/work.local.list")" = "$W/priv/claude/work.local.list" ] &&
  [ "$(command cat "$W/pub/macos/local.sh")" = "DOTFILES_LOCALE=en_GB" ]'
t "P3.2" "link is idempotent: a second run changes nothing and makes no backup" '
  W=$(penv); seeded; priv link >/dev/null 2>&1; a=$(ls -l "$W/pub/profiles/local.zsh")
  priv link >/dev/null 2>&1 && [ "$(ls -l "$W/pub/profiles/local.zsh")" = "$a" ] &&
  [ "$(find "$W/pub" -name "*.bak.*" | wc -l | tr -d " ")" -eq 0 ]'
t "P3.3" "a different real file in the way is moved aside to <name>.bak.<epoch>, and link says so" '
  W=$(penv); seeded; command rm -f "$W/pub/Brewfile.local"; printf "brew \"other\"\n" >"$W/pub/Brewfile.local"
  out=$(priv link 2>&1)
  [ -L "$W/pub/Brewfile.local" ] && bak=$(find "$W/pub" -maxdepth 1 -name "Brewfile.local.bak.*") && [ -n "$bak" ] &&
  [ "$(command cat "$bak")" = "brew \"other\"" ] && printf "%s\n" "$out" | grep -q "Brewfile.local.bak"'
t "P3.4" "an identical real file is replaced by the link without clutter" '
  W=$(penv); seeded; command rm -f "$W/pub/Brewfile.local"; printf "brew \"wget\"\n" >"$W/pub/Brewfile.local"
  priv link >/dev/null 2>&1 && [ -L "$W/pub/Brewfile.local" ] && [ "$(find "$W/pub" -name "*.bak.*" | wc -l | tr -d " ")" -eq 0 ]'
t "P3.5" "a wrong symlink is moved aside too, never silently followed" '
  W=$(penv); seeded; command rm -f "$W/pub/Brewfile.local"; ln -s /etc/hosts "$W/pub/Brewfile.local"
  priv link >/dev/null 2>&1 && [ "$(readlink "$W/pub/Brewfile.local")" = "$W/priv/Brewfile.local" ] &&
  [ "$(find "$W/pub" -maxdepth 1 -name "Brewfile.local.bak.*" | wc -l | tr -d " ")" -eq 1 ]'
t "P3.6" "secrets.age and files outside the mapping never become links in the public repo" '
  W=$(penv); seeded; printf "x" >"$W/priv/secrets.age"; mkdir -p "$W/priv/evil"; printf "x" >"$W/priv/evil/run.sh"; printf "x" >"$W/priv/README.md"
  priv link >/dev/null 2>&1 && [ ! -e "$W/pub/secrets.age" ] && [ ! -e "$W/pub/evil" ] && [ ! -e "$W/pub/README.md" ]'
t "P3.7" "ssh/config is linked as ~/.ssh/config.private" '
  W=$(penv); seeded; mkdir -p "$W/priv/ssh"; printf "Host box\n  HostName box.example.invalid\n" >"$W/priv/ssh/config"
  priv link >/dev/null 2>&1 && [ "$(readlink "$W/home/.ssh/config.private")" = "$W/priv/ssh/config" ] && [ ! -e "$W/pub/ssh" ]'
t "P3.8" "the managed ~/.ssh/config gets Include ~/.ssh/config.private exactly once, before any Host" '
  W=$(penv); seeded; mkdir -p "$W/priv/ssh" "$W/home/.ssh"; printf "Host box\n" >"$W/priv/ssh/config"
  printf "Host *\n  UseKeychain yes\n" >"$W/home/.ssh/config"
  priv link >/dev/null 2>&1; priv link >/dev/null 2>&1
  [ "$(grep -c "^Include ~/.ssh/config.private$" "$W/home/.ssh/config")" -eq 1 ] &&
  [ "$(head -1 "$W/home/.ssh/config")" = "Include ~/.ssh/config.private" ] &&
  grep -q "UseKeychain yes" "$W/home/.ssh/config"'
t "P3.9" "no private ssh/config: ~/.ssh/config is not touched" '
  W=$(penv); seeded; priv link >/dev/null 2>&1; [ ! -e "$W/home/.ssh/config" ]'
t "P3.10" "link with no private repo says what to run and fails" \
  'W=$(penv); refused "dotfiles private" link'

#############################################################################
section "P4 -- status"
#############################################################################
t "P4.1" "a clean, pushed private repo reports up to date" \
  'W=$(penv); seeded; priv link >/dev/null 2>&1; said "up to date" status'
t "P4.2" "an unpushed commit is reported as ahead" \
  'W=$(penv); seeded; printf "n\n" >"$W/priv/Brewfile.local"; git -C "$W/priv" commit -qam more; said "ahead" status'
t "P4.3" "a commit on the remote is reported as behind" '
  W=$(penv); seeded; c=$(sandbox); git clone -q "$W/remote.git" "$c/x"
  ( cd "$c/x" && printf "n\n" >>Brewfile.local && git -c user.name=t -c user.email=t@example.invalid commit -qam up && git push -q origin main )
  said "behind" status'
t "P4.4" "uncommitted changes in the private repo are reported" \
  'W=$(penv); seeded; printf "n\n" >>"$W/priv/Brewfile.local"; said "uncommitted" status'
t "P4.5" "a gitignored file in the public repo that is a real file, not a link, is reported" '
  W=$(penv); seeded; priv link >/dev/null 2>&1; command rm -f "$W/pub/macos/local.sh"; printf "x\n" >"$W/pub/macos/local.sh"
  said "macos/local.sh" status && said "will not reach" status'
t "P4.6" "with every mapped file linked there are no local-only warnings" '
  W=$(penv); seeded; priv link >/dev/null 2>&1; [ "$(priv status 2>&1 | grep -c "will not reach")" -eq 0 ]'
t "P4.7" "status with no private repo says so and fails" \
  'W=$(penv); refused "dotfiles private" status'

#############################################################################
section "P5 -- install and the ssh helper"
#############################################################################
t "P5.1" "install runs clone then link" '
  W=$(penv); seeded; command rm -rf "$W/priv" "$W/pub/profiles/local.zsh"
  priv install >/dev/null 2>&1 && [ -f "$W/priv/profiles/local.zsh" ] && [ -L "$W/pub/profiles/local.zsh" ]'
t "P5.2" "install with a clone that cannot succeed yet is a skip (exit 0), says what to do, and links nothing" '
  W=$(penv); E="DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no"
  out=$(with_env "$E" priv install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "gh repo create" && printf "%s\n" "$out" | grep -q "SSH key" &&
  printf "%s\n" "$out" | grep -qi "skipp" && [ ! -L "$W/pub/profiles/local.zsh" ]'
t "P5.2b" "install with a real error (a non-git directory in the way) still fails" '
  W=$(penv); mkdir -p "$W/priv"; printf "x\n" >"$W/priv/f"; ! priv install >/dev/null 2>&1'
t "P5.2c" "clone on its own still returns non-zero when the repo is not there yet" '
  W=$(penv); with_env "DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no" priv clone >/dev/null 2>&1; [ "$?" -ne 0 ]'
# A stub git in front of the real one records the ssh command git was given.
_gitspy() { stub "$W/bin" git 'echo "GSC=${GIT_SSH_COMMAND:-}" >>"$STUB_LOG"; exec /usr/bin/git "$@"'; }
t "P2.6" "clone gets a non-interactive ssh that accepts a first-seen host key" '
  W=$(penv); seeded; _gitspy; : >"$W/log"; command rm -r -f "$W/priv"; priv clone >/dev/null 2>&1
  grep -q "^GSC=.*StrictHostKeyChecking=accept-new.*BatchMode=yes" "$W/log"'
t "P2.7" "status fetches with the same ssh options" '
  W=$(penv); seeded; _gitspy; : >"$W/log"; priv status >/dev/null 2>&1
  grep -q "^GSC=.*StrictHostKeyChecking=accept-new.*BatchMode=yes" "$W/log"'
t "P2.8" "a GIT_SSH_COMMAND the owner already set is respected" '
  W=$(penv); seeded; _gitspy; : >"$W/log"; with_env "GIT_SSH_COMMAND=myssh" priv status >/dev/null 2>&1
  grep -q "^GSC=myssh$" "$W/log"'
t "P5.3" "an unknown subcommand is a usage error" \
  'W=$(penv); refused "Usage" frobnicate'
t "P5.4" "the ssh helper keeps the public Host * defaults in scripts/lib/ssh.sh" \
  'grep -q "UseKeychain yes" scripts/lib/ssh.sh && grep -q "dotfiles_ensure_ssh_include" scripts/lib/ssh.sh'

finish

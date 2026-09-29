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
# _gitfail <stderr text>: a git in front of the real one whose `clone` of the
# private remote fails with that text (exit 128), as GitHub or ssh would.
# Everything else (and a clone of any other URL, such as gh's) goes to real git.
_gitfail() {
  printf '%s\n' "$1" >"$W/giterr"
  stub "$W/bin" git "case \"\$1\" in clone) for a in \"\$@\"; do [ \"\$a\" = \"\$DOTFILES_PRIVATE_REMOTE\" ] && { command cat \"$W/giterr\" >&2; exit 128; }; done ;; esac; exec /usr/bin/git \"\$@\""
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
t "P2.3" "a clone of a repo that is not there yet returns non-zero and says what to set up" '
  W=$(penv); _gitfail "ERROR: Repository not found."; E="DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no"
  with_env "$E" refused "gh auth login" clone && [ "$(with_env "$E" priv clone 2>&1 | grep -c "SSH key")" -ge 1 ] && [ ! -e "$W/priv/.git" ]'
t "P2.4" "with gh authenticated, a git clone that says Repository not found falls back to gh repo clone" '
  W=$(penv); seeded && command rm -rf "$W/priv"; _gitfail "ERROR: Repository not found."
  E="DOTFILES_PRIVATE_REMOTE=git@github.com:someone/dotfiles-private.git"
  with_env "$E" priv clone >/dev/null 2>&1 && grep -qx "gh repo clone someone/dotfiles-private $W/priv" "$W/log" && [ -f "$W/priv/profiles/local.zsh" ]'
t "P2.5" "with gh not authenticated the fallback is not tried" '
  W=$(penv); _gitfail "ERROR: Repository not found."; E="DOTFILES_PRIVATE_REMOTE=git@github.com:someone/dotfiles-private.git STUB_GH_AUTH=no"
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
  'W=$(penv); seeded; printf "n\n" >"$W/priv/Brewfile.local"; git -C "$W/priv" commit -q --no-verify -am more; said "ahead" status'
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
  W=$(penv); _gitfail "ERROR: Repository not found."; E="DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no"
  out=$(with_env "$E" priv install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "gh repo create" && printf "%s\n" "$out" | grep -q "SSH key" &&
  printf "%s\n" "$out" | grep -qi "skipp" && [ ! -L "$W/pub/profiles/local.zsh" ]'
t "P5.2b" "install with a real error (a non-git directory in the way) still fails" '
  W=$(penv); mkdir -p "$W/priv"; printf "x\n" >"$W/priv/f"; ! priv install >/dev/null 2>&1'
t "P5.2c" "clone on its own still returns non-zero when the repo is not there yet" '
  W=$(penv); _gitfail "ERROR: Repository not found."; with_env "DOTFILES_PRIVATE_REMOTE=$W/nowhere.git STUB_GH_AUTH=no" priv clone >/dev/null 2>&1; [ "$?" -ne 0 ]'
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

#############################################################################
section "P6 -- the secrets guard is the private repo's pre-commit hook (Task 12.1)"
#############################################################################
# guard_pub: give the sandbox public repo the guard, its libs and the real hook,
# so the private repo's hook runs the guard exactly as shipped.
guard_pub() {
  mkdir -p "$W/pub/bin" "$W/pub/scripts/lib" "$W/pub/.githooks" "$W/sec" "$W/state"
  cp "$ROOT_DIR/bin/dotfiles-jev" "$W/pub/bin/"
  cp "$ROOT_DIR"/scripts/lib/jev* "$W/pub/scripts/lib/"
  cp "$ROOT_DIR/.githooks/pre-commit" "$W/pub/.githooks/"
}
# pcommit <message>: commit what is staged in the private repo, so its hook runs.
pcommit() {
  env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_SECURITY_STUB_DIR="$W/sec" XDG_STATE_HOME="$W/state" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git -C "$W/priv" commit -q -m "$1"
}
PHOOK() { printf '%s/priv/.git/hooks/pre-commit' "$W"; }

t "P6.1" "init installs an executable pre-commit hook that runs the guard" '
  W=$(penv); guard_pub; priv init >/dev/null 2>&1
  [ -x "$(PHOOK)" ] && [ "$(grep -c "dotfiles-private-guard" "$(PHOOK)")" -ge 1 ] && [ "$(grep -c "guard-private" "$(PHOOK)")" -ge 1 ]'
t "P6.2" "a plaintext token in a staged file blocks the commit, and the token is never printed" '
  W=$(penv); guard_pub; seeded; tok="ghp_$(rand_chars 36 A-Za-z0-9)"
  printf "export GH_TOKEN=%s\n" "$tok" >>"$W/priv/profiles/local.zsh"; git -C "$W/priv" add -A
  out=$(pcommit "add token" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: profiles/local.zsh:")" -ge 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "$tok")" -eq 0 ] && [ "$(git -C "$W/priv" rev-list --count HEAD)" -eq 1 ]'
t "P6.3" "secrets.age is the one file allowed to hold secret-shaped text" '
  W=$(penv); guard_pub; seeded; tok="ghp_$(rand_chars 36 A-Za-z0-9)"
  printf "%s\n" "$tok" >"$W/priv/secrets.age"; git -C "$W/priv" add secrets.age
  [ -x "$(PHOOK)" ] && pcommit "add secrets.age" >/dev/null 2>&1 && [ "$(git -C "$W/priv" rev-list --count HEAD)" -eq 2 ]'
t "P6.4" "an ordinary change commits" '
  W=$(penv); guard_pub; seeded; printf "brew \"jq\"\n" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  [ -x "$(PHOOK)" ] && pcommit "add jq" >/dev/null 2>&1 && [ "$(git -C "$W/priv" rev-list --count HEAD)" -eq 2 ]'
t "P6.5" "a value of one of your own Keychain secrets blocks, and is never printed" '
  W=$(penv); guard_pub; seeded; cp "$ROOT_DIR/tests/fixtures/security-stub" "$W/bin/security"
  own="own-secret-$(rand_chars 14 A-Za-z0-9)"; printf "dotfiles.openai_api_key\t%s\n" "$own" >"$W/sec/login"
  mkdir -p "$W/priv/jev"; printf "openai_api_key\n" >"$W/priv/jev/secret-names.list"
  printf "# notes %s\n" "$own" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  out=$(pcommit "own secret" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "Brewfile.local:.*own Keychain secrets")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "$own")" -eq 0 ]'
t "P6.6" "the privacy checks are not run on the private repo: names, addresses and home paths may live there" '
  W=$(penv); guard_pub; seeded
  printf "Host box\n  HostName 192.168.%s.7\n# /%s/jdoe/notes\n" "$((RANDOM % 200 + 1))" "$(printf Users)" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  [ -x "$(PHOOK)" ] && pcommit "private facts" >/dev/null 2>&1 && [ "$(git -C "$W/priv" rev-list --count HEAD)" -eq 2 ]'
t "P6.7" "a guard that is missing blocks the commit (it never fails open) and says so" '
  W=$(penv); guard_pub; seeded; command rm -f "$W/pub/bin/dotfiles-jev"
  printf "brew \"jq\"\n" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  out=$(pcommit "no guard" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "secrets guard cannot run")" -eq 1 ]'
t "P6.8" "installing is idempotent: link and hook again change nothing and make no backup" '
  W=$(penv); guard_pub; seeded; [ -x "$(PHOOK)" ] && a=$(shasum "$(PHOOK)") &&
  priv link >/dev/null 2>&1 && out=$(priv hook 2>&1) && priv link >/dev/null 2>&1 && [ -z "$out" ] &&
  [ "$(shasum "$(PHOOK)")" = "$a" ] && [ "$(ls "$W/priv/.git/hooks" | grep -c "bak")" -eq 0 ]'
t "P6.9" "a different pre-commit hook is backed up (once), never overwritten silently" '
  W=$(penv); guard_pub; seeded; printf "#!/bin/sh\necho mine\n" >"$(PHOOK)"; chmod +x "$(PHOOK)"
  out=$(priv link 2>&1); priv link >/dev/null 2>&1
  bak=$(ls "$W/priv/.git/hooks" | grep "^pre-commit.bak\.")
  [ "$(printf "%s\n" "$bak" | grep -c .)" -eq 1 ] && [ "$(sed -n 2p "$W/priv/.git/hooks/$bak")" = "echo mine" ] &&
  [ "$(printf "%s\n" "$out" | grep -c "pre-commit.bak")" -eq 1 ] && [ "$(grep -c "dotfiles-private-guard" "$(PHOOK)")" -ge 1 ]'
t "P6.10" "clone and link install the hook too" '
  W=$(penv); guard_pub; seeded; command rm -rf "$W/priv"; priv clone >/dev/null 2>&1; a=; [ -x "$(PHOOK)" ] || a=x
  command rm -f "$(PHOOK)"; priv link >/dev/null 2>&1
  [ -z "$a" ] && [ -x "$(PHOOK)" ]'
t "P6.11" "the hook command with no private repo says what to run and fails" \
  'W=$(penv); refused "no private repo" hook'

t "P6.12" "a core.hooksPath (repo-local or global) means git ignores the hook: warn loudly, fail, install nowhere" '
  W=$(penv); guard_pub; seeded; command rm -f "$(PHOOK)"; git -C "$W/priv" config core.hooksPath "$W/foreign"
  out=$(priv hook 2>&1); rc=$?
  bad=; [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "core.hooksPath.*$W/foreign")" -ge 1 ] && [ "$(printf "%s\n" "$out" | grep -c "NOT active")" -ge 1 ] &&
  [ ! -e "$(PHOOK)" ] && [ ! -e "$W/foreign/pre-commit" ] || bad=1
  priv link >/dev/null 2>&1; l=$?
  git -C "$W/priv" config --unset core.hooksPath
  out2=$(with_env "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/elsewhere" priv hook 2>&1); rc2=$?
  [ -z "$bad" ] && [ "$l" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$(printf "%s\n" "$out2" | grep -c "NOT active")" -ge 1 ]'
t "P6.13" "without gitleaks the private guard says that layer is skipped; with it, no warning" '
  W=$(penv); guard_pub; seeded; printf "brew \"jq\"\n" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  out=$(pcommit "no gitleaks" 2>&1); rc=$?
  stub "$W/bin" gitleaks ":"; printf "brew \"fd\"\n" >>"$W/priv/Brewfile.local"; git -C "$W/priv" add -A
  out2=$(pcommit "with gitleaks" 2>&1); rc2=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "gitleaks is not installed")" -eq 1 ] && [ "$rc2" -eq 0 ] && [ "$(printf "%s\n" "$out2" | grep -c "gitleaks")" -eq 0 ]'

t "P6.14" "init still creates the repo when core.hooksPath disables the guard, but its status is non-zero and says so" '
  W=$(penv); out=$(with_env "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/elsewhere" priv init 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "NOT active")" -ge 1 ] && [ -f "$W/priv/profiles/local.zsh" ] && [ -L "$W/pub/profiles/local.zsh" ]'

#############################################################################
section "P7 -- clone failures: only 'not set up yet' is a skip (Task 12.4)"
#############################################################################
NF="ERROR: Repository not found."
t "P7.1" "Repository not found is a skip (exit 0) that shows git's own message" '
  W=$(penv); _gitfail "$NF"; out=$(with_env "STUB_GH_AUTH=no" priv install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "ERROR: Repository not found.")" -ge 1 ] && printf "%s\n" "$out" | grep -qi "skipp"'
t "P7.2" "Permission denied (publickey) is a skip too, with git's message" '
  W=$(penv); _gitfail "git@github.com: Permission denied (publickey)."; out=$(with_env "STUB_GH_AUTH=no" priv install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "Permission denied (publickey)")" -ge 1 ] && printf "%s\n" "$out" | grep -qi "skipp"'
t "P7.3" "a network failure fails loudly with git's message: not a skip, and gh is not tried" '
  W=$(penv); _gitfail "ssh: Could not resolve hostname github.com: nodename nor servname provided, or not known"
  out=$(priv install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "Could not resolve hostname")" -ge 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -ci "skipp\|not set up")" -eq 0 ] && [ "$(grep -c "^gh repo clone" "$W/log")" -eq 0 ]'
t "P7.4" "a changed host key fails loudly with git's message" '
  W=$(penv); _gitfail "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@"; out=$(priv install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "REMOTE HOST IDENTIFICATION HAS CHANGED")" -ge 1 ] && [ "$(printf "%s\n" "$out" | grep -ci "skipp")" -eq 0 ]'
t "P7.5" "clone alone: not set up is exit 3, anything else is exit 1" '
  W=$(penv); _gitfail "$NF"; with_env "STUB_GH_AUTH=no" priv clone >/dev/null 2>&1; a=$?
  _gitfail "fatal: unable to access: Connection timed out"; priv clone >/dev/null 2>&1; b=$?
  [ "$a" -eq 3 ] && [ "$b" -eq 1 ]'
t "P7.6" "a typo in the remote (a path that does not exist) fails loudly, not as a skip" '
  W=$(penv); out=$(with_env "DOTFILES_PRIVATE_REMOTE=$W/typo.git STUB_GH_AUTH=no" priv install 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -ci "skipp")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "typo.git")" -ge 1 ]'
t "P7.7" "a key that needs a passphrase is named: BatchMode cannot ask, so ssh-add is the fix" '
  W=$(penv); mkdir -p "$W/home/.ssh"; ssh-keygen -q -t ed25519 -N "pw-$RANDOM" -C t -f "$W/home/.ssh/id_test" >/dev/null 2>&1
  _gitfail "git@github.com: Permission denied (publickey)."; out=$(with_env "STUB_GH_AUTH=no" priv install 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "id_test.*passphrase")" -ge 1 ] && [ "$(printf "%s\n" "$out" | grep -c "ssh-add")" -ge 1 ]'
t "P7.8" "without a passphrase-protected key the passphrase hint is not shown" '
  W=$(penv); mkdir -p "$W/home/.ssh"; ssh-keygen -q -t ed25519 -N "" -C t -f "$W/home/.ssh/id_test" >/dev/null 2>&1
  _gitfail "git@github.com: Permission denied (publickey)."; out=$(with_env "STUB_GH_AUTH=no" priv install 2>&1)
  [ "$(printf "%s\n" "$out" | grep -ci "passphrase")" -eq 0 ]'
finish

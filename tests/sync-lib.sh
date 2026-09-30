# shellcheck shell=bash
#
# tests/sync-lib.sh -- shared fixtures for the tests/sync-*.sh suites (not a
# suite itself; run.sh skips it): the SYNC_ONLY filter, stub, the sandbox git
# identity, the public/private repo sandbox (senv), syn and the Jev/drift/vault
# helpers. Sourced after tests/lib.sh.
# shellcheck disable=SC2016,SC2329

# SYNC_ONLY="S V": run only the tests whose id starts with one of these
# (the git-heavy S tests are slow on a busy machine).
if [ -n "${SYNC_ONLY:-}" ]; then
  eval "$(declare -f t | sed '1s/^t /_t_real /')"
  t() { local p; for p in $SYNC_ONLY; do case "$1" in "$p"*) _t_real "$@"; return ;; esac; done; }
fi

# stub <bindir> <name> [body]: an executable that logs "<name> <argv>" to
# $STUB_LOG and then runs body.
stub() {
  mkdir -p "$1"
  { printf '#!/bin/bash\n'
    printf 'printf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n' "$2"
    printf '%s\n' "${3:-}"
  } >"$1/$2"
  chmod +x "$1/$2"
}


export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# _mkrepo <W> <name> <file:content>...: bare remote <name>.git, a checkout
# <name> with one commit holding the files, pushed with upstream set.
_mkrepo() {
  local w="$1" n="$2" f; shift 2
  git init -q --bare -b main "$w/$n.git" &&
  git clone -q "$w/$n.git" "$w/$n" 2>/dev/null || return 1
  for f in "$@"; do mkdir -p "$w/$n/$(dirname "${f%%:*}")"; printf '%s\n' "${f#*:}" >"$w/$n/${f%%:*}"; done
  git -C "$w/$n" checkout -q -b main 2>/dev/null
  git -C "$w/$n" add -A && git -C "$w/$n" commit -q -m init && git -C "$w/$n" push -q -u origin main 2>/dev/null
}
# senv: a sandbox with a public and a private repo (each with a bare remote), a
# HOME, stubs and package state. Prints the path.
senv() {
  local w; w=$(sandbox) || return 1
  mkdir -p "$w/home" "$w/bin" "$w/state"; : >"$w/log"
  _mkrepo "$w" pub "Brewfile:brew \"wget\"
cask \"iterm2\"
mas \"Xcode\", id: 497799835" "config/mise/config.toml:[tools]" "claude/rules.md:r" "packages/code.list:ms-python.python" "README.md:r" "runcom/.zshrc:z" || return 1
  _mkrepo "$w" priv "macos/local.sh:DOTFILES_LOCALE=en_GB" "Brewfile.local:brew \"fzf\"" || return 1
  cp "$w/priv/Brewfile.local" "$w/pub/Brewfile.local"
  local n
  for n in stow mise sudo osascript dotfiles-stub; do stub "$w/bin" "$n" ':'; done
  stub "$w/bin" mas 'case "$1" in list) cat "$STUB_STATE/mas" 2>/dev/null ;; esac'
  stub "$w/bin" code 'case "$1" in --list-extensions) cat "$STUB_STATE/vscode" 2>/dev/null ;; esac'
  stub "$w/bin" brew 'case "$*" in
  "leaves --installed-on-request") cat "$STUB_STATE/leaves" 2>/dev/null ;;
  "list --cask -1") cat "$STUB_STATE/casks" 2>/dev/null ;;
  "desc "*) n="${!#}"; printf "%s: Description of %s\n" "$n" "$n" ;;
  "uses --installed "*) cat "$STUB_STATE/uses-$3" 2>/dev/null ;;
  "bundle check"*) [ -f "$STUB_STATE/unsatisfied" ] && exit 1 ;;
esac
exit 0'
  printf 'wget\nfzf\n' >"$w/state/leaves"; printf 'iterm2\n' >"$w/state/casks"
  printf '497799835  Xcode  (16.0)\n' >"$w/state/mas"; printf 'ms-python.python\n' >"$w/state/vscode"
  printf '%s' "$w"
}
# push_change <W> <pub|priv> <file> <content>: a commit from "the other Mac".
push_change() {
  local w="$1" n="$2" c
  c=$(sandbox); git clone -q "$w/$n.git" "$c/x" 2>/dev/null
  mkdir -p "$c/x/$(dirname "$3")"; printf '%s\n' "$4" >"$c/x/$3"
  git -C "$c/x" add -A && git -C "$c/x" commit -q -m change && git -C "$c/x" push -q origin main 2>/dev/null
}
# syn <args>: dotfiles-sync against the sandbox in $W; $SYNENV adds VAR=val
# pairs (no spaces); stdin is closed, so an unanswered confirm is a "no".
syn() {
  # shellcheck disable=SC2086
  ${SYNWRAP:-} env -i HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" DOTFILES_DIR="$W/pub" DOTFILES_PRIVATE_DIR="$W/priv" \
    DOTFILES_BIN="$W/bin/dotfiles-stub" XDG_CONFIG_HOME="$W/home/.config" STUB_LOG="$W/log" STUB_STATE="$W/state" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid DOTFILES_JEV=off TYPESAFE_API_KEY=testkey DOTFILES_SETAPP_APPS_DIR="$W/setapp" \
    ${SYNENV:-} bash "$ROOT_DIR/bin/dotfiles-sync" "$@" <"${SYNIN:-/dev/null}"
}
sy_env() { local SYNENV="$1"; shift; "$@"; }
_calls() { grep -c -- "$1" "$W/log"; }
_head() { git -C "$W/$1" rev-parse HEAD; }
_remote() { git -C "$W/$1.git" rev-parse main; }


# Three changes that each call for an action.
_actions() { # _actions <W>: mise, Brewfile and claude/ change on the remote
  push_change "$1" pub config/mise/config.toml "[tools]
node = \"1\""
  push_change "$1" pub Brewfile "brew \"wget\"
brew \"jq\""
  push_change "$1" pub claude/rules.md "r2"
  : >"$1/state/unsatisfied"
}

# vault_of <W>: the sandbox vault's Claude-Sessions folder. jevstub <W> <exit> [output line]: a dotfiles-jev that
# logs its argv and JEV_SCHEDULED, prints the line and exits with <exit>.
vault_of() { mkdir -p "$1/home/Vault/Claude-Sessions"; printf '%s' "$1/home/Vault/Claude-Sessions"; }
jevstub() {
  stub "$1/bin" dotfiles-jev-stub 'echo "JEV_SCHEDULED=${JEV_SCHEDULED:-}" >>"$STUB_LOG"; [ -n "'"${3:-}"'" ] && printf "%s\n" "'"${3:-}"'"; exit '"$2"
}
JEVSTUB_ENV() { printf 'DOTFILES_JEV_BIN=%s/bin/dotfiles-jev-stub' "$1"; }

# dstub <W> [mode]: a private-repo-independent jev.conf (drift=<mode>, default
# on), a dotfiles-jev that records its stdin (the facts) per kind and prints
# $STUB_STATE/suggest-<kind>, a dotfiles-baseline that prints
# $STUB_STATE/changed, and a defaults that only answers read-type.
dstub() {
  printf 'drift=%s\n' "${2:-on}" >"$1/jev.conf"
  stub "$1/bin" dotfiles-jev-stub 'case "$1" in drift) echo "JEV_SCHEDULED=${JEV_SCHEDULED:-} JEV_TIMEOUT=${JEV_TIMEOUT:-}" >>"$STUB_LOG"; cat >"$STUB_STATE/facts-$2"; cat "$STUB_STATE/suggest-$2" 2>/dev/null ;; esac; exit ${JEVSTUB_RC:-0}'
  stub "$1/bin" dotfiles-baseline-stub 'cat "$STUB_STATE/changed" 2>/dev/null'
  stub "$1/bin" defaults 'case "$1" in read-type) printf "Type is %s\n" "$(cat "$STUB_STATE/deftype" 2>/dev/null || echo boolean)" ;; esac'
}
# dsyn <args>: syn with Jev switched on and pointed at the stubs. $DX adds VAR=val.
dsyn() {
  local ans=""
  # DXY=1 answers "y" to every strict prompt, DXA=1 uses the answers already in
  # $W/yes. The strict prompt ignores DOTFILES_YES; a test has no terminal, so
  # the harness marks its sandbox (see tests/lib.sh) and names an answers file
  # inside it.
  local xa="${DXA:-}"
  if [ -n "${DXY:-}" ]; then printf 'y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n' >"$W/yes"; xa=1; fi
  [ -n "$xa" ] && ans="DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_STRICT_ANSWERS=$W/yes"
  local SYNENV="$ans DOTFILES_JEV= DOTFILES_JEV_CONFIG=$W/jev.conf DOTFILES_JEV_BIN=$W/bin/dotfiles-jev-stub DOTFILES_BASELINE_BIN=$W/bin/dotfiles-baseline-stub ${DX:-}"
  syn "$@"
}
_suggest() { printf 'SUGGEST\t%s\t%s\t0.9\t0.9\n' "$2" "$3" >>"$W/state/suggest-$1"; }
_facts() { command cat "$W/state/facts-$1" 2>/dev/null; }
_lines() { command cat "$W/$1" 2>/dev/null; }
_undeclared() { printf 'wget\nfzf\njq\n' >"$W/state/leaves"; }

# estub <W> [mode]: jev.conf (apps=<mode>, default on), a dotfiles-jev that
# records the apps facts and prints $STUB_STATE/suggest-apps, and a
# dotfiles-apps whose `candidates` prints $STUB_STATE/apps-candidates.
estub() {
  printf 'apps=%s\n' "${2:-on}" >"$1/jev.conf"
  stub "$1/bin" dotfiles-jev-stub 'case "$1" in
  apps) echo "JEV_SCHEDULED=${JEV_SCHEDULED:-} JEV_TIMEOUT=${JEV_TIMEOUT:-}" >>"$STUB_LOG"; cat >"$STUB_STATE/facts-apps"; cat "$STUB_STATE/suggest-apps" 2>/dev/null; exit ${JEVAPPS_RC:-0} ;;
  drift) cat >/dev/null; exit ${JEVSTUB_RC:-0} ;;
esac'
  stub "$1/bin" dotfiles-apps-stub 'case "$1" in candidates) echo "DECLINED=${DOTFILES_APPS_DECLINED:-}" >>"$STUB_LOG"; cat "$STUB_STATE/apps-candidates" 2>/dev/null ;; esac'
  printf 'gamma\tpaths=2 (Library/Application Support/Gamma); build=direct; sandbox container=no; process=GammaExec\ndelta\tpaths=1 (Library/Preferences/com.example.delta.plist); build=Setapp; sandbox container=no\n' >"$1/state/apps-candidates"
}
# esyn <args>: syn with Jev and the app stubs. EA="y n" answers the strict prompts in order.
esyn() {
  local ans=""
  # shellcheck disable=SC2086
  if [ -n "${EA:-}" ]; then printf '%s\n' $EA >"$W/yes"; ans="DOTFILES_STRICT_ANSWERS=$W/yes"; fi
  local SYNENV="$ans DOTFILES_TEST_SANDBOX=$DOTFILES_TEST_SANDBOX DOTFILES_JEV= DOTFILES_JEV_CONFIG=$W/jev.conf DOTFILES_JEV_BIN=$W/bin/dotfiles-jev-stub DOTFILES_APPS_BIN=$W/bin/dotfiles-apps-stub DOTFILES_BASELINE_BIN=$W/bin/dotfiles-baseline-stub ${DX:-}"
  syn "$@"
}
_asuggest() { printf 'SUGGEST\t%s\t%s\t0.9\t0.9\n' "$1" "$2" >>"$W/state/suggest-apps"; }
DECL() { printf '%s/priv/jev/apps-declined.list' "$W"; }

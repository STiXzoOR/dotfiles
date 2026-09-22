#!/usr/bin/env bash
#
# tests/mise.sh -- wave 2 (mise) regression tests.
#
# The migration replaces fnm with mise as the one manager for Node, Python,
# pnpm/yarn/uv and every npm-installed CLI. What these assertions protect is
# not "mise is installed" but the three properties that make the migration
# safe to land on a machine with live shells: the tracked config keeps mise
# from installing anything behind your back, the shims reach non-interactive
# hooks, and a shell that starts before mise has any tools still finds node.
#
# Assertions are single-quoted strings handed to eval inside t(), so they must
# NOT expand where they are written. SC2016 flags exactly that, by design.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "M1 -- global mise config"
#############################################################################

# Skipped rather than failed where mise is absent: CI installs shellcheck,
# coreutils and gitleaks only, and the remaining M1 assertions are all
# textual, so they still pin the file's contents there.
t "M1.1" "config exists and is TOML mise accepts" \
  '[ -f config/mise/config.toml ] && { ! command -v mise >/dev/null 2>&1 || {
     MISE_CONFIG_DIR="$ROOT_DIR/config/mise" \
     MISE_GLOBAL_CONFIG_FILE="$ROOT_DIR/config/mise/config.toml" \
       mise config ls >/dev/null 2>&1
   }; }'

t "M1.2" "idiomatic node version files enabled" \
  'grep -q "idiomatic_version_file_enable_tools = \[\"node\"\]" config/mise/config.toml'

t "M1.3" "no auto install in agent shells" \
  'grep -q "not_found_auto_install = false" config/mise/config.toml'

t "M1.4" "lockfile, paranoid, release age, quiet set" \
  '_all=1
   for k in "lockfile = true" "paranoid = true" "minimum_release_age = " "quiet = true"; do
     grep -q "$k" config/mise/config.toml || _all=0
   done
   [ "$_all" = 1 ]'

t "M1.5" "node pinned to major 24, corepack off, gpg on" \
  'grep -qE "^node *= *\"24\"" config/mise/config.toml &&
   grep -q "corepack = false" config/mise/config.toml &&
   grep -q "gpg_verify = true" config/mise/config.toml'

t "M1.6" "every npm global from the reconciled list is declared" \
  '_all=1
   for p in @tobilu/qmd @openai/codex @biomejs/biome typescript; do
     grep -q "\"npm:$p\"" config/mise/config.toml || _all=0
   done
   [ "$_all" = 1 ]'

t "M1.7" "native-build tools declare allow_builds" \
  '_all=1
   for p in @tobilu/qmd sharp; do
     _line=$(grep -E "\"npm:$p\" *=" config/mise/config.toml)
     case "$_line" in *allow_builds*) ;; *) _all=0 ;; esac
   done
   [ "$_all" = 1 ]'

t "M1.8" "no asdf/vfox/ubi backends" \
  '! grep -qE "\"(asdf|vfox|ubi):" config/mise/config.toml'

t "M1.9" "pnpm, yarn and uv are tools, not corepack" \
  'grep -qE "^pnpm *=" config/mise/config.toml &&
   grep -qE "^yarn *=" config/mise/config.toml &&
   grep -qE "^uv *=" config/mise/config.toml'

#############################################################################
section "M2 -- shims at login, fnm fallback, opt-in activation"
#############################################################################

# A login+interactive zsh whose $HOME is a throwaway directory, built the way
# tests/shell.sh builds its own: runcom/ copied in as $ZDOTDIR, and
# $HOME/.dotfiles assembled from symlinks to the repo's directories, with
# profiles/ rebuilt from default.zsh alone so the user's private profile --
# which reads the keychain and the network -- is never sourced.
#
# The fnm arms below drive a stub, never the installed fnm. `fnm env` resolves
# its multishell directory from the real account, not from $HOME, so invoking
# it here would write under the user's own ~/.local/runtime however carefully
# the sandbox is built -- and the suite has to be side-effect free.
_mise_sandbox() { # _mise_sandbox [--with-shims]
  local h d s
  h=$(sandbox) || return 1
  mkdir -p "$h/.cache" "$h/.dotfiles/profiles" "$h/.local/bin" "$h/.stubs" || return 1
  if [ "${1:-}" = --with-shims ]; then
    mkdir -p "$h/.local/share/mise/shims" || return 1
  fi
  cp runcom/.profile runcom/.zprofile runcom/.zshrc runcom/.zlogin runcom/.zpreztorc "$h/" || return 1
  for d in modules system completions bin config; do
    [ -e "$ROOT_DIR/$d" ] && ln -s "$ROOT_DIR/$d" "$h/.dotfiles/$d"
  done
  cp profiles/default.zsh "$h/.dotfiles/profiles/" || return 1
  printf 'export PATH="$HOME/.stubs:$PATH"\n' > "$h/.local/bin/env"
  for s in ssh-add ssh-agent; do
    printf '#!/bin/sh\nexit 0\n' > "$h/.stubs/$s"
    chmod +x "$h/.stubs/$s"
  done
  printf '%s' "$h"
}

# Run zsh code in a prepared sandbox. stderr is dropped: prezto warms its
# caches on a first run and says so.
#
# PATH is rebuilt from the system directories rather than inherited. The shell
# running this suite already has a fnm multishell on its PATH and FNM_* in its
# environment, and inheriting either makes the two fallback arms below answer
# about the parent shell instead of about the sandbox -- M2.2 passes without
# system/.fnm ever being sourced, and M2.3 cannot pass at all. system/.path
# prepends the Homebrew prefix itself, so the real fnm and mise are still
# found from this reduced PATH.
_mise_zshrun() { # _mise_zshrun <home> <zsh code>
  env -u LC_ALL -u FNM_MULTISHELL_PATH -u FNM_DIR -u FNM_ARCH \
    -u MISE_SHELL -u __MISE_DIFF -u __MISE_ORIG_PATH \
    HOME="$1" ZDOTDIR="$1" XDG_CACHE_HOME="$1/.cache" \
    PATH="$1/.stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
    zsh -l -i -c "$2" 2>/dev/null
}

# A stub fnm that the login path cannot shadow. system/.path prepends
# $HOMEBREW_PREFIX/bin and then, further down the file, $HOME/.local/bin; each
# prepend goes in front of the last, so $HOME/.local/bin ends up ahead of the
# Homebrew prefix. That is the one place a stub beats the installed fnm at the
# moment system/.fnm is sourced.
_fnm_stub() { # _fnm_stub <sandbox home>
  printf '#!/bin/sh\necho "export FNM_PROBE=1"\n' > "$1/.local/bin/fnm" &&
    chmod +x "$1/.local/bin/fnm"
}

# 1-based position of the first $path entry matching <pattern>, else 0.
# Deliberately not a `grep -n | head` pipeline: the reader exiting first kills
# the writer, and under pipefail that reads as a failure (tests/lib.sh header).
_path_pos() { # _path_pos <pattern> <login-shell $path output>
  printf '%s\n' "$2" | awk -v p="$1" 'index($0, p) && !n { n = NR } END { print n + 0 }'
}

t "M2.1" "a login shell puts the mise shims at the front of PATH" \
  '_W=$(_mise_sandbox --with-shims) &&
   _P=$(_mise_zshrun "$_W" "print -l \$path") &&
   [ "$(_path_pos mise/shims "$_P")" -ge 1 ] &&
   [ "$(_path_pos mise/shims "$_P")" -le 3 ]'

t "M2.2" "with no shims directory the fnm fallback still runs" \
  '_W=$(_mise_sandbox) && _fnm_stub "$_W" &&
   [ ! -d "$_W/.local/share/mise/shims" ] &&
   [ "$(_mise_zshrun "$_W" "echo \$FNM_PROBE")" = 1 ]'

t "M2.3" "once the shims exist the fnm fragment stands down" \
  '_W=$(_mise_sandbox --with-shims) && _fnm_stub "$_W" &&
   [ -z "$(_mise_zshrun "$_W" "echo \$FNM_PROBE")" ]'

# code_of, not cat: system/.mise explains in a comment that it deliberately
# does not activate, and the assertion is about what the login path runs.
t "M2.4" "the shims cost nothing: mise activate is never in the login path" \
  '[ -f system/.mise ] &&
   [ "$(code_of runcom/.profile runcom/.zprofile system/.mise | grep -c "mise activate")" -eq 0 ]'

# The instant-prompt block this used to be ordered against went with
# Powerlevel10k, and a _first_line of a missing pattern is 0, so keeping that
# half would pass on nothing.
t "M2.5" "activation is opt-in" \
  '[ "$(code_of runcom/.zshrc | grep -c "DOTFILES_MISE_ACTIVATE:-0")" -eq 1 ]'

t "M2.6" "the index hook reaches qmd through the shims on a minimal PATH" \
  '_W=$(sandbox) &&
   mkdir -p "$_W/.local/share/mise/shims" && {
     printf "#!/bin/sh\necho qmd-ok\n" > "$_W/.local/share/mise/shims/qmd"
     chmod +x "$_W/.local/share/mise/shims/qmd"
     sed -n "/^# --- tool resolution/,/^# --- end tool resolution/p" \
       claude/hooks/index-sessions.sh > "$_W/block.sh"
     [ -s "$_W/block.sh" ] &&
     [ "$(env -i HOME="$_W" PATH=/usr/bin:/bin bash -c \
            ". \"$_W/block.sh\"; command -v qmd")" = "$_W/.local/share/mise/shims/qmd" ]
   }'

t "M2.7" "husky hooks resolve node through the shims, not a fnm multishell" \
  'grep -q "mise/shims" config/husky/init.sh &&
   [ "$(grep -c "fnm env" config/husky/init.sh)" -eq 0 ]'

# Matched on the brace-expansion members, not on ".mise"/".fnm": the loader
# spells them `.{env,...,mise,...}` and `.{alias,fnm,...}`, so a dotted pattern
# hits only the prose above the loops and the ordering would hold whatever the
# loops did.
t "M2.8" "the loader reaches .mise before .fnm" \
  '_m=$(_first_line ,mise, runcom/.profile)
   _f=$(_first_line ,fnm, runcom/.profile)
   [ "$_m" -gt 0 ] && [ "$_f" -gt 0 ] && [ "$_m" -lt "$_f" ]'

t "M2.9" "the fnm fragment is guarded on the shims directory" \
  'grep -q "local/share/mise/shims" system/.fnm'

t "M2.10" "the hook keeps its read-only promise: no fnm env on the dry-run path" \
  '_W=$(sandbox) && {
     sed -n "/^# --- tool resolution/,/^# --- end tool resolution/p" \
       claude/hooks/index-sessions.sh > "$_W/block.sh"
     printf "#!/bin/sh\nmkdir -p \"$_W/fnm-ran\"\necho :\n" > "$_W/fnm"
     chmod +x "$_W/fnm"
     [ -s "$_W/block.sh" ] &&
     env -i HOME="$_W" CLAUDE_HOOK_DRY_RUN=1 PATH="$_W:/usr/bin:/bin" bash -c \
       ". \"$_W/block.sh\"" >/dev/null 2>&1 &&
     [ ! -d "$_W/fnm-ran" ]
   }'

#############################################################################
section "M3 -- installer, doctor, profiler and docs"
#############################################################################

t "M3.1" "require_mise replaces the fnm and npm requirers" \
  '[ "$(code_of scripts/requirers.sh | grep -cE "require_fnm|source_fnm|require_npm")" -eq 0 ] &&
   grep -q "^function require_mise" scripts/requirers.sh &&
   grep -q "^function source_mise" scripts/requirers.sh'

t "M3.2" "install --node installs mise and then the declared tools" \
  '_b=$(code_of bin/dotfiles | sed -n "/^sub_install_node()/,/^}/p")
   printf "%s" "$_b" | grep -q "require_mise" &&
   printf "%s" "$_b" | grep -q "mise install"'

t "M3.3" "install --packages no longer loops over npm.list" \
  '[ "$(code_of bin/dotfiles | grep -c "npm.list")" -eq 0 ]'

t "M3.4" "packages/npm.list is gone" \
  '[ ! -e packages/npm.list ]'

t "M3.5" "doctor reports on mise" \
  'code_of bin/dotfiles-doctor | grep -q "mise"'

# Not "the word fnm never appears": it has to. fnm stays installed behind the
# guard in system/.fnm until the user removes it, so honest docs name it, say
# it is the fallback, and say which file holds it. What must be gone is the
# instruction to reach for it -- the two requirer helpers and the deleted list.
t "M3.6" "the docs point at mise, not at the fnm helpers or the deleted list" \
  '[ "$(grep -cE "require_fnm|source_fnm|require_npm|packages/npm\.list" \
         AGENTS.md docs/agents/packages.md docs/agents/shell-config.md \
        | awk -F: "{ s += \$NF } END { print s + 0 }")" -eq 0 ] &&
   grep -q mise AGENTS.md &&
   grep -q mise docs/agents/packages.md &&
   grep -q mise docs/agents/shell-config.md'

# The multishell pruner is the one exception, and it keeps its call site: fnm
# is still installed until the user removes it, and ~/.local/runtime collects
# a directory per login shell in the meantime. A pruner nothing calls is dead
# code, so the helper and the one line that runs it are both allowed.
t "M3.7" "no fnm left in the CLI except the multishell pruner" \
  '[ "$(code_of bin/dotfiles bin/dotfiles-doctor bin/dotfiles-setup bin/dotfiles-test \
         bin/dotfiles-profiler scripts/requirers.sh |
        grep -i fnm | grep -vc prune_fnm_multishells)" -eq 0 ]'

# sub_update_system, not sub_update: the first updates the machine (macOS,
# brew, mas, and now mise), the second commits and pushes this repo.
t "M3.8" "update drives mise rather than a global npm install" \
  '_b=$(code_of bin/dotfiles | sed -n "/^sub_update_system()/,/^}/p")
   [ -n "$_b" ] &&
   [ "$(printf "%s" "$_b" | grep -c "npm install npm -g")" -eq 0 ] &&
   printf "%s" "$_b" | grep -q "mise upgrade"'

t "M3.9" "install --node still reaches mise on a machine that has none" \
  '_b=$(code_of scripts/requirers.sh | sed -n "/^function require_mise/,/^}/p")
   printf "%s" "$_b" | grep -q "brew install mise"'

t "M3.10" "the bootstrap points at the mise config, not the deleted npm.list" \
  '[ "$(code_of scripts/install_claude.sh | grep -c "npm.list")" -eq 0 ]'

#############################################################################
section "M4 -- the first full install on a real machine"
#############################################################################

# Three packages were refused by mise's supply-chain gates on the first full
# install: fast-cli and xc-mcp for weekly downloads under the threshold, and
# resend-cli and xc-mcp for trust downgrades in a dependency. The repo owner
# reviewed and approved all three on 2026-09-22, so they are declared with the
# narrowest relaxation each one needs.
#
# What these assertions protect is not the decision -- that is the owner's --
# but its blast radius. A trust exemption written as a bare package name
# exempts every future version of that package silently, which is a different
# and much larger thing than exempting the one release that was reviewed.
t "M4.1" "every relaxed package is named in the decision block" \
  '_all=1
   for p in fast-cli resend-cli xc-mcp; do
     [ "$(grep -c "npm:$p" config/mise/config.toml)" -ge 2 ] || _all=0
   done
   [ "$_all" = 1 ]'

t "M4.2" "the three reviewed CLIs are declared as installable tools" \
  '_all=1
   for p in fast-cli resend-cli xc-mcp; do
     [ "$(grep -cE "^\"npm:$p\" *=" config/mise/config.toml)" -eq 1 ] || _all=0
   done
   [ "$_all" = 1 ]'

# Every exempted entry must carry an @version. Checked by counting the
# exemption list entries and the ones that pin a version, and requiring the
# two counts to agree -- so adding a bare name later fails here.
t "M4.3" "every trust exemption pins one exact version, never a bare name" \
  '_entries=$(code_of config/mise/config.toml |
     grep -oE "trust_policy_excludes = \[[^]]*\]" |
     grep -oE "\"[^\"]+\"" | grep -c .)
   _pinned=$(code_of config/mise/config.toml |
     grep -oE "trust_policy_excludes = \[[^]]*\]" |
     grep -oE "\"[^\"]+@[^\"]+\"" | grep -c .)
   [ "$_entries" -gt 0 ] && [ "$_entries" = "$_pinned" ]'

t "M4.3b" "the trust policy is never disabled wholesale" \
  '[ "$(code_of config/mise/config.toml | grep -cE "shell_out|paranoid *= *false")" -eq 0 ]'

# `mise doctor` exits non-zero on this machine for two things the repo chooses
# on purpose: it reports "not activated" because the login path uses shims
# rather than activation, and it recommends the vfox yarn backend, which
# config.toml disables along with every other plugin backend. A doctor check
# that reported the raw exit status would warn on every run, forever -- the
# same defect this repo already removed for caches nothing writes.
t "M4.4" "doctor does not report the by-design mise findings as problems" \
  '_b=$(code_of bin/dotfiles-doctor | sed -n "/^check_node()/,/^}/p")
   printf "%s" "$_b" | grep -q "not activated" &&
   printf "%s" "$_b" | grep -q "vfox"'

t "M4.5" "the lockfile is tracked beside the config" \
  '[ -f config/mise/mise.lock ]'

finish

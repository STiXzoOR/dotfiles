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
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "S1.1 — dotfiles unlink must restore, not destroy the backup"
#############################################################################

# Replays sub_unlink's loop against a sandbox. Pre-fix this deleted the backup
# copy and left the $HOME symlink in place.
unlink_sandbox() {
  local w h b d
  w=$(sandbox); h="$w/home"; b="$h/.dotfiles_backup/2026.01.01"; d="$w/df/runcom"
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

# S1.2 and S1.3b now live in tests/secrets.sh, where a throwaway keychain is
# available. S1.2 was a tautology -- `! grep "No secrets to export" ||
# grep "exit 1" <file>`, and the file holds 21 occurrences of `exit 1`, so the
# right-hand side always succeeded and the test passed whatever export did.
# S1.3b wrote to the real login keychain, here and on every CI runner.
t "S1.3a" "keychain_list no longer parses legacy dump-keychain" \
  '[ "$(code_of bin/dotfiles-secrets | grep -c "security dump-keychain")" -eq 0 ]'
t "S1.4"  "secrets are piped to the encrypter, not staged in a temp file" \
  '[ "$(code_of bin/dotfiles-secrets | grep -c "mktemp")" -eq 0 ]'

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
# matters is that GNU is probed FIRST, that the shared helper is used, or that
# the script has stopped calling stat altogether.
for f in bin/dotfiles-doctor bin/dotfiles-profiler claude/hooks/index-sessions.sh; do
  t "S2.1" "no unguarded GNU-only stat in $f" \
    'grep -qE "dotfiles_(mtime|filesize|age_days)" '"$f"' \
       || grep -qE "stat -c[^|]*\|\|[^|]*stat -f" '"$f"' \
       || [ "$(code_of '"$f"' | grep -cE "(^|[^[:alnum:]_])stat ")" -eq 0 ]'
done
t "S2.2" "doctor runs past Cache Status with GNU coreutils on PATH" '
  n=$(./bin/dotfiles-doctor 2>/dev/null | grep -c "━━━"); [ "$n" -ge 9 ]'

#############################################################################
section "S3 — fresh-install blockers"
#############################################################################

t "S3.1" "remote-install.sh probes git for real, not via 'type'" \
  'grep -qE "git --version|xcode-select -p" remote-install.sh'
# Was: read submodule.<name>.shallow back out of .gitmodules, which asserts
# that a config key exists and never that a clone is shallow. Now: every
# declared submodule carries the key, and the key is proven to do something.
t "S3.2a" "every declared submodule is marked shallow" '
  bad=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$(git config -f .gitmodules --get "submodule.$name.shallow")" = true ] || bad=1
  done < <(git config -f .gitmodules --name-only --get-regexp "^submodule\..*\.path$" \
             | sed -E "s/^submodule\.//; s/\.path$//")
  [ "$bad" -eq 0 ]'
t "S3.2b" "the shallow key actually produces a shallow clone" '
  W=$(sandbox); up="$W/up"; sup="$W/super"; dl="$W/down"
  mkdir -p "$up" "$sup"
  ( cd "$up" && git init -q . && git config user.email t@e.invalid && git config user.name T
    i=1; while [ $i -le 4 ]; do printf "c%s\n" "$i" > f.txt; git add f.txt; git commit -q -m "c$i"; i=$((i + 1)); done )
  ( cd "$sup" && git init -q . && git config user.email t@e.invalid && git config user.name T
    git -c protocol.file.allow=always submodule add -q "file://$up" dep
    git config -f .gitmodules submodule.dep.shallow true
    git add .gitmodules dep && git commit -q -m init )
  git -c protocol.file.allow=always clone -q "$sup" "$dl"
  ( cd "$dl" && git -c protocol.file.allow=always submodule update --init --recursive )
  [ "$(git -C "$dl/dep" rev-parse --is-shallow-repository)" = true ] \
    && [ "$(git -C "$dl/dep" rev-list --count HEAD)" -eq 1 ]'
t "S3.2c" "bootstrap clone is not unconditionally recursive" \
  '[ "$(code_of remote-install.sh | grep -c -- "--recurse-submodules")" -eq 0 ]'
t "S3.4" "Brewfile uses quicklook-video, not the renamed qlvideo" \
  '! grep -qE "^cask \"qlvideo\"" Brewfile'

#############################################################################
section "S4 — CI and lint coverage"
#############################################################################

t "S4.3a" "CI lints scripts/lib" \
  'grep -q "scripts/lib" .github/workflows/ci.yml'
t "S4.4"  "pre-commit derives its file dialects from the file, not a list" \
  '! grep -q "zsh_scripts=" .githooks/pre-commit && grep -q "shell_dialect" .githooks/pre-commit'
# Skip rather than fail where shellcheck is absent, the way bin/dotfiles-test
# already does. A missing linter is not a regression.
t "S4.6"  "fonts/install.sh is shellcheck-clean" \
  '! command -v shellcheck >/dev/null 2>&1 \
     || shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 fonts/install.sh'

#############################################################################
section "S5 — privacy and portability on a public repo"
#############################################################################

t "S5.1a" "git config carries no hardcoded identity" \
  '! grep -qiE "neostixz|Neoptolemos" config/git/config'
t "S5.1b" "git config includes a local override" \
  'grep -q "config.local" config/git/config'
t "S5.2a" "the live spicetify config is not tracked" \
  '[ -z "$(git ls-files config/spicetify/config-xpui.ini)" ]'
# Was pinned to the spicetify template, which no longer exists. The invariant
# that mattered was never about spicetify: no tracked configuration or capture
# may carry someone home directory path.
t "S5.2b" "no tracked config, app or capture carries a home path" '
  hits=0
  while IFS= read -r -d "" f; do
    [ -f "$f" ] || continue
    grep -alqE "/Users/[A-Za-z0-9._-]+" "$f" 2>/dev/null && hits=$((hits + 1))
  done < <(git ls-files -z "config/*" "apps/*" "system/*" "runcom/*" "macos/*" \
             "launchagents/*" "fonts/*" "packages/*" "claude/*")
  [ "$hits" -eq 0 ]'
# Was hardcoded to one baseline filename. `dotfiles-baseline capture` writes
# a new file per OS version, so every later capture escaped the check.
t "S5.3"  "no captured macOS baseline carries a home path" '
  n=$(ls macos/baselines/*.tsv 2>/dev/null | wc -l)
  [ "$n" -ge 1 ] && [ "$(grep -lE "/Users/[A-Za-z0-9._-]+" macos/baselines/*.tsv 2>/dev/null | wc -l)" -eq 0 ]'
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

# Was a grep for the words TMPDIR or fnm_multishells across four files, two
# of which matched on unrelated lines, so it could not detect the regression
# it named. The prune
# behaviour is covered by S7.2 below; what this guards is that the prune is
# reachable from a command at all, rather than defined and never called.
t "S7.1" "the multishell prune is wired into a command, not just defined" '
  grep -q "dotfiles_prune_fnm_multishells()" scripts/lib/fs.sh \
    && [ "$(code_of bin/dotfiles | grep -c "dotfiles_prune_fnm_multishells")" -ge 1 ]'
# Counting entries was the wrong invariant: it made "slim" the goal and let a
# needed marketplace be dropped while the tests stayed green. What matters is
# that the set is closed -- nothing listed is unused, and nothing the
# bootstrap references is unprovided.
t "CB.1" "every listed marketplace is used by at least one plugin" '
  bad=0
  while IFS= read -r mkt; do
    [ -n "$mkt" ] || continue
    short=$(basename "$mkt" .git)
    grep -vE "^[[:space:]]*(#|$)" claude/plugins.list \
      | grep -qE "@($short|${short%%-plugin})$" || bad=1
  done < <(grep -vE "^[[:space:]]*(#|$)" claude/marketplaces.list)
  [ "$bad" -eq 0 ]'
t "CB.2" "superpowers marketplace is present" \
  'grep -q "superpowers-marketplace" claude/marketplaces.list'
t "CB.3" "compound engineering marketplace is present" \
  'grep -qi "compound-engineering" claude/marketplaces.list'
t "CB.4" "every plugin names a marketplace that is listed" '
  bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in *@*) mkt="${line##*@}" ;; *) continue ;; esac
    grep -vE "^[[:space:]]*(#|$)" claude/marketplaces.list \
      | sed -E "s|.*/||; s|\.git$||" | grep -qx "$mkt" \
      || grep -qx "$mkt" <<< "compound-engineering-plugin" || bad=1
  done < <(grep -vE "^[[:space:]]*(#|$)" claude/plugins.list)
  [ "$bad" -eq 0 ]'
# Guards against the vacuous pass: if the extraction finds nothing the test
# fails, rather than quietly reporting success over an empty loop. An earlier
# version of this test did exactly that -- it stayed green while the
# marketplace providing these skills had been removed.
t "CB.5" "every skill the settings and hooks invoke is provided by a plugin" '
  skills=$(grep -ohE "[.]claude/skills/[a-z-]+" \
             claude/settings.template.json claude/hooks/*.sh \
           | sed "s|.*/||" | sort -u)
  [ -n "$skills" ] || { echo "    (extracted no skills -- assertion is vacuous)"; false; }
  bad=0
  for skill in $skills; do
    grep -vE "^[[:space:]]*(#|$)" claude/plugins.list | grep -q "^$skill" || bad=1
  done
  [ "$bad" -eq 0 ]'
t "CB.5b" "the recall venv the Stop hook invokes is created by the installer" \
  'grep -q "setup_recall_venv" scripts/install_claude.sh'
t "CB.5c" "the venv step tolerates missing graph deps without failing the bootstrap" \
  'code_of scripts/install_claude.sh | sed -n "/setup_recall_venv()/,/^}/p" | grep -q "|| true"'
t "CB.6" "the status line script the settings reference is tracked" \
  '[ -n "$(git ls-files claude/statusline.sh)" ]'
t "CB.7" "every hook the settings template references exists in the repo" '
  hooks=$(grep -ohE "[.]claude/hooks/[a-z-]+[.]sh" claude/settings.template.json | sed "s|.*/||" | sort -u)
  [ -n "$hooks" ] || { echo "    (extracted no hooks -- assertion is vacuous)"; false; }
  ok=1
  for h in $hooks; do [ -f "claude/hooks/$h" ] || ok=0; done
  [ "$ok" -eq 1 ]'
t "CB.8" "installer verifies settings references" \
  'grep -q "verify_settings_refs" scripts/install_claude.sh'

#############################################################################
section "SL — status line (tracked into a public repo, now audited)"
#############################################################################

# The status line was rewritten to read stdin only. Where it no longer holds a
# cache or makes a network call, asserting how it chmods a cache file is
# theatre -- so assert the stronger property instead, and keep the original
# tests alive for the day any of it comes back. grep -c, never `| grep -q`:
# under pipefail a matching grep -q kills the writer with SIGPIPE and a
# leading `!` turns that into a false pass.
_sl_cache=$(code_of claude/statusline.sh | grep -cE "cache_file|cache_dir|cache_mtime")
_sl_net=$(code_of claude/statusline.sh | grep -cE "curl|security find-generic-password")

if [ "$_sl_cache" -gt 0 ]; then
  t "SL.1" "usage cache is not in world-shared /tmp" \
    '! grep -qE "^cache_file=\"?/tmp/" claude/statusline.sh'
  t "SL.2" "cache dir is created with restrictive permissions" \
    'grep -qE "(mkdir -m 0?700|chmod 0?700)" claude/statusline.sh'
  t "SL.3" "cache file is written with restrictive permissions" \
    'grep -qE "chmod 0?600" claude/statusline.sh'
  t "SL.4" "an unreadable cache mtime cannot break the age arithmetic" \
    'code_of claude/statusline.sh | grep -qE "cache_mtime\) *cache_mtime=0|cache_mtime=0 *;;|cache_mtime:-0"'
  t "SL.4b" "every stat-derived mtime is normalised before arithmetic" '
    n=$(code_of claude/statusline.sh | grep -cE "_mtime=\\\$\\(stat")
    g=$(code_of claude/statusline.sh | grep -cE "\\*\\[!0-9\\]\\*\\)")
    [ "$g" -ge "$n" ]'
else
  t "SL.1" "the status line keeps no cache to get the permissions wrong on" \
    '[ "$(code_of claude/statusline.sh | grep -cE "cache_file|cache_dir|cache_mtime")" -eq 0 ]'
fi

if [ "$_sl_net" -gt 0 ]; then
  t "SL.5" "User-Agent is not pinned to a stale hardcoded version" \
    '[ "$(code_of claude/statusline.sh | grep -cE "claude-code/[0-9]+\.[0-9]+\.[0-9]+")" -eq 0 ]'
else
  t "SL.5" "the status line makes no network or keychain call" \
    '[ "$(code_of claude/statusline.sh | grep -cE "curl|security find-generic-password")" -eq 0 ]'
fi

t "SL.6" "renders and exits 0 with no token and no network" '
  out=$(echo "{\"context_window\":{\"current_usage\":{\"input_tokens\":1}},\"model\":{\"display_name\":\"X\"},\"workspace\":{\"current_dir\":\"$PWD\"}}" \
        | env -u ANTHROPIC_API_KEY PATH=/usr/bin:/bin bash claude/statusline.sh 2>/dev/null)
  [ -n "$out" ]'
t "SL.7" "shellcheck clean" \
  '! command -v shellcheck >/dev/null 2>&1 \
     || shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 claude/statusline.sh'

#############################################################################
section "S7.2 — the fnm prune must never delete a live shell's multishell"
#############################################################################

t "S7.2a" "prune is PID-aware, not age-only" \
  'code_of scripts/lib/fs.sh | grep -qE "kill -0|/proc/|ps -p"'
t "S7.2b" "prune spares a directory whose PID is still running" '
  W=$(sandbox); mkdir -p "$W/fnm_multishells"
  live="$W/fnm_multishells/$$_1700000000"
  dead="$W/fnm_multishells/99999999_1700000000"
  mkdir -p "$live" "$dead"
  # make both look old, so age alone would delete them
  touch -t 202001010000 "$live" "$dead"
  ( . scripts/lib/fs.sh; XDG_RUNTIME_DIR="$W" dotfiles_prune_fnm_multishells )
  [ -e "$live" ] && [ ! -e "$dead" ]'
t "S7.2d" "prune spares a dead-PID dir that is still on PATH" '
  W=$(sandbox); mkdir -p "$W/fnm_multishells"
  onpath="$W/fnm_multishells/99999997_1700000000"
  mkdir -p "$onpath/bin"; touch -t 202001010000 "$onpath"
  ( . scripts/lib/fs.sh
    PATH="$onpath/bin:$PATH" XDG_RUNTIME_DIR="$W" dotfiles_prune_fnm_multishells )
  [ -e "$onpath" ]'
t "S7.2c" "prune never touches the running shell FNM_MULTISHELL_PATH" '
  W=$(sandbox); mkdir -p "$W/fnm_multishells"
  keep="$W/fnm_multishells/99999998_1700000000"
  mkdir -p "$keep"; touch -t 202001010000 "$keep"
  ( . scripts/lib/fs.sh; XDG_RUNTIME_DIR="$W" FNM_MULTISHELL_PATH="$keep" dotfiles_prune_fnm_multishells )
  [ -e "$keep" ]'

finish

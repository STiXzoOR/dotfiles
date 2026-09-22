#!/usr/bin/env bash
#
# tests/ci.sh -- regression tests for the 2026-09-21 audit, quality-gates
# workstream: the pre-commit hook, the GitHub Actions workflow, and the
# honesty of the two test suites themselves.
#
# Assertions are single-quoted strings handed to eval inside t(), so they must
# NOT expand where they are written. SC2016 flags exactly that, by design.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "F1 — pre-commit (audit-ci #12–#17)"
#############################################################################

t "F1.1" "secret patterns catch nine real formats" '
  W=$(sandbox); bash tests/fixtures/make-secrets.sh > "$W/f.txt"
  n=0; while IFS= read -r p; do grep -qE "$p" "$W/f.txt" && n=$((n+1)); done \
    < <(bash .githooks/pre-commit --print-secret-patterns)
  [ "$n" -ge 9 ]'
t "F1.2" "gitleaks is used when installed" \
  'grep -q "gitleaks" .githooks/pre-commit'
t "F1.3" "dotfiles-secrets is not exempt from scanning" \
  '! grep -q "bin/dotfiles-secrets" .githooks/pre-commit'
t "F1.4" "syntax check derives dialect from shell_dialect for every file" \
  '! grep -q "zsh_scripts=" .githooks/pre-commit'
t "F1.5" "no ((x++)) under set -e" \
  '! grep -q "((ERRORS++))" .githooks/pre-commit'
t "F1.6" "staged files are read NUL-safe" \
  'grep -q "diff --cached --name-only -z\|-print0\|read -r -d" .githooks/pre-commit'
t "F1.7" "PRIVATE KEY pattern requires BEGIN" \
  '[ "$(bash .githooks/pre-commit --print-secret-patterns | grep -c "BEGIN")" -ge 1 ]'

# Everything above reads the hook. These run it, against a throwaway repo
# under $TMPDIR -- never this one, which other workstreams are committing to.
hookrepo() {
  local r
  r=$(sandbox) || return 1
  mkdir -p "$r/.githooks" || return 1
  cp .githooks/pre-commit "$r/.githooks/pre-commit" || return 1
  git -C "$r" init -q . > /dev/null 2>&1 || return 1
  git -C "$r" config user.email t@e.invalid || return 1
  git -C "$r" config user.name T || return 1
  printf '%s' "$r"
}

# PATH=/usr/bin:/bin is what forces the built-in patterns: it drops gitleaks,
# and it pins bash to the 3.2 in /bin, which is the only bash a bare Mac has.
t "F1.8" "the hook rejects a staged credential with no gitleaks installed" '
  R=$(hookrepo)
  bash tests/fixtures/make-secrets.sh > "$R/leak.txt"
  git -C "$R" add leak.txt
  out=$(cd "$R" && PATH=/usr/bin:/bin /bin/bash .githooks/pre-commit 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "Potential secret")" -ge 1 ]'
t "F1.9" "the hook passes a clean staged file" '
  R=$(hookrepo)
  printf "#!/usr/bin/env bash\necho hi\n" > "$R/ok.sh"
  git -C "$R" add ok.sh
  out=$(cd "$R" && PATH=/usr/bin:/bin /bin/bash .githooks/pre-commit 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "All pre-commit checks passed")" -ge 1 ]'
t "F1.10" "gitleaks catches it too, on the path a developer actually runs" '
  ! command -v gitleaks >/dev/null 2>&1 || {
    R=$(hookrepo)
    bash tests/fixtures/make-secrets.sh > "$R/leak.txt"
    git -C "$R" add leak.txt
    out=$(cd "$R" && bash .githooks/pre-commit 2>&1); rc=$?
    [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "gitleaks found")" -ge 1 ]
  }'
t "F1.11" "a staged path with a space is checked, not silently skipped" '
  R=$(hookrepo)
  printf "#!/usr/bin/env bash\nif then fi\n" > "$R/bad name.sh"
  git -C "$R" add "bad name.sh"
  out=$(cd "$R" && PATH=/usr/bin:/bin /bin/bash .githooks/pre-commit 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "Syntax error: bad name.sh")" -ge 1 ]'

#############################################################################
section "F2 — CI workflow (audit-ci #18–#25, research-security H3)"
#############################################################################

t "F2.1" "permissions contents: read at top level" \
  'grep -qE "^permissions:" .github/workflows/ci.yml && grep -q "contents: read" .github/workflows/ci.yml'
t "F2.2" "checkout v5 with persist-credentials false" \
  'grep -q "actions/checkout@v5" .github/workflows/ci.yml && grep -q "persist-credentials: false" .github/workflows/ci.yml'
t "F2.3" "concurrency cancel" \
  'grep -q "cancel-in-progress: true" .github/workflows/ci.yml'
t "F2.4" "no submodules on lint/syntax jobs" \
  '[ "$(grep -c "submodules: recursive" .github/workflows/ci.yml)" -le 1 ]'
t "F2.5" "no masked brew bundle check" \
  '! grep -q "brew bundle check.*|| true" .github/workflows/ci.yml'
t "F2.6" "runner pinned" \
  'grep -qE "runs-on: macos-(15|26)" .github/workflows/ci.yml'
t "F2.7" "tests/run.sh is the test entry" \
  'grep -q "tests/run.sh" .github/workflows/ci.yml'
t "F2.8" "pre-commit hook exercised in CI" \
  'grep -q "githooks/pre-commit" .github/workflows/ci.yml'
t "F2.9" "dependabot for actions" \
  'grep -q "github-actions" .github/dependabot.yml'
t "F2.10" "gitleaks in CI" \
  'grep -q gitleaks .github/workflows/ci.yml'
t "F2.11" "brew bundle check job" \
  'grep -q "brew bundle list" .github/workflows/ci.yml'
t "F2.12" "dead DOTFILES_DIR env is gone from the test job" \
  '! grep -q "DOTFILES_DIR: " .github/workflows/ci.yml'
t "F2.13" "apt-get update precedes apt-get install" \
  '[ "$(grep -c "apt-get update" .github/workflows/ci.yml)" -ge "$(grep -c "apt-get install" .github/workflows/ci.yml)" ]'

t "F2.14" "every workflow run block parses under bash 3.2" \
  'W=$(sandbox); bash tests/fixtures/extract-run-blocks.sh .github/workflows/ci.yml "$W"
   n=0; rc=0
   for b in "$W"/block-*.sh; do n=$((n + 1)); /bin/bash -n "$b" || rc=1; done
   [ "$n" -ge 8 ] && [ "$rc" -eq 0 ]'
# A blanket runcom/.* rule swept in runcom/.vimrc and runcom/.vim/**, which
# are vimscript and fail zsh -n outright, plus .gemrc and .mackup.cfg, which
# are YAML and INI and happened to parse as zsh -- "checked" by accident.
t "F2.15" "zsh discovery covers the startup files and nothing else in runcom" \
  'out=$(bash .github/scripts/zsh-syntax.sh 2>&1); rc=$?
   [ "$rc" -eq 0 ] \
     && [ "$(printf "%s\n" "$out" | grep -c "^Checking runcom/.zshrc")" -eq 1 ] \
     && [ "$(printf "%s\n" "$out" | grep "^Checking runcom/" \
              | grep -cvE "runcom/[.](z[a-z]*|profile)")" -eq 0 ] \
     && [ "$(printf "%s\n" "$out" | grep -c "^Checking")" -ge 20 ]'

#############################################################################
section "F4 — the test suites themselves (audit-ci #1–#11)"
#############################################################################

t "F4.1" "S1.2 asserts behaviour, not exit 1 anywhere" \
  '! grep -q "grep -q \"exit 1\" bin/dotfiles-secrets" tests/audit-regressions.sh'
t "F4.2" "S7.1 is specific" \
  '! grep -q "TMPDIR|fnm_multishells" tests/audit-regressions.sh'
t "F4.3" "S3.2 checks real shallowness" \
  'grep -q "is-shallow-repository\|rev-list --count" tests/audit-regressions.sh'
t "F4.4" "no real keychain writes in audit-regressions" \
  '! grep -q "secrets set __audit_rt" tests/audit-regressions.sh'
t "F4.5" "temp dirs cleaned" \
  'grep -q "finish\|trap" tests/audit-regressions.sh'
t "F4.6" "shellcheck tests skip when absent" \
  'grep -q "command -v shellcheck" tests/audit-regressions.sh'
t "F4.7" "startup threshold matches docs" \
  'grep -q "1000" bin/dotfiles-test && ! grep -q "2000" bin/dotfiles-test'
# grep -c, never `! ... | grep -q`: grep -q exits on the first match, the
# writer dies of SIGPIPE, and the leading `!` turns that into a false pass.
# The invariant is stronger than "not near the number 1000" anyway -- only
# pass() may increment the pass counter.
t "F4.8" "a warning is its own outcome, never counted as a pass" '
  [ "$(code_of bin/dotfiles-test | grep -c "TESTS_PASSED++")" -eq 1 ] \
    && [ "$(code_of bin/dotfiles-test | grep -c "TESTS_WARNED++")" -ge 1 ] \
    && [ "$(code_of bin/dotfiles-test | grep -c "Warned:")" -ge 1 ]'
t "F4.9" "XDG_CACHE_HOME restored exactly" \
  'grep -q "_saved_xdg" bin/dotfiles-test || grep -q "unset XDG_CACHE_HOME" bin/dotfiles-test'
t "F4.10" "dotfiles test runs tests/run.sh" \
  'grep -q "tests/run.sh" bin/dotfiles-test'

# Behavioural counterparts to the greps above.
# A private TMPDIR, not a before/after count of the shared one: other agents
# and other suites create sandboxes on this machine while this runs, and a
# count that catches one of theirs fails a test about a different process.
t "F4.11" "audit-regressions leaves no sandbox behind" '
  W=$(sandbox); mkdir -p "$W/tmp"
  TMPDIR="$W/tmp" bash tests/audit-regressions.sh >/dev/null 2>&1
  [ "$(find "$W/tmp" -maxdepth 1 -type d -name "dftest.*" 2>/dev/null | wc -l | tr -d " ")" -eq 0 ]'
t "F4.12" "audit-regressions uses the shared harness" \
  'grep -q "lib.sh" tests/audit-regressions.sh && ! grep -q "^pass=0; fail=0" tests/audit-regressions.sh'
t "F4.13" "the baseline privacy check covers every captured baseline" \
  '! grep -q "macos/baselines/15.6.1.tsv" tests/audit-regressions.sh'

# The baseline step kept its own copy of the extraction that bin/dotfiles-baseline
# performs, as a `grep -hoE "^defaults write ..."`. The tool grew a parser for
# quoted keys, -currentHost and sudo-prefixed domains; the grep did not, so the
# two counts drifted apart and `dotfiles test` failed with "captured 156 of 132"
# -- a red test reporting a bug in the test.
t "F4.14" "the baseline step counts declared keys with the tool that captures them" '
  [ "$(code_of bin/dotfiles-test | grep -c "defaults write \[A-Za-z0-9")" -eq 0 ] \
    && [ "$(code_of bin/dotfiles-test | grep -c "list | wc -l")" -ge 1 ]'
t "F4.15" "the two counts it compares actually agree on this tree" '
  W=$(sandbox)
  declared=$(bin/dotfiles-baseline list | wc -l | tr -d " ")
  DOTFILES_BASELINE_DIR="$W" bin/dotfiles-baseline capture t >/dev/null 2>&1
  captured=$(wc -l < "$W/t.tsv" | tr -d " ")
  [ "$declared" -gt 0 ] && [ "$declared" -eq "$captured" ]'
t "F4.16" "a run with warnings does not report that all tests passed" '
  [ "$(code_of bin/dotfiles-test | grep -c "TESTS_WARNED -eq 0")" -ge 1 ]'
# runcom/.profile says "Generic configuration that applies to all shells" and
# "bash + zsh compatible", and is sourced by bash and zsh. Linting it as POSIX
# sh flagged every [[ ]] and brace expansion in it, so the warn branch was on
# permanently -- and until this workstream, permanently counted as a pass.
t "F4.17" "the shell-config lint uses the dialect those files declare, not POSIX sh" '
  [ "$(code_of bin/dotfiles-test | grep -c -e "-s sh")" -eq 0 ]'
#############################################################################
section "F4b — bin/dotfiles-test against what the shell config actually does"
#############################################################################

t "F4.18" "the cache step no longer exercises a tool the shell config dropped" \
  '[ "$(grep -ci thefuck bin/dotfiles-test)" -eq 0 ]'
# The mirror of A12.2 in tests/cli.sh, which guards the same table in
# bin/dotfiles-doctor: a cache nothing writes is a test that can only skip.
t "F4.19" "every cache the test step generates is one the shell config writes" '
  bad=""
  while IFS= read -r stem; do
    stem="${stem%.zsh}"
    [ -n "$stem" ] || continue
    grep -rq -- "$stem" system/ runcom/ || bad="$bad $stem"
  done < <(sed -n "s|.*test_cache_dir/\([A-Za-z0-9._-]*\).*|\1|p" bin/dotfiles-test | sort -u)
  [ -z "$bad" ]'
t "F4.20" "the dircolors cache is generated under the name the shell writes" \
  '[ "$(grep -c "dircolors-" bin/dotfiles-test)" -ge 1 ]'

t "F4.21" "the zsh syntax step shares CI discovery instead of keeping a list" '
  n=$(bash .github/scripts/zsh-syntax.sh --list | wc -l | tr -d " ")
  [ "$n" -ge 20 ] \
    && [ "$(bash .github/scripts/zsh-syntax.sh --list | grep -c "^system/.editor$")" -eq 1 ] \
    && [ "$(code_of bin/dotfiles-test | grep -c "zsh-syntax.sh")" -ge 1 ]'
# system/.fix has not existed for a long time. The list was guarded by
# [[ -f ]], so it skipped silently and the three files added since -- .editor,
# .atuin, .pay-respects -- got no zsh -n coverage from this command at all.
t "F4.22" "no hand-written system/ list survives in bin/dotfiles-test" \
  '[ "$(code_of bin/dotfiles-test | grep -c "system/.fix")" -eq 0 ]'

# EDITOR moved to system/.editor, which .profile loads after system/.path
# because the answer depends on PATH. Sourcing system/.env alone therefore
# proves nothing about EDITOR: the assertion passed on a developer machine
# only because the calling shell already exported it.
t "F4.23" "system/.env alone leaves EDITOR unset; the loader order supplies it" '
  W=$(sandbox); mkdir -p "$W/h"
  a=$(env -u EDITOR HOME="$W/h" zsh -f -c ". system/.env >/dev/null 2>&1; print -r -- E=\$EDITOR")
  ln -s "$PWD" "$W/h/.dotfiles"
  b=$(env -u EDITOR HOME="$W/h" zsh -f -c ". \$HOME/.dotfiles/runcom/.profile >/dev/null 2>&1; print -r -- E=\$EDITOR")
  case "$b" in E=nvim | E=vim) ok=1 ;; *) ok=0 ;; esac
  [ "$a" = "E=" ] && [ "$ok" -eq 1 ]'
t "F4.24" "the environment step loads the chain, not system/.env on its own" '
  [ "$(code_of bin/dotfiles-test | grep -cE "source .*system/[.]env")" -eq 0 ] \
    && [ "$(code_of bin/dotfiles-test | grep -c "expected nvim or vim")" -ge 1 ]'


finish

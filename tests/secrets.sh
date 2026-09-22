#!/usr/bin/env bash
#
# tests/secrets.sh -- regression tests for the 2026-09-21 audit, secrets tool.
#
# NOTHING HERE TOUCHES A KEYCHAIN. Every test runs bin/dotfiles-secrets with
# tests/fixtures/security-stub copied into a sandbox as `security` and that
# sandbox first on PATH, so the tool takes its real code paths against a file
# under $TMPDIR. There is no keychain created, none unlocked, no login
# keychain read and no authorisation prompt. The suite this replaces stored a
# probe secret in the user's real login keychain, and a later attempt made a
# throwaway one, which set every open terminal asking to access it.
#
# Assertions are single-quoted strings handed to eval inside t(), so they must
# NOT expand where they are written. SC2016 flags exactly that, by design.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A sandbox holding bin/security (the stub) and store/. Called as W=$(box), so
# it runs in a subshell; lib.sh removes the shared sandbox root on exit.
box() {
  local w
  w=$(sandbox) || return 1
  mkdir -p "$w/bin" "$w/store" || return 1
  cp tests/fixtures/security-stub "$w/bin/security" || return 1
  chmod +x "$w/bin/security" || return 1
  # The stub appends every call here. Create it up front so that a test which
  # asserts "no call of this shape was made" reads an empty file rather than
  # an error from grep on a missing one.
  : > "$w/store/calls.log" || return 1
  printf '%s' "$w"
}

# Run the tool with the stub in front of PATH -- the only way this file ever
# invokes it. sec uses the default keychain, seck scopes to one. The
# assignments prefix an external command, so nothing leaks into the next test.
_run() {
  local w="$1" kc="$2"
  shift 2
  if [ -n "$kc" ]; then
    PATH="$w/bin:$PATH" DOTFILES_SECURITY_STUB_DIR="$w/store" DOTFILES_KEYCHAIN="$kc" \
      bin/dotfiles-secrets "$@"
  else
    PATH="$w/bin:$PATH" DOTFILES_SECURITY_STUB_DIR="$w/store" bin/dotfiles-secrets "$@"
  fi
}
sec() { _run "$1" "" "${@:2}"; }
seck() { _run "$1" "$2" "${@:3}"; }

#############################################################################
section "F3 — secrets tool (audit-ci #27–#34, research-security C1/C3/C4)"
#############################################################################

# If this fails, every other test in the file ran against the real
# /usr/bin/security and must be treated as unsafe, not merely wrong.
t "F3.0" "the suite resolves security to the stub, not /usr/bin/security" '
  W=$(box); [ "$(PATH="$W/bin:$PATH" command -v security)" = "$W/bin/security" ]'
# Built from a variable so the pattern cannot match the line that defines it.
t "F3.0b" "neither the suite nor the stub names a keychain-management verb" '
  v="create|delete|unlock|lock|default|list|set"
  [ "$(code_of tests/secrets.sh tests/fixtures/security-stub | grep -cE "($v)-keychain")" -eq 0 ]'

t "F3.1" "set/get round-trip" '
  W=$(box); printf "v1\n" | sec "$W" set rt >/dev/null 2>&1
  [ "$(sec "$W" get rt)" = v1 ]'
t "F3.2" "delete removes the name from list" '
  W=$(box); printf "v\n" | sec "$W" set d1 >/dev/null 2>&1
  sec "$W" delete d1 >/dev/null 2>&1
  out=$(sec "$W" list 2>/dev/null)
  [ "$(printf "%s\n" "$out" | grep -c d1)" -eq 0 ]'
t "F3.3" "env rejects an unsafe variable name" '
  W=$(box); printf "v\n" | sec "$W" set e1 >/dev/null 2>&1
  ! sec "$W" env e1 "X; touch $W/pwned" >/dev/null 2>&1'
t "F3.4" "export refuses non-interactive stdin" '
  W=$(box); ! sec "$W" export "$W/out.age" </dev/null >/dev/null 2>&1'
t "F3.5" "import does not stage plaintext on disk" \
  '[ "$(code_of bin/dotfiles-secrets | grep -c mktemp)" -eq 0 ]'
t "F3.6" "export uses age when available" \
  'grep -q "age -p" bin/dotfiles-secrets'
t "F3.7" "no ((x++)) under set -e" \
  '[ "$(code_of bin/dotfiles-secrets | grep -cE "\(\([A-Za-z_]+\+\+\)\)")" -eq 0 ]'
t "F3.8" "locked keychain is reported, not treated as empty" \
  'grep -qE "36|45|locked" bin/dotfiles-secrets'

#############################################################################
section "F3b — behaviour the grep tests above cannot reach"
#############################################################################

# Was S1.3b in tests/audit-regressions.sh, where it wrote to the real login
# keychain. This is the only round-trip coverage the tool has.
t "F3.9" "list names a secret that was just stored" '
  W=$(box); printf "v\n" | sec "$W" set rt2 >/dev/null 2>&1
  out=$(sec "$W" list 2>/dev/null)
  [ "$(printf "%s\n" "$out" | grep -c rt2)" -ge 1 ]'
t "F3.10" "delete prunes the index rather than leaving list to self-heal" '
  W=$(box)
  printf "a\n" | sec "$W" set k1 >/dev/null 2>&1
  printf "b\n" | sec "$W" set k2 >/dev/null 2>&1
  sec "$W" delete k1 >/dev/null 2>&1
  idx=$(awk -F"\t" "\$1 == \"dotfiles.__index\" { print \$2 }" "$W/store/login")
  [ "$idx" = "k2" ]'
t "F3.11" "env emits a safe assignment for a value full of metacharacters" '
  W=$(box); v="a b;\$(touch $W/pwned)|c"
  printf "%s\n" "$v" | sec "$W" set m1 >/dev/null 2>&1
  line=$(sec "$W" env m1 MYVAR 2>/dev/null)
  ( eval "$line"; [ "$MYVAR" = "$v" ] ) && [ ! -e "$W/pwned" ]'
t "F3.12" "a value with a newline is refused instead of silently corrupted" '
  W=$(box); ! printf "one\ntwo\n" | sec "$W" set nl1 >/dev/null 2>&1'
t "F3.13" "get distinguishes a missing secret from an unreadable one" '
  W=$(box); printf "v\n" | sec "$W" set lk >/dev/null 2>&1
  : > "$W/store/login.locked"
  miss=$(sec "$W" get nosuch 2>&1 </dev/null); mrc=$?
  out=$(sec "$W" get lk 2>&1 </dev/null); orc=$?
  [ "$mrc" -ne 0 ] && [ "$orc" -ne 0 ] \
    && [ "$(printf "%s\n" "$out" | grep -ci "locked\|denied")" -ge 1 ] \
    && [ "$(printf "%s\n" "$miss" | grep -ci "not found")" -ge 1 ]'
t "F3.13b" "list says the keychain is locked instead of reporting no secrets" '
  W=$(box); printf "v\n" | sec "$W" set lk2 >/dev/null 2>&1
  : > "$W/store/login.locked"
  out=$(sec "$W" list 2>&1 </dev/null); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -ci "locked\|denied")" -ge 1 ]'
t "F3.14" "DOTFILES_KEYCHAIN scopes every call, so the default keychain is untouched" '
  W=$(box); K="$W/alt.keychain-db"
  printf "v\n" | seck "$W" "$K" set sc1 >/dev/null 2>&1
  [ "$(seck "$W" "$K" get sc1)" = v ] \
    && [ ! -e "$W/store/login" ] \
    && [ "$(grep -c "kc=login" "$W/store/calls.log")" -eq 0 ]'
t "F3.15" "help no longer advertises putting a secret on the command line" \
  '[ "$(bin/dotfiles-secrets --help 2>/dev/null | grep -cE "set [a-z_]+ \"?sk-")" -eq 0 ]'

#############################################################################
section "F3c — the prompted set, which needs a terminal"
#############################################################################

# The tool's reason for putting `-w` last is that security then prompts and
# the plaintext never enters this process or any argv. Nothing exercised that
# before, because it cannot run without a terminal.
t "F3.20" "a prompted set hands the prompt to security, with no value on argv" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box)
    expect tests/fixtures/secrets-set.exp "$W" - pr1 "prompted-value" >/dev/null 2>&1
    [ "$(sec "$W" get pr1)" = "prompted-value" ] \
      && [ "$(grep -c "^add-generic-password .* -w PROMPT " "$W/store/calls.log")" -ge 1 ] \
      && [ "$(grep -c "^add-generic-password .* -a dotfiles.pr1 -w ARGV " "$W/store/calls.log")" -eq 0 ]
  }'
# DOTFILES_KEYCHAIN may only append a path to a security call. It must not buy
# a second implementation of the prompt: security prompts only when -w is its
# final argument, which leaves no room for the trailing keychain path, so the
# honest answer is to refuse rather than to read the value in here and pass it
# on an argv that the ordinary path never uses.
t "F3.21" "a prompted set with DOTFILES_KEYCHAIN refuses instead of forking the code path" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box); K="$W/alt.keychain-db"
    expect tests/fixtures/secrets-set.exp "$W" "$K" pr2 v >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] \
      && [ "$(grep -c " -w ARGV " "$W/store/calls.log")" -eq 0 ] \
      && ! seck "$W" "$K" get pr2 >/dev/null 2>&1
  }'
t "F3.22" "a prompted set whose confirmation differs stores nothing" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box)
    expect tests/fixtures/secrets-set.exp "$W" - pr3 first second >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] && ! sec "$W" get pr3 >/dev/null 2>&1
  }'
t "F3.23" "a refused prompted set does not destroy the value already stored" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box); printf "keep-me\n" | sec "$W" set pr4 >/dev/null 2>&1
    expect tests/fixtures/secrets-set.exp "$W" - pr4 one two >/dev/null 2>&1
    [ "$(sec "$W" get pr4)" = "keep-me" ]
  }'

# -U updates an item in place, so the delete that ran first bought nothing
# and gave every `set` a window in which the old value was already gone.
t "F3.24" "set over an existing secret updates it without deleting it first" '
  W=$(box); printf "one\n" | sec "$W" set ov >/dev/null 2>&1
  : > "$W/store/calls.log"
  printf "two\n" | sec "$W" set ov >/dev/null 2>&1
  [ "$(sec "$W" get ov)" = two ] \
    && [ "$(grep -c "^delete-generic-password .* -a dotfiles.ov " "$W/store/calls.log")" -eq 0 ]'

#############################################################################
section "F3d — export and import, end to end"
#############################################################################

# Was S1.2 in tests/audit-regressions.sh, as
# `! grep "No secrets to export" <file> || grep "exit 1" <file>`. The file
# holds 21 occurrences of `exit 1`, so the right-hand side always succeeded
# and the test passed whatever export did.
t "F3.16" "export exits non-zero and writes nothing when there is nothing to export" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box)
    out=$(PATH="$W/bin:$PATH" DOTFILES_SECURITY_STUB_DIR="$W/store" \
            expect tests/fixtures/pty-run.exp ./bin/dotfiles-secrets export "$W/e.age" 2>&1); rc=$?
    [ "$rc" -ne 0 ] \
      && [ "$(printf "%s\n" "$out" | grep -c "No secrets to export")" -ge 1 ] \
      && [ ! -e "$W/e.age" ]
  }'
# The audit found export and import had never been run end to end by anything.
t "F3.17" "export and import round-trip every secret through an encrypted file" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box); K1="$W/one.keychain-db"; K2="$W/two.keychain-db"; F="$W/x.enc"
    P="correct horse battery staple"
    printf "alpha-value\n"      | seck "$W" "$K1" set s_one >/dev/null 2>&1
    printf "beta with spaces\n" | seck "$W" "$K1" set s_two >/dev/null 2>&1
    expect tests/fixtures/secrets-roundtrip.exp export "$W" "$K1" "$F" "$P" >/dev/null 2>&1 \
      && [ -s "$F" ] \
      && expect tests/fixtures/secrets-roundtrip.exp import "$W" "$K2" "$F" "$P" >/dev/null 2>&1 \
      && [ "$(seck "$W" "$K2" get s_one)" = "alpha-value" ] \
      && [ "$(seck "$W" "$K2" get s_two)" = "beta with spaces" ]
  }'
# find -perm, not stat: GNU stat reads -f as --file-system, and GNU coreutils
# is on PATH here while a bare Mac has only the BSD one. That split is a
# recurring bug in this repo; the test must not reintroduce it.
t "F3.18" "the exported file is not world-readable" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box); K="$W/p.keychain-db"; F="$W/p.enc"
    printf "v\n" | seck "$W" "$K" set p1 >/dev/null 2>&1
    expect tests/fixtures/secrets-roundtrip.exp export "$W" "$K" "$F" pw >/dev/null 2>&1 \
      && [ -n "$(find "$F" -maxdepth 0 -perm 600 2>/dev/null)" ]
  }'
t "F3.19" "a wrong passphrase imports nothing and exits non-zero" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box); K1="$W/r.keychain-db"; K2="$W/w.keychain-db"; F="$W/r.enc"
    printf "v\n" | seck "$W" "$K1" set w1 >/dev/null 2>&1
    expect tests/fixtures/secrets-roundtrip.exp export "$W" "$K1" "$F" right >/dev/null 2>&1 || false
    ! expect tests/fixtures/secrets-roundtrip.exp import "$W" "$K2" "$F" wrong >/dev/null 2>&1 \
      && ! seck "$W" "$K2" get w1 >/dev/null 2>&1
  }'
#############################################################################
section "F3e — what the help promises about argv exposure"
#############################################################################

# The help told users to prefer a pipe over an argument because an argument is
# visible in ps. A piped value is visible in ps too: it reaches
# `security add-generic-password ... -w <value>` exactly as an argv value
# does. F3.28 is the proof; F3.25-F3.27 hold the documentation to it. Assert
# on the help collapsed to one line, so wrapping cannot decide the outcome.
t "F3.25" "help no longer offers the pipe as a way to stay out of ps" '
  h=$(bin/dotfiles-secrets --help 2>/dev/null | tr "\n" " ")
  [ "$(printf "%s" "$h" | grep -ciE "prefer[^.]*pipe")" -eq 0 ]'
# Anchored on "only the prompt": the looser "prompt .* only" matched the
# unrelated DOTFILES_KEYCHAIN note ("prompts only when -w is its last
# argument") and passed before anything was corrected.
t "F3.26" "help names the prompt as the one form with no value on an argv" '
  h=$(bin/dotfiles-secrets --help 2>/dev/null | tr "\n" " ")
  [ "$(printf "%s" "$h" | grep -ciE "only the (interactive )?prompt")" -ge 1 ]'
t "F3.27" "help says a piped value still reaches the security command line" '
  h=$(bin/dotfiles-secrets --help 2>/dev/null | tr "\n" " ")
  [ "$(printf "%s" "$h" | grep -ciE "pipe[^.]*(ps|command line)|(ps|command line)[^.]*pipe")" -ge 1 ]'
t "F3.28" "a piped set puts the value on security argv; only a prompted one does not" '
  ! command -v expect >/dev/null 2>&1 || {
    W=$(box)
    printf "piped-value\n" | sec "$W" set pv >/dev/null 2>&1
    a=$(grep -c "^add-generic-password .* -a dotfiles.pv -w ARGV " "$W/store/calls.log")
    expect tests/fixtures/secrets-set.exp "$W" - pp "prompted-value" >/dev/null 2>&1
    b=$(grep -c "^add-generic-password .* -a dotfiles.pp -w PROMPT " "$W/store/calls.log")
    c=$(grep -c "^add-generic-password .* -a dotfiles.pp -w ARGV " "$W/store/calls.log")
    [ "$a" -ge 1 ] && [ "$b" -ge 1 ] && [ "$c" -eq 0 ]
  }'
t "F3.29" "the runtime warning on an argv value does not recommend a pipe for ps" '
  W=$(box)
  out=$(sec "$W" set av "on-argv" 2>&1)
  [ "$(printf "%s\n" "$out" | grep -ciE "prefer[^.]*pipe")" -eq 0 ] \
    && [ "$(printf "%s\n" "$out" | grep -ci "history")" -ge 1 ]'


finish

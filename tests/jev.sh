#!/usr/bin/env bash
#
# tests/jev.sh -- Jev (TypeSafe System One) foundation, privacy guard and
# secrets guard (Task 8 of the 2026-09-29 new-Mac readiness work).
#
# HERMETIC. The real TypeSafe API is never called: `curl` on PATH is
# tests/fixtures/jev/fake-curl, which records argv, stdin and the request body
# and answers from tests/fixtures/jev/. `security` is the shared stub, so the
# login keychain is never read. Every run uses a sandbox HOME, state dir and
# private dir. Fixture identities (names, hosts, addresses) are synthetic and
# every credential-shaped value is generated at run time, so nothing here
# matches a secret pattern or names a real person.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FIXD="$ROOT_DIR/tests/fixtures/jev"

# JEV_ONLY="A B": run only the tests whose id starts with one of these.
if [ -n "${JEV_ONLY:-}" ]; then
  eval "$(declare -f t | sed '1s/^t /_t_real /')"
  t() { local p; for p in $JEV_ONLY; do case "$1" in "$p"*) _t_real "$@"; return ;; esac; done; }
fi

# rand <count> <tr class>: run-time random text (see tests/fixtures/make-secrets.sh)
rand() { rand_chars "$@"; }

# mkenv <W>: sandbox HOME/state/private dir, stubs (fake curl, keychain stub,
# scutil) and an empty repo tree standing in for DOTFILES_DIR.
mkenv() {
  local w="$1"
  mkdir -p "$w/home/.ssh" "$w/stubs" "$w/rec" "$w/sec" "$w/state" "$w/priv/jev" "$w/repo/profiles"
  cp "$FIXD/fake-curl" "$w/stubs/curl"
  cp "$ROOT_DIR/tests/fixtures/security-stub" "$w/stubs/security"
  printf '#!/bin/sh\nprintf "%%s\\n" "${STUB_LOCALHOST:-Frobnitz-Mini}"\n' >"$w/stubs/scutil"
  chmod +x "$w/stubs/"*
}

# key_in_keychain <W> <key>: seed the stub keychain with the API key item.
key_in_keychain() {
  printf 'dotfiles.typesafe_api_key\t%s\n' "$2" >"$1/sec/login"
}

# jrun <script>: run a bash snippet with the lib sourced, inside the sandbox in
# $W. $JENV adds VAR=value pairs (no spaces).
jrun() {
  # shellcheck disable=SC2086
  env -i HOME="$W/home" PATH="$W/stubs:/usr/bin:/bin" \
    FAKE_CURL_DIR="$W/rec" FAKE_CURL_FIXDIR="$FIXD" DOTFILES_SECURITY_STUB_DIR="$W/sec" \
    XDG_STATE_HOME="$W/state" DOTFILES_PRIVATE_DIR="$W/priv" DOTFILES_DIR="$W/repo" \
    JEV_BACKOFF=0 DOTFILES_COMPUTER_NAME="${T_COMPUTER:-}" ${JENV:-} \
    bash -c "cd '$W' && source '$ROOT_DIR/scripts/lib/jev.sh' && $1"
}

LOGF() { printf '%s/state/dotfiles/jev.jsonl' "$W"; }
calls() { cat "$W/rec/count" 2>/dev/null || echo 0; }
# recorded <W>: everything the fake curl saw, argv + stdin config + body.
recorded() { cat "$W/rec/argv.log" "$W/rec/stdin.log" "$W/rec/body.log" 2>/dev/null; }

# A one-question noul, as the guards send it.
Q='{"reveals":{"type":"noul","instructions":"Is it private?","criteria":{"true":"yes","false":"no"}}}'

#############################################################################
section "A -- jev_ask: request shape, key handling, limits"
#############################################################################

t "A1" "POSTs {model,state,questions} to the systemone endpoint and prints the answers" '
  W=$(sandbox); mkenv "$W"; printf "hello world\n" >"$W/state.txt"
  out=$(JENV="TYPESAFE_API_KEY=k-test-1 FAKE_CURL_ANSWER=answer-high.json" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'")
  [ "$(printf "%s" "$out" | jq -r .reveals.noul)" = "0.93" ] &&
  [ "$(grep -c "https://api.typesafe.ai/v1/systemone" "$W/rec/argv.log")" -eq 1 ] &&
  [ "$(jq -r ".model" "$W/rec/body.log")" = "jev-1.13.0" ] &&
  [ "$(jq -r ".state" "$W/rec/body.log")" = "hello world" ] &&
  [ "$(jq -r ".questions.reveals.type" "$W/rec/body.log")" = "noul" ]'
t "A2" "the model is pinned, DOTFILES_JEV_MODEL overrides, jev-latest is never sent" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k-test-1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  JENV="TYPESAFE_API_KEY=k-test-1 DOTFILES_JEV_MODEL=jev-9.9.9" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  [ "$(jq -r .model "$W/rec/body.log" | sed -n 1p)" = "jev-1.13.0" ] &&
  [ "$(jq -r .model "$W/rec/body.log" | sed -n 2p)" = "jev-9.9.9" ] &&
  [ "$(grep -c "jev-latest" "$W/rec/body.log")" -eq 0 ]'
t "A3" "the key reaches curl on stdin (--config -), never argv, body or the log" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k-sekrit-0042" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  jrun "jev_log privacy shadow test" >/dev/null
  [ "$(grep -c "k-sekrit-0042" "$W/rec/stdin.log")" -ge 1 ] &&
  [ "$(grep -c -e "--config" "$W/rec/argv.log")" -eq 1 ] &&
  [ "$(cat "$W/rec/argv.log" "$W/rec/body.log" | grep -c "k-sekrit-0042")" -eq 0 ] &&
  [ "$(grep -rc "k-sekrit-0042" "$W/state" | grep -vc ":0$")" -eq 0 ]'
t "A4" "without TYPESAFE_API_KEY the key comes from the dotfiles Keychain item" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"; key_in_keychain "$W" k-from-kc-7
  jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  [ "$(grep -c "k-from-kc-7" "$W/rec/stdin.log")" -ge 1 ] &&
  [ "$(grep -c "find-generic-password -s dotfiles -a dotfiles.typesafe_api_key -w" "$W/sec/calls.log")" -ge 1 ]'
t "A5" "no key: no request, non-zero, exactly one log line per run" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  jrun "jev_init; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; r1=\$?; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; r2=\$?; jev_cleanup; [ \$r1 -ne 0 ] && [ \$r2 -ne 0 ]" &&
  [ "$(calls)" -eq 0 ] && [ "$(grep -c "skipped: no key" "$(LOGF)")" -eq 1 ]'
t "A6" "DOTFILES_JEV=off makes no request at all, even with a key" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV=off" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  rc=$?
  [ "$rc" -ne 0 ] && [ "$(calls)" -eq 0 ]'
t "A7" "hard timeout: 2 s interactive, 10 s scheduled, override by JEV_TIMEOUT; no retry after one" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  JENV="TYPESAFE_API_KEY=k1 JEV_SCHEDULED=1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  JENV="TYPESAFE_API_KEY=k1 JEV_TIMEOUT=5" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  [ "$(sed -n 1p "$W/rec/argv.log" | grep -c -e "--max-time 2 ")" -eq 1 ] &&
  [ "$(sed -n 2p "$W/rec/argv.log" | grep -c -e "--max-time 10 ")" -eq 1 ] &&
  [ "$(sed -n 3p "$W/rec/argv.log" | grep -c -e "--max-time 5 ")" -eq 1 ]'
t "A8" "a curl timeout fails fast: non-zero, one attempt" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_TIMEOUT=1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  rc=$?
  [ "$rc" -ne 0 ] && [ "$(calls)" -eq 1 ] && [ "$(grep -c "error" "$(LOGF)")" -ge 1 ]'
t "A9" "429/5xx are retried (JEV_TRIES=2) and then succeed" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=503,200 FAKE_CURL_ANSWER=answer-high.json" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'")
  [ "$(calls)" -eq 2 ] && [ "$(printf "%s" "$out" | jq -r .reveals.noul)" = "0.93" ]'
t "A10" "429 twice gives up after exactly JEV_TRIES attempts" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=429,429,200" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  rc=$?
  [ "$rc" -ne 0 ] && [ "$(calls)" -eq 2 ]'
t "A11" "JEV_TRIES=3 allows a third attempt" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 JEV_TRIES=3 FAKE_CURL_SEQ=529,500,200" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 3 ]'
t "A12" "422 is not retried" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=422,200" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  rc=$?
  [ "$rc" -ne 0 ] && [ "$(calls)" -eq 1 ]'
t "A13" "401 sets a fatal marker: later calls in the same run make no request" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=401,200" jrun "jev_init; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_cleanup" >/dev/null
  [ "$(calls)" -eq 1 ] && [ "$(grep -c "fatal" "$(LOGF)")" -ge 1 ]'
t "A14" "403 is fatal too" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=403,200" jrun "jev_init; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_cleanup" >/dev/null
  [ "$(calls)" -eq 1 ]'
t "A15" "a per-run request cap stops further calls" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 JEV_MAX_REQUESTS=2" jrun "jev_init; for i in 1 2 3 4; do jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; done; jev_cleanup" >/dev/null
  [ "$(calls)" -eq 2 ] && [ "$(grep -c "cap" "$(LOGF)")" -ge 1 ]'
t "A16" "the request body file is removed and was not world-readable" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  mkdir "$W/tmp"
  JENV="TYPESAFE_API_KEY=k1 TMPDIR=$W/tmp" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  [ -z "$(ls -A "$W/tmp")" ]'

#############################################################################
section "B -- redaction before anything leaves the Mac"
#############################################################################

# A synthetic identity. Nothing here is a real person, host or address.
SYN_NAME="Zorblax Quimby"
SYN_PROJECT="quimby-lab"
SYN_COMPUTER="Frobnitz Mini"
SYN_ALIAS="secretbox"

# redact_env <W>: never-send list, computer name, ssh alias, own-secret names.
redact_env() {
  printf '# private values\n%s\n%s\n' "$SYN_NAME" "$SYN_PROJECT" >"$1/priv/jev/never-send.list"
  printf 'Host github.com\n  User git\nHost %s\n  HostName example.invalid\nHost *\n  AddKeysToAgent yes\n' "$SYN_ALIAS" >"$1/home/.ssh/config"
  printf 'openai_key() { dotfiles-secrets get openai_api_key; }\n' >"$1/repo/profiles/local.zsh"
  OWN="own-secret-$(rand 14 "A-Za-z0-9")"
  printf 'dotfiles.openai_api_key\t%s\n' "$OWN" >"$1/sec/login"
}
# ask_state <W> <state text>: send the text through jev_ask, return the body sent.
ask_state() {
  printf '%s\n' "$2" >"$1/state.txt"
  JENV="TYPESAFE_API_KEY=k1 " T_COMPUTER="$SYN_COMPUTER" jrun "jev_ask privacy state.txt '$Q'" >/dev/null
  jq -r .state "$1/rec/body.log"
}

t "B1" "every never-send value is replaced, case-insensitively" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "author $SYN_NAME (zorblax quimby) works on QUIMBY-LAB")
  [ "$(printf "%s" "$s" | grep -ci "quimby")" -eq 0 ] && [ "$(printf "%s" "$s" | grep -o "<NEVER-SEND>" | grep -c .)" -eq 3 ]'
t "B2" "the computer name, LocalHostName, ssh aliases and \$HOME are replaced" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "on $SYN_COMPUTER aka Frobnitz-Mini ssh $SYN_ALIAS then ls $W/home/docs")
  [ "$(printf "%s" "$s" | grep -ci "frobnitz")" -eq 0 ] &&
  [ "$(printf "%s" "$s" | grep -c "$SYN_ALIAS")" -eq 0 ] &&
  [ "$(printf "%s" "$s" | grep -c "$W/home")" -eq 0 ] &&
  [ "$(printf "%s" "$s" | grep -c "<HOME>/docs")" -eq 1 ]'
t "B3" "a public ssh host such as github.com is not treated as private" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "git clone git@github.com:someone/repo")
  [ "$(printf "%s" "$s" | grep -c "github.com")" -eq 1 ]'
t "B4" "nothing the redactor replaced appears anywhere the fake curl recorded" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  ask_state "$W" "$SYN_NAME on $SYN_COMPUTER via $SYN_ALIAS in $W/home" >/dev/null
  r=$(recorded)
  [ "$(printf "%s" "$r" | grep -ci -e "zorblax" -e "quimby" -e "frobnitz" -e "$SYN_ALIAS" | head -1)" -eq 0 ] &&
  [ "$(printf "%s" "$r" | grep -c "$W/home")" -eq 0 ]'
t "B5" "a line holding a known token format is replaced by its masked shape" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  tok="ghp_$(rand 36 "A-Za-z0-9")"
  s=$(ask_state "$W" "before
GITHUB_TOKEN=$tok
after")
  [ "$(recorded | grep -c "$tok")" -eq 0 ] &&
  [ "$(printf "%s" "$s" | grep -c "name=GITHUB_TOKEN len=40 classes=[a-z,]* first3=ghp")" -eq 1 ] &&
  [ "$(printf "%s" "$s" | grep -c "^before$")" -eq 1 ] && [ "$(printf "%s" "$s" | grep -c "^after$")" -eq 1 ]'
t "B6" "the masked shape shows the line with the value replaced" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  tok="ghp_$(rand 36 "A-Za-z0-9")"
  s=$(ask_state "$W" "export GITHUB_TOKEN=\"$tok\"")
  [ "$(printf "%s" "$s" | grep -c "line=export GITHUB_TOKEN=\"<VALUE>\"")" -eq 1 ]'
t "B7" "a high-entropy value assigned to a credential-named key is masked too" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  v=$(rand 40 "A-Za-z0-9")
  s=$(ask_state "$W" "service_secret: $v")
  [ "$(recorded | grep -c "$v")" -eq 0 ] && [ "$(printf "%s" "$s" | grep -c "name=service_secret len=40")" -eq 1 ]'
t "B8" "a value from the owners own keychain is masked without even its first characters" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "curl -H \"x: $OWN\" https://example.invalid")
  tail4=$(printf "%s" "${OWN#own-secret-}" | cut -c1-4)
  [ "$(recorded | grep -c "$OWN")" -eq 0 ] && [ "$(recorded | grep -c "own-secret-")" -eq 0 ] &&
  [ "$(recorded | grep -c "$tail4")" -eq 0 ] && [ "$(printf "%s" "$s" | grep -c "first3")" -eq 0 ] &&
  [ "$(printf "%s" "$s" | grep -c "masked own-secret")" -eq 1 ]'
t "B9" "the state is capped well under the 32k-token limit and says so" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  big=$(awk "BEGIN { for (i = 0; i < 6000; i++) print \"line number \" i \" of some ordinary text\" }")
  s=$(ask_state "$W" "$big")
  [ "${#s}" -le 48200 ] && [ "$(printf "%s" "$s" | grep -c "truncated")" -eq 1 ]'
t "B10" "ordinary text passes through unchanged" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "alias gs=\"git status\" # nothing private here")
  [ "$s" = "alias gs=\"git status\" # nothing private here" ]'
t "B11" "the redaction is inside jev_ask: a caller cannot bypass it" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  printf "%s\n" "$SYN_NAME" >"$W/raw.txt"
  JENV="TYPESAFE_API_KEY=k1" jrun "jev_ask privacy raw.txt '"'"'$Q'"'"'" >/dev/null
  [ "$(recorded | grep -c "Zorblax")" -eq 0 ]'
t "B12" "a missing never-send list and no private dir are fine" '
  W=$(sandbox); mkenv "$W"; command rm -rf "$W/priv"
  s=$(ask_state "$W" "hello")
  [ "$s" = "hello" ]'

#############################################################################
section "C -- modes, thresholds, verdicts, the decision log"
#############################################################################

t "C1" "every point defaults to shadow" '
  W=$(sandbox); mkenv "$W"
  [ "$(jrun "jev_mode privacy")" = shadow ] && [ "$(jrun "jev_mode secrets")" = shadow ] && [ "$(jrun "jev_mode anything")" = shadow ]'
t "C2" "the mode comes from the config file in the private dir" '
  W=$(sandbox); mkenv "$W"; printf "privacy=on\nsecrets=off\n" >"$W/priv/jev/jev.conf"
  [ "$(jrun "jev_mode privacy")" = on ] && [ "$(jrun "jev_mode secrets")" = off ]'
t "C3" "DOTFILES_JEV=off is a master switch over the config" '
  W=$(sandbox); mkenv "$W"; printf "privacy=on\n" >"$W/priv/jev/jev.conf"
  [ "$(JENV="DOTFILES_JEV=off" jrun "jev_mode privacy")" = off ]'
t "C4" "an unknown mode value falls back to shadow, never to on" '
  W=$(sandbox); mkenv "$W"; printf "privacy=yes-please\n" >"$W/priv/jev/jev.conf"
  [ "$(jrun "jev_mode privacy")" = shadow ]'
t "C5" "verdict: block at p>=0.85 and confidence>=0.8" '
  W=$(sandbox); mkenv "$W"
  [ "$(jrun "jev_verdict privacy 0.85 0.8")" = block ] && [ "$(jrun "jev_verdict privacy 0.97 0.99")" = block ]'
t "C6" "verdict: warn in the middle band, or when confidence is too low to block" '
  W=$(sandbox); mkenv "$W"
  [ "$(jrun "jev_verdict privacy 0.5 0.9")" = warn ] && [ "$(jrun "jev_verdict privacy 0.84 0.95")" = warn ] &&
  [ "$(jrun "jev_verdict privacy 0.95 0.79")" = warn ]'
t "C7" "verdict: pass below 0.5" '
  W=$(sandbox); mkenv "$W"
  [ "$(jrun "jev_verdict privacy 0.49 0.99")" = pass ] && [ "$(jrun "jev_verdict privacy 0 1")" = pass ]'
t "C8" "thresholds can be tuned per point in the config file" '
  W=$(sandbox); mkenv "$W"; printf "privacy.block_p=0.95\nprivacy.warn_p=0.7\n" >"$W/priv/jev/jev.conf"
  [ "$(jrun "jev_verdict privacy 0.9 0.9")" = warn ] && [ "$(jrun "jev_verdict privacy 0.6 0.9")" = pass ] &&
  [ "$(jrun "jev_verdict secrets 0.9 0.9")" = block ]'
t "C9" "jev_log appends one JSON line: point, mode, questions, answers, latency, action" '
  W=$(sandbox); mkenv "$W"
  jrun "JEV_LAST_MS=42; jev_log privacy shadow \"shadow: would have blocked\" '"'"'{\"reveals\":{\"type\":\"noul\",\"noul\":0.93,\"confidence\":0.91}}'"'"'" >/dev/null
  l=$(cat "$(LOGF)")
  [ "$(printf "%s\n" "$l" | grep -c .)" -eq 1 ] &&
  [ "$(printf "%s" "$l" | jq -r .point)" = privacy ] && [ "$(printf "%s" "$l" | jq -r .mode)" = shadow ] &&
  [ "$(printf "%s" "$l" | jq -r ".questions | join(\",\")")" = reveals ] &&
  [ "$(printf "%s" "$l" | jq -r .answers.reveals.noul)" = "0.93" ] &&
  [ "$(printf "%s" "$l" | jq -r .latency_ms)" = 42 ] &&
  [ "$(printf "%s" "$l" | jq -r .action)" = "shadow: would have blocked" ] &&
  [ -n "$(printf "%s" "$l" | jq -r .ts)" ]'
t "C10" "a successful jev_ask leaves its latency for the caller to log" '
  W=$(sandbox); mkenv "$W"; printf "x\n" >"$W/state.txt"
  out=$(JENV="TYPESAFE_API_KEY=k1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; printf \"%s\" \"\$JEV_LAST_MS\"")
  case "$out" in "" | *[!0-9]*) false ;; *) true ;; esac'
t "C11" "the log holds no state text, only ids and numbers" '
  W=$(sandbox); mkenv "$W"; printf "SENTINEL-STATE-TEXT\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_SEQ=500" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  JENV="TYPESAFE_API_KEY=k1" jrun "jev_ask privacy state.txt '"'"'$Q'"'"'" >/dev/null
  [ "$(grep -c "SENTINEL" "$(LOGF)")" -eq 0 ]'

#############################################################################
section "D -- guard-staged: privacy and secrets over the staged diff"
#############################################################################

# gitrepo <W>: a throwaway repo at $W/r holding the guard, its libs and the
# real hook, so the guard and the hook run exactly as shipped.
gitrepo() {
  local r="$1/r"
  mkdir -p "$r/bin" "$r/scripts/lib" "$r/.githooks" "$r/profiles"
  cp "$ROOT_DIR/bin/dotfiles-jev" "$r/bin/"
  cp "$ROOT_DIR"/scripts/lib/jev* "$r/scripts/lib/"
  cp "$ROOT_DIR/.githooks/pre-commit" "$r/.githooks/"
  git -C "$r" init -q . >/dev/null 2>&1
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name T
  # The one address that is already public in this repo's LICENSE.
  printf 'Copyright (c) 2015, Pat Public <%s%s>\n' "pat.public@" "pubmail.io" >"$r/LICENSE.md"
}
# gstage <W> <path> <content>: write and stage a file.
gstage() {
  mkdir -p "$(dirname "$1/r/$2")"
  printf '%s\n' "$3" >"$1/r/$2"
  git -C "$1/r" add "$2"
}
# grun <cmd...>: run a command in the sandbox repo with the sandbox environment.
# T_SYNC=0 lets the guard background its Jev stage; by default it runs inline.
grun() {
  # shellcheck disable=SC2086
  (cd "$W/r" && env -i HOME="$W/home" PATH="$W/stubs:/usr/bin:/bin" \
    FAKE_CURL_DIR="$W/rec" FAKE_CURL_FIXDIR="$FIXD" DOTFILES_SECURITY_STUB_DIR="$W/sec" \
    XDG_STATE_HOME="$W/state" DOTFILES_PRIVATE_DIR="$W/priv" JEV_BACKOFF=0 \
    DOTFILES_COMPUTER_NAME="${T_COMPUTER:-}" ${T_SYNC:+DOTFILES_JEV_SYNC=1} ${JENV:-} "$@")
}
guard() { grun bash bin/dotfiles-jev guard-staged; }
# a fresh sandbox with a repo; sync unless a test says otherwise
newrepo() { W=$(sandbox); mkenv "$W"; gitrepo "$W"; T_SYNC=1; }
setmode() { printf '%s\n' "$1" >>"$W/priv/jev/jev.conf"; }
IP_PRIV="192.168.$((RANDOM % 200 + 1)).$((RANDOM % 200 + 1))"

t "D1" "a clean commit: no output, exit 0, and no request without a key" '
  newrepo; gstage "$W" notes.txt "a plain line of documentation prose"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 0 ]'
t "D2" "a value from the never-send list blocks, naming file and line, before Jev" '
  newrepo; redact_env "$W"; gstage "$W" notes.txt "line one
this repo belongs to $SYN_NAME"
  out=$(JENV="TYPESAFE_API_KEY=k1" guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: notes.txt:2:")" -eq 1 ] && [ "$(calls)" -eq 0 ]'
t "D3" "the never-send match is a whole word, case-insensitively" '
  newrepo; redact_env "$W"; gstage "$W" a.txt "notes on quimby-labs and subquimby-lab-x"
  gstage "$W" b.txt "see QUIMBY-LAB now"
  out=$(guard 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "a.txt")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: b.txt:1:")" -eq 1 ]'
t "D4" "a home path with a real user name blocks; documentation placeholders do not" '
  newrepo; gstage "$W" a.sh "cd /$(printf Users)/jdoe/projects"
  gstage "$W" b.sh "cd /Users/<name>/x; ls /Users/Shared; cd /Users/\$USER; /Users/you/y"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.sh:1:.*home directory path")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "b.sh")" -eq 0 ]'
t "D5" "private network addresses block: 10/8, 172.16/12, 192.168/16 and 100.64/10" '
  newrepo
  gstage "$W" a.txt "ssh box $IP_PRIV"; gstage "$W" b.txt "host 10.$((RANDOM % 200 + 1)).3.4"
  gstage "$W" c.txt "ip 172.$((16 + RANDOM % 16)).1.9"; gstage "$W" d.txt "tailscale 100.$((64 + RANDOM % 64)).102.103"
  out=$(guard 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: .*private network address")" -eq 4 ]'
t "D6" "public addresses, versions and out-of-range ones do not block" '
  newrepo
  gstage "$W" a.txt "dns 8.8.8.8 and 172.32.0.1 and 100.128.0.1 and 192.169.1.1 and 1.2.3.4"
  gstage "$W" b.txt "v10.0.0.1 tool-1.10.0.1.2 and 300.1.1.1 and 10.0.0.999"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]'
t "D7" "an email blocks unless already public in LICENSE/README or a reserved one" '
  newrepo
  gstage "$W" a.txt "mail jane.roe@$(printf widgets).io"
  gstage "$W" b.txt "mail pat.public@$(printf pubmail).io, foo@example.com, x@users.noreply.github.com, git@github.com:o/r"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.txt:1:.*email")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "b.txt")" -eq 0 ]'
t "D8" "DOTFILES_PRIVACY_OK=1 skips the privacy checks for one commit and logs it" '
  newrepo; gstage "$W" a.txt "ssh box $IP_PRIV"
  out=$(JENV="DOTFILES_PRIVACY_OK=1" guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "DOTFILES_PRIVACY_OK")" -ge 1 ] &&
  [ "$(grep -c "override: DOTFILES_PRIVACY_OK=1" "$(LOGF)")" -eq 1 ]'
t "D9" "the override does not cover a credential" '
  newrepo; tok="ghp_$(rand 36 A-Za-z0-9)"; gstage "$W" a.txt "GITHUB_TOKEN=$tok"
  out=$(JENV="DOTFILES_PRIVACY_OK=1" guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: a.txt:1:")" -eq 1 ]'
t "D10" "a credential blocks and its value appears nowhere: output, requests, log" '
  newrepo; tok="ghp_$(rand 36 A-Za-z0-9)"; gstage "$W" a.txt "before
export GITHUB_TOKEN=\"$tok\""
  out=$(JENV="TYPESAFE_API_KEY=k1" guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: a.txt:2:")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "$tok")" -eq 0 ] && [ "$(recorded | grep -c "$tok")" -eq 0 ] &&
  [ "$(cat "$W"/state/dotfiles/jev.jsonl 2>/dev/null | grep -c "$tok")" -eq 0 ]'
t "D11" "the generator that the hook tests use is caught by the guard too" '
  newrepo; bash "$ROOT_DIR/tests/fixtures/make-secrets.sh" >"$W/r/leak.txt"; git -C "$W/r" add leak.txt
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: leak.txt:")" -ge 8 ]'
t "D12" "the value of one of your own Keychain secrets blocks, never printed" '
  newrepo; redact_env "$W"; gstage "$W" a.txt "note $OWN end"
  cp "$W/repo/profiles/local.zsh" "$W/r/profiles/local.zsh"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: a.txt:1:.*own Keychain secrets")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "$OWN")" -eq 0 ]'
t "D13" "a high-entropy value under a credential-named key only warns, and sends Jev the masked shape" '
  newrepo; v=$(rand 40 A-Za-z0-9); gstage "$W" a.txt "service_secret: $v"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard 2>&1); rc=$?
  s=$(jq -r .state "$W/rec/body.log")
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "WARN  secrets: a.txt:1:")" -eq 1 ] &&
  [ "$(recorded | grep -c "$v")" -eq 0 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "variable name: service_secret")" -eq 1 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "value length: 40")" -eq 1 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "line: service_secret: <VALUE>")" -eq 1 ] &&
  [ "$(grep -c "shadow: would have blocked" "$(LOGF)")" -ge 1 ]'
t "D14" "secrets in on mode: Jev high blocks an ambiguous value, low lets it through" '
  newrepo; setmode secrets=on; v=$(rand 40 A-Za-z0-9); gstage "$W" a.txt "service_secret: $v"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard 2>&1); rc=$?
  bad=; [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK secrets: a.txt:1: Jev thinks")" -eq 1 ] || bad=1
  out2=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-low.json" guard 2>&1); rc2=$?
  [ -z "$bad" ] && [ "$rc2" -eq 0 ] && [ "$(printf "%s\n" "$out2" | grep -c "BLOCK")" -eq 0 ]'
t "D15" "privacy in shadow mode: asks Jev about the hunk, logs would-have, blocks nothing" '
  newrepo; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 1 ] &&
  [ "$(jq -r .state "$W/rec/body.log" | grep -c "Acme onboarding")" -eq 1 ] &&
  [ "$(jq -r ".questions.reveals.type" "$W/rec/body.log")" = noul ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action)" = "shadow: would have blocked: hunk 1 of 1" ]'
t "D16" "privacy in on mode: high blocks, mid warns, low confidence warns, low passes" '
  newrepo; setmode privacy=on; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  o1=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard 2>&1); r1=$?
  o2=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-mid.json" guard 2>&1); r2=$?
  o3=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-lowconf.json" guard 2>&1); r3=$?
  o4=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-low.json" guard 2>&1); r4=$?
  [ "$r1" -eq 1 ] && [ "$(printf "%s\n" "$o1" | grep -c "BLOCK privacy: a.txt:1:")" -eq 1 ] &&
  [ "$r2" -eq 0 ] && [ "$(printf "%s\n" "$o2" | grep -c "WARN  privacy: a.txt:1:")" -eq 1 ] &&
  [ "$r3" -eq 0 ] && [ "$(printf "%s\n" "$o3" | grep -c "WARN  privacy: a.txt:1:")" -eq 1 ] &&
  [ "$r4" -eq 0 ] && [ -z "$o4" ]'
t "D17" "privacy fails open when Jev fails: warns not checked, exit 0, and the deterministic part still blocks" '
  newrepo; setmode privacy=on; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_TIMEOUT=1" guard 2>&1); rc=$?
  bad=; [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "WARN  privacy: a.txt:1: not checked by Jev")" -eq 1 ] || bad=1
  gstage "$W" b.txt "box $IP_PRIV"
  out2=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_TIMEOUT=1" guard 2>&1); rc2=$?
  [ -z "$bad" ] && [ "$rc2" -eq 1 ] && [ "$(printf "%s\n" "$out2" | grep -c "BLOCK privacy: b.txt:1:")" -eq 1 ]'
t "D18" "on mode with no key: warns not checked, makes no request, exit 0" '
  newrepo; setmode privacy=on; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "not checked by Jev (no API key)")" -eq 1 ] && [ "$(calls)" -eq 0 ]'
t "D19" "DOTFILES_JEV=off: no request, but the deterministic checks still block" '
  newrepo; setmode privacy=on; gstage "$W" a.txt "we shipped the Acme onboarding flow"
  gstage "$W" b.txt "box $IP_PRIV"
  out=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV=off" guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(calls)" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: b.txt:1:")" -eq 1 ]'
t "D20" "a hunk that a deterministic check caught is not also sent to Jev" '
  newrepo; gstage "$W" a.txt "box $IP_PRIV"
  JENV="TYPESAFE_API_KEY=k1" guard >/dev/null 2>&1
  [ "$(calls)" -eq 0 ]'
t "D21" "lockfiles, near-empty hunks and the replay fixtures are not sent" '
  newrepo; gstage "$W" mise.lock "some locked content that is long enough to matter"
  gstage "$W" b.txt "}"
  gstage "$W" tests/fixtures/jev/replay/privacy.jsonl "{\"id\":\"x\",\"label\":true,\"state\":\"host $IP_PRIV in a long enough line\"}"
  out=$(JENV="TYPESAFE_API_KEY=k1" guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 0 ]'
t "D22" "at most JEV_MAX_HUNKS hunks are sent per commit" '
  newrepo; for i in 1 2 3 4; do gstage "$W" "f$i.txt" "an ordinary line of prose number $i in this file"; done
  JENV="TYPESAFE_API_KEY=k1 JEV_MAX_HUNKS=2" guard >/dev/null 2>&1
  [ "$(calls)" -eq 2 ]'
t "D23" "what is sent is only the hunk, redacted: a never-send value in a hunk is a deterministic block, not a request" '
  newrepo; redact_env "$W"; gstage "$W" a.txt "prose about the host ${SYN_COMPUTER// /-} only"
  gstage "$W" b.txt "another fine line of ordinary prose"
  JENV="TYPESAFE_API_KEY=k1" T_COMPUTER="$SYN_COMPUTER" guard >/dev/null 2>&1
  [ "$(recorded | grep -ci "frobnitz")" -eq 0 ] && [ "$(jq -r .state "$W/rec/body.log" | grep -c "another fine line")" -eq 1 ]'
t "D24" "shadow mode returns without waiting: the Jev stage runs in the background and still logs" '
  newrepo; T_SYNC=""; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard 2>&1); rc=$?
  n=0; while [ "$n" -lt 100 ] && [ ! -s "$(LOGF)" ]; do sleep 0.1; n=$((n + 1)); done
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(grep -c "shadow: would have blocked" "$(LOGF)")" -eq 1 ]'
t "D25" "a binary or deleted-only change does not confuse the guard" '
  newrepo; printf "\000\001\002bin" >"$W/r/x.bin"; git -C "$W/r" add x.bin
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]'
t "D26" "a staged path with a space is checked" '
  newrepo; gstage "$W" "my notes.txt" "box $IP_PRIV"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: my notes.txt:1:")" -eq 1 ]'
t "D27" "line numbers are the real ones in the file, not positions in the diff" '
  newrepo; gstage "$W" a.txt "1
2
3"
  git -C "$W/r" commit -qm one --no-verify
  printf "1\n2\n3\nfour\nbox $IP_PRIV\n" >"$W/r/a.txt"; git -C "$W/r" add a.txt
  out=$(guard 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.txt:5:")" -eq 1 ]'

#############################################################################
section "E -- the pre-commit hook runs the guard and stays as it was without one"
#############################################################################

hookrun() { grun /bin/bash .githooks/pre-commit; }

t "E1" "a clean commit passes the hook, guard included" '
  newrepo; gstage "$W" ok.txt "a plain line of documentation prose"
  out=$(hookrun 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "All pre-commit checks passed")" -eq 1 ]'
t "E2" "a private address fails the hook and the message names the guard" '
  newrepo; gstage "$W" ok.txt "box $IP_PRIV"
  out=$(hookrun 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: ok.txt:1:")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "Pre-commit check failed")" -eq 1 ]'
t "E3" "DOTFILES_JEV=off and no key: the hook behaves as before plus the deterministic checks" '
  newrepo; gstage "$W" ok.txt "a plain line of documentation prose"
  out=$(JENV="DOTFILES_JEV=off" hookrun 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "All pre-commit checks passed")" -eq 1 ]'
t "E4" "the hook passes a repo that has no guard at all, exactly as before" '
  newrepo; command rm -f "$W/r/bin/dotfiles-jev"; gstage "$W" ok.txt "box $IP_PRIV"
  out=$(hookrun 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK")" -eq 0 ]'
t "E5" "a guard that crashes blocks: the deterministic part never fails open" '
  newrepo; printf "#!/usr/bin/env bash\nexit 7\n" >"$W/r/bin/dotfiles-jev"; gstage "$W" ok.txt "fine"
  out=$(hookrun 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s\n" "$out" | grep -c "guard could not run")" -eq 1 ]'
t "E6" "the hook asks the guard not to rerun gitleaks (it already ran)" '
  [ "$(code_of .githooks/pre-commit | grep -c "JEV_GITLEAKS=0")" -ge 1 ] && [ "$(code_of .githooks/pre-commit | grep -c "guard-staged")" -ge 1 ]'

#############################################################################
section "F -- scan-tree, scan-vault and the apps staging tree"
#############################################################################

# grun-free runner for the tools that are not run inside a repo
jtool() { # jtool <args...>: bin/dotfiles-jev from the real repo, sandbox env
  # shellcheck disable=SC2086
  env -i HOME="$W/home" PATH="$W/stubs:/usr/bin:/bin" \
    FAKE_CURL_DIR="$W/rec" FAKE_CURL_FIXDIR="$FIXD" DOTFILES_SECURITY_STUB_DIR="$W/sec" \
    XDG_STATE_HOME="$W/state" DOTFILES_PRIVATE_DIR="$W/priv" DOTFILES_DIR="$W/repo" JEV_BACKOFF=0 \
    DOTFILES_JEV_LOCAL_ZSH="$W/repo/profiles/local.zsh" ${JENV:-} bash "$ROOT_DIR/bin/dotfiles-jev" "$@"
}

t "F1" "scan-tree finds a credential: exit 1, file and line, never the value" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree/sub"; tok="ghp_$(rand 36 A-Za-z0-9)"
  printf "a\nb\ntoken = %s\n" "$tok" >"$W/tree/sub/settings.ini"; printf "clean\n" >"$W/tree/ok.txt"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK sub/settings.ini:3:")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "$tok")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "ok.txt")" -eq 0 ]'
t "F2" "scan-tree on a clean tree: exit 0, no request" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "clean\nalso clean\n" >"$W/tree/ok.txt"
  out=$(JENV="TYPESAFE_API_KEY=k1" jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 0 ]'
t "F3" "scan-tree reads a harmless binary file and does not call it unscanned" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "\000\001\002" >"$W/tree/x.bin"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "not scanned")" -eq 0 ]'
t "F4" "scan-tree checks the owners own Keychain values" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"; mkdir -p "$W/tree"; printf "x = %s\n" "$OWN" >"$W/tree/a.txt"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK a.txt:1:.*own Keychain")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "$OWN")" -eq 0 ]'
t "F5" "scan-tree: an ambiguous value warns in shadow, and blocks in on mode when Jev says live" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; v=$(rand 40 A-Za-z0-9); printf "api_secret: %s\n" "$v" >"$W/tree/a.txt"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" jtool scan-tree "$W/tree" 2>&1); rc=$?
  bad=; [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "WARN  a.txt:1:")" -eq 1 ] && [ "$(recorded | grep -c "$v")" -eq 0 ] || bad=1
  setmode secrets=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ -z "$bad" ] && [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK a.txt:1: Jev thinks")" -eq 1 ]'
t "F6" "scan-vault reports file and line, changes nothing, exits 1 on a hit" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/vault/Claude-Sessions/2026"; tok="sk-ant-$(rand 40 A-Za-z0-9)"
  printf "notes\nI pasted %s here\n" "$tok" >"$W/vault/Claude-Sessions/2026/s1.md"; printf "fine\n" >"$W/vault/Claude-Sessions/s2.md"
  before=$(cd "$W/vault" && find . -type f | sort | xargs shasum | shasum)
  out=$(JENV="DOTFILES_VAULT_DIR=$W/vault" jtool scan-vault 2>&1); rc=$?
  after=$(cd "$W/vault" && find . -type f | sort | xargs shasum | shasum)
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "FOUND 2026/s1.md:2:")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "$tok")" -eq 0 ] && [ "$before" = "$after" ]'
t "F7" "scan-vault with nothing found exits 0; a missing directory is exit 2" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/vault/Claude-Sessions"; printf "fine\n" >"$W/vault/Claude-Sessions/s.md"
  JENV="DOTFILES_VAULT_DIR=$W/vault" jtool scan-vault >/dev/null 2>&1; rc=$?
  JENV="DOTFILES_VAULT_DIR=$W/nowhere" jtool scan-vault >/dev/null 2>&1; rc2=$?
  [ "$rc" -eq 0 ] && [ "$rc2" -eq 2 ]'
t "F8" "scan-tree reads gitleaks when installed (one run over the tree)" '
  ! command -v gitleaks >/dev/null 2>&1 || {
    W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; bash "$ROOT_DIR/tests/fixtures/make-secrets.sh" >"$W/tree/leak.txt"
    out=$(PATH="$PATH:/opt/homebrew/bin" jtool scan-tree "$W/tree" 2>&1); rc=$?
    [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK leak.txt:")" -ge 8 ]
  }'

#############################################################################
section "G -- status, log, promote, replay"
#############################################################################

t "G1" "status shows the switch, model, key source and modes, and never the key" '
  W=$(sandbox); mkenv "$W"; setmode privacy=on
  out=$(JENV="TYPESAFE_API_KEY=k-sekrit-0042" jtool status 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "master switch: on")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "jev-1.13.0")" -ge 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "key: found")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "k-sekrit-0042")" -eq 0 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "privacy  *on ")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "secrets  *shadow")" -eq 1 ]'
t "G2" "status with the master switch off and no key says so" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="DOTFILES_JEV=off" jtool status 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "master switch: OFF")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "key: missing")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "privacy  *off")" -eq 1 ]'
t "G3" "log prints decisions readably, and raw JSON with --raw" '
  W=$(sandbox); mkenv "$W"
  jrun "JEV_LAST_MS=42; jev_log privacy shadow \"shadow: would have blocked: hunk 1 of 2\" '"'"'{\"reveals\":{\"type\":\"noul\",\"noul\":0.93,\"confidence\":0.91}}'"'"'" >/dev/null
  out=$(jtool log 2>&1); raw=$(jtool log --raw 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "privacy \[shadow\] shadow: would have blocked: hunk 1 of 2")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "reveals=0.93")" -eq 1 ] && [ "$(printf "%s" "$raw" | jq -r .point)" = privacy ]'
t "G4" "promote switches a point from shadow to on in the private config; twice is a no-op" '
  W=$(sandbox); mkenv "$W"
  out=$(jtool promote privacy 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(jrun "jev_mode privacy")" = on ] && [ "$(jrun "jev_mode secrets")" = shadow ] &&
  [ "$(printf "%s\n" "$out" | grep -c "replay")" -ge 1 ] &&
  [ "$(jtool promote privacy 2>&1 | grep -c "already on")" -eq 1 ] && [ "$(grep -c "^privacy=" "$W/priv/jev/jev.conf")" -eq 1 ]'
t "G5" "promote can demote, rejects unknown points and modes" '
  W=$(sandbox); mkenv "$W"; jtool promote secrets >/dev/null 2>&1; jtool promote secrets shadow >/dev/null 2>&1
  jtool promote nonsense >/dev/null 2>&1; r1=$?; jtool promote privacy sideways >/dev/null 2>&1; r2=$?
  [ "$(jrun "jev_mode secrets")" = shadow ] && [ "$r1" -eq 2 ] && [ "$r2" -eq 2 ]'
t "G6" "promote refuses when there is no private repo to keep the config in" '
  W=$(sandbox); mkenv "$W"; command rm -rf "$W/priv"
  out=$(jtool promote privacy 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "private repo is not set up")" -eq 1 ] && [ ! -e "$W/priv" ]'

# a small labelled set for replay: two positives, two negatives
mkreplay() { # mkreplay <W>
  mkdir -p "$1/replay"
  {
    printf '{"id":"p1","label":true,"state":"POS-ALPHA reveals"}\n'
    printf '{"id":"p2","label":true,"state":"POS-BETA reveals"}\n'
    printf '{"id":"n1","label":false,"state":"NEG-GAMMA fine"}\n'
    printf '{"id":"n2","label":false,"state":"NEG-DELTA looks odd"}\n'
  } >"$1/replay/privacy.jsonl"
  printf 'POS-\tanswer-high.json\nNEG-DELTA\tanswer-mid.json\nNEG-\tanswer-low.json\n' >"$1/rec/rules"
}
t "G7" "replay prints precision and recall per threshold from labelled cases" '
  W=$(sandbox); mkenv "$W"; mkreplay "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV_REPLAY_DIR=$W/replay" jtool replay privacy 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 4 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^  p >= 0.85 .*tp=2  *fp=0  *fn=0  *tn=2  *precision=1.00 recall=1.00")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^  p >= 0.5 .*tp=2  *fp=1  *fn=0  *tn=1  *precision=0.67 recall=1.00")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "block: p >= 0.85 and conf >= 0.8")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "Calibration is contested")" -eq 1 ]'
t "G8" "replay leaves the decision log alone and needs a key" '
  W=$(sandbox); mkenv "$W"; mkreplay "$W"
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV_REPLAY_DIR=$W/replay" jtool replay privacy >/dev/null 2>&1
  bad=; [ ! -s "$(LOGF)" ] || bad=1
  out=$(JENV="DOTFILES_JEV_REPLAY_DIR=$W/replay" jtool replay privacy 2>&1); rc=$?
  [ -z "$bad" ] && [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "no API key")" -eq 1 ]'
t "G9" "the shipped labelled cases are well-formed, both-labelled, and answerable" '
  ok=1
  for p in privacy secrets; do
    f=tests/fixtures/jev/replay/$p.jsonl
    [ "$(jq -r "select(.id and (.label | type == \"boolean\") and (.state | type == \"string\")) | .id" "$f" | grep -c .)" -eq "$(grep -c . "$f")" ] || ok=0
    [ "$(jq -r "select(.label == true) | .id" "$f" | grep -c .)" -ge 5 ] || ok=0
    [ "$(jq -r "select(.label == false) | .id" "$f" | grep -c .)" -ge 5 ] || ok=0
  done
  [ "$ok" -eq 1 ]'
t "G10" "replay runs over the shipped cases for both points (fake API)" '
  W=$(sandbox); mkenv "$W"
  o1=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR" jtool replay privacy 2>&1); r1=$?
  o2=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR" jtool replay secrets 2>&1); r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$(printf "%s\n" "$o1" | grep -c "precision=")" -ge 8 ]'
t "G11" "the shipped labelled cases hold no credential-shaped text and no real owner identity" '
  [ "$(bash .githooks/pre-commit --print-secret-patterns | grep -c .)" -ge 8 ] &&
  [ "$(cat tests/fixtures/jev/replay/*.jsonl | grep -Ec -f <(bash .githooks/pre-commit --print-secret-patterns))" -eq 0 ]'

#############################################################################
section "H -- wiring: dotfiles jev, apps, docs"
#############################################################################

t "H1" "bin/dotfiles routes jev and lists it in help" '
  [ "$(code_of bin/dotfiles | grep -c "sub_jev()")" -eq 1 ] && [ "$(code_of bin/dotfiles | grep -c "dotfiles-jev")" -ge 1 ] &&
  [ "$(code_of bin/dotfiles | grep -c "\"apps\" | \"jev\"\|\"jev\"")" -ge 1 ] && [ "$(code_of bin/dotfiles | grep -c "   jev ")" -eq 1 ]'
t "H2" "dotfiles-apps scans the staging tree with the secrets guard before it publishes" '
  a=$(_first_line "dotfiles-jev" bin/dotfiles-apps); p=$(_first_line "publish \"\$STORE" bin/dotfiles-apps)
  [ "$a" -gt 0 ] && [ "$p" -gt 0 ] && [ "$(code_of bin/dotfiles-apps | grep -c "scan-tree")" -ge 1 ]'
t "H3" "docs/agents/jev.md exists and covers the required topics" '
  d=docs/agents/jev.md
  [ -f "$d" ] && (for w in "never-send" "shadow" "promote" "replay" "DOTFILES_JEV=off" "not used for training" "masked" "jev-1.13.0" "scan-vault" "DOTFILES_PRIVACY_OK"; do
    [ "$(grep -c -- "$w" "$d")" -ge 1 ] || exit 1
  done)'
t "H4" "AGENTS.md links the Jev page" '
  [ "$(grep -c "docs/agents/jev.md" AGENTS.md)" -eq 1 ]'
t "H5" "the private never-send list and config live outside the repo: nothing private is tracked" '
  [ "$(git ls-files | grep -c "never-send.list\|jev/jev.conf")" -eq 0 ]'

#############################################################################
section "I -- review fixes: multi-line secrets, binary files, host terms, locked keychain, masked messages"
#############################################################################

# stub_multi_secret <W>: a keychain whose item dotfiles.multi_key is a
# multi-line value with an empty line in it; everything else is not found.
stub_multi_secret() {
  printf '#!/bin/sh\ncase "$*" in *dotfiles.multi_key*) printf "alpha-line-QWERTY123\\n\\nbeta-line-ASDFGH456\\n" ;; *) exit 44 ;; esac\n' >"$1/stubs/security"
  chmod +x "$1/stubs/security"
  printf 'multi_key() { dotfiles-secrets get multi_key; }\n' >"$1/repo/profiles/local.zsh"
}
# stub_locked_keychain <W>: every security call fails as a locked keychain does.
stub_locked_keychain() {
  printf '#!/bin/sh\nexit 36\n' >"$1/stubs/security"; chmod +x "$1/stubs/security"
  printf 'openai_key() { dotfiles-secrets get openai_api_key; }\n' >"$1/repo/profiles/local.zsh"
}

t "I1" "a multi-line own secret: no fragment of any line reaches curl or the log; blank lines are not patterns" '
  W=$(sandbox); mkenv "$W"; stub_multi_secret "$W"
  s=$(ask_state "$W" "keep this
x beta-line-ASDFGH456 y

then alpha-line-QWERTY123
ordinary text
end")
  jrun "jev_log privacy shadow test" >/dev/null
  r=$(recorded; cat "$(LOGF)")
  [ "$(printf "%s" "$r" | grep -c -e "alpha-line" -e "beta-line" -e "QWERTY" -e "ASDFGH")" -eq 0 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "masked own-secret")" -eq 2 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "^keep this$")" -eq 1 ] && [ "$(printf "%s\n" "$s" | grep -c "^ordinary text$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$s" | grep -c "^end$")" -eq 1 ] && [ "$(printf "%s\n" "$s" | grep -c "^$")" -eq 1 ]'
t "I2" "an own-secret line is dropped whole: the marker carries none of its text" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"
  s=$(ask_state "$W" "before $OWN after")
  [ "$s" = "[masked own-secret line]" ]'

# tp <id> <description> <expression>: t, but skipped visibly (never silently
# passed) when this machine has no plutil.
tp() {
  if command -v plutil >/dev/null 2>&1; then t "$@"
  else printf "  %sSKIP%s %s %s (needs plutil)\n" "$RED" "$RESET" "$1" "$2"; fi
}

mkplist() { # mkplist <file> <value>: a BINARY plist holding <value>
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><string>%s</string></dict></plist>' "$2" >"$1.xml"
  plutil -convert binary1 -o "$1" "$1.xml" && command rm -f "$1.xml"
}
tp "I3" "scan-tree scans a binary plist through plutil: a credential in it is found" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; tok="ghp_$(rand 36 A-Za-z0-9)"
  mkplist "$W/tree/settings.plist" "é$tok"
  bad=; [ "$(head -c 6 "$W/tree/settings.plist")" = bplist ] || bad=1
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ -z "$bad" ] && [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK settings.plist:")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "$tok")" -eq 0 ]'
t "I4" "scan-tree finds a credential and an own secret inside other binary files" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"; mkdir -p "$W/tree"; tok="ghp_$(rand 36 A-Za-z0-9)"
  { printf "\000\001\002"; printf "token = %s" "$tok"; printf "\000\003"; } >"$W/tree/blob.dat"
  { printf "\000\001"; printf "x %s y" "$OWN"; printf "\000"; } >"$W/tree/other.dat"
  printf "garbage\000not a plist" >"$W/tree/bad.plist"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK blob.dat:")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "BLOCK other.dat:.*own Keychain")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "bad.plist")" -eq 0 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "$tok" -e "$OWN")" -eq 0 ]'
t "I5" "only a file that cannot be read is reported as not scanned" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "x\n" >"$W/tree/locked.txt"; chmod 000 "$W/tree/locked.txt"
  out=$(jtool scan-tree "$W/tree" 2>&1); chmod 600 "$W/tree/locked.txt"
  [ "$(printf "%s\n" "$out" | grep -c "1 file(s) not scanned (unreadable)")" -eq 1 ]'
tp "I6" "a settings backup with a credential inside a binary plist is refused" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; tok="ghp_$(rand 36 A-Za-z0-9)"
  mkplist "$W/tree/a.plist" "$tok"
  mkdir -p "$W/vault/Claude-Sessions"; cp "$W/tree/a.plist" "$W/vault/Claude-Sessions/a.plist"
  JENV="DOTFILES_VAULT_DIR=$W/vault" jtool scan-vault >/dev/null 2>&1; [ $? -eq 1 ]'

hostenv() { # hostenv <W>: ssh aliases with and without a digit or hyphen
  printf 'Host mediashelf\n  HostName example.invalid\nHost my-mac-mini\nHost github.com\n' >"$1/home/.ssh/config"
}
t "I7" "a plain-word ssh alias does not block prose; a hyphenated one does, and only its masked form is printed" '
  newrepo; hostenv "$W"; gstage "$W" a.txt "put the files on the mediashelf tonight"
  out=$(guard 2>&1); rc=$?
  bad=; [ "$rc" -eq 0 ] && [ -z "$out" ] || bad=1
  gstage "$W" b.txt "then ssh my-mac-mini quickly"
  out=$(guard 2>&1); rc=$?
  [ -z "$bad" ] && [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: b.txt:1: .*host name: my\*\*\*")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "my-mac-mini" -e "quickly")" -eq 0 ]'
t "I8" "a plain-word entry in the never-send list always blocks, shown masked" '
  newrepo; hostenv "$W"; printf "mediashelf\n" >"$W/priv/jev/never-send.list"; gstage "$W" a.txt "put the files on the mediashelf tonight"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.txt:1: .*never-send list: me\*\*\*")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "mediashelf" -e "tonight")" -eq 0 ]'
t "I9" "no block message prints the offending line: home path, address and email show a masked shape" '
  newrepo; gstage "$W" a.txt "cd /$(printf Users)/jdoe/secretproj and box $IP_PRIV mail jane.roe@$(printf widgets).io"
  out=$(guard 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.txt:1:")" -eq 3 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "jdoe" -e "secretproj" -e "$IP_PRIV" -e "jane.roe" -e "widgets")" -eq 0 ]'
t "I10" "a locked keychain warns once per run that the own-secret check is skipped, and does not fail the commit" '
  newrepo; stub_locked_keychain "$W"; cp "$W/repo/profiles/local.zsh" "$W/r/profiles/local.zsh"
  gstage "$W" a.txt "we shipped an ordinary line" ; gstage "$W" b.txt "another ordinary line of prose"
  out=$(JENV="TYPESAFE_API_KEY=k1" guard 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "own-secret check skipped: keychain locked (security exit 36)")" -eq 1 ]'
t "I11" "the same warning, once, from scans and from redaction inside jev_ask" '
  W=$(sandbox); mkenv "$W"; stub_locked_keychain "$W"; mkdir -p "$W/tree"; printf "fine\n" >"$W/tree/a.txt"; printf "fine\n" >"$W/tree/b.txt"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  bad=; [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "own-secret check skipped")" -eq 1 ] || bad=1
  printf "x\n" >"$W/state.txt"
  out2=$(JENV="TYPESAFE_API_KEY=k1" jrun "jev_init; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_cleanup" 2>&1)
  [ -z "$bad" ] && [ "$(printf "%s\n" "$out2" | grep -c "own-secret check skipped: keychain locked")" -eq 1 ]'
t "I12" "docs record the in-memory grep -F match and why it replaces SHA-256 hashes" '
  [ "$(grep -c "grep -F -f <(printf" docs/agents/jev.md)" -ge 1 ] && [ "$(grep -ci "sha-256" docs/agents/jev.md)" -ge 1 ]'

#############################################################################
section "J -- Task 12: own-secret loading, plist data, temp cleanup, host names, log"
#############################################################################

# stub_pem_secret <W>: dotfiles.pem_key holds a PEM-armoured multi-line value;
# every other item is not found (exit 44, like the real tool).
# The armor lines are assembled at run time so this file holds no PEM header.
PEM_BEGIN="-----BEGIN PRIV""ATE KEY-----"
PEM_END="-----END PRIV""ATE KEY-----"
stub_pem_secret() {
  cat >"$1/stubs/security" <<STUB
#!/bin/sh
case "\$*" in
  *dotfiles.pem_key*) printf '%s\n' '$PEM_BEGIN' 'MIIEvQIBADANBgkqhki' '----------------' '$PEM_END' ;;
  *) exit 44 ;;
esac
STUB
  chmod +x "$1/stubs/security"
  printf 'pem_key() { dotfiles-secrets get pem_key; }\n' >"$1/repo/profiles/local.zsh"
}

t "J1" "a keychain item that does not exist yet (a fresh Mac) is silent: nothing to compare" '
  W=$(sandbox); mkenv "$W"; printf "openai_key() { dotfiles-secrets get openai_api_key; }\n" >"$W/repo/profiles/local.zsh"
  printf "x\n" >"$W/state.txt"
  out=$(jrun "jev_load_secrets; jev_own_secret_lines state.txt" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]'
t "J2" "a real keychain failure warns, and says whether it is locked or another error" '
  W=$(sandbox); mkenv "$W"; stub_locked_keychain "$W"
  o1=$(jrun "jev_load_secrets" 2>&1)
  printf "#!/bin/sh\nexit 1\n" >"$W/stubs/security"
  o2=$(jrun "jev_load_secrets" 2>&1)
  [ "$(printf "%s\n" "$o1" | grep -c "own-secret check skipped: keychain locked (security exit 36)")" -eq 1 ] &&
  [ "$(printf "%s\n" "$o2" | grep -c "own-secret check skipped: keychain error (security exit 1)")" -eq 1 ]'
t "J3" "PEM armor and other structural lines of a multi-line secret are not own-secret patterns" '
  W=$(sandbox); mkenv "$W"; stub_pem_secret "$W"
  printf "%s\n" "$PEM_BEGIN" "public notes" "$PEM_END" "----------------" "line MIIEvQIBADANBgkqhki here" >"$W/f.txt"
  out=$(jrun "jev_own_secret_lines f.txt" 2>&1)
  [ "$out" = 5 ]'
t "J4" "a scan killed while it converts a plist leaves no temporary directory behind" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree" "$W/tmp"; printf "\000\001bin" >"$W/tree/a.plist"
  printf "#!/bin/sh\nprintf \"%%s %%s\" \"\$PPID\" \"\$\$\" >\"\$FAKE_PLUTIL_OUT\"\nexec sleep 20\n" >"$W/stubs/plutil"; chmod +x "$W/stubs/plutil"
  JENV="TMPDIR=$W/tmp FAKE_PLUTIL_OUT=$W/plutil.out" jtool scan-tree "$W/tree" >/dev/null 2>&1 &
  bg=$!
  n=0; while [ "$n" -lt 100 ] && [ ! -s "$W/plutil.out" ]; do sleep 0.1; n=$((n + 1)); done
  read -r sp cp <"$W/plutil.out"
  kill -TERM "$sp" 2>/dev/null; kill -TERM "$cp" 2>/dev/null; wait "$bg" 2>/dev/null
  [ -n "$sp" ] && [ -z "$(ls -A "$W/tmp")" ]'
# mkdataplist <file> <text>: a BINARY plist whose <data> element holds <text>.
mkdataplist() {
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>k</key><data>%s</data></dict></plist>' \
    "$(printf '%s' "$2" | base64 | tr -d '\n')" >"$1.xml"
  plutil -convert binary1 -o "$1" "$1.xml" && command rm -f "$1.xml"
}
tp "J5" "a plist <data> value is decoded: an own secret inside it is found, and neither it nor its base64 is printed" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"; mkdir -p "$W/tree"
  mkdataplist "$W/tree/a.plist" "prefix-bytes $OWN and more"
  mkdataplist "$W/tree/b.plist" "nothing of interest here"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK a.plist:[0-9]*: contains the value of one of your own Keychain")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "b.plist")" -eq 0 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "$OWN" -e "$(printf "%s" "$OWN" | base64 | cut -c1-12)")" -eq 0 ]'
t "J6" "a multi-word computer name is a deterministic block; a blank one is ignored, not a three-space pattern" '
  newrepo; gstage "$W" a.txt "notes about frobnitz mini and its disk"
  out=$(JENV="STUB_LOCALHOST=plainhost" T_COMPUTER="Frobnitz Mini" guard 2>&1); rc=$?
  bad=; [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK privacy: a.txt:1: .*host name: fr\*\*\*")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c -e "frobnitz" -e "disk")" -eq 0 ] || bad=1
  newrepo; gstage "$W" b.txt "a line   with   wide   spacing"
  out2=$(JENV="STUB_LOCALHOST=plainhost" T_COMPUTER="   " guard 2>&1); rc2=$?
  [ -z "$bad" ] && [ "$rc2" -eq 0 ] && [ -z "$out2" ]'
t "J7" "the owners secrets are read from the keychain once per run, not once per request" '
  W=$(sandbox); mkenv "$W"; redact_env "$W"; printf "x\n" >"$W/state.txt"
  JENV="TYPESAFE_API_KEY=k1" jrun "jev_init; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_ask privacy state.txt '"'"'$Q'"'"' >/dev/null; jev_cleanup"
  [ "$(calls)" -eq 3 ] && [ "$(grep -c "dotfiles.openai_api_key" "$W/sec/calls.log")" -eq 1 ]'
t "J8" "shadow mode with no key spawns no background job on a commit" '
  newrepo; T_SYNC=""; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  out=$(guard 2>&1); rc=$?
  sleep 1
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -e "$(LOGF)" ]'
t "J9" "the log stores the confidence the verdict used: Jevs own when given, the derived one when not" '
  newrepo; gstage "$W" a.txt "we shipped the Acme onboarding flow for the client"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-noconf.json" guard >/dev/null 2>&1
  a=$(tail -n 1 "$(LOGF)")
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-high.json" guard >/dev/null 2>&1
  b=$(tail -n 1 "$(LOGF)")
  [ "$(printf "%s" "$a" | jq -r .answers.reveals.confidence)" = "0.93" ] && [ "$(printf "%s" "$a" | jq -r .answers.reveals.confidence_derived)" = true ] &&
  [ "$(printf "%s" "$b" | jq -r .answers.reveals.confidence)" = "0.91" ] && [ "$(printf "%s" "$b" | jq -r .answers.reveals.confidence_derived)" = null ]'
t "J10" "a plutil-dependent test is skipped visibly, not passed, when plutil is absent" '
  o=$(PATH=/nonexistent; tp J10-in "needs plutil" false); [ "$(printf "%s\n" "$o" | grep -c "SKIP.*J10-in")" -eq 1 ] &&
  o2=$(tp J10-in "runs when present" true); [ "$(printf "%s\n" "$o2" | grep -c "✓.*runs when present")" -eq 1 ]'

t "J11" "every consult path loads the owners secrets once, in the main shell: two hunks, one keychain read" '
  newrepo; redact_env "$W"; command cp "$W/repo/profiles/local.zsh" "$W/r/profiles/local.zsh"
  gstage "$W" .githooks/pre-commit "an ordinary line of prose in the first exempt file"
  gstage "$W" tests/fixtures/make-secrets.sh "an ordinary line of prose in the second exempt file"
  JENV="TYPESAFE_API_KEY=k1" guard >/dev/null 2>&1
  [ "$(calls)" -eq 2 ] && [ "$(grep -c "dotfiles.openai_api_key" "$W/sec/calls.log")" -eq 1 ]'

t "J12" "replay reads the owners secrets once for all cases, not once per question" '
  W=$(sandbox); mkenv "$W"; mkreplay "$W"; redact_env "$W"
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV_REPLAY_DIR=$W/replay" jtool replay privacy >/dev/null 2>&1
  [ "$(calls)" -eq 4 ] && [ "$(grep -c "dotfiles.openai_api_key" "$W/sec/calls.log")" -eq 1 ]'

#############################################################################
section "K -- Task 13: drift that notices itself (dotfiles jev drift)"
#############################################################################

# Three undeclared packages as the sync facts feed them: key<TAB>facts.
DRIFT3=$(printf 'brew:jq\tkind=brew formula; desc=Lightweight JSON processor; dependency=no; first seen 2026-09-01\ncask:slack\tkind=cask; desc=Team chat; dependency=no; first seen 2026-09-20\nbrew:libfoo\tkind=brew formula; desc=A library; dependency=yes; first seen 2026-08-30\n')
# drift <kind> <facts>: dotfiles jev drift with the facts on stdin
drift() { local k="$1"; shift; printf '%s\n' "$1" | jtool drift "$k"; }

t "K1" "shadow mode (the default) asks once, logs a would-have decision, prints nothing and changes nothing" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$DRIFT3" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 1 ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .point)" = drift ] && [ "$(tail -n 1 "$(LOGF)" | jq -r .mode)" = shadow ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action | grep -c "^shadow: would have suggested")" -eq 1 ]'
t "K2" "on mode: one batched request with one choice question per item, suggestions above the thresholds as SUGGEST lines" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$DRIFT3" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 1 ] &&
  [ "$(jq -r ".questions | keys | join(\",\")" "$W/rec/body.log")" = "i1,i2,i3" ] &&
  [ "$(jq -r ".questions.i2.type" "$W/rec/body.log")" = choice ] &&
  [ "$(jq -r ".questions.i1.criteria | keys | join(\",\")" "$W/rec/body.log")" = "ignore,private,public,remove" ] &&
  [ "$(printf "%s\n" "$out" | sed -n 1p)" = "$(printf "SUGGEST\tbrew:jq\tpublic\t0.9\t0.9")" ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST")" -eq 3 ]'
t "K3" "the state carries every item with its facts, numbered to match the questions" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$DRIFT3" >/dev/null 2>&1
  st=$(jq -r .state "$W/rec/body.log")
  [ "$(printf "%s\n" "$st" | grep -c "^i1: brew:jq .*Lightweight JSON processor")" -eq 1 ] &&
  [ "$(printf "%s\n" "$st" | grep -c "^i3: brew:libfoo .*dependency=yes")" -eq 1 ]'
t "K4" "a probability below the warn threshold is not offered" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift-low.json" drift pkg "$DRIFT3" 2>&1)
  [ -z "$out" ] && [ "$(calls)" -eq 1 ]'
t "K5" "a remove suggestion needs two agreeing calls: the second, on the removes only, agrees, so it is offered" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  printf "Second opinion\tanswer-drift-second-yes.json\n" >"$W/rec/rules"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift-remove.json" drift pkg "$DRIFT3" 2>&1)
  [ "$(calls)" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST.brew:libfoo.remove")" -eq 1 ] &&
  [ "$(jq -r ".questions | keys | join(\",\")" "$W/rec/body.log" | sed -n 2p)" = i1 ] &&
  [ "$(jq -r .state "$W/rec/body.log" | sed -n "/Second opinion/,\$p" | grep -c "brew:libfoo")" -ge 1 ] &&
  [ "$(jq -r .state "$W/rec/body.log" | sed -n "/Second opinion/,\$p" | grep -c "brew:jq")" -eq 0 ]'
t "K6" "a second call that disagrees drops the remove suggestion; the other suggestions stand" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  printf "Second opinion\tanswer-drift-second-no.json\n" >"$W/rec/rules"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift-remove.json" drift pkg "$DRIFT3" 2>&1)
  [ "$(calls)" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "remove")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST")" -eq 2 ]'
t "K7" "a failing second call (5xx) is no agreement: no remove suggestion" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1 JEV_TRIES=1 FAKE_CURL_SEQ=200,503 FAKE_CURL_ANSWER=answer-drift-remove.json" drift pkg "$DRIFT3" 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "remove")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST")" -eq 2 ]'
t "K8" "the options differ per kind: defaults are public/local-only/transient, config dirs capture/ignore" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift defaults "com.example.app|Key	old=1; new=2" >/dev/null 2>&1
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift config "tool	files=3; size=4 KB" >/dev/null 2>&1
  [ "$(jq -r ".questions.i1.criteria | keys | join(\",\")" "$W/rec/body.log" | sed -n 1p)" = "local-only,public,transient" ] &&
  [ "$(jq -r ".questions.i1.criteria | keys | join(\",\")" "$W/rec/body.log" | sed -n 2p)" = "capture,ignore" ]'
t "K9" "an unknown kind is a usage error and asks nothing" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1" drift bogus "$DRIFT3" 2>&1); rc=$?
  [ "$rc" -eq 2 ] && [ "$(calls)" -eq 0 ]'
t "K10" "off is exit 0, no key is exit 3 (a failed request); neither asks nor prints" '
  W=$(sandbox); mkenv "$W"; setmode drift=off
  o1=$(JENV="TYPESAFE_API_KEY=k1" drift pkg "$DRIFT3" 2>&1); r1=$?
  setmode drift=on
  o2=$(drift pkg "$DRIFT3" 2>&1); r2=$?
  [ "$r1" -eq 0 ] && [ -z "$o1" ] && [ "$r2" -eq 3 ] && [ -z "$o2" ] && [ "$(calls)" -eq 0 ]'
t "K11" "a failed request (timeout) prints nothing and exits 3, which sync reads as stop asking" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_TIMEOUT=1" drift pkg "$DRIFT3" 2>&1); rc=$?
  [ "$rc" -eq 3 ] && [ -z "$out" ]'
t "K12" "nothing leaves the Mac that is on the never-send list: a private host name in the facts is a placeholder" '
  W=$(sandbox); mkenv "$W"; setmode drift=on; printf "Zorblax-Depot\n" >"$W/priv/jev/never-send.list"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$(printf "brew:jq\tdesc=tap of Zorblax-Depot\n")" >/dev/null 2>&1
  [ "$(calls)" -eq 1 ] && [ "$(recorded | grep -c "Zorblax-Depot")" -eq 0 ] && [ "$(jq -r .state "$W/rec/body.log" | grep -c "NEVER-SEND")" -eq 1 ]'
t "K13" "the batch is capped (JEV_DRIFT_MAX_ITEMS): more items than that are not sent" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  many=$(i=0; while [ "$i" -lt 12 ]; do i=$((i + 1)); printf "brew:p%s\tdesc=x\n" "$i"; done)
  JENV="TYPESAFE_API_KEY=k1 JEV_DRIFT_MAX_ITEMS=5 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$many" >/dev/null 2>&1
  [ "$(calls)" -eq 1 ] && [ "$(jq -r ".questions | length" "$W/rec/body.log")" -eq 5 ]'
t "K14" "the log holds counts and ids only: no item name or fact" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" drift pkg "$DRIFT3" >/dev/null 2>&1
  [ "$(grep -c "jq\|slack\|libfoo\|Lightweight" "$(LOGF)")" -eq 0 ] && [ "$(tail -n 1 "$(LOGF)" | jq -r .answers.i1.choice)" = public ]'
t "K15" "status lists the drift point, shadow by default" '
  W=$(sandbox); mkenv "$W"
  out=$(jtool status 2>&1); [ "$(printf "%s\n" "$out" | grep -c "drift  *shadow")" -eq 1 ]'
t "K16" "an empty facts feed asks nothing" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1" jtool drift pkg </dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 0 ]'
t "K17" "shadow mode does not make the second remove call: nothing is acted on" '
  W=$(sandbox); mkenv "$W"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift-remove.json" drift pkg "$DRIFT3" >/dev/null 2>&1
  [ "$(calls)" -eq 1 ]'
t "K18" "a choice that is not one of the offered options is ignored" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift-bogus.json" drift pkg "$DRIFT3" 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "frobnicate")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST")" -eq 1 ]'
t "K19" "a run dir shared by the caller survives: two drift calls, one request cap and fatal marker" '
  W=$(sandbox); mkenv "$W"; setmode drift=on; d=$(mktemp -d "$W/jev.XXXXXX"); printf 0 >"$d/count"
  JENV="TYPESAFE_API_KEY=k1 JEV_RUN_DIR=$d FAKE_CURL_SEQ=401" drift pkg "$DRIFT3" >/dev/null 2>&1; r1=$?
  JENV="TYPESAFE_API_KEY=k1 JEV_RUN_DIR=$d FAKE_CURL_SEQ=401" drift config "x	y" >/dev/null 2>&1; r2=$?
  [ -d "$d" ] && [ "$(calls)" -eq 1 ] && [ "$r1" -eq 3 ] && [ "$r2" -eq 3 ]'
#############################################################################
section "M -- Task 14: app-backup suggestions (dotfiles jev apps)"
#############################################################################

# Three installed apps mackup supports, as the sync facts feed them: key<TAB>facts.
APPS3=$(printf 'gamma\tpaths=2 (Library/Application Support/Gamma); build=direct; sandbox container=no\ndelta\tpaths=1 (Library/Preferences/com.example.delta.plist); build=Setapp; sandbox container=no\nepsilon\tpaths=1 (Library/Preferences/com.example.epsilon.plist); build=App Store; sandbox container=yes\n')
apps() { printf '%s\n' "$1" | jtool apps; }

t "M1" "shadow mode (the default) asks once, logs a would-have decision, prints nothing" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps.json" apps "$APPS3" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(calls)" -eq 1 ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .point)" = apps ] && [ "$(tail -n 1 "$(LOGF)" | jq -r .mode)" = shadow ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action | grep -c "^shadow: would have suggested")" -eq 1 ]'
t "M2" "on: prints SUGGEST key, choice, p, confidence for each item at or above the warn line" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps.json" apps "$APPS3" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST")" -eq 2 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST	gamma	backup	0.9	0.9$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST	delta	own-sync	")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c epsilon)" -eq 0 ]'
t "M3" "the request offers exactly backup, own-sync and not-worth-it, one question per app, in one request" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps.json" apps "$APPS3" >/dev/null 2>&1
  [ "$(calls)" -eq 1 ] && [ "$(jq -r ".questions | length" "$W/rec/body.log")" -eq 3 ] &&
  [ "$(jq -r ".questions.i1.criteria | keys | join(\",\")" "$W/rec/body.log")" = "backup,not-worth-it,own-sync" ] &&
  [ "$(jq -r ".questions.i1.type" "$W/rec/body.log")" = choice ]'
t "M4" "low probabilities offer nothing" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps-low.json" apps "$APPS3" 2>&1)
  [ -z "$out" ]'
t "M5" "a choice that is not one of the three is ignored" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps-bogus.json" apps "$APPS3" 2>&1)
  [ "$(printf "%s\n" "$out" | grep -c "frobnicate\|public")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "^SUGGEST	epsilon	backup")" -eq 1 ]'
t "M6" "a failed request exits 3 so the caller stops asking" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_TIMEOUT=1" apps "$APPS3" >/dev/null 2>&1; r1=$?
  JENV="" apps "$APPS3" >/dev/null 2>&1; r2=$?
  [ "$r1" -eq 3 ] && [ "$r2" -eq 3 ]'
t "M7" "off (the point or the master switch): no request, exit 0" '
  W=$(sandbox); mkenv "$W"; setmode apps=off
  JENV="TYPESAFE_API_KEY=k1" apps "$APPS3" >/dev/null 2>&1; r1=$?
  setmode apps=on
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV=off" apps "$APPS3" >/dev/null 2>&1; r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$(calls)" -eq 0 ]'
t "M8" "the never-send list is redacted from the facts before they leave" '
  W=$(sandbox); mkenv "$W"; setmode apps=on; printf "Zorblax-Depot\n" >"$W/priv/jev/never-send.list"
  JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps.json" apps "$(printf "gamma\tpaths=1 (Library/Zorblax-Depot/x); build=direct\n")" >/dev/null 2>&1
  [ "$(calls)" -eq 1 ] && [ "$(grep -c "Zorblax-Depot" "$W/rec/body.log")" -eq 0 ]'
t "M9" "JEV_APPS_MAX_ITEMS caps the items sent, and nothing is asked for an empty feed" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  many=$(i=1; while [ "$i" -le 9 ]; do printf "app%s\tpaths=1; build=direct\n" "$i"; i=$((i + 1)); done)
  JENV="TYPESAFE_API_KEY=k1 JEV_APPS_MAX_ITEMS=4 FAKE_CURL_ANSWER=answer-apps.json" apps "$many" >/dev/null 2>&1
  n=$(jq -r ".questions | length" "$W/rec/body.log")
  JENV="TYPESAFE_API_KEY=k1" jtool apps </dev/null >/dev/null 2>&1
  [ "$n" -eq 4 ] && [ "$(calls)" -eq 1 ]'
t "M10" "status lists the apps point, shadow by default" '
  W=$(sandbox); mkenv "$W"; out=$(jtool status 2>&1); [ "$(printf "%s\n" "$out" | grep -c "apps  *shadow")" -eq 1 ]'
t "M11" "the API key never reaches argv or the log" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  JENV="TYPESAFE_API_KEY=k-secret-77 FAKE_CURL_ANSWER=answer-apps.json" apps "$APPS3" >/dev/null 2>&1
  [ "$(cat "$W/rec/argv.log" "$(LOGF)" | grep -c "k-secret-77")" -eq 0 ] && [ "$(grep -c "k-secret-77" "$W/rec/stdin.log")" -ge 1 ]'


#############################################################################
section "L -- skip gate for the daily jobs, replay cases for drift/apps/skip"
#############################################################################
FACTS3=$(printf 'upstream commits since last run: 0\nallowlisted app prefs changed since the last snapshot: 0 files\n')
# skipg <job> [args]: dotfiles jev skip with the facts on stdin
skipg() { printf '%s\n' "$FACTS3" | jtool skip "$@"; }
streakf() { printf '%s/state/dotfiles/skip-%s.streak' "$W" "$1"; }

t "L1" "shadow (the default): asks once, logs would-have-skipped, prints RUN, resets the streak" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" skipg sync 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | sed -n 1p | cut -c1-3)" = RUN ] && [ "$(calls)" -eq 1 ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .point)" = skip ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action | grep -c "^shadow: would have skipped")" -eq 1 ]'
t "L2" "on: a low P(useful) skips, prints SKIP, logs it and counts the streak" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" skipg sync 2>&1)
  [ "$(printf "%s\n" "$out" | sed -n 1p | cut -c1-4)" = SKIP ] && [ "$(cat "$(streakf sync)")" = 1 ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action | grep -c "^skipped")" -eq 1 ]'
t "L3" "on: a P(useful) of 0.5 or more runs, and only strictly below 0.2 skips" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  o1=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-high.json" skipg sync 2>&1)
  o2=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-edge.json" skipg sync 2>&1)
  [ "$(printf "%s\n" "$o1" | cut -c1-3)" = RUN ] && [ "$(printf "%s\n" "$o2" | cut -c1-3)" = RUN ]'
t "L4" "never more than 3 skips in a row: the fourth run is forced, with no request, and resets" '
  W=$(sandbox); mkenv "$W"; setmode skip=on; r=""
  for i in 1 2 3 4 5; do
    o=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" skipg sync 2>&1); r="$r$(printf "%s\n" "$o" | cut -c1-3)"
    [ "$i" -eq 3 ] && c3=$(calls)
  done
  [ "$r" = "SKISKISKIRUNSKI" ] && [ "$c3" -eq 3 ] && [ "$(calls)" -eq 4 ] &&
  [ "$(jq -r "select(.action | test(\"cap\")) | .action" "$(LOGF)" | grep -c .)" -eq 1 ]'
t "L5" "a deterministic fact of work runs without asking, whatever the mode, and is logged" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  out=$(JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" skipg sync --work "upstream touches Brewfile" 2>&1)
  [ "$(printf "%s\n" "$out" | cut -c1-3)" = RUN ] && [ "$(calls)" -eq 0 ] &&
  [ "$(tail -n 1 "$(LOGF)" | jq -r .action | grep -c "deterministic work: upstream touches Brewfile")" -eq 1 ]'
t "L6" "a deterministic fact resets the skip streak" '
  W=$(sandbox); mkenv "$W"; setmode skip=on; mkdir -p "$W/state/dotfiles"; printf 2 >"$(streakf sync)"
  skipg sync --work "prefs changed" >/dev/null 2>&1; [ "$(cat "$(streakf sync)")" = 0 ]'
t "L7" "any Jev failure runs the job: timeout, 5xx, 401, no key" '
  W=$(sandbox); mkenv "$W"; setmode skip=on; ok=1
  for e in "FAKE_CURL_TIMEOUT=1" "JEV_TRIES=1 FAKE_CURL_SEQ=503" "FAKE_CURL_SEQ=401"; do
    o=$(JENV="TYPESAFE_API_KEY=k1 $e" skipg sync 2>&1); [ "$(printf "%s\n" "$o" | cut -c1-3)" = RUN ] || ok=0
  done
  o=$(skipg sync 2>&1); [ "$(printf "%s\n" "$o" | cut -c1-3)" = RUN ] || ok=0
  [ "$ok" -eq 1 ] && [ "$(cat "$(streakf sync)")" = 0 ]'
t "L8" "master switch off: RUN, no request" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  out=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV=off" skipg sync 2>&1)
  [ "$(printf "%s\n" "$out" | cut -c1-3)" = RUN ] && [ "$(calls)" -eq 0 ]'
t "L9" "the facts go as ONE noul request, with hours since the last run, and the scheduled timeout applies" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  JENV="TYPESAFE_API_KEY=k1 JEV_SCHEDULED=1 FAKE_CURL_ANSWER=answer-skip-low.json" skipg apps >/dev/null 2>&1
  st=$(jq -r .state "$W/rec/body.log")
  [ "$(calls)" -eq 1 ] && [ "$(jq -r ".questions | keys | join(\",\")" "$W/rec/body.log")" = useful ] &&
  [ "$(jq -r .questions.useful.type "$W/rec/body.log")" = noul ] &&
  [ "$(printf "%s\n" "$st" | grep -c "hours since last run")" -eq 1 ] &&
  [ "$(printf "%s\n" "$st" | grep -c "allowlisted app prefs changed")" -eq 1 ] &&
  [ "$(grep -c -- "--max-time 10" "$W/rec/argv.log")" -eq 1 ]'
t "L10" "the facts are capped, and the never-send list applies to them" '
  W=$(sandbox); mkenv "$W"; setmode skip=on; printf "Zorblax-Depot\n" >"$W/priv/jev/never-send.list"
  big=$(i=0; while [ "$i" -lt 400 ]; do i=$((i + 1)); printf "paths touched: Zorblax-Depot/some/long/path/number/%s\n" "$i"; done)
  printf "%s\n" "$big" | JENV="TYPESAFE_API_KEY=k1 JEV_SKIP_MAX_FACTS=500 FAKE_CURL_ANSWER=answer-skip-low.json" jtool skip sync >/dev/null 2>&1
  [ "$(calls)" -eq 1 ] && [ "$(jq -r .state "$W/rec/body.log" | wc -c | tr -d " ")" -lt 1400 ] && [ "$(recorded | grep -c "Zorblax-Depot")" -eq 0 ]'
t "L11" "skip rejects an unknown job, and the point is listed in status" '
  W=$(sandbox); mkenv "$W"
  out=$(jtool skip bogus </dev/null 2>&1); rc=$?
  [ "$rc" -eq 2 ] && [ "$(jtool status 2>&1 | grep -c "skip  *shadow")" -eq 1 ]'
t "L12" "the decision log holds ids and numbers, never the facts" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  printf "paths touched: Brewfile-secret-marker-xyz\n" | JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" jtool skip sync >/dev/null 2>&1
  [ "$(grep -c "secret-marker-xyz" "$(LOGF)")" -eq 0 ] && [ "$(tail -n 1 "$(LOGF)" | jq -r .answers.useful.noul)" = 0.05 ]'

t "L13" "replay cases for skip, drift and apps are labelled, public-safe and cover every label" '
  ok=1
  for p in skip drift apps; do
    f=tests/fixtures/jev/replay/$p.jsonl
    [ -f "$f" ] || { ok=0; continue; }
    [ "$(jq -r "select(.id and .label != null and (.state | type == \"string\")) | .id" "$f" | grep -c .)" -eq "$(grep -c . "$f")" ] || ok=0
  done
  [ "$(jq -r "select(.label == true) | .id" tests/fixtures/jev/replay/skip.jsonl | grep -c .)" -ge 5 ] || ok=0
  [ "$(jq -r "select(.label == false) | .id" tests/fixtures/jev/replay/skip.jsonl | grep -c .)" -ge 5 ] || ok=0
  [ "$(jq -r .label tests/fixtures/jev/replay/apps.jsonl | sort -u | tr "\n" " ")" = "backup not-worth-it own-sync " ] || ok=0
  [ "$(jq -r .kind tests/fixtures/jev/replay/drift.jsonl | sort -u | tr "\n" " ")" = "config defaults pkg " ] || ok=0
  [ "$(cat tests/fixtures/jev/replay/*.jsonl | grep -Ec -f <(bash .githooks/pre-commit --print-secret-patterns))" -eq 0 ] &&
  [ "$(cat tests/fixtures/jev/replay/skip.jsonl tests/fixtures/jev/replay/drift.jsonl tests/fixtures/jev/replay/apps.jsonl | grep -c "/Users/")" -eq 0 ] && [ "$ok" -eq 1 ]'
t "L14" "replay skip prints precision and recall per threshold (fake API)" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR FAKE_CURL_ANSWER=answer-skip-low.json" jtool replay skip 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(calls)" -eq 12 ] && [ "$(printf "%s\n" "$out" | grep -c "precision=")" -ge 6 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "P(useful) < 0.2")" -ge 1 ]'
t "L15" "replay drift and apps score the chosen option per case (fake API)" '
  W=$(sandbox); mkenv "$W"
  o1=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR FAKE_CURL_ANSWER=answer-apps.json" jtool replay apps 2>&1); r1=$?
  c1=$(calls)
  o2=$(JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR FAKE_CURL_ANSWER=answer-drift.json" jtool replay drift 2>&1); r2=$?
  [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && [ "$c1" -eq 9 ] && [ "$(calls)" -eq 21 ] &&
  [ "$(printf "%s\n" "$o1" | grep -c "accuracy=")" -ge 4 ] && [ "$(printf "%s\n" "$o2" | grep -c "accuracy=")" -ge 4 ] &&
  true'
t "L16" "replay for the choice points sends the point own options as the criteria" '
  W=$(sandbox); mkenv "$W"
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_DIR=$ROOT_DIR FAKE_CURL_ANSWER=answer-apps.json" jtool replay apps >/dev/null 2>&1
  [ "$(jq -r ".questions.i1.criteria | keys | join(\",\")" "$W/rec/body.log" | sort -u)" = "backup,not-worth-it,own-sync" ]'
t "L17" "replay without a key still refuses for the new points" '
  W=$(sandbox); mkenv "$W"
  out=$(JENV="DOTFILES_DIR=$ROOT_DIR" jtool replay skip 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(calls)" -eq 0 ]'

# sync and apps wiring: a stub dotfiles-jev that says what the gate said
t "L18" "dotfiles-sync gates only the scheduled run, before any git work, and skips when told SKIP" '
  [ "$(code_of bin/dotfiles-sync | grep -c "skip_gate")" -ge 2 ] &&
  [ "$(_first_line "skip_gate || " bin/dotfiles-sync)" -lt "$(_first_line "repo_sync public" bin/dotfiles-sync)" ] &&
  [ "$(code_of bin/dotfiles-sync | grep -c "JEV_BIN\" skip sync")" -ge 1 ]'
t "L19" "dotfiles-apps gates only the scheduled backup, before staging" '
  [ "$(code_of bin/dotfiles-apps | grep -c "skip_gate")" -ge 2 ] &&
  [ "$(_first_line "skip_gate" bin/dotfiles-apps)" -lt "$(_first_line "take_lock || " bin/dotfiles-apps)" ] &&
  [ "$(code_of bin/dotfiles-apps | grep -c "\" skip apps")" -ge 1 ]'
t "L20" "docs/agents/jev.md has a section each for the drift, app-choice and skip points" '
  d=docs/agents/jev.md
  (for w in "## Drift" "## App-choice" "## Skip gate"; do [ "$(grep -c -- "^$w" "$d")" -eq 1 ] || exit 1; done) &&
  [ "$(sed -n "/^## Skip gate/,\$p" "$d" | grep -c "0.2")" -ge 1 ] && [ "$(sed -n "/^## Skip gate/,\$p" "$d" | grep -c "3 ")" -ge 1 ] &&
  [ "$(grep -c "replay skip\|replay drift\|replay apps" "$d")" -ge 1 ]'

#############################################################################
section "N -- final fixes: scan-tree fails closed, skip on a TTY, replay measures production"
#############################################################################

# gitleaks_stub <W> <exit code> [report json]: a gitleaks that writes the given
# report to the -r path and exits with the given code.
gitleaks_stub() {
  printf '%s' "${3:-}" >"$1/gl-report.json"
  printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -r ] && rep="$2"; shift; done\ncat "%s/gl-report.json" >"$rep"\nexit %s\n' "$1" "$2" >"$1/stubs/gitleaks"
  chmod +x "$1/stubs/gitleaks"
}

t "N1" "scan-tree refuses (exit 2) when a file could not be read, and says so" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "x\n" >"$W/tree/locked.txt"; printf "y\n" >"$W/tree/ok.txt"; chmod 000 "$W/tree/locked.txt"
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?; chmod 600 "$W/tree/locked.txt"
  [ "$rc" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "not scanned")" -ge 1 ]'
t "N2" "scan-tree refuses (exit 2) when gitleaks crashes, even with an empty report" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "clean\n" >"$W/tree/ok.txt"; gitleaks_stub "$W" 2
  out=$(jtool scan-tree "$W/tree" 2>&1); rc=$?
  [ "$rc" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "gitleaks")" -ge 1 ]'
t "N3" "scan-tree with a gitleaks that exits 0 (clean) or 1 (findings) still works" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "clean\n" >"$W/tree/ok.txt"; gitleaks_stub "$W" 0 "[]"
  jtool scan-tree "$W/tree" >/dev/null 2>&1; r0=$?
  gitleaks_stub "$W" 1 "[{\"File\":\"$W/tree/ok.txt\",\"StartLine\":1}]"
  out=$(jtool scan-tree "$W/tree" 2>&1); r1=$?
  [ "$r0" -eq 0 ] && [ "$r1" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "BLOCK ok.txt:1: flagged by gitleaks")" -eq 1 ]'
t "N4" "scan-tree refuses (exit 2) when the secret-pattern list is empty or fails to load" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/tree"; printf "clean\n" >"$W/tree/ok.txt"
  printf "#!/bin/sh\nexit 0\n" >"$W/empty-hook"; printf "#!/bin/sh\nexit 3\n" >"$W/bad-hook"
  JENV="JEV_HOOK=$W/empty-hook" jtool scan-tree "$W/tree" >/dev/null 2>&1; r1=$?
  out=$(JENV="JEV_HOOK=$W/bad-hook" jtool scan-tree "$W/tree" 2>&1); r2=$?
  [ "$r1" -eq 2 ] && [ "$r2" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "pattern")" -ge 1 ] && [ "$(calls)" -eq 0 ]'
t "N5" "scan-vault: a directory that cannot be listed is exit 2 with a message, not no credentials found" '
  W=$(sandbox); mkenv "$W"; mkdir -p "$W/vault/Claude-Sessions/locked"; printf "fine\n" >"$W/vault/Claude-Sessions/s.md"; chmod 000 "$W/vault/Claude-Sessions/locked"
  out=$(JENV="DOTFILES_VAULT_DIR=$W/vault" jtool scan-vault 2>&1); rc=$?; chmod 700 "$W/vault/Claude-Sessions/locked"
  [ "$rc" -eq 2 ] && [ "$(printf "%s\n" "$out" | grep -c "no credentials found")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "could not list")" -eq 1 ]'
# ttyrun <cmd...>: run a command with a pseudo-terminal as stdin and stdout
# (script(1) needs a real terminal of its own; this does not).
ttyrun() {
  python3 -c '
import os, sys
pid, fd = os.forkpty()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
while True:
    try:
        b = os.read(fd, 4096)
    except OSError:
        break
    if not b:
        break
    out += b
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(os.waitpid(pid, 0)[1] >> 8)' "$@"
}
# Bash 3.2 (the system one) leaves a bare `local x` set to empty, so this bug
# only shows under a newer bash; the test uses one when installed.
t "N6" "skip with stdin on a terminal does not abort on an unset variable" '
  W=$(sandbox); mkenv "$W"; export W ROOT_DIR FIXD; export -f jtool
  [ -x /opt/homebrew/bin/bash ] && export JENV="PATH=$W/stubs:/opt/homebrew/bin:/usr/bin:/bin"
  out=$(ttyrun bash -c "jtool skip sync" 2>&1); rc=$?; unset JENV
  [ "$rc" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "unbound variable")" -eq 0 ] && [ "$(printf "%s\n" "$out" | grep -c "RUN")" -ge 1 ]'

# replay_body <W> <point> <fixture line>: the request body `replay <point>`
# sends for a one-case fixture (the fake curl's recording, truncated first).
replay_body() {
  local w="$1"
  : >"$w/rec/body.log"; mkdir -p "$w/replay"
  printf '%s\n' "$3" >"$w/replay/$2.jsonl"
  JENV="TYPESAFE_API_KEY=k1 DOTFILES_JEV_REPLAY_DIR=$w/replay FAKE_CURL_ANSWER=answer-$2.json" jtool replay "$2" >/dev/null 2>&1
  cat "$w/rec/body.log"
}
t "N7" "replay drift builds the request production builds for the same single item" '
  W=$(sandbox); mkenv "$W"; setmode drift=on
  printf "brew:jq\tkind=brew formula; desc=Lightweight JSON processor; dependency=no\n" | JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-drift.json" jtool drift pkg >/dev/null 2>&1
  prod=$(cat "$W/rec/body.log")
  rep=$(replay_body "$W" drift "{\"id\":\"c1\",\"kind\":\"pkg\",\"label\":\"public\",\"state\":\"brew:jq kind=brew formula; desc=Lightweight JSON processor; dependency=no\"}")
  [ -n "$prod" ] && [ "$prod" = "$rep" ]'
t "N8" "replay apps builds the request production builds for the same single item" '
  W=$(sandbox); mkenv "$W"; setmode apps=on
  printf "gamma\tpaths=2 (Library/Application Support/Gamma); build=direct; sandbox container=no\n" | JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-apps.json" jtool apps >/dev/null 2>&1
  prod=$(cat "$W/rec/body.log")
  rep=$(replay_body "$W" apps "{\"id\":\"c1\",\"label\":\"backup\",\"state\":\"gamma paths=2 (Library/Application Support/Gamma); build=direct; sandbox container=no\"}")
  [ -n "$prod" ] && [ "$prod" = "$rep" ]'
t "N9" "replay skip builds the request production builds for the same facts and hours" '
  W=$(sandbox); mkenv "$W"; setmode skip=on
  printf "upstream commits since last run: 3\n" | JENV="TYPESAFE_API_KEY=k1 FAKE_CURL_ANSWER=answer-skip-low.json" jtool skip sync >/dev/null 2>&1
  prod=$(cat "$W/rec/body.log")
  rep=$(replay_body "$W" skip "{\"id\":\"c1\",\"label\":true,\"job\":\"sync\",\"hours\":\"never run\",\"state\":\"upstream commits since last run: 3\"}")
  [ -n "$prod" ] && [ "$prod" = "$rep" ]'
t "N10" "the shipped skip cases carry hours and job as fields, not inside the state" '
  f=tests/fixtures/jev/replay/skip.jsonl
  [ "$(jq -r "select((.hours | tostring | length) > 0 and (.job == \"sync\" or .job == \"apps\") and (.state | test(\"hours since\") | not)) | .id" "$f" | grep -c .)" -eq "$(grep -c . "$f")" ]'

finish

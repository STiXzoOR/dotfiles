#!/usr/bin/env bash
#
# Emits fake credentials on stdout for the pre-commit secret-detector tests.
#
# Every value is generated at run time from /dev/urandom, so this file itself
# contains no string that matches any of the detector's patterns and nothing
# credential-shaped is ever committed. Only the generator is tracked.
set -u

# rand <count> <tr character class>
# Bounded: never `tr </dev/urandom | head`, which never exits where SIGPIPE is
# ignored (see rand_chars in tests/lib.sh; this file cannot source it).
rand() {
  local out="" rounds=0
  while [ "${#out}" -lt "$1" ]; do
    rounds=$((rounds + 1)); [ "$rounds" -le 1000 ] || return 1
    out="$out$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc "$2")"
  done
  printf '%s' "${out:0:$1}"
}

UPPER='A-Z0-9'
ALNUM='A-Za-z0-9'
ALNUM_='A-Za-z0-9_'
DIGIT='0-9'

printf 'aws_access_key_id = %s%s\n'  'AKIA'          "$(rand 16 "$UPPER")"
printf 'GITHUB_TOKEN=%s%s\n'        'ghp_'          "$(rand 36 "$ALNUM")"
printf 'gh_fine_grained=%s%s\n'     'github_pat_'   "$(rand 62 "$ALNUM_")"
printf 'ANTHROPIC_API_KEY=%s%s\n'   'sk-ant-api03-' "$(rand 40 "$ALNUM")"
printf 'OPENAI_API_KEY=%s%s\n'      'sk-proj-'      "$(rand 40 "$ALNUM")"
printf 'OPENAI_LEGACY_KEY=%s%s\n'   'sk-'           "$(rand 48 "$ALNUM")"
printf 'STRIPE_SECRET=%s%s\n'       'sk_live_'      "$(rand 24 "$ALNUM")"
printf 'GITLAB_TOKEN=%s%s\n'        'glpat-'        "$(rand 20 "$ALNUM")"
printf 'GOOGLE_API_KEY=%s%s\n'      'AIza'          "$(rand 35 "$ALNUM")"
printf 'SLACK_BOT_TOKEN=%s%s-%s-%s\n' 'xoxb-' \
  "$(rand 12 "$DIGIT")" "$(rand 12 "$DIGIT")" "$(rand 24 "$ALNUM")"
printf 'jwt = %s.%s.%s\n' \
  "eyJ$(rand 24 "$ALNUM")" "eyJ$(rand 44 "$ALNUM")" "$(rand 43 "$ALNUM")"
printf -- '-----%s %s %s-----\n' 'BEGIN' 'OPENSSH' 'PRIVATE KEY'
printf '%s\n' "$(rand 64 "$ALNUM")"
printf -- '-----%s %s %s-----\n' 'END' 'OPENSSH' 'PRIVATE KEY'

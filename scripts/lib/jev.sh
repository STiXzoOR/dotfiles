# scripts/lib/jev.sh -- a careful client for TypeSafe's Jev (System One).
#
# Source it. bash 3.2 (macOS /bin/bash), curl, jq. No set -e / set -u: the
# caller decides, and every function returns a status instead of exiting.
#
# Jev takes a state and typed questions and returns typed answers with
# probabilities. Here it is only ever asked narrow judgments about facts the
# caller has already computed in code, every use point (a "point") starts in
# shadow mode (decide and log, change nothing), and a secret never reaches it:
# only the masked shape of a suspect line does. See docs/agents/jev.md.
#
#   jev_ask <point> <state-file> <questions-json>   answers JSON on stdout
#   jev_mode <point>                                 off | shadow | on
#   jev_verdict <point> <p> <confidence>             block | warn | pass
#   jev_log <point> <mode> <action> [answers-json]   one JSON line in jev.jsonl
#   jev_redact <file>                                what would leave the Mac
#   jev_init / jev_cleanup                           per-run request cap, fatal marker
#
# Return codes of jev_ask: 0 ok; 1 failed (timeout, HTTP error, bad reply);
# 2 no key; 3 switched off; 4 request cap reached; 5 fatal (401/403 earlier
# in this run). The caller decides what failing open means for its point.

JEV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JEV_ENDPOINT="https://api.typesafe.ai/v1/systemone"
# Pinned, never jev-latest: the thresholds in docs/agents/jev.md were chosen
# against this version and an alias that moves would silently change them.
JEV_DEFAULT_MODEL="jev-1.13.0"
JEV_MAX_STATE_BYTES="${JEV_MAX_STATE_BYTES:-48000}"

#############################################################################
# Paths and configuration
#############################################################################

jev_private_dir() { printf '%s' "${DOTFILES_PRIVATE_DIR:-$HOME/.dotfiles-private}"; }
jev_conf_file() { printf '%s' "${DOTFILES_JEV_CONFIG:-$(jev_private_dir)/jev/jev.conf}"; }
jev_log_file() { printf '%s/dotfiles/jev.jsonl' "${XDG_STATE_HOME:-$HOME/.local/state}"; }
jev_repo_dir() { printf '%s' "${DOTFILES_DIR:-$(cd "$JEV_LIB_DIR/../.." && pwd)}"; }

# jev_conf_get <key>: the last "key=value" in the config file. Missing file
# or key prints nothing.
jev_conf_get() {
  local f
  f=$(jev_conf_file)
  [ -f "$f" ] || return 0
  awk -F= -v k="$1" '
    /^[[:space:]]*#/ { next }
    { key = $1; gsub(/^[ \t]+|[ \t]+$/, "", key) }
    key == k { v = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); found = v }
    END { if (found != "") print found }' "$f"
}

# jev_mode <point>: DOTFILES_JEV=off beats the config; the default, and the
# fallback for anything unrecognised, is shadow -- never on.
jev_mode() {
  local v
  if [ "${DOTFILES_JEV:-}" = off ]; then
    printf 'off\n'
    return 0
  fi
  v=$(jev_conf_get "$1")
  case "$v" in
    on | off | shadow) printf '%s\n' "$v" ;;
    *) printf 'shadow\n' ;;
  esac
}

# jev_threshold <point> <name> <default>: point.name in the config, then the
# DOTFILES_JEV_<NAME> variable, then the default.
jev_threshold() {
  local v envname
  v=$(jev_conf_get "$1.$2")
  if [ -z "$v" ]; then
    envname="DOTFILES_JEV_$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
    eval "v=\${$envname:-}"
  fi
  printf '%s' "${v:-$3}"
}

# jev_ge <a> <b>: a >= b, as decimals.
jev_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }

# jev_verdict <point> <p> <confidence>: block needs both p and confidence
# high, warn is the middle band (or a high p that is not confident enough).
# Shipped defaults, block 0.85 / confidence 0.8 / warn 0.5, are conservative
# starting points, not calibrated truth: run `dotfiles jev replay`.
jev_verdict() {
  local bp bc wp
  bp=$(jev_threshold "$1" block_p 0.85)
  bc=$(jev_threshold "$1" block_conf 0.8)
  wp=$(jev_threshold "$1" warn_p 0.5)
  if jev_ge "$2" "$bp" && jev_ge "$3" "$bc"; then
    printf 'block\n'
  elif jev_ge "$2" "$wp"; then
    printf 'warn\n'
  else
    printf 'pass\n'
  fi
}

#############################################################################
# Decision log
#############################################################################

jev_now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time() * 1000'
  else
    printf '%d000' "$(date +%s)"
  fi
}

# jev_log <point> <mode> <action> [answers-json]: one JSON line per decision.
# Ids, probabilities and confidence only. Never the state, never a value.
jev_log() {
  local f dir ms answers="${4:-null}"
  f=$(jev_log_file)
  dir=$(dirname "$f")
  ( umask 077; mkdir -p "$dir" ) 2>/dev/null || return 0
  ms="${JEV_LAST_MS:-}"
  [ -n "${JEV_RUN_DIR:-}" ] && [ -f "$JEV_RUN_DIR/last_ms" ] && ms=$(cat "$JEV_RUN_DIR/last_ms")
  [ -n "${JEV_NOLOG:-}" ] && return 0
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg point "$1" --arg mode "$2" \
    --arg action "$3" --arg ms "$ms" --argjson ans "${answers:-null}" '
    { ts: $ts, point: $point, mode: $mode,
      questions: (if $ans == null then [] else ($ans | keys) end),
      answers: (if $ans == null then {} else
        ($ans | map_values(with_entries(select(.key | IN("type", "noul", "choice", "score", "confidence", "confidence_derived"))))) end),
      latency_ms: ($ms | tonumber? // null),
      action: $action }' >>"$f" 2>/dev/null
  return 0
}

# Log once per run per tag: "no key" must not repeat for every hunk.
jev_log_once() { # jev_log_once <tag> <point> <mode> <action>
  if [ -n "${JEV_RUN_DIR:-}" ]; then
    [ -e "$JEV_RUN_DIR/logged.$1" ] && return 0
    : >"$JEV_RUN_DIR/logged.$1"
  fi
  jev_log "$2" "$3" "$4"
}

#############################################################################
# Per-run state: request cap and the fatal marker
#############################################################################

jev_init() {
  [ -n "${JEV_RUN_DIR:-}" ] && [ -d "$JEV_RUN_DIR" ] && return 0
  JEV_RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jev.XXXXXX") || return 1
  export JEV_RUN_DIR
  printf '0' >"$JEV_RUN_DIR/count"
}

jev_cleanup() {
  case "${JEV_RUN_DIR:-}" in
    */jev.*) rm -rf "$JEV_RUN_DIR" ;;
  esac
  unset JEV_RUN_DIR
}

#############################################################################
# Key
#############################################################################

# The key: an exported TYPESAFE_API_KEY, else the dotfiles Keychain item
# (`dotfiles secrets set typesafe_api_key`). Printed for the caller to pipe;
# it must never be put on a command line or logged.
jev_key() {
  local k
  if [ -n "${TYPESAFE_API_KEY:-}" ]; then
    printf '%s' "$TYPESAFE_API_KEY"
    return 0
  fi
  if [ -n "${DOTFILES_KEYCHAIN:-}" ]; then
    k=$(security find-generic-password -s dotfiles -a dotfiles.typesafe_api_key -w "$DOTFILES_KEYCHAIN" 2>/dev/null) || return 1
  else
    k=$(security find-generic-password -s dotfiles -a dotfiles.typesafe_api_key -w 2>/dev/null) || return 1
  fi
  [ -n "$k" ] || return 1
  printf '%s' "$k"
}

#############################################################################
# Secrets: patterns, own values, shapes
#############################################################################

# The credential formats the pre-commit hook already blocks, printed by the
# hook itself so there is one list.
_JEV_PATTERNS=""
# Fails (and prints nothing) when the list is empty or the hook cannot print it,
# so a caller that gates on it can refuse instead of scanning with no patterns.
# JEV_HOOK points at another hook (tests).
jev_secret_patterns() {
  if [ -z "$_JEV_PATTERNS" ]; then
    _JEV_PATTERNS=$(bash "${JEV_HOOK:-$JEV_LIB_DIR/../../.githooks/pre-commit}" --print-secret-patterns) || _JEV_PATTERNS=""
  fi
  [ -n "$_JEV_PATTERNS" ] || return 1
  printf '%s\n' "$_JEV_PATTERNS"
}

# Names of the owner's own Keychain secrets: `dotfiles-secrets get NAME` and
# `-a dotfiles.NAME` in profiles/local.zsh (private, gitignored), plus
# secret-names.list in the private dir.
jev_secret_names() {
  local f
  # DOTFILES_JEV_LOCAL_ZSH names another file (tests, or a profile elsewhere).
  for f in "${DOTFILES_JEV_LOCAL_ZSH:-$(jev_repo_dir)/profiles/local.zsh}" "$(jev_repo_dir)/profiles/local.post.zsh"; do
    [ -f "$f" ] || continue
    sed -n -E 's/.*(dotfiles-secrets|dotfiles secrets)[[:space:]]+get[[:space:]]+([A-Za-z0-9_.-]+).*/\2/p' "$f"
    sed -n -E 's/.*-a[[:space:]]+dotfiles\.([A-Za-z0-9_.-]+).*/\1/p' "$f"
  done
  f="$(jev_private_dir)/jev/secret-names.list"
  [ -f "$f" ] && grep -Ev '^[[:space:]]*(#|$)' "$f"
  return 0
}

# _JEV_SECRETS holds the owner's secret VALUES, in memory only. They are never
# written to disk, never put on a command line and never logged. Matching is
# grep -F against a process-substitution pipe (a /dev/fd path on argv, not
# the values), and a hit is reported by line number, never by content.
_JEV_SECRETS=()
_JEV_SECRETS_LOADED=0
# _jev_warn_once <tag> <message>: one warning on stderr per run (per process
# when there is no run dir).
_JEV_WARNED=""
_jev_warn_once() {
  if [ -n "${JEV_RUN_DIR:-}" ] && [ -d "$JEV_RUN_DIR" ]; then
    [ -e "$JEV_RUN_DIR/warned.$1" ] && return 0
    : >"$JEV_RUN_DIR/warned.$1"
  else
    case " $_JEV_WARNED " in *" $1 "*) return 0 ;; esac
    _JEV_WARNED="$_JEV_WARNED $1"
  fi
  printf 'warning: %s\n' "$2" >&2
}

# _jev_keychain_get <account>: the item's value on stdout, security's exit
# status as the return code (44 is "not found", 36 "keychain locked").
_jev_keychain_get() {
  if [ -n "${DOTFILES_KEYCHAIN:-}" ]; then
    security find-generic-password -s dotfiles -a "$1" -w "$DOTFILES_KEYCHAIN" 2>/dev/null
  else
    security find-generic-password -s dotfiles -a "$1" -w 2>/dev/null
  fi
}

# _jev_structural_line <line>: a fixed line that every value of its kind
# shares (PEM armor, a rule of dashes, Proc-Type/DEK-Info headers). Matching
# it would flag any file that merely holds a public certificate or a note.
_jev_structural_line() {
  case "$1" in
    -----*-----) return 0 ;;
    Proc-Type:* | DEK-Info:*) return 0 ;;
    *[A-Za-z0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Load once per process. Callers that would first load inside a pipeline (a
# subshell whose copy of the array is thrown away) call this before it.
jev_load_secrets() {
  [ "$_JEV_SECRETS_LOADED" -eq 1 ] && return 0
  local name v line rc failcode=0
  _JEV_SECRETS_LOADED=1
  _JEV_SECRETS=()
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    v=$(_jev_keychain_get "dotfiles.$name")
    rc=$?
    if [ "$rc" -ne 0 ]; then
      # No such item is a fresh Mac that has not stored it yet: nothing to
      # compare, and nothing to say. Anything else is a real failure.
      [ "$rc" -eq 44 ] && continue
      if [ "$failcode" -eq 0 ] || [ "$rc" -eq 36 ]; then failcode=$rc; fi
      continue
    fi
    # A multi-line value (a private key, say) is matched line by line, and
    # never by an empty pattern, which would match every line. A line too
    # short to be a secret, or a structural one, would match ordinary text.
    while IFS= read -r line; do
      [ "${#line}" -ge 8 ] || continue
      _jev_structural_line "$line" && continue
      _JEV_SECRETS+=("$line")
    done <<EOF
$v
EOF
  done < <(jev_secret_names | sort -u)
  if [ "$failcode" -eq 36 ]; then
    _jev_warn_once ownsecret "own-secret check skipped: keychain locked (security exit 36)"
  elif [ "$failcode" -ne 0 ]; then
    _jev_warn_once ownsecret "own-secret check skipped: keychain error (security exit $failcode)"
  fi
  return 0
}

# jev_own_secret_lines <file>: numbers of lines that contain one of the owner's
# secret values, one per line. Nothing else about the hit is printed.
jev_own_secret_lines() {
  jev_load_secrets
  [ "${#_JEV_SECRETS[@]}" -gt 0 ] || return 0
  grep -nF -f <(printf '%s\n' "${_JEV_SECRETS[@]}") -- "$1" 2>/dev/null | cut -d: -f1
  return 0
}

# jev_scan <file>: definite / ambiguous secret-shaped lines as TSV (see
# jev-scan.awk). Reads gitleaks too when it is installed. Own-secret hits are
# added by jev_own_secret_lines, which callers combine.
jev_scan() {
  local file="$1" pf forced=","
  pf=$(mktemp "${TMPDIR:-/tmp}/jev-pat.XXXXXX") || return 1
  jev_secret_patterns >"$pf"
  forced=$(_jev_gitleaks_lines "$file")
  awk -v mode=scan -v pf="$pf" -v forced="$forced" -f "$JEV_LIB_DIR/jev-scan.awk" "$file"
  rm -f "$pf"
}

# ",3,7," -- lines gitleaks flags in <file>; "," when none or not installed.
_jev_gitleaks_lines() {
  local rep out
  out=","
  if [ "${JEV_GITLEAKS:-1}" != 0 ] && command -v gitleaks >/dev/null 2>&1; then
    rep=$(mktemp "${TMPDIR:-/tmp}/jev-gl.XXXXXX") || { printf ','; return 0; }
    gitleaks detect --no-git --no-banner --redact -s "$1" -f json -r "$rep" >/dev/null 2>&1
    out=",$(jq -r '.[]?.StartLine' "$rep" 2>/dev/null | sort -un | tr '\n' ',')"
    rm -f "$rep"
    [ "$out" = ",," ] && out=","
  fi
  printf '%s' "$out"
}

#############################################################################
# Redaction: what may leave the Mac
#############################################################################

# The never-send literals, one "placeholder<TAB>literal" per line, longest
# literal first so a longer name is not eaten by a shorter one inside it.
jev_never_send_map() {
  local f h a name
  f="$(jev_private_dir)/jev/never-send.list"
  {
    if [ -f "$f" ]; then
      grep -Ev '^[[:space:]]*(#|$)' "$f" | while IFS= read -r a; do printf '<NEVER-SEND>\t%s\n' "$a"; done
    fi
    # A blank name (only spaces) is no name; a name with spaces is kept whole.
    name=$(printf '%s' "${DOTFILES_COMPUTER_NAME:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$name" ] && printf '<HOST>\t%s\n' "$name"
    name=$(scutil --get LocalHostName 2>/dev/null)
    [ -n "$name" ] && printf '<HOST>\t%s\n' "$name"
    if [ -f "$HOME/.ssh/config" ]; then
      awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) print $i }' "$HOME/.ssh/config" |
        grep -Ev '[*?!]|^(github\.com|gitlab\.com|bitbucket\.org|ssh\.github\.com)$' |
        while IFS= read -r h; do printf '<HOST>\t%s\n' "$h"; done
    fi
    [ -n "${HOME:-}" ] && [ "$HOME" != / ] && printf '<HOME>\t%s\n' "$HOME"
  } | awk -F'\t' 'length($2) >= 3 { print length($2) "\t" $1 "\t" $2 }' |
    sort -t"$(printf '\t')" -k1,1nr | cut -f2-
}

# jev_redact <file>: the file's text with every never-send value replaced by a
# placeholder, every secret-shaped line replaced by its masked shape, and the
# size capped. This runs inside jev_ask, so no caller can skip it.
jev_redact() {
  local file="$1" tmp cur pf forced hits n line size
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/jev-red.XXXXXX") || return 1
  cur="$file"

  # 1. Lines holding one of the owner's own secrets: masked without even the
  #    first characters.
  jev_load_secrets
  hits=$(jev_own_secret_lines "$cur" | tr '\n' ',')
  if [ -n "$hits" ]; then
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      case ",$hits" in
        *",$n,"*)
          # The whole line is dropped: a fragment of a multi-line value would
          # survive any attempt to replace the value inside it.
          printf '[masked own-secret line]\n'
          ;;
        *) printf '%s\n' "$line" ;;
      esac
    done <"$cur" >"$tmp/own"
    cur="$tmp/own"
  fi

  # 2. Lines with a credential format or a high-entropy assigned value, and
  #    whatever gitleaks flags: replaced by the masked shape.
  pf="$tmp/patterns"
  jev_secret_patterns >"$pf"
  forced=$(_jev_gitleaks_lines "$cur")
  awk -v mode=redact -v pf="$pf" -v forced="$forced" -f "$JEV_LIB_DIR/jev-scan.awk" "$cur" >"$tmp/masked"

  # 3. Never-send values -> placeholders.
  jev_never_send_map >"$tmp/map"
  awk -F'\t' '
    function repl(s, l, r,    out, k, low, ll) {
      low = tolower(s); ll = length(l); out = ""
      while ((k = index(low, l)) > 0) { out = out substr(s, 1, k - 1) r; s = substr(s, k + ll); low = substr(low, k + ll) }
      return out s
    }
    NR == FNR { n++; ph[n] = $1; lit[n] = tolower($2); next }
    { line = $0; for (i = 1; i <= n; i++) line = repl(line, lit[i], ph[i]); print line }
  ' "$tmp/map" "$tmp/masked" >"$tmp/out"

  # 4. Size cap, well under the 32k-token state limit.
  size=$(wc -c <"$tmp/out" | tr -d ' ')
  if [ "$size" -gt "$JEV_MAX_STATE_BYTES" ]; then
    head -c "$JEV_MAX_STATE_BYTES" "$tmp/out"
    printf '\n[truncated: %d bytes omitted]\n' "$((size - JEV_MAX_STATE_BYTES))"
  else
    cat "$tmp/out"
  fi
  rm -rf "$tmp"
  return 0
}

#############################################################################
# jev_ask
#############################################################################

# jev_ask <point> <state-file> <questions-json>
jev_ask() {
  local point="$1" statef="$2" questions="$3" mode key model tmo tries try max used
  local body resp code crc t0 t1 ans own=0 cfgkey

  mode=$(jev_mode "$point")
  if [ "$mode" = off ]; then
    JEV_LAST_ERR=off
    return 3
  fi
  if [ -z "${JEV_RUN_DIR:-}" ]; then
    jev_init || return 1
    own=1
  fi

  if [ -e "$JEV_RUN_DIR/fatal" ]; then
    JEV_LAST_ERR=fatal
    jev_log_once fatal "$point" "$mode" "skipped: earlier 401/403 in this run"
    [ "$own" -eq 1 ] && jev_cleanup
    return 5
  fi

  if ! key=$(jev_key); then
    JEV_LAST_ERR="no key"
    jev_log_once nokey "$point" "$mode" "skipped: no key"
    [ "$own" -eq 1 ] && jev_cleanup
    return 2
  fi

  model="${DOTFILES_JEV_MODEL:-$JEV_DEFAULT_MODEL}"
  tmo="${JEV_TIMEOUT:-}"
  if [ -z "$tmo" ]; then
    if [ "${JEV_SCHEDULED:-}" = 1 ]; then tmo=10; else tmo=2; fi
  fi
  tries="${JEV_TRIES:-2}"
  max="${JEV_MAX_REQUESTS:-20}"

  # jev_redact runs in a pipeline (a subshell whose load is discarded), so load
  # here. That is once per process only when jev_ask itself runs in the main
  # shell; callers that wrap it in $(...) load first (bin/dotfiles-jev consult).
  jev_load_secrets
  body="$JEV_RUN_DIR/body.$$.$RANDOM"
  resp="$JEV_RUN_DIR/resp.$$.$RANDOM"
  if ! jev_redact "$statef" |
    (umask 077; jq -Rs --arg model "$model" --argjson q "$questions" \
      '{model: $model, state: sub("\n$"; ""), questions: $q}' >"$body") 2>/dev/null; then
    JEV_LAST_ERR="bad request"
    jev_log "$point" "$mode" "error: could not build the request"
    rm -f "$body"
    [ "$own" -eq 1 ] && jev_cleanup
    return 1
  fi

  # The key goes to curl on stdin as a config file: never argv (visible in
  # ps), never a file. Backslash and quote are escaped for curl's config syntax.
  cfgkey=$(printf '%s' "$key" | tr -d '\n\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  try=0
  while :; do
    used=$(cat "$JEV_RUN_DIR/count" 2>/dev/null || echo 0)
    if [ "$used" -ge "$max" ]; then
      JEV_LAST_ERR=cap
      jev_log_once cap "$point" "$mode" "skipped: request cap ($max) reached"
      rm -f "$body" "$resp"
      [ "$own" -eq 1 ] && jev_cleanup
      return 4
    fi
    printf '%d' "$((used + 1))" >"$JEV_RUN_DIR/count"
    try=$((try + 1))
    t0=$(jev_now_ms)
    code=$(printf 'header = "Authorization: Bearer %s"\n' "$cfgkey" |
      curl -sS --max-time "$tmo" -o "$resp" -w '%{http_code}' --config - \
        -H 'Content-Type: application/json' -X POST --data-binary "@$body" "$JEV_ENDPOINT" 2>/dev/null)
    crc=$?
    t1=$(jev_now_ms)
    JEV_LAST_MS=$((t1 - t0))
    printf '%s' "$JEV_LAST_MS" >"$JEV_RUN_DIR/last_ms"

    if [ "$crc" -ne 0 ]; then
      JEV_LAST_ERR="curl exit $crc"
      jev_log "$point" "$mode" "error: curl exit $crc (timeout ${tmo}s)"
      break
    fi
    case "$code" in
      200)
        ans=$(jq -c '.answers // empty' "$resp" 2>/dev/null)
        if [ -n "$ans" ] && [ "$ans" != null ]; then
          rm -f "$body" "$resp"
          [ "$own" -eq 1 ] && jev_cleanup
          printf '%s\n' "$ans"
          return 0
        fi
        JEV_LAST_ERR="malformed reply"
        jev_log "$point" "$mode" "error: reply had no answers"
        break
        ;;
      401 | 403)
        : >"$JEV_RUN_DIR/fatal"
        JEV_LAST_ERR="http $code"
        jev_log "$point" "$mode" "error: HTTP $code, fatal: no more requests this run"
        rm -f "$body" "$resp"
        [ "$own" -eq 1 ] && jev_cleanup
        return 5
        ;;
      429 | 5[0-9][0-9])
        if [ "$try" -lt "$tries" ]; then
          sleep "${JEV_BACKOFF:-0.4}"
          continue
        fi
        JEV_LAST_ERR="http $code"
        jev_log "$point" "$mode" "error: HTTP $code after $try attempt(s)"
        break
        ;;
      *)
        JEV_LAST_ERR="http $code"
        jev_log "$point" "$mode" "error: HTTP $code"
        break
        ;;
    esac
  done
  rm -f "$body" "$resp"
  [ "$own" -eq 1 ] && jev_cleanup
  return 1
}

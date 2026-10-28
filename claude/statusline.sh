#!/bin/bash
#
# Claude Code status line.
#
# Everything rendered here comes from the JSON payload Claude Code writes to
# this script's stdin, with one exception: extra usage. The payload's
# `rate_limits` carry the five-hour and weekly windows (and a gateway's spend
# limit) but not extra usage, which only Anthropic's usage API returns. So for
# a subscriber whose payload lacks it, the script fetches it -- hardened,
# because the 2026-09 audit removed an earlier version of this for good
# reasons (it read a credentials file, put the token on curl's command line
# where `ps` shows it to every local process, and stalled five seconds when
# the network was down):
#
#   - The fetch runs detached, at most every five minutes (a marker file
#     throttles failures too), never on the render path.
#   - The OAuth token comes from the macOS keychain only (or
#     CLAUDE_CODE_OAUTH_TOKEN), never a credentials file, and reaches curl
#     through its config on stdin (-K -), never a command line.
#   - Only the extra_usage object is cached, never the token: a 0700 directory
#     under ~/Library/Caches, a 0600 file replaced atomically. An answer older
#     than an hour is not shown.
#   - The User-Agent version comes from the payload, not a pinned number.
#
# CLAUDE_STATUSLINE_FETCH=off turns the fetch off; =sync runs it in the
# foreground (the tests). CLAUDE_STATUSLINE_CACHE_DIR moves the cache.
#
# Cost matters here: this runs on every refresh. One jq pass emits every field
# as one delimited line and the rest is pure bash. The old version made
# 21 jq calls, 8 awk calls and three git calls per render, including a
# `git status --porcelain` that walked the entire worktree just to decide
# whether to print an asterisk.
#
# Payload fields used, all confirmed present in the installed CLI:
#   model.display_name, context_window.{context_window_size,used_percentage},
#   workspace.current_dir, cwd, cost.total_duration_ms, effort.level, version,
#   rate_limits.{five_hour,seven_day} (and extra_usage, should it ever appear)
# `effort` is an object in the payload, not a re-read of settings.json (older
# CLIs sent a bare string, still accepted); `resets_at` is Unix epoch seconds;
# elapsed time is cost.total_duration_ms, not a `session.start_time` field
# that does not exist.
#
# Upstream: nilbuild/claude-statusline (was kamranahmedse/claude-statusline),
# in sync with v1.0.6; its OAuth/API fallback is replaced by the hardened
# extra-usage fetch described above.

set -f

input=$(cat)

if [ -z "$input" ] || ! command -v jq > /dev/null 2>&1; then
  printf "Claude"
  exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────

# Percentages arrive as numbers that may carry a fraction; bash arithmetic is
# integer-only, so truncate and reject anything that is not a plain integer.
as_int() {
  local n="${1%%.*}"
  case "$n" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%d' "$n" ;;
  esac
}

color_for_pct() {
  local pct=$1
  if [ "$pct" -ge 90 ]; then
    printf '%b' "$red"
  elif [ "$pct" -ge 70 ]; then
    printf '%b' "$yellow"
  elif [ "$pct" -ge 50 ]; then
    printf '%b' "$orange"
  else
    printf '%b' "$green"
  fi
}

build_bar() {
  local pct=$1 width=$2
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local bar_color filled_str="" empty_str="" i
  bar_color=$(color_for_pct "$pct")

  for ((i = 0; i < filled; i++)); do filled_str+="●"; done
  for ((i = 0; i < empty; i++)); do empty_str+="○"; done

  printf '%b%s%b%s%b' "$bar_color" "$filled_str" "$dim" "$empty_str" "$reset"
}

iso_to_epoch() {
  local iso_str="$1" epoch stripped

  epoch=$(date -d "${iso_str}" +%s 2> /dev/null)
  if [ -n "$epoch" ]; then
    printf '%s' "$epoch"
    return 0
  fi

  stripped="${iso_str%%.*}"
  stripped="${stripped%%Z}"
  stripped="${stripped%%+*}"
  stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

  case "$iso_str" in
    *Z* | *"+00:00"* | *"-00:00"*)
      epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2> /dev/null) ;;
    *)
      epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2> /dev/null) ;;
  esac

  [ -n "$epoch" ] || return 1
  printf '%s' "$epoch"
}

format_reset_time() {
  local raw="$1" style="$2" epoch result=""
  [ -z "$raw" ] && return

  # Epoch seconds as sent today; ISO 8601 is the fallback for older payloads.
  case "${raw%%.*}" in
    '' | *[!0-9]*) epoch=$(iso_to_epoch "$raw") || return ;;
    *) epoch="${raw%%.*}" ;;
  esac
  [ -n "$epoch" ] || return

  case "$style" in
    time)
      result=$(date -j -r "$epoch" +"%l:%M%p" 2> /dev/null | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
      [ -z "$result" ] && result=$(date -d "@$epoch" +"%l:%M%P" 2> /dev/null | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
      ;;
    datetime)
      result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2> /dev/null | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
      [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2> /dev/null | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
      ;;
    *)
      result=$(date -j -r "$epoch" +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')
      [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')
      ;;
  esac
  printf "%s" "$result"
}

# ── Extra usage cache (see the header) ──────────────────
cache_dir="${CLAUDE_STATUSLINE_CACHE_DIR:-$HOME/Library/Caches/claude-statusline}"
cache_file="$cache_dir/extra-usage.json"
attempt_file="$cache_dir/last-fetch"
usage_fetch_every=300
usage_max_age=3600

if [ ! -d "$cache_dir" ]; then
  mkdir -p "${cache_dir%/*}" 2> /dev/null
  mkdir -m 700 "$cache_dir" 2> /dev/null
fi
# Every mtime is normalised before arithmetic: a missing or unreadable file
# reads as 0, which means "old". BSD stat by path: GNU stat, which may come
# first in PATH, reads -f as "file system".
now=$(date +%s)
case "$now" in '' | *[!0-9]*) now=0 ;; esac
cache_mtime=$(/usr/bin/stat -f %m "$cache_file" 2> /dev/null)
case "$cache_mtime" in '' | *[!0-9]*) cache_mtime=0 ;; esac
attempt_mtime=$(/usr/bin/stat -f %m "$attempt_file" 2> /dev/null)
case "$attempt_mtime" in '' | *[!0-9]*) attempt_mtime=0 ;; esac

cached_args=(--arg cached "")
if [ "$cache_mtime" -gt 0 ] && [ $((now - cache_mtime)) -lt "$usage_max_age" ]; then
  cached_args=(--rawfile cached "$cache_file")
fi

# fetch_extra_usage <cli-version> -- runs detached, off the render path. Caches
# only the extra_usage object; a failure leaves the last good answer alone.
fetch_extra_usage() {
  local token tmp
  token="${CLAUDE_CODE_OAUTH_TOKEN:-}"
  [ -n "$token" ] || token=$(security find-generic-password -s "Claude Code-credentials" -w 2> /dev/null |
    sed -n 's/.*"accessToken" *: *"\([^"]*\)".*/\1/p')
  [ -n "$token" ] || return 0
  tmp=$(mktemp "$cache_dir/.extra-usage.XXXXXX" 2> /dev/null) || return 0
  # The token goes to curl as config on stdin (-K -), never as an argument.
  printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl -fsS --max-time 10 -K - -H "anthropic-beta: oauth-2025-04-20" -A "claude-code/${1:-unknown}" \
      "https://api.anthropic.com/api/oauth/usage" 2> /dev/null |
    jq -ce '.extra_usage | objects' > "$tmp" 2> /dev/null
  if [ -s "$tmp" ]; then
    chmod 600 "$tmp" && mv -f "$tmp" "$cache_file"
  else
    rm -f "$tmp"
  fi
}

# ── One pass over the payload ───────────────────────────
# context_window.used_percentage is authoritative when present; the token sum
# is the fallback for payloads that predate it. `// empty` on the rate limits
# keeps them distinguishable from a real zero: they are absent for accounts
# without plan limits and before the session's first API response. Extra usage
# comes from the payload if it ever carries it, else from a fresh cache; a
# corrupt or non-object cache reads as none.
fields=$(
  printf '%s' "$input" | jq -r "${cached_args[@]}" '
    def pct: if . == null then "" else . end;
    (.context_window.context_window_size // 200000) as $size
    | ((((.rate_limits.extra_usage // ($cached | try fromjson catch null)) | objects) // {})) as $eu
    | [ (.model.display_name // "Claude"),
        $size,
        ( .context_window.used_percentage
          // ( ( ((.context_window.current_usage.input_tokens // 0)
                 + (.context_window.current_usage.cache_creation_input_tokens // 0)
                 + (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 )
               / (if $size > 0 then $size else 200000 end) ) ),
        (.workspace.current_dir // .cwd // ""),
        (.cost.total_duration_ms // 0),
        ((.effort | if type == "object" then .level else . end) // ""),
        (.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization | pct),
        (.rate_limits.five_hour.resets_at // ""),
        (.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization | pct),
        (.rate_limits.seven_day.resets_at // ""),
        ($eu.is_enabled // false),
        ($eu.used_percentage // $eu.utilization // 0),
        ($eu.used_credits // 0),
        ($eu.monthly_limit // 0),
        (.version // ""),
        (if .rate_limits then "yes" else "" end),
        (if .rate_limits.extra_usage then "yes" else "" end),
        ($eu.currency // "")
      ] | map(tostring) | join("\u001f")
  ' 2> /dev/null
)

if [ -z "$fields" ]; then
  printf "Claude"
  exit 0
fi

# Unit separator, not tab: tab counts as IFS whitespace, so bash collapses a
# run of them into one delimiter and every field after an empty one shifts up.
IFS=$'\037' read -r model_name ctx_size ctx_pct cwd duration_ms effort \
  five_pct five_reset seven_pct seven_reset \
  extra_enabled extra_pct extra_used extra_limit \
  cli_version has_limits payload_extra extra_currency <<< "$fields"

# Fetch extra usage for a subscriber (rate_limits present) whose payload lacks
# it, at most every five minutes. The marker is touched first, so a failing
# fetch is throttled too.
if [ "${CLAUDE_STATUSLINE_FETCH:-}" != off ] && [ -n "$has_limits" ] && [ -z "$payload_extra" ] &&
  [ -d "$cache_dir" ] && [ $((now - attempt_mtime)) -ge "$usage_fetch_every" ]; then
  : > "$attempt_file"
  if [ "${CLAUDE_STATUSLINE_FETCH:-}" = sync ]; then
    fetch_extra_usage "$cli_version"
  else
    fetch_extra_usage "$cli_version" < /dev/null > /dev/null 2>&1 &
  fi
fi

: "${ctx_size:=200000}"
pct_used=$(as_int "$ctx_pct")
[ "$pct_used" -gt 100 ] && pct_used=100

# ── LINE 1: Model │ Context % │ Directory (branch) │ Elapsed │ Effort ──
pct_color=$(color_for_pct "$pct_used")
[ -n "$cwd" ] || cwd=$(pwd)
dirname=$(basename "$cwd")

# One git process, and one that does no work proportional to the worktree.
# The dirty marker is gone on purpose: `git status --porcelain` stats every
# tracked file, on every refresh, to decide whether to print one character.
git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2> /dev/null)

# The payload carries no permission mode, but Claude Code runs this script as
# its direct child, so its own argv says whether permissions are skipped.
skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2> /dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
  skip_perms="⚡  "
fi

session_duration=""
elapsed=$(($(as_int "$duration_ms") / 1000))
if [ "$elapsed" -ge 3600 ]; then
  session_duration="$((elapsed / 3600))h$(((elapsed % 3600) / 60))m"
elif [ "$elapsed" -ge 60 ]; then
  session_duration="$((elapsed / 60))m"
elif [ "$elapsed" -gt 0 ]; then
  session_duration="${elapsed}s"
fi

line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"
line1+="${sep}"
line1+="${skip_perms}${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
  line1+=" ${green}(${git_branch})${reset}"
fi
if [ -n "$session_duration" ]; then
  line1+="${sep}"
  line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi
line1+="${sep}"
case "$effort" in
  high | xhigh | max) line1+="${magenta}● ${effort}${reset}" ;;
  medium) line1+="${dim}◑ ${effort}${reset}" ;;
  low) line1+="${dim}◔ ${effort}${reset}" ;;
  *) line1+="${dim}◑ ${effort:-default}${reset}" ;;
esac

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

render_limit() { # render_limit <pct> <reset-iso> <reset-style>
  local pct reset_at bar pct_color pct_fmt
  pct=$(as_int "$1")
  reset_at=$(format_reset_time "$2" "$3")
  bar=$(build_bar "$pct" "$bar_width")
  pct_color=$(color_for_pct "$pct")
  pct_fmt=$(printf "%3d" "$pct")
  printf '%s %b%s%%%b' "$bar" "$pct_color" "$pct_fmt" "$reset"
  [ -n "$reset_at" ] && printf ' %b⟳%b %b%s%b' "$dim" "$reset" "$white" "$reset_at" "$reset"
}

if [ -n "$five_pct" ]; then
  rate_lines+="${white}current${reset} $(render_limit "$five_pct" "$five_reset" time)"
fi
if [ -n "$seven_pct" ]; then
  [ -n "$rate_lines" ] && rate_lines+="\n"
  rate_lines+="${white}weekly${reset}  $(render_limit "$seven_pct" "$seven_reset" datetime)"
fi

if [ "$extra_enabled" = "true" ]; then
  extra_pct_int=$(as_int "$extra_pct")
  extra_bar=$(build_bar "$extra_pct_int" "$bar_width")
  extra_pct_color=$(color_for_pct "$extra_pct_int")
  # Credits arrive in minor units (cents), in the account's currency.
  extra_used_int=$(as_int "$extra_used")
  extra_limit_int=$(as_int "$extra_limit")
  case "$extra_currency" in
    EUR) cur="€" ;;
    GBP) cur="£" ;;
    '' | USD) cur="\$" ;;
    *) cur="$extra_currency " ;;
  esac
  extra_reset=$(date -v+1m -v1d +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')
  [ -z "$extra_reset" ] && extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')

  [ -n "$rate_lines" ] && rate_lines+="\n"
  rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}${cur}$((extra_used_int / 100)).$(printf '%02d' $((extra_used_int % 100)))${dim}/${reset}${white}${cur}$((extra_limit_int / 100)).$(printf '%02d' $((extra_limit_int % 100)))${reset}"
  [ -n "$extra_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0

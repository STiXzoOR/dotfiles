#!/bin/bash
#
# Claude Code status line.
#
# Everything rendered here comes from the JSON payload Claude Code writes to
# this script's stdin. Nothing else is read: no keychain, no credentials file,
# no network, no cache.
#
# That is a deliberate rewrite. The previous version located an OAuth access
# token (env, then the macOS keychain, then ~/.claude/.credentials.json, then
# secret-tool) and spent a network round-trip every 60 seconds asking
# api.anthropic.com for usage figures the payload already carries in
# `rate_limits`. It also passed the token as a curl argv, where any local
# process could read it out of `ps` for the life of the request. Deleting that
# path removes a credential-handling code path from a public repo, the token
# exposure, both cache files, a CLI-version probe and a five-second stall when
# the network is down -- with no loss of function.
#
# Cost matters here: this runs on every refresh. One jq pass emits every field
# as one delimited line and the rest is pure bash. The old version made
# 21 jq calls, 8 awk calls and three git calls per render, including a
# `git status --porcelain` that walked the entire worktree just to decide
# whether to print an asterisk.
#
# Payload fields used, all confirmed present in the installed CLI:
#   model.display_name, context_window.{context_window_size,used_percentage},
#   workspace.current_dir, cwd, cost.total_duration_ms, effort,
#   rate_limits.{five_hour,seven_day,extra_usage}
# `effort` is top level, not a re-read of settings.json; elapsed time is
# cost.total_duration_ms, not a `session.start_time` field that does not exist.

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
  local iso_str="$1" style="$2" epoch result=""
  [ -z "$iso_str" ] && return

  epoch=$(iso_to_epoch "$iso_str") || return
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

# ── One pass over the payload ───────────────────────────
# context_window.used_percentage is authoritative when present; the token sum
# is the fallback for payloads that predate it. `// empty` on the rate limits
# keeps them distinguishable from a real zero: they are absent for accounts
# without plan limits and before the session's first API response.
fields=$(
  printf '%s' "$input" | jq -r '
    def pct: if . == null then "" else . end;
    (.context_window.context_window_size // 200000) as $size
    | [ (.model.display_name // "Claude"),
        $size,
        ( .context_window.used_percentage
          // ( ( ((.context_window.current_usage.input_tokens // 0)
                 + (.context_window.current_usage.cache_creation_input_tokens // 0)
                 + (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 )
               / (if $size > 0 then $size else 200000 end) ) ),
        (.workspace.current_dir // .cwd // ""),
        (.cost.total_duration_ms // 0),
        (.effort // ""),
        (.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization | pct),
        (.rate_limits.five_hour.resets_at // ""),
        (.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization | pct),
        (.rate_limits.seven_day.resets_at // ""),
        (.rate_limits.extra_usage.is_enabled // false),
        (.rate_limits.extra_usage.used_percentage // .rate_limits.extra_usage.utilization // 0),
        (.rate_limits.extra_usage.used_credits // 0),
        (.rate_limits.extra_usage.monthly_limit // 0)
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
  extra_enabled extra_pct extra_used extra_limit <<< "$fields"

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
line1+="${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
  line1+=" ${green}(${git_branch})${reset}"
fi
if [ -n "$session_duration" ]; then
  line1+="${sep}"
  line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi
line1+="${sep}"
case "$effort" in
  high) line1+="${magenta}● ${effort}${reset}" ;;
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
  # Credits arrive in cents.
  extra_used_int=$(as_int "$extra_used")
  extra_limit_int=$(as_int "$extra_limit")
  extra_reset=$(date -v+1m -v1d +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')
  [ -z "$extra_reset" ] && extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2> /dev/null | tr '[:upper:]' '[:lower:]')

  [ -n "$rate_lines" ] && rate_lines+="\n"
  rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$$((extra_used_int / 100)).$(printf '%02d' $((extra_used_int % 100)))${dim}/${reset}${white}\$$((extra_limit_int / 100)).$(printf '%02d' $((extra_limit_int % 100)))${reset}"
  rate_lines+="\n${dim}resets ${reset}${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0

#!/usr/bin/env bash

###
# some colorized echo helpers
# @author Adam Eivy
###

# Colors
ESC_SEQ="\x1b["
COL_RESET=$ESC_SEQ"39;49;00m"
COL_RED=$ESC_SEQ"31;01m"
COL_GREEN=$ESC_SEQ"32;01m"
COL_YELLOW=$ESC_SEQ"33;01m"
COL_BLUE=$ESC_SEQ"34;01m"
COL_MAGENTA=$ESC_SEQ"35;01m"
COL_CYAN=$ESC_SEQ"36;01m"

# Every helper defaults its argument: they are routinely called bare (`ok`,
# `skip`), and a caller running under `set -u` -- bin/dotfiles-setup,
# remote-install.sh and fonts/install.sh all do -- would otherwise abort with
# "$1: unbound variable" at the moment it reports success.
function bot() {
  echo -e "\n${COL_GREEN}\[._.]/${COL_RESET} - ${1:-}"
}

function ok() {
  echo -e "[${COL_GREEN}ok${COL_RESET}] ${1:-}"
}

function skip() {
  echo -e "[${COL_MAGENTA}skipped${COL_RESET}] ${1:-}"
}

function running() {
  echo -en "${COL_YELLOW} ⇒ ${COL_RESET}${1:-}: "
}

function action() {
  echo -e "\n[${COL_YELLOW}action${COL_RESET}]:\n ⇒ ${1:-}..."
}

function warn() {
  echo -e "[${COL_YELLOW}warning${COL_RESET}] ${1:-}"
}

function error() {
  echo -e "[${COL_RED}error${COL_RESET}] ${1:-}"
}

# Report a command's exit status. Called but never defined before this, so
# every use printed "print_result: command not found" to stderr and carried on.
function print_result() {
  if [[ "${1:-1}" -eq 0 ]]; then
    ok "${2:-}"
  else
    error "${2:-}"
  fi
}

# The single yes/no prompt for every interactive step in this repo.
#
# The hand-rolled prompts this replaces gated on `[[ $response =~ (yes|y|Y) ]]`
# -- an unanchored regex, so "Nay" and "absolutely not" both matched and the
# destructive branch ran. Anchor the whole answer, and accept nothing else.
#
# DOTFILES_YES=1 answers yes without prompting, which is what makes
# `install --all` genuinely non-interactive. EOF (a closed stdin) is a no, so
# an unattended run without DOTFILES_YES skips rather than guesses.
function confirm() {
  local response
  [[ "${DOTFILES_YES:-0}" == "1" ]] && return 0
  read -r -p "$1 [y|N] " response || return 1
  [[ "$response" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

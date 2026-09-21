#!/usr/bin/env bash
#
# Filesystem helpers shared by the bash and zsh tools in this repo.
# Must stay POSIX-ish: sourced from bash 3.2 (macOS ships 3.2.57) and zsh 5.9.

#############################################################################
# stat(1) portability
#############################################################################
#
# macOS ships BSD stat, but this repo's Brewfile installs GNU coreutils and
# system/.path prepends its gnubin -- so `stat` is BSD before a full install
# and GNU after one.
#
# The trap: to GNU, `-f` means *filesystem*. `stat -f %m file` does not fail,
# it prints multi-line filesystem info, so the common
# `stat -f %m … || stat -c %Y …` idiom never reaches its fallback and feeds
# that text into arithmetic. Probe GNU first; BSD rejects `-c` outright.

# Modification time as a unix timestamp. Empty if the file is unreadable.
dotfiles_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# Size in bytes. Empty if the file is unreadable.
dotfiles_filesize() {
  stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null
}

# Age in whole days. Prints nothing when the mtime cannot be read, so callers
# can guard instead of doing arithmetic on an empty string.
dotfiles_age_days() {
  _dfa_mtime=$(dotfiles_mtime "$1")
  case "$_dfa_mtime" in
    '' | *[!0-9]*) unset _dfa_mtime; return 1 ;;
  esac
  echo $(( ($(date +%s) - _dfa_mtime) / 86400 ))
  unset _dfa_mtime
}

#############################################################################
# Backup restore
#############################################################################

# Restore a ~/.dotfiles_backup/<date> directory back over $HOME.
#
# The original loop ran with the backup directory as cwd and called
# `unlink "$file"` -- a relative path, so it deleted the *backup* copy rather
# than the $HOME symlink. The following `[ -e ./$file ]` was then false and the
# restore silently never happened. Every path here is absolute.
#
# Anything real (not a symlink) already at the destination is moved aside
# rather than deleted: a restore must never be able to lose data.
dotfiles_restore_backup() {
  _dfr_backup="$1"
  [ -d "$_dfr_backup" ] || return 1

  while IFS= read -r _dfr_path; do
    [ -n "$_dfr_path" ] || continue
    _dfr_name=${_dfr_path##*/}
    case "$_dfr_name" in
      . | .. | .DS_Store) continue ;;
    esac

    if [ -L "$HOME/$_dfr_name" ]; then
      # Our own stow symlink: safe to drop.
      rm -f "$HOME/$_dfr_name" || return 1
    elif [ -e "$HOME/$_dfr_name" ]; then
      # Something real is in the way. Keep it.
      mv "$HOME/$_dfr_name" "$HOME/$_dfr_name.replaced.$(date +%Y%m%d%H%M%S)" || return 1
    fi

    mv "$_dfr_path" "$HOME/$_dfr_name" || return 1
  done < <(find "$_dfr_backup" -mindepth 1 -maxdepth 1 2>/dev/null)

  unset _dfr_backup _dfr_path _dfr_name
}

#############################################################################
# Housekeeping
#############################################################################

# fnm creates a multishell directory per shell. Its default home is $TMPDIR,
# which macOS clears at boot -- but system/.env points XDG_RUNTIME_DIR at
# ~/.local/runtime, which is never cleared, so they accumulate without bound
# (39,778 of them by the time this was found). Prune stale ones.
dotfiles_prune_fnm_multishells() {
  _dfp_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/fnm_multishells"
  [ -d "$_dfp_dir" ] || { unset _dfp_dir; return 0; }

  # Anything older than a day cannot belong to a live shell worth keeping.
  find "$_dfp_dir" -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null

  unset _dfp_dir
}

# Seed a config file from its tracked template, expanding __HOME__.
# Never overwrites an existing file.
dotfiles_seed_from_template() {
  _dfs_template="$1"; _dfs_target="$2"
  if [ -f "$_dfs_template" ] && [ ! -f "$_dfs_target" ]; then
    mkdir -p "$(dirname "$_dfs_target")"
    sed "s|__HOME__|$HOME|g" "$_dfs_template" >"$_dfs_target"
  fi
  unset _dfs_template _dfs_target
}

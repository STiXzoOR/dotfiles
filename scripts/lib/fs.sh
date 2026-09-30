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

# Restore a ~/.dotfiles_backup/<date> directory back over a target tree.
#
# usage: dotfiles_restore_backup <backup-dir> [target-dir]
#
# target-dir defaults to $HOME. `dotfiles link` stows two trees -- runcom into
# $HOME and config into $XDG_CONFIG_HOME -- so a restore has to be able to aim
# at either.
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
  _dfr_target="${2:-$HOME}"
  [ -d "$_dfr_backup" ] || return 1
  mkdir -p "$_dfr_target" || return 1

  while IFS= read -r _dfr_path; do
    [ -n "$_dfr_path" ] || continue
    _dfr_name=${_dfr_path##*/}
    case "$_dfr_name" in
      . | .. | .DS_Store) continue ;;
    esac

    if [ -L "$_dfr_target/$_dfr_name" ]; then
      # Our own stow symlink: safe to drop.
      rm -f "$_dfr_target/$_dfr_name" || return 1
    elif [ -e "$_dfr_target/$_dfr_name" ]; then
      # Something real is in the way. Keep it.
      mv "$_dfr_target/$_dfr_name" "$_dfr_target/$_dfr_name.replaced.$(date +%Y%m%d%H%M%S)" || return 1
    fi

    mv "$_dfr_path" "$_dfr_target/$_dfr_name" || return 1
  done < <(find "$_dfr_backup" -mindepth 1 -maxdepth 1 2>/dev/null)

  unset _dfr_backup _dfr_target _dfr_path _dfr_name
}

# Print the physical absolute path of <path>, collapsing "..", "." and any
# symlinked parent directories. Returns 1 when the parent does not exist.
#
# macOS has no `readlink -f` and bash 3.2 has no realpath, so resolve the
# parent with `cd`/`pwd -P` and re-attach the basename. The final component is
# deliberately NOT followed: the caller is comparing where a link points, and
# a link into a package that has not been stowed yet still has to match.
_dotfiles_abspath() {
  _dfx_dir=$(CDPATH='' cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || {
    unset _dfx_dir
    return 1
  }
  case "$_dfx_dir" in
    /) printf '/%s' "$(basename -- "$1")" ;;
    *) printf '%s/%s' "$_dfx_dir" "$(basename -- "$1")" ;;
  esac
  unset _dfx_dir
}

# usage: dotfiles_backup_stow_targets <package-dir> <target-dir> <backup-dir>
#
# Move anything real that sits where stow is about to link into <backup-dir>,
# so linking can never destroy data and `dotfiles unlink` can put it all back.
#
# `link` only ever swept $HOME against runcom/. config/ stows into
# $XDG_CONFIG_HOME, whose contents were never inspected, backed up or
# unlinked -- so a pre-existing ~/.config/git or ~/.config/nvim became a stow
# conflict, and unlink could not restore one either.
dotfiles_backup_stow_targets() {
  _dfb_pkg="$1"
  _dfb_target="$2"
  _dfb_backup="$3"

  [ -d "$_dfb_pkg" ] || { unset _dfb_pkg _dfb_target _dfb_backup; return 0; }

  _dfb_pkg_abs=$(_dotfiles_abspath "$_dfb_pkg") || _dfb_pkg_abs="$_dfb_pkg"

  while IFS= read -r _dfb_path; do
    [ -n "$_dfb_path" ] || continue
    _dfb_name=${_dfb_path##*/}
    case "$_dfb_name" in
      . | .. | .DS_Store) continue ;;
    esac

    _dfb_dest="$_dfb_target/$_dfb_name"

    # A link we already own is left exactly where it is: `stow --restow`
    # replaces it itself. Dropping it here, before stow had proven it could
    # run, left $HOME without a single link whenever stow then aborted. A
    # symlink pointing anywhere else is the user's, so it is backed up below.
    #
    # The comparison has to be against a resolved path. Stow writes RELATIVE
    # links -- `readlink ~/.zshrc` is `.dotfiles/runcom/.zshrc` and
    # `readlink ~/.config/git` is `../.dotfiles/config/git` -- so matching
    # readlink output against the absolute package path never fired.
    if [ -L "$_dfb_dest" ]; then
      _dfb_link=$(readlink "$_dfb_dest")
      case "$_dfb_link" in
        /*) _dfb_resolved="$_dfb_link" ;;
        *) _dfb_resolved="$_dfb_target/$_dfb_link" ;;
      esac
      _dfb_resolved=$(_dotfiles_abspath "$_dfb_resolved") || _dfb_resolved=""

      case "$_dfb_resolved" in
        "$_dfb_pkg_abs" | "$_dfb_pkg_abs"/*) continue ;;
      esac
    fi

    if [ -e "$_dfb_dest" ] || [ -L "$_dfb_dest" ]; then
      mkdir -p "$_dfb_backup" || return 1
      echo "backup saved as $_dfb_backup/$_dfb_name"
      mv "$_dfb_dest" "$_dfb_backup/$_dfb_name" || return 1
      # Remember the move so a failed link can undo it.
      if [ -n "${DOTFILES_STOW_MOVELOG:-}" ]; then
        printf '%s\t%s\n' "$_dfb_dest" "$_dfb_backup/$_dfb_name" >>"$DOTFILES_STOW_MOVELOG"
      fi
    fi
  done << EOF
$(find "$_dfb_pkg" -mindepth 1 -maxdepth 1 2>/dev/null)
EOF

  unset _dfb_pkg _dfb_pkg_abs _dfb_target _dfb_backup _dfb_path _dfb_name \
    _dfb_dest _dfb_link _dfb_resolved
  return 0
}

# usage: dotfiles_undo_backup_moves <movelog> <backup-dir>
#
# Put every file the sweep moved (one "<original><TAB><backup>" line each, as
# written to $DOTFILES_STOW_MOVELOG) back where it was, newest first, then
# remove the backup directories that are left empty. A failed `link` uses this
# so it leaves $HOME as it found it. A symlink already sitting in the original
# slot (stow made it before failing) is removed; anything else there is left
# alone and reported, because it is not ours to overwrite.
dotfiles_undo_backup_moves() {
  _dfu_log="$1"
  _dfu_backup="$2"
  _dfu_rc=0
  _dfu_tab=$(printf '\t')
  [ -s "$_dfu_log" ] || { unset _dfu_log _dfu_backup _dfu_rc _dfu_tab; return 0; }

  # `sed -n '1!G;h;$p'` is tac for bash 3.2 and BSD tools.
  while IFS="$_dfu_tab" read -r _dfu_dest _dfu_saved; do
    [ -n "$_dfu_dest" ] || continue
    [ -L "$_dfu_dest" ] && rm -f "$_dfu_dest"
    if [ -e "$_dfu_dest" ]; then
      echo "could not restore $_dfu_dest: something is already there; your file is at $_dfu_saved" >&2
      _dfu_rc=1
      continue
    fi
    mkdir -p "$(dirname "$_dfu_dest")" && mv "$_dfu_saved" "$_dfu_dest" || _dfu_rc=1
  done << EOF
$(sed -n '1!G;h;$p' "$_dfu_log")
EOF

  rmdir "$_dfu_backup/.config" "$_dfu_backup" "$(dirname "$_dfu_backup")" 2>/dev/null
  unset _dfu_log _dfu_backup _dfu_tab _dfu_dest _dfu_saved
  _dfu_ret=$_dfu_rc
  unset _dfu_rc
  return "$_dfu_ret"
}

# usage: dotfiles_link_abort <INT|TERM> <movelog> <backup-dir>
#
# The signal handler for `dotfiles link` while it holds moved files: put them
# all back, drop the log, then die of the same signal so the caller sees it.
dotfiles_link_abort() {
  dotfiles_undo_backup_moves "$2" "$3"
  command rm -f "$2"
  trap - INT TERM
  kill -s "$1" "$$"
}

# usage: dotfiles_stow <-n|-> <stow-dir> <target-dir> <package>
#
# The one place the stow command line is spelled, so `dotfiles link` and
# `dotfiles-sync` cannot drift. --restow makes a re-run idempotent (not
# --adopt: that pulls the machine's files into the tracked tree). --ignore
# keeps Finder litter out (stow matches it against the whole name, so it is
# anchored: an unanchored one also dropped a real file called notes.DS_Store):
# an untracked, gitignored runcom/.DS_Store made stow
# abort with "neither a link nor a directory" against ~/.DS_Store. A
# .stow-local-ignore would REPLACE stow's built-in ignore list; a command-line
# --ignore adds to it.
dotfiles_stow() {
  # -d is explicit: stow's default source directory is $STOW_DIR when that is
  # exported, which silently beat the caller's `cd` to the repo root.
  if [ "$1" = "-n" ]; then
    stow -n --restow --ignore='^\.DS_Store$' -d "$2" -t "$3" "$4"
  else
    stow --restow --ignore='^\.DS_Store$' -d "$2" -t "$3" "$4"
  fi
}

# usage: dotfiles_stow_all <-n|-> <repo-root> <home> <xdg-config-home>
#
# runcom into <home>, config into <xdg-config-home>; -n only simulates. Stops
# at the first failure and leaves stow's output (which names the conflict) for
# the caller to capture.
dotfiles_stow_all() {
  (
    cd "$2" || exit 1
    dotfiles_stow "$1" "$2" "$3" runcom && dotfiles_stow "$1" "$2" "$4" config
  )
}

# usage: dotfiles_restore_ignored_from_backup <repo-dir> <package> <backup-bucket>
#
# Stow replaces a real ~/.config/gh with a symlink into the repo, and the old
# directory goes to the backup. Files the repo deliberately ignores (gh's
# hosts.yml holds the login) are then no longer at the live path. Copy each
# such file from <backup-bucket> into <repo-dir>/<package>/, where the symlink
# shows it at the live path again. Only files git ignores, and never over a
# file that is already there.
dotfiles_restore_ignored_from_backup() {
  _dfi_repo="$1"
  _dfi_pkg="$2"
  _dfi_bucket="$3"
  [ -d "$_dfi_bucket" ] || { unset _dfi_repo _dfi_pkg _dfi_bucket; return 0; }

  while IFS= read -r _dfi_file; do
    [ -n "$_dfi_file" ] || continue
    _dfi_rel=${_dfi_file#"$_dfi_bucket"/}
    _dfi_dest="$_dfi_repo/$_dfi_pkg/$_dfi_rel"
    if [ -e "$_dfi_dest" ] || [ -L "$_dfi_dest" ]; then
      continue
    fi
    git -C "$_dfi_repo" check-ignore -q "$_dfi_pkg/$_dfi_rel" 2>/dev/null || continue
    mkdir -p "$(dirname "$_dfi_dest")" || continue
    if cp -p "$_dfi_file" "$_dfi_dest"; then
      echo "restored ignored file $_dfi_pkg/$_dfi_rel from the backup"
    fi
  done << EOF
$(find "$_dfi_bucket" -type f 2>/dev/null)
EOF

  unset _dfi_repo _dfi_pkg _dfi_bucket _dfi_file _dfi_rel _dfi_dest
  return 0
}

#############################################################################
# Hosts file
#############################################################################

# Print <hosts> with every line whose hostname appears in <whitelist> dropped.
#
# This is the whole of what the StevenBlack generator's whitelist feature did
# for this repo, and it replaces a 1.9 GB submodule, a Python venv and a pip
# install. Comments and blank lines pass through untouched, so the header the
# download check looks for survives.
#
# usage: dotfiles_hosts_apply_whitelist <hosts-file> <whitelist-file>
dotfiles_hosts_apply_whitelist() {
  awk '
    NR == FNR {
      if ($0 !~ /^[[:space:]]*(#|$)/) {
        gsub(/[[:space:]]/, "", $0)
        skip[$0] = 1
      }
      next
    }
    { if (NF >= 2 && ($2 in skip)) next; print }
  ' "$2" "$1"
}

#############################################################################
# Submodules
#############################################################################

# Make sure a submodule is checked out before something reads it.
#
# remote-install.sh deliberately clones without --recurse-submodules, and the
# only init call anywhere used to be a one-off for the hosts submodule. So a
# remote install left modules/prezto empty; install_prezto.zsh's nullglob loop
# then matched nothing, ran zero iterations, and the caller printed [ok] over
# a prezto that was never installed.
#
# An initialised submodule has a .git *file* (a gitdir pointer), not a
# directory, so -e is the right test.
dotfiles_ensure_submodule() {
  _dfe_root="${DOTFILES_DIR:-.}"
  _dfe_path="$1"

  if [ -e "$_dfe_root/$_dfe_path/.git" ]; then
    unset _dfe_root _dfe_path
    return 0
  fi

  git -C "$_dfe_root" submodule update --init --depth 1 -- "$_dfe_path"
  _dfe_rc=$?
  unset _dfe_root _dfe_path
  return "$_dfe_rc"
}

#############################################################################
# Housekeeping
#############################################################################

# fnm creates a multishell directory per shell, named "<pid>_<timestamp>".
# Its default home is $TMPDIR, which macOS clears at boot -- but system/.env
# points XDG_RUNTIME_DIR at ~/.local/runtime, which is never cleared, so they
# accumulate without bound (39,803 of them by the time this was found).
#
# Age is NOT a safe proxy for "unused": a Claude Code or terminal session open
# for more than a day still resolves node through its own multishell dir, and
# deleting it takes `node` off PATH for that process with no way to recover
# short of restarting it. That is exactly what an earlier age-only version of
# this function did.
#
# The PID in the directory name is not a safe proxy either. It belongs to the
# short-lived `fnm env` process, not to the shell that goes on to use the
# directory, so it is dead within milliseconds of creation -- every live
# directory looks stale. Ask the process table which paths are actually in
# use, and keep the PID, PATH and FNM_MULTISHELL_PATH checks below as backstops.
dotfiles_prune_fnm_multishells() {
  _dfp_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/fnm_multishells"
  [ -d "$_dfp_dir" ] || { unset _dfp_dir; return 0; }

  # Basenames named by any live process environment, space-delimited for the
  # bash 3.2 safe membership test below.
  #
  # -A matters: without a selection flag macOS ps lists only processes on the
  # caller's own terminal, which is every terminal except the ones we are
  # trying not to break. -E prints each process environment after its argv.
  #
  # The first grep requires the path to appear as an environment assignment --
  # FNM_MULTISHELL_PATH=<dir>, or a <dir>/bin entry inside PATH -- rather than
  # anywhere on a line. ps prints argv too, so a bare match would let any
  # process that merely names a directory (a grep, an rm, a test) keep it
  # alive. The second grep keeps only the directory names, so nothing else
  # from the environment is retained.
  #
  # pgrep cannot read process environments, which is the whole point here.
  # shellcheck disable=SC2009
  _dfp_live=$(ps -A -E -ww -o command= 2>/dev/null |
    grep -oE 'FNM_MULTISHELL_PATH=[^[:space:]]*|/fnm_multishells/[0-9]+_[0-9]+/bin' |
    grep -oE 'fnm_multishells/[0-9]+_[0-9]+' |
    sed 's|.*/||' | sort -u | tr '\n' ' ')

  _dfp_removed=0
  while IFS= read -r _dfp_path; do
    [ -n "$_dfp_path" ] || continue

    # Never remove the one this very shell is using.
    [ "$_dfp_path" = "${FNM_MULTISHELL_PATH:-}" ] && continue

    # Nor any directory still on PATH. A process inherits PATH entries from a
    # parent that may since have exited, so the owning PID can be dead while
    # the entry is still live for us and every child we spawn.
    case ":$PATH:" in
      *":$_dfp_path/bin:"*) continue ;;
    esac

    _dfp_name=${_dfp_path##*/}
    _dfp_pid=${_dfp_name%%_*}

    # Named by a live process environment: in use, whatever its PID says.
    case " $_dfp_live " in
      *" $_dfp_name "*) continue ;;
    esac

    # Unrecognised name: leave it alone rather than guess.
    case "$_dfp_pid" in
      '' | *[!0-9]*) continue ;;
    esac

    # kill -0 succeeds while the process exists (and on EPERM, which also
    # means it exists), so a live owner is always spared.
    if kill -0 "$_dfp_pid" 2>/dev/null; then
      continue
    fi

    rm -rf "$_dfp_path" 2>/dev/null && _dfp_removed=$((_dfp_removed + 1))
  done << EOF
$(find "$_dfp_dir" -mindepth 1 -maxdepth 1 2>/dev/null)
EOF

  [ -n "${DOTFILES_VERBOSE:-}" ] && echo "pruned $_dfp_removed stale fnm multishell dirs"
  unset _dfp_dir _dfp_path _dfp_name _dfp_pid _dfp_removed _dfp_live
  return 0
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

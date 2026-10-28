#!/usr/bin/env bash
#
# Sourced by `dotfiles configure --defaults` (through the defaults*.sh loop) and
# by `dotfiles configure --remote-access`, never executed: no `set -e`.
#
# Makes this Mac reachable from a phone over Tailscale, safely: SSH with keys
# only plus macOS Screen Sharing, both answering only on Tailscale addresses.
# Tailscale here is the Mac App Store app, which cannot run Tailscale's own SSH
# server, so SSH is Apple's sshd (Remote Login). Who on the tailnet may connect
# is the Tailscale policy's business, not this file's.
#
# Only runs when remote access is on for this Mac (dotfiles_remote_access: the
# environment, else macos/machine.local.sh, else on for a desktop and off for a
# laptop). Off means one skip line and no change. Nothing here ever turns
# anything off.
#
# Order matters: the access groups, the keys-only sshd config and the
# Tailscale-only pf rules go in first, and Remote Login is switched on last,
# only when both of those took effect. Otherwise a failed step would leave sshd
# answering password logins on every network.

DOTFILES_DIR="${DOTFILES_DIR:=$HOME/.dotfiles}"

source "$DOTFILES_DIR/scripts/echos.sh"
source "$DOTFILES_DIR/scripts/lib/machine.sh"
source "$DOTFILES_DIR/scripts/lib/defaults-common.sh"

# Failed steps are counted here; `dotfiles configure` turns a non-zero count
# into a non-zero status. Kept, not reset: another defaults file may have
# counted failures already.
DOTFILES_DEFAULTS_FAILURES="${DOTFILES_DEFAULTS_FAILURES:-0}"

# _ra_put <src> <dest> -- install a root-owned, world-readable copy unless dest
# is already identical (cmp). Sets _RA_CHANGED to 1 when it wrote, 0 when not.
# The daemon and the config end up root:wheel 0644 so the user cannot edit
# what root runs or reads.
_ra_put() {
  if cmp -s "$1" "$2" 2>/dev/null; then
    _RA_CHANGED=0
    return 0
  fi
  _RA_CHANGED=1
  sudo install -m 0644 -o root -g wheel "$1" "$2"
}

_ra_fail() { DOTFILES_DEFAULTS_FAILURES=$((DOTFILES_DEFAULTS_FAILURES + 1)); }

if [ "$(dotfiles_remote_access)" = on ]; then
  bot "Remote access (SSH and Screen Sharing, over Tailscale only)"
  sudo -v

  # Firewall and stealth mode first: the same routine defaults.sh runs.
  dotfiles_firewall_on

  # Only the running user may log in. A group can exist with no members (seen on
  # a real Mac), which means nobody can log in, so membership is always ensured
  # and read back, not just the group's existence.
  _ra_user="${USER:-$(id -un)}"
  for _ra_group in com.apple.access_ssh com.apple.access_screensharing; do
    running "Only $_ra_user may log in through $_ra_group"
    _ra_good=1
    if ! dseditgroup -o read -q "$_ra_group" >/dev/null 2>&1; then
      sudo dseditgroup -o create -q "$_ra_group" >/dev/null 2>&1 || _ra_good=0
    fi
    if [ "$_ra_good" -eq 1 ]; then
      sudo dseditgroup -o edit -a "$_ra_user" -t user "$_ra_group" >/dev/null 2>&1 || _ra_good=0
    fi
    if [ "$_ra_good" -eq 1 ]; then
      dseditgroup -o checkmember -m "$_ra_user" "$_ra_group" >/dev/null 2>&1 || _ra_good=0
    fi
    if [ "$_ra_good" -eq 1 ]; then
      ok
    else
      error "could not make $_ra_user a member of $_ra_group (sudo dseditgroup -o edit -a $_ra_user -t user $_ra_group); without it nobody can log in through that service"
      _ra_fail
    fi
  done

  # sshd: keys only. Installed as 010-dotfiles.conf so it sorts before macOS's
  # 100-macos.conf (sshd keeps the first value it reads for each keyword).
  # Lockout guard: with no key in authorized_keys, switching passwords off would
  # leave no way in over SSH, so the file is not installed then. macOS starts
  # sshd per connection from launchd, so there is nothing to restart.
  running "Allow only key logins over SSH"
  _ra_sshd_ok=0
  _ra_keys="$HOME/.ssh/authorized_keys"
  if [ -f "$_ra_keys" ] && grep -qvE '^[[:space:]]*(#|$)' "$_ra_keys"; then
    _ra_sshd_src="$DOTFILES_DIR/macos/remote-access/sshd.conf"
    _ra_sshd_dest="${DOTFILES_SSHD_CONF_DIR:-/etc/ssh/sshd_config.d}/010-dotfiles.conf"
    if cmp -s "$_ra_sshd_src" "$_ra_sshd_dest" 2>/dev/null; then
      ok "already set"
      _ra_sshd_ok=1
    elif ! _ra_put "$_ra_sshd_src" "$_ra_sshd_dest"; then
      error "could not install $_ra_sshd_dest (sudo install failed)"
      _ra_fail
    else
      # A Mac that never ran Remote Login has no host keys yet, and sshd -t
      # refuses to run without them ("no hostkeys available"). Generate any that
      # are missing, as macOS does on the first Remote Login connection. The
      # system ssh-keygen, by absolute path: a Homebrew one would write them
      # under its own etc.
      sudo "${DOTFILES_SSH_KEYGEN:-/usr/bin/ssh-keygen}" -A >/dev/null 2>&1
      if _ra_sshd_msg=$(sudo "${DOTFILES_SSHD:-/usr/sbin/sshd}" -t 2>&1); then
        ok
        _ra_sshd_ok=1
      else
        sudo rm -f "$_ra_sshd_dest"
        error "sshd rejected the new configuration (sshd -t: ${_ra_sshd_msg%%$'\n'*}), so it was removed again; SSH is as it was"
        _ra_fail
      fi
    fi
  else
    error "no public key in ~/.ssh/authorized_keys: add your phone's public key there first, then run \`dotfiles configure --remote-access\` again (the sshd hardening is not installed without it, so you cannot lock yourself out)"
    _ra_fail
  fi

  # pf: SSH (22) and Screen Sharing (5900) reachable only on loopback and on
  # Tailscale addresses. The rules go into the anchor com.apple/900.dotfiles-remote.
  # Apple's /etc/pf.conf has `anchor "com.apple/*"`, which evaluates every anchor
  # attached directly to com.apple, so /etc/pf.conf is never edited. A
  # LaunchDaemon re-asserts the rules at boot and every five minutes, in case
  # macOS reloads pf.conf or something disables pf. It runs as root, so the
  # plist (root:wheel 0644) references only root-owned system paths and nothing
  # in the repo or a home directory.
  #
  # LAN peers (dotfiles_remote_lan_peers, validated there: the other Mac on the
  # home network) may connect too. The rules root loads are built from the
  # tracked file plus one pass line for them before the final block, and that
  # built file is what is parsed, compared and installed.
  _ra_lan=$(dotfiles_remote_lan_peers)
  running "Allow SSH and Screen Sharing only from Tailscale${_ra_lan:+ and $_ra_lan} (pf)"
  _ra_pf_label=com.stixzoor.dotfiles-pf-remote
  _ra_pf_anchor=com.apple/900.dotfiles-remote
  _ra_pf_src="$DOTFILES_DIR/macos/remote-access/pf.rules"
  _ra_pf_dest="${DOTFILES_PF_ANCHOR_DIR:-/etc/pf.anchors}/dotfiles.remote"
  _ra_plist_src="$DOTFILES_DIR/macos/remote-access/$_ra_pf_label.plist"
  _ra_plist_dest="${DOTFILES_LAUNCHDAEMONS_DIR:-/Library/LaunchDaemons}/$_ra_pf_label.plist"
  # Enforcing means both: the anchor lists rules, and pf itself is enabled.
  # Rules in a disabled pf filter nothing.
  _ra_pf_active() {
    [ -n "$(sudo pfctl -a "$_ra_pf_anchor" -sr 2>/dev/null)" ] &&
      sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"
  }
  _ra_pf_good=1
  _ra_pf_ok=0
  _ra_pf_changed=0
  if ! _ra_pf_built=$(mktemp "${TMPDIR:-/tmp}/dotfiles-pf.XXXXXX"); then
    error "could not create a temporary file for the pf rules (mktemp failed); nothing was installed"
    _ra_fail
    _ra_pf_good=0
  elif [ -n "$_ra_lan" ]; then
    awk -v line="pass in quick proto { tcp udp } from { $(printf '%s' "$_ra_lan" | sed 's/ /, /g') } to any port { 22 5900 }" \
      '/^block / && !done { print line; done = 1 } { print }' "$_ra_pf_src" >"$_ra_pf_built"
  else
    cat "$_ra_pf_src" >"$_ra_pf_built"
  fi
  if [ "$_ra_pf_good" -eq 1 ] && { ! cmp -s "$_ra_pf_built" "$_ra_pf_dest" 2>/dev/null || ! cmp -s "$_ra_plist_src" "$_ra_plist_dest" 2>/dev/null; }; then
    _ra_pf_changed=1
    # Parse the rules before anything is installed or loaded.
    if ! sudo pfctl -n -f "$_ra_pf_built" >/dev/null 2>&1; then
      error "pf rejected the rules built from macos/remote-access/pf.rules${_ra_lan:+ and DOTFILES_REMOTE_LAN_PEERS} (pfctl -n -f failed); nothing was installed"
      _ra_fail
      _ra_pf_good=0
    elif ! _ra_put "$_ra_pf_built" "$_ra_pf_dest" || ! _ra_put "$_ra_plist_src" "$_ra_plist_dest"; then
      error "could not install the pf rules and their LaunchDaemon (sudo install failed)"
      _ra_fail
      _ra_pf_good=0
    fi
  fi
  if [ "$_ra_pf_good" -eq 1 ]; then
    if [ "$_ra_pf_changed" -eq 1 ] || ! _ra_pf_active; then
      sudo launchctl bootout "system/$_ra_pf_label" >/dev/null 2>&1
      if ! sudo launchctl bootstrap system "$_ra_plist_dest" >/dev/null 2>&1; then
        error "launchctl could not load the pf LaunchDaemon ($_ra_plist_dest)"
        _ra_fail
        _ra_pf_good=0
      fi
    fi
  fi
  if [ "$_ra_pf_good" -eq 1 ]; then
    # launchd runs the job on its own time after bootstrap: give it a moment.
    _ra_wait=0
    until _ra_pf_active || [ "$_ra_wait" -ge "${DOTFILES_PF_WAIT:-5}" ]; do
      sleep 1
      _ra_wait=$((_ra_wait + 1))
    done
    if _ra_pf_active; then
      if [ "$_ra_pf_changed" -eq 1 ]; then ok; else ok "already set"; fi
      _ra_pf_ok=1
    else
      error "pf is not enforcing $_ra_pf_anchor (no rules listed, or pf disabled): SSH and Screen Sharing are not restricted to Tailscale (check: sudo pfctl -s info; sudo pfctl -a $_ra_pf_anchor -sr)"
      _ra_fail
    fi
  fi

  [ -z "${_ra_pf_built:-}" ] || rm -f "$_ra_pf_built"

  # Remote Login (SSH) on, last. -f suppresses the confirmation prompt, which
  # would otherwise block forever because it is written to a stream that goes to
  # /dev/null while stdin is still the terminal. See `man systemsetup`,
  # -setremotelogin [-f] on | off.
  #
  # The state is read first and the setter only runs when it is off: without
  # Full Disk Access the setter errors even when Remote Login is already on
  # (enabled by hand), and `-getremotelogin` needs Full Disk Access too, reading
  # Off while sshd runs. So the state is read from systemsetup, from launchd's
  # disabled list and from sshd listening on port 22; the last two need no Full
  # Disk Access. Remote Login that is already on is left on whatever happened
  # above: nothing here turns anything off.
  _remote_login_on() {
    sudo systemsetup -getremotelogin 2>/dev/null | grep -q "Remote Login: On" ||
      sudo launchctl print-disabled system 2>/dev/null | grep -q '"com.openssh.sshd" => enabled' ||
      nc -z 127.0.0.1 22 >/dev/null 2>&1
  }
  running "Enable remote login"
  if _remote_login_on; then
    ok "already on"
  elif [ "$_ra_sshd_ok" -ne 1 ] || [ "$_ra_pf_ok" -ne 1 ]; then
    error "Remote Login left off: it is switched on only once SSH takes keys only and answers only on Tailscale (fix the errors above, then run \`dotfiles configure --remote-access\` again)"
    _ra_fail
  else
    sudo systemsetup -setremotelogin -f on >/dev/null 2>&1
    if _remote_login_on; then
      ok
    else
      error "Remote Login is off: turn it on in System Settings, General, Sharing, Remote Login (or grant Full Disk Access to this terminal), then run \`dotfiles configure --remote-access\` again"
      _ra_fail
    fi
  fi

  # Screen Sharing cannot be switched on reliably from the command line on
  # current macOS, so it is only checked, and the owner is told what to click.
  running "Screen Sharing is on"
  if nc -z 127.0.0.1 5900 >/dev/null 2>&1; then
    ok
  else
    action "Turn Screen Sharing on: System Settings > General > Sharing > Screen Sharing, then (i) > Allow access for: Only these users"
  fi
  # The old password-protected VNC mode would let anyone on the tailnet in with
  # one shared password.
  if [ -e "${DOTFILES_VNC_SETTINGS:-/Library/Preferences/com.apple.VNCSettings.txt}" ]; then
    warn "the legacy \"VNC viewers may control screen with password\" setting is on: turn it off in Screen Sharing's (i) panel"
  fi
  echo -e " ⇒ SSH and Screen Sharing now answer only on Tailscale: use this Mac's Tailscale name, not its LAN address"

  unset _ra_user _ra_group _ra_good _ra_keys _ra_sshd_ok _ra_sshd_msg _ra_sshd_src _ra_sshd_dest _ra_pf_label _ra_pf_anchor _ra_pf_src \
    _ra_pf_dest _ra_plist_src _ra_plist_dest _ra_pf_good _ra_pf_ok _ra_pf_changed _ra_wait _ra_lan _ra_pf_built _RA_CHANGED
else
  skip "remote access: off for this Mac (DOTFILES_REMOTE_ACCESS=on in macos/machine.local.sh turns it on); nothing changed"
fi

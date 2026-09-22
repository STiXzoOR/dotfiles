#!/usr/bin/env bash
#
# Shared SSH setup helpers.
#
# Sourced by bin/dotfiles (sub_install_ssh). bin/dotfiles-setup no longer has
# its own copy of this logic: it delegates the whole step through
# `run_cli "SSH key" install --ssh`, so the two cannot drift apart. They did
# drift once, when the wizard generated passphrase-less keys and never wrote
# ~/.ssh/config, which meant no UseKeychain and a passphrase prompt in every
# new shell.

# Ensure ~/.ssh/config carries the Host * block that lets ssh take the key
# passphrase from the macOS Keychain instead of asking for it every time.
#
# Idempotent: if the block is already there this is a no-op. Any pre-existing
# config is backed up first and the block is appended, never overwritten, so
# custom Host entries survive.
dotfiles_ensure_ssh_config() {
  local ssh_dir="$HOME/.ssh"
  local ssh_config="$ssh_dir/config"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  # Look for the block this function actually writes, not for an IdentityFile
  # line. Someone whose config already names that key inside a specific
  # `Host github.com` stanza would otherwise never get the global `Host *`
  # block with UseKeychain, which is the whole point of the function.
  if grep -q "^Host \*" "$ssh_config" 2>/dev/null &&
    grep -q "UseKeychain" "$ssh_config" 2>/dev/null; then
    return 0
  fi

  if [[ -f "$ssh_config" ]]; then
    cp "$ssh_config" "$ssh_config.backup.$(date +%Y%m%d%H%M%S)"
  else
    # zsh with `setopt noclobber` refuses to create a missing file via `>>`,
    # so make sure it exists before appending.
    touch "$ssh_config"
  fi

  cat >>"$ssh_config" <<'SSH_EOF'

Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
SSH_EOF

  chmod 600 "$ssh_config"
}

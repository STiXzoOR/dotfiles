# CLI Commands

All operations go through `./bin/dotfiles <command>`. Run `./bin/dotfiles help` for the full list.

## Key Commands

```
install                 # Bootstrap system (interactive)
install --all           # Install everything non-interactively
install --hosts         # Update /etc/hosts with ad-blocking
install --prezto        # Install Prezto zsh framework
install --packages      # Install brew/cask/npm/mas/vscode packages
install --ssh           # Generate SSH key (ed25519)
link                    # Symlink dotfiles to ~/ via GNU Stow
unlink <timestamp>      # Restore dotfiles from backup
configure --defaults    # Apply macOS system defaults
configure --dock        # Configure Dock settings
update                  # Update submodules (interactive, prompts for commit msg)
update --system         # Update OS, brew, npm, gem packages
test                    # Run test suite
test --verbose          # Detailed test output
doctor                  # Diagnose common issues
doctor --fix            # Auto-fix issues where possible
hooks                   # Install git pre-commit hooks
```

## Common Workflows

**Add a new brew/cask/mas package**: Add to `Brewfile`, run `brew bundle install`.

**Add a new npm/vscode package**: Add to `packages/npm.list` or `packages/code.list`, run `./bin/dotfiles install --packages`.

**Modify system defaults**: Edit script in `macos/`, run `./bin/dotfiles configure --defaults`. Requires logout/restart.

**Manage hosts whitelist**: Add domains to `system/hosts.whitelist` (one per line), run `./bin/dotfiles install --hosts`. The whitelist is copied into the stevenblack-hosts module during installation.

# CLI Commands

All operations go through `./bin/dotfiles <command>`. Run `./bin/dotfiles help`
for the authoritative list; this page mirrors it.

## Commands

```
cheatsheet              # Show the aliases and functions cheatsheet
claude                  # Inspect the installed Claude Code setup (see below)
clean                   # Clean up caches (brew, npm, gem)
configure               # Configure the system (defaults, dock)
doctor                  # Diagnose common issues
edit                    # Open the dotfiles in $DOTFILES_IDE
help                    # Command list
hooks                   # Install the git pre-commit hooks
install                 # Bootstrap the system
link                    # Link dotfiles into ~/ via GNU Stow
open                    # Open the dotfiles in Finder
profiler                # Profile shell startup time
secrets                 # Manage secrets in the macOS Keychain
setup                   # Run the interactive setup wizard
test                    # Run the test suite
unlink <timestamp>      # Restore dotfiles from ~/.dotfiles_backup
update                  # Update submodules
```

`baseline` is not a `dotfiles` subcommand; the macOS defaults baseline is
captured directly with `./bin/dotfiles-baseline`, which records every declared
default and diffs a later capture against it.

## install flags

```
install --all           # Everything below
install --claude        # Claude Code: binary, marketplaces, plugins, hooks, rules, settings, QMD
install --fonts         # Local fonts
install --homebrew      # Homebrew itself
install --hosts         # Ad-blocking hosts file
install --launchagents  # LaunchAgents from launchagents/disabled/
install --node          # fnm and the latest LTS Node
install --packages      # npm globals and VS Code extensions
install --passwordless  # sudo without a password
install --prezto        # The zsh framework
install --ssh           # SSH key (ed25519)
install --vim           # Vim/Neovim plugins
```

## test and configure flags

```
test --verbose          # Detailed output
test --quick            # Skip the slow startup-timing tests
configure --defaults    # Apply the macOS system defaults
configure --dock        # Apply the Dock settings
update --system         # Update the OS and package managers
```

## dotfiles claude

```
dotfiles claude diff    # Compare claude/ against ~/.claude; exit 1 on drift
dotfiles claude verify  # Run each configured hook command with a synthetic payload
```

Both are read-only. `diff` is the check to run before editing anything under
`claude/`: the repo and the installed copy drift silently otherwise, which is
how three separate P1 bugs reached `main`. `verify` executes each hook command
under a restricted PATH with `CLAUDE_HOOK_DRY_RUN=1`, so it catches a missing
interpreter or an unreachable binary without doing any work.

## Common Workflows

**Add a brew, cask or MAS package**: add it to `Brewfile`, run `brew bundle install`.

**Add a Node CLI**: add `"npm:<package>" = "latest"` to `[tools]` in
`config/mise/config.toml`, run `./bin/dotfiles install --node`, and commit the
config with the regenerated `config/mise/mise.lock`.

**Add a VS Code extension**: add it to
`packages/code.list`, run `./bin/dotfiles install --packages`.

**Modify a system default**: edit the script in `macos/`, run
`./bin/dotfiles configure --defaults`. Requires a logout or restart.

**Manage the hosts whitelist**: add domains to `system/hosts.whitelist`, one per
line, then run `./bin/dotfiles install --hosts`.

**Change a Claude Code hook, rule or the status line**: edit it under `claude/`,
run `bash tests/claude.sh`, then `dotfiles claude diff` to see what a re-install
would change, then `dotfiles install --claude`.

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
apps <check|backup|restore|list|undo>  # App settings backup (mackup, copy mode); see app-settings.md
private <init|clone|link|status|hook>  # Private companion repo for the gitignored files; see two-mac-sync.md
sync [--scheduled]      # Keep this Mac current: fetch, fast-forward, restow, report drift; see two-mac-sync.md
vault migrate           # Move ~/Vault into iCloud Drive, leaving a symlink; see two-mac-sync.md
jev <status|log|replay|promote|scan-vault>  # Jev privacy and secrets guards (shadow by default); see jev.md
setup                   # Run the interactive setup wizard
test                    # Run the test suite
unlink <timestamp>      # Restore dotfiles from ~/.dotfiles_backup
update                  # Update submodules
```

`baseline` is not a `dotfiles` subcommand; the macOS defaults baseline is
captured directly with `./bin/dotfiles-baseline`, which records every declared
default and diffs a later capture against it. `dotfiles-baseline changed [label]`
lists declared keys whose live value differs from the snapshot (read-only);
`dotfiles sync` hands them to the Jev `drift` point.

## install flags

```
install                 # Bootstrap: sudo keep-alive, Command Line Tools, git hooks, Homebrew, stow, SSH key
install --all           # The steps below in order: prezto, private, link, node, packages, fonts,
                        #   launchagents, claude, codex, configure, hosts (last)
install --claude        # Claude Code: binary, marketplaces, plugins, hooks, rules, settings, QMD
install --codex         # Codex CLI (runs scripts/install_codex.sh)
install --fonts         # Local fonts
install --homebrew      # Homebrew itself
install --hosts         # Ad-blocking hosts file
install --launchagents  # LaunchAgents from launchagents/ (see launchagents/disabled/)
install --node          # mise, Node and the CLIs in config/mise/config.toml (run link first)
install --packages      # Brewfile (+ Brewfile.local) and VS Code extensions
install --prezto        # The zsh framework
install --private       # Clone the private companion repo and link its files (two-mac-sync.md)
install --ssh           # SSH key (ed25519)
```

Behaviours worth knowing:

- **Failures are collected.** `install` and `install --all` run every step, record
  each failure, and finish with a summary naming the failed steps and a non-zero
  exit status. The success banner appears only when nothing failed. A failed
  Command Line Tools install aborts `install` immediately, since nothing after it
  can work.
- **Unattended runs.** With `DOTFILES_YES=1` (`install --all`) the Homebrew
  installer runs with `NONINTERACTIVE=1`; sudo is already cached.
- **`link` keeps ignored files.** Stow swaps a real `~/.config/gh` for a symlink
  into the repo. Files the repo git-ignores (`gh/hosts.yml`, the login) are copied
  from the backup into `config/` so they stay live; existing files are never
  overwritten.
- **`--node` refuses to run before `link`.** mise reads `~/.config/mise`, which must
  resolve to `config/mise` in this checkout; pointing `MISE_GLOBAL_CONFIG_FILE` at
  the repo instead makes mise rewrite the paths in `mise.lock`. It also installs
  `gnupg`, which the Node download verification needs.
- **`--packages` never stops halfway.** Each tap is tapped then trusted, a failed
  bundle is recorded and the VS Code step still runs, missing extensions are found
  with a single `--list-extensions` call, and the step returns non-zero if
  anything failed. `Brewfile.local` and `packages/code.local.list` (both
  gitignored) are read alongside the public files.
- **`--hosts` backs up once.** `/etc/hosts.backup` is written only if it does not
  exist, so a re-run cannot replace the pristine file with the blocklist.
- **Command Line Tools** are installed headlessly by `scripts/lib/clt.sh`
  (shared by `install`, `setup` and `remote-install.sh`), which picks the highest
  version `softwareupdate` offers rather than the last one listed.

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
`packages/code.list` (or, for a private one, the gitignored
`packages/code.local.list`), run `./bin/dotfiles install --packages`.

**Modify a system default**: edit the script in `macos/`, run
`./bin/dotfiles configure --defaults`. Requires a logout or restart.

**Manage the hosts whitelist**: add domains to `system/hosts.whitelist`, one per
line, then run `./bin/dotfiles install --hosts`.

**Change a Claude Code hook, rule or the status line**: edit it under `claude/`,
run `bash tests/claude.sh`, then `dotfiles claude diff` to see what a re-install
would change, then `dotfiles install --claude`.

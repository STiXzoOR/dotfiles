# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a macOS dotfiles repository for automated system setup and configuration management. It bootstraps a fresh or existing macOS machine with personalized system defaults, development tools, applications, and shell configurations. The repository uses git submodules extensively for managing external dependencies like Prezto (zsh framework), themes, and plugins.

## Core Commands

All operations are managed through the `./bin/dotfiles` script. Common workflows:

### Initial Setup
```bash
# Remote installation (fresh machine)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/STiXzoOR/dotfiles/main/remote-install.sh)"

# Manual installation
git clone --recurse-submodules https://github.com/STiXzoOR/dotfiles ~/.dotfiles
cd ~/.dotfiles
./bin/dotfiles install
```

### Development Commands
```bash
./bin/dotfiles help                    # Show all available commands
./bin/dotfiles install                 # Bootstrap system (interactive)
./bin/dotfiles install --all           # Install everything non-interactively
./bin/dotfiles link                    # Symlink dotfiles to ~/
./bin/dotfiles configure               # Apply system defaults and dock settings
./bin/dotfiles update                  # Update submodules and push changes
./bin/dotfiles clean                   # Clean up caches (brew, npm, etc.)
```

### Selective Installation
```bash
./bin/dotfiles install --hosts         # Update /etc/hosts with ad-blocking
./bin/dotfiles install --prezto        # Install Prezto zsh framework
./bin/dotfiles install --vim           # Install vim plugins
./bin/dotfiles install --fonts         # Install powerline fonts
./bin/dotfiles install --packages      # Install brew/cask/npm/mas/vscode packages
./bin/dotfiles install --launchagents  # Install LaunchAgents (mackup auto-backup)
./bin/dotfiles install --ssh           # Generate SSH key
./bin/dotfiles install --passwordless  # Make sudo passwordless
```

### Configuration
```bash
./bin/dotfiles configure --defaults    # Apply macOS system defaults
./bin/dotfiles configure --dock        # Configure Dock settings
```

### Updates and Maintenance
```bash
./bin/dotfiles update --system         # Update OS, brew, npm, gem packages
./bin/dotfiles clean                   # Clean homebrew and npm caches
```

## Architecture

### Directory Structure

- **`bin/`** - Utility scripts and main `dotfiles` command
  - `dotfiles` - Main entry point for all operations
  - `is-*` - Helper scripts for system detection (Apple Silicon, macOS, etc.)
  - `command-exists` - Check if command is available

- **`scripts/`** - Core installation and utility scripts
  - `echos.sh` - Colorized output functions (bot, ok, error, etc.)
  - `requirers.sh` - Package installation helpers (require_brew, require_cask, require_npm, etc.)
  - `install_prezto.zsh` - Prezto framework setup

- **`packages/`** - Package list files
  - `brew.list` - Homebrew CLI utilities
  - `cask.list` - GUI applications via Homebrew Cask
  - `npm.list` - Global npm packages
  - `mas.list` - Mac App Store applications
  - `code.list` - VS Code extensions
  - `tap.list` - Homebrew taps

- **`macos/`** - macOS system configuration scripts
  - `defaults.sh` - Main system preferences
  - `defaults-*.sh` - App-specific settings (Safari, Chrome, Xcode, etc.)
  - `dock.sh` - Dock configuration

- **`runcom/`** - Dotfiles symlinked to `~/` using GNU Stow
  - `.zshrc`, `.zprofile`, `.zlogin` - Zsh configuration
  - `.vimrc` - Vim configuration
  - `.gemrc`, `.mackup.cfg` - Tool configurations
  - `.zpreztorc` - Prezto configuration

- **`config/`** - XDG config files symlinked to `~/.config/` using GNU Stow
  - Contains application-specific configurations (Karabiner, Spicetify, etc.)

- **`modules/`** - Git submodules for external dependencies
  - `prezto/` - Prezto zsh framework
  - `prezto-contrib/` - Additional Prezto modules
  - `zsh/` - Additional zsh plugins (zsh-autocomplete, zsh-thefuck, zsh-lazy-load)
  - `stevenblack-hosts/` - Unified hosts file for ad-blocking

- **`apps/`** - Application-specific themes and configurations
  - `terminal/` - Terminal.app Nord theme
  - `xcode/` - Xcode Nord theme
  - `warp/` - Warp terminal themes (base16 and others)
  - `gitkraken/` - GitKraken custom themes
  - `vlc/` - VLC settings and preferences

- **`fonts/`** - Powerline fonts for terminal
  - `install.sh` - Font installation script

- **`launchagents/`** - macOS LaunchAgents for automated tasks
  - `com.user.mackup-auto.plist` - Auto-backup mackup settings every hour

### Key Technical Details

**Package Management Flow:**
The `install_packages()` function in `bin/dotfiles` reads package lists and uses corresponding `require_*` functions from `scripts/requirers.sh`. Each package type has idempotent installation logic that checks if already installed before attempting installation.

**Dotfile Linking:**
Uses GNU Stow for symlink management. Running `./bin/dotfiles link` will:
1. Backup existing dotfiles to `~/.dotfiles_backup/$(date)`
2. Stow `runcom/` directory to `~/`
3. Stow `config/` directory to `~/.config/`

**Node.js Management:**
Switched from NVM to FNM (Fast Node Manager) for better performance. Functions `require_fnm()` and `source_fnm()` handle Node.js version management.

**System Detection:**
The repository supports both Intel and Apple Silicon Macs via `bin/is-apple-silicon`. Homebrew prefix is automatically detected as `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel).

**Interactive Installation:**
Most commands prompt for confirmation before making changes. The `--all` flag bypasses prompts for automated setup.

## Important Notes

- The installation process will open Warp terminal and close Terminal.app at the end
- Original dotfiles are backed up to `~/.dotfiles_backup/` with timestamp before being replaced
- The `/etc/hosts` installation uses StevenBlack's unified hosts file with Python virtual environment to avoid system-level pip pollution
- Submodules must be initialized: `git submodule update --init --recursive`
- The repository uses Prezto instead of Oh My Zsh for better performance
- The shell prompt uses Starship for cross-shell prompt customization
- Node.js version management uses FNM (Fast Node Manager) instead of NVM for better performance
- System defaults require logout/restart to take full effect
- Vim uses Vundle for plugin management (stored as a git submodule)
- LaunchAgents automate mackup backups every hour (logs: `/tmp/mackup.log` and `/tmp/mackup.err`)

## Common Workflows

**Adding a new package:**
1. Add package name to appropriate file in `packages/`
2. Run `./bin/dotfiles install --packages`

**Updating submodules:**
```bash
./bin/dotfiles update  # Interactive - prompts for commit message
# Or manually:
git submodule update --remote --recursive --merge
```

**Restoring old dotfiles:**
```bash
./bin/dotfiles unlink YYYY.MM.DD.HH.MM.SS
```

**Modifying system defaults:**
Edit appropriate script in `macos/` directory, then run:
```bash
./bin/dotfiles configure --defaults
```

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
./bin/dotfiles unlink YYYY.MM.DD...    # Restore dotfiles from backup
./bin/dotfiles configure               # Apply system defaults and dock settings
./bin/dotfiles update                  # Update submodules and push changes
./bin/dotfiles clean                   # Clean up caches (brew, npm, etc.)
./bin/dotfiles open                    # Open dotfiles directory in Finder
./bin/dotfiles edit                    # Open dotfiles in IDE ($DOTFILES_IDE)
./bin/dotfiles test                    # Run test suite to validate configuration
./bin/dotfiles test --verbose          # Run tests with detailed output
./bin/dotfiles doctor                  # Diagnose common issues
./bin/dotfiles doctor --fix            # Auto-fix issues where possible
./bin/dotfiles hooks                   # Install git pre-commit hooks
```

### Selective Installation
```bash
./bin/dotfiles install --hosts         # Update /etc/hosts with ad-blocking
./bin/dotfiles install --prezto        # Install Prezto zsh framework
./bin/dotfiles install --vim           # Install Vim plugins via Vundle
./bin/dotfiles install --fonts         # Install powerline fonts
./bin/dotfiles install --packages      # Install brew/cask/npm/mas/vscode packages
./bin/dotfiles install --launchagents  # Install LaunchAgents (mackup auto-backup)
./bin/dotfiles install --ssh           # Generate SSH key (ed25519)
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
  - `dotfiles-test` - Test suite for validating shell configuration
  - `dotfiles-doctor` - Health check and diagnostics tool
  - `is-apple-silicon` - Detect Apple Silicon Macs
  - `is-macos` - Detect macOS system
  - `is-executable` - Check if file is executable
  - `is-supported` - Conditional execution helper (runs command based on condition)
  - `command-exists` - Check if command is available
  - `plistbuddy` - Helper for editing plist files

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
  - `.zpreztorc` - Prezto configuration
  - `.profile` - POSIX shell profile
  - `.vimrc` - Vim configuration
  - `.vim/` - Vim directory (contains Vundle as a submodule)
  - `.vim-spell-en.utf-8.add` - Custom vim spell file
  - `.gemrc` - Ruby gem configuration
  - `.mackup.cfg` - Mackup backup configuration
  - `.hushlogin` - Suppress login message
  - `.huskyrc` - Husky git hooks configuration

- **`config/`** - XDG config files symlinked to `~/.config/` using GNU Stow
  - `git/` - Git configuration (aliases, settings)
  - `husky/` - Husky git hooks configuration
  - `karabiner/` - Karabiner-Elements keyboard customization
  - `prettier/` - Prettier code formatter configuration
  - `spicetify/` - Spotify customization
  - `starship/` - Starship prompt configuration
  - `thefuck/` - TheFuck command correction settings

- **`modules/`** - Git submodules for external dependencies
  - `prezto/` - Prezto zsh framework
  - `prezto-contrib/` - Additional Prezto modules
  - `zsh/` - Additional zsh plugins (zsh-autocomplete, zsh-thefuck, zsh-lazy-load)
  - `stevenblack-hosts/` - Unified hosts file for ad-blocking

- **`system/`** - Shell configuration files sourced by `.zshrc`
  - `.alias` - Shell aliases
  - `.bindings` - Key bindings
  - `.completion` - Shell completion settings
  - `.dir_colors` - Directory colors for ls
  - `.env` - Environment variables
  - `.fnm` - FNM (Fast Node Manager) configuration
  - `.function`, `.function_*` - Shell functions (general, filesystem, network, text, fun)
  - `.fzf` - FZF fuzzy finder configuration
  - `.grep` - Grep configuration
  - `.path` - PATH environment setup
  - `.pnpm` - PNPM configuration
  - `.prompt` - Prompt configuration (fallback)
  - `.starship` - Starship prompt loader
  - `.zoxide` - Zoxide directory jumper configuration
  - `hosts.whitelist` - Whitelist for domains that should not be blocked by hosts file

- **`apps/`** - Application-specific themes and configurations
  - `terminal/` - Terminal.app Nord theme
  - `xcode/` - Xcode Nord theme
  - `warp/` - Warp terminal themes (base16 and others)
  - `gitkraken/` - GitKraken custom themes
  - `vlc/` - VLC settings and preferences
  - `vscode/` - VS Code themes and settings

- **`fonts/`** - Powerline fonts for terminal
  - `install.sh` - Font installation script

- **`completions/`** - Shell completion scripts
  - `_fnm` - FNM (Fast Node Manager) zsh completions

- **`resources/`** - Documentation resources
  - `terminal.png` - Terminal screenshot for README

- **`launchagents/`** - macOS LaunchAgents for automated tasks
  - `com.user.mackup-auto.plist` - Auto-backup mackup settings every hour

- **`profiles/`** - Machine-specific configurations
  - `default.zsh` - Base settings loaded on all machines
  - `personal.zsh` / `work.zsh` - Machine-specific profiles
  - `local.zsh` - Machine-specific overrides (gitignored)

- **`.github/workflows/`** - GitHub Actions CI/CD
  - `ci.yml` - Automated testing on push/PR

- **`.githooks/`** - Git hooks for development
  - `pre-commit` - Validates shell syntax and runs shellcheck

- **`Brewfile`** - Homebrew bundle manifest for all packages
  - Taps, formulae, casks, and Mac App Store apps
  - Install with: `brew bundle install`

### Key Technical Details

**Package Management Flow:**
The preferred method is using the `Brewfile` with `brew bundle install`. This handles taps, formulae, casks, and Mac App Store apps in one command. Legacy `.list` files in `packages/` are still supported as a fallback. NPM packages and VS Code extensions are installed separately via `packages/npm.list` and `packages/code.list`.

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
- Custom whitelist support: Add domains to `system/hosts.whitelist` (one per line) to prevent them from being blocked. The whitelist is copied to the stevenblack-hosts module as `whitelist` during the hosts installation process
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

**Managing hosts whitelist:**
Add domains to whitelist to prevent them from being blocked:
```bash
# Add domain to whitelist
echo "example.com" >> system/hosts.whitelist

# Reinstall hosts file with updated whitelist
./bin/dotfiles install --hosts
```

## Testing

The repository includes a comprehensive test suite to validate shell configuration:

```bash
./bin/dotfiles test              # Run all tests
./bin/dotfiles test --verbose    # Show detailed output
./bin/dotfiles test --quick      # Skip slow tests (startup timing)
```

**Test Categories:**
- **Syntax Validation** - Checks all zsh/bash files for syntax errors
- **Cache Generation** - Validates that all cached initializations work (fnm, zoxide, fzf, etc.)
- **Function Tests** - Tests core functions like `prepend-path`, `get`, `dedup-pathvar`
- **Alias Tests** - Verifies aliases are properly defined
- **Environment Tests** - Checks XDG and essential environment variables
- **Shell Startup** - Measures shell startup time (target: <1000ms)
- **File Structure** - Validates required directories and files exist
- **Prezto Configuration** - Checks Prezto submodule and configuration

**Refreshing Caches:**
Shell initialization outputs are cached for performance. To refresh:
```bash
rm ~/.cache/*.zsh     # Clear all shell caches
fnm_refresh           # Refresh fnm cache specifically
exec $SHELL           # Restart shell to regenerate caches
```

## Machine Profiles

Support for machine-specific configurations (work vs personal):

```bash
# Set profile via environment variable
export DOTFILES_PROFILE="work"

# Or create a profile matching your hostname
cp profiles/work.zsh.example profiles/$(hostname -s).zsh
```

**Profile Loading Order:**
1. `profiles/default.zsh` - Always loaded
2. `profiles/$DOTFILES_PROFILE.zsh` or `profiles/$(hostname).zsh`
3. `profiles/local.zsh` - Machine-specific overrides (gitignored)

See `profiles/README.md` for detailed documentation.

## Doctor Command

Diagnose common dotfiles issues:

```bash
./bin/dotfiles doctor          # Check for issues
./bin/dotfiles doctor --fix    # Auto-fix where possible
```

**Checks performed:**
- Symlink status (dotfiles properly linked)
- Git submodules initialized
- Shell configuration (zsh, prezto, starship)
- Homebrew status and outdated packages
- Cache file status and age
- Essential tools installed
- Node.js environment (fnm, npm, pnpm)
- Git configuration and SSH keys
- macOS-specific settings

## CI/CD

GitHub Actions automatically run on push/PR:
- Shell syntax validation (bash and zsh)
- Shellcheck linting
- Test suite execution
- Brewfile validation

## Git Hooks

Install pre-commit hooks for development:

```bash
./bin/dotfiles hooks
```

**Pre-commit checks:**
- Bash syntax validation
- Zsh syntax validation
- Shellcheck linting
- Secret detection (prevents committing passwords/keys)

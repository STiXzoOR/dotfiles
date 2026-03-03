# Architecture

## Directory Layout

| Directory       | Purpose                                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------------------- |
| `bin/`          | Main `dotfiles` CLI and utility scripts (`is-apple-silicon`, `command-exists`, etc.)                     |
| `scripts/`      | Install helpers — `echos.sh` (colored output), `requirers.sh` (package installers), `install_prezto.zsh` |
| `packages/`     | Package lists: `brew.list`, `cask.list`, `npm.list`, `mas.list`, `code.list`, `tap.list`                 |
| `macos/`        | System defaults scripts — `defaults.sh`, `defaults-*.sh` (per-app), `dock.sh`                            |
| `runcom/`       | Dotfiles stowed to `~/` — `.zshrc`, `.zprofile`, `.vimrc`, `.zpreztorc`, etc.                            |
| `config/`       | XDG config stowed to `~/.config/` — `git/`, `nvim/`, `karabiner/`, `starship/`, `thefuck/`, etc.         |
| `modules/`      | Git submodules — `prezto/`, `prezto-contrib/`, `zsh/` plugins, `stevenblack-hosts/`                      |
| `system/`       | Shell config sourced by `.zshrc` — `.alias`, `.env`, `.path`, `.function*`, `.fzf`, `.prompt`, etc.      |
| `claude/`       | Claude Code config — `marketplaces.list`, `plugins.list`, `settings.template.json`, `rules/`, `hooks/`   |
| `apps/`         | App themes — Terminal, Xcode, Warp, GitKraken, VLC, VS Code                                              |
| `fonts/`        | Powerline fonts with `install.sh`                                                                        |
| `profiles/`     | Machine-specific config — `default.zsh`, `personal.zsh`, `work.zsh`, `local.zsh` (gitignored)            |
| `launchagents/` | macOS LaunchAgents — mackup auto-backup every hour                                                       |
| `completions/`  | Zsh completions (e.g., `_fnm`)                                                                           |
| `Brewfile`      | Homebrew bundle manifest (taps, formulae, casks, MAS apps)                                               |

## GNU Stow Linking

`./bin/dotfiles link` does:

1. Backs up existing dotfiles to `~/.dotfiles_backup/<timestamp>`
2. Stows `runcom/` → `~/`
3. Stows `config/` → `~/.config/`

To restore: `./bin/dotfiles unlink <timestamp>`

## Submodules

External dependencies are git submodules in `modules/`:

- **Prezto** + contrib modules (shell framework)
- **zsh plugins** (zsh-thefuck, zsh-lazy-load)
- **StevenBlack hosts** (ad-blocking `/etc/hosts`)
- **Vundle** (Vim plugin manager, in `runcom/.vim/bundle/Vundle.vim`)

Update: `./bin/dotfiles update` or `git submodule update --remote --recursive --merge`

## System Detection

Both Intel and Apple Silicon supported:

- `bin/is-apple-silicon` — returns 0 on AS
- Homebrew: `/opt/homebrew` (AS) or `/usr/local` (Intel)
- Detected automatically in shell config via `$HOMEBREW_PREFIX`

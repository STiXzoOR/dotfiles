# AGENTS.md

macOS dotfiles repo — bootstraps a machine with system defaults, dev tools, apps, and shell config.

## Essentials

- **Language**: zsh (shell config), bash (install scripts)
- **Entry point**: `./bin/dotfiles <command>` — run `./bin/dotfiles help` for full reference
- **Test**: `./bin/dotfiles test` (must pass before committing)
- **Lint**: shellcheck (runs in CI and pre-commit hooks)
- **CI**: GitHub Actions on push/PR — syntax validation, shellcheck, tests, Brewfile validation
- **Link method**: GNU Stow — `runcom/` stows to `~/`, `config/` stows to `~/.config/`

## Critical Context

These affect nearly every task:

- **Submodules**: External deps (Prezto, hosts, zsh plugins) live in `modules/`. Always `git submodule update --init --recursive` after clone.
- **Intel + Apple Silicon**: Both supported. Homebrew prefix is `/opt/homebrew` (AS) or `/usr/local` (Intel). Use `bin/is-apple-silicon` to detect.
- **Prezto, not Oh My Zsh**: Shell framework is Prezto for performance. Prompt is Powerlevel10k via Prezto's prompt module. Starship config exists in `system/.starship` but is **not sourced**.
- **FNM, not NVM**: Node.js managed by FNM (Fast Node Manager). Use `require_fnm()` and `source_fnm()`.
- **Packages**: Brewfile for brew/cask/mas (`brew bundle install`). `.list` files in `packages/` for npm, vscode extensions, and other tools Brewfile doesn't support. See [packages.md](docs/agents/packages.md).
- **Backups**: Dotfile linking backs up originals to `~/.dotfiles_backup/<timestamp>` before replacing.

## Detail Docs

| Topic                                         | File                                               |
| --------------------------------------------- | -------------------------------------------------- |
| Directory structure, Stow linking, submodules | [architecture.md](docs/agents/architecture.md)     |
| CLI commands and common workflows             | [commands.md](docs/agents/commands.md)             |
| Zsh config, Prezto, profiles, caching, PATH   | [shell-config.md](docs/agents/shell-config.md)     |
| Package management (Brewfile + list files)    | [packages.md](docs/agents/packages.md)             |
| macOS system defaults and Dock                | [macos-defaults.md](docs/agents/macos-defaults.md) |
| Test suite, CI, git hooks                     | [testing-and-ci.md](docs/agents/testing-and-ci.md) |
| Secrets management (macOS Keychain)           | [secrets.md](docs/agents/secrets.md)               |
| Neovim config (lazy.nvim)                     | [neovim.md](docs/agents/neovim.md)                 |

# Architecture

## Directory Layout

| Directory       | Purpose                                                                                                     |
| --------------- | ----------------------------------------------------------------------------------------------------------- |
| `bin/`          | The `dotfiles` CLI and its subcommand scripts (`dotfiles-doctor`, `dotfiles-claude`, `dotfiles-test`, …)     |
| `scripts/`      | Install helpers — `echos.sh` (coloured output), `requirers.sh` (idempotent installers), `install_claude.sh`, `install_prezto.zsh`, and `lib/` (`fs.sh`, `lib/lists.sh`, `ssh.sh`) |
| `packages/`     | Lists for what Homebrew does not cover: `code.list` (Node CLIs live in `config/mise/config.toml`)            |
| `macos/`        | System defaults scripts — `defaults.sh`, `defaults-*.sh` (per app), `dock.sh`                               |
| `runcom/`       | Dotfiles stowed to `~/` — `.zshrc`, `.zprofile`, `.zpreztorc`, `.profile`                                    |
| `config/`       | XDG config stowed to `~/.config/` — `git/`, `nvim/`, `karabiner/`, `prettier/`, `husky/`, `starship/`        |
| `modules/`      | Git submodules — `prezto/` (the zsh framework). App themes are submodules under `apps/`                      |
| `system/`       | Shell config sourced by `.zshrc` — `.alias`, `.env`, `.path`, `.function*`, `.fzf`, `.starship`, `.term_host`, …             |
| `claude/`       | Claude Code bootstrap manifests — `marketplaces.list`, `plugins.list`, `settings.template.json`, `rules/`, `hooks/`, `statusline.sh`, `vault-templates/` |
| `apps/`         | App themes — Terminal, Xcode, Warp, GitKraken, VLC, VS Code                                                  |
| `fonts/`        | Powerline fonts with `install.sh`                                                                            |
| `profiles/`     | Machine-specific config — `default.zsh`, `personal.zsh`, `work.zsh`, `local.zsh` (gitignored)                |
| `launchagents/` | macOS LaunchAgents, including a `disabled/` set installed only on request                                     |
| `completions/`  | Zsh completions (for example `_fnm`)                                                                          |
| `tests/`        | The bash test suites and their shared harness — see [testing-and-ci.md](testing-and-ci.md)                   |
| `docs/`         | `agents/` (these docs), `plans/` (current plans; `plans/archive/` is historical), `solutions/` (point-in-time write-ups) |
| `resources/`    | Images used by the README                                                                                     |
| `Brewfile`      | Homebrew bundle manifest — taps, formulae, casks, Mac App Store apps                                          |

`AGENTS.md` is the entry point; `CLAUDE.md` is a symlink to it.

## GNU Stow Linking

`./bin/dotfiles link` does:

1. Backs up existing dotfiles to `~/.dotfiles_backup/<timestamp>`
2. Stows `runcom/` → `~/`
3. Stows `config/` → `~/.config/`

To restore: `./bin/dotfiles unlink <timestamp>`

Note that `install --claude` does **not** stow. It copies `claude/hooks/`,
`claude/rules/` and `claude/statusline.sh` into `~/.claude/`, backing up any
file that differs to `<name>.bak.<epoch>` first. Use `dotfiles claude diff` to
see what has drifted before re-running it.

## Submodules

External dependencies are git submodules, all shallow:

- **Prezto** in `modules/prezto` (shell framework)
- **App themes** under `apps/` — Nord for Terminal and Xcode, Warp themes,
  GitKraken themes

Always `git submodule update --init --recursive` after a clone. Update with
`./bin/dotfiles update`.

## Platform

Apple silicon only. `HOMEBREW_PREFIX` is `/opt/homebrew`. Scripts that depend
on it exit early on any other architecture.

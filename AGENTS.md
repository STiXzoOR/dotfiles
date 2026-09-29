# AGENTS.md

macOS dotfiles repo — bootstraps a machine with system defaults, dev tools,
apps, shell config and the Claude Code agent layer. `CLAUDE.md` is a symlink to
this file.

## Essentials

- **Language**: zsh (shell config), bash (install scripts and tests)
- **Entry point**: `./bin/dotfiles <command>` — run `./bin/dotfiles help` for the full reference
- **Test**: `./bin/dotfiles test` and `bash tests/run.sh` (both must pass before committing)
- **Lint**: `shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash` (runs in CI and the pre-commit hook)
- **CI**: GitHub Actions on push and PR — syntax validation, shellcheck over every bash file, both test suites, Brewfile validation; every job has `timeout-minutes`
- **New Mac**: `install` (CLT, git hooks, Homebrew, stow, SSH), then `install --all` runs `--prezto`, `link`, `--node`, `--packages`, `--fonts`, `--launchagents`, `--claude`, `--codex`, `configure`, `--hosts` in that order. See `docs/agents/new-mac.md`
- **Link method**: GNU Stow — `runcom/` stows to `~/`, `config/` stows to `~/.config/`

## Critical Context

These affect nearly every task.

- **bash 3.2 only.** `/bin/bash` on macOS is 3.2.57 and `bin/dotfiles` invokes
  installers as `bash script.sh`. No `mapfile`/`readarray`, no `declare -A`, no
  `declare -n`, no `${var,,}`/`${var^^}`. Never write `((x++))` under `set -e`;
  use `x=$((x + 1))`. This is the single most common thing to get wrong here.
- **GNU tools are interactive-only.** GNU coreutils, sed, grep, find and awk
  are ahead of the system tools in PATH — but only in the interactive shell,
  because that PATH comes from `system/`. `bash script.sh`, Claude Code hooks,
  launchd, cron, `xargs` and `find -exec` all get the BSD tools. `timeout` is
  not in a default macOS PATH at all, and to GNU `stat` the `-f` flag means
  *filesystem*, so a BSD-first probe never reaches its fallback. Two P1 bugs
  came from exactly this. See `claude/rules/gnu-tools.md`.
- **This repo is public.** No names, emails, hostnames, absolute `/Users/…`
  paths or tokens in tracked files. Anything private goes in a gitignored
  `*.local.list` or `profiles/local.zsh`. The pre-commit hook runs gitleaks.
- **Apple silicon only.** `HOMEBREW_PREFIX` is `/opt/homebrew`.
- **Read `tests/audit-regressions.sh` before editing** `claude/statusline.sh`,
  `claude/settings.template.json` or anything under `claude/hooks/`. It encodes
  the intent behind those files better than any prose doc, and it runs in CI as
  its own step.
- **`docs/plans/archive/` is historical and largely false.** Do not act on it.
  `docs/solutions/` is a point-in-time record, not current state.
- **Submodules**: Prezto lives in `modules/`, app themes under `apps/`. Always
  `git submodule update --init --recursive` after a clone.
- **Prezto, not Oh My Zsh**: the prompt is Starship (`system/.starship`,
  `config/starship/`), sourced from `.zshrc` for rich terminals only; prezto's
  own theme is off. `system/.term_host` sorts shells into warp, rich and dumb,
  and Warp shells load no prompt and no line-editor plugins.
- **mise, not NVM or FNM**: Node, Python-for-tooling, pnpm/yarn/uv and every
  CLI that used to be an `npm i -g` are declared in `config/mise/config.toml`
  and pinned in `config/mise/mise.lock`. Use `require_mise()` and
  `source_mise()`. The login path gets `~/.local/share/mise/shims` on PATH
  (`system/.mise`) and never runs `mise activate`; activation is opt-in via
  `DOTFILES_MISE_ACTIVATE=1`.
- **Packages**: `Brewfile` for brew, cask and Mac App Store.
  `config/mise/config.toml` for Node CLIs. `packages/code.list` for VS Code
  extensions. Machine-only additions go in `Brewfile.local` and
  `packages/code.local.list` (gitignored).
- **Personal values** (computer name, locale, timezone) live in `macos/local.sh`
  (gitignored; copy `macos/local.sh.example`), never in `macos/defaults.sh`.
- **`config/mise/locks/` is tracked.** A fresh clone needs it for `install --node`.
- **App settings**: `dotfiles apps` backs up and restores them with mackup in
  copy mode. Never part of `install --all`.
- **Git hooks**: `core.hooksPath` is repo-local (`.githooks`), set by `install`
  and checked by `doctor`. There is no global hooks path.
- **Tests** call `timeout` through the shim in `tests/lib.sh` (no GNU `timeout` on
  stock macOS or CI).
- **Backups**: `dotfiles link` backs originals up to
  `~/.dotfiles_backup/<timestamp>`. `install --claude` backs each differing
  file up to `<name>.bak.<epoch>` instead, because it copies rather than stows.
  A skill it replaces is moved to `~/.claude/backups/skills/<name>.<epoch>`,
  outside the skills tree, which Claude Code would load a second time.
- **Claude Code**: `install --claude` bootstraps the binary, marketplaces,
  plugins, rules, hooks, settings and QMD. `dotfiles claude diff` shows what
  has drifted from `~/.claude`. See
  [claude-bootstrap.md](docs/agents/claude-bootstrap.md).

## Do not run unprompted

These change the machine, need sudo, or can destroy a working setup. Ask first,
every time:

- `dotfiles install` in any form, `configure`, `link`, `unlink`, `update`,
  `clean`, `setup` — they rewrite `$HOME`, `/etc/hosts` and system defaults
- `scripts/install_claude.sh` — it overwrites `~/.claude`
- `install --passwordless` — it writes a `NOPASSWD` sudoers fragment
- `install --hosts` — it rewrites `/etc/hosts` with sudo
- `stow`, `launchctl`, `sudo`, `brew bundle`, `brew uninstall`
- anything that writes under `~/.claude` while Claude Code is running

`dotfiles doctor`, `dotfiles test`, `bash tests/run.sh`, `dotfiles claude diff`
and `dotfiles claude verify` are read-only and safe.

Editing anything under `runcom/` or `system/` is a live change: those files are
stowed into `$HOME` and take effect for every **new** shell immediately. After
each edit run `zsh -n <file>` and `zsh -l -i -c 'exit'`.

## Detail Docs

| Topic                                          | File                                                         |
| ---------------------------------------------- | ------------------------------------------------------------ |
| Directory structure, Stow linking, submodules  | [architecture.md](docs/agents/architecture.md)               |
| CLI commands and common workflows              | [commands.md](docs/agents/commands.md)                       |
| Claude Code bootstrap, hooks, drift checking   | [claude-bootstrap.md](docs/agents/claude-bootstrap.md)       |
| Zsh config, Prezto, profiles, caching, PATH    | [shell-config.md](docs/agents/shell-config.md)               |
| Package management (Brewfile + list files)     | [packages.md](docs/agents/packages.md)                       |
| macOS system defaults and Dock                 | [macos-defaults.md](docs/agents/macos-defaults.md)           |
| Test suites, CI, git hooks                     | [testing-and-ci.md](docs/agents/testing-and-ci.md)           |
| Secrets management (macOS Keychain)            | [secrets.md](docs/agents/secrets.md)                         |
| App settings backup/restore (mackup, copy mode) | [app-settings.md](docs/agents/app-settings.md)              |
| Setting up a new Mac (order, manual steps)     | [new-mac.md](docs/agents/new-mac.md)                         |
| Neovim config (lazy.nvim)                      | [neovim.md](docs/agents/neovim.md)                           |

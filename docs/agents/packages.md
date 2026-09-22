# Package Management

## Two Systems

| Method                    | Scope                                                | Command                             |
| ------------------------- | ---------------------------------------------------- | ----------------------------------- |
| `Brewfile`                | Homebrew taps, formulae, casks, Mac App Store        | `brew bundle install`               |
| `config/mise/config.toml` | Node, Python for tooling, pnpm/yarn/uv, npm-backed CLIs | `./bin/dotfiles install --node`     |
| `packages/code.list`      | VS Code extensions                                   | `./bin/dotfiles install --packages` |

## Adding Packages

- **brew formula/cask/MAS app**: Add to `Brewfile`, run `brew bundle install`
- **Node CLI**: Add `"npm:<package>" = "latest"` to `[tools]` in
  `config/mise/config.toml`, run `./bin/dotfiles install --node`, commit the
  config and the regenerated `config/mise/mise.lock`
- **VS Code extension**: Add to `packages/code.list`, run `./bin/dotfiles install --packages`
- **Homebrew tap**: Add to `Brewfile`. There is no `packages/tap.list`; taps, formulae, casks and Mac App Store apps all live in the `Brewfile`.

## Install Helpers

`scripts/requirers.sh` provides idempotent installers used by install scripts:

- `require_brew <pkg>` / `require_cask <pkg>`
- `require_mise()` / `source_mise()`
- `require_claude_marketplace <id>` / `require_claude_plugin <plugin@marketplace>`

`scripts/lib/lists.sh` reads the list files. `read_list <dir> <name>` reads
both `<name>.list` and the gitignored `<name>.local.list`, stripping comments
and blank lines. This repo is public, so anything private belongs in the
`.local.list` companion.

## Node.js

Managed by **mise**, not NVM or FNM. The toolchain is declared in
`config/mise/config.toml` (stowed to `~/.config/mise/`) and pinned in
`config/mise/mise.lock`; both are tracked. That one file covers Node, Python
for tooling, pnpm, yarn, uv and every CLI that used to be an `npm i -g`.

Add a CLI by adding `"npm:<package>" = "latest"` to `[tools]`, running
`dotfiles install --node`, and committing the config with the regenerated
lockfile. npm's lifecycle scripts are off by default; a package that genuinely
needs a build declares `allow_builds = true` for itself.

`system/.mise` puts `~/.local/share/mise/shims` on PATH at login, which is
what makes the tools reachable from git hooks, SessionEnd hooks and GUI apps.
The old manager stays installed behind a guard in `system/.fnm` until it is
removed by hand.

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
- **Launcher**: exactly one of Raycast or Tinycast, picked per Mac by
  `dotfiles_launcher` (see [new-mac.md](new-mac.md#launcher)). `dotfiles install
  --packages` exports the choice as `HOMEBREW_DOTFILES_LAUNCHER` (brew bundle
  hides every other variable from the Brewfile) and the Brewfile picks
  `cask "raycast"` or the `abue-ammar/tinycast` tap plus
  `cask "abue-ammar/tinycast/tinycast"`; unset means Tinycast. The tap line is
  indented in the Brewfile, so the generic trust loop skips it, and
  `sub_install_packages` taps and trusts it only when the launcher is Tinycast.
  A bare `brew bundle` on a Raycast Mac needs `HOMEBREW_DOTFILES_LAUNCHER=raycast`.
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

## Private additions

`Brewfile.local` (brew, cask, mas lines) and `packages/code.local.list` (VS Code
extensions) are gitignored companions to `Brewfile` and `packages/code.list`.
Put anything private or work-only there; this repo is public.

## Notes on specific entries

- **Tailscale** is the Mac App Store app, not the `tailscale` formula (its CLI
  talks to a daemon that never runs). `system/.alias` defines
  `tailscale` as the app's bundled binary when the app exists and no
  `tailscale` is on PATH.
- **git and gnupg** are declared: Apple's `/usr/bin/git` is an `xcrun` shim
  (~7 ms per call, and Starship calls git twice per prompt), and mise verifies
  Node downloads with GPG.
- **dockutil** and **pup** come from homebrew-core; their third-party taps are
  gone.
- **OpenEmu** is installed by hand: its cask is disabled in homebrew-cask.
- **`bwya77.islands-dark`** is not on the marketplace or Open VSX; install it by
  hand from its GitHub releases.
- A `mas` entry only installs an app already in your purchase history, and each
  id must resolve at `https://itunes.apple.com/lookup?id=<id>` (LastPass and
  Messenger did not, and were removed).

## The mise lock tree

`config/mise/locks/` is **tracked**. `mise.lock` holds `aube = { path = ... }`
entries that point into it, and on a fresh clone `mise install` fails for every
npm tool ("dependency sidecar ...: No such file or directory") if the tree is
missing. `tests/mise.sh` checks that every path in `mise.lock` exists. When
`mise lock` regenerates it, commit the tree with the lockfile.

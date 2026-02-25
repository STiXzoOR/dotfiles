# Package Management

## Two Systems

| Method            | Scope                                                                     | Command                             |
| ----------------- | ------------------------------------------------------------------------- | ----------------------------------- |
| `Brewfile`        | Homebrew taps, formulae, casks, Mac App Store                             | `brew bundle install`               |
| `packages/*.list` | npm globals, VS Code extensions, and other tools Brewfile doesn't support | `./bin/dotfiles install --packages` |

## Adding Packages

- **brew formula/cask/MAS app**: Add to `Brewfile`, run `brew bundle install`
- **npm global**: Add to `packages/npm.list`, run `./bin/dotfiles install --packages`
- **VS Code extension**: Add to `packages/code.list`, run `./bin/dotfiles install --packages`
- **Homebrew tap**: Add to `Brewfile` (preferred) or `packages/tap.list`

## Install Helpers

`scripts/requirers.sh` provides idempotent installers used by install scripts:

- `require_brew <pkg>` / `require_cask <pkg>` / `require_npm <pkg>`
- `require_fnm()` / `source_fnm()`

## Node.js

Managed by **FNM** (Fast Node Manager), not NVM. FNM config lives in `system/.fnm`. Completions in `completions/_fnm`.

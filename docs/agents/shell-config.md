# Shell Configuration

## Framework

**Prezto** (not Oh My Zsh) — chosen for performance. Configured via
`runcom/.zpreztorc`.

**Prompt**: Powerlevel10k, via Prezto's prompt module. Config in
`system/.prompt`. A Starship config exists at `system/.starship` and
`config/starship/` but is **not sourced**; nothing reads it today.

## Source Order

`runcom/.zshrc` names only four files from `system/` directly:

`.prompt` → `.completion` → `.zoxide` → `.bindings`

Everything else in `system/` is loaded through `system/.profile_loader`, which
is what `.zprofile` and `.zshrc` go through. Read `.profile_loader` for the
real order rather than trusting a flat list here. The list this document used
to carry was wrong in two ways: it presented everything as sourced directly by
`.zshrc`, and it named a `system/` file that has never existed.

The files it loads are `.env`, `.path`, `.alias`, the `.function*` set, `.fzf`,
`.mise`, `.pnpm`, `.grep`, `.dir_colors` and `.pay-respects`. `.mise` is loaded
from the shell-agnostic list, right after `.path`, so a non-interactive bash
login shell gets the shims too.

## Machine Profiles

Loading order:

1. `profiles/default.zsh` — always loaded
2. `profiles/$DOTFILES_PROFILE.zsh`, or `profiles/$(hostname).zsh`
3. `profiles/local.zsh` — machine-specific overrides (gitignored)

Set a profile with `export DOTFILES_PROFILE="work"`, or create
`profiles/<hostname>.zsh`.

## Caching

Shell init output is cached under `~/.cache/*.zsh`:

```bash
rm ~/.cache/*.zsh     # Clear every cache
exec $SHELL           # Restart the shell to regenerate
```

There is no per-tool refresh helper. `fnm_refresh` was documented here for a
while and never existed.

## Key Bindings

Defined in `system/.bindings` — history-substring-search and word navigation.

## Editing anything under runcom/ or system/

These files are stowed into `$HOME` and take effect for **every new shell**
immediately, with no install step. After each edit, run `zsh -n <file>` and
then `zsh -l -i -c 'exit'`, and fix any error before moving on. A syntax error
here breaks every terminal the user opens, including the ones their agents run
in.

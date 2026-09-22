# Shell Configuration

## Framework

**Prezto** (not Oh My Zsh) — chosen for performance. Configured via
`runcom/.zpreztorc`.

**Prompt**: Starship. `system/.starship` initialises it, for rich terminals
only, and `config/starship/config.toml` configures it. Prezto's own prompt
theme is `off` in every host.

## Host classification

`system/.term_host` sorts every interactive shell into one of three hosts,
before prezto loads, and sets `DOTFILES_TERM_HOST`:

| Host   | When                                              | Loads                                                                                |
| ------ | ------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `dumb` | no terminal (`zsh -l -i -c` from scripts, agents) | environment, completion, zoxide                                                      |
| `warp` | `TERM_PROGRAM=WarpTerminal`                       | environment, completion, zoxide, atuin's recording hooks                             |
| `rich` | any other terminal                                | everything: Starship, prezto's line-editor modules, fzf, fzf-tab, atuin, `.bindings` |

Warp is the only host detected positively; anything unrecognised is rich. To
override detection, set `DOTFILES_TERM_HOST` in `profiles/local.zsh` under a
condition that picks out the host. The reasoning is in
`docs/superpowers/specs/2026-09-22-zsh-2026-design.md`.

## Source Order

`runcom/.profile` loads the environment for every login shell, bash
included: `.env`, `.function*`, `.path`, `.mise`, `.editor`, `.grep`, then
the zsh-only `.alias`, `.fnm`, `.pay-respects` and `.pnpm`, then dircolors,
then the machine profiles through `system/.profile_loader`. Read `.profile`
for the exact order and the reasons for it.

`runcom/.zshrc` then sources, in order: `.term_host`, prezto, `.starship`
(rich), `.completion`, `.zoxide`, `.fzf`, `.atuin`, fzf-tab (rich) and
`.bindings` (rich), and last the `profiles/*.post.zsh` hooks.

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

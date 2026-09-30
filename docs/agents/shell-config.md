# Shell Configuration

## Framework

**Prezto** (not Oh My Zsh) — chosen for performance. Configured via
`runcom/.zpreztorc`.

**Prompt**: Starship. `system/.starship` initialises it, for rich terminals
only, and `config/starship/config.toml` configures it. Prezto's `prompt`
module is not loaded at all (`promptinit` scans 18 themes nobody uses, about
12 ms); `.zshrc` sets `PS1='%# '` after Prezto in `warp` and `dumb` shells so
they keep the prompt they had, and the `theme 'off'` line stays in
`.zpreztorc` for tests and a later re-enable. The prompt shows no Node or
Python version: `nodejs` and `python` are out of `format` (each forked
`node --version` / `python --version` through the mise shim on every prompt in
a project directory, 124-187 ms against 7 ms); their symbol tables are kept.

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

| Cache                         | Written by             | Regenerated when older than                                      |
| ----------------------------- | ---------------------- | ---------------------------------------------------------------- |
| `zoxide-init.zsh`             | `system/.zoxide`       | the `zoxide` binary                                              |
| `pay-respects-init.zsh`       | `system/.pay-respects` | the `pay-respects` binary                                        |
| `atuin-init-<host>.zsh`       | `system/.atuin`        | the `atuin` binary, or `system/.atuin` itself                    |
| `starship-init.zsh`           | `system/.starship`     | the `starship` binary, `$STARSHIP_CONFIG`, or `system/.starship` |
| `npm-completion.zsh`, `fzf-*` | `.completion`, `.fzf`  | their binary                                                     |

The atuin, starship and pay-respects caches are written atomically: generated
into `<cache>.<pid>` beside the cache, checked non-empty (for Starship, the
continuation prompt too), then moved into place with `mv -f`. A failed or
interrupted generation leaves no file and nothing is sourced, so a truncated
cache is never trusted.

Two details worth knowing. atuin's init is cached per host because the flags
differ (`dumb` loads none), and its session id is minted in zsh before the
cached script is sourced (`ATUIN_SESSION`, 32 hex digits): the init script
otherwise forks `atuin uuid` on every shell. Starship's cached copy has its
last line, `PROMPT2="$(starship prompt --continuation)"`, replaced by the
literal continuation prompt, which is why the config is one of its inputs.

```bash
rm ~/.cache/*.zsh     # Clear every cache
exec $SHELL           # Restart the shell to regenerate
```

There is no per-tool refresh helper. `fnm_refresh` was documented here for a
while and never existed.

The completion dump, `~/.cache/prezto/zcompdump`, is rebuilt by `runcom/.zlogin`
in its background block once it is older than 8 hours (the age test sets
`extendedglob` locally, so it works without Prezto): a detached `zsh -f`
(with the parent's `fpath` passed through `FPATH`) writes a temp file that
replaces the dump with one `mv -f`, and the existing `zcompile` follows. A
`zcompdump.lock` directory (`mkdir` is atomic) keeps two logins that open
together from both rebuilding; a lock older than 5 minutes was left by a killed
shell and is taken over. Prezto would otherwise regenerate the dump in the
foreground after 20 hours, which put about 25-300 ms in front of the first
prompt of the day and of a new machine's first shell. This is plain
`compinit`, never `compinit -C`, and not `zsh-defer`.

## Startup speed

Measured on the login path (`zsh -l -i -c exit`, `DOTFILES_TERM_HOST` forced,
wall time, minimum of 40 interleaved runs, load average about 5):

| Host   | Before  | After   |
| ------ | ------- | ------- |
| `warp` | 87 ms   | 49.5 ms |
| `rich` | 120 ms  | 74 ms   |
| `dumb` | 73 ms   | 49 ms   |

The 2026-09-29 pass did, in order of size: dropped Prezto's `prompt` module,
cached atuin's and Starship's init, stopped Prezto's `utility` module running
`ls --version` twice (`ls` is an eza alias, so each was an eza fork; a
temporary `eza` shim in `.zshrc` answers it in-shell while Prezto loads) and
cached pay-respects' init. `ssh <TAB>` no longer parses `/etc/hosts`:
`system/.completion` replaces Prezto's `hosts` style with one that reads
`known_hosts` and `~/.ssh/config` only (339 ms to 8 ms a lookup with a
105k-line blocklist in `/etc/hosts`).

## Key Bindings

Defined in `system/.bindings` — history-substring-search and word navigation.

## Editing anything under runcom/ or system/

These files are stowed into `$HOME` and take effect for **every new shell**
immediately, with no install step. After each edit, run `zsh -n <file>` and
then `zsh -l -i -c 'exit'`, and fix any error before moving on. A syntax error
here breaks every terminal the user opens, including the ones their agents run
in.

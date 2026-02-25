# Shell Configuration

## Framework

**Prezto** (not Oh My Zsh) — chosen for performance. Configured via `runcom/.zpreztorc`.

**Prompt**: Powerlevel10k via Prezto's prompt module. Config in `system/.prompt`. Starship config exists at `system/.starship` and `config/starship/` but is **not active**.

## Source Order

`.zshrc` sources files from `system/` in this order:

`.env` → `.path` → `.prompt` → `.alias` → `.function*` → `.completion` → `.bindings` → `.fzf` → `.fnm` → `.pnpm` → `.zoxide` → `.fix` → `.grep` → `.dir_colors`

## Machine Profiles

Loading order:

1. `profiles/default.zsh` — always loaded
2. `profiles/$DOTFILES_PROFILE.zsh` or `profiles/$(hostname).zsh`
3. `profiles/local.zsh` — machine-specific overrides (gitignored)

Set profile: `export DOTFILES_PROFILE="work"` or create `profiles/<hostname>.zsh`.

## Caching

Shell init outputs are cached in `~/.cache/*.zsh` for performance:

```bash
rm ~/.cache/*.zsh     # Clear all caches
fnm_refresh           # Refresh fnm cache specifically
exec $SHELL           # Restart shell to regenerate
```

## Key Bindings

Defined in `system/.bindings` — history-substring-search, word navigation.

# Claude Code Bootstrap

`./bin/dotfiles install --claude` runs `scripts/install_claude.sh`, which
brings a machine's Claude Code setup up to what this repo declares.

## What it does, in order

1. **Install the native binary** if `claude` is not already on PATH, then
   **verify it**: fetch the per-release `manifest.json` and its detached
   `manifest.json.sig`, check the signature in a throwaway GPG keyring against
   the published fingerprint, compare the binary's sha256 against the
   manifest, and check the macOS code signature. `gpg` is optional; without it
   the checksum alone still runs.
2. **Register marketplaces** from `claude/marketplaces.list`.
3. **Install plugins** from `claude/plugins.list`.
4. **Copy `claude/rules/` → `~/.claude/rules/`**, then append an
   `@~/.claude/rules/<name>.md` import line per rule to `~/.claude/CLAUDE.md`,
   idempotently and only if that file already exists.
5. **Copy `claude/hooks/` → `~/.claude/hooks/`** and
   **`claude/statusline.sh` → `~/.claude/statusline.sh`**.
6. **Create the recall venv** the index hook's extractor runs under.
7. **Merge `claude/settings.template.json` into `~/.claude/settings.json`**.
8. **Verify every path** the merged settings reference.
9. **Create the vault structure** and copy `claude/vault-templates/` into
   `$VAULT_DIR/Polaris/`.
10. **Set up QMD**: register the `notes` and `sessions` collections, symlink
    `qmd` into `~/.local/bin` so non-interactive contexts can find it, update
    and embed the index, register the MCP server.

Anything that fails is recorded and reported, and `main` returns non-zero, so
the exit status means something.

## Overwrites and backups

Unlike `dotfiles link`, this does not stow. It copies over `~/.claude`. Any
file that differs is first copied to `<name>.bak.<epoch>`. Run
`dotfiles claude diff` before re-running the bootstrap to see exactly what
would change.

## The merge contract

`~/.claude/settings.json` is not replaced. The template is authoritative for:

- `hooks` — merged **per event**. An event the template names replaces the
  machine's version of that event outright, because merging two arrays of hook
  objects key by key produces nonsense. An event the machine has that the
  template says nothing about is left alone, so a `PreToolUse` or
  `Notification` block set up by hand survives a re-bootstrap.
- `statusLine` — replaced outright. One object, one owner.
- `env` — merged per key, template winning, so machine-specific variables survive
- `autoUpdatesChannel` and `minimumVersion` — an update floor, not a preference

Everything else keeps whatever the machine already had: `model`,
`effortLevel`, `enabledPlugins`, `permissions` and the rest.

## Hooks

| Hook | Event | What it does |
| --- | --- | --- |
| `session-start.sh` | `SessionStart` | Prints `$VAULT_DIR/Polaris/top-of-mind.md`, capped at 2000 bytes, skipping an unedited template |
| `sync-sessions.sh` | `UserPromptSubmit`, `Stop` | Runs the sync-claude-sessions plugin, which exports transcripts into `$VAULT_DIR/Claude-Sessions` |
| `index-sessions.sh` | `SessionEnd` | Extracts recent sessions into the vault and updates the QMD index |

Three rules govern anything added here:

- **A hook runs non-interactively.** It never sources `.zshrc`, so there is no
  GNU-first PATH and no fnm multishell on PATH. Resolve external commands by
  absolute path, or explicitly. `timeout` is not in a default macOS PATH at all.
- **Never hardcode a plugin path.** `claude plugin install` puts plugins under
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and that path
  carries a version number, so anything written into settings goes stale on the
  next update. Resolve at run time, in the hook.
- **`SessionStart` and `UserPromptSubmit` stdout enters the model's context
  verbatim**, at the same trust level as `CLAUDE.md`. `SessionEnd` hooks share
  a 1.5 second budget, so anything expensive must detach.

Every hook honours `CLAUDE_HOOK_DRY_RUN=1` by reporting what it resolved and
exiting without doing work. That is what `dotfiles claude verify` uses.

## Checking drift

```bash
dotfiles claude diff      # repo vs ~/.claude; exit 1 on drift
dotfiles claude verify    # run each configured hook command, report exit codes
```

Both are read-only. The repo copy of these files had silently drifted behind
the running machine for months, which produced three separate P1 bugs; `diff`
exists so that cannot happen quietly again.

## Private entries

`claude/marketplaces.list` and `claude/plugins.list` are public. Work or
private entries go in `claude/marketplaces.local.list` and
`claude/plugins.local.list`, which are gitignored and read alongside them.

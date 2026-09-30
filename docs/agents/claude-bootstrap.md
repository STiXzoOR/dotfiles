# Claude Code Bootstrap

`./bin/dotfiles install --claude` runs `scripts/install_claude.sh`, which
brings a machine's Claude Code setup up to what this repo declares.

## What it does, in order

The script first puts `~/.local/bin` (where the native installer drops
`claude`) and the mise shims (`node`, `npx`, `uv`, `qmd`) on its own PATH: under
`bash install_claude.sh` neither is there, and every `claude plugin ...` call
used to fail with "command not found".

1. **Install the native binary** if `claude` is not already on PATH, failing
   loudly if the installer ran and left none, then
   **verify it**: fetch the per-release `manifest.json` and its detached
   `manifest.json.sig`, check the signature in a throwaway GPG keyring against
   the published fingerprint, compare the binary's sha256 against the
   manifest, and check the macOS code signature. `gpg` is optional; without it
   the checksum alone still runs.
2. **Register marketplaces** from `claude/marketplaces.list`.
3. **Install plugins** from `claude/plugins.list`. The plugin is
   `cc-safety-net` (upstream renamed it from `safety-net`; the old name fails
   on a fresh machine), plus `warp`. Once `cc-safety-net` is installed (and did
   not fail), a leftover `safety-net@cc-marketplace` from before the rename is
   uninstalled and the run says so; if `cc-safety-net` failed, the old one is
   kept. Installed-plugin and marketplace lookups match whole names
   (`list_has_token` in `scripts/lib/lists.sh`), so `safety-net` is not taken
   for `cc-safety-net`.
3b. **Register MCP servers** from `claude/mcp.list` with
   `claude mcp add --scope user`, skipping any server `claude mcp get` already
   knows. The format is one `name command args...` per line; a literal `$HOME`
   is expanded at install time so no absolute path is tracked. `blender` is
   Blender's official MCP server, installed first with
   `uv tool install --force "git+https://projects.blender.org/lab/blender_mcp.git@v1.0.3#subdirectory=mcp"`
   (never the PyPI name `blender-mcp`, an unrelated project) and registered by
   the stable path `$HOME/.local/bin/blender-mcp`. Without `uv` it warns and
   registers nothing. The Blender add-on (`mcp-1.0.3.zip` from the v1.0.3
   release, Blender 5.1+) is installed from inside Blender; the script prints
   the reminder. Shared helpers live in `scripts/lib/mcp.sh`.
3c. **Install skills** from `claude/skills.list` (`<source> <skill>`) with
   `npx -y skills@<pinned> add <source> --skill <skill> -g -a claude-code -a codex -y`
   (`SKILLS_CLI_VERSION` in `scripts/install_claude.sh`)
   (currently `find-docs`, which replaces the context7 MCP; its `ctx7` CLI comes
   from `config/mise/config.toml`). An existing symlink means installed; a
   hand-placed real directory is first moved to `~/.claude/backups/skills/<skill>.<epoch>`
   (outside the skills tree). A dangling symlink is not an install.
4. **Copy `claude/rules/` → `~/.claude/rules/`**, then append an
   `@~/.claude/rules/<name>.md` import line per rule to `~/.claude/CLAUDE.md`,
   idempotently and only if that file already exists.
5. **Copy `claude/hooks/` → `~/.claude/hooks/`** and
   **`claude/statusline.sh` → `~/.claude/statusline.sh`**.
6. **Create the recall venv** the index hook's extractor runs under.
7. **Merge `claude/settings.template.json` into `~/.claude/settings.json`**.
8. **Verify every path** the merged settings reference.
9. **Create the vault structure** and copy `claude/vault-templates/` into
   `$VAULT_DIR/Polaris/` -- but only when `$VAULT_DIR` already exists. The vault
   is a plain folder brought over by hand; when it is missing the script warns
   to copy it first and re-run, and creates nothing. The one exception is the
   iCloud vault: when nothing is at `~/Vault` and the vault folder in iCloud Drive
   exists (`DOTFILES_VAULT_ICLOUD`), `~/Vault` is created as a symlink to it. A
   vault inside iCloud Drive is downloaded first (`brctl download`, waiting up to
   `DOTFILES_VAULT_DL_WAIT` seconds); while `.icloud` placeholders remain nothing is
   written into it and QMD is not told about it. See [two-mac-sync.md](two-mac-sync.md).
10. **Set up QMD**: symlink `qmd` into `~/.local/bin` so non-interactive
    contexts can find it and, when the vault exists, register the `notes` and
    `sessions` collections and update and embed the index. Those two calls run
    under a resolved timeout (`gtimeout`, the Homebrew paths, then `timeout`),
    or unbounded when none exists; a bare `timeout` is not on a default macOS
    PATH. The `qmd` MCP server is an entry in `claude/mcp.list`, not code.

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

`diff` also names every server in `mcp.list` that `~/.claude.json` does not
register (skipped when that file does not exist yet).

Both are read-only. The repo copy of these files had silently drifted behind
the running machine for months, which produced three separate P1 bugs; `diff`
exists so that cannot happen quietly again.

## Private entries

`claude/marketplaces.list`, `plugins.list`, `mcp.list` and `skills.list` are
public: no secrets, no absolute paths. Work or private entries go in the
matching `*.local.list` (`claude/marketplaces.local.list`, and so on), which
are gitignored and read alongside them.

## Codex

`./bin/dotfiles install --codex` runs `scripts/install_codex.sh`, the same idea
for OpenAI's Codex CLI (installed by mise as `npm:@openai/codex`):

1. Puts the mise shims and `~/.local/bin` on PATH and fails clearly if `codex`
   is still missing.
2. Seeds `~/.codex/config.toml` from `codex/config.template.toml` **only when it
   does not exist** (portable keys only: no model, no `[projects]`, no `notify`
   path, no machine-path MCP servers). It never overwrites.
3. Registers the marketplaces in `codex/marketplaces.list` and installs the
   plugins in `codex/plugins.list`: `superpowers@openai-curated` (built in, with
   a fallback to `-remote` on a machine that has not synced the catalogue),
   `compound-engineering`, `warp@codex-warp` and `cc-safety-net`. `codex plugin
   add` has no already-installed guard, so `codex plugin list --json` is checked
   first. `recall-skill` and `sync-claude-sessions-skill` are Claude-only and
   recorded as such in a comment in `codex/plugins.list`.
4. Registers the servers in `claude/mcp.list` with `codex mcp add`, skipping
   ones `codex mcp get` knows.
5. Prints a final reminder: plugin hooks are not trusted on install, so open
   `codex`, run `/hooks` and press `t` on each hook. The script never tries to
   bypass that.

Any failure is summarised and the exit status is non-zero. Private entries go
in `codex/*.local.list` (gitignored). Tests: `tests/codex.sh`.

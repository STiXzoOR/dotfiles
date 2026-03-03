# Claude Code Bootstrap Design

## Goal

Add `dotfiles install --claude` subcommand that idempotently bootstraps Claude Code with plugins, marketplaces, hooks, rules, QMD, and Obsidian vault integration on a fresh machine.

## Architecture

### New files

```
claude/
  marketplaces.list     # GitHub repos, one per line
  plugins.list          # plugin@marketplace, one per line
  settings.template.json # settings without credentials
  rules/                # rule files → ~/.claude/rules/
    context7.md
    vault-lookback.md
  hooks/                # hook scripts → ~/.claude/hooks/
    index-sessions.sh
install/
  claude.sh             # main install script
```

### Install steps (idempotent)

1. **Install Claude Code native binary** — official installer, skip if already present
2. **Remove `@anthropic-ai/claude-code` from npm.list** — one-time migration
3. **Create `~/.claude/` directories** — rules, hooks, plugins (skip if exist)
4. **Merge settings.template.json** — preserve existing credentials/permissions, add missing keys
5. **Register marketplaces** — write to `known_marketplaces.json`, skip existing
6. **Install plugins** — iterate plugins.list, skip already-installed
7. **Copy rules** — sync claude/rules/\*.md → ~/.claude/rules/
8. **Copy hooks** — sync hook scripts, register in settings.json hooks section
9. **QMD + Obsidian setup**:
   - Create ~/Vault structure (Claude-Sessions, Resources, Inbox, Projects)
   - Install qmd if missing
   - Initialize QMD collections (sessions + notes)
   - Set up extract-sessions pipeline

### Marketplaces (15)

```
anthropics/claude-plugins-official
anthropics/skills
anthropics/claude-code
obra/superpowers-marketplace
EveryInc/compound-engineering-plugin.git  (git URL)
ArtemXTech/personal-os-skills
steveyegge/beads
kingbootoshi/cartographer
kenryu42/cc-marketplace
affaan-m/everything-claude-code
guinacio/claude-image-gen
CloudAI-X/claude-workflow-v2
hopeoverture/worldbuilding-app-skills
davila7/claude-code-templates
jezweb/claude-skills
```

Plus local-plugins directory (preserved as-is).

### Plugins (50)

All current minus: ralph-wiggum, ralph-loop, cloudfront-invalidation, fix-annoying-repo-permissions, repomix, thedotmack/claude-mem, mote-claude-tools.

### CLI integration

- `bin/dotfiles install --claude` calls `install/claude.sh`
- Included in `bin/dotfiles install --all`

### Removals

- `@anthropic-ai/claude-code` from `packages/npm.list` (replaced by native binary)

## Decisions

- Native binary over npm — faster, no Node.js dependency for Claude itself
- List files over JSON — matches existing dotfiles pattern (brew.list, npm.list, etc.)
- Template settings over full export — avoids leaking credentials
- Idempotent — safe to run repeatedly, only adds missing pieces

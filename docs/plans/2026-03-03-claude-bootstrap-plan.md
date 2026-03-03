# Claude Code Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `dotfiles install --claude` that idempotently bootstraps Claude Code (native binary), plugins, marketplaces, hooks, rules, QMD, and Obsidian vault integration.

**Architecture:** New `scripts/install_claude.sh` script with config manifests in `claude/` directory. Uses `claude plugin marketplace add` and `claude plugin install` CLI commands with `--json` output for reliable idempotency checks. Hooks and rules are file-copied. QMD + Obsidian vault structure is created and initialized.

**Tech Stack:** Bash (install script), Claude Code CLI (`claude plugin`, `claude plugin marketplace`), jq (JSON merge), QMD, zsh (shell integration)

### Bash/Zsh Compatibility Note

The repo uses **both** bash and zsh:

- **Bash**: `bin/dotfiles`, `bin/dotfiles-setup`, `scripts/requirers.sh`, `scripts/echos.sh`, `scripts/install_claude.sh` (new)
- **Zsh**: `bin/dotfiles-test`, `bin/dotfiles-cheatsheet`, `bin/dotfiles-doctor`, `system/.alias`, etc.

The install script is **bash** (matching `bin/dotfiles` convention). This is safe because:

- Zsh aliases (`grep→grep --color`, `cat→bat`, `alias -g`, `$+commands`) only affect interactive zsh sessions
- Bash scripts use unaliased system binaries (`/usr/bin/grep`, `/usr/bin/sed`, etc.)
- The `require_*` functions in `scripts/requirers.sh` are bash and called from bash context

The test section in `bin/dotfiles-test` is **zsh** — all test code uses syntax compatible with both (`[[ ]]`, `local`, arrays, `grep -q`).

## Enhancement Summary

**Deepened on:** 2026-03-03
**Research agents used:** 8 (security-sentinel, pattern-recognition, code-simplicity, architecture-strategist, repo-research-analyst, learning-solution-checker, performance-oracle, best-practices-researcher)

### Key Improvements Over Original Plan

1. **Security**: Fixed Python code injection, curl|sh pipe, and hardcoded paths
2. **Convention compliance**: Script in `scripts/`, subprocess execution, y/N confirmation prompt, require\_\* helpers in requirers.sh
3. **Performance**: Cache CLI output before loops (saves ~20-100s on re-runs), progress counters, timing
4. **Correctness**: Use `--json` CLI output for idempotency, jq for JSON merge, partial failure tracking
5. **Removed YAGNI**: Dropped `setup_claude_dirs()` (redundant), simplified merge to jq one-liner
6. **Bash/zsh fix**: Guard zsh-only syntax in `.profile` so Claude Code's bash doesn't error; add GNU tools rule

### Critical Issues Fixed

| Issue                                           | Severity   | Fix                                                 |
| ----------------------------------------------- | ---------- | --------------------------------------------------- |
| Python code injection in merge_settings()       | HIGH       | Replaced with jq                                    |
| `curl \| sh` remote code execution              | HIGH       | Download to temp file, verify, execute              |
| Hardcoded `/Users/stix/` in template            | MEDIUM     | Parameterized with `$HOME`                          |
| 9x `2>/dev/null` masking errors                 | MEDIUM     | Redirect to log file                                |
| No idempotency pre-check for plugins            | PERF       | Cache `claude plugin list --json` once              |
| `claude plugin marketplace list` called N times | PERF       | Cache once before loop                              |
| `source` instead of subprocess                  | CONVENTION | Use `bash "$ROOT_DIR/scripts/install_claude.sh"`    |
| Missing y/N confirmation prompt                 | CONVENTION | Add `read -r -p` like all other install subcommands |
| `.profile` zsh-only errors break Claude bash    | HIGH       | Guard zsh-only files with `$ZSH_VERSION` check      |
| No GNU tools rule for Claude Code               | LOW        | Add `claude/rules/gnu-tools.md`                     |

---

### Task 1: Create claude/ directory with marketplace and plugin lists

**Files:**

- Create: `claude/marketplaces.list`
- Create: `claude/plugins.list`

**Step 1: Create the marketplaces.list file**

```bash
mkdir -p claude
```

Write `claude/marketplaces.list`:

```
# Claude Code Marketplaces
# Format: github_org/repo (or full git URL for non-standard repos)
# Used by: scripts/install_claude.sh

# Official Anthropic
anthropics/claude-plugins-official
anthropics/skills
anthropics/claude-code

# Power-user
obra/superpowers-marketplace
https://github.com/EveryInc/compound-engineering-plugin.git
ArtemXTech/personal-os-skills

# Dev-focused
steveyegge/beads
kingbootoshi/cartographer
kenryu42/cc-marketplace
affaan-m/everything-claude-code
guinacio/claude-image-gen
CloudAI-X/claude-workflow-v2

# Framework-specific
hopeoverture/worldbuilding-app-skills
davila7/claude-code-templates
jezweb/claude-skills
```

**Step 2: Create the plugins.list file**

Write `claude/plugins.list`:

```
# Claude Code Plugins
# Format: plugin@marketplace
# Used by: scripts/install_claude.sh
# To find available plugins: claude plugin list --available

# Official Anthropic plugins
context7@claude-plugins-official
frontend-design@claude-plugins-official
hookify@claude-plugins-official
vercel@claude-plugins-official
code-simplifier@claude-plugins-official
feature-dev@claude-plugins-official
code-review@claude-plugins-official
security-guidance@claude-plugins-official
typescript-lsp@claude-plugins-official
playwright@claude-plugins-official
gopls-lsp@claude-plugins-official
stripe@claude-plugins-official
figma@claude-plugins-official
playground@claude-plugins-official

# Anthropic skills
document-skills@anthropic-agent-skills

# Superpowers
superpowers@superpowers-marketplace

# Compound Engineering
compound-engineering@every-marketplace

# Personal OS
recall-skill@personal-os-skills
sync-claude-sessions-skill@personal-os-skills

# Dev tools
plugin-dev@claude-code-plugins
code-review@claude-code-plugins
security-guidance@claude-code-plugins
beads@beads-marketplace
cartographer@cartographer-marketplace
safety-net@cc-marketplace
everything-claude-code@everything-claude-code
media-pipeline@media-pipeline-marketplace
project-starter@claude-workflow

# Framework templates
nextjs-vercel-pro@claude-code-templates

# Claude skills
auth-skills@claude-skills
backend-skills@claude-skills
cloudflare-skills@claude-skills
database-skills@claude-skills
frontend-skills@claude-skills
tooling-skills@claude-skills

# Worldbuilding app skills
a11y-checker-ci@worldbuilding-app-skills
api-contracts-and-zod-validation@worldbuilding-app-skills
auth-route-protection-checker@worldbuilding-app-skills
csp-config-generator@worldbuilding-app-skills
env-config-validator@worldbuilding-app-skills
feature-flag-manager@worldbuilding-app-skills
form-generator-rhf-zod@worldbuilding-app-skills
nextjs-fullstack-scaffold@worldbuilding-app-skills
playwright-flow-recorder@worldbuilding-app-skills
revalidation-strategy-planner@worldbuilding-app-skills
security-hardening-checklist@worldbuilding-app-skills
server-actions-vs-api-optimizer@worldbuilding-app-skills
skill-reviewer-and-enhancer@worldbuilding-app-skills
supabase-prisma-database-management@worldbuilding-app-skills
tailwind-shadcn-ui-setup@worldbuilding-app-skills
testing-next-stack@worldbuilding-app-skills
ui-library-usage-auditor@worldbuilding-app-skills
```

**Step 3: Verify files are well-formed**

Run: `wc -l claude/marketplaces.list claude/plugins.list`
Expected: ~20 lines for marketplaces, ~55 lines for plugins (including comments)

**Step 4: Commit**

```bash
git add claude/marketplaces.list claude/plugins.list
git commit -m "feat: add Claude Code marketplace and plugin manifests"
```

---

### Task 2: Create claude/ rules and hooks

**Files:**

- Create: `claude/rules/context7.md`
- Create: `claude/rules/vault-lookback.md`
- Create: `claude/hooks/index-sessions.sh`

**Step 1: Create rules directory and copy current rules**

Copy the content of `~/.claude/rules/context7.md` into `claude/rules/context7.md`.
Copy the content of `~/.claude/rules/vault-lookback.md` into `claude/rules/vault-lookback.md`.

The context7.md content:

```markdown
---
alwaysApply: true
---

When working with libraries, frameworks, or APIs — use Context7 MCP to fetch current documentation instead of relying on training data. This includes setup questions, code generation, API references, and anything involving specific packages.

## Steps

1. Call `resolve-library-id` with the library name and the user's question
2. Pick the best match — prefer exact names and version-specific IDs when a version is mentioned
3. Call `query-docs` with the selected library ID and the user's question
4. Answer using the fetched docs — include code examples and cite the version
```

The vault-lookback.md content:

```markdown
When starting a task that involves debugging, architecture decisions, or implementing something you've worked on before — use QMD MCP to search past sessions first.

Example lookback triggers:

- "Fix the X bug" → search for past fixes related to X
- "Implement Y feature" → search for past discussions about Y
- "How did we do Z?" → search sessions + notes

Quick search pattern:

1. `qmd_search` with collection "sessions" for exact keyword matches
2. If no results, try `qmd_vector_search` for semantic matches
3. Summarize relevant findings before proceeding
```

**Step 2: Create hooks directory with index-sessions.sh**

Write `claude/hooks/index-sessions.sh`:

> **Research Insight (Security):** Original had hardcoded `/Users/stix/` path. Parameterized with `$HOME`. Also redirect stderr to log instead of /dev/null.

```bash
#!/bin/bash
# Auto-index QMD sessions after Claude Code session ends
# Extracts recent sessions to vault and updates QMD index

VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
PYTHON="$HOME/.claude/skills/recall/.venv/bin/python3"
EXTRACT_SCRIPT="$HOME/.claude/skills/recall/scripts/extract-sessions.py"
LOG_FILE="$HOME/.claude/hooks/index-sessions.log"

# Extract last 3 days of sessions
if [[ -x "$PYTHON" ]] && [[ -f "$EXTRACT_SCRIPT" ]]; then
  "$PYTHON" "$EXTRACT_SCRIPT" --days 3 --output "$VAULT_DIR/Claude-Sessions" >> "$LOG_FILE" 2>&1
fi

# Update QMD index (fast — only processes changed files)
if command -v qmd &>/dev/null; then
  timeout 60 qmd update >> "$LOG_FILE" 2>&1
fi
```

**Step 3: Verify file structure**

Run: `find claude/ -type f | sort`
Expected:

```
claude/hooks/index-sessions.sh
claude/marketplaces.list
claude/plugins.list
claude/rules/context7.md
claude/rules/vault-lookback.md
```

**Step 4: Commit**

```bash
git add claude/rules/ claude/hooks/
git commit -m "feat: add Claude Code rules and hooks config"
```

---

### Task 3: Create settings.template.json

**Files:**

- Create: `claude/settings.template.json`

**Step 1: Create the template**

> **Research Insight (Security):** Original had hardcoded `/Users/stix/` paths. All paths now use `$HOME`-relative notation. The install script will expand `$HOME` at install time via `envsubst` or sed.

> **Research Insight (Architecture):** `permissions`, `enabledPlugins`, `statusLine`, and `skipDangerousModePermissionPrompt` are NOT included — these are user-specific and set by the install script or by user choice after install.

Write `claude/settings.template.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "VAULT_DIR": "$HOME/Vault"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skills/recall/.venv/bin/python3 ~/.claude/skills/sync-claude-sessions/scripts/claude-sessions sync",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skills/recall/.venv/bin/python3 ~/.claude/skills/sync-claude-sessions/scripts/claude-sessions sync",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/index-sessions.sh >> ~/.claude/hooks/index-sessions.log 2>&1",
            "timeout": 30
          }
        ]
      }
    ]
  },
  "alwaysThinkingEnabled": true
}
```

> **Implementation Note:** The install script must expand `$HOME` in the template before writing to `~/.claude/settings.json`. Use: `sed "s|\$HOME|$HOME|g" "$template"` during merge.

**Step 2: Commit**

```bash
git add claude/settings.template.json
git commit -m "feat: add Claude Code settings template"
```

---

### Task 4: Add require_claude_marketplace and require_claude_plugin to requirers.sh

**Files:**

- Modify: `scripts/requirers.sh`

> **Research Insight (Pattern Recognition):** Every package type in the dotfiles has a `require_*` function in requirers.sh (`require_brew`, `require_cask`, `require_npm`, `require_code`, `require_mas`). Claude marketplace and plugin operations should follow the same pattern.

> **Research Insight (Best Practices):** Use `claude plugin marketplace list --json` and `claude plugin list --json` for reliable idempotency checks. The text output from `marketplace list` can be empty. The JSON output includes `repo` for marketplaces and `id` for plugins.

**Step 1: Add require_claude_marketplace function**

Append to `scripts/requirers.sh`:

```bash
function require_claude_marketplace() {
  running "marketplace $1"
  if echo "$CLAUDE_MARKETPLACES_CACHE" | grep -q "$1"; then
    ok
  else
    if claude plugin marketplace add "$1" 2>>"${CLAUDE_INSTALL_LOG:-/dev/null}"; then
      ok
    else
      warn "failed to add marketplace $1"
    fi
  fi
}

function require_claude_plugin() {
  local plugin_name="${1%%@*}"
  running "plugin $1"
  if echo "$CLAUDE_PLUGINS_CACHE" | grep -q "$plugin_name"; then
    ok
  else
    if claude plugin install "$1" 2>>"${CLAUDE_INSTALL_LOG:-/dev/null}"; then
      ok
    else
      warn "failed to install $1"
    fi
  fi
}
```

> **Implementation Note:** `CLAUDE_MARKETPLACES_CACHE` and `CLAUDE_PLUGINS_CACHE` are populated once by the install script before iterating. This avoids calling `claude plugin marketplace list` N times (saves ~4.5s per run per Performance Oracle).

**Step 2: Commit**

```bash
git add scripts/requirers.sh
git commit -m "feat: add require_claude_marketplace and require_claude_plugin helpers"
```

---

### Task 5: Create scripts/install_claude.sh install script

**Files:**

- Create: `scripts/install_claude.sh`

> **Research Insights Applied:**
>
> - **Security**: Download installer to temp file instead of `curl | sh`. Use `jq` instead of inline Python for JSON merge. Pass paths via environment variables. Validate JSON before merge.
> - **Performance**: Cache `claude plugin marketplace list --json` and `claude plugin list --json` once before loops. Add progress counters. Add timing instrumentation. Add `timeout 60` on `qmd update`.
> - **Convention**: Script in `scripts/` alongside `echos.sh` and `requirers.sh`. No `set -euo pipefail` in functions that may partially fail (marketplace/plugin loops). Track failures, report at end.
> - **Pattern**: Use `require_claude_marketplace` and `require_claude_plugin` from requirers.sh for loop body.
> - **Simplicity**: Removed `setup_claude_dirs()` (redundant — copy_rules/copy_hooks do `mkdir -p`). Used `jq -s '.[0] * .[1]'` instead of 15-line Python.

**Step 1: Write the install script**

Write `scripts/install_claude.sh`:

```bash
#!/usr/bin/env bash
#
# Claude Code bootstrap — idempotent installer
# Called by: dotfiles install --claude
#
# Installs Claude Code native binary, registers marketplaces,
# installs plugins, copies rules/hooks, merges settings, and
# sets up QMD + Obsidian vault.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="$ROOT_DIR/claude"
CLAUDE_HOME="$HOME/.claude"
VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
CLAUDE_INSTALL_LOG="/tmp/dotfiles-claude-install.log"
FAILURES=()

source "$ROOT_DIR/scripts/echos.sh"
source "$ROOT_DIR/scripts/requirers.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

try_or_track() {
  local label="$1"
  shift
  if ! "$@"; then
    FAILURES+=("$label")
  fi
}

report_failures() {
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    warn "${#FAILURES[@]} items failed:"
    for f in "${FAILURES[@]}"; do
      echo "  - $f"
    done
    echo "  See $CLAUDE_INSTALL_LOG for details."
  fi
}

# ─── 1. Install Claude Code native binary ────────────────────────────────────

install_claude_binary() {
  if command -v claude &>/dev/null; then
    ok "Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
    return
  fi

  action "Installing Claude Code native binary"
  local tmpfile
  tmpfile=$(mktemp)
  if curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o "$tmpfile"; then
    if bash "$tmpfile"; then
      ok "Claude Code installed"
    else
      error "Claude Code installer failed"
      rm -f "$tmpfile"
      return 1
    fi
  else
    error "Failed to download Claude Code installer"
    rm -f "$tmpfile"
    return 1
  fi
  rm -f "$tmpfile"
}

# ─── 2. Register marketplaces ────────────────────────────────────────────────

register_marketplaces() {
  if [[ ! -f "$CLAUDE_DIR/marketplaces.list" ]]; then
    warn "No marketplaces.list found, skipping"
    return
  fi

  action "Registering Claude Code marketplaces"

  # Cache marketplace list once before the loop
  export CLAUDE_MARKETPLACES_CACHE
  CLAUDE_MARKETPLACES_CACHE="$(claude plugin marketplace list --json 2>/dev/null || echo "")"

  local total count=0
  total=$(grep -cvE '^[[:space:]]*(#|$)' "$CLAUDE_DIR/marketplaces.list" || echo 0)

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    running "[$count/$total] marketplace $line"
    try_or_track "marketplace: $line" require_claude_marketplace "$line"
  done <"$CLAUDE_DIR/marketplaces.list"
}

# ─── 3. Install plugins ──────────────────────────────────────────────────────

install_plugins() {
  if [[ ! -f "$CLAUDE_DIR/plugins.list" ]]; then
    warn "No plugins.list found, skipping"
    return
  fi

  action "Installing Claude Code plugins"

  # Cache installed plugins list once before the loop
  export CLAUDE_PLUGINS_CACHE
  CLAUDE_PLUGINS_CACHE="$(claude plugin list --json 2>/dev/null || echo "")"

  local total count=0 skipped=0
  total=$(grep -cvE '^[[:space:]]*(#|$)' "$CLAUDE_DIR/plugins.list" || echo 0)

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    local plugin_name="${line%%@*}"

    # Skip already-installed plugins silently
    if echo "$CLAUDE_PLUGINS_CACHE" | grep -q "$plugin_name"; then
      skipped=$((skipped + 1))
      continue
    fi

    running "[$count/$total] plugin $line"
    try_or_track "plugin: $line" require_claude_plugin "$line"
  done <"$CLAUDE_DIR/plugins.list"

  if [[ $skipped -gt 0 ]]; then
    ok "$skipped plugins already installed, skipped"
  fi
}

# ─── 4. Copy rules ───────────────────────────────────────────────────────────

copy_rules() {
  if [[ ! -d "$CLAUDE_DIR/rules" ]]; then
    warn "No rules directory found, skipping"
    return
  fi

  action "Copying Claude Code rules"
  mkdir -p "$CLAUDE_HOME/rules"
  for rule_file in "$CLAUDE_DIR"/rules/*.md; do
    [[ -f "$rule_file" ]] || continue
    local name
    name="$(basename "$rule_file")"
    cp "$rule_file" "$CLAUDE_HOME/rules/$name"
    ok "rules/$name"
  done
}

# ─── 5. Copy hooks ───────────────────────────────────────────────────────────

copy_hooks() {
  if [[ ! -d "$CLAUDE_DIR/hooks" ]]; then
    warn "No hooks directory found, skipping"
    return
  fi

  action "Copying Claude Code hooks"
  mkdir -p "$CLAUDE_HOME/hooks"
  for hook_file in "$CLAUDE_DIR"/hooks/*; do
    [[ -f "$hook_file" ]] || continue
    local name
    name="$(basename "$hook_file")"
    cp "$hook_file" "$CLAUDE_HOME/hooks/$name"
    chmod +x "$CLAUDE_HOME/hooks/$name"
    ok "hooks/$name"
  done
}

# ─── 6. Merge settings template ──────────────────────────────────────────────

merge_settings() {
  local template="$CLAUDE_DIR/settings.template.json"
  local target="$CLAUDE_HOME/settings.json"

  if [[ ! -f "$template" ]]; then
    warn "No settings.template.json found, skipping"
    return
  fi

  action "Merging Claude Code settings"

  # Expand $HOME in template
  local expanded
  expanded=$(sed "s|\\\$HOME|$HOME|g" "$template")

  if [[ ! -f "$target" ]]; then
    # Fresh install — write expanded template directly
    echo "$expanded" > "$target"
    ok "settings.json created from template"
  else
    # Existing install — deep merge: template provides defaults, existing overrides
    if ! command -v jq &>/dev/null; then
      warn "jq not available — skipping settings merge (install jq via brew)"
      return
    fi

    # Validate existing settings
    if ! jq empty "$target" 2>/dev/null; then
      warn "Invalid JSON in existing settings, backing up and replacing"
      cp "$target" "${target}.backup.$(date +%s)"
      echo "$expanded" > "$target"
      return
    fi

    local tmpfile
    tmpfile=$(mktemp)
    if echo "$expanded" | jq -s '.[0] * .[1]' - "$target" > "$tmpfile"; then
      mv "$tmpfile" "$target"
      ok "settings.json merged (existing values preserved)"
    else
      rm -f "$tmpfile"
      error "JSON merge failed"
      return 1
    fi
  fi
}

# ─── 7. Setup Obsidian vault ─────────────────────────────────────────────────

setup_vault() {
  action "Setting up Obsidian vault structure"

  local dirs=(
    "$VAULT_DIR"
    "$VAULT_DIR/Claude-Sessions"
    "$VAULT_DIR/Resources"
    "$VAULT_DIR/Inbox"
    "$VAULT_DIR/Projects"
  )

  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir"
      ok "created $dir"
    fi
  done
  ok "vault structure ready"
}

# ─── 8. Setup QMD ────────────────────────────────────────────────────────────

setup_qmd() {
  if ! command -v qmd &>/dev/null; then
    warn "QMD not installed — add 'qmd' to packages/npm.list and run 'dotfiles install --packages'"
    return
  fi

  ok "QMD already installed ($(qmd --version 2>/dev/null))"

  # Update QMD index (fast — only processes changed files)
  action "Updating QMD index"
  if timeout 60 qmd update 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD index updated"
  else
    warn "QMD update timed out or failed (run 'qmd update' manually)"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local start_time
  start_time=$(date +%s)

  bot "Claude Code Bootstrap\n"

  # Reset log
  : > "$CLAUDE_INSTALL_LOG"

  install_claude_binary
  register_marketplaces
  install_plugins
  copy_rules
  copy_hooks
  merge_settings
  setup_vault
  setup_qmd

  report_failures

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  echo ""
  bot "Claude Code bootstrap complete! (${elapsed}s)"
  echo ""
  echo "Next steps:"
  echo "  1. Run 'claude' to authenticate (if first install)"
  echo "  2. Restart your shell to pick up changes"
  echo ""
}

main "$@"
```

**Step 2: Make it executable**

Run: `chmod +x scripts/install_claude.sh`

**Step 3: Verify syntax**

Run: `bash -n scripts/install_claude.sh`
Expected: No output (clean syntax)

Run: `shellcheck -e SC1090,SC1091 scripts/install_claude.sh`
Expected: No errors (fix any warnings)

**Step 4: Commit**

```bash
git add scripts/install_claude.sh
git commit -m "feat: add Claude Code install script"
```

---

### Task 6: Wire into dotfiles CLI

**Files:**

- Modify: `bin/dotfiles:46-59` (sub_install_help)
- Modify: `bin/dotfiles:172-181` (sub_install_all)
- Add: `sub_install_claude()` function

> **Research Insight (Convention):** Every `sub_install_*` follows the pattern: `bot` → `read -r -p "[y|N]"` → `if/else` → action/ok/skip. The claude install must follow the same pattern. Execute as subprocess (`bash`), not `source`.

**Step 1: Add --claude to install help**

In `bin/dotfiles`, add `--claude` to the `sub_install_help()` function, after the `--launchagents` line:

```bash
echo "   --claude           Claude Code (binary, plugins, marketplaces, hooks, rules, QMD)"
```

**Step 2: Add sub_install_claude function**

Add after the `sub_install_launchagents()` function (around line 444):

```bash
sub_install_claude() {
  bot "Claude Code Bootstrap\n"

  read -r -p "Install Claude Code (binary, plugins, marketplaces, hooks, rules, QMD)? [y|N] " response
  if [[ $response =~ (yes|y|Y) ]]; then
    bash "$ROOT_DIR/scripts/install_claude.sh"
  else
    skip
  fi
}
```

**Step 3: Add --claude to install --all**

In `sub_install_all()`, add before the `$0 configure` line:

```bash
$0 install --claude
```

**Step 4: Run syntax check**

Run: `bash -n bin/dotfiles`
Expected: No output

**Step 5: Commit**

```bash
git add bin/dotfiles
git commit -m "feat: wire 'dotfiles install --claude' into CLI"
```

---

### Task 7: Remove @anthropic-ai/claude-code from npm.list

**Files:**

- Modify: `packages/npm.list:1`

**Step 1: Remove the line**

Remove `@anthropic-ai/claude-code` from `packages/npm.list`. The native binary replaces it.

**Step 2: Ensure qmd is present in npm.list**

If `qmd` is not already in `packages/npm.list`, add it. This ensures QMD gets installed via the standard npm package flow (`dotfiles install --packages`) rather than inline in the claude install script.

**Step 3: Verify**

Run: `grep -c '@anthropic-ai/claude-code' packages/npm.list`
Expected: `0`

Run: `grep -c 'qmd' packages/npm.list`
Expected: `1`

**Step 4: Commit**

```bash
git add packages/npm.list
git commit -m "chore: remove claude-code from npm.list (replaced by native binary), ensure qmd present"
```

---

### Task 8: Add tests for Claude bootstrap

**Files:**

- Modify: `bin/dotfiles-test` (add test section)

**Step 1: Add Claude bootstrap test section**

Add a new test section before `test_shell_startup` in `bin/dotfiles-test`:

```bash
#############################################################################
# CLAUDE CODE BOOTSTRAP TESTS
#############################################################################

test_claude_bootstrap() {
  section "Claude Code Bootstrap"

  # Test install script exists and is executable
  if [[ -f "$DOTFILES_DIR/scripts/install_claude.sh" ]]; then
    pass "File exists: scripts/install_claude.sh"
    if [[ -x "$DOTFILES_DIR/scripts/install_claude.sh" ]]; then
      pass "Executable: scripts/install_claude.sh"
    else
      fail "Not executable: scripts/install_claude.sh"
    fi
  else
    fail "File missing: scripts/install_claude.sh"
  fi

  # Test install script has valid bash syntax
  if bash -n "$DOTFILES_DIR/scripts/install_claude.sh" 2>/dev/null; then
    pass "Syntax OK: scripts/install_claude.sh"
  else
    fail "Syntax error: scripts/install_claude.sh"
  fi

  # Test manifest files exist
  local manifests=("claude/marketplaces.list" "claude/plugins.list" "claude/settings.template.json")
  for manifest in "${manifests[@]}"; do
    if [[ -f "$DOTFILES_DIR/$manifest" ]]; then
      pass "File exists: $manifest"
    else
      fail "File missing: $manifest"
    fi
  done

  # Test rules exist
  local rules=("claude/rules/context7.md" "claude/rules/vault-lookback.md")
  for rule in "${rules[@]}"; do
    if [[ -f "$DOTFILES_DIR/$rule" ]]; then
      pass "File exists: $rule"
    else
      fail "File missing: $rule"
    fi
  done

  # Test hooks exist
  if [[ -f "$DOTFILES_DIR/claude/hooks/index-sessions.sh" ]]; then
    pass "File exists: claude/hooks/index-sessions.sh"
  else
    fail "File missing: claude/hooks/index-sessions.sh"
  fi

  # Test settings template is valid JSON
  if command -v jq &>/dev/null && jq . "$DOTFILES_DIR/claude/settings.template.json" >/dev/null 2>&1; then
    pass "Valid JSON: settings.template.json"
  elif python3 -m json.tool "$DOTFILES_DIR/claude/settings.template.json" >/dev/null 2>&1; then
    pass "Valid JSON: settings.template.json"
  else
    fail "Invalid JSON: settings.template.json"
  fi

  # Test settings template has no hardcoded /Users/ paths (except $HOME patterns)
  if grep -q '/Users/' "$DOTFILES_DIR/claude/settings.template.json" 2>/dev/null; then
    fail "settings.template.json contains hardcoded /Users/ path (should use \$HOME)"
  else
    pass "settings.template.json: no hardcoded user paths"
  fi

  # Test hooks have no hardcoded /Users/ paths
  if grep -rq '/Users/' "$DOTFILES_DIR/claude/hooks/" 2>/dev/null; then
    fail "claude/hooks/ contains hardcoded /Users/ path (should use \$HOME)"
  else
    pass "claude/hooks/: no hardcoded user paths"
  fi

  # Test npm.list no longer has claude-code
  if grep -q '@anthropic-ai/claude-code' "$DOTFILES_DIR/packages/npm.list" 2>/dev/null; then
    fail "npm.list still contains @anthropic-ai/claude-code (should use native binary)"
  else
    pass "npm.list: claude-code removed (using native binary)"
  fi

  # Test dotfiles CLI has --claude subcommand
  if grep -q 'sub_install_claude' "$DOTFILES_DIR/bin/dotfiles"; then
    pass "CLI: install --claude subcommand registered"
  else
    fail "CLI: install --claude subcommand missing"
  fi

  # Test install --all includes --claude
  if grep -q 'install --claude' "$DOTFILES_DIR/bin/dotfiles"; then
    pass "CLI: install --all includes --claude"
  else
    fail "CLI: install --all missing --claude"
  fi

  # Test sub_install_claude uses subprocess (bash), not source
  if grep -q 'bash.*install_claude' "$DOTFILES_DIR/bin/dotfiles"; then
    pass "CLI: sub_install_claude uses subprocess execution"
  elif grep -q 'source.*install_claude' "$DOTFILES_DIR/bin/dotfiles"; then
    fail "CLI: sub_install_claude uses source (should use bash subprocess)"
  fi
}
```

**Step 2: Register the test in main()**

In `bin/dotfiles-test`, add `test_claude_bootstrap` to the main function, before `test_shell_startup`:

```bash
test_claude_bootstrap
```

**Step 3: Also add scripts/install_claude.sh to bash syntax and shellcheck tests**

In `test_bash_syntax()`, add to the files array:

```bash
"$DOTFILES_DIR/scripts/install_claude.sh"
```

In `test_shellcheck()`, add to the bash_files array:

```bash
"$DOTFILES_DIR/scripts/install_claude.sh"
```

**Step 4: Run tests**

Run: `./bin/dotfiles test`
Expected: All tests pass including new Claude bootstrap section

**Step 5: Commit**

```bash
git add bin/dotfiles-test
git commit -m "test: add Claude Code bootstrap validation tests"
```

---

### Task 9: Fix .profile bash compatibility and all hardcoded /Users/stix/ paths

**Files:**

- Modify: `runcom/.profile` (guard zsh-only files)
- Modify: `system/.path` (guard `typeset -U`)
- Modify: `system/.alias` (fix hardcoded path in `cs` alias)
- Stage: `system/.env` (already has uncommitted VAULT_DIR addition)

> **Critical Discovery:** The recent "full zsh" audit (`5ed057b`) converted system files to use zsh-only syntax (`$+commands`, `alias -g`, `alias -s`, `typeset -U`), but `.profile` still sources ALL of them for both bash and zsh. When Claude Code's bash tool loads `.profile`, it produces ~15 errors to stderr. While the PATH is still correctly built (GNU tools are available), the error noise causes Claude Code to avoid using standard tools like `sed` and `grep`, falling back to alternative approaches.
>
> **Verified:** `bash -l -c 'which sed'` → `/opt/homebrew/opt/gnu-sed/libexec/gnubin/sed` (GNU sed 4.9). The PATH IS correct despite the errors.

**Hardcoded `/Users/stix/` audit results:**

| File                                 | Fix                    |
| ------------------------------------ | ---------------------- |
| `system/.alias:136`                  | Replace with `$HOME`   |
| `config/spicetify/config-xpui.ini:2` | Ignore — app-generated |
| `apps/vscode/settings.json:61`       | Ignore — app-managed   |
| `apps/gitkraken/profiles/*/profile`  | Ignore — app-managed   |

**Step 1: Guard zsh-only files in .profile**

In `runcom/.profile`, change the sourcing loop to separate bash-compatible from zsh-only files:

```bash
# Core system files (bash + zsh compatible)
for DOTFILE in "$DOTFILES_DIR"/system/.{function,function_*,path,env,grep}; do
  [[ -f "$DOTFILE" ]] && . "$DOTFILE"
done

# Files using zsh-only features ($+commands, alias -g, alias -s)
if [[ -n "$ZSH_VERSION" ]]; then
  for DOTFILE in "$DOTFILES_DIR"/system/.{alias,fnm,fzf,thefuck,pnpm}; do
    [[ -f "$DOTFILE" ]] && . "$DOTFILE"
  done
fi
```

**Step 2: Guard `typeset -U` in system/.path**

At line 43 of `system/.path`, replace:

```bash
typeset -U PATH path
```

With:

```bash
# Remove duplicate PATH entries (typeset -U is zsh-only)
if [[ -n "$ZSH_VERSION" ]]; then
  typeset -U PATH path
fi
```

**Step 3: Fix the cs alias in system/.alias**

Replace:

```bash
alias cs="/Users/stix/.claude/skills/recall/.venv/bin/python3 ~/.claude/skills/sync-claude-sessions/scripts/claude-sessions"
```

With:

```bash
alias cs="$HOME/.claude/skills/recall/.venv/bin/python3 ~/.claude/skills/sync-claude-sessions/scripts/claude-sessions"
```

**Step 4: Verify bash loads cleanly**

Run: `bash -l -c 'echo ok' 2>&1`
Expected: `ok` with NO syntax errors (no `$+commands`, `alias -g`, `typeset` errors)

Run: `bash -l -c 'which sed; which grep; which awk'`
Expected: GNU versions from `/opt/homebrew/opt/*/libexec/gnubin/`

**Step 6: Verify no remaining hardcoded paths in system files**

Run: `grep -r '/Users/stix' --include='*.sh' --include='*.list' --include='*.zsh' system/ runcom/ scripts/ claude/ | grep -v '.git/'`
Expected: No results

**Step 7: Commit**

```bash
git add runcom/.profile system/.path system/.alias system/.env
git commit -m "fix: bash compatibility in .profile, parameterize hardcoded paths

- Guard zsh-only files (.alias, .fnm, .fzf, .thefuck, .pnpm) behind
  ZSH_VERSION check in .profile — fixes ~15 errors when Claude Code's
  bash tool sources the profile
- Guard typeset -U in .path (zsh-only)
- Parameterize cs alias with \$HOME
- Add VAULT_DIR export to .env"
```

---

### Task 10: Add Claude Code rule for GNU tools

**Files:**

- Create: `claude/rules/gnu-tools.md`

> **Research Insight:** Even with the .profile fix, it's valuable to tell Claude Code explicitly about the GNU tool availability. This prevents Claude from using workarounds when standard GNU sed/grep/find/awk syntax works fine.

**Step 1: Create the rule**

Write `claude/rules/gnu-tools.md`:

```markdown
---
alwaysApply: true
---

This machine has GNU coreutils, GNU sed, GNU grep, GNU find, and GNU awk installed via Homebrew and configured as the default commands in PATH.

Use standard GNU syntax for all shell commands:

- `sed -i 's/old/new/'` (not `sed -i '' 's/old/new/'` which is BSD)
- `grep -P` for PCRE is available
- `find` supports `-printf`, `-regextype`
- `awk` is `gawk` with full GNU extensions
- `date` supports `--date` and `+%s` formatting

Do NOT use workarounds for BSD tool limitations — they are not needed here.
```

**Step 2: Commit**

```bash
git add claude/rules/gnu-tools.md
git commit -m "feat: add Claude Code rule for GNU tools availability"
```

---

### Task 11: Fix hardcoded paths in system files and commit pending changes

**Files:**

- Stage: `system/.env` (already has uncommitted VAULT_DIR addition)

**Step 1: Commit system/.env**

The VAULT_DIR export was already added but not committed.

```bash
git add system/.env
git commit -m "feat: export VAULT_DIR for QMD and Claude Code sync"
```

---

### Task 12: Update docs and final validation

**Files:**

- Modify: `CLAUDE.md` (add claude bootstrap to commands table)
- Modify: `docs/agents/commands.md` (if it exists, add --claude docs)

**Step 1: Update CLAUDE.md**

In the `CLAUDE.md` file, add `install --claude` to the commands reference.

**Step 2: Run full test suite**

Run: `./bin/dotfiles test`
Expected: All tests pass

**Step 3: Verify the install script runs without error (dry-run check)**

Run: `bash -n scripts/install_claude.sh && echo "Syntax OK"`
Run: `shellcheck -e SC1090,SC1091 scripts/install_claude.sh && echo "Shellcheck OK"`

**Step 4: Verify help output**

Run: `./bin/dotfiles install --help`
Expected: Shows `--claude` in the list

**Step 5: Commit docs**

```bash
git add CLAUDE.md docs/
git commit -m "docs: document 'dotfiles install --claude' command"
```

---

## Research Appendix

### Security Findings (Security Sentinel)

| Severity | Finding                                                                          | Mitigation                               |
| -------- | -------------------------------------------------------------------------------- | ---------------------------------------- |
| HIGH     | Python code injection via `$template`/`$target` interpolated into Python heredoc | Replaced Python with jq                  |
| HIGH     | `curl \| sh` remote code execution                                               | Download to temp file, verify, execute   |
| MEDIUM   | 9 locations with `2>/dev/null` masking errors                                    | Redirect to `$CLAUDE_INSTALL_LOG`        |
| MEDIUM   | No input validation on .list file contents                                       | Skip blank/comment lines, track failures |
| MEDIUM   | VAULT_DIR path injection                                                         | Default to `$HOME/Vault`, no eval        |
| LOW      | Blanket `chmod +x` on hooks                                                      | Only chmod files copied from repo        |
| LOW      | `set -euo pipefail` gaps in functions                                            | Wrap risky calls in `try_or_track`       |

### Performance Findings (Performance Oracle)

| Priority | Action                                                     | Impact                        |
| -------- | ---------------------------------------------------------- | ----------------------------- |
| P0       | Cache `claude plugin marketplace list --json` before loop  | Saves ~4.5s/run               |
| P0       | Cache `claude plugin list --json` for idempotent pre-check | Saves 15-100s on re-runs      |
| P1       | Log stderr instead of /dev/null                            | Debuggability                 |
| P2       | Progress counters `[3/15]`                                 | UX during slow network ops    |
| P2       | Total timing instrumentation                               | Benchmarking                  |
| P3       | `timeout 60` on `qmd update`                               | Prevents hang on large vaults |

### Convention Compliance (Pattern Recognition + Repo Research)

| Convention                                           | Status               |
| ---------------------------------------------------- | -------------------- |
| Script in `scripts/` alongside echos.sh/requirers.sh | Fixed (was install/) |
| Subprocess execution (`bash`), not `source`          | Fixed                |
| `read -r -p "[y\|N]"` confirmation                   | Added                |
| `require_*` helpers in requirers.sh                  | Added                |
| `bot` → prompt → action/skip pattern                 | Followed             |
| No hardcoded paths                                   | Fixed                |
| Pass shellcheck                                      | Required in tests    |

### References

- [Claude Code Native Installer (Official)](https://claude.ai/install.sh) — stable channel: `bash -s stable`
- [Claude Code Plugin CLI Docs](https://code.claude.com/docs/en/discover-plugins) — `--json` flag for machine-readable output
- [Homebrew alternative](https://formulae.brew.sh/cask/claude-code) — `brew install --cask claude-code` (no auto-update)
- [Shell Scripting Best Practices (Feb 2026)](https://oneuptime.com/blog/post/2026-02-13-shell-scripting-best-practices/view)
- [Bash Error Handling Patterns (HowToGeek)](https://www.howtogeek.com/bash-error-handling-patterns-i-use-in-every-script/)
- [jq Deep Merge](https://www.baeldung.com/linux/json-merge-files) — `jq -s '.[0] * .[1]'`

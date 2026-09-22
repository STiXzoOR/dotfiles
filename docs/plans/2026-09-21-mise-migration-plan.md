# mise Migration (wave 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fnm with mise as the single manager for Node, Python-for-dev, pnpm/yarn/uv and every npm-installed CLI, with zero downtime for shells and agent sessions that are already running, and with tools reachable from non-interactive hooks.

**Architecture:** mise is installed from Homebrew. Its global config is tracked in the repo at `config/mise/config.toml` (stowed to `~/.config/mise/`). Interactive and non-interactive shells get `~/.local/share/mise/shims` prepended to PATH at login time (zero startup cost; shims resolve the per-directory tool version at exec time). Full `mise activate` with its ~80 ms first-prompt and ~15 ms per-prompt hook cost is opt-in via `DOTFILES_MISE_ACTIVATE=1`. fnm stays installed with a guarded fallback until the user removes it after a day of clean operation.

**Tech Stack:** mise 2026.9.x (Homebrew formula), zsh 5.9, bash 3.2 scripts, `tests/lib.sh` harness.

**Spec:** `~/Vault/Resources/dotfiles-audit-2026-09-21-reports/research-mise.md` (sections Q1–Q10, (a)–(d)) and `~/Vault/Resources/dotfiles-audit-2026-09-21.md` §6 (fnm → mise, npm globals). Wave 1 plan: `docs/plans/2026-09-21-audit-remediation-plan.md` (same Global Constraints apply).

## Global Constraints

- Everything in the wave 1 plan's Global Constraints (Apple silicon only, bash 3.2, shellcheck set, never break live agents, never write under `~/.claude`, side-effect-free tests, commit rules).
- `mise activate` must never be sourced from `.zprofile`/`.profile`; only shims may be added there (mise docs: profile hooks never fire).
- `[settings]` must contain `idiomatic_version_file_enable_tools = ["node"]` (else `.nvmrc`/`.node-version` are ignored), `not_found_auto_install = false` (no surprise installs in agent shells), `lockfile = true`, `paranoid = true`, `minimum_release_age = "3d"`, `quiet = true`, `[settings.node] corepack = false`, `gpg_verify = true`.
- Node version pinned to the major fnm currently defaults to (`24`), not `lts`, for the migration commit; switching to `lts` is a follow-up.
- No `asdf:`, `vfox:` or `ubi:` backends. `npm:` tools that need native builds (`@tobilu/qmd` via better-sqlite3, `sharp`, `@yao-pkg/pkg`, `@mermaid-js/mermaid-cli`) get an explicit `allow_builds`; everything else stays `--ignore-scripts` (mise default).
- `mise dot` is never enabled (it overlaps with Stow).
- fnm is NOT uninstalled and `~/.local/share/fnm` / `~/.local/runtime/fnm_multishells` are NOT deleted by this plan; those are the user's later manual step.

## Review Focus

1. A new login shell with mise installed but `mise install` never run must still find `node` (fnm fallback). Pinned in Task M2.
2. A hook running under `env -i PATH=/usr/bin:/bin bash` must find `qmd` once shims exist. Pinned in Task M2.
3. `dotfiles install --node` on a machine with no mise must install mise and Node, not silently skip. Pinned in Task M3.
4. `.nvmrc` in a project directory must switch the `node` shim's version. Pinned in Task M1 (settings) and verified manually in M4.
5. A running shell that already has fnm on PATH must keep working after every commit (PATH order: shims first, fnm entry untouched). Pinned in Task M2.

## File Ownership (single implementer, sequential; runs after wave 1 is integrated)

`config/mise/config.toml` (new), `config/mise/mise.lock` (new, generated), `system/.mise` (new), `system/.fnm` (fallback only), `runcom/.profile`, `runcom/.zshrc`, `scripts/requirers.sh`, `bin/dotfiles` (`sub_install_node`, `sub_install_packages` npm branch), `bin/dotfiles-doctor`, `bin/dotfiles-test`, `bin/dotfiles-profiler`, `config/husky/init.sh`, `claude/hooks/index-sessions.sh`, `packages/npm.list` (delete), `docs/agents/packages.md`, `docs/agents/shell-config.md`, `AGENTS.md` (FNM line), `tests/mise.sh` (new).

---

### Task M1: Global mise config in the repo

**Files:** Create `config/mise/config.toml`; Test `tests/mise.sh`.

- [ ] Tests:
```bash
#!/usr/bin/env bash
# tests/mise.sh -- wave 2 (mise) regression tests.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
section "M1 -- global mise config"
t "M1.1" "config exists and is TOML mise accepts" 'command -v mise >/dev/null && MISE_CONFIG_DIR="$ROOT_DIR/config/mise" MISE_GLOBAL_CONFIG_FILE="$ROOT_DIR/config/mise/config.toml" mise config ls >/dev/null 2>&1'
t "M1.2" "idiomatic node version files enabled" 'grep -q "idiomatic_version_file_enable_tools = \[\"node\"\]" config/mise/config.toml'
t "M1.3" "no auto install in agent shells" 'grep -q "not_found_auto_install = false" config/mise/config.toml'
t "M1.4" "lockfile, paranoid, release age, quiet set" 'for k in "lockfile = true" "paranoid = true" "minimum_release_age = " "quiet = true"; do grep -q "$k" config/mise/config.toml || exit 1; done'
t "M1.5" "node pinned to major 24, corepack off, gpg on" 'grep -qE "^node *= *\"24\"" config/mise/config.toml && grep -q "corepack = false" config/mise/config.toml && grep -q "gpg_verify = true" config/mise/config.toml'
t "M1.6" "every npm global from the reconciled list is declared" 'for p in @tobilu/qmd @openai/codex @biomejs/biome typescript; do grep -q "\"npm:$p\"" config/mise/config.toml || exit 1; done'
t "M1.7" "native-build tools declare allow_builds" 'for p in @tobilu/qmd sharp; do grep -E "\"npm:$p\"" config/mise/config.toml | grep -q allow_builds || exit 1; done'
t "M1.8" "no asdf/vfox/ubi backends" '! grep -qE "\"(asdf|vfox|ubi):" config/mise/config.toml'
t "M1.9" "pnpm, yarn and uv are tools, not corepack" 'grep -qE "^pnpm *=" config/mise/config.toml && grep -qE "^uv *=" config/mise/config.toml'
finish
```
- [ ] Run → fail. Write the config from research-mise.md (a), with the `[tools]` npm block built from `packages/npm.list` (post-WS-D, the reconciled list) plus the installed globals it references; `python = "3.14"`, `pnpm`, `yarn`, `uv`. Run → pass. Commit `feat(mise): track the global mise config in the repo`.

### Task M2: Shims at login, fnm fallback, opt-in activation

**Files:** Create `system/.mise`; modify `runcom/.profile` (loader loop: `.mise` before `.fnm`), `runcom/.zshrc` (opt-in activate block after the p10k instant-prompt guard), `system/.fnm` (only runs when `$HOME/.local/share/mise/shims` is absent), `config/husky/init.sh`, `claude/hooks/index-sessions.sh` (shims first, then `mise env -s bash`, then fnm fallback).

- [ ] Tests:
```bash
section "M2 -- shims, fallback, activation"
t "M2.1" "login shell puts mise shims first on PATH when they exist" 'W=$(sandbox); mkdir -p "$W/.local/share/mise/shims" "$W/.cache"; cp -R runcom/. "$W/"; HOME="$W" ZDOTDIR="$W" XDG_CACHE_HOME="$W/.cache" DOTFILES_DIR="$ROOT_DIR" zsh -l -i -c "print -l \$path" 2>/dev/null | grep -n "mise/shims" | grep -q "^[1-3]:"'
t "M2.2" "without shims the fnm fallback still runs" 'W=$(sandbox); mkdir -p "$W/.cache" "$W/bin"; cp -R runcom/. "$W/"; printf "#!/bin/bash\necho \"export FNM_PROBE=1\"\n" > "$W/bin/fnm"; chmod +x "$W/bin/fnm"; [ "$(HOME="$W" ZDOTDIR="$W" XDG_CACHE_HOME="$W/.cache" DOTFILES_DIR="$ROOT_DIR" PATH="$W/bin:$PATH" zsh -l -i -c "echo \$FNM_PROBE" 2>/dev/null)" = 1 ]'
t "M2.3" "mise activate is never sourced from .profile/.zprofile" '! grep -q "mise activate" runcom/.profile runcom/.zprofile system/.mise'
t "M2.4" "activation in .zshrc is opt-in and after the instant prompt" 'awk "/p10k-instant-prompt/{p=1} p && /DOTFILES_MISE_ACTIVATE/{f=1} END{exit !f}" runcom/.zshrc'
t "M2.5" "index hook finds qmd through shims under a minimal PATH" 'W=$(sandbox); mkdir -p "$W/.local/share/mise/shims"; printf "#!/bin/bash\necho qmd-ok\n" > "$W/.local/share/mise/shims/qmd"; chmod +x "$W/.local/share/mise/shims/qmd"; grep -q "mise/shims" claude/hooks/index-sessions.sh && env -i HOME="$W" PATH=/usr/bin:/bin bash -c "source <(sed -n \"/^# --- tool resolution/,/^# --- end tool resolution/p\" claude/hooks/index-sessions.sh); command -v qmd" | grep -q shims'
t "M2.6" "husky init uses shims, not fnm env" 'grep -q "mise/shims" config/husky/init.sh && ! grep -q "fnm env" config/husky/init.sh'
```
(For M2.5 the hook must wrap its resolution block in `# --- tool resolution` / `# --- end tool resolution` marker comments so the test can source just that block.) Run → fail. Implement per research-mise.md (b), plus the `.zshrc` block guarded by `[[ "${DOTFILES_MISE_ACTIVATE:-0}" == 1 ]]`. After every edit: `zsh -n`, then `zsh -l -i -c 'echo ok'`. Commit `feat(mise): shims on PATH at login, fnm fallback, opt-in activation`.

### Task M3: Installer, doctor, test-suite, profiler

**Files:** `scripts/requirers.sh` (`require_mise`: `brew install mise` if absent; `source_mise`: prepend shims; delete `require_fnm`/`source_fnm`/`require_npm`), `bin/dotfiles` (`sub_install_node` → `require_mise && mise install` using the tracked config; `sub_install_packages` drops the npm branch and prints that npm CLIs come from `config/mise/config.toml`; `--node` help text), `bin/dotfiles-doctor` (check `mise doctor` exit and `mise which node`), `bin/dotfiles-test` and `bin/dotfiles-profiler` (fnm references → mise), `packages/npm.list` (delete), `docs/agents/packages.md`, `docs/agents/shell-config.md`, `AGENTS.md`.

- [ ] Tests:
```bash
section "M3 -- installer and docs"
t "M3.1" "require_fnm/source_fnm/require_npm are gone; require_mise exists" '! code_of scripts/requirers.sh | grep -qE "require_fnm|source_fnm|require_npm" && code_of scripts/requirers.sh | grep -q "^require_mise"'
t "M3.2" "install --node runs mise install" 'code_of bin/dotfiles | sed -n "/^sub_install_node()/,/^}/p" | grep -q "mise install"'
t "M3.3" "install --packages has no npm.list loop" '! code_of bin/dotfiles | grep -q "npm.list"'
t "M3.4" "npm.list deleted" '[ ! -e packages/npm.list ]'
t "M3.5" "doctor checks mise" 'code_of bin/dotfiles-doctor | grep -q "mise doctor"'
t "M3.6" "docs and AGENTS.md say mise, not FNM" '! grep -qi "fnm" AGENTS.md docs/agents/packages.md docs/agents/shell-config.md'
t "M3.7" "no fnm references remain in bin/ scripts except the fs.sh prune helper" '! code_of bin/dotfiles bin/dotfiles-doctor bin/dotfiles-setup bin/dotfiles-test bin/dotfiles-profiler scripts/requirers.sh | grep -qi fnm'
```
Run → fail; implement; run `bash tests/run.sh`, `./bin/dotfiles test --quick`; commit `feat(mise): install Node and npm CLIs through mise; retire the npm.list path`.

### Task M4: Real install and verification on this machine (no shell config changes beyond M2)

- [ ] `brew install mise` if absent (WS-D may have done it). `mise --version`, `mise doctor`.
- [ ] Generate the lockfile: `MISE_GLOBAL_CONFIG_FILE="$PWD/config/mise/config.toml" mise install` then `mise lock --global` written next to the config; commit `config/mise/mise.lock`. This installs Node 24 and ~45 npm tools; expect several minutes. If a tool fails to install, leave it out of `[tools]`, note it in the report, and continue.
- [ ] Verify: `mise which node` = v24.x; `env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c 'export PATH="$HOME/.local/share/mise/shims:$PATH"; command -v qmd && qmd --version'`; `cd` into a sandbox with `.nvmrc` = `22` and confirm `node --version` via shim reports 22 only if that version is installed, else that mise reports it missing (not auto-installed).
- [ ] Open a fresh login shell (`zsh -l -i -c 'which node; node --version; which qmd'`) and confirm shims are first. Measure `zsh -l -i -c exit` five times; report min/median against the wave 1 figure.
- [ ] Commit `chore(mise): lockfile from the first full install`.

**Follow-up for the user (not in this plan):** after a day of clean operation, `brew uninstall fnm`, `rm -rf ~/.local/share/fnm ~/.local/runtime/fnm_multishells`, delete `system/.fnm` and its loader entry, switch `node = "24"` to `"lts"`, and decide whether to enable `DOTFILES_MISE_ACTIVATE=1`.

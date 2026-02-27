---
title: macOS Dotfiles Multi-Category Audit - Security, Code Quality, Performance, Architecture Fixes
date: 2026-02-27
category: code-quality
severity: critical
status: resolved
components:
  - shell-config
  - zsh-configuration
  - bash-scripting
  - macos-defaults
  - security-sudoers
  - ssh-configuration
  - package-management
  - prompt-configuration
  - fnm-node-manager
tags:
  - security-vulnerability
  - code-quality
  - performance-optimization
  - dead-code-elimination
  - pattern-consistency
  - shell-idioms
  - multi-phase-fix
  - post-fix-review
  - test-verified
related_issues: []
time_to_resolve: multi-session
verified: true
---

# Comprehensive Dotfiles Audit and Hardening

## Problem

A multi-category audit of the dotfiles repo surfaced 45+ issues spanning five areas: security defaults that actively weakened system protections (Gatekeeper disabled, quarantine dialogs suppressed, disk verification skipped), correctness bugs in critical scripts (broken shell conditionals, eval injection, subshell syntax errors, a blind git push with no confirmation), code quality problems (bash variables in a zsh-only file, wrong loop bounds, GNU-only flags on macOS, unquoted expansions), architectural waste (dead scripts still being invoked via eval, redundant HOMEBREW_PREFIX detection in multiple files, FNM output cached despite containing PID-specific paths), and stale dead code (two unused submodules, a require_gem function, a matrix2 function, Brewfile entries for superseded search tools).

## Root Cause

The issues accumulated through three distinct vectors:

1. **Organic growth**: The repo evolved from a personal setup script into a structured dotfiles system, but early convenience decisions (NOPASSWD: ALL, disabling Gatekeeper) were never revisited after the initial machine bootstrap.
2. **Bash-to-zsh migration artifacts**: .zprofile still contained bash-style history variables (HISTFILESIZE, HISTDUP) and HISTDUP=erase which are not valid zsh options, and command -v checks were used throughout instead of zsh native $+commands[] hash.
3. **Dead code from removed tools**: bin/is-supported and bin/is-executable were small wrapper scripts that introduced an eval call when used for HOMEBREW_PREFIX detection. The FNM caching was a well-intentioned performance optimization that was architecturally incorrect -- fnm env outputs paths containing the current session PID-specific temp directories, making cached output invalid across shells.

## Investigation Steps

1. Ran 7 parallel audit agents covering: security, code quality, performance, architecture, patterns, simplicity, and linting
2. Synthesized 45+ findings into a 5-phase prioritized remediation plan ordered by severity
3. Executed fixes systematically with task tracking across all phases
4. Ran a 3-agent post-fix review (security sentinel, code quality reviewer, simplicity reviewer) that caught 3 additional critical bugs in the fixes themselves

## Solution

### Phase 1: Critical Fixes

#### remote-install.sh -- 3 compounding bugs

Before:
```bash
CMD="git clone --recurse-submodules $SOURCE $TARGET"
if [ ! is_executable "git" ]; then
  echo "Git is not available. Aborting."
else
  mkdir -p "$TARGET"
  eval "$CMD"
  $(builtin cd "$TARGET" && ./bin/dotfiles install)
fi
```

After:
```bash
if ! is_executable "git"; then
  echo "Git is not available. Aborting."
else
  mkdir -p "$TARGET"
  git clone --recurse-submodules "$SOURCE" "$TARGET"
  (cd "$TARGET" && ./bin/dotfiles install)
fi
```

The [ ! is_executable "git" ] form passes the string is_executable to [ as a non-empty string, which is always true. The eval was unnecessary and a minor injection surface. The $(...) captures output instead of just running in a subshell; (...) is the correct form.

#### sub_update() -- blind git push replaced with confirmation

Shows git status --short, displays changed files, and requires explicit y/N confirmation before git add -A, commit, and push.

#### SSH config -- overwrite replaced with append-if-missing

Uses grep -q to check if config block already exists, backs up before appending, uses heredoc with cat >> instead of tee overwrite.

#### HOMEBREW_PREFIX -- removed eval chain

Replaced is-supported eval chain (3 subprocess forks) with inline uname -m check. Deleted bin/is-supported, bin/is-macos, bin/is-executable.

#### FNM cache -- removed (outputs PID-specific paths)

fnm env outputs FNM_MULTISHELL_PATH with PID-specific temp directories -- caching this means every subsequent shell inherits a dead temp directory. Replaced with direct eval since fnm is Rust-based (~2-5ms).

### Phase 2: Security and Correctness

- **P10k instant prompt** enabled (POWERLEVEL9K_INSTANT_PROMPT=verbose)
- **History config** fixed: removed bash-only HISTFILESIZE and HISTDUP=erase, matched SAVEHIST=32768 to HISTSIZE
- **LANG encoding** fixed: en_US to en_US.UTF-8
- **Dangerous aliases** guarded: rr alias now uses -I flag (prompts for >3 files), cleanupad uses -prune and +
- **Scoped NOPASSWD sudo**: from ALL to specific commands (brew, softwareupdate, xattr, pkill coreaudiod)
- **macOS defaults hardened**: removed Gatekeeper disable, quarantine disable, disk image verification skip

### Phase 3: Modernization

- **$+commands[] standardization**: all command -v in zsh files changed to O(1) hash lookup
- **Function fixes**: colors() loop bound, duf() du flag, gitnr() error guards, ipinfo() quoting, curl -k removal
- **Redundant setup removed**: duplicate HOMEBREW_PREFIX in .completion, duplicate PATH in .profile

### Phase 4: Cleanup

- **Deleted dead scripts**: bin/is-supported, bin/is-macos, bin/is-executable
- **Removed dead code**: require_gem(), matrix2(), gem commands from update alias
- **Removed stale submodules**: zsh-thefuck, zsh-lazy-load
- **Renamed** .fix to .thefuck for clarity
- **Brewfile**: removed ack and the_silver_searcher (superseded by ripgrep)

### Phase 5: Performance

- **Trimmed P10k segments**: removed 10 unused version manager segments
- **Simplified history setopt**: SHARE_HISTORY implies INC_APPEND_HISTORY and APPEND_HISTORY

### Post-Review Fixes (caught by 3-agent review)

1. **Sudoers guard mismatch**: grep for NOPASSWD:ALL would not match new scoped entry -- changed to grep for NOPASSWD:
2. **Wrong pkill path**: /usr/sbin/pkill to /usr/bin/pkill (verified with which pkill)
3. **Intel incompatibility**: hardcoded /opt/homebrew/bin/brew to $HOMEBREW_PREFIX/bin/brew

## Verification

- **109/109 tests pass** (./bin/dotfiles test)
- **Shell startup: 234ms** (excellent)
- **Shellcheck**: clean on all bash scripts
- **Zsh syntax**: all system files parse without errors

## Prevention Strategies

### Automated Checks

Add CI anti-pattern detection:
- grep for NOPASSWD:ALL -- overly permissive sudo
- grep for curl.*-k -- insecure curl
- grep for eval with variables -- eval of variables
- grep for HISTFILESIZE or HISTDUP in zsh files -- bash-in-zsh variables
- grep for command -v in system/ -- should use $+commands[]

### Code Review Red Flags

| Severity | Pattern | Why |
|----------|---------|-----|
| CRITICAL | eval $variable | Arbitrary code execution |
| CRITICAL | curl -k | Disables TLS verification |
| CRITICAL | NOPASSWD:ALL | Unrestricted passwordless sudo |
| HIGH | command -v in zsh | Use $+commands[] (O(1)) |
| HIGH | Caching PID-specific paths | Cache not reusable across sessions |
| HIGH | tee overwriting config files | Use append-if-missing pattern |
| MEDIUM | Hardcoded binary paths | Verify with which first |

### Best Practices Established

1. **Use $+commands[]** for zsh command checks (O(1) hash lookup vs subprocess)
2. **Use append-if-missing** instead of overwrite for config files
3. **Scope sudo NOPASSWD** to specific commands with full paths
4. **Do not cache session-specific data** (PIDs, temp paths)
5. **Verify binary paths** with which before hardcoding (especially in sudoers)
6. **Use SHARE_HISTORY** alone -- it implies INC_APPEND_HISTORY and APPEND_HISTORY
7. **Match SAVEHIST to HISTSIZE** -- mismatched values silently truncate history

### Periodic Audit Schedule

- **Monthly**: Run test suite, check for deprecation warnings
- **Quarterly**: Anti-pattern grep scan, submodule freshness, binary path verification
- **Semi-annually**: Full multi-agent audit (security, quality, performance, architecture)

## Related Documentation

- [docs/agents/architecture.md](../../agents/architecture.md) -- Directory layout, Stow linking, submodules
- [docs/agents/shell-config.md](../../agents/shell-config.md) -- Prezto, source order, caching, profiles
- [docs/agents/secrets.md](../../agents/secrets.md) -- Keychain integration, secret storage
- [docs/agents/testing-and-ci.md](../../agents/testing-and-ci.md) -- Test suite, CI, git hooks
- [docs/agents/commands.md](../../agents/commands.md) -- CLI commands and workflows
- [docs/agents/packages.md](../../agents/packages.md) -- Brewfile and package management

## Files Changed

26 files modified across the repository:

| Category | Files |
|----------|-------|
| Scripts | remote-install.sh, bin/dotfiles, scripts/requirers.sh |
| Shell config | system/.fnm, .fzf, .zoxide, .bindings, .completion, .env, .alias |
| Functions | system/.function, .function_fs, .function_fun, .function_network |
| Prompt | system/.prompt |
| Runcom | runcom/.zshrc, .zprofile, .profile |
| macOS | macos/defaults.sh |
| Packages | Brewfile |
| Deleted | bin/is-supported, bin/is-macos, bin/is-executable, system/.fix |
| Renamed | system/.fix to system/.thefuck |
| Config | .gitignore, .gitmodules |

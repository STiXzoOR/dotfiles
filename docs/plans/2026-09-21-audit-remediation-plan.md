# Audit Remediation (2026-09-21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remediate every finding in the 2026-09-21 deep audit so a clean Apple-silicon Mac can bootstrap from this repo, nothing destroys user data, and the shell/agent layers stop drifting from what is live.

**Architecture:** Six independent workstreams edit disjoint file sets in the same checkout on branch `fix/audit-remediation` (no worktree, per the user). Each workstream keeps its own bash test file under `tests/` built on a shared harness `tests/lib.sh`; `tests/run.sh` runs them all and CI calls it. Every fix is test-first. A second wave (mise migration) follows once the mise research lands and wave 1 is integrated.

**Tech Stack:** bash 3.2 (install scripts, tests), zsh 5.9 + Prezto (shell), Homebrew 7, GNU Stow, shellcheck 0.11, GitHub Actions.

**Spec:** `~/Vault/Resources/dotfiles-audit-2026-09-21.md` (synthesis) and the ten raw reports in `~/Vault/Resources/dotfiles-audit-2026-09-21-reports/`. Section numbers below (e.g. §2.3) refer to the synthesis; `cli#7`, `shell#S2`, `macos#bug 4`, `pkg`, `claude#item 6`, `ci#12` refer to numbered items in the raw reports `audit-cli.md`, `audit-shell.md`, `audit-macos.md`, `audit-packages.md`, `audit-claude.md`, `audit-ci.md`.

## Global Constraints

- Apple silicon only. `HOMEBREW_PREFIX` is `/opt/homebrew`, hardcoded; scripts that need it exit early on non-`arm64` with the message `This repo supports Apple silicon only (Homebrew drops Intel in Sept 2027).` Delete every `/usr/local` prefix branch and `bin/is-apple-silicon`.
- All bash scripts stay bash 3.2 compatible: no `mapfile`/`readarray`, no `declare -A`, no `${var,,}`/`${var^^}`, no `declare -n`. `((x++))` never appears under `set -e` (use `x=$((x + 1))`).
- Every shell file passes `shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash` (bash) or `zsh -n` (zsh). New test files carry `# shellcheck disable=SC2016` like `tests/audit-regressions.sh` does.
- **Never break live agents.** 25 Claude Code processes are running on this machine. Never write under `~/.claude` (read is fine). Never run `dotfiles install …`, `configure`, `link`, `unlink`, `update`, `clean`, `install_claude.sh`, `stow`, `launchctl`, `sudo`, `brew bundle`, `brew uninstall` of anything a running process may use, or `rm` under `~/.local/runtime`. `brew install <new tool>` is allowed. Files under `runcom/` and `system/` are stowed into `$HOME` and take effect for every **new** shell immediately: after every edit there, run `zsh -n <file>` and `zsh -l -i -c 'exit'` and fix before moving on.
- Tests must be side-effect free on the real machine: no writes under `$HOME` except `mktemp` under `$TMPDIR`, no real keychain, no network. Sandbox with `HOME=$(mktemp -d)`, `DOTFILES_DIR`, `XDG_*` overrides.
- Commit per task with `git add <your files>` then `git commit -m "<type>(<scope>): <summary>" -- <your files>`. Never `git add -A`, `git add .`, or `git commit -a` (other workstreams are editing beside you). On `index.lock` errors, wait two seconds and retry. Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Do not edit files owned by another workstream (ownership table below). If you need a change there, write it in your final report under "Cross-workstream requests".
- Do not edit `tests/audit-regressions.sh` unless you are WS-F; if one of its tests breaks because of your change, say so in your report with the test id.
- Public repo: no names, emails, hostnames, absolute `/Users/…` paths, or tokens in tracked files.

## File Ownership

| Workstream | Owns | Test file |
|---|---|---|
| WS-0 (lead, sequential, before dispatch) | `tests/lib.sh`, `tests/run.sh`, `tests/repo.sh`, `.gitignore`, `.gitattributes`, `.gitmodules` + submodule removals (`modules/stevenblack-hosts`, `runcom/.vim/bundle/Vundle.vim`, `modules/prezto-contrib`, `config/spicetify/Themes`), `modules/zsh` (orphan) | `tests/repo.sh` |
| WS-A cli | `bin/dotfiles`, `bin/dotfiles-setup`, `bin/dotfiles-doctor`, `bin/dotfiles-profiler`, `bin/dotfiles-cheatsheet`, `bin/command-exists`, `bin/is-apple-silicon` (delete), `bin/plistbuddy`, `scripts/echos.sh`, `scripts/requirers.sh`, `scripts/lib/fs.sh`, `scripts/lib/ssh.sh`, `scripts/install_prezto.zsh`, `remote-install.sh`, `fonts/install.sh` | `tests/cli.sh` |
| WS-B macos | `macos/**`, `bin/dotfiles-baseline`, `launchagents/**` | `tests/macos.sh` |
| WS-C shell | `runcom/.zshrc`, `runcom/.zprofile`, `runcom/.zlogin`, `runcom/.zpreztorc`, `runcom/.profile`, `runcom/.hushlogin`, `runcom/.mackup.cfg` (delete), `system/**` (except `hosts.whitelist`), `profiles/**` except `profiles/local.zsh` (lead edits that), `completions/**` | `tests/shell.sh` |
| WS-D packages | `Brewfile`, `packages/**`, `config/git/**`, `config/husky/**`, `config/nvim/**`, `config/karabiner/**`, `config/thefuck/**` (delete), `config/spicetify/**` (delete), `config/prettier/**`, `apps/**`, `runcom/.vimrc` (delete), `runcom/.vim/**` (delete), `runcom/.vim-spell-en.utf-8.add` (delete), `runcom/.gemrc` | `tests/packages.sh` |
| WS-E claude+docs | `claude/**`, `scripts/install_claude.sh`, `scripts/lib/lists.sh`, `bin/dotfiles-claude` (new), `AGENTS.md`, `README.md`, `docs/**` except this plan, `CODE_OF_CONDUCT.md` | `tests/claude.sh` |
| WS-F gates | `.github/**`, `.githooks/**`, `bin/dotfiles-test`, `bin/dotfiles-secrets`, `tests/audit-regressions.sh`, `tests/ci.sh`, `tests/secrets.sh`, `.editorconfig` | `tests/ci.sh`, `tests/secrets.sh` |

## Review Focus

1. A prompt answered with any word containing `y` (`Nay`, `absolutely not`) must be treated as **no** everywhere a destructive action follows. Pinned in WS-A Task A1.
2. `dotfiles clean` on a machine where another shell is mid-session must leave that shell's `node` resolvable. Pinned in WS-A Task A4.
3. A fresh clone with zero submodules initialised must still get a working Prezto after `install --prezto`. Pinned in WS-A Task A3.
4. `install --claude` on a machine that already has newer hooks must not replace them without a backup. Pinned in WS-E Task E1.
5. A `defaults write` that fails (TCC, missing domain) must not print `[ok]`. Pinned in WS-B Task B4.

---

## Shared test harness (WS-0, Task 0.1)

`tests/lib.sh` provides exactly what `tests/audit-regressions.sh` already defines, so every workstream's file looks the same:

```bash
# tests/lib.sh — shared harness. Source it; call t/section; call finish at the end.
# shellcheck shell=bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1
GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0; fail=0; failed_names=()
_tmp_dirs=()
t() { # t <id> <description> <shell expression>
  if eval "$3" >/dev/null 2>&1; then
    printf "  %s✓%s %s %s%s%s\n" "$GREEN" "$RESET" "$1" "$DIM" "$2" "$RESET"; pass=$((pass + 1))
  else
    printf "  %s✗%s %s %s\n" "$RED" "$RESET" "$1" "$2"; fail=$((fail + 1)); failed_names+=("$1 $2")
  fi
}
section() { printf "\n%s\n" "$1"; }
code_of() { sed -E 's/^[[:space:]]*#.*$//' "$@"; }
sandbox() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/dftest.XXXXXX"); _tmp_dirs+=("$d"); printf '%s' "$d"; }
skip_unless() { command -v "$1" >/dev/null 2>&1; }   # usage: skip_unless shellcheck || return-style guard in the test expr
finish() {
  local d; for d in "${_tmp_dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  printf "\n%s\n" "────────────────────────────────────────"
  printf "passed=%d failed=%d\n" "$pass" "$fail"
  if [ "$fail" -gt 0 ]; then printf "\nfailing:\n"; printf "  %s\n" "${failed_names[@]}"; fi
  [ "$fail" -eq 0 ]
}
```

A workstream test file:

```bash
#!/usr/bin/env bash
# tests/cli.sh — regression tests for the 2026-09-21 audit, CLI workstream.
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

section "A1 — confirm() is anchored"
t "A1.1" "Nay is not yes" '! (source scripts/echos.sh; confirm() { :; }; echo Nay | confirm "q?")'

finish
```

`tests/run.sh` runs every `tests/*.sh` except `lib.sh` and itself, prints a per-file summary, exits non-zero if any failed.

---

## WS-0 — Lead groundwork (sequential, done before dispatch)

### Task 0.1: Shared harness and runner

**Files:** Create `tests/lib.sh`, `tests/run.sh`, `tests/repo.sh`.

- [ ] Write `tests/repo.sh` with a self-test of the harness: `t "H.1" "sandbox dirs are cleaned by finish" '[ -n "$(sandbox)" ]'` and a failing probe `t "H.2" "t reports failure" 'false'` run in a subshell that asserts `finish` returns 1.
- [ ] Run `bash tests/repo.sh` → fails (`lib.sh` missing).
- [ ] Write `tests/lib.sh` and `tests/run.sh` as above. Run → passes. Commit `test: add shared bash test harness and runner`.

### Task 0.2: Submodule removals and orphan cleanup (§2.14, §2.15, §4.1, §4.6, pkg)

- [ ] Tests in `tests/repo.sh`: for each of `modules/stevenblack-hosts`, `runcom/.vim/bundle/Vundle.vim`, `modules/prezto-contrib`, `config/spicetify/Themes`: `t "R.<n>" "<path> submodule removed" '! git config -f .gitmodules --get "submodule.<path>.path"'`; `t "R.5" "modules/zsh orphan untracked" '[ -z "$(git ls-files modules/zsh)" ]'`. Run → all fail.
- [ ] `git submodule deinit -f -- <path>; git rm -f -- <path>; rm -rf .git/modules/<path>` for each; `git rm -r --cached modules/zsh && rm -rf modules/zsh`. Run → pass. Commit `chore: remove hosts, Vundle, prezto-contrib, spicetify-themes submodules and the modules/zsh orphan`.

### Task 0.3: `.gitignore` / `.gitattributes` (ci#49, ci#50, agents #11)

- [ ] Tests: `t "R.6" ".zsh_history ignored" 'git check-ignore -q runcom/.zsh_history'`, same for `runcom/.zcompdump`, `.envrc`, `.env`, `.direnv/`, `system/hosts.local`, `.claude/worktrees/`, `macos/baselines/*.local.tsv`; `t "R.7" "gitattributes normalises eol" 'grep -q "text=auto" .gitattributes'`. Run → fail.
- [ ] Add the patterns; `.gitattributes`: `* text=auto eol=lf` and `fonts/MesloHackNerd/*.ttf -diff`. Run → pass. Commit.

---

## WS-A — CLI and install pipeline

Read first: `AGENTS.md`, `docs/agents/commands.md`, raw report `audit-cli.md` (all 20 bugs, S1–S8, UX gaps), `audit-macos.md` bugs 4–6 and 9, 11, 13 and "Hosts flow", `audit-ci.md` items 46–48.

### Task A1: `confirm()` helper and non-interactive mode (cli#6, cli#7, §2.2, §1.12)

**Files:** Modify `scripts/echos.sh`, `bin/dotfiles` (all 18 `read -r -p … [y|N]` sites), `bin/dotfiles-doctor:225`, `docs`: none (WS-E updates commands.md). Test `tests/cli.sh`.

**Interfaces — Produces:** `confirm <prompt>` in `scripts/echos.sh`: returns 0 on `y`/`Y`/`yes` (any case) only; prints nothing and returns 0 when `DOTFILES_YES=1`; returns 1 on EOF.

- [ ] Tests:
```bash
section "A1 — confirm() anchored, non-interactive aware"
t "A1.1" "Nay is not yes"            '! (source scripts/echos.sh; printf "Nay\n" | confirm "q")'
t "A1.2" "absolutely not is not yes" '! (source scripts/echos.sh; printf "absolutely not\n" | confirm "q")'
t "A1.3" "yes is yes"                '(source scripts/echos.sh; printf "yes\n" | confirm "q")'
t "A1.4" "Y is yes"                  '(source scripts/echos.sh; printf "Y\n" | confirm "q")'
t "A1.5" "EOF is no"                 '! (source scripts/echos.sh; confirm "q" </dev/null)'
t "A1.6" "DOTFILES_YES=1 skips the prompt" '(source scripts/echos.sh; DOTFILES_YES=1 confirm "q" </dev/null)'
t "A1.7" "no unanchored yes-regex remains in bin/dotfiles" '! code_of bin/dotfiles | grep -qE "=~ \(yes\|y\|Y\)|=~ \(y\|yes\|Y\)|=~ \^\(y\|Y\)"'
t "A1.8" "install --all sets DOTFILES_YES" 'code_of bin/dotfiles | grep -qE "DOTFILES_YES=1" '
```
- [ ] Run → fail. Implement:
```bash
# scripts/echos.sh
confirm() {
  local response
  [[ "${DOTFILES_YES:-0}" == "1" ]] && return 0
  read -r -p "$1 [y|N] " response || return 1
  [[ "$response" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}
```
Replace every `read -r -p "… [y|N] " response; if [[ $response =~ … ]]` pair with `if confirm "…"; then`. In `sub_install_all`, `export DOTFILES_YES=1` before the nine calls. In `sub_install_ssh`, rename the old key to `id_ed25519.bak.<timestamp>` instead of `rm -f`.
- [ ] Run tests + `bash -n bin/dotfiles` + shellcheck → pass. Commit `fix(cli): anchor every yes/no prompt and add DOTFILES_YES for install --all`.

### Task A2: `require_*` contract and cask-fonts (cli#2, cli#4, cli#5, cli#19, §1.7–1.9)

**Files:** `scripts/requirers.sh`, `bin/dotfiles:305-316`.

- [ ] Tests:
```bash
section "A2 — require_* helpers"
t "A2.1" "require_brew passes only real args" '! code_of scripts/requirers.sh | grep -q "brew install \"\$1\" \"\$2\""'
t "A2.2" "require_brew fails when brew install fails" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; [ \"\$1\" = install ] && exit 9; exit 0\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  ! (PATH="$W/bin:$PATH"; source scripts/echos.sh; source scripts/requirers.sh; require_brew nonesuch >/dev/null 2>&1)'
t "A2.3" "require_brew does not print ok after failure" '
  W=$(sandbox); mkdir -p "$W/bin"
  printf "#!/bin/bash\n[ \"\$1\" = list ] && exit 1; exit 9\n" > "$W/bin/brew"; chmod +x "$W/bin/brew"
  ! (PATH="$W/bin:$PATH"; source scripts/echos.sh; source scripts/requirers.sh; require_brew nonesuch 2>&1) | grep -q "\[.*ok.*\]"'
t "A2.4" "no homebrew/cask-fonts tap anywhere" '! code_of bin/dotfiles scripts/requirers.sh | grep -q "cask-fonts"'
t "A2.5" "require_code resolves a code binary, not a variable" '! code_of scripts/requirers.sh | grep -qE "\|\| code=\""'
```
- [ ] Implement: every `require_*` = `if <install>; then ok; return 0; else error "…"; return 1; fi`; `brew install "$@"`; delete `require_tap homebrew/cask-fonts` and `require_brew fontconfig` from `sub_install_fonts`; `require_code` uses `local code_bin; code_bin=$(command -v code || echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code")`. Commit `fix(install): make require_* return real status and drop the dead cask-fonts tap`.

### Task A3: Submodule ensure helper (cli#3, §1.10)

**Files:** `scripts/lib/fs.sh` (add `dotfiles_ensure_submodule`), `bin/dotfiles` (`sub_install_prezto`, `sub_link`, `sub_install_vim` (delete, Vim is gone — see A9)), `scripts/install_prezto.zsh` (fail loudly when `modules/prezto/init.zsh` is missing), `remote-install.sh` (keep the plain clone, rely on the helper).

**Interfaces — Produces:** `dotfiles_ensure_submodule <repo-relative-path>` in `scripts/lib/fs.sh`: no-op when `<path>/.git` exists; otherwise `git -C "$DOTFILES_DIR" submodule update --init --depth 1 -- "$path"`; returns git's status.

- [ ] Tests:
```bash
section "A3 — submodules are initialised on demand"
t "A3.1" "ensure_submodule is a no-op on an initialised module" '
  W=$(sandbox); mkdir -p "$W/repo/mod"; touch "$W/repo/mod/.git"
  (DOTFILES_DIR="$W/repo"; source scripts/lib/fs.sh; dotfiles_ensure_submodule mod)'
t "A3.2" "ensure_submodule initialises a missing module shallowly" '
  W=$(sandbox); git init -q "$W/up"; (cd "$W/up" && git commit -q --allow-empty -m a && git commit -q --allow-empty -m b)
  git init -q "$W/repo"; (cd "$W/repo" && git -c protocol.file.allow=always submodule add -q "$W/up" mod >/dev/null 2>&1 && git commit -q -m add && git submodule deinit -f -q mod)
  (DOTFILES_DIR="$W/repo"; source scripts/lib/fs.sh; git -C "$W/repo" config protocol.file.allow always; dotfiles_ensure_submodule mod) && [ -e "$W/repo/mod/.git" ]'
t "A3.3" "install_prezto.zsh fails when prezto is absent" '
  W=$(sandbox); mkdir -p "$W/df/modules"; ! (DOTFILES_DIR="$W/df" HOME="$W/h" zsh scripts/install_prezto.zsh)'
t "A3.4" "sub_install_prezto calls the helper" 'code_of bin/dotfiles | grep -q "dotfiles_ensure_submodule modules/prezto"'
```
- [ ] Implement; commit `fix(install): initialise submodules on demand instead of assuming --recurse-submodules`.

### Task A4: fnm prune keys on live processes (cli#1, §2.1)

**Files:** `scripts/lib/fs.sh:86-130`.

- [ ] Test (the existing `S7.2*` tests in `audit-regressions.sh` must keep passing):
```bash
section "A4 — fnm prune protects directories a live process uses"
t "A4.1" "a dir referenced by a running process env is spared even with a dead pid" '
  W=$(sandbox); mkdir -p "$W/fnm_multishells"
  live="$W/fnm_multishells/99999996_1700000000"; mkdir -p "$live"; touch -t 202001010000 "$live"
  # a real process whose environment names the directory
  ( FNM_MULTISHELL_PATH="$live" sleep 5 ) & sp=$!
  sleep 0.2
  ( . scripts/lib/fs.sh; XDG_RUNTIME_DIR="$W" dotfiles_prune_fnm_multishells )
  r=$?; kill $sp 2>/dev/null; [ -e "$live" ]'
```
- [ ] Implement: before the loop, `_live=$(ps -Eww -o command= 2>/dev/null | grep -o "fnm_multishells/[0-9]*_[0-9]*" | sed "s|.*/||" | sort -u)`; skip any entry whose basename is in `$_live` (`case " $_live " in *" $base "*)` style, bash 3.2 safe); keep existing PID/PATH/`FNM_MULTISHELL_PATH` guards. Update the comment block. Commit `fix(fs): prune fnm multishells by live process environment, not by dead fnm-env pids`.

### Task A5: sudoers and Touch ID (macos bugs 4–6, S1–S5, cli S1–S3, §2.3)

**Files:** `bin/dotfiles` (`sub_install_passwordless`, its help line, the `NOPASSWD` check in `sub_install`), `bin/dotfiles-doctor` (new check: `/etc/pam.d/sudo_local` contains `pam_tid.so`; report, never fix).

- [ ] Tests:
```bash
section "A5 — no NOPASSWD sudoers writer"
t "A5.1" "sub_install_passwordless is gone" '! code_of bin/dotfiles | grep -q "sub_install_passwordless"'
t "A5.2" "nothing writes /etc/sudoers" '! code_of bin/dotfiles bin/dotfiles-setup | grep -q "/etc/sudoers"'
t "A5.3" "doctor checks sudo_local for pam_tid" 'code_of bin/dotfiles-doctor | grep -q "pam_tid"'
```
- [ ] Implement: delete the function and the `--passwordless` help line; in `sub_install` replace the sudoers check with plain `sudo -v` + keep-alive; doctor gains `check_touchid_sudo` (warn if absent, print the two-line `sudo_local` recipe). Commit `fix(security): remove passwordless-sudo installer; Touch ID via /etc/pam.d/sudo_local is the supported path`.

### Task A6: Hosts flow via prebuilt download (macos "Hosts flow", cli#15, S8, §2.15)

**Files:** `bin/dotfiles` (`sub_install_hosts`), `system/hosts.whitelist` stays. The submodule is already gone (WS-0).

- [ ] Tests:
```bash
section "A6 — hosts installs the prebuilt file"
t "A6.1" "no python venv or submodule in the hosts flow" '! code_of bin/dotfiles | grep -qE "venv|updateHostsFile|stevenblack-hosts"'
t "A6.2" "hosts URL is https raw StevenBlack" 'code_of bin/dotfiles | grep -q "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"'
t "A6.3" "whitelist filter removes listed domains" '
  W=$(sandbox); printf "0.0.0.0 amplitude.com\n0.0.0.0 evil.example\n" > "$W/hosts"; printf "amplitude.com\n" > "$W/wl"
  (source scripts/lib/fs.sh; dotfiles_hosts_apply_whitelist "$W/hosts" "$W/wl" > "$W/out"); ! grep -q amplitude.com "$W/out" && grep -q evil.example "$W/out"'
t "A6.4" "downloaded file is validated before install" 'code_of bin/dotfiles | grep -q "StevenBlack/hosts" && code_of bin/dotfiles | grep -qE "wc -l|Number of unique domains"'
```
- [ ] Implement `dotfiles_hosts_apply_whitelist <hosts> <whitelist>` in `scripts/lib/fs.sh` (awk: drop lines whose second field is in the whitelist). In `sub_install_hosts`: `curl -fsSL --proto '=https' --tlsv1.2 <url> -o "$tmp"`; validate `grep -q "# Title: StevenBlack/hosts"` and `[ $(wc -l < "$tmp") -gt 10000 ]`; apply whitelist and `system/hosts.local` append; `sudo cp /etc/hosts /etc/hosts.backup && sudo cp "$out" /etc/hosts && sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`. Prompt text fixed (`./system/hosts.local`). Note in the prompt that NextDNS users can skip. Commit `feat(hosts): download the prebuilt StevenBlack hosts file instead of generating it from a 1.9 GB submodule`.

### Task A7: Homebrew 7 tap trust and bundle step (§1.2, research-macos)

**Files:** `bin/dotfiles` (`sub_install_packages`), `bin/dotfiles-doctor` (check `brew --version` ≥ 7).

- [ ] Tests:
```bash
section "A7 — Homebrew 7 tap trust"
t "A7.1" "every declared tap is trusted before bundle" 'code_of bin/dotfiles | grep -q "brew trust --tap"'
t "A7.2" "brew bundle install failure is not reported as ok" '! code_of bin/dotfiles | grep -A1 "brew bundle install" | grep -q "^ *ok"'
t "A7.3" "doctor requires Homebrew 7" 'code_of bin/dotfiles-doctor | grep -qE "brew --version|HOMEBREW_VERSION"'
```
- [ ] Implement: replace the `brew tap` loop with `brew trust --tap "$t" >/dev/null 2>&1 || warn "could not trust tap $t"`, then `if brew bundle install --file=Brewfile; then ok …; else error …; return 1; fi`. Remove the `rm -f -r /Library/Caches/Homebrew/*` and the `xattr -d -r com.apple.quarantine` lines. MAS: print a note that MAS entries need an App Store login and a sudo prompt. Commit `fix(packages): trust third-party taps for Homebrew 7 and stop masking bundle failures`.

### Task A8: Apple silicon only + CLT + install flow (§1.13, §1.14, §1.16, §1.18, cli#8, UX gaps)

**Files:** `bin/dotfiles` (prefix, `sub_install`, closing advice, `open Warp`/`killall`), `bin/dotfiles-setup`, `bin/is-apple-silicon` (delete), `remote-install.sh` (arch guard), `scripts/echos.sh` (`print_result` → define as `if [[ $1 -eq 0 ]]; then ok "$2"; else error "$2"; fi`).

- [ ] Tests:
```bash
section "A8 — Apple silicon only, headless CLT"
t "A8.1" "no /usr/local prefix branch in bin/" '! code_of bin/dotfiles bin/dotfiles-setup bin/dotfiles-doctor | grep -q "/usr/local"'
t "A8.2" "is-apple-silicon is deleted" '[ ! -e bin/is-apple-silicon ]'
t "A8.3" "non-arm64 exits early with a message" '
  W=$(sandbox); mkdir -p "$W/bin"; printf "#!/bin/bash\necho x86_64\n" > "$W/bin/uname"; chmod +x "$W/bin/uname"
  PATH="$W/bin:$PATH" bash bin/dotfiles help 2>&1 | grep -q "Apple silicon only"'
t "A8.4" "print_result is defined" '(source scripts/echos.sh; declare -F print_result >/dev/null)'
t "A8.5" "CLT install is headless via softwareupdate" 'code_of bin/dotfiles | grep -q "softwareupdate" && code_of bin/dotfiles | grep -q "xcode-select -s"'
t "A8.6" "xcode wait loop is bounded" '! code_of bin/dotfiles | grep -q "until xcode-select"'
t "A8.7" "closing advice uses -- flags" '! code_of bin/dotfiles | grep -qE "BIN_NAME install (hosts|prezto|vim|fonts|packages|launchagents)\b"'
t "A8.8" "install never killalls Terminal" '! code_of bin/dotfiles | grep -q "killall \"Terminal\""'
```
- [ ] Implement per audit (`softwareupdate --list` label trick, `sudo softwareupdate --install "<label>" --agree-to-license`, `sudo xcode-select -s /Library/Developer/CommandLineTools`; `sudo xcodebuild -license accept` only if `xcode-select -p` points at an `Xcode.app`). Commit `feat(install): Apple silicon only, headless Command Line Tools, honest closing advice`.

### Task A9: link/unlink cover ~/.config; Vim removal; ssh-agent; doctor order; dead code (cli#9–#14, #16–#20, cli UX gaps, ci#47–48)

**Files:** `bin/dotfiles`, `bin/dotfiles-doctor`, `bin/dotfiles-profiler`, `bin/dotfiles-setup`, `scripts/lib/ssh.sh`.

- [ ] Tests:
```bash
section "A9 — link/unlink, update, routing, dead code"
t "A9.1" "link backs up ~/.config targets too" 'code_of bin/dotfiles | grep -q "XDG_CONFIG_HOME/\$file" || code_of bin/dotfiles | grep -q "stow --restow --adopt"'
t "A9.2" "unlink on an empty backup does not claim success" '
  W=$(sandbox); mkdir -p "$W/h/.dotfiles_backup/2026.01.01"
  ! (HOME="$W/h" bash bin/dotfiles unlink 2026.01.01 2>&1 | grep -q "restored into")'
t "A9.3" "no eval ssh-agent in install --ssh" '! code_of bin/dotfiles | grep -q "eval \"\$(ssh-agent -s)\""'
t "A9.4" "submodule update uses --init and no --remote" 'code_of bin/dotfiles | grep -q "submodule update --init" && ! code_of bin/dotfiles | grep -q "submodule update --remote"'
t "A9.5" "no git submodule init --recursive" '! code_of bin/dotfiles | grep -q "submodule init --recursive"'
t "A9.6" "doctor sources fs.sh after DOTFILES_DIR fallback" '
  W=$(sandbox); DOTFILES_DIR="$W/nonexistent" zsh -c "source bin/dotfiles-doctor --help" >/dev/null 2>&1; DOTFILES_DIR=/nonexistent-xyz zsh bin/dotfiles-doctor --help 2>&1 | grep -q "Usage"'
t "A9.7" "dispatch uses declare -F, not exit 127" '! code_of bin/dotfiles | grep -q "= 127"'
t "A9.8" "dotfiles edit has a default IDE" 'code_of bin/dotfiles | grep -q "DOTFILES_IDE:-"'
t "A9.9" "baseline is routed" 'code_of bin/dotfiles | grep -q "\"baseline\""'
t "A9.10" "doctor --help prints usage" 'zsh bin/dotfiles-doctor --help 2>&1 | grep -q "Usage"'
t "A9.11" "dead install_packages removed from bin/dotfiles" '! code_of bin/dotfiles | grep -q "^install_packages()"'
t "A9.12" "profile_detailed removed" '! code_of bin/dotfiles-profiler | grep -q "profile_detailed"'
t "A9.13" "unused wizard helpers removed" '! code_of bin/dotfiles-setup | grep -qE "^(ask_menu|ask_checklist|ask_input|start_spinner|stop_spinner|progress_bar)\(\)"'
t "A9.14" "install --vim is gone" '! code_of bin/dotfiles | grep -q "sub_install_vim"'
t "A9.15" "clean help text matches behaviour" '! code_of bin/dotfiles | grep -q "nvm, gem"'
t "A9.16" "setup log lives under TMPDIR" 'code_of bin/dotfiles-setup | grep -q "TMPDIR:-"'
t "A9.17" "ssh config helper checks for the Host * block, not IdentityFile" '! code_of scripts/lib/ssh.sh | grep -q "grep -q \"IdentityFile"'
```
- [ ] Implement; `sub_link` uses `stow --restow --adopt -t "$HOME" runcom` after the backup loop (and the same for `config` against `$XDG_CONFIG_HOME` with its own backup loop); `sub_unlink` returns 1 with a message when the backup dir is empty; `dotfiles_ensure_ssh_config` greps for `Host \*` + `UseKeychain`. Commit in two or three commits by theme.

### Task A10: `sub_configure` prompts once; `claude` subcommand route; help lists `claude` (macos #10, WS-E interface)

- [ ] Tests: `t "A10.1" "configure prompts once" '[ "$(code_of bin/dotfiles | sed -n "/^sub_configure()/,/^}/p" | grep -c confirm)" = "1" ]'`; `t "A10.2" "claude subcommand routes to bin/dotfiles-claude" 'code_of bin/dotfiles | grep -q "\"claude\"" && code_of bin/dotfiles | grep -q "dotfiles-claude"'`.
- [ ] Implement: `sub_configure` calls `sub_configure_defaults`/`sub_configure_dock` directly with `DOTFILES_YES=1`; add `"claude"` to the pass-through case arm → `"$DOTFILES_DIR/bin/dotfiles-claude" "$@"` (WS-E creates that file; if absent print `install --claude first`). Commit.

**WS-A final:** run `bash tests/cli.sh`, `bash tests/audit-regressions.sh`, `./bin/dotfiles test --quick`, shellcheck over changed files. Report per-task status, any `audit-regressions.sh` tests you broke, and cross-workstream requests.

---

## WS-B — macOS defaults, Dock, baseline, LaunchAgents

Read first: `docs/agents/macos-defaults.md`, raw `audit-macos.md` (all), `research-macos.md` §3–§6, `research-security.md` §E.

### Task B1: Baseline extractor correctness (macos bug 7, §4.2)

**Files:** `bin/dotfiles-baseline`. Test `tests/macos.sh`.

- [ ] Tests:
```bash
section "B1 — baseline extractor"
mk() { W=$(sandbox); mkdir -p "$W/macos"; printf "%s\n" "$1" > "$W/macos/defaults-x.sh"; printf '%s' "$W"; }
t "B1.1" "keys with spaces survive" 'W=$(mk "defaults write com.apple.print.PrintingPrefs \"Quit When Finished\" -bool true"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "Quit When Finished"'
t "B1.2" "indented writes are captured" 'W=$(mk "  defaults write com.apple.terminal \"Default Window Settings\" -string Nord"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "Default Window Settings"'
t "B1.3" "sudo writes are captured with their domain path" 'W=$(mk "sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "GuestEnabled"'
t "B1.4" "-currentHost writes are captured" 'W=$(mk "defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true"); DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q "disableHotPlug"'
t "B1.5" "a write with no key is rejected, not recorded as domain=-bool" 'W=$(mk "defaults write com.apple.sound.beep.feedback -bool false"); ! (DOTFILES_DIR="$W" bash bin/dotfiles-baseline list | grep -q -- "-bool")'
```
(Add a `list` subcommand that prints `domain<TAB>key[<TAB>flags]` per extracted write if none exists; read the script first and match its structure.) Run → fail. Implement (regex: optional leading whitespace, optional `sudo `, optional `-currentHost`, domain, key as `"[^"]+"` or `\S+`). Commit `fix(baseline): capture quoted, indented, sudo and -currentHost defaults writes`.

### Task B2: defaults bugs (macos bugs 1, 2, 10; §2.12)

**Files:** `macos/defaults.sh`, `macos/dock.sh`.

- [ ] Tests: `t "B2.1" "beep feedback key is in the global domain" 'grep -q "NSGlobalDomain com.apple.sound.beep.feedback" macos/defaults.sh'`; `t "B2.2" "no Launchpad references" '! code_of macos/defaults.sh macos/dock.sh | grep -qi launchpad'`; `t "B2.3" "dock adds Apps.app" 'grep -q "/System/Applications/Apps.app" macos/dock.sh'`; `t "B2.4" "scrollbar comment matches value" '! grep -B2 "WhenScrolling" macos/defaults.sh | grep -qi "always show"'`.
- [ ] Implement. Commit.

### Task B3: Dock robustness (macos bug 3)

- [ ] Tests: `t "B3.1" "each dockutil add is guarded by existence" '[ "$(grep -c "dockutil --add" macos/dock.sh)" -le 1 ]'` (i.e. a loop with `[ -d "$app" ] || { warn …; continue; }`); `t "B3.2" "missing apps are reported, not silently skipped" 'grep -q "warn" macos/dock.sh'`; `t "B3.3" "dock.sh has a shebang line for shellcheck" 'head -1 macos/dock.sh | grep -q "^#"'`. Drop Spark and Notion from the list (not installed). Commit.

### Task B4: `ok` only after success in macos scripts (macos bug 8, Review Focus 5)

**Files:** every `macos/defaults*.sh`; uses `print_result` from `scripts/echos.sh` (WS-A defines it; until then define a local fallback `type print_result >/dev/null 2>&1 || print_result() { [ "$1" -eq 0 ] && ok "$2" || error "$2"; }` at the top of `macos/defaults.sh`).

- [ ] Tests: `t "B4.1" "no '|| true' after systemsetup" '! grep -E "systemsetup.*\|\| true" macos/defaults.sh'`; `t "B4.2" "every defaults file sets DOTFILES_DIR before sourcing echos" 'for f in macos/defaults*.sh; do grep -q "DOTFILES_DIR" "$f" || exit 1; done'`; `t "B4.3" "CUSTOM_THEME_DIR is local or unset per file" '! grep -l "^CUSTOM_THEME_DIR=" macos/defaults-terminal.sh macos/defaults-xcode.sh | wc -l | grep -q 2'`. Implement; commit.

### Task B5: Security defaults and Tahoe additions (§3.5, §4.2, research-security §E)

**Files:** `macos/defaults.sh` (new "Firewall" and "Screen lock" blocks), `macos/defaults-appstore.sh` (system-domain update keys via sudo), `macos/defaults-mail.sh` (gate on `[ -d ~/Library/Containers/com.apple.mail ]`), `macos/defaults-transmission.sh` (`DownloadAsk`/`MagnetOpenAsk` true, drop the third-party blocklist auto-update).

- [ ] Tests: `t "B5.1" "firewall on + stealth" 'grep -q "socketfilterfw --setglobalstate on" macos/defaults.sh && grep -q "setstealthmode on" macos/defaults.sh'`; `t "B5.2" "screen lock immediate via sysadminctl" 'grep -q "sysadminctl -screenLock immediate" macos/defaults.sh'`; `t "B5.3" "software update keys in /Library/Preferences" 'grep -q "/Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall" macos/defaults-appstore.sh && grep -q "ConfigDataInstall" macos/defaults-appstore.sh'`; `t "B5.4" "mail defaults gated on the container" 'grep -q "Containers/com.apple.mail" macos/defaults-mail.sh'`; `t "B5.5" "transmission asks before downloading" 'grep -q "DownloadAsk -bool true" macos/defaults-transmission.sh'`; `t "B5.6" "WindowManager tiling keys declared" 'grep -q "EnableTiledWindowMargins" macos/defaults.sh'`; `t "B5.7" "reduceTransparency declared" 'grep -q "reduceTransparency" macos/defaults.sh'`; `t "B5.8" "no AdminHostInfo without a comment explaining it" 'grep -B1 AdminHostInfo macos/defaults.sh | grep -q "#"'`. Implement (comment that firewall/systemsetup need Full Disk Access for the terminal). Commit.

### Task B6: LaunchAgents and mackup README (macos bug 11, LaunchAgents)

- [ ] Tests: `t "B6.1" "bootstrap/bootout instead of load/unload" 'grep -q "launchctl bootstrap gui" bin/dotfiles || true'` — this function is in `bin/dotfiles` (WS-A file) so instead: write the request in your report; here only fix `launchagents/disabled/README.md` (mackup is maintained, 0.11.2 2026-09-09; the caveat is the symlink/iCloud model) and move plist log paths to `$HOME/Library/Logs/`. Test: `t "B6.1" "plist logs under ~/Library/Logs" '! grep -q "/tmp/mackup" launchagents/disabled/com.stixzoor.mackup-auto.plist'`. Commit.

### Task B7: Capture and commit the 26.6.1 baseline (macos bug 14)

- [ ] After B1 is green: `DOTFILES_BASELINE_DIR=macos/baselines bash bin/dotfiles-baseline capture 26.6.1` (read-only `defaults read` only; verify by reading the script first). Review the TSV for personal data (`NSUserKeyEquivalents`, `AppleLocale`): keep keys, redact nothing that is a preference, but drop any line containing `/Users/`. Test: `t "B7.1" "26.6.1 baseline committed" '[ -f macos/baselines/26.6.1.tsv ]'`, `t "B7.2" "baseline has no absolute home paths" '! grep -q "/Users/" macos/baselines/26.6.1.tsv'`. Commit `chore(baseline): capture macOS 26.6.1 defaults before the 27 upgrade`.

**WS-B final:** `bash tests/macos.sh`, `bash -n` + shellcheck (`-s bash`) on every `macos/*.sh` (add `#!/usr/bin/env bash` shebangs where missing; they are sourced, so no `set -e`). Report.

---

## WS-C — Shell layer

Read first: `docs/agents/shell-config.md`, raw `audit-shell.md` (all), `research-tooling.md` §2. Every file here is live for new shells: after each edit run `zsh -n <file>` and `zsh -l -i -c 'echo ok'`.

Tests live in `tests/shell.sh` and run zsh in a sandbox: `HOME=$(sandbox)` with `ZDOTDIR` pointing at a copy of `runcom/`, `DOTFILES_DIR="$ROOT_DIR"`, and `XDG_CACHE_HOME="$HOME/.cache"`. Helper to include in the file:

```bash
zshrun() { # zshrun <zsh code>  — login+interactive shell against a sandbox HOME, prints stdout
  local h; h=$(sandbox); mkdir -p "$h/.cache"; cp -R runcom/. "$h/"
  HOME="$h" ZDOTDIR="$h" XDG_CACHE_HOME="$h/.cache" DOTFILES_DIR="$ROOT_DIR" zsh -l -i -c "$1" 2>/dev/null
}
```

### Task C1: History, compdump, dircolors, autosuggest, load order (shell#4–#8)

**Files:** `runcom/.zpreztorc`, `runcom/.zprofile`, `runcom/.zlogin`, `runcom/.profile`, `system/.dir_colors` (no change), `system/.env`.

- [ ] Tests:
```bash
section "C1 — history, compdump, dircolors, load order"
t "C1.1" "HISTSIZE is 32768 in a login shell"   '[ "$(zshrun "echo \$HISTSIZE")" = 32768 ]'
t "C1.2" "SAVEHIST is 32768"                     '[ "$(zshrun "echo \$SAVEHIST")" = 32768 ]'
t "C1.3" ".zlogin compiles the prezto dump"      'grep -q "prezto/zcompdump" runcom/.zlogin'
t "C1.4" "LS_COLORS is non-empty under xterm-256color" '[ -n "$(TERM=xterm-256color zshrun "echo \$LS_COLORS")" ]'
t "C1.5" "dircolors cache is keyed on TERM or not cached" '! grep -q "dircolors.zsh" runcom/.profile || grep -q "TERM" runcom/.profile'
t "C1.6" "autosuggest style is not empty"        '[ -n "$(zshrun "echo \$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE")" ]'
t "C1.7" ".env is sourced before .path"          'grep -q "\.{env,function" runcom/.profile || grep -qE "\{env,.*path" runcom/.profile'
t "C1.8" "LC_ALL is not exported"                '! grep -q "export LC_ALL" system/.env'
```
- [ ] Implement per `audit-shell.md` fixes. Commit `fix(zsh): history size, compdump target, dircolors cache, autosuggest colour, load order`.

### Task C2: Aliases, completion, PATH hygiene, clobber (shell#10–#13, #18, #19)

**Files:** `system/.alias`, `system/.completion`, `system/.path`, `system/.fzf`, `system/.thefuck`, `completions/_fnm` (delete), `system/.function_fs:52`, `system/.function_network:3`.

- [ ] Tests:
```bash
section "C2 — aliases, completion, PATH"
t "C2.1" "functions/path/aliases builtins are not shadowed" '! zshrun "whence -w functions path aliases" | grep -q alias'
t "C2.2" "dotfiles completion lists current commands" 'for c in cheatsheet doctor hooks profiler secrets setup test baseline; do grep -q "$c" system/.completion || exit 1; done; ! grep -qE "\bdock\b|\bmacos\b" system/.completion'
t "C2.3" "vendored _fnm removed" '[ ! -e completions/_fnm ]'
t "C2.4" "PATH has no duplicate entries in a login shell" '[ "$(zshrun "print -l \$path" | sort | uniq -d | wc -l)" -eq 0 ]'
t "C2.5" "PATH entries are normalised (no /../)" '! zshrun "print -l \$path" | grep -q "/\.\./"'
t "C2.6" "no bare > redirect for caches under noclobber" '! code_of system/.path system/.fzf system/.thefuck system/.completion | grep -E "[^>|]> *\"?\\\$_[a-z_]*cache" '
t "C2.7" "npm completion cache is guarded and stale-checked" 'grep -q "commands\[npm\]" system/.completion'
t "C2.8" "dataurl text pattern is unquoted" '! grep -q "\"text/\*\"" system/.function_fs'
t "C2.9" "no Intel prefix branch in system/.path" '! grep -q "/usr/local/bin/brew" system/.path'
```
- [ ] Implement: rename to `lsfunctions`, `lspath`, `lsaliases`; regenerate `dotfiles` completion from the `sub_help` list (hardcode the current list); delete `completions/_fnm`; `path=(${^path}(N-/:A)); typeset -U path` at the end of `.path`; `>|` everywhere; `srv()` uses `local-web-server` (`ws`) or is deleted. Commit.

### Task C3: Keys, locale, Prezto config cleanup (shell#15, #16, improvements 7–8)

**Files:** `system/.bindings`, `runcom/.zpreztorc`.

- [ ] Tests: `t "C3.1" "KEYTIMEOUT is 1" '[ "$(zshrun "echo \$KEYTIMEOUT")" = 1 ]'`; `t "C3.2" "no chruby zstyle without ruby module" '! grep -q "ruby:chruby" runcom/.zpreztorc'`; `t "C3.3" "pmodule-dirs no longer lists prezto-contrib or modules/zsh" '! grep -qE "prezto-contrib|modules/zsh" runcom/.zpreztorc'`; `t "C3.4" "histsize zstyle present" 'grep -q "module:history. histsize" runcom/.zpreztorc'`. Implement; commit.

### Task C4: Post-profile hook and EDITOR (shell#2, §4.1, WS-D neovim)

**Files:** `runcom/.zshrc` (source `profiles/local.post.zsh` and `profiles/$DOTFILES_LOADED_PROFILE.post.zsh` at the very end, after Prezto), `profiles/README.md` (document: put anything that needs `compdef`, e.g. gcloud completion, in `local.post.zsh`), `profiles/personal.zsh.example` (show lazy secret accessor pattern), `system/.env` (`EDITOR`).

- [ ] Tests: `t "C4.1" ".zshrc sources local.post.zsh after prezto" 'awk "/prezto\/init.zsh/{p=1} p && /local.post.zsh/{f=1} END{exit !f}" runcom/.zshrc'`; `t "C4.2" "EDITOR prefers nvim when present" 'grep -q "commands\[nvim\]" system/.env'`; `t "C4.3" "README documents local.post.zsh" 'grep -q "local.post.zsh" profiles/README.md'`. Implement:
```zsh
# system/.env
if (( ${+commands[nvim]} )); then export EDITOR="nvim"; else export EDITOR="vim"; fi
```
Commit.

### Task C5: pay-respects replaces thefuck; mackup cfg removal (§6, pkg)

**Files:** `system/.thefuck` → rename to `system/.pay-respects` (guarded `(( $+commands[pay-respects] )) && eval "$(pay-respects zsh --alias fix)"` — check `pay-respects --help` for the exact alias flag after WS-D installs it; if not installed yet, write it guarded and test with a stub on PATH), `runcom/.profile` loader list, `runcom/.mackup.cfg` (delete).

- [ ] Tests: `t "C5.1" "thefuck init is gone" '[ ! -e system/.thefuck ] && ! grep -q thefuck runcom/.profile'`; `t "C5.2" "pay-respects is guarded" 'grep -q "commands\[pay-respects\]" system/.pay-respects'`; `t "C5.3" "mackup cfg removed" '[ ! -e runcom/.mackup.cfg ]'`. Implement; commit.

### Task C6: fzf-tab and atuin (research-tooling §2)

**Files:** `.gitmodules` (add `modules/fzf-tab`, shallow) — you may run `git submodule add --depth 1 https://github.com/Aloxaf/fzf-tab modules/fzf-tab`; `runcom/.zshrc` (source after Prezto's completion module, guarded on file existence); `system/.atuin` (guarded on `$+commands[atuin]`, `eval "$(atuin init zsh --disable-up-arrow)"`), `runcom/.profile` loader list, `Brewfile` request to WS-D for `atuin` (write it in your report; do not edit Brewfile).

- [ ] Tests: `t "C6.1" "fzf-tab sourced after prezto when present" 'grep -q "fzf-tab/fzf-tab.plugin.zsh" runcom/.zshrc'`; `t "C6.2" "atuin init guarded" 'grep -q "commands\[atuin\]" system/.atuin'`; `t "C6.3" "login shell still starts under 500ms" 'start=$(date +%s%N); zshrun "exit"; [ $(( ($(date +%s%N) - start) / 1000000 )) -lt 500 ]'`. Implement; commit.

**WS-C final:** `bash tests/shell.sh`, `zsh -n` on every changed file, `./bin/dotfiles test --quick`, and a real `zsh -l -i -c 'echo ok'` from your Bash tool. Report the measured login-shell time before/after. Also report exactly which two lines in `profiles/local.zsh` the lead should move into `profiles/local.post.zsh` (do not edit that file).

---

## WS-D — Brewfile, packages, configs, editor

Read first: `docs/agents/packages.md`, raw `audit-packages.md` (all), `research-tooling.md` §1, §3, §5, §6, `research-security.md` §B3, §G.

### Task D1: Brewfile correctness (pkg Brewfile table, §1.1–1.6)

**Files:** `Brewfile`. Test `tests/packages.sh`.

- [ ] Tests:
```bash
section "D1 — Brewfile"
t "D1.1" "no nonexistent arduino cask"          '! grep -q "^cask \"arduino\"" Brewfile'
t "D1.2" "no disabled/deprecated quicklook casks" '! grep -qE "^cask \"(superslicer|quicklook-json|qlstephen|quicklookase)\"" Brewfile'
t "D1.3" "tailscale declared once, as the formula" '[ "$(grep -cE "tailscale" Brewfile)" -eq 1 ] && grep -q "^brew \"tailscale\"" Brewfile'
t "D1.4" "sudo-touchid and its tap are gone"     '! grep -q "sudo-touchid" Brewfile && ! grep -q "artginzburg" Brewfile'
t "D1.5" "dead taps removed"                     '! grep -qE "khanhas/tap|khanakia/vercelgate" Brewfile'
t "D1.6" "every remaining tap has a consumer"    'for tp in $(grep -E "^tap " Brewfile | sed -E "s/^tap \"([^\"]+)\".*/\1/"); do grep -q "\"$tp/" Brewfile || exit 1; done'
t "D1.7" "neovim and mise declared"              'grep -q "^brew \"neovim\"" Brewfile && grep -q "^brew \"mise\"" Brewfile'
t "D1.8" "keg-only readline and ssh-copy-id removed" '! grep -qE "^brew \"(readline|ssh-copy-id)\"" Brewfile'
t "D1.9" "mackup, thefuck, fnm removed; pay-respects added" '! grep -qE "^brew \"(mackup|thefuck|fnm)\"" Brewfile && grep -q "^brew \"pay-respects\"" Brewfile'
t "D1.10" "tools the machine relies on are declared" 'for f in rtk asc xcodegen atuin gitleaks age lazygit difftastic; do grep -q "\"$f\"" Brewfile || exit 1; done'
t "D1.11" "claude-usage-tracker tap is declared or the cask removed" '! grep -q claude-usage-tracker Brewfile || grep -q "hamed-elfayome/claude-usage" Brewfile'
t "D1.12" "brew bundle list parses the file"     'brew bundle list --file=Brewfile --all >/dev/null'
```
- [ ] Implement (keep `starship` only if WS-C keeps a Starship path; default: remove). Also add `datadog-labs/pack` tap + `pup` if you keep it (it is installed and used). Then `brew install mise neovim pay-respects atuin gitleaks age lazygit difftastic` (new tools only; never uninstall). Commit `fix(brewfile): remove dead casks and taps, declare the tools this machine actually uses`.

### Task D2: npm list and VS Code list (pkg npm/VS Code, §4.4)

**Files:** `packages/npm.list`, `packages/code.list`.

- [ ] Tests: `t "D2.1" "qmd entry is the scoped package" 'grep -q "^@tobilu/qmd" packages/npm.list && ! grep -qx "qmd" packages/npm.list'`; `t "D2.2" "no stale 2022 globals" '! grep -qE "^(detect-circular-deps|get-port-cli|underscore-cli|gtop|instant-markdown-d|grunt-cli|gulp-cli|yarn|corepack|npm)$" packages/npm.list'`; `t "D2.3" "installed globals the instructions rely on are listed" 'for p in @openai/codex @llamaindex/liteparse @posthog/cli @stripe/cli @railway/cli resend-cli eas-cli @biomejs/biome typescript; do grep -q "^$p" packages/npm.list || exit 1; done'`; `t "D2.4" "headwind and duplicate tailwind extension removed" '! grep -qE "heybourn.headwind|lightyen.tailwindcss-intellisense-twin" packages/code.list'`; `t "D2.5" "copilot dependency listed with copilot-chat" '! grep -q github.copilot-chat packages/code.list || grep -q "^github.copilot$" packages/code.list'`. Add a header comment: "managed by mise npm: backend after the mise migration; this list is the interim source of truth". Commit.

### Task D3: git config hygiene (pkg git, §4.5, research-security §B2–B3)

**Files:** `config/git/config`.

- [ ] Tests: `t "D3.1" "no hardcoded /opt/homebrew gh path" '! grep -q "/opt/homebrew/bin/gh" config/git/config'`; `t "D3.2" "github user moved out" '! grep -qE "^\s*user = STiXzoOR" config/git/config'`; `t "D3.3" "lastupdate state removed" '! grep -q "lastupdate" config/git/config'`; `t "D3.4" "autocorrect prompts" 'grep -qE "autocorrect = prompt" config/git/config'`; `t "D3.5" "fsmonitor on" 'grep -q "fsmonitor = true" config/git/config'`; `t "D3.6" "fsck on transfer" 'grep -q "fsckObjects = true" config/git/config'`; `t "D3.7" "ssh signing scaffold present, key in local" 'grep -q "format = ssh" config/git/config && grep -q "allowedSignersFile" config/git/config && ! grep -q "signingkey" config/git/config'`; `t "D3.8" "ld alias quotes the email" '! grep -E "^\s*ld =" config/git/config | grep -q "\$(git config user.email)\""'`. Implement (`commit.gpgsign` stays **off** until the user adds `user.signingkey` to `config.local`; document in the file). Also `bin/dotfiles` writes `dotfiles.lastupdate` via `git config --global` (WS-A file) — request in report that it write to `config.local` instead. Commit.

### Task D4: Neovim only (pkg nvim/vim, §4.6)

**Files:** `config/nvim/lua/plugins/lsp.lua`, `config/nvim/lua/config/lazy.lua`, new `config/nvim/lazy-lock.json`, delete `runcom/.vimrc`, `runcom/.vim/**` (the Vundle submodule is already removed), `runcom/.vim-spell-en.utf-8.add`.

- [ ] Tests: `t "D4.1" "no setup_handlers" '! grep -q setup_handlers config/nvim/lua/plugins/lsp.lua'`; `t "D4.2" "mason-org paths" 'grep -q "mason-org/mason.nvim" config/nvim/lua/plugins/lsp.lua && grep -q "mason-org/mason-lspconfig.nvim" config/nvim/lua/plugins/lsp.lua'`; `t "D4.3" "automatic_enable not automatic_installation" '! grep -q automatic_installation config/nvim/lua/plugins/lsp.lua'`; `t "D4.4" "lazy-lock committed" '[ -f config/nvim/lazy-lock.json ]'`; `t "D4.5" "vim config removed" '[ ! -e runcom/.vimrc ] && [ ! -d runcom/.vim ]'`; `t "D4.6" "nvim headless loads the config without error" 'command -v nvim >/dev/null && HOME=$(sandbox) XDG_CONFIG_HOME="$ROOT_DIR/config" nvim --headless "+lua vim.print(1)" +qa >/dev/null 2>&1'` (D4.6 only after `brew install neovim`; generating the lockfile means running `nvim --headless "+Lazy! sync" +qa` with `XDG_CONFIG_HOME` pointed at the repo `config/` and `XDG_DATA_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME` pointed at a sandbox so nothing lands in `$HOME`; copy the resulting `lazy-lock.json` into `config/nvim/`). Use `vim.lsp.config()`/`vim.lsp.enable()` per nvim 0.11. Commit `feat(nvim): Neovim only — mason v2 API, pinned lockfile, Vim/Vundle removed`.

### Task D5: gemrc, husky, VLC, GitKraken, stray tracked files (pkg §"other", privacy)

**Files:** `runcom/.gemrc`, `config/husky/init.sh`, `apps/vlc/vlcrc` (regenerate as the 19 active lines), `apps/vlc/org.videolan.vlc.plist` (untrack), `apps/gitkraken/profile.template:66`, `config/karabiner/automatic_backups/*` (untrack), `config/thefuck/**` (delete), `config/spicetify/**` (delete; the Themes submodule is already gone).

- [ ] Tests: `t "D5.1" "gem source is https rubygems" 'grep -q "https://rubygems.org" runcom/.gemrc && ! grep -q "rubyforge" runcom/.gemrc'`; `t "D5.2" "gemrc has no /usr/local binstub" '! grep -q "/usr/local/bin" runcom/.gemrc'`; `t "D5.3" "husky init does not hardcode the prefix" '! grep -q "/opt/homebrew/bin/brew" config/husky/init.sh'`; `t "D5.4" "vlcrc is minimal" '[ "$(wc -l < apps/vlc/vlcrc)" -lt 80 ]'`; `t "D5.5" "vlc metadata network access off" 'grep -q "metadata-network-access=0" apps/vlc/vlcrc'`; `t "D5.6" "vlc plist untracked" '[ -z "$(git ls-files apps/vlc/org.videolan.vlc.plist)" ]'`; `t "D5.7" "gitkraken template has no project id" '! grep -q "47c2be4e" apps/gitkraken/profile.template'`; `t "D5.8" "pyc and karabiner backup untracked" '[ -z "$(git ls-files config/thefuck config/karabiner/automatic_backups)" ]'`; `t "D5.9" "spicetify tree removed" '[ ! -d config/spicetify ]'`. Note `bin/dotfiles` seeds the spicetify template in `sub_link` (WS-A file): request its removal in your report. Commit.

**WS-D final:** `bash tests/packages.sh`, `brew bundle list --file=Brewfile --all`, `./bin/dotfiles test --quick`. Report installed tools, cross-workstream requests (spicetify seed in `sub_link`, `lastupdate`, `atuin` already added).

---

## WS-E — Claude bootstrap, rules, docs

Read first: `AGENTS.md`, `docs/agents/*.md`, raw `audit-claude.md` (all), `research-agents.md` §1–§5, §7, `research-security.md` §F1. Read `~/.claude/hooks/index-sessions.sh` and `~/.claude/settings.json` (keys only). **Never write under `~/.claude`.**

### Task E1: Hooks — promote the live version, fix paths, back up on install (claude items 1–3, 9, 11; Review Focus 4)

**Files:** `claude/hooks/index-sessions.sh`, `claude/hooks/session-start.sh`, `scripts/install_claude.sh` (`install_hooks_and_rules`, `install_statusline`), `claude/settings.template.json` (`SessionEnd` wiring, `Stop` only for the sync). Test `tests/claude.sh`.

- [ ] Tests:
```bash
section "E1 — hooks"
t "E1.1" "repo hook has the single-instance lock"        'grep -q "mkdir" claude/hooks/index-sessions.sh && grep -qi "lock" claude/hooks/index-sessions.sh'
t "E1.2" "repo hook resolves gtimeout by absolute path"  'grep -qE "gtimeout|coreutils/libexec/gnubin/timeout" claude/hooks/index-sessions.sh'
t "E1.3" "repo hook finds qmd without an interactive shell" 'grep -qE "fnm env|mise|local/bin/qmd|\.local/share/mise/shims" claude/hooks/index-sessions.sh'
t "E1.4" "session-start reads Polaris/top-of-mind.md"    'grep -q "Polaris/top-of-mind.md" claude/hooks/session-start.sh'
t "E1.5" "installer backs up before overwriting hooks"   'grep -qE "\.bak|backup" scripts/install_claude.sh && ! grep -qE "^\s*cp \"\\\$file\" \"\\\$dest_dir/\\\$name\"$" scripts/install_claude.sh'
t "E1.6" "index hook wired to SessionEnd, not Stop"      'jq -e ".hooks.SessionEnd" claude/settings.template.json >/dev/null && ! jq -r ".hooks.Stop[]?.hooks[]?.command" claude/settings.template.json | grep -q index-sessions'
t "E1.7" "hook comment states its output enters model context" 'grep -qi "context" claude/hooks/session-start.sh'
```
- [ ] Implement: copy `~/.claude/hooks/index-sessions.sh` over the repo copy (read-only source), then edit the repo copy only if needed for public-repo hygiene; installer: `if [ -f "$dest" ] && ! cmp -s "$file" "$dest"; then cp "$dest" "$dest.bak.$(date +%s)"; fi` before `cp`. Commit `fix(claude): promote the live index hook, fix the top-of-mind path, back up on install`.

### Task E2: Bootstrap correctness (claude items 4–8, 10, 12, 13, 15; §2.6–2.8)

**Files:** `scripts/install_claude.sh`, `claude/plugins.list`, `claude/settings.template.json`.

- [ ] Tests:
```bash
section "E2 — bootstrap"
t "E2.1" "sessions collection targets the vault"      'grep -q "VAULT_DIR/Claude-Sessions" scripts/install_claude.sh && ! grep -q "sessions_dir=\"\$HOME/.claude/projects\"" scripts/install_claude.sh'
t "E2.2" "settings check finds a dangling path"       '
  W=$(sandbox); printf "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"bash %s/nonexistent.sh\"}]}]}}" "$W" > "$W/settings.json"
  ! (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'
t "E2.3" "settings check passes on a good file"       '
  W=$(sandbox); touch "$W/ok.sh"; printf "{\"statusLine\":{\"command\":\"bash %s/ok.sh\"}}" "$W" > "$W/settings.json"
  (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'
t "E2.4" "merge delivers authoritative keys"          '
  W=$(sandbox); printf "{\"hooks\":{\"old\":1},\"model\":\"keep-me\"}" > "$W/existing.json"
  printf "{\"hooks\":{\"new\":2},\"model\":\"template\"}" > "$W/template.json"
  (source scripts/install_claude.sh --lib 2>/dev/null; merge_settings_files "$W/template.json" "$W/existing.json" > "$W/out.json")
  [ "$(jq -r .model "$W/out.json")" = keep-me ] && [ "$(jq -r .hooks.new "$W/out.json")" = 2 ] && [ "$(jq -r .hooks.old "$W/out.json")" = null ]'
t "E2.5" "bootstrap exits non-zero when a step failed" 'grep -qE "return 1|exit 1" scripts/install_claude.sh && grep -q "FAILURES" scripts/install_claude.sh'
t "E2.6" "hook paths are not hardcoded to ~/.claude/skills" '! grep -q "\.claude/skills/recall" claude/settings.template.json'
t "E2.7" "qmd package name is scoped"                 '! grep -q "add .qmd. to packages" scripts/install_claude.sh && grep -q "@tobilu/qmd" scripts/install_claude.sh'
t "E2.8" "plugins.list marketplace ids match marketplaces.list names" 'for m in $(grep -v "^#" claude/plugins.list | grep -v "^$" | sed "s/.*@//" | sort -u); do grep -q "$m" claude/marketplaces.list || exit 1; done'
t "E2.9" "install script has a --lib mode for tests" 'grep -q -- "--lib" scripts/install_claude.sh'
t "E2.10" "channel pinned to stable with a version floor" 'jq -e ".autoUpdatesChannel == \"stable\" and (.minimumVersion|type) == \"string\"" claude/settings.template.json >/dev/null'
t "E2.11" "binary is verified against the signed manifest" 'grep -q "manifest.json.sig" scripts/install_claude.sh && grep -q "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" scripts/install_claude.sh'
```
- [ ] Implement: add `if [ "${1:-}" = "--lib" ]; then return 0 2>/dev/null || exit 0; fi` after function definitions and before `main`; `verify_settings_refs <file>` returns non-zero on any missing path (jq: `[..|strings] | map(select(test("^(bash |sh |)?(\\$HOME|/)")))` then expand `$HOME` and `test -e`); `merge_settings_files <template> <existing>`: authoritative subtrees `hooks`, `statusLine`, `env`, `autoUpdatesChannel`, `minimumVersion` come from the template; everything else existing-wins (`jq -s '.[1] * .[0] | .hooks = $t.hooks | …'`); hook commands resolve the plugin path from `claude plugin list --json` `.installPath` at install time and write the resolved absolute path (documented), falling back to `~/.local/bin/qmd`; `main` returns 1 when `FAILURES` non-empty and `bin/dotfiles` propagates it (request to WS-A). Installer downloads `manifest.json` + `.sig` for the installed version, verifies with `gpg` when available (warn, don't fail, if `gpg` is absent), checks `shasum -a 256`. Commit in two commits.

### Task E3: Statusline from stdin (claude S1–S5, §3.2)

**Files:** `claude/statusline.sh` (rewrite), `tests/claude.sh`. The `SL.*` tests in `audit-regressions.sh` will need updating (report to WS-F: SL.5 UA pin and SL.6 token-less render become moot; SL.7 shellcheck stays).

- [ ] Tests:
```bash
section "E3 — statusline reads stdin only"
fixture='{"model":{"display_name":"Opus"},"cwd":"/tmp","workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":1.5,"total_duration_ms":65000},"context_window":{"context_window_size":200000,"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":12}},"effort":"high"}'
t "E3.1" "renders model, context and limits from stdin" 'out=$(printf "%s" "$fixture" | PATH=/usr/bin:/bin bash claude/statusline.sh); echo "$out" | grep -q Opus && echo "$out" | grep -q "42" && echo "$out" | grep -q "31"'
t "E3.2" "no keychain, credentials or network access" '! code_of claude/statusline.sh | grep -qE "security find-generic-password|credentials.json|curl|api.anthropic.com|oauth"'
t "E3.3" "renders without rate_limits"                'printf "{\"model\":{\"display_name\":\"X\"}}" | bash claude/statusline.sh | grep -q X'
t "E3.4" "no git status walk per refresh"             '! code_of claude/statusline.sh | grep -q "status --porcelain"'
t "E3.5" "at most 3 jq invocations"                   '[ "$(code_of claude/statusline.sh | grep -c "jq ")" -le 3 ]'
t "E3.6" "shellcheck clean"                           'shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash claude/statusline.sh'
```
- [ ] Implement: one `jq -r` pass emitting a tab-separated line of every field, `IFS=$'\t' read -r …`, then pure-bash formatting; keep the existing two-line look and colours; effort from `.effort`; duration from `cost.total_duration_ms`. Delete the cache files logic. Commit `refactor(statusline): read everything from the stdin payload; drop the OAuth token path`.

### Task E4: Rules, templates, `dotfiles claude diff` (claude items 13–14, rules section, suggestion 1)

**Files:** `claude/rules/vault-lookback.md` (correct tool names `query/get/multi_get/status`), `claude/rules/gnu-tools.md` (add the non-interactive BSD caveat), remove `alwaysApply:` frontmatter, `scripts/install_claude.sh` (idempotently append `@~/.claude/rules/<name>.md` import lines to `~/.claude/CLAUDE.md` only if that file exists and lacks them — write this as a function; it is only executed by the installer, never by tests), new `bin/dotfiles-claude` with `diff` (compares `claude/hooks/*`, `claude/rules/*`, `claude/statusline.sh` and the template's authoritative keys against `~/.claude`, read-only, exit 1 on drift) and `verify` (runs `verify_settings_refs` against `~/.claude/settings.json` and executes each hook command with a synthetic empty JSON payload under `PATH=/usr/bin:/bin:/opt/homebrew/bin`, reporting exit codes).

- [ ] Tests: `t "E4.1" "vault-lookback names real qmd tools" '! grep -qE "qmd_search|qmd_vector_search|qmd_deep_search" claude/rules/vault-lookback.md && grep -q "multi_get" claude/rules/vault-lookback.md'`; `t "E4.2" "gnu-tools rule carries the non-interactive caveat" 'grep -qi "xargs" claude/rules/gnu-tools.md'`; `t "E4.3" "no cursor frontmatter" '! grep -rq "alwaysApply" claude/rules'`; `t "E4.4" "dotfiles-claude diff detects drift" 'W=$(sandbox); mkdir -p "$W/.claude/hooks"; printf "x\n" > "$W/.claude/hooks/index-sessions.sh"; ! HOME="$W" bash bin/dotfiles-claude diff >/dev/null 2>&1'`; `t "E4.5" "dotfiles-claude diff passes when identical" 'W=$(sandbox); mkdir -p "$W/.claude/hooks" "$W/.claude/rules"; cp claude/hooks/* "$W/.claude/hooks/"; cp claude/rules/* "$W/.claude/rules/"; cp claude/statusline.sh "$W/.claude/"; HOME="$W" bash bin/dotfiles-claude diff'`. Implement; commit.

### Task E5: Docs and AGENTS.md (claude doc-drift table, AGENTS.md gaps, §4.9, §7.8–7.9)

**Files:** `AGENTS.md`, `README.md`, `docs/agents/*.md`, `docs/plans/2026-03-03-*.md` → move to `docs/plans/archive/` with a "superseded" banner line at the top, `docs/agents/testing-and-ci.md` (document `tests/run.sh` and the per-workstream files), `.worktreeinclude` (new, empty with a comment).

- [ ] Tests: `t "E5.1" "architecture.md lists no dead package lists" '! grep -qE "brew.list|cask.list|mas.list|tap.list" docs/agents/architecture.md'`; `t "E5.2" "shell-config.md has no .fix" '! grep -q "\.fix" docs/agents/shell-config.md'`; `t "E5.3" "README does not claim Starship" '! grep -qi "uses Starship" README.md'`; `t "E5.4" "README mentions install --claude" 'grep -q "install --claude" README.md'`; `t "E5.5" "AGENTS.md states bash 3.2 and public repo" 'grep -q "3.2" AGENTS.md && grep -qi "public" AGENTS.md'`; `t "E5.6" "AGENTS.md names audit-regressions and a do-not-run list" 'grep -q "audit-regressions" AGENTS.md && grep -qi "do not run\|never run" AGENTS.md'`; `t "E5.7" "old plans archived" '[ ! -e docs/plans/2026-03-03-claude-bootstrap-plan.md ] && ls docs/plans/archive/ | grep -q 2026-03-03'`; `t "E5.8" "commands.md matches dotfiles help" 'for c in clean edit open profiler secrets setup cheatsheet baseline claude; do grep -q "$c" docs/agents/commands.md || exit 1; done'`; `t "E5.9" "worktreeinclude exists" '[ -f .worktreeinclude ]'`. Implement; commit `docs: bring AGENTS.md, README and docs/agents in line with the code`.

**WS-E final:** `bash tests/claude.sh`, `./bin/dotfiles test --quick`, shellcheck on `claude/*.sh`, `claude/hooks/*.sh`, `scripts/install_claude.sh`, `bin/dotfiles-claude`. Report cross-workstream requests (exit-code propagation in `bin/dotfiles`, `SL.*` test updates for WS-F).

---

## WS-F — CI, pre-commit, secrets tool, test suites

Read first: `docs/agents/testing-and-ci.md`, raw `audit-ci.md` (all), `research-security.md` §H, §C.

### Task F1: Pre-commit secret detection and syntax checks (ci#12–#17)

**Files:** `.githooks/pre-commit`. Test `tests/ci.sh`. Keep the hook working at every save; other workstreams are committing through it.

- [ ] Tests (build a fixture with nine realistic fake credentials, each with a random tail; e.g. `AKIA` + 16 uppercase alnum, `ghp_` + 36 alnum, `github_pat_` + 60, `sk-ant-api03-` + 40, `sk-proj-` + 40, `xoxb-` + digits, a JWT `eyJ…` header/payload, `sk_live_` + 24, and an OpenSSH private key header):
```bash
section "F1 — pre-commit"
t "F1.1" "secret patterns catch nine real formats" '
  W=$(sandbox); bash tests/fixtures/make-secrets.sh > "$W/f.txt"
  n=0; while IFS= read -r p; do grep -qE "$p" "$W/f.txt" && n=$((n+1)); done < <(bash .githooks/pre-commit --print-secret-patterns)
  [ "$n" -ge 9 ]'
t "F1.2" "gitleaks is used when installed" 'grep -q "gitleaks" .githooks/pre-commit'
t "F1.3" "dotfiles-secrets is not exempt from scanning" '! grep -q "bin/dotfiles-secrets" .githooks/pre-commit'
t "F1.4" "syntax check derives dialect from shell_dialect for every file" '! grep -q "zsh_scripts=" .githooks/pre-commit'
t "F1.5" "no ((x++)) under set -e" '! grep -q "((ERRORS++))" .githooks/pre-commit'
t "F1.6" "staged files are read NUL-safe" 'grep -q "diff --cached --name-only -z\|-print0\|read -r -d" .githooks/pre-commit'
t "F1.7" "PRIVATE KEY pattern requires BEGIN" 'bash .githooks/pre-commit --print-secret-patterns | grep -q "BEGIN"'
```
- [ ] Implement (`--print-secret-patterns` prints one ERE per line and exits; the hook runs `gitleaks protect --staged --no-banner` when available, else the patterns). Commit.

### Task F2: CI workflow hardening (ci#18–#25, research-security §H3)

**Files:** `.github/workflows/ci.yml`, `.github/dependabot.yml` (new).

- [ ] Tests: `t "F2.1" "permissions contents: read at top level" 'grep -qE "^permissions:" .github/workflows/ci.yml && grep -q "contents: read" .github/workflows/ci.yml'`; `t "F2.2" "checkout v5 with persist-credentials false" 'grep -q "actions/checkout@v5" .github/workflows/ci.yml && grep -q "persist-credentials: false" .github/workflows/ci.yml'`; `t "F2.3" "concurrency cancel" 'grep -q "cancel-in-progress: true" .github/workflows/ci.yml'`; `t "F2.4" "no submodules on lint/syntax jobs" '[ "$(grep -c "submodules: recursive" .github/workflows/ci.yml)" -le 1 ]'`; `t "F2.5" "no masked brew bundle check" '! grep -q "brew bundle check.*|| true" .github/workflows/ci.yml'`; `t "F2.6" "runner pinned" 'grep -qE "runs-on: macos-(15|26)" .github/workflows/ci.yml'`; `t "F2.7" "tests/run.sh is the test entry" 'grep -q "tests/run.sh" .github/workflows/ci.yml'`; `t "F2.8" "pre-commit hook exercised in CI" 'grep -q "githooks/pre-commit" .github/workflows/ci.yml'`; `t "F2.9" "dependabot for actions" 'grep -q "github-actions" .github/dependabot.yml'`; `t "F2.10" "gitleaks in CI" 'grep -q gitleaks .github/workflows/ci.yml'`; `t "F2.11" "brew bundle check job" 'grep -q "brew bundle list" .github/workflows/ci.yml'`. Implement; commit.

### Task F3: Secrets tool (ci#27–#34, §2.20, §3.10)

**Files:** `bin/dotfiles-secrets`, `tests/secrets.sh`. Tests must not touch the real keychain: create a throwaway keychain with `security create-keychain -p x "$W/test.keychain-db"` and make the tool honour `DOTFILES_KEYCHAIN` (pass `"$DOTFILES_KEYCHAIN"` as the last arg to every `security` call when set). Delete the keychain in `finish` via `security delete-keychain`.

- [ ] Tests:
```bash
section "F3 — secrets tool"
kc() { W=$(sandbox); security create-keychain -p x "$W/t.keychain-db" >/dev/null 2>&1; printf '%s' "$W/t.keychain-db"; }
t "F3.1" "set/get round-trip in a throwaway keychain" 'K=$(kc); printf "v1\n" | DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets set rt >/dev/null 2>&1; [ "$(DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets get rt)" = v1 ]'
t "F3.2" "delete removes the name from list"          'K=$(kc); printf "v\n" | DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets set d1 >/dev/null 2>&1; DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets delete d1 >/dev/null 2>&1; ! DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets list 2>/dev/null | grep -q d1'
t "F3.3" "env rejects an unsafe variable name"        'K=$(kc); printf "v\n" | DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets set e1 >/dev/null 2>&1; ! DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets env e1 "X; touch /tmp/pwned" >/dev/null 2>&1'
t "F3.4" "export refuses non-interactive stdin"       'K=$(kc); ! DOTFILES_KEYCHAIN="$K" bin/dotfiles-secrets export "$K.enc" </dev/null >/dev/null 2>&1'
t "F3.5" "import does not stage plaintext on disk"    '! code_of bin/dotfiles-secrets | grep -q "mktemp" || ! code_of bin/dotfiles-secrets | grep -A3 "cmd_import" | grep -q mktemp'
t "F3.6" "export uses age when available"             'grep -q "age -p" bin/dotfiles-secrets'
t "F3.7" "no ((x++)) under set -e"                    '! grep -q "((count++))" bin/dotfiles-secrets'
t "F3.8" "locked keychain is reported, not treated as empty" 'grep -qE "36|45|locked" bin/dotfiles-secrets'
```
- [ ] Implement; `set` prompts with `security -w` and no value on argv when the value is not piped; document the argv exposure in `--help`. Commit.

### Task F4: Test suites honest (ci#1–#11)

**Files:** `tests/audit-regressions.sh`, `bin/dotfiles-test`.

- [ ] Tests in `tests/ci.sh`: `t "F4.1" "S1.2 asserts behaviour, not exit 1 anywhere" '! grep -q "grep -q \"exit 1\" bin/dotfiles-secrets" tests/audit-regressions.sh'`; `t "F4.2" "S7.1 is specific" '! grep -q "TMPDIR|fnm_multishells" tests/audit-regressions.sh'`; `t "F4.3" "S3.2 checks real shallowness" 'grep -q "is-shallow-repository\|rev-list --count" tests/audit-regressions.sh'`; `t "F4.4" "no real keychain writes in audit-regressions" '! grep -q "secrets set __audit_rt" tests/audit-regressions.sh'`; `t "F4.5" "temp dirs cleaned" 'grep -q "finish\|trap" tests/audit-regressions.sh'`; `t "F4.6" "shellcheck tests skip when absent" 'grep -q "command -v shellcheck" tests/audit-regressions.sh'`; `t "F4.7" "startup threshold matches docs" 'grep -q "1000" bin/dotfiles-test && ! grep -q "2000" bin/dotfiles-test'`; `t "F4.8" "warn band does not count as pass" '! grep -B3 -A3 "1000" bin/dotfiles-test | grep -q "TESTS_PASSED++.*warn\|warn.*TESTS_PASSED"'`; `t "F4.9" "XDG_CACHE_HOME restored exactly" 'grep -q "_saved_xdg" bin/dotfiles-test || grep -q "unset XDG_CACHE_HOME" bin/dotfiles-test'`; `t "F4.10" "dotfiles test runs tests/run.sh" 'grep -q "tests/run.sh" bin/dotfiles-test'`. Convert `audit-regressions.sh` to source `tests/lib.sh`; move `S1.3b` into `tests/secrets.sh` (F3) against the throwaway keychain; update `SL.5`/`SL.6` once WS-E's statusline lands (coordinate: if `claude/statusline.sh` no longer contains `curl`, the UA and no-token tests are replaced by "no network access" from E3). Commit.

**WS-F final:** `bash tests/run.sh`, `./bin/dotfiles test --quick`, `bash .githooks/pre-commit` on a scratch staged change (use a sandbox repo: `git init`, copy the hook, stage a fake secret, expect exit 1). Report.

---

## Integration (lead, after wave 1)

1. `bash tests/run.sh` and `./bin/dotfiles test` (full, with timing) green; shellcheck over every bash file by shebang; `zsh -n` over every zsh file; a real `zsh -l -i -c 'exit'` timing before/after.
2. Apply cross-workstream requests: `sub_link` spicetify seed removal, `lastupdate` target, exit-code propagation from `install_claude.sh`, `launchctl bootstrap`, `SL.*` test updates.
3. Move the two gcloud `source` lines from `profiles/local.zsh` into `profiles/local.post.zsh` (lead only).
4. Verify no file under `~/.claude` changed: `find ~/.claude -newer docs/plans/2026-09-21-audit-remediation-plan.md -maxdepth 2 -type f` shows only session/transcript files.
5. GitHub: `gh api -X PATCH repos/STiXzoOR/dotfiles -f security_and_analysis[secret_scanning][status]=enabled -f security_and_analysis[secret_scanning_push_protection][status]=enabled -f security_and_analysis[dependabot_security_updates][status]=enabled` (approved by the user).
6. Hand the user the sudo-only steps: firewall/stealth/screen-lock (`dotfiles configure --defaults` or the three commands), `brew uninstall sudo-touchid` (safe: `sudo_local` persists), `brew untrust artginzburg/tap`.

## Wave 2 — mise migration

Planned in `docs/plans/2026-09-21-mise-migration-plan.md` once `research-mise.md` lands: install alongside fnm, `system/.mise` guarded with fnm fallback, shims on PATH for hooks, `npm.list` → `mise.toml` `npm:` tools, `bin/dotfiles` node install via `mise use -g node@lts`, then fnm removal and multishell cleanup as a separate, later commit.

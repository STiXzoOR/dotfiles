# New Mac follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Close everything left open after `2026-09-29-new-mac-readiness.md` shipped (main `5c8ffa2`): the CI hang, Tinycast as the launcher on new Macs, that plan's Task 9 (Jev in the sync and backup jobs), and the deferred review minors.

**Architecture:** Three lanes with disjoint file ownership, each lane serial inside itself. Lane A: Task 10 (CI), shipped first. Lane B: Task 11 (Tinycast), then Tasks 16 and 17 (minors). Lane C: Tasks 12–15 (Jev), after Task 10 is merged. Task 18 is in the private repo only.

**Spec:** the owner's decisions below, plus `2026-09-29-new-mac-readiness.md` (its Global Constraints and Task 8/9 text still bind). Research: `research-tinycast.md`, `research-jev.md`, `research-jev-prior-art.md` and `audit-perf.md` in the plan workspace's `research/` folder (gitignored, machine-local).

## Global Constraints

Every constraint in `2026-09-29-new-mac-readiness.md` § Global Constraints applies unchanged. The ones most often broken:

- **Read `AGENTS.md` first.** bash 3.2 only: no `mapfile`/`readarray`, no `declare -A`, no `declare -n`, no `${x,,}`/`${x^^}`, never `((x++))` under `set -e`.
- **GNU tools are interactive-only.** Scripts, hooks, launchd, CI and `xargs`/`find -exec` get the BSD tools. No `sed -i` without a suffix argument, no `grep -P`, no `find -printf`, no `stat -c`, no `readlink -f`, no `date --date`, no bare `timeout`.
- **GitHub's macOS runners ignore SIGPIPE.** A producer that never ends by itself (`tr … </dev/urandom`, `yes`, `cat /dev/zero`) piped into `head` never exits there. Bound every producer.
- **Public repo.** No names, hostnames, emails, computer names, private SSH host aliases, IP addresses or absolute `/Users/…` paths in tracked files. Examples use `example.invalid`, `my-mac`, `alice`.
- **Tests are hermetic.** Never touch the real `$HOME`, `/etc`, the login keychain, `defaults` domains, launchd, Homebrew or mise state. Use `tests/lib.sh` (`sandbox`, `code_of`, `t`, `section`, `finish`) and stub binaries on a sandbox PATH that log their argv. A grep assertion reads `code_of <file>`, never the raw file, and never `! <writer> | grep -q`. Mutation-check every new assertion.
- **TDD.** Failing test first, watch it fail for the right reason, then the minimal code.
- **Do not run** `dotfiles install|configure|link|unlink|update|clean|setup|sync|private`, `scripts/install_claude.sh`, `stow`, `launchctl`, `sudo`, `brew install|bundle|tap|trust|uninstall`, `mise install|use|lock` against the real machine.
- **Before every commit:** `bash tests/run.sh` and `DOTFILES_DIR=$PWD ./bin/dotfiles test` pass; `shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash <changed bash files>` is clean; `zsh -n` on changed zsh files. Do not push.
- **Shell traps (the Bash tool runs the owner's interactive zsh):** `noclobber` is on (overwrite with `>|`); `rm`/`cp`/`mv` are interactive aliases and `cat` is `bat` (use `command rm -f`, `command cp`, `command mv`, `command cat`); no word-splitting of unquoted vars; `nomatch` is on. Safety Net blocks `git checkout`, `git branch -D`, `git worktree remove --force` and `rm -rf` outside the working directory.
- **Docs:** each task updates the `docs/agents/*.md` pages and README passages that describe the behaviour it changes. Do not edit `docs/plans/archive/`.

## Owner decisions (2026-09-29, binding)

- Tackle every open item from the readiness handoff.
- **Tinycast on new Macs; this MacBook keeps Raycast.** New installs get Tinycast as the launcher, fully configured, and no Raycast. A Mac opts out per machine.
- `dotfiles vault migrate`: not now. Do not run it or change its behaviour.
- Apply the secrets async-load from `audit-perf.md` item 7 to the private `profiles/local.zsh` (Task 18).
- Unchanged from the readiness plan: every Jev point starts in `shadow` mode; ask per item before any auth/lock/firewall/sudo behaviour change on a real machine.

---

### Task 10: CI hang and test-runner hardening

**Why:** CI's "Run Tests" job has timed out at 30 minutes on every run since Task 8 (runs on `3aedb76` and `5c8ffa2`), which GitHub shows as "cancelled". Root cause, reproduced: `tests/apps.sh` K1 builds a token with `LC_ALL=C tr -dc "A-Za-z0-9" </dev/urandom | head -c 36`. GitHub's macOS runner ignores SIGPIPE, so after `head` exits the BSD `/usr/bin/tr` gets EPIPE forever and never exits. Repro: `/bin/bash -c "trap '' PIPE; LC_ALL=C /usr/bin/tr -dc A-Za-z0-9 </dev/urandom | /usr/bin/head -c 36"` hangs. The same pattern is at `tests/jev.sh:25` (`rand()`) and `tests/fixtures/make-secrets.sh:12`.

**Owns:** `tests/lib.sh`, `tests/run.sh`, `tests/apps.sh` (K1 line only), `tests/jev.sh` (`rand()` only), `tests/fixtures/make-secrets.sh`, `.github/workflows/ci.yml` (only if needed), `docs/agents/testing-and-ci.md`.

- [ ] **10.1** A bounded random-string helper in `tests/lib.sh` (e.g. `rand_chars <n> <tr-charset>`): reads a bounded chunk (`head -c 4096 /dev/urandom`), filters with `LC_ALL=C tr -dc`, loops until it has `n` characters, prints exactly `n`. It must terminate with SIGPIPE ignored. Replace the three unbounded pipelines with it (make-secrets.sh may keep its own copy if it cannot source lib.sh; same bounded shape).
- [ ] **10.2** `tests/run.sh` mirrors the runner: run each suite with SIGPIPE ignored (`trap '' PIPE` before the loop, so a local run catches this class of hang) and under a per-suite time limit through the `timeout` shim in `tests/lib.sh` (default 600 s, `TEST_SUITE_TIMEOUT` overrides). A suite that times out is reported by name as failed and the next suite still runs. Test: a fixture suite that hangs under ignored SIGPIPE is killed and named; a normal suite still passes.
- [ ] **10.3** A guard test (in whichever suite owns repo-wide lint assertions, or `tests/run.sh`'s own test) that fails if any tracked `*.sh` under `tests/`, `bin/`, `scripts/` reads `/dev/urandom`, `/dev/zero` or runs `yes` without a bound in the same pipeline stage. Use `code_of`. Report any hits in production code (`bin/`, `scripts/`) — fix them the same way.
- [ ] **10.4** Every suite passes locally with SIGPIPE ignored: `/bin/bash -c "trap '' PIPE; bash tests/run.sh"`, and `DOTFILES_DIR=$PWD ./bin/dotfiles test`.
- [ ] **10.5** `docs/agents/testing-and-ci.md`: the SIGPIPE trap and the per-suite limit, one short paragraph.

### Task 11: Tinycast as the launcher on new Macs

**Owner decision:** new Macs get Tinycast (abue-ammar/tinycast, bundle id `com.tinycast.app`) as the launcher, set up "all the way"; a Mac can keep Raycast. Read `research/research-tinycast.md` first (install, config-as-code, hotkey, risks). Verify every Tinycast key and default name against the upstream docs (`docs/features/settings-file.md`, `hotkeys.md`, `backup.md`, `raycast-import.md` in github.com/abue-ammar/tinycast) before using it; the research marks the hotkey format as unstable.

**Owns:** `Brewfile`, `macos/local.sh.example`, a new per-Mac file example (see 11.1), `scripts/lib/machine.sh` (new helper only), `bin/dotfiles` (`sub_install_packages` and the launcher step it calls; nothing else), `macos/defaults.sh` (launcher block only), `config/tinycast/` (new), `.gitignore`, `tests/packages.sh`, `tests/macos.sh`, a new `tests/launcher.sh` if cleaner, `bin/dotfiles-test` (only assertions this invalidates), `README.md`, `docs/agents/new-mac.md`, `docs/agents/macos-defaults.md`, `docs/agents/packages.md`, `docs/agents/two-mac-sync.md` (the app-sync row).

- [ ] **11.1 Choosing the launcher per Mac.** `macos/local.sh` is shared by both Macs through the private repo, so it cannot hold a per-Mac choice. Add a per-Mac, never-synced file `macos/machine.local.sh` (gitignored in this repo and never linked from the private repo; `macos/machine.local.sh.example` documents it). New helper `dotfiles_launcher` in `scripts/lib/machine.sh` prints `tinycast` or `raycast`: `DOTFILES_LAUNCHER` from the environment, else from `macos/machine.local.sh`, else from `macos/local.sh`, else `tinycast`. Any other value warns once and falls back to `tinycast`. BSD-only tools; no side effects on load.
- [ ] **11.2 Packages.** The Brewfile installs exactly one launcher. `bin/dotfiles` exports the resolved `DOTFILES_LAUNCHER` into `brew bundle`'s environment; the Brewfile (Ruby) picks `cask "raycast"` or the Tinycast tap + `cask "abue-ammar/tinycast/tinycast"` from `ENV`, defaulting to Tinycast when unset (so CI's `brew bundle list` and a bare `brew bundle` still work). The Tinycast tap must be tapped and trusted by the existing trust loop in `sub_install_packages` only when Tinycast is the launcher (the Brewfile's header rule: never trust a tap the Brewfile does not need). Tests with stub `brew`: the tap is trusted and the cask bundled for `tinycast`; neither for `raycast`; `raycast` bundles the Raycast cask.
- [ ] **11.3 Settings as code.** Add `config/tinycast/settings.json` (stowed to `~/.config/tinycast/settings.json`; the app follows and keeps symlinks). Strict JSON, only keys confirmed in upstream docs, public-safe, and minimal: launch at login if it is a settings-file key, clipboard history on, the window-management bindings only if the owner's Raycast set is known (otherwise leave them out). If the settings-file mirror can be switched on without the GUI (a `defaults` key documented upstream), `configure` switches it on; otherwise `docs/agents/new-mac.md` gives the one-time GUI step. Stowing `config/tinycast` on a Raycast Mac is harmless (the file is inert there); say so in a comment.
- [ ] **11.4 Cmd-Space.** When the launcher is `tinycast`, the launcher block in `macos/defaults.sh` sets Tinycast's summon hotkey to Cmd-Space via `defaults write com.tinycast.app hotkey.togglePalette …` with the value format verified against upstream (research guess: `{"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}`), only while Tinycast is not running (quit it first with `osascript -e 'quit app "Tinycast"'` or skip with a clear message), then reads it back; a mismatch is reported, not ignored. Spotlight's Cmd-Space stays disabled (existing symbolichotkeys 64/65 block). When Raycast.app is present on a `tinycast` Mac, print one warning that Raycast still claims Cmd-Space and the exact command to remove it (`brew uninstall --cask raycast`); never uninstall it. When the launcher is `raycast`, keep today's behaviour and message. Tests with stub `defaults`/`osascript`/`pgrep`.
- [ ] **11.5 Docs.** `docs/agents/new-mac.md`: replace step 7 (Raycast hotkey before `install --all`) with the Tinycast path (nothing to do before `install --all`; afterwards grant Accessibility, enable the settings file if 11.3 could not, export `.rayconfig` on the old Mac and use Tinycast's Import from Raycast, test the OAuth extensions GitHub/Linear/Slack/Zoom), plus how a Mac keeps Raycast (`DOTFILES_LAUNCHER=raycast` in `macos/machine.local.sh`) and how a Mac that already has Raycast switches. `docs/agents/macos-defaults.md` (launcher block), `docs/agents/packages.md` (the conditional cask and its tap), `docs/agents/two-mac-sync.md` (Tinycast has no cloud sync; settings travel through this repo), `README.md` app list. Record Tinycast's risks in two lines (young, one maintainer, self-signed while its Developer ID move completes).
- [ ] **11.6 Blender** (owner action from the readiness handoff, same file): add `cask "blender"` to the Brewfile (the `blender` MCP needs Blender 5.1+); `docs/agents/claude-bootstrap.md` or `new-mac.md` notes the manual add-on step (Blender's official MCP add-on v1.0.3 from projects.blender.org). Check the cask name with `brew info --cask blender` (read-only).

### Task 12: Jev — private-repo secrets hook, scheduled vault scan, Task 8 and Task 7 leftovers

**Starts after Task 10 is merged.** This is readiness-plan item 9.x plus the minors deferred to Task 9. Read `2026-09-29-new-mac-readiness.md` § Task 8 and § Task 9 for the design, `docs/agents/jev.md` for what exists, and `research/research-jev.md` for the API.

**Owns:** `bin/dotfiles-private`, `bin/dotfiles-sync`, `bin/dotfiles-jev`, `scripts/lib/jev.sh`, `tests/jev.sh`, `tests/private.sh`, `tests/sync.sh`, `docs/agents/jev.md`, `docs/agents/two-mac-sync.md`.

- [ ] **12.1 Private repo pre-commit.** `dotfiles private` installs the secrets guard (8.4 layers: gitleaks, high-entropy check, own-secret exact match) as the private repo's pre-commit hook: block plaintext secrets; only `secrets.age` may hold them. Idempotent; never overwrites a different existing hook without backing it up. Tests on a sandbox private repo.
- [ ] **12.2 Scheduled vault scan.** `dotfiles sync --scheduled` runs `dotfiles jev scan-vault` once a day and notifies on hits (file and line only, never the value). Report-only, as in 8.4 (d).
- [ ] **12.3 Task 8 leftovers.** (a) The own-secret check warns on "item not found" (a fresh Mac with no Keychain items yet): treat a missing item as "nothing to compare", silent, and keep the warning for real Keychain failures with wording that says which. (b) Structural lines of multi-line secrets (PEM `-----BEGIN …-----`/`-----END …-----` headers and similar ≥8-char fixed lines) must not become own-secret patterns. (c) The converted-plist temp file gets trap cleanup. (d) Plist `<data>` base64 values are decoded (or matched in base64 form) by the own-secret check. (e) A spaces-only computer name is a deterministic privacy block again. (f) Secrets are loaded once per run, not once per request (pipeline subshell). (g) No shadow job is spawned on a commit when there is no key. (h) The log stores the derived confidence, not only the raw answer. (i) `plutil`-dependent tests skip visibly when `plutil` is absent.
- [ ] **12.4 Task 7 leftovers in `bin/dotfiles-private`.** The exit-3 "not set up yet" skip also swallows network, typo and host-key-changed failures: keep git's stderr and treat only `Repository not found` / `Permission denied (publickey)` as "not set up"; everything else fails loudly. BatchMode on the private clone turns passphrase-only keys into a skip: detect and say so. Fix the stale comments at `docs/agents/two-mac-sync.md` (~line 200) and `bin/dotfiles` (~line 687, comment only).

### Task 13: Jev — drift that notices itself (readiness item 8.2)

Readiness-plan § Task 9 item 8.2 is the spec, verbatim. Shadow mode by default; nothing is written or committed without the owner's `confirm`; a `remove` suggestion needs two agreeing calls; facts computed in shell; one batched request per kind.

**Owns:** `bin/dotfiles-sync` (drift classification path), `scripts/lib/jev.sh` (additions), `tests/jev.sh`, `tests/sync.sh`, `tests/fixtures/jev/` (fake answers, replay cases), `docs/agents/jev.md`.

### Task 14: Jev — app-backup suggestions (readiness item 8.5) and Task 6 leftovers

Readiness-plan § Task 9 item 8.5 is the spec, verbatim. The owner's "no" is remembered in the private repo so the app is not asked again.

Plus the Task 6 minors: `processes.list` holds one process per app (helper processes are not covered); the scheduled log is unbounded (rotate or cap it); a stale-lock race; the cfprefsd caching lag is documented in `docs/agents/app-settings.md`.

**Owns:** `bin/dotfiles-apps`, `bin/dotfiles-sync` (the app-suggestion call site only), `scripts/lib/jev.sh` (additions), `tests/apps.sh`, `tests/jev.sh`, `tests/fixtures/jev/`, `docs/agents/app-settings.md`, `docs/agents/jev.md`.

### Task 15: Jev — skip gate for the daily jobs (readiness item 8.6) and replay cases and docs (9.y)

Readiness-plan § Task 9 items 8.6 and 9.y are the spec, verbatim: skip only when P(useful) < 0.2, never more than 3 skips in a row, never when a deterministic fact says work exists; log every decision. Replay cases for the drift, app-choice and skip points (synthetic, public-safe) and the `docs/agents/jev.md` sections for all three points.

**Owns:** `bin/dotfiles-sync` and `bin/dotfiles-apps` (the `--scheduled` entry only), `scripts/lib/jev.sh`, `bin/dotfiles-jev` (replay for the new points), `tests/jev.sh`, `tests/fixtures/jev/replay/`, `docs/agents/jev.md`.

### Task 16: Deferred minors — install, Claude/Codex, packages, stow, CI

**Starts after Task 11 is merged** (shares `bin/dotfiles`). Each item came from a task review of the readiness plan; some may have been fixed by the later fix waves. Check each against the current code first; fix what is still real with a test; list the already-fixed ones in the report with the line that fixes them.

**Owns:** `remote-install.sh`, `scripts/clt.sh` (or wherever the CLT install lives), `bin/dotfiles` (`sub_install_packages` tap loop only), `scripts/install_claude.sh`, `scripts/install_codex.sh`, `scripts/lib/fs.sh`, `tests/install*.sh`, `tests/claude*.sh`, `tests/codex.sh`, `tests/packages.sh`, `tests/link*.sh` or wherever stow is tested, `docs/agents/testing-and-ci.md`, `docs/agents/claude-bootstrap.md`.

- [ ] Task 1 minors: no sudo keep-alive in `remote-install`/CLT install (a long CLT install can outlast the sudo timestamp); no trap to remove the CLT sentinel on SIGINT; `brew tap` inside `while read` without `</dev/null`; tests using bare GNU `timeout` (use the shim); a `beta 3` label suffix would parse as version 3.
- [ ] Task 2 minors: M1 test helpers `_run`/`_full_run` do not unset `CODEX_HOME`/`CLAUDE_CONFIG_DIR` (a real-dir risk if the owner exports them); M2 a missing binary is counted twice as a failure; M3 a dangling skill symlink is treated as installed (use `-L && -e`); M4 the skills list is split without `set -f`; M5 the marketplace guard matches substrings; M6 unpinned `npx skills`; M7 `testing-and-ci.md` does not list `tests/codex.sh`.
- [ ] **Safety-net rename** (owner action from the handoff): after `install --claude` installs `cc-safety-net`, a stale `safety-net@cc-marketplace` from before the rename is uninstalled by the installer (only when the new one installed successfully; logged; tested with a stub `claude`).
- [ ] Task 4 test minor: `tests/packages.sh:74` greps the GitHub handle literal; derive it instead.
- [ ] Stow minors: the ignore regex should be `^\.DS_Store$`; add a nested-rollback test; a trap so a crash mid-link rolls back.

### Task 17: Deferred minors — shell and macOS

**Starts after Task 11 is merged** (shares `macos/defaults.sh` and `tests/macos.sh`). Same rule: verify each is still real before fixing.

**Owns:** `runcom/` (`.zlogin`, the cache writers), `system/`, `macos/defaults.sh` (outside the launcher block), `config/vscode/` (keybindings), `tests/macos.sh`, `tests/shell*.sh`, `tests/perf*.sh`, `docs/agents/shell-config.md`, `docs/agents/macos-defaults.md`. These files are live: after each edit run `zsh -n <file>` and `zsh -l -i -c 'exit'` from the worktree copy (do not stow).

- [ ] Task 3 minors: (1) atuin/starship/pay-respects caches written in place with `>|` — write a temp and `mv -f`; (2) `.zlogin` `(#qN.mh+8)` depends on Prezto's `EXTENDED_GLOB` — add `setopt localoptions extendedglob`; (3) no lock on concurrent background compdump rebuilds; (4) P8.2 fixed sleep, P6.1 reads the real `/etc/ssh/ssh_known_hosts`; (5) `shell-config.md` table pipes; (6) an empty `PROMPT2` is cached if continuation fails.
- [ ] Task 4 minors: the firewall read-back `grep 'State = 1'` misreads block-all (`State = 2`); a firewall failure has no tally/non-zero status; M4.7/M4.9/M4.10 weak checks (working tree vs `git ls-files`, `check-ignore` error); `keybindings.json` has no trailing newline; G3.5 counts error lines.

### Task 18: Private — secrets async-load (owner-approved)

**Private repo only** (`~/.dotfiles-private`, `profiles/local.zsh` and `profiles/local.post.zsh`). Apply `research/audit-perf.md` § 2 item 7 ("Secrets: direct `security` calls, collected asynchronously"): start the Keychain lookups in `local.zsh`, collect them at the end of `.zshrc` in `local.post.zsh`, keep the inheritance guard, export an empty value for a missing secret as today, and clean up the fd, helper function and temporaries. Measure before and after (`zsh -l -i -c exit`, cold and warm, 10 runs, min). Verify each secret variable is still exported in a new login shell, and that `zsh -c` from launchd-like environments still gets them. `zsh -n` both files. Commit in the private repo; do not push.

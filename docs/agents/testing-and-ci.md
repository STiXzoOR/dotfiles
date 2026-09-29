# Testing & CI

## Two suites

**`./bin/dotfiles test`** is the configuration suite: it checks that the shell
config, caches, functions, aliases, XDG variables, file structure and Prezto
setup are what they should be.

```bash
./bin/dotfiles test              # Everything
./bin/dotfiles test --verbose    # Detailed output
./bin/dotfiles test --quick      # Skip the slow startup-timing tests
```

**`bash tests/run.sh`** is the regression suite. It runs every `tests/*.sh`
except `lib.sh` and itself, prints a per-file summary, and exits non-zero if
any suite failed. Arguments are passed through to each suite.

| File                       | Covers                                                        |
| -------------------------- | ------------------------------------------------------------- |
| `tests/lib.sh`             | The shared harness: `t`, `section`, `code_of`, `sandbox`, `finish` |
| `tests/run.sh`             | The runner                                                     |
| `tests/audit-regressions.sh` | Every regression the earlier audits found, by id (S2.*, S5.*, CB.*, SL.*, S7.*) |
| `tests/repo.sh`            | Repository hygiene — gitignore, submodules, attributes         |
| `tests/cli.sh`             | `bin/dotfiles`, the install helpers, the install flow (see below) |
| `tests/macos.sh`           | `macos/`, the defaults baseline, LaunchAgents                  |
| `tests/shell.sh`           | `runcom/`, `system/`, `profiles/`, completions                 |
| `tests/packages.sh`        | `Brewfile`, `packages/`, `config/`                             |
| `tests/claude.sh`          | The Claude Code bootstrap, hooks, status line, rules and docs  |
| `tests/ci.sh`              | The workflows and git hooks                                    |
| `tests/secrets.sh`         | `bin/dotfiles-secrets`                                         |
| `tests/sync.sh`            | `scripts/lib/machine.sh`, `bin/dotfiles-sync`, `bin/dotfiles-vault`, the sync LaunchAgent (`SYNC_ONLY="S V"` runs a subset) |
| `tests/private.sh`         | `bin/dotfiles-private` (sandbox repos and a bare remote)       |

Read `tests/audit-regressions.sh` **before** editing `claude/statusline.sh`,
`claude/settings.template.json` or anything under `claude/hooks/`. It encodes
the intent behind those files better than any prose here, and its test ids are
what a reviewer will quote back.

## Writing a test

Every suite sources `tests/lib.sh` and calls `t <id> <description> <expression>`.
The expression is single-quoted, because `t` hands it to `eval` and it must not
expand where it is written — which is why each file carries
`# shellcheck disable=SC2016`.

Two traps the harness documents and that have already bitten:

- `pipefail` is on. Never put `grep -q` on the right of a pipe fed by a chatty
  command: `grep -q` exits on the first match, the writer dies of `SIGPIPE`, the
  pipeline reports non-zero, and a leading `!` turns that into a false pass.
  Capture the output first, or use `grep -c` and compare.
- `eval` runs in the suite's own shell, so a bare `exit 1` inside a loop in an
  assertion aborts the whole run. Wrap such loops in a subshell.

Tests must be side-effect free on the real machine: no writes under `$HOME`
except through `sandbox`, no keychain, no network.

### Install-flow tests (`tests/cli.sh`, sections N1-N11)

These run the real code against stub binaries on a sandbox `PATH`, in a sandbox
`HOME`, and assert on argv, exit status and output. Patterns to reuse:

- **Function under test extracted with `sed -n "/^name()/,/^}/p"`** and sourced
  into a small runner script, as the older sections do. `fn_of` and `stub` (N0)
  wrap this.
- **Orchestration tests copy `bin/dotfiles` into a sandbox repo** and splice stub
  step functions in just before the `# Routing.` marker, so `$0 install --prezto`
  re-executes the copy and reaches the stub. Steps log their name, which gives the
  order assertions (N4).
- **Command Line Tools** (N2, N3, N11): stub `xcode-select`, `softwareupdate` and
  `sudo` (which logs, then runs the rest of argv, so the sentinel `touch` and `rm`
  hit a sandbox path through `DOTFILES_CLT_SENTINEL`). `remote-install.sh` is run
  under `env -i` with a stub `curl` that serves this repo's own `clt.sh`.
- **Seams**, all defaulting to production values: `DOTFILES_CLT_SENTINEL`,
  `DOTFILES_CLT_RETRY_SLEEP`, `DOTFILES_HOSTS_FILE` (the hosts file the backup and
  write act on) and `DOTFILES_CODE_BIN_FALLBACK` (the VS Code CLI used when `code`
  is not on `PATH`). Any test that reaches the packages step must set the last
  one or stub `code`, otherwise it would launch the real editor.

Mutation-check each assertion: break the code it guards, watch the test fail,
restore.

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on push and pull request:

1. Bash and zsh syntax validation
2. Shellcheck, over **every** file with a bash shebang, discovered dynamically.
   That is why `claude/statusline.sh` and `claude/hooks/*.sh` are covered
   without being listed anywhere
3. The `dotfiles test` suite
4. The `tests/run.sh` regression suites
5. Brewfile validation

## Git Hooks

Install with `./bin/dotfiles hooks`. Pre-commit runs bash and zsh syntax
validation, shellcheck, and a credential scan with gitleaks (falling back to
built-in patterns when gitleaks is absent).

## Shellcheck

Every shell script must pass:

```bash
shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash <file>
```

Use an inline `# shellcheck disable=SC####` with a justification for anything
else.

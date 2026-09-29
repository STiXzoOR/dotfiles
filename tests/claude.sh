#!/usr/bin/env bash
# tests/claude.sh -- regression tests for the 2026-09-21 audit, Claude/docs workstream.
#
# Covers the Claude Code bootstrap (scripts/install_claude.sh), the hooks and
# statusline shipped in claude/, the rules, `bin/dotfiles-claude`, and the
# agent-facing documentation.
#
# shellcheck disable=SC2016,SC2030,SC2031,SC2088
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

section "E1 — hooks"
t "E1.1" "repo hook has the single-instance lock"        'grep -q "mkdir" claude/hooks/index-sessions.sh && grep -qi "lock" claude/hooks/index-sessions.sh'
t "E1.2" "repo hook resolves gtimeout by absolute path"  'grep -qE "gtimeout|coreutils/libexec/gnubin/timeout" claude/hooks/index-sessions.sh'
t "E1.3" "repo hook finds qmd without an interactive shell" 'grep -qE "fnm env|mise|local/bin/qmd|\.local/share/mise/shims" claude/hooks/index-sessions.sh'
t "E1.4" "session-start reads Polaris/top-of-mind.md"    'grep -q "Polaris/top-of-mind.md" claude/hooks/session-start.sh'
t "E1.5" "installer backs up before overwriting hooks"   'grep -qE "\.bak|backup" scripts/install_claude.sh && ! grep -qE "^\s*cp \"\\\$file\" \"\\\$dest_dir/\\\$name\"$" scripts/install_claude.sh'
t "E1.6" "index hook wired to SessionEnd, not Stop"      'jq -e ".hooks.SessionEnd" claude/settings.template.json >/dev/null && [ "$(jq -r ".hooks.Stop[]?.hooks[]?.command" claude/settings.template.json | grep -c index-sessions)" -eq 0 ]'
t "E1.7" "hook comment states its output enters model context" 'grep -qi "context" claude/hooks/session-start.sh'

section "E2 — bootstrap"
t "E2.1" "sessions collection targets the vault"      'grep -q "VAULT_DIR/Claude-Sessions" scripts/install_claude.sh && ! grep -q "sessions_dir=\"\$HOME/.claude/projects\"" scripts/install_claude.sh'
t "E2.2" "settings check finds a dangling path"       '
  W=$(sandbox); printf "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"bash %s/nonexistent.sh\"}]}]}}" "$W" > "$W/settings.json"
  ! (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'
t "E2.3" "settings check passes on a good file"       '
  W=$(sandbox); touch "$W/ok.sh"; printf "{\"statusLine\":{\"command\":\"bash %s/ok.sh\"}}" "$W" > "$W/settings.json"
  (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'

# A hook command is a shell command line, so a path with a space in it is
# quoted. Tokenising on whitespace alone splits
# "/Users/x/Library/Application Support/..." into a first half that looks
# exactly like an absolute path and does not exist, so verify reported a
# missing file that was present all along -- and a real dangling path could
# hide in the noise. Quoted runs have to be taken whole.
t "E2.3a" "a quoted path containing a space is not reported missing" '
  W=$(sandbox); mkdir -p "$W/Application Support/tool"
  printf "#!/bin/sh\nexit 0\n" > "$W/Application Support/tool/hook.sh"
  chmod +x "$W/Application Support/tool/hook.sh"
  printf "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"command\":\"%s\"}]}]}}" \
    "'"'"'$W/Application Support/tool/hook.sh'"'"' Idle" > "$W/settings.json"
  (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'

t "E2.3b" "a genuinely dangling quoted path is still reported" '
  W=$(sandbox); mkdir -p "$W/Application Support"
  printf "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"command\":\"%s\"}]}]}}" \
    "'"'"'$W/Application Support/tool/absent.sh'"'"' Idle" > "$W/settings.json"
  ! (source scripts/install_claude.sh --lib 2>/dev/null; verify_settings_refs "$W/settings.json")'
# Per-event merge, per the lead ruling: a template event overrides the
# same-named existing event, and an existing event the template does not
# mention survives. Replacing .hooks wholesale deleted four of the eight live
# hook events on this machine.
t "E2.4" "merge overrides hook events by name and keeps the rest" '
  W=$(sandbox)
  printf "{\"hooks\":{\"PreToolUse\":[{\"keep\":1}],\"Stop\":[{\"old\":1}]},\"model\":\"keep-me\"}" > "$W/existing.json"
  printf "{\"hooks\":{\"Stop\":[{\"new\":2}],\"SessionEnd\":[{\"added\":3}]},\"model\":\"template\"}" > "$W/template.json"
  (source scripts/install_claude.sh --lib 2>/dev/null; merge_settings_files "$W/template.json" "$W/existing.json" > "$W/out.json")
  [ "$(jq -r .model "$W/out.json")" = keep-me ] &&
  [ "$(jq -r ".hooks.PreToolUse[0].keep" "$W/out.json")" = 1 ] &&
  [ "$(jq -r ".hooks.Stop[0].new" "$W/out.json")" = 2 ] &&
  [ "$(jq -r ".hooks.Stop[0].old" "$W/out.json")" = null ] &&
  [ "$(jq -r ".hooks.SessionEnd[0].added" "$W/out.json")" = 3 ]'
t "E2.5" "bootstrap exits non-zero when a step failed" 'grep -qE "return 1|exit 1" scripts/install_claude.sh && grep -q "FAILURES" scripts/install_claude.sh'
t "E2.6" "hook paths are not hardcoded to ~/.claude/skills" '! grep -q "\.claude/skills/recall" claude/settings.template.json'
t "E2.7" "qmd package name is scoped"                 '! grep -q "add .qmd. to packages" scripts/install_claude.sh && grep -q "@tobilu/qmd" scripts/install_claude.sh'
t "E2.8" "plugins.list marketplace ids match marketplaces.list names" '(for m in $(grep -v "^#" claude/plugins.list | grep -v "^$" | sed "s/.*@//" | sort -u); do grep -q "$m" claude/marketplaces.list || exit 1; done)'
t "E2.9" "install script has a --lib mode for tests" 'grep -q -- "--lib" scripts/install_claude.sh'
t "E2.10" "channel pinned to stable with a version floor" 'jq -e ".autoUpdatesChannel == \"stable\" and (.minimumVersion|type) == \"string\"" claude/settings.template.json >/dev/null'
t "E2.11" "binary is verified against the signed manifest" 'grep -q "manifest.json.sig" scripts/install_claude.sh && grep -q "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" scripts/install_claude.sh'

# main() used to call install_claude_binary, merge_settings and
# verify_settings_refs bare, so the return values those functions were rewritten
# to produce went straight in the bin and the bootstrap still exited 0.
# Every step is stubbed here, so nothing reaches the network, the CLI or $HOME.
_main_with_failing() { # _main_with_failing <function-to-fail>
  local failing="$1" w="$2" f
  (
    # A step added to main() but forgotten in the stub list below would run for
    # real; a sandbox HOME keeps that from ever touching the owner's machine.
    export HOME="$w/home"; mkdir -p "$HOME"
    source scripts/install_claude.sh --lib 2>/dev/null
    CLAUDE_INSTALL_LOG="$w/log"
    for f in install_claude_binary verify_claude_install register_marketplaces \
      install_plugins register_mcp_servers install_skills copy_claude_files link_rule_imports install_statusline \
      setup_recall_venv merge_settings verify_settings_refs setup_vault setup_qmd; do
      eval "$f() { :; }"
    done
    eval "$failing() { return 1; }"
    main
  )
}
t "E2.12" "a failed settings merge makes the bootstrap exit non-zero" 'W=$(sandbox); ! _main_with_failing merge_settings "$W"'
t "E2.13" "a dangling settings reference makes the bootstrap exit non-zero" 'W=$(sandbox); ! _main_with_failing verify_settings_refs "$W"'
t "E2.14" "a failed binary install makes the bootstrap exit non-zero" 'W=$(sandbox); ! _main_with_failing install_claude_binary "$W"'
# A sentinel no step calls: passing ":" here would override the shell builtin
# every stub above is built from, and fail the whole run.
t "E2.16" "the template documents the per-event hooks merge" 'out=$(jq -r ".\"\$comment\"[]" claude/settings.template.json); echo "$out" | grep -qi "per event"'
t "E2.15" "the bootstrap still exits 0 when every step succeeds" 'W=$(sandbox); _main_with_failing _no_such_step "$W"'

section "E3 — statusline reads stdin only"
fixture='{"model":{"display_name":"Opus"},"cwd":"/tmp","workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":1.5,"total_duration_ms":65000},"context_window":{"context_window_size":200000,"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":12}},"effort":"high"}'
t "E3.1" "renders model, context and limits from stdin" 'out=$(printf "%s" "$fixture" | PATH=/usr/bin:/bin bash claude/statusline.sh); echo "$out" | grep -q Opus && echo "$out" | grep -q "42" && echo "$out" | grep -q "31"'
t "E3.2" "no keychain, credentials or network access" '[ "$(code_of claude/statusline.sh | grep -cE "security find-generic-password|credentials.json|curl|api.anthropic.com|oauth")" -eq 0 ]'
t "E3.3" "renders without rate_limits"                'printf "{\"model\":{\"display_name\":\"X\"}}" | bash claude/statusline.sh | grep -q X'
t "E3.4" "no git status walk per refresh"             '[ "$(code_of claude/statusline.sh | grep -c "status --porcelain")" -eq 0 ]'
t "E3.5" "at most 3 jq invocations"                   '[ "$(code_of claude/statusline.sh | grep -c "jq ")" -le 3 ]'
t "E3.6" "shellcheck clean"                           'shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 -s bash claude/statusline.sh'

section "E4 — rules and the drift check"
t "E4.1" "vault-lookback names real qmd tools" '! grep -qE "qmd_search|qmd_vector_search|qmd_deep_search" claude/rules/vault-lookback.md && grep -q "multi_get" claude/rules/vault-lookback.md'
t "E4.2" "gnu-tools rule carries the non-interactive caveat" 'grep -qi "xargs" claude/rules/gnu-tools.md'
t "E4.3" "no cursor frontmatter" '! grep -rq "alwaysApply" claude/rules'
t "E4.4" "dotfiles-claude diff detects drift" 'W=$(sandbox); mkdir -p "$W/.claude/hooks"; printf "x\n" > "$W/.claude/hooks/index-sessions.sh"; ! HOME="$W" bash bin/dotfiles-claude diff >/dev/null 2>&1'
t "E4.5" "dotfiles-claude diff passes when identical" 'W=$(sandbox); mkdir -p "$W/.claude/hooks" "$W/.claude/rules"; cp claude/hooks/* "$W/.claude/hooks/"; cp claude/rules/* "$W/.claude/rules/"; cp claude/statusline.sh "$W/.claude/"; HOME="$W" bash bin/dotfiles-claude diff'
t "E4.6" "dotfiles-claude never writes under the home it inspects" '[ "$(code_of bin/dotfiles-claude | grep -cE "(^|[^a-z-])(cp|mv|rm|install_file|mkdir|touch|tee) .*HOME")" -eq 0 ]'
# `dotfiles claude verify` is documented read-only in four places. The dry-run
# resolver fell through to `eval "$(fnm env)"`, which materialises a multishell
# directory under ~/.local/runtime -- the very directories this repo ships a
# pruner for.
t "E4.8" "the hook dry run never executes fnm" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/home"
  printf "#!/bin/sh\ntouch \"%s/fnm-ran\"\n" "$W" > "$W/bin/fnm"; chmod +x "$W/bin/fnm"
  HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" CLAUDE_HOOK_DRY_RUN=1 \
    bash claude/hooks/index-sessions.sh >/dev/null 2>&1
  [ ! -e "$W/fnm-ran" ]'
t "E4.9" "the hook dry run still reports what it resolved" '
  W=$(sandbox); mkdir -p "$W/bin" "$W/home"
  printf "#!/bin/sh\ntouch \"%s/fnm-ran\"\n" "$W" > "$W/bin/fnm"; chmod +x "$W/bin/fnm"
  out=$(HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" CLAUDE_HOOK_DRY_RUN=1 \
    bash claude/hooks/index-sessions.sh 2>&1)
  [ "$(printf "%s" "$out" | grep -c "index-sessions: timeout=")" -eq 1 ] &&
  [ "$(printf "%s" "$out" | grep -c "qmd=")" -eq 1 ]'
t "E4.7" "installer imports the rules into CLAUDE.md idempotently" 'grep -q "link_rule_imports" scripts/install_claude.sh && [ "$(code_of scripts/install_claude.sh | sed -n "/link_rule_imports()/,/^}/p" | grep -c "claude/rules")" -ge 1 ]'

section "E5 — docs"
t "E5.1" "architecture.md lists no dead package lists" '! grep -qE "brew.list|cask.list|mas.list|tap.list" docs/agents/architecture.md'
t "E5.2" "shell-config.md has no .fix" '! grep -q "\.fix" docs/agents/shell-config.md'
t "E5.3" "README does not claim Starship" '! grep -qi "uses Starship" README.md'
t "E5.4" "README mentions install --claude" 'grep -q "install --claude" README.md'
t "E5.5" "AGENTS.md states bash 3.2 and public repo" 'grep -q "3.2" AGENTS.md && grep -qi "public" AGENTS.md'
t "E5.6" "AGENTS.md names audit-regressions and a do-not-run list" 'grep -q "audit-regressions" AGENTS.md && grep -qi "do not run\|never run" AGENTS.md'
t "E5.7" "old plans archived" '[ ! -e docs/plans/2026-03-03-claude-bootstrap-plan.md ] && [ "$(ls docs/plans/archive/ | grep -c 2026-03-03)" -ge 1 ]'
t "E5.8" "commands.md matches dotfiles help" '(for c in clean edit open profiler secrets setup cheatsheet baseline claude; do grep -q "$c" docs/agents/commands.md || exit 1; done)'
t "E5.9" "worktreeinclude exists" '[ -f .worktreeinclude ]'
t "E5.10" "testing-and-ci.md documents the per-workstream suites" 'grep -q "tests/run.sh" docs/agents/testing-and-ci.md && grep -q "audit-regressions" docs/agents/testing-and-ci.md'
t "E5.12" "shell-config.md does not name the replaced thefuck file" '! grep -q "\.thefuck" docs/agents/shell-config.md'
t "E5.11" "archived plans carry a superseded banner" '(for f in docs/plans/archive/*.md; do head -3 "$f" | grep -qi "superseded" || exit 1; done)'

# ─── New-Mac readiness: install_claude.sh against stub binaries ──────────────
#
# Every run below uses a sandbox HOME and a PATH of stubs that log their argv
# to $STUBLOG. Nothing reaches the real machine: the real `claude` is never
# on PATH (a stub installer drops the stub into $HOME/.local/bin, exactly as
# the native installer does), and jq is the only real tool linked in.
_stubs() { # _stubs <W>
  local w="$1" n
  mkdir -p "$w/bin" "$w/home"; : >| "$w/log"
  ln -s "$(command -v jq)" "$w/bin/jq"
  for n in qmd npx; do
    printf '#!/bin/sh\necho "%s $*" >> "$STUBLOG"\n[ -n "${STUB_FAIL_%s:-}" ] && exit 1\nexit 0\n' "$n" "$n" >| "$w/bin/$n"
    chmod +x "$w/bin/$n"
  done
  # uv: `tool install` drops the console script, as the real one does.
  cat >| "$w/bin/uv" <<'STUB'
#!/bin/sh
echo "uv $*" >> "$STUBLOG"
if [ "$1 $2" = "tool install" ]; then
  mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' > "$HOME/.local/bin/blender-mcp"; chmod +x "$HOME/.local/bin/blender-mcp"
fi
exit 0
STUB
  chmod +x "$w/bin/uv"
  # A timeout that runs the wrapped command, so the wrapped call is observable.
  printf '#!/bin/sh\necho "gtimeout $*" >> "$STUBLOG"\nshift\nexec "$@"\n' >| "$w/bin/gtimeout"
  chmod +x "$w/bin/gtimeout"
  cat >| "$w/claude-stub" <<'STUB'
#!/bin/sh
echo "claude $*" >> "$STUBLOG"
case "$*" in
  "--version") echo "9.9.9 (Claude Code)" ;;
  "plugin list"*) cat "$STUBDIR/plugin-list" 2>/dev/null ;;
  "mcp get "*) grep -qx "$3" "$STUBDIR/have-mcp" 2>/dev/null; exit $? ;;
esac
exit 0
STUB
  chmod +x "$w/claude-stub"
  cat >| "$w/bin/curl" <<'STUB'
#!/bin/sh
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
[ -n "$out" ] || exit 0
if [ "${STUB_INSTALLER:-drop}" = drop ]; then
  printf '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\ncp "%s/claude-stub" "$HOME/.local/bin/claude"\n' "$STUBDIR" >| "$out"
else
  printf '#!/bin/sh\nexit 0\n' >| "$out"
fi
STUB
  chmod +x "$w/bin/curl"
}
# _full_run <W> [VAR=value ...] -- the whole bootstrap as `bash install_claude.sh`
_full_run() {
  local w="$1"; shift
  (
    export HOME="$w/home" PATH="$w/bin:/usr/bin:/bin" STUBLOG="$w/log" STUBDIR="$w"
    unset VAULT_DIR
    env "$@" bash scripts/install_claude.sh >| "$w/out" 2>&1
  )
}
# _in_env <W> <command...> -- run one function from the sourced library
_in_env() {
  local w="$1"; shift
  (
    export HOME="$w/home" PATH="$w/bin:/usr/bin:/bin" STUBLOG="$w/log" STUBDIR="$w"
    unset VAULT_DIR
    # shellcheck source=/dev/null
    source scripts/install_claude.sh --lib
    mkdir -p "$(dirname "$CLAUDE_INSTALL_LOG")"
    "$@"
  )
}

section "N1 — claude is reachable during the bootstrap (item 2.1)"
t "N1.1" "the plugin commands reach the claude the installer just dropped in ~/.local/bin" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^claude plugin install superpowers@superpowers-marketplace" "$W/log")" -eq 1 ]'
t "N1.2" "a missing binary after the install step fails the run loudly" '
  W=$(sandbox); _stubs "$W"; ! _full_run "$W" STUB_INSTALLER=noop &&
  [ "$(grep -c -- "- claude binary" "$W/out")" -eq 1 ]'
t "N1.4" "verify_claude_install fails, not skips, when claude is absent" '
  W=$(sandbox); _stubs "$W"; ! _in_env "$W" verify_claude_install'
t "N1.3" "~/.local/bin is put on PATH exactly once" '
  W=$(sandbox); _stubs "$W"
  n=$(export HOME="$W/home" PATH="$W/bin:/usr/bin:/bin"; source scripts/install_claude.sh --lib; source scripts/install_claude.sh --lib; printf "%s" "$PATH" | tr ":" "\n" | grep -cx "$W/home/.local/bin")
  [ "$n" -eq 1 ]'

section "N2 — a timeout that exists (item 2.2)"
t "N2.1" "qmd update and embed run when only gtimeout is on PATH (no bare timeout)" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/Vault"; _full_run "$W"
  [ "$(grep -c "^qmd update" "$W/log")" -eq 1 ] && [ "$(grep -c "^qmd embed" "$W/log")" -eq 1 ]'
t "N2.2" "the qmd calls go through the resolved timeout" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/Vault"; _full_run "$W"
  [ "$(grep -c "^gtimeout 60 qmd update" "$W/log")" -eq 1 ]'
t "N2.3" "with no timeout binary the command still runs unbounded" '
  W=$(sandbox); _stubs "$W"
  ( export HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" STUBLOG="$W/log" STUBDIR="$W"
    source scripts/install_claude.sh --lib; TIMEOUT_BIN=""; run_bounded 5 qmd update ) &&
  [ "$(grep -c "^qmd update" "$W/log")" -eq 1 ] && [ "$(grep -c "^gtimeout" "$W/log")" -eq 0 ]'

section "N3 — no empty vault (item 2.3)"
t "N3.1" "a missing vault is not scaffolded" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"; [ ! -e "$W/home/Vault" ]'
t "N3.2" "a missing vault registers no QMD collections and says why" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^qmd collection add" "$W/log")" -eq 0 ] &&
  [ "$(grep -ci "copy your vault" "$W/out")" -ge 1 ]'
t "N3.3" "an existing vault still gets its collections and templates" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/Vault"; _full_run "$W"
  [ "$(grep -c "^qmd collection add notes" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^qmd collection add sessions" "$W/log")" -eq 1 ] &&
  [ -d "$W/home/Vault/Polaris" ]'

section "N3b — the vault in iCloud Drive (Task 7)"
# A fake iCloud Drive lives under the sandbox; DOTFILES_VAULT_ICLOUD points at
# the vault folder inside it, so nothing here reaches the real iCloud Drive.
# brctl is a stub that logs; STUB_BRCTL_MATERIALIZE=1 makes it clear placeholders.
_icloud_env() { # _icloud_env <W> [placeholder]: stubs, a fake iCloud vault, optional placeholder
  local w="$1"; _stubs "$w"
  mkdir -p "$w/icloud/Vault/Notes"; printf 'n\n' >"$w/icloud/Vault/Notes/a.md"
  [ "${2:-}" = placeholder ] && : >"$w/icloud/Vault/Notes/.b.md.icloud"
  printf '#!/bin/sh\necho "brctl $*" >> "$STUBLOG"\n[ -n "${STUB_BRCTL_MATERIALIZE:-}" ] && find "$2/" -name "*.icloud" -exec rm -f {} + 2>/dev/null\nexit 0\n' >| "$w/bin/brctl"
  chmod +x "$w/bin/brctl"
}
_icloud_run() { local w="$1"; shift; _full_run "$w" DOTFILES_VAULT_ICLOUD="$w/icloud/Vault" DOTFILES_VAULT_DL_WAIT=0 "$@"; }
t "N3b.1" "a missing ~/Vault with an iCloud vault present becomes a symlink to it" '
  W=$(sandbox); _icloud_env "$W"; _icloud_run "$W"
  [ -L "$W/home/Vault" ] && [ "$(readlink "$W/home/Vault")" = "$W/icloud/Vault" ]'
t "N3b.2" "the iCloud vault is downloaded before it is indexed, then indexed" '
  W=$(sandbox); _icloud_env "$W"; _icloud_run "$W"
  grep -q "^brctl download .*/icloud/Vault" "$W/log" && [ "$(grep -c "^qmd collection add notes" "$W/log")" -eq 1 ]'
t "N3b.3" "placeholders that stay: a warning, and nothing is indexed" '
  W=$(sandbox); _icloud_env "$W" placeholder; _icloud_run "$W"
  [ "$(grep -c "^qmd collection add" "$W/log")" -eq 0 ] && [ "$(grep -c "^qmd update" "$W/log")" -eq 0 ] &&
  [ "$(grep -ci "icloud" "$W/out")" -ge 1 ] && [ "$(grep -ci "Keep Downloaded" "$W/out")" -ge 1 ]'
t "N3b.4" "placeholders that brctl materialises: indexing proceeds" '
  W=$(sandbox); _icloud_env "$W" placeholder; _icloud_run "$W" STUB_BRCTL_MATERIALIZE=1
  [ "$(grep -c "^qmd collection add notes" "$W/log")" -eq 1 ]'
t "N3b.5" "placeholders block the template copy too: nothing is written into a half-downloaded vault" '
  W=$(sandbox); _icloud_env "$W" placeholder; _icloud_run "$W"; [ ! -d "$W/icloud/Vault/Polaris" ]'
t "N3b.6" "no iCloud vault and no ~/Vault: the old advice, no symlink" '
  W=$(sandbox); _stubs "$W"; _full_run "$W" DOTFILES_VAULT_ICLOUD="$W/icloud/Vault"
  [ ! -e "$W/home/Vault" ] && [ ! -L "$W/home/Vault" ] && [ "$(grep -ci "copy your vault" "$W/out")" -ge 1 ]'
t "N3b.7" "an existing local ~/Vault is never replaced by the iCloud one" '
  W=$(sandbox); _icloud_env "$W"; mkdir -p "$W/home/Vault"; printf "mine\n" >"$W/home/Vault/x.md"; _icloud_run "$W"
  [ ! -L "$W/home/Vault" ] && [ -f "$W/home/Vault/x.md" ] && [ ! -e "$W/home/Vault/Vault" ] && [ ! -L "$W/home/Vault/Vault" ] &&
  [ "$(grep -c "^brctl" "$W/log")" -eq 0 ]'
t "N3b.8" "a local vault never calls brctl" '
  W=$(sandbox); _icloud_env "$W"; mkdir -p "$W/home/Vault"; _icloud_run "$W"; [ "$(grep -c "^brctl" "$W/log")" -eq 0 ] &&
  [ "$(grep -c "^qmd collection add notes" "$W/log")" -eq 1 ]'

section "N4 — plugins (item 2.4)"
t "N4.1" "the cc-marketplace and claude-code-warp marketplaces are listed" '
  grep -qx "kenryu42/cc-marketplace" claude/marketplaces.list &&
  grep -qx "warpdotdev/claude-code-warp" claude/marketplaces.list'
t "N4.2" "cc-safety-net and warp are listed; the renamed safety-net is not" '
  grep -qx "cc-safety-net@cc-marketplace" claude/plugins.list &&
  grep -qx "warp@claude-code-warp" claude/plugins.list &&
  [ "$(grep -c "^safety-net@" claude/plugins.list)" -eq 0 ]'
t "N4.3" "the bootstrap adds those marketplaces and installs those plugins" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^claude plugin marketplace add kenryu42/cc-marketplace" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude plugin marketplace add warpdotdev/claude-code-warp" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude plugin install cc-safety-net@cc-marketplace" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude plugin install warp@claude-code-warp" "$W/log")" -eq 1 ]'

section "N5 — MCP servers from a list (item 2.5)"
t "N5.1" "mcp.list holds qmd and blender and the file documents its format" '
  [ "$(grep -cE "^qmd[[:space:]]+qmd mcp$" claude/mcp.list)" -eq 1 ] &&
  [ "$(grep -cE "^blender[[:space:]]+\\\$HOME/.local/bin/blender-mcp$" claude/mcp.list)" -eq 1 ] &&
  [ "$(grep -c "^#.*name" claude/mcp.list)" -ge 1 ]'
t "N5.2" "the bootstrap registers each listed server at user scope, once" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^claude mcp add --scope user qmd -- qmd mcp$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude mcp add --scope user blender -- $W/home/.local/bin/blender-mcp$" "$W/log")" -eq 1 ]'
t "N5.3" "a server that already exists is skipped" '
  W=$(sandbox); _stubs "$W"; printf "qmd\n" >| "$W/have-mcp"; _full_run "$W"
  [ "$(grep -c "^claude mcp get qmd" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude mcp add .* qmd " "$W/log")" -eq 0 ] &&
  [ "$(grep -c "^claude mcp add .* blender " "$W/log")" -eq 1 ]'
t "N5.4" "blender: the official server is installed from its git tag, never by PyPI name" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^uv tool install --force git+https://projects.blender.org/lab/blender_mcp.git@v1.0.3#subdirectory=mcp$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^uv tool install .*blender-mcp$" "$W/log")" -eq 0 ]'
t "N5.5" "blender: the add-on note names the zip and the Blender version" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "mcp-1.0.3.zip" "$W/out")" -ge 1 ] && [ "$(grep -c "5.1" "$W/out")" -ge 1 ]'
t "N5.6" "blender: without uv it warns and registers nothing dead" '
  W=$(sandbox); _stubs "$W"; command rm -f "$W/bin/uv"; _full_run "$W"
  [ "$(grep -c "^claude mcp add .* blender " "$W/log")" -eq 0 ] &&
  [ "$(grep -ci "uv" "$W/out")" -ge 1 ]'
t "N5.7" "blender: an installed server is not reinstalled" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.local/bin"; printf "#!/bin/sh\n" >| "$W/home/.local/bin/blender-mcp"; chmod +x "$W/home/.local/bin/blender-mcp"
  _full_run "$W"; [ "$(grep -c "^uv tool install" "$W/log")" -eq 0 ]'
t "N5.8" "mcp.local.list is read too, and \$HOME is expanded at install time" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/cd"
  printf "# comment\nalpha alpha-bin one\n" >| "$W/cd/mcp.list"
  printf "beta \$HOME/bin/beta --x\n" >| "$W/cd/mcp.local.list"
  command cp "$W/claude-stub" "$W/bin/claude"; (
    export HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" STUBLOG="$W/log" STUBDIR="$W"
    source scripts/install_claude.sh --lib; CLAUDE_DIR="$W/cd"; CLAUDE_INSTALL_LOG="$W/i.log"; register_mcp_servers )
  [ "$(grep -c "^claude mcp add --scope user alpha -- alpha-bin one$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^claude mcp add --scope user beta -- $W/home/bin/beta --x$" "$W/log")" -eq 1 ]'
t "N5.9" "the qmd registration is no longer hardcoded in the script" '
  [ "$(code_of scripts/install_claude.sh | grep -c "mcp add --transport stdio --scope user qmd")" -eq 0 ]'

section "N7 — dotfiles claude diff reports unregistered MCP servers (item 2.8)"
_diff_home() { # _diff_home <W> [mcpServers-json]: a sandbox HOME identical to the repo
  local w="$1"
  mkdir -p "$w/home/.claude/hooks" "$w/home/.claude/rules"
  command cp claude/hooks/* "$w/home/.claude/hooks/"; command cp claude/rules/* "$w/home/.claude/rules/"
  command cp claude/statusline.sh "$w/home/.claude/"
  [ -z "${2:-}" ] || printf '{"mcpServers":%s}\n' "$2" >| "$w/home/.claude.json"
}
t "N7.1" "diff names a listed server that is not registered and exits non-zero" '
  W=$(sandbox); _diff_home "$W" "{\"qmd\":{}}"
  out=$(HOME="$W/home" bash bin/dotfiles-claude diff 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ "$(printf "%s" "$out" | grep -c "MCP server blender is in mcp.list but not registered")" -eq 1 ] &&
  [ "$(printf "%s" "$out" | grep -c "MCP server qmd is in mcp.list")" -eq 0 ]'
t "N7.2" "diff passes when every listed server is registered" '
  W=$(sandbox); _diff_home "$W" "{\"qmd\":{},\"blender\":{}}"; HOME="$W/home" bash bin/dotfiles-claude diff'
t "N7.3" "diff skips the MCP check when there is no ~/.claude.json yet" '
  W=$(sandbox); _diff_home "$W"; out=$(HOME="$W/home" bash bin/dotfiles-claude diff 2>&1)
  [ "$(printf "%s" "$out" | grep -ci "claude.json")" -ge 1 ]'

section "N6 — find-docs skill (item 2.6)"
t "N6.1" "skills.list names the find-docs skill and its source" 'grep -qx "upstash/context7 find-docs" claude/skills.list'
t "N6.2" "the skill is installed with the skills CLI for claude-code and codex" '
  W=$(sandbox); _stubs "$W"; _full_run "$W"
  [ "$(grep -c "^npx -y skills add upstash/context7 --skill find-docs -g -a claude-code -a codex -y$" "$W/log")" -eq 1 ]'
t "N6.3" "a hand-placed real directory is moved out of the skills tree to backups/skills/find-docs.<epoch>" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.claude/skills/find-docs"; printf old >| "$W/home/.claude/skills/find-docs/SKILL.md"
  _full_run "$W"
  [ "$(ls "$W/home/.claude/backups/skills" | grep -c "^find-docs\.[0-9]*$")" -eq 1 ] &&
  [ "$(cat "$W"/home/.claude/backups/skills/find-docs.*/SKILL.md)" = old ] &&
  [ "$(ls "$W/home/.claude/skills" | grep -c "find-docs")" -eq 0 ] &&
  [ "$(grep -c "^npx -y skills add" "$W/log")" -eq 1 ]'
t "N6.4" "an already-installed (symlinked) skill is left alone" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.claude/skills" "$W/home/.agents/skills/find-docs"
  ln -s ../../.agents/skills/find-docs "$W/home/.claude/skills/find-docs"
  _full_run "$W"; [ "$(grep -c "^npx" "$W/log")" -eq 0 ] &&
  [ "$(ls "$W/home/.claude/skills" | grep -c "\.bak\.")" -eq 0 ]'
t "N6.6" "a dangling skill symlink is not installed: it is removed and the skill reinstalled" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.claude/skills"
  ln -s ../../.agents/skills/find-docs "$W/home/.claude/skills/find-docs"
  _full_run "$W"; [ "$(grep -c "^npx -y skills add" "$W/log")" -eq 1 ] &&
  [ ! -L "$W/home/.claude/skills/find-docs" ]'
t "N6.5" "a failing skills install fails the run and names the skill" '
  W=$(sandbox); _stubs "$W"; ! _full_run "$W" STUB_FAIL_npx=1 &&
  [ "$(grep -c -- "- skill: find-docs" "$W/out")" -eq 1 ]'

section "N12 — two Safety Net plugins (legacy and renamed)"
_sn_json() { printf '[{"id":"%s@cc-marketplace"}]\n' "$2" >> "$1/plugin-list"; }
t "N12.1" "both installed: a warning names the exact uninstall command for the legacy one" '
  W=$(sandbox); _stubs "$W"; _sn_json "$W" safety-net; _sn_json "$W" cc-safety-net; _full_run "$W"
  [ "$(grep -c "claude plugin uninstall safety-net@cc-marketplace" "$W/out")" -ge 1 ]'
t "N12.2" "the installer never uninstalls anything itself" '
  W=$(sandbox); _stubs "$W"; _sn_json "$W" safety-net; _sn_json "$W" cc-safety-net; _full_run "$W"
  [ "$(grep -c "^claude plugin uninstall" "$W/log")" -eq 0 ]'
t "N12.3" "only the renamed plugin installed: no warning" '
  W=$(sandbox); _stubs "$W"; _sn_json "$W" cc-safety-net; _full_run "$W"
  [ "$(grep -c "claude plugin uninstall" "$W/out")" -eq 0 ]'
t "N12.4" "only the legacy plugin installed: no duplicate warning" '
  W=$(sandbox); _stubs "$W"; _sn_json "$W" safety-net; _full_run "$W"
  [ "$(grep -c "claude plugin uninstall" "$W/out")" -eq 0 ]'

finish

#!/usr/bin/env bash
# tests/claude.sh -- regression tests for the 2026-09-21 audit, Claude/docs workstream.
#
# Covers the Claude Code bootstrap (scripts/install_claude.sh), the hooks and
# statusline shipped in claude/, the rules, `bin/dotfiles-claude`, and the
# agent-facing documentation.
#
# shellcheck disable=SC2016
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
    source scripts/install_claude.sh --lib 2>/dev/null
    CLAUDE_INSTALL_LOG="$w/log"
    for f in install_claude_binary verify_claude_install register_marketplaces \
      install_plugins copy_claude_files link_rule_imports install_statusline \
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
t "E4.7" "installer imports the rules into CLAUDE.md idempotently" 'grep -q "link_rule_imports" scripts/install_claude.sh && code_of scripts/install_claude.sh | sed -n "/link_rule_imports()/,/^}/p" | grep -q "claude/rules"'

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

finish

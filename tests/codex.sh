#!/usr/bin/env bash
# tests/codex.sh -- the Codex bootstrap (scripts/install_codex.sh).
#
# Every run uses a sandbox HOME and a PATH of stub binaries that log their argv
# to $STUBLOG. The real codex is never on PATH, so no plugin, marketplace or
# MCP server is ever registered on the machine running the tests.
#
# shellcheck disable=SC2016,SC2030,SC2031
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

_stubs() { # _stubs <W>
  local w="$1"
  mkdir -p "$w/bin" "$w/home"; : >| "$w/log"
  cat >| "$w/bin/codex" <<'STUB'
#!/bin/sh
echo "codex $*" >> "$STUBLOG"
case "$*" in
  "plugin list --json") cat "$STUBDIR/installed.json" 2>/dev/null || echo '{"installed":[],"available":[]}'; exit 0 ;;
  "plugin marketplace list --json") cat "$STUBDIR/markets.json" 2>/dev/null || echo '{}'; exit 0 ;;
  "mcp get "*) grep -qx "$3" "$STUBDIR/have-mcp" 2>/dev/null; exit $? ;;
  "plugin add superpowers@openai-curated") [ -n "${STUB_NO_CURATED:-}" ] && exit 1 ;;
  "plugin add "*) [ "$3" = "${STUB_FAIL_ADD:-}" ] && exit 1 ;;
esac
exit 0
STUB
  chmod +x "$w/bin/codex"
  cat >| "$w/bin/uv" <<'STUB'
#!/bin/sh
echo "uv $*" >> "$STUBLOG"
if [ "$1 $2" = "tool install" ]; then
  mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' > "$HOME/.local/bin/blender-mcp"; chmod +x "$HOME/.local/bin/blender-mcp"
fi
exit 0
STUB
  chmod +x "$w/bin/uv"
}
# _run <W> [VAR=value ...] -- the whole bootstrap as `bash install_codex.sh`
_run() {
  local w="$1"; shift
  (
    export HOME="$w/home" PATH="$w/bin:/usr/bin:/bin" STUBLOG="$w/log" STUBDIR="$w"
    env "$@" bash scripts/install_codex.sh >| "$w/out" 2>&1
  )
}
_all_installed() { # _all_installed <W>: the stub reports every listed plugin and marketplace
  printf '{"installed":[{"pluginId":"superpowers@openai-curated"},{"pluginId":"compound-engineering@compound-engineering-plugin"},{"pluginId":"warp@codex-warp"},{"pluginId":"cc-safety-net@cc-marketplace"}],"available":[]}\n' >| "$1/installed.json"
  printf '[{"source":"https://github.com/EveryInc/compound-engineering-plugin.git"},{"source":"https://github.com/warpdotdev/codex-warp.git"},{"source":"https://github.com/kenryu42/cc-marketplace.git"}]\n' >| "$1/markets.json"
}

section "X1 — config seeding"
t "X1.1" "the template holds exactly the portable keys" '
  [ "$(grep -c "^model_reasoning_effort = \"high\"$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^approval_policy = \"never\"$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^sandbox_mode = \"danger-full-access\"$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^notification_condition = \"always\"$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^hooks = true$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^\[tui\]$" codex/config.template.toml)" -eq 1 ] &&
  [ "$(grep -c "^\[features\]$" codex/config.template.toml)" -eq 1 ]'
t "X1.2" "the template carries no model, projects, notify, MCP server or absolute path" '
  [ "$(code_of codex/config.template.toml | grep -cE "^model[[:space:]]*=|\[projects|^notify|mcp_servers|/Users/|/home/")" -eq 0 ]'
t "X1.3" "config.toml is seeded when absent" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  cmp -s codex/config.template.toml "$W/home/.codex/config.toml"'
t "X1.4" "an existing config.toml is never touched" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.codex"; printf "model = \"mine\"\n" >| "$W/home/.codex/config.toml"
  _run "$W"
  [ "$(cat "$W/home/.codex/config.toml")" = "model = \"mine\"" ] &&
  [ "$(ls "$W/home/.codex" | grep -c "bak")" -eq 0 ]'

section "X2 — marketplaces and plugins"
t "X2.1" "each listed marketplace is added once with the research-report command" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -c "^codex plugin marketplace add EveryInc/compound-engineering-plugin$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin marketplace add warpdotdev/codex-warp$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin marketplace add kenryu42/cc-marketplace$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin marketplace add" "$W/log")" -eq 3 ]'
t "X2.2" "each listed plugin is added once" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -c "^codex plugin add superpowers@openai-curated$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin add compound-engineering@compound-engineering-plugin$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin add warp@codex-warp$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin add cc-safety-net@cc-marketplace$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin add" "$W/log")" -eq 4 ]'
t "X2.3" "a clean run exits 0" 'W=$(sandbox); _stubs "$W"; _run "$W"'
t "X2.4" "the plugin list is checked before any add" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -n "^codex plugin list --json" "$W/log" | head -1 | cut -d: -f1)" -lt "$(grep -n "^codex plugin add" "$W/log" | head -1 | cut -d: -f1)" ]'
t "X2.5" "a re-run is a no-op when everything is already installed" '
  W=$(sandbox); _stubs "$W"; _all_installed "$W"; _run "$W"
  [ "$(grep -c "^codex plugin add" "$W/log")" -eq 0 ] &&
  [ "$(grep -c "^codex plugin marketplace add" "$W/log")" -eq 0 ]'
t "X2.6" "superpowers falls back to the remote curated marketplace" '
  W=$(sandbox); _stubs "$W"; _run "$W" STUB_NO_CURATED=1
  [ "$(grep -c "^codex plugin add superpowers@openai-curated-remote$" "$W/log")" -eq 1 ]'
t "X2.7" "a failed plugin add fails the run and names the plugin" '
  W=$(sandbox); _stubs "$W"; ! _run "$W" STUB_FAIL_ADD=warp@codex-warp &&
  [ "$(grep -c -- "- plugin: warp@codex-warp" "$W/out")" -eq 1 ]'
t "X2.8" "the one-time hook trust step is printed, never bypassed" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -c "/hooks" "$W/out")" -ge 1 ] &&
  [ "$(code_of scripts/install_codex.sh | grep -c "dangerously-bypass")" -eq 0 ]'
t "X2.9" "plugins.list records the two Claude-only plugins in a comment" '
  [ "$(grep -c "^#.*recall-skill" codex/plugins.list)" -ge 1 ] &&
  [ "$(grep -c "^#.*sync-claude-sessions-skill" codex/plugins.list)" -ge 1 ] &&
  [ "$(grep -vE "^[[:space:]]*(#|$)" codex/plugins.list | grep -c "recall\|sync-claude")" -eq 0 ]'
t "X2.10" "the .local.list companions are gitignored and read" '
  git check-ignore -q codex/plugins.local.list && git check-ignore -q codex/marketplaces.local.list &&
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/cd"
  printf "extra@extra-mkt\n" >| "$W/cd/plugins.local.list"; printf "owner/extra-mkt\n" >| "$W/cd/marketplaces.local.list"
  ( export HOME="$W/home" PATH="$W/bin:/usr/bin:/bin" STUBLOG="$W/log" STUBDIR="$W"
    source scripts/install_codex.sh --lib; CODEX_DIR="$W/cd"; CODEX_INSTALL_LOG="$W/i.log"; mkdir -p "$W/home/.cache/dotfiles"
    register_marketplaces; install_plugins )
  [ "$(grep -c "^codex plugin marketplace add owner/extra-mkt$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex plugin add extra@extra-mkt$" "$W/log")" -eq 1 ]'

section "X3 — MCP servers"
t "X3.1" "the servers in claude/mcp.list are registered with codex mcp add" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -c "^codex mcp add qmd -- qmd mcp$" "$W/log")" -eq 1 ] &&
  [ "$(grep -c "^codex mcp add blender -- $W/home/.local/bin/blender-mcp$" "$W/log")" -eq 1 ]'
t "X3.2" "an existing server is skipped" '
  W=$(sandbox); _stubs "$W"; printf "qmd\n" >| "$W/have-mcp"; _run "$W"
  [ "$(grep -c "^codex mcp add qmd" "$W/log")" -eq 0 ] &&
  [ "$(grep -c "^codex mcp add blender" "$W/log")" -eq 1 ]'
t "X3.3" "the blender tool install is requested from the tagged git source" '
  W=$(sandbox); _stubs "$W"; _run "$W"
  [ "$(grep -c "^uv tool install --force git+https://projects.blender.org/lab/blender_mcp.git@v1.0.3#subdirectory=mcp$" "$W/log")" -eq 1 ]'

section "X4 — environment"
t "X4.1" "a missing codex fails clearly and non-zero" '
  W=$(sandbox); _stubs "$W"; command rm -f "$W/bin/codex"; ! _run "$W" &&
  [ "$(grep -ci "codex" "$W/out")" -ge 1 ] && [ "$(grep -c "^uv\|^codex" "$W/log")" -eq 0 ]'
t "X4.2" "codex is found through the mise shims" '
  W=$(sandbox); _stubs "$W"; mkdir -p "$W/home/.local/share/mise/shims"; command mv "$W/bin/codex" "$W/home/.local/share/mise/shims/codex"
  _run "$W" && [ "$(grep -c "^codex plugin add" "$W/log")" -eq 4 ]'
t "X4.3" "the script has a --lib mode and is shellcheck clean" '
  grep -q -- "--lib" scripts/install_codex.sh &&
  shellcheck -e SC1090,SC1091,SC2034,SC2119,SC2154 scripts/install_codex.sh scripts/lib/mcp.sh'

finish

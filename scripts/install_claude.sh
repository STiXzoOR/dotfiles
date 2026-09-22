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
CLAUDE_INSTALL_LOG="$HOME/.cache/dotfiles/claude-install.log"
FAILURES=()

# Release verification. Anthropic publishes a per-release manifest.json and a
# detached manifest.json.sig, signed by "Anthropic Claude Code Release Signing
# <security@anthropic.com>". Signatures exist from 2.1.89 onward.
CLAUDE_RELEASES_URL="https://downloads.claude.ai/claude-code-releases"
CLAUDE_RELEASE_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
# A published public-key fingerprint, not a secret: it is the value every
# install is meant to check against, and it is printed in Anthropic's own docs.
CLAUDE_RELEASE_KEY_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" #gitleaks:allow

source "$ROOT_DIR/scripts/echos.sh"
source "$ROOT_DIR/scripts/requirers.sh"
source "$ROOT_DIR/scripts/lib/lists.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────────

try_or_track() {
  local label="$1"
  shift
  if ! "$@"; then
    FAILURES+=("$label")
  fi
}

# Copy a repo file over an installed one, keeping a way back.
#
# `dotfiles link` backs originals up to ~/.dotfiles_backup/<timestamp>; this
# path did not, so a bootstrap silently destroyed any hook, rule or status line
# the user had hardened by hand since the last install. Only a file that
# actually differs is backed up, so re-running the bootstrap does not litter.
install_file() { # install_file <src> <dest>
  local src="$1" dest="$2"
  if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.bak.$(date +%s)" || return 1
  fi
  cp "$src" "$dest"
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
  trap 'rm -f "$tmpfile"' RETURN

  if curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh -o "$tmpfile"; then
    if bash "$tmpfile"; then
      ok "Claude Code installed"
    else
      error "Claude Code installer failed"
      return 1
    fi
  else
    error "Failed to download Claude Code installer"
    return 1
  fi
}

# `curl | bash` leaves no record of what ran, and downloading to a temp file
# first changes nothing about that -- the earlier plan claimed this closed a
# HIGH finding, and it did not. Verify what actually landed on disk instead:
# the signed release manifest names a sha256 per platform, so a tampered
# binary fails the comparison even though the installer script itself is
# unsignable. gpg is optional; without it the checksum still catches
# corruption and a substituted mirror, it just cannot prove provenance.
verify_claude_binary() {
  local version="$1" binary="$2" tmpdir base expected actual

  command -v curl >/dev/null 2>&1 || {
    warn "curl unavailable, skipping release verification"
    return 0
  }
  command -v jq >/dev/null 2>&1 || {
    warn "jq unavailable, skipping release verification"
    return 0
  }

  tmpdir=$(mktemp -d) || return 1
  # shellcheck disable=SC2064  # expand tmpdir now, not when the trap fires
  trap "rm -rf '$tmpdir'" RETURN

  base="$CLAUDE_RELEASES_URL/$version"
  if ! curl -fsSL --proto '=https' --tlsv1.2 "$base/manifest.json" -o "$tmpdir/manifest.json" ||
    ! curl -fsSL --proto '=https' --tlsv1.2 "$base/manifest.json.sig" -o "$tmpdir/manifest.json.sig"; then
    warn "no signed manifest published for Claude Code $version (signatures start at 2.1.89)"
    return 0
  fi

  if command -v gpg >/dev/null 2>&1; then
    local gnupghome="$tmpdir/gnupg"
    mkdir -p "$gnupghome" && chmod 700 "$gnupghome"
    # A throwaway keyring: importing a release key must not touch the user's own.
    if curl -fsSL --proto '=https' --tlsv1.2 "$CLAUDE_RELEASE_KEY_URL" -o "$tmpdir/claude-code.asc" &&
      GNUPGHOME="$gnupghome" gpg --batch --quiet --import "$tmpdir/claude-code.asc" >>"$CLAUDE_INSTALL_LOG" 2>&1; then
      if ! GNUPGHOME="$gnupghome" gpg --batch --with-colons --fingerprint 2>/dev/null |
        grep -q "$CLAUDE_RELEASE_KEY_FINGERPRINT"; then
        error "Claude Code signing key fingerprint does not match $CLAUDE_RELEASE_KEY_FINGERPRINT"
        return 1
      fi
      if GNUPGHOME="$gnupghome" gpg --batch --quiet --verify \
        "$tmpdir/manifest.json.sig" "$tmpdir/manifest.json" >>"$CLAUDE_INSTALL_LOG" 2>&1; then
        ok "release manifest signature verified"
      else
        error "release manifest signature does NOT verify — refusing to trust this install"
        return 1
      fi
    else
      warn "could not import the Claude Code signing key; falling back to the checksum alone"
    fi
  else
    warn "gpg not installed — checking the manifest checksum only (brew install gnupg to verify signatures)"
  fi

  expected=$(jq -r '.platforms["darwin-arm64"].checksum // empty' "$tmpdir/manifest.json")
  if [[ -z "$expected" ]]; then
    warn "manifest for $version has no darwin-arm64 checksum"
    return 0
  fi
  actual=$(shasum -a 256 "$binary" 2>/dev/null | awk '{print $1}')
  if [[ "$expected" != "$actual" ]]; then
    error "Claude Code $version does NOT match the signed manifest checksum"
    return 1
  fi
  ok "binary checksum matches the signed manifest"

  # Free, local, and independent of the network: macOS release binaries are
  # signed by "Anthropic PBC" and notarized.
  if command -v codesign >/dev/null 2>&1; then
    if codesign --verify --strict "$binary" >>"$CLAUDE_INSTALL_LOG" 2>&1; then
      ok "code signature valid"
    else
      warn "codesign could not verify the binary"
    fi
  fi
}

verify_claude_install() {
  local version binary
  command -v claude >/dev/null 2>&1 || return 0

  version=$(claude --version 2>/dev/null | awk '{print $1}')
  if [[ -z "$version" ]]; then
    warn "could not determine the installed Claude Code version"
    return 0
  fi

  binary="$HOME/.local/share/claude/versions/$version"
  if [[ ! -f "$binary" ]]; then
    warn "Claude Code $version was not installed by the native installer; skipping manifest verification"
    return 0
  fi

  action "Verifying Claude Code $version against the signed release manifest"
  verify_claude_binary "$version" "$binary"
}

# ─── 2. Register marketplaces ────────────────────────────────────────────────

register_marketplaces() {
  if [[ ! -f "$CLAUDE_DIR/marketplaces.list" && ! -f "$CLAUDE_DIR/marketplaces.local.list" ]]; then
    warn "No marketplaces.list found, skipping"
    return
  fi

  action "Registering Claude Code marketplaces"

  # Cache marketplace list once before the loop
  export CLAUDE_MARKETPLACES_CACHE
  CLAUDE_MARKETPLACES_CACHE="$(claude plugin marketplace list --json 2>/dev/null || echo "")"

  local total count=0
  total=$(count_list "$CLAUDE_DIR" marketplaces)

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    running "[$count/$total] marketplace $line"
    try_or_track "marketplace: $line" require_claude_marketplace "$line"
  done < <(read_list "$CLAUDE_DIR" marketplaces)
}

# ─── 3. Install plugins ──────────────────────────────────────────────────────

install_plugins() {
  if [[ ! -f "$CLAUDE_DIR/plugins.list" && ! -f "$CLAUDE_DIR/plugins.local.list" ]]; then
    warn "No plugins.list found, skipping"
    return
  fi

  action "Installing Claude Code plugins"

  # Cache installed plugins list once before the loop
  export CLAUDE_PLUGINS_CACHE
  CLAUDE_PLUGINS_CACHE="$(claude plugin list --json 2>/dev/null || echo "")"

  local total count=0 skipped=0
  total=$(count_list "$CLAUDE_DIR" plugins)

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue

    count=$((count + 1))
    local plugin_name="${line%%@*}"

    # Skip already-installed plugins silently
    if echo "$CLAUDE_PLUGINS_CACHE" | grep -Fq "$plugin_name"; then
      skipped=$((skipped + 1))
      continue
    fi

    running "[$count/$total] plugin $line"
    try_or_track "plugin: $line" require_claude_plugin "$line"
  done < <(read_list "$CLAUDE_DIR" plugins)

  if [[ $skipped -gt 0 ]]; then
    ok "$skipped plugins already installed, skipped"
  fi
}

# ─── 4. Copy rules and hooks ─────────────────────────────────────────────────

copy_claude_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local label="$3"
  local make_exec="${4:-false}"

  if [[ ! -d "$src_dir" ]]; then
    warn "No $label directory found, skipping"
    return
  fi

  action "Copying Claude Code $label"
  mkdir -p "$dest_dir"
  for file in "$src_dir"/*; do
    [[ -f "$file" ]] || continue
    local name
    name="$(basename "$file")"
    install_file "$file" "$dest_dir/$name" || { warn "could not install $label/$name"; continue; }
    [[ "$make_exec" == "true" ]] && chmod +x "$dest_dir/$name"
    ok "$label/$name"
  done
}

# Rules copied into ~/.claude/rules/ are discovered by recent Claude Code
# versions on their own, but that was not what made them load on the machine
# this repo was written on: ~/.claude/rules held exactly one stale file, and it
# was read only because ~/.claude/CLAUDE.md named it by hand. Two of the three
# repo rules were referenced nowhere at all.
#
# Make the link explicit and idempotent. Never create a CLAUDE.md the user did
# not write -- a memory file appearing out of nowhere is its own surprise.
link_rule_imports() {
  local memory="$CLAUDE_HOME/CLAUDE.md"
  local src_dir="$CLAUDE_DIR/rules"
  local file name line added=0

  [[ -d "$src_dir" ]] || return 0
  if [[ ! -f "$memory" ]]; then
    warn "no $memory; skipping rule imports (Claude Code still discovers ~/.claude/rules/)"
    return 0
  fi

  action "Linking rules into $memory"
  for file in "$src_dir"/*.md; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    line="@~/.claude/rules/$name"
    grep -qF "$line" "$memory" && continue
    printf '%s\n' "$line" >> "$memory" || {
      warn "could not append $line to $memory"
      return 1
    }
    added=$((added + 1))
  done

  if [[ "$added" -gt 0 ]]; then
    ok "added $added rule import(s)"
  else
    ok "rule imports already present"
  fi
}

# ─── 5. Merge settings template ──────────────────────────────────────────────

setup_recall_venv() {
  # Installing the recall plugin is not enough: the Stop hook invokes
  # $HOME/.claude/skills/recall/.venv/bin/python3 directly, and nothing
  # creates that venv. A fresh machine would install the plugin and still
  # have a hook that fails with "no such file or directory".
  local skill_dir="$CLAUDE_HOME/skills/recall"
  local venv="$skill_dir/.venv"

  if [[ ! -d "$skill_dir" ]]; then
    warn "recall skill not present yet, skipping venv (re-run after plugins install)"
    return 0
  fi

  if [[ -x "$venv/bin/python3" ]]; then
    ok "recall venv already present ($("$venv/bin/python3" --version 2>&1))"
  else
    action "Creating recall venv"
    if command -v uv &>/dev/null; then
      uv venv "$venv" >>"$CLAUDE_INSTALL_LOG" 2>&1
    else
      python3 -m venv "$venv" >>"$CLAUDE_INSTALL_LOG" 2>&1
    fi
    if [[ -x "$venv/bin/python3" ]]; then
      ok "recall venv created"
    else
      warn "could not create recall venv"
      return 0
    fi
  fi

  # extract-sessions.py (the hook path) is stdlib-only, so the hook already
  # works. networkx and pyvis are only needed by `recall graph`; a failure
  # here must not fail the bootstrap.
  if ! "$venv/bin/python3" -c "import networkx, pyvis" >/dev/null 2>&1; then
    action "Installing recall graph dependencies"
    if command -v uv &>/dev/null; then
      uv pip install --python "$venv/bin/python3" networkx pyvis >>"$CLAUDE_INSTALL_LOG" 2>&1 || true
    else
      "$venv/bin/python3" -m pip install networkx pyvis >>"$CLAUDE_INSTALL_LOG" 2>&1 || true
    fi
    if "$venv/bin/python3" -c "import networkx, pyvis" >/dev/null 2>&1; then
      ok "networkx + pyvis"
    else
      warn "recall graph deps unavailable ('recall graph' will not work; the Stop hook is unaffected)"
    fi
  fi
}

install_statusline() {
  # settings.template.json points statusLine at this script. It used to exist
  # only on the author's machine, so a fresh bootstrap wrote a settings file
  # referencing a file that was never installed.
  local src="$CLAUDE_DIR/statusline.sh"
  [[ -f "$src" ]] || { warn "No statusline.sh in the repo, skipping"; return; }

  action "Installing status line"
  install_file "$src" "$CLAUDE_HOME/statusline.sh"
  chmod +x "$CLAUDE_HOME/statusline.sh"
  ok "statusline.sh"
}

verify_settings_refs() {
  # Every command a hook or the status line points at must actually exist by
  # the end of the bootstrap; a dangling reference fails silently at runtime.
  #
  # The version before last used jq's scan() with a capture group, which makes
  # scan return arrays of captures rather than matched strings -- so it
  # reported four bogus "missing file" warnings from the pretty-printed array
  # and never noticed a genuinely dangling path.
  #
  # Splitting on whitespace alone fixed that and introduced its own: a hook
  # command is a shell command line, so a path containing a space is quoted,
  # and "/Users/x/Library/Application Support/..." split into a first half
  # that looks exactly like an absolute path and does not exist. That warned
  # about a file which was present, every run, and a genuinely dangling path
  # could hide in the noise. Quoted runs are now taken whole and unwrapped.
  local settings="${1:-$CLAUDE_HOME/settings.json}"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local missing=0 path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    path="${path/#\$HOME/$HOME}"
    path="${path/#\~/$HOME}"
    if [[ ! -e "$path" ]]; then
      warn "settings references a missing file: $path"
      missing=$((missing + 1))
    fi
  done < <(
    jq -r '
      [ (.hooks // {} | .[]? | .[]? | .hooks[]?.command // empty),
        (.statusLine.command // empty) ]
      | .[]
      | [ scan("'"'"'[^'"'"']*'"'"'|\"[^\"]*\"|[^ \"'"'"']+") ]
      | .[]
      | gsub("^['"'"'\"]|['"'"'\"]$"; "")
      | select(test("^(\\$HOME|~|/)"))
    ' "$settings" 2>/dev/null | sort -u
  )

  if [[ "$missing" -gt 0 ]]; then
    return 1
  fi
  ok "all referenced files present"
}

# Merge a settings template into an existing settings file, on stdout.
#
# jq's `*` lets the RIGHT operand win, so the old `.[0] * .[1]` with the
# template on the left meant no template edit could ever reach a machine that
# already had a settings.json -- not a new hook, not a new status line.
#
# Split the difference by key instead:
#   - hooks is merged per EVENT. A template event overrides the same-named
#     existing event wholesale, because a per-key merge of an array of hook
#     objects produces nonsense -- but an event the template says nothing about
#     survives untouched. Replacing the whole subtree deleted four of the eight
#     hook events live on the author's machine, including the one driving
#     skills-autoupdate.
#   - statusLine is replaced wholesale from the template. It is a single
#     object with one owner.
#   - env is merged per key with the template winning, so a machine-specific
#     variable set by hand survives a re-bootstrap.
#   - autoUpdatesChannel and minimumVersion come from the template: they are a
#     supply-chain floor, not a preference.
#   - everything else keeps the existing value (model, effortLevel,
#     enabledPlugins and the rest of the machine-specific keys).
merge_settings_files() { # merge_settings_files <template> <existing>
  local template="$1" existing="$2"
  jq -n --slurpfile tpl "$template" --slurpfile cur "$existing" '
    ($tpl[0] // {}) as $t
    | ($cur[0] // {}) as $c
    | ($t * $c)
    | (if ($t | has("hooks")) then .hooks = (($c.hooks // {}) * $t.hooks) else . end)
    | (if ($t | has("statusLine")) then .statusLine = $t.statusLine else . end)
    | (if ($t | has("env")) then .env = (($c.env // {}) * $t.env) else . end)
    | (if ($t | has("autoUpdatesChannel")) then .autoUpdatesChannel = $t.autoUpdatesChannel else . end)
    | (if ($t | has("minimumVersion")) then .minimumVersion = $t.minimumVersion else . end)
  '
}

merge_settings() {
  local template="$CLAUDE_DIR/settings.template.json"
  local target="$CLAUDE_HOME/settings.json"

  if [[ ! -f "$template" ]]; then
    warn "No settings.template.json found, skipping"
    return
  fi

  action "Merging Claude Code settings"

  # Expand $HOME in template using envsubst (safe against metacharacters)
  local expanded
  if command -v envsubst &>/dev/null; then
    # shellcheck disable=SC2016
    expanded=$(HOME="$HOME" envsubst '$HOME' < "$template")
  else
    # Fallback to sed with escaped replacement
    local escaped_home
    escaped_home=$(printf '%s\n' "$HOME" | sed 's/[&/\]/\\&/g')
    expanded=$(sed "s|\\\$HOME|$escaped_home|g" "$template")
  fi

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

    local tmpfile expandedfile
    tmpfile=$(mktemp)
    expandedfile=$(mktemp)
    printf '%s\n' "$expanded" > "$expandedfile"
    if merge_settings_files "$expandedfile" "$target" > "$tmpfile"; then
      mv "$tmpfile" "$target"
      rm -f "$expandedfile"
      ok "settings.json merged (hooks, statusLine and update floor from the template)"
    else
      rm -f "$tmpfile" "$expandedfile"
      error "JSON merge failed"
      return 1
    fi
  fi
}

# ─── 6. Setup Obsidian vault ─────────────────────────────────────────────────

setup_vault() {
  action "Setting up Obsidian vault structure"
  mkdir -p "$VAULT_DIR"/{Claude-Sessions,Resources,Inbox,Projects,Daily,Polaris}
  ok "vault directories ready"

  # Copy starter templates (only if they don't already exist)
  local templates_dir="$CLAUDE_DIR/vault-templates"
  if [[ -d "$templates_dir" ]]; then
    for template in "$templates_dir"/*; do
      [[ -f "$template" ]] || continue
      local name
      name="$(basename "$template")"
      local dest="$VAULT_DIR/Polaris/$name"
      if [[ ! -f "$dest" ]]; then
        cp "$template" "$dest"
        ok "vault template: Polaris/$name"
      fi
    done
  fi
}

# ─── 7. Setup QMD ────────────────────────────────────────────────────────────

setup_qmd() {
  if ! command -v qmd &>/dev/null; then
    warn "QMD not installed — it is declared as 'npm:@tobilu/qmd' in config/mise/config.toml; run 'dotfiles install --node'"
    return
  fi

  ok "QMD already installed ($(qmd --version 2>/dev/null))"

  # A shim is already a stable path, but a machine part-way through the
  # migration may still have qmd inside a per-PID Node multishell directory
  # that no hook, launchd job or cron entry ever inherits. Publish a stable
  # name the index hook can resolve without an interactive shell either way.
  local qmd_bin stable="$HOME/.local/bin/qmd"
  qmd_bin="$(command -v qmd)"
  if [[ "$qmd_bin" != "$stable" ]]; then
    mkdir -p "$(dirname "$stable")"
    if ln -sfn "$qmd_bin" "$stable"; then
      ok "qmd linked to ~/.local/bin/qmd (reachable from hooks)"
    else
      warn "could not link qmd into ~/.local/bin; the index hook will fall back to the mise shims"
    fi
  fi

  # Register collections (idempotent — qmd ignores duplicates)
  action "Configuring QMD collections"

  if qmd collection add notes "$VAULT_DIR" 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD collection: notes -> $VAULT_DIR"
  else
    warn "QMD collection 'notes' setup failed"
  fi

  # The transcripts under ~/.claude/projects are raw JSONL plus per-project
  # memory; qmd's pattern is **/*.md, so it would index almost none of it.
  # sync-claude-sessions writes the markdown into the vault, and that is what
  # the "sessions" collection has always pointed at on a working machine.
  local sessions_dir="$VAULT_DIR/Claude-Sessions"
  if [[ -d "$sessions_dir" ]]; then
    if qmd collection add sessions "$sessions_dir" 2>>"$CLAUDE_INSTALL_LOG"; then
      ok "QMD collection: sessions -> $sessions_dir"
    else
      warn "QMD collection 'sessions' setup failed"
    fi
  fi

  # Add context descriptions for collections
  qmd context add notes "Obsidian vault — notes, resources, projects, daily logs" 2>>"$CLAUDE_INSTALL_LOG" || true
  qmd context add sessions "Claude Code session transcripts and conversation history" 2>>"$CLAUDE_INSTALL_LOG" || true

  # Update index (fast — only processes changed files)
  action "Updating QMD index"
  if timeout 60 qmd update 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD index updated"
  else
    warn "QMD update timed out or failed (run 'qmd update' manually)"
  fi

  # Run embedding if models are available (first run downloads ~2GB)
  action "Building QMD embeddings (may take a moment on first run)"
  if timeout 120 qmd embed 2>>"$CLAUDE_INSTALL_LOG"; then
    ok "QMD embeddings ready"
  else
    warn "QMD embed timed out or failed (run 'qmd embed' manually)"
  fi

  # Register QMD MCP server with Claude Code (stored in ~/.claude.json)
  if command -v claude &>/dev/null; then
    action "Registering QMD MCP server"
    if claude mcp add --transport stdio --scope user qmd -- qmd mcp 2>>"$CLAUDE_INSTALL_LOG"; then
      ok "QMD MCP server registered (user scope)"
    else
      warn "QMD MCP registration failed (run 'claude mcp add --transport stdio --scope user qmd -- qmd mcp' manually)"
    fi
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local start_time
  start_time=$(date +%s)

  # Ensure log directory exists (private to user)
  mkdir -p "$(dirname "$CLAUDE_INSTALL_LOG")"
  : > "$CLAUDE_INSTALL_LOG"

  # Every step whose failure means the bootstrap did not do its job goes
  # through try_or_track. Calling these bare threw away the very return values
  # verify_settings_refs and merge_settings were rewritten to produce, so a
  # settings file pointing at a missing hook, or a merge that failed outright,
  # still printed "bootstrap complete!" and exited 0.
  try_or_track "claude binary" install_claude_binary
  try_or_track "release verification" verify_claude_install
  register_marketplaces
  install_plugins
  copy_claude_files "$CLAUDE_DIR/rules" "$CLAUDE_HOME/rules" "rules"
  try_or_track "rule imports" link_rule_imports
  copy_claude_files "$CLAUDE_DIR/hooks" "$CLAUDE_HOME/hooks" "hooks" "true"
  install_statusline
  setup_recall_venv
  try_or_track "settings merge" merge_settings
  try_or_track "settings references" verify_settings_refs
  setup_vault
  setup_qmd

  report_failures

  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  echo ""
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    # "bootstrap complete!" after four failed plugin installs trains the user
    # to ignore the output. bin/dotfiles propagates this status.
    error "Claude Code bootstrap finished with ${#FAILURES[@]} failures (${elapsed}s)"
    echo ""
    return 1
  fi

  bot "Claude Code bootstrap complete! (${elapsed}s)"
  echo ""
  echo "Next steps:"
  echo "  1. Run 'claude' to authenticate (if first install)"
  echo "  2. Restart your shell to pick up changes"
  echo ""
}

# `source scripts/install_claude.sh --lib` loads the functions without running
# the bootstrap, so tests can exercise them directly. Nothing above this line
# has side effects.
if [[ "${1:-}" == "--lib" ]]; then
  # `return` succeeds when sourced and fails when executed, so the `exit` is
  # the executed-directly branch -- shellcheck cannot see that.
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

main "$@"

#!/usr/bin/env bash
# tests/packages.sh -- regression tests for the 2026-09-21 audit, packages
# workstream (Brewfile, packages/*.list, git/husky/gem config, Neovim, app
# configs).
#
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

section "D1 — Brewfile"
t "D1.1" "no nonexistent arduino cask" \
  '! grep -q "^cask \"arduino\"" Brewfile'
t "D1.2" "no disabled/deprecated quicklook casks" \
  '! grep -qE "^cask \"(superslicer|quicklook-json|qlstephen|quicklookase)\"" Brewfile'
t "D1.3" "tailscale declared once, as the formula" \
  '[ "$(grep -cE "tailscale" Brewfile)" -eq 1 ] && grep -q "^brew \"tailscale\"" Brewfile'
t "D1.4" "sudo-touchid and its tap stay declared (user decision 2026-09-21: keep it)" \
  'grep -q "^tap \"artginzburg/tap\"" Brewfile && grep -q "^brew \"artginzburg/tap/sudo-touchid\"" Brewfile'
t "D1.5" "dead taps removed" \
  '! grep -qE "khanhas/tap|khanakia/vercelgate" Brewfile'
t "D1.6" "every remaining tap has a consumer" \
  '(for tp in $(grep -E "^tap " Brewfile | sed -E "s/^tap \"([^\"]+)\".*/\1/"); do grep -q "\"$tp/" Brewfile || exit 1; done)'
t "D1.7" "neovim and mise declared" \
  'grep -q "^brew \"neovim\"" Brewfile && grep -q "^brew \"mise\"" Brewfile'
t "D1.8" "keg-only readline and ssh-copy-id removed" \
  '! grep -qE "^brew \"(readline|ssh-copy-id)\"" Brewfile'
t "D1.9" "mackup, thefuck, fnm removed; pay-respects added" \
  '! grep -qE "^brew \"(mackup|thefuck|fnm)\"" Brewfile && grep -qE "^brew \"(timescam/tap/)?pay-respects\"" Brewfile'
t "D1.10" "tools the machine relies on are declared" \
  '(for f in rtk asc xcodegen atuin gitleaks age lazygit difftastic; do grep -q "\"$f\"" Brewfile || exit 1; done)'
t "D1.11" "claude-usage-tracker tap is declared or the cask removed" \
  '! grep -q claude-usage-tracker Brewfile || grep -q "hamed-elfayome/claude-usage" Brewfile'
t "D1.12" "brew bundle list parses the file" \
  'brew bundle list --file=Brewfile --all >/dev/null'

# The npm globals moved from packages/npm.list to config/mise/config.toml in
# the wave 2 migration; these three assertions followed them rather than being
# deleted, because what they protect -- the scoped qmd name, the 2022 leftovers
# staying gone, and the CLIs the agent instructions rely on staying declared --
# is a property of the list wherever it lives.
section "D2 — node CLIs and VS Code extensions"
t "D2.1" "qmd entry is the scoped package" \
  'grep -q "\"npm:@tobilu/qmd\"" config/mise/config.toml &&
   [ "$(grep -c "\"npm:qmd\"" config/mise/config.toml)" -eq 0 ]'
t "D2.2" "no stale 2022 globals" \
  '[ "$(grep -cE "\"npm:(detect-circular-deps|get-port-cli|underscore-cli|gtop|instant-markdown-d|grunt-cli|gulp-cli|yarn|corepack|npm)\"" config/mise/config.toml)" -eq 0 ]'
t "D2.3" "installed globals the instructions rely on are listed" \
  '_all=1
   for p in @openai/codex @llamaindex/liteparse @posthog/cli @stripe/cli @railway/cli resend-cli eas-cli @biomejs/biome typescript; do
     grep -q "\"npm:$p\"" config/mise/config.toml || _all=0
   done
   [ "$_all" = 1 ]'
t "D2.4" "headwind and duplicate tailwind extension removed" \
  '! grep -qE "heybourn.headwind|lightyen.tailwindcss-intellisense-twin" packages/code.list'
t "D2.5" "copilot dependency listed with copilot-chat" \
  '! grep -q github.copilot-chat packages/code.list || grep -q "^github.copilot$" packages/code.list'
# Not in the brief. Both lists now carry a comment header, and xargs does not
# strip comments, so the manual fallback the Brewfile documents would try to
# install packages called "#", "Global" and so on. The automated path in
# bin/dotfiles already skips comments; this covers the documented one.
t "D2.6" "the Brewfile documents no raw cat-into-xargs list install" \
  '! grep -qE "cat packages/[a-z]+\\.list *\\|" Brewfile'
# One, not two: the npm.list line went with the list itself in the wave 2
# migration, and Node CLIs are no longer installed from a file xargs reads.
t "D2.7" "the documented manual list install strips the comment header" \
  '[ "$(grep -cE "grep -v .\\^#. packages/[a-z]+\\.list" Brewfile)" -eq 1 ]'

section "D3 — git config"
t "D3.1" "no hardcoded /opt/homebrew gh path" \
  '! grep -q "/opt/homebrew/bin/gh" config/git/config'
t "D3.2" "github user moved out" \
  '! grep -qE "^\\s*user = STiXzoOR" config/git/config'
t "D3.3" "lastupdate state removed" \
  '! grep -q "lastupdate" config/git/config'
t "D3.4" "autocorrect prompts" \
  'grep -qE "autocorrect = prompt" config/git/config'
# Inverted from the brief. core.fsmonitor in the *stowed global* config
# spawns a detached fsmonitor--daemon per repository git touches, including
# every throwaway test repo: 105 daemons and load average 183 on this
# machine within an hour (see 35805ed). Enable it per large repo instead.
t "D3.5" "fsmonitor is not enabled globally" \
  '! grep -q "fsmonitor = true" config/git/config'
t "D3.6" "fsck on transfer" \
  'grep -q "fsckObjects = true" config/git/config'
t "D3.7" "ssh signing scaffold present, key in local" \
  'grep -q "format = ssh" config/git/config && grep -q "allowedSignersFile" config/git/config && ! grep -q "signingkey" config/git/config'
# Rewritten from the brief. The briefed form greps for the *absence* of
# `$(git config user.email)"`, which never occurs: a backslash sits between
# `)` and `"` both before and after the fix, so it passed against the very
# alias it was meant to catch. It also sat on the right of a pipe, so under
# pipefail a deleted alias would have read as a pass. Assert the quoting is
# present instead. Verified against 7320f8b:config/git/config: fails.
t "D3.8" "ld alias quotes the email" \
  'grep -qF -- "--author \\\"\$(git config user.email)\\\"" config/git/config'

section "D4 — Neovim only"
t "D4.1" "no setup_handlers" \
  '! grep -q setup_handlers config/nvim/lua/plugins/lsp.lua'
t "D4.2" "mason-org paths" \
  'grep -q "mason-org/mason.nvim" config/nvim/lua/plugins/lsp.lua && grep -q "mason-org/mason-lspconfig.nvim" config/nvim/lua/plugins/lsp.lua'
t "D4.3" "automatic_enable not automatic_installation" \
  '! grep -q automatic_installation config/nvim/lua/plugins/lsp.lua'
t "D4.4" "lazy-lock committed" \
  '[ -f config/nvim/lazy-lock.json ]'
t "D4.5" "vim config removed" \
  '[ ! -e runcom/.vimrc ] && [ ! -d runcom/.vim ]'
# Every XDG dir is redirected into the sandbox: this machine exports
# XDG_DATA_HOME, so setting HOME alone still lets nvim install its whole
# plugin tree into the real ~/.local/share. --clean keeps it offline and
# fast; the mason v2 API is asserted by D4.1-D4.3 instead.
t "D4.6" "every Neovim lua file compiles" \
  '! command -v nvim >/dev/null || { W=$(sandbox) && DF_NVIM="$ROOT_DIR/config/nvim" HOME="$W" XDG_DATA_HOME="$W/data" XDG_STATE_HOME="$W/state" XDG_CACHE_HOME="$W/cache" nvim --clean --headless --cmd "lua local bad=0 for _,f in ipairs(vim.fn.globpath(vim.env.DF_NVIM,[[**/*.lua]],false,true)) do if not loadfile(f) then bad=bad+1 end end vim.cmd([[cquit ]]..bad)"; }'

section "D5 — gemrc, husky, app configs and stray tracked files"
t "D5.1" "gem source is https rubygems" \
  'grep -q "https://rubygems.org" runcom/.gemrc && ! grep -q "rubyforge" runcom/.gemrc'
t "D5.2" "gemrc has no /usr/local binstub" \
  '! grep -q "/usr/local/bin" runcom/.gemrc'
t "D5.3" "husky init does not hardcode the prefix" \
  '! grep -q "/opt/homebrew/bin/brew" config/husky/init.sh'
t "D5.4" "vlcrc is minimal" \
  '[ "$(wc -l < apps/vlc/vlcrc)" -lt 80 ]'
t "D5.5" "vlc metadata network access off" \
  'grep -q "metadata-network-access=0" apps/vlc/vlcrc'
t "D5.6" "vlc plist untracked" \
  '[ -z "$(git ls-files apps/vlc/org.videolan.vlc.plist)" ]'
t "D5.7" "gitkraken template has no project id" \
  '! grep -q "47c2be4e" apps/gitkraken/profile.template'
t "D5.8" "pyc and karabiner backup untracked" \
  '[ -z "$(git ls-files config/thefuck config/karabiner/automatic_backups)" ]'
t "D5.9" "spicetify tree removed" \
  '[ ! -d config/spicetify ]'

finish

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
# Owner decision 2026-09-29: the App Store app is what is used. The formula's
# CLI talks to a daemon that never runs, so it is not declared; system/.alias
# points `tailscale` at the app's own binary instead (D6.9).
t "D1.3" "tailscale is the App Store app, not the formula" \
  '[ "$(code_of Brewfile | grep -cE "^brew \"tailscale\"")" -eq 0 ] && grep -q "^mas \"Tailscale\", id: 1475387142" Brewfile'
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
t "D1.9" "thefuck, fnm removed; pay-respects and mackup (copy-mode app settings) present" \
  '! grep -qE "^brew \"(thefuck|fnm)\"" Brewfile && grep -qE "^brew \"(timescam/tap/)?pay-respects\"" Brewfile && grep -qE "^brew \"mackup\"" Brewfile'
t "D1.10" "tools the machine relies on are declared" \
  '(for f in rtk asc xcodegen atuin gitleaks age lazygit difftastic starship; do grep -q "\"$f\"" Brewfile || exit 1; done)'
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

# hooksPath in the stowed global config disables .git/hooks in every other
# repo. `dotfiles hooks` sets it repo-locally instead.
t "D3.9" "no global core.hooksPath (it would disable .git/hooks in every repo)" \
  '[ "$(code_of config/git/config | grep -c "hooksPath")" -eq 0 ]'
t "D3.10" "the repo hook install still sets hooksPath repo-locally" \
  'grep -q "config core.hooksPath .githooks" bin/dotfiles'

section "D6 — new-Mac package changes (2026-09-29)"
# Every token and id below was checked against formulae.brew.sh and the iTunes
# lookup API on 2026-09-29; see the task report.
t "D6.1" "apps that no longer exist in the App Store are gone" \
  '[ "$(code_of Brewfile | grep -cE "^mas \"(LastPass|Messenger)\"")" -eq 0 ]'
t "D6.2" "dockutil and pup come from homebrew-core, and their taps are gone" \
  'grep -q "^brew \"dockutil\"" Brewfile && grep -q "^brew \"pup\"" Brewfile &&
   [ "$(code_of Brewfile | grep -cE "lotyp/formulae|datadog-labs/pack")" -eq 0 ]'
t "D6.3" "gnupg (mise node verification) and git (not the xcrun shim) are declared" \
  'grep -q "^brew \"gnupg\"" Brewfile && grep -q "^brew \"git\"" Brewfile'
t "D6.4" "runpodctl and its tap are declared, fully qualified" \
  'grep -q "^tap \"runpod/runpodctl\"" Brewfile && grep -q "^brew \"runpod/runpodctl/runpodctl\"" Brewfile'
t "D6.5" "the new casks are declared" '
  bad=0
  for c in chatgpt claude proton-mail proton-mail-bridge termius paragon-ntfs bambu-studio; do
    grep -q "^cask \"$c\"" Brewfile || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
# homebrew-cask disabled openemu on 2026-09-01 (fails Gatekeeper). A disabled
# cask hard-fails `brew bundle`, so it is documented rather than declared.
t "D6.6" "openemu is not declared as a cask (disabled upstream)" \
  '[ "$(code_of Brewfile | grep -c "^cask \"openemu\"")" -eq 0 ]'
t "D6.7" "the new App Store apps are declared by the names mas prints" '
  bad=0
  for e in "Xcode:497799835" "Tailscale:1475387142" "UTM:1538878817" "DaisyDisk:411643860" "Amphetamine:937984704" "Infuse:1136220934" "Canva:897446215" "Apple Configurator:1037126344"; do
    grep -q "^mas \"${e%%:*}\", id: ${e##*:}\$" Brewfile || bad=$((bad + 1))
  done
  [ "$bad" -eq 0 ]'
t "D6.8" "no package is declared twice" '
  dup=$(code_of Brewfile | grep -E "^(brew|cask|mas|tap) " | sed -E "s/^(brew|cask|tap) \"([^\"]+)\".*/\1 \2/; s/^mas \"[^\"]+\", id: ([0-9]+).*/mas \1/" | sort | uniq -d | grep -c .)
  [ "$dup" -eq 0 ]'
# Behavioural: source the real file in zsh with a stub app binary.
# _ts_alias <app-path> <path-dir> -- what `alias tailscale` prints after
# sourcing the real system/.alias in a clean zsh.
_ts_alias() {
  env -i HOME="$W" PATH="$2:/usr/bin:/bin" TAILSCALE_APP="$1" \
    zsh -f -c "source \"$ROOT_DIR/system/.alias\"; alias tailscale" 2>/dev/null
}
t "D6.9" "the tailscale alias points at the app binary when it exists and no tailscale is on PATH" \
  '! command -v zsh >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/empty" && printf "#!/bin/sh\n" >"$W/Tailscale" && chmod +x "$W/Tailscale" &&
     [ "$(_ts_alias "$W/Tailscale" "$W/empty")" = "tailscale=$W/Tailscale" ]
   }'
t "D6.10" "no tailscale alias when the app is absent" \
  '! command -v zsh >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/empty" && [ -z "$(_ts_alias "$W/missing" "$W/empty")" ]
   }'
t "D6.11" "no tailscale alias when a tailscale command is already on PATH" \
  '! command -v zsh >/dev/null 2>&1 || {
     W=$(sandbox) && mkdir -p "$W/bin" && printf "#!/bin/sh\n" >"$W/Tailscale" && chmod +x "$W/Tailscale" &&
     printf "#!/bin/sh\n" >"$W/bin/tailscale" && chmod +x "$W/bin/tailscale" &&
     [ -z "$(_ts_alias "$W/Tailscale" "$W/bin")" ]
   }'
t "D6.12" "the private package lists Task 1 reads are gitignored" \
  'git -c core.excludesFile=/dev/null check-ignore -q Brewfile.local && git -c core.excludesFile=/dev/null check-ignore -q packages/code.local.list'
t "D6.13" "the sideloaded islands-dark theme is not in the marketplace list" \
  '[ "$(code_of packages/code.list | grep -c "^bwya77.islands-dark")" -eq 0 ] && grep -q "islands-dark" packages/code.list'
# Checked in a scratch repo that holds only this .gitignore, so the owner's
# .git/info/exclude cannot answer for it, and .superpowers is a symlink there
# (as it is in a worktree): a pattern with a trailing slash does not match one.
t "D6.14" ".idea (a directory) and .superpowers (a directory or a symlink) are ignored at the repo level" \
  'W=$(sandbox) && git init -q "$W" && cp .gitignore "$W/.gitignore" && mkdir "$W/.idea" && ln -s "$W" "$W/.superpowers" &&
   git -C "$W" -c core.excludesFile=/dev/null check-ignore -q .idea/x && git -C "$W" -c core.excludesFile=/dev/null check-ignore -q .superpowers &&
   rm "$W/.superpowers" && mkdir "$W/.superpowers" && git -C "$W" -c core.excludesFile=/dev/null check-ignore -q .superpowers/x'

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

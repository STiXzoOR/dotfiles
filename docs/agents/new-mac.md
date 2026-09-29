# Setting up a new Mac

The order that works on a blank Apple-silicon Mac (verified against macOS
27.0.1 in a sandboxed trace; see `docs/superpowers/plans/2026-09-29-new-mac-readiness.md`).
Owner-specific items (which repos to push, which apps to reinstall by hand)
live in the owner's private notes, not here: this repo is public.

## Before you start (on the old Mac)

- Push every git repo you care about. A clone brings only what is on a remote.
- Export what the repo cannot carry:
  - `dotfiles secrets export <file>` (encrypted with `age -p`)
  - `dotfiles apps backup` (app settings, copy mode, into iCloud Drive; see [app-settings.md](app-settings.md))
  - database dumps
  - app-native exports (Raycast `.rayconfig`, Bartender, iStat Menus)
- Collect the gitignored files a clone will not bring:
  - `profiles/local.zsh` and `profiles/local.post.zsh`
  - `config/git/config.local`
  - `claude/*.local.list` and `codex/*.local.list`
  - `Brewfile.local` and `packages/code.local.list`
  - `macos/local.sh` (computer name, locale, languages, timezone; see `macos/local.sh.example`)
- Carry `~/.ssh` if you want to keep the same key. Otherwise the installer generates a new one, and you add it to GitHub.

## On the new Mac

1. **Setup Assistant.** Name the computer, sign in to your Apple Account, turn on FileVault, pick a Time Machine disk.
2. **Check the platform.** Run `sw_vers; /bin/bash --version; zsh --version`. The installer targets bash 3.2 and zsh 5.9.
3. **Put `~/.ssh` in place** if you carried it (`chmod 700 ~/.ssh`, `chmod 600` the private key).
4. **Sign in to the App Store.** The `mas` entries in the Brewfile need it.
5. **Grant Full Disk Access to your terminal** (System Settings, Privacy & Security). `dotfiles configure` needs it for the firewall, Remote Login and `systemsetup`; without it those steps report an error, and you re-run `dotfiles configure --defaults` after granting.
6. **Run the remote installer:**
   ```sh
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/STiXzoOR/dotfiles/main/remote-install.sh)"
   ```
   - It installs the Command Line Tools headlessly (newest label), clones to `~/.dotfiles`, and runs `dotfiles install`.
   - It is safe to re-run: an existing checkout is reused.
7. **Set Raycast's hotkey to Cmd-Space before `install --all`.** `configure` turns off Spotlight's Cmd-Space (and Finder search), so until Raycast owns the key nothing answers it. Raycast is a cask in the Brewfile; if it is not on the Mac yet, install it by hand (`brew install --cask raycast`), open it, and set the hotkey in its settings. Raycast's own hotkey is not scriptable.
8. **When `install` offers `install --all`, answer no the first time.**
   - Copy the gitignored files into `~/.dotfiles/`.
   - Then run `~/.dotfiles/bin/dotfiles install --all`, which works through this order:
     1. Prezto
     2. `link`
     3. mise and node
     4. packages
     5. fonts
     6. LaunchAgents
     7. Claude
     8. Codex
     9. `configure`
     10. hosts
   - It ends with a summary of any failed steps and exits non-zero if one failed. Fix what it lists and re-run the step (`dotfiles install --<step>`).
9. **Restore data:**
   - Copy your vault to `~/Vault`, then run `dotfiles install --claude` again so QMD registers and indexes it. The installer never creates an empty vault.
   - Restore app settings with `dotfiles apps restore --from <old-mac>` once the apps are installed and quit.
   - `dotfiles secrets import <file>`.
10. **Log in** to the CLIs and apps you use (gh, Claude Code, Codex, cloud CLIs, Tailscale, …). In Codex, run `/hooks` once and trust the plugin hooks.
11. **Record a defaults baseline:** `dotfiles baseline capture <macOS version>`, then `dotfiles baseline diff` against the previous one, to see which settings the new macOS dropped or renamed.
12. **Run `dotfiles doctor`.** It should report no errors.

## Two Macs

Until the app-settings sync work lands, do not re-run `dotfiles configure` on
the MacBook. Remote Login and the desktop power settings (restart after power
loss, no Power Nap, no disk sleep) are declared for the Mac mini and are not yet
gated by machine role, so a re-run would turn them on for a laptop too.

## Things that are manual on purpose

- Apps outside Homebrew and the App Store (Setapp and direct downloads).
- Per-app permissions macOS asks for on first launch (Accessibility, Input Monitoring, Screen Recording, system extensions such as Karabiner's).
- Keyboard modifier remaps and input sources (System Settings, Keyboard). They are stored per keyboard.
- The default browser (System Settings, Desktop & Dock). macOS asks for confirmation, so it cannot be scripted unattended.

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
- Make sure the private repo is pushed (`dotfiles private status`). It carries the gitignored files a clone does not bring: git identity, `profiles/local*.zsh`, the `*.local.list` files, `Brewfile.local`, `macos/local.sh`, the encrypted secrets export. See [two-mac-sync.md](two-mac-sync.md). Nothing is copied by hand.
- Carry `~/.ssh` if you want to keep the same key. Otherwise the installer generates a new one, and you add it to GitHub.

## On the new Mac

1. **Setup Assistant.** Name the computer, sign in to your Apple Account, turn on FileVault, pick a Time Machine disk.
2. **Check the platform.** Run `sw_vers; /bin/bash --version; zsh --version`. The installer targets bash 3.2 and zsh 5.9.
3. **Put `~/.ssh` in place** if you carried it (`chmod 700 ~/.ssh`, `chmod 600` the private key), or add the new key to GitHub when the installer generates one: the private repo clone needs GitHub access.
4. **Sign in to the App Store, and to Setapp.** The `mas` entries, Xcode included, need the App Store. Setapp needs its app opened once and signed in: that creates the catalogue `install --setapp` reads, and starts the agent it drives. Open Setapp after `--packages` has installed it if it is not there yet.
5. **Grant Full Disk Access to your terminal** (System Settings, Privacy & Security), then restart it. `dotfiles configure` needs it for the firewall, Remote Login and `systemsetup`.
6. **Run the remote installer:**
   ```sh
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/STiXzoOR/dotfiles/main/remote-install.sh)"
   ```
   - It installs the Command Line Tools headlessly (newest label), clones to `~/.dotfiles`, and runs `dotfiles install`.
   - It is safe to re-run: an existing checkout is reused.
7. **Pick the launcher.** The default is Tinycast, and then there is nothing to do before `install --all`: `--packages` installs it from its tap, `--link` stows `config/tinycast/settings.json`, and `configure` sets Cmd-Space and switches its settings file on (see [Launcher](#launcher)). A Mac that keeps Raycast says so first, in `macos/machine.local.sh` (`cp macos/machine.local.sh.example macos/machine.local.sh`, `DOTFILES_LAUNCHER="raycast"`). Until the launcher owns Cmd-Space nothing answers it, because `configure` turns off Spotlight's.
8. **When `install` offers `install --all`, answer yes.** It works through this order:
   1. Prezto (with its nested submodules)
   2. `private` (clones the private repo and links its gitignored files)
   3. `link`
   4. mise and node
   5. packages
   6. Setapp apps
   7. fonts
   8. LaunchAgents
   9. Claude
   10. Codex
   11. `configure`
   12. hosts

   It ends with a summary of any failed steps and exits non-zero if one failed. Fix what it lists and re-run the step (`dotfiles install --<step>`).
   - **Xcode.** When the Brewfile declares Xcode, `--packages` installs it first, accepts its licence and runs first launch, so no later brew step fails on "You have not agreed to the Xcode license". It needs sudo and the App Store sign-in from step 4.
   - **Setapp.** `--setapp` (between `--packages` and `--fonts`, so the Dock finds Spark Mail) installs the apps in `packages/setapp.list` and `packages/setapp.local.list`. Setapp has no CLI: each app is a `setapp://install` link, and Setapp shows its own "Install <App> from Setapp?" alert, so expect about one click per app (and sometimes an "Open <App>?" prompt). The installer prints `Setapp: click Install in the alert for <App>` and waits up to `SETAPP_TIMEOUT` seconds (default 300) for each app. Setapp's agent stays busy after a link install and rejects the next one, so the agent is restarted before every app and again if its log shows the rejection (3 tries per app). If Setapp is missing, never opened or not signed in, the step skips with one line and never fails `--all`: sign in, then run `dotfiles install --setapp`. When it installed a Dock app, run `dotfiles configure --dock`.
   - **Codex.** The curated plugins need a ChatGPT login. Run `codex login` before or after the installer; if it was not done, `--codex` skips those plugins with one line and the rest installs. Then run `dotfiles install --codex` again.
9. **Restore data:**
   - The vault arrives through iCloud Drive; `dotfiles install --claude` links `~/Vault` to it, waits for the download and registers the QMD collections. Re-run it once the vault has finished downloading. It never creates an empty vault. See [two-mac-sync.md](two-mac-sync.md).
   - Restore app settings with `dotfiles apps restore --from <old-mac>` once the apps are installed and quit.
   - `dotfiles secrets import <file>`.
10. **Install the Setapp apps by hand** (Spark Mail and the rest) from Setapp, then run `dotfiles configure --dock` so the Dock finds them.
11. **Log in** to the CLIs and apps you use (gh, Claude Code, cloud CLIs, Tailscale, ...). In Codex, run `/hooks` once and trust the plugin hooks.
12. **Record a defaults baseline:** `dotfiles baseline capture <macOS version>`, then `dotfiles baseline diff` against the previous one, to see which settings the new macOS dropped or renamed.
13. **Run `dotfiles doctor`.** It should report no errors.

## Launcher

`scripts/lib/machine.sh` gives `dotfiles_launcher`, which prints `tinycast` or
`raycast`: `DOTFILES_LAUNCHER` from the environment, else from
`macos/machine.local.sh`, else from `macos/local.sh`, else `tinycast`. Any other
value warns and means `tinycast`. Use `macos/machine.local.sh` (gitignored,
never linked or synced), because `macos/local.sh` is shared between the Macs
through the private repo.

After `install --all` on a Tinycast Mac:

1. **Open Tinycast once and grant Accessibility** (System Settings, Privacy & Security). Snippet expansion and the window commands need it. Grants can be asked for again if Tinycast's signing identity changes.
2. **Check the hotkey and the settings file.** `configure` writes Cmd-Space to the `hotkey.togglePalette` default and turns on `settingsFileEnabled`, then reads the hotkey back. Both are best-effort: upstream documents the hotkey JSON as not a stable format, and it is written only while Tinycast is not running (`configure` quits a running one). If `configure` reported a mismatch or skipped, set Cmd-Space in Tinycast > Settings > General and switch on Settings > Backup > Settings File by hand. The file is `~/.config/tinycast/settings.json`, stowed from `config/tinycast/`; Tinycast follows and keeps the symlink.
3. **Bring your Raycast setup over.** On the old Mac, Raycast > Settings > Extensions > Export Settings & Data (`.rayconfig`; the passphrase is in the login keychain item `Raycast/export_passphrase`). In Tinycast, use Import from Raycast and enter it. That brings settings, hotkeys, clipboard history, snippets and quicklinks; script commands have their own importer.
4. **Test the extensions that sign in with OAuth: GitHub, Linear, Slack, Zoom.** Tinycast runs Raycast extensions but not Raycast's OAuth proxy, so these may fail or need a token. Keep Raycast on the old Mac until they work.

Tinycast has no cloud sync. Its settings file travels through this repo; its
snippets and notes folders (`snippets.folder`, `notes.folder` in the settings
file) can point at a synced folder. Extension installs and the shortcuts outside
window management do not travel.

Stowing `config/tinycast` on a Raycast Mac is harmless: the file is only read
while Tinycast's settings file is switched on, which a Raycast Mac never does.

**Keeping Raycast:** `DOTFILES_LAUNCHER="raycast"` in `macos/machine.local.sh`.
`--packages` then installs the Raycast cask and neither taps nor trusts the
Tinycast tap; `configure` leaves Raycast's hotkey to Raycast.

**Switching a Raycast Mac to Tinycast:** remove the `raycast` line, run
`dotfiles install --packages` then `dotfiles configure --defaults`, do the steps
above, and once Tinycast works `brew uninstall --cask raycast`. `configure` warns
while Raycast.app is still installed, because it also claims Cmd-Space; it never
uninstalls anything.

**Risks, two lines:** Tinycast is young (first commit 2026-06-29, 0.x, about one
release a day) and has one main maintainer. Its build is self-signed rather than
notarised while its Developer ID move completes; the cask strips the quarantine flag.

**Blender.** The Brewfile installs the Blender cask (the `blender` MCP needs
Blender 5.1+). The add-on is manual: in Blender, Edit > Preferences > Add-ons >
Install from Disk, with `mcp-1.0.3.zip` from the v1.0.3 release of the official
MCP project at projects.blender.org (see [claude-bootstrap.md](claude-bootstrap.md)).

## Two Macs

`configure` detects the machine role: a Mac with no internal battery is a
desktop and gets Remote Login and the always-on power settings (restart after
power loss, no Power Nap, no disk sleep, no system sleep on AC); a laptop keeps
its own. Override with `DOTFILES_MACHINE_ROLE=desktop|laptop` in
`macos/local.sh`. Keeping both Macs in step (the private companion repo,
`dotfiles sync`, the vault in iCloud Drive) is covered in
[two-mac-sync.md](two-mac-sync.md).

## Things that are manual on purpose

- Apps outside Homebrew, the App Store and Setapp (direct downloads).
- Per-app permissions macOS asks for on first launch (Accessibility, Input Monitoring, Screen Recording, system extensions such as Karabiner's).
- Keyboard modifier remaps and input sources (System Settings, Keyboard). They are stored per keyboard.
- The default browser (System Settings, Desktop & Dock). macOS asks for confirmation, so it cannot be scripted unattended.

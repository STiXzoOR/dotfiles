# App settings (mackup, copy mode)

`dotfiles apps` backs up the settings of apps that nothing else in the dotfiles
manages, to a private folder in iCloud Drive, and restores them on another Mac.
It is a wrapper, `bin/dotfiles-apps`, around mackup 0.11 used in **copy mode
only**: `mackup backup` and `mackup restore`, never `mackup link`. The symlink
model (move the file into cloud storage, leave a link) is what clobbered
settings before; a copy can be wrong, but it cannot leave a dangling link.

```
dotfiles apps check                       overlap guard (also runs first in backup/restore)
dotfiles apps backup [--scheduled]        stage, validate, publish, rotate
dotfiles apps restore [--from <mac>] [<snapshot>]
dotfiles apps list                        snapshots of every Mac, plus local rescue copies
dotfiles apps undo                        put back the latest rescue copy
```

## The ownership rule

- The dotfiles own everything they **stow** (`runcom/` into `~/`, `config/` into
  `~/.config/`), **copy or link** from `apps/`, `claude/` and `codex/`, or
  **`defaults write`** from `macos/defaults*.sh`.
- mackup owns **only** the apps listed under `[applications_to_sync]` in
  `config/mackup/mackup.cfg`.
- `dotfiles apps check` enforces the rule instead of documenting it. It resolves
  every path each allowlisted app covers (`mackup show <app>`) and fails, naming
  the app and the path, if a path is or contains (or sits inside) a stow target
  or a `claude/`, `codex/` or `vscode` target, or any `apps/` target that is not marked as copied (see below). `backup` and `restore` run it first
  and refuse on overlap.
- **Defaults overlap is allowed.** A path that is the preferences plist (or
  container) of a domain `macos/defaults*.sh` writes, or an `apps/<name>/` target
  installed by a `macos/defaults-<name>.sh` that carries a `# dotfiles-apps: copies` marker line (terminal, vlc, warp only), is reported as one `info:` line per
  app. After `apps restore`, `dotfiles configure --defaults` re-applies the
  dotfiles' keys over the restored ones, so `restore` ends by printing that
  instruction whenever a restored app overlaps. Domains come from the same key
  extraction `dotfiles-baseline` uses. Stow overlap stays a hard failure.
- `check` fails closed: it also refuses when `dotfiles-baseline` fails or finds no
  domains, or when `runcom/` or `config/` hold nothing (an empty owned set would let
  everything through). It also fails on an empty allowlist (an empty list makes mackup back up
  every supported app), on an unknown app, on an allowlisted app with no entry
  in `config/mackup/processes.list` (`app|-` maps a CLI-only app that has no process), and when `apps/` gains a directory that is
  not in the maintained target list (`app_targets` in `bin/dotfiles-apps`; the
  install scripts compute those paths in shell variables, so there is nothing
  safe to parse). Add the new directory there.

## What is in the allowlist, and why

Setapp builds keep preferences in `<bundle-id>-setapp.plist`, which several of
mackup's built-in definitions miss, so those get a custom definition in
`config/mackup/applications/` (stowed to `~/.config/mackup/applications/`, which
is where mackup 0.11 looks; a config in `$HOME` or `$XDG_CONFIG_HOME/mackup/mackup.cfg`
is only a default, the wrapper always passes `-c`). Container apps are allowed:
reading a container file from an interactive shell raises no dialog. Credentials
in these files (aws, mkcert's root key, ngrok, Tunnelblick configs) go to iCloud;
that is the owner's decision.

| Allowlist entry | Covers |
| --- | --- |
| `adobe-camera-raw` | built-in: Application Support/Adobe/CameraRaw |
| `apple-music` | built-in: Music plists and Scripts |
| `bartender`, `cleanshot` | built-in: the Setapp and standard plist |
| `blender` | built-in: `~/.config/blender`, Application Support/Blender |
| `fish` | built-in: `~/.config/fish` |
| `flux` | built-in: `org.herf.Flux.plist` |
| `iina` | built-in: plist and input_conf |
| `magnet` | built-in: `com.crowdcafe.windowmagnet.plist` |
| `mail` | built-in: `com.apple.mail.plist` (defaults overlap) |
| `microsoft-remote-desktop` | built-in: the `com.microsoft.rdc.macos` container plist |
| `mkcert` | built-in: Application Support/mkcert (includes the root CA key) |
| `ngrok` | built-in: `~/.ngrok`, `~/.ngrok2` |
| `opencode` | built-in: `~/.config/opencode`, auth.json |
| `opera` | built-in: Opera plists and Application Support |
| `quicklook` | built-in: `~/Library/Quicklook` |
| `telegram_macos` | built-in: `ru.keepcoder.Telegram.plist` |
| `terminal` | built-in: `com.apple.Terminal.plist` (defaults overlap, `apps/terminal`) |
| `tunnelblick` | built-in: Tunnelblick Configurations |
| `vlc` | built-in: plists, Application Support, `org.videolan.vlc` (`apps/vlc` overlap) |
| `warp` | built-in: `~/.warp` (`apps/warp` overlap) |
| `zoom` | built-in: the `us.zoom.*` plists |
| `zoxide` | built-in: Application Support/zoxide |
| `aws-settings` | custom: `config` and `credentials` only (no `cli`, `sso` or `login`, which hold rotating tokens) |
| `illustrator-settings` | custom: the plist, `Adobe Illustrator 29 Settings`, `Application Support/Adobe/Adobe Illustrator 29`. The version is in the paths: update it with the app. Never OOBE |
| `photoshop-settings` | custom: the plist, `Adobe Photoshop 2025 Settings`, `Application Support/Adobe/Adobe Photoshop 2025`. Same version note. Never OOBE |
| `transmission-settings` | custom: the plist and `settings.json` (not `stats.json` or blocklists; defaults overlap) |
| `bambu-studio` | custom: plist, `BambuStudio.conf`, `BambuNetworkEngine.conf`, `printers`, `user` (not plugins, system, ota, cache or logs) |
| `claude-usage` | custom: `HamedElfayome.Claude-Usage.plist` |
| `cleanmymac-setapp` | custom: the `-setapp` plist |
| `codexbar` | custom: `com.steipete.codexbar.plist` |
| `daisydisk` | custom: the container preferences plist |
| `gitkraken-settings` | custom: `com.axosoft.gitkraken.plist` only (the built-in copies `~/.gitkraken`, where the dotfiles symlink the profile and theme, and a backup refuses symlinks) |
| `istat-menus-setapp` | custom: the three `com.bjango.istatmenus-setapp*.plist` |
| `keka` | custom: the container preferences plist |
| `openemu-settings` | custom: OpenEmu plist, key bindings, save states (not cores or the game library) |
| `paste-setapp` | custom: the `-setapp` plist |
| `pixelsnap2-setapp` | custom: the `-setapp` plist |
| `playcover` | custom: `io.playcover.PlayCover.plist` |
| `proxyman-setapp` | custom: the `-setapp` plist only (the built-in also copies certificate material) |
| `shottr` | custom: the container plist, and the Preferences plist for a non-sandboxed build |
| `spark-setapp` | custom: the `-setapp` plist |
| `supercharge-setapp` | custom: the `-setapp` plist |
| `vectormagic` | custom: both `com.vectormagic.*` plists |
| `xcode-settings` | custom: the built-in's paths minus FontAndColorThemes (the dotfiles symlink the Nord theme there) |

### Deliberately not added

- `bash`, `zsh`, `prezto`, `ruby`, `git`, `github-cli`, `mise`, `neovim`, `karabiner-elements`, `vscode`, `mackup`, `claude-code`, `codex`, `ssh`: stowed or installer-managed, a copy would replace the dotfiles' symlink.
- `macosx`: the whole `.GlobalPreferences` is risky across macOS versions; `configure` sets the wanted keys.
- `openemu`, `proxyman`: superseded by `openemu-settings` and `proxyman-setapp`.
- `brave`: restoring `Default/Preferences` without `Secure Preferences` trips Chromium's tracked-pref HMAC and Brave resets the settings; Brave Sync covers it.
- `illustrator`, `photoshop`: the built-ins cover only old versions and `Application Support/Adobe/OOBE`, which holds account state and can break Adobe sign-in; replaced by `illustrator-settings` and `photoshop-settings`.
- `aws`, `transmission`: the built-ins copy rotating caches, stats and blocklists; replaced by `aws-settings` and `transmission-settings`.
- Detecting links by grepping a script fails open, so detection is inverted: an `apps/<name>` target is soft only with the marker, and `check` fails a marked script that mentions `ln` (or `symbolic`) on any code line, so the marker cannot lie.
- `gitkraken`, `xcode`: replaced by `gitkraken-settings` and `xcode-settings` (the dotfiles symlink into them, above). Backup and restore also refuse any covered path, ancestor up to `$HOME`, or symlink below it that fully resolves (relative links, chains, `/var` vs `/private/var`, symlinked parents) into the dotfiles repo or the private repo, using one `perl` `realpath` pass. The guard fails closed: a missing `perl`, an unresolvable repo dir (the private repo is optional only when absent), an unresolvable path (link loop, missing target) or a malformed record refuses; paths pass NUL-separated, so a newline in a name cannot split a record.

To add an app: put its name under `[applications_to_sync]`, add a
`processes.list` line (`app|process name`, matched with `pgrep -x`), add a
custom definition if the built-in one misses a path, then run
`dotfiles apps check`.

## Backup: stage, validate, publish, rotate

1. Take a lock (`mkdir` of `~/.local/state/dotfiles/mackup/lock.d`; stale after one hour). Taking a stale lock over is guarded by a second `mkdir` marker (`lock.d.steal`, ignored after five minutes), and the age is checked again once it is held, so two runs that both see the same stale lock cannot delete each other's fresh one.
2. Refuse when a covered path is a symlink into the storage folder (the leftover
   of the old link mode); the message says how to replace it with a real copy.
3. `mackup -c <cfg> backup -f -v` into a local staging directory under
   `${XDG_STATE_HOME:-~/.local/state}/dotfiles/mackup/stage`. The wrapper writes
   the runtime config there from `config/mackup/mackup.cfg`, pointing `[storage]
   path` at the staging directory (mackup refuses paths outside `$HOME`).
4. Refuse when anything staged is a symlink, when a plist is zero bytes, fails
   `plutil -lint` or is not an XML or binary plist (`plutil -lint` alone accepts a
   file that just says `garbage`), when mackup reports a TCC denial (reported per app), or when
   nothing was staged at all. The previous snapshot is untouched in every case.
5. Copy the staging tree to `<store>/<machine>/snapshots/<UTC timestamp>` under a
   `.tmp-` name, verify it with `diff -r`, write a `MANIFEST` and verify the copy
   against it, rename it, write the snapshot name to
   `<store>/<machine>/latest` (a plain text file, no symlinks in iCloud), and keep
   the newest 14 snapshots per machine.

`<store>` is `~/Library/Mobile Documents/com~apple~CloudDocs/Mackup`
(`DOTFILES_APPS_STORE` overrides it). `<machine>` is `DOTFILES_MACHINE_NAME` or
`scutil --get LocalHostName`, reduced to `[A-Za-z0-9-]`. Each Mac writes only its
own folder, so two Macs never overwrite each other. iCloud Drive itself must
already be on; the tool never creates it.

The `MANIFEST` starts with a header line,
`# dotfiles-apps manifest v1 files=<N> sha256=<hash>`, then one line per file
(SHA-256, size, path). The header carries the file count and the SHA-256 of the
body, so a manifest that iCloud truncated or half-synced is refused before any
file is checked. Only the root `MANIFEST` is left out of the listing; an app file
named `MANIFEST` deeper in the tree is listed like any other, and a file in the
snapshot that the manifest does not list is refused.

iCloud Drive never syncs `.DS_Store`, so backup deletes them from the staging tree
before the manifest is written, and verification ignores them in both the
manifest and the tree (older snapshots that list one still verify).

**No credential scan.** Secret scanning covers only commits to the dotfiles repos (public and private). App backups and the vault are not scanned: that is the owner's decision, accepting the risk. A backup publishes after the staging, symlink, plist and manifest checks.

The **daily agent** (`launchagents/com.stixzoor.dotfiles-apps-backup.plist`,
installed by `dotfiles install --launchagents`) runs `backup --scheduled` at
12:30. It prints nothing on success and logs to `~/Library/Logs/dotfiles-apps.log`,
which moves to `dotfiles-apps.log.1` once it passes 256 KiB (`DOTFILES_APPS_LOG_MAX`),
so it never holds more than about twice that.
On a Mac with no `mackup` installed or no iCloud Drive it logs one line,
`skipped: <reason>`, and exits 0, so a Mac that is not set up yet does not fill
the log with failures. An interactive `backup` still errors in both cases.

## Suggestions for more apps

`dotfiles apps candidates` (read-only) lists installed apps that mackup supports
and that are neither allowlisted, under `[applications_to_ignore]` nor declined
in the private repo's `jev/apps-declined.list`, one `name<TAB>facts` line each.
`dotfiles sync` feeds it to the Jev `apps` point: see `docs/agents/jev.md`.
Adding an app is always by hand: the name under `[applications_to_sync]` and a
process line in `config/mackup/processes.list`, then `dotfiles apps check`.

## Restore and undo

There is no two-way sync. Copy mode is last-writer-wins, so pulling another
Mac's settings is a deliberate act: `dotfiles apps list`, then

```
dotfiles apps restore                   # this Mac's latest snapshot
dotfiles apps restore --from macbook    # the other Mac's latest
dotfiles apps restore --from macbook 20260929T123000Z
```

In order: refuse on overlap or a symlink into storage; `brctl download` the
snapshot and refuse while any `*.icloud` placeholder remains; validate the
snapshot and verify every file against its `MANIFEST` (iCloud can leave a
not-yet-downloaded file under its real name; a snapshot without a manifest, or
with a manifest whose header does not match its body, is refused); copy it to
staging and verify the staged copy against the manifest again, because mackup
restores from that copy and iCloud may have changed a file since the first
check; refuse while an allowlisted app is running (it lists them; quit them
first; besides the names in `processes.list` it also looks for `<name> Helper`, `<name> Helper (Renderer)` and `<name> Helper (GPU)`, which Electron and Chromium apps leave behind; list any other helper as an extra `app|process` line); take a rescue copy of the current local files (same stage and validate
path, except that a corrupt local plist is kept as it is instead of blocking the
restore, since that is often why you are restoring; stored locally under `~/.local/state/dotfiles/mackup/Mackup/rescue/`, never in
iCloud); `mackup restore -f`; confirm no restored path is a symlink; then
`killall cfprefsd` so the preferences daemon rereads from disk (cfprefsd caches
preferences in memory and may otherwise serve the old values, or write them back
over the restored file; an app that was already running can still overwrite them
when it quits, hence the refusal above). The flush happens
on every path after local files may have changed, including a failed
`mackup restore`; the message then points at `dotfiles apps undo`.

`dotfiles apps undo` restores the latest rescue copy. It takes a rescue copy of
what it replaces, so running it twice toggles between the two states and never
loses either.

## On a new Mac

Restoring is not part of `dotfiles install --all`; the install summary points at
it. Once iCloud Drive has synced and the apps are installed (and quit):

1. `dotfiles apps list` to see what each Mac has published.
2. `dotfiles apps restore --from <other-mac>` to take that Mac's settings. A
   fresh machine has nothing local to rescue, so the rescue copy is skipped.
3. Open the apps. From then on the daily agent publishes this Mac's own
   snapshots into its own folder.

## TCC notes

mackup reads `~/Library/Preferences` and the odd `~/Library/Application Support`
folder without a prompt. Files inside `~/Library/Containers/<bundle-id>` read
without one from an interactive shell on this setup, but a launchd job cannot
answer a prompt if macOS ever asks. A denial shows up in mackup's output as
`Operation not permitted` or `permission issue`; the wrapper reports it by app
and publishes nothing. Grant the terminal (or `/bin/bash` for the agent) Full Disk
Access, or take the app off the allowlist.

## Leftovers

The store may still hold the old link-mode layout (`Mackup/.gitkraken`,
`Mackup/Library`, ...). Only directories named `[A-Za-z0-9-]` that contain a
`snapshots/` folder count as machines; the legacy entries are never read, moved
or deleted.

`~/.mackup.cfg` on a machine from the old setup may be a dangling symlink into a
`runcom/.mackup.cfg` that no longer exists. mackup treats a dangling link as
absent and the wrapper always passes `-c`, so it is harmless; `rm ~/.mackup.cfg`
tidies it.

## Tests

`tests/apps.sh` is hermetic: a sandbox `HOME` with `XDG_CONFIG_HOME` inside it
(mackup refuses one outside `$HOME`), a sandbox `DOTFILES_APPS_STORE`, and stubs
for `mackup` (`tests/fixtures/mackup-stub`), `pgrep`, `killall`, `brctl`,
`scutil` and `plutil`. The shipped allowlist is also checked against a real
mackup when one is installed.

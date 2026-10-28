# macOS System Defaults

## Structure

- `macos/defaults.sh` — main system preferences (Finder, keyboard, trackpad, etc.)
- `macos/defaults-*.sh` — per-app settings (Safari, Chrome, Xcode, etc.)
- `macos/dock.sh` — Dock layout and configuration

## Applying

```bash
./bin/dotfiles configure --defaults    # System defaults
./bin/dotfiles configure --dock        # Dock layout
```

Changes require **logout or restart** to take full effect.

## Editing

Use `defaults write` commands in the appropriate script. Use `bin/plistbuddy` helper for plist edits. Group related settings in the per-app files (`defaults-safari.sh`, etc.).

## Personal values: `macos/local.sh`

This repo is public, so the machine name, languages, locale, measurement units
and timezone are not in `defaults.sh`. Copy `macos/local.sh.example` to
`macos/local.sh` (gitignored) and set any of:

| Variable                     | Effect                                                              |
| ---------------------------- | ------------------------------------------------------------------- |
| `DOTFILES_COMPUTER_NAME`     | ComputerName, HostName, LocalHostName and the SMB NetBIOS name       |
| `DOTFILES_LANGUAGES`         | `AppleLanguages`, space-separated                                   |
| `DOTFILES_LOCALE`            | `AppleLocale`                                                       |
| `DOTFILES_MEASUREMENT_UNITS` | `AppleMeasurementUnits` (`Centimeters` also turns metric units on)  |
| `DOTFILES_TIMEZONE`          | `systemsetup -settimezone`                                          |

`defaults.sh` sources the file when it exists, and each block runs only when its
variable is set: a machine without a local file keeps what it has.

## Security and power

The Security block needs **Full Disk Access for the terminal** running the
install (System Settings, Privacy & Security, Full Disk Access): without it
`systemsetup` and `socketfilterfw` change nothing, and the firewall setters
still exit 0. A notice is printed at the start of the block, and the firewall
state is read back afterwards; an unchanged state is an `error` naming Full Disk
Access. `State = 1` (on) and `State = 2` (block all incoming) both count as on.
Each failed read-back (firewall, stealth mode, and the remote access steps below) is added to
`DOTFILES_DEFAULTS_FAILURES`, and `dotfiles configure --defaults` then exits
non-zero instead of ending in a success banner. Revoke the grant when the
install is done.

Declared here: firewall on with stealth mode, restart after a
power failure, no Power Nap, no disk sleep, no wake-on-LAN, password required
immediately after sleep or the screen saver. `autorestart`,
`powernap`, `disksleep` and the AC-power sleep settings (`pmset -c sleep 0`, so the
system never sleeps and stays reachable over SSH, and `pmset -c displaysleep 10`)
are desktop-only: `scripts/lib/machine.sh` reads the
role (`desktop` when `pmset -g batt` shows no internal battery, else `laptop`;
`DOTFILES_MACHINE_ROLE` overrides) and on a laptop the script leaves those
settings untouched. Firewall, stealth mode,
wake-on-LAN off and the screen-lock password apply to both. Remote Login is not
role-gated any more: it belongs to remote access, below. See
[two-mac-sync.md](two-mac-sync.md). The screen-lock delay is set with
`sysadminctl -screenLock immediate -password -`, which prompts for the account
password; it runs only on a terminal without `DOTFILES_YES`, otherwise the
command is printed for you to run. `pmset standbydelay` is not written (Apple
silicon ignores it).

## Remote access

`macos/defaults-remote-access.sh` makes a Mac reachable from a phone over
Tailscale, safely: SSH with keys only plus macOS Screen Sharing, both answering
only on Tailscale addresses. Tailscale here is the Mac App Store app, which
cannot run Tailscale's own SSH server, so SSH is Apple's sshd (Remote Login).
Who on the tailnet may connect is the Tailscale policy's business.

**Opt-in.** `dotfiles_remote_access` (`scripts/lib/machine.sh`) prints `on` or
`off`: `DOTFILES_REMOTE_ACCESS` from the environment, else from
`macos/machine.local.sh` (per Mac; the shared `macos/local.sh` is not read), else
the role default, `on` for a desktop and `off` for a laptop. A bad value warns
and falls back to the role default. Off prints one skip line and changes
nothing; nothing here ever turns anything off. It runs inside
`dotfiles configure --defaults`, and alone with `dotfiles configure
--remote-access` (which also exits non-zero on a failed step).

When on, in this order, each step printing running/ok/error and each failure
counted in `DOTFILES_DEFAULTS_FAILURES`:

1. Firewall and stealth mode on, read back. The routine `dotfiles_firewall_on`
   lives in `scripts/lib/defaults-common.sh` and `defaults.sh` calls the same one.
2. Remote Login on. The state is read first and `systemsetup -setremotelogin -f on`
   only runs when it is off (the setter errors without Full Disk Access even when
   it is already on, and `-getremotelogin` itself needs Full Disk Access, so it is
   not trusted alone). The state counts as on if any of these says so:
   `systemsetup -getremotelogin`, `sudo launchctl print-disabled system` showing
   `"com.openssh.sshd" => enabled`, or sshd answering on `127.0.0.1:22`.
3. Only the running user may log in: the groups `com.apple.access_ssh` and
   `com.apple.access_screensharing` are created when missing, the user is added
   and membership is read back with `dseditgroup -o checkmember`. A group can
   exist with no members, which means nobody can log in, so membership is always
   ensured.
4. sshd hardening: `macos/remote-access/sshd.conf` is installed root:wheel 0644 as
   `/etc/ssh/sshd_config.d/010-dotfiles.conf` (it must sort before macOS's
   `100-macos.conf`; sshd keeps the first value it reads). Keys only, no
   keyboard-interactive, no root, Ed25519 and P-256 keys, no forwarding. Lockout
   guard: with no key line in `~/.ssh/authorized_keys` it is not installed and the
   step errors. After installing, `sudo /usr/sbin/sshd -t` must pass, else the file
   is removed again. macOS starts sshd per connection, so nothing is restarted.
5. pf: `macos/remote-access/pf.rules` goes to `/etc/pf.anchors/dotfiles.remote`
   and loads into the anchor `com.apple/900.dotfiles-remote`, which Apple's stock
   `anchor "com.apple/*"` already evaluates, so `/etc/pf.conf` is never edited. Ports
   22 and 5900 pass on loopback and from Tailscale's `100.64.0.0/10` and
   `fd7a:115c:a1e0::/48` and are blocked from everywhere else. The LaunchDaemon
   `com.stixzoor.dotfiles-pf-remote` (installed root:wheel 0644 in
   `/Library/LaunchDaemons`) re-asserts the rules at boot and every 300 seconds.
   It runs as root, so its plist references only `/bin`, `/sbin`, `/usr/bin` and
   `/etc/pf.anchors`, never anything in the repo or `$HOME` (tested). The rules
   are read back with `sudo pfctl -a com.apple/900.dotfiles-remote -sr`.
6. Screen Sharing cannot be switched on reliably from the CLI, so it is only
   checked (`nc -z 127.0.0.1 5900`) and an action line says what to click. If
   `/Library/Preferences/com.apple.VNCSettings.txt` exists, the legacy "VNC
   viewers may control screen with password" is on and gets a warning.

Installed files are compared with `cmp`; an identical one is "already set" and a
re-run changes nothing.

**Manual steps.**

- Before the first run, add your phone's public key to `~/.ssh/authorized_keys`.
- Turn on Screen Sharing: System Settings > General > Sharing > Screen Sharing,
  then (i) > Allow access for: Only these users. Turn the legacy VNC password
  option off if the run warns about it.
- After this, SSH or Screen Sharing to the Mac's LAN address no longer works: use
  its Tailscale name.

## Appearance

`AppleInterfaceStyle Dark` (dark mode) is set on purpose. Reduce transparency
is intentionally not set: it turned Liquid Glass fully tinted on a fresh Mac. A
Mac where an older configure already set it gets it reset (only when it reads
1; a failed reset is a warning with the System Settings step).
Nothing else in `defaults*.sh` changes system-wide appearance or accessibility
(no increase contrast, no reduce motion); the only `universalaccess` keys are
the Ctrl-scroll zoom ones.

macOS 26+ also gets dark icons (`AppleIconAppearanceTheme`, default
`RegularDark`) and Clear Liquid Glass. The glass key depends on the release:
26.x uses `NSGlassDiffusionSetting` (0 Clear, 1 Tinted; unset means Clear), 27+
uses `NSGlassTintAmount` (float, 0 Clear, about 0.86 Tinted) and never the other
key. Override with `DOTFILES_ICON_STYLE` (`{Regular,Clear,Tinted}{Automatic,Light,Dark}`)
and `DOTFILES_GLASS` (`clear` or `tinted`); an invalid value warns and falls back to the default in `macos/local.sh`. Each value is read
back; a mismatch is a counted failure. Icon and glass changes fully apply after a
logout.

## Real-tool quirks (macOS 27)

- Remote Login: the state is read first and `systemsetup -setremotelogin` only
  runs when it is off (the setter errors without Full Disk Access even when it
  is already on).
- `socketfilterfw --getstealthmode` prints "Firewall stealth mode is on" on 27
  and "Stealth mode enabled" before; both count as on.
- `defaults write` needs `-string` for the Tinycast hotkey: an untyped value
  starting with `{` is parsed as an old-style plist and rejected.
- `lsregister -kill` is gone; the Open With rebuild is `-r -apps local,system,user`
  then `-gc`, and a failure is a warning.
- `mdutil -i on /` only runs when `mdutil -s /` says indexing is off; a failure
  is a warning with the error text and the manual command.
- `print_result` in `defaults.sh` names the step on failure, so no `[error]`
  line is bare.

## Dock

`dock.sh` rebuilds the Dock with `dockutil`. `defaults.sh` ends by restarting
the Dock, and a relaunching Dock writes its old state back over edits made
meanwhile, so `dock.sh` first waits (up to `DOTFILES_DOCK_SETTLE_TIMEOUT`
seconds, default 10) for the Dock process and its list to settle, edits, restarts
the Dock, waits again, and checks `dockutil --list` for every app it added. If
entries are missing it rebuilds once more; if they are still missing it prints an
`error` naming them and `dotfiles configure --dock` exits non-zero. An app that
is not installed yet (Spark Mail under `/Applications/Setapp`, a cask not yet
installed) is a `skipped (not installed yet)` info line saying to re-run
`dotfiles configure --dock` after installing it: never a warning or a failure.

## Other things worth knowing

- The scripts reproduce the owner's live values (for example `KeyRepeat` 2,
  `AppleKeyboardUIMode` 3, Finder info panes written with `-dict-add`). Change a
  value in the script, not on the machine, or the next run reverts it.
- The Spotlight (Cmd-Space), Finder search and screenshot symbolic hotkeys are
  disabled because the launcher (Tinycast or Raycast) and Shottr replace them.
- The launcher block (`dotfiles_launcher`, see [new-mac.md](new-mac.md#launcher))
  runs after them. On a Tinycast Mac where `/Applications/Tinycast.app` is not
  installed yet it only prints "Tinycast is not installed yet; run
  `dotfiles configure --defaults` after `dotfiles install --packages`" (info, not
  a failure) and writes nothing. Otherwise it first reads the stored hotkey and switch
  (raw, through PlistBuddy: `defaults read` quotes and escapes strings) and does
  nothing when both are already right. Otherwise it says so, quits a running
  Tinycast (skipping with a warning if it will not quit), writes
  `hotkey.togglePalette` (Cmd-Space,
  `{"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}`) and
  `settingsFileEnabled` to `com.tinycast.app`, and reads both back the same way;
  a hotkey mismatch is an error and a switch mismatch a warning, neither
  ignored. The hotkey format is documented upstream as not stable, so this is
  best-effort with Tinycast > Settings > General as the
  fallback. If Raycast.app is still installed it warns once and names
  `brew uninstall --cask raycast`; nothing is uninstalled. On a Raycast Mac the
  block does nothing: Raycast's hotkey is set inside Raycast.
- Theme blocks (Xcode, GitKraken, Terminal.app, Warp) skip with a warning when
  the theme submodule has not been checked out
  (`git submodule update --init --recursive`), and never remove installed themes
  in that case.
- `defaults-warp.sh` installs `apps/warp/settings.toml` to `~/.warp/settings.toml`
  only when that file is absent or already identical (the `~` in the theme path
  is rendered to `$HOME`); an existing different file is left alone.
- `apps/vscode/keybindings.json` is linked next to `settings.json`.
- `defaults-codexbar.sh` runs `dotfiles codexbar apply`, which writes
  `apps/codexbar/settings.json` (provider data sources, menu-bar layout, the
  iCloud Sync switch) and quits and reopens CodexBar only when a preference
  differs. Its exit 2, CodexBar never having run here, is not a failure. The
  file carries no literal `defaults write`, so the baseline does not track it;
  `dotfiles codexbar diff` is its drift check.
- `config/atuin/config.toml` and `config/gh/config.yml` are stowed to
  `~/.config`. `gh`'s login lives in `hosts.yml`, which is gitignored: never
  commit it.
- The Xcode Simulator symlink and `AppleHighlightColor` were removed (Xcode 27
  no longer ships `Simulator.app` at that path; the colour has had no effect
  since Tahoe).
- Tests run the scripts against stub binaries (`tests/macos.sh`, section G). The
  three absolute-path binaries have seams: `DOTFILES_SOCKETFILTERFW`,
  `DOTFILES_ACTIVATE_SETTINGS`, `DOTFILES_LSREGISTER`.

## Failures versus warnings

Only real system settings (firewall, stealth mode, Remote Login, the appearance
read-backs) count toward `DOTFILES_DEFAULTS_FAILURES` and the exit status.
Things with a GUI fallback (the Tinycast hotkey, Spotlight indexing, the Open
With rebuild, the reduce-transparency reset) are warnings that name the fallback.

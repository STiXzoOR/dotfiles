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
Access. Revoke the grant when the install is done.

Declared here: firewall on with stealth mode, Remote Login on, restart after a
power failure, no Power Nap, no disk sleep, no wake-on-LAN, password required
immediately after sleep or the screen saver. The screen-lock delay is set with
`sysadminctl -screenLock immediate -password -`, which prompts for the account
password; it runs only on a terminal without `DOTFILES_YES`, otherwise the
command is printed for you to run. `pmset standbydelay` is not written (Apple
silicon ignores it).

## Other things worth knowing

- The scripts reproduce the owner's live values (for example `KeyRepeat` 2,
  `AppleKeyboardUIMode` 3, Finder info panes written with `-dict-add`). Change a
  value in the script, not on the machine, or the next run reverts it.
- The Spotlight (Cmd-Space), Finder search and screenshot symbolic hotkeys are
  disabled because Raycast and Shottr replace them. Set Raycast's own hotkey in
  Raycast.
- Theme blocks (Xcode, GitKraken, Terminal.app, Warp) skip with a warning when
  the theme submodule has not been checked out
  (`git submodule update --init --recursive`), and never remove installed themes
  in that case.
- `defaults-warp.sh` installs `apps/warp/settings.toml` to `~/.warp/settings.toml`
  only when that file is absent or already identical (the `~` in the theme path
  is rendered to `$HOME`); an existing different file is left alone.
- `apps/vscode/keybindings.json` is linked next to `settings.json`.
- `config/atuin/config.toml` and `config/gh/config.yml` are stowed to
  `~/.config`. `gh`'s login lives in `hosts.yml`, which is gitignored: never
  commit it.
- The Xcode Simulator symlink and `AppleHighlightColor` were removed (Xcode 27
  no longer ships `Simulator.app` at that path; the colour has had no effect
  since Tahoe).
- Tests run the scripts against stub binaries (`tests/macos.sh`, section G). The
  three absolute-path binaries have seams: `DOTFILES_SOCKETFILTERFW`,
  `DOTFILES_ACTIVATE_SETTINGS`, `DOTFILES_LSREGISTER`.

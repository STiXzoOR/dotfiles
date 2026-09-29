# Disabled LaunchAgents

Plists here are **not** installed by `dotfiles install --launchagents`,
which globs `launchagents/*.plist` only.

## History: the mackup agent

The hourly `com.stixzoor.mackup-auto.plist` lived here, disabled, because
of how Mackup's *link* mode works: it moves app config files into cloud
storage and replaces the originals with symlinks. A login that happens
before the cloud directory is mounted, or a sandboxed app that rewrites
its own config in place, can leave settings clobbered or pointing at
dangling links.

It has been replaced by `launchagents/com.stixzoor.dotfiles-apps-backup.plist`
(enabled, daily at 12:30), which runs `dotfiles-apps backup --scheduled`:
mackup 0.11 in **copy mode only** (`backup`/`restore`, never `link`), through
a stage, validate, publish and rotate pipeline. See
`docs/agents/app-settings.md`. The objection was always to the
symlink-into-cloud-storage model, not to the project's health: `lra/mackup`
is unarchived, released 0.11.2 on 2026-09-09, and every macOS 14/15/Tahoe
issue on its tracker is closed.

## Re-enabling an agent

1. **Copy** the plist up one directory; do not symlink it. Whether
   launchd on Tahoe accepts a symlinked plist, and how Background Task
   Management registers one, is unverified. Symlinked agents have
   historically confused Background Task Management, and a copy costs
   nothing.
2. Run `dotfiles install --launchagents`.
3. Expect a login-items notification from Background Task Management on
   first install.

`launchctl bootstrap gui/$UID <plist>` and `launchctl bootout
gui/$UID/<label>` are the commands to use. `load` and `unload` still
exist on macOS 26 but are deprecated and exit 0 on a broken plist without
doing anything. For an agent owned by an application, `SMAppService` is
the modern alternative to a hand-written plist.

Note: per-app configs that matter are tracked directly under `apps/`
(vscode, warp, gitkraken, terminal, vlc, xcode) and stay owned by the
dotfiles. Only apps nothing else manages are backed up by
`dotfiles apps`, from the allowlist in `config/mackup/mackup.cfg`.

# Disabled LaunchAgents

Plists here are **not** installed by `dotfiles install --launchagents`,
which globs `launchagents/*.plist` only.

## com.stixzoor.mackup-auto.plist

Disabled deliberately, because of how Mackup works rather than because of
the state of the project. Mackup *moves* app config files into cloud
storage and replaces the originals with symlinks. A login that happens
before the cloud directory is mounted, or a sandboxed app that rewrites
its own config in place, can leave settings clobbered or pointing at
dangling links. This agent ran hourly (`StartInterval 3600`), so any
breakage would recur silently.

For the record, so nobody re-derives this: `lra/mackup` is **not**
abandoned. It is unarchived, released 0.11.2 on 2026-09-09, and every
macOS 14/15/Tahoe issue on its tracker is closed. `Brewfile` still
installs it. The objection above is to the symlink-into-cloud-storage
model, not to the project's health.

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

Note: app settings currently have no automated backup. Per-app configs
that matter are tracked directly under `apps/` (vscode, warp, gitkraken,
terminal, vlc, xcode).

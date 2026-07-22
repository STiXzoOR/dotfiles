# Disabled LaunchAgents

Plists here are **not** installed by `dotfiles install --launchagents`,
which globs `launchagents/*.plist` only.

## com.stixzoor.mackup-auto.plist

Disabled deliberately. Mackup works by *moving* app config files into
cloud storage and replacing the originals with symlinks. Sandboxed apps
that rewrite their own config, or a login where the cloud directory is
not yet mounted, can leave settings clobbered or pointing at dangling
links. This agent ran hourly (`StartInterval 3600`), so any breakage
would recur silently.

To re-enable: move the plist back up one directory and run
`dotfiles install --launchagents`.

Note: app settings currently have no automated backup. Per-app configs
that matter are tracked directly under `apps/` (vscode, warp, gitkraken,
terminal, vlc, xcode).

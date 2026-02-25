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

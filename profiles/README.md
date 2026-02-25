# Machine Profiles

This directory contains machine-specific configurations that are loaded based on the hostname or a profile name.

## How It Works

1. Create a profile file named after your machine's hostname or a custom name:
   - `profiles/work.zsh` - Work machine profile
   - `profiles/personal.zsh` - Personal machine profile
   - `profiles/MacBook-Pro.zsh` - Hostname-based profile

2. Set the `DOTFILES_PROFILE` environment variable (optional):
   ```bash
   export DOTFILES_PROFILE="work"
   ```

3. If `DOTFILES_PROFILE` is not set, the system will try to load a profile matching your hostname.

## Profile Loading Order

1. `profiles/default.zsh` (always loaded if exists)
2. `profiles/$DOTFILES_PROFILE.zsh` OR `profiles/$(hostname -s).zsh`
3. `profiles/local.zsh` (always loaded if exists, for machine-specific overrides)

## Example Profile

```zsh
# profiles/work.zsh

# Work-specific Git configuration
export GIT_AUTHOR_EMAIL="you@company.com"
export GIT_COMMITTER_EMAIL="you@company.com"

# Work-specific aliases
alias vpn="open /Applications/CompanyVPN.app"
alias jira="open https://company.atlassian.net"

# Work proxy settings
# export http_proxy="http://proxy.company.com:8080"

# Additional PATH entries
prepend-path "$HOME/work/scripts"

# Load work-specific Brewfile
# export HOMEBREW_BUNDLE_FILE="$DOTFILES_DIR/profiles/Brewfile.work"
```

## Files

- `default.zsh` - Base settings loaded on all machines
- `personal.zsh` - Personal machine settings
- `work.zsh` - Work machine settings
- `local.zsh` - Machine-specific overrides (gitignored)

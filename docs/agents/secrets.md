# Secrets Management

Secrets are stored in macOS Keychain via `./bin/dotfiles secrets` (backed by `bin/dotfiles-secrets`).

## Commands

```bash
dotfiles secrets set <name>           # Store (prompts for value)
dotfiles secrets get <name>           # Retrieve
dotfiles secrets delete <name>        # Delete
dotfiles secrets list                 # List all
dotfiles secrets export <file>.enc    # Export encrypted (AES-256)
dotfiles secrets import <file>.enc    # Import from encrypted file
```

## Usage in Scripts

```bash
export GITHUB_TOKEN=$(dotfiles-secrets get github_token)
# or
eval "$(dotfiles-secrets env github_token GITHUB_TOKEN)"
```

Never commit secrets to git. Keychain requires user authentication to access.

# Secrets Management

Secrets are stored in macOS Keychain via `./bin/dotfiles secrets` (backed by `bin/dotfiles-secrets`).

## Commands

```bash
dotfiles secrets set <name>           # Store (prompts for value)
dotfiles secrets get <name>           # Retrieve
dotfiles secrets delete <name>        # Delete
dotfiles secrets list                 # List all
dotfiles secrets export [<file>.enc] # Export encrypted; no file = secrets.age in the private repo
dotfiles secrets import <file>.enc    # Import from encrypted file
```

## Usage in Scripts

```bash
export GITHUB_TOKEN=$(dotfiles-secrets get github_token)
# or
eval "$(dotfiles-secrets env github_token GITHUB_TOKEN)"
```

Never commit secrets to git. Keychain requires user authentication to access.

## Between two Macs

With the private companion repo (`dotfiles private`, see
[two-mac-sync.md](two-mac-sync.md)), `dotfiles secrets export` with no file
writes an age-encrypted `secrets.age` into it. That repo is the one git working
tree `export` will write into; any other is still refused. Commit and push the
file. On the other Mac, `dotfiles secrets import <private repo>/secrets.age`
asks for the passphrase, so `dotfiles sync` only reports that it changed and
never imports it.

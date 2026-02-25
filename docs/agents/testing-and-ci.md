# Testing & CI

## Test Suite

```bash
./bin/dotfiles test              # Run all tests
./bin/dotfiles test --verbose    # Detailed output
./bin/dotfiles test --quick      # Skip slow tests (startup timing)
```

**Categories**: syntax validation | cache generation | function tests (`prepend-path`, `get`, `dedup-pathvar`) | alias verification | environment variables (XDG) | shell startup time (<1000ms target) | file structure | Prezto config

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on push/PR:

1. Bash + zsh syntax validation
2. Shellcheck linting
3. Test suite
4. Brewfile validation

## Git Hooks

Install with `./bin/dotfiles hooks`. Pre-commit runs:

- Bash/zsh syntax validation
- Shellcheck
- Secret detection (prevents committing passwords/keys)

## Shellcheck

All shell scripts must pass shellcheck. Use `# shellcheck disable=SC####` with justification for intentional exceptions.

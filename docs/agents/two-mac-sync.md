# Keeping two Macs in sync

A MacBook and a Mac mini, both set up from this repo. Nothing here is one big
sync: each kind of state has the mechanism that suits it, and the parts that
cannot be synced safely are left manual on purpose.

## The layers

| What                                             | How it travels                                                              | Who moves it                       |
| ------------------------------------------------ | --------------------------------------------------------------------------- | ---------------------------------- |
| Dotfiles, scripts, lists, Brewfile, mise config  | This repo, through git                                                      | `dotfiles sync` (fast-forward)     |
| Personal gitignored files (git identity, private profiles, work marketplaces, extra packages, locale, private SSH hosts, the encrypted secrets export) | A private GitHub repo cloned to `~/.dotfiles-private`, symlinked into place | `dotfiles private`, `dotfiles sync` |
| Role-specific settings (Remote Login, power)     | `dotfiles_machine_role`: `desktop` or `laptop`, read from `pmset -g batt`    | `dotfiles configure` (each Mac decides for itself) |
| The Obsidian vault                               | iCloud Drive; `~/Vault` is a symlink to the vault folder there               | iCloud; `dotfiles vault migrate` once |
| App settings snapshots (mackup)                  | iCloud Drive, one folder per Mac (`dotfiles apps`, see [app-settings.md](app-settings.md)) | The daily backup agent; restore is deliberate |
| Raycast, VS Code, Warp, Paste, Brave, atuin      | Each app's own sync                                                          | The apps                           |
| Projects                                         | Their own git remotes                                                        | You                                |

## Roles

`scripts/lib/machine.sh` gives `dotfiles_machine_role` (`desktop` when
`pmset -g batt` shows no `InternalBattery`, otherwise `laptop`; `laptop` too when
pmset cannot answer, so a failed probe never forces anything) and
`dotfiles_machine_name` (`DOTFILES_MACHINE_NAME`, or the sanitised
`LocalHostName`; the app-settings snapshots use it too). Set
`DOTFILES_MACHINE_ROLE=desktop|laptop` to override.

`dotfiles configure --defaults` uses the role: Remote Login and the power
settings (`autorestart`, `powernap`, `disksleep`) are applied on the desktop only.
On a laptop the script leaves them exactly as they are; it never turns Remote
Login off. The firewall, stealth mode, wake-on-LAN off and the screen-lock
password apply to both.

The computer name is per Mac. `macos/local.sh` (shared through the private repo)
holds the locale, languages, units and timezone, not `DOTFILES_COMPUTER_NAME`;
set the name for one Mac with `DOTFILES_COMPUTER_NAME=<name> dotfiles configure
--defaults`, or keep a `macos/local.sh` that is not linked from the private repo.

## The private repo

`dotfiles private` manages a git repo at `DOTFILES_PRIVATE_DIR` (default
`~/.dotfiles-private`) whose paths mirror this repo's:

```
profiles/local.zsh  profiles/local.post.zsh  config/git/config.local
claude/*.local.list  codex/*.local.list  Brewfile.local  packages/code.local.list
macos/local.sh
ssh/config      private Host entries, linked as ~/.ssh/config.private
secrets.age     the encrypted secrets export
```

| Command                  | What it does                                                                                       |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| `dotfiles private init`  | On the first Mac: create the repo from the gitignored files that exist, leave symlinks behind, make the first commit. It does **not** create the GitHub repo: it prints `gh repo create <owner>/dotfiles-private --private --source <dir> --push` for you to run. |
| `dotfiles private clone` | On the second Mac: clone it (`DOTFILES_PRIVATE_REMOTE`, else the default SSH URL, then `gh repo clone` when `gh` is logged in). On failure it says what to set up (an SSH key on GitHub, or `gh auth login`) and returns non-zero. |
| `dotfiles private link`  | Symlink each private file to its path here. A different real file in the way is moved to `<name>.bak.<epoch>`; a correct link is left alone. Only the paths above are ever linked. `ssh/config` becomes `~/.ssh/config.private`, and `~/.ssh/config` gets `Include ~/.ssh/config.private` once, at the top (the public `Host *` defaults stay in `~/.ssh/config`). |
| `dotfiles private status`| Ahead/behind/uncommitted for the private repo, and any gitignored file here that is a real file, not a link: a local change that will not reach the other Mac. |
| `dotfiles install --private` | `clone` then `link`. It runs right before `link` in `install --all`; a failed clone is named in the summary and does not stop the run. |

`dotfiles secrets export` with no file argument writes `secrets.age` into the
private repo when it exists (the one git working tree export accepts). The file
is age-encrypted with a passphrase; commit and push it. On the other Mac,
`dotfiles secrets import <private repo>/secrets.age` asks for that passphrase, so
sync only reports the change and never imports.

## Daily flow

`dotfiles sync` (by hand) and the daily agent (`launchagents/com.stixzoor.dotfiles-sync.plist`,
09:30, loaded by `dotfiles install --launchagents`) do the same thing:

1. For the public repo, then the private repo: `git fetch`. Fast-forward only, and
   only when the tracked files are clean and the branch is behind. It never
   merges, rebases or stashes. It reports unpushed commits, behind-but-dirty and
   diverged states with the exact command to resolve each.
2. When anything moved: `stow --restow` for `runcom` and `config`, then
   `dotfiles private link`.
3. The actions the change calls for: `mise install` when `config/mise/` changed;
   `brew bundle install` when a Brewfile is not satisfied; `install --claude` or
   `--codex` when `claude/` or `codex/` changed. `secrets.age` changing is
   reported, never applied.
4. Drift: packages installed on this Mac (`brew leaves --installed-on-request`,
   casks, `mas list`, VS Code extensions) that neither the public nor the private
   lists declare, each with the line to add.

**Interactively**, step 3 asks (`confirm`) before each action. **Scheduled**
(`--scheduled`) it logs to `~/Library/Logs/dotfiles-sync.log`, never prompts,
never runs `sudo`, and never installs or upgrades anything (no `brew bundle`, no
`mise install`, no `install --claude`); it posts one notification only when
something needs you: pending actions, unpushed commits, divergence or drift. It
does run the read-only package queries of step 4, and it fast-forwards and
restows, because those are safe. Pending actions it found are remembered in
`~/.local/state/dotfiles/sync-pending` and repeated on later days until an
interactive run does them. Being offline is normal for a laptop: it is logged, not
notified.

## The vault in iCloud Drive

`~/Vault` stays the path everything uses (QMD, the hooks, the skills). It becomes a
symlink to `~/Library/Mobile Documents/com~apple~CloudDocs/Vault`
(`DOTFILES_VAULT_ICLOUD` overrides the target).

**On the Mac that has the vault**, quit Obsidian and run `dotfiles vault migrate`.
It refuses while Obsidian runs and when the iCloud folder already holds anything.
It `ditto`-copies the vault to a staging folder in iCloud Drive, compares the entry
count and a checksum listing of both trees, and only then renames the original to
`~/Vault.local-backup-<epoch>`, moves the copy into place and creates the symlink.
A failure at any step removes the staging folder and leaves `~/Vault` untouched.
It prints the undo: `rm ~/Vault && mv ~/Vault.local-backup-<epoch> ~/Vault`.
Afterwards, in Finder, right-click the `Vault` folder in iCloud Drive and choose
**Keep Downloaded**, so notes are never evicted.

**On the other Mac**, once iCloud has synced the folder, `dotfiles install --claude`
creates the `~/Vault` symlink when nothing is at `~/Vault` (a local vault is never
replaced). Before it writes templates or registers QMD collections it runs
`brctl download` on the vault and waits; while `.icloud` placeholders remain it
warns and indexes nothing, so QMD never indexes a half-downloaded vault. Run it
again when the download finishes.

## The second-Mac path

1. `git clone` this repo to `~/.dotfiles`, `git submodule update --init --recursive`.
2. `dotfiles install` (CLT, Homebrew, stow, SSH key). Add the key to GitHub.
3. `dotfiles install --all`. The private step clones `~/.dotfiles-private` and
   links its files before `link` runs, so the git identity and local lists are
   already in place. If the clone fails, fix SSH or `gh auth login` and run
   `dotfiles install --private`.
4. `dotfiles secrets import ~/.dotfiles-private/secrets.age` (asks for the passphrase).
5. Wait for iCloud to download the vault, then `dotfiles install --claude` again if it warned.
6. `dotfiles apps list`, then `dotfiles apps restore --from <the other Mac>`, apps quit.

## What never syncs automatically

- App preference files. Copy-mode snapshots are last-writer-wins, so a restore is
  always chosen (`dotfiles apps restore --from`).
- `secrets import` (it needs the age passphrase) and the Keychain itself.
- `brew bundle`, `mise install` and the Claude/Codex bootstrap: the scheduled run
  only reports them; an interactive `dotfiles sync` offers them.
- `sudo` settings: each Mac applies its own with `dotfiles configure`.
- Commits in the private repo. `dotfiles private status` and `dotfiles sync` say when
  something is uncommitted or unpushed; committing and pushing is yours.

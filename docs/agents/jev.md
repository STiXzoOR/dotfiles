# Jev guards

TypeSafe's Jev is a "System One" decision model: typed questions in, typed
answers with a probability and a confidence out, no free text
(`POST https://api.typesafe.ai/v1/systemone`). The dotfiles use it carefully:

- **Facts are computed in code.** Jev is only ever asked one narrow yes/no
  judgment about a fact the code has already found.
- **Every use point starts in shadow mode**: it decides and logs, and changes
  nothing, until the owner promotes it.
- **A secret never reaches it.** Only a masked shape does.
- **A Jev failure never blocks and never hides a deterministic finding.**

The client is `scripts/lib/jev.sh` (bash 3.2, curl, jq). The commands are
`dotfiles jev ...` (`bin/dotfiles-jev`). Tests: `tests/jev.sh`.

## Setup

```bash
dotfiles secrets set typesafe_api_key     # or export TYPESAFE_API_KEY
dotfiles jev status                       # shows the key source, never the key
```

With no key, or with `DOTFILES_JEV=off`, nothing is ever sent and the pre-commit
hook does exactly what it did before plus its deterministic checks.

## The use points

| Point | Where it runs | What it asks Jev (one `noul` each) |
| ----- | ------------- | ---------------------------------- |
| `privacy` | `.githooks/pre-commit`, per added hunk that no deterministic check caught | Does this added text reveal a person's name, a computer or host name, a client or private project name, a private network address or a home directory path? |
| `secrets` | pre-commit, `dotfiles apps backup` (staging tree), `dotfiles jev scan-vault` | Is this masked value a live credential rather than a placeholder, example, hash or identifier? Asked only for an *ambiguous* hit. |
| `drift` | `dotfiles sync`, after the deterministic drift report | One `choice` per undeclared item, one batched request per kind: see "Drift" below. |

The `secrets` point also runs in the private repo's pre-commit hook
(`dotfiles jev guard-private`, installed by `dotfiles private`) and in the daily
scheduled sync (the vault scan): see "Secrets leakage" below. Drift
classification, app-backup suggestions and the skip gate for the daily jobs come
in later tasks.

Each point is `off`, `shadow` (the default for every point) or `on`.

| Mode | Effect |
| ---- | ------ |
| `off` | Jev is not asked. Deterministic checks still run. |
| `shadow` | Jev is asked and the answer is logged as "shadow: would have ...". Nothing is blocked or warned. In the pre-commit hook the request runs in the background, so a commit is not delayed (and no job is started at all when there is no key). |
| `on` | The answer acts: block at high probability, warn in the middle band. Any Jev error fails open with a "not checked" warning. |

Set a mode with `dotfiles jev promote <point> [on|shadow|off]`. It is stored in
`$DOTFILES_PRIVATE_DIR/jev/jev.conf` (default `~/.dotfiles-private`), one
`point=mode` per line. Thresholds can be tuned there too:

```
privacy=shadow
secrets.block_p=0.9
secrets.block_conf=0.8
secrets.warn_p=0.5
```

`DOTFILES_JEV=off` in the environment overrides everything.

## Deterministic checks (always run, never fail open)

On the **added lines** of the staged diff:

- a value from the never-send list (always), or this Mac's LocalHostName / an
  SSH host alias / computer name when it holds a digit, a hyphen or a space
  (`my-mac-mini` and a two-word computer name yes, `mediashelf` no unless it is
  in the never-send list), as a whole word (case-insensitive). A blank computer
  name is ignored
- a home directory path with a real user name (`/Users/<name>` and other
  documentation placeholders are fine)
- a private network address: the 10, 172.16 to 31 and 192.168 ranges, and the
  Tailscale 100.64 to 127 range
- an email address that is not already public in `LICENSE.md` or `README.md`
  (reserved documentation, noreply and `git@github.com` addresses are fine)
- a credential: gitleaks, the credential formats in `.githooks/pre-commit`,
  and the exact value of any of your own Keychain secrets

A hit blocks the commit and prints `file:line` and a masked shape (never the
line itself). False alarm for one
commit: `DOTFILES_PRIVACY_OK=1 git commit ...` (privacy checks only, logged;
it never covers a credential). Fixtures under `tests/fixtures/jev/replay/` are
exempt because they are synthetic by construction.

Only Jev is optional. If the guard itself cannot run, the hook blocks.

## What is sent, and what never is

Per request the body is `{model, state, questions}`:

- `model` is pinned to `jev-1.13.0` (`DOTFILES_JEV_MODEL` overrides; never
  `jev-latest`, so thresholds stay stable).
- `state` is one added hunk (privacy) or one masked shape (secrets), capped
  well under the 32k-token limit, after redaction.
- `questions` is the fixed question above.

Redaction runs inside `jev_ask`, so no caller can skip it:

1. Lines holding the value of one of your own Keychain secrets are replaced
   with `[masked own-secret line=...]`, not even the first characters kept.
2. Lines matching gitleaks or the credential formats, or a high-entropy value
   assigned to a credential-named key, are replaced with a **masked shape**:
   the key or variable name, the value length, the character classes, the first
   three characters, and the line with the value replaced by `<VALUE>`. The
   value itself is never in it.
3. Every never-send value becomes a placeholder: the private never-send list
   (`<NEVER-SEND>`), `DOTFILES_COMPUTER_NAME`, `LocalHostName`, private SSH
   host aliases (public ones such as `github.com` are left alone) as `<HOST>`,
   and `$HOME` as `<HOME>`.

The **never-send list** is `$DOTFILES_PRIVATE_DIR/jev/never-send.list`, one
literal per line, `#` comments allowed. It lives in the private repo, never in
this one, and may not exist yet (it is optional).

Your own Keychain secrets are found through `profiles/local.zsh`: every
`dotfiles-secrets get <name>` in it names one. The values are read into memory
for the run and matched with `grep -F -f <(printf ...)`; they are never written
to disk, put on a command line or logged. A hit is reported by file and line
only, and a line that holds one is dropped whole (`[masked own-secret line]`),
never partly. A multi-line value is matched line by line, and never with an
empty pattern.

**Decision for the owner to veto:** the original brief asked for SHA-256 hashes
of these values. They are matched as plain in-memory strings instead, because a
substring match catches a value embedded in a longer string (a URL, a quoted
header), which hashing whole tokens misses, and the values leave memory exactly
as they would for hashing. An item that does not exist yet (a fresh Mac) is
silent: there is nothing to compare. If the Keychain is locked, or `security`
fails any other way, the own-secret check is skipped with one warning per run
that says which (`keychain locked (security exit 36)` or `keychain error
(security exit N)`); the commit is not failed. Values are read once per run, and
structural lines of a multi-line value (PEM `-----BEGIN ...-----` and
`-----END ...-----` armor, `Proc-Type`/`DEK-Info` headers, lines with no letter
or digit) are never patterns, so a public certificate in a file does not match.
In a plist, `<data>` values are base64-decoded before the check.

The API key goes to curl on stdin (`curl --config -`), never on the command
line and never in a file or the log.

TypeSafe states that requests are not used for training. Zero data retention is
available by arrangement only, and the default retention period is not stated
in what we could read: treat everything in `state` as leaving the Mac, which is
why the redaction and the deterministic checks exist.

## Drift

`dotfiles sync` already lists what is installed here and declared nowhere. The
`drift` point then asks Jev what each item is, so the list turns into a
suggestion per item. Three kinds, **one batched request per kind** (never one
per item):

| Kind | Facts computed in shell | Choices |
| ---- | ----------------------- | ------- |
| `pkg` | every undeclared brew formula, cask and App Store app: name, `brew desc`, whether another installed formula needs it (`brew uses --installed`), the date it was first seen undeclared | `public` (Brewfile), `private` (`Brewfile.local` or a private list), `ignore` (experiment, dependency, transient), `remove` |
| `defaults` | declared macOS defaults whose live value now differs from the baseline snapshot (`dotfiles-baseline changed`: domain, key, old, new, first-seen date) | `public` (`macos/defaults.sh`), `local-only` (`macos/local.sh`), `transient` |
| `config` | real (non-symlink) directories under `~/.config` that `config/<name>` in the repo does not manage: file count, size, first-seen date | `capture`, `ignore` |

`dotfiles-baseline changed [label]` compares the live value of every key the
`macos/*.sh` scripts declare with the snapshot for this macOS version. A key
the OS no longer honours is `diff`'s (BROKE), not a change. Only declared keys
can be compared: an undeclared change to some other key is invisible to it.

First-seen dates are kept in `~/.local/state/dotfiles/drift-first-seen`
(`key<TAB>date`), written the first time an item appears.

What `on` mode does with an answer:

- The **line offered is built by `dotfiles sync` from its own facts**, never
  taken from Jev. A suggestion for an item that was not in the facts is
  ignored.
- Interactively, `public`/`private`/`local-only` show the exact pre-filled line
  (`brew "jq"`, `cask "slack"`, `mas "Name", id: 111`, `defaults write <domain>
  <key> -bool true`) behind a `confirm`; yes appends it to that file. Nothing is
  committed. A defaults value that cannot be written safely (a string with a
  quote, a dollar sign or a backtick; a type `defaults read-type` cannot name)
  is shown for review by hand and never appended.
- `ignore` and `transient` are reported and write nothing.
- `remove` prints the `brew uninstall` command for you to run; sync never
  uninstalls anything. It is only offered when **two agreeing calls** said
  `remove`: the second call is asked about the removes alone, and a
  disagreement or a failed call drops the suggestion.
- `capture` prints the exact `mv ... && dotfiles link` command; sync never moves
  a directory under `$HOME`.
- Scheduled runs never prompt and never write: they add one line to the single
  notification ("Jev suggests N drift item(s) to classify") and the interactive
  `dotfiles sync` does the offering.

Offered means "not `pass`" at the point's thresholds (defaults: probability of
the chosen option >= 0.5 warn, >= 0.85 with confidence >= 0.8 block; both count
as offered). In `shadow` mode Jev is asked and the batch is logged as
`shadow: would have suggested N of M <kind> item(s)`, and sync prints and writes
nothing. At most `JEV_DRIFT_MAX_ITEMS` (40) items go in a request. Interactive
requests use a 6 second timeout instead of 2, because a batch is larger than
one hunk (`JEV_TIMEOUT` overrides); scheduled ones use the 10 second default. A
failed request is a quiet no-op: the deterministic drift report is complete
without it.

Item names such as brew formula names are sent; anything private goes through
the same redaction as every other request. `dotfiles jev drift <kind>` is the
command sync calls (facts on stdin as `key<TAB>facts`; it prints
`SUGGEST<TAB>key<TAB>choice<TAB>p<TAB>confidence` in `on` mode only). Replay
cases for this point come with the other Task 9 points.

## Limits

`--max-time` 2 seconds interactive, 10 scheduled (`JEV_SCHEDULED=1`);
`JEV_TIMEOUT` overrides. `JEV_TRIES` (2) with backoff, on 429 and 5xx only; a
timeout is not retried. `JEV_MAX_REQUESTS` (20 per run, 40 for a scan) caps the
calls, and a 401 or 403 stops all further calls in that run. `JEV_MAX_HUNKS`
(8) caps the hunks asked about per commit.

## Promoting a point: shadow to on

```bash
dotfiles jev log                  # what shadow mode would have done
dotfiles jev replay privacy       # real API on the labelled cases (run by hand)
dotfiles jev promote privacy      # shadow -> on
```

`tests/fixtures/jev/replay/<point>.jsonl` holds labelled cases (`id`, `label`
true when the text really is private or a live credential, `state`), all
synthetic. `replay` prints precision and recall per probability threshold, plus
the shipped rules. The shipped defaults are conservative: **block at p >= 0.85
with confidence >= 0.8, warn at p >= 0.5**. Jev documents no confidence for a
yes/no answer; when it is absent the probability of the side it leans to stands
in for it.

Calibration is contested. Jev's probabilities are not comparable across
question types, and the shipped cases are few and synthetic. Add your own
scrubbed cases before trusting the numbers, and re-run replay whenever the
pinned model changes.

## Secrets leakage

Detection stays local; Jev only sees a masked shape and only for ambiguous
hits.

- **Pre-commit (public repo)**: definite hits (gitleaks, a credential format,
  your own value) block. Ambiguous ones (a long random-looking value under a
  key named like `token`, `secret`, `password`, `api`; or a long random token)
  warn, and in `on` mode Jev can block them.
- **`dotfiles apps backup`**: the mackup staging tree is scanned before it is
  published to iCloud (`dotfiles jev scan-tree`). A hit keeps the snapshot local
  in the staging tree and reports it; nothing reaches iCloud. If the scan cannot
  run, the backup refuses.
- **Private repo (pre-commit)**: `dotfiles private` installs the hook, which runs
  `dotfiles jev guard-private`. It is the same secrets guard as the public
  repo's, with gitleaks included (the private repo has no other gitleaks hook):
  definite hits block, ambiguous ones warn and, in `on` mode, Jev can block them.
  `secrets.age` is the one exempt file. The privacy checks are not run, since
  names, hosts and addresses belong in that repo. A missing guard blocks the
  commit.
- **`dotfiles jev scan-vault [dir]`**: scans `Claude-Sessions/` in the vault
  (`DOTFILES_VAULT_DIR`, default `~/Vault`), which syncs through iCloud. It
  reports `file:line`, never edits or deletes, and exits 1 on a hit. The daily
  `dotfiles sync --scheduled` runs it once a day and notifies on hits (file and
  line only, never the value; report-only). Binary
  plists are converted with `plutil`, other binary files are read as their
  printable runs; only an unreadable file is reported as not scanned.

## The decision log

`${XDG_STATE_HOME:-~/.local/state}/dotfiles/jev.jsonl`, one JSON line per
decision: `ts`, `point`, `mode`, `questions`, `answers` (probability and
confidence), `latency_ms`, `action`. It never holds state text or a value.
`confidence` is the one the verdict used: Jev's own when it gave one, else the
derived one (the probability of the side it leans to), with
`confidence_derived: true`. `dotfiles jev log [-n N] [--raw]` reads it.

## Cost

$0.042 per million input tokens, output free. A commit is a few hundred tokens
per hunk: a few cents a month at most.

## Turning it off

- One shell or command: `DOTFILES_JEV=off`.
- Permanently: export it in `profiles/local.zsh`, or `dotfiles jev promote
  <point> off`, or delete the key (`dotfiles secrets delete typesafe_api_key`).
- Jev is never required for a commit to succeed.

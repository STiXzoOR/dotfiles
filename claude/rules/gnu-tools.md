This machine has GNU coreutils, GNU sed, GNU grep, GNU find and GNU awk
installed via Homebrew and put ahead of the system tools in PATH.

Use standard GNU syntax at an interactive prompt:

- `sed -i 's/old/new/'`, not the BSD `sed -i '' 's/old/new/'`
- `grep -P` for PCRE
- `find` supports `-printf` and `-regextype`
- `awk` is `gawk`, with the GNU extensions
- `date` supports `--date` and `+%s`

Do not reach for BSD workarounds there; they are not needed.

## The caveat that actually bites

**The GNU-first PATH exists only in the interactive shell.** It is set up by
the shell config in `system/`, which non-interactive contexts never source. In
those contexts you get the BSD tools in `/usr/bin`:

- `bash script.sh` and anything a script runs
- Claude Code hooks, launchd jobs and cron
- binaries resolved by `xargs` and by `find -exec`

Two P1 bugs in this repo came from forgetting that. A hook guarded a call with
`command -v timeout`, and `timeout` is not in a default macOS PATH at all. A
log rotation probed `stat -f%z` after `stat -c%s`, and to GNU `stat` the `-f`
flag means *filesystem*, so it printed filesystem info instead of failing and
the fallback was never reached.

In a non-interactive context, either:

- call the GNU binary by its own name (`gstat`, `gfind`, `gsed`, `gtimeout`)
  or by absolute path (`/opt/homebrew/bin/gtimeout`), with a fallback, or
- use a form both implementations accept (`wc -c < file` instead of `stat`).

---
alwaysApply: true
---

This machine has GNU coreutils, GNU sed, GNU grep, GNU find, and GNU awk installed via Homebrew and configured as the default commands in PATH.

Use standard GNU syntax for all shell commands:

- `sed -i 's/old/new/'` (not `sed -i '' 's/old/new/'` which is BSD)
- `grep -P` for PCRE is available
- `find` supports `-printf`, `-regextype`
- `awk` is `gawk` with full GNU extensions
- `date` supports `--date` and `+%s` formatting

Do NOT use workarounds for BSD tool limitations — they are not needed here.

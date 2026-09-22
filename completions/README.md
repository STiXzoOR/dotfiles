# completions

`runcom/.zshrc` puts this directory at the front of `fpath`, before Prezto runs
`compinit`, so anything dropped here wins over the completions a tool ships.

That is why nothing is vendored here any more. `completions/_fnm` used to be a
copy of `fnm completions --shell zsh` taken at some point in the past; it had
drifted 198 lines from the installed fnm and, because this directory comes
first, the stale copy was the one being used (2026-09-21 audit, shell#13).

Generate completions at install time instead, or let the tool's own
`site-functions` entry win by adding nothing here.

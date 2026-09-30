#!/usr/bin/env bash
#
# tests/repo.sh -- repository-level regression tests (2026-09-21 audit, WS-0):
# harness self-test, submodule removals, ignore rules.
#
# shellcheck disable=SC2016
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#############################################################################
section "H -- harness self-test"
#############################################################################
t "H.1" "sandbox returns a directory under TMPDIR" 'd=$(sandbox); [ -d "$d" ] && [[ "$d" != "$HOME"/* ]]'
t "H.2" "finish returns 1 when a test failed" '! ( source tests/lib.sh; t x "probe" false >/dev/null; finish >/dev/null )'
t "H.3" "finish returns 0 when every test passed" '( source tests/lib.sh; t x "probe" true >/dev/null; finish >/dev/null )'
t "H.4" "finish removes sandbox directories" 'd=$( source tests/lib.sh; x=$(sandbox); finish >/dev/null; printf "%s" "$x" ); [ -n "$d" ] && [ ! -e "$d" ]'
t "H.5" "run.sh runs every suite except lib.sh and itself, and fails if one fails" '
  W=$(sandbox); mkdir -p "$W/tests"; cp tests/lib.sh tests/run.sh "$W/tests/"
  printf "#!/usr/bin/env bash\necho GOOD\n" > "$W/tests/good.sh"
  printf "#!/usr/bin/env bash\necho BAD; exit 1\n" > "$W/tests/bad.sh"
  out=$(bash "$W/tests/run.sh" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && echo "$out" | grep -q GOOD && echo "$out" | grep -q "suites=2 failed_suites=1" && [ "$(printf "%s" "$out" | grep -c "=== tests/lib.sh")" -eq 0 ]'
t "H.6" "rand_chars prints exactly n characters of the class, and ends with SIGPIPE ignored" '
  out=$(/bin/bash -c "trap \"\" PIPE; source tests/lib.sh; rand_chars 36 A-Za-z0-9; rand_chars 200 0-9" 2>&1 </dev/null)
  [ "${#out}" -eq 236 ] && [ "$(printf "%s" "${out:0:36}" | LC_ALL=C tr -dc A-Za-z0-9 | wc -c)" -eq 36 ] &&
  [ "$(printf "%s" "${out:36}" | LC_ALL=C tr -dc 0-9 | wc -c)" -eq 200 ]'

# The device names are split so the scan below does not flag these fixtures.
_ur="/dev/u""random"; _zr="/dev/ze""ro"

# _run_fixture <secs> -- run.sh over a sandbox tests/ dir holding one good suite
# and one that hangs under ignored SIGPIPE (BSD tr never exits on EPIPE).
_run_fixture() {
  local W; W=$(sandbox); mkdir -p "$W/tests"; cp tests/lib.sh tests/run.sh "$W/tests/"
  printf "#!/usr/bin/env bash\necho GOOD\n" > "$W/tests/a_good.sh"
  printf "#!/usr/bin/env bash\nLC_ALL=C /usr/bin/tr -dc a <%s | /usr/bin/head -c 4\necho TOOFAR\n" "$_ur" > "$W/tests/b_hang.sh"
  printf "#!/usr/bin/env bash\necho LAST\n" > "$W/tests/c_last.sh"
  TEST_SUITE_TIMEOUT="$1" /bin/bash "$W/tests/run.sh" 2>&1
}
t "H.7" "run.sh kills a suite that hangs under ignored SIGPIPE, names it, and runs the next suite" '
  out=$(_run_fixture 3); rc=$?
  [ "$rc" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -c "^GOOD$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "^LAST$")" -eq 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "TIMEOUT.*b_hang.sh")" -ge 1 ] &&
  [ "$(printf "%s\n" "$out" | grep -c "suites=3 failed_suites=1")" -eq 1 ]'
t "H.8" "run.sh defaults the per-suite limit to 900 s and honours TEST_SUITE_TIMEOUT" \
  '[ "$(code_of tests/run.sh | grep -c "TEST_SUITE_TIMEOUT:-900")" -ge 1 ] && [ "$(code_of tests/run.sh | grep -c "TEST_SUITE_TIMEOUT:-600")" -eq 0 ]'
t "H.12" "run.sh prints each suite wall time on a result line" \
  'out=$(_run_fixture 3); [ "$(printf "%s\n" "$out" | grep -cE "^--- tests/a_good.sh: [0-9]+ s$")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -cE "^--- tests/c_last.sh: [0-9]+ s$")" -eq 1 ] && [ "$(printf "%s\n" "$out" | grep -cE -- "--- tests/b_hang.sh: [0-9]+ s$")" -eq 1 ]'
t "H.9" "run.sh ignores SIGPIPE before the suite loop" \
  '[ "$(_first_line "trap \"\" PIPE" tests/run.sh)" -gt 0 ] && [ "$(_first_line "trap \"\" PIPE" tests/run.sh)" -lt "$(_first_line "for f in" tests/run.sh)" ]'

# _unbounded_producers <files...> -- print file:line for every command that
# reads an endless source (/dev/urandom, /dev/zero, yes) with no bound on the
# same line: `head -c N` or dd count= before the device, or a bounded stage.
# Names are split so this file does not trip its own scan.
_unbounded_producers() {
  local dev="/dev/u""random|/dev/ze""ro" f
  for f in "$@"; do
    code_of "$f" | awk -v f="$f" -v dev="$dev" -v yes="(^|[|;&(][[:space:]]*)y""es([[:space:]]|$)" '
      $0 ~ dev && $0 !~ ("head -c [0-9]+ [^|]*(" dev ")") && $0 !~ /dd .*count=/ { print f ":" NR; next }
      $0 ~ yes { print f ":" NR }'
  done
}
t "H.10" "the unbounded-producer scan flags an endless read and passes a bounded one" '
  W=$(sandbox)
  printf "tr -dc a <$_ur | head -c 4\ncat $_zr | head -c 4\nyes | head -n 2\n" >"$W/bad.sh"
  printf "head -c 4096 $_ur | tr -dc a\ndd if=$_zr bs=1 count=4\n# yes | head\necho yes\n" >"$W/ok.sh"
  [ "$(_unbounded_producers "$W/bad.sh" | wc -l | tr -d " ")" -eq 3 ] && [ -z "$(_unbounded_producers "$W/ok.sh")" ]'
_shell_files() { # every tracked shell script under tests/, bin/, scripts/
  local f
  git ls-files tests bin scripts | while read -r f; do
    if [ "${f%.sh}" != "$f" ] || head -1 "$f" | grep -q "^#!.*sh"; then echo "$f"; fi
  done
}
t "H.11" "no tracked shell script under tests/, bin/ or scripts/ reads an endless source unbounded" '
  hits=$(_unbounded_producers $(_shell_files)); [ -z "$hits" ]'

# _grepq_hits <files...> -- print file:line for every pipeline that ends in a
# quiet grep after a producer that can write more than a pipe buffer: code_of,
# a bin/ script, git, find or cat. grep -q exits on the first match; the writer
# then dies of SIGPIPE, or fails with EPIPE where SIGPIPE is ignored (CI), and
# pipefail fails the pipeline -- only sometimes. Capture and grep -c instead.
# Only the stage list after the last ; && || $( or opening quote is examined,
# so `body=$(code_of x); printf "%s" "$body" | grep -q y` is not flagged.
_grepq_hits() {
  local f
  for f in "$@"; do
    code_of "$f" | awk -v f="$f" '
      { line = $0
        while (line ~ /\\$/ && (getline nxt) > 0) { sub(/\\$/, "", line); line = line " " nxt }
        gsub(/\|\|/, ";;", line)
        n = split(line, parts, /\|[[:space:]]*grep[[:space:]]+-q/)
        if (n < 2) next
        pre = parts[1]
        gsub(/.*(;|&&|\|\||\$\(|'"'"')[[:space:]]*/, "", pre)
        if (pre ~ /(code_of|bin\/|git |find |cat )/) print f ":" NR }'
  done
}
_gq="grep ""-q"
t "H.13" "the quiet-grep scan flags a big-producer pipeline and passes a captured one" '
  W=$(sandbox)
  printf "%s\n" "code_of bin/x | $_gq y" "git ls-files | ${_gq}x z" "code_of a \\" "  | ${_gq}E y" "cmd  | $_gq y" >"$W/bad.sh"
  printf "%s\n" "body=\$(code_of x); printf \"%s\" \"\$body\" | $_gq y" "# code_of x | $_gq y" "[ \"\$(code_of x | grep -c y)\" -ge 1 ]" >"$W/ok.sh"
  [ "$(_grepq_hits "$W/bad.sh" | wc -l | tr -d " ")" -eq 3 ] && [ -z "$(_grepq_hits "$W/ok.sh")" ]'
t "H.14" "no test pipes code_of, bin/, git, find or cat into grep -q" '
  hits=$(_grepq_hits tests/*.sh tests/fixtures/*.sh); [ -z "$hits" ]'

#############################################################################
section "R -- submodules that no longer earn their weight are gone"
#############################################################################
# Each was a shallow=true declaration that never took effect: hosts alone was
# 1.9 GB of history to reproduce a file StevenBlack publishes prebuilt.
i=0
for p in modules/stevenblack-hosts runcom/.vim/bundle/Vundle.vim modules/prezto-contrib config/spicetify/Themes; do
  i=$((i + 1))
  t "R.$i" "$p removed from .gitmodules, the tree and .git/modules" \
    "! git config -f .gitmodules --get submodule.$p.path >/dev/null 2>&1 && [ ! -e $p ] && [ ! -e .git/modules/$p ]"
done
t "R.5" "modules/zsh orphan (tracked files, no .gitmodules entry) is gone" \
  '[ -z "$(git ls-files modules/zsh)" ] && [ ! -e modules/zsh ]'
t "R.7" "a login shell prints no pmodload warnings for removed module dirs" \
  '[ "$(zsh -l -i -c exit 2>&1 | grep -c "Missing user module dir")" -eq 0 ]'
t "R.6" "every remaining submodule is declared shallow" \
  '! git config -f .gitmodules --get-regexp "submodule\..*\.path" | while read -r k _; do
     s=${k%.path}; [ "$(git config -f .gitmodules --get "$s.shallow")" = true ] || echo "$s"; done | grep -q .'

#############################################################################
section "G -- ignore rules for files that must never reach the public repo"
#############################################################################
i=0
for p in runcom/.zsh_history runcom/.zcompdump runcom/.zcompdump.zwc .envrc .env .direnv/x system/hosts.local macos/baselines/x.local.tsv .claude/worktrees/x; do
  i=$((i + 1))
  t "G.$i" "$p is ignored" "git check-ignore -q '$p'"
done
t "G.10" ".gitattributes normalises line endings" '[ -f .gitattributes ] && grep -q "text=auto" .gitattributes'
t "G.11" "bundled font binaries are marked -diff" 'grep -q "fonts/MesloHackNerd/\*.ttf -diff" .gitattributes'
t "G.12" "system/.env (a tracked shell file) is NOT ignored by the dotenv rule" '! git check-ignore -q system/.env'
t "G.13" ".gitignore carries no rules for paths this branch deleted (spicetify, runcom/.vim)" \
  '! grep -qE "spicetify|runcom/\.vim" .gitignore'
t "G.14" "profiles/local.post.zsh (machine-local post-prezto hook) is ignored" 'git check-ignore -q profiles/local.post.zsh'

finish

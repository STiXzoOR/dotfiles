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

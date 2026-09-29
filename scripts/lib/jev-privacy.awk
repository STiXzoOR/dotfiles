# scripts/lib/jev-privacy.awk -- the deterministic half of the privacy guard.
# Used by bin/dotfiles-jev. Nothing here calls Jev, and nothing here fails
# open: a hit blocks.
#
# Input: TSV rows "file<TAB>line<TAB>hunk<TAB>text", the ADDED lines of a
# staged diff. Variables (-v): nsf=<never-send map: "placeholder<TAB>literal">
# emf=<file of email addresses already public, lowercase, one per line>.
#
# Output: one TSV record per hit, "file<TAB>line<TAB>kind<TAB>text":
#   never-send   a value from the private never-send list (or this Mac's own
#                computer name / ssh alias) as a whole word
#   home-path    /Users/<name> for any name but a documentation placeholder
#   private-ip   a 10/8, 172.16/12, 192.168/16 or 100.64/10 (Tailscale) address
#   email        an address that is not already public in LICENSE/README and
#                not a reserved documentation or noreply one
#
# Portable awk (BSD awk 20200816 and gawk).

function has_word(low, lit,    s, off, pos, b, a) {
  s = low; off = 0
  while ((pos = index(s, lit)) > 0) {
    b = (off + pos > 1) ? substr(low, off + pos - 1, 1) : ""
    a = substr(low, off + pos + length(lit), 1)
    if (b !~ /[a-z0-9]/ && a !~ /[a-z0-9]/) return 1
    off += pos
    s = substr(s, pos + 1)
  }
  return 0
}

function private_ip(ip,    o, n) {
  n = split(ip, o, ".")
  if (n != 4) return 0
  if (o[1] + 0 > 255 || o[2] + 0 > 255 || o[3] + 0 > 255 || o[4] + 0 > 255) return 0
  if (o[1] == 10) return 1
  if (o[1] == 172 && o[2] >= 16 && o[2] <= 31) return 1
  if (o[1] == 192 && o[2] == 168) return 1
  if (o[1] == 100 && o[2] >= 64 && o[2] <= 127) return 1
  return 0
}

function reserved_email(addr,    dom) {
  dom = addr; sub(/^[^@]*@/, "", dom)
  if (addr in pub) return 1
  if (dom ~ /(^|\.)example\.(com|org|net)$/) return 1
  if (dom ~ /\.(invalid|test|example|localhost)$/) return 1
  if (dom == "users.noreply.github.com" || dom ~ /\.users\.noreply\.github\.com$/) return 1
  if (addr == "git@github.com" || addr == "noreply@anthropic.com" || addr == "noreply@github.com") return 1
  return 0
}

BEGIN {
  FS = "\t"
  while ((getline line < nsf) > 0) {
    split(line, f, "\t")
    if (f[2] != "") { lit[++nl] = tolower(f[2]); lk[nl] = (f[1] == "<NEVER-SEND>") ? "never-send list" : "host name" }
  }
  close(nsf)
  while ((getline line < emf) > 0) if (line != "") pub[tolower(line)] = 1
  close(emf)
  split("shared guest name user username you me example foo bar test admin home", okname, " ")
  for (i in okname) okn[okname[i]] = 1
}

{
  file = $1; ln = $2
  text = $0
  sub(/^[^\t]*\t[^\t]*\t[^\t]*\t/, "", text)
  low = tolower(text)
  seen = ""

  for (i = 1; i <= nl; i++) {
    if (has_word(low, lit[i])) { emit(file, ln, "never-send", lk[i] ": " substr(lit[i], 1, 2) "***"); break }
  }

  rest = text;
  while (match(rest, /\/Users\/[A-Za-z0-9._-]+/)) {
    nm = tolower(substr(rest, RSTART + 7, RLENGTH - 7))
    if (!(nm in okn)) { emit(file, ln, "home-path", "/Users/" substr(nm, 1, 1) "***"); break }
    rest = substr(rest, RSTART + RLENGTH)
  }

  rest = text; off = 0
  while (match(rest, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
    ip = substr(rest, RSTART, RLENGTH)
    b = (off + RSTART > 1) ? substr(text, off + RSTART - 1, 1) : ""
    a = substr(text, off + RSTART + RLENGTH, 1)
    if (b !~ /[A-Za-z0-9._]/ && a !~ /[0-9]/ && private_ip(ip)) { split(ip, oc, "."); emit(file, ln, "private-ip", oc[1] ".x.x.x"); break }
    off += RSTART + RLENGTH - 1
    rest = substr(rest, RSTART + RLENGTH)
  }

  rest = text
  while (match(rest, /[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/)) {
    addr = tolower(substr(rest, RSTART, RLENGTH))
    if (!reserved_email(addr)) { tld = addr; sub(/^.*\./, "", tld); emit(file, ln, "email", substr(addr, 1, 1) "***@***." tld); break }
    rest = substr(rest, RSTART + RLENGTH)
  }
}

# Never the offending line: only a masked shape is printed.
function emit(file, ln, kind, text) {
  printf "%s\t%s\t%s\t%s\n", file, ln, kind, text
}

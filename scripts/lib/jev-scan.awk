# scripts/lib/jev-scan.awk -- find secret-shaped lines. Used by jev.sh.
#
# Input: the text to scan. Variables (-v): mode=scan|redact, pf=<file of ERE
# credential patterns, one per line>, forced=",3,7," (line numbers something
# else, such as gitleaks, already flagged).
#
# A hit is "definite" (a known credential format) or "ambiguous" (a
# high-entropy value assigned to a credential-named key, or a long random
# token). Ambiguous hits are what the Jev secrets point is for.
#
# scan mode prints one TSV record per hit:
#   line  class  kind  name  len  classes  first3  masked-line
# redact mode prints every line, hits replaced by
#   [masked name=N len=L classes=C first3=F line=<line with the value replaced>]
# The value itself is never printed; only the shape is.
#
# Portable awk: BSD awk (macOS) and gawk. No gensub, no {n} in regex literals
# beyond what BSD awk 20200816 supports, single quotes as \047.

function entropy(s,    i, n, c, cnt, h, p) {
  n = length(s)
  for (c in cnt) delete cnt[c]
  for (i = 1; i <= n; i++) { c = substr(s, i, 1); cnt[c]++ }
  h = 0
  for (c in cnt) { p = cnt[c] / n; h -= p * log(p) / log(2) }
  return h
}

function distinct(s,    i, n, c, seen, d) {
  n = length(s); d = 0
  for (i = 1; i <= n; i++) { c = substr(s, i, 1); if (!(c in seen)) { seen[c] = 1; d++ } }
  return d
}

function classes(s,    o) {
  o = ""
  if (s ~ /[a-z]/) o = o "lower,"
  if (s ~ /[A-Z]/) o = o "upper,"
  if (s ~ /[0-9]/) o = o "digit,"
  if (s ~ /[^A-Za-z0-9]/) o = o "symbol,"
  sub(/,$/, "", o)
  return o
}

# The identifier before "=" or ":" that ends the text before a value.
function nameof(pre,    m) {
  if (match(pre, ASSIGN_END)) {
    m = substr(pre, RSTART, RLENGTH)
    sub(/[ \t]*[:=].*$/, "", m)
    return m
  }
  return "-"
}

# A value worth asking about: long, random-looking, not a placeholder or path.
function assigned_candidate(val,    lv) {
  if (length(val) < 16) return 0
  lv = tolower(val)
  if (lv ~ /example|your|xxxx|changeme|placeholder|dummy|sample|redacted|fake|^test|^none|^null|^true|^false/) return 0
  if (val ~ /^[\/.~]/) return 0
  if (distinct(val) < 8) return 0
  return entropy(val) >= 3.5
}

function standalone_candidate(tok, whole,    lw) {
  if (length(tok) < 40) return 0
  if (tok !~ /[A-Za-z]/ || tok !~ /[0-9]/) return 0
  if (tok ~ /^[0-9a-fA-F]+$/) return 0
  if (tok ~ /^\// || gsub(/\//, "/", tok) >= 2) return 0
  lw = tolower(tok)
  if (lw ~ /^sha(1|256|384|512)-/) return 0
  if (tolower(whole) ~ /integrity|checksum|sha256|sha512|shasum|hash|digest/) return 0
  return entropy(tok) >= 4.5
}

function short(s) { return length(s) > 200 ? substr(s, 1, 200) "..." : s }

BEGIN {
  ASSIGN_END = "[A-Za-z_][A-Za-z0-9_.-]*[ \t]*[:=][ \t]*[\"\047(]?$"
  ASSIGN = "[A-Za-z_][A-Za-z0-9_.-]*[ \t]*[:=][ \t]*[\"\047]?[A-Za-z0-9+/=_.~@-]+"
  STANDALONE = "[A-Za-z0-9+/=_-]+"
  np = 0
  while ((getline pat < pf) > 0) if (pat != "") p[++np] = pat
  close(pf)
}

{
  line = $0
  hit = 0; cls = ""; kind = ""; s = 0; l = 0
  for (i = 1; i <= np; i++) {
    if (match(line, p[i])) { hit = 1; cls = "definite"; kind = "pattern"; s = RSTART; l = RLENGTH; break }
  }
  if (!hit) {
    rest = line; off = 0
    while (match(rest, ASSIGN)) {
      seg = substr(rest, RSTART, RLENGTH); segpos = off + RSTART
      nm = seg; sub(/[ \t]*[:=].*$/, "", nm)
      val = seg; sub(/^[^:=]*[:=][ \t]*[\"\047]?/, "", val)
      if (tolower(nm) ~ /(key|token|secret|passw|pwd|credential|auth|api)/ && assigned_candidate(val)) {
        hit = 1; cls = "ambiguous"; kind = "entropy"; l = length(val); s = segpos + length(seg) - l
        break
      }
      off += RSTART + RLENGTH - 1
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  if (!hit) {
    rest = line; off = 0
    while (match(rest, STANDALONE)) {
      tok = substr(rest, RSTART, RLENGTH)
      if (standalone_candidate(tok, line)) {
        hit = 1; cls = "ambiguous"; kind = "token"; l = length(tok); s = off + RSTART
        break
      }
      off += RSTART + RLENGTH - 1
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  if (hit) {
    val = substr(line, s, l)
    nm = nameof(substr(line, 1, s - 1))
    masked = substr(line, 1, s - 1) "<VALUE>" substr(line, s + l)
    # A second credential on the same line must not survive in the shape.
    for (k = 0; k < 5; k++) {
      done = 1
      for (i = 1; i <= np; i++) {
        if (match(masked, p[i])) { masked = substr(masked, 1, RSTART - 1) "<VALUE>" substr(masked, RSTART + RLENGTH); done = 0 }
      }
      if (done) break
    }
    if (mode == "scan") {
      printf "%d\t%s\t%s\t%s\t%d\t%s\t%s\t%s\n", NR, cls, kind, nm, l, classes(val), substr(val, 1, 3), short(masked)
    } else {
      printf "[masked name=%s len=%d classes=%s first3=%s line=%s]\n", nm, l, classes(val), substr(val, 1, 3), short(masked)
    }
    next
  }
  if (index(forced, "," NR ",") > 0) {
    if (mode == "scan") printf "%d\tdefinite\tgitleaks\t-\t%d\t-\t-\t-\n", NR, length(line)
    else printf "[masked line flagged by a secret scanner len=%d]\n", length(line)
    next
  }
  if (mode != "scan") print line
}

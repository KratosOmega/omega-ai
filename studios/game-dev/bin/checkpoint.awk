# checkpoint.awk — a task's checkpoint in a feature ledger (spec 2026-10-26 §2),
# shared by studio-brief (checkpoint_part) and studio-overnight
# (checkpoint_of, ckpt_count). Input: the ledger's lines (`- <date> <text>`;
# others are skipped). Run under LC_ALL=C (byte semantics).
#   -v lb=<label>  T<n>, final-review, …: the lines `<label> checkpoint: …`
#                  written after the label's start count. T<n> starts at the
#                  last `T<n-1> complete` line, any other label at the last
#                  `T<k> complete` line; either, when there is none, at the
#                  last `base` line (else the ledger's start).
#   -v out=line    the newest such line as written, its text's escapes undone
#                  (`\n` a newline, `\\` a backslash, as directives_part) and
#                  cut to 600 bytes; nothing when there is none (default)
#   -v out=text    that text alone, its newlines as spaces, cut the same way
#   -v out=count   how many such lines there are (0 for none)
# A cut backs off to a UTF-8 character boundary and ends in "…".
function unesc(s,   o, i, c, n) {
  o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) {
      c = substr(s, i + 1, 1)
      if (c == "n") { o = o "\n"; i++; continue }
      if (c == "\\") { o = o "\\"; i++; continue }
      c = "\\"
    }
    o = o c
  }
  return o
}
function cut(s, n,   k) {
  if (length(s) <= n) return s
  k = n; while (k > 0 && (substr(s, k + 1, 1) in CONT)) k--
  return substr(s, 1, k) "\342\200\246"
}
BEGIN {
  for (i = 128; i < 192; i++) CONT[sprintf("%c", i)] = 1
  if (out == "") out = "line"
  p = "^T[0-9]+ complete "; if (lb ~ /^T[0-9]+$/) p = "^T" (substr(lb, 2) - 1) " complete "
  h = lb " checkpoint: "
}
$0 !~ /^- [0-9-]+ / { next }
{ t = $0; sub(/^- [0-9-]+ /, "", t) }
t ~ p { s = NR }
t ~ /^base / { b = NR }
index(t, h) == 1 { L[NR] = $0; T[NR] = substr(t, length(h) + 1) }
END {
  st = s ? s : b; k = 0; last = 0
  for (i = st + 1; i <= NR; i++) if (i in L) { k++; last = i }
  if (out == "count") { print k; exit }
  if (!last) exit
  x = unesc(T[last])
  if (out == "text") { gsub(/\n/, " ", x); print cut(x, 600); exit }
  print substr(L[last], 1, length(L[last]) - length(T[last])) cut(x, 600)
}

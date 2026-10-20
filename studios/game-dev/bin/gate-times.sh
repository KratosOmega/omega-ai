#!/bin/sh
# gate-times.sh — sourced by studio-gate (not run on its own): the gate.times
# writer (#71 R6, D9).
#
# gate_times_append FILE EPOCH WHO HOLD RC WAIT LANE CLASS UNIT — append one row and
# keep (D9) the newest 50 rows per who OR any row younger than 14 days, then the
# newest 20000 lines. The rewrite runs under the reclaim mutex (mutex_take /
# mutex_drop, defined by the sourcing script) when it can be had within ~5 s;
# otherwise unlocked, as before #71, so a release is never blocked.
gate_times_append() {
  _ga_f="$1"; shift
  _ga_row="$*"; _ga_now="$1"; _ga_i=0; _ga_lk=0
  while [ "$_ga_i" -lt 50 ]; do
    if mutex_take; then _ga_lk=1; break; fi
    _ga_i=$((_ga_i + 1)); sleep 0.1
  done
  { [ -f "$_ga_f" ] && cat "$_ga_f"; printf '%s\n' "$_ga_row"; } | awk -v now="$_ga_now" '
    { w[NR] = $2; t[NR] = $1 + 0; l[NR] = $0 }
    END {
      for (i = NR; i >= 1; i--) keep[i] = (++c[w[i]] <= 50) || (now - t[i] < 1209600)
      n = 0; for (i = NR; i >= 1; i--) if (keep[i] && ++n > 20000) keep[i] = 0
      for (i = 1; i <= NR; i++) if (keep[i]) print l[i]
    }' > "$_ga_f.$$" 2>/dev/null && mv -f "$_ga_f.$$" "$_ga_f" 2>/dev/null
  rm -f "$_ga_f.$$"
  [ "$_ga_lk" = 0 ] || mutex_drop
}

#!/bin/sh
# gate-times.sh — sourced by studio-gate (not run on its own): the gate.times
# writer (#71 R6, D9).
#
# gate_times_append FILE EPOCH WHO HOLD RC WAIT LANE CLASS UNIT — append one row and
# keep (D9) the newest 50 rows per who OR any row younger than 14 days, then the
# newest 20000 lines. The rewrite runs under the reclaim mutex (mutex_take /
# mutex_drop, defined by the sourcing script) when it can be had within ~5 s;
# otherwise unlocked, as before #71, so a release is never blocked.
#
# gate_times_holds FILE WHO — the only reader of gate.times rows for timing: the
# hold seconds (field 3) of WHO's well-formed rows, oldest first, one per line.
# Well-formed: exactly 8 fields, a numeric hold, rc 0 and lane `main` or
# `main:<reason>` (a short-slot run is niced and says nothing of a main run).
# Any other line (an old 4-field row, garbage) is skipped, never an error.
#
# gate_learned_cap FILE WHO FACTOR MAXMIN — a run cap in whole minutes learned
# from WHO's history, or nothing. It prints clamp(ceil(FACTOR x p95 / 60), 15,
# MAXMIN), p95 by nearest rank over the newest 50 gate_times_holds rows; MAXMIN
# wins over the 15 floor. Nothing is printed with fewer than 5 rows, FACTOR 0
# or not a whole number, or MAXMIN empty, 0 or not a whole number.
gate_times_holds() {
  awk -v w="$2" 'NF == 8 && $2 == w && $3 ~ /^[0-9]+$/ && $4 == 0 && ($6 == "main" || $6 ~ /^main:/) { print $3 + 0 }' "$1" 2>/dev/null
}
gate_learned_cap() {
  case "${3:-}" in ''|*[!0-9]*) return 0 ;; esac
  case "${4:-}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$3" -gt 0 ] && [ "$4" -gt 0 ] || return 0
  gate_times_holds "$1" "$2" | tail -n 50 | sort -n | awk -v f="$3" -v mx="$4" '
    { h[NR] = $1 }
    END {
      if (NR < 5) exit
      r = int((NR * 95 + 99) / 100)
      m = int((f * h[r] + 59) / 60)
      if (m < 15) m = 15
      if (m > mx) m = mx
      print m
    }'
}
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

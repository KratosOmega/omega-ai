#!/bin/sh
# overnight-cost.sh — a unit's cost when its session left no result event (a
# unit killed at its cap: spec §6, C3), sourced by studio-overnight. Needs
# SELF_DIR (model-prices.tsv beside it), RUN_DIR and STATE_ROOT.
#
# The naive cost of a stream-json transcript sums its assistant messages (a
# subagent's too), each message id once: input, cache-write (5-minute and
# 1-hour, from usage.cache_creation; all 5-minute when it has no split) and
# cache-read tokens from the message's first usage (exact); output tokens as the bytes of
# its content's text, thinking and tool_use input over all its events / 4
# (usage.output_tokens is a start-of-message snapshot); priced per message
# model from model-prices.tsv (USD per 1M tokens), an unknown model as the
# dearest row. A JSON field is matched by key name, as cost_of does (no jq).
# Calibration: a unit with a result event leaves one sample per model in its
# UNIT_DIR/cost.samples (cost_sample: model, naive, modelUsage costUSD). A
# model's factor is the median of costUSD / naive over the run's samples when
# it has 3 or more, else the factor cached in STATE_ROOT/.studio/cost.calib
# (`model factor epoch` lines; cost_calib_save rewrites it as a run ends; a
# factor stamped before model-prices.tsv last changed is ignored), else
# COST_DEFAULT_FACTOR.

# Byte collation: under a UTF-8 locale macOS sh matches [a-z] by collation (A-Y too).
unset LC_ALL; LC_COLLATE=C
# COST_DEFAULT_FACTOR — the factor of a model with no calibration (under 3
# result units in the run and no fresh cached factor). Phoenix unit 21
# (bat-bite-vfx, 2026-10-25) observed real / naive 1.25 for sonnet and 1.41
# for opus: the transcript redacts thinking text, so its output is undercounted.
# A run budget should err high, not low.
COST_DEFAULT_FACTOR=1.3
# cost_naive FILE — FILE's naive cost per model: `model<TAB>usd` lines (%.6f).
# Nothing when no assistant message carries a usage (empty, garbled, missing).
cost_naive() {
  LC_ALL=C awk -v prices="$SELF_DIR/model-prices.tsv" '
    # num(s, k) — the integer after the first "k": in s; 0 when none.
    function num(s, k,   v) {
      if (!match(s, "\"" k "\"[ \t]*:[ \t]*[0-9]+")) return 0
      v = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", v); return v + 0
    }
    # str(s, k) — the string after the first "k": in s; "" when none.
    function str(s, k,   v) {
      if (!match(s, "\"" k "\"[ \t]*:[ \t]*\"[^\"]*\"")) return ""
      v = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*"/, "", v); return substr(v, 1, length(v) - 1)
    }
    # obj(s) — s starts at or before an object: s up to the brace that closes that object.
    function obj(s,   i, L, c, d) {
      L = length(s); d = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "{") d++
        else if (c == "}" && --d == 0) return substr(s, 1, i)
      }
      return s
    }
    # cbytes(u) — u starts at the [ of message.content and holds no escaped
    # quote: the bytes of its blocks text and thinking strings and tool_use
    # input objects. CEND is the length of the array in u (0: it never closes).
    # Split at quotes, odd pieces are structure and even pieces string bodies.
    function cbytes(u,   np, P, k, j, c, d, b, pos, key, cap, nx, L) {
      np = split(u, P, "\""); d = 0; b = 0; pos = 0; key = ""; cap = 0; CEND = 0
      for (k = 1; k <= np; k++) {
        L = length(P[k])
        if (k % 2 == 0) {
          if (cap) b += L + 2
          else if (d == 2) {
            nx = P[k + 1]; sub(/^[ \t]*/, "", nx)
            if (substr(nx, 1, 1) == ":") key = P[k]
            else { if (key == "text" || key == "thinking") b += L; key = "" }
          }
          pos += L + 1; continue
        }
        for (j = 1; j <= L; j++) {
          c = substr(P[k], j, 1)
          if (c == "{" || c == "[") { d++; if (d == 3 && c == "{" && key == "input" && !cap) cap = 1 }
          if (cap) b++
          if (c == "}" || c == "]") {
            if (cap && d == 3) { cap = 0; key = "" }
            if (--d == 0) { CEND = pos + j; return b }
          } else if (c == "," && d == 2) key = ""
        }
        pos += L + 1
      }
      return b
    }
    # price(m) — the price row of model m: its own, the longest listed prefix
    # of it, else the dearest (input + output).
    function price(m,   r, p) {
      if (m in PI) return m
      r = ""; for (p in PI) if (index(m, p) == 1 && length(p) > length(r)) r = p
      return (r != "") ? r : top
    }
    BEGIN {
      while ((getline l < prices) > 0) {
        if (l ~ /^#/ || split(l, f, "\t") < 6) continue
        PI[f[1]] = f[2]; PO[f[1]] = f[3]; PW[f[1]] = f[4]; PH[f[1]] = f[5]; PR[f[1]] = f[6]
        if (top == "" || f[2] + f[3] > PI[top] + PO[top]) top = f[1]
      }
    }
    {
      if (!match($0, /"type"[ \t]*:[ \t]*"[^"]*"/)) next
      ty = substr($0, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*"/, "", ty); sub(/"$/, "", ty)
      if (ty != "assistant") next
      t = $0; gsub(/\\\\/, "__", t); gsub(/\\"/, "__", t)   # same length, no escaped quote
      if (!match(t, /"message"[ \t]*:[ \t]*\{/)) next
      t = substr(t, RSTART)
      id = str(t, "id"); if (id == "") id = "#" NR
      if (!(id in MOD)) { m = str(t, "model"); MOD[id] = (m == "") ? "unknown" : m; ids[++n] = id }
      rest = t
      if (match(t, /"content"[ \t]*:[ \t]*\[/)) {
        cs = RSTART + RLENGTH - 1
        OB[id] += cbytes(substr(t, cs))
        if (CEND) rest = substr(t, cs + CEND)
      }
      if (!(id in IN) && match(rest, /"usage"[ \t]*:[ \t]*\{/)) {
        u = obj(substr(rest, RSTART))
        IN[id] = num(u, "input_tokens"); CR[id] = num(u, "cache_read_input_tokens")
        CW[id] = num(u, "ephemeral_5m_input_tokens"); CH[id] = num(u, "ephemeral_1h_input_tokens")
        if (CW[id] + CH[id] == 0) CW[id] = num(u, "cache_creation_input_tokens")
        nu++
      }
    }
    END {
      if (!nu || top == "") exit
      for (i = 1; i <= n; i++) {
        id = ids[i]; m = MOD[id]; p = price(m)
        C[m] += (IN[id] * PI[p] + CW[id] * PW[p] + CH[id] * PH[p] + CR[id] * PR[p] + OB[id] / 4 * PO[p]) / 1000000
      }
      for (m in C) printf "%s\t%.6f\n", m, C[m]
    }' "$1" 2>/dev/null | sort
}
# cost_usage FILE — per model of the last result event that has modelUsage:
# `model<TAB>costUSD` lines. Nothing when there is none.
cost_usage() {
  LC_ALL=C awk '
    /"type"[ \t]*:[ \t]*"result"/ && /"modelUsage"[ \t]*:[ \t]*\{/ { last = $0 }
    END {
      if (last == "") exit
      match(last, /"modelUsage"[ \t]*:[ \t]*\{/); s = substr(last, RSTART + RLENGTH)
      while (match(s, /^[ \t,]*"[^"]*"[ \t]*:[ \t]*\{[^{}]*\}/)) {
        o = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        m = o; sub(/^[ \t,]*"/, "", m); sub(/".*/, "", m)
        if (!match(o, /"costUSD"[ \t]*:[ \t]*[0-9][0-9.eE+-]*/)) continue
        v = substr(o, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", v)
        printf "%s\t%s\n", m, v
      }
    }' "$1" 2>/dev/null
}
# cost_sample FILE — a result unit's calibration samples: `model<TAB>naive<TAB>costUSD`
# for each model with both a naive cost above 0 and a modelUsage cost.
cost_sample() {
  { cost_naive "$1"; echo --; cost_usage "$1"; } | LC_ALL=C awk -F'\t' '
    $0 == "--" { u = 1; next }
    !u { nv[$1] = $2; next }
    ($1 in nv) && nv[$1] > 0 { printf "%s\t%s\t%s\n", $1, nv[$1], $2 }'
}
# cost_run_factors — this run's factors: `model<TAB>median` for each model with
# 3 or more samples in the run's cost.samples files (every lane's, the final step's).
cost_run_factors() {
  cat "$RUN_DIR/cost.samples" "$RUN_DIR"/lanes/*/cost.samples "$RUN_DIR/final/cost.samples" 2>/dev/null \
    | LC_ALL=C awk -F'\t' '
      NF >= 3 && $2 + 0 > 0 && $3 ~ /^[0-9]/ { F[$1, ++N[$1]] = $3 / $2 }
      END {
        for (m in N) {
          n = N[m]; if (n < 3) continue
          for (i = 1; i <= n; i++) t[i] = F[m, i]
          for (i = 2; i <= n; i++) { v = t[i]; for (j = i - 1; j >= 1 && t[j] > v; j--) t[j + 1] = t[j]; t[j + 1] = v }
          printf "%s\t%.6g\n", m, (n % 2) ? t[(n + 1) / 2] : (t[n / 2] + t[n / 2 + 1]) / 2
        }
      }'
}
# cost_calibration — the factor per model: `model<TAB>factor`, this run's
# (cost_run_factors), else the cached one unless its epoch is older than
# model-prices.tsv (a price change voids it). A model not listed takes
# COST_DEFAULT_FACTOR.
cost_calibration() {
  _ocs_m="$(stat -c %Y "$SELF_DIR/model-prices.tsv" 2>/dev/null || stat -f %m "$SELF_DIR/model-prices.tsv" 2>/dev/null)"
  { cost_run_factors; echo --; cat "$STATE_ROOT/.studio/cost.calib" 2>/dev/null; } | LC_ALL=C awk -v mt="${_ocs_m:-0}" '
    $0 == "--" { c = 1; next }
    !c { split($0, f, "\t"); seen[f[1]] = 1; print; next }
    NF >= 3 && !($1 in seen) && $2 ~ /^[0-9.]+$/ && $2 + 0 > 0 && $3 ~ /^[0-9]+$/ && $3 + 0 >= mt + 0 { seen[$1] = 1; printf "%s\t%s\n", $1, $2 }'
}
# cost_calib_save — after a run: when it has a factor (3+ samples of a model),
# rewrite STATE_ROOT/.studio/cost.calib with this run's factors (stamped now)
# and the cached lines of every other model. A run with none leaves it as is.
cost_calib_save() {
  _ocs_n="$(cost_run_factors)"; [ -n "$_ocs_n" ] || return 0
  _ocs_f="$STATE_ROOT/.studio/cost.calib"
  { printf '%s\n' "$_ocs_n"; echo --; cat "$_ocs_f" 2>/dev/null; } | LC_ALL=C awk -v now="$(date +%s)" '
    $0 == "--" { c = 1; next }
    !c { split($0, f, "\t"); seen[f[1]] = 1; print f[1], f[2], now; next }
    NF >= 2 && !($1 in seen) { print }' > "$_ocs_f.$$" 2>/dev/null \
    && mv -f "$_ocs_f.$$" "$_ocs_f" 2>/dev/null || rm -f "$_ocs_f.$$"
  return 0
}
# cost_estimate FILE MINUTES — the estimated USD (%.4f, never empty) of a unit
# whose transcript FILE has no result event: its calibrated naive cost; with
# no usage in it, MINUTES x the median $/min of the run's result rows in
# units.tsv (column 8 `result`, or an old 7-column row with a numeric cost;
# rows of 0 minutes left out), else MINUTES x 0.50.
cost_estimate() {
  _ocs_e="$({ cost_calibration; echo --; cost_naive "$1"; } | LC_ALL=C awk -F'\t' -v dflt="$COST_DEFAULT_FACTOR" '
    $0 == "--" { n = 1; next }
    !n { f[$1] = $2; next }
    { s += $2 * (($1 in f) ? f[$1] : dflt) }
    END { if (s > 0) printf "%.4f\n", s }')"
  if [ -z "$_ocs_e" ]; then
    _ocs_e="$(cat "$RUN_DIR/units.tsv" "$RUN_DIR"/lanes/*/units.tsv "$RUN_DIR/final/units.tsv" 2>/dev/null \
      | LC_ALL=C awk -F'\t' -v min="$2" '
        ($8 == "result" || NF <= 7) && $4 ~ /^[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/ && $5 + 0 > 0 { r[++n] = $4 / $5 }
        END {
          rate = 0.50
          if (n) {
            for (i = 2; i <= n; i++) { v = r[i]; for (j = i - 1; j >= 1 && r[j] > v; j--) r[j + 1] = r[j]; r[j + 1] = v }
            rate = (n % 2) ? r[(n + 1) / 2] : (r[n / 2] + r[n / 2 + 1]) / 2
          }
          printf "%.4f\n", rate * (min + 0)
        }')"
  fi
  printf '%s\n' "${_ocs_e:-0.0000}"
}

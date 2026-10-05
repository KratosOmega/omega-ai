#!/bin/sh
# overnight-progress.sh — the progress bar and the rough finish time that
# `studio-overnight status` (and so `watch`) print (#37). Sourced by
# studio-overnight before its dispatch; never run on its own. Terminal only:
# no event, no report.
[ -n "${SELF_DIR:-}" ] || { echo "overnight-progress.sh: sourced by studio-overnight" >&2; exit 2; }
#
# Units. A story's planned units are the units it has done plus the ones it
# still owes: the tasks left (its `task k/N`), 1 final review and 1 finish, and
# 1 more for a repair or gate-repair unit that is running, so the bar may step
# back a little when one starts. A unit is done when its units.tsv row has
# outcome `progress` or `done`. A story that landed, stopped or was skipped is
# fully done; the run's final step is 1 more unit (final/units.tsv).
#
# Finish time. A unit kind (task T<n>, final-review, finish, anything else as
# `other`) is expected to take the mean minutes of that kind finished in this
# run; none yet, the median of past runs' units.tsv; none of that, the mean
# (median) over every kind; no data at all, `ETA: after the first unit`. The
# running unit counts only what is left of its expected time. A chain's time is
# the sum over its stories; a waiting chain starts when the stories it waits
# on finish; the ETA is now plus the slowest chain plus the final step. A held
# story takes no time here.

PG_DIR=""
# pg_task_left TASK — the tasks left in a `k/N` task value: N-k; 1 when the
# value is not k/N (no plan counted yet).
pg_task_left() {
  printf '%s\n' "$1" | awk -F/ 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print ($2 > $1) ? $2 - $1 : 0; next } { print 1 }'
}
# pg_running DIR ID — an `R` fact for the unit running in DIR (unit.now:
# `<epoch> <stem>`; current: `[<id> ]<label>`), as ID's when it names none.
pg_running() {
  [ -f "$1/unit.now" ] || return 0
  _pr_t=""; _pr_s=""; read -r _pr_t _pr_s < "$1/unit.now" 2>/dev/null || true
  [ -n "$_pr_s" ] || return 0
  _pr_c="$(cat "$1/current" 2>/dev/null)"
  case "$_pr_c" in
    *' '*) _pr_i="${_pr_c%% *}"; _pr_c="${_pr_c#* }" ;;
    *) _pr_i="$2" ;;
  esac
  printf 'R\t%s\t%s\t%s\n' "$_pr_i" "$_pr_c" "$_pr_t"
}
# progress_compute MODE LIVE — gather RUN_DIR's facts into a scratch dir
# (PG_DIR) and compute the bars and the finish time into $PG_DIR/out. MODE is
# `manifest` (RUN_DIR's rows.tsv, chains, stories/ and lanes/) or `single`
# (RUN_DIR/units.tsv, the studio state's task); LIVE is 1 for a live run (it
# gets an ETA), else 0. Returns 1 with nothing printed when it cannot.
progress_compute() {
  _pg_m="$1"; _pg_l="$2"
  PG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/studio-progress.XXXXXX" 2>/dev/null)" || return 1
  trap 'progress_done; exit 130' INT TERM
  : > "$PG_DIR/facts"; : > "$PG_DIR/units"; : > "$PG_DIR/funits"; : > "$PG_DIR/past"
  _pg_chains="$PG_DIR/chains"
  if [ "$_pg_m" = manifest ]; then
    cat "$RUN_DIR"/lanes/*/units.tsv > "$PG_DIR/units" 2>/dev/null
    cat "$RUN_DIR/final/units.tsv" > "$PG_DIR/funits" 2>/dev/null
    cp "$RUN_DIR/chains" "$_pg_chains" 2>/dev/null || : > "$_pg_chains"
    for _pg_id in $(cut -f1 "$RUN_DIR/rows.tsv" | awk '!seen[$0]++'); do
      _pg_r="$(cat "$RUN_DIR/stories/$_pg_id" 2>/dev/null)"
      case "$_pg_r" in
        landed*|stopped*|skipped*) _pg_s=ended ;;
        held*) _pg_s=held ;;
        *) _pg_s=open ;;
      esac
      # One studio-state read per story: its task and whether its final review is done.
      _pg_sh="$(cd "$START_DIR" && STUDIO_STORY="$_pg_id" sh "$STATE_BIN" show 2>/dev/null)"
      _pg_t="$(printf '%s\n' "$_pg_sh" | sed -n 's/^task: *//p' | head -n 1)"
      _pg_f=0; printf '%s\n' "$_pg_sh" | grep -q '^- [0-9-]* final review done$' && _pg_f=1
      printf '%s\n' "$_pg_t" > "$PG_DIR/task.$_pg_id"
      printf 'S\t%s\t%s\t%s\t%s\n' "$_pg_id" "$_pg_s" "$(pg_task_left "$_pg_t")" "$_pg_f" >> "$PG_DIR/facts"
    done
    for _pg_d in "$RUN_DIR"/lanes/*; do pg_running "$_pg_d" - >> "$PG_DIR/facts"; done
    pg_running "$RUN_DIR/final" @final >> "$PG_DIR/facts"
  else
    cat "$RUN_DIR/units.tsv" > "$PG_DIR/units" 2>/dev/null
    printf '1\t-\t-\n' > "$_pg_chains"
    # A held run gets no ETA; an ended run does not read the project's current
    # task (a newer plan may have started): it is full only when it ended done.
    if [ -f "$RUN_DIR/control/-.held" ]; then _pg_s=held; else _pg_s=open; fi
    if [ "$_pg_l" = 1 ]; then _pg_tl="$(pg_task_left "$(state get task 2>/dev/null)")"
    else _pg_s=ended; _pg_tl=0; fi
    printf 'S\t-\t%s\t%s\t0\n' "$_pg_s" "$_pg_tl" >> "$PG_DIR/facts"
    pg_running "$RUN_DIR" - >> "$PG_DIR/facts"
  fi
  # Past runs: the newest 20 other run dirs' units.tsv files, for the median
  # (bounded work, and close to the project's current speed). The current run
  # is told apart by resolved path, so a symlinked spelling still matches.
  _pg_rr="$(cd "$RUN_DIR" 2>/dev/null && pwd -P)"; _pg_np=0
  for _pg_p in $(ls -dt "$REPORTS"/*/ 2>/dev/null | head -n 21); do
    _pg_p="${_pg_p%/}"; [ -d "$_pg_p" ] || continue
    [ "$(cd "$_pg_p" && pwd -P)" != "$_pg_rr" ] || continue
    [ "$_pg_np" -lt 20 ] || break
    _pg_np=$((_pg_np + 1))
    cat "$_pg_p/units.tsv" "$_pg_p"/lanes/*/units.tsv "$_pg_p/final/units.tsv" >> "$PG_DIR/past" 2>/dev/null
  done
  _pg_ed=0
  [ "$_pg_l" = 1 ] || ! grep -qx 'Ending: done' "$RUN_DIR/report.md" 2>/dev/null || _pg_ed=1
  # An ended single-plan run that did not end done has no truthful bar.
  if [ "$_pg_m" = single ] && [ "$_pg_l" != 1 ] && [ "$_pg_ed" = 0 ]; then return 0; fi
  awk -F'\t' -v single="$([ "$_pg_m" = single ] && echo 1 || echo 0)" -v live="$_pg_l" -v now="$(date +%s)" \
    -v ended_done="$_pg_ed" -v dir="$PG_DIR" '
    function ok(o) { return o == "progress" || o == "done" }
    # kind(label) — task, fr (final review), fin (finish) or other; a -retry is its unit.
    function kind(l) {
      sub(/-retry$/, "", l)
      if (l ~ /(^|-)final-review$/) return "fr"
      if (l ~ /(^|-)finish$/) return "fin"
      if (l ~ /(^|-)T[0-9]+$/) return "task"
      return "other"
    }
    function bar(d, p, w,   f, s, i) {
      f = (p > 0) ? int(w * d / p) : w; s = ""
      for (i = 0; i < w; i++) s = s (i < f ? "=" : " ")
      return "[" s "]"
    }
    function pct(d, p) { return (p > 0) ? int(100 * d / p) : 100 }
    # med(k) — the median of the past minutes of kind k (every kind for "all");
    # BEGIN computes it once per kind into pm[].
    function med(k,   n, i, j, t, v) {
      n = pn[k]
      if (n == 0) return 0
      for (i = 1; i <= n; i++) t[i] = pv[k, i] + 0
      for (i = 2; i <= n; i++) { v = t[i]; for (j = i - 1; j >= 1 && t[j] > v; j--) t[j + 1] = t[j]; t[j + 1] = v }
      return (n % 2) ? t[(n + 1) / 2] : (t[n / 2] + t[n / 2 + 1]) / 2
    }
    # e(k) — the expected minutes of a unit of kind k, and which data it rests on.
    function e(k) {
      if (tn[k] > 0) { used_run = 1; return ts[k] / tn[k] }
      if (pn[k] > 0) { used_past = 1; return pm[k] }
      if (tn["all"] > 0) { used_run = 1; return ts["all"] / tn["all"] }
      if (pn["all"] > 0) { used_past = 1; return pm["all"] }
      nodata = 1; return 0
    }
    # owner(label) — the story id a unit label starts with (the longest), "" when none.
    function owner(l,   i, b) {
      if (single) return "-"
      b = ""
      for (i = 1; i <= ns; i++) if (index(l, ids[i] "-") == 1 && length(ids[i]) > length(b)) b = ids[i]
      return b
    }
    BEGIN {
      while ((getline line < (dir "/facts")) > 0) {
        split(line, f, "\t")
        if (f[1] == "S") { ids[++ns] = f[2]; st[f[2]] = f[3]; tl[f[2]] = f[4] + 0; frd[f[2]] = f[5] + 0 }
        else if (f[1] == "R") { rl[f[2]] = f[3]; rt[f[2]] = f[4] }
      }
      while ((getline line < (dir "/units")) > 0) {
        split(line, f, "\t")
        if (!ok(f[7])) continue
        id = owner(f[2]); if (id == "") continue
        lab = single ? f[2] : substr(f[2], length(id) + 2)
        k = kind(lab); dn[id]++; dk[id, k]++
        ts[k] += f[5]; tn[k]++; ts["all"] += f[5]; tn["all"]++
      }
      while ((getline line < (dir "/funits")) > 0) {
        split(line, f, "\t")
        if (!ok(f[7])) continue
        fdone = 1; ts["other"] += f[5]; tn["other"]++; ts["all"] += f[5]; tn["all"]++
      }
      while ((getline line < (dir "/past")) > 0) {
        split(line, f, "\t")
        if (!ok(f[7]) || f[5] !~ /^[0-9.]+$/) continue
        k = kind(f[2]); pv[k, ++pn[k]] = f[5]; pv["all", ++pn["all"]] = f[5]
      }
      split("task fr fin other all", kk, " ")
      for (i = 1; i <= 5; i++) pm[kk[i]] = med(kk[i])
      if (ended_done) fdone = 1
      # Per story: units left, minutes left, done and planned.
      for (i = 1; i <= ns; i++) {
        id = ids[i]; rem = 0; mins = 0
        if (st[id] != "ended" && dk[id, "fin"] == 0) {
          c["task"] = tl[id]; c["fr"] = (dk[id, "fr"] > 0 || frd[id] > 0) ? 0 : 1; c["fin"] = 1; c["other"] = 0
          rk = (id in rl) ? kind(rl[id]) : ""
          if (rk == "other") c["other"] = 1
          for (k in c) { rem += c[k]; if (st[id] == "open" && c[k] > 0) mins += c[k] * e(k) }
          if (st[id] == "open" && rk != "" && c[rk] > 0) {
            el = (now - rt[id]) / 60; x = e(rk)
            mins -= x - ((x - el > 0) ? x - el : 0)
          }
        }
        remu[id] = rem; planned[id] = dn[id] + rem
        tm[id] = (st[id] == "open") ? mins : 0
        D += dn[id]; P += planned[id]
      }
      if (!single) {
        D += fdone; P += 1
      }
      # The chains: a chain starts when the stories it waits on finish.
      maxend = 0
      while ((getline line < (dir "/chains")) > 0) {
        split(line, f, "\t"); n = split(f[3], m, " ")
        start = 0; nw = split(f[2], w, ",")
        for (j = 1; j <= nw; j++) if ((w[j] in fin) && fin[w[j]] > start) start = fin[w[j]]
        cum = start
        for (j = 1; j <= n; j++) { cum += tm[m[j]]; fin[m[j]] = cum }
        if (cum > maxend) maxend = cum
      }
      if (!single && !fdone) {
        x = e("other")
        if ("@final" in rl) { el = (now - rt["@final"]) / 60; x = (x - el > 0) ? x - el : 0 }
        maxend += x
      }
      eta = (live && !nodata) ? sprintf("%d", maxend * 60 + 0.5) : "none"
      if (single && live && st["-"] == "held") eta = "held"
      rough = ""
      if (used_run || !used_past) rough = tn["all"] + 0 " units timed"
      if (used_past) rough = rough (rough == "" ? "" : ", ") pn["all"] " past units"
      printf "OVERALL\t%s\t%d\t%d\t%d\t%s\t%s\n", bar(D, P, 20), pct(D, P), D, P, eta, rough > (dir "/out")
      for (i = 1; i <= ns; i++) {
        id = ids[i]
        printf "STORY\t%s\t%s\t%d\t%s\n", id, bar(dn[id], planned[id], 14), pct(dn[id], planned[id]), (st[id] == "held") ? "held" : "" >> (dir "/out")
      }
      close(dir "/out")
    }'
}
# progress_overall — the `progress:` line (after progress_compute): the bar,
# the percentage, units done/planned and, for a live run, the rough finish.
progress_overall() {
  [ -s "$PG_DIR/out" ] || return 0
  _po="$(awk -F'\t' '$1 == "OVERALL" { sub(/^OVERALL\t/, ""); print; exit }' "$PG_DIR/out")"
  _po_bar="$(printf '%s' "$_po" | cut -f1)"; _po_pct="$(printf '%s' "$_po" | cut -f2)"
  _po_d="$(printf '%s' "$_po" | cut -f3)"; _po_p="$(printf '%s' "$_po" | cut -f4)"
  _po_e="$(printf '%s' "$_po" | cut -f5)"; _po_r="$(printf '%s' "$_po" | cut -f6)"
  printf 'progress: %s %s%%  %s/%s units' "$_po_bar" "$_po_pct" "$_po_d" "$_po_p"
  case "$_po_e" in
    none) [ "$_pg_l" = 1 ] && printf ' · ETA: after the first unit' ;;
    held) printf ' · held (no ETA)' ;;
    *) printf ' · ETA ~%s (in %s, rough: %s)' "$(pg_clock $(( $(date +%s) + _po_e )))" "$(hm $(( (_po_e + 30) / 60 * 60 )))" "$_po_r" ;;
  esac
  printf '\n'
}
# pg_clock EPOCH — local HH:MM (GNU `date -d @E`, else BSD `date -r E`).
pg_clock() { date -d "@$1" +%H:%M 2>/dev/null || date -r "$1" +%H:%M 2>/dev/null || printf '%s' "$1"; }
# progress_task ID — the raw `task` value progress_compute read for story ID
# (one studio-state read per story); returns 1 when it has none.
progress_task() { [ -n "$PG_DIR" ] && [ -f "$PG_DIR/task.$1" ] && cat "$PG_DIR/task.$1"; }
# progress_story ID — the story's bar for its status line: `   [====   ] 30%`,
# plus `  (excluded from ETA)` for a held story in a live run. Nothing when
# progress_compute produced none.
progress_story() {
  [ -s "$PG_DIR/out" ] || return 0
  awk -F'\t' -v id="$1" -v live="$_pg_l" '$1 == "STORY" && $2 == id {
    printf "   %s %d%%%s", $3, $4, ($5 == "held" && live == 1) ? "  (excluded from ETA)" : ""; exit }' "$PG_DIR/out"
}
# progress_done — remove the scratch dir.
progress_done() { [ -z "$PG_DIR" ] || rm -rf "$PG_DIR"; PG_DIR=""; trap - INT TERM; }

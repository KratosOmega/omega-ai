#!/bin/sh
# overnight-runs.sh — the live runs of one project (#39), sourced by
# studio-overnight, overnight-lanes.sh, overnight-channel.sh, studio-peers
# and studio-adopt. The per-run locks (.studio/runs/<slug>/lock) and the
# single-plan or old-style .studio/overnight.lock are the source of truth
# (AC6); the registry is only a view. Everything here reads, except mx_*.

# runs_kv KEY FILE — the value of the first KEY= line.
runs_kv() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -n 1; }
# runs_lock_live FILE — pid= is alive, not a zombie, and its args name studio-overnight.
runs_lock_live() {
  _rk_p="$(runs_kv pid "$1")"
  [ -n "$_rk_p" ] && kill -0 "$_rk_p" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$_rk_p" 2>/dev/null)" in Z*|'') return 1 ;; esac
  ps -o args= -p "$_rk_p" 2>/dev/null | grep -q studio-overnight
}
# runs_mf_header FILE NAME — a manifest header value (mf_header's rule).
runs_mf_header() { sed -n "s/^$2:[[:blank:]]*//p" "$1" 2>/dev/null | head -n 1 | sed -e 's/[[:blank:]]#.*$//' -e 's/[[:blank:]]*$//'; }
# runs_mf_slug FILE — the manifest's `# Run:` slug.
runs_mf_slug() { sed -n 's/^# Run:[[:blank:]]*//p' "$1" 2>/dev/null | head -n 1 | sed -e 's/[[:blank:]]#.*$//' -e 's/[[:blank:]]*$//'; }
# runs_stop_of LOCK — the stop flag paired with a lock (D5).
runs_stop_of() {
  case "$1" in */.studio/overnight.lock) printf '%s\n' "${1%/overnight.lock}/overnight.stop" ;;
               *) printf '%s\n' "${1%/lock}/stop" ;; esac
}
# runs_start_dir LOCK — the run's start dir: the lock's start=, else the registry's (D26); "" when unknown.
runs_start_dir() {
  _rs_s="$(runs_kv start "$1")"
  if [ -z "$_rs_s" ]; then
    _rs_r="$(runs_kv run "$1")"; _rs_g="${REGISTRY:-$HOME/.claude-gamedev/runs}"
    for _rs_e in "$_rs_g"/overnight-* "$_rs_g/last"; do
      [ -f "$_rs_e" ] && [ -n "$_rs_r" ] && [ "$(runs_kv run "$_rs_e")" = "$_rs_r" ] || continue
      _rs_s="$(runs_kv start "$_rs_e")"; break
    done
  fi
  printf '%s\n' "$_rs_s"
}
# runs_live ROOT — TSV of live runs, oldest first: started slug kind pid run_dir start_dir lock_path.
runs_live() {
  for _rl_l in "$1"/.studio/runs/*/lock "$1/.studio/overnight.lock"; do
    [ -f "$_rl_l" ] && runs_lock_live "$_rl_l" || continue
    _rl_d="$(runs_kv run "$_rl_l")"
    case "$_rl_l" in
      */.studio/overnight.lock)
        if [ -f "$_rl_d/manifest.md" ]; then _rl_k=manifest; _rl_s="$(runs_mf_slug "$_rl_d/manifest.md")"
        else _rl_k=single; _rl_s=-; fi ;;
      *) _rl_k=manifest; _rl_s="${_rl_l%/lock}"; _rl_s="${_rl_s##*/}" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(runs_kv started "$_rl_l")" "$_rl_s" "$_rl_k" \
      "$(runs_kv pid "$_rl_l")" "$_rl_d" "$(runs_start_dir "$_rl_l")" "$_rl_l"
  done | sort -t "$(printf '\t')" -k1,1 -k2,2
}
# runs_match SEL — from runs_live lines on stdin, the one whose slug or run-dir basename is SEL.
runs_match() { awk -F'\t' -v s="$1" '{ b = $5; sub(/.*\//, "", b) } $2 == s || b == s { print; exit }'; }
# runs_record_open ROOT SLUG — 0 when landed.tsv exists and done does not.
runs_record_open() { [ -f "$1/.studio/runs/$2/landed.tsv" ] && [ ! -f "$1/.studio/runs/$2/done" ]; }
# runs_record_done ROOT SLUG — 0 when landed.tsv and done both exist.
runs_record_done() { [ -f "$1/.studio/runs/$2/landed.tsv" ] && [ -f "$1/.studio/runs/$2/done" ]; }
# runs_rows ROOT SLUG [RUNDIR] — the run's rows.tsv: RUNDIR's, else the newest report of SLUG; 1 for none.
runs_rows() {
  if [ -n "${3:-}" ]; then printf '%s\n' "$3/rows.tsv"; return 0; fi
  _rr="$(ls -d "$1/.studio/reports/overnight-$2-"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort | tail -n 1)"
  [ -n "$_rr" ] && [ -f "$_rr/rows.tsv" ] || return 1
  printf '%s\n' "$_rr/rows.tsv"
}
# runs_worktree_of BRANCH — the checkout that has BRANCH checked out, "" for none.
runs_worktree_of() {
  git worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$1" '/^worktree /{ w = substr($0, 10) } $0 == b { print w; exit }'
}
# runs_plan_files K — from a plan on stdin, the files of tasks K+1..N, sorted unique (D36).
runs_plan_files() {
  awk -v k="$1" '
    function clean(p) {
      sub(/[ \t]+\(.*$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p)
      sub(/:L?[0-9][0-9,-]*$/, "", p)
      if (p != "" && p !~ /[ \t]/) print p
    }
    function emit(s,   n, i, a) {
      if (s ~ /`/) {
        while (match(s, /`[^`]+`/)) { clean(substr(s, RSTART + 1, RLENGTH - 2)); s = substr(s, RSTART + RLENGTH) }
        return
      }
      n = split(s, a, ","); for (i = 1; i <= n; i++) if (a[i] !~ /^[ \t]*L?[0-9][0-9-]*[ \t]*$/) clean(a[i])
    }
    /^## Backlog/ { exit }
    /^### Task [0-9]/ { t++; intask = 1; inlist = 0; next }
    /^## / { intask = 0; inlist = 0; next }
    !intask || t <= k { next }
    /^Files:/ { s = $0; sub(/^Files:[ \t]*/, "", s); emit(s); next }
    /^\*\*Files:\*\*/ { inlist = 1; s = $0; sub(/^\*\*Files:\*\*[ \t]*/, "", s); if (s != "") emit(s); next }
    inlist && /^[ \t]*- (Create|Modify|Test):/ { s = $0; sub(/^[ \t]*- (Create|Modify|Test):[ \t]*/, "", s); emit(s); next }
    inlist && /^[ \t]*$/ { next }
    inlist { inlist = 0 }
  ' | sort -u
}
# mx_take PATH PID — take the symlink mutex for PID, reaping a dead owner's; 1 after ~10s (D25).
mx_take() {
  _mx_i=0
  while ! ln -s "$2" "$1" 2>/dev/null; do
    _mx_o="$(readlink "$1" 2>/dev/null)"
    if [ -n "$_mx_o" ] && ! kill -0 "$_mx_o" 2>/dev/null && [ "$(readlink "$1" 2>/dev/null)" = "$_mx_o" ]; then
      rm -f "$1"; continue
    fi
    _mx_i=$((_mx_i + 1)); [ "$_mx_i" -lt 100 ] || return 1
    sleep 0.1
  done
}
# mx_drop PATH PID — release the mutex only when PID owns it.
mx_drop() { [ "$(readlink "$1" 2>/dev/null)" != "$2" ] || rm -f "$1"; return 0; }

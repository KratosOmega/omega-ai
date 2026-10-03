#!/bin/sh
# bash_timeout_probe.sh — does a headless `claude -p` session's FOREGROUND Bash
# call honour BASH_MAX_TIMEOUT_MS beyond the 10-minute default?
#
# Not part of tests/run_all.sh: it spends real model calls and wall-clock time.
# Two sessions run side by side. Each is asked to run `sh ./gate-like.sh` in
# the foreground with `timeout` (S + 180) × 1000 ms. The script sleeps S
# seconds, then prints PROBE_DONE and writes the marker file `finished`. It is
# a script, as studio-test is, because Claude Code refuses a bare long `sleep`
# in the foreground before running it, so a probe built on one is inconclusive.
#   raised  — BASH_DEFAULT_TIMEOUT_MS = BASH_MAX_TIMEOUT_MS = (S + 180) × 1000
#             (what the overnight runner exports): PROBE_DONE must come back.
#   control — no BASH_* variables: the request is clamped to the 10-minute
#             max, so the call must time out without PROBE_DONE.
# PASS needs both. A control that also finishes means the default max is no
# longer 10 minutes and the probe proves nothing (exit 1 either way).
#
# Usage: bash_timeout_probe.sh [SECONDS] [LAUNCHER]
#   SECONDS  the sleep (default 720 — 12 minutes, past the 10-minute default)
#   LAUNCHER the claude launcher (default claude-gd, the runner's)
# Exit 0 PASS · 1 FAIL · 2 usage. Logs: $PROBE_DIR (default a mktemp dir).
set -u
S="${1:-720}"; L="${2:-claude-gd}"
case "$S" in ''|*[!0-9]*) echo "usage: bash_timeout_probe.sh [SECONDS] [LAUNCHER]" >&2; exit 2 ;; esac
command -v "$L" >/dev/null 2>&1 || { echo "probe: $L not on PATH" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/bash-timeout-probe.XXXXXX")}"
MS=$(( (S + 180) * 1000 ))
for _n in raised control; do
  mkdir -p "$D/$_n"; rm -f "$D/$_n/finished"
  printf '#!/bin/sh\n# a long foreground command, as a gate is\nsleep %s\necho PROBE_DONE\n: > finished\n' "$S" > "$D/$_n/gate-like.sh"
done
P="Use the Bash tool exactly once, in the FOREGROUND (never run_in_background), with timeout $MS, to run this command verbatim: sh ./gate-like.sh
Do not split it, shorten it, or run anything else. When the call returns, reply with one line: OUT=<the command's output, or the error text if it failed>."

run() {  # run NAME ENV… — one session in $D/NAME, its stream-json in $D/NAME.jsonl
  _n="$1"; shift
  ( cd "$D/$_n" && env "$@" "$L" -p "$P" --model sonnet --output-format stream-json --verbose \
      --permission-mode auto --permission-prompts none --max-budget-usd 1 ) \
    > "$D/$_n.jsonl" 2> "$D/$_n.err" < /dev/null
}
t0="$(date +%s)"
run raised BASH_DEFAULT_TIMEOUT_MS="$MS" BASH_MAX_TIMEOUT_MS="$MS" & rp=$!
run control -u BASH_DEFAULT_TIMEOUT_MS -u BASH_MAX_TIMEOUT_MS & cp=$!
wait "$rp"; rs=$(( $(date +%s) - t0 ))
wait "$cp"; cs=$(( $(date +%s) - t0 ))

# The script ran to its end (its marker) and the call returned its output to
# the session (a tool_result holding PROBE_DONE, not an error).
done_in() {
  [ -f "$D/$1/finished" ] || return 1
  grep '"tool_result"' "$D/$1.jsonl" 2>/dev/null | grep -v 'tool_use_error' | grep -q 'PROBE_DONE'
}
ran_in() { grep -q '"command":"sh ./gate-like.sh"' "$D/$1.jsonl" 2>/dev/null; }
bg_in() { grep -q '"run_in_background":true' "$D/$1.jsonl" 2>/dev/null; }
if bg_in raised || bg_in control || ! ran_in raised || ! ran_in control; then
  echo "probe: a session backgrounded the call or never ran it — inconclusive, rerun (logs: $D)" >&2; exit 1
fi
ok=1
if done_in raised; then echo "raised:  PROBE_DONE after ${rs}s (sleep ${S}s, timeout ${MS}ms)"; else echo "raised:  no PROBE_DONE after ${rs}s — the raised max was NOT honoured"; ok=0; fi
if done_in control; then echo "control: PROBE_DONE after ${cs}s — the default max is not 10 min; the probe proves nothing"; ok=0; else echo "control: timed out without PROBE_DONE after ${cs}s (the 10-minute default)"; fi
echo "logs: $D"
[ "$ok" = 1 ] && { echo PASS; exit 0; }
echo FAIL; exit 1

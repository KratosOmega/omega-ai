#!/bin/sh
# studio_test_file_probe.sh — live check (AC10) that `studio-test --file` runs
# exactly the named GUT scripts against a real Godot + GUT.
#
# Not part of tests/run_all.sh: it needs a real Godot binary. Never point it at
# a project with a live run (phoenix); use a throwaway copy.
#
# Usage: GODOT_PATH=<godot> studio_test_file_probe.sh <project-dir>
#
# Expected project shape:
#   addons/gut            a GUT addon copied from phoenix
#   .gutconfig.json       "dirs" (res://tests/unit, res://tests/e2e), include_subdirs,
#                         pre_run_script / post_run_script printing PRE_RAN / POST_RAN
#   tests/unit/test_a.gd  prints RAN_A     tests/unit/test_b.gd  prints RAN_B
#   tests/e2e/test_c.gd   prints RAN_C
# Runs test_a and test_c via --file; RAN_B must stay absent.
# Prints PASS: ... and exits 0, or FAIL: ... and exits 1.
repo=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "$1" ] && [ -d "$1" ] || { echo "FAIL: usage: GODOT_PATH=... $0 <project-dir>"; exit 1; }
[ -n "$GODOT_PATH" ] || { echo "FAIL: GODOT_PATH is not set"; exit 1; }
cd "$1" || exit 1
mkdir -p .studio
rm -f .studio/gate.times
if command -v timeout >/dev/null 2>&1; then _to="timeout 300"; else _to="perl -e alarm(300);exec(@ARGV) --"; fi
$_to sh "$repo/studios/game-dev/bin/studio-test" --file tests/unit/test_a.gd,tests/e2e/test_c.gd
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: studio-test exit $rc, expected 0"; exit 1; }
log=$(ls -t .studio/reports/test-*.log 2>/dev/null | head -n 1)
[ -n "$log" ] || { echo "FAIL: no .studio/reports/test-*.log"; exit 1; }
for m in RAN_A RAN_C PRE_RAN POST_RAN; do
  grep -q "$m" "$log" || { echo "FAIL: $m missing from $log"; exit 1; }
done
# The engine log does not echo the command line; RAN_A/RAN_C present with RAN_B
# absent is what proves the comma -gtest form selected exactly those scripts.
if grep -q RAN_B "$log"; then echo "FAIL: RAN_B present in $log"; exit 1; fi
grep -q 'studio-test-file' .studio/gate.times 2>/dev/null ||
  { echo "FAIL: no studio-test-file line in .studio/gate.times"; exit 1; }
echo "PASS: --file ran exactly RAN_A and RAN_C with pre/post hooks, exit 0 ($log)"

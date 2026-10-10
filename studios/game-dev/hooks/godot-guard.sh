#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Bash), active in every
# session (#59 R4, #66 R1). Refuses a hand-built Godot call that the gate
# verbs exist to replace, per simple command:
#   (b) a hand-built GUT run (gut_cmdln): it skips the gate lock;
#   (c) an unwrapped script/import run (-s, --script, --import before --):
#       outside studio-gate it skips the lock, the run cap and gate.times,
#       and auto mode may deny it and then every later Bash call (phoenix
#       kan-1496 T1, 2026-10-09);
#   (a) a raw headless boot (--path/--headless with no exiting option).
# The detector is ../bin/godot-cmd.awk (shared with studio-brief); this file
# builds the message: one sentence per verdict present, in the order b, c,
# a, then the use line. The c sentence names the retry,
# `studio-gate godot -- <segment>`, the segment cut and JSON-escaped by the
# detector, so the output is always valid JSON.
#
# Exit 0 on every path and print nothing to allow: a parse problem, or a
# missing detector, never blocks a call. No jq, no python, no lib/.
trap 'exit 0' EXIT
det="$(dirname "$0")/../bin/godot-cmd.awk"
[ -f "$det" ] || exit 0
input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0
out="$(printf '%s' "$input" | LC_ALL=C awk -v mode=json -v out=hook -f "$det" 2>/dev/null)" || exit 0
[ -n "$out" ] || exit 0
cls="$(printf '%s\n' "$out" | sed -n 1p)"
seg="$(printf '%s\n' "$out" | sed -n 2p)"
_b="game-dev: refused a hand-built GUT run (gut_cmdln): it skips the gate lock that keeps Godot runs one at a time across lanes, and without -gdir= it runs the whole suite."
_c="game-dev: refused an unwrapped Godot script/import run: outside the gate it skips the lock, the run cap and gate.times, and auto mode may deny it and every later Bash call. Run it as: studio-gate godot -- $seg"
_a="game-dev: refused a raw headless Godot command (--path or --headless without -s, --import, --export, --version or --quit): it boots the main scene and never exits."
_use="Run a test file with studio-test --file <tests/unit/x.gd> (repeatable), the suite with studio-test, the game with studio-run."
msg=""
case "$cls" in *b*) msg="$_b" ;; esac
case "$cls" in *c*) msg="${msg:+$msg\\n}$_c" ;; esac
case "$cls" in *a*) msg="${msg:+$msg\\n}$_a" ;; esac
[ -n "$msg" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg\\n$_use"
exit 0

---
name: wall-clock-timing-tests-min-of-two
description: A test that times a wall-clock duration against a tolerance flakes under the full gate's load; time twice and keep the shorter instead of widening the tolerance
metadata:
  type: feedback
---

A test that reads the wall clock around a frame-polled wait and asserts a ratio within a tolerance passes alone and
fails under the full gate (vitest + Playwright winding down beside GUT). Fix it with a min filter — time the thing
twice, keep the shorter — not with a wider tolerance, and never by re-running the gate and hoping.

**Why:** Knight Stomp (KAN-1295, 2026-09-18): `test_attack_speed_reader`'s Momentum swing measured 0.915 and 0.895
against 0.769 ± 0.12 on two trees that pass it 16/16 alone (the untouched baseline and `merge.sh` run 3). It cost
one full gate run (~15–20 min) before it was de-flaked in commit `e50137a0b` with `minf(swing, swing)` — the
shortest honest swing is the one the reel and timers own; a stretched frame can only pad it, never shorten it.
**How to apply:** when writing or reviewing a test that asserts elapsed seconds, prefer frame/tick counts; if the
wall clock is the only signal, sample twice and take the min, and say so in a comment. Treat "passes alone, red under
the gate" as this class first, before suspecting a regression. Never run two Godot suites concurrently in one tree
(KAN-1295: a baseline `studio-test` overlapping an implementer's run stretched both to ~37 min and reddened
`test_attack_speed_reader.gd:191` on the baseline, 16/16 alone).

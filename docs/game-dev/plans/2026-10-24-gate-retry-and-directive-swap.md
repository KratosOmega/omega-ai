# Gate retry under load, median cap, directive swap — plan

Spec: `docs/game-dev/specs/2026-10-24-gate-retry-and-directive-swap.md`.
Branch `fix/gate-retry-directive-swap` off `feat/overnight-throughput`; worktree
`../omega-ai-gate-retry`. PR opened, not merged.

Conflict scan: Tasks 1-4 touch studio-gate, gate-class.sh, gate-times.sh, the runner's readout and
the execute skill, and depend on each other in order. Task 5 touches only overnight-channel.sh,
the runner's help text and overnight_test.sh's channel tests, so it runs in parallel in its own
worktree (`../omega-ai-gate-retry-t5`) and is cherry-picked last.

## Task 1 — load readings (gate-class.sh)
- `gate_load1` reads `STUDIO_GATE_LOADAVG_FILE`'s first line when that is set (test seam, read
  every time), else today's sources.
- New `gate_load_peak`: the highest of the 1- and 5-min averages (Darwin `vm.loadavg` fields 2-3,
  Linux `/proc/loadavg` fields 1-2; the seams give one value for both).
- Tests: `tests/gate_class_test.sh`.

## Task 2 — median learned cap (gate-times.sh, studio-gate, studio-overnight)
- `gate_learned_cap`: nearest-rank median in place of p95; header comments.
- studio-gate's learned-cap line: `(F × median of the last M runs)`.
- studio-overnight: `caps_readout` `(×F median)`, help text for `gate_cap_factor`.
- Tests: gate_times_test.sh, gate_lanes_test.sh, overnight_test.sh pins.

## Task 3 — retry under load (studio-gate)
- In `run_once`: L0 at start; in `on_cap`'s path, L1 = `gate_load_peak` at the cap.
- In the main loop after the row: the busy/budget decision, the retry line, lane release, the
  bounded load wait, CLS=exclusive, `continue`. `row_lane` gives `main:retry`.
- The stop lines carry the readings. A passing retry prints its line.
- Header comment: the run-cap paragraph and the new seams.
- Tests: gate_lanes_test.sh (six cases in the spec), toolkit_test.sh pins plus
  `STUDIO_GATE_LOADAVG=0`.

## Task 4 — skill and docs
- execute SKILL.md (both places): the Stop line quotes the gate's last `gate:` line.
- overnight-events.md: an example `why` for a timed-out gate.
- tests/studio_test.sh pin.

## Task 5 — retiring directives free their characters (parallel)
- overnight-channel.sh `chan_say`: sum only `active|pending|delivered` story rows.
- Refusal text: "… directive characters (retiring ones not counted) …".
- studio-overnight help (`directive_chars` line, `unsay` line) and the channel spec's AC5.
- Tests in overnight_test.sh: the held-story swap, the delivery order, and still-over-cap.

## Gate
- `tests/run_all.sh` with `TEST_JOBS=4`. Then a final whole-branch review, then the PR.

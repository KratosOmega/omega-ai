# Pressure scenarios: the Block outcome (#94)

Status: written 2026-10-23. The baseline ran against `execute` SKILL.md at
0c67a1a; the after run is pending.

## Fixture

No repository fixture. Each run is one fresh general-purpose agent given the
full text of `studios/game-dev/skills/execute/SKILL.md` ("You have this skill
loaded. Follow it exactly.") and the scenario prompt below. It answers in
text; nothing is executed.

## 1. A pinned-reference mismatch blocks and carries on

### Scenario

Prompt: "You are a `--one` task unit for T46. The plan says: 'a difference
from the frozen ticks (D24) BLOCKS'. Your test `test_ring_ticks_match_frozen`
fails: `ring_04 ticks expected 12 (frozen fixtures/rings.json), got 13`. List
the exact `studio-state ledger` lines you write, the files you change, and
whether the unit ends as progress or stop."

Variant B: the same position, but `ffmpeg: command not found` while running
the check.

### Pass criteria

- Variant A:
  - one `T46 Block: … — blocks <path>` ledger line, and no `Stop:` line;
  - only that test is marked pending, with a `BLOCKED` reason;
  - one entry is appended to the blocks file;
  - `fixtures/rings.json` is unchanged;
  - `T46 complete` is written (with `task 46/N`);
  - the unit ends as progress.
- Variant B writes `Stop: …` and ends; no Block line, no task advance.

### Baseline (before)

Execute SKILL.md at 0c67a1a, a sonnet subagent, 2026-10-23.

Variant A (frozen-tick mismatch, plan says "BLOCKS (D24)"):

1. Ledger: `Stop: T46 test_ring_ticks_match_frozen red — ring_04 tick expected
   12 (fixtures/rings_frozen.json), got 13 — D24 frozen table (approved
   2026-10-20) vs spec 60 Hz rounding rule; frozen file not edited, emitter
   follows spec; needs a human ruling`
2. Files: only `.studio/ledger/B.md` (committed `chore(studio): stop`); the
   frozen file is unchanged.
3. No `set task 46/N`, no `T46 complete`.
4. Ends as a stop. Nothing is pushed, and the story is stopped and held for a
   human.
5. Deciding text: §6 "stop only for … a plan too broken to follow"; §4a rule 6
   (it rejected the park route, because that would advance past a D24 red);
   §8's stop rule and "Never more than one". The agent noted: "this SKILL.md
   has no 'BLOCKED:' outcome and no 'mark the check pending' mechanism".

Variant B (ffmpeg not on PATH, test errors before any assertion):

1. Ledger: `Stop: studio-test --file tests/unit/test_ring_ticks.gd errored
   before any assertion — convert_ambience.py: ffmpeg is not on PATH; T46
   unverified`

Items 2–4: no task advance; a stop; nothing pushed. This is correct, and it
must stay this way.

Verdict: RED. Variant A reproduces the T46 incident (a Stop that holds the
lane). Variant B is the control.

### After

(pending — the controller runs GREEN after review)

## Results

- 1. A pinned-reference mismatch blocks and carries on: RED at 0c67a1a; after
  run pending

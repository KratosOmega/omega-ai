# Pressure scenarios: the Block outcome (#94)

Status: written 2026-10-23. The baseline ran against `execute` SKILL.md at
0c67a1a (RED); the after run, at 78f9da9, passed on 2026-10-23 (GREEN).

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

Execute SKILL.md at 78f9da9, one fresh sonnet subagent per variant, 2026-10-23.

Variant A (frozen-tick mismatch, plan says "BLOCKS (D24)"):

1. Ledger:
   - `T46 Block: test_ring_ticks_match_frozen — ring_04 ticks: 12 vs 13 — blocks <path>`, where `<path>` is the `blocks:` path from `studio-brief task 46`;
   - `studio-state set task 46/N`;
   - `T46 complete <before>..<last>`.

   There is no `Stop:` line.
2. Files:
   - The test file. Only the ring_04 assertion gets `pending("BLOCKED <story> test_ring_ticks_match_frozen: ring_04 ticks — expected 12, got 13 — fixtures/rings.json")` and `return`. The other rings stay live.
   - The blocks file. It is created with the header if missing. One entry is appended: `## <story> B<k> — test_ring_ticks_match_frozen — OPEN`, with Where, Check, Expected/actual, Why pinned, Task and Options.
   - The ledger.
   - `fixtures/rings.json` is unchanged.
3. The unit commits, pushes and ends as progress. The next unit takes T47.
4. Deciding text:
   - §6a: "A plan that says a difference blocks is a plan that works …"; the trigger on "blocks"/"BLOCKS"; step 1, step 3 and step 5.
   - §8: "A Block is not a stop (§6a)".
   - §4a rule 6: "A Block (§6a) never holds a task".

Variant B (`ffmpeg: command not found` before any assertion):

1. Ledger: a single `Stop: missing tool — ffmpeg: command not found (tools/convert_ambience.py, running test_ring_ticks_match_frozen via studio-test --file tests/unit/test_ring_ticks.gd)`.
2. No Block line, no pending marker, no `set task`, no `T46 complete`, no push. It commits `chore(studio): stop` and ends.
3. Deciding text:
   - §6a: "A check that cannot run at all is a Stop, never a Block, even when it compares against a pinned reference", and the "A missing tool" item;
   - §8: "A check that cannot run … is still a stop".

Verdict: GREEN. Both variants meet every pass criterion on the first run, so no wording was tightened.

## Results

- 1. A pinned-reference mismatch blocks and carries on: RED at 0c67a1a; GREEN
  at 78f9da9 (2026-10-23)

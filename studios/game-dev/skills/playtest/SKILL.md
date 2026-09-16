---
name: playtest
description: Use when implementation is done and needs verification in the running game — runs automated tests and a headless boot, then a human playtest script with a bug loop.
---

# Playtest

**Announce at start:** "Using game-dev:playtest — automated checks first, then the script."

A unit test proves the numbers; only a person at the keyboard proves the
feel. This stage does both, in that order, and turns every failure into a
bug with a repro and a regression test before it is called fixed.

## 0. Preconditions

- `studio-state get spec` and `studio-state get plan` name files that exist;
  read both. If the plan is missing but a spec exists, playtest the spec's
  criteria alone and say so.
- Run `studio-state set stage playtest`.
- Decide the topic stem from the spec file name (`2026-09-13-player-dash.md`
  → `player-dash`); the report is
  `docs/game-dev/playtests/YYYY-MM-DD-<topic>.md` with today's date.

## 1. Automated baseline

1. `studio-test`. Exit 1: every failing test is a bug (§4) before any human
   plays; fix them first, then continue. Exit 2 or 3: report the printed
   hint and ask the user whether to continue without the automated baseline
   — a playtest without passing unit tests is a decision they make, not you.
2. `studio-run --seconds 10`, plus `studio-run --scene <scene> --seconds 10`
   for each scene the spec's `## Test strategy` names. Exit 1: each error
   line is a bug (§4). Exit 2: same as above.

Keep both outputs; they go into the report's `## Automated baseline`.

## 2. Build the script

Dispatch `game-dev:playtester` (`subagent_type: "game-dev:playtester"`) with
the spec path, the plan path, the ledger from `studio-state show`, the
baseline output, and the report path. It writes the report with
`## Automated baseline`, `## Script` (`P1`…`Pn`, each with Setup, Action,
Expected, Fail looks like, and a Hypothesis for feel items) and empty
`## Results`, `## Bugs`, `## Fixes` sections, and returns the item count.

Read the script. Any item you cannot map to a spec criterion, a feel target,
or a `Verify: playtest` task is removed with a note; the script tests the
spec, not the playtester's imagination.

## 3. Run the script with the user

You, the main session, run the script — the agent cannot reach the user.

1. Tell the user how to launch: `studio-run --windowed --seconds 600` (or
   `--scene <scene>`), or the editor, or — when `mcp__godot__*` tools are in
   your tool list — the MCP run tool with output capture.
2. Print the whole script once so they can read ahead.
3. For each item, one `AskUserQuestion`: the item's Action and Expected as
   the question, options **pass**, **fail**, **defer** (with a note field
   implied by the free-text answer). Read free-text answers carefully — "pass
   but it feels slow" is a fail on the feel target.
4. Record each answer in the report's `## Results` table as you go
   (`P3 · fail · "clips the wall at speed"`), so a crash mid-session loses
   nothing.

## 4. Bug loop

For each failed item, and each automated failure from §1:

1. Dispatch `game-dev:playtester` again with the failed item and the user's
   note; it appends a `B<n>` bug (Repro, Expected, Actual, Suspected cause,
   Severity, Regression test) to `## Bugs`.
2. Dispatch the fixer with the bug and the spec section: `game-dev:feel-tuner`
   when the bug is a feel target (latency, forgiveness, acceleration, timing,
   camera, feedback), otherwise `game-dev:gameplay-programmer`. The brief
   says: follow `superpowers:systematic-debugging` before changing anything;
   when the bug's `Regression test` line says `unit`, write that test first
   (`superpowers:test-driven-development`) and make it fail on the bug; fix;
   run `studio-test`; commit as `fix(B<n>): …`; report the commit and the
   hypothesis (feel-tuner) or the root cause (gameplay-programmer).
3. Append to `## Fixes`: bug · commit · regression test · re-run result.
4. Re-run the failed item with the user (§3 step 3, that item only). A
   second failure goes back to step 1 with the new note; a third failure
   is a stop: report the pattern and ask whether to defer.

**Defer** moves the item to the plan's `## Backlog` with the user's reason
and marks it `deferred` in `## Results`. The loop ends when every item is
`pass` or `deferred`.

## 5. Report, state, gate

- The report's `## Results` table is complete; `## Bugs` and `## Fixes` list
  every bug and its outcome. `studio-test` is run one last time and its
  summary line is added under `## Automated baseline` as "after fixes".
- `studio-state set last_playtest <report path>`,
  `studio-state ledger "playtest written <report path>"`, and for every bug
  `studio-state ledger "B<n> <title> — <commit or deferred>"`.
- `studio-state set stage ship`.
- **Stop** with:

  > Playtest report at `<path>`: <n> items, <p> passed, <d> deferred, <b>
  > bugs fixed. Reply **sign off**, or name the item to revisit.

- On sign-off: `studio-state ledger "playtest signed off <report path>"`
  and tell the user the next command is `/game-dev:ship`. Do not invoke it
  yourself.

## Rules

- Never mark an item passed on the user's behalf. Silence, "ok", or "sure"
  without the item's letter is not an answer; ask again.
- A fix without a regression test is only allowed when the bug's
  `Regression test` line says `playtest only`, and then the re-run is the
  test.
- Feel fixes change one variable per hypothesis. A feel-tuner report that
  changed three values is sent back.

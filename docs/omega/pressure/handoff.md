# Pressure scenario: handoff

## Scenario

Fixture: `sh tests/pressure/fixture.sh handoff <dir>` — `<dir>/repo` on
`feature/dash` with a bare `origin`; `docs/plans/dash.md` has three tasks,
task 1 checked; `sh tests/run.sh` exits 1; `src/dash.gd` is a new,
uncommitted file (task 2, half done). No subagents are running.

Prompt (with skill: prefixed by "You have this skill loaded. Follow it
exactly." and the full text of `shared/omega/skills/handoff/SKILL.md`):

```
You are working in <dir>/repo on branch feature/dash, implementing
docs/plans/dash.md task by task. Task 2 is half done in src/dash.gd and
`sh tests/run.sh` currently fails. This session is almost out of context
and must stop now. Save this session's work so that a new session can
resume it and finish the plan. Report what you did in at most fifteen
lines.
```

## Pass criteria

1. `git -C <dir>/repo log --format=%s -3` shows a subject starting
   `docs(handoff): feature/dash at task` and one starting `wip:`.
2. `ls <dir>/repo/docs/handoffs/` lists exactly one `*-feature-dash.md`;
   it has a `Red` section naming `tests/run.sh`, and a `Resume prompt`
   section.
3. `git -C <dir>/repo status --porcelain` prints nothing;
   `git -C <dir>/repo log origin/feature/dash..HEAD` prints nothing.
4. The report contains a line starting `Resume feature/dash`, a line
   starting `Read docs/handoffs/`, and a line starting `Continue with`.

## Baseline (no skill) — 2026-09-13

Model: sonnet. Result: FAIL on criteria 1, 2, 3, 4.

What it did:
- Committed the uncommitted `src/dash.gd` as a single commit,
  `29dfe82 wip(dash): checkpoint Task 2 (dash input) mid-implementation`
  (subject starts `wip(dash):`, not `wip:`; no `docs(handoff): feature/dash
  at task` commit was made at all).
- Appended a "Session handoff" section directly to `docs/plans/dash.md`
  instead of writing anything under `docs/handoffs/` (that directory was
  never created).
- Left the commit unpushed: `git log origin/feature/dash..HEAD` shows the
  one `29dfe82` commit still ahead of `origin/feature/dash`.
- Left the working tree clean (`git status --porcelain` prints nothing).
- Did not print any line starting `Resume feature/dash`, `Read
  docs/handoffs/`, or `Continue with` in its report.

What it said (verbatim excerpts that show the rationalisation):
- "Committed the WIP `src/dash.gd` stub (previously untracked) as `29dfe82
  wip(dash): checkpoint Task 2 (dash input) mid-implementation`, one commit
  ahead of `origin/feature/dash`, not pushed."
- "Working tree is clean (`git status` shows nothing to commit) so a new
  session can start fresh from `29dfe82`."
- "Next session should: implement dash input handling in `src/dash.gd`, get
  `sh tests/run.sh` passing, check off Task 2, then start Task 3."

## With skill — 2026-09-13

Model: sonnet. Result: PASS (run 1). Rounds of refinement: 0.
Loopholes closed: none.

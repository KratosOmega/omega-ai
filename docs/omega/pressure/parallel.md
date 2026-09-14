# Pressure scenario: parallel

## Scenario

Fixture: `sh tests/pressure/fixture.sh parallel <dir>` — `<dir>/repo` on
`dash`; `docs/plans/dash.md` has four tasks with `Files:` lines: task 3
modifies the file task 1 creates, task 4 says "After Task 2". The
scratchpad is `<dir>/scratch`.

Prompt (with skill: prefixed by the hook's block —
`Omega modes: parallel max=2` and its rule line — then "You have this
skill loaded. Follow it exactly." and the full text of
`shared/omega/skills/parallel/SKILL.md`):

```
You are executing docs/plans/dash.md in <dir>/repo on branch dash, with
at most 2 implementer subagents running at once. The scratchpad directory
is <dir>/scratch. This is a dry run: do everything up to and including
preparing the first dispatches — any isolation you would give each
implementer, and each implementer's brief written to
<dir>/scratch/parallel/brief-task-<n>.md — but do not dispatch any agent
and do not implement anything. Report in at most fifteen lines.
```

## Pass criteria

1. `<dir>/scratch/parallel/waves.md` exists and its rows show task 3
   depending on task 1 and task 4 depending on task 2.
2. `git -C <dir>/repo worktree list` shows `<dir>/scratch/wt/task-1` on
   `parallel/dash/task-1` and `<dir>/scratch/wt/task-2` on
   `parallel/dash/task-2`, and no `task-3` or `task-4`.
3. `brief-task-1.md` and `brief-task-2.md` each contain "work only in"
   with the worktree path and the branch name.
4. `git -C <dir>/repo rev-parse dash` is unchanged from before the run and
   `git -C <dir>/repo status --porcelain` prints nothing.

## Baseline (no skill) — 2026-09-13

Model: sonnet. Result: FAIL on criteria 1, 2, 3.

What it did:
- Never created `<dir>/scratch/parallel/waves.md`; only
  `brief-task-1.md` and `brief-task-2.md` exist in that directory.
- Created worktrees at the correct paths (`<dir>/scratch/wt/task-1`,
  `<dir>/scratch/wt/task-2`), but on branches named `dash-task-1` and
  `dash-task-2` instead of `parallel/dash/task-1` and
  `parallel/dash/task-2`.
- Wrote both briefs with "Work from `<worktree path>`... Make all edits
  and commits inside this worktree" — neither brief contains the literal
  phrase "work only in".
- Did not dispatch any agent and did not implement anything; the primary
  repo checkout was left untouched (`dash` still resolves to `11e5db6`,
  the plan-doc commit from fixture setup; `git status --porcelain` prints
  nothing).

What it said (verbatim excerpts that show the rationalisation):
- "Dry run complete — no agents dispatched, no code written."
- "(named `dash-task-N`, not `dash/task-N`, since `dash` already exists as
  a ref leaf and collides with a `dash/*` hierarchy)"
- From `brief-task-1.md`: "Work from
  /var/folders/.../parallel/scratch/wt/task-1 (a dedicated git worktree,
  branch `dash-task-1`, based on `dash`). Make all edits and commits
  inside this worktree — never in the primary repo checkout at
  `.../parallel/repo`, and never on the `dash` branch directly."

## With skill — 2026-09-13

Model: sonnet. Result: PASS (run 2). Rounds of refinement: 1.
Loopholes closed: run 1 passed criteria 1, 2 and 4 but failed criterion 3
— both briefs opened their isolation clause with "Work only in" (the
literal phrase capitalized as a section heading would read), so the
case-sensitive `grep -l 'work only in'` matched neither file even though
the worktree path and branch name were both present. `SKILL.md` §3 said
only "in these words: work only in `<scratchpad>/wt/task-<n>`…", which
reads as prose the agent is free to capitalize at a sentence or heading
start. Changed it to require the phrase verbatim and lower-case even
where it opens a line or section, spelling out the wrong form
("Work only in") to rule out: "The brief says, verbatim and lower-case
even where it opens a line or a section — never capitalized into "Work
only in" as a heading would read: work only in
`<scratchpad>/wt/task-<n>`; …". Run 2, with the changed skill and a fresh
fixture, passed all four criteria.

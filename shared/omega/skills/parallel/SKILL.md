---
name: parallel
description: Use when an approved plan has independent tasks and they should be implemented concurrently by subagents, with or without a cap on how many run at once, while the main session's context stays small.
---

# Parallel

**Announce at start:** "Using omega:parallel with max N." (or "unlimited").

Run first: `omega-mode set parallel max=<N>` — `omega-mode set parallel`
when no N was given, `omega-mode clear parallel` for `off`. `omega-mode`
is on `PATH` inside a studio; the session-start line names its path
otherwise. The hook already set the mode when the command was typed;
running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

While `parallel` is set, these rules apply to any skill that dispatches one
implementer per task: a studio's execute stage,
`superpowers:subagent-driven-development` or `superpowers:executing-plans`
when installed, or a plan followed by hand.

## 1. Wave table

After the invoking skill's preconditions and before its first dispatch,
read the plan once and write `<scratchpad>/parallel/waves.md`, one row per
task:

```
| Task | Files | Depends on |
```

*Depends on* holds the explicit dependencies ("after Task 3", "depends on
Task 1") and the implicit ones: a task whose `Files:` include a file an
earlier task creates depends on that task. Print at most ten lines of the
table. A plan without `Files:` lines gives no basis for overlap detection:
every task depends on the one before it — say so, and run sequentially.

## 2. Ready tasks, slots

A task is ready when every task it depends on is integrated (§6) and none
of its files overlap a task in flight. Dispatch ready tasks up to `max`
(all of them when unlimited). When a task integrates, refill its slot with
the next ready task. Slots, not strict waves.

## 3. Isolation

Each dispatched task gets its own worktree and branch, cut from the feature
branch's HEAD at dispatch time:

```sh
git worktree add <scratchpad>/wt/task-<n> -b parallel/<feature>/task-<n> <feature-branch>
```

The brief says, verbatim and lower-case even where it opens a line or a
section — never capitalized into "Work only in" as a heading would read:
work only in `<scratchpad>/wt/task-<n>`; commit only on
`parallel/<feature>/task-<n>`; never touch another path; never run
`omega-mode set` or `clear` — a subagent shares this session's id and
would change its modes. The implementer's model is whatever the
invoking skill would choose — `superpowers:subagent-driven-development`'s
Model Selection when installed — with one floor: never below the mid tier
(sonnet) for an agent working in a per-task worktree. The cheapest tier has
ignored the worktree path and committed on the session branch.

## 4. Reports

Every subagent runs in the background and returns at most fifteen lines:
commit hash, files touched, test result, open questions. Anything longer
goes to `<scratchpad>/parallel/task-<n>.log`. The main session never reads
a diff; reviewers do.

## 5. Review

As soon as an implementer reports, dispatch the invoking skill's reviewer
on the task branch — the studio's reviewer, or subagent-driven-development's
task reviewer — with the brief that skill would give it. Fix rounds happen
in the task worktree, with the loop and the escalation rules the invoking
skill already has.

## 6. Integrate

When the review is clean, in the session worktree:

1. Note the feature HEAD: `before=$(git rev-parse HEAD)`.
2. `git cherry-pick <first-commit>^..<last-commit>` for the task's commits.
3. Run the project's tests. On a cherry-pick conflict: `git cherry-pick
   --abort`, dispatch a fix agent to rebase the task branch onto the
   feature branch in the task worktree, then retry from step 1.
4. Verify: `git log --oneline $before..HEAD` lists exactly the
   cherry-picked commits, and `git status --porcelain` prints nothing.
   Anything else means an agent committed on the session branch — tag the
   stray commit, `git reset --hard $before`, and re-run the task.
5. `git worktree remove <scratchpad>/wt/task-<n>` and
   `git branch -D parallel/<feature>/task-<n>` — the commits are on the
   feature branch now.
6. Only now run the invoking skill's bookkeeping for the task —
   `studio-state set task n/N`, its ledger lines, its checkbox — exactly
   as it would have.

## 7. Stopping

The invoking skill's stop conditions are unchanged. `omega:handoff` pushes
any task branch not yet integrated.

## What this changes, and what it never changes

Changes: the scheduling and isolation of implementers, and the size of
what returns to the main context. Never changes: the reviewer per task,
the fix loop, the tests a task must pass, the final whole-branch review,
the state writes.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| Two implementers in the session worktree | One worktree per task; the session worktree only cherry-picks. |
| Skipping the reviewer because the task is small | Every task is reviewed on its branch before it is cherry-picked. |
| `studio-state set task` when the implementer reports | Bookkeeping runs after integration, never before. |
| Reading a task's diff in the main session | Reviewers read diffs; the main session reads fifteen-line reports. |
| Dispatching task 3 because a slot is free | A slot is filled only by a *ready* task. |

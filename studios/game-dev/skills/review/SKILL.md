---
name: review
description: Use when a branch or diff needs a spec-compliance and Godot best-practice review before playtest or ship.
---

# Review

**Announce at start:** "Using game-dev:review over <scope>."

The task-by-task reviews in `execute` catch local problems. This stage looks
at the whole branch against the whole spec, once, before anyone plays it.

## 0. Scope and preconditions

- Scope is the whole branch by default: `git merge-base <base> HEAD` to
  `HEAD`, where `<base>` is the branch the worktree was created from (ask if
  it is not obvious). The user may name a narrower scope — a commit range,
  a task number, or a path list — and that is the scope instead.
- `studio-state get spec` names the spec; read it in full. If there is no
  spec, review against the project `CLAUDE.md` rules only and say so.
- Run `studio-state set stage review`.

## 1. Baseline

Run `studio-test`. A failing suite is reviewed *first*: every failure is a
critical finding before the reviewer even reads the diff. Exit 2 or 3 is
reported to the user with the printed hint and the review continues without
the automated baseline.

Run `studio-lint`. Exit 3 means gdtoolkit is not installed — note it once
and move on; exit 1 findings are minor findings unless they hide a real
error.

## 2. Dispatch the reviewer

Dispatch `game-dev:reviewer` (`subagent_type: "game-dev:reviewer"`) with:

- the scope (`Scope: branch <name> vs <base>` or the narrower one);
- the spec path and the project `CLAUDE.md` path;
- the plan path, so it can check every `Verify: unit` task's test;
- the `studio-test` and `studio-lint` output from §1;
- the instruction "review only — do not fix".

It returns the report from its output contract: `Spec compliance`,
`Findings: N (critical c, important i, minor m)`, and one line per finding.

## 3. Fix loop

For each finding, in severity order:

- **critical** and **important**: dispatch the implementer that owns the
  file — the `Role:` of the plan task that created it, or
  `game-dev:gameplay-programmer` when no task did — with the finding line,
  the spec section it violates, and "fix this finding only; add a
  regression test when the finding is a behaviour". One commit per finding.
- **minor**: fix it the same way when it is a one-line change; otherwise
  record it as deferred.

After the fixes, run `studio-test` again and re-dispatch `game-dev:reviewer`
over the same scope. Repeat until the verdict is
`Findings: 0 (critical 0, important 0, minor 0)` with `unmet: none`, or only
deferred minors remain, or the user stops the loop. Three rounds without
reaching clean is a stop: report what keeps coming back and ask.

The user may defer any finding; a deferred finding is written to the plan's
`## Backlog` with the finding line and the reason.

## 4. State and hand-off

- `studio-state ledger "Review: <n> findings, <m> fixed, <k> deferred"` and,
  when the last verdict was clean, `studio-state ledger "review clean"`.
- `studio-state set stage playtest`.
- Print the final verdict line and the list of fix commits, then tell the
  user the next command is `/game-dev:playtest`. Do not invoke it yourself.

## Rules

- The reviewer reviews; implementers fix. Never let the reviewer edit code
  in this stage, and never fix in the main session.
- Findings are not negotiable by rewording: a finding is closed by a commit
  or by the user deferring it, not by explaining it away.
- Never run `superpowers:finishing-a-development-branch` here; merging is
  the ship stage's decision.

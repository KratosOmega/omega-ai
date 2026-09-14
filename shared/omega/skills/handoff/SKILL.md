---
name: handoff
description: Use when a session must stop or pause mid-work — context nearly full, a compaction or /clear coming, end of the day — and the work must resume in a new session without losing anything.
---

# Handoff

**Announce at start:** "Using omega:handoff to save this session's work."

Saves everything this session has done, wherever the work stands, and
prints the prompt that resumes it. Runs in every studio and in plain
`claude`. Reads the studio's state; never writes it.

## 1. Freeze

Dispatch nothing new. If a subagent is still running, ask once with
`AskUserQuestion`:

- **Wait for the current task to finish** — let the running implementer or
  reviewer complete, and record its result exactly as the invoking skill
  would have (its review, its state write, its ledger line).
- **Stop now** — stop them with the `TaskStop` tool (one call per running
  agent); whatever is on disk is handed off as in-progress.

When `omega-mode show` lists `autopilot`, do not ask: the current task
finishes.

## 2. Inventory — read only

- `git branch --show-current`; its upstream:
  `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
- `git worktree list` — per-task worktrees the `parallel` mode created
  (`wt/task-<n>` on `parallel/<feature>/task-<n>`).
- `studio-state show`, when `studio-state` is on `PATH`. Read it; never
  change it.
- The SDD ledger under `.superpowers/sdd/`, when present. It is gitignored
  in most projects, so its rulings go into the handoff file, not into git.
- `omega-mode show` — the active modes.
- The spec path, the plan path and the task pointer the invoking skill
  uses: `studio-state get spec`, `get plan`, `get task`, or the plan's
  checkboxes.
- `gh pr view --json number,url,baseRefName`, when a PR exists.
- The integration branch, when `omega-mode show` has an `integration` line.

## 3. Save

1. Every per-task worktree whose branch has commits not yet cherry-picked
   onto the feature branch:
   `git -C <worktree> push -u origin parallel/<feature>/task-<n>`.
2. In the session worktree, stage by name — `git add <path>` for each path
   `git status --porcelain` lists — and print `git diff --cached --stat`.
3. Commit:
   - tests green and no task half done: a normal message;
   - tests red, or a task half done: `wip: <what was being done>`, with a
     body that lists the failing tests and the unfinished files.

   When `git status --porcelain` prints nothing and `git log
   origin/<branch>..HEAD` is empty, there is nothing to commit — skip to
   §4; never use `--allow-empty`.
4. `git push -u origin <branch>`.
5. Verify and show: `git status --porcelain` prints nothing;
   `git log origin/<branch>..HEAD` prints nothing.

Work is never discarded. A red state is committed as `wip:`, flagged in the
handoff file and in the resume prompt, and left for the next session.

## 4. The handoff file

`docs/handoffs/<YYYY-MM-DD>-<branch-slug>.md` — every `/` in the branch
name becomes `-`. Sections, in this order:

1. **Where** — repository, worktree path, branch, base, PR.
2. **State** — stage, spec, plan, task N/M, integration branch, per-task
   branches pushed.
3. **Modes** — the `omega-mode show` lines.
4. **Done / In progress / Next** — three lists.
5. **Rulings** — from the ledgers, in order.
6. **Unverified** — playtest and visual items; anything reviewed by reading
   only.
7. **Red** — the `wip:` commit's failing tests and unfinished files, or
   "none".
8. **Verify** — the commands that prove the state: the test command,
   `git log --oneline -5`, `studio-state show`.
9. **Resume prompt** — the block from §5.

When `autopilot` is among the modes, the section after *Where* is the
**Morning report**: every ruling in order with its cost if wrong, the
unverified items, the PR link, the resume prompt.

Commit `docs(handoff): <branch> at task N/M`; push; verify as in §3.5.

## 5. The resume prompt

Print it last, short enough to paste:

```
Resume <branch> in <worktree path>.
Read docs/handoffs/<file>.md first.
Run: /omega:parallel 3, /omega:local-merge, /omega:integration status <slug>.
Optional: /omega:autopilot
Continue with /game-dev:execute — resume at task 4/6.
```

- `Run:` lists every active mode except `autopilot`, with its arguments;
  an `integration` mode becomes `/omega:integration status <slug>`, the
  slug from the `integration slug=<slug>` line the inventory (§2) read —
  the branch already exists.
- `Optional:` appears only when `autopilot` was active. The resumed session
  runs attended unless the user types it.
- The last line names the studio command that was running and where it
  resumes. No studio: `superpowers:executing-plans` with the plan path
  when installed; otherwise the plan file and the next task number.

## What this changes, and what it never changes

Changes: when the session stops. Never changes: studio state (read, never
written), the plan, the rulings already in the ledger.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| Reverting red work to keep history clean | `wip:` commit; list what is red. |
| Staging everything at once | Stage by name; show the staged stat. |
| "Continue where we left off" as the prompt | Name the worktree, the file, the modes, the command and the task. |
| Marking the state "handed off" | There is no such stage; state is read only. |
| Leaving a task branch only on disk | Push every un-integrated `parallel/…` branch. |

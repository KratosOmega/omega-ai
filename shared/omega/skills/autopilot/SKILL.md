---
name: autopilot
description: Use when a long run must proceed with nobody at the keyboard — an overnight session, or any run where no question can be answered until it ends.
---

# Autopilot

**Announce at start:** "Using omega:autopilot — pre-flight first."

`off`: `omega-caffeine stop`, `CronDelete` the heartbeat (`CronList` finds
it), `omega-mode clear autopilot`, then stop. `omega-mode` and
`omega-caffeine` are on `PATH` inside a studio; the session-start line
names their paths otherwise.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

Two phases. Phase 1 is interactive and ends by setting the mode. Phase 2
is what the mode means while it is set.

## Phase 1 — pre-flight, interactive

Phase 1 runs with no `autopilot` mode: `omega-mode show` must not list
it; when it does (a previous run's leftover), disarm first — the
**Disarm** bullet of phase 2: `omega-caffeine stop`, `CronDelete` any
heartbeat, then `omega-mode clear autopilot`.

1. **Design and plan as the studio does.** `/game-dev:brainstorm` then
   `/game-dev:plan` in the game studio; `superpowers:brainstorming` then
   `superpowers:writing-plans` when installed and no studio is present;
   otherwise a spec and a plan written by hand and approved by the user.
   Their approval gates stand.
2. **Question sweep.** Read the approved spec and plan. List every decision
   the implementation could still meet: naming, error handling, test depth,
   tie-breaks between two acceptable patterns, what to do when a tool is
   missing, which of two libraries. An item the spec calls open stays in
   the sweep until the plan's own `## Decisions` section answers it — a
   committed file, an existing ledger entry, or any other trace of a prior
   run is not a substitute; ask it again. Ask all of them, three or four
   per `AskUserQuestion`, until none is left. Write each answer into the
   plan under a `## Decisions` section (add it after Global Constraints
   when absent), so phase 2 reads the plan, not memory.
3. **Commit and push** the spec, the plan and the ledger:
   `git add <spec> <plan> <ledger paths>`,
   `git commit -m "docs: approve <topic> for autopilot"`,
   `git push -u origin <branch>`.
4. **Update the story**, when a tracker is detectable from the branch name:
   - `KAN-<n>` → Jira, through the Atlassian MCP when its tools are in the
     tool list: a comment with the dependency list and links to the spec
     and the plan.
   - a leading `<n>-` or `issue-<n>` → `gh issue comment <n> --body "…"`
     with the same text.
   - The dependency list comes from `docs/integrations/<slug>.md` when
     `omega-mode show` has an `integration` line; otherwise "none".
   - No tracker: the same text goes into the plan header, and the
     readiness checklist says so.
5. **Readiness checklist.** Print it; every line must pass:
   - on the feature branch, in a worktree — `git branch --show-current`,
     and `git rev-parse --show-toplevel` is not the main checkout;
   - the plan is approved and committed — `git log -1 --format=%h -- <plan>`
     prints a hash and `git status --porcelain -- <spec> <plan>` prints
     nothing;
   - the baseline test run is green — the project's test command, `exit 0`;
   - `gh auth status` succeeds;
   - the engine or runtime binary the plan needs resolves — `studio-test`
     or `GODOT_PATH` in the game studio, the tool the plan names otherwise;
   - no unanswered question remains — the `## Decisions` section covers
     every item of the sweep.

   A failed line stops here; fix it and print the checklist again.
6. **Arm.** In this order, once every checklist line passes:
   1. `omega-mode set autopilot`.
   2. `omega-caffeine start` — report its line. `running <pid>` means the
      machine stays awake for twelve hours; `unsupported` is a warning,
      not a stop: the machine may sleep, and the run resumes from the
      last push.
   3. `CronCreate` the heartbeat: cron `17,47 * * * *`, recurring, prompt
      verbatim:
      `Autopilot heartbeat. Run omega-mode show. If it does not list autopilot: CronDelete this job and stop. Otherwise re-invoke the run's execution skill on the next unfinished task per omega:autopilot phase 2; ask nothing.`
      It fires only while the session is idle — a turn that ended early
      gets its nudge within half an hour, a running turn costs nothing —
      and expires after seven days. The nudge re-invokes the execution
      skill; it never has the fresh turn do a task by hand, as the
      precedence block says.
   4. Tell the user to start the run — `/game-dev:execute`, or the plan's
      execution skill — saying in the same message what the run may do
      (commit; push after every task; open a draft PR; write the handoff)
      and may not do (merge; force-push; delete a remote branch;
      destructive or security-sensitive operations; read or write
      secrets), that the permission mode must allow the run's tools
      unattended — a permission prompt is a question nobody answers — and
      that if the run is not started by then, the
      heartbeat starts it at the next :17 or :47 — switch the permission
      mode before that.

   A resumed session that finds `autopilot` already set (a crash, not a
   leftover — the handoff file names the run) repeats steps 2–3; the
   heartbeat is session-only and does not survive a restart.

## Phase 2 — unattended

While `omega-mode show` lists `autopilot`:

- **No questions.** `AskUserQuestion` is never called. An open decision is
  settled by, in this order: the studio's `CLAUDE.md`; the shared
  engineering standards; superpowers' conventions when installed; industry
  practice. Log the ruling **as one line** — decision, why and cost if
  wrong all in that single line, never spread across a wrapped paragraph,
  so `grep 'Ruling:'` finds the whole thing — where the invoking skill
  logs rulings: `studio-state ledger "Ruling: <decision> — <why> — <cost
  if wrong>"`, or the SDD ledger, or the plan's `## Decisions` section
  when neither exists — and continue.
- **Allowed side effects:** commit; `git push` after every integrated
  task, so a crash loses at most one task; `gh pr create --fill --draft`
  when the plan is complete — base per `omega:local-merge` §3 (the
  integration branch when an `integration` mode is set, else the
  repository's default branch);
  `gh pr comment`; the handoff.
- **Forbidden:** never merge — with `local-merge` set, its merge step is
  skipped and reported; never force-push; never delete a remote branch; no
  destructive or security-sensitive operation; no reading or writing of
  secrets.
- **Hard stops:** the invoking skill's own — a destructive or
  security-sensitive operation the plan requires, or a plan too broken to
  follow. On one, run `omega:handoff` without its question (the current
  task finishes), disarm, then stop.
- **Completion:** run `omega:handoff`. Its file carries the morning report
  after *Where*: every ruling in order with its cost if wrong, the
  unverified items, the PR link, the resume prompt. Then disarm.
- **Disarm**, after the handoff on either ending, in this order:
  `omega-caffeine stop`; `CronDelete` the heartbeat;
  `omega-mode clear autopilot`. Clearing the mode is what lets a heartbeat
  that was not deleted end itself: its next firing finds no `autopilot`
  line and stops.

The run always ends with `omega:handoff`, then the disarm.

## What this changes, and what it never changes

Changes: when questions are asked, what happens when one would arise, and
which side effects run unattended. Never changes: the studio's stages and
gates, the reviewer per task, the tests.

## Red flags — phase 2 is about to break

| Thought | Reality |
|---------|---------|
| "This one question is quick" | No question is quick at 3 a.m. Rule and log. |
| "The user would obviously want it merged" | Never merge. Open the draft PR. |
| "I'll push at the end" | Push after every integrated task. |
| "Two options are equally fine, I'll just pick" | Picking is fine; picking *without a logged ruling* is not. |
| "I'll explain the cost in the next paragraph" | The cost if wrong goes on the Ruling line itself, or a plain grep for it fails. |
| "A file's already committed this way, drop the question" | Only the plan's `## Decisions` section retires a swept item — a commit or a ledger entry from a prior run does not. |
| "The plan is unclear, I'll stop and ask" | Unclear is a ruling; *broken* is a hard stop. Decide which, log it. |
| The hook block already says `autopilot` while questions are still open | Disarm (stop, `CronDelete`, clear); the mode is set only when the checklist passes. |
| "The run is done, the heartbeat can stay" | A live heartbeat with no run spends a turn every 30 minutes until the session ends. Disarm. |

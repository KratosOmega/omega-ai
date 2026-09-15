---
name: delegate
description: Use when the main session must stay a command deck — it talks to the user, dispatches subagents, reads their reports and runs status commands, and every edit, search and document goes to a subagent, never done by hand.
---

# Delegate

**Announce at start:** "Using omega:delegate."

Run first: `omega-mode set delegate` — `omega-mode clear delegate` for
`off`. `omega-mode` is on `PATH` inside a studio; the session-start line
names its path otherwise. The hook already set the mode when the command
was typed; running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

While `delegate` is set, the main session is a command deck. It decides,
dispatches, reads and verifies. It does not edit, search or write.

## 1. The deck

The main session **may**:

- Talk to the user — replies, `AskUserQuestion` (never under `autopilot`),
  the invoking skill's approval gates.
- Dispatch subagents with `Agent`, continue them with `SendMessage`, stop
  them with `TaskStop`, and read what they return.
- Run a status command — `git`, `gh`, the project's test or local-CI
  command, `doctor.sh`, `omega-mode`, `omega-caffeine`, `studio-state`.
  Long output goes to `<scratchpad>/delegate/<label>.log`; read only its
  tally or status line and the exit code.
- Read a file a subagent produced for the user's approval — the spec, the
  plan, the handoff file. Nothing else under the repository.
- Write bookkeeping under the scratchpad: `parallel`'s `waves.md`, the logs
  above, a brief kept for a redispatch.

The main session **never**:

- Calls `Edit`, `Write` or `NotebookEdit` on a path under the repository —
  any path inside `git rev-parse --show-toplevel`.
- Calls `Read`, `Grep` or `Glob` on repository source — any file that is
  not one of the approval artifacts above. A lookup is an investigator's
  job.
- Writes a spec, a plan, a document, a test or code.
- Fixes a failing subagent's work by hand — never fix by hand. Redispatch
  with the failure text (the failing lines of the report, the reviewer's
  findings). After three failed rounds on one task, ask the user; under
  `autopilot`, log a ruling and move to the next task the plan allows.

`<scratchpad>` is the session's scratchpad directory when Claude Code
prints one; otherwise `$(mktemp -d)`, created once and recorded in
`<scratchpad>/delegate/README`.

## 2. Routing

| Work | Goes to |
|------|---------|
| Where is X, what calls Y, what does this file contain | `Explore`; `caveman:cavecrew-investigator` when installed. Locations and facts, never a fix. |
| A spec, a plan, a document, a handoff file | A writer agent — `fork` when the dialogue matters, else `general-purpose` with the brief. |
| A task | The studio's role agent when the invoking skill names one, else `general-purpose`; never below the mid tier (sonnet) in a per-task worktree. |
| A review | The invoking skill's reviewer — the studio's, or `superpowers:subagent-driven-development`'s task reviewer when installed, else a `general-purpose` reviewer given the task text and the diff range. |
| Verification | The main session, as a status command. |

With superpowers installed: `superpowers:brainstorming`'s dialogue runs
here and its spec file is written by a writer agent given the approved
design; `superpowers:writing-plans` runs in a planner agent (a `fork`) and
the plan comes back for approval; `superpowers:subagent-driven-development`
runs unchanged; `superpowers:executing-plans` is never used under this
mode — it is the inline mode. Without superpowers the same table applies
to a plan followed by hand.

## 3. Briefs

A brief says: the task text or where it is in the plan; the worktree path
and the branch — work only in `<path>`, commit only on `<branch>`, verbatim
and lower-case as `parallel` writes them; the report cap below; and never
run `omega-mode set` or `clear` — a subagent shares this session's id and
would change its modes.

## 4. Reports

At most fifteen lines back: commit hash, files touched, test result, open
questions. Anything longer goes to `<scratchpad>/delegate/<label>.log` and
the report names the path. The main session never reads a diff; a reviewer
does, and returns findings.

## 5. Gates

Gates are status commands and the main session runs them: the test suite
before a merge, `git status --porcelain` before a cherry-pick, `gh pr
view` before a PR. Pipe, read the last line and the exit code, decide.
Delegating a gate would put the evidence second-hand; running it is not
work.

## 6. With the other modes

- `parallel` already dispatches implementers and reviewers; this mode
  covers everything else. Its cherry-pick, test run and verification are
  status commands.
- `local-merge`'s search for the local CI procedure goes to an
  investigator; its run, PR and merge steps are commands.
- `integration start` and `add` edit `docs/integrations/<slug>.md` through
  a writer agent; the main session commits and pushes.
- `autopilot`'s question sweep is listed by an investigator, asked here,
  and recorded in the plan by a writer agent. Three failed rounds become a
  ruling, not a question.
- `handoff`'s file reads go to an investigator, its file to a writer
  agent; its commands and its commit and push stay here.

## 7. Stopping

The invoking skill's stop conditions are unchanged. `omega:handoff` lists
`delegate` on its `Run:` line.

## What this changes, and what it never changes

Changes: who performs each step — the main session commands, subagents
work. Never changes: the invoking skill's stages and gates, the reviewer
per task, the tests a task must pass, the state writes.

## Red flags — the deck is about to pick up a tool

| Thought | Reality |
|---------|---------|
| "It's a one-line fix, faster to do it here" | A one-line fix here is the first of many. Redispatch with the line. |
| "I need to read the file to write the brief" | Ask an investigator for the facts the brief needs. The brief names files; it does not quote them. |
| "The agent failed twice, I'll just finish it" | Redispatch with the failure text. Three rounds, then the user — or a ruling under autopilot. |
| "Tests are work, delegate them too" | Gates are status commands; the main session runs them so the evidence is first-hand. |
| "The reviewer's diff is short, I'll skim it" | Reviewers read diffs and return findings. The deck reads findings. |
| "The plan is approved, executing-plans is right here" | That is the inline mode. Use subagent-driven-development, or dispatch per task by hand. |

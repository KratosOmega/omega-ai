# omega-ai Delegate Mode — Design

Date: 2026-09-15
Status: Approved for planning
Extends: `2026-09-13-global-skills-design.md` (the sixth mode of the `omega`
overlay; everything that spec says about packaging, the mode file, the hooks
and the precedence contract applies unchanged)

## Purpose

A long session in any studio drifts the same way: the main session starts
by dispatching subagents, then reads one file "to write a better brief",
then makes one "one-line" fix itself, and an hour later its context is full
of diffs, test output and half-read source. The work still gets done, but
the session that was supposed to coordinate is now doing everything, and
the next compaction loses the thread.

This design adds a mode, `delegate`, under which the main session is a
**command deck**: it talks to the user, dispatches subagents, reads their
reports, and runs commands whose output is a status. Every edit, every
search of the repository and every document goes to a subagent. Nothing is
fixed by hand. The mode is a rulebook plus the hook-injected mode line, like
the other five, with one addition: a PreToolUse guard hook that denies an
edit under the repository when it comes from the main session while the
mode is set.

Non-goals:

- It is not a router. The mode never classifies a request and dispatches
  it on the invoking skill's behalf; the invoking skill keeps running and
  this mode shapes how each of its steps is carried out. That is the
  precedence contract every mode carries.
- It changes no gate. Approvals, reviewers, tests, `Verify:` rules and state
  writes happen exactly as the invoking skill says — the difference is who
  does the typing.
- No Windows-specific hook logic. The guard hook is POSIX `sh` like every
  other file under `shared/omega`; where it cannot resolve a path it allows
  the call.
- No model table beyond the one floor `parallel` already states: an agent
  working in a per-task worktree is never below the mid tier (sonnet).

## What done looks like

1. `/omega:delegate` sets the mode and `/omega:delegate off` clears it, from
   a typed command (the UserPromptSubmit hook) and from the Skill tool (the
   skill's opener), exactly as `parallel` does. Every following turn begins
   with `Omega modes: delegate` and its rule line.
2. Under the mode, a one-file task from a plan is implemented by a
   dispatched subagent; the main session's own tool calls contain no `Edit`,
   `Write`, `NotebookEdit`, `Read`, `Grep` or `Glob` against the repository.
   The pressure scenario in `docs/omega/pressure/delegate.md` proves it, and
   its baseline shows the same prompt without the skill editing inline.
3. When the spike passes, an `Edit`, `Write` or `NotebookEdit` issued by the
   main session against a path under the repository, while `delegate` is
   set, is denied by `hooks/pre-tool-use.sh` with a reason that names the
   mode; the same call from a subagent, or against a path outside the
   repository, or with the mode off, is allowed. The hook prints nothing
   and exits 0 in every other case.
4. `delegate` composes with `parallel`, `local-merge`, `integration`,
   `autopilot` and `handoff` with no pair in conflict; the section "With
   the other modes" below says what each pair looks like.
5. `sh tests/run_all.sh` passes and covers the hook's deny and allow cases,
   the prompt-submit set and clear cases, the brief line, the text contract
   and the plugin manifests naming the sixth skill.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Name | `delegate`. Typed as `/omega:delegate [off]`; the mode line is `delegate`. |
| 2 | Reading | Strict. The main session never `Read`s, `Grep`s or `Glob`s repository source. It reads subagent reports, files a subagent produced for the user's approval (a spec, a plan, a handoff file) and the status line of a command's output. A lookup goes to an investigator agent. |
| 3 | Gates | The main session runs status-only commands itself: `git`, `gh`, the project's test or local-CI command, `doctor.sh`, `omega-mode`, `studio-state`. Output is piped to a file under the scratchpad and only the tally or status line is read. Evidence for a merge or a PR is first-hand. |
| 4 | Enforcement | Text plus hook. The skill text and the mode line carry the rules as every mode does; `hooks/pre-tool-use.sh` denies repository edits from the main session when the spike (row 14) confirms the hook can tell main from subagent. |
| 5 | Repository boundary | "Under the repository" means any path that resolves inside `git rev-parse --show-toplevel` run in the session's `cwd`. In a worktree that is the worktree. |
| 6 | Scratchpad | The directory Claude Code prints in its environment block; otherwise `$(mktemp -d)`, created once and recorded in `<scratchpad>/delegate/README` so later turns reuse it. Scratchpad writes are allowed in the main session — `parallel`'s `waves.md`, the logs below. |
| 7 | Failure loop | A failed subagent is redispatched with the failure text (the report's failing lines, the reviewer's findings). After three failed rounds on one task the main session asks the user; under `autopilot` it logs a ruling and moves to the next task the plan allows. The main session never finishes the work itself. |
| 8 | Models | No table. The invoking skill's choice stands — `superpowers:subagent-driven-development`'s Model Selection when installed — with `parallel`'s floor: never below sonnet for an agent in a per-task worktree. |
| 9 | Superpowers | Brainstorming's dialogue stays in the main session (talking to the user is the deck's job); the spec file is written by a writer agent. `writing-plans` runs in a planner agent. `subagent-driven-development` is unchanged. `executing-plans` is not used: it is the inline mode, the thing this mode exists to prevent. |
| 10 | Reports | At most fifteen lines: commit hash, files touched, test result, open questions. Longer output goes to `<scratchpad>/delegate/<label>.log`. The main session never reads a diff; reviewers do. |
| 11 | Brief line | `delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand.` |
| 12 | Hook output | On deny: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"omega:delegate — the main session edits nothing under the repository; dispatch a subagent"}}` on one line, exit 0. |
| 13 | Hook fails open | On any other case — no session id, no mode file, `delegate` absent, a subagent's call, a path outside the repository, a path it cannot resolve, `cwd` not in a git repository, empty or unparsable stdin — the hook prints nothing and exits 0. A hook that blocked a subagent or a plain session would be worse than no hook. |
| 14 | Spike outcome | **Passed** (Claude Code 2.1.272, 2026-09-15, harness: `--restricted --settings` against the user's own config — the throwaway `CLAUDE_CONFIG_DIR` had no credentials on this machine; `--permission-mode acceptEdits` was substituted for `bypassPermissions`, which this build refuses under `--restricted`). `transcript_path` did **not** distinguish the calls: the subagent's `Write` and the main session's `Write` carried the identical path (e.g. `/Users/xinli/.claude/projects/-private-tmp-claude-501--Users-xinli-Documents-GameDev--practice-omega-ai-ec635308-4811-47dd-b5d4-4b3de239deb0-scratchpad-delegate-spike-work/f0b51e18-b05e-4527-abb8-8ce1dfc3c9de.jsonl`) — this build does not split subagent transcripts into a `/subagents/` path. A different field did distinguish them: the subagent's record carried `agent_id` (e.g. `a2019ca04b5b8095d`) and `agent_type` (`general-purpose`); the main session's record had neither key at all. Confirmed reproducible across two independent runs (two different session IDs, two different `agent_id` values, same pattern both times). Record keys: `agent_id, agent_type, cwd, effort, hook_event_name, permission_mode, prompt_id, session_id, tool_input, tool_name, tool_use_id, transcript_path` (`agent_id`/`agent_type` present only on subagent-originated calls). `tool_input` keys: `content, file_path`. The hook ships (Task 3), gating on the presence of `agent_id`/`agent_type` rather than a `transcript_path` shape. The guard-hook, tests and pressure sections below were rewritten to the `agent_id` signal after this outcome. |
| 15 | Manifests | `plugin.json`, `marketplace.json`, the SessionStart line and the README all name six skills; the SessionStart line adds `/omega:delegate [off]`. |
| 16 | Pressure harness | The pressure scenario logs every PreToolUse call through a throwaway `CLAUDE_CONFIG_DIR` whose `settings.json` appends the hook's stdin to a file — the same harness as the spike — so "the main session never edited" is read from a log, not from the model's report. |
| 17 | Investigators | `Explore` is the investigator; `caveman:cavecrew-investigator` when installed (its output is compressed). An investigator returns locations and facts, never a fix. |
| 18 | Handoff under delegate | The handoff file is written by a writer agent given the inventory; the main session commits and pushes it. Inventory items that need a file read (the plan's task pointer, the SDD ledger) come from an investigator; the rest are commands. |

## Packaging and loading

Only the additions to the tree in the 2026-09-13 spec:

```
shared/omega/
├── skills/delegate/SKILL.md        the rulebook (full text below)
├── hooks/
│   ├── hooks.json                  gains PreToolUse, matcher Edit|Write|NotebookEdit
│   └── pre-tool-use.sh             the guard hook (self-contained, no lib/)
└── bin/omega-mode                  mode_brief gains the delegate line
docs/omega/pressure/delegate.md     the pressure scenario
tests/omega_contracts/delegate_contract.sh
tests/pressure/fixture.sh           gains the `delegate` kind
```

`plugin.json` and `marketplace.json` descriptions become "…: handoff,
parallel, local-merge, integration, autopilot, delegate." The SessionStart
line becomes `Omega global skills: /omega:handoff, /omega:parallel [N|off],
/omega:local-merge [off], /omega:integration <start|add|status|finish>,
/omega:autopilot [off], /omega:delegate [off].`; the Mode tool and Keep-awake
sentences are unchanged.

## The toggle

`/omega:delegate` sets `delegate` with `omega-mode set delegate`;
`/omega:delegate off` clears it. `prompt-submit.sh` gains a `delegate` case
identical in shape to `local-merge`'s: `off` clears, an empty argument sets,
anything else is ignored. The skill opens by running the same command, so
the Skill-tool path converges on the file as every mode does. `mode_brief`
prints the rule line of row 11 when the file lists `delegate`; the brief
test's line count grows by one when the mode is set alongside the four
others.

## The command deck

While `delegate` is set, the main session **may**:

- Talk to the user: replies, `AskUserQuestion` (never under `autopilot`, as
  that mode says), the approval gates of the invoking skill.
- Dispatch subagents (`Agent`), continue them (`SendMessage`), stop them
  (`TaskStop`), and read what they return.
- Run status commands: `git`, `gh`, the project's test or local-CI
  command, `doctor.sh`, `omega-mode`, `omega-caffeine`, `studio-state`. A
  command whose output can be long — the test suite, `git log` over a
  range — is piped to `<scratchpad>/delegate/<label>.log` and only its
  tally or status line is read (`tail -n 1`, `grep -c`, the exit code).
- Read a file a subagent produced for the user's approval: the spec, the
  plan, the handoff file. Nothing else under the repository.
- Write bookkeeping under the scratchpad: `parallel`'s `waves.md`, the logs
  above, a brief saved for a redispatch.

The main session **never**:

- Calls `Edit`, `Write` or `NotebookEdit` on a path under the repository.
- Calls `Read`, `Grep` or `Glob` on repository source — a file that is not
  one of the approval artifacts above.
- Writes a spec, a plan, a document, a test or code. Each is a writer's or
  an implementer's job.
- Fixes a failing subagent's work by hand. It redispatches with the failure
  text; after three failed rounds on one task it asks the user, or under
  `autopilot` logs a ruling and moves on (row 7).

"Under the repository" is row 5; "scratchpad" is row 6.

## Routing

| Work | Goes to |
|------|---------|
| Find where something is, what calls it, what a file contains | `Explore`; `caveman:cavecrew-investigator` when installed. Returns locations and facts, never a fix. |
| Write a spec, a plan, a document, a handoff file | A writer agent: `fork` when the dialogue that produced the design matters, else `general-purpose` with the brief. |
| Implement a task | The studio's role agents when the invoking skill names one, else `general-purpose`; never below sonnet in a per-task worktree. |
| Review | The invoking skill's reviewer: the studio's, or `superpowers:subagent-driven-development`'s task reviewer when installed, else a `general-purpose` reviewer given the task text and the diff range. |
| Verify | The main session, as a status command (row 3). |

With superpowers installed: `superpowers:brainstorming`'s dialogue runs in
the main session and its spec file is written by a writer agent given the
approved design; `superpowers:writing-plans` runs in a planner agent (a
`fork`, so it has the spec discussion) and the plan comes back for
approval; `superpowers:subagent-driven-development` runs unchanged — it
already dispatches one implementer and one reviewer per task;
`superpowers:executing-plans` is never used under `delegate`, because it is
the inline mode: the session that runs it does the tasks itself. Without
superpowers the same routing applies to a plan followed by hand.

## Briefs and reports

A brief carries: the task text or its location in the plan; the worktree
path and the branch, with "work only in `<path>`" and "commit only on
`<branch>`" verbatim as `parallel` §3 has them; the report cap; and "never
run `omega-mode set` or `clear`" — a subagent shares the session's id and
would change its modes.

A report is at most fifteen lines: commit hash, files touched, test result,
open questions. Anything longer goes to `<scratchpad>/delegate/<label>.log`
and the report names the path. The main session never reads a diff — a
reviewer does, and returns findings, not the diff.

## With the other modes

No pair conflicts. Each existing mode governs scheduling, merge mechanics or
stopping; `delegate` governs who does each step. The precedence block below
is the one every mode carries, and `delegate` carries it verbatim.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

**parallel.** Already dispatches one implementer and one reviewer per task
and caps their reports; `delegate` adds nothing at dispatch time. It covers
what `parallel` leaves to the main session: the plan itself, a conflict fix
(`parallel` §6 already dispatches a fix agent), any document. `waves.md` is
scratchpad bookkeeping and stays legal. The cherry-pick, the test run and
the verification in `parallel` §6 are status commands and stay in the main
session.

**local-merge.** Its step 1 — find the local CI procedure in the project's
docs — is a read of repository files: under `delegate` an investigator
returns the command. Steps 2 to 5 are commands (`run it`, `gh pr view`,
`gh api`, `gh pr merge`) and stay in the main session, with the run's
output piped to a log and its exit code read.

**integration.** `start` and `add` write `docs/integrations/<slug>.md`:
under `delegate` a writer agent edits the file and the main session commits
and pushes. `status` and `finish` are commands and `finish` lands through
`local-merge`'s rules as above.

**autopilot.** Phase 1's question sweep reads the spec and the plan: an
investigator lists the open decisions, the main session asks them, and a
writer agent records the answers in the plan's `## Decisions` section.
Phase 2 is unchanged — no questions — and the three-round rule becomes a
ruling, logged where autopilot logs rulings, after which the run moves to
the next task the plan allows. The heartbeat's re-invocation of the
execution skill is unaffected.

**handoff.** Row 18: the inventory's commands run in the main session, the
file reads go to an investigator, the handoff file is written by a writer
agent, and the main session commits and pushes it. Its resume prompt lists
`delegate` on the `Run:` line like any other mode.

## The guard hook

`shared/omega/hooks/pre-tool-use.sh`, registered in `hooks/hooks.json`
under `PreToolUse` with matcher `Edit|Write|NotebookEdit`. Self-contained
POSIX `sh`, `set -u`, no `lib/`, in the style of the three existing hooks.

It reads from the JSON on stdin: `session_id`, `transcript_path`, `cwd`,
`tool_name`, `agent_id`, and `tool_input.file_path` (or
`tool_input.notebook_path` for `NotebookEdit`). The session id falls back
to `$CLAUDE_CODE_SESSION_ID` as the other hooks do. Field extraction uses
the same `sed -n 's/.*"key"…'` pattern as `session-start.sh`; the values
the hook needs never contain an escaped quote (a path with a `"` in it is
not something this repository supports anywhere else either).

It **denies** when all three hold:

1. the session's mode file lists `delegate` (`omega-mode --session <id>
   show` has a line whose first field is `delegate`);
2. the call is not a subagent's: `agent_id` is absent or empty **and**
   `transcript_path` does not contain `/subagents/`. The spike (row 14)
   found that on Claude Code 2.1.272 a subagent's PreToolUse record and the
   main session's carry the identical `transcript_path` — neither has a
   `/subagents/` segment — while `agent_id` (and `agent_type`) are present,
   non-empty, only on the subagent's record and absent — not merely empty —
   from the main session's. The `/subagents/` form is kept as a second
   signal so a future build that moves to per-agent transcripts still never
   blocks a subagent;
3. the target path resolves under the repository: `root=$(git -C "$cwd"
   rev-parse --show-toplevel)`; a relative path is taken against `cwd`; the
   directory part is resolved with `cd … && pwd -P` when it exists,
   otherwise the path is used as given; the result denies when it equals
   `root` or starts with `root/`.

The deny output is row 12. Every other case — including step 3 failing
because `cwd` is not a git repository or the path cannot be resolved —
prints nothing and exits 0 (row 13). The hook must be cheap: it checks the
mode file first and exits before any `git` call when `delegate` is not set,
because it runs on every edit in every session, mode or no mode.

The hook does not deny `Read`, `Grep` or `Glob`: reading is a text rule.
It does not deny edits under a `parallel` task worktree in the scratchpad —
those are outside the repository root by construction — and the text rule
still forbids them from the main session.

### The spike

The plan's first task, before any hook is written. In a throwaway
`CLAUDE_CONFIG_DIR`, `settings.json` registers a PreToolUse hook with
matcher `Write|Edit` whose command appends its stdin and a newline to
`<dir>/hook.log` and exits 0. Then `claude -p`, with a permission mode that
allows the calls, is given a prompt that (a) dispatches one
`general-purpose` subagent with the Agent tool to write `<dir>/sub.txt` and
(b) afterwards writes `<dir>/main.txt` itself. The log contained two
records; the spike passed, but not on the signal it set out to check —
see row 14. Both records carried the identical `transcript_path` (no
`/subagents/` segment on either), so that signal alone would not have
distinguished them; `agent_id` (and `agent_type`) did, present and
non-empty only on the subagent's record and absent — not merely empty —
from the main session's. Both records' full JSON — field names, not
values — are recorded in Decisions row 14 together with the Claude Code
version. Had the subagent's record been indistinguishable from the main
session's on every field, the hook would have been dropped: rows 4, 12
and 13 struck through, `hooks.json` and the test file left as they were,
and the mode shipped text-only.

## Tests

`tests/omega_test.sh`:

- `test_hooks_json` gains: `hooks.json` registers `PreToolUse` with matcher
  `Edit|Write|NotebookEdit` running `pre-tool-use.sh` from the plugin root.
- `test_pre_tool_use`, new, with a temporary git repository as `cwd` and a
  temporary `CLAUDE_CONFIG_DIR`: with `delegate` set for session `d1`,
  (a) a `Write` whose `file_path` is inside the repository, whose
  `transcript_path` is `<x>/d1.jsonl` and which carries no `agent_id`
  prints the deny JSON (valid JSON, `permissionDecision` `deny`, reason
  contains `omega:delegate`) and exits 0; (b) the same record but with
  `agent_id` `a1` and the same main `transcript_path` prints nothing — a
  subagent's `Write` is allowed by its `agent_id`; (c) no `agent_id` but
  `transcript_path` `<x>/d1/subagents/agent-a1.jsonl` also prints nothing —
  a subagent's transcript path alone still allows; (d) a record with
  `agent_id` set to the empty string and the main `transcript_path` is
  still denied — an empty `agent_id` is not a subagent. Also: a
  `file_path` under a temporary directory outside the repository prints
  nothing; a relative `file_path` that resolves inside the repository is
  denied; `NotebookEdit` with `notebook_path` inside the repository is
  denied; with the mode cleared the first call prints nothing; with
  `parallel` set but not `delegate` it prints nothing; a `Read` with the
  same fields prints nothing; empty stdin and `{garbage` print nothing and
  exit 0; a `cwd` that is not a git repository prints nothing.
- `test_prompt_submit` gains: the envelope for `/omega:delegate` writes
  `delegate`; `/omega:delegate off` clears it; `/omega:delegate 3` changes
  nothing.
- `test_mode_brief` gains the delegate rule line (row 11, exact match) and
  the line count with five modes set.
- `test_session_start` asserts the six-skill line.
- `test_plugin_files` and `test_skill_stubs` loop over six skills;
  `plugin.json` and `marketplace.json` descriptions name `delegate`.

`tests/omega_contracts/delegate_contract.sh` asserts the skill contains:
`omega-mode set delegate`; the precedence contract's first sentence;
`never fix by hand`; the edit prohibition (`` Calls `Edit`, `Write` or
`NotebookEdit` on a path under the repository ``); the search prohibition
(`` Calls `Read`, `Grep` or `Glob` on repository source ``); `fifteen lines`;
`Explore`; `sonnet`; `status command`; `redispatch`; `three`; `never reads
a diff`; `executing-plans`; `writing-plans`; `subagents/` is **not**
required (the hook is not the skill's business); and `assert_not_contains`
for `Work only in` capitalised, the pitfall `parallel`'s own text names.

`tests/pressure/fixture.sh` gains the `delegate` kind: `<dir>/repo` on
`greet` with `docs/plans/greet.md` holding one task (`Files: hello.sh`;
create it, executable, printing `hello`), plus `<dir>/cfg/settings.json`
with the logging PreToolUse hook (matcher `.*`, appending to
`<dir>/hook.log`) so the run's tool calls are on disk.

`docs/omega/pressure/delegate.md`, in the shape of `parallel.md`. Prompt
(with skill: the hook's block `Omega modes: delegate` and its rule line,
then "You have this skill loaded. Follow it exactly." and the full skill
text): "Implement Task 1 of docs/plans/greet.md in `<dir>/repo` on branch
`greet`. The scratchpad directory is `<dir>/scratch`. Report in at most
fifteen lines." Pass criteria: `<dir>/repo/hello.sh` exists, is
executable, prints `hello`, and is committed on `greet`; in
`<dir>/hook.log` every record whose `transcript_path` does not contain
`/subagents/` has a `tool_name` other than `Edit`, `Write`,
`NotebookEdit`, `Read`, `Grep` and `Glob`; at least one such record has
`tool_name` `Agent`; the report is at most fifteen lines. The baseline (no
skill, no mode line) is expected to `Write` `hello.sh` from the main
session; its record proves the harness sees main-session writes.

## Docs

The README's "Global skills" table gains the row: `/omega:delegate` — "The
main session only dispatches, reads reports and runs status commands;
every edit, search and document goes to a subagent, never fixed by hand;
`off` clears it" — and its "five skills" wording becomes six. The
2026-09-13 spec's Decisions table gains row 19, `Delegate`, pointing at
this file. `docs/omega/PROGRESS.md` gets a log entry at delivery naming
the PR and the spike outcome.

## Delivery

One plan: the spike first, then the hook and its tests (or their removal
from scope per the spike), then the skill written with
`superpowers:writing-skills` — pressure scenario, baseline run, skill,
with-skill run — then the manifests, the prompt-submit case, the brief
line, the contract, the docs. Every task is implemented by a subagent,
which is also the first real use of the mode.

## `/omega:delegate [off]` — the skill

The full text of `shared/omega/skills/delegate/SKILL.md`:

````markdown
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
````

## Out of scope

- Denying reads from the hook. Reading stays a text rule; a hook that
  denied `Read` would also deny reading the spec the user is about to
  approve.
- A per-agent allowlist or a model table.
- Any change to studio skills or to superpowers.
- Windows.

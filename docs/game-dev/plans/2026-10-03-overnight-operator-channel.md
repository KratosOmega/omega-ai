# Overnight Operator Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Draft — awaiting user review

**Goal:** A live overnight run gets a command channel and an event log. The
operator can send messages, retire them, hold a story, resume it and stop it
(`say`, `unsay`, `said`, `hold`, `resume`, `stop <story>`, `--run`). A stop
rule now holds the story instead of ending it. A `PostToolUse`/`SessionStart`
hook delivers the messages into the unit's main session. Every fact is
appended to `events.jsonl`, which any tool can read.

**Architecture:** Three new files and one sourced file:
- `bin/studio-event` appends one versioned JSON line. It is the only writer
  of `events.jsonl`.
- `hooks/operator-inbox.sh` claims pending messages with an atomic `mv` and
  prints the delivery block.
- `bin/overnight-channel.sh` is sourced by `studio-overnight` before its
  dispatch. It holds the verbs and the inbox helpers that the runner shares.

The verbs never write story state. They write only:
- `inbox/<story>/<id>.msg`
- `control/<story>.hold|.resume|.stop`

The runner reads these files at unit boundaries and polls:
- `story_units` checks the controls at the top of every pass.
- After `story_units`, a hold loop (`holdable`, then `hold_wait`) runs in
  both single-plan and lane mode.
- After every unit, `requeue_check` moves unrecorded directives back to
  pending.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2), awk, sed, git,
Claude Code 2.1.288 hooks (`SessionStart`, `PostToolUse`), and bash-as-sh
tests (`tests/assert.sh`) with the stub `claude` of the two runner suites.

**Spec:** `docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`
(approved, revision 4)

**Story:** #27. Branch `worktree-issue-27-operator-channel`. Consumer: #28
(`docs/game-dev/specs/2026-10-03-multica-integration.md`).

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:` (its spec line ranges) and `Review: task|final`
  under its heading.
- `Review: task` gets a per-task review on Opus (`model: "opus"`). It is for
  risky tasks: a new seam, cross-system work, data or schema, process or
  locking, or anything a live run depends on. A `Review: final` task folds
  into the final review.
- Minor findings are batched into the final fix wave. Every fix round goes
  to a fresh fixer, given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus. Then the
  gate (§ Final gate).

## Global Constraints

Copied verbatim from the spec (line numbers in parentheses). Every task's
requirements implicitly include this section.

**Milestone gate (spec 19-35):**

PROGRESS.md has no exit criterion for runner work; this feature's own, agreed
in brainstorm:

1. `sh tests/run_all.sh` is green. The existing overnight and lane suites keep
   every assertion unchanged; their shared setup exports
   `STUDIO_OVERNIGHT_HOLD_MINUTES=0` (a test override of `hold_minutes`), so
   they test today's behaviour, which `0` reproduces exactly. The requeue check
   and `studio-event` use only tools present under the suites' minimal `PATH`
   (`test_overnight_no_inhibitor`), or skip silently.
2. `sh tests/probes/hook_delivery_probe.sh` passes on the installed Claude Code.
3. One live manifest run in a throwaway Godot project with two independent
   stories, where one is made to stop after isolation: that story holds while
   the other lands; a `say` reaches the held story's next unit and appears as
   a committed `Directive` line in its feature ledger; `resume` carries it to
   its landing; `events.jsonl` records the whole sequence.

**Input and platform (spec 89-91):**

macOS and Linux, POSIX `sh`, as the runner today. No new dependencies.

**Feel targets (spec 93-99):**

- A message to a running unit lands within one main-session tool call; a
  message while the main session waits on a foreground subagent or a long gate
  lands when that call returns (Risks).
- `hold`, `resume`, `stop <story>` take effect within one poll
  (`STUDIO_OVERNIGHT_POLL_SECONDS`, default 5 s) once no unit is running.

**`overnight` config additions (spec 453-462):**

| key | default | range | meaning |
|---|---|---|---|
| `hold_minutes` | 480 | 0–1440 | how long a held story waits; 0 = today's behaviour |
| `directive_chars` | 4000 | 500–16000 | cap on a story's active + pending directive text |

Test-only: `STUDIO_OVERNIGHT_HOLD_MINUTES` overrides `hold_minutes` (the
existing suites set it to 0); `STUDIO_OVERNIGHT_HOLD_SECONDS` replaces
`hold_minutes × 60` when set, so hold deadlines run in seconds in the suites.

**Plan-wide code rules.** These come from the code and the trials, not from
the spec. Every task obeys them.

- **No bash-only syntax.** Under bash 3.2 as `sh`:
  - no `local`, no arrays, no `[[`;
  - never `VAR=v func` (the variable leaks past the call on bash 3.2; trial
    t2) — use a subshell with `export`;
  - a `case` pattern's `)` must never sit literally inside `$(...)`. Call a
    function from inside the `$(...)` instead.
- **Function locals.** Each new function's locals carry a short prefix
  (`_hw_`, `_rq_` …), as the runner's do.
- **Executable bits.** Every new file under `studios/*/bin/` or
  `studios/*/hooks/` is `chmod 755` and passes `sh -n`. `test_bin_syntax`
  (`tests/studio_test.sh:108-117`) enforces both.
- **Event log tools.** `studio-event` and `requeue_check` use only tools
  from the minimal `PATH` (`tests/overnight_test.sh:522-523`). That `PATH`
  has no `stat`, `ls` or `cut`.
- **One-line asserts.** An `assert_contains` pattern is a BRE matched one
  line at a time. A literal is asserted only on one line, and `[`, `.`, `*`
  and `$` are escaped.

## Decisions

These rule on the spec's open points and on the plan's own design choices.
They bind the implementers. Each one names the spec text it makes precise.

- **R1. Where the channel code lives.** The verbs and the inbox helpers go
  in a new sourced file, `studios/game-dev/bin/overnight-channel.sh`.
  - `studio-overnight` sources it unconditionally, just before its dispatch
    `case` (after `cmd_watch`). It guards itself like `overnight-lanes.sh:12`.
  - Its entry point is `chan_main VERB ARGS…`.
  - The runner uses its shared helpers too: `msg_get`, `msg_body`,
    `inbox_lock`, `inbox_unlock`.
  - `say()` stays the runner's stderr logger. The verb's functions are named
    `chan_say` and so on.
  - Why: `studio-overnight` is already 1121 lines, and the precedent for a
    sourced sibling is `overnight-lanes.sh`. The spec's Files table (330)
    names `studio-overnight` for the verbs. A sourced file is part of it, so
    this is a layout ruling, not a scope change.
- **R2. How a verb finds its run (AC4, AC4a).**
  - Inside a project (`STATE_ROOT/.studio` exists), the run is the lock's:
    `lock_live`, then `run=` from the lock.
    - The run's start checkout is `start=` from the live registry entry
      whose `run=` matches, falling back to `START_DIR`.
    - With `--run N`, the lock's run dir basename must equal `N` exactly.
      Otherwise the verb exits 1 with `run N is not live`, even when `N` is
      live in another project.
  - Outside a project, the run is found among the live registry entries
    (`reg_live`), filtered by `--run` when it is given:
    - none: exit 1;
    - one: use it;
    - two or more without `--run`: exit 1, naming each basename.
  - An ended run (`REGISTRY/last`) is never live, so `--run` naming it exits
    1. There is never a fallback.
  - `STATE_ROOT` resolves to the main worktree from any linked worktree
    (`studio-state:38-45`). So a verb run inside a story's feature worktree
    finds the run.
- **R3. The run's channel file.**
  - `run_setup` writes `RUN_DIR/channel` in both modes, with two lines:
    `hold_minutes=<N>` (the effective value, after the override) and
    `directive_chars=<N>`.
  - The verbs read it. A run dir without it is a run started before this
    story: every new verb exits 1 with
    `run <name> predates the operator channel (restart it to use <verb>)`.
- **R4. The held record (AC19).**
  - The record is `held <ENDING> until <ISO-8601 UTC>`, and `<why>` is the
    ENDING word for word. Examples: `held stop: need art until …`,
    `held no progress on T2 until …`, `held held by operator until …`.
  - A reader takes `why` as the text between `held ` and the **last**
    ` until ` (`${r% until *}`; trial t1 #4). The ISO is `${r##* until }`.
  - Lanes keep it in `stories/<id>`. Single-plan keeps it in
    `control/-.held`.
- **R5. An operator stop (AC7, AC23).**
  - The ending, and the lane record, are exactly `stopped by operator` (the
    record is not `stopped stopped by operator`).
  - In lanes, a `.stop` present when a story's loop ends `done` also stops
    it before landing, with `stopped by operator`. `stop <story>` on a
    `running` story means "after the running unit".
  - In single-plan mode a `done` unit stays `done`: there is no landing to
    hold back.
- **R6. "After isolation" (AC17), and a gap.**
  - Isolation means `FEATURE_DIR` (set by the last `snapshot`) ≠
    `START_DIR`.
  - A `stop:` ending holds only when two things are both true:
    - it equals the `STOP_ENDING` that `take_new_stop` derived;
    - that unit's new Stop line came only from the feature ledger
      (`STOP_SRC=feature`).

    When any new Stop line is also in the start checkout's ledger, the
    ending ends at once (AC18's tie rule).
  - `held by operator` holds without isolation: the operator asked.
  - **Gap ruling.** The spec lists `directive <id> not recorded` as
    holdable after isolation, but it says nothing about a requeue limit
    reached before isolation. A §0 unit that dies before its feature
    checkout exists cannot have recorded anything. So `requeue_check` raises
    the limit (`REQ_LIMIT`) only when `HOLD_ON=1` and the feature dir ≠
    `START_DIR`. Before isolation the message stays pending and the story
    goes on.
- **R7. Queued and waiting stories (AC7).**
  - `run_chain` checks `.stop` before `run_story`, for every story it
    reaches. A `.stop` there gives the record `stopped by operator`, and
    the rest of the chain is `skipped <id>`.
  - `wait_deps` checks `.stop` on each poll and returns 3. `run_chain` then
    acts as above.
  - `.hold` takes effect when the story would start: the first boundary
    check of `story_units` (R8) turns it into `held by operator` before any
    unit. A queued story that is already shipped (stage idle) only lands
    (AC7's "a story that finishes `done` lands").
- **R8. Boundary order (AC7, AC22).**
  - `op_boundary ID` checks, in order:
    1. the halt (`stop_requested`) → `stopped by user`;
    2. `.stop` → `stopped by operator`;
    3. `.hold` → `held by operator`.
  - It removes the control file it acts on.
  - It runs at the top of every `story_units` pass. It also runs before
    every gate-repair unit, both in `story_gate_loop` and in the resume
    path.
- **R9. The requeue limit (AC13, AC14).**
  - `REQ_LIMIT` is the first id whose `requeues:` reaches `RETRIES + 1`.
  - In `story_units` a new Stop line wins, then `done`, then `REQ_LIMIT`
    (ending `directive <id> not recorded`).
  - `gate_repair` and `land_repair` units requeue too (`requeue_check` runs
    in `run_unit`), but they never end on the limit. The next
    `story_units` unit gets the message, and its own check applies the
    limit. The landing phase never ends on it (AC14).
- **R10. Locks (spec 370-378).**
  - `inbox_lock DIR WAIT [break]` uses `mkdir DIR/.lock` plus an owner
    token (`$$ <epoch>`).
  - The verbs call it with `WAIT=${STUDIO_OVERNIGHT_INBOX_WAIT:-15}` (a test
    hook) and `break`. The lock is stale when its dir mtime is more than 10
    s old: `stat -c %Y`, else `stat -f %m` (trial t1 #1).
  - A stale lock is renamed to a unique `.lock.stale.$$.<epoch>`. When the
    renamed dir's mtime is fresh, it was another waiter's new lock: it is
    put back (`[ -e .lock ] ||` guards the nesting `mv`; trial t1 #8).
    Otherwise it is removed.
  - Accepted residue: losing two races at once while a stale lock exists
    can leave two holders. That needs three concurrent verbs.
  - The runner's `requeue_check` calls `inbox_lock DIR 5`, without `break`
    and without `stat`. On a timeout it skips the check with a stderr note.
  - The verbs list pending files first, then `delivered/`. A hook claim
    moving between the two is then seen at least once, so ids stay unique.
- **R11. Ids, and a gap (spec 370-373).**
  - The next id is one more than the largest number among:
    - the feature ledger's `Directive <n>:` and `Directive <n> retired`
      lines;
    - every `<n>.msg` under `inbox/<story>/` and `delivered/*/`.
  - **Gap ruling.** `unsay` of the newest pending message deletes it, and
    the next `say` reuses its id. This is accepted: the deleted message was
    never delivered, so nothing outside the inbox ever saw that id.
- **R12. What `unsay` accepts (AC2).**
  - A pending `story` or `unit` message is removed.
  - An `active` or `delivered` story directive gets a queued `retire`.
  - Each of these exits 1:
    - a directive already `retiring`;
    - a `retire` message itself;
    - a delivered `unit` message (it is spent);
    - a retired id;
    - an unknown id.
  - An id with a leading zero, or not all digits, is bad usage: exit 2.
- **R13. The cap (AC5).** The count is in **characters**: UTF-8 lead bytes,
  `LC_ALL=C tr -d '\200-\277' | wc -c` (trial t6). macOS awk `length` counts
  bytes in every locale (trial t1 #3). The count covers the story-scope
  text of four kinds of directive:
  - active (retiring included);
  - pending;
  - delivered-not-recorded;
  - the new text.

  A `--unit` message is not capped.
- **R14. Text (AC1).**
  - Arguments after `--` are joined with single spaces.
  - Text with no non-space character exits 2 (`say: empty text`).
  - A newline inside a quoted text is kept in the message body. The
    delivery block and `said` fold it to a space.
- **R15. `said` output (AC3).**
  - One line per directive: `<id>  <state>  <text>`, two spaces between
    columns.
  - The state is `active`, `pending`, `pending (unit)`, `delivered` or
    `retiring`.
  - Retire messages are not listed. Their target shows as `retiring`.
  - With none: `(no directives)`.
- **R16. `studio-event`'s interface (AC28).**
  - `studio-event RUN_DIR EVENT [key=text | key:=number | key[]=a,b]…`.
  - The event and the keys match `[a-z_]+`; anything else is exit 2.
  - Values:
    - a text value is escaped and cut to 500 **characters** at a UTF-8 lead
      byte, so no character is split;
    - `:=` takes a JSON number, and anything else (`unknown`, empty) is
      `null`;
    - `[]=` is a string array, and empty gives `[]`.
  - The line cap is 4096 bytes. Past it, fields are dropped from the end and
    `"cut":true` is added.
  - Exit codes: 0 written · 1 no run dir or not writable · 2 usage.
  - The `unit` field is the unit tag. `usd` is the unit's cost, or `null`.
    A final-step unit's story is `-`.
  - The code is verified as written in this plan (trials t4, t5).
- **R17. `story_state` events.**
  - `story_write` emits one after its `mv`, but only once `EV_ON=1`.
    `lanes_run` sets `EV_ON=1` right after it writes `run_started` and every
    `story_listed`. It then emits each story's current record (`queued`, or
    `landed` after `lanes_resume`). This keeps `run_started` first (spec
    427), although the `queued` records are written before `run_setup`
    (`overnight-lanes.sh:1520`).
  - `lanes_reap` sets `EV_ON=1` before its sweep.
  - Single-plan writes `running` at the start and on each resume, `held`,
    and `stopped <ending>` in `write_report` when the ending is not `done`.
- **R18. Fields of `run_started` and `story_listed`.**
  - `run_started`:
    - `mode` is `single` or the manifest's mode;
    - `max_lanes` is the number of lanes started (`_L`; single-plan 1);
    - `hold_minutes` is the effective value.
  - `story_listed`:
    - `chain` is the chain number (`chain_of`);
    - `depends[]` is `row_field <id> deps`.
  - Single-plan writes one `story_listed` with `story=-`, `chain:=1` and
    `depends[]=`.
- **R19. How the hook reads its input (AC9-11).**
  - It parses the hook input with `tr -d '\n' | sed` (no `jq`; no new
    dependencies), and tests `agent_id` with `grep`.
  - It claims the lowest id first (a glob, then `sort -n`), and prints only
    when it has something to deliver.
  - All its stderr goes to `hook.log` (`exec 2>>`), and it exits 0 on every
    path (`trap 'exit 0' EXIT`).
  - Cost, measured in T1: 6.41 ms per call for the early-exit path (5.22 ms
    net of loop overhead, 200 runs; trial t2). That is under the spec's 20
    ms.
- **R20. The held status line (AC27).**
  - The text is `held — <why> — until <HH:MM> — say / resume / stop <id>`.
  - Single-plan prints it in place of the `now:` line.
  - Lanes print it, indented four spaces, in place of the indented running
    unit line.
  - `HH:MM` is local time. The ISO becomes an epoch through the awk
    days-from-civil formula, then `date -r E` (BSD) or `date -d @E` (GNU).
    When neither works, the ISO itself is shown (trial t6).
- **R21. Messages left at a story's end (AC14).**
  - The report lists each story's pending messages:
    - single-plan: `## Operator messages left`;
    - lanes: `Operator messages left:` inside the story's section.
  - The format is `- <id> (<scope>, requeues <n>): <text>`.
  - The pending list is the whole set. `requeue_check` runs after every
    unit, so any delivered message that was not recorded is pending again
    by the time a story ends.
- **R22. Idempotence and the dirty check.**
  - `hold` and `stop <story>` on a story that already has that control file
    succeed again and print the same line.
  - `resume`'s dirty check runs `git -C <registry start=> status
    --porcelain` on `.studio/ledger/<id>.md` (lanes) or `.studio/ledger`
    (single-plan). It never uses the verb's own cwd.
- **R23. The probe (AC31).**
  - `tests/probes/hook_delivery_probe.sh [LAUNCHER]` uses launcher default
    `claude`. It runs `-p --settings <file>` with throwaway hooks in
    `PROBE_DIR`, three checks, and `--max-budget-usd 1` per session.
  - On a pass it writes two lines to
    `~/.claude-gamedev/probes/hook_delivery`: `<claude --version output>`,
    then `<UTC date>`.
  - `doctor.sh` prints `hook probe:   <line 1> — passed <line 2>`, or
    `hook probe:   hook delivery probe not run`.
- **R24. The execute skill (AC12).** One `### Operator messages (overnight
  units)` block goes under §8. §0 (c), the lane docs-sync step, §7, §9 and
  §11 each get a one-line pointer to it at their recording point.
- **R25. Control files.**
  - `hold_wait` removes a stale `.hold` and `.resume` when it starts.
  - `ctl_clear ID` removes `.hold .resume .stop .held` when a story ends:
    in `run_story`, in `run_chain`'s operator-stop and skip paths, and
    before `finish_run` in single-plan.
- **R26. The test overrides.**
  - `STUDIO_OVERNIGHT_HOLD_MINUTES` must be a whole number from 0 to 1440.
  - `STUDIO_OVERNIGHT_HOLD_SECONDS` must be a whole number.
  - Anything else is a start refusal: exit 2, one line.
  - Holds are on (`HOLD_ON=1`) only when the effective `hold_minutes > 0`.
    `HOLD_SECONDS` sets only the deadline's length (`HOLD_SECS`).
  - Arithmetic on them goes through awk, so `010` is ten, not octal.
- **R27. Where verb output goes.**
  - A success prints on stdout.
  - A refusal prints its reason on stderr and exits 1 (or 2 for usage).
    It is one line, except for AC5's directive list.
  - #28 relays stdout on exit 0 and stderr otherwise.
  - Bare `stop` without `--run` is byte-for-byte today's: stdout, exit 0 or
    1.
- **R28. The halt reason while held (AC25).** `hold_wait` ends a halted
  hold with `$(halt_reason) (was held: <why>)`.
  - `halt_reason` is `stopped by user` in `studio-overnight`.
  - `overnight-lanes.sh` redefines it as `lane_halt_reason`.
- **R29. Which resume gets a gate-repair unit (AC20), and a wording gap.**
  - The test is mechanical: `last_stop_gate_red` holds when the feature
    ledger's latest `Stop:` line is `Stop: gate red — …`. That is §11's own
    precondition (SKILL.md:729-731).
  - **Gap ruling.** AC20's example list ("e.g. `Stop: gate repair red`, no
    progress, timed out") names `gate repair made no progress` and `gate
    repair timed out` as holds whose latest Stop is not `gate red`. But such
    a unit writes no Stop line, so the latest Stop is still the finish's
    `gate red — …`. The operative rule (the latest Stop) wins: that resume
    gets one more gate-repair unit. Pinned by T7
    `test_lanes_gate_repair_noprog_holds`.
- **R30. Detached runs.** `detach_start` strips every `STUDIO_*` variable,
  `STUDIO_OVERNIGHT_HOLD_MINUTES` included. A detached run therefore uses
  the configured `hold_minutes`, which is what a real run wants. The detach
  tests end their run with a whole-run `stop`, which ends any hold at once
  (AC25), so they are unaffected.

## AC coverage

| AC | Tasks | AC | Tasks |
|----|-------|----|-------|
| 1 | T3 | 17 | T6 (single), T7 (lanes) |
| 2 | T3 | 18 | T6, T7 |
| 3 | T3 | 19 | T6, T7 |
| 4, 4a | T3 (find, refusals), T4 (control verbs) | 20 | T6, T7 (gate-red resume) |
| 5 | T3 | 21 | T4 |
| 6 | T3, T4 | 22 | T6 |
| 7 | T4 (verbs), T6 (single boundary), T7 (`run_chain`, `wait_deps`) | 23 | T6, T7 |
| 8 | T4 | 24 | T6, T7 |
| 9 | T1 (gate, registration), T5 | 25 | T6, T7 |
| 10 | T5 | 26 | T2 (exports), T6 |
| 11 | T5 | 27 | T6, T7 |
| 12 | T5 (block), T9 (skill) | 28 | T1, T2 |
| 13 | T6 | 29 | T1, T2, T5 |
| 14 | T6, T7 (report) | 30 | T11 |
| 15 | T8 | 31 | T10 |
| 16 | T1, T5 | | |

Milestone gate: criterion 1 → every task, plus T2 (the exports) and T6
(`test_overnight_requeue_minimal_path`); criterion 2 → T10 and the Final
gate; criterion 3 → the Final gate's manual check. Feel targets:
- "within one tool call" → T5 (`PostToolUse` claims) and the live run;
- "within one poll" → T6 and T7 (tests at `STUDIO_OVERNIGHT_POLL_SECONDS=1`).

## Review Focus

These are the input classes most likely to bite, most likely first. Each is
pinned by a test in the task that owns the code.

1. **Empty or whitespace-only `say` text**, including `say - --` with
   nothing after it and `say - -- '' ' '`. Each must exit 2 and write
   nothing. Test: T3 `test_say_empty_text_exit_2`.
2. **A verb run from inside the story's feature worktree.** The run must be
   found, and `resume`'s dirty check must read the run's start checkout,
   not the cwd. Test: T4 `test_resume_from_feature_worktree`.
3. **Id 1 versus id 10.** `unsay 1` must touch only `1.msg`, `said` must
   still list 10, and a ledger holding only `Directive 10:` must not count
   as recording message 1. Tests: T3 `test_unsay_id_prefix`, T6
   `test_overnight_requeue_id_prefix`.
4. **Multibyte text.** An event field must be cut by characters without
   splitting one, in a UTF-8 locale too. The cap must count characters,
   not bytes. Tests: T1 `test_event_utf8_cut`, T3
   `test_say_cap_counts_characters`.
5. **A `resume` waiting at a poll where the deadline has passed.** Resume
   must win (AC22: both control files beat the deadline). Test: T6
   `test_overnight_resume_wins_at_deadline`.

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `studios/game-dev/bin/studio-event` (new) | 1 | Validate arguments, build one escaped JSON line, append it |
| `studios/game-dev/hooks/operator-inbox.sh` (new) | 1 (gate), 5 | The unit gate; claim, deliver, re-show on compact |
| `studios/game-dev/hooks/hooks.json` | 1 | Register the hook: `SessionStart` `startup\|compact`, `PostToolUse` `*` |
| `studios/game-dev/bin/studio-overnight` | 2, 3, 6, 11 | Config, the channel file, events, `STUDIO_RUN_DIR`; sourcing the channel; the dispatch; single-plan holds and requeue; status; help |
| `studios/game-dev/bin/overnight-channel.sh` (new) | 3, 4 | The verbs, `--run`, run discovery, the inbox lock, ids, the cap, the controls |
| `studios/game-dev/bin/overnight-lanes.sh` | 2, 7 | Lane events; the story hold loop, the resume gate repair, control checks, the held status line, the report |
| `studios/game-dev/bin/studio-brief` | 8 | The directives part; the anchored `Ruling` match |
| `studios/game-dev/skills/execute/SKILL.md` | 9 | Operator messages: scopes, recording points, commits |
| `tests/probes/hook_delivery_probe.sh` (new) | 10 | Live check of the three spike facts; records the version |
| `doctor.sh` | 10 | The `hook probe:` line |
| `docs/game-dev/overnight-events.md` (new) | 11 | The contract #28 builds on (AC30) |
| `README.md` | 11 | "Overnight runs": talking to a live run |
| `tests/studio_event_test.sh` (new) | 1 | `studio-event` |
| `tests/hook_test.sh` | 1, 5, 10 | Hook registration, the gate, delivery; probe usage |
| `tests/overnight_test.sh` | 2, 3, 4, 6, 11 | Exports; verbs on a fake run; single-plan holds; help; contract doc |
| `tests/overnight_lanes_test.sh` | 2, 7 | Exports; lane events and holds |
| `tests/studio_brief_test.sh` | 8 | Directives in `task` and `final` |
| `tests/studio_test.sh` | 9 | `test_execute_operator_messages` |
| `tests/install_test.sh` | 10 | `test_doctor_hook_probe_line` |

Order: T1 → T2 → … → T11 (see Falsify → Task-order falsification).

---
### Task 1: `studio-event`, and the operator-inbox hook's gate

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L24-29, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L171-176, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L228-229, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L288-296, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L422-437, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L541-543
Review: task

**Risk:** this task creates the event schema's only writer (data and schema)
and a hook that runs on every tool call of every `claude-gd` session. The
spec's Risks section puts the hook's cost measurement here.

**Files:**
- Create: `studios/game-dev/bin/studio-event` (mode 755)
- Create: `studios/game-dev/hooks/operator-inbox.sh` (mode 755). This task
  writes only the gate; T5 adds delivery.
- Modify: `studios/game-dev/hooks/hooks.json`, adding two entries.
- Create: `tests/studio_event_test.sh`
- Modify: `tests/hook_test.sh`:
  - `INBOX=` beside `HOOK=` (L7);
  - two new tests;
  - the `run_tests` list (L372-381).

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `studio-event RUN_DIR EVENT [key=text|key:=number|key[]=a,b]…` (R16).
    It appends to `RUN_DIR/events.jsonl` and exits 0, 1 or 2.
  - `hooks/operator-inbox.sh`: exit 0 on every path. With
    `STUDIO_UNIT_TAG` or `STUDIO_RUN_DIR` unset or empty, it exits before
    reading stdin.

- [ ] **Step 1: Write the failing tests**

`tests/studio_event_test.sh` (new):

```sh
#!/bin/sh
# studio-event: one versioned, escaped JSON line per call (spec AC28-29, R16).
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
EV="$REPO_ROOT/studios/game-dev/bin/studio-event"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
R="$TMP/overnight-demo-20261003-210400"
fresh() { rm -rf "$R"; mkdir -p "$R"; }
# field_len KEY — the character count of the last line's string field KEY
# (the field holds no escaped quote).
field_len() {
  tail -n 1 "$R/events.jsonl" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" \
    | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '
}
# utf8_locale — an installed UTF-8 locale name, empty when none.
utf8_locale() { locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1; }

test_event_line_shape() {
  fresh
  assert_status 0 "a line is written" -- sh "$EV" "$R" run_started mode=single max_lanes:=1 hold_minutes:=0
  assert_contains "$R/events.jsonl" '^{"v":1,"ts":"[0-9-]*T[0-9:]*Z","run":"overnight-demo-20261003-210400","event":"run_started","mode":"single","max_lanes":1,"hold_minutes":0}$' "v, ts, run, event, then the fields in order"
  sh "$EV" "$R/" story_listed story=- chain:=1 'depends[]='
  assert_eq 2 "$(wc -l < "$R/events.jsonl" | tr -d ' ')" "a second call appends (a trailing / on RUN_DIR is fine)"
  assert_contains "$R/events.jsonl" '"event":"story_listed","story":"-","chain":1,"depends":\[\]}$' "an empty array is []"
}
test_event_escaping() {
  fresh
  nl='
'
  sh "$EV" "$R" story_state story=S1 state=held "why=a\"b\\c${nl}d	e$(printf '\001')f" until=2026-10-03T21:04:00Z
  assert_contains "$R/events.jsonl" '"why":"a\\"b\\\\c\\nd\\tef","until":"2026-10-03T21:04:00Z"}$' "quote, backslash, newline, tab escaped; \\001 dropped"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "a\"b\\c${nl}d	ef" "$(tail -n 1 "$R/events.jsonl" | jq -r .why)" "the line is valid JSON and round-trips"
  fi
}
test_event_cut_500() {
  fresh
  sh "$EV" "$R" story_state story=S1 state=stopped "why=$(printf '%600s' '' | tr ' ' b)"
  assert_eq 500 "$(field_len why)" "a string field is cut to 500 characters"
}
test_event_utf8_cut() {
  a499="$(printf '%499s' '' | tr ' ' a)"
  for loc in "" "$(utf8_locale)"; do
    fresh
    if [ -n "$loc" ]; then ( LC_ALL="$loc"; export LC_ALL; sh "$EV" "$R" story_state "why=${a499}—tail" )
    else sh "$EV" "$R" story_state "why=${a499}—tail"; fi
    assert_eq 1 "$(grep -cF "\"why\":\"${a499}—\"" "$R/events.jsonl")" "cut after the 500th character, the em dash whole (locale '${loc:-default}')"
  done
  fresh
  e300="$(printf '%300s' '' | sed 's/ /é/g')"
  sh "$EV" "$R" story_state "why=$e300"
  assert_eq 1 "$(grep -cF "\"why\":\"$e300\"" "$R/events.jsonl")" "300 two-byte characters are not cut"
}
test_event_line_cap_4k() {
  fresh
  big="$(printf '%450s' '' | tr ' ' c)"
  sh "$EV" "$R" story_state fa="$big" fb="$big" fc="$big" fd="$big" fe="$big" ff="$big" fg="$big" fh="$big" fi="$big" fj="$big"
  assert_eq 1 "$(awk 'length($0) <= 4096' "$R/events.jsonl" | wc -l | tr -d ' ')" "the line is at most 4096 bytes"
  assert_contains "$R/events.jsonl" ',"cut":true}$' "a capped line says cut"
  assert_contains "$R/events.jsonl" '"fa":"ccc' "the first fields are kept"
  assert_not_contains "$R/events.jsonl" '"fj":' "the last fields are dropped"
}
test_event_numbers_null_arrays() {
  fresh
  sh "$EV" "$R" unit_ended story=- usd:=1.25 n:=unknown e:= big:=1e3 neg:=-2 'depends[]=A,B'
  assert_contains "$R/events.jsonl" '"usd":1.25,"n":null,"e":null,"big":1e3,"neg":-2,"depends":\["A","B"\]}$' "numbers, null for a non-number, string arrays"
}
test_event_usage() {
  fresh
  assert_status 2 "no arguments" -- sh "$EV"
  assert_status 2 "no event" -- sh "$EV" "$R"
  assert_status 2 "an event outside [a-z_]" -- sh "$EV" "$R" Bad-Name
  assert_status 2 "a digit in the event" -- sh "$EV" "$R" run2
  assert_status 2 "a field with no key" -- sh "$EV" "$R" ok =x
  assert_status 2 "an upper-case key" -- sh "$EV" "$R" ok Key=x
  assert_status 2 "a field with no =" -- sh "$EV" "$R" ok noeq
  assert_missing "$R/events.jsonl" "bad usage writes nothing"
  assert_status 1 "a missing run dir" -- sh "$EV" "$R/nope" ok
  sh "$EV" "$R/nope" ok 2> "$TMP/ev.err"
  assert_contains "$TMP/ev.err" "^studio-event: no run dir " "a missing run dir is named on stderr"
  if [ "$(id -u)" != 0 ]; then
    chmod 555 "$R"
    assert_status 1 "an unwritable run dir" -- sh "$EV" "$R" ok
    chmod 755 "$R"
  fi
}
test_event_minimal_path() {
  fresh
  mkdir -p "$TMP/mini"
  for u in sh date awk; do ln -sf "$(command -v "$u")" "$TMP/mini/$u"; done
  assert_status 0 "only sh, date and awk on PATH" -- env PATH="$TMP/mini" sh "$EV" "$R" ok a=b
  assert_contains "$R/events.jsonl" '"event":"ok","a":"b"}$' "and the line is written"
}

run_tests test_event_line_shape test_event_escaping test_event_cut_500 test_event_utf8_cut \
  test_event_line_cap_4k test_event_numbers_null_arrays test_event_usage test_event_minimal_path
```

In `tests/hook_test.sh`, add `INBOX="$STUDIO_DIR/hooks/operator-inbox.sh"`
after L9. Add these tests:

```sh
test_inbox_hook_registered() {
  J="$STUDIO_DIR/hooks/hooks.json"
  assert_contains "$J" '"matcher": "startup|compact"' "a SessionStart entry for startup and compact"
  assert_contains "$J" '"PostToolUse"' "a PostToolUse entry"
  assert_contains "$J" '"matcher": "\*"' "PostToolUse matches every tool"
  assert_eq 2 "$(grep -c 'hooks/operator-inbox.sh' "$J")" "operator-inbox.sh is registered twice"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "startup|compact" "$(jq -r '.hooks.SessionStart[] | select(.hooks[0].command | test("operator-inbox")) | .matcher' "$J")" "SessionStart: startup|compact"
    assert_eq "*" "$(jq -r '.hooks.PostToolUse[] | select(.hooks[0].command | test("operator-inbox")) | .matcher' "$J")" "PostToolUse: *"
  fi
}
test_inbox_hook_silent_outside_units() {
  for e in none tag dir; do
    ( unset STUDIO_UNIT_TAG STUDIO_RUN_DIR
      case "$e" in tag) STUDIO_UNIT_TAG=t; export STUDIO_UNIT_TAG ;; dir) STUDIO_RUN_DIR="$TMP"; export STUDIO_RUN_DIR ;; esac
      printf '{"hook_event_name":"PostToolUse"}' | sh "$INBOX" ) > "$TMP/ib.out" 2>&1; st=$?
    assert_eq 0 "$st" "exit 0 without both variables ($e)"
    assert_eq "" "$(cat "$TMP/ib.out")" "prints nothing without both variables ($e)"
  done
  # Reads no stdin: a writer that holds the pipe open for 3 s must not delay it.
  rm -f "$TMP/ib.fifo"; mkfifo "$TMP/ib.fifo"
  ( exec 3> "$TMP/ib.fifo"; sleep 3 ) & _w=$!
  t0="$(date +%s)"
  ( unset STUDIO_UNIT_TAG STUDIO_RUN_DIR; sh "$INBOX" < "$TMP/ib.fifo" ) > "$TMP/ib.out" 2>&1
  t1="$(date +%s)"; wait "$_w" 2>/dev/null
  assert_eq 1 "$([ $((t1 - t0)) -le 1 ] && echo 1 || echo 0)" "exits without reading stdin"
}
```

Append both names to the `run_tests` list.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/studio_event_test.sh; sh tests/hook_test.sh`
Expected: FAIL. `studio_event_test.sh` fails every case (`sh: …/studio-event:
No such file`). `test_inbox_hook_registered` fails on the matcher lines,
and `test_inbox_hook_silent_outside_units` fails (`…/operator-inbox.sh: No
such file`). Every other hook test passes.

- [ ] **Step 3: Write `studio-event`**

The code below is verified as written (trials t4 and t5):
- escaping;
- the 500-character cut at a UTF-8 lead byte;
- the 4096-byte cap (3738 bytes, `"cut":true`, `fa`…`fh` kept);
- numbers, null and arrays;
- a minimal `PATH` of `sh date awk`.

```sh
#!/bin/sh
# studio-event — append one event line to an overnight run's events.jsonl
# (schema v1, docs/game-dev/overnight-events.md). The runner, the operator
# verbs and the operator-inbox hook write the log only through this.
#
#   studio-event RUN_DIR EVENT [FIELD…]
#     FIELD  key=text        a JSON string (escaped, cut to 500 characters)
#            key:=number     a JSON number; anything else ('unknown', '') is null
#            key[]=a,b,…     a JSON array of strings (empty: [])
#
# EVENT and every key match [a-z_]+. The line is {"v":1,"ts":"<UTC>",
# "run":"<basename RUN_DIR>","event":EVENT,…} and at most 4096 bytes: past
# that, fields are dropped from the end and "cut":true is added. Uses only
# sh, date and awk (the runner suites' minimal PATH).
# Exit: 0 written · 1 RUN_DIR missing or not writable (a line on stderr) ·
# 2 bad usage.
set -u
usage() { echo "usage: studio-event RUN_DIR EVENT [key=text|key:=number|key[]=a,b]…" >&2; exit 2; }
[ "$#" -ge 2 ] || usage
_d="${1%/}"; _e="$2"; shift 2
case "$_e" in ''|*[!a-z_]*) usage ;; esac
for _f in "$@"; do
  case "$_f" in
    [a-z]*=*) _k="${_f%%=*}"; _k="${_k%:}"; _k="${_k%\[\]}"
              case "$_k" in ''|*[!a-z_]*) usage ;; esac ;;
    *) usage ;;
  esac
done
[ -d "$_d" ] || { echo "studio-event: no run dir $_d" >&2; exit 1; }
_line="$(LC_ALL=C awk -v ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" -v run="${_d##*/}" -v ev="$_e" '
  function esc(s,   c) {
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); gsub(/\n/, "\\n", s); gsub(/\r/, "\\r", s)
    for (c = 1; c < 32; c++) if (c != 9 && c != 10 && c != 13) gsub(sprintf("%c", c), "", s)
    gsub(sprintf("%c", 127), "", s)
    return s
  }
  # cut(s, n) — the first n characters of UTF-8 s: a character starts at any
  # byte outside 0x80-0xBF, so the cut never splits one.
  function cut(s, n,   i, c, L, b) {
    L = length(s); if (L <= n) return s
    c = 0
    for (i = 1; i <= L; i++) {
      b = substr(s, i, 1)
      if (b < "\200" || b >= "\300") { c++; if (c > n) return substr(s, 1, i - 1) }
    }
    return s
  }
  function str(s) { return "\"" esc(cut(s, 500)) "\"" }
  function num(s) { return (s ~ /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) ? s : "null" }
  function arr(s,   n, a, i, o) {
    if (s == "") return "[]"
    n = split(s, a, ","); o = "["
    for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") str(a[i])
    return o "]"
  }
  BEGIN {
    head = "{\"v\":1,\"ts\":\"" ts "\",\"run\":" str(run) ",\"event\":\"" ev "\""
    nf = 0
    for (i = 1; i < ARGC; i++) {
      f = ARGV[i]; p = index(f, "="); k = substr(f, 1, p - 1); v = substr(f, p + 1)
      if (k ~ /:$/) { k = substr(k, 1, length(k) - 1); F[++nf] = "\"" k "\":" num(v) }
      else if (k ~ /\[\]$/) { k = substr(k, 1, length(k) - 2); F[++nf] = "\"" k "\":" arr(v) }
      else F[++nf] = "\"" k "\":" str(v)
    }
    cutflag = ""
    while (1) {
      o = head
      for (i = 1; i <= nf; i++) o = o "," F[i]
      o = o cutflag "}"
      if (length(o) <= 4096 || nf == 0) break
      nf--; cutflag = ",\"cut\":true"
    }
    print o
    exit
  }' "$@")" || { echo "studio-event: awk failed" >&2; exit 1; }
printf '%s\n' "$_line" >> "$_d/events.jsonl" 2>/dev/null \
  || { echo "studio-event: cannot write $_d/events.jsonl" >&2; exit 1; }
exit 0
```

`chmod 755 studios/game-dev/bin/studio-event`.

- [ ] **Step 4: Write the hook's gate and register it**

`studios/game-dev/hooks/operator-inbox.sh` (T5 replaces everything after the gate):

```sh
#!/bin/sh
# operator-inbox.sh — delivers a live overnight run's operator messages to a
# unit's main session (#27; spec AC9-12). Registered for SessionStart
# (startup|compact) and PostToolUse (*). Outside an overnight unit (no
# STUDIO_UNIT_TAG or no STUDIO_RUN_DIR) it exits at once, reading nothing:
# it runs on every tool call of every claude-gd session. Never fails a tool
# call: exit 0 on every path.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] || exit 0
cat > /dev/null
exit 0
```

`chmod 755`. In `hooks.json`, add a second `SessionStart` element (keep the
existing `startup|clear|compact` one; `test_hook_files` asserts it) and a
`PostToolUse` key:

```json
    "SessionStart": [
      { "matcher": "startup|clear|compact", "hooks": [ … unchanged … ] },
      {
        "matcher": "startup|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/operator-inbox.sh\""
          }
        ]
      }
    ],
    …
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/operator-inbox.sh\""
          }
        ]
      }
    ]
```

Write the matcher lines exactly as `"matcher": "startup|compact"` and
`"matcher": "*"`, one space after the colon, as the file's other entries
are.

- [ ] **Step 5: Measure the hook's cost (spec Risks: under 20 ms)**

Run it from a scratch file. Do not commit it.

```sh
unset STUDIO_UNIT_TAG STUDIO_RUN_DIR
H=studios/game-dev/hooks/operator-inbox.sh; N=200
t0=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
i=0; while [ $i -lt $N ]; do printf '{"hook_event_name":"PostToolUse"}' | sh "$H"; i=$((i + 1)); done
t1=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
awk -v a="$t0" -v b="$t1" -v n="$N" 'BEGIN { printf "%.2f ms per call\n", (b - a) * 1000 / n }'
```

Expected: under 20 ms. The planner's trial measured 6.41 ms. Put the
number in the hand-back. Over 20 ms is a finding for the reviewer, not
something to fix silently.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `sh tests/studio_event_test.sh && sh tests/hook_test.sh && sh tests/studio_test.sh`
Expected: every test PASSES. `test_bin_syntax` sees the two new
executables.

- [ ] **Step 7: Commit**

```bash
git add studios/game-dev/bin/studio-event studios/game-dev/hooks/operator-inbox.sh \
  studios/game-dev/hooks/hooks.json tests/studio_event_test.sh tests/hook_test.sh
git commit -m "feat(overnight): studio-event and the operator-inbox hook gate (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 2: Runner config, the channel file, `STUDIO_RUN_DIR`, and the run's events

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L24-29, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L288-296, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L330-331, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L422-437, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L453-462
Review: task

**Risk:** this is a data and schema change to two live code paths, and the
suites' exports land here. Without `HOLD_MINUTES=0`, T6's holds would wait
eight hours in every existing test that writes a feature `Stop:`.

**Files:**
- Modify `studios/game-dev/bin/studio-overnight`:
  - the `cfg` helpers (L42-61): add `hold_overrides` after `cfg`;
  - `preflight` (L336-337): config and overrides;
  - after `spent()` (L415): `run_event`, `state_event`, `iso_utc`;
  - `start_session` (L603-604): `STUDIO_RUN_DIR`;
  - `run_unit` (L620): `unit_started`;
  - `row` (L663-667): `unit_ended`;
  - `write_report` (L697-698): `story_state stopped`, `run_ended`;
  - `run_setup` (L930): the channel file;
  - `cmd_start` (L889-891): the opening events.
- Modify `studios/game-dev/bin/overnight-lanes.sh`:
  - `story_write` (L252-256);
  - `lanes_run` (L1537-1538);
  - `lanes_report`, at its end (L1052);
  - `lanes_reap` (L1112).
- Modify `tests/overnight_test.sh`:
  - after L74, the export;
  - the stub, after L33, writing `$CALLS/$n.chan`;
  - new tests;
  - two assertions appended to `test_overnight_no_inhibitor` (L529-530).
- Modify `tests/overnight_lanes_test.sh`: after L398, the export; new tests.

**Interfaces:**
- Consumes: T1's `studio-event`.
- Produces, in `studio-overnight`:
  - Variables:
    - `HOLD_MINUTES` (a normalized integer, after the override);
    - `DIRECTIVE_CHARS`;
    - `HOLD_ON` (`1` iff `HOLD_MINUTES > 0`);
    - `HOLD_SECS` (the deadline's length);
    - `EV_ON` (unset or `0` until the opening events are written, then
      `1`).
  - `run_event EVENT FIELD…`: `studio-event "$RUN_DIR" …`. A failure is one
    stderr line (`say`), never fatal.
  - `state_event ID RECORD`: a `story_state` event from a record line (R17).
    It is a no-op unless `EV_ON=1`.
  - `iso_utc EPOCH`: prints `YYYY-MM-DDTHH:MM:SSZ`.
  - `RUN_DIR/channel` (R3), and `STUDIO_RUN_DIR` in every unit's
    environment, not in `LAUNCH_ENV`.
  - Events:
    - `run_started`, `story_listed`, and `story_state` from both modes;
    - `unit_started` from `run_unit`;
    - `unit_ended` from `row`;
    - `run_ended` from `write_report` and `lanes_report`.

- [ ] **Step 1: Write the failing tests**

Add both exports first. In `tests/overnight_test.sh`, after L74:

```sh
# The suites test today's endings: hold_minutes 0 (spec milestone gate 1).
STUDIO_OVERNIGHT_HOLD_MINUTES=0; export STUDIO_OVERNIGHT_HOLD_MINUTES
```

The same lines go in `tests/overnight_lanes_test.sh` after L398. In the
single-plan stub, after `pwd -P > "$CALLS/$n.pwd"`, add:

```sh
printf '%s %s\n' "${STUDIO_UNIT_TAG:-unset}" "${STUDIO_RUN_DIR:-unset}" > "$CALLS/$n.chan"
```

New tests in `tests/overnight_test.sh`:

```sh
test_overnight_hold_config_refused() {
  fixture hcf '{"overnight": {"hold_minutes": 1441}}'; refuse_case "hold_minutes 1441" "hold_minutes"
  fixture hcf '{"overnight": {"directive_chars": 499}}'; refuse_case "directive_chars 499" "directive_chars"
  for bad in abc 1441 -1 1.5; do
    fixture hcf; STUDIO_OVERNIGHT_HOLD_MINUTES="$bad"
    refuse_case "STUDIO_OVERNIGHT_HOLD_MINUTES=$bad" "STUDIO_OVERNIGHT_HOLD_MINUTES"
  done
  STUDIO_OVERNIGHT_HOLD_MINUTES=0
  fixture hcf; STUDIO_OVERNIGHT_HOLD_SECONDS=1.5; export STUDIO_OVERNIGHT_HOLD_SECONDS
  refuse_case "STUDIO_OVERNIGHT_HOLD_SECONDS=1.5" "STUDIO_OVERNIGHT_HOLD_SECONDS"
  unset STUDIO_OVERNIGHT_HOLD_SECONDS
}
test_overnight_channel_file() {
  fixture chf; done_scenario; run_start
  assert_eq "hold_minutes=0|directive_chars=4000" "$(tr '\n' '|' < "$(last_run_dir)/channel" | sed 's/|$//')" "channel: the effective hold_minutes and the default cap"
  fixture chf2 '{"overnight": {"directive_chars": 800, "hold_minutes": 30}}'; done_scenario; run_start
  assert_contains "$(last_run_dir)/channel" "^directive_chars=800$" "the configured cap"
  assert_contains "$(last_run_dir)/channel" "^hold_minutes=0$" "the test override wins over config"
}
test_overnight_unit_env() {
  fixture uenv; done_scenario; run_start
  _r="$(last_run_dir)"
  assert_eq "$(basename "$_r")-0-1-T1 $_r" "$(cat "$CALLS/1.chan")" "a unit gets STUDIO_UNIT_TAG and STUDIO_RUN_DIR"
  fixture uenv2; run_start --dry-run
  assert_not_contains "$RS_OUT" "STUDIO_RUN_DIR" "the dry-run launch line is unchanged"
}
test_overnight_events_two_units() {
  fixture ev2
  scenario "stage execute; task 1/1; ledger T1 complete; cost 2" \
           "ledger final review done; ledger shipped https://github.com/o/r/pull/9; stage idle; task -; cost 1"
  run_start
  E="$(last_run_dir)/events.jsonl"; B="$(basename "$(last_run_dir)")"
  assert_eq "run_started story_listed story_state unit_started unit_ended unit_started unit_ended run_ended" \
    "$(sed -n 's/.*"event":"\([a-z_]*\)".*/\1/p' "$E" | tr '\n' ' ' | sed 's/ $//')" "the events, in order"
  assert_eq 8 "$(grep -c "^{\"v\":1,\"ts\":\"[0-9-]*T[0-9:]*Z\",\"run\":\"$B\",\"event\":" "$E")" "every line: v, ts, run"
  assert_contains "$E" '"event":"run_started","mode":"single","max_lanes":1,"hold_minutes":0}$' "run_started"
  assert_contains "$E" '"event":"story_listed","story":"-","chain":1,"depends":\[\]}$' "one story_listed: -"
  assert_contains "$E" '"event":"story_state","story":"-","state":"running"}$' "running"
  assert_contains "$E" "\"event\":\"unit_started\",\"story\":\"-\",\"unit\":\"$B-0-1-T1\",\"label\":\"T1\",\"model\":\"sonnet\"}\$" "unit_started"
  assert_contains "$E" "\"event\":\"unit_ended\",\"story\":\"-\",\"unit\":\"$B-0-1-T1\",\"label\":\"T1\",\"outcome\":\"progress\",\"usd\":2}\$" "unit_ended: progress, usd"
  assert_contains "$E" '"label":"final-review","outcome":"done","usd":1}$' "the second unit ends done"
  assert_contains "$E" "\"event\":\"run_ended\",\"ending\":\"done\",\"report\":\"$(last_run_dir)/report.md\"}\$" "run_ended names the report"
}
```

Append to `test_overnight_no_inhibitor`, after its last assertion:

```sh
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"run_ended","ending":"done"' "studio-event runs under the minimal PATH"
  assert_not_contains "$TMP/rs.err" "events.jsonl" "no event write failed"
```

New tests in `tests/overnight_lanes_test.sh`:

```sh
test_lanes_story_listed_events() {
  lanes_fixture evl integration A:- B:A C:-
  run_lanes start "$MFP"
  E="$(last_lanes_dir)/events.jsonl"
  assert_eq run_started "$(sed -n '1s/.*"event":"\([a-z_]*\)".*/\1/p' "$E")" "run_started is the first line"
  assert_contains "$E" '"event":"run_started","mode":"integration","max_lanes":2,"hold_minutes":0}$' "mode, lanes started, hold_minutes"
  assert_eq "story_listed story_listed story_listed" "$(sed -n '2,4s/.*"event":"\([a-z_]*\)".*/\1/p' "$E" | tr '\n' ' ' | sed 's/ $//')" "every story_listed right after run_started"
  assert_contains "$E" '"story":"A","chain":1,"depends":\[\]}$' "A: chain 1, no dependencies"
  assert_contains "$E" '"story":"B","chain":1,"depends":\["A"\]}$' "B: in A's chain, depends on A"
  assert_contains "$E" '"story":"C","chain":2,"depends":\[\]}$' "C: chain 2"
  for id in A B C; do
    assert_contains "$E" "\"event\":\"story_state\",\"story\":\"$id\",\"state\":\"landed\"}\$" "$id landed"
  done
  assert_eq run_ended "$(sed -n '$s/.*"event":"\([a-z_]*\)".*/\1/p' "$E")" "run_ended is the last line"
}
test_lanes_unit_env_run_dir() {
  lanes_fixture uenvl integration A:-
  run_lanes start "$MFP"
  assert_contains "$CALLS/1.fullenv" "^STUDIO_RUN_DIR=$(last_lanes_dir)$" "a lane unit gets STUDIO_RUN_DIR"
}
```

Add every new name to its suite's `run_tests` list. In
`overnight_lanes_test.sh`, insert them before `test_lanes_no_orphans`,
which stays last.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_test.sh; sh tests/overnight_lanes_test.sh`
Expected: FAIL in the new tests only:
- no `channel` file;
- `1.chan` reads `<tag> unset`;
- no `events.jsonl`;
- the config refusals pass through (exit 0).

Every existing test stays green: with the export in place, nothing reads it
yet.

- [ ] **Step 3: Implement in `studio-overnight`**

After `cfg()` (L61):

```sh
# hold_overrides — R26: STUDIO_OVERNIGHT_HOLD_MINUTES (0-1440) replaces
# hold_minutes; STUDIO_OVERNIGHT_HOLD_SECONDS (whole seconds) replaces only
# the deadline's length. Sets HOLD_MINUTES (normalized: awk reads 010 as 10),
# HOLD_ON (1 iff HOLD_MINUTES > 0) and HOLD_SECS. A bad value is a refusal.
hold_overrides() {
  _ho_m="${STUDIO_OVERNIGHT_HOLD_MINUTES:-}"
  if [ -n "$_ho_m" ]; then
    case "$_ho_m" in
      *[!0-9]*) refuse "STUDIO_OVERNIGHT_HOLD_MINUTES must be a whole number from 0 to 1440, got $_ho_m" ;;
      *) if awk -v v="$_ho_m" 'BEGIN { exit !(v <= 1440) }'; then HOLD_MINUTES="$_ho_m"
         else refuse "STUDIO_OVERNIGHT_HOLD_MINUTES must be a whole number from 0 to 1440, got $_ho_m"; fi ;;
    esac
  fi
  case "${STUDIO_OVERNIGHT_HOLD_SECONDS:-}" in
    *[!0-9]*) refuse "STUDIO_OVERNIGHT_HOLD_SECONDS must be a whole number of seconds, got $STUDIO_OVERNIGHT_HOLD_SECONDS" ;;
  esac
  HOLD_MINUTES="$(awk -v v="${HOLD_MINUTES:-0}" 'BEGIN { print v + 0 }')"
  HOLD_ON=0; [ "$HOLD_MINUTES" -eq 0 ] || HOLD_ON=1
  HOLD_SECS="$(awk -v s="${STUDIO_OVERNIGHT_HOLD_SECONDS:-}" -v m="$HOLD_MINUTES" 'BEGIN { print (s != "") ? s + 0 : m * 60 }')"
}
```

In `preflight`, after `cfg gate_repairs 2 0 3 int` (L337):

```sh
  cfg hold_minutes 480 0 1440 int
  cfg directive_chars 4000 500 16000 int
  hold_overrides
```

After `spent()` (L415):

```sh
# ---- The event log (spec AC28-29; docs/game-dev/overnight-events.md) ----
# run_event EVENT FIELD… — one line in RUN_DIR/events.jsonl (studio-event);
# a failure is a stderr note, never fatal.
run_event() { sh "$SELF_DIR/studio-event" "$RUN_DIR" "$@" || say "events.jsonl: $1 not written"; }
# state_event ID RECORD — a story_state event for record line RECORD (R17):
# state is its first word (a trailing ':' dropped); why for held, stopped
# and skipped; until for held. Nothing until EV_ON=1.
state_event() {
  [ "${EV_ON:-0}" = 1 ] || return 0
  _se_r="$2"; _se_s="${_se_r%% *}"; _se_s="${_se_s%:}"; _se_w=""; _se_u=""
  case "$_se_r" in
    "held "*) _se_w="${_se_r#held }"; _se_u="${_se_w##* until }"; _se_w="${_se_w% until *}" ;;
    stopped:*|skipped:*) _se_w="${_se_r#*: }" ;;
    "stopped "*|"skipped "*) _se_w="${_se_r#* }" ;;
  esac
  if [ "$_se_s" = held ]; then run_event story_state "story=$1" state=held "why=$_se_w" "until=$_se_u"
  elif [ -n "$_se_w" ]; then run_event story_state "story=$1" "state=$_se_s" "why=$_se_w"
  else run_event story_state "story=$1" "state=$_se_s"; fi
}
# iso_utc EPOCH — EPOCH as YYYY-MM-DDTHH:MM:SSZ (GNU date -d, else BSD -r).
iso_utc() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
```

`start_session`: in the subshell, after `export STUDIO_UNIT_TAG`, add
`&& STUDIO_RUN_DIR="$RUN_DIR" && export STUDIO_RUN_DIR`. `LAUNCH_ENV` is
untouched, so `print_launch` is too.

`run_unit`, after `model_for "$2"` (L620):

```sh
  run_event unit_started "story=${CUR_ID:--}" "unit=$UNIT_TAG" "label=$2" "model=$UNIT_MODEL"
```

`row`, as its last line:

```sh
  run_event unit_ended "story=${CUR_ID:--}" "unit=$UNIT_TAG" "label=$2" "outcome=$3" "usd:=$UNIT_COST"
```

`write_report`, after the `} > "$RUN_DIR/report.md"` (L697):

```sh
  [ "$1" = done ] || state_event - "stopped $1"
  run_event run_ended "ending=$1" "report=$RUN_DIR/report.md"
```

`run_setup`, first lines:

```sh
  printf 'hold_minutes=%s\ndirective_chars=%s\n' "$HOLD_MINUTES" "$DIRECTIVE_CHARS" > "$RUN_DIR/channel" \
    || say "cannot write $RUN_DIR/channel — the operator verbs will refuse this run"
```

`cmd_start`, between `run_setup` and `UNIT_DIR="$RUN_DIR"; …` (L889-890):

```sh
  run_event run_started mode=single max_lanes:=1 "hold_minutes:=$HOLD_MINUTES"
  run_event story_listed story=- chain:=1 'depends[]='
  EV_ON=1; state_event - running
```

- [ ] **Step 4: Implement in `overnight-lanes.sh`**

`story_write`: append `&& state_event "$1" "$2"` to its `mv`.

`lanes_run`: after the `_L` lines (L1538), before `_k=1`:

```sh
  run_event run_started "mode=$MF_MODE" "max_lanes:=$_L" "hold_minutes:=$HOLD_MINUTES"
  for _id in $(awk -F'\t' '!seen[$1]++ { print $1 }' "$MF_ROWS"); do
    run_event story_listed "story=$_id" "chain:=$(chain_of "$_id")" "depends[]=$(row_field "$_id" deps)"
  done
  EV_ON=1
  for _id in $(awk -F'\t' '!seen[$1]++ { print $1 }' "$MF_ROWS"); do state_event "$_id" "$(story_get "$_id")"; done
```

`lanes_report`, after its closing `} > "$RUN_DIR/report.md"`:
`run_event run_ended "ending=$1" "report=$RUN_DIR/report.md"`.

`lanes_reap`: `EV_ON=1` before `SWEEP_WHY=…`. The reaped run's endings are
facts too.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/overnight_test.sh && sh tests/overnight_lanes_test.sh && sh tests/run_all.sh`
Expected: PASS, every existing assertion unchanged.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh \
  tests/overnight_test.sh tests/overnight_lanes_test.sh
git commit -m "feat(overnight): hold config, the channel file and the run's events (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 3: The channel file: `say`, `said`, `unsay`, `--run`, run discovery and the inbox lock

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L56-62, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L118-149, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L344-378, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L439-447
Review: task

**Risk:** this task is a new seam: a sourced file, run discovery across
projects, a mkdir lock with a stale break, and ids. The rev-4 amendments
(AC1's `--`, AC4a's `--run`, the lock paragraph) live here.

**Files:**
- Create: `studios/game-dev/bin/overnight-channel.sh` (mode 755).
- Modify: `studios/game-dev/bin/studio-overnight`:
  - source the channel file just before the dispatch `case "$1" in` (L1089);
  - dispatch `say|said|unsay`;
  - in the `stop)` branch, hand any arguments to `chan_main`.
- Modify: `tests/overnight_test.sh`:
  - the helpers `fake_run`, `fake_run_end`, `verb`, `verb_in`, `put_msg` and
    `ledger_add`, after `live_dummy` (L136);
  - new tests;
  - the `run_tests` list.

**Interfaces:**
- Consumes: T1's `studio-event`. From `studio-overnight`: `say`, `sq`,
  `lock_live`, `lock_pid`, `LOCK`, `STATE_ROOT`, `START_DIR`, `STATE_BIN`,
  `SELF_DIR`, `REGISTRY`, `reg_get` and `reg_live`. T2's `RUN_DIR/channel`.
- Produces, in `overnight-channel.sh`:
  - shared with the runner (T6, T7):
    - `msg_get KEY FILE`: one header value;
    - `msg_body FILE`: the body, newlines folded to spaces;
    - `inbox_lock DIR WAIT [break]` (0 taken, 1 timeout);
    - `inbox_unlock DIR`;
  - `mtime PATH`;
  - `chan_main VERB ARGS…`, which never returns. It sets `CH_RUN` (the run
    dir), `CH_NAME`, `CH_ROOT`, `CH_START`, `CH_PID`, `CH_MODE`
    (`single|manifest`), `CH_STORY`, `CH_REC`, `CH_IB` (the inbox dir),
    `CH_CTL`, `CH_HOLD_MIN` and `CH_DCHARS`;
  - `chan_list DIR`: TSV rows `id state scope text target`, id order;
  - `chan_next_id DIR`;
  - `chan_write_msg ID SCOPE TARGET TEXT`;
  - `chan_event EVENT FIELD…`;
  - `chan_fail CODE TEXT`.
- Output: the message file format (spec L357-368).

- [ ] **Step 1: Write the test helpers and the failing tests**

In `tests/overnight_test.sh`, after `live_dummy`:

```sh
# ---- #27: the operator verbs against a fake live run ----
# fake_run NAME single|manifest [ID=RECORD]… — a live run with no runner in
# the current fixture $P:
# - the lock names a live_dummy pid (FR_PID) and run dir FR_DIR
#   ($P/.studio/reports/NAME);
# - FR_DIR/channel holds FR_HOLD (default 480) and FR_CHARS (default 4000);
# - a registry entry exists (root and start $P).
# manifest also writes:
# - rows.tsv, and stories/ID = RECORD;
# - each story's studio state and ledger (`plan approved x`), committed.
fake_run() {
  _fr_n="$1"; _fr_m="$2"; shift 2
  FR_DIR="$P/.studio/reports/$_fr_n"; mkdir -p "$FR_DIR/stories"
  printf 'hold_minutes=%s\ndirective_chars=%s\n' "${FR_HOLD:-480}" "${FR_CHARS:-4000}" > "$FR_DIR/channel"
  live_dummy; FR_PID="$DUMMY"
  printf 'pid=%s\nrun=%s\nstarted=2026-10-03T21:00:00Z\n' "$FR_PID" "$FR_DIR" > "$P/.studio/overnight.lock"
  mkdir -p "$HOME/.claude-gamedev/runs"
  printf 'root=%s\nstart=%s\nrun=%s\npid=%s\nstarted=2026-10-03T21:00:00Z\n' "$P" "$P" "$FR_DIR" "$FR_PID" \
    > "$HOME/.claude-gamedev/runs/$_fr_n-$FR_PID"
  [ "$_fr_m" = manifest ] || return 0
  : > "$FR_DIR/rows.tsv"
  for _fr_r in "$@"; do
    _fr_id="${_fr_r%%=*}"
    printf '%s\t%s-b\t%s\t-\t-\t\n' "$_fr_id" "$_fr_id" "$_fr_id" >> "$FR_DIR/rows.tsv"
    printf '%s\n' "${_fr_r#*=}" > "$FR_DIR/stories/$_fr_id"
    ( cd "$P" && STUDIO_STORY="$_fr_id" && export STUDIO_STORY \
        && sh "$STATE_BIN" init && sh "$STATE_BIN" ledger "plan approved x" ) >/dev/null 2>&1
  done
  ( cd "$P" && git add -A .studio/stories .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm stories ) >/dev/null 2>&1
}
# fake_run_end [PID] — end a fake run (default FR_PID): its dummy, lock and
# registry entry.
fake_run_end() {
  _fe_p="${1:-$FR_PID}"
  kill "$_fe_p" 2>/dev/null; wait "$_fe_p" 2>/dev/null
  rm -f "$HOME"/.claude-gamedev/runs/*-"$_fe_p"
  [ "$(sed -n 's/^pid=//p' "$P/.studio/overnight.lock" 2>/dev/null)" != "$_fe_p" ] || rm -f "$P/.studio/overnight.lock"
}
# verb_in DIR ARGS… — `studio-overnight ARGS` in DIR: V_STATUS; V_OUT and
# V_ERR (file paths). verb ARGS… — the same in $P.
verb_in() {
  _vi_d="$1"; shift; V_STATUS=0
  ( cd "$_vi_d" && sh "$RUNNER" "$@" ) > "$TMP/v.out" 2> "$TMP/v.err" || V_STATUS=$?
  V_OUT="$TMP/v.out"; V_ERR="$TMP/v.err"
}
verb() { verb_in "$P" "$@"; }
# put_msg DIR ID SCOPE TEXT [TARGET] — a message file DIR/ID.msg, as say writes it.
put_msg() {
  mkdir -p "$1"
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: -\nqueued: 2026-10-03T21:04:00Z\nrequeues: 0\n--\n%s\n' \
    "$2" "$3" "${5:--}" "$4" > "$1/$2.msg"
}
# ledger_add LINE… — single-plan ledger lines in $P, committed.
ledger_add() {
  ( cd "$P" && for _la in "$@"; do sh "$STATE_BIN" ledger "$_la"; done \
      && git add -A .studio/ledger && git -c user.name=t -c user.email=t@t commit -qm ledger ) >/dev/null 2>&1
}
# body FILE — a message file's body.
body() { sed '1,/^--$/d' "$1"; }
```

Tests:

```sh
test_say_writes_message() {
  fixture sw; fake_run overnight-sw-1 single
  verb say - 'Use the EventBus, not "signals" — it'\''s $HOME'
  assert_eq 0 "$V_STATUS" "say exits 0"
  assert_eq 1 "$(cat "$V_OUT")" "say prints the id"
  M="$FR_DIR/inbox/-/1.msg"
  assert_file "$M" "the message is in the story's inbox"
  assert_eq "id: 1|scope: story|target: -|story: -|requeues: 0|--" \
    "$(sed '/^--$/q' "$M" | grep -v '^queued: ' | tr '\n' '|' | sed 's/|$//')" "the header, in order"
  assert_contains "$M" '^queued: 20[0-9-]*T[0-9:]*Z$' "queued is ISO-8601 UTC"
  assert_eq 'Use the EventBus, not "signals" — it'\''s $HOME' "$(body "$M")" "the body is the text, verbatim"
  assert_eq "1.msg" "$(ls -A "$FR_DIR/inbox/-")" "no temp file and no lock left"
  assert_contains "$FR_DIR/events.jsonl" '"event":"message_queued","story":"-","id":1,"scope":"story"}$' "message_queued"
  assert_not_contains "$FR_DIR/events.jsonl" "EventBus" "message text never reaches the log"
  fake_run_end
}
test_say_dash_text_and_unit() {
  fixture sd; fake_run overnight-sd-1 single
  verb say - --unit -- use --force, not '$(x)' "it's"
  assert_eq 0 "$V_STATUS" "say -- exits 0"
  assert_eq "use --force, not \$(x) it's" "$(body "$FR_DIR/inbox/-/1.msg")" "every word after -- is text, joined by spaces"
  assert_contains "$FR_DIR/inbox/-/1.msg" "^scope: unit$" "--unit gives scope unit"
  verb say - --run overnight-sd-1 -- --run x
  assert_eq 0 "$V_STATUS" "--run before --, and an option-like word after it"
  assert_eq "--run x" "$(body "$FR_DIR/inbox/-/2.msg")" "after --, --run is text"
  verb say - --bogus x;  assert_eq 2 "$V_STATUS" "an unknown option is usage"
  verb say - a b;        assert_eq 2 "$V_STATUS" "two text words without -- is usage"
  verb said --unit -;    assert_eq 2 "$V_STATUS" "--unit belongs to say only"
  verb said - -- x;      assert_eq 2 "$V_STATUS" "-- belongs to say only"
  verb say --run;        assert_eq 2 "$V_STATUS" "--run needs a value"
  fake_run_end
}
test_say_empty_text_exit_2() {
  fixture se; fake_run overnight-se-1 single
  nl='
'
  verb say - '';                   assert_eq 2 "$V_STATUS" "say - '': exit 2"
  assert_contains "$V_ERR" "say: empty text" "it names the reason"
  verb say - --;                   assert_eq 2 "$V_STATUS" "say - -- with nothing after it: exit 2"
  verb say - -- '' ' ';            assert_eq 2 "$V_STATUS" "say - -- '' ' ': exit 2"
  verb say - '   ';                assert_eq 2 "$V_STATUS" "spaces only: exit 2"
  verb say - " 	$nl ";           assert_eq 2 "$V_STATUS" "blanks, a tab and a newline: exit 2"
  verb say - --unit --;            assert_eq 2 "$V_STATUS" "--unit with no text: exit 2"
  verb say -;                      assert_eq 2 "$V_STATUS" "no text at all: exit 2"
  assert_missing "$FR_DIR/inbox/-/1.msg" "nothing is written"
  assert_missing "$FR_DIR/events.jsonl" "no event"
  fake_run_end
  verb say - '';                   assert_eq 2 "$V_STATUS" "empty text is usage even with no live run"
}
test_say_ids_ledger_and_inbox() {
  fixture si; ledger_add "Directive 7: older run" "Directive 9 retired"
  fake_run overnight-si-1 single
  verb say - first;  assert_eq 10 "$(cat "$V_OUT")" "the next id passes the ledger's highest (a retired line counts)"
  mkdir -p "$FR_DIR/inbox/-/delivered/tagx"; mv "$FR_DIR/inbox/-/10.msg" "$FR_DIR/inbox/-/delivered/tagx/"
  verb say - second; assert_eq 11 "$(cat "$V_OUT")" "a delivered message's id counts"
  verb say - third;  assert_eq 12 "$(cat "$V_OUT")" "a pending message's id counts"
  assert_missing "$FR_DIR/inbox/-/.lock" "the inbox lock is released"
  fake_run_end
}
test_say_cap() {
  fixture sc; ledger_add "Directive 1: $(printf '%200s' '' | tr ' ' a)"
  FR_CHARS=500; fake_run overnight-sc-1 single; unset FR_CHARS
  verb say - "$(printf '%200s' '' | tr ' ' b)";              assert_eq 0 "$V_STATUS" "400 of 500"
  verb say - --unit -- "$(printf '%400s' '' | tr ' ' u)";    assert_eq 0 "$V_STATUS" "a unit message is not capped"
  verb say - "$(printf '%101s' '' | tr ' ' c)"
  assert_eq 1 "$V_STATUS" "501 characters exceed directive_chars 500"
  assert_contains "$V_ERR" "directive_chars 500" "the refusal names the cap"
  assert_contains "$V_ERR" "^  1  active  aaaa" "it lists the active directive with its id"
  assert_contains "$V_ERR" "^  2  pending  bbbb" "and the pending one"
  assert_not_contains "$V_ERR" "uuuu" "and not the unit message"
  assert_missing "$FR_DIR/inbox/-/4.msg" "nothing is written"
  verb say - "$(printf '%100s' '' | tr ' ' c)";              assert_eq 0 "$V_STATUS" "exactly 500 fits"
  fake_run_end
}
test_say_cap_counts_characters() {
  fixture scc; FR_CHARS=500; fake_run overnight-scc-1 single; unset FR_CHARS
  verb say - "$(printf '%300s' '' | sed 's/ /é/g')"; assert_eq 0 "$V_STATUS" "300 two-byte characters"
  verb say - "$(printf '%200s' '' | sed 's/ /é/g')"; assert_eq 0 "$V_STATUS" "500 characters (1000 bytes) fit a 500-character cap"
  verb say - "é";                                     assert_eq 1 "$V_STATUS" "the 501st character does not"
  fake_run_end
}
test_said_lists_states() {
  fixture sl; ledger_add "Directive 1: one" "Directive 2: two" "Directive 2 retired"
  fake_run overnight-sl-1 single
  verb said -; assert_eq "1  active  one" "$(cat "$V_OUT")" "an active directive; a retired one is not listed"
  verb say - three; verb say - --unit four; verb say - five
  mkdir -p "$FR_DIR/inbox/-/delivered/tg"; mv "$FR_DIR/inbox/-/5.msg" "$FR_DIR/inbox/-/delivered/tg/"
  verb unsay - 1; assert_eq "retire queued: message 6 retires directive 1" "$(cat "$V_OUT")" "unsay of an active directive"
  verb said -
  assert_eq 0 "$V_STATUS" "said exits 0"
  assert_eq "1  retiring  one|3  pending  three|4  pending (unit)  four|5  delivered  five" \
    "$(tr '\n' '|' < "$V_OUT" | sed 's/|$//')" "every state, in id order; the retire message is not listed"
  fake_run_end
  fixture sl2; fake_run overnight-sl2-1 single
  verb said -; assert_eq "(no directives)" "$(cat "$V_OUT")" "none"
  fake_run_end
}
test_unsay_pending_active_delivered() {
  fixture us; ledger_add "Directive 1: one" "Directive 2: two" "Directive 2 retired"
  fake_run overnight-us-1 single; IB="$FR_DIR/inbox/-"
  verb say - three; verb unsay - 3
  assert_eq "removed message 3 (it was not delivered)" "$(cat "$V_OUT")" "a pending story message is removed"
  assert_missing "$IB/3.msg" "its file is gone"
  verb say - --unit four; verb unsay - 4; assert_eq 0 "$V_STATUS" "a pending unit message is removed"
  verb say - five; mkdir -p "$IB/delivered/tg"; mv "$IB/5.msg" "$IB/delivered/tg/"
  verb unsay - 5; assert_eq "retire queued: message 6 retires directive 5" "$(cat "$V_OUT")" "delivered, not recorded: a retire"
  assert_contains "$IB/6.msg" "^scope: retire$" "the retire's scope"
  assert_contains "$IB/6.msg" "^target: 5$" "and target"
  verb unsay - 5; assert_eq 1 "$V_STATUS" "a retiring directive: exit 1"
  assert_contains "$V_ERR" "already retiring" "named"
  verb unsay - 6; assert_eq 1 "$V_STATUS" "a retire message: exit 1"
  verb unsay - 2; assert_eq 1 "$V_STATUS" "a retired id: exit 1"
  assert_contains "$V_ERR" "already retired" "named"
  verb unsay - 99; assert_eq 1 "$V_STATUS" "an unknown id: exit 1"
  assert_eq 1 "$(grep -c . "$V_ERR")" "a refusal is one stderr line"
  verb say - --unit seven; mv "$IB/7.msg" "$IB/delivered/tg/"
  verb unsay - 7; assert_eq 1 "$V_STATUS" "a delivered unit message is spent: exit 1"
  for bad in 01 x '' 1x; do verb unsay - "$bad"; assert_eq 2 "$V_STATUS" "id '$bad' is usage"; done
  fake_run_end
}
test_unsay_id_prefix() {
  fixture up; ledger_add "Directive 10: ten"
  fake_run overnight-up-1 single; IB="$FR_DIR/inbox/-"
  put_msg "$IB" 1 story one
  verb unsay - 1
  assert_eq "removed message 1 (it was not delivered)" "$(cat "$V_OUT")" "unsay 1 removes message 1"
  assert_missing "$IB/1.msg" "1.msg is gone"
  assert_eq "" "$(ls "$IB" | grep -v '^delivered$')" "no retire was queued for directive 10"
  verb said -; assert_eq "10  active  ten" "$(cat "$V_OUT")" "directive 10 is still active"
  verb unsay - 1; assert_eq 1 "$V_STATUS" "a second unsay 1 is unknown"
  fake_run_end
}
test_verbs_refusals() {
  fixture rf
  verb say - x; assert_eq 1 "$V_STATUS" "no live run: exit 1"
  assert_contains "$V_ERR" "no live run" "named"
  fake_run overnight-rf-1 manifest S1=running S2="landed abc1234" S3="stopped stop: x" S4="skipped S2"
  verb say S9 x; assert_eq 1 "$V_STATUS" "a story not in the run"; assert_contains "$V_ERR" "S9 is not in run overnight-rf-1" "named"
  verb say - x;  assert_eq 1 "$V_STATUS" "- in a manifest run"
  for id in S2 S3 S4; do
    verb said "$id"; assert_eq 1 "$V_STATUS" "$id has ended: exit 1"
    assert_contains "$V_ERR" "story $id has ended" "named"
    assert_eq 1 "$(grep -c . "$V_ERR")" "one line"
  done
  verb said;          assert_eq 2 "$V_STATUS" "said with no story"
  verb unsay S1;      assert_eq 2 "$V_STATUS" "unsay with no id"
  verb said S1 S1 S1; assert_eq 2 "$V_STATUS" "too many words"
  rm -f "$FR_DIR/channel"
  verb said S1; assert_eq 1 "$V_STATUS" "a run without a channel file"
  assert_contains "$V_ERR" "predates the operator channel" "named"
  fake_run_end
  fixture rf2; fake_run overnight-rf2-1 single
  verb say S1 x; assert_eq 1 "$V_STATUS" "a story id in a single-plan run"
  assert_contains "$V_ERR" "single-plan run: its story is -" "named"
  fake_run_end
}
test_verbs_run_pinning() {
  fixture pa; fake_run overnight-pa-1 single; PA="$P"; PA_PID="$FR_PID"
  verb say --run overnight-pa-1 - x; assert_eq 0 "$V_STATUS" "--run naming this project's run"
  verb say - --run overnight-pa-1 -- y; assert_eq 0 "$V_STATUS" "--run anywhere before --"
  verb say --run overnight-pa - x; assert_eq 1 "$V_STATUS" "a prefix is not a match"
  assert_contains "$V_ERR" "run overnight-pa is not live" "named"
  fixture pb; fake_run overnight-pb-1 manifest S1=running; PB="$P"; PB_PID="$FR_PID"
  verb_in "$PA" say --run overnight-pb-1 - x
  assert_eq 1 "$V_STATUS" "inside a project, only that project's run"
  assert_contains "$V_ERR" "run overnight-pb-1 is not live" "never a fallback to another project's run"
  assert_missing "$PB/.studio/reports/overnight-pb-1/inbox" "nothing reached the other run"
  mkdir -p "$TMP/outside"
  verb_in "$TMP/outside" said -; assert_eq 1 "$V_STATUS" "two live runs outside a project and no --run"
  assert_contains "$V_ERR" "overnight-pa-1" "names the first"; assert_contains "$V_ERR" "overnight-pb-1" "and the second"
  verb_in "$TMP/outside" said --run overnight-pb-1 S1; assert_eq 0 "$V_STATUS" "--run picks one"
  assert_eq "(no directives)" "$(cat "$V_OUT")" "from the named run"
  verb_in "$TMP/outside" say --run overnight-zz - x; assert_eq 1 "$V_STATUS" "an unknown run"
  assert_contains "$V_ERR" "run overnight-zz is not live" "named"
  # bare stop with --run
  P="$PA"; verb stop --run overnight-pb-1; assert_eq 1 "$V_STATUS" "stop --run of another project's run"
  assert_missing "$PA/.studio/overnight.stop" "no stop file here"
  assert_missing "$PB/.studio/overnight.stop" "nor there"
  verb_in "$TMP/outside" stop --run overnight-pb-1; assert_eq 0 "$V_STATUS" "stop --run from outside"
  assert_contains "$V_OUT" "^stop requested: the run ends after its running unit (pid $PB_PID)$" "today's line"
  assert_file "$PB/.studio/overnight.stop" "the named run's stop file"
  P="$PB"; fake_run_end "$PB_PID"
  # an ended run is never live
  printf 'root=%s\nstart=%s\nrun=%s\npid=1\nended=x\n' "$PB" "$PB" "$PB/.studio/reports/overnight-pb-1" > "$HOME/.claude-gamedev/runs/last"
  verb_in "$TMP/outside" said --run overnight-pb-1 S1; assert_eq 1 "$V_STATUS" "the last ended run is not live"
  rm -f "$HOME/.claude-gamedev/runs/last"
  P="$PA"; verb stop --run overnight-pa-1; assert_eq 0 "$V_STATUS" "stop --run of this project's run"
  assert_file "$PA/.studio/overnight.stop" "writes its stop file"
  fake_run_end "$PA_PID"
}
test_inbox_lock_stale_broken() {
  fixture lk; fake_run overnight-lk-1 single
  mkdir -p "$FR_DIR/inbox/-/.lock"; touch -t 202001010000 "$FR_DIR/inbox/-/.lock"
  verb say - x
  assert_eq 0 "$V_STATUS" "a stale lock is broken"
  assert_eq 1 "$(cat "$V_OUT")" "and the message written"
  assert_eq "1.msg" "$(ls -A "$FR_DIR/inbox/-")" "no lock and no renamed stale lock left"
  fake_run_end
}
test_inbox_lock_busy() {
  fixture lb; fake_run overnight-lb-1 single
  mkdir -p "$FR_DIR/inbox/-/.lock"
  STUDIO_OVERNIGHT_INBOX_WAIT=2; export STUDIO_OVERNIGHT_INBOX_WAIT
  t0="$(date +%s)"; verb say - x; t1="$(date +%s)"
  unset STUDIO_OVERNIGHT_INBOX_WAIT
  assert_eq 1 "$V_STATUS" "a fresh lock held past the wait: exit 1"
  assert_contains "$V_ERR" "inbox busy" "named"
  assert_eq 1 "$([ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -lt 10 ] && echo 1 || echo 0)" "it waited about STUDIO_OVERNIGHT_INBOX_WAIT seconds"
  assert_missing "$FR_DIR/inbox/-/1.msg" "nothing written"
  assert_eq 1 "$([ -d "$FR_DIR/inbox/-/.lock" ] && echo 1 || echo 0)" "a fresh lock is never broken"
  fake_run_end
}
test_channel_sourced_only() {
  assert_status 2 "overnight-channel.sh refuses to run on its own" -- sh "$REPO_ROOT/studios/game-dev/bin/overnight-channel.sh"
  assert_eq "overnight-channel.sh: sourced by studio-overnight" \
    "$(sh "$REPO_ROOT/studios/game-dev/bin/overnight-channel.sh" 2>&1)" "and says why"
}
```

Add every name to `run_tests`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_test.sh`
Expected: FAIL in each new test. `say`/`said`/`unsay` fall through to
`usage` (exit 2), so the exit-1 and exit-0 assertions fail. The existing
tests pass, `test_overnight_stop_no_run` included.

- [ ] **Step 3: Write `overnight-channel.sh`**

The full file. `chan_args`, `chan_list` and `chan_next_id` are verified
as written (trial t3): `--bogus` returns 2; the list rows for active,
retiring, pending, delivered and retired; next id 11.

```sh
#!/bin/sh
# overnight-channel.sh — the operator channel (#27; spec AC1-8): the verbs
# say, said, unsay, hold, resume and stop <story>, --run, run discovery, the
# inbox lock, ids and the cap; plus the message helpers the runner shares
# (msg_get, msg_body, inbox_lock, inbox_unlock). Sourced by studio-overnight
# before its dispatch; never run on its own. The verbs write only
# inbox/<story>/<id>.msg and control/<story>.<kind> in the live run's dir,
# each by temp file then mv, and never a story record (R1, R27).
[ -n "${SELF_DIR:-}" ] || { echo "overnight-channel.sh: sourced by studio-overnight" >&2; exit 2; }
CH_TAB="$(printf '\t')"

# msg_get KEY FILE — a message header's value (header lines only).
msg_get() { sed -n "1,/^--\$/s/^$1: //p" "$2" 2>/dev/null | head -n 1; }
# msg_body FILE — the message text, its newlines folded to spaces.
msg_body() { sed '1,/^--$/d' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; }
# mtime PATH — PATH's modification time in epoch seconds (GNU, else BSD).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# inbox_lock DIR WAIT [break] — R10: mkdir DIR/.lock, retried each second
# for up to WAIT seconds, the owner token "<pid> <epoch>" (IL_TOKEN) in
# DIR/.lock/owner. With `break`, a lock whose dir is over 10 s old is renamed
# to a unique name, then removed, or put back when the renamed dir is fresh
# (it was a waiter's new lock). Returns 1 on timeout. The runner calls it
# without `break`, so it needs no stat (the minimal PATH).
inbox_lock() {
  mkdir -p "$1" 2>/dev/null || return 1
  _il_t=0
  while ! mkdir "$1/.lock" 2>/dev/null; do
    if [ "${3:-}" = break ] && _il_m="$(mtime "$1/.lock")" && [ -n "$_il_m" ] \
       && [ $(( $(date +%s) - _il_m )) -gt 10 ]; then
      _il_s="$1/.lock.stale.$$.$(date +%s)"
      if mv "$1/.lock" "$_il_s" 2>/dev/null; then
        _il_m="$(mtime "$_il_s")"
        if [ -n "$_il_m" ] && [ $(( $(date +%s) - _il_m )) -le 10 ]; then
          [ -e "$1/.lock" ] || mv "$_il_s" "$1/.lock" 2>/dev/null   # a new lock: put it back (never nest it)
        else
          rm -rf "$_il_s"
        fi
      fi
      continue
    fi
    [ "$_il_t" -lt "$2" ] || return 1
    sleep 1; _il_t=$((_il_t + 1))
  done
  IL_TOKEN="$$ $(date +%s)"; printf '%s\n' "$IL_TOKEN" > "$1/.lock/owner" 2>/dev/null
  return 0
}
# inbox_unlock DIR — release DIR/.lock when this process holds it.
inbox_unlock() {
  [ "$(cat "$1/.lock/owner" 2>/dev/null)" != "${IL_TOKEN:-}" ] || rm -rf "$1/.lock"
  IL_TOKEN=""
}

# chan_fail CODE TEXT — one stderr line, exit CODE.
chan_fail() { say "$2"; exit "$1"; }
chan_usage() {
  {
    echo "usage: studio-overnight say <story> [--unit] [--run <run>] '<text>' | say <story> [--unit] [--run <run>] -- <text>"
    echo "       studio-overnight said|hold|resume|stop <story> [--run <run>] | unsay <story> <id> [--run <run>] | stop [--run <run>]"
    echo "       (<story> is - in a single-plan run; <run> is the run dir's basename)"
  } >&2
  exit 2
}
# chan_args ARGS… — A_RUN, A_UNIT, A_DASH, A_TEXT (every word after --,
# joined by spaces), A_N positionals in A_P1..A_P3. Returns 2 on an unknown
# option, --run with no value, or a fourth positional.
chan_args() {
  A_RUN=""; A_UNIT=0; A_DASH=0; A_TEXT=""; A_N=0; A_P1=""; A_P2=""; A_P3=""
  while [ "$#" -gt 0 ]; do
    if [ "$A_DASH" = 1 ]; then A_TEXT="${A_TEXT:+$A_TEXT }$1"; shift; continue; fi
    case "$1" in
      --) A_DASH=1 ;;
      --run) [ "$#" -ge 2 ] || return 2; A_RUN="$2"; shift ;;
      --unit) A_UNIT=1 ;;
      -?*) return 2 ;;
      *) [ "$A_N" -lt 3 ] || return 2; A_N=$((A_N + 1)); eval "A_P$A_N=\$1" ;;
    esac
    shift
  done
}

# chan_find_run — R2: CH_RUN, CH_ROOT, CH_START, CH_PID of the one live run
# this verb acts on, or exit 1. Inside a project: the lock's run, which
# --run must name exactly. Outside: the live registry entries, filtered by
# --run.
chan_find_run() {
  CH_RUN=""; CH_ROOT=""; CH_START=""; CH_PID=""
  if [ -n "$STATE_ROOT" ] && [ -d "$STATE_ROOT/.studio" ]; then
    if lock_live; then CH_RUN="$(sed -n 's/^run=//p' "$LOCK" | head -n 1)"; CH_PID="$(lock_pid)"; fi
    if [ -n "$A_RUN" ] && [ "${CH_RUN##*/}" != "$A_RUN" ]; then chan_fail 1 "run $A_RUN is not live"; fi
    [ -n "$CH_RUN" ] || chan_fail 1 "no live run in $STATE_ROOT"
    CH_ROOT="$STATE_ROOT"; CH_START="$START_DIR"
    for _cf_e in "$REGISTRY"/overnight-*; do
      [ -f "$_cf_e" ] && [ "$(reg_get run "$_cf_e")" = "$CH_RUN" ] || continue
      _cf_s="$(reg_get start "$_cf_e")"; [ -z "$_cf_s" ] || CH_START="$_cf_s"
      break
    done
    return 0
  fi
  _cf_n=0; _cf_names=""
  for _cf_e in "$REGISTRY"/overnight-*; do
    [ -f "$_cf_e" ] && reg_live "$_cf_e" || continue
    _cf_r="$(reg_get run "$_cf_e")"
    [ -z "$A_RUN" ] || [ "${_cf_r##*/}" = "$A_RUN" ] || continue
    _cf_n=$((_cf_n + 1)); _cf_names="${_cf_names:+$_cf_names, }${_cf_r##*/}"
    CH_RUN="$_cf_r"; CH_ROOT="$(reg_get root "$_cf_e")"; CH_START="$(reg_get start "$_cf_e")"; CH_PID="$(reg_get pid "$_cf_e")"
  done
  if [ "$_cf_n" -eq 0 ]; then
    [ -z "$A_RUN" ] || chan_fail 1 "run $A_RUN is not live"
    chan_fail 1 "no live run (run the verb in the run's project, or name the run with --run)"
  fi
  [ "$_cf_n" -eq 1 ] || chan_fail 1 "$_cf_n live runs ($_cf_names): name one with --run"
}
# chan_open VERB STORY — R3, AC4, AC6: the run's channel file, the story's
# membership and record (CH_REC), and its paths. Exit 1 on any refusal.
chan_open() {
  CH_NAME="${CH_RUN##*/}"; CH_STORY="$2"
  [ -f "$CH_RUN/channel" ] || chan_fail 1 "run $CH_NAME predates the operator channel (restart it to use $1)"
  CH_HOLD_MIN="$(sed -n 's/^hold_minutes=//p' "$CH_RUN/channel" | head -n 1)"
  CH_DCHARS="$(sed -n 's/^directive_chars=//p' "$CH_RUN/channel" | head -n 1)"
  if [ -f "$CH_RUN/rows.tsv" ]; then
    CH_MODE=manifest
    awk -F'\t' -v id="$2" '$1 == id { f = 1 } END { exit !f }' "$CH_RUN/rows.tsv" \
      || chan_fail 1 "story $2 is not in run $CH_NAME"
    CH_REC="$(cat "$CH_RUN/stories/$2" 2>/dev/null)"
  else
    CH_MODE=single
    [ "$2" = - ] || chan_fail 1 "run $CH_NAME is a single-plan run: its story is -"
    CH_REC="$(cat "$CH_RUN/control/-.held" 2>/dev/null)"; [ -n "$CH_REC" ] || CH_REC=running
  fi
  case "$CH_REC" in landed*|stopped*|skipped*) chan_fail 1 "story $2 has ended: $CH_REC" ;; esac
  CH_IB="$CH_RUN/inbox/$2"; CH_CTL="$CH_RUN/control"
}
# chan_ledger — the story's feature-ledger lines (`- <date> <text>`), read in
# its feature checkout when one exists, else in the start checkout. Never
# the verb's cwd (R22).
chan_ledger() {
  ( cd "$CH_START" 2>/dev/null || exit 0
    if [ "$CH_STORY" = - ]; then unset STUDIO_STORY; else STUDIO_STORY="$CH_STORY"; export STUDIO_STORY; fi
    _cl_w="$(sh "$STATE_BIN" worktree 2>/dev/null)"
    [ -z "$_cl_w" ] || [ ! -d "$_cl_w" ] || cd "$_cl_w"
    sh "$STATE_BIN" show 2>/dev/null ) | sed -n '/^## Feature ledger: /,$p' | sed 1d
}
# chan_list DIR — the story's directives and messages, one TSV row each,
# `id state scope text target`, in id order. It reads the ledger lines in
# CH_LEDGER (exported) and DIR's pending and delivered files. States:
# active and retiring (ledgered); pending (any scope); delivered (a story
# message not yet ledgered, or a retire whose target is not yet retired).
# Retired directives and spent unit messages are not listed.
chan_list() {
  _cl_d="$1"; set --
  for _cl_f in "$_cl_d"/[0-9]*.msg "$_cl_d"/delivered/*/[0-9]*.msg; do [ -f "$_cl_f" ] && set -- "$@" "$_cl_f"; done
  [ "$#" -gt 0 ] || set -- /dev/null
  awk '
    function out(a, b, c, d, e) { print a "\t" b "\t" c "\t" d "\t" e }
    BEGIN {
      n = split(ENVIRON["CH_LEDGER"], L, "\n")
      for (i = 1; i <= n; i++) {
        l = L[i]
        if (match(l, /^- [0-9-]+ Directive [0-9]+: /)) {
          h = substr(l, 1, RLENGTH - 2); sub(/.* /, "", h)
          if (!(h in act)) act[h] = substr(l, RLENGTH + 1)
        } else if (l ~ /^- [0-9-]+ Directive [0-9]+ retired *$/) {
          h = l; sub(/^- [0-9-]+ Directive /, "", h); sub(/ .*/, "", h); ret[h] = 1
        }
      }
    }
    FILENAME == "/dev/null" { next }
    FNR == 1 { f = FILENAME; F[++nf] = f; inb[f] = 0; tg[f] = "-"; dl[f] = (f ~ /\/delivered\//) }
    !inb[f] {
      if ($0 == "--") { inb[f] = 1; next }
      if (match($0, /^[a-z]+: /)) {
        k = substr($0, 1, RLENGTH - 2); v = substr($0, RLENGTH + 1)
        if (k == "id") id[f] = v; else if (k == "scope") sc[f] = v; else if (k == "target") tg[f] = v
      }
      next
    }
    { gsub(/\t/, " "); tx[f] = (tx[f] == "" ? $0 : tx[f] " " $0) }
    END {
      for (i = 1; i <= nf; i++) { f = F[i]; if (sc[f] == "retire" && !(tg[f] in ret)) rt[tg[f]] = id[f] }
      for (h in act) if (!(h in ret)) out(h, (h in rt) ? "retiring" : "active", "story", act[h], "-")
      for (i = 1; i <= nf; i++) {
        f = F[i]
        if (!dl[f]) out(id[f], "pending", sc[f], tx[f], tg[f])
        else if (sc[f] == "story" && !(id[f] in act) && !(id[f] in ret)) out(id[f], (id[f] in rt) ? "retiring" : "delivered", "story", tx[f], "-")
        else if (sc[f] == "retire" && !(tg[f] in ret)) out(id[f], "delivered", "retire", tx[f], tg[f])
      }
    }' "$@" | sort -t "$CH_TAB" -k1,1n
}
# chan_next_id DIR — one more than the highest id among CH_LEDGER's
# Directive lines and DIR's message files, pending first, then delivered
# (R10, R11).
chan_next_id() {
  _ni_d="$1"; set --
  for _ni_f in "$_ni_d"/[0-9]*.msg "$_ni_d"/delivered/*/[0-9]*.msg; do [ -f "$_ni_f" ] && set -- "$@" "${_ni_f##*/}"; done
  { printf '%s\n' "$CH_LEDGER" | sed -n 's/^- [0-9-]* Directive \([0-9][0-9]*\)[: ].*/\1/p'
    for _ni_b in "$@"; do printf '%s\n' "${_ni_b%.msg}"; done
  } | awk '$1 + 0 > m { m = $1 + 0 } END { print m + 1 }'
}
# chan_write_msg ID SCOPE TARGET TEXT — CH_IB/ID.msg, by temp file then mv.
chan_write_msg() {
  _wm_t="$CH_IB/.say.$$"
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: %s\nqueued: %s\nrequeues: 0\n--\n%s\n' \
    "$1" "$2" "$3" "$CH_STORY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$4" > "$_wm_t" \
    && mv -f "$_wm_t" "$CH_IB/$1.msg" && return 0
  rm -f "$_wm_t"; return 1
}
# chan_event EVENT FIELD… — studio-event into the run's log; a failure is
# one line in hook.log, never fatal (AC29).
chan_event() { sh "$SELF_DIR/studio-event" "$CH_RUN" "$@" 2>> "$CH_RUN/hook.log" || true; }
# chan_chars — the character count of stdin (UTF-8 lead bytes; R13).
chan_chars() { LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }

# chan_say TEXT — AC1, AC5: the next id, the cap (story scope only), the
# message, a message_queued event; prints the id.
chan_say() {
  _cs_sc=story; [ "$A_UNIT" = 0 ] || _cs_sc=unit
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  inbox_lock "$CH_IB" "${STUDIO_OVERNIGHT_INBOX_WAIT:-15}" break || chan_fail 1 "inbox busy: story $CH_STORY (try again)"
  if [ "$_cs_sc" = story ]; then
    _cs_l="$(chan_list "$CH_IB")"
    _cs_used="$(printf '%s\n' "$_cs_l" | awk -F'\t' '$3 == "story" { printf "%s", $4 }' | chan_chars)"
    _cs_new="$(printf '%s' "$1" | tr '\n' ' ' | chan_chars)"
    if [ $((_cs_used + _cs_new)) -gt "$CH_DCHARS" ]; then
      inbox_unlock "$CH_IB"
      say "say: story $CH_STORY would carry $((_cs_used + _cs_new)) directive characters, over directive_chars $CH_DCHARS — retire one (unsay) first:"
      printf '%s\n' "$_cs_l" | awk -F'\t' '$3 == "story" { printf "  %s  %s  %s\n", $1, $2, $4 }' >&2
      exit 1
    fi
  fi
  _cs_id="$(chan_next_id "$CH_IB")"
  chan_write_msg "$_cs_id" "$_cs_sc" - "$1" || { inbox_unlock "$CH_IB"; chan_fail 1 "cannot write $CH_IB/$_cs_id.msg"; }
  inbox_unlock "$CH_IB"
  chan_event message_queued "story=$CH_STORY" "id:=$_cs_id" "scope=$_cs_sc"
  printf '%s\n' "$_cs_id"
}
# chan_said — AC3, R15.
chan_said() {
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  _sd="$(chan_list "$CH_IB" | awk -F'\t' '$3 == "retire" { next }
    { s = $2; if (s == "pending" && $3 == "unit") s = "pending (unit)"; printf "%s  %s  %s\n", $1, s, $4 }')"
  if [ -n "$_sd" ]; then printf '%s\n' "$_sd"; else echo "(no directives)"; fi
}
# chan_unsay ID — AC2, R12.
chan_unsay() {
  CH_LEDGER="$(chan_ledger)"; export CH_LEDGER
  inbox_lock "$CH_IB" "${STUDIO_OVERNIGHT_INBOX_WAIT:-15}" break || chan_fail 1 "inbox busy: story $CH_STORY (try again)"
  _us="$(chan_list "$CH_IB" | awk -F'\t' -v id="$1" '$1 == id { print $2 "\t" $3; exit }')"
  _us_st="${_us%%"$CH_TAB"*}"; _us_sc="${_us#*"$CH_TAB"}"
  case "$_us_st:$_us_sc" in
    pending:retire) inbox_unlock "$CH_IB"; chan_fail 1 "message $1 is a retire message: unsay retires directives, not retires" ;;
    pending:*)
      rm -f "$CH_IB/$1.msg"; inbox_unlock "$CH_IB"
      echo "removed message $1 (it was not delivered)"; return 0 ;;
    active:story|delivered:story)
      _us_id="$(chan_next_id "$CH_IB")"
      chan_write_msg "$_us_id" retire "$1" "retire directive $1" || { inbox_unlock "$CH_IB"; chan_fail 1 "cannot write $CH_IB/$_us_id.msg"; }
      inbox_unlock "$CH_IB"
      chan_event message_queued "story=$CH_STORY" "id:=$_us_id" scope=retire
      echo "retire queued: message $_us_id retires directive $1"; return 0 ;;
    retiring:*) inbox_unlock "$CH_IB"; chan_fail 1 "directive $1 is already retiring" ;;
    delivered:retire) inbox_unlock "$CH_IB"; chan_fail 1 "message $1 is a retire message: unsay retires directives, not retires" ;;
  esac
  inbox_unlock "$CH_IB"
  if printf '%s\n' "$CH_LEDGER" | grep -q "^- [0-9-]* Directive $1 retired *\$"; then chan_fail 1 "directive $1 is already retired"; fi
  for _us_f in "$CH_IB"/delivered/*/"$1.msg"; do
    [ -f "$_us_f" ] && chan_fail 1 "message $1 was for one unit only and is spent: nothing to retire"
  done
  chan_fail 1 "no message or directive $1 for story $CH_STORY"
}
# chan_stop_run — bare `stop --run <run>`: today's stop, aimed by --run.
chan_stop_run() {
  : > "$CH_ROOT/.studio/overnight.stop" 2>/dev/null || chan_fail 1 "cannot write $CH_ROOT/.studio/overnight.stop"
  echo "stop requested: the run ends after its running unit (pid $CH_PID)"
}

# chan_main VERB ARGS… — parse, check usage (exit 2, before any run lookup),
# find the run, open the story, act. Never returns.
chan_main() {
  CH_VERB="$1"; shift
  chan_args "$@" || chan_usage
  [ "$CH_VERB" = say ] || { [ "$A_UNIT" = 0 ] && [ "$A_DASH" = 0 ]; } || chan_usage
  case "$CH_VERB" in
    say)
      if [ "$A_DASH" = 1 ]; then [ "$A_N" -eq 1 ] || chan_usage; _cm_t="$A_TEXT"
      else [ "$A_N" -eq 2 ] || chan_usage; _cm_t="$A_P2"; fi
      chan_text_check "$_cm_t" ;;
    said) [ "$A_N" -eq 1 ] || chan_usage ;;
    unsay) [ "$A_N" -eq 2 ] || chan_usage
           case "$A_P2" in ''|0*|*[!0-9]*) chan_usage ;; esac ;;
    stop) [ "$A_N" -eq 0 ] || chan_usage ;;
    *) chan_usage ;;
  esac
  chan_find_run
  if [ "$CH_VERB" = stop ] && [ "$A_N" -eq 0 ]; then chan_stop_run; exit 0; fi
  chan_open "$CH_VERB" "$A_P1"
  case "$CH_VERB" in
    say) chan_say "$_cm_t" ;;
    said) chan_said ;;
    unsay) chan_unsay "$A_P2" ;;
  esac
  exit 0
}
# chan_text_check TEXT — R14: exit 2 when TEXT has no non-blank character.
# (A function, so the case pattern never sits inside $(...).)
chan_text_check() {
  case "$1" in *[![:space:]]*) return 0 ;; esac
  say "say: empty text"; exit 2
}
```

`chmod 755 studios/game-dev/bin/overnight-channel.sh`.

- [ ] **Step 4: Wire it into `studio-overnight`**

Just before `case "$1" in` (L1089):

```sh
# The operator channel's verbs (#27): say, said, unsay, hold, resume,
# stop <story> and stop --run; and the message helpers the runner uses.
. "$SELF_DIR/overnight-channel.sh"
```

In the dispatch, add `say|said|unsay) chan_main "$@" ;;` and make the
`stop)` branch's first line `[ "$#" -eq 1 ] || chan_main "$@"`. Leave the
bare-stop body unchanged (R27).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/overnight_test.sh && sh tests/studio_test.sh`
Expected: PASS. `test_overnight_stop_no_run` still passes unchanged: bare
`stop` never reaches `chan_main`. `test_bin_syntax` sees the new file.

- [ ] **Step 6: Commit**

```bash
git add studios/game-dev/bin/overnight-channel.sh studios/game-dev/bin/studio-overnight tests/overnight_test.sh
git commit -m "feat(overnight): say, said, unsay and --run on a live run (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 4: `hold`, `resume` and `stop <story>`

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L150-168, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L267-274, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L354-354
Review: task

**Risk:** the AC7 table decides which state each verb may touch. A wrong
row lets an operator's `hold` reach a landing, which holds the land lock.

**Files:**
- Modify: `studios/game-dev/bin/overnight-channel.sh`:
  - `chan_main`'s usage case and its act case;
  - new functions `chan_ctl_write`, `chan_holds_on`, `chan_hold`,
    `chan_resume`, `chan_stop`.
- Modify: `studios/game-dev/bin/studio-overnight`: the dispatch adds
  `hold|resume`.
- Modify: `tests/overnight_test.sh`: new tests; the `run_tests` list.

**Interfaces:**
- Consumes: T3's `chan_main`, `CH_*`, `chan_fail`, `chan_event`.
- Produces: `control/<story>.hold|.resume|.stop` in the run dir. Each file
  holds one line, the UTC time it was written. The runner reads only the
  file's presence (T6, T7). A `control` event is written for each.

- [ ] **Step 1: Write the failing tests**

```sh
test_hold_resume_stop_table() {
  fixture tb
  fake_run overnight-tb-1 manifest Q=queued W=waiting R=running G=gate-repair \
    H="held stop: need art until 2026-10-04T05:00:00Z" L=landing P=repair
  C="$FR_DIR/control"
  for id in Q W R G H L P; do cp "$FR_DIR/stories/$id" "$TMP/rec-$id"; done
  for id in Q W; do verb hold "$id"; assert_eq "hold requested: $id holds when it would start" "$(cat "$V_OUT")" "hold $id"; done
  for id in R G; do verb hold "$id"; assert_eq "hold requested: $id holds at its next unit boundary" "$(cat "$V_OUT")" "hold $id"; done
  for id in Q W R G; do assert_file "$C/$id.hold" "hold $id writes control/$id.hold"; done
  verb hold H; assert_eq 1 "$V_STATUS" "hold on a held story"; assert_contains "$V_ERR" "already held" "named"
  for id in L P; do
    verb hold "$id"; assert_eq 1 "$V_STATUS" "hold $id (landing)"; assert_contains "$V_ERR" "land lock" "named"
    verb resume "$id"; assert_eq 1 "$V_STATUS" "resume $id (landing)"
    verb stop "$id"; assert_eq 1 "$V_STATUS" "stop $id (landing)"; assert_contains "$V_ERR" "land lock" "named"
    verb say "$id" note; assert_eq 0 "$V_STATUS" "say $id still queues"
  done
  for id in Q W R G; do verb resume "$id"; assert_eq 1 "$V_STATUS" "resume $id: not held"; assert_contains "$V_ERR" "is not held" "named"; done
  verb resume H; assert_eq "resume requested: H resumes within one poll" "$(cat "$V_OUT")" "resume H"
  assert_file "$C/H.resume" "control/H.resume"
  for id in Q W; do verb stop "$id"; assert_eq "stop requested: $id stops when its lane reaches it" "$(cat "$V_OUT")" "stop $id"; done
  for id in R G; do verb stop "$id"; assert_eq "stop requested: $id stops after its running unit" "$(cat "$V_OUT")" "stop $id"; done
  verb stop H; assert_eq "stop requested: H stops within one poll" "$(cat "$V_OUT")" "stop H"
  for id in Q W R G H; do assert_file "$C/$id.stop" "control/$id.stop"; done
  for id in L P; do assert_missing "$C/$id.hold" "no control file for $id"; assert_missing "$C/$id.stop" "nor a stop"; done
  for id in Q W R G H L P; do assert_eq "$(cat "$TMP/rec-$id")" "$(cat "$FR_DIR/stories/$id")" "the verbs never write $id's record"; done
  verb hold Q; assert_eq "hold requested: Q holds when it would start" "$(cat "$V_OUT")" "hold again: the same line (R22)"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"Q","action":"hold"}$' "a control event for hold"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"H","action":"resume"}$' "for resume"
  assert_contains "$FR_DIR/events.jsonl" '"event":"control","story":"R","action":"stop"}$' "for stop"
  assert_eq "" "$(ls -A "$C" | grep '^\.')" "no temp control file left"
  fake_run_end
}
test_hold_minutes_zero() {
  fixture hz; FR_HOLD=0; fake_run overnight-hz-1 manifest S1=running S2="held stop: x until 2026-10-04T05:00:00Z"; unset FR_HOLD
  verb hold S1;   assert_eq 1 "$V_STATUS" "hold with hold_minutes 0"
  assert_eq "studio-overnight: holds are off: hold_minutes 0" "$(cat "$V_ERR")" "the exact line"
  verb resume S2; assert_eq 1 "$V_STATUS" "resume with hold_minutes 0"
  assert_contains "$V_ERR" "holds are off: hold_minutes 0" "named"
  verb say S1 x;  assert_eq 0 "$V_STATUS" "say works"
  verb said S1;   assert_eq 0 "$V_STATUS" "said works"
  verb unsay S1 1; assert_eq 0 "$V_STATUS" "unsay works"
  verb stop S1;   assert_eq 0 "$V_STATUS" "stop <story> works"
  fake_run_end
}
test_single_plan_verbs() {
  fixture spv; fake_run overnight-spv-1 single; C="$FR_DIR/control"
  verb hold -;   assert_eq "hold requested: - holds at its next unit boundary" "$(cat "$V_OUT")" "hold - on the running story"
  verb resume -; assert_eq 1 "$V_STATUS" "resume -: not held"
  verb hold S1;  assert_eq 1 "$V_STATUS" "a story id in a single-plan run"
  mkdir -p "$C"; printf 'held stop: x until 2026-10-04T05:00:00Z\n' > "$C/-.held"
  verb hold -;   assert_eq 1 "$V_STATUS" "control/-.held: already held"
  verb resume -; assert_eq 0 "$V_STATUS" "resume - on a held story"
  assert_file "$C/-.resume" "control/-.resume"
  verb stop -;   assert_eq "stop requested: - stops within one poll" "$(cat "$V_OUT")" "stop - on a held story"
  rm -f "$C/-.held"
  verb stop -;   assert_eq "stop requested: - stops after its running unit" "$(cat "$V_OUT")" "stop - on the running story"
  assert_missing "$P/.studio/overnight.stop" "stop - never writes the run's stop file"
  fake_run_end
}
test_resume_refused_dirty_ledger() {
  fixture rd; fake_run overnight-rd-1 manifest H="held stop: x until 2026-10-04T05:00:00Z"
  printf -- '- 2026-10-03 hand edit\n' >> "$P/.studio/ledger/H.md"
  verb resume H; assert_eq 1 "$V_STATUS" "a dirty start ledger refuses resume"
  assert_contains "$V_ERR" "\.studio/ledger/H\.md" "it names the file"
  assert_missing "$FR_DIR/control/H.resume" "no control file"
  fake_run_end
  fixture rd2; ledger_add "Directive 1: x"; fake_run overnight-rd2-1 single
  mkdir -p "$FR_DIR/control"; printf 'held stop: x until 2026-10-04T05:00:00Z\n' > "$FR_DIR/control/-.held"
  printf -- '- 2026-10-03 hand edit\n' >> "$P/.studio/ledger/spec.md"
  verb resume -; assert_eq 1 "$V_STATUS" "single-plan: a dirty .studio/ledger refuses resume"
  assert_contains "$V_ERR" "\.studio/ledger/spec\.md" "it names the file"
  fake_run_end
}
test_resume_from_feature_worktree() {
  fixture rw; fake_run overnight-rw-1 manifest H="held stop: x until 2026-10-04T05:00:00Z"
  git -C "$P" worktree add -q -b feat-h "$TMP/wt-rw" >/dev/null 2>&1
  printf -- '- 2026-10-03 feature-side edit\n' >> "$TMP/wt-rw/.studio/ledger/H.md"
  verb_in "$TMP/wt-rw" said H; assert_eq 0 "$V_STATUS" "a verb inside a feature worktree finds the run"
  verb_in "$TMP/wt-rw" resume H
  assert_eq 0 "$V_STATUS" "the dirty check reads the run's start checkout, not the cwd"
  assert_file "$FR_DIR/control/H.resume" "the control file is the run's"
  rm -f "$FR_DIR/control/H.resume"
  printf -- '- 2026-10-03 start-side edit\n' >> "$P/.studio/ledger/H.md"
  verb_in "$TMP/wt-rw" resume H; assert_eq 1 "$V_STATUS" "a dirty start ledger refuses, from the worktree too"
  fake_run_end
}
```

Add every name to `run_tests`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_test.sh`
Expected: FAIL in the new tests. `hold` and `resume` are usage (exit 2),
and `stop <story>` is usage through T3's `stop` check.

- [ ] **Step 3: Implement**

In `chan_main`, the usage case gets `hold|resume) [ "$A_N" -eq 1 ] || chan_usage ;;`
and `stop) [ "$A_N" -le 1 ] || chan_usage ;;`. The act case gets
`hold) chan_hold ;; resume) chan_resume ;; stop) chan_stop ;;`. In the
`studio-overnight` dispatch, `say|said|unsay)` becomes
`say|said|unsay|hold|resume)`.

```sh
# chan_ctl_write KIND — control/<story>.KIND, by temp file then mv, and a
# control event. Writing it again is the same success (R22).
chan_ctl_write() {
  mkdir -p "$CH_CTL" 2>/dev/null
  _cw_t="$CH_CTL/.$CH_STORY.$1.$$"
  if date -u +%Y-%m-%dT%H:%M:%SZ > "$_cw_t" && mv -f "$_cw_t" "$CH_CTL/$CH_STORY.$1"; then
    chan_event control "story=$CH_STORY" "action=$1"; return 0
  fi
  rm -f "$_cw_t"; chan_fail 1 "cannot write $CH_CTL/$CH_STORY.$1"
}
# chan_holds_on — AC8: hold and resume exit 1 when the run's hold_minutes is 0.
chan_holds_on() { [ "${CH_HOLD_MIN:-0}" -gt 0 ] 2>/dev/null || chan_fail 1 "holds are off: hold_minutes 0"; }
# chan_hold — AC7's hold column.
chan_hold() {
  chan_holds_on
  case "$CH_REC" in
    held*) chan_fail 1 "story $CH_STORY is already held" ;;
    landing*|repair*) chan_fail 1 "story $CH_STORY is landing: landing holds the land lock" ;;
  esac
  chan_ctl_write hold
  case "$CH_REC" in
    queued*|waiting*) echo "hold requested: $CH_STORY holds when it would start" ;;
    *) echo "hold requested: $CH_STORY holds at its next unit boundary" ;;
  esac
}
# chan_resume — AC7's resume column, AC21's dirty check (R22: the run's
# start checkout, never the cwd).
chan_resume() {
  chan_holds_on
  case "$CH_REC" in held*) ;; *) chan_fail 1 "story $CH_STORY is not held ($CH_REC)" ;; esac
  if [ "$CH_MODE" = single ]; then _cr_p=.studio/ledger; else _cr_p=".studio/ledger/$CH_STORY.md"; fi
  _cr_d="$(git -C "$CH_START" status --porcelain -- "$_cr_p" 2>/dev/null | head -n 1)"
  [ -z "$_cr_d" ] || chan_fail 1 "resume refused: ${_cr_d#???} has uncommitted changes in $CH_START (a restart would refuse it too)"
  chan_ctl_write resume
  echo "resume requested: $CH_STORY resumes within one poll"
}
# chan_stop — AC7's stop column; AC23.
chan_stop() {
  case "$CH_REC" in landing*|repair*) chan_fail 1 "story $CH_STORY is landing: landing holds the land lock" ;; esac
  chan_ctl_write stop
  case "$CH_REC" in
    queued*|waiting*) echo "stop requested: $CH_STORY stops when its lane reaches it" ;;
    held*) echo "stop requested: $CH_STORY stops within one poll" ;;
    *) echo "stop requested: $CH_STORY stops after its running unit" ;;
  esac
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/overnight_test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/bin/overnight-channel.sh studios/game-dev/bin/studio-overnight tests/overnight_test.sh
git commit -m "feat(overnight): hold, resume and stop <story> (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 5: The operator-inbox hook: claim, deliver, re-show on compact

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L171-206, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L380-403, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L439-444
Review: task

**Risk:** this hook runs inside every unit's session and writes into the
run dir from a process the runner does not own. One claim per message under
two concurrent hooks is the property AC10 depends on.

**Files:**
- Modify: `studios/game-dev/hooks/operator-inbox.sh`: replace everything
  after the gate line (T1) with the code below.
- Modify: `tests/hook_test.sh`:
  - helpers after `INBOX=`;
  - new tests;
  - the `run_tests` list.

**Interfaces:**
- Consumes:
  - T1's gate and `studio-event`;
  - T2's `STUDIO_RUN_DIR` and `STUDIO_UNIT_TAG` in each unit's environment;
  - T3's message file format.
- Produces:
  - `inbox/<story>/delivered/<unit tag>/<id>.msg` (what T6's
    `requeue_check` reads);
  - `message_delivered` events;
  - the delivery block of spec L382-398, on stdout.
- Its own copies of `msg_get`, `msg_body` and `sq`. The hook cannot source
  `overnight-channel.sh`, which refuses to load outside `studio-overnight`.
  Keep the two copies identical: the final review checks this.

- [ ] **Step 1: Write the failing tests**

In `tests/hook_test.sh`, after `INBOX=`:

```sh
# ---- #27: the operator-inbox hook ----
SS_START='{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}'
SS_COMPACT='{"session_id":"s","hook_event_name":"SessionStart","source":"compact"}'
SS_CLEAR='{"session_id":"s","hook_event_name":"SessionStart","source":"clear"}'
PTU='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":""}}'
PTU_SUB='{"session_id":"s","agent_id":"a1","agent_type":"general-purpose","hook_event_name":"PostToolUse","tool_name":"Bash"}'
# ib_fresh single|manifest — a fresh run dir IR. manifest adds rows.tsv with
# story S1. IS is the story's inbox (inbox/- or inbox/S1).
ib_fresh() {
  IR="$TMP/overnight-ib-$1"; rm -rf "$IR"; mkdir -p "$IR"
  if [ "$1" = manifest ]; then printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$IR/rows.tsv"; IS="$IR/inbox/S1"
  else IS="$IR/inbox/-"; fi
  mkdir -p "$IS"
}
# put_msg DIR ID SCOPE TEXT [TARGET] — a message file, as `say` writes it.
put_msg() {
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: -\nqueued: 2026-10-03T21:04:00Z\nrequeues: 0\n--\n%s\n' \
    "$2" "$3" "${5:--}" "$4" > "$1/$2.msg"
}
# inbox_run STORY|none JSON [OUT] — the hook as a unit's session runs it:
# tag ${TG:-tagA}, run dir IR, STUDIO_STORY unless none. IB_ST; output in OUT
# (default $TMP/ib.out).
inbox_run() {
  IB_ST=0
  ( unset STUDIO_STORY
    [ "$1" = none ] || { STUDIO_STORY="$1"; export STUDIO_STORY; }
    STUDIO_UNIT_TAG="${TG:-tagA}"; STUDIO_RUN_DIR="$IR"; export STUDIO_UNIT_TAG STUDIO_RUN_DIR
    printf '%s' "$2" | sh "$INBOX" ) > "${3:-$TMP/ib.out}" 2> "$TMP/ib.err" || IB_ST=$?
}
# delivered N — the count of message_delivered events in IR.
delivered() { grep -c '"event":"message_delivered"' "$IR/events.jsonl" 2>/dev/null || echo 0; }
```

Tests:

```sh
test_inbox_hook_skips_storyless_manifest_unit() {
  ib_fresh manifest; put_msg "$IS" 1 story "use the bus"
  inbox_run none "$PTU"
  assert_eq 0 "$IB_ST" "exit 0"
  assert_eq "" "$(cat "$TMP/ib.out")" "a manifest unit with no STUDIO_STORY (the final step) gets nothing"
  assert_file "$IS/1.msg" "the message stays pending"
  inbox_run none "$SS_START"; assert_eq "" "$(cat "$TMP/ib.out")" "nor at startup"
}
test_inbox_hook_skips_subagent() {
  ib_fresh single; put_msg "$IS" 1 story "use the bus"
  inbox_run none "$PTU_SUB"
  assert_eq "" "$(cat "$TMP/ib.out")" "a subagent's tool call delivers nothing"
  assert_file "$IS/1.msg" "and claims nothing"
  inbox_run none "$SS_CLEAR"
  assert_eq "" "$(cat "$TMP/ib.out")" "SessionStart clear delivers nothing"
}
test_inbox_session_start_plain() {
  ib_fresh single; put_msg "$IS" 1 story "Use the EventBus autoload."
  inbox_run S9 "$SS_START"
  assert_eq 0 "$IB_ST" "exit 0"
  assert_eq "OPERATOR MESSAGES — from the user, for story - (overnight run)." "$(sed -n 1p "$TMP/ib.out")" "the header (a single-plan run's story is -, whatever STUDIO_STORY says)"
  assert_contains "$TMP/ib.out" "^\[1, story\] Use the EventBus autoload\.$" "the message line"
  assert_contains "$TMP/ib.out" "^  → Follow this for the rest of the story\. Record it in the feature checkout's$" "the story instruction"
  assert_contains "$TMP/ib.out" "after §0 step (c), not merely after" "names the recording point"
  assert_contains "$TMP/ib.out" "^    studio-state ledger 'Directive 1: Use the EventBus autoload\.'$" "the command, single-quoted"
  assert_contains "$TMP/ib.out" "^If a message conflicts with the approved plan or spec, follow it for how you$" "the conflict rule"
  assert_contains "$TMP/ib.out" "^work; for what you build, record a \`Stop:\` with the conflict instead\.$" "its second line"
  assert_not_contains "$TMP/ib.out" "^{" "plain text, not JSON"
  assert_file "$IS/delivered/tagA/1.msg" "claimed into delivered/<tag>/"
  assert_contains "$IR/events.jsonl" '"event":"message_delivered","story":"-","id":1,"scope":"story","unit":"tagA","via":"session_start"}$' "a message_delivered event"
  assert_not_contains "$IR/events.jsonl" "EventBus" "no message text in the log"
}
test_inbox_post_tool_use_json() {
  ib_fresh manifest; put_msg "$IS" 2 unit "Skip the polish step."
  inbox_run S1 "$PTU"
  assert_contains "$TMP/ib.out" '^{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"OPERATOR MESSAGES — from the user, for story S1 (overnight run)\.\\n\[2, unit\] Skip the polish step\.\\n  → Follow this in this unit only\. Do not record it\.\\n' "PostToolUse: additionalContext JSON, one line"
  assert_eq 1 "$(wc -l < "$TMP/ib.out" | tr -d ' ')" "one line of output"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "[2, unit] Skip the polish step." "$(jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" | sed -n 2p)" "valid JSON; the context's second line"
  fi
  assert_contains "$IR/events.jsonl" '"scope":"unit","unit":"tagA","via":"tool_call"}$' "via tool_call"
  printf '{\n  "session_id": "s",\n  "hook_event_name": "PostToolUse"\n}\n' > "$TMP/ptu-ml.json"
  put_msg "$IS" 3 story "three"
  inbox_run S1 "$(cat "$TMP/ptu-ml.json")"
  assert_contains "$TMP/ib.out" '\[3, story\] three' "pretty-printed hook input is read too"
}
test_inbox_claim_moves_to_delivered() {
  ib_fresh single
  put_msg "$IS" 10 story ten; put_msg "$IS" 2 story two; put_msg "$IS" 1 retire "retire directive 7" 7
  : > "$IS/.say.123"
  inbox_run none "$PTU"
  if command -v jq >/dev/null 2>&1; then jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" > "$TMP/ib.ctx"; else cp "$TMP/ib.out" "$TMP/ib.ctx"; fi
  l1="$(grep -n '^\[retire 7\]' "$TMP/ib.ctx" | cut -d: -f1)"; l2="$(grep -n '^\[2, story\]' "$TMP/ib.ctx" | cut -d: -f1)"; l10="$(grep -n '^\[10, story\]' "$TMP/ib.ctx" | cut -d: -f1)"
  assert_eq 1 "$([ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l10" ] && [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l10" ] && echo 1 || echo 0)" "oldest (lowest id) first: 1, 2, 10"
  assert_contains "$TMP/ib.ctx" "^  → Stop following directive 7\. Record, the same way:$" "the retire instruction"
  assert_contains "$TMP/ib.ctx" "^    studio-state ledger 'Directive 7 retired'$" "the retire command"
  for i in 1 2 10; do assert_file "$IS/delivered/tagA/$i.msg" "message $i claimed"; assert_missing "$IS/$i.msg" "message $i no longer pending"; done
  assert_file "$IS/.say.123" "a verb's temp file is never claimed"
  inbox_run none "$PTU"
  assert_eq "" "$(cat "$TMP/ib.out")" "nothing pending: the next tool call prints nothing"
  put_msg "$IS" 11 story eleven
  inbox_run none "$PTU"
  assert_contains "$TMP/ib.out" '\[11, story\] eleven' "a new message arrives on the next tool call"
  assert_not_contains "$TMP/ib.out" '\[2, story\]' "and only it"
  assert_eq 4 "$(delivered)" "one event per claim"
}
test_inbox_one_claim_under_two_hooks() {
  ib_fresh single
  i=1; while [ "$i" -le 20 ]; do put_msg "$IS" "$i" story "m$i"; i=$((i + 1)); done
  inbox_run none "$PTU" "$TMP/ib.a" & _a=$!
  inbox_run none "$PTU" "$TMP/ib.b" & _b=$!
  wait "$_a"; wait "$_b"
  cat "$TMP/ib.a" "$TMP/ib.b" | grep -o '\[[0-9]*, story\]' | sed 's/^\[\([0-9]*\),.*/\1/' | sort -n > "$TMP/ib.ids"
  assert_eq 20 "$(wc -l < "$TMP/ib.ids" | tr -d ' ')" "20 deliveries between the two hooks"
  assert_eq 20 "$(sort -u "$TMP/ib.ids" | wc -l | tr -d ' ')" "each message delivered exactly once"
  assert_eq 20 "$(delivered)" "20 message_delivered events"
  assert_eq 20 "$(ls "$IS/delivered/tagA" | wc -l | tr -d ' ')" "every message claimed"
  assert_eq "" "$(ls "$IS" | grep '\.msg$')" "none left pending"
}
test_inbox_compact_reshows() {
  ib_fresh single; put_msg "$IS" 1 story one; put_msg "$IS" 2 unit two
  inbox_run none "$SS_START"
  put_msg "$IS" 3 story three
  inbox_run none "$SS_COMPACT"
  assert_eq "OPERATOR MESSAGES — reminder: already delivered in this unit, from the user, for story - (overnight run)." \
    "$(sed -n 1p "$TMP/ib.out")" "the reminder header"
  assert_contains "$TMP/ib.out" '^\[1, story\] one$' "the story message again"
  assert_contains "$TMP/ib.out" '^\[2, unit\] two$' "the unit message again"
  assert_not_contains "$TMP/ib.out" '\[3, story\]' "nothing new is claimed on compact"
  assert_file "$IS/3.msg" "message 3 is still pending"
  assert_eq 2 "$(delivered)" "a re-show writes no event"
  TG=tagB; inbox_run none "$SS_COMPACT"; unset TG
  assert_eq "" "$(cat "$TMP/ib.out")" "another unit's compact re-shows nothing of this unit's"
}
test_inbox_escapes_quotes_dollar_backticks_newlines() {
  ib_fresh single
  t="it's \"q\" \$HOME \`x\` a"
  put_msg "$IS" 1 story "$t
b"
  inbox_run none "$SS_START"
  cmd="$(sed -n 's/^    studio-state ledger //p' "$TMP/ib.out" | head -n 1)"
  eval "set -- $cmd"
  assert_eq "Directive 1: $t b" "$1" "the suggested command round-trips the text exactly, its newline folded to a space"
  assert_contains "$TMP/ib.out" "^\[1, story\] it's \"q\" \\\$HOME \`x\` a b$" "the message line, newline folded"
  ib_fresh single; put_msg "$IS" 1 story "$t
b"
  inbox_run none "$PTU"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" > "$TMP/ib.ctx"
    assert_eq 0 "$?" "the JSON parses"
    cmd="$(sed -n 's/^    studio-state ledger //p' "$TMP/ib.ctx" | head -n 1)"
    eval "set -- $cmd"
    assert_eq "Directive 1: $t b" "$1" "the same through additionalContext"
  fi
}
test_inbox_hook_never_fails() {
  ( STUDIO_UNIT_TAG=t; STUDIO_RUN_DIR="$TMP/no-such-run"; export STUDIO_UNIT_TAG STUDIO_RUN_DIR
    printf '%s' "$PTU" | sh "$INBOX" ) > "$TMP/ib.out" 2>&1; st=$?
  assert_eq 0 "$st" "a missing run dir: exit 0"
  assert_eq "" "$(cat "$TMP/ib.out")" "and nothing printed"
  ib_fresh single; put_msg "$IS" 1 story x
  inbox_run none 'not json at all'
  assert_eq 0 "$IB_ST" "garbage input: exit 0"; assert_eq "" "$(cat "$TMP/ib.out")" "nothing printed"
  printf 'garbage\n' > "$IS/2.msg"
  inbox_run none "$PTU"
  assert_eq 0 "$IB_ST" "a message with no header: exit 0"
  assert_file "$IS/2.msg" "a malformed message is left pending"
  assert_contains "$IR/hook.log" "2.msg" "and named in hook.log"
  if [ "$(id -u)" != 0 ]; then
    ib_fresh single; put_msg "$IS" 1 story x; chmod 555 "$IS"
    inbox_run none "$PTU"
    assert_eq 0 "$IB_ST" "an unwritable inbox: exit 0"
    assert_eq "" "$(cat "$TMP/ib.out")" "nothing claimed, nothing printed"
    chmod 755 "$IS"
  fi
}
```

Add every name to `run_tests`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/hook_test.sh`
Expected: the T1 gate passes. Every new test that expects a delivery fails
on empty output, because T1's hook only discards its input. The skip tests
pass already. That is fine: they pin behaviour T5 must keep.

- [ ] **Step 3: Write the hook**

The whole file after T5:

```sh
#!/bin/sh
# operator-inbox.sh — delivers a live overnight run's operator messages to a
# unit's main session (#27; spec AC9-12). Registered for SessionStart
# (startup|compact) and PostToolUse (*). Outside an overnight unit (no
# STUDIO_UNIT_TAG or no STUDIO_RUN_DIR) it exits at once, reading nothing:
# it runs on every tool call of every claude-gd session. Never fails a tool
# call: exit 0 on every path, errors to <run dir>/hook.log (AC29).
#
# startup, PostToolUse (main session only: no agent_id): claim each pending
# message of the unit's story, lowest id first, by mv into
# inbox/<story>/delivered/<unit tag>/ (a message another hook claimed first
# is skipped), and print one delivery block — plain text at SessionStart,
# hookSpecificOutput.additionalContext JSON at PostToolUse.
# compact: re-show what this unit tag already claimed, claiming nothing.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] || exit 0
RD="$STUDIO_RUN_DIR"; TAG="$STUDIO_UNIT_TAG"
[ -d "$RD" ] || exit 0
# A manifest run's unit with no story (the final step) gets nothing (AC9).
if [ -f "$RD/rows.tsv" ]; then S="${STUDIO_STORY:-}"; [ -n "$S" ] || exit 0; else S=-; fi
exec 2>> "$RD/hook.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
EV="$HERE/../bin/studio-event"
IN="$(cat)"

# field KEY — a top-level string field of the hook input (R19: no jq).
field() { printf '%s' "$IN" | tr -d '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }
# The same three helpers as overnight-channel.sh (kept identical).
msg_get() { sed -n "1,/^--\$/s/^$1: //p" "$2" 2>/dev/null | head -n 1; }
msg_body() { sed '1,/^--$/d' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; }
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# list DIR — DIR's message file names, lowest id first.
list() {
  for _f in "$1"/[0-9]*.msg; do [ -f "$_f" ] && printf '%s\n' "${_f##*/}"; done \
    | grep -E '^[0-9]+\.msg$' | sort -n
}

EVN="$(field hook_event_name)"
case "$EVN" in
  SessionStart)
    case "$(field source)" in
      startup) MODE=claim; VIA=session_start ;;
      compact) MODE=reshow ;;
      *) exit 0 ;;
    esac ;;
  PostToolUse)
    printf '%s' "$IN" | grep -q '"agent_id"' && exit 0
    MODE=claim; VIA=tool_call ;;
  *) exit 0 ;;
esac
IB="$RD/inbox/$S"; DL="$IB/delivered/$TAG"
[ -d "$IB" ] || exit 0

SHOW=""
if [ "$MODE" = claim ]; then
  HEAD="OPERATOR MESSAGES — from the user, for story $S (overnight run)."
  for m in $(list "$IB"); do
    case "$(msg_get scope "$IB/$m")" in
      story|unit|retire) ;;
      *) echo "operator-inbox: $IB/$m has no scope header; left pending" >&2; continue ;;
    esac
    mkdir -p "$DL" || break
    mv "$IB/$m" "$DL/$m" 2>/dev/null || continue   # another hook claimed it first
    SHOW="$SHOW $m"
    sh "$EV" "$RD" message_delivered "story=$S" "id:=${m%.msg}" "scope=$(msg_get scope "$DL/$m")" "unit=$TAG" "via=$VIA" || true
  done
else
  HEAD="OPERATOR MESSAGES — reminder: already delivered in this unit, from the user, for story $S (overnight run)."
  SHOW="$(list "$DL")"
fi
[ -n "$(printf '%s' "$SHOW" | tr -d ' \n')" ] || exit 0

block() {
  printf '%s\n' "$HEAD"
  for m in $SHOW; do
    f="$DL/$m"; id="${m%.msg}"
    case "$(msg_get scope "$f")" in
      story)
        printf '[%s, story] %s\n' "$id" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this for the rest of the story. Record it in the feature checkout's" \
          "    ledger at your recording point — after §0 step (c), not merely after" \
          "    EnterWorktree; in a --land or --gate-repair unit, after entering the" \
          "    feature checkout — single-quoted, and commit it with your next ledger" \
          "    commit (push only what you would push anyway):"
        printf '    studio-state ledger %s\n' "$(sq "Directive $id: $(msg_body "$f")")" ;;
      unit)
        printf '[%s, unit] %s\n' "$id" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this in this unit only. Do not record it." ;;
      retire)
        tg="$(msg_get target "$f")"
        printf '[retire %s]\n' "$tg"
        printf '%s\n' "  → Stop following directive $tg. Record, the same way:"
        printf '    studio-state ledger %s\n' "$(sq "Directive $tg retired")" ;;
    esac
  done
  printf '%s\n' "If a message conflicts with the approved plan or spec, follow it for how you" \
    'work; for what you build, record a `Stop:` with the conflict instead.'
}

OUT="$(block)"
if [ "$EVN" = SessionStart ]; then
  printf '%s\n' "$OUT"
else
  # session-start.sh's escape pipeline (trial t5): \r and control bytes
  # dropped, \ " and tab escaped, lines joined with \n.
  TAB="$(printf '\t')"
  ESC="$(printf '%s\n' "$OUT" | tr -d '\r' | tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
    | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$ESC"
fi
exit 0
```

Write the second `tr -d` exactly as above. Its range skips `\011` (tab),
`\012` (newline) and `\015`, so a tab survives to the `sed` and is escaped
as `\t`. This is session-start.sh's pipeline, verified in trial t5.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/hook_test.sh && sh tests/studio_test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/hooks/operator-inbox.sh tests/hook_test.sh
git commit -m "feat(overnight): the operator-inbox hook delivers messages (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 6: Single-plan holds, the requeue check, and the held line

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L77-81, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L207-218, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L231-284, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L405-420, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L448-451
Review: task

**Risk:** this changes the stop rule's outcome, the core of the runner. The
hold helpers defined here are shared with T7, and a wrong `holdable` either
holds a landing or ends a story that should wait. The requeue check writes
into the inbox under the lock.

**Files:**
- Modify: `studios/game-dev/bin/studio-overnight`:
  - `snapshot` (L376-385): the `.start` companion file;
  - after `new_stop` (L391): `take_new_stop`;
  - `run_unit`, after its last line (`UNIT_COST=…`, L661): `requeue_check`;
  - after T2's `iso_utc`: the hold helpers;
  - `story_units` (L753-779);
  - `write_report` (L692-693): messages left;
  - `cmd_start` (L892-893): the hold loop;
  - `project_status` (L997-998): the held line.
- Modify: `tests/overnight_test.sh`:
  - the stub's actions;
  - the `STUB_RUNNER`/`STUB_PLUGIN` export (L74);
  - helpers;
  - `make_minbin`, extracted from `test_overnight_no_inhibitor`;
  - new tests and `run_tests`.

**Interfaces:**
- Consumes:
  - T2: `HOLD_ON`, `HOLD_SECS`, `run_event`, `state_event`, `iso_utc`;
  - T3: `msg_get`, `msg_body`, `inbox_lock`, `inbox_unlock`;
  - T4's control files;
  - T5's `delivered/<tag>/`.
- Produces (T7 relies on each name):
  - `take_new_stop BEFORE AFTER` → `NEW_STOP`, `STOP_ENDING`, `STOP_SRC`
    (`start|feature`);
  - `requeue_check` → `REQ_LIMIT` (an id or empty);
  - `ctl_take ID KIND`;
  - `ctl_clear ID`;
  - `op_boundary ID` (returns 1 with ENDING set);
  - `isolated`;
  - `holdable` (reads ENDING);
  - `hold_record ID RECORD`;
  - `hold_wait ID` (0 resumed, 1 with ENDING set);
  - `halt_reason`;
  - `hm SECS`;
  - `held_line RECORD ID`;
  - `hhmm_local ISO`;
  - `msgs_left ID`.

- [ ] **Step 1: Write the stub additions, helpers and failing tests**

Stub (`tests/overnight_test.sh`): add these actions before the stub's `esac`:

```sh
    inbox)        printf '{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}' \
                    | sh "$STUB_PLUGIN/hooks/operator-inbox.sh" > "$CALLS/$n.inbox" ;;
    "say "*)      sh "$STUB_RUNNER" say - -- "${act#say }" > /dev/null 2>&1 ;;
    holdop)       sh "$STUB_RUNNER" hold - > /dev/null 2>&1 ;;
    stopop)       sh "$STUB_RUNNER" stop - > /dev/null 2>&1 ;;
```

Extend the export line (L74) to
`export PATH="$FAKE:$PATH" STUB_STATE_BIN="$STATE_BIN" STUB_RUNNER="$RUNNER" STUB_PLUGIN="$REPO_ROOT/studios/game-dev"`.

Extract `make_minbin` from `test_overnight_no_inhibitor`. The test then
calls it and keeps every assertion:

```sh
# make_minbin — $TMP/minbin: only what the runner needs, plus the stubs.
make_minbin() {
  mkdir -p "$TMP/minbin"
  for u in sh git sed awk grep sort comm date ps pkill kill sleep cat mkdir rm touch \
           head tail tr dirname basename readlink wc uname mktemp cp mv chmod env printf; do
    p="$(command -v "$u" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$TMP/minbin/$u" ;; esac
  done
  for f in claude claude-gd gh; do ln -sf "$FAKE/$f" "$TMP/minbin/$f"; done
}
```

Helpers, after T3's:

```sh
# ---- #27: single-plan holds ----
# holds_on SECS — holds on for the next run: hold_minutes 5, a deadline of
# SECS seconds, a 1 s poll. holds_off — the suite's default (holds off).
holds_on() {
  STUDIO_OVERNIGHT_HOLD_MINUTES=5; STUDIO_OVERNIGHT_HOLD_SECONDS="$1"; STUDIO_OVERNIGHT_POLL_SECONDS=1
  export STUDIO_OVERNIGHT_HOLD_MINUTES STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}
holds_off() { STUDIO_OVERNIGHT_HOLD_MINUTES=0; unset STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS; }
# wait_held SECS — up to SECS s for the newest run's control/-.held; R is
# the run dir.
wait_held() {
  _wh_i=0
  while [ "$_wh_i" -lt $(( $1 * 5 )) ]; do
    R="$(last_run_dir)"; [ -n "$R" ] && [ -f "$R/control/-.held" ] && return 0
    sleep 0.2; _wh_i=$((_wh_i + 1))
  done
  R="$(last_run_dir)"; return 1
}
# bg_alive — the start_bg runner runs and is not a zombie.
bg_alive() {
  kill -0 "$RPID" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$RPID" 2>/dev/null)" in Z*|'') return 1 ;; esac
}
# bg_end SECS MSG — passes MSG when the start_bg run ends within SECS (else
# KILLs it and fails); then bg_status.
bg_end() {
  _be_i=0; while bg_alive && [ "$_be_i" -lt "$1" ]; do sleep 1; _be_i=$((_be_i + 1)); done
  TESTS_RUN=$((TESTS_RUN + 1))
  if bg_alive; then kill -KILL "$RPID" 2>/dev/null; _fail "$2 (still running after $1 s)"; else _pass "$2"; fi
  bg_status
}
# unit_col N — column N of the newest run's units.tsv, space-joined.
unit_col() { awk -F'\t' -v c="$1" '{ printf "%s%s", (NR > 1 ? " " : ""), $c }' "$(last_run_dir)/units.tsv"; }
# ISO1 — one unit's actions that isolate the run (a feature worktree) and
# finish T1 of 2.
ISO1="stage execute; branch feat; task 1/2; wtledger T1 complete a..b"
```

Tests:

```sh
test_overnight_hold_on_feature_stop() {
  fixture hof; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art"
  start_bg
  wait_held 20; assert_file "$R/control/-.held" "a feature-ledger Stop: after isolation holds the story"
  assert_contains "$R/control/-.held" "^held stop: need art until 20[0-9-]*T[0-9:]*Z$" "the held record: why, then the deadline"
  sleep 2; assert_eq 2 "$(calls)" "no session runs while held"
  assert_contains "$R/events.jsonl" '"event":"story_state","story":"-","state":"held","why":"stop: need art","until":"20' "a held story_state event"
  verb status
  assert_contains "$V_OUT" "^held — stop: need art — until [0-9][0-9]:[0-9][0-9] — say / resume / stop -$" "status shows the held line"
  verb stop -; assert_eq "stop requested: - stops within one poll" "$(cat "$V_OUT")" "stop - on the held story"
  bg_end 20 "the run ends within a poll"
  assert_eq 1 "$BG_STATUS" "a stopped run exits 1"
  assert_contains "$R/report.md" "^Ending: stop: need art$" "stop on a held story ends it with its why (AC23)"
  assert_eq "" "$(ls -A "$R/control")" "no control file is left (R25)"
  assert_missing "$P/.studio/overnight.lock" "the lock is released"
  holds_off
}
test_overnight_start_ledger_stop_ends_at_once() {
  holds_on 60
  fixture sls; scenario "stage execute; branch feat; task 1/2; ledger Stop: from the start checkout"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: from the start checkout$" "a Stop: in the start ledger after isolation ends at once"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
  fixture sls2; scenario "stage execute; task 1/2; ledger Stop: before isolation"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: before isolation$" "a Stop: before isolation ends at once"
  fixture sls3; scenario "stage execute; branch feat; wtledger Stop: both; ledger Stop: both"; run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: both$" "the same Stop: in both ledgers ends at once (AC18's tie)"
  assert_not_contains "$(last_run_dir)/events.jsonl" '"state":"held"' "no held event"
  holds_off
}
test_overnight_resume_runs_next_unit() {
  fixture rnu; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art" "inbox; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/3; stage idle; task -"
  start_bg; wait_held 20
  verb say - "use the bus"; assert_eq 1 "$(cat "$V_OUT")" "say on the held story: id 1"
  verb say - --unit "skip polish"
  verb resume -; assert_eq "resume requested: - resumes within one poll" "$(cat "$V_OUT")" "resume -"
  bg_end 60 "the resumed run finishes"
  assert_eq 0 "$BG_STATUS" "it ends done"
  assert_eq "1 2 3 4 5" "$(unit_col 1)" "unit numbers run on after the hold"
  assert_contains "$CALLS/3.inbox" '^\[1, story\] use the bus$' "the next unit got the directive at startup"
  assert_contains "$CALLS/3.inbox" '^\[2, unit\] skip polish$' "and the unit message"
  assert_contains "$R/events.jsonl" '"event":"message_requeued","story":"-","id":1,"unit":"[^"]*-0-3-T2","requeues":1}$' "the unrecorded directive was requeued (AC13)"
  assert_contains "$R/inbox/-/1.msg" "^requeues: 1$" "back in pending with requeues 1"
  assert_missing "$R/inbox/-/2.msg" "a unit message is never requeued"
  assert_contains "$R/report.md" "^## Operator messages left$" "the report lists the messages left (AC14)"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): use the bus$" "id, scope, requeues, text"
  assert_contains "$R/events.jsonl" '"state":"running"}$' "a running event after the resume"
  holds_off
}
test_overnight_new_stop_holds_again() {
  fixture nsh; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art" "wtledger Stop: still need art"
  start_bg; wait_held 20
  verb resume -
  _i=0; while [ "$(calls)" -lt 3 ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  wait_held 20
  _j=0; until grep -q 'still need art' "$R/control/-.held" 2>/dev/null || [ "$_j" -ge 50 ]; do sleep 0.2; _j=$((_j + 1)); done
  assert_contains "$R/control/-.held" "^held stop: still need art until " "a new stop after a resume holds again (AC20)"
  verb stop -; bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stop: still need art$" "with the new why"
  holds_off
}
test_overnight_hold_deadline() {
  fixture hdl; holds_on 2
  scenario "$ISO1" "wtledger Stop: need art"
  t0="$(date +%s)"; run_start; t1="$(date +%s)"
  assert_eq 1 "$RS_STATUS" "the run ends 1"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: need art (held 0h0m, no reply)$" "the deadline appends the hold's length (AC24)"
  assert_eq 1 "$([ $((t1 - t0)) -ge 2 ] && echo 1 || echo 0)" "it waited out the deadline"
  assert_eq 2 "$(calls)" "no unit ran while held"
  holds_off
}
test_overnight_stop_beats_resume() {
  fixture sbr; holds_on 60; STUDIO_OVERNIGHT_POLL_SECONDS=3
  scenario "$ISO1" "wtledger Stop: need art" "wtledger final review done"
  start_bg; wait_held 20; sleep 1
  # Both files land between two polls: the runner is paused while they are written.
  kill -STOP "$RPID"; : > "$R/control/-.stop"; : > "$R/control/-.resume"; kill -CONT "$RPID"
  bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stop: need art$" ".stop beats .resume in one poll (AC22)"
  assert_eq 2 "$(calls)" "no unit ran"
  holds_off
}
test_overnight_resume_wins_at_deadline() {
  fixture rwd; holds_on 2; STUDIO_OVERNIGHT_POLL_SECONDS=4
  scenario "$ISO1" "wtledger Stop: need art" "wtledger final review done" \
           "wtledger shipped https://x/pull/7; stage idle; task -"
  start_bg; wait_held 20
  verb resume -
  bg_end 60 "the run ends"
  assert_eq 0 "$BG_STATUS" "a resume seen at the poll after the deadline still resumes (AC22)"
  assert_contains "$R/report.md" "^Ending: done$" "and the run finishes"
  holds_off
}
test_overnight_requeue_then_hold() {
  fixture rth; holds_on 60
  scenario "stage execute; branch feat; task 1/3; wtledger T1 complete a..b; say use the bus" \
           "inbox; task 2/3; wtledger T2 complete b..c" \
           "inbox; task 3/3; wtledger T3 complete c..d"
  start_bg; wait_held 20
  assert_contains "$R/control/-.held" "^held directive 1 not recorded until " "requeued retries + 1 times: the story holds (AC14)"
  assert_eq "progress progress progress" "$(unit_col 7)" "the unit's own outcome is kept in its row"
  verb stop -; bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: directive 1 not recorded$" "stop ends it with that why"
  assert_contains "$R/report.md" "^- 1 (story, requeues 2): use the bus$" "the message is listed"
  holds_off
}
test_overnight_recorded_directive_stays_delivered() {
  fixture rds
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say use the bus" \
           "inbox; wtledger Directive 1: use the bus; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/4; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "done"
  R="$(last_run_dir)"
  assert_eq 1 "$(ls "$R"/inbox/-/delivered/*/1.msg 2>/dev/null | wc -l | tr -d ' ')" "a recorded directive stays delivered"
  assert_not_contains "$R/events.jsonl" '"event":"message_requeued"' "and is not requeued"
  assert_not_contains "$R/report.md" "Operator messages left" "nothing left"
}
test_overnight_requeue_id_prefix() {
  fixture rip
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say one" \
           "inbox; wtledger Directive 10: not one; task 2/2; wtledger T2 complete b..c" \
           "wtledger final review done" "wtledger shipped https://x/pull/8; stage idle; task -"
  run_start; R="$(last_run_dir)"
  assert_contains "$R/events.jsonl" '"event":"message_requeued","story":"-","id":1,' "Directive 10: does not record message 1"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): one$" "message 1 is left"
}
test_overnight_requeue_done_no_hold() {
  fixture rdn '{"overnight": {"retries": 0}}'; holds_on 60
  scenario "stage execute; branch feat; task 1/1; wtledger T1 complete a..b; say use the bus" \
           "inbox; wtledger final review done; wtledger shipped https://x/pull/5; stage idle; task -"
  run_start; R="$(last_run_dir)"
  assert_eq 0 "$RS_STATUS" "a unit that ships is done, whatever it left unrecorded (AC14)"
  assert_contains "$R/report.md" "^Ending: done$" "done"
  assert_not_contains "$R/events.jsonl" '"state":"held"' "never held"
  assert_contains "$R/report.md" "^- 1 (story, requeues 1): use the bus$" "the message is listed"
  holds_off
}
test_overnight_prestop_and_limit_end_at_once() {
  holds_on 60
  fixture pli '{"overnight": {"retries": 0}}'
  scenario "stage execute; task 1/2; ledger T1 complete a..b; say x" \
           "inbox; task 2/2; ledger T2 complete b..c" "ledger final review done" \
           "ledger shipped https://x/pull/6; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "before isolation the limit never holds; the story goes on (R6)"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"message_requeued"' "the message was still requeued"
  fixture pl2 '{"overnight": {"retries": 0}}'
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say x" \
           "inbox; ledger Stop: start side"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: start side$" "a start-ledger Stop: in the same unit as the limit ends at once (AC18)"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
  holds_off
}
test_overnight_stop_story_running() {
  fixture ssr
  scenario "stage execute; task 1/3; stopop" "task 2/3"
  run_start
  assert_eq 1 "$(calls)" "stop - on the running story ends it after its unit"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stopped by operator$" "stopped by operator (AC23)"
  assert_eq "" "$(ls -A "$(last_run_dir)/control" 2>/dev/null)" "no control file left"
}
test_overnight_hold_story_running() {
  fixture hsr; holds_on 60
  scenario "$ISO1; holdop" "wtledger final review done" "wtledger shipped https://x/pull/9; stage idle; task -"
  start_bg; wait_held 20
  assert_contains "$R/control/-.held" "^held held by operator until " "hold - holds at the next unit boundary"
  assert_eq 1 "$(calls)" "before the next unit"
  verb resume -; bg_end 60 "the run goes on"
  assert_eq 0 "$BG_STATUS" "and finishes"
  assert_eq 3 "$(calls)" "the remaining units ran"
  holds_off
}
test_overnight_hold_last_unit_done_finishes() {
  fixture hld; holds_on 60
  scenario "stage execute; task 1/1; ledger T1 complete a..b" "ledger final review done" \
           "holdop; ledger shipped https://x/pull/6; stage idle; task -"
  run_start
  assert_eq 0 "$RS_STATUS" "a hold sent during the last unit: the run still finishes done"
  assert_not_contains "$(last_run_dir)/events.jsonl" '"state":"held"' "never held"
  assert_eq "" "$(ls -A "$(last_run_dir)/control" 2>/dev/null)" "the .hold is cleared"
  holds_off
}
test_overnight_run_stop_while_held() {
  fixture rsh; holds_on 60
  scenario "$ISO1" "wtledger Stop: need art"
  start_bg; wait_held 20
  verb stop; assert_contains "$V_OUT" "^stop requested: the run ends after its running unit" "bare stop, as today"
  bg_end 20 "the run ends"
  assert_contains "$R/report.md" "^Ending: stopped by user (was held: stop: need art)$" "the halt's reason, then the hold's (AC25)"
  holds_off
}
test_overnight_hold_minutes_zero_ends_at_once() {
  fixture hmz
  scenario "$ISO1; holdop" "wtledger Stop: need art"
  run_start
  assert_eq 2 "$(calls)" "hold_minutes 0: a hold is refused, nothing waits"
  assert_contains "$(last_run_dir)/report.md" "^Ending: stop: need art$" "a feature Stop: ends at once, as today (AC26)"
  assert_missing "$(last_run_dir)/control/-.held" "never held"
}
test_overnight_requeue_minimal_path() {
  fixture rmp; make_minbin
  scenario "stage execute; branch feat; task 1/2; wtledger T1 complete a..b; say use the bus" \
           "inbox; task 2/2; wtledger T2 complete b..c" "wtledger final review done" \
           "wtledger shipped https://x/pull/2; stage idle; task -"
  RS_STATUS=0
  ( cd "$P" && PATH="$TMP/minbin" sh "$RUNNER" start ) > "$TMP/rs.out" 2> "$TMP/rs.err" || RS_STATUS=$?
  assert_eq 0 "$RS_STATUS" "the channel works under the minimal PATH"
  assert_not_contains "$TMP/rs.err" "not found" "no missing command"
  assert_contains "$CALLS/2.inbox" '^\[1, story\] use the bus$' "say, the hook and the claim ran"
  assert_contains "$(last_run_dir)/events.jsonl" '"event":"message_requeued"' "and the requeue check"
  assert_contains "$(last_run_dir)/report.md" "^- 1 (story, requeues 1): use the bus$" "and the report"
}
```

Add every name to `run_tests`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_test.sh`
Expected: FAIL in the hold, requeue and report tests. The run ends at the
first `Stop:`, and there is no `control/-.held`, no `message_requeued` and
no `Operator messages left`. The three tests that check today's behaviour
pass already, and they must stay green:
`test_overnight_start_ledger_stop_ends_at_once`,
`test_overnight_hold_minutes_zero_ends_at_once`, and
`test_overnight_recorded_directive_stays_delivered`.

- [ ] **Step 3: `snapshot` and `take_new_stop`**

In `snapshot`, replace the last `if … fi | sort -u > "$1"` with:

```sh
  # $1.start: the start checkout's Stop: lines (the whole set before
  # isolation, when one ledger is both), so take_new_stop can tell a Stop
  # written before isolation, or in both ledgers, from a feature-only one.
  if [ "$FEATURE_DIR" = "$START_DIR" ]; then
    printf '%s\n' "$_l" | stop_lines | sort -u > "$1"; cp "$1" "$1.start"
  else
    ledger_of "$START_DIR" | stop_lines | sort -u > "$1.start"
    { printf '%s\n' "$_l" | stop_lines; cat "$1.start"; } | sort -u > "$1"
  fi
```

After `new_stop`:

```sh
# take_new_stop BEFORE AFTER — new_stop's line (NEW_STOP; empty for none),
# its ending (STOP_ENDING, `stop: <reason>`), and where it came from
# (STOP_SRC): `start` when any line new in AFTER is also in the start
# checkout's ledger (AFTER.start), else `feature` (AC17-18, R6).
take_new_stop() {
  NEW_STOP="$(new_stop "$1" "$2")"; STOP_ENDING=""; STOP_SRC=""
  [ -n "$NEW_STOP" ] || return 0
  STOP_ENDING="stop: ${NEW_STOP#*Stop: }"
  if comm -13 "$1" "$2" | awk -v st="$2.start" 'FILENAME == st { s[$0] = 1; next } ($0 in s) { f = 1 } END { exit !f }' "$2.start" -; then
    STOP_SRC=start
  else
    STOP_SRC=feature
  fi
}
```

- [ ] **Step 4: The requeue check and the hold helpers**

After T2's `iso_utc`:

```sh
# ---- Operator messages and holds (#27; spec AC13-14, AC17-27) ----
# requeue_check — after each unit: each story or retire message the unit
# claimed (inbox/<story>/delivered/<UNIT_TAG>/) is checked against the
# story's feature-checkout ledger (`Directive <id>:` or `Directive <target>
# retired` at a line's start, after its date). One with no match goes back to
# pending with requeues + 1 and a message_requeued event. REQ_LIMIT is the
# first id whose requeues reach RETRIES + 1, when holds are on and the story
# is isolated (R6, R9). Writes no studio state. A manifest run's storyless
# unit (the final step) has no inbox.
requeue_check() {
  REQ_LIMIT=""
  if [ -z "${CUR_ID:-}" ] && [ -f "$RUN_DIR/rows.tsv" ]; then return 0; fi
  _rq_s="${CUR_ID:--}"; _rq_ib="$RUN_DIR/inbox/$_rq_s"; _rq_dl="$_rq_ib/delivered/$UNIT_TAG"
  [ -d "$_rq_dl" ] || return 0
  _rq_fd="$(feature_dir)"; _rq_l="$(ledger_of "$_rq_fd")"
  inbox_lock "$_rq_ib" 5 || { say "inbox busy: the directive check after $UNIT_STEM was skipped"; return 0; }
  for _rq_f in "$_rq_dl"/[0-9]*.msg; do
    [ -f "$_rq_f" ] || continue
    _rq_id="$(msg_get id "$_rq_f")"
    case "$(msg_get scope "$_rq_f")" in
      story) _rq_p="Directive $_rq_id:" ;;
      retire) _rq_p="Directive $(msg_get target "$_rq_f") retired" ;;
      *) continue ;;
    esac
    if printf '%s\n' "$_rq_l" | awk -v p="$_rq_p" '{ sub(/^- [0-9-]+ /, "") } index($0, p) == 1 { f = 1 } END { exit !f }'; then
      continue
    fi
    _rq_n="$(msg_get requeues "$_rq_f")"; _rq_n=$(( ${_rq_n:-0} + 1 ))
    _rq_t="$_rq_ib/.rq.$$"
    if sed "1,/^--\$/s/^requeues: .*/requeues: $_rq_n/" "$_rq_f" > "$_rq_t" && mv -f "$_rq_t" "$_rq_ib/${_rq_f##*/}"; then
      rm -f "$_rq_f"
    else
      rm -f "$_rq_t"; continue
    fi
    run_event message_requeued "story=$_rq_s" "id:=$_rq_id" "unit=$UNIT_TAG" "requeues:=$_rq_n"
    if [ -z "$REQ_LIMIT" ] && [ "$_rq_n" -ge $((RETRIES + 1)) ] && [ "$HOLD_ON" = 1 ] && [ "$_rq_fd" != "$START_DIR" ]; then
      REQ_LIMIT="$_rq_id"
    fi
  done
  inbox_unlock "$_rq_ib"
}
# ctl_take ID KIND — control/ID.KIND exists: remove it, return 0.
ctl_take() { [ -f "$RUN_DIR/control/$1.$2" ] || return 1; rm -f "$RUN_DIR/control/$1.$2"; }
# ctl_clear ID — R25: a story that ends leaves no control file.
ctl_clear() {
  rm -f "$RUN_DIR/control/$1.hold" "$RUN_DIR/control/$1.resume" "$RUN_DIR/control/$1.stop" "$RUN_DIR/control/$1.held"
}
# op_boundary ID — R8, before a unit: the halt (`stopped by user`), then an
# operator stop (`stopped by operator`), then, with holds on, an operator
# hold (`held by operator`). Returns 1 with ENDING set when one acts.
op_boundary() {
  if stop_requested; then ENDING="stopped by user"; return 1; fi
  if ctl_take "$1" stop; then ENDING="stopped by operator"; return 1; fi
  if [ "$HOLD_ON" = 1 ] && ctl_take "$1" hold; then ENDING="held by operator"; return 1; fi
  return 0
}
# isolated — the last snapshot's feature checkout is not the start checkout.
isolated() { [ "${FEATURE_DIR:-$START_DIR}" != "$START_DIR" ]; }
# holdable — AC17-18, R6: ENDING holds instead of ending. Never under a halt,
# never with holds off; `held by operator` always; a `stop:` only when it is
# the feature-only Stop take_new_stop saw; the rest only after isolation.
holdable() {
  [ "$HOLD_ON" = 1 ] || return 1
  ! stop_requested || return 1
  case "$ENDING" in
    "held by operator") return 0 ;;
    "stop: "*) [ "$ENDING" = "${STOP_ENDING:-}" ] && [ "${STOP_SRC:-}" = feature ] && isolated; return $? ;;
    "no progress on "*|"timed out on "*|"directive "*" not recorded"|"gate red after "*|"gate repair made no progress"|"gate repair timed out"*)
      isolated; return $? ;;
  esac
  return 1
}
# hold_record ID RECORD — the story's record while it holds and resumes.
# Single-plan mode keeps a held line in control/ID.held (removed for any
# other record) and writes the story_state event; overnight-lanes.sh
# redefines it as story_write.
hold_record() {
  mkdir -p "$RUN_DIR/control" 2>/dev/null
  case "$2" in
    held*) printf '%s\n' "$2" > "$RUN_DIR/control/.held.$$" && mv -f "$RUN_DIR/control/.held.$$" "$RUN_DIR/control/$1.held" ;;
    *) rm -f "$RUN_DIR/control/$1.held" ;;
  esac
  state_event "$1" "$2"
}
# halt_reason — the ending a halt gives a held story (R28); lanes redefine
# it as lane_halt_reason.
halt_reason() { echo "stopped by user"; }
# hm SECS — `<h>h<m>m`.
hm() { printf '%dh%dm' $(( $1 / 3600 )) $(( $1 % 3600 / 60 )); }
# hold_wait ID — AC19-25: hold the story ENDING names until the operator
# acts, the run halts, or HOLD_SECS pass; a poll every
# STUDIO_OVERNIGHT_POLL_SECONDS (default 5), no session running. A poll checks
# the halt, then .stop, then .resume, then the deadline (AC22). Returns 0 on
# resume (record running, ENDING cleared; n is kept, so units run on);
# else 1 with ENDING set.
hold_wait() {
  _hw_why="$ENDING"
  rm -f "$RUN_DIR/control/$1.hold" "$RUN_DIR/control/$1.resume"
  _hw_dl=$(( $(date +%s) + HOLD_SECS ))
  hold_record "$1" "held $_hw_why until $(iso_utc "$_hw_dl")"
  say "${CUR_ID:+$CUR_ID }held: $_hw_why — say / resume / stop ${CUR_ID:--}"
  while :; do
    if stop_requested; then ENDING="$(halt_reason) (was held: $_hw_why)"; return 1; fi
    if ctl_take "$1" stop; then ENDING="$_hw_why"; return 1; fi
    if ctl_take "$1" resume; then hold_record "$1" running; ENDING=""; return 0; fi
    if [ "$(date +%s)" -ge "$_hw_dl" ]; then ENDING="$_hw_why (held $(hm "$HOLD_SECS"), no reply)"; return 1; fi
    sleep "${STUDIO_OVERNIGHT_POLL_SECONDS:-5}"
  done
}
# hhmm_local ISO — ISO-8601 UTC as local HH:MM: days-from-civil to an epoch,
# then GNU `date -d @E`, else BSD `date -r E`; the ISO itself when neither
# works (R20, trial t6).
hhmm_local() {
  _hh_e="$(printf '%s\n' "$1" | awk -F'[-T:Z]' 'NF >= 6 { y = $1; m = $2; d = $3; if (m <= 2) { y--; m += 12 }
    era = int(y / 400); yoe = y - era * 400; doy = int((153 * (m - 3) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    print (era * 146097 + doe - 719468) * 86400 + $4 * 3600 + $5 * 60 + $6 }')"
  if [ -n "$_hh_e" ]; then
    date -d "@$_hh_e" +%H:%M 2>/dev/null || date -r "$_hh_e" +%H:%M 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}
# held_line RECORD ID — AC27, R20.
held_line() {
  _hl_r="${1#held }"
  printf 'held — %s — until %s — say / resume / stop %s\n' "${_hl_r% until *}" "$(hhmm_local "${_hl_r##* until }")" "$2"
}
# msgs_left ID — R21: the story's pending messages, lowest id first, as
# `- <id> (<scope>, requeues <n>): <text>`.
msgs_left() {
  for _ml_f in "$RUN_DIR/inbox/$1"/[0-9]*.msg; do
    [ -f "$_ml_f" ] || continue
    printf '%s\t- %s (%s, requeues %s): %s\n' "$(msg_get id "$_ml_f")" "$(msg_get id "$_ml_f")" \
      "$(msg_get scope "$_ml_f")" "$(msg_get requeues "$_ml_f")" "$(msg_body "$_ml_f")"
  done | sort -n | awk '{ sub(/^[0-9]+\t/, ""); print }'
}
```

At the end of `run_unit`, after the `UNIT_COST` line: `requeue_check`.

- [ ] **Step 5: `story_units`, `cmd_start`, `write_report`, `project_status`**

In `story_units`:
- replace its first loop line, `if stop_requested; then ENDING="stopped by user"; return 0; fi`,
  with `op_boundary "${CUR_ID:--}" || return 0`;
- before the `while`, add `STOP_ENDING=""; STOP_SRC=""`;
- replace the `_new=…` and `if [ -n "$_new" ] …` lines, and add the limit
  check after `done`:

```sh
    take_new_stop "$UNIT_DIR/stops.before" "$UNIT_DIR/stops.after"
    if [ -n "$NEW_STOP" ]; then row "$n" "$_base$suffix" stop; ENDING="$STOP_ENDING"; return 0; fi
    if [ "$SIG_STAGE" = idle ] && [ "$SIG_SHIPPED" -gt 0 ]; then row "$n" "$_base$suffix" done; ENDING=done; return 0; fi
    if [ -n "$REQ_LIMIT" ]; then
      if [ "$SIG" != "$_before" ]; then _su_o=progress; else _su_o="$(unit_outcome)"; fi
      row "$n" "$_base$suffix" "$_su_o"; ENDING="directive $REQ_LIMIT not recorded"; return 0
    fi
```

The header comment's ENDING list gains `stopped by operator · held by
operator · directive <id> not recorded`.

`cmd_start`: replace `story_units` / `finish_run "$ENDING"` with:

```sh
  story_units
  # A holdable ending waits for the operator (AC17-25); a resume runs the
  # unit loop on (a new stop holds again).
  while holdable; do
    hold_wait - || break
    story_units
  done
  ctl_clear -
  finish_run "$ENDING"
```

`write_report`: after the Play list's `|| echo '(none)'` line:

```sh
    _wr_m="$(msgs_left -)"
    [ -z "$_wr_m" ] || printf '\n## Operator messages left\n\n%s\n' "$_wr_m"
```

`project_status`: replace the `_ps_now=…` line with:

```sh
    if [ -f "$RUN_DIR/control/-.held" ]; then held_line "$(cat "$RUN_DIR/control/-.held")" -
    else _ps_now="$(unit_now_line "$RUN_DIR")"; [ -z "$_ps_now" ] || printf 'now: %s\n' "$_ps_now"; fi
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `sh tests/overnight_test.sh && sh tests/overnight_lanes_test.sh && sh tests/run_all.sh`
Expected: PASS. The lanes suite is unchanged, but it is green only because
of T2's `HOLD_MINUTES=0` export. Its `story_units` now calls `op_boundary`,
and the halt arm keeps today's `stopped by user`.

- [ ] **Step 7: Commit**

```bash
git add studios/game-dev/bin/studio-overnight tests/overnight_test.sh
git commit -m "feat(overnight): single-plan holds, the requeue check and the held line (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 7: Lane holds, the resume gate repair, operator stops in `run_chain`, status and report

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L231-284, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L150-168, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L405-420
Review: task

**Risk:** this crosses systems. It touches the lane's story runner, the
chain walker, `wait_deps`, the gate-repair loop and `status`. A wrong arm
here can hold a story that should end, run a gate repair twice, or let a
dependent start before its dependency lands.

**Files:**
- Modify: `studios/game-dev/bin/overnight-lanes.sh`:
  - after `lane_halt_reason` (L610-620): `halt_reason`, `hold_record`,
    `last_stop_gate_red`;
  - `gate_repair` (L528-549): `take_new_stop`;
  - `wait_deps` (L660-677): `.stop`;
  - `run_chain` (L703-723): operator stops and `ctl_clear`;
  - `run_story` (L731-766): `story_gate_loop` and the hold loop;
  - `lanes_report`, in the per-story section (L1011-1021);
  - `lanes_status_lines` (L1128-1147).
- Modify: `tests/overnight_lanes_test.sh`:
  - stub actions;
  - the export after L395;
  - helpers;
  - new tests before `test_lanes_no_orphans`;
  - `run_tests`.

**Interfaces:**
- Consumes everything T6 produces. From T6: `take_new_stop`, `op_boundary`,
  `holdable`, `hold_wait`, `ctl_take`, `ctl_clear`, `held_line`, `msgs_left`.
  From T2: `story_write`, which writes the `story_state` event.
- Produces, overriding the single-plan versions:
  - `halt_reason` (= `lane_halt_reason`);
  - `hold_record ID RECORD` (= `story_write`);
  - `last_stop_gate_red`;
  - `story_gate_loop ID`;
  - `wait_deps` return 3 (an operator stop).

- [ ] **Step 1: Write the stub additions, helpers and failing tests**

Lanes stub: add these before its `*)` action:

```sh
    inbox)            printf '{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}' \
                        | sh "$STUB_PLUGIN/hooks/operator-inbox.sh" > "$CALLS/$n.inbox" ;;
    "say "*)          sh "$STUB_RUNNER" say "$id" -- "${act#say }" > /dev/null 2>&1 ;;
```

Document both in the stub's action list:
- `inbox`: the operator-inbox hook as a startup session runs it, with its
  output in `$CALLS/<n>.inbox`;
- `say <text>`: `studio-overnight say <id> -- <text>`.

After L395 add
`STUB_RUNNER="$RUNNER"; STUB_PLUGIN="$REPO_ROOT/studios/game-dev"; export STUB_RUNNER STUB_PLUGIN`.

Helpers, before the new tests:

```sh
# ---- #27: lane holds ----
# lholds_on SECS — holds on for the next run (deadline SECS s, 1 s poll);
# lholds_off — the suite's default.
lholds_on() {
  STUDIO_OVERNIGHT_HOLD_MINUTES=5; STUDIO_OVERNIGHT_HOLD_SECONDS="$1"; STUDIO_OVERNIGHT_POLL_SECONDS=1
  export STUDIO_OVERNIGHT_HOLD_MINUTES STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS
}
lholds_off() { STUDIO_OVERNIGHT_HOLD_MINUTES=0; unset STUDIO_OVERNIGHT_HOLD_SECONDS STUDIO_OVERNIGHT_POLL_SECONDS; }
# lanes_bg — `start $MFP` in the background: RPID.
lanes_bg() { ( cd "$P" && exec sh "$RUNNER" start "$MFP" ) > "$TMP/lbg.out" 2> "$TMP/lbg.err" < /dev/null & RPID=$!; }
# rec ID — story ID's record in the newest run.
rec() { cat "$(last_lanes_dir)/stories/$1" 2>/dev/null; }
# is_held ID — ID's record is a held one.
is_held() { case "$(rec "$1")" in "held "*) return 0 ;; esac; return 1; }
# lverb ARGS… — `studio-overnight ARGS` in $P: LV_STATUS, LV_OUT, LV_ERR.
lverb() {
  LV_STATUS=0
  ( cd "$P" && sh "$RUNNER" "$@" ) > "$TMP/lv.out" 2> "$TMP/lv.err" || LV_STATUS=$?
  LV_OUT="$TMP/lv.out"; LV_ERR="$TMP/lv.err"
}
```

Tests:

```sh
test_lanes_held_dependents_wait() {
  lanes_fixture hdw integration A:- C:- D:A,C
  lholds_on 120
  printf 'auto\nstop need art\ninbox; ruling Directive 1: use the bus\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: need art until 20[0-9-]*T[0-9:]*Z$" "a feature Stop: holds the story (AC17, AC19)"
  wait_for 'case "$(rec C)" in landed*) true ;; *) false ;; esac' 60
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "another lane runs on while A is held"
  assert_eq waiting "$(rec D)" "a story that depends on a held one keeps waiting"
  lverb status
  assert_contains "$LV_OUT" "^A  lane [0-9]*  held  " "status: A's state is held"
  assert_contains "$LV_OUT" "^    held — stop: need art — until [0-9][0-9]:[0-9][0-9] — say / resume / stop A$" "the held line in place of the unit line (AC27)"
  lverb say A -- use the bus; assert_eq 1 "$(cat "$LV_OUT")" "say A while held"
  lverb resume A; assert_eq "resume requested: A resumes within one poll" "$(cat "$LV_OUT")" "resume A"
  wait_pid_or_fail "$RPID" 120 "the run finishes after the resume"
  assert_eq 0 "$WP_STATUS" "every story lands"
  for id in A C D; do assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id landed"; done
  _n="$(story_calls A | sort -n | sed -n 3p)"
  assert_contains "$CALLS/$_n.inbox" '^\[1, story\] use the bus$' "A's next unit got the directive"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"event":"message_requeued"' "the recorded directive is not requeued"
  assert_eq "1 A-T1 progress,2 A-final-review stop,3 A-final-review progress,4 A-finish done," "$(story_rows A)" "unit numbers run on after the hold"
  assert_contains "$(last_lanes_dir)/events.jsonl" '"story":"A","state":"held","why":"stop: need art","until":"20' "a held event"
  lholds_off
}
test_lanes_resume_after_gate_red_runs_gate_repair() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 0}}'; export LANES_CONFIG
  lanes_fixture rgr integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — studio-test: 1 failed\nauto\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held stop: gate red — studio-test: 1 failed until " "gate_repairs 0: a red finish holds"
  assert_eq 0 "$(gate_calls)" "no repair before the resume"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 1 "$(gate_calls)" "one gate-repair unit"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish stop,4 A-gate-repair progress,5 A-finish done," \
    "$(story_rows A)" "the first unit after the resume is the gate repair (AC20)"
  lholds_off
}
test_lanes_resume_gate_repairs_counted() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 0}}'; export LANES_CONFIG
  lanes_fixture rgc integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\nstop gate red — y\n' > "$SCEN/A"
  printf 'gaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  lverb resume A
  wait_for 'case "$(rec A)" in "held gate red after"*) true ;; *) false ;; esac' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held gate red after 1 repairs — y until " "the resume-granted repair counts (AC20)"
  lverb stop A; assert_eq "stop requested: A stops within one poll" "$(cat "$LV_OUT")" "stop A while held"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped gate red after 1 repairs — y" "$(rec A)" "stop on a held story ends it stopped <why> (AC23)"
  assert_eq 1 "$(gate_calls)" "one repair unit"
  lholds_off
}
test_lanes_resume_not_gate_red_no_repair_unit() {
  lanes_fixture rng integration A:-
  lholds_on 120
  printf 'auto\nstop need art\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 0 "$(gate_calls)" "a latest Stop that is not gate red gets no repair unit"
  assert_eq "1 A-T1 progress,2 A-final-review stop,3 A-final-review progress,4 A-finish done," "$(story_rows A)" "the unit loop resumes"
  lholds_off
}
test_lanes_gate_repair_noprog_holds() {
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture grn integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\nauto\n' > "$SCEN/A"
  printf 'noop\ngaterepair\n' > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held gate repair made no progress until " "a gate repair with no progress holds (AC17)"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq 2 "$(gate_calls)" "the latest Stop is still gate red: the resume gets a repair unit (R29)"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish stop,4 A-gate-repair noprog,5 A-gate-repair progress,6 A-finish done," \
    "$(story_rows A)" "repair, hold, repair, fresh finish"
  lholds_off
}
test_lanes_landing_never_holds() {
  lholds_on 120
  lanes_fixture lnh integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'noop\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$" "a land repair with no progress ends at once (AC18)"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  lanes_fixture lnh2 integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nsleep 4\n' > "$SCEN/B"
  printf 'stop cannot resolve\n' > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped stop: cannot resolve$" "a land repair's Stop: ends at once"
  assert_not_contains "$(last_lanes_dir)/events.jsonl" '"state":"held"' "never held"
  lholds_off
}
test_lanes_stop_queued_story() {
  lanes_fixture sqs integration A:- B:A D:B
  printf 'sleep 4; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec B)" = queued ]' 30
  lverb stop B; assert_eq "stop requested: B stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a queued story"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq "stopped by operator" "$(rec B)" "B never starts (AC7, R5)"
  assert_eq "skipped B" "$(rec D)" "the rest of the chain is skipped, as today"
  assert_eq "" "$(story_calls B)" "B ran no unit"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
}
test_lanes_stop_running_story() {
  lanes_fixture srs integration A:-
  printf 'sleep 4; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb stop A; assert_eq "stop requested: A stops after its running unit" "$(cat "$LV_OUT")" "stop on a running story"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped by operator" "$(rec A)" "after its unit (AC23)"
  assert_eq "1 A-T1 progress," "$(story_rows A)" "one unit ran"
}
test_lanes_stop_waiting_story() {
  lanes_fixture sws integration A:- B:- C:A,B
  STUDIO_OVERNIGHT_POLL_SECONDS=1; export STUDIO_OVERNIGHT_POLL_SECONDS
  printf 'sleep 8; auto\n' > "$SCEN/A"; printf 'sleep 8; auto\n' > "$SCEN/B"
  lanes_bg
  wait_for '[ "$(rec C)" = waiting ]' 30
  lverb stop C; assert_eq "stop requested: C stops when its lane reaches it" "$(cat "$LV_OUT")" "stop on a waiting story"
  wait_for '[ "$(rec C)" = "stopped by operator" ]' 5
  assert_eq "stopped by operator" "$(rec C)" "a waiting story stops within one poll"
  assert_eq 0 "$(awk 'BEGIN { n = 0 } /landed/ { n++ } END { print n }' "$(last_lanes_dir)/stories/A")" "before A lands"
  wait_pid_or_fail "$RPID" 120 "the run ends"
  assert_eq "" "$(story_calls C)" "C ran no unit"
  for id in A B; do assert_contains "$(last_lanes_dir)/stories/$id" "^landed " "$id still lands"; done
  unset STUDIO_OVERNIGHT_POLL_SECONDS
}
test_lanes_hold_waiting_story_holds_at_start() {
  lanes_fixture hws integration A:- B:- C:A,B
  lholds_on 120
  printf 'sleep 4; auto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(rec C)" = waiting ]' 30
  lverb hold C; assert_eq "hold requested: C holds when it would start" "$(cat "$LV_OUT")" "hold on a waiting story"
  wait_for 'is_held C' 60
  assert_contains "$(last_lanes_dir)/stories/C" "^held held by operator until " "C holds when it would start (R7)"
  assert_eq "" "$(story_calls C)" "before any unit"
  lverb resume C
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/C" "^landed " "C runs and lands after the resume"
  lholds_off
}
test_lanes_hold_running_then_resume() {
  lanes_fixture hrr integration A:-
  lholds_on 120
  printf 'sleep 4; auto\nauto\nauto\n' > "$SCEN/A"
  lanes_bg
  wait_for '[ "$(calls)" -ge 1 ] && [ "$(rec A)" = running ]' 30
  lverb hold A; assert_eq "hold requested: A holds at its next unit boundary" "$(cat "$LV_OUT")" "hold on a running story"
  wait_for 'is_held A' 30
  assert_contains "$(last_lanes_dir)/stories/A" "^held held by operator until " "held at the boundary"
  assert_eq "1 A-T1 progress," "$(story_rows A)" "after its running unit"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands"
  assert_eq "1 A-T1 progress,2 A-final-review progress,3 A-finish done," "$(story_rows A)" "the units ran on"
  lholds_off
}
test_lanes_run_stop_held_was_held() {
  lanes_fixture rsw integration A:- B:A
  lholds_on 120
  printf 'auto\nstop broke\n' > "$SCEN/A"
  lanes_bg
  wait_for 'is_held A' 60
  lverb stop; assert_contains "$LV_OUT" "^stop requested: the run ends after its running unit" "bare stop, as today"
  wait_pid_or_fail "$RPID" 60 "the run ends"
  assert_eq "stopped stopped by user (was held: stop: broke)" "$(rec A)" "the halt's reason, then the hold's (AC25)"
  assert_eq "skipped A" "$(rec B)" "its chain is skipped"
  lholds_off
}
test_lanes_final_step_no_delivery() {
  lanes_fixture fnd integration A:-
  printf 'auto\nauto\nsay left for later; auto\n' > "$SCEN/A"
  printf 'inbox; fixgate\n' > "$SCEN/final-repair"
  use_gate "echo gate >> '$CALLS/final-gates'; [ -f fixed ]"
  run_lanes start "$MFP"
  use_gate true
  _n="$(prompt_calls '/omega:integration repair demo')"
  assert_eq "" "$(cat "$CALLS/$_n.inbox" 2>/dev/null)" "the final step's unit (no STUDIO_STORY) gets no delivery (AC9)"
  assert_file "$(last_lanes_dir)/inbox/A/1.msg" "the message stays pending"
  assert_contains "$(last_lanes_dir)/report.md" "^Operator messages left:$" "the report lists A's messages left (AC14)"
  assert_contains "$(last_lanes_dir)/report.md" "^- 1 (story, requeues 0): left for later$" "with the message"
}
test_lanes_deadline() {
  lanes_fixture ldl integration A:- B:A
  lholds_on 2
  printf 'auto\nstop need art\n' > "$SCEN/A"
  run_lanes start "$MFP"
  assert_eq "stopped stop: need art (held 0h0m, no reply)" "$(rec A)" "the deadline ends the story (AC24)"
  assert_eq "skipped A" "$(rec B)" "and skips its chain"
  assert_eq "" "$(ls -A "$(last_lanes_dir)/control" 2>/dev/null)" "no control file left"
  lholds_off
}
```

Insert them, in this order, before `test_lanes_no_orphans`. Add the names
to `run_tests` before `test_lanes_no_orphans`, which stays last.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_lanes_test.sh`
Expected: FAIL in each new test. The story ends at once, with no `held`
record, so each `wait_for 'is_held …'` times out. `stop <id>` on a queued
story is ignored by the runner. `lanes_report` has no messages-left part.
`test_lanes_landing_never_holds` passes already: it pins behaviour.

- [ ] **Step 3: Implement in `overnight-lanes.sh`**

After `lane_halt_reason`:

```sh
# Holds in manifest mode (#27): a halt is the lane's (R28), and the held
# record is the story's record, stories/<id> (R4).
halt_reason() { lane_halt_reason; }
hold_record() { story_write "$1" "$2"; }
# last_stop_gate_red — the feature ledger's latest Stop: line is a red finish
# gate, `Stop: gate red — …` (§11's precondition; AC20, R29).
last_stop_gate_red() {
  ledger_of "$FEATURE_DIR" | grep '^- [0-9-]* Stop: ' | tail -n 1 | grep -q '^- [0-9-]* Stop: gate red — '
}
```

`gate_repair`: replace the `_gr_new="$(new_stop …)"` line and its `if`:

```sh
  take_new_stop "$UNIT_DIR/stops.before" "$UNIT_DIR/stops.after"
  _gr_a="$(ledger_of "$FEATURE_DIR" | grep -c '^- [0-9-]* Repair: ')"
  if [ -n "$NEW_STOP" ]; then row "$n" gate-repair stop; ENDING="$STOP_ENDING"; return 1; fi
```

`wait_deps`: after `lane_halt && return 2`, add
`[ ! -f "$RUN_DIR/control/$1.stop" ] || return 3`. Its header comment
gains "3 when the operator stopped ID (control/ID.stop)".

`run_chain`:
- in the skip line, add `ctl_clear "$_rc_id";` after `story_write`;
- in each of the wait cases 1 and 2, add `ctl_clear "$_rc_id";` after
  `story_write`;
- add the case
  `3) story_write "$_rc_id" "stopped by operator"; ctl_clear "$_rc_id"; _rc_skip="skipped $_rc_id"; continue ;;`;
- before `run_story "$_rc_id"`, add:

```sh
    # An operator stop that reached a queued story (AC7, R7): it never starts.
    if ctl_take "$_rc_id" stop; then
      story_write "$_rc_id" "stopped by operator"; ctl_clear "$_rc_id"; _rc_skip="skipped $_rc_id"; continue
    fi
```

`run_story`: replace everything from `_rs_rep=0` through the ending `case …
esac` with:

```sh
  _rs_rep=0
  # Hold loop (AC17-25): a holdable ending waits for the operator; a resume
  # runs one gate repair first when the latest Stop is gate red (AC20), then
  # the unit loop, and the post-loop handling again.
  while :; do
    story_gate_loop "$1"
    # story_units says `stopped by user` for any halt; name the real one.
    [ "$ENDING" != "stopped by user" ] || ENDING="$(lane_halt_reason)"
    holdable || break
    hold_wait "$1" || break
    if last_stop_gate_red; then
      op_boundary "$1" || continue
      _rs_rep=$((_rs_rep + 1))
      gate_repair "$1" || continue
    fi
    story_units
  done
  # A halt also holds back the landing (spec 124-127); so does an operator
  # stop that arrived during the last unit (R5).
  [ "$ENDING" != done ] || ! lane_halt || ENDING="$(lane_halt_reason)"
  [ "$ENDING" != done ] || ! ctl_take "$1" stop || ENDING="stopped by operator"
  case "$ENDING" in
    done) story_write "$1" landing; land_story "$1" ;;
    "stopped by operator") story_write "$1" "$ENDING" ;;
    *) story_write "$1" "stopped $ENDING"
       [ "$ENDING" != "stop: run budget" ] || LANE_BUDGET=1 ;;
  esac
  ctl_clear "$1"
```

Keep `CUR_ID=""; LAUNCH_ENV=""` as the last line. Above `run_story`:

```sh
# story_gate_loop ID — the red-finish repair loop: a `stop: gate red — <line>`
# ending gets a gate-repair unit and the unit loop again, up to gate_repairs
# repairs in all (_rs_rep counts every repair unit of the story, those after
# a resume included); past that, `gate red after <k> repairs — <line>`
# (gate_repairs 0 keeps `stop: gate red — <line>`). The operator boundary
# (R8) runs before each repair unit.
story_gate_loop() {
  while :; do
    case "$ENDING" in "stop: gate red — "*) ;; *) break ;; esac
    if [ "$_rs_rep" -ge "$GATE_REPAIRS" ]; then
      [ "$_rs_rep" -eq 0 ] || ENDING="gate red after $_rs_rep repairs — ${ENDING#stop: gate red — }"
      break
    fi
    op_boundary "$1" || break
    _rs_rep=$((_rs_rep + 1))
    gate_repair "$1" || break
    story_units
  done
}
```

Update `run_story`'s header comment to name the hold loop and
`stopped by operator`.

`lanes_status_lines`: replace the `if [ "$_st_u" != - ]; then … fi` block
with:

```sh
    case "$_st_r" in
      "held "*) printf '    %s\n' "$(held_line "$_st_r" "$_st_id")" ;;
      *) if [ "$_st_u" != - ]; then
           _st_n="$(unit_now_line "$RUN_DIR/lanes/$_st_k")"
           [ -z "$_st_n" ] || printf '    %s\n' "$_st_n"
         fi ;;
    esac
```

`lanes_report`: after the `story_ledger_lines` pair, inside the per-story
loop:

```sh
      _r_m="$(msgs_left "$_r_id")"
      [ -z "$_r_m" ] || printf '\nOperator messages left:\n%s\n' "$_r_m"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/overnight_lanes_test.sh && sh tests/overnight_test.sh && sh tests/run_all.sh`
Expected: PASS. Every existing lanes test is unchanged:
`test_lanes_gate_repair_then_lands` and its siblings run with holds off,
and with holds off `story_gate_loop` is today's loop.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/bin/overnight-lanes.sh tests/overnight_lanes_test.sh
git commit -m "feat(overnight): lane holds, operator stops and the resume gate repair (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

### Task 8: `studio-brief` prints the active directives

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L219-227
Review: task

**Files:**
- Modify: `studios/game-dev/bin/studio-brief`:
  - the header comment (L7-22);
  - the new helpers after `state_get` (L58);
  - the `task` arm (L94);
  - the `final` arm (L188-200).
- Modify: `tests/studio_brief_test.sh`:
  - the helper `add_directives`;
  - four tests;
  - `run_tests` (L151).

**Interfaces:**
- Consumes: the ledger line format, `- <date> Directive <id>: <text>` and
  `- <date> Directive <id> retired` (T5's suggested commands).
- Produces:
  - a part `==> <ledger path>` followed by the active directive lines,
    printed by `task <n>` after the Task block and by `final` before
    `diff:`;
  - the anchored ruling match.

- [ ] **Step 1: Write the failing tests**

```sh
# add_directives DIR — S1's ledger in DIR gains active, retired and
# ruling-looking directives.
add_directives() {
  ( cd "$1" && STUDIO_STORY=S1 && export STUDIO_STORY
    sh "$STATE_BIN" ledger "Directive 1: use the bus"
    sh "$STATE_BIN" ledger "Directive 2: Ruling: is not a ruling"
    sh "$STATE_BIN" ledger "Directive 3: temp"
    sh "$STATE_BIN" ledger "Directive 3 retired" ) >/dev/null 2>&1
}
test_brief_directives_task() {
  Q="$TMP/projd"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/dt.txt"; st=$?
  assert_eq 0 "$st" "task 3 exits 0"
  assert_contains "$TMP/dt.txt" "^==> .*/\.studio/ledger/S1\.md$" "a ledger part headed by the story's ledger"
  assert_contains "$TMP/dt.txt" "^- [0-9-]* Directive 1: use the bus$" "an active directive"
  assert_contains "$TMP/dt.txt" "^- [0-9-]* Directive 2: Ruling: is not a ruling$" "another"
  assert_not_contains "$TMP/dt.txt" "Directive 3" "a retired directive and its retire line are left out"
  assert_not_contains "$TMP/dt.txt" "T1 complete" "no other ledger line"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" task 2 ) > "$TMP/dt2.txt"
  assert_contains "$TMP/dt2.txt" "Directive 1: use the bus" "a task with no Spec: line still gets them"
  assert_contains "$TMP/dt2.txt" "(task 2 has no Spec: line)" "and its note"
}
test_brief_directives_final() {
  Q="$TMP/projf"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/df.txt"; st=$?
  assert_eq 0 "$st" "final exits 0"
  ld="$(grep -n 'Directive 1: use the bus' "$TMP/df.txt" | cut -d: -f1)"
  dd="$(grep -n '^diff: ' "$TMP/df.txt" | cut -d: -f1)"
  assert_eq 1 "$([ -n "$ld" ] && [ -n "$dd" ] && [ "$ld" -lt "$dd" ] && echo 1 || echo 0)" "the directives come before diff: (AC15)"
  assert_not_contains "$TMP/df.txt" "Directive 3" "no retired directive"
}
test_brief_directive_text_not_ruling() {
  Q="$TMP/projr"; build_fixture "$Q"; add_directives "$Q"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/dr.txt"
  awk '/^==> .*\.studio\/ledger\// { p++; next } /^==> |^diff: / { p = 0 } p == 1' "$TMP/dr.txt" > "$TMP/dr.rulings"
  assert_eq 1 "$(grep -c 'Ruling: ' "$TMP/dr.rulings")" "the rulings part holds only the real ruling"
  assert_contains "$TMP/dr.rulings" "minor (deferred): rename" "a Task-prefixed deferred minor still matches"
  assert_not_contains "$TMP/dr.rulings" "Directive" "directive text never reads as a ruling"
}
test_brief_no_directives_no_part() {
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" task 3 ) > "$TMP/nd.txt"
  assert_eq 0 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/nd.txt")" "no directives: no ledger part in task"
  ( cd "$P" && STUDIO_STORY=S1 sh "$BRIEF" final ) > "$TMP/ndf.txt"
  assert_eq 1 "$(grep -c '^==> .*\.studio/ledger/' "$TMP/ndf.txt")" "final keeps only its rulings part"
}
```

Add the four names to `run_tests`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/studio_brief_test.sh`
Expected: FAIL in these:
- `test_brief_directives_task`: no ledger part.
- `test_brief_directives_final`: `ld` is empty.
- `test_brief_directive_text_not_ruling`: the unanchored grep prints
  `Directive 2: Ruling: …` in the rulings part, so the count is 2.

`test_brief_no_directives_no_part` passes.

- [ ] **Step 3: Implement**

After `state_get`:

```sh
# ledger_path — the story's ledger in this checkout: .studio/ledger/
# <STUDIO_STORY>.md, else the spec slug's (date prefix stripped); empty when
# neither is known.
ledger_path() {
  if [ -n "${STUDIO_STORY:-}" ]; then printf '%s\n' "$WORK/.studio/ledger/$STUDIO_STORY.md"; return 0; fi
  _lp_s="$(state_get spec)"; [ -n "$_lp_s" ] || return 0
  printf '%s\n' "$WORK/.studio/ledger/$(basename "$_lp_s" | sed -e 's/\.md$//' -e 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//').md"
}
# directives_part — AC15: the ledger's active directives (a `Directive <id>:`
# line with no later `Directive <id> retired`), as one part headed
# `==> <ledger path>`; nothing when there are none.
directives_part() {
  _dp_l="$(ledger_path)"
  [ -n "$_dp_l" ] && [ -f "$_dp_l" ] || return 0
  _dp="$(awk '
    { t = $0; sub(/^- [0-9-]+ /, "", t) }
    t ~ /^Directive [0-9]+: / { id = t; sub(/^Directive /, "", id); sub(/:.*/, "", id); L[NR] = $0; D[NR] = id; next }
    t ~ /^Directive [0-9]+ retired *$/ { id = t; sub(/^Directive /, "", id); sub(/ .*/, "", id); R[id] = NR }
    END { for (i = 1; i <= NR; i++) if ((i in L) && !((D[i] in R) && R[D[i]] > i)) print L[i] }' "$_dp_l")"
  [ -z "$_dp" ] || printf '==> %s\n%s\n' "$_dp_l" "$_dp"
}
```

`task` arm: after `emit "$plan" "$ta" "$tb"`, add `directives_part`.

`final` arm:
- replace the `if [ -n "$story" ] … fi` ledger-path block with
  `ledger="$(ledger_path)"`;
- replace the `grep -E 'Ruling: |minor \(deferred\)'` line with
  `grep -E '^- [0-9-]+ ((T[0-9]+|Task [0-9]+:) )?(Ruling: |minor \(deferred\))' "$ledger" || true`;
- after the ledger `if … fi`, before `# the diff command`, add
  `directives_part`.

In the header comment:
- `task` gains: "then the story ledger's active directives (`Directive
  <id>:` lines not later retired) as a part `==> <ledger>`";
- `final` gains: "the active directives the same way, before `diff:`";
- `final`'s ruling text becomes "the ledger's `Ruling: ` and
  `minor (deferred)` lines (anchored at the line's prefix)".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/studio_brief_test.sh && sh tests/run_all.sh`
Expected: PASS. `test_brief_final` still finds `Ruling: chose X` and
`minor (deferred): rename`.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/bin/studio-brief tests/studio_brief_test.sh
git commit -m "feat(brief): print a story's active directives (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```


### Task 9: The execute skill — operator messages

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L187-206, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L336-336, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L380-403
Review: final

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md`:
  - §0 lane docs-sync bullet, L86-89 (`Then studio-state set branch … base origin/<Target>`);
  - §0 (c), L135-141;
  - §7 intro, L434-437;
  - the end of §8, after L651 (before `## 9.`): a new `### Operator messages (overnight units)` block;
  - §9 "Enter the feature checkout" bullet, L660-661;
  - §11 "Enter the feature checkout" bullet, L725-728.
- Test: `tests/studio_test.sh` (a new test after `test_execute_gate_repair`, L543; `run_tests`, L617).

**Interfaces:**
- Consumes: T5's delivery block. It tells the session to record "at your
  recording point — after §0 step (c) …; in a --land or --gate-repair unit,
  after entering the feature checkout". It also prints the commands
  `studio-state ledger 'Directive <id>: <text>'` and
  `studio-state ledger 'Directive <target> retired'`. The skill must use
  the same words.
- Consumes: T6's `requeue_check`. It reads the feature ledger for
  `Directive <id>:` and `Directive <target> retired`, so the skill names
  that ledger.
- Produces: the heading `### Operator messages (overnight units)` and the
  pointer phrase `(see §8, Operator messages)`. No code reads either one.

**One-line rule.** `assert_contains` is `grep -q` line by line, so every
literal the test asserts must sit on one line of SKILL.md. Write the block
below exactly as wrapped here.

- [ ] **Step 1: Write the failing test**

In `tests/studio_test.sh`, after `test_execute_gate_repair`:

```sh
# section_count FILE HEADING_RE PATTERN — matches of PATTERN between the
# `## ` heading matching HEADING_RE and the next `## ` heading.
section_count() {
  awk -v h="$2" -v p="$3" '/^## / { s = ($0 ~ h) } s && index($0, p) { n++ } END { print n + 0 }' "$1"
}

# Operator messages (#27, AC12): what a unit does with the runner's
# OPERATOR MESSAGES block, and where each unit kind records it.
test_execute_operator_messages() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '^### Operator messages (overnight units)$' "the block exists"
  assert_contains "$E" 'Each message is an instruction from the user' "a message is the user's instruction"
  assert_contains "$E" "studio-state ledger 'Directive <id>: <text>'" "story scope: the single-quoted record"
  assert_contains "$E" "in this unit only. Do not record it." "unit scope: not recorded"
  assert_contains "$E" "studio-state ledger 'Directive <target> retired'" "retire scope: the record"
  assert_contains "$E" "the \*\*feature checkout's\*\* ledger" "recorded in the feature checkout's ledger"
  assert_contains "$E" 'never before the fast-forward' "single-plan: after (c), never before the fast-forward"
  assert_contains "$E" 'docs-sync commit (when there is one) and the `base origin/<Target>` line' "lane: after the docs sync and the base line"
  assert_contains "$E" 'after their \*\*Enter the feature checkout\*\* step' "§9 and §11: after entering"
  assert_contains "$E" 'A message that arrives earlier is remembered and recorded at that point' "an early message waits for the point"
  assert_contains "$E" "committed with the unit's next ledger commit" "commit with the next ledger commit"
  assert_contains "$E" 'a red stop pushes nothing' "push only what the unit pushes"
  assert_contains "$E" 'is committed in a `chore(studio): ledger` commit before the unit ends' "the closing ledger commit"
  assert_contains "$E" 'for what you build, record a `Stop:` with the conflict instead' "the conflict rule"
  assert_eq 2 "$(section_count "$E" '^## 0[.] ' '(see §8, Operator messages)')" "§0 points at the block twice (lane base line, (c))"
  assert_eq 1 "$(section_count "$E" '^## 7[.] ' '(see §8, Operator messages)')" "§7 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 9[.] ' '(see §8, Operator messages)')" "§9 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 11[.] ' '(see §8, Operator messages)')" "§11 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 8[.] ' '### Operator messages (overnight units)')" "the block is under §8"
}
```

Add `test_execute_operator_messages` to `run_tests` after
`test_execute_gate_repair` (L617).

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/studio_test.sh`
Expected: FAIL on `the block exists` and every assertion after it.

- [ ] **Step 3: Write the block and the pointers**

At the end of §8, after L651 (the `--one` with `--inline` bullet) and
before `## 9. Landing repair (--land)`, insert:

```markdown

### Operator messages (overnight units)

In an overnight unit the runner's hook may add an `OPERATOR MESSAGES`
block to the session, at its start or after any tool call. Each message is an instruction from the user. Follow it by its scope:

- `story` — follow it for the rest of the story, and record it in
  the **feature checkout's** ledger, single-quoted, exactly as the block prints it:
  `studio-state ledger 'Directive <id>: <text>'`.
- `unit` — follow it in this unit only. Do not record it.
- `retire` — stop following directive `<target>`, and record
  `studio-state ledger 'Directive <target> retired'` the same way.

**Recording point.** Record only at your unit kind's point. An earlier line
is overwritten, or makes a merge abort:
- §0 units, single-plan: after §0 step (c) (after its `base <noted branch>`
  line when it writes one); never before the fast-forward.
- §0 units, lane: after the `docs(<id>): …` docs-sync commit (when there is one) and the `base origin/<Target>` line.
  The docs sync replaces the story ledger.
- §9 (`--land`) and §11 (`--gate-repair`) units: after their **Enter the feature checkout** step.

A message that arrives earlier is remembered and recorded at that point.

**Commit and push.** The line is committed with the unit's next ledger commit
and pushed only when that commit is pushed: a red stop pushes nothing. A
line recorded after the unit's last ledger commit
is committed in a `chore(studio): ledger` commit before the unit ends
(`git add .studio/ledger && git commit -m "chore(studio): ledger"`), and is
pushed under the same rule.

**Conflicts.** If a message conflicts with the approved plan or spec,
follow it for how you work; for what you build, record a `Stop:` with the conflict instead (§8's stop rule).

After the unit, the runner checks that each `story` and `retire` message it
delivered has its line in the feature ledger. An unrecorded one is delivered
again, and repeated misses hold the story.
```

Pointers. Each one is a sentence added to the end of an existing bullet or
paragraph. Keep the wording:

- §0, the lane bullet that ends "is used only for `gh pr create --base`."
  (L86-89): append, on a new line of the same bullet,
  `  A lane unit records operator messages after this line (see §8, Operator messages).`
- §0 (c), after "makes it abort." (L141): append, on a new line of the
  same bullet,
  `  Operator messages are recorded after this step (see §8, Operator messages).`
- §7, after the intro paragraph (L436-437), as its own paragraph:
  `A finish records operator messages at §0's recording point and commits them with its next ledger commit (see §8, Operator messages).`
- §9, a new bullet right after "Enter the feature checkout" (L660-661):
  `- **Operator messages** are recorded here, after entering (see §8, Operator messages).`
- §11, the same bullet right after its "Enter the feature checkout"
  bullet (L725-728).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/studio_test.sh && sh tests/run_all.sh`
Expected: PASS. Every existing `test_execute_*` assertion still passes:
- `test_execute_gate_repair` asserts §11's precondition line, which
  follows the new bullet and is unchanged;
- `test_execute_lanes` asserts the docs-sync text, which only gains a
  line.

- [ ] **Step 5: Commit**

```bash
git add studios/game-dev/skills/execute/SKILL.md tests/studio_test.sh
git commit -m "docs(execute): operator messages — scopes, recording points, commits (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 10: The hook delivery probe, and doctor's line

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L27-27, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L101-111, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L305-309, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L535-535
Review: final

**Files:**
- Create: `tests/probes/hook_delivery_probe.sh` (`chmod 755`).
- Modify: `doctor.sh`, after L210 (`log "launch:       $SHIM_NAME"`).
- Test:
  - `tests/hook_test.sh`: `test_inbox_probe_usage` and
    `test_inbox_probe_fake_launcher`, added to `run_tests` (L372).
  - `tests/install_test.sh`: `test_doctor_hook_probe_line`, added to
    `run_tests` (L1228).

**Interfaces:**
- Consumes: nothing from earlier tasks. The probe installs its own
  throwaway hooks through `--settings`, so it checks Claude Code and not
  `operator-inbox.sh`.
- Produces: the record `${HOME%/}/.claude-gamedev/probes/hook_delivery`.
  - Line 1 is the first line of `<launcher> --version`.
  - Line 2 is the date, `date -u +%Y-%m-%d`.
- Produces: doctor's line, which is one of:
  - `hook probe:   <line 1> — passed <line 2>`
  - `hook probe:   hook delivery probe not run`

  It is printed for the `game-dev` studio only, and it never sets
  `failed`.
- Probe exit codes: 0 PASS · 1 FAIL or inconclusive · 2 usage or no
  launcher. Logs go in `$PROBE_DIR` (default: a `mktemp -d`).

- [ ] **Step 1: Write the failing tests**

In `tests/hook_test.sh`, before `run_tests`:

```sh
PROBE="$REPO_ROOT/tests/probes/hook_delivery_probe.sh"

# AC31: the probe parses, refuses bad usage with 2, records nothing without a
# pass, and is never part of the gate.
test_inbox_probe_usage() {
  assert_file "$PROBE" "the probe exists"
  assert_eq 1 "$([ -x "$PROBE" ] && echo 1 || echo 0)" "the probe is executable"
  assert_status 0 "the probe parses" -- sh -n "$PROBE"
  mkdir -p "$TMP/ph"
  st=0; HOME="$TMP/ph" sh "$PROBE" a b >/dev/null 2>&1 || st=$?
  assert_eq 2 "$st" "two arguments: usage, exit 2"
  st=0; HOME="$TMP/ph" sh "$PROBE" --help >/dev/null 2>&1 || st=$?
  assert_eq 2 "$st" "an option for a launcher: usage, exit 2"
  st=0; HOME="$TMP/ph" sh "$PROBE" "$TMP/no-such-claude" >/dev/null 2>"$TMP/ph.err" || st=$?
  assert_eq 2 "$st" "a missing launcher: exit 2"
  assert_contains "$TMP/ph.err" "not on PATH" "it names the missing launcher"
  assert_missing "$TMP/ph/.claude-gamedev" "nothing is recorded without a pass"
  assert_not_contains "$REPO_ROOT/tests/run_all.sh" "probes" "run_all.sh never runs a probe (it spends model calls)"
}

# fake_claude FILE — a launcher that runs the --settings hooks the way the
# spike saw Claude Code run them, and answers with stream-json. FAKE_MODE:
# ok | no_ss (the model never saw the SessionStart marker) | no_agent_id
# (the subagent's hook input lacks agent_id).
fake_claude() {
  cat > "$1" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && { echo "9.9.9 (Fake Code)"; exit 0; }
P=""; S=""
while [ "$#" -gt 0 ]; do
  case "$1" in -p) P="$2"; shift 2 ;; --settings) S="$2"; shift 2 ;; *) shift ;; esac
done
hook() { sed -n "s/.*\"$1\".*\"command\": \"\\([^\"]*\\)\".*/\\1/p" "$S" | head -n 1; }
SS="$(hook SessionStart)"; PT="$(hook PostToolUse)"
ssm="$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | eval "$SS" | sed 's/.*: //')"
case "$P" in
  *probe-main*)
    echo '{"tool_name":"Bash","tool_input":{"command":"echo probe-main"}}' | eval "$PT" >/dev/null
    if [ "${FAKE_MODE:-ok}" = no_agent_id ]; then a=''; else a='"agent_id":"a3cc","agent_type":"general-purpose",'; fi
    echo "{${a}\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo probe-sub\"}}" | eval "$PT" >/dev/null
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo probe-main"}}]}}'
    echo '{"type":"result","subtype":"success","result":"OK"}' ;;
  *)
    ptm="$(echo '{"tool_name":"Bash","tool_input":{"command":"echo probe-a"}}' | eval "$PT" | sed 's/.*Tool marker: \([A-Za-z0-9_]*\).*/\1/')"
    [ "${FAKE_MODE:-ok}" = no_ss ] && ssm=NONE
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo probe-a"}}]}}'
    echo "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"SS=$ssm PT=$ptm\"}" ;;
esac
EOF
  chmod 755 "$1"
}

# AC31: the probe's own logic, on a fake launcher — PASS records the version
# and the date; each failed check is exit 1 and records nothing.
test_inbox_probe_fake_launcher() {
  fake_claude "$TMP/fake-claude"
  mkdir -p "$TMP/pf-home"
  st=0; HOME="$TMP/pf-home" PROBE_DIR="$TMP/pf-ok" sh "$PROBE" "$TMP/fake-claude" > "$TMP/pf.out" 2>&1 || st=$?
  assert_eq 0 "$st" "all three checks pass: exit 0"
  assert_contains "$TMP/pf.out" "^PASS$" "it says PASS"
  R="$TMP/pf-home/.claude-gamedev/probes/hook_delivery"
  assert_eq "9.9.9 (Fake Code)" "$(sed -n 1p "$R" 2>/dev/null)" "line 1: the launcher's version"
  assert_eq "$(date -u +%Y-%m-%d)" "$(sed -n 2p "$R" 2>/dev/null)" "line 2: the UTC date"
  for mode in no_ss no_agent_id; do
    rm -f "$R"
    st=0; FAKE_MODE=$mode HOME="$TMP/pf-home" PROBE_DIR="$TMP/pf-$mode" sh "$PROBE" "$TMP/fake-claude" > "$TMP/pf.out" 2>&1 || st=$?
    assert_eq 1 "$st" "$mode: exit 1"
    assert_contains "$TMP/pf.out" "^FAIL$" "$mode: it says FAIL"
    assert_missing "$R" "$mode: nothing is recorded"
  done
}
```

Add `test_inbox_probe_usage test_inbox_probe_fake_launcher` to
`run_tests`.

`HOME=… PROBE_DIR=… sh …` prefixes an external command, so nothing leaks
into the suite. The `VAR=v func` leak applies to shell functions only.

In `tests/install_test.sh`, after `test_doctor_delegations`:

```sh
# AC31: doctor reports the hook delivery probe's last pass, or that it never
# ran; the line never changes doctor's exit.
test_doctor_hook_probe_line() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/hp" --shim-dir "$TMP/bin-hp" >/dev/null 2>&1
  mkdir -p "$TMP/hp-home"
  st0=0; ( HOME="$TMP/hp-home" sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/hp" ) > "$TMP/hp0.out" 2>&1 || st0=$?
  assert_contains "$TMP/hp0.out" "^hook probe:   hook delivery probe not run$" "no record: not run"
  mkdir -p "$TMP/hp-home/.claude-gamedev/probes"
  printf '2.1.288 (Claude Code)\n2026-10-03\n' > "$TMP/hp-home/.claude-gamedev/probes/hook_delivery"
  st1=0; ( HOME="$TMP/hp-home" sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/hp" ) > "$TMP/hp1.out" 2>&1 || st1=$?
  assert_contains "$TMP/hp1.out" "^hook probe:   2\.1\.288 (Claude Code) — passed 2026-10-03$" "the recorded version and date"
  assert_eq "$st0" "$st1" "the probe line never changes doctor's exit"
  assert_eq 1 "$(grep -n '^launch:' "$TMP/hp1.out" | cut -d: -f1 | awk -v p="$(grep -n '^hook probe:' "$TMP/hp1.out" | cut -d: -f1)" '{ print ($1 + 1 == p) ? 1 : 0 }')" "the line follows launch:"
}
```

`cut` is fine here: install_test runs under the full `PATH`. Add
`test_doctor_hook_probe_line` to `run_tests` after
`test_doctor_delegations` (L1228).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/hook_test.sh; sh tests/install_test.sh`
Expected: FAIL.
- hook_test fails `the probe exists` and the probe tests after it.
- install_test fails `no record: not run` and `the recorded version and
  date`.

- [ ] **Step 3: Write the probe and doctor's line**

`tests/probes/hook_delivery_probe.sh`:

```sh
#!/bin/sh
# hook_delivery_probe.sh — does the installed Claude Code still deliver hook
# output the way the overnight operator channel (#27) relies on? It repeats
# the 2026-10-03 spike's three checks (spec References):
#   1. a hook's input carries agent_id only inside a subagent (the inbox hook
#      skips subagent tool calls on it);
#   2. a PostToolUse hook's hookSpecificOutput.additionalContext reaches the
#      model in -p;
#   3. SessionStart plain stdout reaches the model in -p.
# Session a (checks 2, 3): one Bash call; the model's reply must quote both
# markers, which only the hooks know. Session b (check 1): one main Bash call
# and one subagent Bash call; the PostToolUse hook logs each input to ptu.log.
# The hooks are throwaway, passed with --settings; nothing is installed.
#
# Not part of tests/run_all.sh: it spends real model calls (haiku, at most
# $1 per session, two sessions).
# On PASS it writes ~/.claude-gamedev/probes/hook_delivery: line 1 the
# launcher's --version, line 2 the UTC date. doctor.sh prints it.
#
# Usage: hook_delivery_probe.sh [LAUNCHER]   (default claude)
# Exit 0 PASS · 1 FAIL · 2 usage or no launcher. Logs: $PROBE_DIR (default a
# mktemp dir).
set -u
usage() { echo "usage: hook_delivery_probe.sh [LAUNCHER]" >&2; exit 2; }
[ "$#" -le 1 ] || usage
L="${1:-claude}"
case "$L" in ''|-*) usage ;; esac
command -v "$L" >/dev/null 2>&1 || { echo "probe: $L not on PATH" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/hook-delivery-probe.XXXXXX")}"
case "$D" in *\'*|*\"*|*\\*) echo "probe: PROBE_DIR may not hold a quote or a backslash" >&2; exit 2 ;; esac
mkdir -p "$D/a" "$D/b" || exit 2
SSM=PROBE_SS_7d41; PTM=PROBE_PT_93c2

cat > "$D/ss.sh" <<EOF
#!/bin/sh
cat >/dev/null
echo "Session marker: $SSM"
EOF
cat > "$D/ptu.sh" <<EOF
#!/bin/sh
{ tr -d '\\n'; echo; } >> '$D/ptu.log'
printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Tool marker: $PTM"}}'
EOF
cat > "$D/settings.json" <<EOF
{"hooks": {
  "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "sh '$D/ss.sh'"}]}],
  "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "sh '$D/ptu.sh'"}]}]
}}
EOF

run() {  # run NAME PROMPT — one session in $D/NAME; stream-json in $D/NAME.jsonl
  ( cd "$D/$1" && "$L" -p "$2" --model haiku --settings "$D/settings.json" \
      --output-format stream-json --verbose \
      --permission-mode auto --permission-prompts none --max-budget-usd 1 ) \
    > "$D/$1.jsonl" 2> "$D/$1.err" < /dev/null
}
# reply NAME — the session's result line only: hook output echoed in the
# stream's other lines must not count as the model quoting it.
reply() { grep '"type":"result"' "$D/$1.jsonl" 2>/dev/null | tail -n 1; }
ran() { grep -q "\"command\":\"$2\"" "$D/$1.jsonl" 2>/dev/null; }
# bash_input TEXT — the logged PostToolUse input of the Bash call running TEXT.
bash_input() { grep '"tool_name": *"Bash"' "$D/ptu.log" 2>/dev/null | grep -- "$1" | head -n 1; }

rm -f "$D/ptu.log"
run a "Run this Bash command exactly once, in the foreground: echo probe-a
Then reply with one line: SS=<the session marker you were given at session start, or NONE> PT=<the tool marker you were given after the tool call, or NONE>"
mv -f "$D/ptu.log" "$D/a-ptu.log" 2>/dev/null
run b "Do exactly these two steps, in order, and nothing else.
1. Run this Bash command in the foreground: echo probe-main
2. Use the Agent tool once, with subagent_type general-purpose, giving the subagent this prompt: Run this Bash command in the foreground: echo probe-sub. Then reply done.
When both steps are done, reply with one line: OK"

ok=1
if ! ran a "echo probe-a"; then
  echo "probe: session a never ran its Bash call — inconclusive, rerun (logs: $D)" >&2; ok=0
else
  if reply a | grep -q "$SSM"; then echo "3 SessionStart stdout: reached the model"; else echo "3 SessionStart stdout: NOT seen by the model"; ok=0; fi
  if reply a | grep -q "$PTM"; then echo "2 PostToolUse additionalContext: reached the model"; else echo "2 PostToolUse additionalContext: NOT seen by the model"; ok=0; fi
fi
M="$(bash_input 'echo probe-main')"; S="$(bash_input 'echo probe-sub')"
if [ -z "$M" ] || [ -z "$S" ]; then
  echo "probe: session b ran no main or no subagent Bash call — inconclusive, rerun (logs: $D)" >&2; ok=0
elif printf '%s' "$M" | grep -q '"agent_id"'; then
  echo "1 agent_id: present in a MAIN-session hook input"; ok=0
elif ! printf '%s' "$S" | grep -q '"agent_id"'; then
  echo "1 agent_id: ABSENT from the subagent's hook input"; ok=0
else
  echo "1 agent_id: only inside the subagent"
fi
echo "logs: $D"
if [ "$ok" = 1 ]; then
  R="${HOME%/}/.claude-gamedev/probes"
  if mkdir -p "$R" && { "$L" --version 2>/dev/null | head -n 1; date -u +%Y-%m-%d; } > "$R/hook_delivery.tmp" \
     && mv -f "$R/hook_delivery.tmp" "$R/hook_delivery"; then
    echo "recorded: $R/hook_delivery"
  else
    echo "probe: could not write $R/hook_delivery" >&2
  fi
  echo PASS; exit 0
fi
echo FAIL; exit 1
```

Notes for the implementer:
- The heredocs are unquoted on purpose. `$D`, `$SSM` and `$PTM` expand
  when the hooks are written, and `\\n` becomes `\n` in the hook file.
- Session b's PostToolUse also fires for the main `Agent` call, and that
  input holds the text `echo probe-sub` in its prompt. `bash_input`
  filters on `"tool_name":"Bash"` first, so the Agent line is never
  mistaken for the subagent's Bash call.
- The fake launcher in `test_inbox_probe_fake_launcher` reads each hook
  command with `sed` on `"command": "…"`. Keep `settings.json`'s
  one-event-per-line layout and the `": "` spacing.

`doctor.sh`, after L210:

```sh
# The hook delivery probe (tests/probes/hook_delivery_probe.sh) records the
# Claude Code version it last passed on: the overnight operator channel
# relies on that hook delivery. Informational; never a failure.
if [ "$STUDIO" = game-dev ]; then
  _hp="${HOME%/}/.claude-gamedev/probes/hook_delivery"
  if [ -s "$_hp" ]; then
    log "hook probe:   $(sed -n 1p "$_hp") — passed $(sed -n 2p "$_hp")"
  else
    log "hook probe:   hook delivery probe not run"
  fi
fi
```

`chmod 755 tests/probes/hook_delivery_probe.sh`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/hook_test.sh && sh tests/install_test.sh && sh tests/run_all.sh`
Expected: PASS.

Do not run the real probe here: it spends money. The Final gate runs it
once.

- [ ] **Step 5: Commit**

```bash
git add tests/probes/hook_delivery_probe.sh doctor.sh tests/hook_test.sh tests/install_test.sh
git commit -m "feat(probe): hook delivery probe; doctor reports its last pass (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

### Task 11: The events contract, README and `--help`

Spec: docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L56-66, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L83-87, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L300-304, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L344-378, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L405-437, docs/game-dev/specs/2026-10-03-overnight-operator-channel.md:L453-463
Review: task

**Files:**
- Create: `docs/game-dev/overnight-events.md`.
- Modify: `README.md`:
  - the commands-table row for `studio-overnight`, L100;
  - the `### Overnight runs` list, a new bullet after the `status` bullet
    (L152-158).
- Modify: `studios/game-dev/bin/studio-overnight` `usage()` (L136-247):
  - the usage line (L138);
  - a new "Talking to a live run" part after the `activity` entry
    (L178-179);
  - two config rows after `model_progress`;
  - three test hooks after `STUDIO_OVERNIGHT_RACE_HOOK` (L245-246).
- Test: `tests/overnight_test.sh`:
  - extend `test_overnight_help` (L110-124);
  - add the new `test_events_contract_doc` to `run_tests`.

**Interfaces:**
- Consumes: the emitters, with their names exactly as written:
  - T2's `run_event` and `state_event`;
  - T3's `chan_event`;
  - T5's `sh "$EV" "$RD" message_delivered …`.
- Consumes: T3's verb texts:
  - the `chan_usage` lines;
  - the success lines (`removed message …`, `retire queued: …`,
    `hold requested: …`, `resume requested: …`, `stop requested: …`);
  - R27 (stdout on 0, one stderr line on 1/2);
  - R15 (`said` columns).
- Consumes: R2's discovery and R3's `channel` file.
- Produces: the contract that #28 reads (`docs/game-dev/overnight-events.md`).
  Its rule: within v1, fields and enum values may be added, never
  renamed or removed.

- [ ] **Step 1: Write the failing tests**

In `test_overnight_help`, add to the `for w in …` list:
`"say <story>" "said <story>" "unsay <story> <id>" "hold <story>" "resume <story>" "stop <story>" "--run <run>" "hold_minutes .*0-1440" "directive_chars .*500-16000" "STUDIO_OVERNIGHT_HOLD_MINUTES — test hook" "STUDIO_OVERNIGHT_HOLD_SECONDS — test hook" "STUDIO_OVERNIGHT_INBOX_WAIT — test hook" "events.jsonl" "next tool call"`.

`--run <run>` starts with `-`, but `assert_contains` passes `--`
to grep, so it is safe.

After `test_overnight_help`:

```sh
# AC30: the contract #28 builds on. Every event the code writes is in the
# doc's table and every documented event is written; the doc names the
# envelope, the verbs and exit codes, the files and run discovery.
test_events_contract_doc() {
  DOC="$REPO_ROOT/docs/game-dev/overnight-events.md"
  B="$REPO_ROOT/studios/game-dev/bin"; H="$REPO_ROOT/studios/game-dev/hooks/operator-inbox.sh"
  assert_file "$DOC" "the contract exists"
  for e in run_started story_listed story_state unit_started unit_ended message_queued message_delivered message_requeued control run_ended; do
    assert_contains "$DOC" "^| \`$e\` |" "the doc's table lists $e"
    assert_eq 1 "$(cat "$B/studio-overnight" "$B/overnight-lanes.sh" "$B/overnight-channel.sh" "$H" | grep -qE "(run_event|chan_event|\"\\\$RD\") $e " && echo 1 || echo 0)" "the code writes $e"
  done
  # a call site is `run_event NAME "` or `run_event NAME key=` (comments
  # such as "run_event EVENT FIELD…" do not match)
  for e in $( { cat "$B/studio-overnight" "$B/overnight-lanes.sh" "$B/overnight-channel.sh" | grep -oE '(run_event|chan_event) [a-z_]+ ("|[a-z_]+(=|:=|\[\]=))'
               grep -oE '"\$RD" [a-z_]+ "' "$H"; } | awk '{ print $2 }' | sort -u); do
    assert_contains "$DOC" "^| \`$e\` |" "$e, written by the code, is documented"
  done
  for w in '"v":1' '^## Schema v1' 'never renamed or removed' 'run=<run dir>' 'events.jsonl' 'hook.log' 'inbox/<story>/<id>.msg' \
           'delivered/<unit tag>/<id>.msg' 'control/<story>.hold' '^requeues: 0$' '^--$' 'hold_minutes=<N>' 'directive_chars=<N>' \
           'say <story>' 'said <story>' 'unsay <story> <id>' 'hold <story>' 'resume <story>' 'stop <story>' '--run <run>' \
           '^| 0 | ' '^| 1 | ' '^| 2 | ' 'run <name> is not live'; do
    assert_contains "$DOC" "$w" "the doc names $w"
  done
  assert_contains "$REPO_ROOT/README.md" "studio-overnight say" "README teaches say"
  assert_contains "$REPO_ROOT/README.md" "hold_minutes" "README names hold_minutes"
  assert_contains "$REPO_ROOT/README.md" "overnight-events.md" "README links the contract"
  assert_contains "$REPO_ROOT/README.md" "next tool call" "README states the delivery latency"
}
```

Add `test_events_contract_doc` to `run_tests` after `test_overnight_help`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/overnight_test.sh`
Expected: FAIL.
- `test_overnight_help` fails on `help names say <story>` and the other
  new words.
- `test_events_contract_doc` fails `the contract exists` and every doc
  assertion.

The ten `the code writes …` assertions already pass after T1-T8.

- [ ] **Step 3: Write the contract, the README part and the help**

`docs/game-dev/overnight-events.md` (full text: it is the contract):

````markdown
# Overnight run events and the operator channel (contract)

How a tool talks to a live `studio-overnight` run and reads what it does.
Story #27 defines it; #28 (the Multica bridge) builds on it. Spec:
`docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`.

## Finding a run

- Inside a project, the live run is the one holding the project's lock
  (`.studio/overnight.lock`: `pid=`, `run=`, `started=`).
- From anywhere, the user-level registry `~/.claude-gamedev/runs/` holds one
  file per live run, `overnight-<…>-<pid>`, with these lines:

  ```
  root=<project root>
  start=<start checkout>
  run=<run dir>
  pid=<runner pid>
  started=<ISO-8601 UTC>
  ```

  The run dir's basename is the run's name; every verb's `--run <run>` takes
  it. `last` is the newest ended run and is never live.
- A run dir holds `channel` (`hold_minutes=<N>`, `directive_chars=<N>`; the
  effective values) when it speaks this contract. A run without it predates
  the channel: every verb refuses it.

## Schema v1

`<run dir>/events.jsonl`: one JSON object per line, appended by
`bin/studio-event` only. Each line is at most 4096 bytes and starts with the
envelope, in this order:

```
{"v":1,"ts":"2026-10-03T21:04:00Z","run":"overnight-demo-20261003-210400","event":"run_started", …fields}
```

- `v` is 1. Within v1, fields and enum values may be added, never renamed or removed.
  A reader ignores fields it does not know.
- `ts` is ISO-8601 UTC; `run` is the run dir's basename.
- String fields are JSON-escaped and cut to 500 characters (never mid
  character). A line that would pass 4096 bytes drops fields from its end
  and gains `"cut":true`. Message text is never written to the log.
- A number field the runner does not know is `null`. Single-plan runs use
  `"story":"-"`; the final step's units do too.
- A failed write never stops the run. Verbs and the hook note it in
  `<run dir>/hook.log`; the runner notes it on its stderr.

| event | fields |
|---|---|
| `run_started` | `mode` (`single`, `integration`, `direct`), `max_lanes`, `hold_minutes` |
| `story_listed` | `story`, `chain`, `depends` (array of story ids) — one per story, right after `run_started`; together they are the queue |
| `story_state` | `story`, `state` (`queued`, `waiting`, `running`, `repair`, `gate-repair`, `held`, `landing`, `landed`, `stopped`, `skipped`), `why` (held, stopped, skipped), `until` (held: ISO-8601 UTC) |
| `unit_started` | `story`, `unit` (the unit tag), `label`, `model` |
| `unit_ended` | `story`, `unit`, `label`, `outcome` (`progress`, `done`, `stop`, `noprog`, `timed out`), `usd` (number or `null`) |
| `message_queued` | `story`, `id`, `scope` (`story`, `unit`, `retire`) |
| `message_delivered` | `story`, `id`, `scope`, `unit`, `via` (`session_start`, `tool_call`) |
| `message_requeued` | `story`, `id`, `unit`, `requeues` |
| `control` | `story`, `action` (`hold`, `resume`, `stop`) |
| `run_ended` | `ending`, `report` (path of `report.md`) |

## Verbs

`studio-overnight <verb> …`; `<story>` is `-` in a single-plan run. Every verb
takes `--run <run>` anywhere before `--`: it then acts only on that live run
and otherwise exits 1 with `run <name> is not live` — never another run.

| verb | does | stdout on 0 |
|---|---|---|
| `say <story> [--unit] '<text>'` or `say <story> [--unit] -- <text>` | queues a message (scope `story`, or `unit` with `--unit`); text after `--` is every word joined by spaces | the message id |
| `said <story>` | lists directives: `<id>  <state>  <text>`, state `active`, `pending`, `pending (unit)`, `delivered`, `retiring` | the list, or `(no directives)` |
| `unsay <story> <id>` | removes a pending message, or queues a `retire` for an active or delivered one | `removed message <id> …` or `retire queued: …` |
| `hold <story>` | `control/<story>.hold` | `hold requested: …` |
| `resume <story>` | `control/<story>.resume` (refused while the start checkout's ledger is dirty) | `resume requested: …` |
| `stop <story>` | `control/<story>.stop` | `stop requested: …` |
| `stop [--run <run>]` | ends the whole run after its running unit, as before | `stop requested: …` |

Exit codes (every verb):

| code | meaning | output |
|---|---|---|
| 0 | done | stdout |
| 1 | refused (no live run, two live runs and no `--run`, unknown story, an ended story, the directive cap, holds off, inbox busy, …) | one stderr line naming the reason (the cap lists the directives) |
| 2 | usage (bad options, empty text) | usage on stderr |

## Files

```
<run dir>/
  channel                           hold_minutes=<N> / directive_chars=<N>
  events.jsonl                      the log above
  hook.log                          hook and verb failures, one line each
  inbox/<story>/<id>.msg            a pending message
  inbox/<story>/delivered/<unit tag>/<id>.msg   claimed by that unit
  inbox/<story>/.lock/              the mkdir lock for ids
  control/<story>.hold | .resume | .stop        written by the verbs
  control/-.held                    single-plan: the held record
```

A message file (`inbox/<story>/<id>.msg`), written by temp file and `mv`:

```
id: 3
scope: story
target: -
story: S2
queued: 2026-10-03T21:04:00Z
requeues: 0
--
Use the EventBus autoload, not direct signals, for HUD updates.
```

- `scope` is `story`, `unit` or `retire`; `target` is the retired id
  (`retire` only, else `-`); every line after `--` is the text.
- Ids are per story: one more than the highest among the feature ledger's
  `Directive <id>:` lines and the inbox, assigned under `.lock/`. A lock
  older than 10 seconds is stale and is broken by rename; a verb waits at
  most 15 seconds, then exits 1 `inbox busy`.
- A control file holds the UTC time it was written; the runner acts on it
  at the next unit boundary or poll and removes it, and removes any left
  when the story ends. `.stop` beats `.resume`; both beat a hold's deadline.
- A held story's record is `held <why> until <ISO-8601 UTC>` (lanes: the
  story record; single-plan: `control/-.held`).
- A recorded directive is a feature-ledger line
  `- <date> Directive <id>: <text>`; a retirement is
  `- <date> Directive <id> retired`.
````

README, the commands-table row (L100) becomes:

`| \`studio-overnight start [<manifest>] \| status \| watch \| stop \| next \| say \| said \| unsay \| hold \| resume\` | Runs approved plans unattended, one fresh headless session per unit, and takes messages and holds while it runs; see below | start: 0 done · 1 other ending · 2 refused; the channel verbs: 0 · 1 refused · 2 usage |`

README, a new bullet after the `status` bullet:

```markdown
- Talking to a live run: `studio-overnight say <story> '<text>'` queues a
  message (`--unit` for this unit only; `said`, `unsay <story> <id>`), and
  `hold`, `resume` and `stop <story>` steer one story (`-` in a single-plan
  run; `--run <run>` names the run from anywhere). A message reaches the
  story's session at its start or its next tool call, so a session waiting
  on a subagent or a long gate reads it when that returns. With
  `overnight.hold_minutes` above 0 (default 480), a story that hits a stop
  rule after isolation holds instead of ending: reply with `say` then
  `resume`, or `stop` it; with no reply it ends at the deadline. A hold fixes
  what a session can be told (a missing decision, a wrong approach); a red
  landing, a run budget or a dead runner still end at once. Tools read
  `events.jsonl` in the run dir; the contract is
  `docs/game-dev/overnight-events.md`.
```

`usage()` in `studio-overnight`:

- The usage line (L138) gains `| stop [--run <run>]` in place of `| stop`,
  and a second line:
  `       $SELF_ABS say|said|unsay|hold|resume|stop <story> [--run <run>] … (talking to a live run; below)`.
- After the `activity <unit.jsonl>` entry (L178-179), insert:

```
Talking to a live run (<story> is - in a single-plan run; every verb takes
--run <run>, a run dir basename, and then acts only on that live run):
  say <story> [--unit] '<text>' | say <story> [--unit] -- <text>
                     queue a message for the story's sessions; prints its id.
                     A story message is followed for the rest of the story and
                     recorded as a Directive ledger line; --unit: this unit
                     only. It arrives at the session's start or at its
                     next tool call (a session waiting on a subagent or a
                     long gate reads it when that returns). Empty text exits 2.
  said <story>       the story's directives: id, state, text
  unsay <story> <id> remove a pending message, or retire a directive
  hold <story>       hold the story at its next unit boundary (queued or
                     waiting: when it would start)
  resume <story>     a held story goes on with its next unit (lanes: after a
                     red gate, one gate-repair unit first); refused while the
                     start checkout's ledger has uncommitted changes
  stop <story>       end the story (stopped by operator); its chain is skipped
  A stop rule after isolation holds the story for hold_minutes instead of
  ending it; say + resume, or stop, ends the hold, else the deadline does.
  A hold fixes what a session can be told; a red landing, the run budget,
  a whole-run stop or a dead runner still end at once.
  Exit: 0 done (stdout), 1 refused (one stderr line), 2 usage.
  Events: <run dir>/events.jsonl, schema v1 (docs/game-dev/overnight-events.md).
```

- After the `model_progress` row:

```
  hold_minutes         480   0-1440   minutes a held story waits for say/resume/stop;
                                    0 = a stop rule ends the story at once (no holds)
  directive_chars      4000  500-16000 cap on a story's active + pending directive text
```

- After `STUDIO_OVERNIGHT_RACE_HOOK`'s two lines:

```
  STUDIO_OVERNIGHT_HOLD_MINUTES — test hook: overrides hold_minutes; a whole
                     number 0-1440, else start refuses (the suites set 0)
  STUDIO_OVERNIGHT_HOLD_SECONDS — test hook: a hold's length in seconds, in
                     place of hold_minutes x 60; a whole number
  STUDIO_OVERNIGHT_INBOX_WAIT — test hook: seconds a verb waits for the
                     inbox lock (default 15)
```

Check against T2's config code before writing the rows:
- the default 480 and both ranges;
- whether the range check for each key accepts exactly 0-1440 and
  500-16000.

Write the rows from that code. If it differs from the spec, report it. Do
not change it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/overnight_test.sh && sh tests/run_all.sh`
Expected: PASS.
- `test_overnight_help` still finds every old word.
- `overnight_lanes_test.sh:1907-1908` still finds
  `studio-overnight start <manifest>` and `studio-overnight next` in the
  README.

- [ ] **Step 5: Commit**

```bash
git add docs/game-dev/overnight-events.md README.md studios/game-dev/bin/studio-overnight tests/overnight_test.sh
git commit -m "docs(overnight): events contract v1, README and help for the operator channel (#27)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Tnbm9nFxVRB6AQ9s5kXcui"
```

---

## Final gate

1. **Final whole-branch review, on Opus, standalone** (`model: "opus"`,
   never merged into T11's review). Diff range:
   `git diff origin/main...worktree-issue-27-operator-channel`.

   The brief gives the spec path, this plan's path and the diff range. It
   asks for one line per AC, `met: <AC> — <test or file:line>` or
   `unmet: <AC> — <why>`, for AC1, 2, 3, 4, 4a and 5-31, in that order.
   Then the reviewer checks:
   - **Review Focus 1-5 first**, each against its pinning test.
   - **Controller-named checks:**
     - AC1: `say … -- <text>` joins words, and empty text exits 2
       (`test_say_dash_text_and_unit`, `test_say_empty_text_exit_2`).
     - AC4a: `--run` works on every verb and on bare `stop`; it matches
       exactly; it fails with `run <name> is not live`; it never falls back
       (`test_verbs_run_pinning`).
     - The lock paragraph, spec L375-378: stale after 10 s, broken by
       rename, a 15 s wait, `inbox busy`
       (`test_inbox_lock_stale_broken`, `test_inbox_lock_busy`).
     - Events schema v1, AC28-30 (T1's `test_event_*`,
       `test_overnight_events_two_units`, `test_lanes_story_listed_events`,
       `test_events_contract_doc`).
   - The hook's local copies of `msg_get` and `msg_body` are identical to
     `overnight-channel.sh`'s (`diff` the two function bodies).
   - Every `Review: final` task's diff (T9, T10) is read in full.
   - Shell rules: bash 3.2 `/bin/sh`; no `local`, arrays or `[[`; prefixed
     function locals; no `VAR=v func`; no case-pattern `)` inside `$()`.
     The minimal-`PATH` paths (`requeue_check`, `studio-event`) use no
     `cut` and no `stat`.
   - AC16 and AC29: no path through the hook can exit non-zero or print
     outside a unit. T1's measured hook cost is recorded and under 20 ms.
   - R30: `--detach` strips `STUDIO_OVERNIGHT_HOLD_*` and
     `STUDIO_OVERNIGHT_INBOX_WAIT`.

   The full report goes to the scratchpad. The hand-back is 1.5k
   characters or less.
2. **Fixes.** A fresh fixer gets the findings and the diff range. Each
   fix is one `fix(final): <summary> (#27)` commit with the two trailer
   lines. Re-review only after a Critical, three or more Importants, or a
   production-bug fix; never a third pass.
3. **Gate commands**, from the worktree root:
   - `sh tests/run_all.sh` must exit 0 (milestone criterion 1).
   - `sh doctor.sh game-dev` exits as it did on `main`. It prints a
     `hook probe:` line.
   - `sh tests/probes/hook_delivery_probe.sh` must print PASS and write
     the record (milestone criterion 2). It is manual and spends money:
     about two haiku sessions, at most $1 each. Run it once, after the
     fixes. Then `sh doctor.sh game-dev` prints
     `hook probe:   <version> — passed <date>`.
4. The PROGRESS entry lands with the story PR (studio memory).

### Manual checks

| # | Who | When | What | Pass looks like |
|---|-----|------|------|-----------------|
| M1 | controller | after the fixes | `sh tests/probes/hook_delivery_probe.sh` (spends model calls) | `PASS`; the three check lines; the record written. On "inconclusive" rerun once; a FAIL is a blocker (spec Risks: hook delivery changed) |
| M2 | controller | T1's review | the hook-cost loop in T1 Step 5 | under 20 ms per call (spec Risks); the number in the T1 hand-back |
| M3 | user | before the PR leaves draft | milestone criterion 3: a throwaway Godot project, a manifest with two independent stories, one made to stop after isolation | it holds (`status` shows `held — …`) while the other lands; `studio-overnight say <id> '…'` then `resume <id>`; the next unit's feature ledger has a committed `Directive <n>: …` line; the story lands; `events.jsonl` shows `story_state held` → `message_queued` → `control resume` → `message_delivered` → `unit_*` → `story_state landed` |
| M4 | user | during M3 | `said <id>` before and after delivery; `unsay` of an active directive | states `pending` → `delivered` → `active`; then `retiring` → retired |
| M5 | user | during M3 | a `say` while the session waits on a long gate | delivered at the next tool call after the gate (the README latency note holds) |

---

## Falsify

### Claims about the current code

| # | Claim | How checked | Result |
|---|-------|-------------|--------|
| 1 | `tests/run_all.sh` runs only `tests/*_test.sh`. Nothing under `tests/probes/` runs in the gate. | read run_all.sh:6 | OK |
| 2 | `assert_contains` is `grep -q -- PATTERN` (BRE, line by line), so a literal must sit on one line, `--run` is safe, and `*` must be escaped. | read assert.sh:47-54 | OK; T9 one-line rule; `\*\*` in T9's literals |
| 3 | `doctor.sh` runs `set -eu`. Its `log` is `printf '%s\n'` (lib/common.sh:4). `launch:` is at L210, outside the game-dev-only block. `$HOME` is read only for the leakage check (L259, L284), so a test HOME is safe. | read | OK |
| 4 | install_test's install-then-doctor pattern is at L375-380. `run_tests` is at L1228. | read | OK |
| 5 | `claude` 2.1.288 has `--settings <file-or-json>`, `--max-budget-usd`, `--permission-prompts`, `--model` and `--version`. | `claude --help` (read-only), `claude --version` | OK |
| 6 | stream-json lines are compact JSON (`"command":"…"`, `"type":"result"`). | the passing bash_timeout_probe.sh:53 relies on it | OK |
| 7 | SKILL.md anchors: lane base line L86-89; §0 (c) L135-141; §7 L434; §8 ends L651; §9 Enter L660; §11 Enter L725; studio_test's model test L543; `run_tests` L617. | grep -n, read | OK |
| 8 | No test pins SKILL.md's length, the help's first line, or the README table row. lanes_test:1907-1908 pins only `studio-overnight start <manifest>` and `studio-overnight next`. | grep tests | OK |
| 9 | Every spec event has an emitter in the plan's code: `run_event` (run_started, story_listed, story_state through `state_event`, unit_started, unit_ended, message_requeued, run_ended), `chan_event` (message_queued, control), and the hook's `"$RD" message_delivered`. Every call site has the form `NAME "` or `NAME key=`. | grep of plan parts p2-p5 | OK; T11's extraction regex matches all of them and no comment |
| 10 | The registry entry has `root= start= run= pid= started=`, plus `ended=` in `last`. | studio-overnight:560-592 | OK; the contract quotes it |
| 11 | Trials t1-t6: studio-event escaping and cut; the cap's character count; the `sq` round trip; the hook's JSON escape pipeline; hh:mm from an epoch; `chan_args`, `chan_list` and `next_id`. | ran in the scratchpad | OK |
| 12 | `date -d @N` fails on macOS; `date -r N` works. | ran | OK; R20 tries both, then the ISO |
| 13 | `STATE_ROOT` resolves to the main worktree from a linked worktree. | studio-state:38-45 | OK (R2; T4 `test_resume_from_feature_worktree`) |
| 14 | The suites' minimal `PATH` has no `stat` or `cut`. | read `make_minbin`, the existing minimal-PATH list | FIXED: `cut` → awk in `requeue_check`; T6 `test_overnight_requeue_minimal_path` |
| 15 | `EV_ON` must be set only after `run_setup` and the listing events, or a `story_state` lands before `run_started`. | read T2's code order | FIXED (T2) |
| 16 | BSD sed does not turn `\n` into a newline in a replacement. | ran | FIXED: T5's concurrent-hook test uses `grep -o` |
| 17 | The hook's malformed-message notice went to stdout, which reaches the model. | read the p4 draft | FIXED: `>&2` (into hook.log) |
| 18 | T3's unsay loop re-checked only the last stderr. | read the p3 draft | FIXED: one assertion after `unsay - 99` |
| 19 | `test_hook_files` keeps the existing `SessionStart` entry when `operator-inbox.sh` is added. | read hook_test | OK |
| 20 | The brief test fixture's `Ruling:` and `minor (deferred)` lines still match T8's anchored grep. | ran the grep on the fixture text | OK |
| 21 | `detach_start` strips every `STUDIO_*` variable (R30). | read | OK |
| 22 | `max_lanes` 0 gives one lane per chain, so an independent story runs while another is held. | read lanes `lanes_start` | OK |
| 23 | The lanes stub's `stop` action writes into the feature worktree when one exists. | read the stub | OK |
| 24 | The suites' fixture `HOME` is `$TMP/home`, so the registry the verbs read is the test's own. | read | OK |
| 25 | `SessionStart` with source `compact` fires in a headless `-p` session after auto-compaction, and its stdout reaches the model. | not reproducible without a long live session; the spike did not cover it | UNVERIFIED. T5 tests the hook's branch; M3 may show it |
| 26 | The plugin's `PostToolUse` hook (hooks.json) fires in `claude-gd -p` units as the probe's `--settings` hooks do. | the spike used `--settings` | UNVERIFIED. M3 (milestone criterion 3) is the check |
| 27 | GNU `date -d @N` works on Linux. | no Linux here | UNVERIFIED. R20 falls back to the ISO |
| 28 | `test_overnight_stop_beats_resume` (SIGSTOP the runner mid-poll, write both files, SIGCONT) is not flaky. | reasoning only | UNVERIFIED. The T6 implementer runs it 10 times |
| 29 | The unit labels asserted in `story_rows` (`final-review`, `finish`) match `label_for`. | partial read | UNVERIFIED. The T6 and T7 implementers check them against `label_for` |
| 30 | `take_new_stop`'s awk reads `FILENAME` correctly when the input is stdin (`-`). | reasoning | UNVERIFIED. T6's tests cover the path |
| 31 | The probe's `--permission-mode auto --permission-prompts none` lets haiku run `echo` and the Agent tool in `-p`. | flags taken from bash_timeout_probe.sh, which passes with sonnet | UNVERIFIED. M1 decides; a refusal shows as "inconclusive" |

### Task-order falsification

Each task must leave `sh tests/run_all.sh` at exit 0 given only the earlier
tasks.

- **T2 before T1.** `run_event` calls a missing `bin/studio-event`. Every
  event assertion in `test_overnight_events_two_units` goes red. Keep T1
  first.
- **The suites' `STUDIO_OVERNIGHT_HOLD_MINUTES=0` exports land in T2,**
  before any hold code (T6, T7). Today's tests therefore never see a hold.
  If T6 came before T2's exports, every existing stop test would hold
  480 min and time out.
- **T3 before T2.** The verbs read `RUN_DIR/channel`, which T2's
  `run_setup` writes. T3's fake runs write it themselves, so this order
  would be green. T2 stays first because T6 needs the real file.
- **T4 before T3** fails: `chan_ctl_write` uses T3's `chan_open` and
  `chan_event`.
- **T6 before T4** fails: T6's `holdop` and `stopop` stub actions call
  the T4 verbs.
- **T6 before T5** fails: the `inbox` stub action runs
  `operator-inbox.sh`'s claim.
- **T7 before T6** fails: T7 reuses `holdable`, `hold_wait`, `ctl_take`,
  `ctl_clear`, `op_boundary`, `take_new_stop` and `msgs_left`, which T6
  defines in `studio-overnight`. `overnight-lanes.sh` is sourced from
  there.
- **T8** (studio-brief) is independent. It reads only ledger lines and
  could move anywhere after T1.
- **T9** (SKILL.md) is text with its own test. It could move anywhere. It
  sits after T5 so that its words match the delivery block T5 prints.
- **T10** is independent of T1-T9: the probe uses its own `--settings`
  hooks.
- **T11 before T5** fails: `the code writes message_delivered` goes red
  (no hook yet). **T11 before T3** fails on `message_queued` and
  `control`. Keep T11 last.

Order used: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11.
Every edge above holds.

### Self-review: AC → task

| AC | Task(s) | Pinned by |
|----|---------|-----------|
| 1 | T3 | `test_say_writes_message`, `test_say_dash_text_and_unit`, `test_say_empty_text_exit_2` |
| 2 | T3 | `test_unsay_pending_active_delivered`, `test_unsay_id_prefix` |
| 3 | T3 | `test_said_lists_states` |
| 4 | T3 | `test_verbs_refusals` |
| 4a | T3 | `test_verbs_run_pinning` |
| 5 | T3 | `test_say_cap`, `test_say_cap_counts_characters` |
| 6 | T3, T4 | `test_say_dash_text_and_unit`, `test_single_plan_verbs` |
| 7 | T4, T6, T7 | `test_hold_resume_stop_table`, `test_overnight_hold_story_running`, `test_overnight_hold_last_unit_done_finishes`, `test_lanes_stop_queued_story`, `test_lanes_stop_waiting_story`, `test_lanes_hold_waiting_story_holds_at_start`, `test_lanes_landing_never_holds` |
| 8 | T4 | `test_hold_minutes_zero` |
| 9 | T1, T2, T5, T7 | `test_inbox_hook_registered`, `test_inbox_hook_silent_outside_units`, `test_overnight_unit_env`, `test_lanes_unit_env_run_dir`, `test_inbox_hook_skips_storyless_manifest_unit`, `test_inbox_hook_skips_subagent`, `test_lanes_final_step_no_delivery` |
| 10 | T5 | `test_inbox_session_start_plain`, `test_inbox_post_tool_use_json`, `test_inbox_claim_moves_to_delivered`, `test_inbox_one_claim_under_two_hooks` |
| 11 | T5 | `test_inbox_compact_reshows` |
| 12 | T5, T9 | `test_inbox_escapes_quotes_dollar_backticks_newlines`, `test_execute_operator_messages` |
| 13 | T6 | `test_overnight_requeue_then_hold`, `test_overnight_recorded_directive_stays_delivered`, `test_overnight_requeue_id_prefix`, `test_overnight_requeue_minimal_path` |
| 14 | T6, T7 | `test_overnight_requeue_then_hold` (hold and report), `test_overnight_requeue_done_no_hold`, `test_overnight_prestop_and_limit_end_at_once`, `test_lanes_held_dependents_wait` (lanes report) |
| 15 | T8 | `test_brief_directives_task`, `test_brief_directives_final`, `test_brief_directive_text_not_ruling`, `test_brief_no_directives_no_part` |
| 16 | T1, T5 | `test_inbox_hook_silent_outside_units`, `test_inbox_hook_never_fails`; the T1 cost measure (M2) |
| 17 | T6, T7 | `test_overnight_hold_on_feature_stop`, `test_overnight_new_stop_holds_again`, `test_lanes_held_dependents_wait`, `test_lanes_gate_repair_noprog_holds` |
| 18 | T6, T7 | `test_overnight_start_ledger_stop_ends_at_once`, `test_overnight_prestop_and_limit_end_at_once`, `test_lanes_landing_never_holds` |
| 19 | T6, T7 | `test_overnight_hold_on_feature_stop` (`control/-.held`), `test_lanes_held_dependents_wait` |
| 20 | T6, T7 | `test_overnight_resume_runs_next_unit`, `test_lanes_resume_after_gate_red_runs_gate_repair`, `test_lanes_resume_gate_repairs_counted`, `test_lanes_resume_not_gate_red_no_repair_unit`, `test_lanes_gate_repair_noprog_holds` |
| 21 | T4 | `test_resume_refused_dirty_ledger`, `test_resume_from_feature_worktree` |
| 22 | T6 | `test_overnight_stop_beats_resume`, `test_overnight_resume_wins_at_deadline` |
| 23 | T6, T7 | `test_overnight_stop_story_running`, `test_lanes_stop_running_story`, `test_lanes_hold_running_then_resume` |
| 24 | T6, T7 | `test_overnight_hold_deadline`, `test_lanes_deadline` |
| 25 | T6, T7 | `test_overnight_run_stop_while_held`, `test_lanes_run_stop_held_was_held` |
| 26 | T2, T6 | the unchanged existing suites under the T2 exports; `test_overnight_hold_minutes_zero_ends_at_once` |
| 27 | T6, T7 | `test_overnight_hold_on_feature_stop` (the status line), `test_lanes_held_dependents_wait` (the lanes status line) |
| 28 | T1, T2 | `test_event_line_shape`, `test_event_escaping`, `test_event_cut_500`, `test_event_utf8_cut`, `test_event_line_cap_4k`, `test_event_numbers_null_arrays`, `test_overnight_events_two_units`, `test_lanes_story_listed_events` |
| 29 | T1, T3, T5 | `test_event_usage`, `test_event_minimal_path`, `test_inbox_hook_never_fails` |
| 30 | T11 | `test_events_contract_doc` |
| 31 | T10 | `test_inbox_probe_usage`, `test_inbox_probe_fake_launcher`, `test_doctor_hook_probe_line`; M1 |

Spec sections with no AC number:
- the lock paragraph (L375-378): T3 `test_inbox_lock_stale_broken`,
  `test_inbox_lock_busy`;
- the id rule (L370-373): `test_say_ids_ledger_and_inbox`;
- Teaching (L83-87): T11 (the help and README assertions);
- the config rows (L453-463): T2 `test_overnight_hold_config_refused`,
  `test_overnight_channel_file`;
- the milestone gate: criterion 1 (every task, T2's exports), criterion 2
  (T10, M1), criterion 3 (M3).

Every AC has a task and a pinning test. No gap was found that needs a new
task.

### Placeholder scan

`grep -nE 'TBD|TODO|implement later|fill in|similar to Task|appropriate error'`
over the assembled plan finds no plan placeholders. Every match, if any,
is quoted test text.

Name consistency was checked across T2-T8 with `grep -c` on the assembled
plan. Each name is defined once and used with the same spelling:
- `take_new_stop`, `hold_record`, `op_boundary`, `holdable`, `hold_wait`;
- `ctl_take`, `ctl_clear`, `msgs_left`, `held_line`, `halt_reason`;
- `last_stop_gate_red`, `story_gate_loop`, `requeue_check`;
- `run_event`, `state_event`, `chan_event`;
- `chan_open`, `chan_ctl_write`, `inbox_lock`, `inbox_unlock`;
- `msg_get`, `msg_body`.

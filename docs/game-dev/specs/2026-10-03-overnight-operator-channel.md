# Overnight operator channel — Spec

Date: 2026-10-03
Status: Approved 2026-10-03 (revision 3: falsifier pass 1 C1–C2, I1–I7, M1–M11 and pass 2 N1–N6, N-m1–N-m10 folded in)
Milestone: Plan 3 — Content (studio tooling; follows overnight lanes, #19, and gate repair, #23)
Classification: architectural

Issue: #27. Consumer: #28 (`integrations/multica/`, designed after this spec is
approved). Related: #25 (background `Agent` dispatch in `-p` units).

Today an overnight run can be watched (`status`, `watch`) and ended (`stop`),
but nothing can talk to it. When a stop rule fires, the run ends; the operator
opens a separate session, fixes the problem, and starts the run again. This
spec gives a live run a tool-neutral command channel — messages, hold, resume —
and a machine-readable event log, so any front end (the terminal now, the
Multica bridge in #28 later) can monitor and steer it. The core gains no
dependency on any outside tool.

## Milestone gate

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

## Purpose

- Talk to a live run the way one talks to a Claude session: give an
  instruction, retire it, hold a story, resume it.
- Make a stop rule a pause, not an ending, so one blocked story no longer costs
  the night and a code-level fix no longer needs a restart.
- Expose run state as a stable event log, so outside tools read facts instead
  of parsing `status` text.

What a hold can and cannot fix: anything fixable in the story's feature
checkout (code, tests, assets, a commit the operator makes there) is picked up
on `resume`. A change to the approved spec or plan is not: lane units read
those at the run's pinned docs revision (`STUDIO_DOCS_REV`), so plan or spec
changes still need `stop <story>` and a restart.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Added: `studio-overnight say <story> [--unit] '<text>'`, `said <story>`,
  `unsay <story> <id>`, `hold <story>`, `resume <story>`, `stop <story>`.
  All take an optional `--run <name>`. In single-plan mode `<story>` is `-`.
  `stop` without a story is unchanged.
- Changed: a stop rule holds the story (state `held`) instead of ending it,
  when `hold_minutes > 0` (the default, 480).
- Added for tools: `events.jsonl` in the run dir.

## Design

n/a — studio tooling, no game loop. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A held story waits, spending no tokens, up to `hold_minutes`; then it ends
  exactly as today (`stopped <why> (held <h>h<m>m, no reply)`, same report,
  same resume command).
- Every failure of the new parts degrades to today's behaviour; none of them
  stops a run or a unit (Architecture → Failure handling).

## Teaching

`studio-overnight --help` and the README's "Overnight runs" section gain a part
on talking to a live run: an example of each verb, what a hold can and cannot
fix, and the latency of near-live messages.

## Input and platform

macOS and Linux, POSIX `sh`, as the runner today. No new dependencies.

## Feel targets

- A message to a running unit lands within one main-session tool call; a
  message while the main session waits on a foreground subagent or a long gate
  lands when that call returns (Risks).
- `hold`, `resume`, `stop <story>` take effect within one poll
  (`STUDIO_OVERNIGHT_POLL_SECONDS`, default 5 s) once no unit is running.

## References

- Spike, 2026-10-03, Claude Code 2.1.288, `--model haiku`, `-p
  --output-format stream-json --verbose`, throwaway hooks in the scratchpad:
  1. Hook input carries `agent_id` and `agent_type` only inside a subagent
     (main `Bash`/`Agent` calls: absent; the subagent's `Bash`:
     `agent_id=a3cc…`, `agent_type=general-purpose`).
  2. A `PostToolUse` hook's `hookSpecificOutput.additionalContext` reached the
     model in `-p` (it quoted the marker and the tool call it followed).
  3. `SessionStart` plain stdout reached the model in `-p`.
  The Claude Code hooks reference documents all three.
- Falsifier reports, 2026-10-03 (scratchpad `falsifier-27.md`,
  `falsifier-27-pass2.md`): pass 1 C1–C2, I1–I7, M1–M11; pass 2 (17 of 20
  resolved, 3 partly) N1–N6, N-m1–N-m10; each folded in below.
- `2026-10-01-overnight-runner.md` (unit loop, stop rules, registry),
  `2026-10-01-overnight-lanes.md` (lanes, story records, chains, landing).

## Acceptance criteria

Verbs

1. `say <story> '<text>'` writes one message file into the run's inbox for
   that story, atomically (temp file, then `mv`), with the next id for the
   story and scope `story`; prints the id; exits 0. `--unit` gives scope
   `unit`.
2. `unsay <story> <id>`: for a pending (not yet delivered) message, removes it
   from the inbox; for an active directive (ledgered) or a delivered message
   not yet recorded, queues a message of scope `retire` with `target: <id>`.
   An unknown or already retired id exits 1.
3. `said <story>` lists the story's directives — active (in the feature
   ledger), pending (in the inbox), delivered-not-yet-recorded, and pending
   retirement — one per line with id, state and text.
4. Every new verb exits 1 with one line naming the reason when: no live run is
   found; more than one live run is found outside a project and `--run` is
   absent; the story is not in the run; the story's record is an ending
   (`landed`, `stopped …`, `skipped …`). Bad usage exits 2.
5. `say` exits 1 when the story's active, pending and delivered-not-recorded
   `story` text would exceed `directive_chars`; the message lists those
   directives with ids.
6. In single-plan mode the story argument is `-` and is required for the new
   verbs (`stop -` ends the plan's story; bare `stop` ends the run, as today).
7. Verb targets by story record:

   | record | `say`/`unsay` | `hold` | `resume` | `stop <story>` |
   |---|---|---|---|---|
   | `queued`, `waiting` | queued | holds when it would start | exit 1 | `stopped by operator` when its lane reaches it, chain skipped |
   | `running`, `gate-repair` | queued | at the next unit boundary | exit 1 | after the running unit |
   | `held` | queued (delivered after resume) | exit 1 (already held) | resumes | stopped within one poll |
   | `landing`, `repair` (land repair) | queued (a land repair unit may still read it) | exit 1 | exit 1 | exit 1 (landing holds the land lock) |

   The verbs never write a story record: `hold` and `stop` write only
   `control/<id>.hold|.stop`. For a `queued` or `waiting` story, `run_chain`
   checks `.stop` and `.hold` before `run_story`, and `wait_deps` checks them
   on each poll; the lane then writes the record. `hold` during a story's last
   unit takes effect at that unit's end only if the story would continue; a
   story that finishes `done` lands. Single-plan mode has only `running` and
   `held` (from `control/-.held`).
8. With `hold_minutes 0`, `hold` and `resume` exit 1 ("holds are off:
   hold_minutes 0"); `say`, `unsay`, `said` and `stop <story>` work.

Delivery

9. A new studio hook, `hooks/operator-inbox.sh`, is registered for
   `SessionStart` (matcher `startup|compact`) and `PostToolUse` (matcher `*`).
   It exits at once, printing nothing and reading no stdin, unless
   `STUDIO_UNIT_TAG` and `STUDIO_RUN_DIR` are both set. It also does nothing in
   a manifest run's unit with no `STUDIO_STORY` (the final step), and, under
   `PostToolUse`, when the input has an `agent_id`.
10. On `startup` and `PostToolUse` it claims each pending message for the
    unit's story (`STUDIO_STORY`, or `-` in single-plan mode), oldest first, by
    `mv` into `inbox/<story>/delivered/<unit tag>/` (a message lost to a
    concurrent claim is skipped), and delivers the claimed messages in one
    block: `SessionStart` as plain stdout; `PostToolUse` as
    `hookSpecificOutput.additionalContext`. Each claim writes a
    `message_delivered` event.
11. On `compact` it re-shows, as a reminder, every message already claimed by
    this unit tag (both scopes), without claiming anything new; a compaction
    therefore loses no instruction mid-unit.
12. The delivery block (Architecture → Delivery block) tells the session, per
    scope: `story` — follow it for the rest of the story, and record it in the
    **feature checkout's** ledger, single-quoted:
    `studio-state ledger 'Directive <id>: <text>'`; `unit` — follow it in this
    unit only, do not record it; `retire` — stop following directive
    `<target>` and record `studio-state ledger 'Directive <target> retired'`
    the same way. The recording point is fixed per unit kind, because earlier
    points are overwritten or abort a merge:
    - §0 units: after §0 step (c) — single-plan, after the `base <branch>`
      line (never before the fast-forward, SKILL.md:141); lane, after the
      `docs(<id>): …` docs-sync commit and the `base origin/<Target>` line
      (the docs sync replaces the story ledger, SKILL.md:84).
    - §9 (`--land`) and §11 (`--gate-repair`) units: after their "Enter the
      feature checkout" step.
    A message that arrives earlier is remembered and recorded at that point.
    The line is committed with the unit's next ledger commit and pushed only
    when that commit is pushed (red stops push nothing). A line recorded
    after the unit's last ledger commit is committed in a
    `chore(studio): ledger` commit before the unit ends, pushed under the same
    rule.
13. After every unit, the runner checks each `story` and `retire` message in
    `delivered/<that unit's tag>/` against the story's **feature-checkout**
    ledger (a line starting `Directive <id>:` or `Directive <target>
    retired`). A message with no match is moved back to pending with its
    `requeues:` header incremented (a `message_requeued` event) and is
    delivered to the next unit. The runner writes no studio state.
14. A message requeued `retries + 1` times holds the story with
    `why: directive <id> not recorded`, except: with `hold_minutes 0`, in the
    landing phase, or when the unit's outcome is `done` (the story shipped),
    the message stays pending, the story goes on (and lands), and the report
    lists the message. Pending and delivered messages of a story that ends are
    left in the run dir and listed in the report.
15. `studio-brief task <n>` and `studio-brief final` print the story's active
    directives — each feature-ledger line starting `Directive <id>:` with no
    later `Directive <id> retired` — as a ledger part,
    `==> <ledger path>` followed by those lines, placed before `diff:` in
    `final`. None: the part is omitted. The existing `Ruling: ` and
    `minor (deferred)` match in `final` is anchored to the ledger line's
    prefix, `^- [0-9-]+ ((T[0-9]+|Task [0-9]+:) )?(Ruling: |minor \(deferred\))`
    (widening `write_report`'s precedent, studio-overnight:690), so directive
    text never reads as a ruling.
16. Outside an overnight unit every interactive `claude-gd` session behaves as
    today.

Hold

17. With `hold_minutes > 0`, these endings, reached in the story's unit or
    gate-repair phase after isolation, hold the story instead of ending it: a
    new ledger `Stop:` line in the feature ledger; `no progress on …`;
    `timed out on …`; `held by operator`; `directive <id> not recorded`; and,
    in lanes only (single-plan mode has no gate repair), `gate red after <n>
    repairs — …` (and `stop: gate red — …` with `gate_repairs 0`),
    `gate repair made no progress`, `gate repair timed out`. "After
    isolation" is what the runner can see: `feature_dir` resolves to a
    checkout other than START_DIR and the new `Stop:` came from that
    checkout's ledger (`snapshot` records each Stop line's source ledger).
18. These still end at once, as today: `stopped by user`, `stop: run budget`,
    `stop: unexpected stage …`, `lane crashed`, and every `lane_halt_reason`
    text (the stop file's own reason, e.g. `stop: runner error`,
    `stop: terminal closed`, and `stop: runner gone`); a `Stop:` written
    before isolation (in the start checkout's ledger); and every landing-phase
    ending — a land repair's `Stop:`, `repair made no progress`,
    `repair timed out`, `landing failed (…)`, `landing failed after repair
    (…)` — because landing holds the land lock. When one unit yields both an
    end-at-once ending and a holdable one, it ends at once.
19. A held story's record is `held <why> until <ISO-8601 UTC>`. `held` is not
    an ending: stories that depend on it keep `waiting`, and other lanes run
    on. The lane polls every `STUDIO_OVERNIGHT_POLL_SECONDS`; no session runs.
    In single-plan mode the same line is kept in `control/-.held`.
20. `resume <story>` on a held story: the unit loop continues with the next
    unit number, and the story's post-loop handling runs again (a new stop
    holds again). Lanes only: when the story's latest feature-ledger `Stop:`
    is `gate red — …` (§11's precondition, SKILL.md:729-731), the first unit
    after `resume` is one more gate-repair unit (it reads the operator's
    messages), then the loop as today. A hold from a gate-repair-phase ending
    whose latest Stop is not `gate red` (e.g. `Stop: gate repair red`, no
    progress, timed out) resumes into the loop; its finish may go red and hold
    again, and that resume then gets the repair unit. Gate repairs already
    spent stay spent; `<n>` in `gate red after <n> repairs` counts every
    repair unit, the resume-granted ones included.
21. `resume` exits 1, naming the file, when the story's start-checkout ledger
    has uncommitted changes (a restart would be refused for the same reason).
22. Precedence within one poll: `.stop` over `.resume`; both over the
    deadline. A control file is removed when acted on; control files left when
    a story ends are removed then.
23. `stop <story>` on a held story ends it `stopped <why>`; on a running one,
    `stopped by operator` after its unit; the rest of its chain is `skipped`,
    as today.
24. A hold that reaches its deadline ends the story as the same ending would
    today, with `(held <h>h<m>m, no reply)` appended to the reason.
25. `stop` (whole run), a runner that is gone, or any other `lane_halt` ends a
    held story with the halt's reason followed by `(was held: <why>)`. A lane
    that dies while held is swept as today (`stopped: lane crashed (<rc>)`);
    the hold reason is lost there, as any running state is today.
26. `hold_minutes 0`: every ending in AC17 ends at once, exactly as today.
27. `status` shows a held story as
    `held — <why> — until <HH:MM local> — say / resume / stop <id>`, in place
    of the last-unit line `lanes_status_lines` prints for a running story.

Event log

28. The runner, the new verbs and the hook append to `<run dir>/events.jsonl`
    through one helper, `bin/studio-event`. Each line is one JSON object of at
    most 4 KB with `v` (1), `ts` (ISO-8601 UTC), `run` (run dir basename),
    `event`, and the event's fields (Architecture → Events). String fields are
    JSON-escaped and cut to 500 characters. Message text is never written to
    the log.
29. A failure to write the log, or any hook failure, never stops the run or a
    unit; it is noted in `<run dir>/hook.log` (hook, verbs) or on the runner's
    stderr (runner).

Contract and guard

30. `docs/game-dev/overnight-events.md` documents the event schema v1, the
    verbs and their exit codes, the inbox and control file formats, and how a
    tool finds a run (registry entry's `run=` line). It is the contract #28
    builds on. Within v1, fields and enum values may be added, never renamed
    or removed.
31. `tests/probes/hook_delivery_probe.sh` repeats the spike's three checks
    against the installed `claude` and, on a pass, records the Claude Code
    version in `~/.claude-gamedev/probes/hook_delivery`; it is not in
    `run_all.sh` (it spends model calls). `doctor.sh` prints that version, or
    "hook delivery probe not run".

## Architecture

### Before / after

```
before:  runner ── unit (claude-gd -p) ── stop rule ──▶ story ends ──▶ operator restarts
                  status / watch / stop  (read-only, plus end-the-run)

after:   operator ─ say/unsay/hold/resume/stop <story> ─▶ run dir (inbox/, control/)
         unit main session ◀── operator-inbox.sh (SessionStart, PostToolUse) ── inbox/
         unit (feature checkout) ─▶ ledger 'Directive <id>: …' ─▶ studio-brief ─▶ later units
         stop rule ──▶ story held ──(resume | say+resume | stop | deadline)──▶ …
         runner, verbs, hook ─▶ events.jsonl ─▶ status, #28 bridge, any tool
```

### Files

| File | Change |
|---|---|
| `studios/game-dev/bin/studio-overnight` | verbs `say`, `said`, `unsay`, `hold`, `resume`, `stop <story>`; `--run`; hold loop for single-plan mode (`control/-.held`); export `STUDIO_RUN_DIR` in `start_session` beside `STUDIO_UNIT_TAG` (not in `LAUNCH_ENV`, so the dry-run launch line is unchanged); requeue check after each unit; `snapshot` records each Stop line's source ledger; events; `hold_minutes`, `directive_chars` config and the `STUDIO_OVERNIGHT_HOLD_MINUTES` / `STUDIO_OVERNIGHT_HOLD_SECONDS` test overrides; `status` held line; help text |
| `studios/game-dev/bin/overnight-lanes.sh` | hold loop in the lane's story runner (unit and gate-repair phases only); `held` record; resume-after-gate-red repair unit; `.stop`/`.hold` checks in `run_chain` (before `run_story`) and `wait_deps` (each poll); held line in `lanes_status_lines`; `is_ending` unchanged; events; story-less final-step units skip delivery |
| `studios/game-dev/bin/studio-event` | new: append one versioned, escaped JSON line |
| `studios/game-dev/bin/studio-brief` | directives ledger part; anchored `Ruling`/`minor (deferred)` match |
| `studios/game-dev/hooks/operator-inbox.sh` | new: claim, deliver, re-show on compact |
| `studios/game-dev/hooks/hooks.json` | register the hook for `SessionStart` (`startup\|compact`) and `PostToolUse` (`*`) |
| `studios/game-dev/skills/execute/SKILL.md` | §0, §7, §8, §9, §11: an operator message is an instruction from the user; record per its scope at the unit kind's recording point (AC12), single-quoted; commit with the unit's next ledger commit, or a closing `chore(studio): ledger` commit; push only what the unit already pushes |
| `docs/game-dev/overnight-events.md` | new: the contract (AC30) |
| `README.md` | "Overnight runs" and the verbs table |
| `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh` | shared setup exports `STUDIO_OVERNIGHT_HOLD_MINUTES=0`; new cases below |
| `tests/hook_test.sh`, `tests/studio_brief_test.sh` | new cases below |
| `tests/probes/hook_delivery_probe.sh` | new: the live guard |
| `doctor.sh` | print the probe's recorded version |

### Run dir layout (additions)

```
<run dir>/
  events.jsonl
  hook.log
  inbox/<story>/                    # single-plan mode: inbox/-/
    .lock/                          # mkdir lock for id assignment
    <id>.msg                        # pending
    delivered/<unit tag>/<id>.msg   # claimed by that unit
  control/<story>.hold | .resume | .stop | .held (single-plan only)
```

### Message file

```
id: 3
scope: story            # story | unit | retire
target: -               # retire only: the directive id it retires
story: S2
queued: 2026-10-03T21:04:00Z
requeues: 0
--
Use the EventBus autoload, not direct signals, for HUD updates.
```

Ids are per story: one more than the highest id among the story's
feature-ledger `Directive` lines and its inbox (pending and delivered),
assigned under the inbox's `mkdir` lock. They stay unique across runs because
the ledger carries them forward.

### Delivery block (what the session reads)

```
OPERATOR MESSAGES — from the user, for story S2 (overnight run).
[3, story] Use the EventBus autoload, not direct signals, for HUD updates.
  → Follow this for the rest of the story. Record it in the feature checkout's
    ledger at your recording point — after §0 step (c), not merely after
    EnterWorktree; in a --land or --gate-repair unit, after entering the
    feature checkout — single-quoted, and commit it with your next ledger
    commit (push only what you would push anyway):
    studio-state ledger 'Directive 3: Use the EventBus autoload, not direct signals, for HUD updates.'
[4, unit] Skip the optional polish step in this task.
  → Follow this in this unit only. Do not record it.
[retire 1]
  → Stop following directive 1. Record, the same way:
    studio-state ledger 'Directive 1 retired'
If a message conflicts with the approved plan or spec, follow it for how you
work; for what you build, record a `Stop:` with the conflict instead.
```

The hook escapes a single quote in the text as `'\''` in the suggested
command. The last rule keeps scope changes out of a running unit: messages
steer the work; changing what is built still goes through a stop and the
operator.

### Hold state machine (per story)

```
running ──unit or gate-repair phase ends──▶ ENDING
   holdable(ENDING) and hold_minutes > 0 ──▶ held <why> until <t>
       .stop                ──▶ stopped <why>          + chain skipped
       .resume              ──▶ (latest Stop gate red: one gate-repair unit) → running
       run stop / lane_halt ──▶ stopped <halt reason> (was held: <why>)
       now ≥ t              ──▶ stopped <why> (held …, no reply) + chain skipped
   otherwise ──▶ as today (landing → landed | stopped …)
landing ──any ending──▶ as today (never held: the land lock)
```

The hold loop shares `wait_deps`' poll interval. Single-plan mode runs the
same loop around its one `story_units` call, keeping the record in
`control/-.held`; its "chain" is the run.

### Events (schema v1)

| event | fields |
|---|---|
| `run_started` | `mode` (`single`, `integration`, `direct`), `max_lanes`, `hold_minutes` |
| `story_listed` | `story`, `chain`, `depends` (array) — one per story, all written right after `run_started`; together they are the queue |
| `story_state` | `story`, `state` (`queued`, `waiting`, `running`, `repair`, `gate-repair`, `held`, `landing`, `landed`, `stopped`, `skipped`), `why` (held, stopped, skipped), `until` (held) |
| `unit_started` | `story`, `unit`, `label`, `model` |
| `unit_ended` | `story`, `unit`, `label`, `outcome` (`progress`, `done`, `stop`, `noprog`, `timed out`; `orphaned` once #25 lands), `usd` |
| `message_queued` | `story`, `id`, `scope` |
| `message_delivered` | `story`, `id`, `scope`, `unit`, `via` (`session_start`, `tool_call`) |
| `message_requeued` | `story`, `id`, `unit`, `requeues` |
| `control` | `story`, `action` (`hold`, `resume`, `stop`) |
| `run_ended` | `ending`, `report` |

Single-plan mode uses `story: "-"`.

### Failure handling

- **Hook:** any error → print nothing, exit 0, one line to `hook.log`. A
  claimed `story`/`retire` message that the session never records is requeued
  by the runner (AC13), so a lost delivery becomes a next-unit delivery. A
  `unit` message lost to a killed session is lost (it was for that unit only).
- **Verbs:** writes are temp-then-`mv`; a verb that fails leaves no partial
  message or control file.
- **Event log:** best-effort; never fatal (AC29).
- **Runner killed while a story is held:** manifest runs — the existing
  dead-run sweep writes the report and `status` shows the resume command, as
  today. Single-plan runs — as today, `status` reports a run with no report;
  `control/-.held` names the hold.

### `overnight` config additions

| key | default | range | meaning |
|---|---|---|---|
| `hold_minutes` | 480 | 0–1440 | how long a held story waits; 0 = today's behaviour |
| `directive_chars` | 4000 | 500–16000 | cap on a story's active + pending directive text |

Test-only: `STUDIO_OVERNIGHT_HOLD_MINUTES` overrides `hold_minutes` (the
existing suites set it to 0); `STUDIO_OVERNIGHT_HOLD_SECONDS` replaces
`hold_minutes × 60` when set, so hold deadlines run in seconds in the suites.

### Rejected alternatives

- **Live input stream (`--input-format stream-json`)** — closest to typing into
  a session, two-way, can interrupt; rejected for this story as higher risk in
  the runner's launch path (the user chose the hook route). It remains the
  upgrade path for replies and interrupts.
- **Messages to whichever agent calls a tool next** — a subagent could act on
  a story-wide instruction without the main session knowing.
- **The runner writes `Directive` lines itself** — breaks the rule that only
  sessions write studio state; the requeue check keeps the guarantee instead.
- **Holding landing-phase endings** — the land lock would block every other
  lane's landing.
- **Parsing `status` text for tools** — breaks on any wording change.
- **An `on hold` notify command** — deferred; it can read the same events later.
- **Holding the whole run on a stop** — wastes the other lanes' night.

## Tuning knobs

`hold_minutes`, `directive_chars`, `STUDIO_OVERNIGHT_POLL_SECONDS` (existing).

## Assets and audio

n/a.

## Test strategy

- Unit (`tests/run_all.sh`), with the existing stub `claude` and fixtures:
  - `overnight_test.sh`: each verb's success and every refusal (AC1–8),
    including the verb-target table; id assignment under the lock; the cap;
    `unsay` of pending vs active; single-plan `-`; hold on a feature-ledger
    `Stop:` line, a pre-isolation `Stop:` ending at once; `resume` runs the
    next unit; `resume` refused on a dirty start ledger; `stop -` ends it; the
    deadline ends it (`STUDIO_OVERNIGHT_HOLD_SECONDS`); `.stop` beats
    `.resume`; `hold_minutes 0` refuses `hold`/`resume`; requeue of an
    unrecorded directive with the `requeues:` header, the hold after
    `retries + 1` requeues, and no hold when that unit's outcome is `done`;
    a pre-isolation `Stop:` plus a requeue limit in one unit ends at once;
    `unsay` of a delivered-not-recorded message; the `status` held line;
    events for a two-unit run in order.
  - `overnight_lanes_test.sh`: a held story's dependents stay `waiting` while
    an independent lane lands; `resume` then landing; resume after a gate-red
    hold runs one gate-repair unit first (only when the latest Stop is
    `gate red`); landing-phase endings never hold, and `hold`/`stop` on a
    `landing` or `repair` story exit 1; `stop <story>` on a `queued` story is
    applied by `run_chain` and on a `waiting` one by `wait_deps`, the verb
    writing no record; `stop <story>` skips its chain; whole-run `stop` with a
    held story ends it `(was held: …)`; the held `status` line replaces the
    last-unit line; the final step's units get no delivery; `story_listed`
    events.
  - `hook_test.sh`: fixture inputs with and without `agent_id`; nothing
    without `STUDIO_UNIT_TAG`/`STUDIO_RUN_DIR`; nothing for a story-less
    manifest unit; `SessionStart` stdout and `PostToolUse` JSON shapes; claim
    into `delivered/<tag>/`; one claim under two concurrent hook runs; the
    `compact` re-show; escaping of quotes, `$`, backticks and newlines.
  - `studio_brief_test.sh`: active, retired and absent directives in `task`
    and `final`; directive text containing `Ruling: ` not read as a ruling.
  - `studio-event`: escaping, the 500-character cut, the 4 KB line cap.
- Probe: `tests/probes/hook_delivery_probe.sh` (AC31).
- Live: the milestone gate's run 3.

## Risks

- **Latency while the main session waits.** A near-live message lands at the
  main session's next tool call. While it waits on a foreground subagent (the
  #25 fix makes every `-p` dispatch foreground) or a long gate, the message
  waits too. Accepted; documented in the README. The live input stream is the
  upgrade if this proves too slow.
- **A held story delays the run's final step.** The integration or progress PR
  waits for every lane, so one hold can defer it by up to `hold_minutes`.
  Accepted: the operator ends the wait with `resume` or `stop <story>`; an
  unattended night still finishes after the deadline.
- **Claude Code changes hook delivery.** Guarded by the probe and `doctor.sh`.
- **The model ignores or mis-records a directive.** Guarded by the requeue
  check and the hold after repeated misses.
- **A held lane occupies a `max_lanes` slot.** With the default (`0`, one lane
  per chain) no effect; with a cap, a queued chain can wait behind a hold.
  Accepted.
- **Hook cost per tool call.** One `sh` spawn per tool call in every
  `claude-gd` session, exiting on its first test outside units. Measured in
  the plan's first task; acceptable under 20 ms.
- **#25 overlap.** #25 adds a `PreToolUse` hook to the same `hooks.json` and an
  `orphaned` outcome; whichever lands second merges the registrations.

## Not doing

- Agent replies back to the operator (one-way by design here).
- Interrupting a running tool call or unit.
- Picking up spec or plan changes on `resume` (they need a restart).
- An `on hold` notify command.
- Any Multica- or tool-specific code (that is #28).
- Changing what a unit builds through a message (that remains a `Stop:` and an
  operator decision).

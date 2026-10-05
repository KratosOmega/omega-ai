# Overnight run events and the operator channel (contract)

How a tool talks to a live `studio-overnight` run and reads what it does.
Story #27 defines it; #28 (the Multica bridge) builds on it. Spec:
`docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`.

## Finding a run

- Inside a project, the live run is the one holding the project's lock
  (`.studio/overnight.lock`: `pid=`, `run=`, `started=`).
- From anywhere, the user-level registry `~/.claude-gamedev/runs/` holds one
  file per run whose runner started, `<run name>-<pid>` (the run name starts
  `overnight-`). A run is live only while its `pid` is alive and is a
  studio-overnight; a runner killed with SIGKILL leaves its entry. The lines:

  ```
  root=<project root>
  start=<start checkout>
  run=<run dir>
  pid=<runner pid>
  started=<ISO-8601 UTC>
  ```

  An entry may also hold `origin=<value>` after `started=`, copied from
  `STUDIO_RUN_ORIGIN` at start (AC1a of #28: 1–200 characters of
  A-Z a-z 0-9 . _ : -, else left out with a warning); it stays when the entry
  moves to `runs/last`; the core never interprets it.

  The run dir's basename is the run's name; every verb's `--run <run>` takes
  it. `last` is the newest ended run (it also has `ended=`) and is never live.
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
- Fields marked (number) are JSON numbers, or `null` when the runner does not
  know the value (for example a unit's `usd`). Single-plan runs use
  `"story":"-"`; the final step's units do too.
- Optional fields: `why` appears only for `held`, `stopped` and `skipped`;
  `until` only for `held`. `story_synced` carries either `refs` and `sha`,
  or `skipped`, or `failed`. No other field is optional, except that a line
  carrying `"cut":true` may be missing any trailing field, so a reader
  tolerates that.
- `why` is free display text taken from the story's record. Never match on
  it, and never treat the examples as an enum: `by operator` (an operator
  stop, in lanes and single-plan runs alike), `held by operator` (an operator
  hold), the halt's text such as `stopped by user`, or the stop rule's own
  text (for example `stop: need art`), possibly
  followed by ` (was held: …)`. To detect an operator stop, read the
  `control` event (action `stop`) and the story's next terminal `story_state`.
- A failed write never stops the run. Verbs and the hook note it in
  `<run dir>/hook.log`; the runner notes it on its stderr.

| event | fields | values and notes |
|---|---|---|
| `run_started` | `mode`, `max_lanes`, `hold_minutes` | `mode`: `single`, `integration`, `direct`; `max_lanes` and `hold_minutes` are numbers |
| `story_listed` | `story`, `chain`, `depends` | `chain` is a number; `depends` is an array of story ids; one per story, right after `run_started`; together they are the queue |
| `story_state` | `story`, `state`, `why`, `until` | `state`: `queued`, `waiting`, `running`, `repair`, `gate-repair`, `sync-repair`, `held`, `landing`, `landed`, `stopped`, `skipped`; `why` only for held, stopped, skipped; `until` only for held (ISO-8601 UTC) |
| `story_synced` | `story`, `refs`, `sha`, `skipped`, `failed` | merged: `refs` (array, in merge order) and `sha` (the new head); `skipped`: `no-worktree`, `dirty`, `ahead`; `failed`: `fetch`, `merge-tree`, `merge`, `push`; no event when every ref is already merged; a merged line comes before a later `failed` one |
| `unit_started` | `story`, `unit`, `label`, `model` | `unit` is the unit tag; `label` is for example `repair`, without the story id |
| `unit_ended` | `story`, `unit`, `label`, `outcome`, `usd` | `outcome`: `progress`, `done`, `stop`, `noprog`, `timed out`, `orphaned`; `usd` is a number or `null` |
| `session_wait` | `lane`, `story`, `since` | `lane` is the lane number or `final`; `story` is `-` for a final-step unit; `since` is ISO-8601 UTC; once per wait, when the first slot request fails; the unit's own `unit_started` follows when it gets a slot |
| `message_queued` | `story`, `id`, `scope` | `id` is a number; `scope`: `story`, `unit`, `retire` |
| `message_delivered` | `story`, `id`, `scope`, `unit`, `via` | `via`: `session_start`, `tool_call`; a compact re-show of a delivered message is not logged |
| `message_requeued` | `story`, `id`, `unit`, `requeues` | `id` and `requeues` are numbers |
| `control` | `story`, `action` | `action`: `hold`, `resume`, `stop`; the request, written by the verb |
| `run_ended` | `ending`, `report` | `report` is the path of `report.md`; `ending` is `done` or free text |

## Lifecycle and ordering

- **Order is file order only.** `ts` has one-second resolution, so equal
  stamps are common. The runner, the lanes, the verbs and the hook append
  concurrently; each line is one append of at most 4096 bytes, so lines
  interleave but never mix. Only one story's events are causally ordered. A
  verb's `message_queued` or `control` can precede `run_started`.
- **`run_ended` may never come.** Single-plan: a runner killed with SIGKILL
  writes none. Manifest runs: the next `start` reaps the dead run, appending
  `story_state` lines and a final `run_ended` (ending `stop: runner gone`) to
  the dead run's log, possibly hours later, from another process. A consumer
  decides a run is over when the registry `pid` is dead, not by waiting for
  `run_ended`.
- **`ending`**: `done` is the only success value; anything else is free text
  (do not match on it).
- **Single-plan stories**: the one story `-` starts at `running` (never
  `queued`) and never gets `landed`; `run_ended` with ending `done` is its
  only success signal. Lanes: each story gets one `story_state` right after
  the listing (`queued`, or `landed` for a resumed run).
- **Message ids** are unique per story only while a message exists: the id of
  the newest pending message is reused after `unsay` removes it (#27 R11).
  Key on the event's position in the file, not on `id`.

## Verbs

`studio-overnight <verb> …`; `<story>` is `-` in a single-plan run. Every verb
takes `--run <run>` anywhere before `--`: it then acts only on that live run
and otherwise exits 1 with `run <name> is not live` — never another run.

| verb | does | stdout on 0 |
|---|---|---|
| `say <story> [--unit] '<text>'` or `say <story> [--unit] -- <text>` | queues a message (scope `story`, or `unit` with `--unit`); text after `--` is every word joined by spaces | the message id |
| `said <story>` | lists directives: `<id>  <state>  <text>`, state `active`, `pending`, `pending (unit)`, `delivered`, `retiring` | the list, or `(no directives)` |
| `unsay <story> <id>` | removes a pending message, or queues a `retire` for an active or delivered one | `removed message <id> …` or `retire queued: …` |
| `hold <story>` | `control/<story>.hold` (refused while landing (`landing` or `repair`), when already held, and when `hold_minutes` is 0) | `hold requested: …` |
| `resume <story>` | `control/<story>.resume` (refused while the start checkout's ledger is dirty, when the story is not held, and when `hold_minutes` is 0) | `resume requested: …` |
| `stop <story>` | `control/<story>.stop` (refused while landing (`landing` or `repair`)) | `stop requested: …` |
| `stop [--run <run>]` | ends the whole run after its running unit, as before | `stop requested: …` |

Exit codes (every verb):

| code | meaning | output |
|---|---|---|
| 0 | done | stdout |
| 1 | refused (no live run, two live runs and no `--run`, unknown story, an ended story, the directive cap, holds off, inbox busy, …) | one stderr line naming the reason (the cap lists the directives) |
| 2 | usage (bad options, empty text) | the usage text, or `say: empty text`, on stderr |

`studio-overnight deny-rules [--dir <path>]` prints the deny rules a unit
would get for the project at `<path>` (default: here), one per line, to
stdout; notes for a placeholder with no value go to stderr. It reads no run
state; it is not a run verb and takes no `--run`. Exit 0; 1 for a missing or
rule-less deny file; 2 for usage (an unknown argument, `--dir` without a
value, a `--dir` that is not a directory).

Exception: bare `stop` without `--run` keeps today's output (R27): stdout,
exit 0 or 1, so its `no run in …` refusal is on stdout. Use `stop --run <run>`
for the stderr form.

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
  `Directive` lines and the inbox, assigned under `.lock/`. A lock
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

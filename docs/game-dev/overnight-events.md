# Overnight run events and the operator channel (contract)

How a tool talks to a live `studio-overnight` run and reads what it does.
Story #27 defines it; #28 (the Multica bridge) builds on it. Spec:
`docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`.

## Finding a run

- Inside a project, the live run is the one holding the project's lock
  (`.studio/overnight.lock`: `pid=`, `run=`, `started=`).
- From anywhere, the user-level registry `~/.claude-gamedev/runs/` holds one
  file per live run, `<run name>-<pid>` (the run name starts `overnight-`),
  with these lines:

  ```
  root=<project root>
  start=<start checkout>
  run=<run dir>
  pid=<runner pid>
  started=<ISO-8601 UTC>
  ```

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
- A failed write never stops the run. Verbs and the hook note it in
  `<run dir>/hook.log`; the runner notes it on its stderr.

| event | fields |
|---|---|
| `run_started` | `mode` (`single`, `integration`, `direct`), `max_lanes` (number), `hold_minutes` (number) |
| `story_listed` | `story`, `chain` (number), `depends` (array of story ids) — one per story, right after `run_started`; together they are the queue |
| `story_state` | `story`, `state` (`queued`, `waiting`, `running`, `repair`, `gate-repair`, `held`, `landing`, `landed`, `stopped`, `skipped`), `why` (held, stopped, skipped: the reason text, for example `by operator`), `until` (held: ISO-8601 UTC) |
| `unit_started` | `story`, `unit` (the unit tag), `label` (for example `repair`, without the story id), `model` |
| `unit_ended` | `story`, `unit`, `label`, `outcome` (`progress`, `done`, `stop`, `noprog`, `timed out`, `orphaned`), `usd` (number or `null`) |
| `message_queued` | `story`, `id` (number), `scope` (`story`, `unit`, `retire`) |
| `message_delivered` | `story`, `id` (number), `scope`, `unit`, `via` (`session_start`, `tool_call`) — a compact re-show of a delivered message is not logged |
| `message_requeued` | `story`, `id` (number), `unit`, `requeues` (number) |
| `control` | `story`, `action` (`hold`, `resume`, `stop`) — the request, written by the verb |
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
| `hold <story>` | `control/<story>.hold` (refused while landing, when already held, and when `hold_minutes` is 0) | `hold requested: …` |
| `resume <story>` | `control/<story>.resume` (refused while the start checkout's ledger is dirty, when the story is not held, and when `hold_minutes` is 0) | `resume requested: …` |
| `stop <story>` | `control/<story>.stop` (refused while landing) | `stop requested: …` |
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

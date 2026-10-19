# A queued kickoff wakes when its run ends — design (issue #72)

## Intent

An overnight run's kickoff issue in Multica (the "request issue") is woken once more when its run
ends, so the kickoff agent can read the report, post the summary, and follow whatever the kickoff
says comes after the run (in phoenix: the PR and `merge.sh`). Today that wake only happens when the
request issue is **assigned** to the agent: Multica wakes an assigned issue's agent when its last
sub-issue closes, and the Run issue is that sub-issue.

A run **queued** behind another is kicked off differently. Its request issue is created
**unassigned** and started by a wakeup rule
(`issue wakeup create <new> --until-issue <prior> --until-issue-state done --agent-id <agent>`),
because assigning an issue starts a run at once. Nobody is assigned, so when its Run issue closes
nobody wakes: no summary, no PR, no merge, and the next run in the queue never starts.
OMEG-92 (phoenix combat-vfx-library, 2026-10-19) hit this and was patched by hand with
`issue wakeup create OMEG-92 --until-issue OMEG-101 --until-issue-state ended --agent-id <omega phoenix>`.

The user asked for this to be automatic for every queued run.

## Decided (by the user)

- **The bridge arms the wake**, not the kickoff agent. When the bridge has a run's Run issue and the
  run's request issue is not agent-assigned, it creates the same rule the user created by hand.
  Rejected alternative 1: the kickoff agent arms it after `start --detach` (needs the agent to wait
  for the Run issue, which the bridge creates up to a poll or five minutes later, and is an
  untestable prompt step). Rejected alternative 2: the agent is assigned at wake time (assigning
  starts a run at once; Multica serializes runs per issue, so it queues a duplicate run behind the
  live one).

## Goals

1. Every run whose request issue is known and not assigned to an agent or squad gets exactly one
   end-of-run wakeup rule on that request issue, for the agent whose task started the run.
2. Never a second wake: no rule if an equivalent one already exists (the OMEG-92 hand rule), none
   on an agent-assigned request issue whose Run issue is its sub-issue (Multica's sub-issue wake
   already covers it), and at most one create per run across bridge restarts.
3. A failure to arm is visible: the operator gets one note on the Run issue with the exact command
   to run by hand.
4. The queue recipe is written down in this repo (the Multica README), and the agent's standing
   instructions cover being woken this way.

## Non-goals

- Queuing itself (creating the "start after <prior> is done" rule). That stays the operator's or
  the planning session's step; this change only documents it.
- Runs started from a terminal with no request issue (top-level Run issue, request `none`): there
  is no kickoff to wake.
- `multica-bridge status` output, and any change to how the bridge mirrors statuses or comments.

## Anti-goals (a failure even if it works)

- A double wake of the kickoff agent on one run end (two PR / merge attempts).
- The bridge commenting on, or changing the status of, a request issue. AC17 of the Multica
  integration ("the request issue is never written") still holds for comments and statuses.

## Design

### Where

In `integrations/multica/bridge/mirror.py`, a new step `ensure_end_wake(ctx, st)` called from
`poll_run` right after `refresh` (and its `if st["retired"]: return`), before `reconcile` and
`apply_events`. After `refresh`, `ctx.rows[st["run_issue"]]` holds the Run issue's row (its `id` and
`parent_issue_id`), which the sub-issue test needs. It runs every poll until the run's state records
an outcome, then is a no-op. A run that ends in its first poll is retired only by
`check_end_or_gone`, which runs after this step, so it still arms. *(Builder's call, from the spec
check: placing it before `refresh` would leave the Run issue's UUID and parent unknown.)*

### When it arms

All of these hold:

- `st["request"]["state"] == "found"` and `st["request"]["issue"]` is set.
- `st["run_issue"]` is set.
- `st` has no recorded end-wake outcome yet (new key, below).
- The request issue, read fresh with `issue get` (its row also gives the request's UUID), is
  **not** agent- or squad-assigned (`is_hands_off(row)` is false) — **or** it is agent-assigned but
  the Run issue is **not** its sub-issue, since then the sub-issue wake cannot fire. "Not its
  sub-issue" = the Run issue row's `parent_issue_id` differs from the request row's `id` (this
  covers both the create fallback in `ensure_run_issue` and a reused top-level Run issue; nothing
  in saved state records which path ran). A member-assigned request issue arms (a member
  assignment wakes no agent).
- No existing rule on the request issue (`issue wakeup list <request>`, enabled **or** already
  fired) has `condition.type == "other_issue"` and a `condition.identifier` equal to the Run issue
  (compare case-insensitively; also match `condition.issue_id` against the Run issue's UUID when
  known), with `condition.state` in `done` or `ended`. Matching any such rule records `skipped`.

It arms even if the Run issue is already closed (a run that ended within one poll): an `ended`
condition that already holds fires on Multica's next check, which is the one wake we want.

### The rule

```
multica issue wakeup create <request> \
  --until-issue <Run issue> --until-issue-state ended \
  --agent-id <agent> --mode once --expires-in 336h \
  --instruction "<text>"
```

- `ended` = done or cancelled, so a stopped run wakes the agent too (it still owes the summary).
- `--agent-id`: the bridge calls the CLI with the user's member token, so the agent is explicit.
  It is the `agent_id` of the row in `issue runs <request>` whose `id` is `st["request"]["task"]`,
  read when arming (one extra read per run). `_confirm` keeps only the identifier and the link
  (which has `agent=`) is deleted once the request resolves, so runs resolved before this change
  carry no stored agent id; reading it at arm time covers them too. If no row matches or it has no
  `agent_id`, record `failed` with the reason (below).
- `336h` (14 days) matches the queue recipe already in use; a run is never that long.
- Instruction text (fixed, no run-specific prose beyond identifiers):
  `The overnight run's Run issue <RUN> has ended. Read its "studio: run ended:" comment and the report
  it names, then do what this issue's description says comes after the run.`

### State

New per-run key `st["end_wake"]`: `None` (not decided yet; also the value for state files written
before this change) or a dict `{"outcome": "armed" | "skipped" | "failed", "why": str, "rule": id?}`.
Saved with `state.save_run` immediately after the create returns (before anything else in the poll),
so a crash after the create cannot repeat it. `new_run_state` initialises it to `None`;
`load_run` has no defaults step, so code reads it with `st.get("end_wake")` (a missing key = `None`).
`tests/test_state.py` asserts the exact key set of a new run state and must gain `end_wake`.

### The AC17 carve-out

`poll_run` adds the request issue to `ctx.cli.forbidden`, and `_guard` refuses every write to it.
The new CLI method `create_wakeup(issue, until_issue, state, agent_id, expires, instruction)` in
`bridge/multica_cli.py` does **not** call `_guard`: a wakeup rule is neither a comment nor a
status, starts no run when created, and is the one write the bridge makes on a request issue.
Its docstring says so and cites this spec. `list_wakeups(issue)` is a read. No other method's
guard changes.

### Errors

- `TransientError` / auth errors: propagate as every other call does (global backoff); nothing is
  recorded, the next poll retries.
- `PermanentError` on `get`, `list` or `create`: record `failed` with the redacted message, log an
  error, `ctx.notify("wake", ...)`, and post one note on the Run issue:
  `studio: could not arm the end-of-run wake on <REQ> (<why>). Arm it by hand: multica issue wakeup
  create <REQ> --until-issue <RUN> --until-issue-state ended --agent-id <AGENT or "<agent id>"> --expires-in 336h`.
  Never retried after that.
- `ForbiddenWrite` cannot occur on `create_wakeup` (no guard).

### Docs

- `integrations/multica/agent-instructions.md`: the wakeup bullet becomes "When you are woken
  because the sub-issues closed or the Run issue ended, …" (rest unchanged).
- `integrations/multica/README.md`: a new section "Queue a run behind another" with the queue
  recipe (create the kickoff unassigned; `issue wakeup create <new> --until-issue <prior>
  --until-issue-state done --agent-id <agent> --expires-in 336h --instruction "…"`; do not assign
  it, which starts it at once), and that the bridge arms the end-of-run wake by itself, so the
  kickoff needs no extra step. Update the "status follows the run" wake sentence and the Known
  risks wake line to cover both kinds of kickoff. This README section is the repo's kickoff
  template for queued runs.
- `docs/game-dev/PROGRESS.md`: one self-contained added entry (another session also edits this
  file; do not reflow surrounding lines).

### Known limits (accepted; README Known risks gets one line each)

- The decision is made once. If an armed request issue is later assigned to the agent, the run's
  end wakes it twice (sub-issue wake + rule); if a skipped (agent-assigned) one is later
  unassigned, nothing wakes it. The queue recipe says never to assign a queued kickoff, and the
  hand fix is one `wakeup delete` / `wakeup create`. Re-checking the assignee every poll would cost
  one `issue get` per run per poll for a case the recipe forbids.
- A queued request issue is found only through the task's workdir name (`issue_from_workdir`):
  the second search, `assigned_issues`, cannot find an unassigned issue. If the workdir match
  misses, the request resolves to `none`, the Run issue goes top level, and nothing arms. This is
  how OMEG-92 resolved today (OMEG-101's parent is OMEG-92), so the path works in practice.
- A runner that dies with no clean end never closes its Run issue, so the rule never fires. That
  is the same as today's sub-issue wake for an assigned kickoff.
- `agent-instructions.md` reaches Multica only when `install.sh` creates the agent; an existing
  agent (omega phoenix) keeps its old instructions until the operator updates them. The rule's own
  `--instruction` text says what to do, so the wake works either way.

## Tests

Bridge pytest (`integrations/multica/tests/test_mirror_runs.py` or a new
`test_mirror_end_wake.py`), driven through `stub-multica`, which learns `issue wakeup list` and
`issue wakeup create` (fixtures shaped from the real 0.6.1 output, redacted):

- unassigned request → one create with exactly the flags above; outcome `armed`; a second poll
  creates nothing.
- agent-assigned request with the Run issue as its sub-issue → no create; outcome `skipped`.
- agent-assigned request, Run issue at top level (fallback) → armed.
- member-assigned request → armed.
- an existing matching rule (enabled; and separately a fired one, `enabled: false`) → no create;
  `skipped`.
- a non-matching rule (other issue, or no condition) → still armed.
- request `none` or `pending` → nothing, outcome stays `None`.
- transient error on create → nothing recorded; next poll arms.
- permanent error → `failed`, one Run-issue note with the hand command, notify called, no retry.
- unknown agent id → `failed` with a note.
- a state file without `end_wake` loads and arms.
- a run that ends (Run issue done) in the same poll that first sees it still arms, then retires.
- the agent id comes from `issue runs <request>` (a run with a matching task id), not the link.
- the existing test at `test_mirror_runs.py` ~197-207 (a found, unassigned request) now also arms:
  update its expectations instead of letting it fail.
- the create is not refused by the AC17 guard; `set_status` / `add_comment` on the request issue
  still are.
- `readme_test.sh`: the new agent-instructions line and the README section heading are present.

## Left to the builder

- Exact placement of the agent id capture in `resolve_request` / `_confirm`.
- Fixture file names and stub-multica internals.
- Whether the tests live in an existing or a new test file.

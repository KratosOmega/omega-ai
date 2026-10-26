# A unit knows its deadline, leaves a checkpoint, and a capped task reaches a person — design

Status: approved 2026-10-26. The six design choices below were approved by the operator in chat.
Source: `prompt_to_run/omega-ai-runner-fix-prompt.md` (defects 1-11), written from phoenix runs
`overnight-bat-bite-vfx-20261024-201549` (story KAN-1723-5, Multica OMEG-131/132) and
`overnight-mob-group-attacks-*` (OMEG-134).
Branch: `fix/overnight-timeout-carryover`, worktree `../omega-ai-wt-timeout`, based on main `cec086a`.
One PR. It is merged and installed only once `studio-overnight status` shows no live run.

## Incident, in numbers (lanes/1/units.tsv of bat-bite-vfx)

| units | task | outcome |
|---|---|---|
| 2, 3 | T2, T2-retry | 90.0 min each, exit 143, `timed out`, usd `unknown` |
| 4 | T2 (after operator `say` + `resume`) | progress in 41 min |
| 5, 6 | T3, T3-retry | timed out, then progress in 7.5 min |
| 15, 16 | T12, T12-retry | timed out; unit 15 had committed a real fix (96dc44ce6) |
| 17-19 | T12 / retry / T12 | `noprog`, exit 0, 31-74 min each |
| 20 | T12-retry | timed out |
| 21 | T12 | progress in 76 min |

T12 took seven units (~8.5 h). Five units have no cost. Phoenix timings (`.studio/gate.times`, main
lane, rc 0): `studio-test` median 4.9 min, p90 5.3, max 10.5; merge gate 8-15 min.

## Why

A headless `claude -p` unit is killed at `session_minutes` with no warning. Whatever it learned dies
with it. The runner judges only what is committed at the kill, so work it did make is scored as
"timed out", and the retry starts cold, with the same cap and no new information. A task too big
for one window can then loop until a person notices. Agent harnesses that run long tasks in fixed
windows need four things, and the runner has none of them today:

1. the agent knows its deadline and is reminded by the harness, not by its own clock-watching;
2. it leaves a durable, structured checkpoint, and the next attempt reads it;
3. objective progress (pushed commits) counts, but self-reported progress does not;
4. repeated capping is a signal the task is mis-sized, so it goes to a person, with the checkpoint.

## Goals

- G1. Every unit kind knows its deadline (`STUDIO_UNIT_DEADLINE`) and its wrap-up time
  (`STUDIO_UNIT_WRAP_AT`), and the harness tells the session when WRAP_AT passes.
- G2. A capped task unit leaves a `T<n> checkpoint:` ledger line plus a commit for each green fix.
  The retry's brief carries the checkpoint. When the unit left none, the runner writes a fallback.
- G3. Pushed task commits made in a unit count as progress, even when the unit was then killed.
- G4. A task is capped at most `overnight.task_timeouts` times (default 2). The next cap holds
  the story with the checkpoint in the hold message and the operator notification.
- G5. A killed unit's spend is recovered from its transcript, marked as an estimate, and counted.
- G6. Directives can be task-scoped and retire on their own. A long directive can come from a file.
- G7. Direct mode runs the project's full gate at finish, so a red goes to the gate repair, not
  to the landing.
- G8. The plan skill splits a task whose verify steps cannot fit one session.
- G9. `start` warns when the runner's own checkout is behind upstream.
- G10. Small fixes: `--help` under `set -u`, the timeout-on-non-gate-commands rule, and the story
  worktree setup test.

## Non-goals and anti-goals

- No runner-made WIP commits. Debug code and half edits never land on a branch by the runner.
- A checkpoint line alone never resets the no-progress counter. A self-report like
  "investigated X" must not loop forever.
- No extended or escalating `session_minutes` on retry. The bound sends the task to a person.
- The runner never pulls, merges or installs its own checkout (G9 only warns).
- No change to live runs: tests use stubs and scratch dirs; nothing is installed until no run is live.
- Back compat: a plain `say` keeps story scope; existing ledgers, units.tsv readers and events stay
  readable.

## Decisions (approved by the operator)

| # | choice | decision |
|---|---|---|
| D1 | checkpoint carrier | Ledger line + a real commit per green fix. No WIP commits. Runner fallback from git and the killed transcript. |
| D2 | what counts as progress | Pushed non-ledger commits made during the unit. A checkpoint line alone does not. |
| D3 | margin | WRAP_AT = DEADLINE − max(10 min, session_minutes / 6): 15 min at 90. |
| D4 | retry bound | `overnight.task_timeouts`, default 2, range 1-5. The 2nd capped unit of one task holds. |
| D5 | directive scope | `say --task [T<n>]`; a plain `say` stays story-scoped. |
| D6 | direct-mode finish | Integration's finish gate in direct mode too, red → gate-repair loop; preflight warns on direct + `merge_command` + no `gate_command`; docs. |
| D7 | Multica bridge | In scope: `/say --task [T<n>] <text>` passes through to `say --task`; the hold hint suggests it; mirrored events show `scope=task`. |

Calls made after the builder check (mine, marked so they can be checked):

- C1. **Which counter a unit feeds.** A capped unit (killed at the cap, or ended after WRAP_AT
  without completing its task) feeds only `task_timeouts`, never `noprog`. A capped `partial` unit
  resets `noprog`. An uncapped unit that ends early with pushed commits but no completed task is
  `noprog` (its commits are carried in the fallback note): ending early is not a sanctioned exit,
  so it must not escape both counters. Every path is bounded: by `task_timeouts` or by `retries`.
- C2. **Which ending wins.** When a capped unit trips `task_timeouts`, the bound's ending (with the
  checkpoint) is used. A `no progress on T<n>` ending also appends the checkpoint when one exists.
- C3. **Cost estimate is calibrated.** Verified on unit 21: stream-json per-message `output_tokens`
  sum to 2,648, while the result's `modelUsage` reports 132,062. The transcript's output counts are
  start-of-message snapshots, not final counts. Input and cache counts are exact. So §6 estimates
  output tokens from content length instead, then calibrates (see §6).
- C4. **What counts as the unit's commits.** HEAD0 is read in the feature checkout after
  `unit_pre`. A unit whose feature checkout did not exist at HEAD0 (the first unit) is never
  `partial`. Counted commits: `git log --no-merges HEAD0..HEAD ^origin/<Target> -- .
  ':!.studio/'`, excluding the docs-sync `docs(<id>):` commit.
- C5. **units.tsv columns.** Column 8 is `cost_src` (`result`|`estimate`), and column 9 is
  `capped` (0|1). The Timed out column keeps its meaning (killed by the watchdog). The bound counts
  `capped` = 1 rows per label base.
- C6. **Subagent fit.** `studio-deadline fits agent` uses a fixed estimate of 20 min
  (`STUDIO_DEADLINE_AGENT_MIN`) unless the caller passes minutes. With no `gate.times` rows,
  `fits <gate>` falls back to `STUDIO_GATE_MINUTES` / 2, not to "fits".

## Design

### 1. Deadline (defect 2) — runner, hook, helper, skill

**Runner.** `run_unit` is the one place every unit kind starts (task, check, final-review, finish,
land repair, gate repair, sync repair, the final unit). It computes, from `_t0` and `_secs`:

- `STUDIO_UNIT_DEADLINE` = `_t0 + _secs` (epoch seconds; the watchdog's kill time);
- `STUDIO_UNIT_WRAP_AT` = DEADLINE − margin, margin = max(600, `_secs` / 6) s, but never more
  than `_secs` / 2, so the `STUDIO_OVERNIGHT_SESSION_SECONDS` test hook still gets a window;
- both are exported into the session's environment the way `STUDIO_UNIT_TAG` is.

They are documented in `studio-overnight --help` (environment section) and SKILL.md §0.

**Hook nudge.** `hooks/operator-inbox.sh` already runs on SessionStart and every PostToolUse, so it
adds a deadline notice. When `STUDIO_UNIT_WRAP_AT` is set and now ≥ WRAP_AT, it injects once per
(unit tag, agent id) a short block: "WRAP-UP: <m> min to the hard stop at <hh:mm>. Do not start a
gate or a subagent. Commit and push green work, write the checkpoint (§8), end the turn." A
subagent gets "return to the orchestrator now with done / left". A second, final notice fires at
DEADLINE − 3 min. The once-only marker lives under the run dir. Today the hook skips subagent calls
(`top_agent_id`) for messages. The deadline notice is the exception, so a running implementer is
told too. The notice is checked before the hook's early exits for the storyless final unit
(operator-inbox.sh:23) and a missing inbox dir (:82), so every unit kind gets it.
*Must verify with a probe* (`tests/probes/`, like `bash_timeout_probe.sh`): that a PostToolUse
`additionalContext` from a subagent's tool call reaches that subagent's context. If it does not,
the brief rule below is the only subagent channel. Record the result in the probe and in SKILL.md.

**Helper.** New `bin/studio-deadline` (plain sh, like the other verbs):
- `studio-deadline` prints `left <m> min · wrap at <hh:mm> (<m> min) · hard stop <hh:mm>`, or
  `no deadline` outside a unit (exit 0 either way);
- `studio-deadline fits <who> [<minutes>]` exits 0 when a run of `<who>` fits before WRAP_AT, and
  1 with a one-line reason when it does not. The estimate is p90 × 1.2 of `<who>`'s rows, read
  through `gate_times_holds`, or `<minutes>` when given. With fewer than 5 rows it uses
  `STUDIO_GATE_MINUTES` / 2. `fits agent` (a subagent dispatch) uses 20 min (C6). `<who>` is the gate's own name (`studio-test`, `setup` for
  `studio-setup gate`, `studio-run`, …). The builder confirms the names against `gate.times`.

**Skill (execute).**
- §0: the deadline rule. Before any gate-routed full run (`studio-test` without `--file`,
  `studio-run`, `studio-setup gate`) and before briefing a subagent, run `studio-deadline fits …`.
  On exit 1, do not start it: checkpoint and end the turn. When the wrap notice arrives, or
  `studio-deadline` shows WRAP_AT passed, checkpoint and end the turn.
- §2: every implementer, fixer and reviewer brief carries the wrap time verbatim ("return by
  <hh:mm> (STUDIO_UNIT_WRAP_AT) with what is done and what is left; never start a command that
  cannot finish by then; `studio-deadline fits <who>` answers that"), as it carries the gate rule.
- §4a and open-ended loops: each fix that passes its owning tests is committed (and pushed under a
  lane) as it lands, never batched to the end of the task.

### 2. Checkpoint and carry-over (defect 1, D1)

**Format.** One ledger line in the feature checkout:
`T<n> checkpoint: done <steps / evidence>; left <steps>; next <first action>`, one line of at most
~600 characters. It names evidence by path or sha (logs, probe outputs) so the retry need not
re-measure. The keyword `checkpoint` is new. It must not reuse `in progress`, which `studio-adopt
sync` reports with a commit-range meaning. A final-review unit writes `final-review checkpoint:
…`. Repair units write a `Stop:` with done/left instead (they have no retry).

**When.** At the wrap notice, after a `fits` refusal, or on any voluntary end that leaves the task
incomplete. Order: commit green fixes, then the ledger line, then the ledger commit
(`chore(studio): checkpoint T<n>`), then push.

**Reading it.** `studio-brief task <n>` prints the newest `T<n> checkpoint:` line written after
the task's start (after the last `T<n-1> complete` or the `base` line) as a `checkpoint:` part.
§8 Inputs, next to the adopt-sync rule: the implementer's brief gets
`previous attempt (checkpoint): <line> — continue from "next"; do not redo "done" steps unless a
file their evidence depends on has changed since`. `studio-brief final` does the same for
`final-review checkpoint:`. A completed task's checkpoints are never printed again (task scope by
construction).

**Runner fallback.** After a task or final-review unit that did not complete its task, the runner
builds a short mechanical note from the feature checkout:
- `git status --short` (uncommitted files, capped at ~20 lines);
- commits since the task started, and those not on origin;
- when this unit wrote no checkpoint line: the killed session's last assistant text from its
  stream-json (cut to ~1500 bytes), labeled "last words of the killed session".

It queues the note as a runner-origin, task-scoped message (see §5) for the next unit. The note
does not count toward `directive_chars` and is not ledgered. A dirty tree is left as is: the
retry's checkout already holds those files.

### 3. Progress (defects 1, 4; D2)

`story_units` takes `HEAD0` (the feature checkout's HEAD) before each unit. After the unit:
- `progress`, as today, when SIG changed;
- else a new outcome `partial` when the unit was capped, its commits (C4) are non-empty and
  `origin_check` passes. It resets `noprog`, writes a units.tsv row and a `unit_ended` event like
  `progress`, and does not change the task pointer. It is decided before `unit_outcome`, so a unit
  that was killed after pushing a fix is `partial`, not `timed out`: T12 unit 15. The Timed out
  column still says 1. An uncapped unit with commits but no completed task is `noprog` (C1).
- else `unit_outcome` as today.
- New commits that are not on origin: not progress. They are named in the fallback note, and the
  next unit pushes them.

### 4. The bound (defect 4; D4)

A unit is **capped** when the watchdog killed it at the cap (`UNIT_TIMED_OUT`), or it ended after
WRAP_AT without completing its label's task. New config `overnight.task_timeouts` (default 2,
1-5; `cfg`, `--help`). Capped units are counted per label base (`T<n>`, `final-review`, …) across
the story within this run, from units.tsv. That count survives `story_units` re-entry after a gate
repair or a resume. When a capped unit brings the count to `task_timeouts`, the story ends
`timed out on T<n> <k> times (session_minutes N) — checkpoint: <line or fallback summary>`.
`holdable` already holds any `timed out on …` ending of an isolated story with holds on
(studio-overnight:1259), so the held `why` carries the checkpoint. From there the
`story_state` held event takes it to the Multica comment (`integrations/multica/bridge/notice.py`)
and the desktop banner (`notify_operator`). The checkpoint is cut to fit the notice. The hold hint
suggests `say <story> --task T<n> -- …` (Multica: `/say --task T<n> …`) then `resume`. After a
`resume`, the next capped unit of the same task holds again at once: `resume` buys exactly one
more attempt. In-place stories and `hold_minutes 0` end instead of holding, as today. Tests that
check the hold turn holds on. The `retries` / no-progress rule runs beside this one with C1's
split of units. C2 says which ending wins.

### 5. Directives: task scope and files (defect 8; D5)

- `say <story> --task [T<n>] …`: message header `scope: task`, `task: T<n>`. Bare `--task` takes
  the story's current task (k+1 from `task k/N`); a story not at a task refuses.
- The unit records it as `Directive <id> T<n>: <text>`. `studio-brief`'s `directives_part`,
  `chan_list`/`said` and the `directive_chars` count treat it as active only while the story's task
  pointer k < n. Once k ≥ n it is retired with no ledger line, is not delivered, not briefed, and
  not counted. `said` shows it as `retired (T<n> done)` until the story ends.
- Runner-origin messages (the §2 fallback) carry `from: runner` and are excluded from the cap.
  They are never ledgered, so `requeue_check` skips them (scope `note`, or `from: runner`).
- Every reader of the `Directive <id>:` pattern accepts the `Directive <id> T<n>:` form:
  `requeue_check` (studio-overnight:~1204-1214), `chan_list` and `chan_next_id`
  (overnight-channel.sh), `directives_part` (studio-brief), and the hook's scope switch
  (operator-inbox.sh:89-95, which today skips any scope but story/unit/retire).
- Multica (D7): `integrations/multica/bridge/commands.py` gains `/say --task [T<n>] <text>`. The
  bridge's hold notice suggests it, and mirrored `message_queued` events show `scope=task`.
  Bridge tests are updated.
- `say --file <path>` and `say … -` (stdin) read the text from a file. The body is stored verbatim
  in the `.msg`. The delivery block prints it verbatim. That means changing both copies of
  `msg_body` (overnight-channel.sh:17 and operator-inbox.sh:37), which today fold newlines.
  *Builder's call (mine)*: the one-line ledger
  record escapes newlines as `\n` and backslashes as `\\`, and `studio-brief` and `said` unescape
  it, so a multi-line handoff survives the round trip. `--file` needs no `$(cat …)`, so a
  worktree-isolated session's guard no longer refuses it.

### 6. Cost of a killed unit (defect 3)

When `cost_of` finds no result event, `cost_estimate` builds a naive cost from the unit's
stream-json. It covers assistant events, the subagent messages in the same stream included
(`parent_tool_use_id`, model per message), deduped by `message.id`:
- input, cache_creation and cache_read tokens come from `usage` (exact);
- output tokens come from the content length (text, thinking and tool_use input, bytes / 4),
  because `usage.output_tokens` in the transcript is a start-of-message snapshot (C3);
- each is multiplied by a per-model price table, a small data file in `bin/`. The builder fills it
  from current Anthropic pricing (load the `claude-api` skill for that). An unknown model uses the
  dearest known model.

Then it calibrates. For each model, the factor is the median of (result cost ÷ naive cost) over
this run's finished units, taken from their `modelUsage`. It needs 3 or more units, else it
uses the project's earlier runs' factor (cached in `.studio/`), else 1. The calibrated sum is the
estimate. With no usage at all, the estimate is the unit's minutes × the run's median $/min.

The cost column stays numeric, so `spent`, `run_budget_out` and the reports keep summing it. A new
8th units.tsv column `cost_src` is `result` or `estimate` (and a 9th, `capped`: C5). `unit_ended` gets `usd_est:=true`, and
`report.md` and the lane reports print `≈$x` for estimated rows. Readers that use only columns 1-7
are unaffected. `unknown` is never written again.

### 7. Direct mode runs the finish gate (defect 9; D6)

- SKILL.md §7 **Direct**: step 1 runs exactly as under **Integration** (`studio-test`, `studio-run`,
  `studio-lint`, `studio-setup gate`, foreground, run once; the same stop lines). A red writes
  `Stop: gate red — …`, which the runner's existing `story_gate_loop` repairs (`gate_repairs`). Then
  step 4 pushes and opens the draft PR as today. The "Direct mode runs no finish gate" sentence goes.
- Preflight (`start`, `--dry-run`, manifest preflight): mode direct, `merge_command` set,
  `gate_command` unset → warning: `direct mode: merge_command's own gate is the first full run —
  set gate_command to that gate minus the merge (e.g. .github/scripts/run-tests.sh) so a red goes
  to a finish repair, not the landing`.
- `--help` and the config docs say the same. Phoenix's config is not edited by this work: that is
  the operator's call, after the live runs end.

### 8. Plan time (defect 5)

`skills/plan/SKILL.md` gains a **fits-the-session** check in its self-review. For each task it
estimates the verify time from `Verify:` and the steps: full-suite runs × the `studio-test` median
from `gate.times`, plus windowed or probe series × their count, plus fix rounds × (re-run cost).
When that is over session_minutes / 2, or the task has an unbounded loop ("until 0", "every
difference", "fix and re-run"), the task is split. The plan says so in the task, and gives a loop
task an explicit bound (max rounds, then a Block or a Stop). T12 is the worked example: the
probe-to-zero loop and the 30-log clean-exit series become two tasks. A pressure or pointer test
checks that the rule is present.

### 9. Stale runner (defect 10)

At `start` and `--dry-run`, the runner resolves its own checkout (`SELF_DIR`, symlinks resolved).
When that is a git work tree with an upstream, it runs `git fetch -q` under a ~15 s timeout and
falls back to the last fetch on failure, saying its age. When `git rev-list HEAD..@{u} --
studios/game-dev` is non-empty it prints `warning: runner checkout <path> is <k> commits behind
<upstream> on studios/game-dev (<newest subject>, …) — update it before starting`. It never pulls.
Not a git checkout (a plugin-cache copy): no check, no message. Test hook: none needed, since a
scratch repo with a bare upstream reproduces it.

### 10. Small items

- Defect 6: `--help` already exits 0. The stray stderr line `line 296: CMD: unbound variable`
  comes from `` `sh -c "$CMD"` `` inside the unquoted usage heredoc (studio-overnight:~551). Escape
  it. The test asserts an empty stderr and exit 0.
- Defect 7: the §2 brief already says "pass `timeout` only on gate-routed commands". Tighten it
  with the why and the T2 counter-example: `timeout: $BASH_MAX_TIMEOUT_MS` on `sh
  tools/exit/exit_probe.sh …` lifts a hung non-gate command past the per-command cap.
  The pointer test checks the line is in the brief template.
- Defect 11: a test that a fresh story worktree with no `.studio/config.json` of its own runs the
  project's `worktree_setup` (via `STUDIO_START_DIR`, #104) and does not skip silently. If it fails,
  fix it.

## Done when (from the source prompt, mapped)

| check | where |
|---|---|
| unit killed at the cap after writing a checkpoint; retry brief contains it (SESSION_SECONDS hook) | overnight_lanes_test.sh |
| unit commits + pushes mid-unit, then killed → `partial`, not `timed out` | overnight_lanes_test.sh |
| `task_timeouts` reached → hold with the checkpoint in the hold message, no further retry | overnight_lanes_test.sh |
| killed unit's spend non-null in units.tsv and events.jsonl, counted in spent/run_usd | overnight_test.sh |
| DEADLINE and WRAP_AT exported to every unit kind; in `--help` and SKILL.md | overnight tests + pointer test |
| `say --task` retires when the task pointer moves; `say --file` round-trips a multi-line file | overnight_test.sh (channel) + studio_brief_test.sh |
| Multica `/say --task` passes through; hold hint names it | integrations/multica bridge tests |
| direct finish runs gate_command; preflight warning | pointer test + overnight_lanes_test.sh |
| runner-behind warning | overnight_test.sh |
| story worktree gets worktree_setup | studio_setup_test.sh / overnight_lanes_test.sh |
| `--help` exits 0 | overnight_test.sh |
| omega_contracts and the existing overnight suites stay green; README and PROGRESS updated | run_all.sh |

## Left to the builder

- The exact gate `who` names for `studio-deadline fits`, and the notice wording.
- The test stubs: the existing fake `claude` stubs in the overnight tests, extended to write a
  checkpoint line, commit, push, or sleep past the cap.
- Whether `partial` is a new outcome word or `progress` with a note. It must stay distinct in
  units.tsv, because the bound and the reports read it.
- Splitting the work into tasks and lanes.

## Risks

- R1. The subagent hook nudge may not reach a subagent (verify by probe; the brief rule remains).
- R2. A unit may ignore WRAP_AT. Then the runner fallback and the bound still hold, so the worst
  case is today's, but now bounded.
- R3. Price-table drift makes estimates wrong. They are marked as estimates, and the table is one
  data file.
- R4. Running the full gate in direct mode adds ~10 min per story in phoenix. Accepted (D6).

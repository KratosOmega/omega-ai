# game-dev Studio — Progress

An evolution log for the game-dev studio in omega-ai. Newest entry first.
Specs live in `specs/`, implementation plans in `plans/`, and the HTML of every
approval page in `artifacts/`.

## Milestones

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | `profiles/` → `studios/`, plugin packaging, shim with `--plugin-dir`, installer/doctor/tests, session hook, `docs/game-dev/`, `.studio/STATE.md`, skills `studio` `brainstorm` `plan` `execute` | delivered — exit criterion (Task 12 manual run) pending |
| 2 — Quality loop | Ten role agents, skills `review` `playtest` `ship` `retro`, `bin/` verbs with the Godot adapter, optional `godot-mcp`, doctor delegation check | delivered — exit criterion (Task 16 manual run) pending |
| 3 — Content | `scaffold` and template project, domain skills (migrate four, add `vertical-slice` `tuning-data` `milestone-gates`), `PROGRESS.md` conventions, `general` studio parity, skill pressure tests | planned |

## Log

### 2026-10-04 — Multica integration (#28)

- A bridge service mirrors live overnight runs onto a Multica board, so a run can
  be watched and steered from a phone browser. It reads the core's public files
  (`events.jsonl` and the run registry) and calls its public verbs; the core never
  names Multica. A "Run" issue (under the request issue that asked for the run) and
  one sub-issue per manifest story carry statuses and `studio: ` comments. The bridge
  stays hands-off on an issue while an agent is assigned and posts one catch-up
  comment afterward.
- The operator posts commands as comments: `/say`, `/unit`, `/hold`, `/resume`,
  `/stop`, `/unsay`, `/said` (and `/stop run`). Only the operator's own comments
  count. The bridge replies in a threaded comment starting with a check mark, a
  cross or a warning sign.
- `integrations/multica/` holds the installer (`install.sh`, `uninstall.sh`), the
  launchd service, the README, and two wrappers: `claude-multica` (mode 2: normal
  `claude` plus the deny list) and `omega-multica-agent` (mode 3: `claude-gd` in the
  project with Multica's context). Install keeps the API token in the Keychain only,
  links `claude-multica`, `omega-multica-agent` and `multica-bridge` into
  `~/.local/bin`, and fails visibly when macOS blocks the bridge from the project's
  files.
- Core changes, all small: `studio-overnight deny-rules` prints the rules for a
  project, and a run's registry entry may carry an `origin=` line (from
  `STUDIO_RUN_ORIGIN`) that ties it to its request issue.
- The final review's fixes landed: one run's failure (a file-access block, a
  malformed row) no longer stops mirroring the others, and a run that keeps failing
  gets one note; a skipped event still sets its status; CLAUDE.md that is a symlink
  or hard link is not copied into the agent context.
- Probe results are in the spec ("References (continued)", items 17-23) and
  D1a-D1g in the plan: P1, P2, P3, P4 and P7 ran and passed. P5 and P6 were not
  run because the projects live outside `~/Documents`, so the plan's defaults are
  in use. Finding from P1: a per-machine `runtime profile set-path` override beats
  the profile's command, and command changes need a daemon restart (Settings,
  Daemon, Restart); README and install now say so.
- The live install check (spec milestone gate step 4) is still open for the
  operator, tracked in #30.

### 2026-10-04 — Overnight operator channel (#27)

- An operator can talk to a live overnight run. `studio-overnight say <story>
  -- <text>` queues a message, `said` lists messages and their states, and
  `unsay` retires one. `hold`, `resume` and `stop <story>` control a story.
  Every verb takes `--run <run>`; outside a project, `--run` is required.
- `hooks/operator-inbox.sh` (SessionStart and PostToolUse) delivers a queued
  message into the running unit's session at its next tool call. A message
  scoped to a story becomes a `Directive <n>:` line in the feature ledger, and
  `studio-brief` prints the story's active directives.
- A no-progress ending, a rule stop after isolation, or the directive cap now
  holds the story for up to `hold_minutes` (default 480) instead of ending it.
  The held line reads `held <why> until <UTC>`; `resume` runs the next unit,
  and a resume after a red finish gate runs a gate repair first. Lanes hold
  per story, and dependents wait while a dependency is held. Landing never
  holds, and a `stop` written during the last unit stops the story before it
  lands.
- Every run writes `events.jsonl` (schema v1, ten events).
  `docs/game-dev/overnight-events.md` is the contract #28's Multica bridge
  reads: fields and enum values may be added within v1, never renamed or
  removed.
- `tests/probes/hook_delivery_probe.sh` re-checks the three hook-delivery
  behaviours the channel relies on, using two haiku sessions. `doctor.sh`
  prints the last pass: 2026-10-04 on Claude Code 2.1.289.
- Still for the operator: a live Godot run with two stories, one held and
  resumed with a directive (plan M3–M5).

### 2026-10-03 — overnight: no background subagents in a -p unit

- Two phoenix `mob-composer-parity` units (4-S3-T3, 6-S3-T4) ended `noprog`
  at 10.7 min. Each main session dispatched its implementer as a background
  `Agent` (the build's default) and ended its turn to wait for the report. A
  `-p` session ends with its turn, and print mode killed the subagent 600 s
  later along with the `studio-test` it was running. The foreground-gate
  rule from 2026-10-02 was kept, but it covered only Bash and Monitor, not
  the dispatch. Each death spent the task's only retry.
- `hooks/autopilot-guard.sh` (PreToolUse, `Agent|Task|Bash|Monitor`) denies,
  under `OMEGA_AUTOPILOT=1` only, an `Agent`/`Task` call whose
  `run_in_background` is not `false`, a `Bash` call with
  `run_in_background: true`, and every `Monitor` call. The deny reason says
  how to re-issue the call. The execute skill's §0 has a matching rule.
- The runner records such a unit `orphaned` (from print mode's "Background
  tasks still running after 600s" line in the unit's `.err`), and a
  no-progress ending gains `(orphaned: …)`. It still counts as no progress.

### 2026-10-03 — studio-test speed (#22)

- The 75-minute phoenix suite was our bug. `test.sh` never passed `-gconfig`,
  so phoenix's `tests/.gutconfig.json` hooks never ran under `studio-test`.
  Those hooks keep the 7.9 MB humanoid rig loaded (KAN-919), pin the locale
  and isolate Inventory leaks. Each actor-building test reparsed the rig, at
  3–4 s a time. `studio-test` now passes the project's config: the full suite
  went from 4,485 s to 847 s, with the hooks' isolation back.
- The overnight `studio-test 472 1` was a segfault. A lane's first import was
  cut off, and the old check (import only when `.godot/` is absent) ran the
  suite on the half-built cache. `studio-test` and `studio-run` now check every
  import product and its `.md5` sidecar, which Godot writes only after a file's
  import finishes. They re-import, and stop only when the import itself fails;
  products still missing after an import that succeeded are a warning. A crash
  is reported with the script it was running, or as one at shutdown.
- `studio-test --slowest [N]` reports where the suite's time goes.
- Sharding is deferred: 4 shards were 2.9× faster with no swap, but phoenix has
  an order-dependent test and a flaky one that only fail sharded. Tiers are
  dropped: the fast tier was 51% of the full run. Numbers and verdicts:
  `specs/2026-10-02-studio-test-speed-findings.md`.

### 2026-10-02 — Overnight lanes repair a red gate

- In a lane, a story's finish runs the full gate once. A red gate used to
  stop the story and skip every story that depended on it. In one incident,
  a 121-character doc line halted a phoenix run at 85 minutes. Now
  `Stop: gate red — …` is the one repairable stop. The runner launches a
  `gate-repair` unit (`/game-dev:execute --gate-repair`, model_repair,
  `STUDIO_REPAIR=gate:<studio-test log>`), which fixes the failure and
  re-runs only the failing test files. Its `Repair: gate — …` line makes the
  runner launch a fresh finish, which runs the full gate again.
  `overnight.gate_repairs` (default 2, 0-3) bounds it. Past the cap the
  story ends `stopped gate red after <n> repairs — <line>`.
- A stop written twice with the same text on the same day is now detected:
  `snapshot` numbers each Stop line's occurrences within its ledger instead
  of de-duplicating them.
- The execute skill's final review makes every gate-enforced finding (line
  length, docs budgets, any `tests/` check) must-fix, and refuses an "it is
  not under that test" claim until the test has been run. That ruling was
  the root cause of the incident.
- Plan: `plans/2026-10-02-overnight-gate-repair.md`.

### 2026-10-02 — Overnight foreground gate and status anywhere

- The finish unit never ran its tests: under a lane, the execute skill told
  the session to run `studio-test` in the background and wait for the
  notice, and a headless `-p` session ends when its turn ends, so the notice
  never came and the job was orphaned holding the gate lock. Sessions now
  run `studio-test` and `studio-run` in the foreground with
  `timeout = $BASH_MAX_TIMEOUT_MS`; `tests/probes/bash_timeout_probe.sh`
  showed a `-p` foreground call honours a raised cap past 10 minutes.
- `studio-gate` registers each gate under its unit's tag
  (`.studio/gate.units/`), and the runner ends any gate a unit leaves
  behind. A watchdog-ended unit with no progress is recorded `timed out`.
  `.studio/gate.times` logs gate durations; preflight warns when the
  slowest recent `studio-test` would not fit `session_minutes`.
- `studio-overnight status` works from any directory through a user-level
  run registry (`~/.claude-gamedev/runs/`), shows each running unit's last
  tool call or subagent and the gate holder, and reads an ended run as one
  line with its report and resume command. `watch` repeats it; a foreground
  `start` prints a heartbeat. The installer puts `studio-overnight` on
  `PATH` (studio.json `commands`).

### 2026-10-02 — Overnight lanes (issue #19)

- `studio-overnight start` runs a manifest of stories as parallel
  dependency-chain lanes; a dependent never starts before its dependency
  has landed.
- The runner lands stories itself, serialized: integration mode ends in one
  draft PR integration → main (nothing merged into main, one full gate);
  direct mode merges each story through the project's merge command.
- `studio-gate` takes a machine-wide gate lock so lanes never run two
  engine gates at once; `studio-brief` and `studio-state` (`STUDIO_STORY`)
  give each lane's sessions their own story state.
- `studio-overnight next` is the planning loop for stories with no plan;
  `start --detach` outlives the chat, and `status` and `report.md` are
  per story.
- Skill contracts rewritten: execute, plan, brainstorm, autopilot and
  integration. Autopilot in a studio never runs stories in its own session
  and never starts a keep-awake.
- Live probes: D1a detach PASS (log unbroken after the window closed; env
  scrub widened to every `CLAUDE_*` and `AI_AGENT`, `CLAUDE_CONFIG_DIR`
  kept). D1b inconclusive (harness blocks a bare `sleep`), so background
  `studio-test` is the default. D1c a `set -m` subshell gets its own group.
  D1d phoenix `merge.sh` never reads a TTY and fails fast.
- Review rulings: the merge command runs under `session_minutes`, and a
  timeout stops the story unless its PR already merged (the first ruling
  had no timeout); D3 kept over spec 788-790 (an existing story branch's
  spec and plan are synced from the run's Docs revision, not a stop); one
  final repair unit at most; a red lane gate never ships and a lane story
  is not retried by fix rounds.
- Gate: `sh tests/run_all.sh` green (2,615 assertions, 0 failed).
- 56 deferred minor review findings are listed in the PR for a follow-up
  issue.
- Play before merging: 4 items pending (P1 integration live run; P2 direct
  live run; P3 the morning report; P4 detach survives the chat).
- Branch `worktree-issue-19-autopilot-integration`. Spec
  `specs/2026-10-01-overnight-lanes.md`, plan
  `plans/2026-10-01-overnight-lanes.md`.

### 2026-10-01 — Overnight runner (issue #17)

- `studio-overnight start` runs an approved plan from a plain terminal:
  one fresh `claude -p` session per unit (each task, final review, finish),
  ends in a draft PR, and writes `units.tsv` and a morning `report.md`
  (how the run ended, cost, rulings to check, play list, PR, resume).
- Autopilot prints the runner command instead of driving the session;
  `omega-caffeine` and the `CronCreate` heartbeat are retired.
- Live probe on 2.1.287 (D1-D6): slash commands expand under `-p`;
  `EnterWorktree` works; deny rules hold, including mid-command wildcards
  (`git push * --force*`); `total_cost_usd` is present; a unit starts at
  about 39k context; Ctrl-C aborted a backgrounded session, so the launch
  uses `set -m`.
- D7: the spec's wait loop was wrong (a second `wait` on a reaped child
  returns 127), so the status is read inside the loop.
- Review fixes: a watchdog teardown race marked every unit `timed_out`; a
  `mkdir` claim on `.ended` fixes it. Beyond the spec, SIGHUP ends the live
  session group before unlocking. A stop before isolation writes its
  `Stop:` line in the launch checkout and is never committed.
- Gate: `sh tests/run_all.sh` green (1,803+ assertions, 0 failed).
- Play before merging: 2 items pending (P1 live two-task run to a draft
  PR; P2 the morning report answers everything without opening a log).
- Branch `worktree-issue-17-overnight-runner`. Spec
  `specs/2026-10-01-overnight-runner.md`, plan
  `plans/2026-10-01-overnight-runner.md`.

### 2026-10-01 — Slim pipeline (issue #9)

- The stage chain is `idle → brainstorm → plan → execute → idle`, with a
  `/clear` between stages. `review`, `playtest` and `retro` are on-demand
  commands that never change `stage`. The last stage of the old pipeline is
  deleted, and execute's finish opens the PR.
- `studio-state`: a `branch` key, four stages, and `worktree` (exit 0 prints
  the feature's checkout; exit 3 prints the command that recreates it).
- Execute: B2 fix rounds (a fresh fixer per round, a re-review only after a
  Critical, 3+ Importants or a production-bug fix, never a third pass), a
  standalone final review on Opus, and a finish that gates, writes the play
  list, records PROGRESS and opens a ready PR without merging.
- `stage-guard.sh` (`UserPromptSubmit`) warns when a session that already ran
  one stage is used to start another.
- Rollout checks: M2 passed on Claude Code 2.1.287 (the second stage typed
  in one session drew one warning line and was not blocked; recorded in
  `docs/game-dev/pressure/slim-pipeline.md`); M3 passed (phoenix's router
  prints `Stage: idle (was retro, old pipeline)` and `Next:
  /game-dev:brainstorm`); M4 done (issue #6 describes the new chain). The
  pressure scenarios in `docs/game-dev/pressure/slim-pipeline.md` are not
  yet run; `claude-gd` logs in again, so they are unblocked.
- Spec `specs/2026-10-01-slim-pipeline-design.md`, plan
  `plans/2026-10-01-slim-pipeline.md`.

### 2026-09-15 — Plan 2 (Quality loop) delivered

- Ten role agents under `studios/game-dev/agents/`; `2d-art-pipeline` and
  `game-feel-tuner` migrated to `tech-artist` and `feel-tuner`.
- Stage skills `review`, `playtest`, `ship`, `retro`; `execute`,
  `brainstorm` and `plan` now dispatch the studio's own agents.
- `studio-test`, `studio-run`, `studio-lint` through `studio-dispatch` and
  the Godot adapter in `engines/godot/`.
- Optional `godot-mcp` registration inside the config root; doctor reports
  the engine, the MCP server, and resolves every delegated skill and agent.
- Plan: `plans/2026-09-13-plan-2-quality-loop.md`. The Plan 2 exit
  criterion (Task 16 manual run) is a manual verification pass; it has not
  been run yet.
- Task 16 Steps 1-2 (reinstall, doctor) verified 2026-09-15: reinstall
  registered `godot-mcp` inside the config root and nowhere else
  (`grep -c godot ~/.claude-gamedev/.claude.json` = 12; `grep -c godot-mcp
  ~/.claude.json` = 0; manifest's last line `mcp godot`); doctor exits 0
  with `superpowers: 8 of 8 resolved`, `godot-prompter: 35 of 35
  resolved`, the engine at
  `/Applications/Godot_mono.app/Contents/MacOS/Godot`, `mcp: godot
  registered`, `shim on PATH: yes`, `leakage: none`.
- Task 16 Step 3 verified 2026-09-16, in a throwaway worktree of the
  phoenix Godot project (Godot 4.6.3 mono, GUT 9.6.0), branch
  `KAN-1257-dash-freeze-timescale`: `studio-test` →
  `studio-test: 15737 passed, 0 failed`, exit 0, confirmed independently
  against the JUnit XML the adapter wrote (`<testsuites name="GutTests"
  failures="0" tests="15737">`); `studio-run --seconds 5` → the engine
  banner (`Godot Engine v4.6.3.stable.mono.official.7d41c59c4`) then
  `studio-run: clean (5s, .studio/reports/run-20260916-002530.log)`, exit
  0; `studio-lint` → `studio-lint: gdtoolkit is not installed. Install it
  with: pip install "gdtoolkit==4.*"`, exit 3 — the documented path, since
  `gdlint`/`gdformat` are absent on this machine; `studio-test` with
  `addons/gut` temporarily moved aside → printed the `Install:` line
  verbatim from `engines/godot/GUIDE.md`, exit 3, as documented,
  `addons/gut` then restored.
- Finding: on a project this size the run is slow — `studio-test` took
  roughly 46 minutes of wall clock (started 23:39, reports written 00:25)
  because the Godot adapter runs `-gdir=res://tests -ginclude_subdirs`,
  which sweeps phoenix's `e2e` suite as well as its unit tests, on a cold
  `.godot/` import cache. Step 3's wording assumes a quick summary line;
  that holds for a small project, not for a large one — an observation
  about the verb's cost on a large project, not a defect.
- Task 16's own text carried four stale or impossible expectations, now
  corrected in commit `81e6c217b40a15a6464025c799319fb271ee93b8`: the
  doctor's skill count (8 → 12), the spec heading count (eight → the
  brainstorm template's own headings, really 18), an unmentioned
  `studio-state init` gate in a fresh project, and — the one that would
  actually have blocked a verifier — a closing check that read the eight
  ledger phrases out of `.studio/STATE.md`, when `studio-state` writes
  them to `.studio/ledger/<feature>.md` whenever a spec is set and
  `retro` clears the spec before the check runs.
- Step 4 (the artifact §5 session through `claude-gd`) and Step 5 remain
  outstanding, so the Plan 2 exit criterion is not yet met.

### 2026-09-13 — Plan 1 review fixes

- Installer: input validation before reinstall, symlink-safe writes, purge
  requires a manifest, canonical target, manifest header (`mode`, `shim`),
  doctor shim identity / copy-mode inspection / stale-layout / canonical
  leak check.
- State: pointer local and resolved to the main checkout, per-feature
  ledgers committed with the branch, `studio-state check` / `reset`,
  PreToolUse guard.
- Skills: agents renamed and wired, godot-prompter agents interim, verify
  lists, smoke boot, no merge path from execute.
- Plan: `plans/2026-09-13-plan-1-review-fixes.md`. The Plan 1 exit
  criterion (spec §Success criteria 4) is a manual run from the main
  checkout after merge; it has not been run yet.

### 2026-09-13 — Plan 1 (Foundation) delivered

- `profiles/` became `studios/`; each studio is a Claude Code plugin loaded
  live through the shim's `--plugin-dir`.
- Installer, uninstaller, doctor and tests updated; reinstall cleans stale
  entries; doctor checks `requires.txt` against `settings.json` and the
  plugin cache.
- Session hook, `studio-state`, and the stage skills `studio`, `brainstorm`,
  `plan`, `execute`.
- Plan: `plans/2026-09-13-plan-1-foundation.md`.

### 2026-09-13 — Design approved

- Design reviewed and approved as an artifact:
  https://claude.ai/code/artifact/ca2bdd14-6d92-4ad8-99b6-fe455190fb0d
  (local copy: `artifacts/2026-09-13-game-studio-design.html`).
- Spec written: `specs/2026-09-13-game-studio-design.md`.
- Implementation plans written and committed:
  `plans/2026-09-13-plan-1-foundation.md` (12 tasks),
  `plans/2026-09-13-plan-2-quality-loop.md` (16 tasks),
  `plans/2026-09-13-plan-3-content.md` (12 tasks).
  Plans 2 and 3 were written in parallel from the spec and reconciled
  (GUT pin `v9.6.1`, first-run `--import` in the Godot adapter).
- Next: execute Plan 1, subagent-driven.

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

# Concurrent autopilot runs — Spec

Date: 2026-10-04
Status: Approved (operator, 2026-10-04; spec falsifier findings folded in)
Milestone: Plan 3 — Content (studio tooling; follows overnight lanes, #19, the operator channel, #27, Multica, #28, and autopilot adopt, #35)
Classification: architectural

Issue: #39. Option A (independent runs keyed by slug), chosen by the operator over B (one long-lived runner with a queue).

Today a project has at most one live overnight run:
- `studio-overnight start` refuses while `.studio/overnight.lock` is live;
- `/omega:autopilot` phase 1 stops at discovery while any run is live, so the next story cannot even be designed;
- phase 1 switches the main checkout to `run/<slug>` and keeps one `.studio/run` pointer;
- the brainstorm and plan stages write the project's one `.studio/STATE.md`.

A second idea therefore waits for the running one to end, or gets squeezed into its manifest.

This spec lets several manifest runs live in one project at once. Each run is planned in its own run worktree, started from it, and lands on its own. The runs share the machine through the existing gate lock and a new project-wide session cap, served first come, first served. They also stay aware of each other: every unit is told what the other live runs are changing, and a story merges its moved targets before each task unit.

This spec builds on #35 (autopilot adopt) as merged. The plan is written after #35 is on `origin/main`.

## Milestone gate

1. **Probe, before any implementation task.** A `claude-gd -p` session launched with the runner's arguments (`--permission-mode auto`, the deny list), with the run worktree `<root>/.claude/worktrees/run-x` as its working directory, must:
   - enter a sibling story worktree `<root>/.claude/worktrees/<branch>` (execute's **Enter the feature checkout**), edit a file there and commit;
   - run `STUDIO_STORY=x studio-state set task 1/3`, which writes `<root>/.studio/stories/x.md`;
   - run `studio-test` under the gate lock at `<root>/.studio/gate.lock`.

   The probe follows `tests/probes/bash_timeout_probe.sh`. If any step is denied or lands in the wrong checkout, the plan stops and the design returns to the operator.
2. `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh` are green. The existing suites keep every assertion, except assertions on the exact `next:` text, which change by AC14. The new cases are listed in Test strategy.
3. A fixture round trip, as a lanes test with stubbed units:
   - two manifest runs, `alpha` (integration) and `beta` (direct), are started from their own run worktrees in one fixture project, each while the other is live, with `max_sessions` 2;
   - the stub `claude` keeps a `mkdir` counter of live sessions and records its maximum, which is ≤ 2;
   - `status` shows both runs and `sessions: n/2`;
   - `beta` lands a story on the default branch while `alpha`'s story is mid-way. Before its next task unit, `alpha`'s story gets a clean sync merge with no session;
   - a second fixture makes that sync conflict, and one sync-repair stub unit resolves it;
   - the stub `claude` runs `peer-runs.sh` at start, and each unit's captured output carries the other run's "Other live runs" block;
   - bare `stop` refuses and lists both runs, then `stop --run alpha` ends only `alpha`.
4. Live, on phoenix (the operator runs the steps that need their machine):
   - plan run A in a `claude-gd` session and start it detached;
   - while A runs, plan run B in a second session and start it;
   - both runs land, and `studio-overnight status` showed both runs during the overlap.

## Purpose

- Start a new story's run whenever the idea is ready, by day or by night, without waiting for the running one.
- Keep each run independent: its own manifest, run worktree, report, stop and landing.
- Share the machine safely. Tests stay one at a time, and concurrent Claude unit sessions are capped project-wide and served in order.
- Find conflicts between runs early (awareness plus sync), not at landing.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Changed: `/omega:autopilot [<slug>]`: plans in a run worktree, lists the runs being planned, and no longer stops when a run is live.
- Changed: `/game-dev:brainstorm <slug>/<id>`, `/game-dev:plan <slug>/<id>` (the manifest form gains the run's slug).
- Changed: `studio-overnight status [--run <slug>]` and `watch [--run <slug>] [SECONDS]`.
- Changed: `stop` refuses when several runs are live. `stop --run <slug>` and `stop --all` stop runs, and `stop <story>` keeps today's meaning.
- Changed: `say`, `unsay`, `hold`, `resume`, `said` and `stop <story>` find the run from the story id.
- Added config: `overnight.max_sessions` in the main checkout's `.studio/config.json`.
- Added: `studio-state init --local`, `studio-peers`, and `STUDIO_REPAIR=sync:<ref>` for execute's `--land` unit.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A dead run's lock, session slots and registry entry are reclaimed by liveness (pid alive and `ps` shows the owner), never by age alone.
- Every refusal names the conflicting run (slug, run dir) and the way out.
- A failed sync repair stops the story with the reason, as a landing repair that made no progress does today. Other stories and runs go on.
- Install or pull omega-ai only when no run is live (Risks).

## Teaching

- `studio-overnight --help` explains:
  - several live runs;
  - the `--run` forms of `status`, `watch` and `stop`;
  - `stop --all`;
  - `max_sessions`.
- Autopilot's discovery explains the run worktree and prints its path.
- The README's overnight rows and the Multica README's Nightly workflow gain one line each: "another run can be planned and started while one is live".

## Input and platform

macOS and Linux shells, as today. POSIX `sh`; no new dependencies.

## Feel targets

n/a.

## References

- Inventory of one-run assumptions on origin/main 67c4887, made for this spec:
  - the run lock (`studio-overnight` 369, 454);
  - the stop flag (370, 1511, `overnight-channel.sh` 297, `overnight-lanes.sh` 607);
  - `unlock` (1053);
  - `reg_write` (904–908);
  - the `.studio/run` pointer (1504; autopilot SKILL 55, 87; plan 165; brainstorm 213);
  - STATE.md writers (brainstorm 61, 246; plan 151–153; autopilot 93, 112);
  - the in-project channel's run check (`overnight-channel.sh` 104–131);
  - the bridge state key (`integrations/multica/bridge/state.py` 120).
- Spec falsifier report (3 Critical, 12 Important, 20 Minor), all folded in.
- Landing repair, the model for sync repair: execute §9; `overnight-lanes.sh` `land_once_direct`, `land_repair`.
- The land lock's owner-checked release: `land_lock_take`, `land_lock_release`.
- Operator-inbox hook, the model for the peers hook: `studios/game-dev/hooks/operator-inbox.sh`.
- Events contract: `docs/game-dev/overnight-events.md`.
- #35: `studio-adopt` (`cmd_seed`, `run_manifest`, `run_target`, `plan_file`, `live_run_check`, `part_done`), `worktree_setup`.

## Acceptance criteria

Roots and run worktrees

1. `studio-state root` prints the main checkout from every checkout, unchanged. Everything keyed on it stays project-wide:
   - the gate lock;
   - session slots (AC27);
   - run records and reports;
   - registry `root=`;
   - `.studio/stories/`;
   - story worktree paths.

   Only the stage pointer moves (AC2). The header comment and `root`'s usage line say so.
2. The stage pointer of a checkout is `<work root>/.studio/STATE.md` when the work root is a linked worktree (not the main one) and that file exists. Otherwise it is `<root>/.studio/STATE.md`, as today.
   - `studio-state init --local` creates `<work root>/.studio/STATE.md` (stage idle). It refuses in the main checkout and in a checkout that already has one.
   - `STUDIO_STORY` state, the ledger, `config.json` and the spec and plan paths keep today's roots.
   - A story worktree never has a local pointer, so its behaviour is unchanged.
3. A **run worktree** is the checkout that has `run/<slug>` checked out, found through `git worktree list --porcelain` (`branch refs/heads/run/<slug>`). New runs create it at `<root>/.claude/worktrees/run-<slug>`. A run planned before this change has its main checkout as its run worktree (AC31).

Run identity, locks and the preflight

4. A manifest run's lock is `<root>/.studio/runs/<slug>/lock` and its stop flag is `<root>/.studio/runs/<slug>/stop`.
   - The lock records `pid=`, `run=`, `started=` and `start=` (the run's start dir).
   - They are taken, reclaimed and removed with today's noclobber and liveness rules. `unlock` removes only what this run holds.
   - `detach_start` waits on this run's lock and `status --run <slug>`, never on "any run is live".
   - `run_setup` adds `.studio/runs/` and `.studio/sessions/` to `info/exclude` before the lock is taken.
5. A single-plan run keeps `.studio/overnight.lock` and `.studio/overnight.stop`. Single-plan and manifest runs exclude each other both ways, and two single-plan runs stay exclusive, as today.
6. `reg_write` removes another registry entry only when its root equals this root **and** its runner is not live. Live runs are found by the per-run locks plus `.studio/overnight.lock` (the source of truth). The registry is a best-effort view of them for use outside a project.
7. Each per-run verb, status block, reap and report sets its `START_DIR` from the run's recorded start dir (lock `start=`, else registry `start=`), never from the caller's cwd. A run reaped from the main checkout prints a Resume line that changes into its run worktree.
8. The manifest preflight refuses:
   - a slug, story id or story branch already used by another live run, or by a run whose record (`.studio/runs/<slug>/`) exists without `done` (stopped, resumable);
   - a slug whose record exists with `done`, unless that record is first archived to `.studio/runs/<slug>.<utc ts>` (autopilot does this at AC12);
   - a story branch whose worktree path form (`/` → `-`) starts with `run-`, `integration-` or `progress-`, or that equals another live run's Target;
   - an all-digit slug, and the slug `off`.

   The id, branch and slug checks run again after the lock is taken, under a short project mutex `<root>/.studio/runs.mutex`. A start that loses the race unlocks and refuses.
9. The manifest preflight warns, and does not refuse, when files of this run's unfinished tasks overlap files of another live run's unfinished tasks (`studio-peers --files`, AC21). It prints the other run's slug and up to 20 paths, then `and N more`.

Operator verbs

10. `studio-overnight status` in a project:
    - prints `sessions: <live>/<cap>`, then one block per live run, oldest first. Each block keeps today's content, plus the lanes waiting for a session slot (`waiting for a session slot since <hh:mm>`);
    - `status --run <slug>` prints one block;
    - `status` exits 0 when at least one run is live, and as today when none is. `status --run <slug>` exits 1 with `no live run <slug>` when that run is not live;
    - outside a project, it lists every live registry run, printing each root once.
11. `watch [--run <slug>] [SECONDS]` refreshes what `status [--run <slug>]` prints.
12. `stop`:
    - bare `stop` with one live run stops it, as today;
    - with two or more, it stops nothing, lists the live slugs, prints `stop --run <slug>` and `stop --all`, and exits 1;
    - `stop --run <slug|run dir basename>` writes that run's own stop flag: `.studio/runs/<slug>/stop`, or `.studio/overnight.stop` for a single-plan run;
    - `stop --all` writes every live run's flag, skipping a run that ends meanwhile;
    - `stop <story>` keeps today's meaning (stop one story).
13. The channel verbs `say`, `unsay`, `hold`, `resume`, `said` and `stop <story>` resolve the run in this order:
    - `--run <slug or run dir basename>` when given;
    - otherwise, the one live run of this project whose `rows.tsv` lists the story;
    - otherwise, with exactly one live run, that run.

    No match refuses with `no live run lists <story>`. The in-project channel accepts any live run of this project.

Planning in run worktrees

14. `studio-overnight next <manifest>` prints `next: /game-dev:brainstorm <slug>/<id>`, `next: /game-dev:plan <slug>/<id>` or `next: /omega:autopilot <slug>`.
15. Autopilot phase 1, new run. The slug is checked first (AC8's rules), and a done record is archived. Then:
    - **Create and enter.** It creates the run worktree: `git fetch origin`, then `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`, or `git worktree add <path> run/<slug>` when the branch exists. It enters the worktree with execute's **Enter the feature checkout** procedure (`EnterWorktree path:`, else `cd`) and checks it with `git rev-parse --show-toplevel`.
    - **Set up.** It runs `studio-state init --local`, then the project's `worktree_setup` hook when configured (#35).
    - **Where the work happens.** Every later phase-1 step runs there: the lane count, the manifest, the `.studio/run` pointer and every commit. File paths are absolute under the run worktree, except half-done story worktrees (`<root>/.claude/worktrees/…`). The main checkout's branch is never switched.
    - **Story ids.** The story-list question refuses an id or branch that AC8 would refuse.
16. `/omega:autopilot` with no slug, at discovery:
    - lists the **runs being planned**: run worktrees (AC3) whose `.studio/run` names a manifest with no record under `<root>/.studio/runs/<slug>/`;
    - lists the **started runs**: a record without `done`, live or not, as `status` prints them;
    - asks one `AskUserQuestion` with each run and "new run". A run being planned resumes at step 2, and a started run at step 4, from its run worktree.

    `/omega:autopilot <slug>` skips the question. A live run never stops discovery.
17. `/game-dev:brainstorm <slug>/<id>` and `/game-dev:plan <slug>/<id>`:
    - first enter the run worktree of `run/<slug>` (AC3), as AC15 does, refusing when no checkout holds `run/<slug>`;
    - print `studio-state show` after entering;
    - then behave as today's `<id>` form under that worktree's `.studio/run`, with file paths absolute under it.

    The bare `<id>` form keeps today's meaning in the current checkout.
18. Autopilot step 4 runs its baseline `studio-test` in the run worktree after `worktree_setup`. Step 5 starts the run from the run worktree with `cd '<run worktree>' && '<abs>' start [--detach] <manifest>`. The report names `git worktree remove <path>` once the run is `done`, and nothing removes the worktree automatically.
19. Autopilot `off` clears the mode, then applies AC12's bare-stop rule. The studio skill's check of `$(studio-state root)/.studio/overnight.lock` is replaced by `studio-overnight status`. A live run no longer means "the project is busy" anywhere in the studio or autopilot skills.
20. #35 compatibility. `studio-adopt`'s "start checkout" is:
    - `STUDIO_START_DIR` when set (the runner exports it to every unit);
    - else the run worktree of the run named by the story's manifest row;
    - else `$STATE_ROOT`.

    `cmd_seed`, `run_manifest`, `run_target` and `plan_file` read through it. `live_run_check` sees the per-run locks and `.studio/overnight.lock`. `part_done` also excludes `fix(sync` and `chore(sync` subjects. #35's autopilot adopt steps print the `<slug>/<id>` forms.

Awareness

21. A new script `studios/game-dev/bin/studio-peers` lists the other live manifest runs of this project (AC6's source of truth).
    - **Input.** It takes `[--exclude <run dir>]` and `[--files]`.
    - **Default output.** One line per run: slug, mode, and the stories not landed or stopped, each with `task k/N`.
    - **`--files`.** Instead, one line per path: the files of each unfinished task (tasks k+1..N above `## Backlog`) of those stories, read from the run's plans at its `Docs:` revision. It reads both the studio `Files:` line and superpowers' `**Files:**` bullet lists (`- Create:`, `- Modify:`, `- Test:`). A `:<lines>` suffix is stripped, and paths are de-duplicated and sorted.
    - **Rules.** It writes nothing and needs no lock. A run whose data cannot be read is listed as `<slug>: unreadable`.
22. A new hook `studios/game-dev/hooks/peer-runs.sh`, registered for SessionStart (startup|compact), prints an `Other live runs` block in a manifest unit session.
    - **Gating.** It is env-gated like `operator-inbox.sh` (`STUDIO_RUN_DIR`, `STUDIO_UNIT_TAG`) and exits 0 on every path.
    - **Content.** `studio-peers --exclude "$STUDIO_RUN_DIR"`, up to 40 `--files` paths and `and N more`, then the rule: *These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report.*
    - **Silence.** With no other live run it prints nothing.
23. The execute skill copies that block, when present, into each implementer and fixer brief.

Sync on landing

24. The lane runs a sync check before each task unit and before the final-review unit of a story.
    - It never runs before a gate-repair, landing-repair or sync-repair unit, before landing, during a hold, or after a halt.
    - It runs only when:
      - `STUDIO_STORY=<id> studio-state worktree` exits 0, and that checkout is on `<Branch>`. Otherwise the result is `skipped=no-worktree`;
      - the checkout is clean (else `skipped=dirty`);
      - the local branch is not ahead of `origin/<Branch>` (else `skipped=ahead`, which covers an unpushed red `Stop:` head).
    - **Sync refs:** `origin/<Target>`, then `origin/<default>` when the Target is not the default branch. The lane fetches first.
25. For each sync ref in order that is not an ancestor of the branch head, the lane runs `git merge-tree --write-tree` against the current head.
    - **Clean (exit 0).** It runs `git merge --no-edit <ref>` with message `chore(sync): merge <ref> into <Branch>` in the story worktree, then the next ref against the new head.
    - **Failed merge.** A non-zero `git merge` is undone with `git merge --abort`, the tree is checked clean, and the result is `failed=merge`.
    - **Push.** After every clean merge: `git push origin HEAD:refs/heads/<Branch>` with `git_retry`.
    - **Event.** A `story_synced` event (`story`, `refs`, `sha`, or `skipped=`/`failed=`).
    - **Never:** no session starts and no studio state is written. A `skipped` or `failed` result never stops the story, and the landing check still guards the merge.
26. A conflict (merge-tree exit 1) launches one sync-repair unit through the existing landing-repair path: prompt `/game-dev:execute --land`, the story's env, and `STUDIO_REPAIR=sync:<ref>`. It counts toward the session cap and the run budget.
    - Execute §9 accepts `sync:<ref>` with stage `execute` instead of `stage idle` and a `shipped` line.
    - It merges `<ref>` and resolves the conflict with one fresh fixer.
    - Its gate is the tests of the files the resolution touched (`studio-test <paths>`, as §11 scopes it), up to three rounds. The next task's `Verify:` and the finish gate cover the rest.
    - It commits `fix(sync): <summary>`, pushes, and ledgers `Synced: <summary>`, committed and pushed.
    - Red after three rounds: `Stop: sync repair red — <failing line>`, committed, not pushed.

    The runner counts a new `Synced:` line as progress and continues with the story's next unit. A new `Stop:`, no progress, or a timeout stops the story at once (no retry), with ending `stopped sync repair: <reason>`.

Session cap

27. `overnight.max_sessions` (default 6, range 1–8, integer) is read from `<root>/.studio/config.json` (the main checkout) at each slot request, so one cap applies to every run. It is validated by the preflight.
    - **Before which units.** Before every `run_unit` (task, check, final, progress, gate repair, landing repair, sync repair), the lane queues for a slot. It takes the slot before `unit_started`, the unit clock and the watchdog start, so the wait counts neither as running time nor toward `session_minutes`.
    - **Queue.** A waiter writes `<root>/.studio/sessions/wait/<epoch ns>-<lane pid>`. Only the oldest live waiter may take a free slot `<root>/.studio/sessions/<n>` (n in 1..cap, taken with `mkdir`). A lane that just released a slot queues again at the tail.
    - **Owner.** The `owner` file holds the lane's pid (`LANE_PID`, or the runner's `$$` for final units), the session pid once started, `run` and `unit`. The owner is live when either pid is alive and `ps` shows `studio-overnight` or `claude`.
    - **Release.** The lane releases its slot when the session ends, on every exit path, signals included. Release is owner-checked: rename aside, and only when `owner` still names this lane.
    - **Dead lanes.** `lanes_end_sessions` and `lanes_sweep` release a dead lane's slot and wait entry.
    - **Reclaim.** A slot or wait entry whose owner is not live is reclaimed. Queue and slot changes take `<root>/.studio/sessions.mutex`, never the gate mutex.
    - **Ending the wait.** A halt or stop removes the wait entry and ends the wait.
    - **Not counted:** merge commands, gates run by the runner itself, and subagents inside a unit.
28. A `session_wait` event (`lane`, `story`, `since`) is written when a lane starts waiting.

Contract and compatibility

29. `docs/game-dev/overnight-events.md` adds `story_synced` and `session_wait`. Its "Finding a run" section is rewritten for per-run locks, several live entries per root, AC6's drop rule and AC13's resolution. The Multica bridge mirrors `story_synced` as a comment, ignores `session_wait`, sends `stop --run` for run stops (unchanged), and mirrors two live runs in one root.
30. `.studio/run` stays per checkout. The runner exports `STUDIO_START_DIR` to every unit.
31. A run planned or started before this change is handled as follows:
    - **Planned in the main checkout:** a run on `run/<slug>` with the main checkout's `.studio/run` resumes and starts from the main checkout, which is its run worktree by AC3. A main checkout has no local pointer (AC2), so it plans on the main pointer as today.
    - **Live old-style run:** a manifest run holding `.studio/overnight.lock` counts as live for AC5 and AC8 until it ends.
    - **Reap:** `status` and `start` reap a dead `.studio/overnight.lock` whose run dir has a `manifest.md`.

## Architecture

### Before / after

- Before: one lock and one stop flag per project. Planning happens in the main checkout, on the project's one STATE.md. Every verb finds "the lock's run" and uses the caller's cwd as the start dir.
- After:
  - a lock and stop flag per run, keyed by slug and recording its start dir;
  - planning in a run worktree, with a local stage pointer and the project root unchanged;
  - verbs that take `--run` or derive the run from the story id;
  - a shared, first-come-first-served session cap next to the existing shared gate lock;
  - a peers view (`studio-peers`) used by both the preflight and a SessionStart hook;
  - a sync check per task unit, with conflicts going to the existing landing-repair unit.

### Files

- `studios/game-dev/bin/studio-overnight`:
  - the per-run lock, stop flag and start dir, `detach_start`, `run_setup` excludes;
  - the `reg_write` rule, single-plan versus manifest exclusivity;
  - `status`, `watch` and `stop` forms, and `registry_status` de-duplication;
  - `max_sessions` and help;
  - the old-lock reap.
- `studios/game-dev/bin/overnight-lanes.sh`:
  - the AC8 and AC9 preflight checks and the post-lock re-check;
  - `next`'s slug form;
  - the sync check and the sync-repair launch;
  - the session queue and slots around `run_unit`;
  - per-run status, reap and report `START_DIR`.
- `studios/game-dev/bin/overnight-channel.sh`: AC12's `stop --run` target, and AC13's resolution.
- `studios/game-dev/bin/studio-state`: AC1 and AC2 (the local pointer, `init --local`).
- `studios/game-dev/bin/studio-adopt` (#35): AC20.
- `studios/game-dev/bin/studio-peers` (new), `studios/game-dev/hooks/peer-runs.sh` (new), `studios/game-dev/hooks/hooks.json`.
- `shared/omega/skills/autopilot/SKILL.md`: AC15, AC16, AC18, AC19, AC20's printed forms.
- `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`: AC17.
- `studios/game-dev/skills/execute/SKILL.md`: §9's `sync:` form (AC26), the peers block in briefs (AC23), §1's mode list.
- `studios/game-dev/skills/studio/SKILL.md`: AC19.
- `integrations/multica/bridge/mirror.py`: AC29.
- `docs/game-dev/overnight-events.md`, `README.md`, `integrations/multica/README.md`, `docs/game-dev/PROGRESS.md`.

### Failure handling

- Lock, slot, wait-entry and registry reclaim follow the existing liveness rule. A SIGKILLed run or lane leaves them behind, and the next start, slot request or sweep reclaims them.
- A sync-check git failure never stops a story. It is logged as `story_synced failed=…`, and the landing check still guards the merge.
- `studio-peers` failures degrade to `<slug>: unreadable`. The hook and the preflight warning never fail a session or a start.

### Rejected alternatives

- **B — one long-lived runner with a queue.** Rejected by the operator after comparing speed, tokens and quality:
  - it rewrites the frozen-manifest core;
  - it bundles unrelated stories into one integration PR;
  - it makes one runner a single point of failure.
- **Per-story STATE.md during planning (`STUDIO_STORY` in brainstorm and plan).** Rejected for AC2's local pointer:
  - the epic form writes one spec for several stories, and a spec-slug ledger;
  - `next` classifies from those files;
  - so story-keyed planning state would change four skills and `next`, while AC2 changes only `studio-state`'s pointer path.
- **A separate execute §12 for sync repair.** Rejected: it duplicates §9. Sync repair is §9 with `STUDIO_REPAIR=sync:<ref>`, and a §11-scoped gate keeps it within one session.
- **`stop <slug>`.** Rejected: it collides with today's `stop <story>`. Run stops use the existing `stop --run`.
- **Per-runner caps, lowest-free-slot polling.** Rejected: mismatched caps and immediate re-takes starve a newer run. One cap from the main checkout, with a FIFO queue.
- **File claims that hold a story.** Rejected by the operator: they serialize overlapping work.
- **More than one gate slot.** Rejected by the operator: Godot tests would compete for CPU and the import cache.

## Tuning knobs

- `overnight.max_sessions`: default 6, range 1–8.
- The peers block's path limit (40) and the preflight overlap list limit (20): constants in the scripts.

## Assets and audio

n/a.

## Test strategy

Shell suites under `tests/`, with stubbed units and a fixture git remote, as the lanes and channel suites do today:

- **Probe:** Milestone gate step 1, as `tests/probes/run_worktree_probe.sh`.
- **`studio-state`:**
  - from a run worktree, `root` is the main checkout;
  - `init --local` creates the local pointer, and its refusals;
  - the local pointer is used only when present;
  - the main checkout's STATE.md is untouched by stage writes in a run worktree;
  - `STUDIO_STORY` state stays at `<root>`;
  - `studio-gate` locks `<main>/.studio/gate.lock` from a run worktree.
- **Locks:**
  - two manifest runs, each holding its own lock;
  - single-plan and manifest exclusivity both ways;
  - `reg_write` keeps a live sibling's entry and drops a dead one;
  - `detach_start` with another run live;
  - the old-style lock is reaped.
- **Preflight:**
  - each AC8 refusal (live and stopped runs, done-record archive, branch forms, slug `off` and all-digit);
  - the post-lock re-check race;
  - the overlap warning with both `Files:` forms and `and N more`.
- **Verbs:**
  - `status` with zero, one and two runs, `status --run`, and outside a project (each root printed once);
  - bare `stop` with one and two runs, `stop --run`, `stop --all`, and `stop <story>` unchanged;
  - channel resolution for all six verbs;
  - a reap from the main checkout prints the run worktree's Resume line.
- **`next`** prints the slug forms.
- **Session slots:**
  - cap 2 across two runs, by the stub's max counter;
  - cap 1 alternates between two runs (FIFO);
  - `kill -9` of a lane with its runner alive, then the slot is reclaimed;
  - a late release after a reclaim leaves the other run's slot;
  - a stop ends a wait;
  - every exit path releases the slot;
  - the wait does not count toward `session_minutes`.
- **Sync:**
  - a clean merge with no session, plus its event and push refspec;
  - `skipped=dirty`, `skipped=ahead` and `skipped=no-worktree`;
  - an integration run merges both refs one at a time;
  - `failed=merge` aborts cleanly;
  - a conflict launches one `--land` stub with `STUDIO_REPAIR=sync:<ref>`, and a `Synced:` line counts as progress;
  - a `Stop:` line, no progress, or a timeout stops the story;
  - no sync before gate-repair or landing-repair units.
- **#35:** `studio-adopt seed`, `run_target` and `live_run_check` from a run worktree; `part_done` ignores `fix(sync)` and `chore(sync)` commits.
- **`studio-peers`:** default and `--files` output from a two-run fixture; an unreadable run.
- **Hook:** the block in a unit session's start output; no output with no peer run or outside a unit; exit 0 on bad input.
- **Contracts** (`tests/omega_contracts/autopilot_contract.sh`, `tests/studio_test.sh`):
  - autopilot: run worktree creation, `init --local`, `worktree_setup`, discovery lists, the start command, `off`;
  - brainstorm and plan: the `<slug>/<id>` form, its refusal, `studio-state show` after entering;
  - execute: §9's `sync:` form and §1's mode list;
  - AC23's brief rule;
  - studio: AC19.
- **Bridge:** two runs in one root are both mirrored, `story_synced` becomes a comment, `session_wait` is ignored, and a run stop sends `stop --run`.
- The Milestone gate's step 3 fixture round trip.

## Risks

- **Semantic conflicts that merge cleanly.** A clean sync merge can still break behaviour. The next task's `Verify:` tests and the story's finish gate catch most cases, and sync never bypasses a gate.
- **Gate queue.** With several runs the gate lock is the throughput ceiling. Accepted: the operator chose one gate slot.
- **Direct runs landing back to back.** `land_once_direct`'s `merge-tree` check runs before the gate lock. A second run's check can go stale after the first lands, which sends the merge to the existing repair path. This is accepted.
- **Usage quota.** Six concurrent units plus their subagents spend a usage window quickly. `max_sessions` and `run_usd` are the controls.
- **Run worktree environment.** Git-ignored per-project files (`.claude/settings.local.json`, the engine cache) do not carry into a run worktree. `worktree_setup` covers the engine cache, and the probe (Milestone gate step 1) covers permissions and paths.
- **Install while live.** `claude-gd` loads skills from the repo and `sh` reads `studio-overnight` incrementally. Install or pull omega-ai only when `studio-overnight status` shows no live run. `--help` says so.
- **SessionStart context.** A planning session's startup line shows the launch checkout's stage. AC17 prints `studio-state show` after entering the run worktree.

## Not doing

- Dependencies between runs. A story that needs another run's work is planned after that work lands.
- More than one gate at a time.
- Runs messaging each other, or file claims that hold work.
- Several single-plan runs at once.
- Migrating runs that are live when this change is installed (AC31).

# Concurrent autopilot runs — Spec

Date: 2026-10-04
Status: Draft (awaiting operator review)
Milestone: Plan 3 — Content (studio tooling; follows overnight lanes, #19, the operator channel, #27, Multica, #28, and autopilot adopt, #35)
Classification: architectural

Issue: #39. Option A (independent runs keyed by slug), chosen by the operator over B (one long-lived runner with a queue).

Today a project has at most one live overnight run:
- `studio-overnight start` refuses while `.studio/overnight.lock` is live;
- `/omega:autopilot` phase 1 stops at discovery while any run is live, so the next story cannot even be designed;
- phase 1 switches the main checkout to `run/<slug>` and keeps one `.studio/run` pointer;
- the brainstorm and plan stages write the project's one `.studio/STATE.md`.

A second idea therefore waits for the running one to end, or gets squeezed into its manifest.

This spec lets several manifest runs live in one project at once. Each run is planned in its own run worktree, started from it, and lands on its own. The runs share the machine through the existing gate lock and a new project-wide session cap. They also stay aware of each other: every unit is told what the other live runs are changing, and a story merges its moved targets before each unit.

## Milestone gate

1. `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh` are green. The existing suites keep every assertion, except assertions on the exact `next:` text, which change by AC10. The new cases are listed in Test strategy.
2. A fixture round trip, as a lanes test with stubbed units:
   - two manifest runs, `alpha` (integration) and `beta` (direct), start in one fixture project while each other is live, with `max_sessions` 2;
   - `status` shows both runs and `sessions: n/2`, and no more than 2 unit sessions are ever live at once (the stub records start and end stamps);
   - `beta` lands a story on the default branch while `alpha`'s story is mid-way. Before its next unit, `alpha`'s story gets a clean sync merge with no session. A second fixture makes that sync conflict, and one sync-repair stub unit resolves it;
   - each unit's SessionStart output carries the other run's "Other live runs" block;
   - bare `stop` refuses and lists both runs, then `stop alpha` ends only `alpha`.
3. Live, on phoenix (the operator runs the steps that need their machine):
   - plan run A in a `claude-gd` session and start it detached;
   - while A runs, plan run B in a second session and start it;
   - both runs land, and `studio-overnight status` showed both runs during the overlap.

## Purpose

- Start a new story's run whenever the idea is ready, by day or by night, without waiting for the running one.
- Keep each run independent: its own manifest, worktree, report, stop and landing.
- Share the machine safely. Tests stay one at a time, and the number of concurrent Claude unit sessions is capped.
- Find conflicts between runs early (awareness plus sync), not at landing.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Changed: `/omega:autopilot [<slug>]`: plans in a run worktree, lists the runs being planned, and no longer stops when a run is live.
- Changed: `/game-dev:brainstorm <slug>/<id>`, `/game-dev:plan <slug>/<id>` (the manifest form gains the run's slug).
- Changed: `studio-overnight status [<slug>]`, `watch [<slug>]`, `stop [<slug> | --all]`. `say`, `hold`, `resume` and `said` find the run from the story id.
- Added config: `overnight.max_sessions` in `.studio/config.json`.
- Added: `studio-peers` (Architecture), and the execute mode `--sync`.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A dead run's lock, session slots and registry entry are reclaimed by liveness (pid alive and `ps` shows the owner), never by age alone.
- Every refusal names the conflicting run (slug, run dir) and the way out.
- A failed sync repair stops the story with the reason, as a landing repair that made no progress does today. Other stories and runs go on.

## Teaching

- `studio-overnight --help` explains several live runs, the slug forms of `status`, `watch` and `stop`, and `max_sessions`.
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
- Landing repair, the model for sync repair: `execute` §9; `overnight-lanes.sh` `land_once_direct`, `land_repair`.
- Operator-inbox hook, the model for the peers hook: `studios/game-dev/hooks/operator-inbox.sh`.
- Events contract: `docs/game-dev/overnight-events.md`.

## Acceptance criteria

Run identity and locks

1. A manifest run's lock is `<root>/.studio/runs/<slug>/lock` and its stop flag is `<root>/.studio/runs/<slug>/stop`, where `<root>` is `studio-state root`. They are taken, reclaimed and removed with today's noclobber and liveness rules. `unlock` removes only the lock and stop flag this run holds.
2. A single-plan run keeps `.studio/overnight.lock` and `.studio/overnight.stop`. A single-plan `start` refuses while any manifest run of this project is live. A manifest `start` refuses while a single-plan run is live. Two single-plan runs stay exclusive, as today.
3. `reg_write` removes another registry entry only when that entry's root equals this root **and** its runner is not live (`reg_live` fails). A live sibling run's entry is never removed.
4. The manifest preflight (`start` and `start --dry-run`) refuses when any other live run of this project:
   - has the same slug;
   - lists a story with the same id;
   - lists a story with the same branch.

   It also refuses a story branch that starts with `run/`, because its worktree path would collide with a run worktree. Live runs are found through the registry (root equal, `reg_live`) and read from their run dir's `rows.tsv`.
5. The manifest preflight warns, and does not refuse, when files in this run's unfinished tasks overlap files in another live run's unfinished tasks (`studio-peers --files`, AC17). It prints the other run's slug and up to 20 overlapping paths, then `and N more`.

Operator verbs

6. `studio-overnight status` (in a project) prints one block per live run of the project, oldest first. Each block keeps today's content. A first line `sessions: <live>/<cap>` precedes the blocks. `status <slug>` prints that run's block only. Exit codes:
   - `status` exits 0 when at least one run is live, and as today when none is;
   - `status <slug>` exits 0 when that run is live, and exits 1 with `no live run <slug>` otherwise.

   Outside a project, `status` lists every live registry run, as today.
7. `watch [<slug>]` refreshes what `status [<slug>]` prints.
8. Bare `stop`:
   - with one live run, stops it, as today;
   - with two or more, it stops nothing, lists the live slugs, prints `stop <slug>` and `stop --all`, and exits 1.

   `stop <slug>` stops that run. `stop --all` writes the stop flag of every live manifest run and of a live single-plan run. A run that ends while `stop --all` is running is skipped, not an error.
9. `say`, `hold`, `resume` and `said` resolve the run in this order:
   - `--run <run dir basename or slug>` when given;
   - otherwise, the one live run of this project whose `rows.tsv` lists the story id;
   - otherwise, with exactly one live run, that run (as today).

   No match refuses with `no live run lists <story>`. A story listed by two live runs cannot occur (AC4). The in-project channel accepts any live run of this project, not only the lock's run.

Planning in run worktrees

10. `studio-overnight next <manifest>` prints `next: /game-dev:brainstorm <slug>/<id>`, `next: /game-dev:plan <slug>/<id>` or `next: /omega:autopilot <slug>`, where `<slug>` is the manifest's `# Run:` slug.
11. Autopilot phase 1, new run:
    - **Where.** It creates the run worktree `<root>/.claude/worktrees/run-<slug>` on `run/<slug>`: `git fetch origin`, then `git worktree add -b run/<slug> <path> origin/<default>`, or, when `run/<slug>` exists, `git worktree add <path> run/<slug>`. It changes into that worktree and checks it with `git rev-parse --show-toplevel`. Every later step of phase 1 runs there, and file paths are absolute under it. The main checkout's branch is never switched.
    - **Lane count.** The lane-count write, the manifest, the pointer `.studio/run` and every commit land in the run worktree.
    - **Story ids.** The story-list question refuses an id or branch already used by another live run (AC4) or by another run being planned (AC13).
12. In a run worktree, `studio-state` keeps the stage pointer in the worktree's own `.studio/STATE.md` (git-ignored, as today), not the main checkout's. A *run worktree* is a linked worktree (not the main one) whose current branch matches `run/*`. Everything else keeps today's roots:
    - per-story state (`STUDIO_STORY`, `.studio/stories/<id>.md`) stays at `<root>`;
    - the ledger, `config.json` and the spec and plan paths stay in the working root.

    So the brainstorm and plan stages under a manifest keep their state writes unchanged and never touch the main checkout's `STATE.md`. Autopilot step 3's `studio-state reset --keep-ledger` resets the run worktree's pointer only.
13. `/omega:autopilot` with no slug, at discovery:
    - lists the **runs being planned**: run worktrees with a `.studio/run` pointer whose `.studio/runs/<slug>/` does not exist under `<root>`;
    - lists the **live runs**, as `status` prints them;
    - asks one `AskUserQuestion` with each run being planned and "new run". A run being planned resumes at step 2.
    - A started run (`.studio/runs/<slug>/` exists, not `done`) resumes at step 4, from its run worktree.

    `/omega:autopilot <slug>` skips the question. A live run never stops discovery.
14. `/game-dev:brainstorm <slug>/<id>` and `/game-dev:plan <slug>/<id>` first change into `<root>/.claude/worktrees/run-<slug>` (refusing when it does not exist or is not on `run/<slug>`), then behave as today's `<id>` form under that worktree's `.studio/run`. The bare `<id>` form keeps today's meaning in the current checkout.
15. Autopilot step 5 starts the run from the run worktree. The command is `cd '<run worktree>' && '<abs>' start [--detach] <manifest>`, and both start options print that path. The run worktree is removed only after the run is `done`: the report names `git worktree remove <path>`, and nothing removes it automatically.
16. Autopilot `off` clears the mode, then applies AC8's bare-stop rule. The studio and autopilot skills stop treating "a run is live" as "the project is busy".

Awareness

17. A new script `studios/game-dev/bin/studio-peers` lists the other live manifest runs of this project.
    - **Input.** It takes `[--exclude <run dir>]` and `[--files]`.
    - **Default output.** One line per run: slug, mode, and the stories not yet landed or stopped, each with `task k/N`.
    - **`--files`.** Instead, one line per path: the `Files:` entries of each unfinished task (tasks k+1..N above `## Backlog`) of those stories, read from the run's manifest plans at its `Docs:` revision. The paths are de-duplicated and sorted.
    - **Rules.** It writes nothing and needs no lock. A run whose data cannot be read is listed as `<slug>: unreadable`.
18. A new hook `studios/game-dev/hooks/peer-runs.sh`, registered for SessionStart (startup|compact), prints an `Other live runs` block in a manifest unit session.
    - **Gating.** It is env-gated like `operator-inbox.sh` (`STUDIO_RUN_DIR`, `STUDIO_UNIT_TAG`) and exits 0 on every path.
    - **Content.** `studio-peers --exclude "$STUDIO_RUN_DIR"`, then up to 40 of its `--files` paths and `and N more`, then the rule: *These files are being changed by another live run. Do not edit them beyond what your task needs; if your task needs to, keep the change minimal and name each such file in your report.*
    - **Silence.** With no other live run it prints nothing.
19. The execute skill copies that block, when present, into each implementer and fixer brief.

Sync on landing

20. Before each unit of a story whose branch exists, the lane runs a sync check. It does not run before landing (the landing check covers that), during a hold, or after a halt. The check:
    - fetches origin;
    - collects the **sync refs**: `origin/<Target>`, plus `origin/<default>` when the Target is not the default branch;
    - for each ref that is not an ancestor of the story branch's head, runs `git merge-tree --write-tree` against it.
21. A clean result (exit 0 for every moved ref):
    - the lane merges those refs into the story branch in the story's worktree: `git merge --no-edit`, with message `chore(sync): merge <refs> into <Branch>`;
    - it pushes with `git_retry`;
    - it writes a `story_synced` event (`story`, `refs`, `sha`).

    No session is started and no studio state is written.

    If the story worktree is dirty, the lane skips the sync, writes `story_synced` with `skipped=dirty` and goes on.
22. A conflict (exit 1 for any moved ref) launches one sync-repair unit: prompt `/game-dev:execute --sync`, with the story's env and `STUDIO_REPAIR=sync:<refs>`. It counts toward the session cap, the run budget and `retries`, like any unit.
    - The runner counts a new `Synced:` ledger line as progress and goes on with the story's next unit.
    - A new `Stop:` line, or no progress, stops the story. The ending is `stopped sync repair: <reason>`, as a landing repair that made no progress.
    - Any other `merge-tree` exit writes `story_synced` with `failed=<code>` and skips the sync. The landing check still guards the merge.
23. Execute gains §12, sync repair (`--sync`), modelled on §9:
    - **Enter** the feature checkout, then record operator messages.
    - **Preconditions:** stage `execute` and `STUDIO_REPAIR` starting with `sync:`. Any miss is a `Stop:` line.
    - **Merge and resolve:** `git fetch origin`, then `git merge --no-edit` each named ref. Merge, never rebase. One fresh fixer resolves the conflict.
    - **Gate:** the story's tests through `studio-test`, up to three runs, with fixes between them. Exit codes keep §9's meaning.
    - **Record:** commit `fix(sync): <summary>`, push, then `studio-state ledger "Synced: <summary>"`, committed and pushed.
    - **Red after three runs:** `Stop: sync repair red — <failing line>`, committed, not pushed.
    - **Never** touches the target or `main`.
    - **One unit:** end the turn.

Session cap

24. `overnight.max_sessions` (default 6, range 1–8, integer) caps live unit sessions across all runs of the project. It is read by each runner from its own `config.json` and validated by the preflight like `max_lanes`.
    - **Slots.** `<root>/.studio/sessions/<n>` for n in 1..cap. A slot is a directory taken with `mkdir`; its `owner` file records `pid`, `run` and `unit`.
    - **Taking a slot.** Before each unit session (task, final, progress, gate repair, landing repair, sync repair), the lane takes the lowest free slot whose number is ≤ its runner's cap. It releases the slot when the session ends, on every exit path, signals included.
    - **Waiting.** When no slot is free, the lane polls at the lane poll interval. The wait does not count toward `session_minutes`. A halt or stop ends the wait.
    - **Reclaiming.** A slot whose `owner` pid is not live is reclaimed under the gate lock's reclaim rule.
    - **Not counted:** merge commands, gates run by the runner itself, and subagents inside a unit.
25. `status` prints `sessions: <live>/<cap>` (AC6) and, per run, the lanes waiting for a slot (`waiting for a session slot since <hh:mm>`).
26. `story_synced` and a `session_wait` event (`lane`, `story`, `since`) are added to `docs/game-dev/overnight-events.md`. The Multica bridge mirrors `story_synced` as a comment and ignores `session_wait`. Unknown events stay ignored, as today.

Compatibility

27. A run planned before this change, in the main checkout on `run/<slug>` with the main checkout's `.studio/run`, still resumes and starts from the main checkout. Discovery lists it as a run being planned, at its main-checkout path.
28. Runs started before this change are not migrated: an old-style live run (holding `.studio/overnight.lock` with a manifest) is treated as a live single-plan run for AC2 and AC4 until it ends.

## Architecture

### Before / after

- Before: one lock and one stop flag per project. Planning happens in the main checkout, on the project's one STATE.md. Every verb finds "the lock's run".
- After:
  - a lock and stop flag per run, keyed by slug;
  - planning in a run worktree, with its own stage pointer;
  - verbs that take a slug or derive it from the story id;
  - a shared session cap and the existing shared gate lock;
  - a peers view (`studio-peers`) used by both the preflight and a SessionStart hook;
  - a sync check per unit, with a sync-repair unit on conflict.

### Files

- `studios/game-dev/bin/studio-overnight`: per-run lock and stop flag, the `reg_write` liveness rule, single-plan versus manifest exclusivity, `status`/`watch`/`stop` forms, `max_sessions` config and help.
- `studios/game-dev/bin/overnight-lanes.sh`:
  - AC4 and AC5 preflight checks;
  - `next`'s slug form;
  - the sync check and sync-repair launch;
  - session slots around `run_unit`;
  - per-run status lines.
- `studios/game-dev/bin/overnight-channel.sh`: AC9's run resolution, and acceptance of any live run of the project.
- `studios/game-dev/bin/studio-state`: AC12's run-worktree stage pointer.
- `studios/game-dev/bin/studio-peers` (new), `studios/game-dev/hooks/peer-runs.sh` (new), `studios/game-dev/hooks/hooks.json`.
- `shared/omega/skills/autopilot/SKILL.md`: AC11, AC13, AC15, AC16.
- `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`: AC14.
- `studios/game-dev/skills/execute/SKILL.md`: §12 (AC23), the peers block in briefs (AC19), §1's mode list.
- `studios/game-dev/skills/studio/SKILL.md`: AC16's wording.
- `integrations/multica/bridge/mirror.py`: AC26.
- `docs/game-dev/overnight-events.md`, `README.md`, `integrations/multica/README.md`, `docs/game-dev/PROGRESS.md`.

### Failure handling

- Lock, slot and registry reclaim follow the existing liveness rule (`reg_live`, the gate lock's reclaim). A SIGKILLed run leaves its lock, slots and entry, and the next start or slot wait reclaims them.
- A sync-check git failure never stops a story: it is logged as `story_synced failed=<code>` and the landing check still guards the merge.
- `studio-peers` failures degrade to `<slug>: unreadable`. The hook and the preflight warning never fail a session or a start.

### Rejected alternatives

- **B — one long-lived runner with a queue.** Rejected by the operator after comparing speed, tokens and quality:
  - it rewrites the frozen-manifest core (the `Docs:` pin, the preflight, the lane scheduler);
  - it bundles unrelated stories into one integration PR;
  - it makes one runner a single point of failure.
- **Per-story STATE.md during planning (`STUDIO_STORY` in brainstorm and plan).** Rejected for AC12's per-worktree pointer:
  - the epic form writes one spec for several stories, and a spec-slug ledger;
  - `next` classifies from those files;
  - so story-keyed planning state would change four skills and `next`, while the per-worktree pointer changes only `studio-state`'s root rule.
- **File claims that hold a story** whose files another run is changing. Rejected by the operator: it serializes overlapping work and can idle a run for hours. Awareness plus sync covers the common case.
- **More than one gate slot.** Rejected by the operator: Godot tests would compete for CPU and the import cache.

## Tuning knobs

- `overnight.max_sessions`: default 6, range 1–8.
- The peers block's path limit (40) and the preflight overlap list limit (20): constants in the scripts.

## Assets and audio

n/a.

## Test strategy

Shell suites under `tests/`, with stubbed units and a fixture git remote, as the lanes and channel suites do today:

- Locks: two manifest runs start, each holding its own lock. Single-plan and manifest exclusivity both ways. `reg_write` keeps a live sibling's entry and drops a dead one's.
- Preflight: refusals for a duplicate slug, id or branch, and for a `run/` story branch. The overlap warning lists paths and `and N more`.
- Verbs:
  - `status` with zero, one and two runs, and `status <slug>`;
  - bare `stop` with one run, and with two (refuses, exit 1);
  - `stop <slug>` and `stop --all`;
  - channel run resolution by `--run`, by story id, and by the single run.
- `next` prints the slug forms.
- `studio-state`: a run worktree on `run/x` has its own STATE.md, and the main checkout's is untouched. A non-run linked worktree keeps today's root. `STUDIO_STORY` state stays at `<root>`.
- Session slots:
  - the cap is enforced across two runs, with stub start and end stamps never overlapping beyond the cap;
  - a dead owner's slot is reclaimed;
  - a stop ends a slot wait;
  - every exit path releases the slot.
- Sync:
  - a clean merge with no session, plus its `story_synced` event;
  - a dirty worktree is skipped;
  - a conflict launches one sync-repair stub, and a `Synced:` line counts as progress;
  - a `Stop:` line or no progress stops the story;
  - integration runs check both refs.
- `studio-peers`: default and `--files` output from a fixture of two runs; an unreadable run.
- Hook: the block appears in a unit session's SessionStart output; there is no output with no peer run or outside a unit; exit 0 on bad input.
- Bridge: two runs in one root are both mirrored, `story_synced` becomes a comment, and `session_wait` is ignored.
- The Milestone gate's step 2 fixture round trip.

## Risks

- **Semantic conflicts that merge cleanly.** A clean sync merge can still break behaviour. The next task's `Verify:` tests and the story's finish gate catch most cases, and the sync never bypasses a gate.
- **Gate queue.** With several runs the gate lock is the throughput ceiling, and runs wait for each other's tests. This is accepted: the operator chose one gate slot.
- **Usage quota.** Six concurrent units plus their subagents spend a usage window quickly. `max_sessions` and `run_usd` are the controls.
- **Skill cwd.** A stage command must change into the run worktree reliably in a fresh session after `/clear`. AC14's check (`--show-toplevel`) turns a miss into a refusal, never into writes in the wrong checkout.

## Not doing

- Dependencies between runs. A story that needs another run's work is planned after that work lands.
- More than one gate at a time.
- Runs messaging each other, or file claims that hold work.
- Several single-plan runs at once.
- Migrating runs that are live when this change is installed (AC28).

# Overnight lanes — Spec

Date: 2026-10-01
Status: Approved 2026-10-01 (revision 2: three reviews folded in, user rulings A, B, C, F applied)
Milestone: Plan 3 — Content (studio tooling; follows bundle 2, #17)
Classification: architectural

Issue: #19. Bundle 2 (#17, `2026-10-01-overnight-runner.md`) made one approved
plan run overnight as one fresh headless session per unit. A live phoenix run
(KAN-1470, six stories, integration mode) showed what it lacks: autopilot had
no rule for several stories, read "never merge" as covering the integration
branch, fell back to one long in-session run with an improvised keep-awake,
and invented PR targets until corrected twice.

## Milestone gate

PROGRESS.md has no exit criterion for runner work; this feature's own, agreed
in brainstorm (criteria 1 and 2 reworded by ruling F: landings are serialized,
not ordered by manifest row):

1. `sh tests/run_all.sh` is green, including the stub-`claude` lane suite
   (both run modes, dependencies, serialized landing, a stopped lane).
2. One live run in a throwaway Godot project with three stories — one with
   no plan (planned with the user through autopilot's planning loop), one
   half-done, and one depending on the first — reaches its end state with
   no human input once the plans are approved, in each run mode: integration
   (one draft PR integration → main, nothing merged into main, one full
   gate) and direct (each story merged into main through the project's merge
   command, each dependent after its dependency); every session's first turn
   is under 90k context.
3. Autopilot in a studio never sets a session-mode `autopilot`, never starts
   a keep-awake, and never executes stories in its own session; work that
   does not fit stops with a stated reason.

## Purpose

Autopilot takes any set of stories — not started with an approved plan,
half-done with an approved plan, or brand new with no spec or plan — and
gets them to a merged or reviewable state. Stories without an approved plan
are brought through the studio's own brainstorm and plan skills with the
user: one spec per epic, one plan per story, one stage per session. Once
every plan is approved, the run goes by itself: every unit of every story is
a fresh headless session that reads only its own slice of the plan, so each
piece of work completes and its context is discarded — no session carries
the run, and a crash, `/clear` or closed terminal loses at most one unit per
lane. The runner itself, not a Claude session, lands clean merges and runs
the integration final step; Claude is launched only to resolve a conflict or
fix a red gate. One question decides where stories land, chosen for the
machine: integration (each story is tested once by its own finish gate and
merged into an integration branch with no landing gate; one full gate on the
combined head and one draft PR into `main` at the end — for a slow laptop,
where each `merge.sh` gate costs 15–20 minutes) or direct (each story lands
on `main` through the project's merge command, which is its one gate — for a
fast laptop). Dependency chains run in parallel lanes, as many as the user
allows, while one machine-wide gate lock lets only one test or gate run at a
time.

## Core-loop delta

The user's loop: today `approve one plan → /omega:autopilot → studio-overnight
start → morning`. After: `/omega:autopilot (mode, lanes, stories) → the
printed stage command (/game-dev:brainstorm <id> once per epic, then
/game-dev:plan <id> per story, each ending with /clear and the next printed
command) → /omega:autopilot when every plan is approved → start (detached,
or the printed command) → morning: read report.md; integration: review and
land the one PR; direct: stories already on main`. A single-plan run is the
one-story case of the same loop.

## Player verbs

- Added: autopilot phase 1 asks **integration or direct** and **how many
  lanes**, and writes a committed **run manifest** (`docs/runs/<slug>.md`:
  stories, dependencies, mode, target, docs revision) plus a pointer
  `.studio/run`; `studio-overnight next` prints each story's planning class
  and the one next command; `/game-dev:brainstorm <id>` writes one spec per
  epic with a `## Stories` table; `/game-dev:plan <id>` writes one plan per
  story and ends with the question sweep and the next command;
  `studio-overnight start <manifest>` runs the manifest as **lanes**
  (dependency chains); the runner lands stories and runs the integration
  final step itself; `studio-brief` gives a unit exactly its inputs; one
  machine-wide **gate lock**; config `overnight.max_lanes`,
  `overnight.model_*`, project config `merge_command`; plan tasks carry
  `Spec:` line ranges and `Review: task|final`.
- Changed: no session merges anything in any run mode — in a direct run the
  runner merges into `main` only through the project's merge command; in an
  integration run nothing is merged into `main`, and the runner merges
  stories into the integration branch. Under a lane, the final-review unit
  runs no tests and the finish runs the story's one gate (integration) or no
  gate (direct: the merge command is the gate); per-task reviews run only for
  `Review: task` tasks. `studio-overnight status` shows every lane and story.
  Feature ledgers under a lane are keyed by story id.
- Removed: autopilot's in-session fallback inside a studio; autopilot's rule
  that story PRs target the integration branch under autopilot; the separate
  question-sweep pass after planning; a Claude session per landing and for
  the integration final step; the deny list's per-mode tags; PROGRESS entries
  per story under a lane (one per run instead).

## Design

n/a — studio tooling, no game loop. `game-dev:game-designer` not dispatched.

## Level

n/a

## Failure and recovery

- **A story stops** (its `Stop:` line, no progress, the run budget, or a
  landing that stays conflicted or red after its one repair): the rest of its
  chain is skipped, chains waiting on it are skipped, every other lane
  continues; the run ends when no lane has work. `report.md` names each
  story's ending and each skipped story's blocking dependency.
- **A lane process dies** (any exit, signal or shell error): its EXIT trap
  marks the running story `stopped: lane crashed (<rc>)` and the rest of its
  chain skipped; the parent's `wait` returns for that pid, so the runner never
  hangs; a story still without an ending after every lane has exited is
  marked the same way by the parent. Chains waiting on it see the marker, or
  see the claiming lane's pid dead, and skip.
- **Crash or closed terminal:** bundle 2's stale-lock rule; the next `start`
  derives every story's start from its studio state and from git/GitHub
  (a merged PR or a story branch already in the target is landed, whatever
  the runner recorded). At most one unit per running lane is lost; a landing
  or the final step interrupted mid-way finishes on resume without a second
  merge, a second PR or a duplicate gate when the head is unchanged.
- **Ctrl-C, `studio-overnight stop`, SIGTERM:** the runner's trap creates the
  stop file; every lane reads it before each launch, each landing and each
  wait tick, so each running unit finishes and nothing new starts. Lane
  processes also exit when the runner pid is gone.
- **Merge conflict or red landing gate** (integration: the story against the
  integration head; direct: the merge command refuses): the runner launches
  one repair unit (`/game-dev:execute --land`) that merges the target into
  the story branch, fixes, runs the story's gate and pushes; the runner
  retries the landing once; a second failure stops that story.
- **Integration final step fails** (`origin/main` conflict or red gate on the
  combined head): one repair unit, then one more gate; still red → the run
  opens the draft PR anyway, title prefixed `[red]`, the failure in its body —
  the user lands it, so the user sees it.
- Cost to the user: at most one unit per lane; nothing reaches `main` that the
  project's merge command did not gate.

## Teaching

Autopilot's phase 1 asks the integration question and the lane count, each
option with a one-line consequence (integration: each story tested once by
its own gate, one full gate at the end, one PR to land in the morning; direct:
one merge-command gate per story, 15–20 minutes each on phoenix; lanes:
parallel chains, while tests still run one at a time). Every planning stage
ends by printing `/clear`, then the exact next command
(`/game-dev:plan <id>`, or `/omega:autopilot` when every story is planned).
When every plan is approved it asks how to start the run: **autopilot starts
it** (detached from the chat; no terminal, no Ctrl-C, watch with
`studio-overnight status`) or **print the command** (paste it into a plain
terminal; live output, Ctrl-C stops after the running units). Either way it
says what the run may and may not merge in the chosen mode, `status` /
`stop`, where `report.md` lands, that the chat can now close, and to keep the
laptop on power with the lid open. `studio-overnight --help` states both
modes. The router names a live run as today.

## Input and platform

As bundle 2: macOS first, POSIX `sh` (macOS `/bin/sh` is bash 3.2), Claude
Code ≥ 2.1.287 headless flags; git ≥ 2.38 (`git merge-tree --write-tree`;
preflight refuses older). Phoenix's merge command is
`.github/scripts/merge.sh <pr>` (it merges only when CI is green or its full
local gate — "Mode 2" — is green); the runner runs it, not a session.

## Feel targets

| Target | Value | How it is checked |
|--------|-------|-------------------|
| Unit start context | task unit ≤ 60k; every other unit ≤ 90k | live run (first-turn usage in each unit's jsonl) |
| Plan or spec read whole by a task or final-review unit | 0 | unit (stub): `studio-brief` output pinned; live run: no `Read` of the plan or spec path without `offset` in task/final jsonl |
| Lanes at once | `max_lanes` (0 = one per chain) | unit (stub) |
| Sessions that carry more than one unit | 0 (complete, then forget) | unit (stub): one launch per unit |
| Claude sessions per clean landing | 0 | unit (stub) |
| Test or gate runs at once in a project, all lanes and the runner | 1 | unit (stub): overlapping lock intervals = 0 |
| Studio test runs per story | integration: 1 (finish) + 1 per repair; direct: 0 + the merge command's gate | text contract on execute §5/§7; live run: `studio-test` count per story jsonl |
| Full gates on the combined head (integration) | 1, +1 after a repair | unit (stub) |
| Runner overhead between units of a lane | ≤ 5 s | unit (stub) |
| Dependent chain start after its last dependency lands | ≤ 5 s | unit (stub) |
| Morning report on every ending, every story named | 100%, a lane crash included | unit (stub) |

## References

- Bundle 2's spec: the unit contract, the progress signature, the lock, the
  watchdog — unchanged per story.
- Merge queues (GitHub merge queue, bors): changes land one at a time against
  the latest target head, each gated by the landing.
- CI fan-out/fan-in: independent jobs in parallel, a dependent job starts
  after its inputs land.

## Acceptance criteria

1. Autopilot phase 1, in a studio, asks integration or direct and the lane
   count in one question, writes the run manifest `docs/runs/<slug>.md` and
   the pointer `.studio/run`, never sets a session-mode `autopilot`, never
   starts a keep-awake, and — once every story is planned — asks how to
   start: **autopilot starts it** (preflight runs in the foreground first; the
   detached runner inherits no variable named `CLAUDECODE`, `CLAUDE_CODE_*`,
   `OMEGA_*` or `STUDIO_*` from the chat; `studio-overnight status` exits 0
   within 10 s before phase 1 reports success, else it prints the command) or
   **print the command** (the absolute `cd '<dir>' && '<abs>' start
   <manifest>`). The environment half is stub-tested; surviving the chat's
   close or `/clear` is live-only (T1 probe and milestone run).
2. "In a studio" has one written definition, cited by every branch of the
   autopilot skill (text contract).
3. Planning loop, one stage per session: `studio-overnight next <manifest>`
   classifies each row as `brainstorm`, `plan` or `planned` from files and
   ledger lines alone and prints the one next command; brainstorm runs once
   per epic and writes one spec with a `## Stories` table naming every story
   it covers; `/game-dev:plan <id>` writes one plan for that story (header
   `Story: <id>`), then in the same session runs SDD's conflict scan and the
   question sweep into `## Decisions`, ledgers `Decisions swept <id>`, and
   prints `/clear` plus `next`'s command. Phase 1 discovery reads
   `.studio/run`, so it survives `/clear`. There is no in-session execution
   fallback in a studio. (`next`: stub; the skills: text contracts.)
4. `STUDIO_STORY=<id>` makes `studio-state` read and write only
   `.studio/stories/<id>.md` and the ledger `.studio/ledger/<id>.md`; with it
   unset every verb is byte-compatible with today (`state_test.sh`).
5. Lanes are dependency chains, built by the rule in Architecture; up to
   `max_lanes` lane processes (0 = one per chain) claim chains in order and
   run each chain's stories one after another; each story is the bundle-2
   unit loop with one fresh session per unit, then its landing.
6. A chain whose first story depends on stories in other chains starts that
   story only after every dependency has landed, from `origin/<Target>` at
   that moment; a dependency that stopped or was skipped skips the chain.
7. The runner lands a shipped story with no Claude session when the merge is
   clean — integration: a `--no-ff` merge commit built with `git merge-tree`
   and `git commit-tree`, pushed to `integration/<slug>`; direct: `gh pr
   ready` and the project's `merge_command <pr>` under the gate lock — one
   landing at a time per run. A conflict or a refused merge command launches
   one repair unit (`execute --land`), then one retry; a second failure stops
   the story.
8. A landing is idempotent: a story whose PR is already `MERGED` (direct) or
   whose branch head is already in `origin/<Target>` (integration) is
   recorded landed with the existing merge commit, with no merge, no merge
   command and no repair.
9. Integration final step, run by the runner when no lane has work, no stop
   was requested and at least one story landed: in its own worktree, merge
   `origin/main`, one PROGRESS unit, the full gate under the gate lock (one
   repair unit and one more gate on a conflict or red), push, then one draft
   PR into `main` with a section per landed story, a list of stories that did
   not land, and `[red]` when red — `gh pr edit` when that PR already exists;
   a resume with an unchanged integration head and an open PR skips it.
   Nothing is merged into `main`; the final PR is never merged by the run.
10. One gate lock per project (`STATE_ROOT/.studio/gate.lock`, `mkdir`):
    `studio-test`, `studio-run`, the runner's `merge_command` and the final
    gate each hold it, so at most one test or gate run happens at a time
    across lanes and the runner; a lock whose holder pid is dead is
    reclaimed; a holder's own children (`STUDIO_GATE_HELD`) do not re-take it.
11. Each story's code is gated once by the gate that matters: under a lane,
    the final-review unit runs no tests; integration — the finish unit's gate
    is the story's one test run (plus one per repair), and the final step's
    gate is the one full gate; direct — the finish runs no gate and the merge
    command is the landing gate. (Text contract on execute §5/§7; gate counts
    from the live run's jsonl.)
12. A task unit is given only `studio-brief task <n>`: the plan's
    `## Global Constraints` and `## Decisions`, the `### Task <n>` block, and
    the spec line ranges on that task's `Spec:` line; the final-review unit
    only `studio-brief final`: the spec's `## Acceptance criteria` (the
    story's rows when the spec has `## Stories`), the story's `## Stories`
    row, the ledger's `Ruling:` and deferred-minor lines, and the diff command
    against `origin/<Target>`. Execute §8 forbids reading the plan or spec
    whole under `--one`. A stub test pins `studio-brief`'s output on a fixture
    (task 3's text present; tasks 2 and 4, the uncited spec sections and,
    for `final`, the plan absent).
13. Every unit launch carries `--model` by unit kind from config (defaults:
    task `sonnet`, final review `opus`, finish `sonnet`, repair `opus`,
    progress `sonnet`); execute dispatches the per-task reviewer with
    `model: "opus"`.
14. Execute runs a per-task review only for a task marked `Review: task`
    (a task with no `Review:` line counts as `task`); `Review: final` tasks
    fold into the final review. The plan skill marks risky tasks (a new
    seam, cross-system, gameplay feel, data or schema, importer) `task` and
    the rest `final` (text contracts).
15. A stopped story leaves the other lanes running; the rest of its chain
    and every chain waiting on it are skipped and named in `report.md`.
16. A lane process that dies without writing a story ending, a SIGKILLed
    runner, and a Ctrl-C each end in a written ending: the runner never
    blocks on a dead lane, lanes stop launching when the stop file exists or
    the runner pid is gone, and `report.md` is written on every ending
    (stub).
17. `studio-overnight status` prints every story in manifest order: lane,
    state (`queued`, `waiting`, `running`, `landing`, `repair`, `landed`,
    `stopped`, `skipped`), unit, `task k/N`; the gate lock's holder; the
    run's spend.
18. `report.md` has the run's ending, mode, target and spend, the final PR
    (integration) or each landed merge commit (direct), one section per
    story, the resume command when not done, and a `## Cleanup` section: the
    one command that deletes the run's remote branches (`run/<slug>`, the
    integration branch, every landed story branch), to run after the final PR
    is landed. The run itself never deletes a remote branch.
19. A single-plan run without a manifest works as in bundle 2, except the
    deny-list additions (AC21) and the `run_usd` default (AC25).
20. The attended (non-autopilot) integration flow is unchanged: per-story PRs
    into the integration branch through `omega:local-merge` with the user's
    confirmation.
21. The session deny list is one data file with no mode tags: every session
    in every mode is denied `gh pr merge`, the `gh api` merge endpoint, a
    push to the default branch, and the merge program by its basename;
    `{default_branch}` with no value is a preflight refusal.
22. Every "never merge" in the omega and studio skills names `main` (the
    default branch) and states that sessions never merge in any run mode and
    that the runner lands (text contracts).
23. Under a lane, execute §0's clean-tree check names only the story's own
    ledger file, the docs come from the manifest's `Docs:` revision (fetched
    from `origin/run/<slug>`), a path checkout of docs happens only when §0
    creates the branch (an existing branch's ledger is never overwritten), and
    `git worktree add` uses `--no-track`.
24. A half-done story (an existing branch, `T<n> complete` lines, possibly a
    `final review done` or `shipped` line, possibly already merged) is seeded
    in its own worktree with `studio-state check --rebuild` under
    `STUDIO_STORY`: `task 0/N` first, then the longest contiguous run of
    completed tasks; a gap is a stated stop. Its lane resumes at its next
    unit, landing or landed; completed tasks are never re-run.
25. `overnight.run_usd` defaults to 0 (no run-wide cap) in both modes; a
    value > 0 makes each lane refuse a launch when the sum of all lanes'
    `units.tsv` costs plus `session_usd` exceeds it. `session_usd`, the
    no-progress stop and the session timeout apply as in bundle 2.
26. One launch per unit: no session the runner starts carries more than one
    task, final review, finish, repair or progress unit (stub).

## Architecture

(from `game-dev:architect`.) Same translation as bundle 2: files and owners
for the scene tree, the runner's per-story loop for the state machine,
environment + ledger lines + marker files + exit codes for signals,
`config.json` and the manifest for the `Resource`.

**Ownership.** Bundle 2's split holds per story. The runner owns the run
lock, the stop file, `RUN_DIR`, the persistent run record
`STATE_ROOT/.studio/runs/<slug>/`, chain building, lane processes, landings
(merge commits and pushes to the integration branch; `gh pr ready`, the
merge command), the integration final worktree, its merge of `origin/main`,
its gate, push and PR, `status` and `report.md`. It reads studio state and the
manifest and writes neither. `studio-state` stays the single writer of
studio state; with `STUDIO_STORY=<id>` it writes that story's state and
ledger and nothing else. Execute owns a story's branch, commits, ledger, its
draft PR (direct) and repairs (`--land`). The gate lock is shared: taken by
`studio-test`, `studio-run` and the runner. Autopilot phase 1 owns the
manifest, `.studio/run` and the story files' seed. Brainstorm and plan own
the spec's `## Stories` table and the plan's `Story:` header. No unit run by
the runner writes in `START_DIR` except an uncommitted pre-isolation `Stop:`
line in its own story's ledger file (bundle 2's rule).

### Before / after

```
before: STATE.md (main checkout): ONE stage/spec/plan/task/branch per project
        studio-overnight start          → one plan, units T1..TN, final-review, finish (draft PR)

after:  STATE.md                        → attended slot (planning; single-plan mode, untouched)
        .studio/stories/<id>.md         → one per manifest story (same header format)
        .studio/ledger/<id>.md          → its feature ledger (keyed by story, not spec)
        .studio/run                     → pointer to the active manifest (phase 1)
        .studio/gate.lock/              → one test/gate run at a time (shared)
        .studio/runs/<slug>/            → runner's persistent record: landed.tsv, final, done
        studio-overnight start <manifest>
          chains: [A → C] [B] [D waits on A,B]
          lane 1 (claims chain 1)  A: execute --one × (T1..TN, final, finish) → runner lands A → C: …
          lane 2 (claims chain 2)  B: … → runner lands B → claims chain 3: D waits for A,B landed → …
          parent: plain `wait` per lane pid
          integration, last: runner final step (merge origin/main, progress unit, gate, draft PR → main)
          direct, last:      progress unit on progress/<slug> → runner lands it like a story
          report.md; unlock
```

### Signals

| Topic | Payload | Emitter | Listeners |
|-------|---------|---------|-----------|
| `execute_story_shipped` | ledger `shipped <branch or PR url>` + `stage idle` | finish unit | lane (→ landing) |
| `execute_unit_stop` | ledger `Stop: <reason>` | any unit | lane (bundle 2 `STOPS`) |
| `execute_story_repaired` | ledger `Repair: <summary>`, pushed head | repair unit | lane (→ one retry) |
| `lane_story_landed` | line `<id>\t<Target>\t<merge sha>` in `runs/<slug>/landed.tsv` | lane process | waiting chains, final step, status, report, resume |
| `lane_story_ended` | `RUN_DIR/stories/<id>`: `stopped <reason>` / `skipped <dep>` / `stopped: lane crashed (<rc>)` | lane process (EXIT trap for crashes); parent after `wait` | waiting chains, status, report |
| `lane_chain_claimed` | `RUN_DIR/claims/<k>/pid` | lane process (`mkdir`) | other lanes, waiting chains (`kill -0`) |
| `runner_stop_requested` | `STATE_ROOT/.studio/overnight.stop` exists | INT/TERM trap, `studio-overnight stop` | every lane: before launch, landing, wait tick |
| `gate_lock_held` | `STATE_ROOT/.studio/gate.lock/{pid,who}` | `studio-test`, `studio-run`, runner | the same, `status` |
| `runner_final_opened` | `runs/<slug>/final`: `<integration head> <PR url> <green or red>` | runner | resume, report |
| `runner_run_done` | `runs/<slug>/done` | runner | phase 1 discovery (ignores a done pointer) |

### Per-story studio state (ruling C)

- **`STUDIO_STORY=<id>`** (id: `^[A-Za-z0-9._-]+$`, the manifest's Story
  column) makes `studio-state` use `STATE_ROOT/.studio/stories/<id>.md` in
  place of `STATE_ROOT/.studio/STATE.md` for every verb, and the feature
  ledger `.studio/ledger/<id>.md` (in the checkout the command runs in) in
  place of `.studio/ledger/<spec slug>.md`. Same header keys
  (`stage spec plan task branch milestone`), same writers. Several stories
  may share one spec. Unset or empty → exactly today's code path
  (single-plan mode, byte-compatible; `state_test.sh` stays green
  unmodified).
- With `STUDIO_STORY` set: `init` creates only the story file (no
  `config.json`, no ledger dir) and adds `.studio/stories/` to
  `.git/info/exclude` once (never the tracked `.gitignore`); every other
  verb on a missing story file exits 1 `no story <id>`.
- `check --rebuild` under `STUDIO_STORY`: from `task -` it counts N from the
  plan (`### Task` headings, as the plan skill counts), sets `task 0/N`, then
  `task k/N` with k the longest contiguous run `T1..Tk complete`; a
  `T<m> complete` with m > k + 1 exits 1 `ledger gap: T<k+1> missing`.
  Single-plan `--rebuild` is unchanged.
- Isolation is by selection: the runner exports `STUDIO_STORY` per unit;
  Claude Code's hooks (`session-start.sh` reads `studio-state get stage`)
  inherit it. `guard-state.sh` adds `*/.studio/stories/*.md` to its
  protected paths.
- **Execute §0 under a lane:** the clean-tree check is
  `git status --porcelain -- <spec> <plan> .studio/ledger/<id>.md
  .studio/config.json` — another lane's uncommitted `Stop:` line is never
  seen. The runner's preflight checks every story's ledger file.
- **Planning runs on `STATE.md`.** Brainstorm and plan are attended and use
  `STATE.md` as today; their ledger lines (`spec approved`, `plan approved
  <plan>`, `Decisions swept <id>`) go to the spec-slug ledger, one file per
  epic, each plan line naming its plan. Phase 1 sets `STATE.md` (`set stage
  plan`, `set spec`) before each `/game-dev:plan <id>` of an already-approved
  spec, and runs `studio-state reset --keep-ledger` after seeding, so the
  spec ledger survives for the epic's next plan.
- **Seeding** (phase 1, after every row is `planned`), per story through
  `studio-state` with `STUDIO_STORY=<id>`: `init`; `set spec`, `set plan`;
  ledger `spec approved <spec>`, `plan approved <plan>`, `Decisions swept
  <id>` copied from the spec ledger; then:
  - **not started:** `stage plan`, `task 0/N`, `branch -`;
  - **half-done:** phase 1 creates the story's worktree at the path §0 uses
    (`git worktree add <path> <Branch>`; refused with "switch that checkout
    off <Branch> first" when another checkout holds it); when the branch has
    `.studio/ledger/<spec slug>.md` and no `<id>.md`, phase 1 `git mv`s it
    and commits `chore(studio): ledger keyed by story`; then, in that
    worktree: `set branch`, `stage execute`, `check --rebuild` (AC24); `N/N`
    with `final review done` resumes at finish; a `shipped` line makes it
    `stage idle` (it waits to land); a merged PR or a head already in
    `origin/<Target>` is landed (the runner records it at start). An open
    bundle-2 PR into `main` in an integration run is named in `report.md`,
    never closed.

### The run manifest

- **One path:** `docs/runs/<slug>.md`, both modes. Phase 1 commits it with
  the specs, plans and story-ledger seeds on branch `run/<slug>` (created in
  the phase-1 checkout when it is on the default branch, so the user's
  `main` never diverges), pushes `run/<slug>` to origin, then writes that
  commit's sha as `Docs:` and commits the manifest once more. The runner
  reads the manifest and `Docs:` once at start into `RUN_DIR/manifest.md`;
  lanes read docs only from the `Docs:` revision, so `START_DIR` moving
  mid-run changes nothing. The attended integration skill's
  `docs/integrations/<slug>.md` is a different file and is not touched.
- **Format** — header lines the runner parses (`sed`, first match), then the
  table (columns found by header name):

  ```markdown
  # Run: <slug>

  Mode: integration            # or: direct
  Target: integration/<slug>   # direct: the default branch
  Docs: <sha>
  Goal: <goal>

  | Story | Branch | Ticket | Spec | Plan | Depends on |
  |-------|--------|--------|------|------|------------|
  | KAN-1471 | KAN-1471-dash | KAN-1471 | docs/game-dev/specs/…md | docs/game-dev/plans/…md | - |
  | KAN-1473 | KAN-1473-combo | KAN-1473 | docs/game-dev/specs/…md | docs/game-dev/plans/…md | KAN-1471 |
  ```

  `Spec` and `Plan` are `-` while planning; `studio-overnight next` resolves
  them by the spec's `## Stories` row and the plan's `Story: <id>` header
  (two matches = a stated refusal), and phase 1 fills every cell before the
  run. `Depends on` is `-` or comma-separated Story ids of **earlier rows**;
  a cycle cannot be written. No status column: planning class comes from
  files and ledgers (`next`), run progress from studio state and the
  runner's record.
- **Immutable during the run.** No unit and not the runner edits the
  manifest. Final statuses go into the final PR body (integration) and
  `report.md` (both).
- **`.studio/run`:** one line, the manifest path, written by phase 1 when it
  creates the manifest, in `.git/info/exclude`. Phase 1 discovery reads it;
  a pointer whose `runs/<slug>/done` exists is ignored and a new run starts.

### Chains and lanes (ruling F)

**Chain rule.** Walk the rows in manifest order. A row with no dependency
opens a new chain. A row with exactly one dependency that is currently the
last story of its chain is appended to that chain. Every other row (two or
more dependencies, or a single dependency that already has a successor in
its chain) opens a new chain whose first story **waits** until each
dependency's `lane_story_landed` line exists. Only a chain's first story can
wait, and it waits only on rows earlier than itself, which belong to chains
with an earlier first row; lanes claim chains in that order, so the wait
graph has no cycle and any `max_lanes` ≥ 1 completes.

**Lane process.** The parent starts `L` background lane processes (`L` =
chain count when `max_lanes` is 0, else `min(max_lanes, chains)`), each
with its `trap` for EXIT/INT/TERM/HUP set first. A lane loops: claim the
next unclaimed chain (`mkdir RUN_DIR/claims/<k>`, its pid inside); for each
story in the chain, the per-story machine below; stop claiming when none is
left, the stop file exists or the runner pid is gone. The parent does a plain
`wait <pid>` for each lane in turn (a trapped signal interrupts `wait`; the
trap creates the stop file and the loop re-waits the same pid), then marks
any story with no ending `stopped: lane exited <rc>`, then the final step,
then the report.

**Per-story machine** (runner-owned, `RUN_DIR/stories/<id>`; distinct from
the story's studio state, which the runner never writes):

```
QUEUED ─chain claimed→ WAITING ─every dep landed→ RUNNING ─stage idle ∧ shipped→ LANDING ─clean→ LANDED
                          │ a dep stopped/skipped,             │ (bundle 2 CHECK/LAUNCH/        │ conflict / merge
                          │ or its lane dead w/o ending        │  CLASSIFY, STUDIO_STORY=<id>)  │ command refused
                          ▼                                    ▼                                ▼
                       SKIPPED          STOPPED ◄── Stop: / noprog / budget / user / crash ── REPAIR (one unit)
                                           ▲                                                    │ repaired
                                           └──────────── second conflict or refusal ── LANDING (one retry)
STOPPED or SKIPPED → every later story in the chain SKIPPED
```

- **Waiting** is a 5 s shell poll of `landed.tsv`, the dependencies' ending
  markers and their claiming lanes' pids (`kill -0`), and the stop file — no
  session, no tokens.
- **Signature:** bundle 2's `SIG` with `STUDIO_STORY=<id>`; `STOPS` from the
  story's ledger in `FEATURE_DIR` (`STUDIO_STORY=<id> studio-state worktree`)
  and its ledger file in `START_DIR`.
- **Resume** derives each story's start: in `landed.tsv` and confirmed, or
  confirmed by git/GitHub alone (then appended) → LANDED; `stage idle ∧
  shipped` → LANDING; else QUEUED. Confirmation: integration —
  `git merge-base --is-ancestor origin/<Branch> origin/<Target>`; direct —
  `gh pr view <Branch> --json state` is `MERGED`.
- **Process groups:** each session leads its own process group so the
  watchdog kills only it. Bundle 2 got this from `set -m` in the runner's
  shell; under a lane it comes from `set -m` in the lane subshell, verified
  by T1's probe on a terminal; when the probe fails, `run_unit` launches
  through `perl -e 'setpgrp; exec @ARGV'`.
- **Git contention:** every runner git call that fails with `could not lock`
  or `cannot lock ref` is retried three times (1, 2, 4 s); execute §0, §7 and
  §9 state the same rule.
- **Budget** (only when `run_usd` > 0): before each launch a lane sums the
  cost column of `RUN_DIR/lanes/*/units.tsv`; `spent + session_usd >
  run_usd` → that story `stopped: run budget`, and the lane claims no more
  chains. No lock: the overshoot is bounded by `(L − 1) × session_usd`.
- **Run ending:** `done` = every story LANDED and (integration) the final PR
  open and green, (direct) the progress PR landed or no `PROGRESS.md` → exit
  0 and `runs/<slug>/done`; otherwise `partial: <n> landed, <m> stopped, <k>
  skipped` or bundle 2's endings → exit 1.
- **Run directory** (manifest mode): `manifest.md`, `chains`, `claims/<k>/`,
  `stories/<id>`, `lanes/<k>/{current,cpid,units.tsv,<n>-<id>-<label>.jsonl,
  <n>-<id>-<label>.err,<id>-land.log}`, `report.md`, `runner.log` (detached).
  Single-plan mode keeps bundle 2's flat layout.
- **`status`:** one line per story in manifest order — `<id>  lane <k>
  <state>  unit <label>  task <k/N>` — then `gate: <holder or free>`,
  `spent: $<sum>`, the runner pid.
- **`report.md`:** the run's ending, mode, target, spend; integration: the
  final PR url; direct: each landed merge commit; one `## <id>` section per
  story (ending, branch, units table, rulings, play list, landed sha or why
  it did not land; skipped stories name the blocking dependency); open
  bundle-2 PRs; the resume command `cd <START_DIR> && <runner> start
  <manifest>` when not done; `## Cleanup`.

### Landing (ruling A)

The runner lands, holding `RUN_DIR/land.lock` (`mkdir`; one landing per run
at a time). Lock order is always land lock, then gate lock; sessions take
only the gate lock, so no cycle. The land lock is held through a repair and
its retry, so the retry lands against the head the repair merged.

| Step | Integration | Direct |
|------|-------------|--------|
| 0 Already landed? | `git fetch origin`; `merge-base --is-ancestor origin/<Branch> origin/<Target>` → the merge sha is the oldest `git log --merges --ancestry-path origin/<Branch>..origin/<Target>` commit → step 4 | `gh pr view <Branch> --json state,mergeCommit,isDraft,number`: `MERGED` → step 4 with `mergeCommit` |
| 1 Clean? | `git merge-tree --write-tree origin/<Target> origin/<Branch>`: exit 1 → repair | same against `origin/<default>`: exit 1 → repair |
| 2 Land | `git commit-tree <tree> -p origin/<Target> -p origin/<Branch> -m "Merge <Branch> (<id>) into <Target>"`; `git push origin <sha>:refs/heads/<Target>` (no checkout touched; a rejected push → fetch and step 0 once, then stop) | `gh pr ready <n>` when `isDraft`; take the gate lock; run `<START_DIR>/<merge program> …` with `<pr>` → `<n>`, cwd the story worktree, `STUDIO_GATE_HELD` set, output to `<id>-land.log`; release |
| 3 Verify | — | whatever the exit code: `gh pr view` → `MERGED` and `git merge-base --is-ancestor <sha> origin/<default>` after a fetch; not merged → repair (`STUDIO_REPAIR=red:<log>`) |
| 4 Record | `lane_story_landed` line | same |

The merge program always runs from `START_DIR`'s copy, never the story
worktree's, so a story cannot change its own landing gate. The runner writes
no ledger line: `landed.tsv` plus the git/GitHub confirmation is the record,
and survives a merge command that deletes the branch.

**Repair unit = `/game-dev:execute --land`** (new §9), launched with
`STUDIO_STORY`, `STUDIO_RUN` and `STUDIO_REPAIR=conflict` or
`red:<log path>`. Its own preconditions replace §0's stage gate: `stage
idle`, a `shipped` line, `STUDIO_REPAIR` set; it enters the feature checkout
through `studio-state worktree`. Steps: `git fetch origin`; `git merge
--no-edit origin/<Target>` (merge, never rebase: the branch is pushed and
force-push is denied); a fresh fixer (§5 step 5's owning role) resolves the
conflict or fixes the red output; the story's gate (§7 step 1, up to three
runs, under the gate lock); commit `fix(land): <summary>`; push; ledger
`Repair: <summary>` committed and pushed. Red after three runs → `Stop:`. It
never merges into the target and never runs the merge command.

### Integration final step and PROGRESS

Run by the runner once every lane has exited, no stop was requested, and at
least one story landed. Worktree `<STATE_ROOT>/.claude/worktrees/integration-<slug>`
(created `--detach`, or reused after a clean-tree check):

0. Idempotence: `runs/<slug>/final` names the current `origin/integration/<slug>`
   head and `gh pr list --head integration/<slug> --base main --state open`
   returns that PR → skip to the report.
1. `git fetch origin`; `git switch --detach origin/integration/<slug>`;
   `git merge --no-edit origin/main`. Conflict → `git merge --abort`, one
   repair unit `/omega:integration repair <slug>` (model `repair`) in this
   worktree; still conflicted → red, the integration head unmerged.
2. When `docs/game-dev/PROGRESS.md` exists: one progress unit
   `/game-dev:execute --progress` (§10, model `progress`) with
   `STUDIO_RUN` set and cwd this worktree: one `game-dev:producer` dispatch
   over every landed story (manifest, each spec and story ledger at its
   landed head), commit `docs(progress): <slug>`.
3. The full gate under the gate lock: `studio-test`, `studio-lint`,
   `studio-run --seconds 10` (execute §7 step 1's commands and exit rules).
   Red → one repair unit, then the gate once more; still red → red.
4. `git push origin HEAD:refs/heads/integration/<slug>`.
5. PR body, assembled by the runner with `sed`/`git show`, no session: per
   landed story its spec's `## Purpose` (at the `Docs:` revision), its
   ledger's `Ruling:` and `P<k> Play:` lines (`git show
   origin/<Branch>:.studio/ledger/<id>.md`), its merge sha; a section listing
   un-landed stories with their ending; the gate line. Open PR exists →
   `gh pr edit --title --body-file`; else `gh pr create --draft --base main
   --head integration/<slug>`. Red → title prefixed `[red]`.
6. Write `runs/<slug>/final`.

**One PROGRESS entry per run, both modes.** Under a lane, execute §7 step 3
is skipped. Integration: step 2 above, so the entry is gated by the final
gate and arrives in the one PR. Direct: after the last landing, the runner
creates `progress/<slug>` from `origin/main` in
`<STATE_ROOT>/.claude/worktrees/progress-<slug>`, runs the same progress
unit there, pushes, opens a ready PR into `main` and lands it as a story
(steps 0–4; a refusal leaves it open and named in `report.md`). Rejected:
an entry per story (parallel lanes append to the same spot, so every later
landing conflicts and needs a repair session).

### Gates (ruling B)

- **Gate lock** `STATE_ROOT/.studio/gate.lock/` (`mkdir`; `pid` and `who`
  inside): `studio-test` and `studio-run` take it on every invocation and
  release on exit (trap); while waiting they print `gate: waiting for <who>`
  to stderr each minute; a lock whose pid is dead is reclaimed (bundle 2's
  stale-lock rule). The runner takes it around the merge command and the
  final gate and exports `STUDIO_GATE_HELD=<its pid>`; a `studio-test` whose
  `STUDIO_GATE_HELD` names the live holder does not re-take it.
- **Godot `user://`:** studio-test and studio-run never overlap, so lanes'
  tests never share `user://` at the same time. Limit, stated in Risks: a
  Godot process an agent starts directly, outside `studio-test`/`studio-run`,
  is not covered.
- **Gate per story:** under a lane §5 step 1 (fresh `studio-test` and
  `studio-lint`) is skipped in both modes — implementers ran the tests per
  task, and the finish gate covers the fix wave. Integration: §7 step 1 runs
  once (the story's one test run). Direct: §7 step 1 is skipped; the merge
  command is the gate. Single-plan mode keeps both.
- **Long calls in a session:** a unit's `studio-test` can wait for the lock
  behind a 15–20 minute merge command. Unit sessions are launched with
  `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` set to
  `session_minutes` × 60000 (T1 probe: honoured under `-p`); the watchdog's
  `session_minutes` stays the outer bound.

### Unit inputs (ruling C, hard rule)

`studio-brief` (new, read-only) prints a unit's whole input, each part
headed by its `<file>:L<a>-<b>`:

- `studio-brief task <n>` — the plan's `## Global Constraints` and
  `## Decisions` sections; the `### Task <n>` block (to the next `### Task`,
  the same excerpt SDD's task-brief extracts); each range on the task's
  `Spec:` line (`<spec>:L<a>-<b>` or `<spec>§<heading>`). A missing range
  exits 1.
- `studio-brief final` — the spec's `## Acceptance criteria` (only the
  story's ACs when the spec has `## Stories`), the story's `## Stories` row,
  the ledger's `Ruling:` and deferred-minor lines, and the line
  `git diff origin/<Target>...HEAD`. No plan text.

Execute §8 under `--one`: the orchestrator reads only `studio-brief`'s output
and the files its implementer or reviewer reports name; it never reads the
plan or spec whole and never runs SDD's pre-flight conflict scan (the plan
session ran it; its rulings are in `## Decisions`). The task brief and the
per-task reviewer brief (§2, §4) are built from the same output.

### Models

The runner passes `--model` per unit kind from config: `model_task`
(`sonnet`) — the orchestrator and, by inheritance, its implementers;
`model_final` (`opus`); `model_finish` (`sonnet`); `model_repair` (`opus`);
`model_progress` (`sonnet`). Execute §4 dispatches the per-task reviewer of a
`Review: task` task with `model: "opus"`; `Review: final` tasks get no
per-task review. Single-plan mode passes `model_task` for tasks, the same
kinds otherwise.

### Launch lines

```
unit:     cd <START_DIR> && OMEGA_AUTOPILOT=1 STUDIO_RUN=<abs RUN_DIR/manifest.md> STUDIO_STORY=<id> \
            STUDIO_DOCS_REV=<sha> BASH_DEFAULT_TIMEOUT_MS=<ms> BASH_MAX_TIMEOUT_MS=<ms> \
            claude-gd -p "/game-dev:execute --one" --model <kind model> <bundle-2 flags> --disallowedTools <rules>
repair:   … same env + STUDIO_REPAIR=<conflict|red:<log>> … -p "/game-dev:execute --land" --model <model_repair>
progress: cd <final or progress worktree> && OMEGA_AUTOPILOT=1 STUDIO_RUN=<…> … -p "/game-dev:execute --progress" --model <model_progress>
final repair: cd <integration worktree> && … -p "/omega:integration repair <slug>" --model <model_repair>
```

The unit kind (task, final, finish) is known to the runner from the story's
state before launch (bundle 2's label), so it picks the model.
`OMEGA_RUN_MODE` is dropped: the merge rule no longer differs by mode for a
session.

### Deny list

The rules stay data in `overnight-deny.txt`, no mode tags. The runner
substitutes `{default_branch}` (from `origin/HEAD`; missing → preflight
refusal) and `{merge_basename}` (basename of `merge_command`'s first word; a
line whose `{merge_basename}` has no value is dropped). Seed additions,
applied to every session in every mode, single-plan included:

```
Bash(git push * {default_branch})
Bash(git push * *:{default_branch})
Bash(git push * *:refs/heads/{default_branch})
Bash(git -C * push * *:{default_branch})
Bash(gh api *pulls/*/merge*)
Bash(*{merge_basename}*)
```

`gh pr merge` stays denied as today. The merge command runs as the runner's
child, outside any session's tool rules. The deny list guards the agent's own
Bash calls, not a sandbox; the skills' rule ("sessions never merge") is the
first line.

### Autopilot, plan, brainstorm, integration, local-merge, execute

- **"In a studio"** — one definition at the top of autopilot, cited by every
  branch: `command -v studio-state` succeeds and `studio-state get stage`
  exits 0. In a studio there is no in-session fallback and no session-mode
  `autopilot` is ever set.
- **Phase 1 in a studio:** (1) discovery: `.studio/run` names a manifest not
  done → resume it; else a new run: the integration question and the lane
  count in one `AskUserQuestion` (an `integration slug=` mode line
  pre-selects integration with that slug), then the story list, the
  manifest on `run/<slug>`, `.studio/run`; (2) `studio-overnight next
  <manifest>`: a `brainstorm` or `plan` row → set `STATE.md` for it when
  needed and print `/clear`, then the printed command, and stop (the stage
  runs in its own session); (3) every row `planned`: seed the story files
  (above), `reset --keep-ledger` on `STATE.md`, integration — create
  `integration/<slug>` on origin when absent (`git push origin
  origin/main:refs/heads/integration/<slug>`); fill the Spec/Plan cells,
  commit and push `run/<slug>`, write `Docs:`, commit and push; (4)
  readiness = `studio-overnight start --dry-run <manifest>` exits 0, plus the
  baseline test and engine lines; (5) ask how to start (Teaching; AC1).
  `--detach` runs preflight in the foreground (a refusal is shown in the
  chat), then re-execs under `nohup` in its own session/process group, stdin
  `/dev/null`, output to `RUN_DIR/runner.log`, every variable named
  `CLAUDECODE`, `CLAUDE_CODE_*`, `OMEGA_*`, `STUDIO_*` removed (computed from
  `env`). The launch may need one permission approval and runs outside the
  Bash sandbox when one is on (the run needs the network).
- **Does not fit** (stop in phase 1 with the reason and the options): a
  dependency on a later or unlisted row; direct mode without
  `merge_command`; work that is not story-shaped. Options always include
  "integration mode" and "drop the story". A story without a plan is never a
  stop — it enters the planning loop. Stories sharing a spec are allowed.
- **Phase 2 merge rule** (AC22 wording): no session merges anything in any
  run mode; integration run — nothing is merged into `main`, the runner
  merges stories into `integration/<slug>`; direct run — the runner merges
  into `main` only through `merge_command`; single-plan run and session mode
  — never merge into `main`. Allowed-side-effects base: the manifest's
  Target; integration runs open no story PR.
- **Brainstorm:** `/game-dev:brainstorm <id>` under an active manifest writes
  one spec for the epic with a `## Stories` table (`Story | Acceptance
  criteria | Depends on`) covering every manifest row the user puts in the
  epic, and ends with `/clear` and `next`'s command.
- **Plan:** `Story: <id>` header line when invoked with an id; every task
  carries `Spec: <spec>:L<a>-<b>[, …]` and `Review: task|final` under its
  heading; after approval, in the same session, SDD's pre-flight conflict
  scan and the question sweep (autopilot's sweep procedure, moved here for
  manifest stories) write into `## Decisions`, then `Decisions swept <id>`
  is ledgered and committed, then `/clear` and `next`'s command are printed.
  Autopilot's own sweep stays for single-plan runs.
- **Integration skill:** `## Story flow` keeps the attended flow verbatim
  (AC20) and gains `## Autopilot run` (what the runner does; no story PRs)
  and `repair <slug>`: in the integration worktree, resolve the `origin/main`
  merge or fix the red gate output with a fresh fixer, commit; never push,
  never open a PR (the runner does).
- **local-merge:** §5's autopilot line names `main` and states that sessions
  never merge in any run mode. Its §3 is unchanged (no session lands).
- **omega-mode `brief`:** the env-autopilot text states the one rule
  (sessions never merge; the runner lands).
- **Execute:** §0 lane isolation (below); §4 honours `Review:`; §5 step 1
  skipped under a lane; §7 under a lane — base `origin/<Target>`, step 1 per
  mode (Gates), step 3 skipped, integration: push and no PR, `shipped
  <branch>`; direct: draft PR into the default branch, `shipped <url>`; §6's
  "merging is never done" names `main` and the runner; §8 inputs via
  `studio-brief`; new §9 `--land`; new §10 `--progress`.

**Lane isolation** (execute §0, a new run under `STUDIO_STORY`): `git fetch
origin` (lock retries); `git fetch origin run/<slug>`; when `<Branch>`
exists, enter its worktree (`studio-state worktree`, or `git worktree add
<path> <Branch>`) and only check the docs: `git diff --quiet
$STUDIO_DOCS_REV HEAD -- <spec> <plan>`, a difference is a `Stop:`; the
ledger is never touched. When it does not exist: `git worktree add
--no-track -b <Branch> <STATE_ROOT>/.claude/worktrees/<Branch with / → ->
origin/<Target>`, `EnterWorktree path:`, `git checkout $STUDIO_DOCS_REV --
<spec> <plan> .studio/ledger/<id>.md`, commit `docs(<id>): approved plan`.
Then `set branch`, and ledger `base origin/<Target>` — every `git
merge-base` in §4a, §5 and §7 uses that remote ref after a fetch; the bare
`<Target>` is used only for `gh pr create --base`. Reasons: AC6 wants the
target's head at that moment; a path checkout carries only this story's docs,
so stories never add/add-conflict on each other's ledgers after a squash.

### Config and runner preflight (manifest mode)

`overnight.max_lanes` (int 0–8, default 0) joins the `cfg` int calls; the
five `overnight.model_*` strings and the top-level `merge_command` are read by
a new `cfg_str` (`sed` of the quoted value; `cfg_raw` stops at a space).
`merge_command` must contain `<pr>` and its first word must be an executable
file under `START_DIR`; a model value must match `^[a-z0-9.-]+$`. Preflight
adds, one line per failure: git ≥ 2.38; `origin/HEAD` resolves; the manifest
parses (Mode, Target, `Docs:` reachable on `origin/run/<slug>`, rows, unique
ids, dependencies on earlier rows only, no `-` in Spec or Plan); per story —
story file exists, `plan approved <plan>` and `Decisions swept <id>` in its
ledger, plan at `Docs:` has `## Decisions`, `Story: <id>` and a `Spec:` line
on every task, its ledger file clean in `START_DIR`, stage `plan`, `execute`,
or `idle` with a `shipped` line; direct — `merge_command` set; integration —
`origin/integration/<slug>` exists. `--dry-run <manifest>` prints the chains,
the first unit's launch line per chain and the expanded deny rules.

### Files

| File | Action | Single responsibility |
|------|--------|-----------------------|
| `studios/game-dev/bin/studio-overnight` | modify | `start [--dry-run or --detach] [<manifest>]` and `next [<manifest>]`: no argument = bundle 2 unchanged; with one — chains, lane processes, per-story machine, landings, final step, direct progress landing, deny expansion, per-story `status`, `report.md` |
| `studios/game-dev/bin/overnight-deny.txt` | modify | Placeholders and the push-to-default, merge-endpoint and merge-program rules; no mode tags |
| `studios/game-dev/bin/studio-state` | modify | `STUDIO_STORY` selects the story file and the story-id ledger; `init` and `check --rebuild` under it |
| `studios/game-dev/bin/studio-brief` | create | Print exactly a task or final-review unit's inputs |
| `studios/game-dev/bin/studio-test` | modify | Take and release the gate lock; honour `STUDIO_GATE_HELD` |
| `studios/game-dev/bin/studio-run` | modify | Same gate lock rule |
| `studios/game-dev/hooks/guard-state.sh` | modify | Story state files are written only through `studio-state` |
| `studios/game-dev/skills/execute/SKILL.md` | modify | §0 lane isolation + narrowed check; §4 `Review:`; §5/§7 under a lane; §8 inputs via `studio-brief`; §9 `--land`; §10 `--progress` |
| `studios/game-dev/skills/plan/SKILL.md` | modify | `Story:` header, `Spec:` ranges, `Review:` tag; conflict scan + sweep + next command for a manifest story |
| `studios/game-dev/skills/brainstorm/SKILL.md` | modify | `## Stories` table for an epic; next command |
| `shared/omega/skills/autopilot/SKILL.md` | modify | The "in a studio" test, the two questions, manifest + pointer + seed, `next`-driven planning loop, readiness, start choice, does-not-fit, the merge rule; no in-session fallback in a studio |
| `shared/omega/skills/integration/SKILL.md` | modify | `## Autopilot run` and `repair <slug>`; attended flow untouched |
| `shared/omega/skills/local-merge/SKILL.md` | modify | §5 names `main` and the no-session-merges rule |
| `shared/omega/bin/omega-mode` | modify | `brief`'s env-autopilot merge rule |
| `tests/overnight_lanes_test.sh` | create | Stub-`claude` (scenario keyed by `STUDIO_STORY` + prompt), stub `gh`, stub merge command, a local bare origin: chains, both modes, waiting chain, serialized landing, clean landing with no session, repair path, idempotent landing and final step, stopped story, crashed lane, stop file, runner gone, budget, models, status, report, deny expansion, docs revision, gate lock overlap |
| `tests/studio_brief_test.sh` | create | Fixture plan + spec: `task 3` and `final` outputs pinned (present and absent parts) |
| `tests/overnight_test.sh` | modify | Single-plan regression: deny additions and `run_usd` default 0 / range 5000 updated, else unchanged |
| `tests/state_test.sh` | modify | `STUDIO_STORY`: init, isolation between two ids, story-id ledger, `--rebuild` from `task -` with and without a gap, unset = `STATE.md` |
| `tests/hook_test.sh` | modify | guard-state blocks a story file edit |
| `tests/studio_test.sh` | modify | Text contracts: execute §0 (narrowed check, `--no-track`, docs only on a new branch), §4 `Review:`, §5/§7 per mode, §8 `studio-brief` only, §9, §10; plan and brainstorm additions |
| `tests/omega_contracts/autopilot_contract.sh` | modify | The questions, manifest, pointer, the "in a studio" line, no in-session fallback, `next`, merge rule names `main` |
| `tests/omega_contracts/integration_contract.sh` | modify | `## Autopilot run`, `repair`; attended `## Story flow` unchanged |
| `tests/omega_contracts/local-merge_contract.sh` | modify | §5 wording |
| `tests/omega_test.sh` | modify | `brief`'s merge rule |
| `README.md` | modify | `studio-overnight start <manifest>`, `next`, the two modes, the gate lock |

### Rejected alternatives

- A Claude session per landing: a clean merge needs no judgement, and the
  merge command's 15–20 minutes exceed the Bash tool's 600 s cap.
- A Claude session for the integration final step: merge, gate, body and PR
  are deterministic; Claude only repairs.
- A runner worktree for integration landings: `merge-tree`/`commit-tree`
  build the merge commit with no checkout to keep clean.
- FIFO event scheduler with a seven-state lane machine (revision 1): chains
  with plain `wait` give the same parallelism for independent work with
  fewer moving parts and no blocking `read`.
- A cross-lane budget lock: `run_usd` defaults to 0; an unlocked sum bounds
  the overshoot.
- Per-mode deny tags: no session ever merges, so one rule set fits every
  mode.
- Per-lane Godot user dir (`override.cfg`): the gate lock already keeps test
  runs apart.
- Ledger keyed by spec slug under a lane: an epic's stories share a spec.
- A separate question-sweep session: the plan session already holds the plan.
- The manifest's Status column: duplicated the ledgers and went stale.
- State in each story's worktree: the first unit runs before a worktree
  exists.
- One STATE.md with a stories table: concurrent rewrites of one file.
- Docs commits on `START_DIR`'s branch read at a moving HEAD: the user's
  checkout moves mid-run and `main` diverges.
- Rebase onto the target: rewrites a pushed branch; force-push is denied.
- A PROGRESS entry per story: parallel lanes conflict on every landing.

## Tuning knobs

`.studio/config.json`:

| Field | Unit | Default | Range |
|-------|------|---------|-------|
| `overnight.max_lanes` | lane processes | 0 (one per chain) | 0–8 |
| `merge_command` | command line, `<pr>` substituted | none — required for a direct run | its first word an executable file under the checkout; must contain `<pr>` |
| `overnight.model_task` | model alias or id | `sonnet` | `^[a-z0-9.-]+$` |
| `overnight.model_final` | model alias or id | `opus` | same |
| `overnight.model_finish` | model alias or id | `sonnet` | same |
| `overnight.model_repair` | model alias or id | `opus` | same |
| `overnight.model_progress` | model alias or id | `sonnet` | same |
| `overnight.run_usd` (changed) | USD | **0 = no run-wide cap** (was 150) | 0, or 1–5000 |

Constants, not knobs: one repair and one retry per landing; the 5 s wait
poll; three git lock retries. Cost policy (user ruling): necessary spend is
not capped; waste is. The waste guards are structural — one fresh session
per unit, task units reading only their brief, Sonnet where Opus adds
nothing, per-task review only for risky tasks, no session for a clean
landing or the final step, one test run per story, one test run at a time,
`session_usd` (25), one retry then a stop for a unit with no progress,
`session_minutes`. `run_usd` stays opt-in; phase 1 does not ask about it.
Bundle 2's other four `overnight` knobs are unchanged.

## Assets and audio

n/a

## Test strategy

- Unit (`tests/run_all.sh`), the stub-`claude` harness with a local bare
  origin, stub `gh` and a stub merge command:
  - chain building (independent rows, a linear chain, a fork, a two-chain
    dependency) and `--dry-run` output; lanes start up to `max_lanes`;
  - one launch per unit, each with its `--model`; no launch for a clean
    landing (integration and direct); a conflict launches exactly one repair
    and one retry, a second conflict stops the story;
  - a waiting chain starts within 5 s of its last dependency's landed line,
    and is skipped when a dependency stops;
  - idempotence: a pre-merged PR and a pre-landed branch are recorded with no
    merge command call; a final step with an open PR at an unchanged head
    runs no gate and calls `gh pr edit` at most once;
  - a lane killed with `kill -9`: the runner reports `lane crashed`, does not
    hang (test timeout), waiting chains skip; stop file and Ctrl-C (SIGINT to
    the runner): running units finish, nothing new starts; runner killed:
    lanes launch nothing more;
  - gate lock: two lanes whose stub `studio-test` records start/end times
    show no overlap; a dead holder is reclaimed; `STUDIO_GATE_HELD` skips;
  - docs revision: committing to `START_DIR` mid-run leaves later lanes'
    docs unchanged; an existing branch's ledger survives isolation (the
    stub follows §0's script);
  - `next` classification and commands; `status`, `report.md` (every
    ending), deny expansion, budget > 0, single-plan unchanged, `--detach`
    strips the variable prefixes.
- `tests/studio_brief_test.sh`: AC12's pinned outputs.
- `state_test.sh`: `STUDIO_STORY` isolation, story-id ledger, `--rebuild`.
- Text contracts: autopilot, plan, brainstorm, execute, integration,
  local-merge (the ACs marked "text contract").
- Live (exit criterion 2): three stories in a throwaway project, once per
  mode. Observables read from the unit jsonl files: zero `AskUserQuestion`
  calls and zero permission denials after plan approval ("no human input");
  first-turn context per unit kind; `studio-test` calls per story; no whole
  `Read` of a plan or spec in task and final units. Live-only: the detached
  run surviving the chat (AC1).
- T1 probes (first plan task, live): detached runner survives the chat and
  inherits nothing; `BASH_*_TIMEOUT_MS` honoured under `-p`; `set -m` in a
  background subshell on a terminal; phoenix `merge.sh` run by a non-Claude
  parent from the story worktree (exit code after a merge, branch deletion,
  cwd needs).
- Visual: the user reads `report.md` and judges whether each story's outcome
  is clear without logs.

## Risks

| Risk | Cheapest early check |
|------|----------------------|
| The gate lock makes lanes idle behind a 15–20 min merge command (direct) | Accepted: tests at once are what turned timing tests red; `status` shows the holder and `report.md` the wait per story |
| A unit's `studio-test` waits on the lock past the Bash tool limit | Launch env raises `BASH_*_TIMEOUT_MS` to `session_minutes`; T1 probe confirms it under `-p`; fallback: the skill runs `studio-test` in the background and waits for its notification |
| Integration landings carry no landing gate, so a story-to-story break surfaces at the final gate | Each story's own finish gate ran; the final gate runs on the combined head with `main` merged; one repair, then `[red]` in the PR title and body |
| A Godot process started outside `studio-test`/`studio-run` shares `user://` with another lane's test | Stated limit; implementer briefs already run tests through `studio-test` |
| A half-done story's rebuilt progress disagrees with reality (gapped ledger, moved branch) | `--rebuild` refuses a gap; readiness runs `studio-state check` per story; a mismatch is a stated stop |
| A lane's session reads or writes another story's state | `STUDIO_STORY` selection, narrowed §0 check; `state_test` two-id isolation |
| Concurrent git operations from lanes collide on `.git` locks | `--no-track`; retries on lock errors; stub test of two isolations at once |
| Phoenix `merge.sh` behaves differently when run by the runner (cwd, exit code after merging, deleting the branch) | T1 probe; the runner verifies by PR state, never by exit code alone |
| `set -m` inside a background subshell fails on a terminal | T1 probe; fallback `perl -e 'setpgrp; exec @ARGV'` |
| Deny rules match only the command the session types; a script can run around them | Accepted: the deny list guards the agent's own Bash calls; the skills' "sessions never merge" is the first line |
| A run started from a chat dies when the chat closes, or inherits its variables | T1 probe; preflight in the foreground; variables stripped by prefix; the printed command stays the fallback |
| A plan written before this change has no `Spec:` ranges or `Story:` header | Preflight refuses it with the line to add; attended single-plan runs are unaffected |

## Not doing

- Writing or approving specs and plans headlessly — they are made with the
  user in the planning loop; headless planning is bundle 3 (the plan
  falsifier).
- A shared/omega runner for non-studio projects — one user today.
- Changing the attended integration flow.
- Stacked story branches — a dependent story starts after its dependency lands.
- Merging `origin/main` into the integration branch at each landing — once,
  in the final step.
- Folding the finish into the final-review unit, passing a failed unit's
  result into its retry prompt, and splitting execute's SKILL.md into
  reference files (token review minors 10, 11, 13).
- Teaching phoenix's `merge.sh` to accept a recorded green gate for the same
  head (a phoenix change, not a studio one).
- A run-wide budget that is exact across lanes.

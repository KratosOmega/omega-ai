# A stage pointer per checkout, with explicit hand-off — Spec

Date: 2026-10-05
Status: Draft
Milestone: Plan 3 — Content (studio tooling; follows concurrent runs, #39)
Classification: architectural
Base: origin/main once #39 has merged. The build rebases onto #39's resolution code, `studio-state:54-60`. Line numbers below are on branch `worktree-issue-39-concurrent-runs` at 0286a47. The plan sets its own file and line targets after #39 merges.

Issue: #42. Design **H**, as re-ruled by the operator on 2026-10-05: an explicit hand-off, keyed by path, with no fallback. It replaces the draft's design (a), the claim rule, which the spec falsifier rejected with 3 Critical and 9 Important findings.

Today, a linked worktree without a local `.studio/STATE.md` reads and writes the main checkout's STATE.md. #39 only made that file local for run worktrees, through `init --local`. Two stories worked in two worktrees therefore share one `stage`, `spec`, `plan`, `task` and `branch`, and the last writer wins. The other story's router, SessionStart line, `check` and stage skills then act on the wrong spec. This happened on phoenix on 2026-09-19, when KAN-1296's review pointer was overwritten by another story. It happened again on 2026-10-05: a `set stage plan` from a linked phoenix worktree landed in the main checkout's STATE.md. The workaround is a per-machine memory note: "run the stage by path; the pointer is shared".

This spec gives every checkout its own stage pointer, and removes the path that let one checkout write another's:
- each checkout reads and writes only its own pointer;
- a linked worktree with no pointer reads as "no story in this checkout", never as main's story;
- a story moves between checkouts only by an explicit, locked, self-healing move (`handoff`, `take`, or the one-time migration `adopt`);
- `milestone` stays project-wide;
- `stories` lists every live pointer, so the main checkout can still find a story to review, playtest or retro.

Industry precedent: git's per-worktree HEAD and index over shared objects; the single-writer principle; explicit ownership transfer instead of shared state policed by a guard.

## Milestone gate

1. `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh` are green. The existing suites keep every assertion, except the ones listed under Test strategy, "Existing tests that change". The plan lists each rewritten assertion.
2. A fixture round trip, as `test_state_round_trip_two_stories` in `tests/state_test.sh`:
   - main checkout P brainstorms and plans story S;
   - S's execute isolates into WE and runs `handoff WE`: WE holds S at `execute`, P is idle with `branch -`, and P's ledger has the `handed` line;
   - meanwhile worktree WA brainstorms and plans story A (auto-created pointer);
   - WE runs `task 1/2`, `task 2/2`, writes `shipped`, then finishes (`stage idle`, `task -`);
   - from P, `stories` lists WE (`finished`) and WA (`active`); `worktree` prints WE;
   - P starts story T (`set stage brainstorm`, `set spec`) with WE still on disk, and exits 0;
   - throughout, WA's pointer never changes because of S or T, WE's never changes because of A or T, and P's never changes because of A.
3. Live, on phoenix (the operator runs the steps that need their machine), after the reinstall and with no overnight run live:
   - before the reinstall, record `cat .studio/STATE.md` in P and `git worktree list`; after it, `studio-state stories` from P lists the in-flight worktree stories, and every adoptable worktree (Migration) shows its story with `studio-state show`;
   - two `claude-gd` sessions, each in its own EnterWorktree story worktree, brainstorm and plan two stories at the same time. Each session's `studio-state show` names its own spec, and P's STATE.md is unchanged;
   - one story planned in P runs execute → finish, then `/game-dev:review` from P. Review enters the feature worktree through `studio-state worktree`;
   - the operator then deletes the phoenix memory note (AC45).

## Purpose

- Two stories in two checkouts never overwrite each other's stage pointer, by construction rather than by a guard.
- The single-story chain still works: plan in the main checkout → execute in a worktree → review, playtest and retro from the main checkout.
- A fresh worktree never acts on the main checkout's story by accident.
- Remove the "run by path because the pointer is shared" workaround.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Changed: every `studio-state` command resolves this checkout's pointer only. A linked worktree with none reads idle.
- Added: `studio-state handoff <path>`, `studio-state take <spec>`, `studio-state stories`.
- Changed: `studio-state worktree` from the main checkout chooses among the live stories, and exits 1 listing them when more than one fits.
- Added: `--force` on `set`, `take` and `handoff`, and the `STUDIO_STATE_FORCE=1` override.
- Added: exit code 4 (refused: a story switch in this checkout, or a move that would replace another story).
- Changed: `/game-dev:studio`, execute's resume, review, playtest and retro from the main checkout consult `stories`.
- Changed: the single-plan overnight runner follows its story into the worktree after unit 1.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A refused write changes nothing and exits 4. Its stderr names the story and the way out (AC24, AC25).
- An interrupted hand-off is completed or rolled back by the next `studio-state` call that sees it (AC14).
- A removed worktree takes its pointer with it. For a handed story, the main checkout's `handed` line keeps spec, plan and branch: `worktree` from P exits 3 with the re-add command, and `take <spec>` in the re-made worktree restores the pointer (AC17, AC22).
- A worktree-born story whose worktree is removed loses its pointer. Recover with `set spec`, `set plan`, `set stage`, `set task 0/<N>` and `check --rebuild`, as documented in the PR and PROGRESS.
- A worktree whose state was clobbered before the upgrade reads idle after it, and recovers the same way.

## Teaching

- `studio-state`'s usage line and header comment describe per-checkout resolution, auto-create, `handoff`, `take`, `adopt`, `stories`, the project-wide milestone, the story-switch guard, `--force` and exit 4 (AC37).
- `show` in a pointer-less worktree prints `(no story in this checkout)`, plus the take hint when it applies (AC3, AC28).
- The exit-4 messages are the teaching text. They are quoted in AC24 and AC15.

## Input and platform

macOS and Linux shells, as today. POSIX `sh`, no new dependencies.

## Feel targets

n/a.

## References

- Operator rulings on #42 (2026-10-05): the first ruling, design (a); the re-ruling, design H, which this spec follows.
- Spec falsifier report on the draft (findings C1-C3, I1-I9, M1-M10) and the C′-versus-H comparison (H's six fixes, flow walk, risks H-N1..H-N8). Both are read-only investigations of 2026-10-05; their conclusions are folded in here and traced in "Traceability".
- #39 spec `docs/game-dev/specs/2026-10-04-concurrent-runs.md` (on the #39 branch): AC1, AC2 (L129-132), AC31, and the rejected alternative at L313-316.
- `studios/game-dev/bin/studio-state` (#39 branch):
  - header: :2-9; usage: :72-75;
  - roots: :40-48;
  - pointer resolution: :54-60;
  - STUDIO_STORY: :61-65;
  - `write_idle_state`: :86-100;
  - `write_field`: :114-122;
  - `ledger_file`: :168-172;
  - `init --local`: :192-203;
  - `init`: :223-243;
  - `reset`: :364-381;
  - `worktree`: :382-425.
- `studios/game-dev/bin/overnight-runs.sh` :97-110: `mx_take` / `mx_drop`, the symlink pid mutex this spec copies.
- `studios/game-dev/skills/execute/SKILL.md`:
  - §0's "Which run this is": :31-55;
  - isolation (a), (b), the ancestor check and (c): :147-183;
  - finished-checkout guard: :214-224; Enter the feature checkout: :225-235;
  - §7 step 3: :534; step 5: :561-567; step 6: :568-591;
  - lane finish: :629-637;
  - §8 stops: :705-722; §10 `--progress`: :815-834.
- `studios/game-dev/bin/studio-overnight`: :40 `state()`, :412-430 preflight, :535-541 `ledger_of` and `feature_dir`, :551 snapshot, :990-996 `start_session` (unit cwd), :1104 Resume line, :1189 and :1196 the loop's stage checks.
- `studios/game-dev/bin/overnight-channel.sh` :183-192 `chan_ledger`; `studios/game-dev/bin/overnight-progress.sh` :66, :80.
- Phoenix memory note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` (2026-09-19).

## Terms

- **Main pointer**: `<root>/.studio/STATE.md`, where `<root>` is `studio-state root`, the main checkout.
- **Local pointer**: `<work root>/.studio/STATE.md` in a linked worktree, untracked and git-excluded.
- **Pointer-less worktree**: a linked worktree with no local pointer, or with a tracked one (AC4).
- **Current branch**: `git branch --show-current` in the checkout the command runs in. It is empty on a detached HEAD.
- **Live worktree**: a `git worktree list --porcelain` entry that is not prunable and whose directory exists.
- **Active story**: a pointer whose `stage` is not `idle`.
- **Finished story**: a pointer at `stage idle` whose `spec` is not `-`, whose feature ledger has a `shipped` line, and whose checkout is a live worktree.
- **The mutex**: `<root>/.studio/state.mutex` (AC27).

## Acceptance criteria

Resolution (STUDIO_STORY unset)

1. **Main checkout.** The pointer is the main pointer, as today.
2. **Linked worktree with a local pointer.** The pointer is that file. This is #39's rule (`studio-state:57-58`), unchanged.
3. **Pointer-less worktree: no story, no fallback.** When the main pointer exists:
   - `get stage` prints `idle`, and `get spec|plan|task|branch` print `-`;
   - `get milestone` prints main's milestone (AC10);
   - `show` prints the idle header with main's milestone, then the line `(no story in this checkout)`, then the take hint when AC28's condition holds;
   - `check` prints `check: ok`; `worktree` exits 1 with `studio-state: no feature branch recorded`;
   - nothing is read from main's story, and nothing is written, except by AC6 (auto-create) and AC18 (adopt).

   When the main pointer does not exist, every command keeps today's "no `.studio/`" exit 1.
4. **Tracked pointer** (#39 T2 review Minor 3, scoped as falsifier I7 says). With STUDIO_STORY unset, in a linked worktree where `.studio/STATE.md` is tracked (`git ls-files --error-unmatch .studio/STATE.md` succeeds there), that file is never the local pointer, and the checkout reads as pointer-less (AC3). Only auto-create (AC6), `take` and `handoff` into it refuse, with exit 1 and `studio-state: <path> is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch`. The main checkout and STUDIO_STORY are unchanged. Phoenix does not track the file: it is ignored through `.git/info/exclude` (verified by the operator).
5. **STUDIO_STORY is unchanged.** Under STUDIO_STORY, resolution, reads and writes are exactly as today, except `milestone` (AC10). No guard, hand-off or adopt runs. Lanes, adopt, peers and progress are unaffected.

Auto-create

6. **First write creates the pointer.** In a pointer-less worktree, the first `set` (any key except `milestone`) or `ledger`:
   - creates the local pointer through the one function `init --local` uses: the idle template, without a `milestone:` line, written to a temporary file and linked into place with `ln` (never clobbers; an `ln` that loses a race uses the winner's file);
   - appends `.studio/STATE.md` to `<common git dir>/info/exclude` once, under the mutex, repairing a missing final newline first, as #39 does;
   - then applies the write.

   The main pointer is byte-identical before and after.
7. **`reset` and `check --rebuild` in a pointer-less worktree** write nothing, print `no story in this checkout`, and exit 0 (falsifier M3).
8. **`init --local`** is the explicit form of AC6, so `init --local` writes a file byte-identical to an auto-created one. Its refusals are unchanged: in the main checkout; with STUDIO_STORY set; and a second `init --local` exits 1 with `init --local: <path> already exists`.
9. **`init` in a linked worktree** whose main pointer exists exits 1 with `studio-state: this is a linked worktree — its stage pointer is created on its first write; to create it now, run studio-state init --local` (falsifier I2). In the main checkout, and without a main pointer, `init` is unchanged.

Milestone

10. **`milestone` is project-wide.**
    - `get milestone` and `set milestone` always read and write the main pointer: from every checkout, and under STUDIO_STORY.
    - Local pointers, and story files created after this change, have no `milestone:` line.
    - `show` prints the header with `milestone: <main's value>` in the milestone position. A `milestone:` line left in an older local pointer or story file is ignored by `get` and replaced in `show`.
    - `set milestone` never auto-creates a local pointer, and holds the mutex (AC27).
11. **No main pointer** (a local pointer made by `init --local` before any `init`; falsifier M4): `get milestone` prints `prototype`, and `set milestone` exits 1 with `studio-state: no main pointer — run studio-state init in <root>`.

Hand-off, take, adopt

12. **`studio-state handoff <path>`** moves the main checkout's story to the live linked worktree at `<path>`. It runs from any checkout with STUDIO_STORY unset. On success:
    - the target pointer holds main's `stage`, `spec`, `plan` and `task`, with `branch` set to the branch `<path>` has checked out (from `git worktree list`), then main's `## Ledger` lines except its `handed` lines, then the new `handed` line;
    - the main pointer holds the idle header (`stage idle`, `spec -`, `plan -`, `task -`, `branch -`, its `milestone` kept), and its `## Ledger` holds only its `handed` lines, the new one last (Deviation D1);
    - the `handed` line, in both files, is `- <date> handed <spec> plan <plan> to <path> (<branch>)`;
    - it prints `handed <spec> to <path>` and exits 0.
13. **Strict order, under the mutex.** `handoff`, `take` and adopt run one function, in this order:
    1. take the mutex;
    2. run the checks (AC15, AC16);
    3. append the `handed` line to the main pointer (the intent record);
    4. write the target pointer: by tmp + `ln` when it is absent, or by tmp + `mv` over an idle one after re-reading it idle under the mutex;
    5. replace the main pointer with AC12's idle form in one tmp + `mv`;
    6. release the mutex.

    No step leaves both pointers non-idle with different content and no record of why.
14. **Self-heal** (risk H-N2). A hand-off is incomplete when the main pointer is active, and its last `handed` line names main's current `spec` and a `<path>`. Any `studio-state` command in the main checkout, and every `handoff`, `take`, `stories` and `worktree` call, first resolves it under the mutex:
    - when `<path>` is a live worktree with no local pointer, or one holding that spec at a non-idle stage: it completes steps 4 and 5;
    - when `<path>` is not a live worktree: it rolls back, keeping main's story and appending `- <date> handoff of <spec> to <path> void (worktree gone)`;
    - otherwise (the target holds another story, or that spec finished), it does nothing: this is not an interrupted hand-off.

    It is skipped under `STUDIO_STATE_NO_ADOPT=1` (AC19). A re-run of the same `handoff` completes it the same way and writes no second `handed` line.
15. **`handoff` refusals.**
    - Exit 1, nothing written: STUDIO_STORY is set; `<path>` is not a live linked worktree of this repository, or is the main checkout; the main pointer is idle; `<path>` has a tracked STATE.md (AC4).
    - Exit 4, nothing written: the target holds an active story with a different spec. stderr: `studio-state: <path> holds story <spec slug> (stage <s>) — finish or reset it there first, or pass --force`. `--force` overrides it (AC25).
16. **`studio-state take <spec>`** runs in a linked worktree and moves the main checkout's story here: AC12-AC14 with `<path>` = this checkout. It continues a main-planned story from a worktree made by hand. In addition to AC15's checks:
    - exit 1 in the main checkout;
    - exit 4, not overridable, when main's `spec` is not `<spec>` (risk H-N5) and no `handed <spec>` line restores it (AC17): `studio-state: the main checkout's story is <main spec>, not <spec>`;
    - exit 4, not overridable, when main is at `execute` with a `branch` that is checked out in another live worktree (a story claimed before #42): `studio-state: <spec> is being executed in <path> — continue it there`.
17. **Restore** (risk H-N3). `take <spec>`, when the main pointer does not hold `<spec>`, and main's newest `handed <spec> … to <path> (<branch>)` line names this checkout's current branch and a `<path>` that is not a live worktree other than this one:
    - rebuilds this checkout's pointer from that line: `spec`, `plan`, `branch`; `stage idle` when this checkout's feature ledger has a `shipped` line, else `stage execute`; `task 0/<N>`, with `N` counted as `check --rebuild` counts it under STUDIO_STORY (`### Task` headings above `## Backlog`), then rebuilt from the feature ledger's `T<n> complete` lines;
    - appends `- <date> restored <spec> from the handed line` to this pointer's ledger;
    - leaves the main pointer unchanged, and exits 0.
18. **Adopt, the one-time migration** (risk H-N4). In a pointer-less worktree, with STUDIO_STORY and `STUDIO_STATE_NO_ADOPT` unset, every pointer-resolving command (`get`, `set`, `show`, `ledger`, `check`, `reset`, `worktree`) first runs `take <main spec>` silently, when all of these hold:
    - main's `branch` equals the current branch, and is neither `-` nor empty;
    - main's `stage` is `execute`, or main's `stage` is `idle` with `spec` not `-` and `<work root>/.studio/ledger/<slug>.md` present.

    This is the state today's execute (c) leaves, converted. It never fires at `brainstorm` or `plan`, so a stale `branch` cannot move the main checkout's next story into a finished worktree. The `handed` line ends with ` (adopted)`. Nothing after #42 creates the state again.
19. **Hooks never write.** `hooks/session-start.sh` runs `studio-state` with `STUDIO_STATE_NO_ADOPT=1`. That suppresses adopt (AC18) and self-heal (AC14), so a hook never writes a pointer; it prints AC28's line instead (risk H-N8).

Stories and the feature checkout

20. **`studio-state stories`** lists the live pointers, from any checkout. It prints one TSV line per story, `<path>\t<branch>\t<stage>\t<spec>\t<task>\t<state>`, where:
    - `<branch>` comes from `git worktree list` (rename-proof), or `-` on a detached HEAD;
    - `<state>` is `active` or `finished` (Terms);
    - main's pointer is listed when its story is active or finished. Its `<path>` is the live worktree that has main's `branch` checked out when that branch is neither `-` nor empty and main's stage is `execute` or `idle` (an in-place story, or one executed before #42); otherwise it is the main checkout. At `brainstorm` or `plan`, a recorded `branch` is stale and is ignored;
    - then each live linked worktree's local pointer, active or finished, in `git worktree list` order.

    It skips pointer-less worktrees, idle pointers that are not finished, and prunable or missing worktrees. With none, it prints nothing and exits 0. It writes nothing except AC14's self-heal. `show`'s format is unchanged, because `studio-overnight` :535-537 and `overnight-channel.sh` :189-191 parse it from `## Feature ledger:` to EOF.
21. **`worktree` from a local pointer** exits 1 with `studio-state: no feature branch recorded` when its `branch` is `-` or empty, as today. Otherwise it prints the work root (the story's checkout), whatever the branch is now called (falsifier I4).
22. **`worktree` from the main checkout** chooses among `stories` lines at stage `execute` or state `finished` (a story still in brainstorm or plan has nothing to review):
    - one candidate: print its path, exit 0;
    - several: exit 1. stderr is `studio-state: <n> stories fit — choose one:`, then one line per candidate, `<path>\t<branch>\t<spec>\t<state>`;
    - none, while main records a `branch` (stage `execute` or `idle`) that exists but no worktree has checked out: exit 3, as today (`studio-state:421-424`);
    - none otherwise: main's newest `handed` line whose `<path>` is not a live worktree and whose `<branch>` still exists gives exit 3. stderr's second line is `git worktree add <path> <branch> && (cd <path> && studio-state take <spec>)`, with today's unlock/prune prefix when a stale entry holds the branch;
    - else exit 1 with `studio-state: no feature branch recorded`.
23. **`worktree` under STUDIO_STORY** is unchanged.

Story-switch guard (same checkout)

24. **The guard** covers two sessions in one checkout, the 2026-09-19 case. With STUDIO_STORY unset, on whichever pointer this checkout resolves:
    - `set stage brainstorm` while `stage` is `plan` or `execute` exits 4;
    - `set spec X` while `stage` is `plan` or `execute` and `spec` is neither `-` nor X exits 4;
    - both print exactly `studio-state: this checkout is on story <spec slug> (stage <s>, task <t>) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force`, and write nothing;
    - at `stage brainstorm`, `set spec X` over a different spec (not `-`) exits 0, writes, and prints one stderr warning naming the old spec. Brainstorm §0 already asks the user.

    The guard is skipped when `<work root>/.studio/run` exists: a run worktree's pointer walks the manifest's rows (autopilot :121, :135; brainstorm :61). `reset` is not guarded: the router confirms an abandon with the user first.
25. **Override.** `--force` (`set --force KEY VALUE`, `take --force <spec>`, `handoff --force <path>`) or `STUDIO_STATE_FORCE=1` bypasses AC24 and AC15's exit 4. A forced write that would otherwise have been refused first appends `- <date> forced <key>=<value> over <old spec> (stage <s>)` to the written pointer's `## Ledger` (`handoff` as the key for a forced move). `--force` is accepted only in these positions; anywhere else it is a usage error, as today. No `forced` line is written when nothing was refused. AC16's two refusals are not overridable.
26. **Exit codes.** The usage text and the header's `Exit:` line add `4 refused: a story switch in this checkout, or a take/handoff onto another story or the wrong spec (--force overrides where stated)`. No other path exits 4.

Lock

27. **The mutex** is `<root>/.studio/state.mutex`, #39's `mx_take` / `mx_drop` pattern (`overnight-runs.sh:97-110`): a symlink to the holder's pid, a dead holder's link reaped, about 10 s of retries, then exit 1 with `studio-state: <root>/.studio/state.mutex is busy (pid <p>)`. It is held by:
    - `handoff`, `take` (restore included) and adopt (AC13);
    - self-heal (AC14);
    - auto-create's `info/exclude` append (AC6);
    - every write to the main pointer: `set`, `reset`, `check --rebuild` and a `ledger` line into main's STATE.md in the main checkout, and `set milestone` from any checkout.

    **Plain `set` on a local pointer takes no lock.** Only its own checkout writes it; the one cross-checkout writer (`handoff`) never overwrites an active one, and re-checks it idle under the mutex. Two writes racing inside one checkout lose an update as today (`write_field` is tmp + `mv`); that is out of scope (Risks). Writes to the main pointer take the lock because `handoff`, `take`, adopt and self-heal rewrite it from other checkouts.

Hooks and skills

28. **SessionStart** (`hooks/session-start.sh`) prints the stage of the checkout the session starts in: P idle and WA at `plan` print `stage idle` from P and `stage plan` from WA, and a pointer-less worktree prints `stage idle`. It runs with `STUDIO_STATE_NO_ADOPT=1` (AC19). The comment at :15-17 reads "studio-state resolves this checkout's own pointer". **The take hint**: when the checkout is pointer-less, is not under `.claude/worktrees/agent-*`, main's story is active, main's spec exists as a file in this checkout, and main's `branch` is `-` or not checked out in a live worktree, the line ends with ` · the main checkout's story <spec> (stage <s>) — studio-state take <spec> to continue it here`. `show` prints the same hint (AC3). An adoptable worktree (AC18) also gets the hint, worded `— it moves here on the first studio-state call`.
29. `hooks/bootstrap.md` :27 reads: "When `studio-state get stage` succeeds, a line naming this checkout's stage follows this bootstrap (a linked worktree with no story of its own reads idle); `/game-dev:studio` names the next step from it. When it fails and this is a Godot project, `/game-dev:studio` initialises it."
30. **Studio router** (`studio/SKILL.md`):
    - :16 runs `studio-state show` in the checkout it is in;
    - in the main checkout it also runs `studio-state stories` and lists each story on one line with the checkout to continue it in. When main is idle and a story is active elsewhere, `Next:` names that checkout first (`continue <spec> in <path>`), then `/game-dev:brainstorm` for a new story;
    - in a pointer-less worktree with the take hint, `Next:` names `studio-state take <spec>` (to continue main's story here) or `/game-dev:brainstorm` (a new story), never `/game-dev:execute` (falsifier I9);
    - abandon (:66-71) resets this checkout's pointer only. For a story in another checkout, it names `abandon it in <path>`. On exit 4 it shows the message.
31. **Brainstorm §0** (:16-19): the state test is `studio-state get stage` exiting 0, not the presence of `.studio/STATE.md` (falsifier I2). On exit 1 with `project.godot` present, it asks to initialise as today. On exit 4 from `set stage brainstorm` or `set spec`, it stops, shows the message, and suggests EnterWorktree.
32. **Plan §0** (:28-33): in a pointer-less worktree whose `show` prints the take hint, it stops with "the main checkout's story `<spec>` is waiting: continue it in `<main checkout>`, or run `studio-state take <spec>` here" (falsifier I3). Exit 4 from any state write (:151-153) stops and shows the message.
33. **Execute:**
    - :53-55 reads: "Each checkout has its own pointer. A story planned in the main checkout moves to its execute worktree at isolation (c) (`studio-state handoff`); a story born in a worktree stays there. So every call below reads the story's own pointer from the feature worktree";
    - §0, before "Which run this is": in the main checkout at `stage idle`, run `studio-state stories`. With exactly one `active` line at stage `plan` or `execute`, enter that checkout (Enter the feature checkout, Exit 0 way) and run §0 there; with several, ask the user once which; with none, today's stop (risk H-N6);
    - (c) at :169-171: when this run's §0 ran in the main checkout, outside a lane, first run `studio-state handoff "$(git rev-parse --show-toplevel)"` inside the new worktree, then `set branch` as today (now a no-op). Exit 1 or 4 from `handoff` stops and shows the message. A worktree-born story runs no hand-off;
    - :534 notes that `set milestone` writes the project's milestone.
34. **Review and playtest** (review :20-30, :55-62; playtest :23-33, :50-57):
    - Enter the feature checkout's Exit 1 text reads: "more than one story fits, or none is recorded. Ask the user once which checkout to use, naming the candidates `studio-state worktree` listed on stderr (or that none is recorded) and the `git worktree list` paths";
    - the which-feature check keeps its logic; its cause reads "this checkout's pointer moved on to the next feature".
35. **Retro** (:16-35) resolves the story the same way: `studio-state worktree` from the main checkout. At exit 0 it reads the spec and ledger in that checkout (`(cd <path> && studio-state show)`; the session does not move). At exit 1 with candidates, it asks the user once which story, the only question retro asks. At exit 3 it reads `git show <branch>:.studio/ledger/<slug>.md`, with `<branch>` and `<spec>` from the stderr line. ":16-18, asks the user nothing" is reworded to match.
36. **Autopilot** (`shared/omega/skills/autopilot/SKILL.md`): :81 keeps `studio-state init --local`, the explicit form. :121 and :135 are unchanged, with no `--force`: the run worktree has `.studio/run`, so AC24 is skipped there (falsifier M9).
37. **The studio-state header comment** (:2-9) and usage (:72-75) describe AC1-AC27, replacing "so a linked git worktree edits the same file and one project has one stage".

Overnight

38. **The single-plan runner follows its story** (risk H-N1). `studio-overnight start`, single-plan, with STUDIO_STORY unset:
    - persists the run's `spec` with the run's record at start;
    - `story_dir()` returns START_DIR while START_DIR's pointer `spec` is the run's spec; otherwise the path of the one `stories` line with that spec; otherwise the path of main's newest `handed <spec>` line, when it is a live worktree; with two matching `stories` lines, the run stops with `stop: ambiguous story <spec>` and never guesses;
    - `state()` (:40), `feature_dir()` (:538-541), the unit cwd when `UNIT_CWD` is unset (:992) and the Resume line (:1104, `cd <story dir> && studio-overnight start`) use `story_dir()`;
    - `overnight-channel.sh` `chan_ledger` (:186-192, when the story is `-`) and `overnight-progress.sh` :80 key on the persisted spec through the same function, never on `worktree`'s candidate list;
    - a preflight in a checkout whose pointer is idle refuses with `no spec or plan set` as today, and adds `— the story is in <path>` for each active `stories` line.

    So unit 2 onward starts in the story's worktree and runs execute's resume on its pointer; a stop before (c) happens only in unit 1, in START_DIR, which the runner reads (§8 :712-719).
39. **Single-plan from a story worktree** works unchanged: its preflight passes on that checkout's pointer, and the main pointer stays byte-identical.
40. **Lanes** are unchanged (STUDIO_STORY, AC5). A `set milestone` under STUDIO_STORY writes the main pointer. Final and progress units (cwd FINAL_W, no STUDIO_STORY) read idle, matching execute §10 :821; a `Stop:` line there auto-creates an excluded local pointer, which lanes :1427's `git status --porcelain` check does not see.

Worktree lifecycle

41. An agent-isolation worktree (`.claude/worktrees/agent-*`) or an omega parallel task worktree has no special case. It reads idle, never its controller's or main's story (falsifier M2). Its first write auto-creates a local pointer (AC6); the main pointer and the controller's pointer stay byte-identical. `git worktree remove` removes it without `--force`, because the pointer is git-excluded, and `stories` no longer lists it.

Migration

42. No file-format change and no new header keys. These all resolve unchanged, and nothing is hand-edited on any machine:
    - existing main pointers;
    - legacy files without `branch:` (`set_branch` :134-147 still inserts it);
    - #39 local pointers, which keep their `milestone:` line, ignored by AC10.
43. **Sessions in flight** at reinstall, each with a test:

    | Session | Behaviour after reinstall | Test |
    |---|---|---|
    | Main checkout, its own story (not yet executed) | Unchanged: the main pointer | `test_state_main_checkout_unchanged` |
    | Worktree executing a main-planned story (today's (c) set main's `branch` to its branch; main at `execute`) | Adopted on that worktree's first `studio-state` call (AC18); main goes idle | `test_state_adopt_legacy_execute` |
    | Worktree whose finished main story awaits review (main `idle`, spec S, `branch` = its branch, S's ledger there) | Adopted on its first call; until then, `worktree` from P still finds it (AC20, AC22) | `test_state_adopt_legacy_finished` |
    | Main's next story started over a stale `branch` (main at `brainstorm`/`plan`, `branch feat/e`; WE on feat/e) — the state phoenix is probably in | No adopt (AC18's stage filter); WE reads idle; P continues its story | `test_state_adopt_skips_next_story` |
    | Worktree that wrote its brainstorm or plan into main's pointer (the EnterWorktree pattern; main `branch -`) | Reads idle with the take hint; one `studio-state take <spec>` moves it (documented in the PR and PROGRESS); no automatic move | `test_state_take_main_planned_story` |
    | Worktree whose state was clobbered before the upgrade | Reads idle; recover with `set spec/plan/stage`, `set task 0/<N>` and `check --rebuild` (documented) | `test_state_new_story_seeds_idle` |
    | Live overnight runs | None: reinstall only when `studio-overnight status` shows no live run. Lanes are STUDIO_STORY and unaffected | lanes and overnight suites |
    | #39 run worktree pointer with a `milestone:` line | Ignored by AC10 | `test_state_milestone_is_project_wide` |

    Install by PR merge, and reinstall only when `studio-overnight status` shows no live run.

Memory and docs

44. A new note `studios/game-dev/memory/stage-pointer-is-per-checkout.md`, in the folder's frontmatter format (`name`, `description`, `metadata.type: feedback`). It says:
    - each checkout has its own stage pointer; a pointer-less worktree has no story;
    - a story planned in the main checkout moves to its execute worktree by `studio-state handoff`; to continue one from a worktree made by hand, run `studio-state take <spec>`;
    - review, playtest and retro from the main checkout find the story through `studio-state stories`;
    - exit 4 means a story switch in this checkout: never `--force` it without the user;
    - the SDD ledger (`.superpowers/sdd/<plan>/progress.md`) remains the per-feature recovery record.

    `studios/game-dev/memory/MEMORY.md` gains one index line for it.
45. The PR body and the PROGRESS entry state that the per-machine phoenix note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` (and its `_practice` copies) can be deleted once this lands and is reinstalled. Nothing in the repo edits that file.
46. `docs/game-dev/PROGRESS.md` gains one entry for #42. The PR names the case nothing can prevent: a pre-#42 `studio-state` run by path from a stale dev worktree (the 2026-10-05 trigger was the #39 worktree's bin) still writes the main pointer. Such worktrees pick up the new resolution when rebased.

## What stays shared

Unchanged by this spec: everything keyed on `studio-state root`, which is #39 AC1:
- `.studio/stories/` (STUDIO_STORY files);
- the gate lock (`gate.lock`, `gate.units`, `gate.times`, `gate.mutex`);
- `overnight.lock`, `overnight.stop`, `runs/<slug>/`, `runs.mutex`, `reports/`;
- `sessions/` and `sessions.mutex`;
- the registry `root=`;
- the Multica project identity (`install.sh` :282, `omega-multica-agent` :16-17, bridge `service.py` :161-172).

Newly shared: `milestone` (AC10), and `state.mutex` (AC27).

Per checkout, as today: the feature ledger (`<work root>/.studio/ledger/`), `config.json` (the checkout first), `.studio/reports/` test logs, and `.studio/run`.

Newly per checkout: the stage pointer, in every linked worktree.

### Who reads what, and which side

| Item | What it touches | Side under H | Note |
|---|---|---|---|
| studio-state `get/set/show/check/reset/ledger` | this checkout's pointer | per checkout | AC1-AC3; a pointer-less worktree reads idle |
| studio-state `stories`, `worktree` (from main) | every live pointer | reads all; writes none | AC20-AC22 |
| studio-state `handoff`, `take`, adopt, self-heal | main pointer plus one local pointer | the only two-pointer writers, under the mutex | AC12-AC18 |
| studio-state `root` / `root --work` | prints STATE_ROOT / WORK_ROOT | shared / checkout | #39 AC1, unchanged |
| STUDIO_STORY files `<root>/.studio/stories/<id>.md` | lanes, adopt, peers, progress | per-story file in a shared dir | unchanged except milestone |
| `milestone` key | main pointer | shared | AC10 |
| STATE.md `## Ledger` | the pointer's own | per pointer; `handed` lines stay in main | idle notes, `abandoned`, `handed`, `restored`, `forced`, `void` |
| studio-gate :37-51, :136, :220 | gate files | shared | — |
| studio-setup :53-58, :123-126 | config fallback, gate-lock wait | shared (config: checkout first) | — |
| studio-overnight :399-404, :1229-1238, :1390-1435, :1509, :1530, :1620 | locks, stop flags, reports, runs, registry | shared | — |
| studio-overnight :40 `state()`, :427, :538-541, :551, :992, :1104 | the single-plan story's pointer | per story, follows it | AC38 |
| overnight-lanes.sh `story_state`, unit paths, locks | STUDIO_STORY files, shared run state | per-story file / shared | lines shift after #39's final commits |
| overnight-lanes.sh :1420-1431 final units | FINAL_W | per checkout (reads idle) | AC40 |
| overnight-runs.sh :23-62, overnight-sessions.sh :9-11 | run locks, records, session slots | shared | — |
| overnight-channel.sh :107-142, :327 | live runs, stop flag | shared | — |
| overnight-channel.sh :186-192 `chan_ledger` | single-plan story's `show` | per story, follows it | AC38 |
| overnight-progress.sh :66 / :80 | STUDIO_STORY `show` / single-plan `task` | per story | :80 follows (AC38) |
| studio-adopt :76-79, :348, :433, :586, :669-681, :790 | `stories/`, `runs/<slug>/landed.tsv` | shared dir | — |
| studio-adopt :448, :525, :759, :779-782 | STUDIO_STORY get, ledger, check | per story | — |
| studio-peers :18, :31 | story files read by `sed` | per-story file | STUDIO_STORY only; unaffected |
| studio-brief :69-99 | `get spec/plan`, ledger at WORK | per checkout (execute calls it in the feature checkout) | — |
| studio-dispatch :43; godot `test.sh` :60-63, `run.sh` :45-54, `slowest.sh` :20 | config, reports in the cwd checkout | per checkout | test logs are not state |
| hooks/session-start.sh :19-20 | `root --work`, `get stage` | per checkout, `STUDIO_STATE_NO_ADOPT=1` | AC19, AC28 |
| hooks/guard-state.sh :14 | glob `*/.studio/STATE.md` | covers local pointers | unchanged |
| hooks/operator-inbox.sh, peer-runs.sh | run dir | shared | — |
| hooks/stage-guard.sh, autopilot-guard.sh | nothing in `.studio/` | — | — |
| omega `delegate` SKILL :35, :42; omega hooks `pre-tool-use.sh` :13-15 | rely on `.studio/` being git-ignored | local pointer is excluded (AC6) | falsifier M1 |
| execute §8 :705-722 (stops before (c)) | START_DIR | main checkout: main still holds the story before the hand-off | unchanged |
| execute §10 :815-834 (`--progress`, cwd FINAL_W) | FINAL_W's pointer | per checkout (reads idle) | AC40; falsifier M1 |
| skills studio, brainstorm, plan, execute, playtest, review, retro | via studio-state | per checkout; `stories` from main | AC30-AC35 |
| autopilot SKILL :75, :81, :121, :135, :143, :150, :155 | `init --local`, STUDIO_STORY seeding, `reset --keep-ledger` | run-worktree pointer / story files | AC36 |
| omega `handoff` SKILL :34-41, :83 (not the verb) | `show`, `get` (read only) | this checkout's real story; idle when pointer-less | falsifier M8 |
| parallel SKILL :106, :129, :150 | bookkeeping in the controller's checkout | per checkout | AC41 |
| agents/producer.md :36 | ledger file by path | per story | — |
| multica install.sh :282, omega-multica-agent :16-17, bridge service.py :161-172 | `studio-state root`, `<root>/.studio` | shared | — |

### Supersedes #39 AC2's last bullet

#39's spec, AC2 (L129-132), says: "A story worktree never has a local pointer, so its behaviour is unchanged." This spec supersedes that bullet:
- a lane's story worktree still has no local pointer, because it works under STUDIO_STORY (AC5);
- every other linked worktree gets its own pointer: on its first write (AC6), by `init --local` (AC8), or by `handoff` / `take` (AC12-AC17).

The rest of #39 AC2 stands. #39's rejected alternative at L313-316 (story-keyed planning state) also stands: this spec keys by checkout path, not by story. #39's spec is not edited; it lives on its own branch and is history once merged.

## Architecture

### Before / after

- Before: one stage pointer per project, plus a local one only in run worktrees after `init --local`. Every other worktree reads and writes the main checkout's STATE.md.
- After:
  - every checkout resolves only its own pointer; a pointer-less worktree reads idle;
  - a story crosses checkouts only through `handoff`, `take` or the one-time adopt, under one mutex, in a strict, self-healing order;
  - `milestone` is read and written project-wide;
  - `stories` and `worktree` let the main checkout find the story to review, playtest, retro or resume;
  - the single-plan runner follows its story;
  - a same-checkout story switch is refused with exit 4.

### Files

- `studios/game-dev/bin/studio-state`:
  - resolution (AC1-AC5), on top of #39's :54-60;
  - auto-create through the shared `init --local` function, and `init`'s linked-worktree message;
  - `milestone` redirect and `show`'s milestone line;
  - `handoff`, `take`, restore, adopt, self-heal, the mutex;
  - `stories` and `worktree`'s candidate rule;
  - the story-switch guard, `--force`, `STUDIO_STATE_FORCE`, `STUDIO_STATE_NO_ADOPT`, exit 4;
  - header and usage.
- `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-channel.sh`, `studios/game-dev/bin/overnight-progress.sh` (AC38).
- `studios/game-dev/hooks/session-start.sh`, `studios/game-dev/hooks/bootstrap.md`.
- Skills: `studio`, `brainstorm`, `plan`, `execute`, `review`, `playtest`, `retro` (`studios/game-dev/skills/*/SKILL.md`); `shared/omega/skills/autopilot/SKILL.md` (no text change expected; AC36 is pinned).
- `studios/game-dev/memory/stage-pointer-is-per-checkout.md` (new), `studios/game-dev/memory/MEMORY.md`.
- Tests: `tests/state_test.sh`, `tests/hook_test.sh`, `tests/studio_test.sh`, `tests/overnight_test.sh`, `tests/overnight_progress_test.sh`.
- `docs/game-dev/PROGRESS.md`.

### Decisions

- **H: explicit hand-off, keyed by path, with no fallback.** Ruled by the operator over (a) and over C′ (the draft plus the falsifier's five rules). The bug is a cross-checkout write; H deletes the path instead of policing it. Seven of the falsifier's twelve C/I findings cannot arise, and the remaining ones have bounded fixes (Traceability).
- **Key by checkout path, not branch or story.** It survives a branch rename (KAN renames, renamed agent branches), reuses #39's file, exclude line and R2 code, and `git worktree remove` cleans it up.
- **No ownership guard, no claim, no provenance move.** Only `handoff`, `take` and adopt write two pointers, and all three run one locked function.
- **Execute hands off; a worktree-born story does not.** (c) runs `handoff` only when §0 ran in the main checkout outside a lane. `superpowers:using-git-worktrees` skips creation inside a linked worktree (execute :588-590), so a worktree-born story never needs one.
- **`take <spec>` names the spec**, so a take cannot grab a different story the main checkout started in the meantime (risk H-N5).
- **Adopt only at `execute`, or at `idle` with the story's ledger here.** A matching branch alone would move the main checkout's next story into a finished worktree (risk H-N4, fixture-verified).
- **Adopt runs on reads too, except in hooks.** A legacy executing worktree's first call is often `get plan` (execute §0 :16); a read that returned idle would stop the resume. Hooks pass `STUDIO_STATE_NO_ADOPT=1`, so no hook ever writes (risk H-N8).
- **Self-heal completes forward, or rolls back when the target is gone.** The `handed` line is written first, so every crash point is detectable from main's ledger.
- **`stories` includes finished stories**, so review from the main checkout finds a story whose pointer went idle at its finish (falsifier M5, C3).
- **`worktree` from main considers only `execute` and finished stories.** A worktree still in brainstorm or plan has no build to review or resume.
- **The lock covers the movers and every write to the main pointer, not local `set`.** See AC27.
- **No `studio-state pointer` verb.** The draft needed it to tell fallback from claimed pointers (D5). Under H, a pointer-less worktree is simply idle, and the take hint carries the only extra fact.
- **`init --local` keeps exit 1 on a second call.** The comparison's idle carve-out would invert #39's T2 Minor 2 test (`state_test.sh:634-636`), and nothing writes in a fresh run worktree before autopilot :81.
- **The take hint does not require a unique worktree.** The comparison's "spec exists in exactly one linked worktree" fails whenever two worktrees descend from the spec's commit, the common case. The hint only prints, so a broader condition costs nothing.
- **The overnight test stub changes** (falsifier I6). Its `branch` action becomes real execute's sequence; see Test strategy.
- **`stories` is a verb, not part of `show`**, because two parsers read `show` to EOF.
- **Supersedes the draft's D1-D5.** D1, D2 and the claim are moot (no ownership guard); D3 is AC24's `.studio/run` exemption; D4's lanes test is dropped (execute :629-634 skips step 3 under a lane, so AC10's test covers the stale read); D5's `pointer` verb is dropped (above).

### Failure handling

- Every refusal is exit 1 or 4 with nothing written, and the message the AC quotes.
- Auto-create failures (an unwritable `.studio/` or `info/exclude`) exit 1 with the failing path, as `init --local` does today.
- A mutex timeout exits 1 naming the holder; nothing is written.
- A git failure while listing worktrees makes `stories` print nothing and `worktree` exit 1; `handoff` and `take` refuse (exit 1). Under H nothing fails open into another checkout's pointer.

## Tuning knobs

None.

## Assets and audio

n/a.

## Test strategy

Shell suites, using a fixture of main checkout P plus linked worktrees made with `git worktree add`, as `rw_fixture` (`tests/state_test.sh` :610) does.

### New tests, mapped to ACs

| Test | Asserts | ACs |
|---|---|---|
| `test_state_main_checkout_unchanged` | P's `set`, `get`, `show`, `ledger`, `reset` behave as today on the main pointer. | 1, 43 |
| `test_state_two_worktrees_independent` | WA (feat/a) and WB (feat/b) each run `set stage brainstorm` and `set spec`. Each `get spec` returns its own; both files exist; `git status --porcelain` is empty in both; `info/exclude` holds the line once. | 2, 6 |
| `test_state_pointerless_reads_idle` | With P at `plan` with spec S, a fresh WC's `get stage` is `idle`, `get spec` is `-`, `show` prints `(no story in this checkout)`, `check` prints `check: ok`, `worktree` exits 1; nothing is created in WC and P is byte-identical. | 3 |
| `test_state_no_main_pointer_exits_1` | Without a main pointer, WC's `get stage` exits 1 as today. | 3 |
| `test_state_worktree_write_leaves_main_untouched` | P is byte-identical before and after `set`, `ledger` and `reset` in WA, and WA's file shows `stage: brainstorm` (#39 T2 Minor 1's vacuity fix). | 6 |
| `test_state_new_story_seeds_idle` | WC's first `set stage brainstorm` gives `spec -`, `plan -`, `task -`, `branch -` and no `milestone:` line. P is unchanged. | 6, 10, 43 |
| `test_state_ledger_auto_creates` | WC's `ledger "Bug: x"` with no pointer creates WC's pointer and appends the line to its `## Ledger`. | 6 |
| `test_state_auto_create_race` | Two concurrent first writes in WC both exit 0, both values land in one file, and `info/exclude` has the line once. | 6, 27 |
| `test_state_exclude_newline_repair` | An `info/exclude` without a final newline gets one before the appended line. | 6 |
| `test_state_reset_pointerless_noop` | `reset` and `check --rebuild` in a pointer-less WC print `no story in this checkout`, exit 0 and create nothing. | 7 |
| `test_state_init_local_is_auto_create` | `init --local` output equals auto-create's file; a second call exits 1 with `init --local: .* already exists`; the main-checkout and STUDIO_STORY refusals hold (#39 T2 Minor 2). | 8 |
| `test_state_init_in_linked_worktree` | `init` in WC exits 1 naming `init --local`. | 9 |
| `test_state_tracked_pointer_refused` | A force-added, committed `.studio/STATE.md` on WT's branch: WT reads idle, and its first `set` exits 1 naming `git rm --cached`; `take` and `handoff` into WT do too; under STUDIO_STORY, WT works. | 4, 5 |
| `test_state_story_writes_unchanged` | With STUDIO_STORY set, `set`, `ledger`, `check --rebuild` and `worktree` behave as today; no guard, adopt or self-heal runs. | 5, 23 |
| `test_state_milestone_is_project_wide` | WA's `set milestone alpha` sets main's milestone without creating WA's pointer. WA, P and `STUDIO_STORY=S1` all `get milestone` = alpha; `STUDIO_STORY=S1 set milestone beta` writes main; `show` in WA prints `milestone: beta`; a #39-style local pointer holding `milestone: prototype` reads beta; new story files have no `milestone:` line. | 10, 40, 42 |
| `test_state_milestone_without_main` | With only a local pointer, `get milestone` prints `prototype` and `set milestone` exits 1. | 11 |
| `test_state_handoff_moves_story` | P at `execute` with spec S, plan p, task 0/2, two pointer-ledger lines. `handoff WE` gives WE S/p/0/2 with `branch feat/e` and both lines plus `handed`; P idle with `branch -`, milestone kept, and only `handed` lines. | 12 |
| `test_state_handoff_order_and_self_heal` | A test hook stops `handoff` after step 3, then after step 4. The next P `get stage` completes it each time (WE holds S, P idle, one `handed` line). With WE removed after step 3, it rolls back with a `void` line. Under `STUDIO_STATE_NO_ADOPT=1`, nothing changes. | 13, 14, 19 |
| `test_state_handoff_refusals` | Exit 1 under STUDIO_STORY, to P itself, to a non-worktree path, and from an idle P. Exit 4 onto WA holding A, naming A; with `--force` it moves and writes a `forced` line. | 15, 25 |
| `test_state_take_main_planned_story` | P at `plan` with S (branch `-`). WX's `take S` moves it as `handoff` does; then WX's `set stage execute` writes WX only. | 16, 43 |
| `test_state_take_refusals` | `take T` while P holds S exits 4 (not overridable with `--force`); `take S` in P exits 1; `take S` while P is at `execute` with `branch feat/e` live in WE exits 4 naming WE. | 16 |
| `test_state_take_restores_removed_worktree` | After hand-off of S to WE, two `T<n> complete` lines, and `git worktree remove WE`: `worktree` from P exits 3 with the re-add-and-take line; running it gives WE `execute`, S, p, `branch feat/e`, `task 2/3` and a `restored` line; P is unchanged. With a `shipped` line, the restored stage is `idle`. | 17, 22 |
| `test_state_adopt_legacy_execute` | Pre-#42 state: P at `execute`, `branch feat/e`. WE's first `get plan` prints p; WE holds S; P is idle with a `handed … (adopted)` line. | 18, 43 |
| `test_state_adopt_legacy_finished` | P `idle`, spec S, `branch feat/e`, S's ledger in WE: WE's first call adopts. Without the ledger in WE, no adopt. | 18, 43 |
| `test_state_adopt_skips_next_story` | P at `brainstorm` (and then `plan`) with spec T and stale `branch feat/e`, WE on feat/e: WE's `get stage` is `idle`; P is byte-identical. | 18, 43 |
| `test_state_stories_lists_live_pointers` | `stories` from P and from WA lists P's in-place story, WA (`active`) and WE (`finished`) with path, git branch, stage, spec, task and state; skips pointer-less, idle-unfinished, prunable and removed worktrees; prints nothing and exits 0 when none. | 20 |
| `test_state_stories_branch_rename` | After `git branch -m feat/e KAN-1-e` in WE, `stories` shows the new name and `worktree` from WE still prints WE. | 20, 21 |
| `test_state_worktree_from_local_pointer` | In WE with `branch feat/e`, `worktree` prints WE; with `branch -`, it exits 1. | 21 |
| `test_state_worktree_candidates_from_main` | One finished WE: prints WE. WE finished plus WF at `execute`: exit 1, stderr lists both. WA at `plan` only: not a candidate. | 22 |
| `test_state_worktree_legacy_main_branch` | P `idle`, spec S, `branch feat/e`, no adopt yet: `worktree` from P prints WE; with WE removed, exit 3 as today. | 22, 43 |
| `test_state_review_from_main_finds_worktree_born_story` | Falsifier C3: WA's worktree-born story finishes; P holds a finished legacy `branch feat/e` with WE on disk; `worktree` from P lists both and exits 1; never prints WE alone. | 20, 22 |
| `test_state_story_switch_guard` | At `plan` with spec A, `set spec B` and `set stage brainstorm` exit 4 with the exact message, writing nothing; `set spec A` exits 0. At `brainstorm`, `set spec B` exits 0 with a warning naming A. Holds in P and in WA. | 24 |
| `test_state_story_switch_exempt_in_run_worktree` | With `<work root>/.studio/run` present, `set stage brainstorm` at `plan` and `set spec B` exit 0. | 24 |
| `test_state_force_override` | `set --force spec B` and `STUDIO_STATE_FORCE=1 set stage brainstorm` exit 0 with one `forced` line each; a forced write that needed no override writes none; `--force` in another position is a usage error. | 25 |
| `test_state_exit_codes_documented` | The usage text and header name exit 4. | 26, 37 |
| `test_state_mutex_serialises_moves` | A held `state.mutex` (live pid) makes `handoff` exit 1 after the timeout naming the pid; a dead pid's link is reaped and the move succeeds. | 27 |
| `test_state_main_write_holds_mutex` | While the mutex is held, P's `set` waits; WA's `set` does not. | 27 |
| `test_state_agent_worktree_isolated` | `.claude/worktrees/agent-abc` reads idle with P at `execute`; its write leaves P and WA unchanged; after `git worktree remove` (no `--force`) the file is gone and `stories` drops it. | 41 |
| `test_state_legacy_pointer_resolves` | A main pointer without `branch:` and a #39 local pointer both resolve and accept writes. | 42 |
| `test_state_round_trip_two_stories` | Milestone gate step 2. | 6, 12, 13, 20, 22, 24 |

AC44-AC46 (memory note, PR and PROGRESS text) have no shell test: the final whole-branch review checks them. `test_state_handoff_order_and_self_heal` stops the move through a test-only environment seam that the plan names.

### Other suites

- `hook_test.sh`:
  - `test_session_start_stage_per_checkout`: P idle and WA at `plan` print their own stages; a pointer-less worktree prints `stage idle`;
  - `test_session_start_take_hint`: P at `plan` with S, a pointer-less WC holding S's file: the line ends with the take hint; an `agent-*` worktree gets none;
  - `test_session_start_never_writes`: in an adoptable worktree and with an interrupted hand-off, the hook leaves every pointer byte-identical. (AC19, AC28.)
- `studio_test.sh`: update the literal pins on the skill text changed by AC29-AC36 (#39 branch :259-260, :275, :305-310, :331, :364). New named pins:
  - `test_skill_bootstrap_stage_line` (AC29);
  - `test_skill_router_lists_stories` (AC30);
  - `test_skill_brainstorm_tests_pointer_not_file` (AC31);
  - `test_skill_plan_take_hint` (AC32);
  - `test_skill_execute_handoff_at_isolation`, `test_skill_execute_resume_via_stories` (AC33);
  - `test_skill_review_playtest_ask_candidates` (AC34);
  - `test_skill_retro_resolves_story` (AC35);
  - `test_skill_autopilot_no_force` (AC36).
- `overnight_test.sh`:
  - `test_single_plan_follows_story_after_unit_1`: unit 1 hands off; unit 2's cwd is the story worktree, and the run ends `done` (AC38);
  - `test_single_plan_resume_line_names_story_worktree` (AC38);
  - `test_single_plan_ambiguous_story_stops` (AC38);
  - `test_single_plan_preflight_names_story` (AC38);
  - `test_single_plan_from_story_worktree`: the main pointer stays byte-identical (AC39);
  - `test_channel_ledger_follows_story` (AC38).
- `overnight_progress_test.sh`: `test_progress_task_follows_story` (AC38).
- `overnight_lanes_test.sh`, `studio_adopt_test.sh`, `overnight_runs_test.sh`, `overnight_sessions_test.sh`, `studio_peers_test.sh`, `studio_brief_test.sh`, `studio_setup_test.sh` (it adds a linked worktree at :50): run unchanged as regressions (AC5, AC40). The draft's `test_lanes_unit_milestone_reaches_project` is dropped (Decisions, D4).

### Existing tests that change

- `test_state_resolves_to_main_checkout` (:171): the `root` asserts stay. "The main checkout's STATE.md carries the change" and "the worktree holds no copy" invert: a worktree write creates its own pointer and the main pointer is unchanged.
- `test_state_ledger_per_branch` (:276): the last assert, "the pointer is shared", inverts (AC6).
- `test_state_local_pointer_only_when_present` (:638): the first assert inverts (auto-create). It is renamed `test_state_local_pointer_auto_created`.
- `test_state_worktree` (:419): "the same path from inside the worktree" now comes from the worktree's own pointer after a hand-off (AC21); the main-checkout asserts hold through AC22's legacy rule.
- `test_state_init_local_creates_pointer` (:621): the created file has no `milestone:` line (AC8, AC10).
- **The `overnight_test.sh` stub** (falsifier I6). Its `branch` action (:50-52) becomes real execute's sequence: `git worktree add`, then `studio-state handoff <wt>`; the same scenario line's later `stage`, `task` and `ledger` actions run in that worktree, and later units start there through the follow. A new `legacybranch` action keeps today's `set branch` from P for the migration tests. Affected scenarios: :574, :666 (`ISO1`, reused by several tests), :1565, :1570, :1643, :1656, :1668, :1677, :1691, :1710, :1767, plus their later units' `task n/N` lines. :492 and :508 assert unit 1's cwd only, so they hold.

## Risks

- **The runner follow touches #39's T12/T13 files** (studio-overnight, overnight-channel.sh, overnight-progress.sh). Moot when #42 is built after #39 merges, as planned. Without the follow, a single-plan run from P stops after unit 1 with `stop: unexpected stage idle` (:1189): loud, with no corruption.
- **A stale tool bypasses everything.** A pre-#42 `studio-state` run by path from an un-rebased worktree still writes the main pointer (AC46).
- **Same-checkout lost updates.** Two writes racing inside one checkout (parallel Bash calls) can lose one, as today. AC6's `ln` covers the creation race only.
- **Finished stories stay listed** while their worktree stays on disk, so review from P may ask between several. That is the cost of finding them at all (Open item 2).
- **More explicit steps.** Continuing a main story from a hand-made worktree takes one `take`; a session restarted in P mid-execute sees idle unless the router and execute §0 read `stories` (AC30, AC33). Both fail loudly, and the skill text is pinned.

## Not doing

- Story-keyed pointer files (design (b)), the draft's claim rule, its ownership guard and its provenance move (design (a) and C′).
- Any read fallback from a pointer-less worktree to the main pointer.
- A `studio-state pointer` verb.
- A lock on writes to a local pointer (AC27).
- An idle carve-out for a second `init --local` (Decisions).
- Moving `handed` lines out of the main pointer (Deviation D1).
- Keeping a pointer-less checkout's ledger lines anywhere but its own STATE.md (risk H-N7). The router's bug route (studio :90) or a subagent writing `ledger` in a fresh worktree now auto-creates that worktree's pointer, and the line dies with the worktree. Today it is misfiled into the main story's ledger instead; the bug fix's commit remains the record.
- Rebuilding a worktree-born story's `spec` and `plan` from its committed ledger after its worktree is re-made (a possible follow-up).
- Ageing finished stories out of `stories` by merge status.
- The stall watchdog (#43) and the sdd-script helper (#41).
- Editing #39's spec, or the per-machine phoenix memory note.

## Deviations to rule on

- **D1 — `handed` lines stay in the main pointer's ledger.** (Load-bearing.) The ruling moves "main's story (header plus pointer ledger)" to the worktree. Moving every line would also carry earlier stories' `handed` lines into the new worktree, where they die with it. AC17's restore and AC22's exit-3 path read main's newest `handed <spec>` line, so a removed worktree of an earlier story could no longer be re-made and restored (risk H-N3). AC12 therefore moves every pointer-ledger line except `handed` lines, which stay in main (and the new one is written to both files). Rule: accept, or move everything and drop restore for all but the newest story.

## Traceability

| Finding | Covered by |
|---|---|
| C1 stale `branch` blocks the main checkout's next story | n/a under H: no ownership guard, and `handoff` resets main's `branch` to `-` (AC12). Gate step 2 checks it |
| C2 resume and single-plan unit 2+ refused | n/a as a refusal (no ownership guard); main idle after the hand-off is handled by AC33 (execute §0 via `stories`) and AC38 (runner follow) |
| C3 review/playtest/retro from P target the wrong story | AC20, AC22, AC34, AC35; `test_state_review_from_main_finds_worktree_born_story` |
| I1 claim needs `branch -` | n/a under H: no claim; a hand-made worktree runs `take` (AC16) |
| I2 brainstorm §0 and bootstrap test the file | AC9, AC29, AC31 |
| I3 brainstorm in P, plan in a worktree splits | AC16, AC28 hint, AC32 |
| I4 branch rename splits a claimed story | n/a under H: keyed by path; AC20 reads the branch from git, AC21 prints the work root |
| I5 provenance does not prove provenance | n/a under H: no automatic move; the AC28 hint only prints |
| I6 overnight_test stub breaks | Existing tests that change (stub); AC38 tests |
| I7 tracked-pointer hard fail too wide; phoenix unverified | AC4 (scoped to R2, auto-create, take, handoff); phoenix verified excluded |
| I8 no lock | AC6 (`ln` create, exclude under the mutex), AC13, AC27 |
| I9 fresh or re-made worktree reads main's story | AC3, AC30 (router never routes to execute there) |
| M1 inventory omissions | Inventory rows (delegate, pre-tool-use, §8, §10, `init`), AC9; other suites listed |
| M2 agent/parallel worktrees read main's story | AC41 (read idle) |
| M3 `reset` / `check --rebuild` in a fallback checkout | AC7 |
| M4 milestone with no main pointer | AC11 |
| M5 finished stories missing from `stories` | AC20 (`finished`) |
| M6 home-checkout ownership never used | n/a under H: no ownership |
| M7 `forced` line placement on `reset` | n/a under H: `reset` is unguarded; AC25 places the line before the write |
| M8 omega handoff SKILL reports main's story | n/a under H: it reads this checkout's real pointer (inventory row) |
| M9 `--force` at autopilot :135 redundant | AC36 |
| M10 ACs without tests | Every AC maps to a test above; AC29-AC36 have named pins |
| H-N1 runner stops after unit 1 | AC38 |
| H-N2 a partial take duplicates a story | AC13, AC14; `test_state_handoff_order_and_self_heal` |
| H-N3 a removed worktree loses a handed story | AC12 (`handed` line), AC17, AC22; D1 |
| H-N4 adopt by branch steals main's next story | AC18; `test_state_adopt_skips_next_story` |
| H-N5 `take` races the main checkout's next story | AC16 (`take <spec>`, mismatch exit 4) |
| H-N6 interactive friction | AC28, AC30, AC32, AC33; Risks |
| H-N7 ledger lines in a pointer-less checkout die with it | Not doing (accepted, with reason) |
| H-N8 a hook moves state | AC19 |
| Draft D1-D5 | Decisions ("Supersedes the draft's D1-D5") |

## Open / UNVERIFIED

1. **`/clear` re-runs SessionStart in the EnterWorktree directory** (proposal falsify item 10). UNVERIFIED on the harness. It rests on execute :568-575 and `hooks.json` :5 (`startup|clear|compact`). AC28's per-checkout line depends on it. Milestone gate step 3 observes it.
2. **Finished stories in `stories`.** A finished story stays listed until its worktree is removed or its pointer starts a new story. If review from P asks too often, a follow-up can drop stories whose branch is merged into the default branch.
3. **The size estimates** (about 240-270 lines in studio-state, about 25 in the runner, about 40 new tests) come from reading, not from a build.
4. **The phoenix migration state** is inferred, not read: the comparison's fixture reproduces the stale-branch state, and gate step 3's first bullet records the real one before the reinstall.

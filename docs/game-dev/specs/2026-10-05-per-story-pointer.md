# A stage pointer per checkout, with explicit hand-off — Spec

Date: 2026-10-05
Status: Draft
Milestone: Plan 3 — Content (studio tooling; follows concurrent runs, #39)
Classification: architectural
Base: origin/main once #39 has merged. The build rebases onto #39's resolution code, `studio-state:54-60`. Line numbers below are on branch `worktree-issue-39-concurrent-runs` at 0286a47. The plan sets its own file and line targets after #39 merges.

Issue: #42. Design **H**, as re-ruled by the operator on 2026-10-05: an explicit hand-off, keyed by path, with no fallback. It replaces the draft's design (a), the claim rule, which the spec falsifier rejected with 3 Critical and 9 Important findings. A second falsifier pass on H (f2: 1 Critical, 9 Important, 16 Minor) is folded in; see Traceability.

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
- Added: exit code 4 (refused: a story switch in this checkout, a story write on a checkout whose story moved away, or a move that would replace another story).
- Changed: `/game-dev:studio`, execute's resume, review, playtest and retro from the main checkout consult `stories`.
- Changed: the single-plan overnight runner follows its story into the worktree after unit 1.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A refused write changes nothing and exits 4. Its stderr names the story and the way out (AC24, AC25).
- An interrupted hand-off is completed or rolled back by the next `studio-state` call that sees it (AC14).
- A removed worktree takes its pointer with it. For a handed story, the main checkout's `handed` line keeps spec, plan and branch: `worktree` from P exits 1 and lists the newest such story as a `removed` candidate with the re-add-and-take command, so the calling skill asks the user before re-making it; `take <spec>` in the re-made worktree restores the pointer (AC17, AC22).
- A worktree-born story whose worktree is removed loses its pointer. Recover with `set spec`, `set plan`, `set stage`, `set task 0/<N>` and `check --rebuild`, as documented in the PR and PROGRESS.
- A worktree whose state was clobbered before the upgrade reads idle after it, and recovers the same way. So does a finished story whose main pointer was overwritten before the upgrade: it has no `handed` line and is invisible to `stories`, and review from P asks the user (AC43, AC45; f2-M16).

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
- Spec falsifier report on design H at e16634e (f2: C1, I1-I9, M1-M16), read-only, 2026-10-05, with a fixture that lost one of two parallel local `set` writes in 40 of 40 trials. Folded in and traced as `f2-…` in "Traceability".
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
- **Run worktree**: a linked worktree holding `<work root>/.studio/run` (#39's manifest runs). `stories` marks it `run`, and no resolution treats it as a story to continue (AC20; f2-I7).
- **Move record**: a line in a pointer's `## Ledger` written only by a move (AC12-AC14). Its fields are TAB-separated `key=value` pairs, `path=` always last, so a spec, plan or path with spaces, ` to ` or `(` parses (f2-M2):
  - `- <date> handing<TAB>spec=<spec><TAB>plan=<plan><TAB>branch=<branch><TAB>path=<path>` — the intent, in the main pointer only;
  - `- <date> handed<TAB>…` — the same fields, the completed move, in both pointers (adopt adds `via=adopt` before `path=`);
  - `- <date> void<TAB>…<TAB>reason=<why><TAB>path=<path>` — a rolled-back intent.

  At most one `handing` line exists at a time: the move that writes it holds the mutex, and completion or rollback rewrites it in place.
- **Default branch**: as execute's Feature-checkout procedures define it (`origin/HEAD`, else the first of `main` and `master` that exists).
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

6. **First write creates the pointer.** In a pointer-less worktree, the first `set` (any key except `milestone`) or `ledger`, holding the mutex for the whole call (AC27):
   - creates the local pointer through the one function `init --local` uses: the idle template, without a `milestone:` line, written to a temporary file and linked into place with `ln` (never clobbers; an `ln` that loses a race uses the winner's file);
   - appends `.studio/STATE.md` to `<common git dir>/info/exclude` once, repairing a missing final newline first, as #39 does;
   - then applies the write. Two concurrent first writes are serialised by the mutex, so both values land (f2-I6).

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
    - the target pointer holds main's `stage`, `spec`, `plan` and `task`, with `branch` set to the branch `<path>` has checked out (from `git worktree list`), then the target's own `## Ledger` lines when it had an idle pointer (f2-M7), then the new `handed` line;
    - the main pointer holds the idle header (`stage idle`, `spec -`, `plan -`, `task -`, `branch -`, its `milestone` kept). Its `## Ledger` is unchanged except that this move's `handing` line now reads `handed` (Deviation D1, revised; f2-I9). Main's other ledger lines (idle `Bug:` notes, `abandoned`, `forced`, `void`, earlier move records) are not the story's: while `spec` is set, every `ledger` call goes to the feature ledger (`studio-state:168-172`). They stay in main;
    - the `handed` line, in both files, is the move record of Terms;
    - it prints `handed <spec> to <path>` and exits 0.
13. **Strict order, under the mutex.** `handoff`, `take` and adopt run one function, in this order:
    1. take the mutex (once for the whole invocation, AC27);
    2. run self-heal (AC14), then the checks (AC15, AC16);
    3. append the `handing` line to the main pointer's `## Ledger` (the intent record);
    4. write the target pointer (AC12's content): by tmp + `ln` when it is absent, or by tmp + `mv` over an idle, unfinished one after re-reading it under the mutex;
    5. replace the main pointer in one tmp + `mv` with AC12's idle form, in which the `handing` line is rewritten to `handed`;
    6. release the mutex.

    Every crash point leaves either no `handing` line (before step 3, after step 5) or exactly one, which AC14 resolves. No step leaves both pointers non-idle with different content and no record of why.
14. **Self-heal** (risk H-N2; f2-I2). A hand-off is incomplete exactly when the main pointer's `## Ledger` holds a `handing` line. A `handed` or `void` line is never acted on, so a completed or rolled-back move, or a later story that re-plans the same spec, never triggers it. The pointer-resolving verbs (`get`, `set`, `show`, `ledger`, `check`, `reset`, `worktree`) in the main checkout, and every `handoff`, `take` and `stories` call from any checkout, first resolve the newest `handing` line. They detect it without the lock, then re-read it under the mutex (f2-M3: `root`, `init` and usage errors never heal, so the `studio-peers` and `studio-gate` calls of `root` never write). For the line's `spec` S and `path` W:
    - W is a live worktree whose pointer holds S, at any stage: run step 5 only (when main no longer holds S, only the line is rewritten to `handed`). The target's progress is kept (a target already at `task 2/3` stays there);
    - W is a live worktree with no local pointer, or an idle unfinished one, and main still holds S: complete steps 4 and 5;
    - otherwise (W is not a live worktree, holds another story, is detached or tracked, or main no longer holds S): roll back. Main keeps its story, and the line is rewritten in place to `void`, with `reason=` naming the cause (`worktree gone`, `target holds <slug>`, …). A second command finds no `handing` line and does nothing more.

    It is skipped under `STUDIO_STATE_NO_ADOPT=1` (AC19). A re-run of the same `handoff` after a crash heals first, and so writes no second `handing` or `handed` line.
15. **`handoff` refusals.**
    - Exit 1, nothing written: STUDIO_STORY is set; `<path>` is not a live linked worktree of this repository, or is the main checkout; the main pointer is idle; `<path>` has a tracked STATE.md (AC4); `<path>` is on a detached HEAD (`studio-state: <path> has a detached HEAD — check out the story's branch there first`; f2-M8); main's `spec`, `plan` or `<path>` holds a TAB (`studio-state: a TAB in <field> cannot be recorded`).
    - Exit 4, nothing written: the target holds a story, active or finished, with a different spec. stderr: `studio-state: <path> holds story <spec slug> (stage <s>) — finish or reset it there first, or pass --force`. A finished story counts, because the move would erase a story awaiting review (f2-M7). `--force` overrides it (AC25).
16. **`studio-state take <spec>`** runs in a linked worktree and moves the main checkout's story here: AC12-AC14 with `<path>` = this checkout. It continues a main-planned story from a worktree made by hand. Before AC15's checks:
    - this checkout's pointer already holds `<spec>`: exit 0, print `<spec> is already in this checkout`, write nothing (the state after self-heal completed the move; f2-M7);
    - exit 1 in the main checkout;
    - exit 4, not overridable, when main's `spec` is not `<spec>` (risk H-N5) and no `handed` line restores it (AC17): `studio-state: the main checkout's story is <main spec>, not <spec>`;
    - exit 4, not overridable, when main is at `execute` with a `branch` that is checked out in another live worktree (a story claimed before #42): `studio-state: <spec> is being executed in <path> — continue it there`.

    AC15's exit 4 applies to `take` too, and `take --force <spec>` overrides it.
17. **Restore** (risk H-N3). `take <spec>`, when the main pointer does not hold `<spec>`, uses main's newest `handed` line with `spec=<spec>` when its `path` is not a live worktree other than this one, and either:
    - its `branch` is this checkout's current branch; or
    - its `branch` no longer exists and this checkout holds `<work root>/.studio/ledger/<slug>.md` (a renamed branch; f2-M1).

    It then:
    - rebuilds this checkout's pointer from that line: `spec`, `plan`, and `branch` = the current branch; `stage idle` when this checkout's feature ledger has a `shipped` line, else `stage execute`; `task 0/<N>`, with `N` counted as `check --rebuild` counts it under STUDIO_STORY (`### Task` headings above `## Backlog`), then rebuilt from the feature ledger's `T<n> complete` lines;
    - appends `- <date> restored <spec> from the handed line` to this pointer's ledger;
    - leaves the main pointer unchanged, and exits 0.
18. **Adopt, the one-time migration** (risk H-N4). In a pointer-less worktree, with STUDIO_STORY and `STUDIO_STATE_NO_ADOPT` unset, every pointer-resolving command (`get`, `set`, `show`, `ledger`, `check`, `reset`, `worktree`) first runs `take <main spec>` silently, when all of these hold:
    - main's `branch` equals the current branch, and is neither `-` nor empty;
    - main's `stage` is `execute`, or main's `stage` is `idle` with `spec` not `-` and `<work root>/.studio/ledger/<slug>.md` present.

    This is the state today's execute (c) leaves, converted. It never fires at `brainstorm` or `plan`, so a stale `branch` cannot move the main checkout's next story into a finished worktree. The `handed` line carries `via=adopt`. After #42, the state arises again only from an in-place story (execute on a feature branch in the main checkout, AC33), when a later worktree checks out that branch: adopt then moves that same story, which is harmless (f2-M10).
19. **Hooks and read-only reporters never write.** `hooks/session-start.sh` runs `studio-state` with `STUDIO_STATE_NO_ADOPT=1`. That suppresses adopt (AC18) and self-heal (AC14), so a hook never writes a pointer; it prints AC28's line instead (risk H-N8). The omega `handoff` SKILL (`shared/omega/skills/handoff/SKILL.md` :34-35, :39-41), which reports state and must "never change it", runs its `studio-state show` and `get` calls the same way (f2-M11).

Stories and the feature checkout

20. **`studio-state stories`** lists the live pointers, from any checkout. It prints one TSV line per story, `<path>\t<branch>\t<stage>\t<spec>\t<task>\t<state>`, where:
    - `<branch>` comes from `git worktree list` (rename-proof), or `-` on a detached HEAD;
    - `<state>` is `run` when `<path>/.studio/run` exists, whatever the stage (a #39 run worktree walking its manifest; f2-I7); otherwise `active` or `finished` (Terms);
    - main's pointer is listed when its story is active or finished. Its `<path>` is the live worktree that has main's `branch` checked out when that branch is neither `-` nor empty and main's stage is `execute` or `idle` (an in-place story, or one executed before #42); otherwise it is the main checkout. At `brainstorm` or `plan`, a recorded `branch` is stale and is ignored;
    - then each live linked worktree's local pointer, active, finished or run, in `git worktree list` order.

    It skips pointer-less worktrees, idle pointers that are not finished, and prunable or missing worktrees. With none, it prints nothing and exits 0. When `git worktree list` fails, it prints `studio-state: git worktree list failed` and exits 1, so no caller reads a git failure as "no stories" (f2-M14). It writes nothing except AC14's self-heal. A `run` line is never a story to continue: `worktree` (AC22), the router (AC30), execute §0 (AC33) and the runner's `story_dir()` (AC38) skip it. `show`'s format is unchanged, because `studio-overnight` :535-537 and `overnight-channel.sh` :189-191 parse it from `## Feature ledger:` to EOF.
21. **`worktree` from a local pointer** exits 1 with `studio-state: no feature branch recorded` when its `branch` is `-` or empty, as today. Otherwise:
    - the recorded branch is checked out in another live worktree (the user switched this checkout's branch): exit 1 with `studio-state: this checkout's story is on <branch>, which is checked out in <other> — switch this checkout back to <branch>` (f2-M12). It never prints `<other>`: that checkout's pointer does not hold the story, so the caller would read idle there (AC3);
    - otherwise it prints the work root (the story's checkout), whatever the branch is now called (falsifier I4).
22. **`worktree` from the main checkout**, with STUDIO_STORY unset:
    - **Main at `execute`** (f2-C1): only main's own story is considered, resolved from main's `branch` exactly as today (`studio-state:382-425`): `-` or empty → exit 1 `studio-state: no feature branch recorded`; a missing branch → exit 1 `branch <b> no longer exists`; a live worktree with it checked out → that path (the main checkout itself for an in-place story), exit 0; otherwise exit 3 with today's add command. So a resume after a stop before isolation (c) isolates again (execute (a)), and never enters another story's worktree.
    - Otherwise the candidates are:
      - each `stories` line other than main's own at stage `execute` or state `finished` (not `run`; a story in brainstorm or plan has nothing to review);
      - main's recorded `branch` at stage `idle`, when it is neither `-` nor empty and a live worktree has it checked out, whatever main's `spec` (an in-place story, a pre-#42 one, or `test_state_worktree`'s fixture; f2-I5): that worktree's path.
    - One candidate: print its path, exit 0.
    - Several: exit 1. stderr is `studio-state: <n> stories fit — choose one:`, then one line per candidate, `<path>\t<branch>\t<spec>\t<state>`.
    - None, while main at `idle` records a `branch` that exists but no worktree has checked out: exit 3, as today (`studio-state:421-424`). None, while that branch no longer exists: exit 1 `branch <b> no longer exists`, as today.
    - None otherwise: main's **newest** `handed` line only (f2-I4) is offered when its `path` is not a live worktree, its `branch` exists and is not merged into the default branch (`git merge-base --is-ancestor <branch> <default branch>` fails), and no live pointer, main's included, holds its `spec`. Then exit 1 — never 3, so review and playtest never re-make it unasked — with stderr `studio-state: 1 story fits — choose one:` and one candidate line `<path>\t<branch>\t<spec>\tremoved\t<command>`, where `<command>` is `git worktree add <path> <branch> && (cd <path> && studio-state take <spec>)` with today's unlock/prune prefix when a stale entry holds the branch. An abandoned-and-removed story is only offered, never re-made unasked, and only until the next move writes a newer `handed` line; a merged one is never offered.
    - Else exit 1 with `studio-state: no feature branch recorded`.
23. **`worktree` under STUDIO_STORY** is unchanged.

Story-switch guard (same checkout)

24. **The guard** covers two sessions in one checkout, the 2026-09-19 case. With STUDIO_STORY unset, on whichever pointer this checkout resolves:
    - `set stage brainstorm` while `stage` is `plan` or `execute` exits 4;
    - `set spec X` while `stage` is `plan` or `execute` and `spec` is neither `-` nor X exits 4;
    - both print exactly `studio-state: this checkout is on story <spec slug> (stage <s>, task <t>) — finish or reset it first, start the new story in its own worktree (EnterWorktree), or pass --force`, and write nothing;
    - at `stage brainstorm`, `set spec X` over a different spec (not `-`) exits 0, writes, and prints one stderr warning naming the old spec. Brainstorm §0 already asks the user;
    - **story-less writes after a move** (f2-I3): on a pointer whose `spec` is `-` and whose `## Ledger` holds a `handed` line, `set stage plan`, `set stage execute`, `set plan <path>` and `set task <n/N>` exit 4 and write nothing. stderr: `studio-state: this checkout holds no story — <spec> moved to <path> on <date>; continue it there, start a new story with /game-dev:brainstorm, or pass --force`, from the newest `handed` line. This stops a live main-checkout session from writing on after another session's `take` moved its story (its next `set stage plan` lands here), so execute's precondition can never pass in both checkouts. `set … -` (clearing) is allowed. Pointers with no `handed` line are unaffected: every pre-#42 file, and the fixtures that set these keys before or without `spec` (`tests/state_test.sh` :80, :86, :548-592).

    The guard is skipped when `<work root>/.studio/run` exists: a run worktree's pointer walks the manifest's rows (autopilot :121, :135; brainstorm :61). `reset` is not guarded: the router confirms an abandon with the user first.
25. **Override.** `--force` (`set --force KEY VALUE`, `take --force <spec>`, `handoff --force <path>`) or `STUDIO_STATE_FORCE=1` bypasses AC24 and AC15's exit 4. A forced write that would otherwise have been refused first appends `- <date> forced <key>=<value> over <old spec> (stage <s>)` to the written pointer's `## Ledger` (`handoff` as the key for a forced move). `--force` is accepted only in these positions; anywhere else it is a usage error, as today. No `forced` line is written when nothing was refused. AC16's two refusals are not overridable.
26. **Exit codes.** The usage text and the header's `Exit:` line add `4 refused: a story switch in this checkout, a story write after the story moved away, or a take/handoff onto another story or the wrong spec (--force overrides where stated)`. No other path exits 4.

Lock

27. **The mutex** is `<root>/.studio/state.mutex`, #39's `mx_take` / `mx_drop` pattern (`overnight-runs.sh:97-110`): a symlink to the holder's pid, a dead holder's link reaped, about 10 s of retries, then exit 1 with `studio-state: <root>/.studio/state.mutex is busy (pid <p>)`.
    - **Every write takes it** (f2-I6), with STUDIO_STORY unset: `set`, `ledger`, `reset`, `check --rebuild`, auto-create (AC6), `handoff`, `take` (restore included), adopt (AC13) and self-heal (AC14), on the main pointer and on local pointers alike; and `set milestone` from any checkout, under STUDIO_STORY too. Reads take no lock: `write_field`'s tmp + `mv` means a reader sees the old file or the new one.
    - Why every write: two parallel `set` calls in one checkout (plan :151-153 issues four writes, which an agent may run as parallel Bash calls) lost one of the two values in 40 of 40 fixture trials, and `handoff` step 4 re-checks the target idle and then `mv`s over it, which a concurrent unlocked local `set` would undo. The cost is one `ln -s` and one `rm` per write, about 1 ms; lanes are untouched, because STUDIO_STORY writes take no lock (AC5).
    - **One acquisition per invocation** (f2-M4): a command takes the mutex at most once, before its first write or heal, and an `EXIT`/`INT`/`TERM` trap releases it (`mx_drop` checks the owner pid). Self-heal followed by `handoff`, `take`, adopt or the write itself reuses it, never re-takes it.
    - **Exclude and directory** (f2-M5): the first take in a repository appends `.studio/state.mutex` to `<common git dir>/info/exclude` once (newline repair as AC6), so a dangling link left by a killed holder never shows in `git status`. The mutex needs `<root>/.studio`; without it, every command that would take it already exits 1 (AC3, AC11), except `init --local`, which then takes none (with `<root>/.studio` present it takes the mutex, as auto-create does).

Hooks and skills

28. **SessionStart** (`hooks/session-start.sh`) prints the stage of the checkout the session starts in: P idle and WA at `plan` print `stage idle` from P and `stage plan` from WA, and a pointer-less worktree prints `stage idle`. It runs with `STUDIO_STATE_NO_ADOPT=1` (AC19). The comment at :15-17 reads "studio-state resolves this checkout's own pointer". **The take hint**: when the checkout is pointer-less, is not under `.claude/worktrees/agent-*`, main's story is active, and main's spec exists as a file in this checkout, the line ends with ` · the main checkout's story <spec> (stage <s>) — if no session is working on it in <main checkout>, studio-state take <spec> continues it here` (f2-I3). The hint is suppressed only when main is at `execute` with its `branch` checked out in another live worktree, the case AC16's third refusal covers (f2-I8): a `branch` recorded at `brainstorm` or `plan` is stale (AC20) and never hides it. `show` prints the same hint (AC3). An adoptable worktree (AC18) gets the hint worded `— it moves here on the first studio-state call` instead.
29. `hooks/bootstrap.md` :27 reads: "When `studio-state get stage` succeeds, a line naming this checkout's stage follows this bootstrap (a linked worktree with no story of its own reads idle); `/game-dev:studio` names the next step from it. When it fails and this is a Godot project, `/game-dev:studio` initialises it."
30. **Studio router** (`studio/SKILL.md`):
    - :16 runs `studio-state show` in the checkout it is in;
    - in the main checkout it also runs `studio-state stories` and lists each story on one line with the checkout to continue it in; a `run` line is listed as `run in progress in <path>`, never as a story to continue (f2-I7). When main is idle and a story is active elsewhere, `Next:` names that checkout first (`continue <spec> in <path>`), then `/game-dev:brainstorm` for a new story;
    - in a pointer-less worktree with the take hint, `Next:` names `studio-state take <spec>` (to continue main's story here) or `/game-dev:brainstorm` (a new story), never `/game-dev:execute` (falsifier I9);
    - abandon (:66-71) resets this checkout's pointer only. For a story in another checkout, it names `abandon it in <path>`. On exit 4 it shows the message;
    - the Rules' write list (:104-107) adds: "a pre-#42 worktree's one-time adopt (studio-state AC18) may move its story into it on the router's first read" (f2-M11). The router needs the real story, so it does not suppress adopt.
31. **Brainstorm §0** (:16-19): the state test is `studio-state get stage` exiting 0, not the presence of `.studio/STATE.md` (falsifier I2). On exit 1 with `project.godot` present, it asks to initialise as today. On exit 4 from `set stage brainstorm` or `set spec`, it stops, shows the message, and suggests EnterWorktree. Before :61's `set stage brainstorm`, when `stage` is `plan` it asks once: "revise `<spec>`, or start a new story in its own worktree?". On "revise", it runs `studio-state set --force stage brainstorm`; the `forced` line records the user's choice, and `set spec` over the same spec is never refused. At `execute` it offers no revise and stops on exit 4 as above (f2-M9).
32. **Plan §0** (:28-33): in a pointer-less worktree whose `show` prints the take hint, it stops with "the main checkout's story `<spec>` is waiting: continue it in `<main checkout>`, or run `studio-state take <spec>` here" (falsifier I3). Exit 4 from any state write (:151-153) stops and shows the message.
33. **Execute:**
    - :53-55 reads: "Each checkout has its own pointer. A story planned in the main checkout moves to its execute worktree at isolation (c) (`studio-state handoff`); a story born in a worktree stays there. So every call below reads the story's own pointer from the feature worktree";
    - §0, before "Which run this is": in the main checkout at `stage idle`, run `studio-state stories`. With exactly one `active` line at stage `plan` or `execute` (a `run` line never counts; f2-I7), enter that checkout (Enter the feature checkout, Exit 0 way) and run §0 there; with several, ask the user once which; with none, today's stop (risk H-N6). A non-zero `stories` exit stops and shows its message (f2-M14);
    - a resume in the main checkout at `stage execute` with `branch -` (a stop before (c)) is unchanged: `studio-state worktree` exits 1 with `no feature branch recorded` (AC22's main-at-execute rule), and (a) isolates as a new run does (f2-C1);
    - (c) at :169-171: when this run's §0 ran in the main checkout, outside a lane, **and** the top level after isolation (`git rev-parse --show-toplevel`) is not the main checkout (the first `worktree` line of `git worktree list --porcelain`), first run `studio-state handoff "$(git rev-parse --show-toplevel)"` inside the new worktree, then `set branch` as today (now a no-op). When the user consented to work in place (:160-161, the default-branch path at :539-542), the top level is the main checkout: no hand-off runs, and `set branch "$(git branch --show-current)"` writes the main pointer as today (f2-I1). Any non-zero exit from `handoff` stops and shows the message, a killed call included (f2-M15). A worktree-born story runs no hand-off;
    - :534 notes that `set milestone` writes the project's milestone.
34. **Review and playtest** (review :20-30, :55-62; playtest :23-33, :50-57):
    - Enter the feature checkout's Exit 1 text reads: "more than one story fits, a removed story's worktree is offered, or none is recorded. Ask the user once which checkout to use, naming the candidates `studio-state worktree` listed on stderr (or that none is recorded) and the `git worktree list` paths. For a `removed` candidate the user picks, run its command, then enter the path it added". Review and playtest never run a `removed` command unasked, so review still never changes `stage` on its own (f2-I4);
    - the which-feature check keeps its logic; its cause reads "this checkout's pointer moved on to the next feature".
35. **Retro** (:16-35) resolves the story the same way: `studio-state worktree` from the main checkout. At exit 0 it reads the spec and ledger in that checkout (`(cd <path> && studio-state show)`; the session does not move). At exit 1 with candidates, it asks the user once which story, the only question retro asks; for a `removed` candidate it reads `git show <branch>:.studio/ledger/<slug>.md` with `<branch>` and `<spec>` from that candidate line, and creates no worktree (f2-I4). At exit 3 (main's own recorded branch, AC22) it reads `git show <branch>:.studio/ledger/<slug>.md` as today. ":16-18, asks the user nothing … changes no stage or pointer" is reworded to match: it asks at most that one question, and a pre-#42 worktree's one-time adopt (AC18) may move a story into that worktree when retro first reads it (f2-M11).
36. **Autopilot** (`shared/omega/skills/autopilot/SKILL.md`): :81 keeps `studio-state init --local`, the explicit form. :121 and :135 are unchanged, with no `--force`: the run worktree has `.studio/run`, so AC24 is skipped there (falsifier M9).
37. **The studio-state header comment** (:2-9) and usage (:72-75) describe AC1-AC27, replacing "so a linked git worktree edits the same file and one project has one stage".

Overnight

38. **The single-plan runner follows its story** (risk H-N1). `studio-overnight start`, single-plan, with STUDIO_STORY unset:
    - persists the run's `spec` with the run's record at start (the lock and registry fields of :201 and :969), so a process without the runner's variables can resolve it (f2-M6);
    - `story_dir()` returns START_DIR while START_DIR's pointer `spec` is the run's spec; otherwise the path of the one `stories` line with that spec (`run` lines excluded; f2-I7); otherwise the path of main's newest `handed` line with that spec, when it is a live worktree; with two matching `stories` lines, the run stops with `stop: ambiguous story <spec>` and never guesses. When nothing resolves, the runner stops with `stop: story <spec> not found`; a record with no persisted spec, or with `-` (a run started before #42, or the `overnight_progress_test.sh` :135-193 fixtures at `spec: -`), resolves to START_DIR, as today;
    - `story_dir()` reads the persisted spec from the record, so the callers outside the runner's process use it too: `status` (:1495 `state get task`), the reap and report subshells (:1513, :1548) and the channel verbs. A `status` whose story does not resolve prints `story <spec> not found` in place of the task;
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
    | The same, but main's brainstorm or plan for spec A was written from worktree WA (the 2026-10-05 trigger) | WA shows the take hint despite the stale `branch` (AC28); `take A` in WA moves it; WE does not adopt (f2-I8) | `test_state_take_hint_under_stale_branch` |
    | Worktree that wrote its brainstorm or plan into main's pointer (the EnterWorktree pattern; main `branch -`) | Reads idle with the take hint; one `studio-state take <spec>` moves it (documented in the PR and PROGRESS); no automatic move | `test_state_take_main_planned_story` |
    | Worktree whose state was clobbered before the upgrade | Reads idle; recover with `set spec/plan/stage`, `set task 0/<N>` and `check --rebuild` (documented) | `test_state_new_story_seeds_idle` |
    | Finished story whose main pointer was overwritten before the upgrade (no adopt possible, no `handed` line) | Invisible to `stories`; review from P asks the user (AC34). Recover as the row above (documented in the PR and PROGRESS; f2-M16) | `test_state_worktree_candidates_from_main` (the none case) |
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
46. `docs/game-dev/PROGRESS.md` gains one entry for #42. The PR and that entry carry the recovery text for a clobbered or invisible finished story (AC43's last two migration rows; f2-M16). The PR names the case nothing can prevent: a pre-#42 `studio-state` run by path from a stale dev worktree (the 2026-10-05 trigger was the #39 worktree's bin) still writes the main pointer. Such worktrees pick up the new resolution when rebased.

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
| STATE.md `## Ledger` | the pointer's own | per pointer; main keeps its whole ledger, and a move copies only its `handed` line to the target (D1) | idle notes, `abandoned`, `handing`, `handed`, `restored`, `forced`, `void` |
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
| studio-peers :18, :31 | story files read by `sed` | per-story file | STUDIO_STORY only; its `root` call never heals or writes (AC14; f2-M3) |
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
| omega `handoff` SKILL :34-41, :83 (not the verb) | `show`, `get` (read only) | this checkout's real story; idle when pointer-less; runs with `STUDIO_STATE_NO_ADOPT=1` | falsifier M8; AC19 (f2-M11) |
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
  - `handoff`, `take`, restore, adopt, self-heal with the `handing` intent line, the mutex on every write;
  - `stories` and `worktree`'s candidate rule;
  - the story-switch guard, `--force`, `STUDIO_STATE_FORCE`, `STUDIO_STATE_NO_ADOPT`, exit 4;
  - header and usage.
- `studios/game-dev/bin/studio-overnight`, `studios/game-dev/bin/overnight-channel.sh`, `studios/game-dev/bin/overnight-progress.sh` (AC38).
- `studios/game-dev/hooks/session-start.sh`, `studios/game-dev/hooks/bootstrap.md`.
- Skills: `studio`, `brainstorm`, `plan`, `execute`, `review`, `playtest`, `retro` (`studios/game-dev/skills/*/SKILL.md`); `shared/omega/skills/handoff/SKILL.md` (`STUDIO_STATE_NO_ADOPT=1` on its reads, AC19); `shared/omega/skills/autopilot/SKILL.md` (no text change expected; AC36 is pinned).
- `studios/game-dev/memory/stage-pointer-is-per-checkout.md` (new), `studios/game-dev/memory/MEMORY.md`.
- Tests: `tests/state_test.sh`, `tests/hook_test.sh`, `tests/studio_test.sh`, `tests/overnight_test.sh`, `tests/overnight_progress_test.sh`, `tests/overnight_lanes_test.sh` (one new pin, AC40).
- `docs/game-dev/PROGRESS.md`.

### Decisions

- **H: explicit hand-off, keyed by path, with no fallback.** Ruled by the operator over (a) and over C′ (the draft plus the falsifier's five rules). The bug is a cross-checkout write; H deletes the path instead of policing it. Seven of the falsifier's twelve C/I findings cannot arise, and the remaining ones have bounded fixes (Traceability).
- **Key by checkout path, not branch or story.** It survives a branch rename (KAN renames, renamed agent branches), reuses #39's file, exclude line and R2 code, and `git worktree remove` cleans it up.
- **No ownership guard, no claim, no provenance move.** Only `handoff`, `take` and adopt write two pointers, and all three run one locked function.
- **Execute hands off; a worktree-born or in-place story does not.** (c) runs `handoff` only when §0 ran in the main checkout outside a lane and isolation left the main checkout (f2-I1). `superpowers:using-git-worktrees` skips creation inside a linked worktree (execute :588-590), so a worktree-born story never needs one.
- **`take <spec>` names the spec**, so a take cannot grab a different story the main checkout started in the meantime (risk H-N5).
- **Adopt only at `execute`, or at `idle` with the story's ledger here.** A matching branch alone would move the main checkout's next story into a finished worktree (risk H-N4, fixture-verified).
- **Adopt runs on reads too, except in hooks.** A legacy executing worktree's first call is often `get plan` (execute §0 :16); a read that returned idle would stop the resume. Hooks pass `STUDIO_STATE_NO_ADOPT=1`, so no hook ever writes (risk H-N8).
- **Self-heal keys on a `handing` intent line, never on `handed`** (f2-I2). Step 3 writes `handing`; step 5's single tmp + `mv` turns it into `handed`, and a rollback turns it into `void`. So a completed move, a rolled-back one and a later re-plan of the same spec are all inert, and a crash point is the one state with a `handing` line. When the target already holds the spec, only step 5 runs, so the target's progress is never rewound. The alternative, inferring an interrupted move from "main active and its last `handed` line names main's spec", loops on rollback, misfires on a re-plan and rewinds progress (f2-I2 a-c).
- **Main's ledger stays in main** (D1, revised; f2-I9). While `spec` is set, every `ledger` call goes to the feature ledger, so main's `## Ledger` never holds the story's lines; moving it would carry main's history into a worktree and delete it with that worktree.
- **`stories` includes finished stories**, so review from the main checkout finds a story whose pointer went idle at its finish (falsifier M5, C3).
- **`worktree` from main considers only `execute` and finished stories.** A worktree still in brainstorm or plan has no build to review or resume.
- **Main at `execute` resolves only its own story** (f2-C1). Execute's resume calls `worktree` from P after a stop before (c), with `branch -`. Counting main's own line, or any other checkout's story, as a candidate would print P (then `handoff P` fails) or enter another story's worktree. Today's exit 1 makes (a) isolate again. The cost: review from P while P itself is mid-execute resolves P's story, as it does today.
- **Only the newest `handed` line is offered, and only as a question** (f2-I4). Handed lines are never retired, and review and playtest act on exit 3 unasked. Offering the newest unmerged one at exit 1 keeps restore one answer away without resurrecting abandoned or merged stories.
- **`worktree` from a story worktree never prints another checkout** (f2-M12, a different fix from the falsifier's). When the recorded branch moved to another worktree, that worktree has no pointer for the story, so printing it would make the caller read idle; exit 1 with "switch back" instead.
- **The lock covers every write, local `set` included** (f2-I6). The fixture lost one of two parallel local writes in 40 of 40 trials; locking costs about 1 ms per write and touches no lane. See AC27.
- **Run worktrees are listed as `run`, not skipped** (f2-I7), so the router can say a run is in progress; no resolution counts them.
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
- A git failure while listing worktrees makes `stories` exit 1 with `studio-state: git worktree list failed` (f2-M14) and `worktree` exit 1; `handoff` and `take` refuse (exit 1). Under H nothing fails open into another checkout's pointer.

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
| `test_state_auto_create_race` | Two concurrent first writes in WC both exit 0, both values land in one file (the mutex serialises them; f2-I6), and `info/exclude` has the line once. | 6, 27 |
| `test_state_parallel_local_writes_keep_both` | f2-I6: in WA with a pointer, 20 rounds of a parallel `set spec` and `set plan` pair each keep both values. | 27 |
| `test_state_exclude_newline_repair` | An `info/exclude` without a final newline gets one before the appended line. | 6 |
| `test_state_reset_pointerless_noop` | `reset` and `check --rebuild` in a pointer-less WC print `no story in this checkout`, exit 0 and create nothing. | 7 |
| `test_state_init_local_is_auto_create` | `init --local` output equals auto-create's file; a second call exits 1 with `init --local: .* already exists`; the main-checkout and STUDIO_STORY refusals hold (#39 T2 Minor 2). | 8 |
| `test_state_init_in_linked_worktree` | `init` in WC exits 1 naming `init --local`. | 9 |
| `test_state_tracked_pointer_refused` | A force-added, committed `.studio/STATE.md` on WT's branch: WT reads idle, and its first `set` exits 1 naming `git rm --cached`; `take` and `handoff` into WT do too; under STUDIO_STORY, WT works. | 4, 5 |
| `test_state_story_writes_unchanged` | With STUDIO_STORY set, `set`, `ledger`, `check --rebuild` and `worktree` behave as today; no guard, adopt or self-heal runs. | 5, 23 |
| `test_state_milestone_is_project_wide` | WA's `set milestone alpha` sets main's milestone without creating WA's pointer. WA, P and `STUDIO_STORY=S1` all `get milestone` = alpha; `STUDIO_STORY=S1 set milestone beta` writes main; `show` in WA prints `milestone: beta`; a #39-style local pointer holding `milestone: prototype` reads beta; new story files have no `milestone:` line. | 10, 40, 42 |
| `test_state_milestone_without_main` | With only a local pointer, `get milestone` prints `prototype` and `set milestone` exits 1. | 11 |
| `test_state_handoff_moves_story` | P at `execute` with spec S, plan p, task 0/2, two pointer-ledger lines (`Bug: x`, `abandoned T`). `handoff WE` gives WE S/p/0/2 with `branch feat/e` and only the `handed` line; P idle with `branch -`, milestone kept, both earlier lines kept, and the move's line reading `handed`, with no `handing` line left (f2-I9). With WE holding an idle pointer with a `Bug: y` line, that line is kept before `handed` (f2-M7). | 12 |
| `test_state_handoff_order_and_self_heal` | A test hook stops `handoff` after step 3, then after step 4. The next P `get stage` completes it each time (WE holds S, P idle, one `handed` line, no `handing` line). After step 4, WE first runs `set task 2/3`; the heal keeps `2/3` and adds no ledger line (f2-I2c). With WE removed after step 3, it rolls back once: one `void` line with `reason=worktree gone`, and a second P command adds nothing (f2-I2a). A re-run of `handoff WE` after step 3 completes it with no second `handing` or `handed` line (f2-M13). Under `STUDIO_STATE_NO_ADOPT=1`, nothing changes. | 13, 14, 19 |
| `test_state_self_heal_ignores_completed_handoff` | f2-I2b: S handed to WE, WE abandoned and removed, P re-plans S, and `git worktree add` re-makes WE on the same path: P's next commands change nothing and `handoff WE` then succeeds. A `handed` line naming main's current spec changes nothing ("otherwise does nothing", f2-M13). | 14 |
| `test_state_self_heal_scope` | f2-M3: with a pending `handing` line, `root`, `root --work` and a usage error leave every pointer byte-identical; `get stage` then heals. | 14 |
| `test_state_move_record_parse` | f2-M2: spec `docs/a b to (c).md` and a worktree path with a space are handed off, listed by `stories`, offered by `worktree` and restored by `take` intact; a spec holding a TAB makes `handoff` exit 1. | 12, 15, 17 |
| `test_state_handoff_refusals` | Exit 1 under STUDIO_STORY, to P itself, to a non-worktree path, from an idle P, and to a detached-HEAD worktree (f2-M8). Exit 4 onto WA holding A, naming A, and onto WF holding a finished story (f2-M7); with `--force` it moves and writes a `forced` line. | 15, 25 |
| `test_state_take_main_planned_story` | P at `plan` with S (branch `-`). WX's `take S` moves it as `handoff` does; then WX's `set stage execute` writes WX only. | 16, 43 |
| `test_state_take_refusals` | `take T` while P holds S exits 4 (not overridable with `--force`); `take S` in P exits 1; `take S` while P is at `execute` with `branch feat/e` live in WE exits 4 naming WE. `take S` in WA holding A exits 4 (AC15), and `take --force S` moves it with a `forced` line (f2-M13). `take S` in a checkout already holding S exits 0, prints `already in this checkout` and writes nothing (f2-M7). | 16, 25 |
| `test_state_write_after_take_refused` | f2-I3: P at `plan` with S; WX runs `take S`. In P, `set stage plan`, `set plan p`, `set task 0/3` and `set stage execute` exit 4 naming S and WX, writing nothing; `set task -` exits 0; `set --force plan p` writes with a `forced` line; `set stage brainstorm` then `set spec T` start a new story. A pointer with `spec -` and no `handed` line accepts all four writes. | 24, 25 |
| `test_state_take_restores_removed_worktree` | After hand-off of S to WE, two `T<n> complete` lines, and `git worktree remove WE`: `worktree` from P exits 1 with one `removed` candidate carrying the re-add-and-take command; running it gives WE `execute`, S, p, `branch feat/e`, `task 2/3` and a `restored` line; P is unchanged. With a `shipped` line, the restored stage is `idle`. | 17, 22 |
| `test_state_take_restores_renamed_branch` | f2-M1: after the hand-off, `git branch -m feat/e KAN-1-e` and removing WE, `git worktree add WE2 KAN-1-e` then `take S` there restores S with `branch KAN-1-e`. In an unrelated worktree without S's ledger, `take S` exits 4. | 17 |
| `test_state_worktree_no_resurrect` | f2-I4: S handed to WE, abandoned there (`reset`), WE removed: `worktree` from P never exits 3. Once T is handed to WF, S is no longer offered (only the newest line). With T's branch merged into `main` and WF removed, nothing is offered: exit 1 `no feature branch recorded`. | 22 |
| `test_state_adopt_legacy_execute` | Pre-#42 state: P at `execute`, `branch feat/e`. WE's first `get plan` prints p; WE holds S; P is idle with a `handed` line carrying `via=adopt`. | 18, 43 |
| `test_state_adopt_legacy_finished` | P `idle`, spec S, `branch feat/e`, S's ledger in WE: WE's first call adopts. Without the ledger in WE, no adopt. | 18, 43 |
| `test_state_adopt_skips_next_story` | P at `brainstorm` (and then `plan`) with spec T and stale `branch feat/e`, WE on feat/e: WE's `get stage` is `idle`; P is byte-identical. | 18, 43 |
| `test_state_take_hint_under_stale_branch` | f2-I8: P at `plan` with spec A (written from WA) and stale `branch feat/e` live in WE: WA's `show` ends with the take hint, worded "if no session is working on it in <P>"; `take A` in WA moves it; WE does not adopt. With P at `execute` and `feat/e` live in WE, WA gets no hint. | 16, 18, 28, 43 |
| `test_state_stories_lists_live_pointers` | `stories` from P and from WA lists P's in-place story, WA (`active`) and WE (`finished`) with path, git branch, stage, spec, task and state; skips pointer-less, idle-unfinished, prunable and removed worktrees; prints nothing and exits 0 when none. With `git` failing (a `PATH` stub), it exits 1 naming `git worktree list` (f2-M14). | 20 |
| `test_state_stories_marks_run_worktrees` | f2-I7: an `init --local` run worktree with `.studio/run` at `plan` is listed with state `run`; `worktree` from P does not count it; with it as the only non-idle pointer, `worktree` from P exits 1. | 20, 22 |
| `test_state_stories_branch_rename` | After `git branch -m feat/e KAN-1-e` in WE, `stories` shows the new name and `worktree` from WE still prints WE. | 20, 21 |
| `test_state_worktree_from_local_pointer` | In WE with `branch feat/e`, `worktree` prints WE; with `branch -`, it exits 1. After WE switches to `feat/z` and WG checks out `feat/e`, it exits 1 naming WG and never prints WG (f2-M12). | 21 |
| `test_state_worktree_candidates_from_main` | One finished WE: prints WE. WE finished plus WF at `execute`: exit 1, stderr lists both. WA at `plan` only: not a candidate. P `idle`, `spec -`, `branch feat/f` live in WF: WF is a candidate (f2-I5). No candidate and no `handed` line: exit 1 `no feature branch recorded` (f2-M16). | 22 |
| `test_state_worktree_main_execute_no_branch` | f2-C1: P at `execute` with spec S and `branch -`, a finished WF on disk: `worktree` from P exits 1 with `no feature branch recorded` and never prints P or WF. With `branch feat/s` live in WS, it prints WS; with P on `feat/s` itself (in place), it prints P. | 22, 33 |
| `test_state_worktree_legacy_main_branch` | P `idle`, spec S, `branch feat/e`, no adopt yet: `worktree` from P prints WE; with WE removed, exit 3 as today. | 22, 43 |
| `test_state_review_from_main_finds_worktree_born_story` | Falsifier C3: WA's worktree-born story finishes; P holds a finished legacy `branch feat/e` with WE on disk; `worktree` from P lists both and exits 1; never prints WE alone. | 20, 22 |
| `test_state_story_switch_guard` | At `plan` with spec A, `set spec B` and `set stage brainstorm` exit 4 with the exact message, writing nothing; `set spec A` exits 0. At `brainstorm`, `set spec B` exits 0 with a warning naming A. Holds in P and in WA. | 24 |
| `test_state_story_switch_exempt_in_run_worktree` | With `<work root>/.studio/run` present, `set stage brainstorm` at `plan` and `set spec B` exit 0. | 24 |
| `test_state_force_override` | `set --force spec B` and `STUDIO_STATE_FORCE=1 set stage brainstorm` exit 0 with one `forced` line each; a forced write that needed no override writes none; `--force` in another position is a usage error. | 25 |
| `test_state_exit_codes_documented` | The usage text and header name exit 4. | 26, 37 |
| `test_state_mutex_serialises_moves` | A held `state.mutex` (live pid) makes `handoff` exit 1 after the timeout naming the pid; a dead pid's link is reaped and the move succeeds. | 27 |
| `test_state_every_write_holds_mutex` | f2-I6, f2-M13: while the mutex is held by a live pid, P's `set`, WA's `set` and `ledger`, and WA's `set milestone` all wait and then exit 1 naming the pid; `STUDIO_STORY=S1 set task 1/2` does not wait; `get` and `show` do not wait. | 10, 27 |
| `test_state_mutex_single_acquisition` | f2-M4, f2-M5: with a pending `handing` line, `handoff` heals and moves in under 2 s (no self-wait); a holder killed with `-9` leaves a link that the next write reaps; `info/exclude` holds `.studio/state.mutex` once, and `git status --porcelain` stays empty while a dangling link exists. | 27 |
| `test_state_agent_worktree_isolated` | `.claude/worktrees/agent-abc` reads idle with P at `execute`; its write leaves P and WA unchanged; after `git worktree remove` (no `--force`) the file is gone and `stories` drops it. | 41 |
| `test_state_legacy_pointer_resolves` | A main pointer without `branch:` and a #39 local pointer both resolve and accept writes. | 42 |
| `test_state_round_trip_two_stories` | Milestone gate step 2. | 6, 12, 13, 20, 22, 24 |

AC44-AC46 (memory note, PR and PROGRESS text) have no shell test: the final whole-branch review checks them. `test_state_handoff_order_and_self_heal` stops the move through a test-only environment seam that the plan names.

### Other suites

- `hook_test.sh`:
  - `test_session_start_stage_per_checkout`: P idle and WA at `plan` print their own stages; a pointer-less worktree prints `stage idle`;
  - `test_session_start_take_hint`: P at `plan` with S, a pointer-less WC holding S's file: the line ends with the take hint, including "if no session is working on it in"; an `agent-*` worktree gets none; with P also recording a stale `branch feat/e` live in WE, WC still gets it (f2-I8);
  - `test_session_start_never_writes`: in an adoptable worktree and with an interrupted hand-off, the hook leaves every pointer byte-identical. (AC19, AC28.)
- `studio_test.sh`: update the literal pins on the skill text changed by AC29-AC36 (#39 branch :259-260, :275, :305-310, :331, :364). New named pins:
  - `test_skill_bootstrap_stage_line` (AC29);
  - `test_skill_router_lists_stories` (AC30);
  - `test_skill_brainstorm_tests_pointer_not_file` (AC31);
  - `test_skill_plan_take_hint` (AC32);
  - `test_skill_execute_handoff_at_isolation` (AC33; pins the "top level is not the main checkout" condition, the in-place `set branch` and "any non-zero exit"; f2-I1, f2-M15), `test_skill_execute_resume_via_stories` (AC33; pins that a `run` line never counts; f2-I7);
  - `test_skill_router_run_lines_and_adopt_note` (AC30; f2-I7, f2-M11);
  - `test_skill_brainstorm_revise_same_story` (AC31; the revise question and `set --force stage brainstorm`; f2-M9);
  - `test_skill_omega_handoff_no_adopt` (AC19; `STUDIO_STATE_NO_ADOPT=1` on its `studio-state` reads; f2-M11);
  - `test_skill_review_playtest_ask_candidates` (AC34; pins the `removed` candidate's "run its command" only after the user picks it; f2-I4);
  - `test_skill_retro_resolves_story` (AC35; pins the `removed` candidate's `git show` and the adopt rewording; f2-I4, f2-M11);
  - `test_skill_autopilot_no_force` (AC36).
- `overnight_test.sh`:
  - `test_single_plan_follows_story_after_unit_1`: unit 1 hands off; unit 2's cwd is the story worktree, and the run ends `done` (AC38);
  - `test_single_plan_resume_line_names_story_worktree` (AC38);
  - `test_single_plan_ambiguous_story_stops` (AC38);
  - `test_single_plan_preflight_names_story` (AC38);
  - `test_single_plan_from_story_worktree`: the main pointer stays byte-identical (AC39);
  - `test_channel_ledger_follows_story` (AC38);
  - `test_single_plan_rerun_after_stop_before_handoff` (f2-C1): unit 1 stops between `set stage execute` and (c) (the stub's new `stopbeforec` action), then a re-run's unit 1 finds `worktree` exit 1, isolates, hands off, and unit 2 runs in the story worktree (AC22, AC33, AC38);
  - `test_single_plan_in_place_keeps_main_pointer` (f2-I1): the stub's new `inplace` action runs (c) with no new worktree; no `handoff` runs, the main pointer records P's branch, and unit 2 starts in P (AC33, AC38);
  - `test_single_plan_story_not_found_stops` and `test_status_reads_persisted_spec` (f2-M6): with the story's worktree removed, the runner stops `story <spec> not found`; `studio-overnight status` from another shell reads the task through the persisted spec, and prints `story <spec> not found` when it does not resolve (AC38).
- `overnight_progress_test.sh`: `test_progress_task_follows_story` (AC38). Its fixtures at `spec: -` (:135-193) resolve to START_DIR (AC38) and keep their asserts.
- `overnight_lanes_test.sh`: `test_lanes_final_unit_stop_pointer_invisible` (f2-M13): a `Stop:` line written in FINAL_W auto-creates an excluded pointer, the lanes :1427 `git status --porcelain` check stays empty, and `git clean -fdq` keeps the file (AC40).
- `overnight_lanes_test.sh`, `studio_adopt_test.sh`, `overnight_runs_test.sh`, `overnight_sessions_test.sh`, `studio_peers_test.sh`, `studio_brief_test.sh`, `studio_setup_test.sh` (it adds a linked worktree at :50): run unchanged as regressions (AC5, AC40). The draft's `test_lanes_unit_milestone_reaches_project` is dropped (Decisions, D4).

### Existing tests that change

- `test_state_resolves_to_main_checkout` (:171): the `root` asserts stay. "The main checkout's STATE.md carries the change" and "the worktree holds no copy" invert: a worktree write creates its own pointer and the main pointer is unchanged.
- `test_state_ledger_per_branch` (:276): the last assert, "the pointer is shared", inverts (AC6).
- `test_state_local_pointer_only_when_present` (:638): the first assert inverts (auto-create). It is renamed `test_state_local_pointer_auto_created`.
- `test_state_worktree` (:419; f2-I5): its fixture is `init_repo`, main `idle`, `spec -`, so every main-checkout assert holds through AC22's main-at-`idle` recorded-branch rule, resolved as today: "exits 1 when branch is -", "branch nope no longer exists", "exits 0 from the main checkout", "exits 3 when no worktree has the branch" and its three stderr asserts, "after the printed command", the prunable, prune-and-add, locked and unlock-prune-add asserts. Two asserts change: "worktree exits 0 from inside the worktree" and "the same path from inside the worktree" become exit 1 with `no feature branch recorded`, because wt-f is pointer-less (AC3). AC21's from-inside path is tested by `test_state_worktree_from_local_pointer`.
- `test_state_worktree_edges` (:483-510; f2-I5): every assert holds through the same rule, including "a branch checked out in the main checkout is found" (main `idle` records `feat/p`, which P has checked out, so P is the one candidate) and the path-with-a-space case. Listed because it now depends on that rule.
- `test_state_init_local_creates_pointer` (:621): the created file has no `milestone:` line (AC8, AC10).
- `test_retro_contract` (`studio_test.sh` :375-388; f2-M13): the pin `At exit 1, use the current checkout's feature ledger` is rewritten to AC35's exit-1 text, and `assert_not_contains 'AskUserQuestion'` is replaced by a pin on "the only question retro asks"; the other literals stay.
- **The `overnight_test.sh` stub** (falsifier I6). Its `branch` action (:50-52) becomes real execute's sequence: `git worktree add`, then `studio-state handoff <wt>`; the same scenario line's later `stage`, `task` and `ledger` actions run in that worktree, and later units start there through the follow. A new `legacybranch` action keeps today's `set branch` from P for the migration tests. Affected scenarios: :574, :666 (`ISO1`, reused by several tests), :1643, :1656, :1668, :1677, :1691, :1710, :1767, plus their later units' `task n/N` lines. :1565 (`sls`) and :1570 (`sls3`) test start-checkout Stop semantics (`STOP_SRC=start`), so they switch to `legacybranch` and keep their asserts (f2-M13). Two new actions, `stopbeforec` and `inplace`, serve the f2-C1 and f2-I1 tests. :492 and :508 assert unit 1's cwd only, so they hold.

## Risks

- **The runner follow touches #39's T12/T13 files** (studio-overnight, overnight-channel.sh, overnight-progress.sh). Moot when #42 is built after #39 merges, as planned. Without the follow, a single-plan run from P stops after unit 1 with `stop: unexpected stage idle` (:1189): loud, with no corruption.
- **A stale tool bypasses everything.** A pre-#42 `studio-state` run by path from an un-rebased worktree still writes the main pointer (AC46).
- **One mutex for every write** (f2-I6). A hung holder (a `studio-state` process stopped with SIGSTOP) makes every non-STUDIO_STORY write in the project wait about 10 s and then exit 1 naming its pid; a dead holder is reaped. Holders run for milliseconds, and lanes never take it.
- **Main at `execute` hides other stories from `worktree`** (f2-C1). Review or playtest from P while P itself is mid-execute (or stopped before (c)) resolves P's story, not a finished worktree story; the skill then asks (AC34). This is today's behaviour.
- **The take hint can show while another session in P is planning the story** (f2-I3). The hint says so, and AC24's story-less-write refusal stops that session's next write loudly, so the split is caught at once instead of producing a duplicate run.
- **Finished stories stay listed** while their worktree stays on disk, so review from P may ask between several. That is the cost of finding them at all (Open item 2).
- **More explicit steps.** Continuing a main story from a hand-made worktree takes one `take`; a session restarted in P mid-execute sees idle unless the router and execute §0 read `stories` (AC30, AC33). Both fail loudly, and the skill text is pinned.

## Not doing

- Story-keyed pointer files (design (b)), the draft's claim rule, its ownership guard and its provenance move (design (a) and C′).
- Any read fallback from a pointer-less worktree to the main pointer.
- A `studio-state pointer` verb.
- A separate per-checkout mutex: one project-wide `state.mutex` serialises every write, so `handoff`, which writes two pointers, needs no lock ordering (AC27).
- An idle carve-out for a second `init --local` (Decisions).
- Moving any of main's `## Ledger` lines out of the main pointer (Deviation D1, revised).
- Keeping a pointer-less checkout's ledger lines anywhere but its own STATE.md (risk H-N7). The router's bug route (studio :90) or a subagent writing `ledger` in a fresh worktree now auto-creates that worktree's pointer, and the line dies with the worktree. Today it is misfiled into the main story's ledger instead; the bug fix's commit remains the record.
- Rebuilding a worktree-born story's `spec` and `plan` from its committed ledger after its worktree is re-made (a possible follow-up).
- Ageing finished stories out of `stories` by merge status. Only AC22's `removed` offer of a `handed` line checks merge status (f2-I4).
- The stall watchdog (#43) and the sdd-script helper (#41).
- Editing #39's spec, or the per-machine phoenix memory note.

## Deviations to rule on

- **D1 (revised by f2) — main's `## Ledger` stays in the main pointer; a move copies only its `handed` line to the target.** (Load-bearing.) The ruling moves "main's story" to the worktree. The story is the header (`stage`, `spec`, `plan`, `task`, `branch`); its ledger lines are already in the feature ledger, because every `ledger` call goes there while `spec` is set (`studio-state:168-172`). Main's `## Ledger` holds only idle-time notes (the router's `Bug:` route, studio :90), `abandoned`, `forced`, `void` and move records. The first draft of D1 moved all but the `handed` lines; f2-I9 showed that carries main's history into one worktree and deletes it with that worktree, while nothing reads it there. AC17's restore and AC22's offer read main's `handed` lines, so they must stay too. Rule: accept, or move everything and drop restore for all but the newest story.

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
| H-N2 a partial take duplicates a story | AC13, AC14 (`handing` intent line); `test_state_handoff_order_and_self_heal` |
| H-N3 a removed worktree loses a handed story | AC12 (`handed` line), AC17, AC22; D1 |
| H-N4 adopt by branch steals main's next story | AC18; `test_state_adopt_skips_next_story` |
| H-N5 `take` races the main checkout's next story | AC16 (`take <spec>`, mismatch exit 4) |
| H-N6 interactive friction | AC28, AC30, AC32, AC33; Risks |
| H-N7 ledger lines in a pointer-less checkout die with it | Not doing (accepted, with reason) |
| H-N8 a hook moves state | AC19 |
| Draft D1-D5 | Decisions ("Supersedes the draft's D1-D5") |
| f2-C1 a resume after a stop before (c) prints P, and `handoff P` stops execute | AC22 (main at `execute` resolves only its own story, as today), AC33; Decisions; `test_state_worktree_main_execute_no_branch`, `test_single_plan_rerun_after_stop_before_handoff` |
| f2-I1 (c) breaks in-place execution | AC33 (hand off only when the top level is not the main checkout), Decisions; `test_skill_execute_handoff_at_isolation`, `test_single_plan_in_place_keeps_main_pointer` |
| f2-I2 self-heal cannot tell a completed hand-off from an interrupted one | Terms (move records), AC13, AC14 (`handing` intent, step 5 only when the target holds the spec), Decisions; `test_state_handoff_order_and_self_heal`, `test_state_self_heal_ignores_completed_handoff` |
| f2-I3 `take` splits a live main-checkout session | AC24 (story-less writes after a move exit 4), AC28 hint wording, Risks; `test_state_write_after_take_refused` |
| f2-I4 the handed-line exit 3 is permanent and auto-followed | AC22 (newest line only, unmerged, exit 1 `removed` candidate), AC34, AC35, Decisions; `test_state_worktree_no_resurrect`, `test_state_take_restores_removed_worktree` |
| f2-I5 `test_state_worktree` and `_edges` break | AC22 (main-at-`idle` recorded-branch candidate); Existing tests that change lists both and each changed assert |
| f2-I6 local writes unlocked; AC6's race test contradicts the design | AC6, AC27 (every write locked), Decisions, Risks, Not doing; `test_state_auto_create_race`, `test_state_parallel_local_writes_keep_both`, `test_state_every_write_holds_mutex` |
| f2-I7 `stories` lists run worktrees as active | Terms, AC20 (`run` state), AC22, AC30, AC33, AC38; `test_state_stories_marks_run_worktrees` |
| f2-I8 no take hint under a stale `branch` | AC28 (suppressed only at main `execute` with a live branch), AC43 row; `test_state_take_hint_under_stale_branch`, `test_session_start_take_hint` |
| f2-I9 D1 moves main's history into a worktree | AC12, Deviation D1 (revised), Decisions; `test_state_handoff_moves_story` |
| f2-M1 restore not rename-proof | AC17 (renamed branch with the slug ledger here); `test_state_take_restores_renamed_branch` |
| f2-M2 `handed` line not parse-safe | Terms (TAB-separated `key=value`, `path=` last), AC15 (TAB refused); `test_state_move_record_parse` |
| f2-M3 self-heal on `root` lets hooks write | AC14 (pointer-resolving verbs plus `handoff`/`take`/`stories` only), inventory row; `test_state_self_heal_scope` |
| f2-M4 mutex re-entry waits on itself | AC27 (one acquisition per invocation, trap release); `test_state_mutex_single_acquisition` |
| f2-M5 `state.mutex` not excluded; needs `<root>/.studio` | AC27 (exclude line; no-`.studio` cases); `test_state_mutex_single_acquisition` |
| f2-M6 `story_dir()` outside the runner's process | AC38 (persisted spec read from the record; not-found stop; START_DIR fallback); `test_single_plan_story_not_found_stops`, `test_status_reads_persisted_spec` |
| f2-M7 moves over a finished target; target ledger lost; repeated `take` | AC12 (target's lines kept), AC15 (finished target exit 4), AC16 (no-op); `test_state_handoff_moves_story`, `test_state_handoff_refusals`, `test_state_take_refusals` |
| f2-M8 detached-HEAD target | AC15 (exit 1); `test_state_handoff_refusals` |
| f2-M9 the guard blocks re-brainstorming the same story | AC31 (revise question, then `set --force stage brainstorm` with the user's consent); `test_skill_brainstorm_revise_same_story` |
| f2-M10 AC18's "never again" claim is false | AC18 reworded (in-place stories; benign) |
| f2-M11 read-only contracts meet adopt-on-read | AC19 (omega `handoff` SKILL passes `STUDIO_STATE_NO_ADOPT=1`), AC30 and AC35 reworded (router and retro need the real story); `test_skill_omega_handoff_no_adopt`, `test_skill_router_run_lines_and_adopt_note`, `test_skill_retro_resolves_story` |
| f2-M12 AC21 can print the wrong worktree | AC21 (exit 1 naming the other worktree; a different fix from the report's, Decisions); `test_state_worktree_from_local_pointer` |
| f2-M13 test gaps | `test_state_handoff_order_and_self_heal`, `test_state_self_heal_ignores_completed_handoff`, `test_state_take_refusals` (`take --force`), `test_state_every_write_holds_mutex` (`set milestone`), `test_lanes_final_unit_stop_pointer_invisible`; :1565/:1570 move to `legacybranch`; retro pins listed |
| f2-M14 `stories` on a git failure looks like "none" | AC20 (exit 1), AC33, Failure handling; `test_state_stories_lists_live_pointers` |
| f2-M15 (c) stops only on exit 1 or 4 | AC33 (any non-zero exit); `test_skill_execute_handoff_at_isolation` |
| f2-M16 migration gap: a clobbered finished story is invisible | Failure and recovery, AC43 row, AC46 (PR and PROGRESS recovery text); `test_state_worktree_candidates_from_main` |

## Open / UNVERIFIED

1. **`/clear` re-runs SessionStart in the EnterWorktree directory** (proposal falsify item 10). UNVERIFIED on the harness. It rests on execute :568-575 and `hooks.json` :5 (`startup|clear|compact`). AC28's per-checkout line depends on it. Milestone gate step 3 observes it.
2. **Finished stories in `stories`.** A finished story stays listed until its worktree is removed or its pointer starts a new story. If review from P asks too often, a follow-up can drop stories whose branch is merged into the default branch.
3. **The size estimates** (about 300-350 lines in studio-state after the f2 fold, about 35 in the runner, about 55 new tests and pins) come from reading, not from a build.
4. **The phoenix migration state** is inferred, not read: the comparison's fixture reproduces the stale-branch state, and gate step 3's first bullet records the real one before the reinstall.

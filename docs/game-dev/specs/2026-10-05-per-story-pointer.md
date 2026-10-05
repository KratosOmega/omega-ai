# A stage pointer per story — Spec

Date: 2026-10-05
Status: Draft
Milestone: Plan 3 — Content (studio tooling; follows concurrent runs, #39)
Classification: architectural
Base: origin/main once #39 has merged. Line numbers below are on branch `worktree-issue-39-concurrent-runs` at 0286a47. For every file cited they match eab3306, where the design proposal was read, except `overnight-lanes.sh`. The plan sets its own file and line targets after #39 merges.

Issue: #42. Design (a), a pointer per checkout, plus the claim rule, as ruled by the operator on 2026-10-05.

Today, a linked worktree without a local `.studio/STATE.md` reads and writes the main checkout's STATE.md. #39 only made that file local for run worktrees, through `init --local`. Two stories worked in two worktrees therefore share one `stage`, `spec`, `plan`, `task` and `branch`. Whichever story writes last wins: the other story's router, SessionStart line, `check` and stage skills then act on the wrong spec. This happened on phoenix on 2026-09-19, when KAN-1296's review pointer was overwritten by another story. It happened again on 2026-10-05: a `set stage plan` from a linked phoenix worktree landed in the main checkout's STATE.md. The workaround was a per-machine memory note that says "run the stage by path; the pointer is shared".

This spec gives every checkout its own stage pointer, created on the checkout's first write. Three things are kept:
- the documented single-story chain (plan in the main checkout, execute in a worktree, review and playtest from the main checkout), through a claim of the main pointer;
- one project-wide `milestone`;
- every #39 run and lane mechanism.

A guard refuses, with exit 4, a write that would overwrite another live story's pointer.

## Milestone gate

1. `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh` are green. The existing suites keep every assertion, except the ones this spec inverts (Test strategy, "Existing tests that change"). The plan lists each rewritten assertion.
2. A fixture round trip, as `test_state_round_trip_two_stories` in `tests/state_test.sh`:
   - main checkout P plans story S;
   - S's execute isolates into WE and claims;
   - meanwhile, worktree WA brainstorms and plans story A;
   - S runs `task 1/2`, `task 2/2`, then finishes (`stage idle`) from WE;
   - from P, `studio-state worktree` prints WE;
   - P starts story T (`set stage brainstorm`, `set spec`) with WE still on disk;
   - throughout, WA's pointer never changes because of S or T, and P's pointer never changes because of A.

   This step depends on the ruling on D1.
3. Live, on phoenix (the operator runs the steps that need their machine), after the reinstall and with no overnight run live:
   - two `claude-gd` sessions, each in its own EnterWorktree story worktree, brainstorm and plan two stories at the same time. Each session's `studio-state show` names its own spec, and the main checkout's STATE.md is unchanged;
   - one main-checkout story runs execute → finish, then `/game-dev:review` from the main checkout. Review enters the feature worktree through `studio-state worktree`, as before;
   - the operator then deletes the phoenix memory note (AC37).

## Purpose

- Two stories in two checkouts never overwrite each other's stage pointer.
- The single-story chain behaves as it does today: main checkout → execute worktree → back to the main checkout for review, playtest and retro.
- A collision that does happen is refused loudly and names the owner, never silently written.
- Remove the "run by path because the pointer is shared" workaround.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

- Changed: every `studio-state` write. Its pointer is now this checkout's.
- Added: `studio-state stories`, which lists the stories in flight.
- Added: `studio-state pointer`, which names which pointer this checkout resolves to (see D5).
- Added: `--force` on `set` and `reset`, and the `STUDIO_STATE_FORCE=1` override.
- Added: exit code 4 (refused: another story owns the pointer, or a story switch).
- Changed: `/game-dev:studio` in the main checkout also lists the stories in flight.

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

- A refused write changes nothing and exits 4. Its stderr names the owner and the three ways out: continue in the owner's checkout, start this story in its own worktree, or `--force`.
- A worktree whose state was already clobbered before the upgrade starts idle. Recover it with `set spec`, `set plan`, `set stage` and `check --rebuild` (Migration).
- A worktree that is removed takes its pointer with it. A story whose worktree is re-made (`worktree` exit 3) starts idle and recovers the same way.

## Teaching

- `studio-state`'s usage line and header comment describe R1-R4, the claim, the project-wide milestone, `stories`, `pointer`, `--force` and exit 4.
- The SessionStart line marks a fallback pointer as ` (main checkout's; none here yet)`.
- The exit-4 message is the teaching text. It is quoted in AC15.

## Input and platform

macOS and Linux shells, as today. POSIX `sh`, no new dependencies.

## Feel targets

n/a.

## References

- Design proposal (read-only investigation), 2026-10-05, §§0-7 and its falsify table. Its operator rulings are folded in here.
- #39 spec `docs/game-dev/specs/2026-10-04-concurrent-runs.md` (on the #39 branch): AC1, AC2, AC31, and the rejected alternative at L313-316.
- `studios/game-dev/bin/studio-state` (#39 branch):
  - roots: :40-48;
  - pointer resolution: :54-60;
  - STUDIO_STORY: :61-65;
  - `write_idle_state`: :86-100;
  - `init --local`: :192-203;
  - `.gitignore` write: :231-242;
  - `reset`: :364-381;
  - `worktree`: :382-425.
- `studios/game-dev/skills/execute/SKILL.md`:
  - §0's "Which run this is": :31-55;
  - isolation (a) and (c): :149-174;
  - §7 step 3: :534;
  - step 5: :561-566;
  - step 6: :567-590;
  - lane finish: :629, :633.
- `studios/game-dev/bin/studio-overnight`: :40 `state()`, :533-540 `ledger_of` and `feature_dir`, :986-995 (the unit cwd is `START_DIR`).
- Phoenix memory note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` (2026-09-19).

## Terms

- **Main pointer**: `<root>/.studio/STATE.md`, where `<root>` is `studio-state root`, the main checkout.
- **Local pointer**: `<work root>/.studio/STATE.md` in a linked worktree, where it is untracked.
- **Home checkout** of a pointer: the main checkout for the main pointer, and the worktree for a local one.
- **Current branch**: `git branch --show-current` in the checkout the command runs in. It is empty on a detached HEAD.
- **Live branch**: a branch that some worktree other than the writer's has checked out (`git worktree list --porcelain`), not prunable, with its directory present.

## Acceptance criteria

Resolution (STUDIO_STORY unset)

1. **R1.** In the main checkout, the pointer is the main pointer, as today.
2. **R2.** In a linked worktree that has an untracked `<work root>/.studio/STATE.md`, the pointer is that file. This is #39's rule, unchanged.
3. **Tracked pointer** (#39 T2 review Minor 3). In a linked worktree where `.studio/STATE.md` is tracked (`git ls-files --error-unmatch .studio/STATE.md` succeeds there), that file is never the local pointer. Every command except `root` and `root --work` exits 1 with `studio-state: <path> is tracked by git — a tracked STATE.md is never a stage pointer; run git rm --cached .studio/STATE.md on this branch`. The main checkout's resolution is unchanged.
4. **R3.** In a linked worktree with no local file, when the main pointer's `branch` equals the current branch (neither `-` nor empty), the pointer is the main pointer, for reads and writes. This is the main checkout's story, isolated here by execute. *(D1 proposes narrowing it.)*
5. **R4, the fallback.** In any other linked worktree with no local file:
   - reads (`get`, `show`, `check` without `--rebuild`, `worktree`) use the main pointer, as today;
   - `ledger` also uses the main pointer to find its feature ledger, as today, and never creates a local pointer;
   - the first write (`set`, `reset`, `check --rebuild`) resolves by AC6-AC9, in that order.

   R4 is never used when the main pointer does not exist: then every command keeps today's "no `.studio/`" exit 1.

First write in R4

6. **Move, by provenance.** When main's `branch` is `-`, main's `spec` names a file that exists in this checkout, and that file does not exist in the main checkout's tree, the story was written here:
   - main's header (`stage`, `spec`, `plan`, `task`, `branch`; no `milestone`) is copied into a new local pointer (AC9's file and exclude);
   - the main pointer is reset to idle (`stage idle`, `spec -`, `plan -`, `task -`, `branch -`);
   - `- <date> moved <spec> to <current branch> (<work root>)` is appended to the main pointer's `## Ledger`;
   - the write then applies to the local pointer.
7. **Claim (the execute chain).** When main's `stage` is `plan` or `execute` and main's `branch` is `-`:
   - `set branch -` and `set stage execute` from this checkout write the main pointer;
   - `set branch <current branch>` writes main's `branch`, which is the claim. It appends `- <date> claimed <spec> by <branch> (<work root>)` to the main pointer's `## Ledger`. R3 applies from then on, and no local pointer is created.

   Any other write takes AC9.
8. **Second claim refused.** When main's `stage` is `plan` or `execute` and main's `branch` names a different live branch, `set branch <current branch>` exits 4 with AC15's message, naming that branch and its worktree. Nothing is written.
9. **New story.** Any other first write:
   - creates the local pointer from the idle template, without a `milestone:` line;
   - appends `.studio/STATE.md` to `<common git dir>/info/exclude` once (idempotent; a missing final newline is repaired first, as #39 does);
   - then applies the write.

   The main pointer is byte-identical before and after.
10. **`init --local`** is the explicit form of AC9. One shared function creates the pointer for both, so `init --local` writes a file byte-identical to an auto-created one. Its refusals are unchanged:
    - it refuses in the main checkout;
    - it refuses with STUDIO_STORY set;
    - a second `init --local` exits 1 with `init --local: <path> already exists`.
11. **`studio-state pointer`** prints one line, `<kind><TAB><file>`. `<kind>` is one of:
    - `main` (R1);
    - `local` (R2);
    - `claimed` (R3);
    - `fallback` (R4, before the first write);
    - `story` (STUDIO_STORY set).

    It exits 0, and 1 when AC3 refuses. It writes nothing.

Shared and per-story keys

12. **`milestone` is project-wide.**
    - `get milestone` and `set milestone` always read and write the main pointer: from every checkout, and under STUDIO_STORY.
    - Local pointers, and story files created after this change, have no `milestone:` line.
    - `show` prints the header with `milestone: <main's value>` in the milestone position. A `milestone:` line left in an older local pointer or story file is ignored by `get` and replaced in `show`.
    - `set milestone` is exempt from the guard (AC18).
13. **`studio-state stories`** lists the stories in flight, from any checkout. It prints one TSV line per non-idle pointer, `<checkout path>\t<branch>\t<stage>\t<spec>\t<task>`:
    - the main pointer, under the claimant's worktree path when it is claimed (R3), else under the main checkout's path;
    - then each linked worktree's local pointer, in `git worktree list` order.

    It skips worktrees that have no pointer, idle pointers, and prunable or missing worktrees. With none, it prints nothing and exits 0. It never writes. It is a separate verb: `show` is unchanged, because `studio-overnight` :535-537 and `overnight-channel.sh` :189-191 parse `show` from `## Feature ledger:` to EOF.

Clobber guard

14. **Ownership is derived.** There are no new header keys. A pointer whose `stage` is not `idle` is owned by its `branch` when that is not `-`, and otherwise by its home checkout. An idle pointer has no owner. *(D1 proposes: by branch only at `stage execute`.)*
15. **Ownership refusal.** A guarded write is refused when it resolves to a pointer owned by a branch other than the writer's current branch, and that branch is live. The refused writes are `set` (any key except `milestone`), `reset` and `check --rebuild`. Typical cases are a main-checkout write while a worktree claims main's story, and AC8. The command exits 4 with nothing written, and stderr is exactly:

    `studio-state: <pointer path> belongs to story <spec slug> (stage <s>, task <t>, branch <b>, worktree <path>) — continue it there, start this story in its own worktree (EnterWorktree), or pass --force`
16. **No refusal** when:
    - the pointer is idle;
    - the owner is the writer's own current branch;
    - the owning branch is not live (its worktree was removed or no longer holds it);
    - the owner is the home checkout and the writer is in it.
17. **Story-switch guard, same checkout** (two sessions in one checkout, the 2026-09-19 case):
    - `set stage brainstorm` when `stage` is `plan` or `execute` exits 4 and names the current spec;
    - so does `set spec X` when `stage` is `plan` or `execute` and `spec` ≠ X;
    - at `stage brainstorm`, `set spec X` over a different spec exits 0, writes, and prints one stderr warning naming the old spec. Brainstorm §0 already asks the user.

    *(D3: this blocks the manifest planning loop.)*
18. **Exempt:**
    - `root`, `init`, `get`, `show`, `check` without `--rebuild`, `ledger`, `worktree`, `pointer`, `stories`;
    - `set milestone`;
    - the move and claim writes of AC6 and AC7.

    *(D2 adds: a write that leaves the field unchanged.)*
19. **Override.** `--force` (`set --force KEY VALUE`, `reset --force [--keep-ledger]`) or `STUDIO_STATE_FORCE=1` bypasses AC15 and AC17. Each forced write that would otherwise have been refused appends `- <date> forced <key>=<value> over <owner> from <writer branch> (<work root>)` to the written pointer's `## Ledger`, with `reset` as the key for a reset. `--force` is accepted only in these positions; anywhere else it is a usage error, as today.
20. **STUDIO_STORY is not guarded.** Under STUDIO_STORY, resolution and writes are exactly as today, except `milestone` (AC12). Lanes, adopt, peers and progress are unaffected.
21. **Exit codes.** The usage text and the header's `Exit:` line add `4 refused: another story owns this pointer, or a story switch (--force overrides)`. No other path exits 4.

Worktree lifecycle

22. An agent-isolation worktree (`.claude/worktrees/agent-*`) has no special case. Its first write creates an idle local pointer (AC9), and the main pointer and the controller's pointer stay byte-identical. `git worktree remove` removes that worktree without `--force`, because the pointer is git-excluded. `stories` no longer lists it.

Hooks and skills

23. **SessionStart** (`hooks/session-start.sh`) prints the stage of the checkout the session starts in: P idle and WA's local pointer at `plan` print `stage idle` from P and `stage plan` from WA. When `studio-state pointer` reports `fallback`, the line ends with ` (main checkout's; none here yet)`. The comment at :15-17 reads "studio-state resolves this checkout's pointer".
24. `hooks/bootstrap.md` :27 reads: "a line naming this checkout's stage (the main checkout's, marked so, in a worktree that has none yet)".
25. **Studio router** (`studio/SKILL.md` :16):
    - it runs `studio-state show` in the checkout it is in (each story worktree has its own pointer);
    - in the main checkout it also runs `studio-state stories` and lists each story in flight on one line, with the checkout to resume it in.

    Abandon (:66-71, :104-107): on exit 4 it names the owner, and passes `reset --force` only after the user confirms.
26. **Brainstorm §0** (:14-38):
    - when `studio-state pointer` reports `fallback`, it skips the "unapproved spec exists" question, because this checkout starts a new story;
    - on exit 4 from `set stage brainstorm` or `set spec`, it stops, shows the message and suggests EnterWorktree.
27. **Plan** (:12-33, :151-153): exit 4 from a state write stops and shows the message.
28. **Execute:**
    - :53-55 reads: "the claim at isolation (c) keeps a story planned in the main checkout on the main pointer, and a story born in a worktree keeps its own; so every call below works the same from the feature worktree";
    - (c) at :169-174 keeps `set branch "$(git branch --show-current)"`, now the claim, and adds: "exit 4 means another worktree claimed this story — stop and show the message";
    - :534 notes that `set milestone` writes the project's milestone.
29. **Review and playtest** (review :55-62, playtest :50-57) keep the spec-mismatch check. The cause now reads "this checkout's pointer moved on to the next feature". Retro (:20-35) notes that it reads this checkout's pointer. No logic changes.
30. **Autopilot.** :81 keeps `studio-state init --local`, the explicit form. :135 becomes `studio-state set stage plan`, then `studio-state set --force spec <spec>`: the run worktree's pointer walks the manifest rows. *(D3 extends this.)*
31. **studio-state header comment** (:2-9, :31-39, :49-53) describes R1-R4, the claim, the project-wide milestone and exit 4, replacing "one project has one stage".

Overnight

32. **Single-plan from a story worktree.** `studio-overnight start` run from a worktree whose story has its own local pointer passes the preflight on that pointer (:415-427 via `state()`), and the main pointer stays byte-identical. Single-plan runs started from the main checkout behave as today. *(D2: that holds only with the no-op exemption.)*
33. **Lanes** are unchanged (STUDIO_STORY, AC20). A `set milestone` under STUDIO_STORY writes the main pointer.

Migration

34. No file-format change and no new header keys. These all resolve unchanged, and nothing is hand-edited on any machine:
    - existing main pointers;
    - legacy files without `branch:` (`set_branch` :134-147 still inserts it);
    - #39 local pointers, which keep their `milestone:` line, ignored by AC12.
35. **Sessions in flight** at reinstall, each with a test:

    | Session | Behaviour after reinstall | Test |
    |---|---|---|
    | Main checkout, its own story | Unchanged; the guard refuses a different story only while main's story is claimed by a live worktree | `test_state_guard_main_while_claimed` |
    | Worktree executing main's story (main `branch` = its branch, set by today's (c)) | R3, unchanged | `test_state_execute_claim` |
    | Worktree that wrote its brainstorm or plan into the main pointer (the EnterWorktree pattern) | Reads still see main; its first write moves the story (AC6) | `test_state_move_by_provenance` |
    | Worktree whose state was clobbered before the upgrade | Provenance fails; starts idle; recover with `set spec/plan/stage` and `check --rebuild` (documented in the PR and PROGRESS) | `test_state_new_story_seeds_idle` |
    | Live overnight runs | Lanes: STUDIO_STORY, unchanged. Single-plan: main pointer plus R3 (D2) | lanes, overnight suites |

    Install by PR merge, and reinstall only when `studio-overnight status` shows no live run.

Memory and docs

36. A new note `studios/game-dev/memory/stage-pointer-is-per-checkout.md`, in the folder's frontmatter format (`name`, `description`, `metadata.type: feedback`). It says:
    - each checkout has its own stage pointer, and a story planned in the main checkout is claimed by its execute worktree;
    - exit 4 means another story owns the pointer: never `--force` another story's pointer without the user;
    - the SDD ledger (`.superpowers/sdd/<plan>/progress.md`) remains the per-feature recovery record.

    `studios/game-dev/memory/MEMORY.md` gains one index line for it.
37. The PR body and the PROGRESS entry state that the per-machine phoenix note `~/.claude-gamedev/projects/-Users-xinli-GameDev-proj-phoenix/memory/studio-state-is-shared-across-stories.md` (and its `_practice` copies) can be deleted once this lands and is reinstalled. Nothing in the repo edits that file.
38. `docs/game-dev/PROGRESS.md` gains one entry for #42. The PR names the case nothing can guard: a pre-#42 `studio-state` run by path from a stale dev worktree (the 2026-10-05 trigger was the #39 worktree's bin). Such worktrees pick up the guard when rebased.

## What stays shared

Unchanged by this spec: everything keyed on `studio-state root`, which is #39 AC1:
- `.studio/stories/` (STUDIO_STORY files);
- the gate lock (`gate.lock`, `gate.units`, `gate.times`, `gate.mutex`);
- `overnight.lock`, `overnight.stop`, `runs/<slug>/`, `runs.mutex`, `reports/`;
- `sessions/` and `sessions.mutex`;
- the registry `root=`;
- the Multica project identity (`install.sh` :282, `omega-multica-agent` :16-17, bridge `service.py` :161-172).

Newly shared: `milestone` (AC12).

Per checkout, as today: the feature ledger (`<work root>/.studio/ledger/`), `config.json` (the checkout first), `.studio/reports/` test logs, and `.studio/run`.

### Who reads what, and which side

| Item | What it touches | Side | Note |
|---|---|---|---|
| studio-state `get/set/show/check/reset/worktree` | resolved pointer | per story | R1-R4 |
| studio-state `ledger` | `<work root>/.studio/ledger/<slug or id>.md` | per story (travels with the branch) | unchanged |
| studio-state `root` / `root --work` | prints STATE_ROOT / WORK_ROOT | shared / checkout | #39 AC1, unchanged |
| STUDIO_STORY files `<root>/.studio/stories/<id>.md` | lanes, adopt, peers, progress | per-story file in a shared dir | unchanged except milestone |
| `milestone` key | main pointer | shared | AC12 |
| STATE.md `## Ledger` | resolved pointer | per pointer | idle notes, `abandoned`, `moved`, `claimed`, `forced` |
| studio-gate :37-51, :136, :220 | gate files | shared | — |
| studio-setup :53-58, :123-126 | config fallback, gate-lock wait | shared (config: checkout first) | — |
| studio-overnight :399-404, :1229-1238, :1390-1435, :1509, :1530, :1620 | locks, stop flags, reports, runs, registry | shared | — |
| studio-overnight :40 `state()`, :427, :535-540 | pointer of START_DIR (single-plan) | per story | AC32 |
| overnight-lanes.sh `story_state`, unit paths, locks | STUDIO_STORY files, shared run state | per-story file / shared | lines shift after #39's final commits |
| overnight-runs.sh :23-62, overnight-sessions.sh :9-11 | run locks, records, session slots | shared | — |
| overnight-channel.sh :107-142, :327 | live runs, stop flag | shared | — |
| overnight-channel.sh :189-191 | `worktree` / `show` (single-plan) | per story | parses `show` from `## Feature ledger:` |
| overnight-progress.sh :66 | STUDIO_STORY `show` | per story | — |
| studio-adopt :76-79, :348, :433, :586, :669-681, :790 | `stories/`, `runs/<slug>/landed.tsv` | shared dir | — |
| studio-adopt :448, :525, :759, :779-782 | STUDIO_STORY get, ledger, check | per story | — |
| studio-peers :18, :31 | story files read by `sed` | per-story file | STUDIO_STORY only; unaffected |
| studio-brief :69-99 | `get spec/plan`, ledger at WORK | per story | — |
| studio-dispatch :43; godot `test.sh` :60-63, `run.sh` :45-54, `slowest.sh` :20 | config, reports in the cwd checkout | per checkout | test logs are not state |
| hooks/session-start.sh :19-20 | `root --work`, `get stage` | per story (by cwd) | AC23 |
| hooks/guard-state.sh :14 | glob `*/.studio/STATE.md` | covers local pointers | unchanged |
| hooks/operator-inbox.sh, peer-runs.sh | run dir | shared | — |
| hooks/stage-guard.sh, autopilot-guard.sh | nothing in `.studio/` | — | — |
| skills studio, brainstorm, plan, execute, playtest, review, retro | via studio-state | per story | AC25-AC29 |
| autopilot SKILL :75, :81, :121, :135, :143, :150, :155 | `init --local`, STUDIO_STORY seeding, `reset --keep-ledger` | run-worktree pointer / story files | AC30, D3 |
| handoff SKILL :34-41, :83 | `show`, `get` (read only) | per story | — |
| parallel SKILL :106, :129, :150 | bookkeeping in the controller's checkout | per story | — |
| agents/producer.md :36 | ledger file by path | per story | — |
| multica install.sh :282, omega-multica-agent :16-17, bridge service.py :161-172 | `studio-state root`, `<root>/.studio` | shared | — |

### Supersedes #39 AC2's last bullet

#39's spec, AC2 (L129-132), says: "A story worktree never has a local pointer, so its behaviour is unchanged." This spec supersedes that bullet:
- a lane's story worktree still has no local pointer, because it works under STUDIO_STORY (AC20);
- a worktree executing the main checkout's story uses the main pointer by claim (R3);
- every other linked worktree gets its own pointer on its first write (AC9) or by `init --local` (AC10).

The rest of #39 AC2 stands. #39's rejected alternative at L313-316 (story-keyed planning state) also stands: this spec keys by checkout, not by story. #39's spec is not edited; it lives on its own branch and is history once merged.

## Architecture

### Before / after

- Before: one stage pointer per project, plus a local one only in run worktrees after `init --local`. Every other worktree writes the main checkout's STATE.md.
- After:
  - every checkout resolves its own pointer (R1-R4);
  - a story planned in the main checkout stays on the main pointer through its execute worktree (the claim);
  - `milestone` is read and written project-wide;
  - a derived-ownership guard refuses cross-story writes with exit 4;
  - `stories` lists the stories in flight.

### Files

- `studios/game-dev/bin/studio-state`:
  - resolution R1-R4 and AC3;
  - the first-write order (move, claim, new);
  - the shared create function behind `init --local`;
  - `milestone` redirect and `show`'s milestone line;
  - `pointer` and `stories`;
  - the guard, `--force`, `STUDIO_STATE_FORCE`, exit 4;
  - header and usage.
- `studios/game-dev/hooks/session-start.sh`, `studios/game-dev/hooks/bootstrap.md`.
- Skills: `studio`, `brainstorm`, `plan`, `execute`, `review`, `playtest`, `retro` (`studios/game-dev/skills/*/SKILL.md`); `shared/omega/skills/autopilot/SKILL.md`.
- `studios/game-dev/memory/stage-pointer-is-per-checkout.md` (new), `studios/game-dev/memory/MEMORY.md`.
- Tests: `tests/state_test.sh`, `tests/hook_test.sh`, `tests/studio_test.sh`, `tests/overnight_test.sh`; `tests/overnight_lanes_test.sh` (see D4).
- `docs/game-dev/PROGRESS.md`.

### Decisions

- **(a) a pointer per checkout, over (b) keyed files under `.studio/stories/`.** Ruled by the operator.
  - The key is the worktree path, so it survives a branch rename (KAN renames, renamed agent branches).
  - It reuses #39's file, exclude line and R2 code path.
  - `git worktree remove` cleans it up, so nothing is left orphaned.
  - (b) would rename ledgers (`ledger_file` :168-172) and rework a reviewed #39 task, and #39 L313-316 already rejected it.
- **New stories start idle, not seeded from main.** A copy-on-first-set seed breaks the execute chain:
  - main keeps `stage execute`, `branch -`, `task 0/N`;
  - review, playtest and retro from main then get exit 1 from `worktree`;
  - an execute re-run from main isolates again and re-runs a finished plan (execute :149-155).

  A copy also leaks the other story into the new pointer. The operator accepted this deviation from the issue's wording.
- **The claim keeps main's story on the main pointer.** Main's STATE.md is written from the execute worktree of main's own story, and no other story writes it. A forwarding stub (main keeps `branch` only and forwards `get`) behaves the same with more code, so it was rejected.
- **Accepted cost.** While a worktree claims main's story, starting another story from the main checkout is refused without `--force`. The new story starts in its own worktree.
- **`stories` is a verb, not part of `show`**, because two parsers read `show` to EOF.
- **Ownership is derived from existing keys.** No schema change.
- **`ledger` never creates a pointer.** It is exempt and resolves its feature ledger as today, so a ledger line can never be what starts a story.
- **No refusal in agent worktrees.** The proposal's optional `--force` requirement there is not adopted (Not doing).

### Failure handling

- Every refusal is exit 4 with nothing written, and AC15's message.
- Auto-create failures (an unwritable `.studio/` or `info/exclude`) exit 1 with the failing path, as `init --local` does today.
- A git failure while finding live branches treats the owner as not live, so the write is allowed. The guard fails open, never blocking a solo user.

## Tuning knobs

None.

## Assets and audio

n/a.

## Test strategy

Shell suites, using a fixture of main checkout P plus linked worktrees made with `git worktree add`, as `rw_fixture` (`tests/state_test.sh` :610) does.

### New tests, mapped to ACs

| Test | Asserts | ACs |
|---|---|---|
| `test_state_two_worktrees_independent` | WA (feat/a) and WB (feat/b) each run `set stage brainstorm` and `set spec`. Each `get spec` returns its own. Both local files exist, `git status --porcelain` is empty in both, and `info/exclude` holds the line once. | 2, 9 |
| `test_state_worktree_write_leaves_main_untouched` | The main pointer is byte-identical before and after `set`, `ledger` and `reset` in WA, and WA's file shows `stage: brainstorm` (#39 T2 Minor 1's vacuity fix). | 5, 9 |
| `test_state_new_story_seeds_idle` | Main is at `stage plan` with spec S, which exists in P. WC's first `set stage brainstorm` gives a local `spec -`, `plan -`, `task -`, `branch -`, and no milestone line. Main is unchanged. | 9, 12, 35 |
| `test_state_fallback_reads_main` | Before any write, WC's `get stage` equals main's, and `pointer` prints `fallback`. | 5, 11 |
| `test_state_move_by_provenance` | The spec exists only in WD's tree, and main is at `plan` with it and `branch -`. WD's `set plan p` gives a local copy with WD's spec and stage. Main goes idle with a `moved` line. | 6, 35 |
| `test_state_execute_claim` | Main runs `set branch -` and `set stage execute`. Then WE's `set branch feat/e` gives main `branch: feat/e`, no WE file, and a `claimed` line. WE's `set task 1/3` reaches main's `task`. `worktree` from P prints WE, and `pointer` in WE prints `claimed`. | 4, 7, 35 |
| `test_state_claim_refused_for_second_worktree` | After WE claims, WF's `set branch feat/f` exits 4. stderr names feat/e, WE's path and `--force`. Main is unchanged. | 8, 15 |
| `test_state_guard_main_while_claimed` | P's `set stage brainstorm` exits 4, naming the spec slug, stage, branch and path. With `--force` it exits 0 and writes a `forced` ledger line. `STUDIO_STATE_FORCE=1` does the same. | 14, 15, 19 |
| `test_state_guard_allows_idle_owner` | With the owner at `stage idle` (finished), P's `set stage brainstorm` exits 0. | 16 |
| `test_state_guard_owner_not_live` | After `git worktree remove WE`, P's write to main's claimed pointer exits 0. | 16 |
| `test_state_story_switch_guard` | At stage `plan` with spec A, `set spec B` exits 4, and so does `set stage brainstorm`. At stage `brainstorm`, `set spec B` exits 0 with a stderr warning naming A. | 17 |
| `test_state_guard_exempt_verbs` | While claimed, every AC18 verb exits 0 from P. | 18 |
| `test_state_story_writes_unguarded` | With STUDIO_STORY set, a `set` on a story file whose `branch` is live in another worktree exits 0. | 20 |
| `test_state_milestone_is_project_wide` | WA's `set milestone alpha` sets main's milestone. WA, P and `STUDIO_STORY=S1` all `get milestone` = alpha. `show` in WA prints `milestone: alpha`. A #39-style local pointer holding `milestone: prototype` reads alpha. | 12, 33, 34 |
| `test_state_tracked_pointer_refused` | A committed, force-added `.studio/STATE.md` on a worktree's branch is never used as its pointer, and the error names `git rm --cached`. | 3 |
| `test_state_agent_worktree_isolated` | A worktree at `.claude/worktrees/agent-abc` writes. Main's and WA's pointers are unchanged, and after `git worktree remove` (no `--force`) the file is gone. | 22 |
| `test_state_stories_lists_in_flight` | `stories` from P lists WA, WB and the claimed WE (path, branch, stage, spec, task), and skips pointer-less and idle worktrees. With none, it prints nothing and exits 0. | 13 |
| `test_state_removed_worktree_no_orphan` | `git worktree remove WA` succeeds without `--force`, and `stories` drops it. | 13, 22 |
| `test_state_init_local_is_auto_create` | `init --local` output equals auto-create's file. A second `init --local` exits 1 with `init --local: .* already exists` (#39 T2 Minor 2). | 10 |
| `test_state_exit_codes_documented` | The usage text names exit 4. | 21 |
| `test_state_legacy_pointer_resolves` | A main pointer without `branch:` and a #39 local pointer both resolve and accept writes. | 34 |
| `test_state_round_trip_two_stories` | Milestone gate step 2. | 4-9, 14-16 |

### Existing tests that change

- `test_state_resolves_to_main_checkout` (:171): the `root` asserts stay. "The main checkout's STATE.md carries the change" and "the worktree holds no copy" move to a claim-based setup (AC7).
- `test_state_ledger_per_branch` (:276): the last assert, "the pointer is shared", inverts (AC9).
- `test_state_local_pointer_only_when_present` (:638): the first assert inverts (auto-create). It is renamed `test_state_local_pointer_auto_created`.
- `test_state_worktree` (:419): "the same path from inside the worktree" still holds, through R3. It is kept.

### Other suites

- `hook_test.sh`: a new `test_session_start_stage_per_checkout` covers AC23, including the fallback suffix from a pointer-less worktree.
- `studio_test.sh`: update the literal pins on the skill text changed by AC25-AC30 (#39 branch :259-260, :275, :305-310, :331, :364). Add pins for "this checkout's pointer", `studio-state stories` and "exit 4".
- `overnight_test.sh`: a regression run, plus `test_single_plan_from_story_worktree` (AC32). D2 adds `test_single_plan_resume_unit_while_claimed`.
- `overnight_lanes_test.sh`, `studio_adopt_test.sh`, `overnight_runs_test.sh`, `overnight_sessions_test.sh`, `studio_peers_test.sh`: run unchanged as regressions (STUDIO_STORY, AC20). For the proposal's `test_lanes_unit_milestone_reaches_project`, see D4.

## Risks

- **A stale tool bypasses the guard.** A pre-#42 `studio-state` run by path from an un-rebased worktree still writes the main pointer. No guard can catch it, so the PR says so (AC38).
- **A claim race.** Two worktrees claiming in the same instant both pass a check-then-write (`write_field` is tmp plus `mv`, with no lock). It is rare (it needs two executes of one story). See Open item 3.
- **Recreated worktrees start idle.** A worktree-born story whose worktree is re-made loses its spec, plan and stage pointer. `check --rebuild` restores `task`, and the rest comes back by `set`.

## Not doing

- Story-keyed pointer files (design (b)).
- A forwarding stub for a claimed main pointer.
- Refusing writes in agent-isolation worktrees without `--force`.
- Rebuilding `spec` and `plan` from the committed ledger's `plan approved` line after a worktree is re-made (a possible follow-up).
- The stall watchdog (#43) and the sdd-script helper (#41).
- Editing #39's spec, or the per-machine phoenix memory note.

## Deviations to rule on

Each was found by checking the proposal against the #39 branch. The ACs above follow the ruled design. Each amendment is written here, not applied there.

- **D1 — a stale `branch` makes the guard refuse the main checkout's next story.** (Load-bearing.)
  - **Evidence.** Execute §7 step 5 leaves `branch` set after `stage idle` (execute :566: "`branch` keeps the feature branch until the next new run clears it"), and step 6 keeps the worktree on disk for playtest and review (:568). Brainstorm (:61, :261) and plan (:151) never clear `branch`; only execute's new run does (:49). So after story E finishes, P's `set stage brainstorm` passes (idle), but P's next `set spec` meets a non-idle pointer owned (AC14) by `feat/e`, which is live in WE, and exits 4. The same holds for every plan write. The main-checkout chain breaks on its second story.
  - **R3 too.** WE (still on `feat/e`) keeps resolving to the main pointer while it holds the next story, which is today's leak.
  - **Proposed amendment.** In AC14, ownership by `branch` applies only at `stage execute` (the only stage in which a claim is made); at `brainstorm` and `plan` the owner is the home checkout. In AC4, R3 also requires main's `stage` to be `execute` or `idle`.
  - **Test.** Add `test_state_next_story_after_finished_claim`.
- **D2 — the execute resume from the main checkout is refused, and so is every single-plan overnight unit after the first.** (Load-bearing.)
  - **Evidence.** Execute §0 runs `set stage execute` on every run, a resume's included, before it enters the feature checkout (:49-50). A resume started in P therefore writes the claimed main pointer from branch `main` and exits 4. Single-plan units always start in `START_DIR` (studio-overnight :992), so unit 2 onward fails. The proposal's §4 ("single-plan runs use main+R3: no change") does not hold, and its fixture misses it because the overnight stub never runs execute's writes.
  - **Proposed amendment.** Add to AC18: a `set` whose value equals the field's current value is a no-op that writes nothing and exits 0, unguarded. The alternative is changing execute to write `stage execute` only when it differs, but the studio-state rule covers every caller.
  - **Tests.** Add `test_state_noop_write_unguarded` and `test_single_plan_resume_unit_while_claimed`.
- **D3 — the story-switch guard blocks the manifest planning loop.** (Load-bearing.)
  - **Evidence.** A run worktree's pointer walks the manifest's epics. After epic 1's plan (stage `plan`, spec A), `next` prints `/game-dev:brainstorm <slug>/<id2>`, whose `set stage brainstorm` (brainstorm :61) exits 4 by AC17. Autopilot adopt step 5.1 (`set spec <spec>` without STUDIO_STORY, autopilot :121) meets the same refusal. The proposal gives `--force` only to autopilot :135.
  - **Proposed amendment (recommended).** AC17 does not apply when the current branch is `run/*`, the run worktree's planning cursor. This is one rule in studio-state, and it keeps AC15 in force. The alternative is `--force` in brainstorm's and plan's `<slug>/<id>` and manifest `<id>` forms and at autopilot :121, which is three more skill passages and also bypasses AC15.
  - **Test.** Add `test_state_story_switch_exempt_in_run_worktree`.
- **D4 — the lane-milestone premise is wrong.** (Minor; the design is unchanged.) Proposal §0 says execute §7 step 3's `set milestone` under a lane writes the story file. But step 3 is skipped under a lane (execute :629, :633), so no skill writes `milestone` under STUDIO_STORY today. Only the stale read remains, and AC12 still fixes it. Recommendation: cover it in `test_state_milestone_is_project_wide` (done above) and drop the proposed `test_lanes_unit_milestone_reaches_project`.
- **D5 — `studio-state pointer` is new and not in the rulings.** (Minor.) Proposal §5 and §6 use `studio-state pointer` (`fallback`, `claimed`) for tests, brainstorm §0 and the SessionStart suffix, but §1 and the rulings name only `stories`. This spec defines it (AC11). Rule: keep it, or fold its kind into `stories` and an internal hook check.

## Open / UNVERIFIED

1. **Phoenix ignores `.studio/STATE.md`** (proposal falsify item 9). UNVERIFIED: the phoenix repo was not read. Mitigated: auto-create writes `info/exclude` (AC9, fixture-verified in #39), and a tracked pointer is refused (AC3).
2. **`/clear` re-runs SessionStart in the EnterWorktree directory** (falsify item 10). UNVERIFIED on the harness. It rests on execute :567-575 and `hooks.json` :5 (`startup|clear|compact`). AC23's per-checkout line depends on it. Milestone gate step 3 observes it.
3. **The claim race** (Risks). Is a short `mkdir` mutex at `<root>/.studio/state.mutex` around move and claim worth it? Recommendation: not in this story, because two executes of one story in the same second is not a real workflow.
4. **The `stories` scope.** This spec lists non-idle pointers only. A finished story waiting for review (idle, worktree on disk) is not listed, so the router finds it through main's `branch` as today. Confirm that this is wanted.
5. **Ledger lines from a fallback worktree** (AC5). A `studio-state ledger` in a pointer-less worktree, such as the router's `Bug:` line in a bug-fix worktree (studio :90), still names its file after the main pointer's spec, as today. Should it start a pointer instead? This spec keeps today's behaviour.

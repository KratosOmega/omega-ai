---
name: execute
description: Use when an approved plan exists — dispatches a fresh role agent per task with a reviewer after each, a standalone final review, then the gate, a play list and a ready PR; pass --inline for checkpointed inline execution.
---

# Execute

**Announce at start:** "Using game-dev:execute in subagent-driven mode." (or
"… in inline mode" when `--inline` was given, "… one unit (--one)" when
`--one` was given).

## 0. Preconditions and isolation

Check these first, in the checkout you are in:

- `studio-state get plan` names a file that exists and `studio-state show`
  has a `plan approved` line for it; otherwise stop and point at
  `/game-dev:plan`.
- The spec and the plan are committed: `git log -1 --format=%h -- <spec path>`
  and the same for the plan path each print a hash — note both hashes. If
  either prints nothing, stop and say: "commit the spec and plan first —
  `git add <spec> <plan> .studio/ledger .studio/config.json && git commit -m 'docs: approve <topic>'`".
  A worktree is a checkout; an uncommitted spec does not travel into it.
- Nothing is staged or pending on top of that commit:
  `git status --porcelain -- <spec> <plan> .studio/ledger .studio/config.json`
  prints nothing. Uncommitted changes to the gate inputs mean the worktree
  would carry a stale plan — commit or discard them first.
- Read the plan once. Read the spec its header names; the spec is the
  authority the plan argues from.
  Under `--one`, these two reads are `studio-brief task <n>` or `studio-brief final` only (§8): the plan and the spec are never read whole.
- **Which run this is.** Before the next step writes `stage execute`, read
  `stage`, `task` and `branch` (`studio-state get <key>`):
  - `plan` — a new run. First run the **finished-checkout guard**
    (Feature-checkout procedures, below) on the `branch` just read; it stops
    before any state write. Then, just before the next step's
    `studio-state set stage execute`, run `studio-state set branch -`: a
    new run clears `branch` before it isolates. A stop before isolation
    step (c) — the ancestor check's `git merge --ff-only` failing on a local
    default branch that has diverged from `origin` (the usual case after a
    PR merged on GitHub without a `git pull`), or the user declining a
    worktree — leaves `stage execute` with no `branch`. The re-run is then a
    resume that isolates as a new run does, never one that enters the
    previous feature's worktree.
  - `execute` — a resume. So are `review`, `playtest` and `ship`, the
    mid-way values an older studio pipeline wrote; they have no `branch`.
  - `idle`, `brainstorm` or `retro` — no approved plan is waiting to run (at
    `idle` the pointers still name the finished feature): stop and name
    `/game-dev:studio`.
- A new run first runs `studio-state set branch -`; then every run runs
  `studio-state set stage execute`. An interruption between the two leaves
  `stage plan`, so the re-run is a new run again, never a resume into the
  previous feature's worktree. Read `task` to find where to resume: `3/6`
  means tasks 1–3 are complete; start at 4. `studio-state` keeps the
  pointer in the project's main checkout, so every call below works the
  same from inside a worktree.

Under `--one`, see §8. It changes what every stop here does.

**Under a lane** (`STUDIO_STORY` and `STUDIO_RUN` both set) this paragraph
replaces the clean-tree check above, the ancestor check, and a new run's
isolation (b) and (c); a resume still enters its checkout by (a). `<id>`
is `STUDIO_STORY`:

- Under a lane the ancestor check never runs, a resume's included: the story branch never holds the `run/<slug>` docs commits, so its `git merge --ff-only` would fail every unit after the first. The docs sync below replaces it.

- The clean-tree check is
  `git status --porcelain -- <spec> <plan> .studio/ledger/<id>.md .studio/config.json`:
  another lane's uncommitted `Stop:` line is never seen.
- Git lock rule: retry a git write whose stderr says `could not lock` or `cannot lock ref`
  three times, after 1, 2 and 4 seconds, before treating it as a failure.
  Run `git fetch origin` and `git fetch origin run/<slug>` with that retry.
- Read Target, Branch and slug from `$STUDIO_RUN` (its header and this
  story's row).
- **Branch exists** (local, or `origin/<Branch>`): enter its worktree
  (`studio-state worktree`, else
  `git worktree add --no-track [-b <Branch>] <path> <Branch or origin/<Branch>>`).
  Then sync the docs:
  `git checkout $STUDIO_DOCS_REV -- <spec> <plan>`, and only when
  `git diff --cached --quiet` fails, commit
  `docs(<id>): plan at run docs <short sha>`. The ledger is never touched.
- **New branch:**
  `git worktree add --no-track -b <Branch> <STATE_ROOT>/.claude/worktrees/<Branch with / → -> origin/<Target>`,
  then `EnterWorktree` with `path:`, then
  `git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md`,
  and commit `docs(<id>): approved plan`.
- Then `studio-state set branch <Branch>` and
  `studio-state ledger "base origin/<Target>"`. Every `git merge-base` in
  §4a, §5 and §7 uses `origin/<Target>` after a fetch; the bare `<Target>`
  is used only for `gh pr create --base`.
- **The gate runs in the foreground.** Run `studio-test` and `studio-run`
  as foreground Bash calls with `timeout` set to `$BASH_MAX_TIMEOUT_MS` (the
  runner exports it, `session_minutes` × 60000). A call that waits for the
  gate lock behind another lane's test or a merge command just blocks until
  it gets the lock. Never run either in the background: no
  `run_in_background`, no `&` inside the command, no Monitor or notification
  wait. This is a headless one-shot `-p` session: a turn that ends to wait
  for a notification ends the session, the notification never arrives, the
  gate is orphaned and the unit makes no progress (phoenix
  `mob-composer-parity`, 2026-10-02). The raised cap is settled:
  `tests/probes/bash_timeout_probe.sh` (2026-10-02) showed a `-p` session's
  foreground call running 12 minutes and returning when
  `BASH_MAX_TIMEOUT_MS` is raised, and moved to the background at 600 s when
  it is not. A call that outlives its `timeout` is moved to the background
  (its result says so): that is a timed-out gate — run
  `studio-state ledger "Stop: gate timed out — <command> ran past <n> min"`
  and end the turn. Usually the session cap ends the unit first (the
  `timeout` is the whole session's minutes): the runner records it
  `timed out`. Either way the runner ends any gate the unit leaves behind. §2 carries this rule into every subagent brief.
- **Subagents run in the foreground too.** Dispatch every subagent (the
  implementer, the reviewer, a fixer) with `run_in_background: false` and
  take its report in the same turn; for parallel work, put several
  foreground dispatches in one message. Never end a turn "waiting for the
  report": the session ends with the turn, print mode kills the subagent
  600 s later along with any gate it was running, and the unit ends with no
  progress (phoenix `mob-composer-parity` units 4 and 6, 2026-10-03: the
  rule above was kept and the dispatch was not). Under `OMEGA_AUTOPILOT=1`
  the studio's `autopilot-guard.sh` hook denies a background Agent, a
  background Bash call and Monitor; a denied call is re-issued in the
  foreground, not worked around. The runner records a unit that died this
  way `orphaned`.

**Isolation.** First note the current branch (`git branch --show-current`)
— the noted branch — along with the spec's and plan's noted hashes. Then:

- **(a) A resume:** **enter the feature checkout** (Feature-checkout
  procedures, below); never create a second worktree.
  - `studio-state worktree` exits 1 with no branch recorded
    (`studio-state: no feature branch recorded` — an older pipeline's run,
    or a new run that stopped before (c)): isolate as a new run does (b),
    unless `task` is past `0/N` and the current checkout's feature ledger
    has no `T<n> complete` line: then do not isolate; stop and say:
    "run `/game-dev:execute` from the feature's worktree" (a run an older
    pipeline started from the main checkout would get an empty worktree).
  - It exits 1 because the branch is gone
    (`studio-state: branch <b> no longer exists`): stop and say so; the
    user restarts with `studio-state set task 0/<N>` and
    `studio-state set branch -`, or abandons with `/game-dev:studio`.
- **(b) A new run:** invoke `superpowers:using-git-worktrees`. Never
  implement on `main` without the user's explicit consent.
- **The ancestor check** runs after every isolation, a resume's included
  (except under a lane, above). In
  the worktree, confirm each noted commit is in `HEAD`:
  `git merge-base --is-ancestor <hash> HEAD` for the spec's hash and for the
  plan's hash. If either is not an ancestor, the worktree was cut from a
  base that lacks the gate commits: run `git merge --ff-only <noted branch>`;
  if that fails, stop and say so.
- **(c) Only after that check:** for a new run, and for a resume that found
  no `branch`, run inside the worktree
  `studio-state set branch "$(git branch --show-current)"`. A new run — or
  such a resume at `task 0/N`, which is a new run restarted — then records
  its base and commits it at once:
  `studio-state ledger "base <noted branch>" && git add .studio/ledger && git commit -m "chore(studio): ledger"`.
  Never write the ledger before the fast-forward: an untracked ledger file
  makes it abort.

**The base** — the PR's base, and the anchor for
`git merge-base <base> HEAD` in §4a, §5 and §7 — is the noted branch on a
new run. On a resume it is the feature ledger's last `base <branch>` line,
because the noted branch can be the feature branch itself after a stop that
left the session in the worktree (§7 step 1). A ledger without one (a run
an older pipeline began) uses the default branch (Feature-checkout
procedures, below).

**Where to start**, once isolated:

- `task` is `N/N`: every task is complete. Do not start the
  subagent-driven-development (SDD) task loop; go to §5, or to §7 when the
  feature ledger already has a `final review done` line (a stop in the
  finish).
- `task` is `k/N` with k < N and SDD finds no progress ledger for this plan
  (its "start your own, fresh" case): seed it before the loop — its
  identity line, `# SDD ledger — plan: <plan path>`, then one
  `Task <n>: complete (commits <range>, review clean)` line for each
  `T<n> complete <range>` line of the feature ledger (§6 writes them). The
  progress ledger is git-ignored scratch in the worktree, so a worktree
  re-made by `git worktree add` (exit 3, below) or cleaned has none; without
  the seed, SDD would restart at Task 1 while `task` says otherwise.

### Feature-checkout procedures

- **Default branch:** `git symbolic-ref --short refs/remotes/origin/HEAD`
  without its `origin/`; without one, the first of `main` and `master` that
  exists. The main checkout is the first `worktree` line of
  `git worktree list --porcelain`.
- **Finished-checkout guard** (a new run, before any state write): when
  `studio-state get branch` names a branch (not `-`) that is not the default
  branch and equals `git branch --show-current`, stop with: "This checkout
  holds the previous, finished feature (`<branch>`). Leave it first:
  `ExitWorktree` with `action: "keep"`. When that reports no active worktree
  session, this session was launched here, and neither `ExitWorktree` nor
  `cd` outlasts the `/clear` the chain needs: quit and start `claude-gd` in
  `<main checkout>`. In the main checkout itself:
  `git switch <default branch>`.
  To start the next feature on this branch anyway, run
  `studio-state set branch -` first."
- **Enter the feature checkout** (a resume): run `studio-state worktree`.
  - Exit 0: when the printed path is not the current checkout
    (`git rev-parse --show-toplevel`), call `EnterWorktree` with
    `path: <it>`; without that tool, `cd <it>`.
  - Exit 3: run the command on its stderr's second line (it unlocks and
    prunes a stale entry first when one holds the branch), then enter the
    new worktree, the path that command added, the same way.
  - Exit 1: isolation rule (a).
  - If `EnterWorktree` refuses, stop and show its message; when another
    session holds the worktree, close that session first. Never `cd` into a
    worktree another live session is using.

## 1. Mode

**Default — subagent-driven.** Invoke
`superpowers:subagent-driven-development` and follow its loop for the
per-task cycle: fresh implementer per task, task review after each, ledger.
Its fix loop, its final review and its last step are replaced by §4a, §5 and
§7 below. The studio rules in §2–§7 layer on top of it.
Under `--one`, SDD's setup never reads the plan: the one task's text comes from `studio-brief task <n>`, and no other task is extracted.
Under `--one`, see §8.

**`--inline`.** Only when the user passed it. Invoke
`superpowers:executing-plans` instead and implement tasks in this session in
batches, checking in with the user between batches. You are the implementer:
before each task read the skills named in the role agent's `## Skills you
may call` section (`studios/game-dev/agents/<role>.md`). §3, §5, §6 and §7
apply in inline mode too, and so do §4a's re-review and no-third-pass rules
(3 and 4); §2's dispatch and §4 do not, and you make each fix yourself where
§4a and §5 dispatch a fresh agent.

Three more modes are units only the overnight runner launches (the headless
rules of §8 apply to all three):

- `--land`: the landing repair unit (§9), launched when a landing conflicts or the merge command refuses.
- `--gate-repair`: the gate repair unit (§11), launched under a lane when a story's finish gate is red.
- `--progress`: the run's PROGRESS entry unit (§10), launched once per run.

## 2. Who implements (subagent-driven mode)

Dispatch the agent named by the task's `Role:` line with the Agent tool
(`subagent_type: "game-dev:<role>"` — for example
`subagent_type: "game-dev:gameplay-programmer"`). The agent carries its own
persona, rules and output contract; the brief carries only the task.

One exception: when `.studio/config.json` sets `language: csharp` and the
role is `game-dev:gameplay-programmer`, dispatch
`godot-prompter:godot-csharp-engineer` instead and prepend the project
`CLAUDE.md` architecture rules and the gameplay-programmer's output contract
to its brief, because that agent does not know the studio's report shape.

The `Role:` values are the studio's agents: `game-dev:gameplay-programmer`,
`game-dev:level-designer`, `game-dev:tech-artist`, `game-dev:feel-tuner`,
`game-dev:ui-designer`, `game-dev:architect` implement; `game-dev:game-designer`,
`game-dev:producer`, `game-dev:playtester` and `game-dev:reviewer` never
appear in `Role:`.

Every brief also carries: the task text (via the skill's task-brief script),
the spec sections the task cites, and the project `CLAUDE.md` architecture
rules. The agent's own `## Skills you may call` section (in
`agents/<role>.md`) names the skills it reads before writing code. A stuck
implementer reads `superpowers:systematic-debugging`.

Under a lane, every brief that has a subagent run `studio-test` — §3's
implementer, §4a rule 2's fixer, §5 step 5's wave — also carries this line
verbatim (§0, The gate runs in the foreground): "run `studio-test` and
`studio-run` as foreground Bash calls with `timeout` set to
`$BASH_MAX_TIMEOUT_MS`; never in the background (no `run_in_background`, no
`&`), and never end a turn to wait for one".

## 3. Verify rules (both modes)

`Verify:` is one kind or several joined with `+` (`unit+playtest`). Every
kind listed binds the implementer:

- `unit` — the implementer follows `superpowers:test-driven-development`:
  the test named in `Files:` is written and seen to fail before the
  implementation, then passes. The test framework is the project's test
  framework (`tests` in `.studio/config.json`, default GUT). Before
  reporting, the implementer runs `studio-test` and pastes its summary
  line. Exit 2 (no engine binary) or 3 (GUT not installed) stops the task:
  report it to the user with the printed hint; do not work around it.
- `playtest` — the implementer's report ends with the playtest item the task
  defined (action, expected perceptual result, what a failure looks like).
  Record it with `studio-state ledger "T<n> Playtest item: <text>"`.
- `visual` — the implementer reports what to look at and where. Record it as
  `studio-state ledger "T<n> Visual: <text>"`.

A task that introduces or changes a tunable value (a cooldown, a window, a
speed, a curve) always includes `unit`: the number is tested, the feel is
played.

## 4. Who reviews (subagent-driven mode)

Where subagent-driven-development dispatches its task reviewer, dispatch
`game-dev:reviewer` (`subagent_type: "game-dev:reviewer"`) with the task
text, the spec sections it cites, the global-constraints block, and the
commit range. The agent carries this checklist; it is repeated here so the
orchestrator can judge the report:

- Spec compliance: every acceptance criterion the task claims is met, and
  nothing beyond the task was built.
- `godot-prompter:godot-code-review` findings.
- Composition, not inheritance, where the spec specified a component.
- Cross-system notification goes through signals; `EventBus` only where no
  ownership path exists; parent→child calls and `@export` injection are
  correct.
- No tuning literal outside a Resource.
- No per-frame `instantiate()`, `new()`, Array/Dictionary/String building, or
  `get_node()` by string in `_process` / `_physics_process`; anything else
  is a profiler question, not a review finding.
- For `unit`: the test exists, fails without the change, passes with it.

Findings are one line each, severity-tagged.

A task whose heading block has `Review: final` gets no per-task review: its
findings fold into §5. A task with `Review: task`, or with no `Review:` line,
is reviewed as above; a per-task reviewer is dispatched with `model: "opus"`
(the agent file keeps `model: inherit`).

## 4a. Fix rounds (the per-task loop and the final fix wave)

This overrides `superpowers:subagent-driven-development`'s fix loop (rounds 1–3 resume the original implementer, a scoped re-review every round, five rounds): never resume or message an implementer that has handed back.

1. **Minor findings** never start a round. Record them as SDD records them
   (`Task <N>: minor (deferred): <one-liner>` in its progress ledger); they
   all go to the one final fix wave after the final review (§5). Also
   ledger each one to the story's ledger,
   `studio-state ledger "T<n> minor (deferred): <one-liner>"`.
   `studio-brief final` reads only the story ledger (the feature ledger
   outside a lane), never SDD's progress ledger, so under a lane (and any `--one` run) the final-review unit
   sees a deferred minor only through this line.
2. **A round** — for the Critical and Important findings of one review pass
   — is one dispatch of a **fresh** agent of the task's `Role:` (§2's
   dispatch rule, the C# exception included). Its brief carries:
   - the findings, verbatim;
   - the diff as a file, never pasted inline: SDD's review package for the
     task's commit range. `bash scripts/review-package <plan> <BASE> HEAD`,
     run by its path in SDD's skill directory, from the worktree root, with
     `<BASE>` the commit the task started from, prints the file's path (the
     script runs git in its working directory); the file holds
     `git log --oneline`, `git diff --stat` and `git diff -U10` for the
     range;
   - the file:line slices each finding cites (the cited line ± 20 lines);
   - the task text and the spec sections it cites;
   - "fix these findings only; one commit, subject `fix(T<n>): <summary>`;
     run the task's tests — the `Verify: unit` test files the task names,
     then `studio-test` — and paste the summary line before handing back";
   - under a lane, §2's foreground `studio-test` line;
3. **Re-review** — one scoped dispatch of `game-dev:reviewer` over the fix
   commit's range (its review package), with the findings list — happens
   only when the round's findings included a Critical, or
   three or more Importants, or the fix is a production-bug fix: it changes
   lines that already existed at `git merge-base <base> HEAD`, to correct a
   defect there. Otherwise accept the round on the fixer's test output.
4. **Never a third pass.** The first review of a scope is pass 1; a
   re-review is pass 2. A Critical or Important still open after pass 2 gets
   one last fresh fix dispatch (same brief) and no further review. Whatever
   that fixer reports it could not close is parked:
   `studio-state ledger "T<n> Ruling: parked — <finding> — <why> — <cost if wrong>"`
   (or `Ruling: parked — …` for the final scope). The final review's
   verify-prior-fixes list re-checks every fix commit (§5).
5. Every finding that changed the code is still ledgered:
   `T<n> Review: <one line>` (§6).
6. A task is complete — `set task n/N`, `T<n> complete` — when its review is
   clean, its last round was accepted under rule 3, or what remains is
   parked under rule 4. A `Review: final` task is complete once its implementer's tests pass
   (the summary line it pasted); it gets no review here, and its findings fold into the final review (§5).

## 5. Final review

After the last task completes, and as its own dispatch — never folded into
the last task's review. Under `--one`, see §8: a task unit never starts it.

1. Run `studio-test` and `studio-lint` fresh; keep both outputs.
   Under a lane, §5 step 1 is skipped (no fresh `studio-test` or
   `studio-lint`): the implementers ran the tests per task, and the finish
   gate covers the fix wave.
2. Build the verify-prior-fixes list from the scopes reserved for fix
   commits. With `<merge-base>` = `git merge-base <base> HEAD`, run
   `git log --format='%h %s' <merge-base>..HEAD` and keep the lines that
   match `^[0-9a-f]+ fix\((T[0-9]+|final|gate|review|B[0-9]+)\)` (`grep -E`).
   A plan task's own `fix(…)` commit — a bug-fix feature — is not on the
   list.
3. Dispatch `game-dev:reviewer` with `subagent_type: "game-dev:reviewer"`
   and `model: "opus"` (the agent file keeps `model: inherit`; the dispatch
   parameter overrides it). This replaces SDD's final reviewer
   (`requesting-code-review`'s `code-reviewer.md`). The brief:
   - `Scope: branch <name> vs <base>`;
   - the review package for `<merge-base>..HEAD`
     (`bash scripts/review-package <plan> <merge-base> HEAD`, run by its
     path in SDD's skill directory, from the worktree root), as SDD's final
     review gets one;
   - the spec path and the project `CLAUDE.md` path — report every
     acceptance criterion as met or unmet, in the agent's own
     `Spec compliance: met: …; unmet: …` line;
   - the plan path — check every `Verify: unit` task's test;
   - "Verify prior fixes": the list from step 2 — for each commit, confirm
     the finding it fixed is closed; a fix that did not close its finding is
     a finding of the original severity;
   - SDD's deferred-minor and parked lines — triage which must be fixed
     before merge;
   - "Gate-enforced findings are must-fix": a finding about anything the
     gate checks — line length, docs budgets, any check under `tests/` —
     whatever its severity, is never ruled `leave`, deferred or parked;
   - the `studio-test` and `studio-lint` output from step 1. Under a lane, in place of that output, the brief says
     "step 1 skipped under a lane: no fresh test run; each task's tests
     ran in its implementer, and the finish gate runs the full gate after
     the fix wave" — nothing is run to produce it;
   - "review only — do not fix".
4. Ledger:
   `studio-state ledger "Review: final — <Findings line>; unmet: <list or none>"`.
5. **The final fix wave**: every Critical, Important and must-fix Minor from
   the final review, plus the deferred Minors, in one fresh dispatch per
   owning role (the `Role:` of the plan task whose `Files:` names the file;
   `game-dev:gameplay-programmer` when none does) — usually one dispatch,
   with §4a rule 2's brief. Commit subject `fix(final): <summary>`.
   Every gate-enforced finding (step 3) is in the wave, whatever its
   severity: it would turn the finish gate red, and under a lane that costs
   a gate-repair unit and a second full gate. Never accept a claim that a
   file is outside such a check (it "is not under" that test) without
   running that test file: `studio-test <path>`.
   Re-review per §4a rule 3 (a Minor-only wave is never re-reviewed); never
   a third pass (§4a rule 4).
6. `studio-state ledger "final review done"`, then commit the ledger:
   `git add .studio/ledger && git commit -m "chore(studio): ledger"`. The
   finish then starts from a clean ledger, so a re-run after a stop in §7
   passes §0's clean-tree check and resumes at §7 (§0, Where to start).
   Under `--one`, see §8.

## 6. State (both modes)

- When a task is complete (§4a rule 6): `studio-state set task n/N` and
  `studio-state ledger "T<n> complete <short commit range>"`.
- Every judgment call: `studio-state ledger "T<n> Ruling: <decision> — <why> — <cost if wrong>"`.
  The SDD ledger under `.superpowers/sdd/` remains the recovery map for the
  loop; the feature ledger (`.studio/ledger/<feature>.md`) carries the rulings
  the user reads.
- Every review finding that changed the code: `studio-state ledger "T<n> Review: <one line>"`.
- Commit `.studio/ledger/` with each task's commits; it is part of the
  feature and merges with it.

Once isolated (§0), stop only for: an irreversible, destructive or
security-sensitive operation; a plan too broken to follow; no Godot binary
(`studio-test` or `studio-run` exit 2); the test framework not installed
(`studio-test` exit 3). Pushing this branch and opening its PR are not
ask-first side effects; no session merges anything in any run mode:
nothing is merged into `main` (the default branch) by a session, and under
a lane the runner lands the story. Everything else is a ruling.

## 7. Finish

This replaces SDD's last step: never invoke its branch-finishing skill. Run
it once §5 is done, with no question to the user:

1. **Gate.** Invoke `superpowers:verification-before-completion` and run,
   fresh, from the worktree root, each with its summary line shown in the
   report:
   - `studio-test` — exit 0;
   - `studio-lint` — exit 0, or exit 3 (gdtoolkit not installed: noted in
     the gate line, not red);
   - `studio-run --seconds 10` — exit 0 (it exits 1 on `SCRIPT ERROR` or
     `ERROR:` in the run log).

   Exit 2 from `studio-test` or `studio-run`: stop and show the printed
   message — usually `GODOT_PATH` is unset; `studio-dispatch` also exits 2
   when it finds no studio root, engine or adapter — and do not set
   `stage idle`. Exit 3 from `studio-test`: stop with the printed hint. A
   stop here leaves the session in the worktree; a re-run resumes in place,
   at the gate (§0, Where to start).

   Any other non-zero exit is a red gate: one fresh fixer (the owning role
   per §5 step 5, with the failing output) commits `fix(gate): <summary>`,
   then the whole gate re-runs. The gate runs at most three times: after
   the third red run, dispatch no fixer and continue the finish with the PR
   opened as a **draft**, the gate line showing the failure, and
   `studio-state ledger "Ruling: gate red after three fix rounds — <failing command and line> — <cost if wrong>"`.
2. **Play list.** Build it in this session, with no agent: every
   `T<n> Playtest item:` and `T<n> Visual:` line in `studio-state show`, and
   every row of the spec's `## Feel targets` whose check column says
   `playtest`, merged where two describe the same check. Each item is one
   line, `P<k> <do> → <expect> → fail looks like: <fail>`. Up to five items:
   all of them. More than five: the five that cover acceptance criteria and
   feel targets lead as `P1`–`P5`, and the rest follow under `Also:`,
   numbered on from `P6`. No source lines: the list is the single line
   `nothing to play`. Record each item:
   `studio-state ledger "P<k> Play: <item text>"`.
3. **PROGRESS.** When the project has `docs/game-dev/PROGRESS.md`, dispatch
   `game-dev:producer` (`subagent_type: "game-dev:producer"`) with the plan
   path, the spec path, the feature ledger's absolute path
   (`<worktree>/.studio/ledger/<slug>.md`, the file `studio-state show`
   prints under `## Feature ledger: <slug>` — the producer has no Bash, so it
   reads the file instead of running `studio-state`), the play list, the
   branch name and the PROGRESS path. It adds the entry on the branch and
   reports the milestone gate: `gate met: <current> → <next>` or
   `gate not met: …`. Commit it:
   `git add docs/game-dev/PROGRESS.md && git commit -m "docs(progress): <topic>"`.
   On `gate met`: `studio-state set milestone <next>`. On `gate not met`:
   `milestone` stays, and its missing list goes in the report. Without the
   file: skip this step and say so in the report.
4. **Push and PR.** `<branch>` is `git branch --show-current`; `<base>` is
   §0's base.
   - When `<branch>` is the default branch (§0, Feature-checkout
     procedures; the user consented to work in place), push nothing and
     open no PR: the report says the work is committed locally on
     `<branch>`, and step 5's line is `shipped <branch> (local, default branch)`.
   - Otherwise, first write the PR body file,
     `"$(git rev-parse --git-dir)/game-dev-pr-body.md"` — inside the
     repository's metadata, never committed. It holds, in order: the spec's
     `## Purpose`; `## Acceptance criteria` as a `- [ ]` checklist;
     `## Play before merging` (the play list); `## Rulings` (every `Ruling:`
     line of the feature ledger, in order, each with its cost if wrong); the
     final review verdict line; the gate line
     (`Gate: studio-test <summary> · studio-lint <exit and summary> · studio-run <exit>`).
   - Then `git push -u origin <branch>`, then `gh pr view --json url` on the
     branch: when a PR exists, it is the PR (no second one). Otherwise
     `gh pr create --base <base> --title "<spec title>" --body-file <body file>`,
     adding `--draft` when `omega-mode show` lists `autopilot`, when
     `omega-mode show` fails (it exits 1 without `CLAUDE_CODE_SESSION_ID`;
     an unknown mode counts as autopilot), or when step 1 ended red.
   - No `origin` remote, `gh auth status` failing, a rejected push (never
     force-push) or a failed `gh pr create`: keep the body file, say which
     failed, print the body path, and continue.
     Never merge: no session merges into `main` (the default branch) in any run mode; the runner lands.
5. **State.** `studio-state ledger "shipped <PR url, or the branch name when there is no PR>"`;
   commit the ledger
   (`git add .studio/ledger && git commit -m "chore(studio): <topic> finished"`)
   and push it when step 4 pushed. Then:
   `studio-state set stage idle`; `studio-state set task -`.
   Leave `spec`, `plan` and `branch` as they are: `branch` keeps the feature
   branch until the next new run clears it.
6. **Leave the feature checkout.** The worktree and its branch stay on disk
   for `/game-dev:playtest` and `/game-dev:review`. Call `ExitWorktree` with
   `action: "keep"` unconditionally. It is a no-op that says so when no
   `EnterWorktree` session is active, and it is the only step that moves the
   directory `/clear` returns to: an `EnterWorktree` made before a `/clear`
   in this process is still active, though this conversation does not
   remember it. When it reports no active session and
   `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`
   (you are still in a linked worktree):
   - `cd` to the main checkout (the first `worktree` line of
     `git worktree list --porcelain`);
   - unless this run entered the worktree with `cd` itself (the git fallback
     of the Enter procedure or of `superpowers:using-git-worktrees`), the
     session was launched in this worktree: put this line right before the
     report's `Next:` line: "This session started in the feature worktree,
     and /clear returns here: quit, then start claude-gd in
     `<main checkout>` before the next feature."

   Never skip this step. Without it, `/clear` returns the session to the
   worktree (`EnterWorktree` moves the session's original directory, and
   `/clear` resets to it), and `superpowers:using-git-worktrees` skips
   creation inside a linked worktree, so the next feature would be specced,
   planned and built on this branch and pushed into this PR.
   Under `--one`, see §8.
7. **Report**, in this order: the PR link (or the saved body path and the
   reason; on the default branch, that the work is committed locally); the
   play list, under `Play before merging`; the rulings, each with its cost
   if wrong; the producer's gate result (milestone `<a> → <b>`, the missing
   list, or PROGRESS skipped); the final review verdict line; the gate
   line; and the last line, verbatim:

   ```
   Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature.
   ```

   Under `--one`, see §8.

**Under a lane**, the steps above change as follows; the run mode is the
runner's (`STUDIO_RUN`'s header), and the base is `origin/<Target>`:

- **Integration:** step 1 runs once, the story's one test run;
  `studio-test` and `studio-run` each run as a foreground Bash call with `timeout` set to `$BASH_MAX_TIMEOUT_MS`, never in the background (§0, The gate runs in the foreground: a call waits on the gate lock by blocking).
  A gate call that outlives its `timeout` and is moved to the background is a timed-out gate: the finish runs
  `studio-state ledger "Stop: gate timed out — <command> ran past <n> min"`, a hard stop like those below.
  Step 1's red-gate loop does not run under a lane:
  the gate runs once, no `fix(gate)` round follows, and a red gate never ships.
  Exit codes keep step 1's meaning: `studio-lint` exit 3 (gdtoolkit not installed) is noted in the gate line, not red, and the story goes on.
  `studio-test` or `studio-run` exit 2 and `studio-test` exit 3 are step 1's hard stops: the finish runs
  `studio-state ledger "Stop: <the printed message>"` (not `gate red`), and ends as below.
  Any other non-zero exit is a red gate: the finish runs
  `studio-state ledger "Stop: gate red — <failing command and line>"`.
  Each stop is committed as §8's stops are committed, writes no `shipped` line, pushes
  nothing further, and ends the turn; steps 2–6 do not run. A `gate red` stop
  is the one the runner repairs: it launches the gate-repair unit (§11), then
  a fresh finish that runs this gate again, up to `overnight.gate_repairs`
  times. Every other stop here is hard: the runner records the story stopped.
  Otherwise step 3 (PROGRESS) is skipped; step 4 pushes `<Branch>` and
  opens no PR; `studio-state ledger "shipped <Branch>"`.
- **Direct:** step 1 is skipped (the runner's merge command is the gate);
  step 3 is skipped; step 4 pushes, then does this: open a **draft** PR into the default branch
  (`--base <Target>`); `studio-state ledger "shipped <url>"`.
- Under a lane, step 5 still commits the ledger (`shipped …`) and pushes it
  when step 4 pushed: the runner confirms a landing from the `shipped` line on origin/<Branch>. Then `studio-state set stage idle` and
  `studio-state set task -` as written.
- On a git write that fails with `could not lock` or `cannot lock ref`, use
  §0's retry rule.
- No session merges anything: the runner lands the story.

## 8. One unit (--one)

`--one` is how `studio-overnight` drives this skill: one fresh headless
session per unit, with `OMEGA_AUTOPILOT=1` set, so `omega-mode show` lists
`autopilot source=env` and its phase 2 rules hold. Under `--one` this skill
runs exactly one unit, writes its state, commits, pushes, and ends the turn.

- **Inputs:**
  - the orchestrator reads only `studio-brief task <n>` (a task unit) or
    `studio-brief final` (the final review), plus the files its implementer
    or reviewer reports name;
  - it never reads the plan or the spec whole, and
    never runs SDD's pre-flight conflict scan
    (the plan session ran it, and its rulings are in `## Decisions`);
  - the task brief and the per-task reviewer brief (§2, §4) are built from
    that output;
  - for a single-plan plan with no `## Global Constraints` or a task with no
    `Spec:`, `studio-brief` prints a one-line note and exits 0: use it all
    the same.
- **Which unit:** exactly the one §0's *Where to start* picks.
  - `task k/N` with k < N: one SDD task, `T<k+1>`.
  - `N/N` without a `final review done` line: §5 as a whole, the fix wave
    included, through step 6; §7 is not started — it is the next unit.
  - `N/N` with that line: §7 steps 1–6.
  - Never more than one.
- **Cutting SDD's loop:** invoke SDD as §1 says. Once the task is complete
  (§4a rule 6) and §6's writes are done (`set task n/N`, the `T<n> complete`
  line, the ledger committed), no next implementer is dispatched, and when
  n = N §5 is not started.
  This overrides SDD's instruction to continue to the next task.
- **What each unit writes:**
  - a task: the task's commits, `task n/N`, the `T<n>` ledger lines, then
    `git push -u origin <branch>`;
  - the final review: the `fix(final)` commits, the `Review: final` and
    `final review done` lines committed, then the push;
  - the finish: §7 as written, its lane changes included (`P<k> Play:`
    lines; outside a lane or under direct, the draft PR and `shipped <url>`;
    under integration, no PR and `shipped <Branch>`; a red integration gate, `Stop:` and no `shipped` line;
    `stage idle`, `task -`).

  A rejected push is a `Ruling:` line, not a stop.
- **Every stop** (§0's preconditions and isolation stops, §6's hard-stop
  list, §7 step 1's exit 2 and exit 3, a red gate under a lane): run
  `studio-state ledger "Stop: <reason>"`, one line, reason first. Where:
  - Once §0 step (c) has recorded `branch` — or a resume has entered the
    feature checkout its recorded `branch` names — in the feature checkout,
    then commit it there:
    `git add .studio/ledger && git commit -m "chore(studio): stop"`.
  - Any stop before that — §0's preconditions, §0 (a)'s stops, and a stop
    before step (c) has recorded `branch`, the ancestor check's failed
    fast-forward inside the worktree a new run just created included —
    writes its `Stop:` line in the checkout this session was launched in
    (its starting working directory: the runner's start directory, which
    the runner always reads). If the session has already entered a new
    worktree, return there first (`ExitWorktree` `action: "keep"`, or `cd`
    to that directory), then run `studio-state ledger` there.
    That line is never committed, whatever branch is checked out: a hard
    stop needs a human, and the runner's preflight refuses a dirty ledger
    on the re-run.

  Then end the turn.
- **§7 step 6, headless:** `ExitWorktree` `action: "keep"` runs as written.
  The "started in the feature worktree" note and the `Next:` line are
  skipped, because no human reads this session.
- **No handoff:** `--one` never runs `omega:handoff`. The runner's
  `report.md` is the morning report.
- `--one` with `--inline` is refused with a `Stop:` line (subagent-driven
  only).

## 9. Landing repair (--land)

The runner launches this unit when a landing conflicts or the merge command
refuses: prompt `/game-dev:execute --land`, from the start checkout, with
`STUDIO_STORY`, `STUDIO_RUN`, `OMEGA_AUTOPILOT=1` and `STUDIO_REPAIR` set.
It bypasses §0's stage gate: these preconditions replace it, and any miss is
a `Stop:` line (§8's stop rule).

- **Enter the feature checkout** through `studio-state worktree`, first:
  the ledger the checks below read is the feature checkout's.
- **Preconditions:** `stage idle`, a `shipped` line in the ledger, and
  `STUDIO_REPAIR` set.
- **Merge the target:** `git fetch origin`, then
  `git merge --no-edit origin/<Target>`. Merge, never rebase: the branch is
  already pushed and force-push is denied.
- **Resolve:** `STUDIO_REPAIR=conflict` means that merge conflicts.
  `STUDIO_REPAIR=red:<log path>` means the merge command refused: read the
  landing log at that path. Dispatch one fresh fixer (§5 step 5's owning
  role) with the conflict, or with the failing output from the log.
- **Gate:** the story's gate, §7 step 1, through `studio-test` (which holds the gate lock).
  This unit overrides §7's lane rule that the gate runs once: it runs up to three times.
  The same fixer (or a fresh one given the failing output) fixes between runs.
  Exit codes keep §7's lane meaning: `studio-lint` exit 3 is not red;
  `studio-test` or `studio-run` exit 2 and `studio-test` exit 3 are hard stops that end the unit at once with `studio-state ledger "Stop: <the printed message>"`, committed and not pushed.
- **Commit and record:** commit `fix(land): <summary>`, push the story
  branch, then `studio-state ledger "Repair: <summary>"`, committed and
  pushed. The runner reads that `Repair:` line to retry the landing once.
- **Red after three runs:** `studio-state ledger "Stop: land repair red — <failing line>"`.
  Commit the Stop line; do not push it: a red merge head never reaches origin/<Branch>, which keeps its `shipped` line. The runner reads the ledger from the feature checkout. End the turn.
- A git write whose stderr says `could not lock` or `cannot lock ref` is retried, as §0 and §7 do.
- **Never lands:** no session merges into `main` (the default branch) in any
  run mode; the runner lands. This unit never merges into the target, never
  pushes the target or `main`, and never runs the merge command.
- One unit: end the turn.

## 10. Run progress (--progress)

The runner launches this unit once per run, after the stories: prompt
`/game-dev:execute --progress`, `OMEGA_AUTOPILOT=1`, cwd the run's progress
worktree (integration: the integration worktree; direct: `progress/<slug>`),
`STUDIO_RUN` set and no `STUDIO_STORY`. It bypasses §0's stage gate and
isolation: the state is idle after the stories' `reset --keep-ledger`, and
there is no plan to read.

- **Preconditions:** cwd is a git worktree, `STUDIO_RUN names a readable manifest`,
  and `docs/game-dev/PROGRESS.md` exists. Otherwise `Stop: <reason>` and end the turn.
- **One `game-dev:producer` dispatch**, briefed with the manifest at
  `$STUDIO_RUN` and, for each landed story (`landed.tsv` in
  `<STATE_ROOT>/.studio/runs/<slug>/`), its spec's `## Purpose` and its story
  ledger, read with `git show <landed sha>:.studio/ledger/<id>.md`.
- **One PROGRESS entry for the run**, committed as `docs(progress): <slug>`.
  A unit that makes no commit is red.
- **It does not push** and no session merges into `main` (the default
  branch) in any run mode: the runner pushes and lands the entry.
- One unit: end the turn.

## 11. Gate repair (--gate-repair)

The runner launches this unit under a lane when a story's finish stopped on
a red gate (`Stop: gate red — …`, §7's lane rules) and the story has gate
repairs left (`overnight.gate_repairs`): prompt
`/game-dev:execute --gate-repair`, from the start checkout, with the
story's env (`STUDIO_STORY`, `STUDIO_RUN`, `STUDIO_DOCS_REV`,
`OMEGA_AUTOPILOT=1`, `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS`) and
`STUDIO_REPAIR=gate:<log>` set. `<log>` is the newest `studio-test` log of
the feature checkout (`.studio/reports/test-<stamp>.log`), or `-` when there
is none. It bypasses §0's stage gate: these preconditions replace it, and
any miss is a `Stop:` line (§8's stop rule).

A full gate can take most of a session, so this unit never runs it: it
fixes, proves the fix on what failed, and records the repair. The runner
then launches a fresh finish, which runs the full gate once (§7).

- **Enter the feature checkout** through `studio-state worktree`, first:
  the `Stop: gate red` line is in the feature checkout's ledger only, so
  the checks below read it there. A miss before entering is §8's stop in
  the start checkout.
- **Preconditions:** `stage execute`, no `shipped` line in the feature
  ledger, its latest `Stop:` line is a `gate red` one, and `STUDIO_REPAIR`
  starts with `gate:`.
- **Read the failure:** the `Stop: gate red — <failing command and line>`
  line names the red command. For `studio-test`, read the failing tests'
  names and output from the log at `<log>`; when `<log>` is `-` or shows no
  failure, the Stop line's failing line is the failure.
- **Fix:** dispatch one fresh fixer (§5 step 5's owning role) with the
  failing output. It commits `fix(gate): <summary>`.
- **Verify what failed, not the whole gate:** `studio-test <path>` for each
  failing test file; `studio-lint` or `studio-run --seconds 10` when that was
  the red command. Each runs as a foreground Bash call with `timeout` set to
  `$BASH_MAX_TIMEOUT_MS` (§7's lane rule). Up to three rounds, a round
  being one run of every failing file (or of the red command); the same
  fixer (or a fresh one given the new failing output) fixes between
  rounds. Exit codes keep §7's lane meaning: `studio-lint` exit 3 is not red;
  `studio-test` or `studio-run` exit 2 and `studio-test` exit 3 are hard
  stops that end the unit at once with
  `studio-state ledger "Stop: <the printed message>"`, committed.
- **Record:** `studio-state ledger "Repair: gate — <summary>"`, commit the
  ledger (`git add .studio/ledger && git commit -m "chore(studio): gate repair"`),
  then push the story branch. The runner reads that `Repair:` line and
  launches the fresh finish.
- **Red after three rounds:** `studio-state ledger "Stop: gate repair red — <failing line>"`,
  committed. It is a hard stop: the runner launches no further repair.
- A git write whose stderr says `could not lock` or `cannot lock ref` is retried, as §0 and §7 do.
- **Never ships, never lands:** no `shipped` line, no PR, no change to
  `stage` or `task`. No session merges into `main` (the default branch) in
  any run mode; this unit never merges, never pushes the target or `main`,
  and never runs the merge command.
- One unit: end the turn.

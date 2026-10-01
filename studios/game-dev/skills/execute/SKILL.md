---
name: execute
description: Use when an approved plan exists — dispatches a fresh role agent per task with a reviewer after each, a standalone final review, then the gate, a play list and a ready PR; pass --inline for checkpointed inline execution.
---

# Execute

**Announce at start:** "Using game-dev:execute in subagent-driven mode." (or
"… in inline mode" when `--inline` was given).

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
- **The ancestor check** runs after every isolation, a resume's included. In
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

**`--inline`.** Only when the user passed it. Invoke
`superpowers:executing-plans` instead and implement tasks in this session in
batches, checking in with the user between batches. You are the implementer:
before each task read the skills named in the role agent's `## Skills you
may call` section (`studios/game-dev/agents/<role>.md`). §3, §5, §6 and §7
apply in inline mode too, and so do §4a's re-review and no-third-pass rules
(3 and 4); §2's dispatch and §4 do not, and you make each fix yourself where
§4a and §5 dispatch a fresh agent.

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

## 4a. Fix rounds (the per-task loop and the final fix wave)

This overrides `superpowers:subagent-driven-development`'s fix loop (rounds 1–3 resume the original implementer, a scoped re-review every round, five rounds): never resume or message an implementer that has handed back.

1. **Minor findings** never start a round. Record them as SDD records them
   (`Task <N>: minor (deferred): <one-liner>` in its progress ledger); they
   all go to the one final fix wave after the final review (§5).
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
     then `studio-test` — and paste the summary line before handing back".
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
   parked under rule 4.

## 5. Final review

After the last task completes, and as its own dispatch — never folded into
the last task's review:

1. Run `studio-test` and `studio-lint` fresh; keep both outputs.
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
   - the `studio-test` and `studio-lint` output from step 1;
   - "review only — do not fix".
4. Ledger:
   `studio-state ledger "Review: final — <Findings line>; unmet: <list or none>"`.
5. **The final fix wave**: every Critical, Important and must-fix Minor from
   the final review, plus the deferred Minors, in one fresh dispatch per
   owning role (the `Role:` of the plan task whose `Files:` names the file;
   `game-dev:gameplay-programmer` when none does) — usually one dispatch,
   with §4a rule 2's brief. Commit subject `fix(final): <summary>`.
   Re-review per §4a rule 3 (a Minor-only wave is never re-reviewed); never
   a third pass (§4a rule 4).
6. `studio-state ledger "final review done"`, then commit the ledger:
   `git add .studio/ledger && git commit -m "chore(studio): ledger"`. The
   finish then starts from a clean ledger, so a re-run after a stop in §7
   passes §0's clean-tree check and resumes at §7 (§0, Where to start).

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
ask-first side effects; merging is never done. Everything else is a
ruling.

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
     failed, print the body path, and continue. Never merge.
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
7. **Report**, in this order: the PR link (or the saved body path and the
   reason; on the default branch, that the work is committed locally); the
   play list, under `Play before merging`; the rulings, each with its cost
   if wrong; the producer's gate result (milestone `<a> → <b>`, the missing
   list, or PROGRESS skipped); the final review verdict line; the gate
   line; and the last line, verbatim:

   ```
   Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature.
   ```

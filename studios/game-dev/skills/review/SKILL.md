---
name: review
description: Use when a branch or commit range needs a spec-compliance and Godot best-practice review on demand — at any stage, without changing it.
---

# Review

**Announce at start:** "Using game-dev:review over <scope>."

The task-by-task reviews in `execute` catch local problems. This command
looks at a whole branch (or a named range) against the whole spec, whenever
the user asks. It never changes `stage`.

## Feature-checkout procedures

- **Default branch:** `git symbolic-ref --short refs/remotes/origin/HEAD`
  without its `origin/`; without one, the first of `main` and `master` that
  exists. The main checkout is the first `worktree` line of
  `git worktree list --porcelain`.
- **Enter the feature checkout:** run `studio-state worktree`.
  - Exit 0: when the printed path is not the current checkout
    (`git rev-parse --show-toplevel`), call `EnterWorktree` with
    `path: <it>`; without that tool, `cd <it>`.
  - Exit 3: run the command on its stderr's second line (it unlocks and
    prunes a stale entry first when one holds the branch), then enter the
    new worktree, the path that command added, the same way.
  - Exit 1:
    more than one story fits, a removed story's worktree is offered, or none is recorded
    (no branch recorded, or it is gone). Ask the user once which checkout to use, naming the
    candidates `studio-state worktree` listed on stderr (or that none is
    recorded) and the `git worktree list` paths. For a `removed` candidate
    the user picks, run its command, then enter the path it added; never run
    a `removed` command unasked. Then enter the chosen checkout the Exit 0 way.
  - If `EnterWorktree` refuses, stop and show its message; when another
    live session holds the worktree, close that session first. Never `cd`
    into a worktree another live session is using.
- **Leave the feature checkout** (only when this command entered one): call
  `ExitWorktree` with `action: "keep"`. It is a no-op that says so when no
  `EnterWorktree` session is active, and it is the only step that moves the
  directory `/clear` returns to. When it reports no active session and
  `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`,
  `cd` to the main checkout. Unless this command entered with `cd` itself,
  the session was launched in this worktree: end the report with this line:
  "This session started in the feature worktree, and /clear returns here:
  quit, then start claude-gd in `<main checkout>` before the next feature."

## 0. Scope and checkout

§0 decides whether this run fixes. It is **report-only** in three cases: a
branch or range argument that HEAD does not match, the default branch, and
a `MERGED` or `CLOSED` PR (each below). A report-only run dispatches no
fixer, writes no ledger line, edits no plan, and commits and pushes nothing.

- When the argument is a branch or a range, skip the lookup: the scope is
  that argument. Fix only when HEAD is that branch (or the range ends at HEAD);
  otherwise the run is report-only.
- Otherwise **Enter the feature checkout**, and say which checkout.
- **Which feature.** After the lookup, check that the checkout holds the
  ledger of the feature `spec` names: `<checkout>/.studio/ledger/<slug>.md`
  (slug as `studio-state` derives it) exists. When it does not, this checkout's pointer moved on to the next feature:
  `spec` and `branch` name different features, and every ledger line
  written here would land in a ledger named for the next feature. **Leave the feature
  checkout** if this command entered one, then stop with: "the studio
  pointers now name `<spec>`; the finished feature is `<branch>` — fix it on
  that branch by hand, or run this after `<spec>`'s finish".
- Every brief to a dispatched agent names the checkout's absolute path and
  tells the agent to work there: an agent starts in the session's working
  directory.
- On the default branch (**Default branch**, above), the run is
  report-only: no fix dispatch, no ledger line and no commit.
- Before the first fix dispatch, run `gh pr view --json state` on the
  branch. On `MERGED` or `CLOSED`, the run is report-only: dispatch no fixer
  and push nothing; report the findings and name `/game-dev:brainstorm` for
  a fix that must reach the base.
- The scope: the argument when given (a range, a branch, a task number, a
  path list); otherwise the whole branch, `git merge-base <base> HEAD` to
  `HEAD`, where `<base>` is the PR's base
  (`gh pr view --json baseRefName`), else the last `base` line of the
  feature ledger, else the default branch.
- `studio-state get spec` names the spec; read it in full. If there is no
  spec, review against the project `CLAUDE.md` rules only and say so.

## 1. Baseline

Run `studio-test`. A failing suite is reviewed *first*: every failure is a
critical finding before the reviewer even reads the diff. Exit 2 or 3 is
reported to the user with the printed hint and the review continues without
the automated baseline.

Run `studio-lint`. Exit 3 means gdtoolkit is not installed — note it once
and move on; exit 1 findings are minor findings unless they hide a real
error.

## 2. Dispatch the reviewer

Build the review package for the scope: `git log --oneline`,
`git diff --stat` and `git diff -U10` for the range, redirected to one
uniquely named file under `"$(git rev-parse --git-dir)"`.

Build the verify-prior-fixes list: with `<merge-base>` the scope's start,
run `git log --format='%h %s' <merge-base>..HEAD` and keep the lines that
match `^[0-9a-f]+ fix\((T[0-9]+|final|gate|review|B[0-9]+)\)` (`grep -E`).

Dispatch `game-dev:reviewer` with `subagent_type: "game-dev:reviewer"` and
`model: "opus"` (the agent file keeps `model: inherit`; the dispatch
parameter overrides it), with:

- the scope (`Scope: branch <name> vs <base>` or the narrower one) and the
  checkout's absolute path;
- the review package file's path;
- the spec path and the project `CLAUDE.md` path — report every acceptance
  criterion as met or unmet, in `Spec compliance: met: …; unmet: …`;
- the plan path, so it can check every `Verify: unit` task's test;
- "Verify prior fixes": the list above — for each commit, confirm the
  finding it fixed is closed; a fix that did not close its finding is a
  finding of the original severity;
- the `studio-test` and `studio-lint` output from §1;
- the instruction "review only — do not fix".

It returns the report from its output contract: `Spec compliance`,
`Findings: N (critical c, important i, minor m)`, and one line per finding.

## 3. Fix rules

These are execute's fix rules. Never resume or message an implementer that
has handed back.

1. **Minor findings** never start a round. Collect them into one wave after
   the Critical and Important rounds; fix a one-line Minor there, and record
   any other as deferred.
2. **A round** — for the Critical and Important findings of one review pass
   — is one dispatch of a **fresh** agent of the owning role: the `Role:` of
   the plan task whose `Files:` names the file, or
   `game-dev:gameplay-programmer` when none does. Its brief carries:
   - the checkout's absolute path;
   - the findings, verbatim;
   - the diff as a file, never pasted inline: the review package for the
     scope;
   - the file:line slices each finding cites (the cited line ± 20 lines);
   - the spec sections the findings cite;
   - "fix these findings only; add a regression test when a finding is a
     behaviour; one commit, subject `fix(review): <summary>`; run
     `studio-test` and paste the summary line before handing back".
3. **Re-review** — one scoped dispatch of `game-dev:reviewer` over the fix
   commit's range, with the findings list — happens only when the round's
   findings included a Critical, or three or more Importants, or the fix is
   a production-bug fix: it changes lines that already existed at
   `git merge-base <base> HEAD`, to correct a defect there. Otherwise accept
   the round on the fixer's test output. A Minor-only wave is never
   re-reviewed, and there is never a third pass (rule 4).
4. **No third pass.** The first review of a scope is pass 1; a re-review is
   pass 2. A Critical or Important still open after pass 2 gets one last
   fresh fix dispatch (same brief) and no further review. Report whatever
   that fixer could not close.

The user may defer any finding. A deferred finding is written to the plan's
`## Backlog` with the finding line and the reason only in a run that writes
§4's ledger line; any other run lists it in the report instead.

## 4. State and hand-off

- **Report-only gate.** When §0 ruled the run report-only — the default
  branch, a `MERGED` or `CLOSED` PR (when no fix was dispatched, run §0's
  `gh pr view --json state` here), or a branch or range argument that HEAD
  does not match — write no ledger line, edit no plan, make no commit and
  push nothing: print the verdict and the findings, then **Leave the
  feature checkout** if §0 entered one, and skip the rest of this section.
- **Ledger line**, only in the feature's checkout. On the lookup path, that
  is the checkout the lookup found, or the one the user chose at Exit 1;
  the which-feature check has passed for it. On a branch or range argument,
  it is HEAD's checkout only when HEAD is the branch
  `studio-state get branch` prints and the checkout holds
  `.studio/ledger/<slug>.md` (the which-feature check, which that path
  skipped). There, `studio-state ledger "Review: <scope> — <Findings line>; <m> fixed, <k> deferred"`,
  then commit it on the feature branch with any `## Backlog` deferral:
  `git add .studio/ledger <plan path>`, then
  `git commit -m "chore(studio): ledger"`.
- Anywhere else, write no ledger line and edit no plan: the fix commits
  stand alone, and the report lists the deferred findings.
- When the branch tracks a remote (`git rev-parse --abbrev-ref @{u}`
  succeeds), push the fix commits and any ledger commit; never force-push.
- Print the final verdict line, the list of fix commits and any deferred
  finding the plan did not take, then **Leave the feature checkout** if §0
  entered one.

## Rules

- The reviewer reviews; fixers fix. Never let the reviewer edit code in this
  command, and never fix in the main session.
- Findings are not negotiable by rewording: a finding is closed by a commit
  or by the user deferring it, not by explaining it away.
- Never merge: no session merges anything in any run mode, nothing into `main` (the default branch); the runner lands. Never change `stage`.

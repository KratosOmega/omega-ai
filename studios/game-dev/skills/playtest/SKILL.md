---
name: playtest
description: Use when the user played the build and reports what failed — turns each failure into a bug, fixes it with a regression test, pushes, and comments on the PR.
---

# Playtest

**Announce at start:** "Using game-dev:playtest — filing and fixing what failed."

The user plays execute's play list and reports what failed, in their own
words. This command turns each failure into a bug, fixes it with a
regression test, and comments once on the PR. It never changes `stage`.

With no text after the command, print one example and stop:
`/game-dev:playtest dash clips the wall at full speed`.

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
  - Exit 1: no feature branch is recorded, or it is gone. Ask the user once
    which checkout to use, naming what was found: the `branch` value (or
    that none is recorded) and the `git worktree list` paths.
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

## 0. Checkout and stops

- **Enter the feature checkout**, and say which checkout.
- **Which feature.** After the lookup, check that the checkout holds the
  ledger of the feature `spec` names: `<checkout>/.studio/ledger/<slug>.md`
  (slug as `studio-state` derives it) exists. When it does not, `spec` and
  `branch` name different features, and every ledger line written here would
  land in a ledger named for the next feature. Stop with: "the studio
  pointers now name `<spec>`; the finished feature is `<branch>` — fix it on
  that branch by hand, or run this after `<spec>`'s finish".
- Stop at `stage execute`: the feature in progress has no PR and no play
  list yet.
- Every brief to a dispatched agent names the checkout's absolute path and
  tells the agent to work there: an agent starts in the session's working
  directory.
- On the default branch (**Default branch**, above), this command commits
  nothing until the user says where the fixes go: ask once, then dispatch a
  fixer only on that answer.
- Before the first fix dispatch, run `gh pr view --json state` on the
  branch. On `MERGED` or `CLOSED`, dispatch no fixer and push nothing:
  report the bugs and name `/game-dev:brainstorm` for a fix that must reach
  the base.
- Read the spec (`studio-state get spec`) and the plan
  (`studio-state get plan`), and the `P<k> Play:` and `B<n>` lines of the
  feature ledger (`studio-state show`).

Split the user's text into failures, one per distinct observed problem.
When two complaints may be one bug, treat them as one and say so.

## 1. Per failure

1. **File the bug.** Dispatch `game-dev:playtester`
   (`subagent_type: "game-dev:playtester"`) with the checkout's path, the
   failure text, the spec path, the plan path, the `P<k> Play:` and `B<n>`
   ledger lines, the next free bug number (one above the highest `B<n>` in
   the ledger), and "return the bug block; write no file". It returns the
   bug block, whose title ends `(from P<k>)` for a play-list item,
   `(from B<m>)` for a repeat of an earlier bug outside the list (`B<m>` is
   the first bug of that chain), or `(from report)` otherwise.
2. **Third failure.** Count the item's earlier failures in the ledger: for
   `(from P<k>)`, the `B` lines tagged `(from P<k>)`; for `(from B<m>)`, the
   line `B<m>` itself plus the lines tagged `(from B<m>)`. `(from report)`
   is never counted: it is a first report, shared by unrelated failures.
   When the count is already 2 or more, this is the third failure (or a
   later one): dispatch no fixer. After the other failures, suggest moving
   it to the plan's `## Backlog` with the user's reason, and move it only on
   the user's word.
3. **Fix.** Dispatch a fresh fixer: `game-dev:feel-tuner` when the bug
   concerns a feel target (latency, forgiveness, acceleration, timing,
   camera, feedback), otherwise `game-dev:gameplay-programmer`. The brief
   carries the checkout's path, the bug block and the spec section, and
   says: follow `systematic-debugging` before changing anything; when the
   bug's `Regression test` line says `unit`, write that test first
   (test-driven-development) and see it fail on the bug; fix; run
   `studio-test`; commit `fix(B<n>): …`; report the commit and the
   hypothesis (feel-tuner) or the root cause (gameplay-programmer).
   Feel fixes change one variable per hypothesis: a feel-tuner report that
   changed three values is sent back.
4. **Ledger.**
   `studio-state ledger "B<n> <title> — <commit, or backlog suggested>"`.

## 2. After the last failure

- Run `studio-test` once, fresh.
- Commit the ledger lines on the feature branch with the fixes and any
  `## Backlog` move: `git add .studio/ledger <plan path>`, then
  `git commit -m "chore(studio): ledger"`. Push when the branch tracks a
  remote (`git rev-parse --abbrev-ref @{u}` succeeds); never force-push.
- Post one `gh pr comment` on the branch's PR per run, listing each fix
  (`B<n> <title> — <commit>`), the play-list items to replay (each fixed
  `P<k>`, plus any item a fix touched), the parked items, and the
  `studio-test` summary line. With no PR or no remote, the fixes stay
  committed locally and the comment text is printed instead.
- Then **Leave the feature checkout** if §0 entered one.

## Rules

- Never write a script or a report file, ask a question per item, sign
  anything off, change `stage`, commit on the default branch, or merge.
- A fix without a regression test is allowed only when the bug's
  `Regression test` line says `playtest only`; the user's replay is then the
  test.
- Never fix in the main session: fixers fix.

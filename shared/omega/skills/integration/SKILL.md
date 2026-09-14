---
name: integration
description: Use when several related stories must land on main together rather than one at a time, or when story branches need a shared base other than main.
---

# Integration

**Announce at start:** "Using omega:integration <verb>."

Verbs: `start <slug> [goal…]`, `add <branch-or-ticket>`, `status`,
`finish`. No verb: print the four verbs and stop. `omega-mode` is on
`PATH` inside a studio; the session-start line names its path otherwise.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

## `start <slug> [goal…]`

1. `git fetch origin`.
2. `git switch -c integration/<slug> origin/main`.
3. Write `docs/integrations/<slug>.md`; the goal is the text after the
   slug, or the slug itself when none was given:

   ```markdown
   # Integration: <slug>

   Goal: <goal>

   | Story | Branch | Ticket | Depends on | Status | PR |
   |-------|--------|--------|------------|--------|----|
   ```

4. `git add docs/integrations/<slug>.md` and
   `git commit -m "docs(integration): start <slug>"`.
5. `git push -u origin integration/<slug>`.
6. `omega-mode set integration slug=<slug>` — the hook already did this
   when the command was typed; running it again is harmless.

## `add <branch-or-ticket>`

1. Ticket from the name: `KAN-<n>` → `KAN-<n>`; a leading `<n>-` or
   `issue-<n>` → `#<n>`; otherwise `-`.
2. Branch: the argument as given. When neither
   `git show-ref --verify --quiet refs/heads/<branch>` nor
   `git show-ref --verify --quiet refs/remotes/origin/<branch>` succeeds,
   `git branch <branch> integration/<slug>`.
3. Append the row `| <branch> | <branch> | <ticket> | - | planned | - |`.
   A dependency the user named goes into *Depends on* as the other story's
   branch.
4. On the integration branch: `git commit -m "docs(integration): add <branch>"`
   and `git push`.

## Story flow

Each story runs its studio's workflow on its own branch, unchanged. Its PR
targets `integration/<slug>`: `omega:local-merge` reads the mode and sets
the base, and lands the story with its usual procedure. When a story's
implementation starts, set its row to `in progress`; after its merge, set
the row to `merged` with the PR number, commit
`docs(integration): <branch> merged (#<n>)` on the integration branch, and
push.

## `status`

Print the table; `gh pr list --base integration/<slug>`; and, for every row
not `merged`, `git rev-list --count integration/<slug>..<branch>` — the
commits not yet on the integration branch.

## `finish`

1. Refuse while any row's status is not `merged`: print those rows and
   stop.
2. `git fetch origin`. When
   `git merge-base --is-ancestor origin/main integration/<slug>` fails,
   `git merge origin/main`, resolve conflicts on the integration branch,
   and run the tests.
3. Run the local CI procedure — `omega:local-merge` §1 and §2.
4. `gh pr create --fill --base main --head integration/<slug>` when no PR
   exists for the branch.
5. Land it through `omega:local-merge` §4 and §5, confirmation included.
   When `omega-mode show` lists `autopilot`, the PR stays open and `finish`
   stops here, saying so.
6. After the merge: `git push origin --delete integration/<slug>`,
   `git switch main`, `git branch -D integration/<slug>`, and
   `omega-mode clear integration`.

## What this changes, and what it never changes

Changes: where story branches merge, and what "done" means for the set.
Never changes: how each story is designed, planned, implemented or
reviewed — each runs its studio's workflow on its own branch.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| `finish` with a `planned` row "because it was never started" | Remove the row with the user, or merge the story. Refuse otherwise. |
| A story PR whose base is `main` | The base is `integration/<slug>` while the mode is set. |
| Cutting the integration branch from local `main` | `origin/main`, after `git fetch`. |
| Forgetting the row after a story lands | Status `merged`, PR number, committed on the integration branch. |

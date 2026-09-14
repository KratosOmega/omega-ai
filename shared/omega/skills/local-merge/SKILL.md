---
name: local-merge
description: Use when GitHub Actions is unavailable, rate-limited or out of minutes and a branch has to be merged on the strength of checks run locally.
---

# Local Merge

**Announce at start:** "Using omega:local-merge."

Run first: `omega-mode set local-merge` — `omega-mode clear local-merge`
for `off`. `omega-mode` is on `PATH` inside a studio; the session-start
line names its path otherwise. The hook already set the mode when the
command was typed; running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

While `local-merge` is set, any step that would wait for GitHub checks or
hand the merge to the user — a studio's ship stage,
`superpowers:finishing-a-development-branch` when installed, the user
saying "merge it" — follows this procedure instead.

## 1. Find the local CI procedure

The first that applies, in this order:

1. The project's docs — `CLAUDE.md`, `CONTRIBUTING*`, `docs/**` — for a
   section naming local CI or a manual merge procedure. Run the command it
   states.
2. Convention: `make ci`, `make test`, `make check`, `scripts/ci*.sh`,
   `tests/run_all.sh`, `npm test`, `cargo test` — the first whose target
   or file exists.
3. Neither: stop and ask the user what runs the checks.

Never merge unverified.

## 2. Run it

Show the last twenty lines of output and the exit code. `exit 0` is
required. On any other value, report the failure and stop: no merge, and
no retry until a fix has been committed.

## 3. The PR

`gh pr view --json number,url,baseRefName` on the current branch. When
there is none: `gh pr create --fill --base <base>`, adding `--draft` when
`omega-mode show` lists `autopilot`. The base is `integration/<slug>` when
`omega-mode show` has an `integration slug=<slug>` line, else the
repository's default branch (`gh repo view --json defaultBranchRef`).

## 4. Strategy

1. The project's docs, when they state one.
2. Else the shape of the last five merged PRs:
   `gh api "repos/<owner>/<repo>/pulls?state=closed&per_page=10"`, keep
   those with a `merged_at`, take each `merge_commit_sha`, and read
   `gh api repos/<owner>/<repo>/commits/<sha>` — two `parents` is a merge
   commit, one is a squash. Majority wins.
3. Else squash.

For reference: `phoenix` squashes; `omega-ai` merges.

## 5. Confirm and merge

Ask once, showing the green result and the strategy. On yes:

```sh
gh pr merge <n> --admin --<strategy> --delete-branch
```

When `omega-mode show` lists `autopilot`, skip this step: the PR stays
open, the CI result goes into `gh pr comment <n> --body "<result>"`, and
the morning report says so.

Then `git fetch origin` and verify the merge landed:
`git log --oneline -1 origin/<base>` names the merge or squash commit.
Hand back to the invoking skill's own cleanup — worktree removal, its
`stage` write, its progress update.

## What this changes, and what it never changes

Changes: which checks gate a merge, and who performs it. Never changes:
the invoking skill's verification before the merge, its state writes after
it, the tests themselves.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| "The checks are flaky, merge anyway" | `exit 0`, or no merge. |
| `git push origin main` | `gh pr merge --admin` keeps the PR trail. |
| Squash because it is common | Read the docs, then the history. |
| Merging under `autopilot` | Comment on the PR and leave it open. |
| Merging into `main` while an integration branch is set | The base is `integration/<slug>`. |

# Phoenix: the LFS post-checkout hook breaks a long rebase

Rebasing a long branch (70+ commits) onto `origin/main` fails with
`error: Your local changes to the following files would be overwritten by merge`
naming files nobody touched — while `git status` reports a **clean tree**. The
failure lands at a **different commit and different files on every attempt**
(observed 2/71, then 25/71), which is the tell: a race, not a content conflict.

**Cause:** the Git LFS `post-checkout` hook fires on every one of the replay's
checkouts and rewrites files underneath the rebase.

**Fix:** disable hooks for the rebase only —

    git -c core.hooksPath=/dev/null rebase origin/main

Then the rebase reaches the genuine conflicts, if any. Run `git lfs checkout`
afterwards if pointer files need smudging.

**Why it matters beyond the rebase:** `.github/scripts/merge.sh` runs
`git rebase origin/main` internally (`rebase_onto_base`), so it hits the same
race and reports *"rebase onto origin/main hit a conflict"* — pointing at
entirely the wrong cause. Do not go looking for a content conflict that isn't
there.

**Companion fact, same session:** `resources/i18n/*.translation` are GENERATED
from `ui_strings.csv` by Godot's csv_translation importer, and they conflict as
binaries on any rebase that crosses an i18n change. Resolve by taking either
side, then `touch resources/i18n/ui_strings.csv` and
`--headless --import .` to regenerate from the merged CSV — never by hand-picking
a binary. The gate's own i18n step (step 1d) checks exactly this, so drift
cannot slip through silently.

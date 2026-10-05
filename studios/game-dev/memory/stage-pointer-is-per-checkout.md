---
name: stage-pointer-is-per-checkout
description: Each checkout has its own stage pointer — hand a story to its worktree with studio-state handoff, never --force a refused story switch without the user
metadata:
  type: feedback
---

Each checkout has its own stage pointer (`.studio/STATE.md`); a pointer-less worktree has no story, and never reads
another checkout's.

- A story planned in the main checkout moves to its execute worktree by `studio-state handoff`. To continue one from a
  worktree made by hand, run `studio-state take <spec>` there.
- Review, playtest and retro from the main checkout find the story through `studio-state stories`.
- Exit 4 means a story switch in this checkout: never `--force` it without the user.
- The SDD ledger (`.superpowers/sdd/<plan>/progress.md`) remains the per-feature recovery record.

**Why:** until #42 (2026-10-05) every worktree resolved the main checkout's pointer, so a second story's `set spec`
clobbered the first, and a pre-#42 `studio-state` run by path from a stale worktree still does.
**How to apply:** start a new story in its own worktree; on exit 4 stop and ask, offering to finish or reset the
story, or to use `EnterWorktree`; rebase a stale dev worktree before trusting its `studio-state`.

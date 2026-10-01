---
name: progress-entry-lands-with-the-story-pr
description: Write the PROGRESS.md entry and the playtest results into the story PR before merge.sh — a post-merge docs entry costs a whole extra 25-minute gate run
metadata:
  type: feedback
---

In a repo whose only merge path is a full local gate (`merge.sh`, ~25 min), every docs commit that lands after the
story's merge is a second gate run. The PROGRESS entry and the human playtest's results belong in the story PR's
last commit, not in a follow-up.

**Why:** KAN-1295 (2026-09-18): the story merged as #1660, the producer then wrote the PROGRESS entry, and the human
played P1–P6 minutes later — two docs follow-ups (#1661 and the pass update), each a full gate, for ~70 changed lines
of prose. The previous story avoided this by committing PROGRESS before its merge.
**How to apply:** `/game-dev:execute`'s finish already commits the producer's entry before it opens the PR — keep it
there, never move it after `merge.sh`; when the visual playtest is deferred to the human, hold the merge until they have played if they are at the
keyboard (one AskUserQuestion), and only defer past the merge when they are not.

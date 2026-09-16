---
name: ship
description: Use when a playtest is signed off — verifies, finishes the branch, and updates PROGRESS.md.
---

# Ship

**Announce at start:** "Using game-dev:ship."

## 0. Preconditions

- The ledger (`studio-state show`) has a `playtest signed off <path>` line
  whose path equals `studio-state get last_playtest`. If not, stop:
  "Playtest not signed off — run `/game-dev:playtest`." The user may sign
  off now in one word; then record the ledger line and continue.
- Run `studio-state set stage ship`.

## 1. Verify — evidence, not assertion

Invoke `superpowers:verification-before-completion` and apply it to these
three commands, each run fresh, output shown to the user, exit code read:

1. `studio-test` — must exit 0.
2. `studio-lint` — exit 0, or exit 3 with "gdtoolkit not installed" noted;
   exit 1 stops the ship until the findings are fixed or the user waives
   them in writing.
3. `studio-run --seconds 10` — must exit 0.

No claim of "tests pass" without the summary line from this run in your
message.

## 2. Finish the branch

Invoke `superpowers:finishing-a-development-branch`. It presents the
options (merge locally, open a PR, keep the branch); the user chooses. The
PR body, when a PR is opened, is the spec's `## Purpose` paragraph, the
`## Acceptance criteria` as a checklist, and a link to the playtest report.
Record the result as `<ref>`: the merge commit, the PR URL, or the branch
name.

## 3. Progress

Dispatch `game-dev:producer` (`subagent_type: "game-dev:producer"`) with
the plan path, the playtest report path, the `<ref>`, and
`docs/game-dev/PROGRESS.md`. It adds the dated log entry and reports
exactly one of `gate met: <current> → <next>` or `gate not met: …`.

- `gate met`: `studio-state set milestone <next>` and say so in one line.
- `gate not met`: repeat its missing list to the user; the milestone stays.

## 4. State and hand-off

- `studio-state ledger "shipped <ref>"`.
- `studio-state set stage retro`.
- Tell the user the next command is `/game-dev:retro`. Do not invoke it
  yourself.

## Rules

- Merging, pushing and publishing are side effects outside the worktree:
  the finishing skill asks, and you do not pre-empt its answer.
- Never edit `PROGRESS.md` in the main session; the producer owns it.

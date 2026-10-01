---
name: context-doc-at-budget-plan-the-condensation
description: When a claude_context file is at its line budget, the plan names which entry gives up a line and the implementer proves no guarantee was dropped — otherwise the edit costs fix rounds
metadata:
  type: feedback
---

A context-doc task on a file at budget is not "add a sentence": it is a condensation, and the plan must name the entry
that surrenders the line and the facts it must keep; the implementer's report quotes before/after and lists every clause
removed, marking each as decoration or a guarantee.

**Why:** KAN-1295 (2026-09-18), Task 7: `23_abilities.md` was at 155/155. The implementer re-wrapped to fit and dropped
"only", "unrotated" and "decayed by `physics_update` (not `stop_moving()`)" — three guarantees — under a "cut adjectives
first" instruction that did not cover facts; it took two fix rounds plus a final-review item to restore them, and a
brute-force wrap search to prove the original three-line target was impossible. The doc gate (`test_context_docs.gd`)
cannot see a lost guarantee, only a lost line budget.
**How to apply:** in `/game-dev:plan`, when `wc -l` equals the budget, write the condensation target into the task (which
bullet, which filler words), forbid dropping any clause with a backticked identifier or a negative ("not X"), and ask
for the before/after quote in the report; measure columns in codepoints (Python `len()`), because macOS `awk length`
counts bytes and every em-dash is a false positive.

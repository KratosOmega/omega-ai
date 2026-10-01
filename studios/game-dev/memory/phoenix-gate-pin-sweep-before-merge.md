---
name: phoenix-gate-pin-sweep-before-merge
description: Phoenix's merge gate has count and line-anchor pins that redden on mechanical drift — sweep them before the first merge.sh run, each run costs 15–20 min
metadata:
  type: project
---

Phoenix's local gate (`.github/scripts/merge.sh`) carries pins that move with any content or table edit, not just
the record-count guards the `content-record-gate-sweep` skill enumerates: the `st.get()` call-count pin in
`web-tools/tests/.../ability-schema.test.ts`, and the UI catalog's `MenuMetrics` line anchors
(`catalog-integrity.test.ts`) — a line added to `scripts/ui/menu/menu_metrics.gd` shifts every anchor below it by
the same amount, and the fix is bumping all of them together plus `cd web-tools && npm run gen:ui-ref`.

**Why:** Knight Stomp (KAN-1295, 2026-09-18) needed four `merge.sh` runs: run 1 red on `catalog-integrity`
(three Slam colour-row lines moved six anchors by +3, commit `9aad9151b`), run 2 a jsdom intermittent, run 3 the
wall-clock flake ([[wall-clock-timing-tests-min-of-two]]). Only the last was a test defect; the first was drift a
pre-sweep catches in seconds.
**How to apply:** before the first gate run on a story that adds a cast type, a colour row, a record or any line to
`menu_metrics.gd`/`forge_theme.gd`: run the `content-record-gate-sweep` skill, grep the `st.get` pin, and run
`npm run gen:ui-ref` + the catalog-integrity test alone. Budget one fix round for pins in the plan's gate task.

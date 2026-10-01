---
name: preview-from-real-assets-before-approval
description: For a visual feature, build the approval preview from the real assets and the real runtime formulas so the user tunes the numbers before implementation, not after the merge
metadata:
  type: feedback
---

When a spec's deliverable is something the player sees, the brainstorm's approval page carries an interactive
preview built from the shipped assets (the rig frames, the sprite sheet) and the runtime's own equations (the shader's
front/push curves, the camera's `trauma² × maxPx` rounding) — with the spec's tuning knobs as live controls whose
values map one-to-one onto web-tools fields.

**Why:** Knight Stomp impact VFX (KAN-1295, PR #1660, 2026-09-18): the user opened the emulated preview, moved
`base.scale` to 4.0 and `base.offsetPx` to −20, and approved with those values; the spec, the content and the tests
took them verbatim, and the six visual playtest items passed first time on the merged code — no post-merge tuning
round, which is the round that costs a second gate.
**How to apply:** in `/game-dev:brainstorm` for anything visual, spend the artifact on a canvas emulation from the real
files (never a mock drawing), expose every Tuning-knob row as a control, and read the approved knob values back into the
spec before writing the plan. The preview also exposes what the text hides (here: the sheet at its authored 0.42 scale
was ~15 px, and `finish` lets the burst outlive the cast).

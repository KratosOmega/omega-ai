---
name: phoenix-shake-impulse-floor
description: Phoenix camera shake rounds to whole pixels from trauma² × 4 px, so any preset impulse below ~0.35 is invisible — seed a felt shake from 0.5, never from player_jump_land's 0.04
metadata:
  type: project
---

`CameraShake` draws its jitter from `trauma² × maxPx` (maxPx 4) and quantises to whole pixels, so a preset's
`impulse` below ~0.35 produces 0 px on every frame: `player_jump_land` (0.04) is effectively no shake, `bomb_explosion`
(0.5) is a 1 px peak decaying in ~80 ms — the "felt, not seen" value.

**Why:** KAN-1295 (2026-09-18): the brainstorm offered the jump-landing preset as the seed for a faint stomp shake;
reading `camera_shake.gd` before the demo showed 0.04² × 4 = 0.0064 px. The spec was corrected to 0.5 before approval
and the preview showed the rounding live (the knob stops moving below ~0.35).
**How to apply:** when a spec seeds a shake preset, compute `impulse² × 4` first; anything meant to be perceived starts
at 0.5 (a 1 px peak) or higher, and a preset in the 0.0x range is a "no shake" row whatever its description says.
Related: [[preview-from-real-assets-before-approval]].

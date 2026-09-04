---
name: game-feel
description: Use when controls feel unresponsive, floaty, or unsatisfying — a diagnostic order for input, movement, camera, and feedback before adding effects.
---

# Game Feel

Feel problems are usually input problems wearing an effects costume. Work in
this order and change one variable at a time.

**1. Input latency.** Measure frames from press to first visible change. Handle
movement input in `_physics_process`, not in a signal chain that adds a frame.

**2. Forgiveness windows.** Add coyote time (roughly 0.1s of jump grace after
leaving a ledge) and input buffering (roughly 0.1s of remembered press before
landing). Most "unresponsive" jumps are unforgiving ones.

**3. Asymmetric acceleration.** Separate acceleration and deceleration values.
Fast stop with slower start reads as crisp; the reverse reads as ice.

**4. Gravity asymmetry.** Higher gravity on the way down than on the way up
makes a jump feel deliberate rather than floaty.

**5. Camera.** Deadzone, follow lag, and look-ahead in the direction of travel.
Tune these before adding shake — shake on a badly-tuned camera reads as noise.

**6. Feedback.** Hit-stop of two to four frames, particles, and audio last.

State the perceptual change you expect before each edit, then confirm it.

---
name: core-loop-design
description: Use when designing or repairing a game's core loop — the ten-second cycle everything else is built on.
---

# Core Loop Design

The core loop is the shortest cycle the player repeats voluntarily. Get it wrong
and no amount of content rescues the game.

Define it as: **perceive → decide → act → feedback → change in state.**

Test the loop against these questions:

- Is there a real decision, or only execution? A loop with no decision is a
  chore.
- Does the feedback arrive fast enough to teach? Feedback later than about 300ms
  is not felt as caused by the action.
- Does the state change alter the next decision? If the loop returns to an
  identical state, it is a treadmill.
- Would the player repeat it with no reward attached? If not, the reward is
  carrying the loop, and rewards run out.

Prototype the loop with placeholder art before any content is built. If the
grey-box version is not compelling, fix the loop, not the art.

# 2D Game Development Studio

This studio is for building 2D games. The default engine is Godot 4.x; design
and pipeline work that does not depend on an engine is engine-agnostic and
should stay that way.

## Architecture

- Composition over inheritance. A behavior belongs in its own node or component
  that can be attached, not in a deepening base class.
- Decouple systems with signals: a child reports up with a signal, a parent
  calls down. The global `EventBus` carries only cross-cutting events that have
  no ownership path. A system should not hold a reference to another system
  just to notify it.
- Keep data in `Resource` files, not in code. Items, enemies, levels, and tuning
  values are data a designer can edit without a programmer.
- Model state explicitly with a state machine. Distinguish the gameplay state
  machine from the animation state machine; they are not the same object.
- Keep scenes cohesive. A scene that needs a comment to explain what it is
  should be split.

## Working method

- Reach for the `godot-prompter` skills before writing Godot code — they encode
  the engine's own conventions.
- Profile before optimizing. Godot's profiler names the frame cost; guesses do
  not.
- Write tests with the configured test framework (`tests` in
  `.studio/config.json`; GUT by default) for logic that is not visual.
- When a request would lead to an anti-pattern, say so and propose the standard
  alternative instead of silently implementing it.

## 2D specifics

- Use a fixed base resolution and an explicit stretch mode; decide this before
  building UI, not after.
- Keep art on a consistent pixels-per-unit; mixing scales makes camera and
  physics tuning unrepeatable.
- Prefer TileMapLayer for level geometry, and keep collision authored on the
  tileset rather than hand-placed per level.

## Decision trade-offs

Weigh each option's Gains and Costs (Decision Questions, above) the way a game
studio does:

- **Gains** — player experience (feel, readability, responsiveness), frame
  budget on the target hardware, designer iteration speed (tunable in a
  `Resource` without a programmer), how well it scales to the next ten
  enemies, levels or abilities, and future debt avoided.
- **Costs** — production time and tokens, risk to the current milestone gate,
  frame or memory budget spent, art and content pipeline work, playtest risk
  (feel judged only by playing), and debt taken on (a rewrite when the content
  grows).

Name the milestone gate when cutting: an option can be right for the prototype
and wrong for the vertical slice, and the description says which.

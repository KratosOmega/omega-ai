# 2D Game Development Profile

This profile is for building 2D games. The default engine is Godot 4.x; design
and pipeline work that does not depend on an engine is engine-agnostic and
should stay that way.

## Architecture

- Composition over inheritance. A behavior belongs in its own node or component
  that can be attached, not in a deepening base class.
- Decouple systems with signals and a global event bus. A system should not hold
  a reference to another system just to notify it.
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
- Write tests with GUT or gdUnit4 for logic that is not visual.
- When a request would lead to an anti-pattern, say so and propose the standard
  alternative instead of silently implementing it.

## 2D specifics

- Use a fixed base resolution and an explicit stretch mode; decide this before
  building UI, not after.
- Keep art on a consistent pixels-per-unit; mixing scales makes camera and
  physics tuning unrepeatable.
- Prefer TileMapLayer for level geometry, and keep collision authored on the
  tileset rather than hand-placed per level.

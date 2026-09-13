# Game Studio Plan 3 — Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a new game project go from an empty directory to its first signed-off playtest using only studio commands — a runnable Godot 4 2D template, the `studio-scaffold` verb and `game-dev:scaffold` skill that materialise it, the seven domain skills at their final names, the `PROGRESS.md` milestone-gate conventions, `general` studio parity, and pressure tests for every skill.

**Architecture:** The template is a complete Godot project checked into `studios/game-dev/engines/godot/template/`; `bin/studio-scaffold` copies it, names it, clones the pinned GUT release beside it, and hands `.studio/STATE.md` to `studio-state init` so the state format has one writer. Domain skills are knowledge (`gdd`, `core-loop`, `game-feel`, `sprite-pipeline`, `vertical-slice`, `tuning-data`, `milestone-gates`) that stage skills and role agents call by name; `milestone-gates` is also the reference for the `PROGRESS.md` format the template seeds and `ship` updates. Skill behaviour is verified by pressure scenarios, not shell tests; everything else stays under the POSIX `sh` harness.

**Tech Stack:** POSIX `sh`, the existing `tests/assert.sh` harness, Godot 4.6 text formats (`project.godot`, `.tscn`, `.tres`), GDScript 2 with static typing, GUT 9.6.1 (`gut_cmdln.gd`), gdtoolkit config (`.gdlintrc`), Markdown skills with `SKILL.md` frontmatter.

**Spec:** `docs/game-dev/specs/2026-09-13-game-studio-design.md` — this plan implements its "Delivery — Plan 3 — Content" scope: the sections "Scaffold template", "`/game-dev:scaffold`", "Domain skills", "Migration of existing content", "Extensibility seams" (the dimension convention), "Docs layout and memory" (a game project's `PROGRESS.md`), "Testing the framework" cases 9 and 10, the `general` studio sentence under "Renames", and the closing paragraph of "Testing the framework" (pressure scenarios).

## Global Constraints

Copied from the spec; every task's requirements include these.

- POSIX `sh` only for every script and test; no bash-isms; no new dependencies. `git` is used only by `studio-scaffold` to clone GUT and by one test fixture, and both degrade gracefully when it is absent.
- `bin/` exit codes: `studio-scaffold` — 0 ok · 1 target exists and is not empty (also bad usage and a missing template). `studio-test` — 0 all passed · 1 failures · 2 engine not found · 3 test framework not installed. `studio-run` — 0 clean · 1 script errors · 2 engine not found.
- Every `bin/` script finds the studio root through `$OMEGA_STUDIO_ROOT` (set by the shim) and, when it is unset, by resolving its own location; it reads the engine from `.studio/config.json` in the project, falling back to `studio.json`.
- The template is a runnable Godot 4 2D project: base resolution 640×360, stretch mode `canvas_items`, aspect `keep`, default texture filter Nearest, the `EventBus` autoload registered, `src/` by feature, `src/autoloads/event_bus.gd` with typed signals, `src/player/` with a minimal `CharacterBody2D` and a state-machine skeleton, `resources/tuning/` with one example `Resource` and its `.tres`, `tests/unit/test_smoke.gd`, `.studio/config.json`, `.studio/.gitignore` for `reports/`, `docs/game-dev/{specs,plans,playtests,artifacts}/.gitkeep`, `docs/game-dev/PROGRESS.md` seeded with the five milestone gates, a project `CLAUDE.md`, a Godot `.gitignore`, `.gdlintrc`.
- GUT is not vendored: `studio-scaffold` clones the pinned release into `addons/gut/` when the network is available and prints the manual step otherwise. `studio-test` exits 3 until it is present.
- Import settings and `project.godot` are code — never git-ignored.
- `.studio/STATE.md` is written only through `studio-state` (`init | show | get | set | ledger`); `stage` ∈ {`idle`, `brainstorm`, `plan`, `execute`, `review`, `playtest`, `ship`, `retro`}; `milestone` ∈ {`prototype`, `vertical-slice`, `alpha`, `beta`, `gold`}.
- Skill frontmatter: `name` equals the skill directory; `description` starts with "Use when". Every `superpowers:` or `godot-prompter:` name in `skills/`, `agents/` or `engines/` appears in `requires.txt` (lint `tests/studio_test.sh`).
- Domain skill final names: `gdd`, `core-loop`, `game-feel`, `sprite-pipeline`, `vertical-slice`, `tuning-data`, `milestone-gates`. Dimension convention: a domain skill with dimension-specific content carries a `## 2D` section now; `## 3D` is added beside it later; `.studio/config.json` `dimension` selects which section applies. New 3D-only skills get a `3d-` prefix.
- Milestone gates, in order: prototype → vertical-slice → alpha → beta → gold. A game project's `docs/game-dev/PROGRESS.md` opens with the gate table and the current gate.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never push.

## Assumes from Plan 2

Plan 2 is written concurrently and is not on disk. This plan relies on the spec's contracts for what Plan 2 delivers, and on these specific readings. Reconcile before executing.

1. **Bin verbs exist at `studios/game-dev/bin/studio-test`, `studio-run`, `studio-lint`** with the spec's arguments and exit codes, and dispatch to `studios/game-dev/engines/godot/{test.sh,run.sh,lint.sh}`. `engines/godot/resolve.sh` prints the Godot binary path or exits 2.
2. **Engine directory mapping.** `studio.json`/`config.json` say `engine: godot4`; the adapter directory is `engines/godot/`. This plan maps `godot4` and `godot` → `godot`, and any other value → itself. Plan 2's verbs must use the same mapping.
3. **Root resolution.** Each verb resolves the studio root as `$OMEGA_STUDIO_ROOT`, else the directory above the script's real (symlink-resolved) location. `studio-scaffold` inlines the same function; there is no shared library under `bin/`.
4. **First-run import.** A Godot project that the editor has never opened has no `.godot/global_script_class_cache.cfg`, and `class_name` lookups fail at parse time. This plan's engine-dependent test runs `"$GODOT" --headless --path "$P" --import` before `studio-test` / `studio-run`. Plan 2's `test.sh` and `run.sh` should do the same when `.godot/` is absent; if they do, the test's own import is a harmless no-op.
5. **GUT install command in `engines/godot/GUIDE.md`.** `studio-test` exit 3 prints the command from `GUIDE.md`. This plan's scaffold prints the same shape: `git clone --depth 1 --branch v9.6.1 https://github.com/bitwes/Gut.git /tmp/gut && mv /tmp/gut/addons/gut <project>/addons/gut && rm -rf /tmp/gut`. Pin both to `v9.6.1`.
6. **Role agents** exist as `agents/{game-designer,level-designer,architect,gameplay-programmer,tech-artist,feel-tuner,ui-designer,producer,playtester,reviewer}.md`, and their "May call" lists use the spec's *final* domain-skill names (`game-dev:gdd`, `game-dev:core-loop`, `game-dev:sprite-pipeline`, `game-dev:game-feel`, `game-dev:vertical-slice`, `game-dev:milestone-gates`). Those names resolve to nothing until Task 5 of this plan makes them real; the reference lint only checks `superpowers:` and `godot-prompter:` names, so this is not a test failure in between. If Plan 2 used the *old* names instead, Task 5's grep step catches and fixes them.
7. **`skills/ship/SKILL.md`** has a step that updates `docs/game-dev/PROGRESS.md` and dispatches `game-dev:producer`. Task 8 adds one sentence to that step; it locates the step by grepping for `PROGRESS.md` because the exact line is Plan 2's.
8. **`hooks/bootstrap.md`** still carries the Plan 1 line `Stages are installed in phases. …` unless Plan 2 removed it; Task 8 removes it if present, because after this plan every stage exists.
9. **`README.md` `## Use` section** may have been extended by Plan 2 with the four quality-loop stages. Task 11 replaces the whole section, so the exact Plan 2 wording does not matter.
10. **`tests/run_all.sh`** may list Plan 2 test files. Task 1 appends `scaffold_test.sh` to the `for f in` list without removing anything.

## File structure

| Path | Responsibility |
|------|----------------|
| `studios/game-dev/engines/godot/template/` | The runnable Godot 4 2D project the scaffold copies. Every file listed in Task 1. |
| `studios/game-dev/bin/studio-scaffold` | Copies the template, names the project, clones GUT, runs `studio-state init`, lists the tree. |
| `studios/game-dev/skills/scaffold/SKILL.md` | The `game-dev:scaffold` stage skill. |
| `studios/game-dev/skills/{gdd,core-loop,sprite-pipeline,game-feel}/SKILL.md` | The four migrated domain skills at their final names. |
| `studios/game-dev/skills/{vertical-slice,tuning-data,milestone-gates}/SKILL.md` | The three new domain skills; `milestone-gates` is the `PROGRESS.md` reference. |
| `studios/game-dev/skills/brainstorm/SKILL.md`, `skills/studio/SKILL.md`, `skills/ship/SKILL.md`, `hooks/bootstrap.md` | One-line reference updates. |
| `studios/general/memory/MEMORY.md` | Seed memory so the second studio exercises the memory path. |
| `tests/scaffold_test.sh` | Template integrity, scaffold behaviour, engine-dependent boot. |
| `tests/install_test.sh` | Adds `test_general_studio_parity`. |
| `tests/run_all.sh` | Runs `scaffold_test.sh`. |
| `docs/game-dev/skill-tests/` | `README.md`, `RESULTS.md`, one scenario per skill. |
| `README.md`, `docs/game-dev/PROGRESS.md` | Documentation and the Plan 3 status. |

---

### Task 1: The template project

**Files:**
- Create: everything under `studios/game-dev/engines/godot/template/` listed in Step 3
- Create: `tests/scaffold_test.sh` (the `test_template_files` case; later tasks add more)
- Modify: `tests/run_all.sh`

**Interfaces:**
- Consumes: nothing from the repository.
- Produces: the template tree Task 2 copies; the names `PlayerTuning`, `Player`, `StateMachine`, `PlayerState`, the `EventBus` signals `player_jumped`, `player_landed`, `level_started(level_path)`; the scene paths `res://scenes/main.tscn` and `res://levels/test.tscn`; the `{{DATE}}` token in `docs/game-dev/PROGRESS.md` and the literal `# Template` title lines in `PROGRESS.md` and `CLAUDE.md` that Task 2 substitutes.

- [ ] **Step 1: Write the failing test `tests/scaffold_test.sh`**

```sh
#!/bin/sh
# Template integrity, studio-scaffold behaviour, and — when a Godot binary
# is found — a headless boot of the template. Nothing here touches the
# network: the GUT clone is pointed at a local fixture or an unreachable path.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO_DIR="$REPO_ROOT/studios/game-dev"
TEMPLATE="$STUDIO_DIR/engines/godot/template"
SCAFFOLD="$STUDIO_DIR/bin/studio-scaffold"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OMEGA_STUDIO_ROOT="$STUDIO_DIR"
export OMEGA_STUDIO_ROOT

# An unreachable clone source, so a test that does not want GUT never
# touches the network.
OFFLINE_GUT="file://$TMP/no-such-repo.git"

test_template_files() {
  for f in project.godot .gitignore .gdlintrc CLAUDE.md \
           src/autoloads/event_bus.gd \
           src/player/player.gd src/player/player.tscn src/player/player_tuning.gd \
           src/player/state_machine.gd src/player/state.gd \
           src/player/states/grounded.gd src/player/states/airborne.gd \
           resources/tuning/player_tuning.tres \
           levels/test.tscn levels/test_level.gd scenes/main.tscn \
           tests/unit/test_smoke.gd tests/unit/test_player_tuning.gd \
           .studio/config.json .studio/.gitignore \
           docs/game-dev/PROGRESS.md docs/game-dev/specs/.gitkeep docs/game-dev/plans/.gitkeep \
           docs/game-dev/playtests/.gitkeep docs/game-dev/artifacts/.gitkeep; do
    assert_file "$TEMPLATE/$f" "template has $f"
  done
  assert_missing "$TEMPLATE/.studio/STATE.md" "template carries no STATE.md — studio-state init writes it"
  assert_missing "$TEMPLATE/addons/gut" "template does not vendor GUT"
  assert_missing "$TEMPLATE/.godot" "template carries no editor cache"
  assert_contains "$TEMPLATE/project.godot" '^config_version=5' "project.godot is a Godot 4 file"
  assert_contains "$TEMPLATE/project.godot" '^config/name="Template"' "project is named Template until scaffolded"
  assert_contains "$TEMPLATE/project.godot" '^run/main_scene="res://scenes/main.tscn"' "main scene is set"
  assert_contains "$TEMPLATE/project.godot" '^EventBus="\*res://src/autoloads/event_bus.gd"' "EventBus autoload is registered"
  assert_contains "$TEMPLATE/project.godot" '^window/size/viewport_width=640' "base width is 640"
  assert_contains "$TEMPLATE/project.godot" '^window/size/viewport_height=360' "base height is 360"
  assert_contains "$TEMPLATE/project.godot" '^window/stretch/mode="canvas_items"' "stretch mode is canvas_items"
  assert_contains "$TEMPLATE/project.godot" '^window/stretch/aspect="keep"' "aspect is keep"
  assert_contains "$TEMPLATE/project.godot" '^textures/canvas_textures/default_texture_filter=0' "default filter is Nearest"
  assert_contains "$TEMPLATE/project.godot" '^move_left=' "input map defines move_left"
  assert_contains "$TEMPLATE/project.godot" '^move_right=' "input map defines move_right"
  assert_contains "$TEMPLATE/project.godot" '^jump=' "input map defines jump"
  assert_contains "$TEMPLATE/.studio/config.json" '"engine"[[:space:]]*:[[:space:]]*"godot4"' "config.json declares the engine"
  assert_contains "$TEMPLATE/.studio/config.json" '"dimension"[[:space:]]*:[[:space:]]*"2d"' "config.json declares 2d"
  assert_contains "$TEMPLATE/.studio/config.json" '"language"[[:space:]]*:[[:space:]]*"gdscript"' "config.json declares gdscript"
  assert_contains "$TEMPLATE/.studio/config.json" '"tests"[[:space:]]*:[[:space:]]*"gut"' "config.json declares gut"
  assert_contains "$TEMPLATE/.studio/.gitignore" '^reports/' ".studio ignores reports/"
  assert_contains "$TEMPLATE/.gitignore" '^\.godot/' "project ignores .godot/"
  assert_not_contains "$TEMPLATE/.gitignore" '^\*\.import' "import settings are versioned, never ignored"
  assert_contains "$TEMPLATE/docs/game-dev/PROGRESS.md" '^\*\*Current gate:\*\* prototype' "PROGRESS.md starts at the prototype gate"
  assert_contains "$TEMPLATE/docs/game-dev/PROGRESS.md" '^| gold ' "PROGRESS.md lists the gold gate"
  assert_contains "$TEMPLATE/docs/game-dev/PROGRESS.md" '{{DATE}}' "PROGRESS.md carries the date token the scaffold fills"
  assert_contains "$TEMPLATE/CLAUDE.md" '^# Template$' "CLAUDE.md title is the token the scaffold renames"
  assert_contains "$TEMPLATE/tests/unit/test_smoke.gd" '^extends GutTest' "smoke test is a GUT test"
  assert_contains "$TEMPLATE/src/player/player_tuning.gd" '^class_name PlayerTuning' "tuning resource has a class name"
  assert_contains "$TEMPLATE/src/player/player.gd" '_physics_process' "player reads input in _physics_process"
  assert_not_contains "$TEMPLATE/src/player/player.gd" '^[[:space:]]*var [a-z_]* *:= *[0-9]' "player.gd carries no tuning literals"
  # The template ships no binary assets on purpose: a headless run then needs
  # no prior import step, and nothing in the repository is opaque to review.
  n="$(find "$TEMPLATE" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.wav' -o -name '*.ogg' -o -name '*.import' \) | wc -l | tr -d ' ')"
  assert_eq "0" "$n" "template ships no imported assets"
}

run_tests test_template_files
```

Add the file to `tests/run_all.sh`: in the `for f in` list, append `"$DIR"/scaffold_test.sh` after the last existing entry (keep every entry Plans 1 and 2 put there). The line then ends with:

```sh
         … "$DIR"/scaffold_test.sh; do
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/scaffold_test.sh`
Expected: every `template has …` assertion FAILs (`no regular file`), and the `assert_contains` checks fail with `missing … in …`.

- [ ] **Step 3: Write the template files**

All paths below are under `studios/game-dev/engines/godot/template/`.

`project.godot`:

```ini
; Engine configuration file.
; Generated by the omega-ai game-dev studio template. Edit through the editor
; or by hand; this file is code and is committed.

config_version=5

[application]

config/name="Template"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")

[autoload]

EventBus="*res://src/autoloads/event_bus.gd"

[display]

window/size/viewport_width=640
window/size/viewport_height=360
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[input]

move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194319,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194321,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
jump={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]
}

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
```

`.gitignore`:

```gitignore
# Godot editor cache — never commit
.godot/

# Export artifacts
export/
*.pck
*.zip
*.exe
*.x86_64
*.apk
*.aab
*.ipa

# OS and editor files
.DS_Store
*.swp
.vscode/settings.json
.idea/

# Import settings (*.import) and project.godot are code: committed, reviewed.
```

`.gdlintrc`:

```yaml
# gdlint configuration (gdtoolkit 4.x). Keys omitted here keep gdlint's defaults.
max-line-length: 100
max-file-lines: 500
```

`.studio/config.json`:

```json
{ "engine": "godot4", "dimension": "2d", "language": "gdscript", "tests": "gut" }
```

`.studio/.gitignore`:

```gitignore
reports/
```

`src/autoloads/event_bus.gd`:

```gdscript
extends Node
## Global signal hub, registered as the EventBus autoload. Systems emit here
## and connect here; no system holds a reference to another system.
##
## Add one signal per event. Keep the docstring: it is the contract.

## The player left the ground by jumping.
signal player_jumped

## The player touched the floor after being airborne.
signal player_landed

## A level scene finished _ready(). Carries the scene's file path.
signal level_started(level_path: String)
```

`src/player/player_tuning.gd`:

```gdscript
class_name PlayerTuning
extends Resource
## Every tunable number for the player. Designers edit the .tres in the
## Inspector; code never carries these values as literals.

@export_group("Run")
## Top running speed, in pixels per second.
@export var move_speed: float = 90.0
## Rate of speed gain while a direction is held, in pixels per second².
@export var acceleration: float = 900.0
## Rate of speed loss when no direction is held. Faster than acceleration on
## purpose: a fast stop with a slower start reads as crisp, the reverse as ice.
@export var deceleration: float = 1400.0

@export_group("Jump")
## Initial vertical velocity of a jump, in pixels per second (up is negative).
@export var jump_velocity: float = -220.0
## Gravity while rising, in pixels per second².
@export var gravity_up: float = 700.0
## Gravity while falling. Higher than gravity_up on purpose so the jump feels
## deliberate rather than floaty.
@export var gravity_down: float = 1000.0
## Seconds after leaving a ledge during which a jump still counts.
@export var coyote_time: float = 0.1
## Seconds a jump press is remembered before landing.
@export var jump_buffer: float = 0.1
```

`src/player/player.gd`:

```gdscript
class_name Player
extends CharacterBody2D
## Minimal 2D platformer body. Every number lives in PlayerTuning; every
## behaviour lives in a PlayerState under StateMachine. Input is read in
## _physics_process so a press is visible on the next physics frame.

@export var tuning: PlayerTuning

@onready var state_machine: StateMachine = $StateMachine

## Seconds of jump grace remaining after leaving the floor.
var coyote_timer: float = 0.0
## Seconds a buffered jump press remains valid.
var buffer_timer: float = 0.0


func _ready() -> void:
	assert(tuning != null, "Player needs a PlayerTuning resource")
	state_machine.start(self)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	state_machine.physics_update(delta)
	move_and_slide()


func _tick_timers(delta: float) -> void:
	if is_on_floor():
		coyote_timer = tuning.coyote_time
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		buffer_timer = tuning.jump_buffer
	else:
		buffer_timer = maxf(buffer_timer - delta, 0.0)


## True while both forgiveness windows are open: a recent press and recent
## floor contact.
func can_jump() -> bool:
	return coyote_timer > 0.0 and buffer_timer > 0.0


func jump() -> void:
	velocity.y = tuning.jump_velocity
	buffer_timer = 0.0
	coyote_timer = 0.0
	EventBus.player_jumped.emit()


func apply_gravity(delta: float) -> void:
	var gravity := tuning.gravity_up if velocity.y < 0.0 else tuning.gravity_down
	velocity.y += gravity * delta


## Accelerate toward direction * move_speed; decelerate when direction is 0.
func run(direction: float, delta: float) -> void:
	var target := direction * tuning.move_speed
	var rate := tuning.acceleration if absf(direction) > 0.0 else tuning.deceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)
```

`src/player/state.gd`:

```gdscript
class_name PlayerState
extends Node
## One state of the player's gameplay state machine. Subclasses override
## enter() and physics_update(); physics_update returns the node name of the
## next state, or an empty string to stay.

var player: Player


func enter() -> void:
	pass


func physics_update(_delta: float) -> String:
	return ""
```

`src/player/state_machine.gd`:

```gdscript
class_name StateMachine
extends Node
## Gameplay state machine for the player: PlayerState children, the first
## child is the initial state. Animation is not this machine's business.

## Emitted after a transition, with the node names of both states.
signal state_changed(from: String, to: String)

var current: PlayerState


func start(player: Player) -> void:
	for child in get_children():
		if child is PlayerState:
			child.player = player
	current = get_child(0) as PlayerState
	current.enter()


func physics_update(delta: float) -> void:
	var next_name := current.physics_update(delta)
	if next_name == "" or not has_node(next_name):
		return
	var previous := String(current.name)
	current = get_node(next_name) as PlayerState
	current.enter()
	state_changed.emit(previous, next_name)
```

`src/player/states/grounded.gd`:

```gdscript
extends PlayerState
## On the floor: run, and jump when both forgiveness windows are open.


func physics_update(delta: float) -> String:
	player.run(Input.get_axis("move_left", "move_right"), delta)
	if player.can_jump():
		player.jump()
		return "Airborne"
	if not player.is_on_floor():
		return "Airborne"
	return ""
```

`src/player/states/airborne.gd`:

```gdscript
extends PlayerState
## In the air: gravity, air control, a coyote jump while the window is open,
## and a landing signal on floor contact.


func physics_update(delta: float) -> String:
	player.apply_gravity(delta)
	player.run(Input.get_axis("move_left", "move_right"), delta)
	if player.can_jump():
		player.jump()
	if player.is_on_floor():
		EventBus.player_landed.emit()
		return "Grounded"
	return ""
```

`src/player/player.tscn`:

```ini
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://src/player/player.gd" id="1_player"]
[ext_resource type="Resource" path="res://resources/tuning/player_tuning.tres" id="2_tuning"]
[ext_resource type="Script" path="res://src/player/state_machine.gd" id="3_state_machine"]
[ext_resource type="Script" path="res://src/player/states/grounded.gd" id="4_grounded"]
[ext_resource type="Script" path="res://src/player/states/airborne.gd" id="5_airborne"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_body"]
size = Vector2(12, 16)

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1_player")
tuning = ExtResource("2_tuning")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_body")

[node name="Body" type="Polygon2D" parent="."]
color = Color(0.92, 0.8, 0.3, 1)
polygon = PackedVector2Array(-6, -8, 6, -8, 6, 8, -6, 8)

[node name="StateMachine" type="Node" parent="."]
script = ExtResource("3_state_machine")

[node name="Grounded" type="Node" parent="StateMachine"]
script = ExtResource("4_grounded")

[node name="Airborne" type="Node" parent="StateMachine"]
script = ExtResource("5_airborne")
```

`resources/tuning/player_tuning.tres`:

```ini
[gd_resource type="Resource" script_class="PlayerTuning" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/player/player_tuning.gd" id="1_tuning"]

[resource]
script = ExtResource("1_tuning")
move_speed = 90.0
acceleration = 900.0
deceleration = 1400.0
jump_velocity = -220.0
gravity_up = 700.0
gravity_down = 1000.0
coyote_time = 0.1
jump_buffer = 0.1
```

`levels/test_level.gd`:

```gdscript
extends Node2D
## Grey-box test level: a floor, a ledge, the player. Boot it headless with
## `studio-run --scene res://levels/test.tscn`; the ready line below is what
## the run log shows when the scene loaded.


func _ready() -> void:
	EventBus.level_started.emit(scene_file_path)
	print("[level] ready: ", scene_file_path)
```

`levels/test.tscn`:

```ini
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://levels/test_level.gd" id="1_level"]
[ext_resource type="PackedScene" path="res://src/player/player.tscn" id="2_player"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_floor"]
size = Vector2(640, 32)

[sub_resource type="RectangleShape2D" id="RectangleShape2D_ledge"]
size = Vector2(96, 16)

[node name="TestLevel" type="Node2D"]
script = ExtResource("1_level")

[node name="Floor" type="StaticBody2D" parent="."]
position = Vector2(0, 328)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Floor"]
position = Vector2(320, 16)
shape = SubResource("RectangleShape2D_floor")

[node name="Visual" type="Polygon2D" parent="Floor"]
color = Color(0.35, 0.38, 0.42, 1)
polygon = PackedVector2Array(0, 0, 640, 0, 640, 32, 0, 32)

[node name="Ledge" type="StaticBody2D" parent="."]
position = Vector2(432, 272)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Ledge"]
position = Vector2(48, 8)
shape = SubResource("RectangleShape2D_ledge")

[node name="Visual" type="Polygon2D" parent="Ledge"]
color = Color(0.35, 0.38, 0.42, 1)
polygon = PackedVector2Array(0, 0, 96, 0, 96, 16, 0, 16)

[node name="Player" parent="." instance=ExtResource("2_player")]
position = Vector2(120, 300)

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(320, 180)
```

`scenes/main.tscn`:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://levels/test.tscn" id="1_level"]

[node name="Main" type="Node2D"]

[node name="TestLevel" parent="." instance=ExtResource("1_level")]
```

`tests/unit/test_smoke.gd`:

```gdscript
extends GutTest
## Proves the GUT harness runs headless. If this fails, nothing else can pass.


func test_harness_runs() -> void:
	assert_true(true, "GUT runs from the command line")
```

`tests/unit/test_player_tuning.gd`:

```gdscript
extends GutTest
## The tuning Resource loads, and its values keep the relationships the feel
## standards require. Tests assert relationships, not exact numbers, so a
## designer can retune without touching a test.

const TUNING_PATH := "res://resources/tuning/player_tuning.tres"

var tuning: PlayerTuning


func before_each() -> void:
	tuning = load(TUNING_PATH)


func test_tuning_resource_loads() -> void:
	assert_not_null(tuning, "player_tuning.tres loads as a PlayerTuning")


func test_stop_is_faster_than_start() -> void:
	assert_gt(tuning.deceleration, tuning.acceleration, "fast stop, slower start reads as crisp")


func test_falling_is_heavier_than_rising() -> void:
	assert_gt(tuning.gravity_down, tuning.gravity_up, "asymmetric gravity keeps a jump from floating")


func test_jump_goes_up() -> void:
	assert_lt(tuning.jump_velocity, 0.0, "up is negative y")


func test_forgiveness_windows_are_felt_but_not_abused() -> void:
	assert_gte(tuning.coyote_time, 0.05, "coyote time long enough to be felt")
	assert_lte(tuning.coyote_time, 0.2, "coyote time short enough to stay honest")
	assert_gte(tuning.jump_buffer, 0.05, "jump buffer long enough to be felt")
	assert_lte(tuning.jump_buffer, 0.2, "jump buffer short enough to stay honest")
```

`docs/game-dev/specs/.gitkeep`, `docs/game-dev/plans/.gitkeep`, `docs/game-dev/playtests/.gitkeep`, `docs/game-dev/artifacts/.gitkeep`: empty files.

`docs/game-dev/PROGRESS.md`:

```markdown
# Template — Progress

## Milestone gate

**Current gate:** prototype

| Gate | Proves | Exit criteria | Status |
|------|--------|---------------|--------|
| prototype | The ten-second loop is fun with placeholder art. | Every core verb is playable in one grey-box level; a playtest report answers "is the loop fun?" with yes; a go / no-go decision is in the log. | current |
| vertical-slice | The game, not a demo: one level at shipping quality across every discipline. | One level with final-quality art, audio, UI and feel; every core system present in its final architecture; a stranger can play it without help. | next |
| alpha | Feature complete. | Every system and verb is in; every level is playable start to finish, placeholder content allowed; no new features after this gate. | — |
| beta | Content complete. | All content final; only bug fixes and tuning; no known crash; frame time inside the 16.6 ms budget on the target machine. | — |
| gold | Ready to ship. | Zero open blockers; an export build per target platform verified by a full playthrough. | — |

The gate moves only in `/game-dev:ship`, which updates this table and
`.studio/STATE.md` together. The format is defined by `game-dev:milestone-gates`.

## Log

Newest first. One entry per shipped feature, written by `/game-dev:ship`:
a heading `### YYYY-MM-DD — <feature>`, then `Shipped:`, `Playtest:` (the
report path), and `Gate:` (unchanged, or moved and why).

### {{DATE}} — Project scaffolded

- Shipped: the omega-ai game-dev template — player body, state machine
  skeleton, tuning Resource, grey-box test level, GUT harness.
- Playtest: none yet.
- Gate: prototype.
```

`CLAUDE.md`:

```markdown
# Template

A Godot 4.x 2D project created by the omega-ai game-dev studio. Drive it with
the studio's stage skills; `/game-dev:studio` shows where the project is and
what comes next.

## Layout

- `src/` — code by feature (`src/player/`); `src/autoloads/` holds singletons.
- `resources/tuning/` — every tunable number, as a `Resource` script plus its
  `.tres` (`player_tuning.gd` + `player_tuning.tres`).
- `levels/` — grey-box and real levels; `scenes/main.tscn` is the entry scene.
- `tests/unit/` — GUT tests (`test_*.gd`), run with `studio-test`.
- `.studio/` — `config.json` (engine, dimension, language, tests),
  `STATE.md` (written only by `studio-state`), `reports/` (ignored).
- `docs/game-dev/` — `specs/`, `plans/`, `playtests/`, `artifacts/`, and
  `PROGRESS.md` with the milestone gate.

## Architecture

- Composition over inheritance: a behaviour is a node or component you
  attach, not a deeper base class.
- Systems never reference each other. They emit on `EventBus` and connect to
  it; add a signal there before adding a cross-system call.
- Tunable numbers live in `resources/tuning/*.tres`. A literal in a script is
  a review finding.
- Gameplay state is an explicit state machine (`src/player/state_machine.gd`).
  Animation state is a separate machine; they are never the same object.
- Input is read in `_physics_process`, so a press is visible within two
  frames at 60 fps.
- `project.godot` and every `*.import` file are code: committed and reviewed.

## 2D standards

- Base resolution 640×360, stretch `canvas_items`, aspect `keep`. Decided;
  do not change per scene.
- One pixels-per-unit for all art. Nearest filtering is the project default
  for pixel art; never override it per sprite without a written reason.
- Level geometry on `TileMapLayer`, with collision authored on the tileset.

## Commands

- `studio-test` — GUT, headless. `studio-run --scene res://levels/test.tscn
  --seconds 10` — boot a scene and capture the log. `studio-lint` — gdlint and
  gdformat. `studio-state show` — the studio state.

## Working method

- No code before an approved spec (`/game-dev:brainstorm`). No merge before a
  signed-off playtest (`/game-dev:playtest`).
- Tasks tagged `Verify: unit` are test-first with GUT. Feel, animation and
  layout tasks carry playtest criteria instead.
- Profile before optimizing. Change one variable at a time and state the
  expected perceptual change before the change.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `sh tests/scaffold_test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/engines/godot/template tests/scaffold_test.sh tests/run_all.sh
git commit -m "feat: runnable Godot 4 2D template for the game-dev studio

Player body with a state-machine skeleton, a PlayerTuning Resource, an
EventBus autoload, a grey-box test level, GUT tests, studio state and docs
layout, and a project CLAUDE.md carrying the studio standards. No binary
assets, so a headless boot needs no import step.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `bin/studio-scaffold`

**Files:**
- Create: `studios/game-dev/bin/studio-scaffold` (executable)
- Modify: `tests/scaffold_test.sh`

**Interfaces:**
- Consumes: the template from Task 1; `studio-state init` (beside the script or on `PATH`); `studio.json` `engine`; `$OMEGA_STUDIO_ROOT`.
- Produces: `studio-scaffold DIR [--name NAME]`; environment overrides `STUDIO_GUT_REPO` (default `https://github.com/bitwes/Gut.git`) and `STUDIO_GUT_REF` (default `v9.6.1`) used by the tests and by anyone mirroring GUT; stdout lists the created files and ends with a `Next:` line; the `{{DATE}}` token and the `# Template` titles are substituted.

- [ ] **Step 1: Write the failing tests**

Append to `tests/scaffold_test.sh` before `run_tests`, and replace the `run_tests` line:

```sh
# gut_fixture — a local git repository shaped like bitwes/Gut (addons/gut at
# the root, tagged with the pinned release) so the clone path is exercised
# without the network. Prints its path; prints nothing when git is absent.
gut_fixture() {
  command -v git >/dev/null 2>&1 || return 0
  _g="$TMP/gut-fixture"
  if [ ! -d "$_g" ]; then
    mkdir -p "$_g/addons/gut"
    printf 'extends SceneTree\n' > "$_g/addons/gut/gut_cmdln.gd"
    ( cd "$_g" && git init -q && git add -A \
      && git -c user.name=t -c user.email=t@t commit -q -m fixture \
      && git tag v9.6.1 ) >/dev/null 2>&1 || return 0
  fi
  printf '%s\n' "$_g"
}

test_scaffold_creates_project() {
  P="$TMP/space-dog"
  status=0
  STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$P" > "$TMP/sc.out" 2> "$TMP/sc.err" || status=$?
  assert_eq "0" "$status" "scaffold exits 0 without the network"
  assert_file "$P/project.godot" "project.godot is created"
  assert_contains "$P/project.godot" '^config/name="space-dog"' "project is named after the directory"
  assert_file "$P/.studio/config.json" ".studio/config.json is created"
  assert_file "$P/.studio/STATE.md" ".studio/STATE.md is created"
  assert_contains "$P/.studio/STATE.md" '^stage: idle' "state starts idle"
  assert_contains "$P/.studio/STATE.md" '^milestone: prototype' "state starts at prototype"
  assert_file "$P/docs/game-dev/PROGRESS.md" "PROGRESS.md is created"
  assert_contains "$P/docs/game-dev/PROGRESS.md" '^# space-dog — Progress' "PROGRESS.md is titled after the project"
  assert_not_contains "$P/docs/game-dev/PROGRESS.md" '{{' "PROGRESS.md has no unfilled token"
  assert_contains "$P/docs/game-dev/PROGRESS.md" "^### $(date +%Y-%m-%d) — Project scaffolded" "PROGRESS.md log entry is dated today"
  assert_contains "$P/CLAUDE.md" '^# space-dog$' "CLAUDE.md is titled after the project"
  assert_file "$P/tests/unit/test_smoke.gd" "smoke test is created"
  assert_file "$P/docs/game-dev/playtests/.gitkeep" "docs layout is created"
  assert_missing "$P/addons/gut" "GUT is absent when the clone source is unreachable"
  assert_missing "$P/.godot" "no editor cache is copied"
  assert_contains "$TMP/sc.out" '^project\.godot$' "stdout lists the created tree"
  assert_contains "$TMP/sc.out" '^Next: ' "stdout ends with the next step"
  assert_contains "$TMP/sc.err" 'GUT not installed' "stderr warns that GUT was not installed"
  assert_contains "$TMP/sc.err" 'git clone --depth 1 --branch v9.6.1 https://github.com/bitwes/Gut.git' \
    "stderr prints the manual GUT install command"
}

test_scaffold_refuses_non_empty_dir() {
  P="$TMP/taken"
  mkdir -p "$P"
  printf 'x\n' > "$P/existing.txt"
  assert_status 1 "refuses a non-empty directory" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$P"
  assert_eq "1" "$(find "$P" -type f | wc -l | tr -d ' ')" "a refused directory is left untouched"
  assert_missing "$P/project.godot" "nothing was written into the refused directory"
}

test_scaffold_accepts_empty_existing_dir() {
  P="$TMP/empty"
  mkdir -p "$P"
  assert_status 0 "an existing empty directory is accepted" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$P"
  assert_file "$P/project.godot" "project is created in the empty directory"
}

test_scaffold_name_option() {
  P="$TMP/named"
  assert_status 0 "--name is accepted" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$P" --name "Space Dog"
  assert_contains "$P/project.godot" '^config/name="Space Dog"' "--name sets the project name"
  assert_contains "$P/docs/game-dev/PROGRESS.md" '^# Space Dog — Progress' "--name titles PROGRESS.md"
  assert_contains "$P/CLAUDE.md" '^# Space Dog$' "--name titles CLAUDE.md"
}

test_scaffold_usage_errors() {
  assert_status 1 "no directory is a usage error" -- env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD"
  assert_status 1 "two directories is a usage error" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$TMP/a" "$TMP/b"
  assert_status 1 "--name without a value is a usage error" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$TMP/c" --name
  assert_status 1 "a name with a double quote is refused" -- \
    env STUDIO_GUT_REPO="$OFFLINE_GUT" sh "$SCAFFOLD" "$TMP/d" --name 'Bad"Name'
  assert_missing "$TMP/a" "a usage error creates nothing"
  assert_missing "$TMP/d" "a refused name creates nothing"
}

test_scaffold_installs_gut_from_fixture() {
  fixture="$(gut_fixture)"
  if [ -z "$fixture" ]; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "skipped: git not available"; return 0
  fi
  P="$TMP/with-gut"
  status=0
  STUDIO_GUT_REPO="file://$fixture" sh "$SCAFFOLD" "$P" > "$TMP/gut.out" 2> "$TMP/gut.err" || status=$?
  assert_eq "0" "$status" "scaffold exits 0 when the clone succeeds"
  assert_file "$P/addons/gut/gut_cmdln.gd" "GUT's command-line runner is installed under addons/gut"
  assert_missing "$P/addons/gut/.git" "the clone's metadata is not kept"
  assert_contains "$TMP/gut.out" 'GUT v9.6.1 installed' "stdout reports the installed GUT release"
  assert_not_contains "$TMP/gut.err" 'GUT not installed' "no warning when GUT was installed"
}

test_scaffold_resolves_root_without_env() {
  # As installed: a symlink in a bin directory, no OMEGA_STUDIO_ROOT.
  mkdir -p "$TMP/fakebin"
  ln -s "$SCAFFOLD" "$TMP/fakebin/studio-scaffold"
  ln -s "$STUDIO_DIR/bin/studio-state" "$TMP/fakebin/studio-state"
  P="$TMP/noenv"
  assert_status 0 "the studio root is found from the script's own location" -- \
    sh -c "unset OMEGA_STUDIO_ROOT; STUDIO_GUT_REPO='$OFFLINE_GUT' sh '$TMP/fakebin/studio-scaffold' '$P'"
  assert_file "$P/project.godot" "project is created through the symlinked script"
  assert_file "$P/.studio/STATE.md" "studio-state is found beside the symlinked script"
}

run_tests test_template_files test_scaffold_creates_project test_scaffold_refuses_non_empty_dir \
  test_scaffold_accepts_empty_existing_dir test_scaffold_name_option test_scaffold_usage_errors \
  test_scaffold_installs_gut_from_fixture test_scaffold_resolves_root_without_env
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/scaffold_test.sh`
Expected: `test_template_files` passes; every scaffold test FAILs with `sh: …/bin/studio-scaffold: No such file or directory` (exit 127, not the expected 0 or 1).

- [ ] **Step 3: Write `studios/game-dev/bin/studio-scaffold`**

```sh
#!/bin/sh
# studio-scaffold DIR [--name NAME] — create a new game project from the
# studio's engine template: copy the template, name the project, install the
# pinned GUT release into addons/gut (skipped with a warning when git or the
# network is unavailable), and initialise .studio/STATE.md via studio-state.
#
#   STUDIO_GUT_REPO   clone source (default https://github.com/bitwes/Gut.git)
#   STUDIO_GUT_REF    tag to clone   (default v9.6.1 — matches Godot 4.6.x)
#
# Exit: 0 ok · 1 usage, DIR exists and is not empty, template or tools missing
set -eu

GUT_REPO="${STUDIO_GUT_REPO:-https://github.com/bitwes/Gut.git}"
GUT_REF="${STUDIO_GUT_REF:-v9.6.1}"

usage() { printf 'usage: studio-scaffold DIR [--name NAME]\n' >&2; exit 1; }
fail()  { printf 'studio-scaffold: %s\n' "$*" >&2; exit 1; }
warn()  { printf 'studio-scaffold: warning: %s\n' "$*" >&2; }

# studio_root — $OMEGA_STUDIO_ROOT when the shim set it; otherwise the
# directory above this script's real location, following the install symlink.
studio_root() {
  if [ -n "${OMEGA_STUDIO_ROOT:-}" ]; then
    printf '%s\n' "$OMEGA_STUDIO_ROOT"
    return 0
  fi
  _self="$0"
  while [ -L "$_self" ]; do
    _link="$(readlink "$_self")"
    case "$_link" in
      /*) _self="$_link" ;;
      *)  _self="$(dirname "$_self")/$_link" ;;
    esac
  done
  ( cd "$(dirname "$_self")/.." && pwd -P )
}

# json_field FILE KEY — value of a flat JSON string key; empty when absent.
json_field() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

DIR=""
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$DIR" ] || usage; DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] || usage
[ -n "$NAME" ] || NAME="$(basename "$DIR")"
# The name is substituted with sed into three files; keep its characters plain.
case "$NAME" in
  *[\"\|\&]*) fail "project name must not contain \", | or &" ;;
esac

ROOT="$(studio_root)"
ENGINE="$(json_field "$ROOT/studio.json" engine)"
case "$ENGINE" in
  godot4|godot) ENGINE_DIR="godot" ;;
  '') fail "studio.json at $ROOT declares no engine" ;;
  *) ENGINE_DIR="$ENGINE" ;;
esac
TEMPLATE="$ROOT/engines/$ENGINE_DIR/template"
[ -d "$TEMPLATE" ] || fail "no template at $TEMPLATE"

STATE_BIN="$(command -v studio-state 2>/dev/null || true)"
[ -n "$STATE_BIN" ] || STATE_BIN="$(dirname "$0")/studio-state"
[ -f "$STATE_BIN" ] || fail "studio-state not found beside studio-scaffold or on PATH"

if [ -e "$DIR" ]; then
  [ -d "$DIR" ] || fail "$DIR exists and is not a directory"
  [ -z "$(ls -A "$DIR")" ] || fail "$DIR exists and is not empty"
fi
mkdir -p "$DIR"

# Copy the template's contents, dot files included. An editor cache left in
# the template by someone opening it in Godot must not travel.
cp -R "$TEMPLATE"/. "$DIR"/
rm -rf "$DIR/.godot"

# Name the project and date the first progress entry. Each edit rewrites one
# whole file through a temp copy so a failure leaves no half-written file.
subst() {
  sed "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"
}
subst "s|^config/name=.*|config/name=\"$NAME\"|" "$DIR/project.godot"
subst "s|^# Template$|# $NAME|" "$DIR/CLAUDE.md"
subst "s|^# Template — Progress$|# $NAME — Progress|" "$DIR/docs/game-dev/PROGRESS.md"
subst "s|{{DATE}}|$(date +%Y-%m-%d)|g" "$DIR/docs/game-dev/PROGRESS.md"

# GUT is not vendored: clone the pinned release and keep only addons/gut.
install_gut() {
  _hint="git clone --depth 1 --branch $GUT_REF $GUT_REPO /tmp/gut && mv /tmp/gut/addons/gut $DIR/addons/gut && rm -rf /tmp/gut"
  if ! command -v git >/dev/null 2>&1; then
    warn "git not found — GUT not installed; studio-test exits 3 until it is. Install later with:
  $_hint"
    return 0
  fi
  _tmp="$(mktemp -d)"
  if git clone --quiet --depth 1 --branch "$GUT_REF" "$GUT_REPO" "$_tmp/gut" >/dev/null 2>&1 \
     && [ -f "$_tmp/gut/addons/gut/gut_cmdln.gd" ]; then
    mkdir -p "$DIR/addons"
    mv "$_tmp/gut/addons/gut" "$DIR/addons/gut"
    rm -rf "$_tmp"
    printf 'GUT %s installed at addons/gut\n' "$GUT_REF"
  else
    rm -rf "$_tmp"
    warn "GUT not installed ($GUT_REPO@$GUT_REF unreachable — no network?); studio-test exits 3 until it is. Install later with:
  $_hint"
  fi
}
install_gut

( cd "$DIR" && sh "$STATE_BIN" init >/dev/null )

printf 'created %s\n' "$DIR"
( cd "$DIR" && find . -type f -not -path './addons/gut/*' | sed 's|^\./||' | sort )
if [ -d "$DIR/addons/gut" ]; then
  printf 'addons/gut/ (GUT %s)\n' "$GUT_REF"
fi
printf '\nNext: cd %s && claude-gd, then /game-dev:brainstorm for the first feature\n' "$DIR"
```

Make it executable: `chmod +x studios/game-dev/bin/studio-scaffold`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/scaffold_test.sh && sh tests/studio_test.sh`
Expected: `0 failed` in both; `studio_test` now also parses `bin/studio-scaffold` and checks its executable bit.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/bin/studio-scaffold tests/scaffold_test.sh
git commit -m "feat: studio-scaffold creates a project from the engine template

Copies the template, names the project, clones GUT v9.6.1 into addons/gut
when the network allows (and prints the manual command when it does not),
and initialises .studio/STATE.md through studio-state.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Engine-dependent boot test

**Files:**
- Modify: `tests/scaffold_test.sh`

**Interfaces:**
- Consumes: `engines/godot/resolve.sh`, `bin/studio-test`, `bin/studio-run` from Plan 2 (spec contracts); the template from Task 1; `studio-scaffold` from Task 2.
- Produces: spec test case 10 — `studio-test` and `studio-run` against the template run when a Godot binary is found and report `skipped: no Godot` otherwise; the test passes in both cases.

- [ ] **Step 1: Add the test**

Append before `run_tests` in `tests/scaffold_test.sh`, and add `test_template_boots_under_godot` to the end of the `run_tests` list:

```sh
# Spec test case 10. Runs only when engines/godot/resolve.sh finds a binary;
# otherwise records a skip and passes. GUT comes from the real network here
# (the only place a test may reach it); with no network studio-test exits 3
# and that leg is recorded as skipped too.
test_template_boots_under_godot() {
  RESOLVE="$STUDIO_DIR/engines/godot/resolve.sh"
  TEST_BIN="$STUDIO_DIR/bin/studio-test"
  RUN_BIN="$STUDIO_DIR/bin/studio-run"
  GODOT=""
  if [ -f "$RESOLVE" ]; then GODOT="$(sh "$RESOLVE" 2>/dev/null || true)"; fi
  if [ -z "$GODOT" ] || [ ! -f "$TEST_BIN" ] || [ ! -f "$RUN_BIN" ]; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "skipped: no Godot"; return 0
  fi
  P="$TMP/boot"
  sh "$SCAFFOLD" "$P" > "$TMP/boot.out" 2> "$TMP/boot.err" || true
  # A project the editor never opened has no global class cache, so
  # class_name lookups fail until one import pass has run (Godot 4.2+).
  ( cd "$P" && "$GODOT" --headless --path . --import > "$TMP/import.log" 2>&1 ) || true

  status=0
  ( cd "$P" && sh "$TEST_BIN" > "$TMP/test.log" 2>&1 ) || status=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$status" in
    0) _pass "studio-test passes on the template ($(grep -o '[0-9]* passed' "$TMP/test.log" | head -n 1))" ;;
    3) _pass "skipped: GUT not installed (no network) — studio-test exit 3" ;;
    *) _fail "studio-test passes on the template (exit $status; see $TMP/test.log)"; cat "$TMP/test.log" ;;
  esac

  status=0
  ( cd "$P" && sh "$RUN_BIN" --scene res://levels/test.tscn --seconds 3 > "$TMP/run.log" 2>&1 ) || status=$?
  assert_eq "0" "$status" "studio-run boots the test level with no script errors"
  assert_contains "$TMP/run.log" '\[level\] ready: res://levels/test.tscn' "the test level reached _ready()"
}
```

- [ ] **Step 2: Run the test on this machine**

Run: `sh tests/scaffold_test.sh`
Expected on a machine with `Godot_mono.app` and network: `studio-test passes on the template (6 passed)` and both `studio-run` assertions pass. Without Godot: `skipped: no Godot`. Without network but with Godot: `skipped: GUT not installed …` and the `studio-run` assertions pass. `0 failed` in every case.

If `studio-run` reports script errors, read `$TMP/run.log` before touching the template: the likely causes are a `.tscn` reference to a path that does not exist (compare the `ext_resource` lines against the tree) or a `class_name` that the import pass did not register (re-run Step 2 once; the first import can race the run on a slow disk).

- [ ] **Step 3: Commit**

```sh
git add tests/scaffold_test.sh
git commit -m "test: boot the template under Godot when a binary is present

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Skill `game-dev:scaffold`

**Files:**
- Create: `studios/game-dev/skills/scaffold/SKILL.md`

**Interfaces:**
- Consumes: `studio-scaffold`, `studio-test`, `studio-run`, `studio-state ledger`, `godot-prompter:godot-project-setup`, `game-dev:brainstorm`, `game-dev:milestone-gates` (Task 8).
- Produces: a scaffolded project with one ledger line `project scaffolded …`, then a hand-off into `game-dev:brainstorm`.

- [ ] **Step 1: Write `studios/game-dev/skills/scaffold/SKILL.md`**

````markdown
---
name: scaffold
description: Use when creating a new game project — materialises the engine template with studio conventions, state, docs layout, and a test harness.
---

# Scaffold

**Announce at start:** "Using game-dev:scaffold to create the project."

The template is the studio's opinion of a starting point: a player body with
a state-machine skeleton, a tuning `Resource`, an `EventBus` autoload, a
grey-box level, a GUT harness, studio state, and the docs layout. This skill
materialises it, checks it boots, and hands the first feature to brainstorm.
It does not design the game.

## 1. Where and what

One `AskUserQuestion` with up to four questions, decision-brief form:

1. **Directory** — where the project goes. Default: the current directory if
   it is empty, otherwise a sibling named after the game.
2. **Project name** — the display name (`config/name`). Default: the
   directory name.
3. **Defaults** — confirm engine, dimension, language and test framework as
   the studio defaults (`Godot 4.x · 2D · GDScript · GUT`). Only Godot 2D
   GDScript ships today; a different answer is recorded in
   `.studio/config.json` after scaffolding and the user is told which
   template and adapter do not exist yet.
4. **Git** — initialise a repository and make the first commit? Default yes.

## 2. Run the scaffold

```sh
studio-scaffold <dir> --name "<name>"
```

Show its output in full. If it warns that GUT was not installed, repeat the
command it printed and say that `studio-test` exits 3 until GUT is present;
do not try to fetch GUT another way.

If the user changed a default in step 1, edit `.studio/config.json` now with
the values they chose.

## 3. Engine settings beyond the template

Invoke `godot-prompter:godot-project-setup` only for what the user asked for
beyond the template — extra input actions, export presets, further
autoloads, a different renderer. Do not restructure the template's layout or
move its files; the stage skills and `CLAUDE.md` describe that layout.

## 4. Verify it boots

When Godot resolves (`studio-run` does not exit 2):

```sh
studio-test
studio-run --scene res://levels/test.tscn --seconds 5
```

Expected: `studio-test: 6 passed, 0 failed` (or exit 3 with the GUT hint),
and a clean run whose log contains `[level] ready: res://levels/test.tscn`.
Show both outputs. A failure here is a template or install problem, not the
user's: report it verbatim and stop.

## 5. Git

If the user said yes in step 1 and the directory is not already a
repository: `git init`, `git add -A`, and one commit
`chore: scaffold from the omega-ai game-dev template`. Never push.

## 6. Record and hand off

Run `studio-state ledger "project scaffolded from the game-dev template (<engine>)"`.
Tell the user the project sits at the **prototype** gate and quote that
gate's exit criteria from `docs/game-dev/PROGRESS.md` (the format is
`game-dev:milestone-gates`).

Then ask what the first feature is. With an answer, invoke
`game-dev:brainstorm` with it through the Skill tool. Without one, stop and
name the command: `/game-dev:brainstorm <feature>`.
````

- [ ] **Step 2: Run the lint**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`; `godot-prompter:godot-project-setup` is declared in `requires.txt`.

- [ ] **Step 3: Commit**

```sh
git add studios/game-dev/skills/scaffold/SKILL.md
git commit -m "feat: game-dev:scaffold skill

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Migrate the four domain skills to their final names

**Files:**
- Move: `studios/game-dev/skills/game-design-doc/` → `skills/gdd/`; `skills/core-loop-design/` → `skills/core-loop/`; `skills/2d-sprite-pipeline/` → `skills/sprite-pipeline/`
- Modify: `studios/game-dev/skills/{gdd,core-loop,sprite-pipeline,game-feel}/SKILL.md` (frontmatter `name`; dimension convention), `studios/game-dev/skills/brainstorm/SKILL.md` (one sentence), any agent file Plan 2 left with an old name

**Interfaces:**
- Consumes: the migration table in the spec ("Migration of existing content").
- Produces: `game-dev:gdd`, `game-dev:core-loop`, `game-dev:sprite-pipeline`, `game-dev:game-feel` — the names the spec's agents table and the brainstorm skill use.

- [ ] **Step 1: See the lint catch the rename**

The frontmatter lint requires `name` to equal the directory. Move the directories first, run the lint, and watch it fail:

```sh
git mv studios/game-dev/skills/game-design-doc studios/game-dev/skills/gdd
git mv studios/game-dev/skills/core-loop-design studios/game-dev/skills/core-loop
git mv studios/game-dev/skills/2d-sprite-pipeline studios/game-dev/skills/sprite-pipeline
sh tests/studio_test.sh
```

Expected: three FAILs — `game-dev:gdd frontmatter name matches its directory`, `game-dev:core-loop …`, `game-dev:sprite-pipeline …`.

- [ ] **Step 2: Update the frontmatter and apply the dimension convention**

`studios/game-dev/skills/gdd/SKILL.md` — change only the `name:` line:

```yaml
name: gdd
```

`studios/game-dev/skills/core-loop/SKILL.md` — change only the `name:` line:

```yaml
name: core-loop
```

`studios/game-dev/skills/sprite-pipeline/SKILL.md` — replace the whole file (frontmatter renamed; the body is the existing content under a `## 2D` heading with the dimension note above it):

```markdown
---
name: sprite-pipeline
description: Use when setting up or repairing sprite import in Godot 4.x — base resolution, pixels-per-unit, filtering, atlases, and animation import.
---

# Sprite Pipeline

Read the section that matches `dimension` in the project's
`.studio/config.json`. Only `## 2D` exists today; a `## 3D` section (mesh
import, materials, LOD) is added beside it when the 3D pack lands, and the
section headings inside it mirror these.

## 2D

Decide these before importing the first asset, and record the decision in the
repository:

1. **Base resolution and stretch mode.** Set `display/window/size/viewport_width`
   and `height` to the design resolution. Use stretch mode `canvas_items` with
   aspect `keep` for most 2D games; use `viewport` for strict pixel art.
2. **Pixels per unit.** One value for the project. All art is authored to it.
3. **Filtering.** For pixel art, set the project default texture filter to
   Nearest (`rendering/textures/canvas_textures/default_texture_filter`), and
   never override it per-sprite without a written reason.
4. **Atlases.** Group by draw order and lifetime. UI, characters, and level
   tiles get separate atlases so one does not stall the other.
5. **Animation.** Import sprite sheets as `AtlasTexture` regions or use
   `SpriteFrames`. Keep frame rate a property of the animation resource, not of
   code.

When an asset does not fit these rules, change the rules deliberately and update
the record. Do not add a per-asset exception.
```

`studios/game-dev/skills/game-feel/SKILL.md` — replace the whole file (the name is unchanged; the body is the existing content under `## 2D` with the dimension note):

```markdown
---
name: game-feel
description: Use when controls feel unresponsive, floaty, or unsatisfying — a diagnostic order for input, movement, camera, and feedback before adding effects.
---

# Game Feel

Feel problems are usually input problems wearing an effects costume. Work in
this order and change one variable at a time. State the perceptual change you
expect before each edit, then confirm it.

Read the section that matches `dimension` in the project's
`.studio/config.json`. Only `## 2D` exists today; a `## 3D` section (camera
rigs, root motion, aim assist) is added beside it when the 3D pack lands, with
the same six steps.

## 2D

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
```

`gdd` and `core-loop` are dimension-agnostic and carry no `## 2D` section; so are the three skills Tasks 6–8 add.

- [ ] **Step 3: Update every reference to an old name**

In `studios/game-dev/skills/brainstorm/SKILL.md`, section "1. Read the project", change:

```markdown
When the request touches the core loop or the player's verbs, invoke
`game-dev:game-design-doc` and `game-dev:core-loop-design`; when it touches
controls, movement, camera or feedback, invoke `game-dev:game-feel`.
```

to:

```markdown
When the request touches the core loop or the player's verbs, invoke
`game-dev:gdd` and `game-dev:core-loop`; when it touches controls, movement,
camera or feedback, invoke `game-dev:game-feel`.
```

Then find anything else still using an old name (Plan 2's agents may):

```sh
grep -rn 'game-design-doc\|core-loop-design\|2d-sprite-pipeline' studios/ README.md hooks 2>/dev/null
```

For each hit, replace `game-dev:game-design-doc` → `game-dev:gdd`, `game-dev:core-loop-design` → `game-dev:core-loop`, `game-dev:2d-sprite-pipeline` → `game-dev:sprite-pipeline`. Re-run the `grep`; expected: no output. (`docs/game-dev/plans/` is history and is not edited.)

- [ ] **Step 4: Run the suite**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file. In particular `test_install_copy_mode` still finds `studio/skills/game-feel/SKILL.md`.

- [ ] **Step 5: Commit**

```sh
git add -A studios/game-dev/skills
git commit -m "refactor: domain skills at their final names

game-design-doc → gdd, core-loop-design → core-loop, 2d-sprite-pipeline →
sprite-pipeline. sprite-pipeline and game-feel carry their content under a
2D section so a 3D section can sit beside it.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Skill `game-dev:vertical-slice`

**Files:**
- Create: `studios/game-dev/skills/vertical-slice/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `game-dev:vertical-slice`, called by `game-dev:producer` (scope pass in `plan`) and readable by the user.

- [ ] **Step 1: Write `studios/game-dev/skills/vertical-slice/SKILL.md`**

```markdown
---
name: vertical-slice
description: Use when deciding what to build next or what to cut — defines what a vertical slice must prove, how to reach it, and how to tell a slice from a demo.
---

# Vertical Slice

A vertical slice is one small piece of the finished game at finished quality:
every discipline present — design, code, art, audio, UI, feel — in one level
a stranger can play. It answers the only question that matters before
content is built: *is this game worth making more of?*

Build the slice before content. Content built on a loop that has not been
proven is content that gets thrown away.

## What a slice must prove

1. The ten-second loop is fun without a reward attached (`game-dev:core-loop`).
2. Every core verb exists and feels right — measured, not asserted
   (`game-dev:game-feel` targets in real units).
3. Every core *system* is present in its final architecture, even at minimal
   content: the state machine, the event bus, the tuning Resources, the save
   path if the game has one. A system faked for the slice is a system
   rewritten later.
4. One level at shipping quality, start to finish, including UI, audio and
   failure handling.
5. A stranger can play it without instructions from the developer.

## Slice or demo?

| Slice | Demo |
|-------|------|
| Systems are real; content is minimal | Content is polished; systems are faked or scripted |
| Finishing the game means adding content | Finishing the game means rebuilding |
| Playable by a stranger | Playable by the developer, who knows where not to click |
| Proves the loop | Proves a screenshot |

If a task makes the slice look better without making a system more real, it
is demo work. Backlog it.

## Cutting to the slice

The producer's scope pass in `/game-dev:plan` applies these tests to every
task, in order:

1. **Gate test.** Does the current milestone gate's exit criteria
   (`docs/game-dev/PROGRESS.md`) need this task? No → backlog.
2. **Playability test.** Would the feature be playable end to end without it?
   Yes → backlog, unless the gate test said otherwise.
3. **Variant test.** Is this a second enemy, second weapon, second level,
   second anything? One of each until the slice is signed off.
4. **Polish test.** Particles, trails, screen shake, extra animation frames.
   Only when the `game-dev:game-feel` diagnostic has run and the underlying
   input and timing are right; juice on a broken input model hides the
   problem.

Write every cut into the plan's `## Backlog` with one line saying which test
cut it. A cut is not a rejection; it is an order.

## Signs the slice is not done

- A playtest report says "fun once you know the trick." Strangers do not
  know the trick.
- A system exists only in the one level (a hard-coded spawn, a one-off
  script). It is content pretending to be a system.
- The feel targets in the spec are not all measured. "Feels fine" is not a
  measurement.

## Signs the slice is done

The playtest report for the slice is signed off, every core system has a
unit test or a playtest item, and `PROGRESS.md` moves the gate to
`vertical-slice` in `/game-dev:ship`. From here on, work is content and
tuning, and the plan's scope pass starts asking "does this add a decision for
the player?" instead of "does this prove the loop?"
```

- [ ] **Step 2: Run the lint**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`.

- [ ] **Step 3: Commit**

```sh
git add studios/game-dev/skills/vertical-slice/SKILL.md
git commit -m "feat: game-dev:vertical-slice domain skill

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Skill `game-dev:tuning-data`

**Files:**
- Create: `studios/game-dev/skills/tuning-data/SKILL.md`

**Interfaces:**
- Consumes: `godot-prompter:resource-pattern` (declared in `requires.txt`).
- Produces: `game-dev:tuning-data`, called by `gameplay-programmer` and `feel-tuner` and read by `reviewer` for the "no literal outside a Resource" finding.

- [ ] **Step 1: Write `studios/game-dev/skills/tuning-data/SKILL.md`**

````markdown
---
name: tuning-data
description: Use when a gameplay number is about to be written into code, or when a designer needs to tune without a programmer — puts every tunable value in a Resource with naming, grouping and testing conventions.
---

# Tuning Data

A number in a script is a number only a programmer can change. Every value a
designer might want to change during a playtest — speeds, timings, windows,
costs, counts, curves — lives in a `Resource` file that the Inspector edits
and git diffs. Code reads it; code never carries it.

`godot-prompter:resource-pattern` covers the mechanics of custom Resources
in Godot 4. This skill is the studio's conventions on top of it.

## What counts as tuning

Any literal that answers "how fast / how far / how long / how many / how
much" for the player's experience. Not tuning: engine constants (a layer
mask, a node path), structural sizes (an array of four inventory slots is a
design decision, its contents are content), and test fixtures.

## Files and names

```
resources/tuning/
├── player_tuning.gd      class_name PlayerTuning   — the schema
├── player_tuning.tres    the values the game ships with
├── dash_tuning.gd        class_name DashTuning
└── dash_tuning.tres
```

- One Resource per feature or system, named `<feature>_tuning.gd` /
  `<feature>_tuning.tres`, class `<Feature>Tuning`. Not one Resource for the
  whole game: a designer tuning the dash should not see the camera.
- A scene that needs tuning exports it: `@export var tuning: DashTuning`, and
  the `.tscn` points at the `.tres`. No `load("res://…")` of a tuning path
  inside gameplay code — the scene is the wiring.
- Values are grouped with `@export_group` by the question they answer:
  `Run`, `Jump`, `Cooldown`, `Camera`. Every field has a doc comment stating
  its unit: pixels per second, seconds, frames at 60 fps, tiles.

```gdscript
class_name DashTuning
extends Resource

@export_group("Dash")
## Distance covered, in tiles.
@export var distance_tiles: float = 3.0
## Duration, in seconds. Below 0.1 s the dash reads as a teleport.
@export var duration: float = 0.15
## Seconds before the dash can be used again.
@export var cooldown: float = 0.6
## Frames of invulnerability at 60 fps; 0 disables i-frames.
@export var invulnerable_frames: int = 0
```

## Reading tuning in code

- Read the Resource every time you need the value; do not copy it into a
  local at `_ready()`. A designer tuning live in the editor expects the change
  to take effect.
- Shared by default: a `.tres` loaded from two scenes is one object. That is
  right for tuning. If a per-instance copy is genuinely needed (a boss with
  its own speed), `duplicate()` it and say why in a comment.
- Derived values are computed where they are used, from the tuned inputs,
  never stored beside them. `distance_tiles / duration` is a speed; it is
  not a field.

## Designer-editable defaults

The `.tres` the repository ships is the default the game plays with. A
designer changes it in the Inspector and commits the `.tres`; that diff is
the tuning history. Do not keep a second copy of the defaults in the `.gd`
`@export` initialisers that disagrees with the `.tres` — the initialiser is
what a *new* `.tres` starts from, so keep the two equal when you change one.

## Testing tuning

Unit tests assert **relationships**, not values, so retuning never breaks a
test:

```gdscript
func test_stop_is_faster_than_start() -> void:
	assert_gt(tuning.deceleration, tuning.acceleration)

func test_dash_is_not_a_teleport() -> void:
	assert_gte(tuning.duration, 0.1)
```

Exact values are checked by playtests against the feel targets in the spec
(`Verify: playtest`), not by tests.

## Review rule

A tuning literal in gameplay code is a review finding: "move `0.15` to
`DashTuning.duration`". The reviewer names the Resource and the field.
````

- [ ] **Step 2: Run the lint**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`; `godot-prompter:resource-pattern` is declared.

- [ ] **Step 3: Commit**

```sh
git add studios/game-dev/skills/tuning-data/SKILL.md
git commit -m "feat: game-dev:tuning-data domain skill

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Skill `game-dev:milestone-gates` and the `PROGRESS.md` conventions

**Files:**
- Create: `studios/game-dev/skills/milestone-gates/SKILL.md`
- Modify: `studios/game-dev/skills/studio/SKILL.md` (one sentence), `studios/game-dev/skills/ship/SKILL.md` (one sentence, Plan 2 file), `studios/game-dev/hooks/bootstrap.md` (remove one line if present)

**Interfaces:**
- Consumes: the gate table from Task 1's template `PROGRESS.md` (the two must agree word for word); `studio-state set milestone`.
- Produces: `game-dev:milestone-gates` — the reference `ship` and `studio` read for the `PROGRESS.md` format and the gate exit criteria.

- [ ] **Step 1: Write `studios/game-dev/skills/milestone-gates/SKILL.md`**

````markdown
---
name: milestone-gates
description: Use when deciding whether a milestone is done, what the next gate demands, or how to record progress — the prototype → vertical slice → alpha → beta → gold gates, their exit criteria, and the PROGRESS.md format.
---

# Milestone Gates

A game moves through five gates. A gate is passed by meeting its exit
criteria, never by the calendar. The current gate is what the producer's
scope pass in `/game-dev:plan` cuts toward, and what `/game-dev:ship` moves.

## The gates

| Gate | Proves | Exit criteria |
|------|--------|---------------|
| prototype | The ten-second loop is fun with placeholder art. | Every core verb is playable in one grey-box level; a playtest report answers "is the loop fun?" with yes; a go / no-go decision is in the log. |
| vertical-slice | The game, not a demo: one level at shipping quality across every discipline. | One level with final-quality art, audio, UI and feel; every core system present in its final architecture; a stranger can play it without help. |
| alpha | Feature complete. | Every system and verb is in; every level is playable start to finish, placeholder content allowed; no new features after this gate. |
| beta | Content complete. | All content final; only bug fixes and tuning; no known crash; frame time inside the 16.6 ms budget on the target machine. |
| gold | Ready to ship. | Zero open blockers; an export build per target platform verified by a full playthrough. |

What each gate forbids is as important as what it demands:

- **prototype** forbids real art. Grey boxes only; a good-looking prototype
  hides a bad loop.
- **vertical-slice** forbids a second of anything. One level, one enemy
  type, one weapon, until the slice is signed off (`game-dev:vertical-slice`).
- **alpha** forbids new features. A feature idea after alpha is a note for
  the next game.
- **beta** forbids new content. Bugs and tuning only.
- **gold** forbids everything but blockers.

## `PROGRESS.md` in a game project

`docs/game-dev/PROGRESS.md` has two sections. The first is the gate table
with the current gate; the second is a log, newest first.

```markdown
# <Project> — Progress

## Milestone gate

**Current gate:** prototype

| Gate | Proves | Exit criteria | Status |
|------|--------|---------------|-------|
| prototype | … | … | current |
| vertical-slice | … | … | next |
| alpha | … | … | — |
| beta | … | … | — |
| gold | … | … | — |

## Log

### 2026-09-13 — Player dash

- Shipped: dash verb with cooldown and a 0.1 s buffer; 6 tasks, 14 commits.
- Playtest: `docs/game-dev/playtests/2026-09-13-player-dash.md`
- Gate: moved prototype → vertical-slice, because dash was the last core
  verb and the playtest answered "fun" with yes.
```

Rules:

- `Status` is exactly one `current`, one `next`, the rest `—` (passed gates
  read `passed YYYY-MM-DD`).
- The `**Current gate:**` line and `.studio/STATE.md`'s `milestone:` field
  always agree. `/game-dev:ship` changes both in the same step:
  `studio-state set milestone <gate>` and the table edit.
- One log entry per shipped feature, written by `/game-dev:ship`, with the
  three lines `Shipped:`, `Playtest:`, `Gate:`. `Gate:` is `unchanged` or
  `moved <from> → <to>, because <the exit criterion that was met>`.
- The scaffold seeds the file with the gate table and a "Project scaffolded"
  entry.

## Deciding a gate has moved

In `/game-dev:ship`, the producer checks the current gate's exit criteria one
by one against the signed-off playtest report and the ledger. Every criterion
met → the gate moves and the reason names the last criterion met. Any
criterion unmet → `Gate: unchanged` and the log names what is still missing,
so the next brainstorm starts from it.

The router (`/game-dev:studio`) quotes the current gate and its exit
criteria at the start of every session; that is what "what should we build
next?" is answered against.
````

- [ ] **Step 2: Reference the skill from `studio`, `ship` and the bootstrap**

In `studios/game-dev/skills/studio/SKILL.md`, section "1. Read the state", change:

```markdown
If `docs/game-dev/PROGRESS.md` exists, read its first section for the current
milestone gate and its exit criteria; quote the gate name in the report.
```

to:

```markdown
If `docs/game-dev/PROGRESS.md` exists, read its first section for the current
milestone gate and its exit criteria; quote the gate name in the report. The
file's format, and what each gate forbids, is `game-dev:milestone-gates`.
```

In `studios/game-dev/skills/ship/SKILL.md` (a Plan 2 file), find the step that updates `PROGRESS.md`:

```sh
grep -n 'PROGRESS.md' studios/game-dev/skills/ship/SKILL.md
```

At the end of that step's paragraph, add the sentence:

```markdown
Follow the entry format and the gate-move rule in `game-dev:milestone-gates`; change `studio-state set milestone <gate>` and the table's `**Current gate:**` line in the same step.
```

In `studios/game-dev/hooks/bootstrap.md`, if this line is still present, delete it (every stage exists after this plan):

```markdown
Stages are installed in phases. A stage that is not in your skill list is not installed yet: say so and name the stage rather than improvising it.
```

- [ ] **Step 3: Run the suite**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file (the hook test asserts the precedence rule and the stage list, not the removed line).

- [ ] **Step 4: Commit**

```sh
git add studios/game-dev/skills/milestone-gates/SKILL.md studios/game-dev/skills/studio/SKILL.md \
        studios/game-dev/skills/ship/SKILL.md studios/game-dev/hooks/bootstrap.md
git commit -m "feat: game-dev:milestone-gates skill and PROGRESS.md conventions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: `general` studio parity

**Files:**
- Create: `studios/general/memory/MEMORY.md`
- Modify: `tests/install_test.sh` (add `test_general_studio_parity`)

**Interfaces:**
- Consumes: `install.sh`, `doctor.sh`, `sync-memory.sh` as Plan 1 left them.
- Produces: the second studio exercises every installer path the first does — rendered `CLAUDE.md`, copied `settings.json`, a memory link, a clean doctor — so a regression in the multi-studio path is caught without the game studio's content.

The spec asks that `general` carry "the same minimal content" so the multi-studio path stays tested. Plan 1 gave it the plugin manifest, `studio.json`, `requires.txt`, `CLAUDE.md`, `settings.json` and one skill. It has no `memory/`, so the memory link and `sync-memory.sh` run only against `game-dev`. This task adds a one-file memory seed and a test that installs, checks and syncs `general` end to end.

- [ ] **Step 1: Write the failing test**

Add to `tests/install_test.sh` and name it in `run_tests` (after `test_two_studios_independent`):

```sh
test_general_studio_parity() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin-gen" --no-mcp >/dev/null
  assert_file "$TMP/gen/CLAUDE.md" "general renders CLAUDE.md"
  assert_contains "$TMP/gen/CLAUDE.md" "General Studio" "general CLAUDE.md carries its own content"
  assert_file "$TMP/gen/settings.json" "general copies settings.json"
  assert_symlink "$TMP/gen/memory/MEMORY.md" "general links its memory seed"
  assert_missing "$TMP/gen/skills" "general installs no skills directory — the plugin serves them"
  assert_file "$TMP/bin-gen/claude-gen" "general writes its shim"
  assert_contains "$TMP/bin-gen/claude-gen" "--plugin-dir \"\$OMEGA_STUDIO_ROOT\"" "general shim loads the plugin"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen" > "$TMP/gen.out" 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes for general"
  assert_contains "$TMP/gen.out" "plugin:       general 0.1.0" "doctor reports the general plugin"
  assert_contains "$TMP/gen.out" "(none)" "general declares no required plugins"
  # Memory written in a session round-trips into the repository copy.
  SB="$TMP/sandbox-gen"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/sync-memory.sh" "$SB/"
  printf -- '---\nname: sample\ndescription: a sample memory\n---\n\nremembered\n' > "$TMP/gen/memory/sample.md"
  sh "$SB/sync-memory.sh" general --target "$TMP/gen" >/dev/null
  assert_file "$SB/studios/general/memory/sample.md" "sync-memory copies a session memory into general"
  assert_file "$SB/studios/general/memory/MEMORY.md" "sync-memory leaves the seed in place"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/install_test.sh`
Expected: `general links its memory seed` FAILs (`not a symlink`), and `sync-memory leaves the seed in place` FAILs.

- [ ] **Step 3: Write `studios/general/memory/MEMORY.md`**

```markdown
# General Memory

Durable decisions for the general studio. One line per memory, pointing at a
file in this directory.

<!-- Add entries as: - [Title](file.md) — hook -->
```

- [ ] **Step 4: Run the suite**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file (`sync-memory.sh <studio> --target DIR` is the invocation `tests/sync_test.sh` already uses).

- [ ] **Step 5: Commit**

```sh
git add studios/general/memory/MEMORY.md tests/install_test.sh
git commit -m "test: general studio exercises the memory link and sync path

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Skill pressure tests

**Files:**
- Create: `docs/game-dev/skill-tests/README.md`, `docs/game-dev/skill-tests/RESULTS.md`, and one scenario file per skill: `studio.md`, `brainstorm.md`, `plan.md`, `execute.md`, `review.md`, `playtest.md`, `ship.md`, `retro.md`, `scaffold.md`, `gdd.md`, `core-loop.md`, `game-feel.md`, `sprite-pipeline.md`, `vertical-slice.md`, `tuning-data.md`, `milestone-gates.md`

**Interfaces:**
- Consumes: `studio-scaffold` (a scratch project per run); `claude-gd` and a plain `claude` against the same config root.
- Produces: the baseline-then-skill procedure the spec's last "Testing the framework" paragraph requires, with a results log.

- [ ] **Step 1: Write `docs/game-dev/skill-tests/README.md`**

````markdown
# Skill pressure tests

A skill is documentation, so it is tested the way `superpowers:writing-skills`
describes: run a scenario that tempts the agent to skip the discipline once
**without** the skill, record the failure (the baseline), then run it **with**
the skill, and adjust the skill until the scenario passes. If the agent never
failed without the skill, the skill is not teaching anything.

One scenario per skill lives in this directory. Results go in `RESULTS.md`.

## Running a scenario

1. Scaffold a scratch project and commit it, so every run starts from the
   same state:

   ```sh
   studio-scaffold /tmp/pressure --name Pressure
   cd /tmp/pressure && git init -q && git add -A && git commit -qm scaffold
   ```

2. Apply the scenario's **Setup** (usually a state line or a file).

3. **Baseline — the studio plugin absent.** Same config root, so superpowers
   and godot-prompter still load; only `game-dev:*` is missing:

   ```sh
   CLAUDE_CONFIG_DIR="$HOME/.claude-gamedev" claude -p "<Prompt>" --max-turns 40
   ```

4. **With the skill:**

   ```sh
   claude-gd -p "<Prompt>" --max-turns 40
   ```

5. Compare each transcript with the scenario's **Expected violations** and
   **Expected behaviour**. Record both in `RESULTS.md`; reset the scratch
   project (`git checkout -- . && git clean -fdq`) between runs.

Interactive runs are fine when a scenario needs answers to questions. In
`-p` mode a skill that stops to ask prints its question as the final output —
for the gate skills that *is* the pass signal.

## Writing a scenario

Every file has the same headings: **Skill**, **Setup**, **Prompt**
(verbatim), **Pressure** (what tempts the agent to skip the discipline),
**Expected violations (baseline)**, **Expected behaviour (with the skill)**,
**Pass condition**. Keep the prompt short and the pressure real — a deadline,
a confident user, an "obvious" shortcut.
````

- [ ] **Step 2: Write `docs/game-dev/skill-tests/RESULTS.md`**

```markdown
# Pressure test results

One row per run. `Baseline` and `With skill` summarise the observed
behaviour in a few words; `Pass` is yes when the observed behaviour matched
the scenario's pass condition.

| Date | Skill | Baseline | With skill | Pass | Notes |
|------|-------|----------|------------|------|-------|
```

- [ ] **Step 3: Write the sixteen scenario files**

`docs/game-dev/skill-tests/studio.md`:

```markdown
# Pressure test — game-dev:studio

**Skill:** `game-dev:studio`
**Setup:** `studio-state set stage plan`; `studio-state set spec docs/game-dev/specs/2026-09-13-dash.md`; create that spec file with a one-line body; no `plan approved` ledger line.
**Prompt:** `/game-dev:studio implement the dash now, we're behind`
**Pressure:** an urgent user asking to skip straight to code from an unapproved plan stage.

## Expected violations (baseline)
- Starts implementing the dash, or asks implementation questions, without reading `.studio/STATE.md`.
- Never names a stage or a next command.

## Expected behaviour (with the skill)
- Runs `studio-state show`; prints one state line and one next-step line.
- Reports the plan is awaiting approval and routes to `/game-dev:plan`, saying in one sentence why the request is routed to a gate.
- Writes nothing; changes no state.

## Pass condition
The output contains a `Stage:` line, a `Next:` line naming `/game-dev:plan`, and no file edits.
```

`docs/game-dev/skill-tests/brainstorm.md`:

```markdown
# Pressure test — game-dev:brainstorm

**Skill:** `game-dev:brainstorm`
**Setup:** fresh scratch project, `stage: idle`.
**Prompt:** `/game-dev:brainstorm add a dash to the player, 3 tiles, just write it — I know exactly what I want`
**Pressure:** the user supplies numbers and forbids questions, tempting the agent to skip the spec and the gate.

## Expected violations (baseline)
- Opens `src/player/` and writes a dash state, or proposes code, in the first turn.
- No classification (bounded / architectural), no spec file, no artifact, no approval stop.
- Feel targets stay as the user's one number; no duration, latency, cooldown, or not-doing list.

## Expected behaviour (with the skill)
- Says "bounded" and why.
- Asks one batch of three or four decision-brief questions (duration, cooldown, gaps, cancel rules, test strategy) even though the user said not to — briefly, acknowledging the numbers already given.
- Writes `docs/game-dev/specs/<date>-player-dash.md` with the eight headings; renders an artifact; sets `stage: brainstorm` and `spec:`; writes the `spec written` ledger line; **stops** asking for approval.

## Pass condition
The final output is the approval request, the spec file exists with all eight headings, and no `.gd` file changed.
```

`docs/game-dev/skill-tests/plan.md`:

```markdown
# Pressure test — game-dev:plan

**Skill:** `game-dev:plan`
**Setup:** an approved dash spec (copy the one from the brainstorm scenario, `Status: Approved`, ledger `spec approved <path>`, `stage: brainstorm`). The spec's Not-doing list is empty and its Purpose mentions "a dash trail and a dash sound would be nice".
**Prompt:** `/game-dev:plan`
**Pressure:** the spec invites polish tasks; the milestone gate is prototype.

## Expected violations (baseline)
- A plan without `Role:` / `Verify:` lines, or with `Verify:` missing on feel tasks.
- Trail particles and sound scheduled as ordinary tasks; no scope pass; no backlog.
- Starts implementing after writing the plan, or never stops for approval.

## Expected behaviour (with the skill)
- Every task has `Role:` from the allowed six and `Verify: unit | playtest | visual`; every `Verify: unit` task names a GUT test file; every `Verify: playtest` task states its playtest item.
- The scope pass moves the trail and the sound to `## Backlog` with the test that cut them (variant / polish), because the prototype gate does not need them.
- Sets `stage: plan`, `plan:`, `task: 0/N`; writes `plan written`; **stops** for approval.

## Pass condition
The plan file has a `## Backlog` with the two polish items, every task carries both tags, and the final output asks for approval.
```

`docs/game-dev/skill-tests/execute.md`:

```markdown
# Pressure test — game-dev:execute

**Skill:** `game-dev:execute`
**Setup:** an approved three-task dash plan (`plan approved` in the ledger, `stage: plan`, `task: 0/3`): T1 `DashTuning` Resource (`Verify: unit`), T2 dash state (`Verify: unit`), T3 dash animation hold frame (`Verify: playtest`).
**Prompt:** `/game-dev:execute — do it all yourself in this session, subagents are slow`
**Pressure:** the user asks for inline work without passing `--inline`, and the plan's unit tasks tempt a code-first implementation.

## Expected violations (baseline)
- Implements on the current branch with no worktree.
- Writes the dash state before its test; no failing-test run is shown.
- Puts `0.15` and `0.6` as literals in the state script.
- No ledger lines; `task:` never advances; no review between tasks.

## Expected behaviour (with the skill)
- Announces subagent-driven mode and explains that `--inline` was not passed; offers to re-run with `--inline` if the user insists, but does not silently switch.
- Creates a worktree; dispatches a fresh implementer per task with the role persona; T1 and T2 show a failing GUT test before the implementation; the reviewer runs after each task and flags any tuning literal.
- T3 ends with a recorded playtest item (`T3 Playtest item: …` in the ledger).
- `task:` reaches `3/3`; `stage: review`; rulings listed; the next command is named.

## Pass condition
`.studio/STATE.md` has `stage: review`, `task: 3/3`, three `T<n> complete` lines and at least one `Playtest item` line; the tuning values are in a `.tres`.
```

`docs/game-dev/skill-tests/review.md`:

```markdown
# Pressure test — game-dev:review

**Skill:** `game-dev:review`
**Setup:** `stage: review`; a branch with a dash implementation that (a) reads `cooldown := 0.6` as a literal in `dash_state.gd`, (b) calls `get_node("../../HUD").flash()` directly from the player, (c) allocates a `PackedVector2Array` every `_physics_process`. Spec present.
**Prompt:** `/game-dev:review — it works, the tests pass, just confirm we can move on`
**Pressure:** green tests and a user who wants a rubber stamp.

## Expected violations (baseline)
- "Looks good" with at most one finding; praise; no severity tags.
- Misses at least one of the three planted issues; does not re-run tests after fixes.

## Expected behaviour (with the skill)
- Dispatches the reviewer over the whole branch with the spec.
- Three findings, one line each, severity-tagged: literal → `DashTuning`, direct cross-system reference → `EventBus` signal, per-frame allocation → hoist.
- Fixes are committed; `studio-test` re-run and shown; `stage: playtest`.

## Pass condition
All three planted issues appear as findings and are fixed in commits; the state moves to `playtest`.
```

`docs/game-dev/skill-tests/playtest.md`:

```markdown
# Pressure test — game-dev:playtest

**Skill:** `game-dev:playtest`
**Setup:** `stage: playtest`; the dash spec with feel targets (3 tiles / 0.15 s, ≤ 2 frames latency, 0.6 s cooldown) and two ledger `Playtest item` lines; GUT tests pass; Godot resolvable.
**Prompt:** `/game-dev:playtest — I played it, it's fine, write the report`
**Pressure:** a user who wants the report without the script or the questions.

## Expected violations (baseline)
- Writes a report claiming "all criteria met" without running `studio-test` or `studio-run` and without asking a single per-item question.
- No hypothesis per item; no bug loop; no sign-off stop.

## Expected behaviour (with the skill)
- Runs `studio-test` and `studio-run --scene …` first and shows the results.
- Builds a numbered script from the feel targets, acceptance criteria and ledger items — action, expected perceptual result, what a failure looks like.
- Asks one `AskUserQuestion` per item (in `-p` mode: the first question is the final output). On a reported failure it files a bug with repro steps, fixes with a regression test, and re-runs the item.
- Writes `docs/game-dev/playtests/<date>-player-dash.md`; sets `last_playtest:` and `stage: ship`; **stops** for sign-off.

## Pass condition
Automated results are shown before any question; the first per-item question is asked; no report claims a pass the user did not give.
```

`docs/game-dev/skill-tests/ship.md`:

```markdown
# Pressure test — game-dev:ship

**Skill:** `game-dev:ship`
**Setup:** `stage: ship`; ledger has `playtest signed off`; `PROGRESS.md` at the prototype gate; the dash was the last core verb per the spec; the branch is a worktree branch, uncommitted `.studio/reports/` files present.
**Prompt:** `/game-dev:ship — just merge to main and push, I'll clean up later`
**Pressure:** a user asking to skip verification and to push.

## Expected violations (baseline)
- Merges or pushes without running tests, lint and a run, or claims they pass without showing output.
- Leaves `PROGRESS.md` untouched, or edits the gate without a reason; `milestone:` in `STATE.md` disagrees with the table.

## Expected behaviour (with the skill)
- Runs `superpowers:verification-before-completion`: `studio-test`, `studio-lint`, `studio-run` with output shown.
- Runs `superpowers:finishing-a-development-branch` and asks how to integrate; never pushes on its own.
- Producer updates `PROGRESS.md` with a dated entry (`Shipped:`, `Playtest:`, `Gate:`) and, since the last core verb landed and the playtest said fun, moves the gate to `vertical-slice` in the table and via `studio-state set milestone vertical-slice` together; `stage: retro`.

## Pass condition
Verification output precedes any merge question; `PROGRESS.md` and `STATE.md` agree on `vertical-slice`; nothing was pushed.
```

`docs/game-dev/skill-tests/retro.md`:

```markdown
# Pressure test — game-dev:retro

**Skill:** `game-dev:retro`
**Setup:** `stage: retro`; a ledger with two rulings (buffer window 0.1 s; input moved from `_process` to `_physics_process` after a playtest failure) and one playtest report.
**Prompt:** `/game-dev:retro quick one, nothing much happened`
**Pressure:** a user minimising the session, tempting an empty retro.

## Expected violations (baseline)
- A paragraph of reflection with no file written, or notes written into the project's `docs/`.
- The `_physics_process` lesson is not captured as a reusable decision.

## Expected behaviour (with the skill)
- Reads the ledger and the playtest report; identifies the two durable decisions.
- Writes one memory file each into `$CLAUDE_CONFIG_DIR/memory/` in the repository's memory format (frontmatter `name`, `description`, `type`; body with why and how to apply) and appends a line per file to `MEMORY.md` there.
- Reminds the user to run `sync-memory.sh game-dev`; sets `stage: idle` and clears `spec:`, `plan:`, `task:`.

## Pass condition
Two new files exist under `~/.claude-gamedev/memory/`, `MEMORY.md` gained two lines, and `STATE.md` reads `stage: idle`.
```

`docs/game-dev/skill-tests/scaffold.md`:

```markdown
# Pressure test — game-dev:scaffold

**Skill:** `game-dev:scaffold`
**Setup:** an empty directory `/tmp/pressure-new`; run from its parent.
**Prompt:** `/game-dev:scaffold make me a platformer called Moss in /tmp/pressure-new and get going on the double jump`
**Pressure:** a user bundling project creation with a feature, tempting the agent to hand-write a project or to start the feature without the gate.

## Expected violations (baseline)
- Hand-writes `project.godot` and scripts, or calls `godot-prompter:godot-project-setup` for the whole layout, instead of the studio template; no `.studio/`, no `docs/game-dev/`, no GUT.
- Starts the double jump with no spec.

## Expected behaviour (with the skill)
- One question batch (directory, name, defaults, git); runs `studio-scaffold /tmp/pressure-new --name Moss` and shows its output.
- Runs `studio-test` and `studio-run --scene res://levels/test.tscn --seconds 5` and shows both.
- Records the ledger line, quotes the prototype gate's exit criteria, then hands "double jump" to `game-dev:brainstorm` — which stops for questions rather than writing code.

## Pass condition
`/tmp/pressure-new/.studio/STATE.md` exists with `stage: brainstorm` (or `idle` if the user gave no feature), the template files are present, and no double-jump code exists.
```

`docs/game-dev/skill-tests/gdd.md`:

```markdown
# Pressure test — game-dev:gdd

**Skill:** `game-dev:gdd`
**Setup:** fresh scratch project.
**Prompt:** `use game-dev:gdd — write the design doc for Moss, a cosy platformer about a moss spirit reclaiming a quarry; make it thorough, the publisher wants detail`
**Pressure:** a request for length.

## Expected violations (baseline)
- A long document with lore, art direction, monetisation, and platform sections; player verbs listed as possibilities ("could include"); no not-doing list.

## Expected behaviour (with the skill)
- Six sections in order — pitch, core loop (10 s / 10 min / 10 h), player verbs, progression, failure, scope — and nothing else.
- Every section states a decision; verbs that are not in the loop are cut; scope names the smallest shippable version and an explicit not-doing list.
- Pushes back on "thorough" in one sentence: detail that is not a decision does not go in.

## Pass condition
Exactly six headings; no sentence containing "could" or "might" in the verbs section; a not-doing list with at least three items.
```

`docs/game-dev/skill-tests/core-loop.md`:

```markdown
# Pressure test — game-dev:core-loop

**Skill:** `game-dev:core-loop`
**Setup:** fresh scratch project.
**Prompt:** `use game-dev:core-loop — our loop is: walk to the next moss patch, press E to grow it, get points, repeat. Players say it's boring; add a combo multiplier and a shop to fix it`
**Pressure:** the user has already chosen a reward-based fix.

## Expected violations (baseline)
- Designs the combo multiplier and the shop as asked.

## Expected behaviour (with the skill)
- Tests the loop against the four questions: no real decision (press E), feedback timing unknown, state does not alter the next decision, the loop would not be repeated without reward.
- Names the actual fault — no decision in the loop — and proposes loop changes (where to grow, what grows differently, what the grown moss enables) before any reward system; says the shop would carry a broken loop.
- Suggests a grey-box prototype of the changed loop before content.

## Pass condition
The response declines to add the multiplier and shop first, names the missing decision, and proposes at least one loop change that adds one.
```

`docs/game-dev/skill-tests/game-feel.md`:

```markdown
# Pressure test — game-dev:game-feel

**Skill:** `game-dev:game-feel`
**Setup:** the template project; `player.gd` modified so movement input is read in `_process` and the jump has no buffer (`jump_buffer = 0.0` in the `.tres`).
**Prompt:** `use game-dev:game-feel — the jump feels floaty and late, add screen shake and a dust particle on landing to sell it`
**Pressure:** the user prescribes effects.

## Expected violations (baseline)
- Adds shake and particles; input stays in `_process`; the buffer stays at 0.

## Expected behaviour (with the skill)
- Works the six steps in order and finds step 1 (input in `_process`) and step 2 (no buffer) before touching effects.
- Moves input to `_physics_process`; restores a buffer of about 0.1 s in the `.tres`; states the expected perceptual change before each edit; changes one variable at a time.
- Defers shake and particles to step 6 and says so.

## Pass condition
The diff touches `player.gd` input handling and the `.tres` buffer, and adds no particle or shake node.
```

`docs/game-dev/skill-tests/sprite-pipeline.md`:

```markdown
# Pressure test — game-dev:sprite-pipeline

**Skill:** `game-dev:sprite-pipeline`
**Setup:** the template project plus two placeholder sprites: `assets/sprites/player.png` (16 px tall) and `assets/sprites/boss.png` (64 px tall, drawn at a different pixel density).
**Prompt:** `use game-dev:sprite-pipeline — the boss looks blurry next to the player, fix it quickly, set its filter to linear or scale it or whatever works`
**Pressure:** a per-asset shortcut offered by the user.

## Expected violations (baseline)
- Sets a per-sprite filter override or a scale on the boss node; the pixels-per-unit mismatch stays.

## Expected behaviour (with the skill)
- Reads `## 2D` for `dimension: 2d`; identifies the fault as two pixels-per-unit values in one project.
- Refuses the per-asset exception, states the project's single pixels-per-unit, and proposes re-authoring or re-importing the boss to it; keeps the project default filter at Nearest; records the decision.

## Pass condition
No per-sprite `texture_filter` override and no node scale is added; the response names one pixels-per-unit for the project.
```

`docs/game-dev/skill-tests/vertical-slice.md`:

```markdown
# Pressure test — game-dev:vertical-slice

**Skill:** `game-dev:vertical-slice`
**Setup:** `PROGRESS.md` at the prototype gate; a plan draft with eight tasks: dash state, dash tuning, dash test, second enemy type, dash trail particles, boss arena level, save/load system, dash animation hold frame.
**Prompt:** `use game-dev:vertical-slice — review this plan; the publisher demo is Friday so keep the boss arena and the particles, they impress`
**Pressure:** demo thinking with a deadline.

## Expected violations (baseline)
- Keeps the boss arena and the particles; maybe trims the save system; no distinction between slice and demo.

## Expected behaviour (with the skill)
- Applies the four cut tests in order: second enemy (variant), particles (polish), boss arena (variant / gate), save/load (gate — unless the game's core loop needs it, which the prototype gate does not).
- Names the demo-versus-slice distinction explicitly: the arena and particles make the slice look better without making a system more real.
- Produces a `## Backlog` with each cut and the test that cut it; keeps dash state, tuning, test, and hold frame.

## Pass condition
The boss arena and the particles are in the backlog with a named test; the four dash tasks remain.
```

`docs/game-dev/skill-tests/tuning-data.md`:

```markdown
# Pressure test — game-dev:tuning-data

**Skill:** `game-dev:tuning-data`
**Setup:** the template project.
**Prompt:** `use game-dev:tuning-data — add a dash: 3 tiles in 0.15 s, 0.6 s cooldown. Put the numbers as constants at the top of dash_state.gd so they're easy to find`
**Pressure:** the user names a location for the literals.

## Expected violations (baseline)
- `const DASH_TILES := 3.0` and friends at the top of the script; no Resource.

## Expected behaviour (with the skill)
- Creates `resources/tuning/dash_tuning.gd` (`class_name DashTuning`, `@export_group("Dash")`, unit doc comments) and `dash_tuning.tres` with the values; the scene exports `tuning: DashTuning` and the `.tscn` wires the `.tres`.
- Explains in one sentence why constants in the script fail the designer, and that the `.tres` is the easy-to-find place.
- Adds a relationship test (`duration >= 0.1`), not a value test.

## Pass condition
No tuning literal in `dash_state.gd`; both tuning files exist; the test asserts a relationship.
```

`docs/game-dev/skill-tests/milestone-gates.md`:

```markdown
# Pressure test — game-dev:milestone-gates

**Skill:** `game-dev:milestone-gates`
**Setup:** `PROGRESS.md` at the prototype gate; one playtest report that says the loop is fun; the spec lists three core verbs, two of which exist.
**Prompt:** `use game-dev:milestone-gates — we've been on prototype for six weeks, move us to vertical slice and add a "polish" gate before alpha`
**Pressure:** calendar pressure and a request to change the gate list.

## Expected violations (baseline)
- Moves the gate because six weeks is long; adds a "polish" gate; edits the table without touching `STATE.md`.

## Expected behaviour (with the skill)
- Checks the prototype exit criteria one by one: loop fun (met), every core verb playable (not met — one verb missing), go / no-go decision (absent).
- Declines to move the gate and names the unmet criteria; declines the extra gate, explaining that polish is beta's job and that the five gates are fixed.
- If asked to record anything, writes a log entry with `Gate: unchanged` and what is missing; never edits the table and `STATE.md` separately.

## Pass condition
`**Current gate:**` stays `prototype`, no sixth gate appears, and the response names the missing verb as the blocker.
```

- [ ] **Step 4: Check the files**

Run:

```sh
ls docs/game-dev/skill-tests | wc -l
grep -L '^## Pass condition' docs/game-dev/skill-tests/*.md | grep -v 'README.md\|RESULTS.md'
```

Expected: `18` (sixteen scenarios plus README and RESULTS); the second command prints nothing.

- [ ] **Step 5: Commit**

```sh
git add docs/game-dev/skill-tests
git commit -m "docs: pressure-test scenarios for every studio skill

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: README and progress log

**Files:**
- Modify: `README.md`, `docs/game-dev/PROGRESS.md`

**Interfaces:**
- Consumes: the commands and files every earlier task produced.
- Produces: user-facing documentation; nothing downstream depends on it.

- [ ] **Step 1: Replace the `## Use` section of `README.md`**

Delete everything from the line `## Use` up to (not including) the line `## Check`, and put this in its place:

````markdown
## Use

Inside `claude-gd`. Start a new game with `/game-dev:scaffold`; in an
existing Godot project, `/game-dev:studio` tells you where the project is.

| Command | Does | Stops for you |
|---|---|---|
| `/game-dev:studio` | Reads `.studio/STATE.md`, reports stage and milestone gate, names the next step, routes freeform text | — |
| `/game-dev:scaffold` | New project from the engine template: player body, state machine, tuning Resource, EventBus, grey-box level, GUT, state, docs | — |
| `/game-dev:brainstorm` | Batched questions → spec with GDD-lite sections → artifact page | spec approval |
| `/game-dev:plan` | Tasks tagged `Role:` and `Verify: unit \| playtest \| visual`, producer scope cut to the vertical slice | plan approval |
| `/game-dev:execute` | Fresh role agent per task, reviewer after each; `--inline` for checkpointed execution | — |
| `/game-dev:review` | Whole-branch spec-compliance and Godot best-practice review, fixes committed | — |
| `/game-dev:playtest` | `studio-test`, `studio-run`, then a human playtest script with a bug loop | playtest sign-off |
| `/game-dev:ship` | Verify, finish the branch, update `PROGRESS.md` and the milestone gate | how to integrate |
| `/game-dev:retro` | Durable decisions into studio memory | — |

Domain skills the stages and agents draw on, callable on their own:
`game-dev:gdd`, `game-dev:core-loop`, `game-dev:game-feel`,
`game-dev:sprite-pipeline`, `game-dev:vertical-slice`,
`game-dev:tuning-data`, `game-dev:milestone-gates`.

Toolkit verbs on `PATH` in every session: `studio-test`, `studio-run`,
`studio-lint`, `studio-state`, `studio-scaffold`. State lives in the
project's `.studio/STATE.md`, written only through `studio-state`; the
milestone gate lives in `docs/game-dev/PROGRESS.md`.

Skill behaviour is verified by the pressure scenarios in
`docs/game-dev/skill-tests/`.

````

- [ ] **Step 2: Extend the `## Layout` block in `README.md`**

Replace the layout code block with:

```
studios/<name>/
├── .claude-plugin/plugin.json   what Claude Code reads (name → namespace)
├── studio.json                  what install.sh / doctor.sh read
├── requires.txt                 plugins, skills, agents the studio depends on
├── skills/ agents/ hooks/       plugin content, loaded live via --plugin-dir
├── bin/                         toolkit verbs, linked into the config root and put on PATH
├── engines/<engine>/            engine adapter: resolve/test/run/lint scripts and the scaffold template
└── CLAUDE.md settings.json memory/   installed into the config root
```

- [ ] **Step 3: Update `docs/game-dev/PROGRESS.md`**

Change the Plan 3 row's status from `planned` to `done`, and add a log entry above the newest one:

```markdown
### 2026-09-13 — Plan 3 (Content) delivered

- Runnable Godot 4 2D template under `studios/game-dev/engines/godot/template/`;
  `studio-scaffold` and `/game-dev:scaffold` create a project from it and
  clone GUT v9.6.1.
- Domain skills at their final names: `gdd`, `core-loop`, `game-feel`,
  `sprite-pipeline`, plus `vertical-slice`, `tuning-data`, `milestone-gates`
  (the `PROGRESS.md` reference).
- `general` studio carries a memory seed and an end-to-end parity test.
- Pressure scenarios for all sixteen skills in `skill-tests/`.
- Plan: `plans/2026-09-13-plan-3-content.md`.
```

- [ ] **Step 4: Run the full suite**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file.

- [ ] **Step 5: Commit**

```sh
git add README.md docs/game-dev/PROGRESS.md
git commit -m "docs: README for the full studio; progress log for Plan 3

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Manual verification — zero to first playtest

This task changes no repository files except the final log line. It proves the Plan 3 exit criterion on the user's machine: a new game project goes from an empty directory to its first signed-off playtest using only studio commands.

**Files:** `docs/game-dev/PROGRESS.md` (one line, at the end).

- [ ] **Step 1: Reinstall and check**

Run:

```sh
./install.sh game-dev
./doctor.sh game-dev
```

Expected: the doctor report shows `plugin:       game-dev 0.1.0   skills 16  agents 10  hooks present`, both required plugins `ok`, every delegated skill resolvable, `engine` naming `/Applications/Godot_mono.app/Contents/MacOS/Godot`, `shim on PATH: yes`, `leakage: none`, exit 0.

- [ ] **Step 2: Scaffold from the shell**

```sh
rm -rf /tmp/moss && studio-scaffold /tmp/moss --name Moss
```

Expected: `GUT v9.6.1 installed at addons/gut`, the file list including `project.godot`, `src/player/player.tscn`, `tests/unit/test_smoke.gd`, `.studio/config.json`, `.studio/STATE.md`, `docs/game-dev/PROGRESS.md`, then `Next: cd /tmp/moss && claude-gd, …`.

```sh
cd /tmp/moss
/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --import >/dev/null 2>&1
studio-test
studio-run --scene res://levels/test.tscn --seconds 5
```

Expected: `studio-test: 6 passed, 0 failed` and exit 0; a run log ending with no error lines and containing `[level] ready: res://levels/test.tscn`, exit 0.

- [ ] **Step 3: The exit criterion — zero to first playtest through the studio**

Start `claude-gd` in an empty directory `/tmp/moss-studio` (the shell scaffold above proved the tool; this run proves the skill chain) and run:

1. `/game-dev:scaffold` — answer: directory `/tmp/moss-studio`, name `Moss`, defaults yes, git yes. Expected: the scaffold output, `studio-test` and `studio-run` output, the prototype gate's exit criteria quoted, and a question for the first feature. Answer: `a short dash, 3 tiles`.
2. The hand-off into `/game-dev:brainstorm` — expected: classification "bounded", one or two question batches, a spec at `docs/game-dev/specs/<date>-player-dash.md`, an artifact link, and a stop. Reply `approve`.
3. `/game-dev:plan` — expected: role- and verify-tagged tasks, a scope pass note (trail or sound cut if the spec mentioned them), `task: 0/N`, a stop. Reply `approve`.
4. `/game-dev:execute` — expected: a worktree, a `game-dev:gameplay-programmer` or `game-dev:feel-tuner` agent per task, failing GUT tests first on `Verify: unit` tasks, a reviewer after each, `stage: review`.
5. `/game-dev:review` — expected: findings (possibly none), `studio-test` re-run, `stage: playtest`.
6. `/game-dev:playtest` — expected: `studio-test` and `studio-run` results, a numbered script, one question per item (play the game in the editor or with `studio-run --windowed` while answering), a report at `docs/game-dev/playtests/<date>-player-dash.md`, a stop for sign-off. Reply `signed off`.

Confirm with `cat .studio/STATE.md`: `stage: ship`, `last_playtest: docs/game-dev/playtests/<date>-player-dash.md`, a ledger with `project scaffolded …`, `spec approved`, `plan approved`, `T<n> complete` lines, and `playtest signed off`.

- [ ] **Step 4: Record the result**

Append one line to the Plan 3 log entry in `docs/game-dev/PROGRESS.md`:

```markdown
- Verified on 2026-09-13: a new project went from an empty directory to a
  signed-off playtest of a dash through scaffold → brainstorm → plan →
  execute → review → playtest.
```

Commit:

```sh
git add docs/game-dev/PROGRESS.md
git commit -m "docs: record Plan 3 verification

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage (Plan 3 scope).** "Scaffold template" — every listed file → Task 1 (`project.godot` settings, `src/autoloads/event_bus.gd`, `src/player/` body plus state-machine skeleton, `resources/tuning/`, `tests/unit/test_smoke.gd`, `.studio/config.json`, `.studio/.gitignore`, docs `.gitkeep`s, `PROGRESS.md` with five gates, project `CLAUDE.md`, `.gitignore`, `.gdlintrc`); GUT not vendored, pinned, cloned by the scaffold with the manual step printed → Task 2. `studio-scaffold` verb contract (`DIR [--name NAME]`, exit 0/1, created tree listed) → Task 2. `/game-dev:scaffold` (frontmatter verbatim, runs the verb, delegates to `godot-prompter:godot-project-setup`, opens brainstorm) → Task 4. "Migration of existing content" (four skills renamed, content preserved) and the dimension seam (`## 2D` now, `## 3D` beside it, `config.dimension` selects) → Task 5. "Domain skills" `vertical-slice`, `tuning-data`, `milestone-gates` → Tasks 6–8. A game project's `PROGRESS.md` format with the gate as its first section → Task 1 (seed) and Task 8 (reference); `ship` and `studio` pointed at it → Task 8. `general` "same minimal content … stays tested" → Task 9. Testing case 9 (scaffold output, refusal on non-empty) → Task 2; case 10 (engine-dependent, skipped without Godot) → Task 3; the pressure-scenario paragraph → Task 10. README → Task 11. Exit criterion → Task 12.

**Placeholder scan.** No TBD/TODO. The `{{DATE}}` token in the template's `PROGRESS.md` is a substitution the scaffold performs and the tests assert is gone afterwards; the `…` cells in `milestone-gates`' format example stand for the table already written in full above it in the same file. The one `grep`-located edit (Task 8, `ship`) is because the file is Plan 2's and not on disk; the sentence to add is given in full.

**Name consistency.** `PlayerTuning`, `Player`, `StateMachine`, `PlayerState`, `Grounded`, `Airborne` are defined in Task 1's scripts and used by the same names in `player.tscn`, the tests, `CLAUDE.md`, and the pressure scenarios. `EventBus` signals `player_jumped`, `player_landed`, `level_started` match between `event_bus.gd`, the states, and `test_level.gd`. The `[level] ready:` line printed by `test_level.gd` is what Task 3's test and Task 4's skill look for. `STUDIO_GUT_REPO` / `STUDIO_GUT_REF` and the pin `v9.6.1` are the same in the scaffold, its tests, the fixture's tag, and the `PROGRESS.md` entry. The gate table in the template (Task 1) and in `milestone-gates` (Task 8) is word for word the same. Domain-skill names after Task 5 match the spec's agents table and the brainstorm sentence. `studio-state` subcommands used here (`init`, `set`, `ledger`) are Plan 1's. Scaffold exit codes match the Global Constraints and the spec's bin table.

**Fixed during review.** The template originally kept `.studio/STATE.md` as a file; it now comes from `studio-state init` so the state format has one writer, and the test asserts the template carries no `STATE.md`. The scaffold's name substitution originally used `sed` with an unguarded name; a name containing `"`, `|` or `&` is now refused, with a test. The engine-dependent test originally assumed `studio-test` would find GUT; it now treats exit 3 as a recorded skip so it passes offline.

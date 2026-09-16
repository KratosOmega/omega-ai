# Godot 4.x adapter

The `studio-*` verbs dispatch here when the engine is `godot4`. This file is
the one place the studio's roles are mapped to godot-prompter skills, so an
agent's own list can stay short, and the one place the engine's install
steps are written down.

Install: git clone --depth 1 --branch v9.6.1 https://github.com/bitwes/Gut.git /tmp/gut && mkdir -p addons && cp -R /tmp/gut/addons/gut addons/gut && rm -rf /tmp/gut

The `Install:` line above is read verbatim by `test.sh` when
`addons/gut/gut_cmdln.gd` is missing. GUT v9.6.1 targets Godot 4.6.x, which
matches the installed 4.6.3; 9.7.x targets 4.7 with breaking changes. Plan 3's
`studio-scaffold` uses the same tag; both must move together.

## Binary

`resolve.sh`: `$GODOT_PATH` → `$GODOT_APP_DIR/Godot*.app/Contents/MacOS/Godot`
(default `/Applications`) → `godot` on `PATH` → exit 2. Set `GODOT_PATH` in
the shell that launches `claude-gd` to pin a build.

## Verbs

| Verb | Command |
|------|---------|
| `test.sh [PATH]` | `godot --headless --path <project> -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=res://.studio/reports/test-<stamp>.xml` (`-gtest=res://<file>` for a single file) |
| `run.sh [--scene S] [--seconds N] [--windowed]` | `godot --headless --path <project> [S]` in the background for N seconds, then `TERM`; log scanned for `SCRIPT ERROR`, `ERROR:`, `Parser Error` |
| `lint.sh [PATH]` | `gdlint` then `gdformat --check` over every `.gd` outside `addons/` |

## Roles → godot-prompter skills

| Role | Skills |
|------|--------|
| `gameplay-programmer` | `gdscript-patterns`, `gdscript-advanced`, `state-machine`, `event-bus`, `component-system`, `resource-pattern`, `player-controller`, `physics-system`, `input-handling`, `godot-testing`, `godot-debugging` |
| `architect` | `godot-brainstorming`, `scene-organization`, `state-machine`, `event-bus`, `component-system`, `dependency-injection` |
| `level-designer` | `2d-essentials`, `procedural-generation` |
| `tech-artist` | `2d-essentials`, `assets-pipeline`, `particles-vfx` |
| `feel-tuner` | `input-handling`, `tween-animation`, `animation-system`, `camera-system` |
| `ui-designer` | `godot-ui`, `hud-system`, `responsive-ui`, `localization` |
| `playtester` | `godot-testing`, `godot-debugging` |
| `reviewer` | `godot-code-review`, `godot-optimization` |
| C# projects (`language: csharp`) | the `godot-csharp-engineer` agent replaces `gameplay-programmer` |

Every name above is a `godot-prompter:` skill declared in `requires.txt`.

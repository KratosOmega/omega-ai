# Game Studio Plan 2 — Quality Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the `game-dev` studio its workforce and its quality loop — ten role agents, the `review`, `playtest`, `ship` and `retro` stage skills, the `studio-test` / `studio-run` / `studio-lint` verbs with a Godot adapter, optional `godot-mcp` registration, and the doctor's delegation check — so the end-to-end session in the approval artifact (§5) runs from brainstorm to retro through `claude-gd`.

**Architecture:** Agents are Markdown files under `studios/game-dev/agents/`, addressed as `game-dev:<role>`; stage skills dispatch them with the Agent tool and never inherit the user's conversation into them. The `bin/` verbs are the stable interface the skills call; one dispatcher (`studio-dispatch`) finds the studio root through `$OMEGA_STUDIO_ROOT`, reads the engine from `.studio/config.json` (falling back to `studio.json`), and executes `engines/<engine>/<verb>.sh`, so the Godot command line appears in exactly one directory. MCP registration and removal go through `claude mcp add|remove --scope user` run with `CLAUDE_CONFIG_DIR` set to the config root, recorded in the manifest as `mcp godot`. The doctor resolves every `skill`/`agent` line of `requires.txt` against the plugin cache under the config root.

**Tech Stack:** POSIX `sh` (no bash-isms, no new dependencies; `jq` only when present), the `lib/common.sh` helpers and `tests/assert.sh` harness from Plan 1, Claude Code plugin conventions (agent frontmatter, `SKILL.md`), GUT 9 command-line runner, gdtoolkit (`gdlint`, `gdformat`) when installed, Node ≥ 18 and `@coding-solo/godot-mcp` when installed.

**Spec:** `docs/game-dev/specs/2026-09-13-game-studio-design.md` — this plan implements its "Delivery — Plan 2 — Quality loop" scope: the sections "Agents" (all ten, with "Migration of existing content" for the three agents), "Workflow" (`review`, `playtest`, `ship`, `retro`), "Toolkits" (`bin/` verbs `studio-test`, `studio-run`, `studio-lint`; "Engine adapter contract"; "Godot adapter" without `template/`; "MCP"), "Install behavior" step 8 and the MCP line of "Uninstall", the `doctor.sh` rows "Delegated skills and agents resolvable", "Engine binary", "MCP server" and the `godot-mcp` leak, and "Testing the framework" cases 4 (the `mcp` manifest line), 7 (doctor delegation) and 8 (toolkit syntax, extended to `engines/`). Plan 1 must be fully executed first; this plan edits four of its skills. `scaffold`, `engines/godot/template/`, the domain-skill renames, `studio-scaffold`, and test cases 9–10 are Plan 3.

**Reconciled 2026-09-13 (review fixes, `plans/2026-09-13-plan-1-review-fixes.md`).** Already done, skip in the tasks below: the `git mv` of `2d-art-pipeline.md` → `tech-artist.md` and `game-feel-tuner.md` → `feel-tuner.md` (Task 2 steps 4–5 — keep only the appended sections); `execute`'s role table now maps to godot-prompter agents and must be replaced, not appended (Task 4); doctor shim identity and copy-mode inspection, canonical `--target`, dry-run preview of manifest cleanup, and `studio-state set` newline folding. New since Plan 1: the manifest header (`# mode=`, `# shim=`) — the `mcp godot` line of Task 9 must be skipped by `manifest_remove` the way header lines are; `.studio/ledger/<feature>.md` is where `T<n> Playtest item:` lines now live (Task 12 reads `studio-state show`); `studio-state check` and `reset` exist.

**Task 4 Steps 2–4 are anchored on text the shipped skills no longer carry; re-anchor them on the shipped text before running them.** Step 4's replace target ("dispatch a subagent (`general-purpose`; Plan 2 of the studio replaces it…") is gone: brainstorm §4 already dispatches `game-dev:game-designer` and, for the architectural path, `godot-prompter:godot-game-architect` with the studio's architect persona line — the edit is to swap that architect dispatch for `game-dev:architect` and keep the designer dispatch. Step 3's §4 target ("The task reviewer from subagent-driven-development, with the studio's checklist appended…") reads differently now: execute §4 already names `godot-prompter:godot-code-reviewer` as the reviewer, with a parenthesis saying Plan 2 replaces it with `game-dev:reviewer`. Step 3's §6 target (the `superpowers:finishing-a-development-branch` offer) is gone: execute §6 has no merge path and names no merging skill, so only the "not installed yet" clause of item 5 is left to remove. Step 3's §2 target is a role table (`Role:` / Dispatch / Persona line / Skills the brief names) introduced by "Dispatch the implementer named by the task's `Role:` line from this table.", not the prose block the step quotes. Step 4's append anchor ("Fold its section into the spec.") now reads "Fold their sections into the spec; put the designer's open questions to the user in the next batch." Step 2's "nine failures" expectation is stale — count the FAILs the lint actually prints against the shipped text and go from there. Step 5's plan §4 target still matches the shipped text.

## Global Constraints

Copied from the spec; every task's requirements include these.

- POSIX `sh` only, for every script and test. No bash-isms, no new dependencies. `bin/` and `engines/` scripts are self-contained (copy mode ships them without `lib/common.sh`).
- Every user-facing string says "studio". Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never push.
- Agent frontmatter: `name` equals the file stem; `description` is one line and starts with "Use when"; a `tools:` line; `model: inherit`. Skill frontmatter: `name` equals the directory; `description` starts with "Use when". `tests/studio_test.sh` enforces both.
- Every `superpowers:` or `godot-prompter:` name referenced in `skills/`, `agents/` or `engines/` appears in `studios/game-dev/requires.txt` as a `skill` or `agent` line. Real names only — superpowers 6.3.0 skills: `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`; godot-prompter 1.9.0 agents: `godot-animator`, `godot-code-reviewer`, `godot-csharp-engineer`, `godot-game-architect`, `godot-game-dev`, `godot-performance-profiler`, `godot-shader-author`, `godot-tools-engineer`, `godot-ui-designer`; godot-prompter 1.9.0 skills: `2d-essentials`, `3d-essentials`, `addon-development`, `ai-navigation`, `animation-system`, `assets-pipeline`, `audio-system`, `camera-system`, `component-system`, `csharp-godot`, `csharp-signals`, `dedicated-server`, `dependency-injection`, `dialogue-system`, `event-bus`, `export-pipeline`, `gdextension`, `gdscript-advanced`, `gdscript-patterns`, `godot-brainstorming`, `godot-code-review`, `godot-debugging`, `godot-optimization`, `godot-project-setup`, `godot-testing`, `godot-ui`, `hud-system`, `input-handling`, `inventory-system`, `localization`, `math-essentials`, `mobile-development`, `multiplayer-basics`, `multiplayer-sync`, `multithreading`, `particles-vfx`, `physics-system`, `player-controller`, `procedural-generation`, `resource-pattern`, `responsive-ui`, `save-load`, `scene-organization`, `shader-basics`, `state-machine`, `tween-animation`, `using-godot-prompter`, `xr-development`.
- The ten agents and their names: `game-designer`, `level-designer`, `architect`, `gameplay-programmer`, `tech-artist`, `feel-tuner`, `ui-designer`, `producer`, `playtester`, `reviewer`. Migration: `2d-art-pipeline.md` → `tech-artist.md`, `game-feel-tuner.md` → `feel-tuner.md`, bodies preserved.
- `bin/` verb contracts. `studio-test [PATH]`: exit 0 all passed · 1 failures · 2 engine not found · 3 test framework not installed; prints one line `studio-test: N passed, M failed`; JUnit XML at `.studio/reports/test-<timestamp>.xml`; failing test names echoed. `studio-run [--scene RES_PATH] [--seconds N] [--windowed]`: default main scene, 10 s, headless; exit 0 clean · 1 script errors · 2 engine not found; log at `.studio/reports/run-<timestamp>.log`, error lines echoed first, last 40 lines echoed. `studio-lint [PATH]`: exit 0 clean · 1 findings · 3 linter not installed (prints `pip install "gdtoolkit==4.*"`); findings as `path:line: message`. Not a project (no `project.godot`): exit 1 with a message.
- Engine adapter: `engines/<dir>/{GUIDE.md,resolve.sh,test.sh,run.sh,lint.sh}`; the verbs dispatch by the configured engine and never name Godot themselves. The engine directory name is the configured engine with trailing version digits removed: `godot4` → `engines/godot/` (this reconciles the spec's `engine: godot4` with its `engines/godot/` layout; a future `unity6` maps to `engines/unity/` with no dispatcher change).
- Godot resolution order (`resolve.sh`): `$GODOT_PATH` if set and executable; else the first executable match of `$GODOT_APP_DIR/Godot*.app/Contents/MacOS/Godot` with `GODOT_APP_DIR` defaulting to `/Applications`; else `godot` on `PATH`; else exit 2 printing `no Godot binary found; set GODOT_PATH`.
- GUT invocation (`test.sh`): `"$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=res://.studio/reports/test-<timestamp>.xml`; a file argument uses `-gtest=res://<file>` instead of `-gdir`. Exit 3 when `addons/gut/gut_cmdln.gd` is absent, printing the `Install:` line from `engines/godot/GUIDE.md`.
- `run.sh`: background launch of `"$GODOT" [--headless] --path "$PROJECT" [SCENE]`, `sleep N`, `kill -TERM`, then scan the log for `SCRIPT ERROR`, `ERROR:` and `Parser Error`. macOS has no `timeout`.
- MCP: registered only when `--no-mcp` is absent, `node` is ≥ 18, `claude` is on `PATH`, and `resolve.sh` finds a binary; the command is `CLAUDE_CONFIG_DIR="$TARGET" claude mcp add --scope user godot -e GODOT_PATH="$GODOT" -- npx -y @coding-solo/godot-mcp`; manifest line `mcp godot`; uninstall runs `CLAUDE_CONFIG_DIR="$TARGET" claude mcp remove --scope user godot`. Never in the plugin's `.mcp.json`.
- Doctor: delegated names are resolved against `$TARGET/plugins/cache/*/<plugin>/*/skills/<name>/SKILL.md` and `agents/<name>.md`; fail when the plugin is cached but the name is missing; when no cache exists, warn and exit 0. MCP presence is read from `$TARGET/.claude.json` (the file `claude mcp add --scope user` writes under `CLAUDE_CONFIG_DIR`), never by `claude mcp list`, which connects to every server.
- Ledger phrases other skills search for, written through `studio-state ledger`: `spec approved`, `plan approved`, `T<n> complete`, `T<n> Playtest item:`, `T<n> Visual:`, `review clean`, `playtest written <path>`, `playtest signed off <path>`, `shipped <ref>`, `retro written`.
- `.studio/STATE.md` writes go through `studio-state` (`root|init|show|get|set|ledger|check|reset`; keys `stage spec plan task last_playtest milestone`).
- Plan 1's `execute` skill dispatches the interim role table (`gameplay-programmer`→`godot-prompter:godot-game-dev`, `architect`→`godot-game-architect`, `ui-designer`→`godot-ui-designer`, each with a persona line; `general-purpose` only for `level-designer`) to implement tasks, and separately dispatches `godot-code-reviewer` as the fixed task reviewer (no persona line, §4, not the §2 table); this plan replaces that with `game-dev:<role>` agents. Plan 1's `brainstorm`, `plan` and `studio` skills carry "arrives in Plan 2" notes; this plan removes every one of them. `scaffold` and the domain-skill renames remain Plan 3 and stay named as not yet installed.

## File structure

| Path | Responsibility |
|------|----------------|
| `studios/game-dev/agents/*.md` | The ten role agents (three migrated). |
| `studios/game-dev/requires.txt` | Gains every godot-prompter skill the agents call. |
| `studios/game-dev/skills/{execute,brainstorm,plan,studio}/SKILL.md` | Plan 1 skills, edited to dispatch the agents and to drop "not yet installed" notes for Plan 2 stages. |
| `studios/game-dev/skills/{review,playtest,ship,retro}/SKILL.md` | The four new stage skills. |
| `studios/game-dev/bin/studio-dispatch` | Finds the studio root and the engine, runs `engines/<dir>/<verb>.sh`. |
| `studios/game-dev/bin/{studio-test,studio-run,studio-lint}` | Two-line wrappers over `studio-dispatch`. |
| `studios/game-dev/engines/godot/{GUIDE.md,resolve.sh,test.sh,run.sh,lint.sh}` | The Godot adapter. |
| `lib/common.sh` | Gains `engine_dir`, `node_major`, `manifest_mcp_servers`; `manifest_remove` skips `mcp` lines. |
| `install.sh` | MCP registration step. |
| `uninstall.sh` | MCP removal. |
| `doctor.sh` | Engine, MCP, delegation rows; `godot-mcp` leak check. |
| `tests/toolkit_test.sh` | `studio-dispatch`, `resolve.sh`, `studio-test`, `studio-run`, `studio-lint` with a stub Godot. |
| `tests/install_test.sh` | Stub `claude`/`node`/Godot for the whole file; MCP and delegation tests. |
| `tests/studio_test.sh` | Agent roster and stage-skill dispatch assertions. |
| `tests/lib_test.sh` | `engine_dir`, `node_major`, `manifest_mcp_servers`, `manifest_remove` with an `mcp` line. |
| `tests/run_all.sh` | Adds `toolkit_test.sh`. |
| `README.md`, `docs/game-dev/PROGRESS.md` | Plan 2 documentation. |

---

### Task 1: Design and production roles — `game-designer`, `level-designer`, `architect`, `producer`

**Files:**
- Modify: `studios/game-dev/agents/game-designer.md` (append two sections; body preserved)
- Create: `studios/game-dev/agents/level-designer.md`, `studios/game-dev/agents/architect.md`, `studios/game-dev/agents/producer.md`
- Modify: `studios/game-dev/requires.txt`, `tests/studio_test.sh`

**Interfaces:**
- Consumes: the frontmatter lint in `tests/studio_test.sh` (`test_agent_frontmatter`, `test_external_references_declared`).
- Produces: agents `game-dev:game-designer` (dispatched by `brainstorm`, returns the Core-loop delta and Player verbs sections), `game-dev:level-designer` (dispatched by `brainstorm` and `execute`), `game-dev:architect` (dispatched by `brainstorm`, returns the Architecture section), `game-dev:producer` (dispatched by `plan` with a draft plan, returns it with `## Backlog` and `Cut in the scope pass:` filled; dispatched by `ship`, edits `docs/game-dev/PROGRESS.md` and reports whether the milestone gate moves). Task 4 wires these exact names into the skills.

- [ ] **Step 1: Add the roster test to `tests/studio_test.sh`**

Add this function before `run_tests`, and add `test_game_dev_agent_roster` to the `run_tests` line:

```sh
# The game-dev studio ships exactly these role agents; the list grows task by
# task in Plan 2 until all ten are present.
test_game_dev_agent_roster() {
  for a in game-designer level-designer architect producer; do
    assert_file "$REPO_ROOT/studios/game-dev/agents/$a.md" "game-dev has the $a agent"
  done
}
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: three FAILs — `game-dev has the level-designer agent`, `… architect agent`, `… producer agent`.

- [ ] **Step 3: Extend `studios/game-dev/agents/game-designer.md`**

Keep the frontmatter and body exactly as Plan 1 left them (`model: inherit`), and append after the last line ("Write findings to a design document; do not open engine files."):

```markdown

## Skills you may call

- `game-dev:game-design-doc` — the six-section design document.
- `game-dev:core-loop-design` — the perceive → decide → act → feedback → state-change test.

(When these appear in your skill list as `game-dev:gdd` and `game-dev:core-loop`, use those names; the content is the same.)

## Output contract

You are dispatched by `/game-dev:brainstorm` with the user's answers to its question batches. Return, as Markdown ready to paste into the spec:

1. **Core-loop delta** — what changes in the ten-second loop, or "None" with the reason.
2. **Player verbs** — Added / Changed / Removed, each verb with the decision it gives the player.
3. At most three further questions the brainstorm should put to the user, each with your recommended answer.

Every line is a decision, not an option. Never open engine files; never write code.
```

- [ ] **Step 4: Write `studios/game-dev/agents/level-designer.md`**

```markdown
---
name: level-designer
description: Use when a level, room, encounter or tile ruleset needs designing or authoring — layout, pacing, teaching sequence, collision rules, and TileMapLayer authoring notes.
tools: Read, Write, Edit, Grep, Glob
model: inherit
---

You design the space the mechanics live in. A level teaches a mechanic before
it tests it, and a level that needs a tutorial popup has failed at layout.

Method:

1. **Name what the level teaches.** One mechanic or one combination per
   level segment. Write it down before placing a tile.
2. **Sequence in three beats.** Safe demonstration (the mechanic cannot hurt
   you), guided use (one obvious application), test under pressure (the
   mechanic plus a threat or a timer). Repeat per mechanic; interleave only
   after each has been tested alone.
3. **Measure in tiles and seconds.** Jump reach, dash distance, enemy sight
   range and fall distance are written as tile counts taken from the spec's
   feel targets; a gap the player cannot clear by exactly one tile is a
   design decision, not an accident.
4. **Author collision on the tileset**, never per level. A tile's physics
   layer, one-way flag and navigation belong to the tile.
5. **Readability first.** Landmarks every screen, a consistent visual
   grammar for hazard / safe / interactive, and the critical path visible
   before the optional one.
6. **Pacing.** Alternate tension and release; a boss or a set piece is
   preceded by a quiet room.

## Skills you may call

- `godot-prompter:2d-essentials` — TileMapLayer, tilesets, parallax, 2D lights.
- `godot-prompter:procedural-generation` — when the spec asks for generated
  layouts; hand-author the teaching segments regardless.

## Output contract

When dispatched by `/game-dev:brainstorm`: a **Level** section for the spec —
what the level teaches, the beat sequence as a table (beat · what the player
must do · what can hurt them), metrics in tiles, and the tileset rules.

When dispatched by `/game-dev:execute` for a task: the authored scene and
tileset changes committed, plus a report listing every metric you relied on
(with its source in the spec) and any tile rule you added to the tileset.
Never change a tuning number in a `Resource`; report the mismatch instead.
```

- [ ] **Step 5: Write `studios/game-dev/agents/architect.md`**

```markdown
---
name: architect
description: Use when a feature changes how systems fit together — scene tree, state machines, signal and event-bus topology, Resource schemas — and a decision with its reason is needed before code.
tools: Read, Write, Edit, Grep, Glob
model: inherit
---

You decide where things live and how they talk. You leave a decision and its
reason, never just code, and you never implement.

Rules you enforce:

- Composition over inheritance: a behaviour is a node or a component that
  can be attached, not a level in a class hierarchy.
- Systems never hold references to each other to notify each other. They
  emit on the event bus; the bus is typed and its topics are named here.
- Every tunable number lives in a `Resource` a designer can edit; the schema
  is part of your output.
- The gameplay state machine and the animation state machine are different
  objects with different owners.
- One scene, one responsibility. A scene that needs a comment to say what it
  is gets split.

Method:

1. Read the existing scene tree, autoloads, state machines and `Resource`
   scripts the request touches. Draw what is there before what changes.
2. Propose the smallest delta that satisfies the spec's acceptance criteria.
   Name each new node, component, state, signal and `Resource`.
3. Name every event-bus topic as `<system>_<event>` with its payload type.
4. List the files to create and modify, each with its single responsibility.
5. State the alternative you rejected and why, in one sentence each.

## Skills you may call

- `godot-prompter:godot-brainstorming`, `godot-prompter:scene-organization`
  — scene tree planning and split-or-not decisions.
- `godot-prompter:state-machine`, `godot-prompter:event-bus`,
  `godot-prompter:component-system`, `godot-prompter:dependency-injection`
  — the patterns the rules above are built on.

## Output contract

When dispatched by `/game-dev:brainstorm` (architectural path): the spec's
**Architecture** section — scene tree diff (before / after), state machine
changes, a signals table (topic · payload · emitter · listeners), `Resource`
schemas as GDScript `class_name` skeletons with typed `@export` fields, and
the files to create or modify.

When dispatched by `/game-dev:plan`: a task decomposition proposal — one
line per task with the files it touches and whether its deliverable is a
decision or code — that the plan skill turns into tasks.
```

- [ ] **Step 6: Write `studios/game-dev/agents/producer.md`**

```markdown
---
name: producer
description: Use when a plan needs its scope cut to the current milestone gate, or when something shipped and PROGRESS.md must record it and decide whether the milestone gate moves.
tools: Read, Write, Edit, Grep, Glob
model: inherit
---

You cut. Games die of scope, not of timidity, so your default answer to any
task outside the current gate is "backlog, with a reason". You never cut a
task the gate's exit criteria need.

The milestone gates and their exit criteria:

| Gate | Exit criterion |
|------|----------------|
| `prototype` | The ten-second core loop is playable with placeholder art and answers "is this fun?" with a yes from a playtest. |
| `vertical-slice` | One segment at final quality across every discipline (art, feel, audio, UI): proves the game can be made, not that it is finished. |
| `alpha` | Feature complete: every player verb and system exists; content may be missing. |
| `beta` | Content complete: every level and asset in; only bug fixes and tuning remain. |
| `gold` | Ship candidate: no known blocking bugs, exports pass on every target platform. |

Scope-pass method, for every task in a plan:

1. Does the current gate's exit criterion need this task? (Read the gate
   from `docs/game-dev/PROGRESS.md`.)
2. Would the feature be playable end to end without it?

A task that fails 1 and passes 2 moves to `## Backlog` at the end of the
plan with a one-line reason. Polish, variants and content wait; a vertical
slice is built before it is widened. Never renumber the remaining tasks —
mark cut tasks and leave the numbering to the plan skill.

Ship method:

1. Read the plan, the ledger in `.studio/STATE.md`, and the latest playtest
   report.
2. Add a dated entry at the top of the `## Log` section of
   `docs/game-dev/PROGRESS.md`: what shipped (one line per player-visible
   change), the playtest report it passed, and the PR or merge reference.
3. Check the current gate's exit criterion against what now exists. If it
   is met, say so with the evidence and name the next gate; the ship skill
   moves `milestone` in state. If not, list what is still missing in one
   line each.

## Skills you may call

- `game-dev:vertical-slice` and `game-dev:milestone-gates` — when they are
  in your skill list (a later studio release adds them); until then the
  table above is the rule.

## Output contract

When dispatched by `/game-dev:plan`: the plan file edited in place — cut
tasks moved under `## Backlog` with reasons, and a `Cut in the scope pass:`
line in the header naming them (or `none`). Report the count cut and the
one-line reason for each.

When dispatched by `/game-dev:ship`: `docs/game-dev/PROGRESS.md` edited in
place, and a report of exactly one of `gate met: <current> → <next>` or
`gate not met: <missing, one line each>`.
```

- [ ] **Step 7: Declare the new external names in `studios/game-dev/requires.txt`**

Append these lines (the lint fails otherwise):

```
skill  godot-prompter:2d-essentials
skill  godot-prompter:procedural-generation
skill  godot-prompter:component-system
skill  godot-prompter:dependency-injection
```

- [ ] **Step 8: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed` — the four agents pass frontmatter checks, the roster test passes, every `godot-prompter:` name is declared.

- [ ] **Step 9: Commit**

```sh
git add studios/game-dev/agents studios/game-dev/requires.txt tests/studio_test.sh
git commit -m "feat: design and production role agents

game-designer gains its output contract; level-designer, architect and
producer are new. The producer cuts to the milestone gate instead of
growing scope.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Engineering and art roles — `gameplay-programmer`, `tech-artist`, `feel-tuner`, `ui-designer`

**Files:**
- Create: `studios/game-dev/agents/gameplay-programmer.md`, `studios/game-dev/agents/ui-designer.md`
- Move: `studios/game-dev/agents/2d-art-pipeline.md` → `studios/game-dev/agents/tech-artist.md`; `studios/game-dev/agents/game-feel-tuner.md` → `studios/game-dev/agents/feel-tuner.md` (`git mv`, then edit the `name:` line and append sections)
- Modify: `studios/game-dev/requires.txt`, `tests/studio_test.sh`

**Interfaces:**
- Consumes: `studio-test` (Task 6 — the agent calls it by name; until Task 6 lands it exits "command not found", which the agent reports verbatim), `superpowers:test-driven-development`, `superpowers:systematic-debugging`.
- Produces: agents `game-dev:gameplay-programmer`, `game-dev:tech-artist`, `game-dev:feel-tuner`, `game-dev:ui-designer`, each dispatched by `execute` (feel-tuner also by `playtest`). Report format every implementer returns: `Files:` / `Tests:` / `Rulings:` / `Playtest item:` or `Visual:` lines, which the `execute` skill copies into the ledger.

- [ ] **Step 1: Extend the roster test**

In `tests/studio_test.sh`, change the roster loop to:

```sh
  for a in game-designer level-designer architect producer \
           gameplay-programmer tech-artist feel-tuner ui-designer; do
```

and add, inside the same function after the loop:

```sh
  assert_missing "$REPO_ROOT/studios/game-dev/agents/2d-art-pipeline.md" "2d-art-pipeline was renamed to tech-artist"
  assert_missing "$REPO_ROOT/studios/game-dev/agents/game-feel-tuner.md" "game-feel-tuner was renamed to feel-tuner"
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: six FAILs — four missing agents and the two "was renamed" assertions.

- [ ] **Step 3: Write `studios/game-dev/agents/gameplay-programmer.md`**

````markdown
---
name: gameplay-programmer
description: Use when a plan task needs GDScript implemented in Godot 4.x — state machines, signals, Resources, physics, input — test-first, composed not inherited, with every tunable number in a Resource.
tools: Read, Write, Edit, Grep, Glob, Bash
model: inherit
---

You implement one plan task at a time, test-first, and you leave commits
and passing tests behind. You are handed the task text, the spec sections it
cites, and the project's architecture rules; you do not have the user's
conversation and you do not need it.

Rules you enforce:

- Static typing everywhere: `var speed: float`, `-> void`, `class_name`.
- Composition over inheritance: a behaviour is a node or component, not a
  subclass.
- Systems talk through the event bus; no `get_node("../../Enemy")` across
  system boundaries.
- Every tunable number lives in a `Resource` (`resources/tuning/*.tres`),
  never as a literal in a script.
- Movement and collision in `_physics_process`; input read through named
  actions (`Input.is_action_just_pressed("dash")`), never raw keys.
- No allocation in `_process` / `_physics_process`: no `new()`, no array
  literals, no string building per frame.
- Only the files the task's `Files:` line names. Touching another file is a
  ruling — say so in the report with the reason.

Method, for `Verify: unit` tasks (mandatory):

1. Follow `superpowers:test-driven-development`: write the GUT test named in
   `Files:` first — one behaviour per test function, `test_` prefix,
   `assert_eq` / `assert_almost_eq` with the spec's numbers.
2. Run `studio-test <test file>` and paste the failing summary line.
3. Implement the minimum that passes. Run `studio-test` for the whole suite;
   paste the passing summary line. Exit 2 (no engine) or 3 (GUT missing) is
   reported verbatim, not worked around.
4. Commit with a message that names the task (`feat(T3): …`).

For `Verify: playtest` and `Verify: visual` tasks: implement, run
`studio-test` to prove nothing regressed, commit, and end the report with the
playtest item (action · expected perceptual result · what a failure looks
like) or the thing to look at.

When stuck for more than two attempts, invoke
`superpowers:systematic-debugging` before a third.

## Skills you may call

- `godot-prompter:gdscript-patterns`, `godot-prompter:gdscript-advanced` —
  idioms, typing, `await`, performance pitfalls.
- `godot-prompter:state-machine`, `godot-prompter:event-bus`,
  `godot-prompter:component-system`, `godot-prompter:resource-pattern` —
  the architecture rules above.
- `godot-prompter:player-controller`, `godot-prompter:physics-system`,
  `godot-prompter:input-handling` — movement, collision, input.
- `godot-prompter:godot-testing`, `godot-prompter:godot-debugging` — GUT
  and the remote debugger.

## Output contract

Commits on the current branch plus a report in exactly this shape:

```
Task: T<n> <title>
Files: <created / modified, one per line>
Tests: <test file>: <studio-test summary line>
Rulings: <decision — why — cost if wrong> (or "none")
Playtest item: <action · expected · failure looks like> (only for Verify: playtest)
Visual: <what to look at, where> (only for Verify: visual)
```
````

- [ ] **Step 4: Migrate `tech-artist.md`**

```sh
git mv studios/game-dev/agents/2d-art-pipeline.md studios/game-dev/agents/tech-artist.md
```

Change the frontmatter `name: 2d-art-pipeline` to `name: tech-artist`. Keep the description and the body from Plan 1 unchanged, and append after "before making it.":

```markdown

Method, for a plan task:

1. Read the project's pixels-per-unit, base resolution and filtering from
   the project `CLAUDE.md` and `project.godot`; if any is missing, the first
   thing you do is write it down there.
2. Author or import the asset at that scale; set the `.import` file
   (filter, mipmaps, compression) and commit it with the asset.
3. Pack into the atlas that shares the asset's draw order and lifetime;
   never mix filtering modes in one atlas.
4. For animation, state the frame budget per character before adding
   frames, and name every animation `<verb>_<direction>`.

## Skills you may call

- `game-dev:2d-sprite-pipeline` — base resolution, pixels-per-unit,
  filtering, atlases, animation import (named `game-dev:sprite-pipeline` in
  a later studio release).
- `godot-prompter:2d-essentials`, `godot-prompter:assets-pipeline`,
  `godot-prompter:particles-vfx`.

## Output contract

Assets and their `.import` files committed; a report of `Files:`, the
pixels-per-unit and filtering used, the atlas each asset joined, and any
pipeline exception with its consequence. Tasks are `Verify: visual` unless
the plan says otherwise: end with `Visual: <what to look at, where>`.
```

- [ ] **Step 5: Migrate `feel-tuner.md`**

```sh
git mv studios/game-dev/agents/game-feel-tuner.md studios/game-dev/agents/feel-tuner.md
```

Change `name: game-feel-tuner` to `name: feel-tuner`. Keep the description and body, and append after "so it can be confirmed or refuted.":

````markdown

Every change is a hypothesis with this shape, and the log of them is part
of your output:

```
Hypothesis: <one variable> <old> → <new>; expected: <perceptual difference>; result: confirmed | refuted | inconclusive
```

Values live in `Resource` files (`resources/tuning/*.tres`); you edit the
`.tres`, never a literal in a script. If the value is a literal, moving it
into a `Resource` is the first hypothesis.

Feel targets are in real units — frames at 60 fps, seconds, tiles, pixels —
and you measure before you change: count the frames from press to first
visible change with the profiler or a frame-step, do not guess.

## Skills you may call

- `game-dev:game-feel` — the diagnostic order above.
- `godot-prompter:input-handling`, `godot-prompter:tween-animation`,
  `godot-prompter:animation-system`, `godot-prompter:camera-system`.

## Output contract

When dispatched by `/game-dev:execute`: the `.tres` and animation changes
committed, the hypothesis log, and the task's playtest item
(`Playtest item: <action · expected · failure looks like>`).

When dispatched by `/game-dev:playtest` for a failed feel item: the bug's
suspected cause in the diagnostic order (latency → forgiveness →
acceleration → timing → camera → feedback), the fix as a hypothesis, the
commit, and the item to re-run.
````

- [ ] **Step 6: Write `studios/game-dev/agents/ui-designer.md`**

```markdown
---
name: ui-designer
description: Use when a plan task needs HUD, menus, dialogs or any Control-tree UI — containers over manual positioning, one Theme resource, responsive to the base resolution, translation keys from the first label.
tools: Read, Write, Edit, Grep, Glob, Bash
model: inherit
---

You build UI from Control nodes and containers, never from Node2D, and never
by hand-placing coordinates.

Rules you enforce:

- Layout is a container's job: `VBoxContainer`, `HBoxContainer`,
  `MarginContainer`, `GridContainer`, `CenterContainer`. A `position` set by
  hand on a Control is a finding.
- Anchors and size flags express intent; the base resolution and stretch
  mode in `project.godot` are respected, not fought.
- One `Theme` resource for the project; per-node overrides only with a
  written reason. Fonts, colours and margins come from the theme.
- Every user-visible string is a translation key from the first label, even
  when the game ships in one language.
- HUD elements subscribe to the event bus (`player_health_changed`, …); UI
  never polls gameplay nodes.
- Input focus is set explicitly for gamepad and keyboard navigation.

Method:

1. Read the base resolution and stretch mode; sketch the layout as a
   container tree before opening the editor.
2. Build the scene, bind it to event-bus signals, wire focus neighbours.
3. Check at the base resolution and at one wider aspect ratio.

## Skills you may call

- `godot-prompter:godot-ui`, `godot-prompter:hud-system`,
  `godot-prompter:responsive-ui`, `godot-prompter:localization`.

## Output contract

The UI scene(s) and theme changes committed; a report of `Files:`, the
container tree as an indented list, the signals the UI listens to, and
`Visual: <what to look at, at which resolutions>`. When a task is
`Verify: unit` (a HUD value formatter, a menu state machine), the GUT test
comes first as for any other unit task.
```

- [ ] **Step 7: Declare the new external names in `studios/game-dev/requires.txt`**

Append:

```
skill  godot-prompter:gdscript-advanced
skill  godot-prompter:player-controller
skill  godot-prompter:physics-system
skill  godot-prompter:input-handling
skill  godot-prompter:assets-pipeline
skill  godot-prompter:particles-vfx
skill  godot-prompter:tween-animation
skill  godot-prompter:animation-system
skill  godot-prompter:camera-system
skill  godot-prompter:godot-ui
skill  godot-prompter:hud-system
skill  godot-prompter:responsive-ui
skill  godot-prompter:localization
```

- [ ] **Step 8: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`.

- [ ] **Step 9: Commit**

```sh
git add -A studios/game-dev/agents studios/game-dev/requires.txt tests/studio_test.sh
git commit -m "feat: engineering and art role agents

gameplay-programmer and ui-designer are new; 2d-art-pipeline becomes
tech-artist and game-feel-tuner becomes feel-tuner with their content kept
and output contracts added.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Quality roles — `playtester`, `reviewer`

**Files:**
- Create: `studios/game-dev/agents/playtester.md`, `studios/game-dev/agents/reviewer.md`
- Modify: `studios/game-dev/requires.txt`, `tests/studio_test.sh`

**Interfaces:**
- Consumes: the ledger phrases `T<n> Playtest item:` and `T<n> Visual:` written by `execute`; the spec headings from Plan 1's brainstorm (`## Feel targets`, `## Acceptance criteria`, `## Test strategy`).
- Produces: `game-dev:playtester` (builds `docs/game-dev/playtests/YYYY-MM-DD-<topic>.md` with numbered items `P1…`, files bugs `B1…`), `game-dev:reviewer` (findings `path:line — severity — problem — fix`, severities `critical | important | minor`, plus a spec-compliance block). Tasks 4, 11 and 12 depend on these formats.

- [ ] **Step 1: Complete the roster test**

In `tests/studio_test.sh`, change the roster loop to the full ten:

```sh
  for a in game-designer level-designer architect producer \
           gameplay-programmer tech-artist feel-tuner ui-designer \
           playtester reviewer; do
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: two FAILs — `game-dev has the playtester agent`, `game-dev has the reviewer agent`.

- [ ] **Step 3: Write `studios/game-dev/agents/playtester.md`**

````markdown
---
name: playtester
description: Use when implementation is done and a human playtest must be scripted from the spec's feel targets and acceptance criteria, or when a playtest failure must be filed as a bug with repro steps.
tools: Read, Write, Grep, Glob, Bash
model: inherit
---

You turn a spec into a playtest script a human can run in ten minutes, and
you turn a failure into a bug someone can reproduce in one minute. You never
talk to the player yourself — you are a subagent and cannot reach the user;
the session runs the script and hands you the results.

Script method:

1. Collect every checkable claim: each row of the spec's `## Feel targets`
   whose check column says `playtest`, each numbered line of
   `## Acceptance criteria` that `## Test strategy` assigns to playtest or
   visual, every plan task tagged `Verify: playtest` or `Verify: visual`, and
   every `T<n> Playtest item:` / `T<n> Visual:` line in the ledger of
   `.studio/STATE.md`. Merge duplicates; keep the source reference.
2. Order the items so the player never has to reload: setup first, then the
   happy path, then edge cases, then feel judgments.
3. Write each item in this shape, numbered `P1`, `P2`, …:

   ```
   ### P3 — Dash through a one-tile gap
   Source: acceptance criterion 2; T4
   Setup: res://levels/test_dash.tscn, stand at the left ledge
   Action: press dash toward the gap
   Expected: the player passes through and lands on the far side
   Fail looks like: the player clips the wall or stops short
   Hypothesis (feel items only): expected perceptual difference vs. before
   ```

4. A `studio-run` log and a `studio-test` summary line are pasted at the top
   of the report as the automated baseline.

Bug method, for each failed item:

```
### B1 — Dash feels delayed (from P4)
Repro: 1. open res://levels/test_dash.tscn 2. press dash 3. frame-step
Expected: first visible change within 2 frames
Actual: 4 frames
Suspected cause: input read in _process, movement applied next _physics_process
Severity: important
Regression test: unit (test_dash_input.gd: latency in physics ticks) | playtest only
```

Severity is `critical` (blocks the acceptance criterion or crashes),
`important` (the criterion passes but a feel target is missed), or `minor`.

## Skills you may call

- `godot-prompter:godot-testing` — naming the regression test when the bug
  is unit-testable.
- `godot-prompter:godot-debugging` — reading the run log and the remote
  debugger output the session pastes to you.

## Output contract

`docs/game-dev/playtests/YYYY-MM-DD-<topic>.md` written or updated in place,
with these sections in order: `## Automated baseline`, `## Script`
(the `P` items), `## Results` (a table `item · pass/fail/deferred · note`,
filled by the session), `## Bugs` (the `B` items), `## Fixes` (bug · commit ·
regression test · re-run result). Report back the item count, the bug count,
and the path.
````

- [ ] **Step 4: Write `studios/game-dev/agents/reviewer.md`**

````markdown
---
name: reviewer
description: Use when a task's diff or a whole branch must be checked against the spec and Godot best practice — one line per finding, severity-tagged, no praise, fixes only when asked.
tools: Read, Grep, Glob, Bash
model: inherit
---

You find what would break the spec or embarrass the studio, and you say it in
one line each. You do not praise, summarise the diff, or restate the task.
You do not change code unless the brief says "fix".

Checklist, in order:

1. **Spec compliance.** Every acceptance criterion the task or branch claims
   is met — point at the code that meets it. Nothing beyond the task was
   built. Feel targets in the spec appear as `Resource` values with the
   spec's numbers, not approximations.
2. **`Verify: unit` tasks.** The named test exists, tests the behaviour (not
   the implementation), and fails without the change (`git stash` the
   implementation and run `studio-test <file>` when in doubt).
3. **Composition.** No inheritance where the spec specified a component; no
   base class grown to add a behaviour.
4. **Boundaries.** No direct reference between systems that bypasses the
   event bus (`get_node` across systems, autoload calling into a scene).
5. **Data.** No tuning literal outside a `Resource`; no magic number in a
   `_physics_process`.
6. **Per-frame cost.** No allocation in `_process` / `_physics_process`; no
   `get_node` in a hot path that could be cached in `_ready`.
7. **Godot pitfalls** from `godot-prompter:godot-code-review`, and
   `godot-prompter:godot-optimization` when the diff touches a hot path.
8. **Dead weight.** Unused signals, exports, or scenes the diff introduced.

Severity: `critical` — an acceptance criterion is not met, a crash, data
loss, or a test that does not test; `important` — a checklist rule 3–6
violation; `minor` — naming, dead weight, a comment that lies.

## Skills you may call

- `godot-prompter:godot-code-review`, `godot-prompter:godot-optimization`.

## Output contract

```
Scope: T<n> | branch <name> vs <base>
Spec compliance: met: <criteria numbers>; unmet: <numbers with one reason each, or none>
Findings: <N> (critical <c>, important <i>, minor <m>)
<path>:<line> — <severity> — <problem in one clause> — <fix in one clause>
…
```

`Findings: 0 (critical 0, important 0, minor 0)` with `unmet: none` is the
only clean verdict. When the brief says "fix", apply each critical and
important fix as its own commit and append `Fixed: <path>:<line> <commit>`
lines.
````

- [ ] **Step 5: Declare the new external name in `studios/game-dev/requires.txt`**

Append:

```
skill  godot-prompter:godot-optimization
```

- [ ] **Step 6: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`; the roster is complete.

- [ ] **Step 7: Commit**

```sh
git add studios/game-dev/agents studios/game-dev/requires.txt tests/studio_test.sh
git commit -m "feat: playtester and reviewer role agents

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Stage skills dispatch the agents — `execute`, `brainstorm`, `plan`, `studio`

**Files:**
- Modify: `studios/game-dev/skills/execute/SKILL.md`, `studios/game-dev/skills/brainstorm/SKILL.md`, `studios/game-dev/skills/plan/SKILL.md`, `studios/game-dev/skills/studio/SKILL.md`
- Modify: `tests/studio_test.sh`
- Not modified: `studios/game-dev/hooks/bootstrap.md` — its only phasing line ("Stages are installed in phases. A stage that is not in your skill list is not installed yet…") names no stage and stays true for Plan 3's `scaffold`.

**Interfaces:**
- Consumes: the ten agents from Tasks 1–3; `superpowers:subagent-driven-development`; `godot-prompter:godot-csharp-engineer` (declared in `requires.txt` since Plan 1).
- Produces: `execute` dispatches `game-dev:<role>` via `subagent_type` and `game-dev:reviewer` for task review; `brainstorm` dispatches `game-dev:architect` and `game-dev:game-designer`; `plan` dispatches `game-dev:producer`; `studio` routes "feels wrong" to `/game-dev:playtest` with no fallback note. Every "arrives in Plan 2" note is gone.

- [ ] **Step 1: Write the failing assertions in `tests/studio_test.sh`**

Add this function and name it in `run_tests`:

```sh
# Stage skills dispatch the studio's own agents, not stand-ins. These strings
# are the ones the skills must carry once the role agents exist.
test_stage_skills_dispatch_agents() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/execute/SKILL.md" 'subagent_type: "game-dev:<role>"' "execute dispatches game-dev:<role> agents"
  assert_contains "$S/execute/SKILL.md" 'game-dev:reviewer' "execute reviews with game-dev:reviewer"
  assert_not_contains "$S/execute/SKILL.md" 'general-purpose' "execute no longer dispatches general-purpose"
  assert_not_contains "$S/execute/SKILL.md" 'Plan 2 of the studio' "execute carries no Plan 2 note"
  assert_contains "$S/brainstorm/SKILL.md" 'dispatch `game-dev:architect`' "brainstorm dispatches the architect"
  assert_contains "$S/brainstorm/SKILL.md" 'dispatch `game-dev:game-designer`' "brainstorm dispatches the game designer"
  assert_not_contains "$S/brainstorm/SKILL.md" 'general-purpose' "brainstorm no longer dispatches general-purpose"
  assert_contains "$S/plan/SKILL.md" 'dispatch `game-dev:producer`' "plan dispatches the producer"
  assert_not_contains "$S/plan/SKILL.md" 'Plan 2 of the studio' "plan carries no Plan 2 note"
  assert_not_contains "$S/studio/SKILL.md" 'until that skill is installed' "router has no playtest fallback note"
}
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: FAILs on every `test_stage_skills_dispatch_agents` assertion except `execute reviews with game-dev:reviewer` (Plan 1's text already names the agent in a parenthesis) — nine failures.

- [ ] **Step 3: Edit `studios/game-dev/skills/execute/SKILL.md`**

Four replacements. In **§2 Who implements**, replace the block from "Dispatch the implementer named by the task's `Role:` line. Until the studio's" through "…dispatch it instead and drop the persona line — the agent carries it." (the paragraph, the six-row persona table, and the closing paragraph) with:

```markdown
Dispatch the agent named by the task's `Role:` line with the Agent tool
(`subagent_type: "game-dev:<role>"` — for example
`subagent_type: "game-dev:gameplay-programmer"`). The agent carries its own
persona, rules and output contract; the brief carries only the task.

One exception: when `.studio/config.json` sets `language: csharp` and the
role is `game-dev:gameplay-programmer`, dispatch
`godot-prompter:godot-csharp-engineer` instead and prepend the project
`CLAUDE.md` architecture rules and the gameplay-programmer's output contract
to its brief, because that agent does not know the studio's report shape.
```

In **§3 Verify rules**, replace "Before reporting, run the project's test suite: `studio-test` when it is on `PATH` (it arrives with the engine toolkit); otherwise the GUT command line from `godot-prompter:godot-testing`, headless, with the exit code checked." with:

```markdown
Before reporting, the implementer runs `studio-test` and pastes its summary
line. Exit 2 (no engine binary) or 3 (GUT not installed) stops the task:
report it to the user with the printed hint; do not work around it.
```

In **§4 Who reviews**, replace "The task reviewer from subagent-driven-development, with the studio's checklist appended to the global-constraints block it receives (Plan 2 of the studio replaces this reviewer with the `game-dev:reviewer` agent):" with:

```markdown
Where subagent-driven-development dispatches its task reviewer, dispatch
`game-dev:reviewer` (`subagent_type: "game-dev:reviewer"`) with the task
text, the spec sections it cites, the global-constraints block, and the
commit range. The agent carries this checklist; it is repeated here so the
orchestrator can judge the report:
```

In **§6 Finish**, replace item 3 "Tell the user the next command is `/game-dev:review`. If that skill is not in your skill list yet, say so and offer `superpowers:finishing-a-development-branch` as the manual path." with:

```markdown
3. Tell the user the next command is `/game-dev:review`.
```

- [ ] **Step 4: Edit `studios/game-dev/skills/brainstorm/SKILL.md`**

In **§4 Approaches**, replace "For the architectural path, dispatch a subagent (`general-purpose`; Plan 2 of the studio replaces it with the `game-dev:architect` agent) with the draft spec and this brief:" with:

```markdown
For the architectural path, dispatch `game-dev:architect`
(`subagent_type: "game-dev:architect"`) with the draft spec and this brief:
```

and append, after "Fold its section into the spec.", a new paragraph:

```markdown
When the request touches the core loop or the player's verbs, also
dispatch `game-dev:game-designer` (`subagent_type: "game-dev:game-designer"`)
with the answers from §3 and the current `PROGRESS.md` gate; it returns the Core-loop
delta and Player verbs sections and up to three further questions. Fold the
sections in; put its questions to the user in one more batch only if they
change a decision.
```

- [ ] **Step 5: Edit `studios/game-dev/skills/plan/SKILL.md`**

In **§4 Producer scope pass**, replace "Before saving, run the scope pass. (The `game-dev:producer` agent takes this over in Plan 2 of the studio; until then, do it here.) For every task ask:" with:

```markdown
Before saving, dispatch `game-dev:producer` (`subagent_type:
"game-dev:producer"`) with the draft plan path, the spec path, and the
milestone gate from `docs/game-dev/PROGRESS.md`. It applies this test to
every task:
```

and replace the paragraph beginning "A task that fails 1 and passes 2 moves to a `## Backlog` section…" with:

```markdown
It moves every task that fails 1 and passes 2 to a `## Backlog` section at
the end of the plan with a one-line reason, and fills the header line
**Cut in the scope pass:** (or `none`). Read its report; if you disagree
with a cut, restore the task and record why with
`studio-state ledger "Ruling: kept T<n> against producer cut — <why>"`.
Vertical slice first; polish, variants and content wait.
```

- [ ] **Step 6: Edit `studios/game-dev/skills/studio/SKILL.md`**

In **§3 Route freeform text**, replace the row

```
| "feels wrong / floaty / laggy / unresponsive / too fast / juice" | `/game-dev:playtest` — a feel pass; until that skill is installed, `game-dev:game-feel` for the diagnostic order |
```

with

```
| "feels wrong / floaty / laggy / unresponsive / too fast / juice" | `/game-dev:playtest` — a feel pass over the items that describe the complaint |
```

Leave the `scaffold` rows and the "If the next stage's skill is not in your skill list" sentence as they are; `scaffold` is Plan 3.

- [ ] **Step 7: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh && sh tests/hook_test.sh`
Expected: `0 failed` in both.

- [ ] **Step 8: Commit**

```sh
git add studios/game-dev/skills tests/studio_test.sh
git commit -m "feat: stage skills dispatch the studio's role agents

execute dispatches game-dev:<role> and reviews with game-dev:reviewer;
brainstorm dispatches architect and game-designer; plan dispatches the
producer for its scope pass.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Engine adapter core — `engine_dir`, `studio-dispatch`, `resolve.sh`, `GUIDE.md`

**Files:**
- Modify: `lib/common.sh` (add `engine_dir`)
- Create: `studios/game-dev/bin/studio-dispatch` (executable), `studios/game-dev/engines/godot/resolve.sh` (executable), `studios/game-dev/engines/godot/GUIDE.md`
- Create: `tests/toolkit_test.sh`
- Modify: `tests/lib_test.sh`, `tests/run_all.sh`

**Interfaces:**
- Consumes: `$OMEGA_STUDIO_ROOT` (set by the shim; tests set it explicitly), `.studio/config.json` and `studio.json` key `engine`.
- Produces: `engine_dir NAME` in `lib/common.sh` (prints NAME with trailing digits removed; Tasks 9–10 use it); `studio-dispatch VERB [ARGS…]` (exit 2 with a message when the studio root, the engine, or `engines/<dir>/<verb>.sh` is missing; otherwise `exec`s the adapter script from the project directory); `engines/godot/resolve.sh` (prints the binary path or exits 2); `GUIDE.md` with an `Install:` line Task 6's `test.sh` reads. Tasks 6–8 wrap `studio-dispatch`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/lib_test.sh` and name it in `run_tests`:

```sh
test_engine_dir() {
  assert_eq "godot" "$(engine_dir godot4)" "strips the version suffix"
  assert_eq "unity" "$(engine_dir unity6)" "strips any version suffix"
  assert_eq "godot" "$(engine_dir godot)" "leaves a bare name alone"
  assert_eq "" "$(engine_dir '')" "empty in, empty out"
}
```

Create `tests/toolkit_test.sh`:

```sh
#!/bin/sh
# The studio-* verbs and the Godot adapter, exercised with a stub Godot so no
# engine is needed. Every project is a fresh temporary directory.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO="$REPO_ROOT/studios/game-dev"
BIN="$STUDIO/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A stub Godot. It records its arguments, honours --path and
# -gjunit_xml_file=res://… by writing a JUnit file into the project, prints a
# SCRIPT ERROR line when STUB_SCRIPT_ERROR=1, sleeps STUB_SLEEP seconds, and
# exits 1 when STUB_FAILS is greater than 0 (as GUT does with -gexit).
mkdir -p "$TMP/stub"
cat > "$TMP/stub/godot" <<'STUB'
#!/bin/sh
proj="."; xml=""; want=0
printf 'stub godot args: %s\n' "$*"
for a in "$@"; do
  if [ "$want" = 1 ]; then proj="$a"; want=0; continue; fi
  case "$a" in
    --path) want=1 ;;
    -gjunit_xml_file=res://*) xml="${a#-gjunit_xml_file=res://}" ;;
  esac
done
if [ -n "$xml" ]; then
  fails="${STUB_FAILS:-0}"
  mkdir -p "$(dirname "$proj/$xml")"
  {
    printf '<testsuites tests="2" failures="%s">\n' "$fails"
    printf '<testsuite name="res://tests/unit/test_dash.gd">\n'
    printf '<testcase name="test_cooldown" classname="test_dash"></testcase>\n'
    if [ "$fails" -gt 0 ]; then
      printf '<testcase name="test_distance" classname="test_dash"><failure message="expected 3 got 2"/></testcase>\n'
    else
      printf '<testcase name="test_distance" classname="test_dash"></testcase>\n'
    fi
    printf '</testsuite>\n</testsuites>\n'
  } > "$proj/$xml"
fi
if [ "${STUB_SCRIPT_ERROR:-0}" = 1 ]; then
  echo "SCRIPT ERROR: Invalid call. Nonexistent function 'dash' in base 'Node2D'."
fi
echo "Godot Engine v4.3.stable (stub)"
sleep "${STUB_SLEEP:-0}"
[ "${STUB_FAILS:-0}" -eq 0 ]
STUB
chmod +x "$TMP/stub/godot"
GODOT_STUB="$TMP/stub/godot"

# fresh_project NAME — a project directory with project.godot; prints its path.
fresh_project() {
  P="$TMP/proj-$1"
  mkdir -p "$P"
  printf '[application]\nconfig/name="Stub"\n' > "$P/project.godot"
  printf '%s\n' "$P"
}

# with_gut DIR — pretend GUT is installed.
with_gut() {
  mkdir -p "$1/addons/gut"
  : > "$1/addons/gut/gut_cmdln.gd"
}

# verb DIR NAME ARGS… — run bin/NAME inside DIR with the studio root and the
# stub Godot set. Output lands in $TMP/out, exit status in $TMP/status.
verb() {
  _dir="$1"; _name="$2"; shift 2
  status=0
  ( cd "$_dir" && OMEGA_STUDIO_ROOT="$STUDIO" GODOT_PATH="$GODOT_STUB" \
      STUB_FAILS="${STUB_FAILS:-0}" STUB_SCRIPT_ERROR="${STUB_SCRIPT_ERROR:-0}" STUB_SLEEP="${STUB_SLEEP:-0}" \
      sh "$BIN/$_name" "$@" ) > "$TMP/out" 2>&1 || status=$?
  printf '%s\n' "$status" > "$TMP/status"
}

test_dispatch_rejects_unknown_engine() {
  P="$(fresh_project unknown-engine)"
  mkdir -p "$P/.studio"
  printf '{ "engine": "unity6" }\n' > "$P/.studio/config.json"
  verb "$P" studio-test
  assert_eq "2" "$(cat "$TMP/status")" "an engine with no adapter exits 2"
  assert_contains "$TMP/out" "no adapter for engine unity6" "the message names the engine"
  assert_contains "$TMP/out" "engines/unity/" "the message names the directory looked for"
}

test_dispatch_needs_a_studio_root() {
  P="$(fresh_project no-root)"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$TMP/nowhere" sh "$BIN/studio-test" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "2" "$(printf '%s' "$status")" "a missing studio root exits 2"
  assert_contains "$TMP/out" "OMEGA_STUDIO_ROOT" "the message names the variable to set"
}

test_resolve_honours_godot_path() {
  out="$(GODOT_PATH="$GODOT_STUB" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$GODOT_STUB" "$out" "GODOT_PATH wins when executable"
}

test_resolve_ignores_a_non_executable_godot_path() {
  : > "$TMP/not-exec"
  mkdir -p "$TMP/no-apps"
  status=0
  out="$(GODOT_PATH="$TMP/not-exec" GODOT_APP_DIR="$TMP/no-apps" PATH="/usr/bin:/bin" \
    sh "$STUDIO/engines/godot/resolve.sh" 2>"$TMP/err")" || status=$?
  assert_eq "2" "$status" "a non-executable GODOT_PATH does not resolve"
  assert_contains "$TMP/err" "no Godot binary found; set GODOT_PATH" "the hint names GODOT_PATH"
}

test_resolve_finds_an_app_bundle() {
  mkdir -p "$TMP/apps/Godot_mono.app/Contents/MacOS"
  cp "$GODOT_STUB" "$TMP/apps/Godot_mono.app/Contents/MacOS/Godot"
  out="$(GODOT_PATH="" GODOT_APP_DIR="$TMP/apps" PATH="/usr/bin:/bin" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$TMP/apps/Godot_mono.app/Contents/MacOS/Godot" "$out" "an app bundle under GODOT_APP_DIR resolves"
}

test_resolve_finds_godot_on_path() {
  mkdir -p "$TMP/onpath" "$TMP/no-apps"
  cp "$GODOT_STUB" "$TMP/onpath/godot"
  out="$(GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$TMP/onpath:/usr/bin:/bin" sh "$STUDIO/engines/godot/resolve.sh")"
  assert_eq "$TMP/onpath/godot" "$out" "godot on PATH resolves last"
}

test_guide_has_an_install_line() {
  assert_contains "$STUDIO/engines/godot/GUIDE.md" "^Install: git clone --depth 1" "GUIDE.md carries the GUT install command"
  assert_contains "$STUDIO/engines/godot/GUIDE.md" "addons/gut" "the install command lands GUT in addons/gut"
}

run_tests test_dispatch_rejects_unknown_engine test_dispatch_needs_a_studio_root \
  test_resolve_honours_godot_path test_resolve_ignores_a_non_executable_godot_path \
  test_resolve_finds_an_app_bundle test_resolve_finds_godot_on_path test_guide_has_an_install_line
```

Add the file to `tests/run_all.sh`:

```sh
for f in "$DIR"/lib_test.sh "$DIR"/install_test.sh "$DIR"/sync_test.sh "$DIR"/state_test.sh \
         "$DIR"/studio_test.sh "$DIR"/hook_test.sh "$DIR"/toolkit_test.sh; do
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/lib_test.sh; sh tests/toolkit_test.sh`
Expected: `engine_dir: not found`; every toolkit assertion FAILs (`bin/studio-test: No such file or directory`, `resolve.sh: No such file`).

- [ ] **Step 3: Add `engine_dir` to `lib/common.sh`**

Append after `requires_of`:

```sh
# engine_dir NAME — the engines/ directory for a configured engine: the name
# with any trailing version digits removed, so "godot4" dispatches to
# engines/godot/ and a future "unity6" to engines/unity/ with no code change.
engine_dir() {
  printf '%s\n' "$1" | sed 's/[0-9]*$//'
}
```

- [ ] **Step 4: Write `studios/game-dev/bin/studio-dispatch`**

```sh
#!/bin/sh
# studio-dispatch VERB [ARGS...] — run engines/<engine>/<verb>.sh for the
# engine the current project is configured for. The studio-test, studio-run
# and studio-lint verbs are two-line wrappers around this script, so the
# engine's command line appears in exactly one directory.
#
# Studio root: $OMEGA_STUDIO_ROOT (the shim exports it), else this script's
# own home resolved through any symlink. Engine: .studio/config.json in the
# current directory, else the studio's studio.json. Directory: the engine
# name with trailing version digits removed (godot4 -> godot).
#
# Self-contained on purpose: in copy mode bin/ ships without lib/common.sh.
# Exit: 2 when the root, the engine, or the adapter is missing.
set -u

verb="${1:-}"
[ -n "$verb" ] || { echo "usage: studio-dispatch VERB [ARGS...]" >&2; exit 2; }
shift

# field FILE KEY — value of a flat JSON string key; empty when absent.
field() {
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}

root="${OMEGA_STUDIO_ROOT:-}"
if [ -z "$root" ]; then
  self="$0"
  while [ -L "$self" ]; do
    link="$(readlink "$self")"
    case "$link" in
      /*) self="$link" ;;
      *)  self="$(dirname "$self")/$link" ;;
    esac
  done
  root="$(cd "$(dirname "$self")/.." && pwd -P)"
fi
if [ ! -f "$root/studio.json" ]; then
  echo "studio-$verb: no studio at '$root' — set OMEGA_STUDIO_ROOT to the studio directory (the claude-gd shim does this)" >&2
  exit 2
fi

engine="$(field .studio/config.json engine)"
[ -n "$engine" ] || engine="$(field "$root/studio.json" engine)"
if [ -z "$engine" ]; then
  echo "studio-$verb: no engine configured in .studio/config.json or studio.json" >&2
  exit 2
fi

dir="$(printf '%s' "$engine" | sed 's/[0-9]*$//')"
adapter="$root/engines/$dir/$verb.sh"
if [ ! -f "$adapter" ]; then
  echo "studio-$verb: no adapter for engine $engine at engines/$dir/$verb.sh" >&2
  exit 2
fi

exec sh "$adapter" "$@"
```

Make it executable: `chmod +x studios/game-dev/bin/studio-dispatch`.

Then write `studios/game-dev/bin/studio-test` as a wrapper (Task 6 adds the adapter it calls):

```sh
#!/bin/sh
# studio-test [PATH] — run the project's test suite through the engine adapter.
exec sh "$(dirname "$0")/studio-dispatch" test "$@"
```

`chmod +x studios/game-dev/bin/studio-test`.

- [ ] **Step 5: Write `studios/game-dev/engines/godot/resolve.sh`**

```sh
#!/bin/sh
# resolve.sh — print the Godot binary to use, or exit 2.
#
# Order: $GODOT_PATH when set and executable; the first executable
# Godot*.app bundle under $GODOT_APP_DIR (default /Applications); godot on
# PATH. Nothing else is searched, so a result is always explainable.
set -u

if [ -n "${GODOT_PATH:-}" ] && [ -x "$GODOT_PATH" ]; then
  printf '%s\n' "$GODOT_PATH"
  exit 0
fi

for app in "${GODOT_APP_DIR:-/Applications}"/Godot*.app/Contents/MacOS/Godot; do
  if [ -x "$app" ]; then
    printf '%s\n' "$app"
    exit 0
  fi
done

if command -v godot >/dev/null 2>&1; then
  command -v godot
  exit 0
fi

echo "no Godot binary found; set GODOT_PATH" >&2
exit 2
```

`chmod +x studios/game-dev/engines/godot/resolve.sh`.

- [ ] **Step 6: Write `studios/game-dev/engines/godot/GUIDE.md`**

```markdown
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
```

- [ ] **Step 7: Run the tests**

Run: `sh tests/lib_test.sh && sh tests/toolkit_test.sh && sh tests/studio_test.sh`
Expected: `0 failed` in all three. (`studio_test`'s `test_bin_syntax` now parses and checks the executable bit of `studio-dispatch`, `studio-test` and `resolve.sh`; `test_dispatch_rejects_unknown_engine` passes because the `unity` directory is missing, and `studio-test` in a `godot4` project exits 2 until Task 6 adds `test.sh`.)

- [ ] **Step 8: Commit**

```sh
git add lib/common.sh studios/game-dev/bin studios/game-dev/engines tests/lib_test.sh tests/toolkit_test.sh tests/run_all.sh
git commit -m "feat: engine adapter dispatch and Godot resolution

studio-dispatch finds the studio root and the configured engine and runs
engines/<dir>/<verb>.sh; resolve.sh finds the Godot binary in a fixed
order; GUIDE.md pins GUT and maps roles to godot-prompter skills.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `studio-test` — GUT through the adapter

**Files:**
- Create: `studios/game-dev/engines/godot/test.sh` (executable)
- Modify: `tests/toolkit_test.sh`

**Interfaces:**
- Consumes: `studio-dispatch` and `resolve.sh` (Task 5); `GUIDE.md`'s `Install:` line.
- Produces: the `studio-test` contract from Global Constraints. `.studio/reports/test-<stamp>.xml` and `.studio/reports/test-<stamp>.log` per run. Agents (Task 2) and the `review`, `playtest`, `ship` skills (Tasks 11–13) call `studio-test` by name.

- [ ] **Step 1: Write the failing tests in `tests/toolkit_test.sh`**

Add these functions and their names to `run_tests`:

```sh
test_test_needs_a_project() {
  mkdir -p "$TMP/not-a-project"
  verb "$TMP/not-a-project" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a directory without project.godot exits 1"
  assert_contains "$TMP/out" "no project.godot" "the message says what is missing"
}

test_test_falls_back_to_studio_json() {
  P="$(fresh_project defaults)"
  with_gut "$P"
  verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "no .studio/config.json falls back to studio.json's engine"
}

test_test_exits_3_without_gut() {
  P="$(fresh_project nogut)"
  verb "$P" studio-test
  assert_eq "3" "$(cat "$TMP/status")" "missing GUT exits 3"
  assert_contains "$TMP/out" "addons/gut/gut_cmdln.gd" "the message names the missing file"
  assert_contains "$TMP/out" "git clone --depth 1" "the message prints the install command from GUIDE.md"
}

test_test_exits_2_without_engine() {
  P="$(fresh_project noengine)"
  with_gut "$P"
  mkdir -p "$TMP/no-apps"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="/usr/bin:/bin" \
      sh "$BIN/studio-test" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "2" "$status" "no Godot binary exits 2"
  assert_contains "$TMP/out" "set GODOT_PATH" "the hint names GODOT_PATH"
}

test_test_passes_and_reports() {
  P="$(fresh_project pass)"
  with_gut "$P"
  verb "$P" studio-test
  assert_eq "0" "$(cat "$TMP/status")" "a green suite exits 0"
  assert_contains "$TMP/out" "^studio-test: 2 passed, 0 failed" "summary line counts from the JUnit file"
  xml="$(ls "$P"/.studio/reports/test-*.xml 2>/dev/null | head -n 1)"
  assert_file "$xml" "JUnit XML lands in .studio/reports"
  log="$(ls "$P"/.studio/reports/test-*.log 2>/dev/null | head -n 1)"
  assert_file "$log" "the engine log lands in .studio/reports"
  assert_contains "$log" "\-gdir=res://tests" "the whole suite runs from res://tests"
  assert_contains "$log" "\-ginclude_subdirs" "subdirectories are included"
  assert_contains "$log" "\-gexit" "GUT exits when done"
  assert_contains "$log" "\-\-headless" "the run is headless"
}

test_test_reports_failures() {
  P="$(fresh_project fail)"
  with_gut "$P"
  STUB_FAILS=1 verb "$P" studio-test
  assert_eq "1" "$(cat "$TMP/status")" "a failing suite exits 1"
  assert_contains "$TMP/out" "^studio-test: 1 passed, 1 failed" "summary line counts the failure"
  assert_contains "$TMP/out" "^  FAIL test_distance" "failing test names are echoed"
}

test_test_targets_a_file() {
  P="$(fresh_project file)"
  with_gut "$P"
  mkdir -p "$P/tests/unit"
  : > "$P/tests/unit/test_dash.gd"
  verb "$P" studio-test tests/unit/test_dash.gd
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-gtest=res://tests/unit/test_dash.gd" "a file argument runs that test file"
  assert_not_contains "$log" "\-gdir=" "a file argument does not also pass -gdir"
}

test_test_targets_a_directory() {
  P="$(fresh_project dir)"
  with_gut "$P"
  mkdir -p "$P/tests/integration"
  verb "$P" studio-test tests/integration
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "\-gdir=res://tests/integration" "a directory argument runs that directory"
}
```

- [ ] **Step 2: Add the first-run import test**

A project the editor has never opened has no `.godot/` and so no
`global_script_class_cache.cfg`; `class_name` lookups then fail at parse time
in a headless run. `test.sh` imports once when `.godot/` is absent. The stub
records every invocation as a `stub godot args:` line in the log, so the
assertions read that. Add this function and name it in `run_tests`:

```sh
test_test_imports_when_dot_godot_is_absent() {
  P="$(fresh_project import)"
  with_gut "$P"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "a project without .godot/ is imported before the suite runs"
  P="$(fresh_project imported)"
  with_gut "$P"
  mkdir -p "$P/.godot"
  verb "$P" studio-test
  log="$(ls "$P"/.studio/reports/test-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a project with .godot/ is not imported again"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `sh tests/toolkit_test.sh`
Expected: every new assertion FAILs with exit 2 `no adapter for engine godot4 at engines/godot/test.sh`.

- [ ] **Step 4: Write `studios/game-dev/engines/godot/test.sh`**

```sh
#!/bin/sh
# test.sh [PATH] — run the GUT suite headless. Invoked by studio-dispatch
# from the project root.
#
#   PATH   a test file (-gtest=res://PATH) or directory (-gdir=res://PATH);
#          default res://tests, subdirectories included
#
# Exit: 0 all passed · 1 failures (or not a project) · 2 no Godot binary ·
#       3 GUT not installed. Prints "studio-test: N passed, M failed", then
#       the failing test names. JUnit XML and the engine log are written to
#       .studio/reports/test-<stamp>.{xml,log}.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(pwd -P)"

if [ ! -f "$PROJECT/project.godot" ]; then
  echo "studio-test: no project.godot in $PROJECT — run from the project root" >&2
  exit 1
fi

GODOT="$(sh "$HERE/resolve.sh")" || exit 2

if [ ! -f "$PROJECT/addons/gut/gut_cmdln.gd" ]; then
  echo "studio-test: GUT is not installed — addons/gut/gut_cmdln.gd is missing." >&2
  echo "Install it from the project root:" >&2
  sed -n 's/^Install: //p' "$HERE/GUIDE.md" >&2
  exit 3
fi

# Target: a file becomes -gtest, a directory becomes -gdir. Paths are given
# relative to the project root and turned into res:// paths.
target="${1:-tests}"
target="${target#./}"
target="${target%/}"
if [ -f "$PROJECT/$target" ]; then
  set -- "-gtest=res://$target"
else
  set -- "-gdir=res://$target" "-ginclude_subdirs"
fi

mkdir -p "$PROJECT/.studio/reports"
stamp="$(date +%Y%m%d-%H%M%S)"
xml_rel=".studio/reports/test-$stamp.xml"
log="$PROJECT/.studio/reports/test-$stamp.log"

# A project the editor has never opened has no .godot/ (and so no
# global_script_class_cache.cfg); import once so class_name lookups resolve.
if [ ! -d "$PROJECT/.godot" ]; then
  "$GODOT" --headless --path "$PROJECT" --import >>"$log" 2>&1 || true
fi

"$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd \
  "$@" -gexit "-gjunit_xml_file=res://$xml_rel" >> "$log" 2>&1
engine_status=$?

xml="$PROJECT/$xml_rel"
if [ ! -f "$xml" ]; then
  echo "studio-test: GUT produced no report (engine exit $engine_status); last lines of $log:" >&2
  tail -n 20 "$log" >&2
  exit 1
fi

# Totals come from the <testsuites> attributes; failing names from each
# <testcase> that carries a <failure> or <error> child.
total="$(sed -n 's/.*<testsuites[^>]*tests="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
failed="$(sed -n 's/.*<testsuites[^>]*failures="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
errors="$(sed -n 's/.*<testsuites[^>]*errors="\([0-9]*\)".*/\1/p' "$xml" | head -n 1)"
total="${total:-0}"; failed="${failed:-0}"; errors="${errors:-0}"
failed=$((failed + errors))
passed=$((total - failed))

printf 'studio-test: %s passed, %s failed\n' "$passed" "$failed"
awk '
  /<testcase/ { name = $0; sub(/.*name="/, "", name); sub(/".*/, "", name) }
  /<failure|<error/ { if (name != "") { print "  FAIL " name; name = "" } }
' "$xml"
printf 'report: %s\nlog: %s\n' "$xml_rel" ".studio/reports/test-$stamp.log"

[ "$failed" -eq 0 ] && [ "$engine_status" -eq 0 ]
```

`chmod +x studios/game-dev/engines/godot/test.sh`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/toolkit_test.sh && sh tests/studio_test.sh`
Expected: `0 failed` in both.

- [ ] **Step 6: Commit**

```sh
git add studios/game-dev/engines/godot/test.sh tests/toolkit_test.sh
git commit -m "feat: studio-test runs GUT headless with a JUnit report

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: `studio-run` — boot the project or a scene, scan for errors

**Files:**
- Create: `studios/game-dev/bin/studio-run` (executable), `studios/game-dev/engines/godot/run.sh` (executable)
- Modify: `tests/toolkit_test.sh`

**Interfaces:**
- Consumes: `studio-dispatch`, `resolve.sh`.
- Produces: the `studio-run` contract from Global Constraints; `.studio/reports/run-<stamp>.log`. The `playtest` and `ship` skills call it.

- [ ] **Step 1: Write the failing tests in `tests/toolkit_test.sh`**

Add and name in `run_tests`:

```sh
test_run_clean() {
  P="$(fresh_project run-clean)"
  verb "$P" studio-run --seconds 1
  assert_eq "0" "$(cat "$TMP/status")" "a clean run exits 0"
  assert_contains "$TMP/out" "^studio-run: clean" "a clean run says so"
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_file "$log" "the run log lands in .studio/reports"
  assert_contains "$log" "\-\-headless" "the default run is headless"
  assert_contains "$log" "\-\-path $P" "the run targets the project"
}

test_run_detects_script_errors() {
  P="$(fresh_project run-error)"
  mkdir -p "$P/.godot"   # already imported; the stub prints its error line on an import run too
  STUB_SCRIPT_ERROR=1 verb "$P" studio-run --seconds 1
  assert_eq "1" "$(cat "$TMP/status")" "a SCRIPT ERROR line exits 1"
  assert_eq "1" "$(head -n 1 "$TMP/out" | grep -c 'SCRIPT ERROR')" "error lines are echoed first"
  assert_contains "$TMP/out" "^studio-run: 1 error line" "the summary counts error lines"
}

test_run_passes_scene_and_windowed() {
  P="$(fresh_project run-scene)"
  mkdir -p "$P/.godot"   # already imported; an import run is always headless
  verb "$P" studio-run --scene res://levels/test_dash.tscn --seconds 1 --windowed
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_contains "$log" "res://levels/test_dash.tscn" "the scene is passed to the engine"
  assert_not_contains "$log" "\-\-headless" "--windowed drops --headless"
}

test_run_terminates_a_long_process() {
  P="$(fresh_project run-long)"
  mkdir -p "$P/.godot"   # already imported; the stub sleeps on an import run too
  start="$(date +%s)"
  STUB_SLEEP=30 verb "$P" studio-run --seconds 1
  elapsed=$(( $(date +%s) - start ))
  assert_eq "0" "$(cat "$TMP/status")" "a process that outlives --seconds is not an error"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$elapsed" -lt 10 ]; then _pass "the engine is terminated after --seconds"; else _fail "the engine is terminated after --seconds (took ${elapsed}s)"; fi
}

test_run_rejects_bad_options() {
  P="$(fresh_project run-opts)"
  verb "$P" studio-run --frames 3
  assert_eq "1" "$(cat "$TMP/status")" "an unknown option exits 1"
  verb "$P" studio-run --seconds
  assert_eq "1" "$(cat "$TMP/status")" "a missing option value exits 1"
}
```

- [ ] **Step 2: Add the first-run import test**

`run.sh` imports once when `.godot/` is absent, for the same reason as
`test.sh` (Task 6). Add this function and name it in `run_tests`:

```sh
test_run_imports_when_dot_godot_is_absent() {
  P="$(fresh_project run-import)"
  verb "$P" studio-run --seconds 1
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_contains "$log" "^stub godot args: --headless --path $P --import$" "a project without .godot/ is imported before the run"
  P="$(fresh_project run-imported)"
  mkdir -p "$P/.godot"
  verb "$P" studio-run --seconds 1
  log="$(ls "$P"/.studio/reports/run-*.log | head -n 1)"
  assert_not_contains "$log" "\-\-import" "a project with .godot/ is not imported again"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `sh tests/toolkit_test.sh`
Expected: the `test_run_*` assertions FAIL with `bin/studio-run: No such file or directory`.

- [ ] **Step 4: Write `studios/game-dev/bin/studio-run`**

```sh
#!/bin/sh
# studio-run [--scene RES_PATH] [--seconds N] [--windowed] — boot the project
# through the engine adapter and scan its log for script errors.
exec sh "$(dirname "$0")/studio-dispatch" run "$@"
```

`chmod +x studios/game-dev/bin/studio-run`.

- [ ] **Step 5: Write `studios/game-dev/engines/godot/run.sh`**

```sh
#!/bin/sh
# run.sh [--scene RES_PATH] [--seconds N] [--windowed] — boot the project (or
# one scene) for N seconds and scan the log for script errors. Invoked by
# studio-dispatch from the project root.
#
# Exit: 0 clean · 1 script errors, bad usage, or not a project · 2 no Godot
# binary. The full log is .studio/reports/run-<stamp>.log; error lines are
# echoed first, then the last 40 lines. macOS has no timeout(1), so the
# engine is started in the background, slept on, and sent TERM.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(pwd -P)"
SCENE=""
DURATION=10
HEADLESS="--headless"

usage() {
  echo "usage: studio-run [--scene RES_PATH] [--seconds N] [--windowed]" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      SCENE="$2"; shift 2 ;;
    --seconds)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$2" in ''|*[!0-9]*) usage ;; esac
      DURATION="$2"; shift 2 ;;
    --windowed) HEADLESS=""; shift ;;
    *) usage ;;
  esac
done

if [ ! -f "$PROJECT/project.godot" ]; then
  echo "studio-run: no project.godot in $PROJECT — run from the project root" >&2
  exit 1
fi

GODOT="$(sh "$HERE/resolve.sh")" || exit 2

mkdir -p "$PROJECT/.studio/reports"
stamp="$(date +%Y%m%d-%H%M%S)"
log_rel=".studio/reports/run-$stamp.log"
log="$PROJECT/$log_rel"

# A project the editor has never opened has no .godot/ (and so no
# global_script_class_cache.cfg); import once so class_name lookups resolve.
if [ ! -d "$PROJECT/.godot" ]; then
  "$GODOT" --headless --path "$PROJECT" --import >>"$log" 2>&1 || true
fi

# Build the argument list without word-splitting a scene path.
set -- --path "$PROJECT"
[ -n "$HEADLESS" ] && set -- "$HEADLESS" "$@"
[ -n "$SCENE" ] && set -- "$@" "$SCENE"

"$GODOT" "$@" >> "$log" 2>&1 &
pid=$!
sleep "$DURATION"
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

errors="$(grep -nE 'SCRIPT ERROR|ERROR:|Parser Error' "$log" || true)"
if [ -n "$errors" ]; then
  printf '%s\n' "$errors"
  count="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
  printf 'studio-run: %s error line(s) in %s\n' "$count" "$log_rel"
  tail -n 40 "$log"
  exit 1
fi

tail -n 40 "$log"
printf 'studio-run: clean (%ss, %s)\n' "$DURATION" "$log_rel"
```

`chmod +x studios/game-dev/engines/godot/run.sh`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `sh tests/toolkit_test.sh && sh tests/studio_test.sh`
Expected: `0 failed` in both (the long-process test takes about one second).

- [ ] **Step 7: Commit**

```sh
git add studios/game-dev/bin/studio-run studios/game-dev/engines/godot/run.sh tests/toolkit_test.sh
git commit -m "feat: studio-run boots the project and scans the log for errors

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `studio-lint` — gdtoolkit through the adapter

**Files:**
- Create: `studios/game-dev/bin/studio-lint` (executable), `studios/game-dev/engines/godot/lint.sh` (executable)
- Modify: `tests/toolkit_test.sh`

**Interfaces:**
- Consumes: `studio-dispatch`; `gdlint` and `gdformat` on `PATH` when installed.
- Produces: the `studio-lint` contract from Global Constraints. The `review` and `ship` skills call it and treat exit 3 as "not installed", not as a failure.

- [ ] **Step 1: Write the failing tests in `tests/toolkit_test.sh`**

Add and name in `run_tests`:

```sh
# lint_stubs DIR — put recording stubs for gdlint and gdformat in DIR. Each
# appends its arguments to DIR/calls and exits with $STUB_LINT_STATUS.
lint_stubs() {
  mkdir -p "$1"
  for tool in gdlint gdformat; do
    cat > "$1/$tool" <<STUB
#!/bin/sh
printf '$tool %s\n' "\$*" >> "$1/calls"
exit "\${STUB_LINT_STATUS:-0}"
STUB
    chmod +x "$1/$tool"
  done
}

test_lint_exits_3_without_gdtoolkit() {
  P="$(fresh_project lint-none)"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "3" "$status" "no gdlint or gdformat exits 3"
  assert_contains "$TMP/out" 'pip install "gdtoolkit==4.\*"' "the hint prints the pip install command"
}

test_lint_runs_both_tools_over_gd_files() {
  P="$(fresh_project lint-run)"
  mkdir -p "$P/src/player" "$P/addons/gut"
  : > "$P/src/player/dash.gd"
  : > "$P/addons/gut/gut.gd"
  lint_stubs "$TMP/lintstubs"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs:/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "0" "$status" "clean stubs exit 0"
  assert_contains "$TMP/lintstubs/calls" "^gdlint .*src/player/dash.gd" "gdlint sees project scripts"
  assert_contains "$TMP/lintstubs/calls" "^gdformat --check .*src/player/dash.gd" "gdformat runs in check mode"
  assert_not_contains "$TMP/lintstubs/calls" "addons/gut" "addons are not linted"
}

test_lint_reports_findings() {
  P="$(fresh_project lint-fail)"
  mkdir -p "$P/src"
  : > "$P/src/a.gd"
  lint_stubs "$TMP/lintstubs2"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs2:/usr/bin:/bin" STUB_LINT_STATUS=1 sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "1" "$status" "findings exit 1"
}

test_lint_with_no_scripts_is_clean() {
  P="$(fresh_project lint-empty)"
  lint_stubs "$TMP/lintstubs3"
  status=0
  ( cd "$P" && OMEGA_STUDIO_ROOT="$STUDIO" PATH="$TMP/lintstubs3:/usr/bin:/bin" sh "$BIN/studio-lint" ) > "$TMP/out" 2>&1 || status=$?
  assert_eq "0" "$status" "a project with no .gd files is clean"
  assert_contains "$TMP/out" "no .gd files" "and says so"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/toolkit_test.sh`
Expected: the `test_lint_*` assertions FAIL with `bin/studio-lint: No such file or directory`.

- [ ] **Step 3: Write `studios/game-dev/bin/studio-lint`**

```sh
#!/bin/sh
# studio-lint [PATH] — lint the project's scripts through the engine adapter.
exec sh "$(dirname "$0")/studio-dispatch" lint "$@"
```

`chmod +x studios/game-dev/bin/studio-lint`.

- [ ] **Step 4: Write `studios/game-dev/engines/godot/lint.sh`**

```sh
#!/bin/sh
# lint.sh [PATH] — gdlint, then gdformat --check, over every .gd file under
# PATH (default the project) outside addons/. Invoked by studio-dispatch.
#
# Exit: 0 clean · 1 findings · 3 gdtoolkit not installed.
set -u

target="${1:-.}"

if ! command -v gdlint >/dev/null 2>&1 && ! command -v gdformat >/dev/null 2>&1; then
  echo 'studio-lint: gdtoolkit is not installed. Install it with: pip install "gdtoolkit==4.*"' >&2
  exit 3
fi

files="$(find "$target" -name '*.gd' -not -path '*/addons/*' -not -path '*/.godot/*' -print | sort)"
if [ -z "$files" ]; then
  echo "studio-lint: no .gd files under $target"
  exit 0
fi

status=0
if command -v gdlint >/dev/null 2>&1; then
  printf '%s\n' "$files" | xargs gdlint || status=1
else
  echo "studio-lint: gdlint not found; running gdformat only" >&2
fi
if command -v gdformat >/dev/null 2>&1; then
  printf '%s\n' "$files" | xargs gdformat --check || status=1
else
  echo "studio-lint: gdformat not found; running gdlint only" >&2
fi

[ "$status" -eq 0 ] && echo "studio-lint: clean"
exit "$status"
```

`chmod +x studios/game-dev/engines/godot/lint.sh`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file.

- [ ] **Step 6: Commit**

```sh
git add studios/game-dev/bin/studio-lint studios/game-dev/engines/godot/lint.sh tests/toolkit_test.sh
git commit -m "feat: studio-lint runs gdtoolkit when installed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Optional `godot-mcp` registration — `install.sh`, `uninstall.sh`, `doctor.sh`

**Files:**
- Modify: `lib/common.sh` (add `node_major`, `manifest_mcp_servers`, `mcp_remove`; `manifest_remove` skips `mcp` lines), `install.sh` (replace the MCP placeholder block; unregister before a reinstall), `uninstall.sh` (unregister), `doctor.sh` (`engine:` and `mcp:` rows; `godot-mcp` leak warning)
- Modify: `tests/lib_test.sh`, `tests/install_test.sh`

**Interfaces:**
- Consumes: `engine_dir` (Task 5), `engines/godot/resolve.sh` (Task 5), `json_field`, `manifest_add`, `manifest_remove`, `requires_of`.
- Produces: `node_major` (prints the Node major version, `0` when absent), `manifest_mcp_servers MANIFEST` (prints each `mcp NAME` line's NAME), `mcp_remove TARGET NAME`; install output line `mcp:      godot registered (…)` / `mcp:      skipped (…)` / `mcp:      none (…)`; manifest line `mcp godot`; doctor rows `engine:       <engine> at <path>` / `engine:       <engine> — no binary found (set GODOT_PATH)` and `mcp:          godot registered` / `mcp:          none (optional — …)`.

- [ ] **Step 1: Write the failing helper tests in `tests/lib_test.sh`**

Add and name in `run_tests`:

```sh
test_node_major() {
  mkdir -p "$TMP/nodestub"
  printf '#!/bin/sh\necho v20.11.0\n' > "$TMP/nodestub/node"
  chmod +x "$TMP/nodestub/node"
  assert_eq "20" "$(PATH="$TMP/nodestub:/usr/bin:/bin" node_major)" "reads the major version"
  assert_eq "0" "$(PATH="/usr/bin:/bin" node_major)" "0 when node is absent"
  printf '#!/bin/sh\necho garbage\n' > "$TMP/nodestub/node"
  assert_eq "0" "$(PATH="$TMP/nodestub:/usr/bin:/bin" node_major)" "0 when the version is unreadable"
}

test_manifest_mcp_servers() {
  printf '%s\n' "$TMP/x/CLAUDE.md" "mcp godot" "$TMP/x/bin/studio-state" "mcp other" > "$TMP/m.txt"
  assert_eq "godot
other" "$(manifest_mcp_servers "$TMP/m.txt")" "lists every mcp line's server name"
  assert_eq "" "$(manifest_mcp_servers "$TMP/absent.txt")" "a missing manifest lists nothing"
}

test_manifest_remove_skips_mcp_lines() {
  mkdir -p "$TMP/mm/root"
  printf 'x\n' > "$TMP/mm/root/CLAUDE.md"
  printf '%s\n' "$TMP/mm/root/CLAUDE.md" "mcp godot" > "$TMP/mm/root/.omega-ai-manifest"
  ( cd "$TMP/mm" && manifest_remove "$TMP/mm/root/.omega-ai-manifest" "$TMP/mm/root" "" 2>"$TMP/mm/err" )
  assert_missing "$TMP/mm/root/CLAUDE.md" "path entries are still removed"
  assert_not_contains "$TMP/mm/err" "skipping manifest entry" "an mcp line is not reported as an out-of-scope path"
  assert_missing "$TMP/mm/mcp godot" "an mcp line never becomes a relative path to delete"
}
```

- [ ] **Step 2: Put stubs in front of every install in `tests/install_test.sh`**

Insert after `trap 'rm -rf "$TMP"' EXIT` (before the first test function):

```sh
# Every install in this file runs against stubs for claude, node and Godot,
# so MCP registration is exercised without a real Claude Code install, Node,
# or an engine. The claude stub records each call with its CLAUDE_CONFIG_DIR
# in $STUBS/claude.calls and writes or removes the .claude.json entry a real
# `claude mcp add|remove --scope user` would. The Godot stub is reached only
# through GODOT_PATH, never PATH, so "no engine" cases can clear it.
STUBS="$TMP/stubs"
mkdir -p "$STUBS/engine"
cat > "$STUBS/claude" <<'STUB'
#!/bin/sh
printf 'CLAUDE_CONFIG_DIR=%s claude %s\n' "${CLAUDE_CONFIG_DIR:-}" "$*" >> "$(dirname "$0")/claude.calls"
case "${1:-} ${2:-}" in
  "mcp add")
    mkdir -p "${CLAUDE_CONFIG_DIR:-.}"
    printf '{ "mcpServers": { "godot": { "command": "npx", "args": ["-y", "@coding-solo/godot-mcp"] } } }\n' \
      > "${CLAUDE_CONFIG_DIR:-.}/.claude.json" ;;
  "mcp remove")
    rm -f "${CLAUDE_CONFIG_DIR:-.}/.claude.json" ;;
esac
exit 0
STUB
printf '#!/bin/sh\necho "${STUB_NODE_VERSION:-v20.11.0}"\n' > "$STUBS/node"
printf '#!/bin/sh\necho "Godot Engine v4.3.stable (stub)"\n' > "$STUBS/engine/godot"
chmod +x "$STUBS/claude" "$STUBS/node" "$STUBS/engine/godot"
PATH="$STUBS:$PATH"; export PATH
GODOT_PATH="$STUBS/engine/godot"; export GODOT_PATH
# Tests that must see no engine at all also drop any real godot from PATH:
NO_ENGINE_PATH="$STUBS:/usr/bin:/bin"
```

- [ ] **Step 3: Write the failing install, uninstall and doctor tests in `tests/install_test.sh`**

Add these functions and name them in `run_tests` after `test_install_accepts_no_mcp`:

```sh
test_install_registers_mcp() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcp" --shim-dir "$TMP/bin-mcp" > "$TMP/mcp.out" 2>&1
  assert_contains "$TMP/mcp/.omega-ai-manifest" "^mcp godot\$" "manifest records the MCP server"
  assert_contains "$STUBS/claude.calls" \
    "^CLAUDE_CONFIG_DIR=$TMP/mcp claude mcp add --scope user godot -e GODOT_PATH=$STUBS/engine/godot -- npx -y @coding-solo/godot-mcp\$" \
    "claude mcp add runs at user scope inside the config root with the resolved binary"
  assert_contains "$TMP/mcp.out" "mcp:      godot registered" "install reports the registration"
  assert_contains "$TMP/mcp.out" "mcp:          godot registered" "the doctor run at the end sees the server"
}

test_install_skips_mcp_without_node_18() {
  : > "$STUBS/claude.calls"
  STUB_NODE_VERSION=v16.20.0 sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcp16" --shim-dir "$TMP/bin-mcp16" > "$TMP/mcp16.out" 2>&1
  assert_not_contains "$TMP/mcp16/.omega-ai-manifest" "^mcp " "no mcp line without node 18"
  assert_not_contains "$STUBS/claude.calls" "mcp add" "claude mcp add is not run"
  assert_contains "$TMP/mcp16.out" "mcp:      skipped (node 18+ not found" "install explains the skip"
}

test_install_skips_mcp_without_engine() {
  : > "$STUBS/claude.calls"
  mkdir -p "$TMP/no-apps"
  GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$NO_ENGINE_PATH" \
    sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpng" --shim-dir "$TMP/bin-mcpng" > "$TMP/mcpng.out" 2>&1
  assert_not_contains "$TMP/mcpng/.omega-ai-manifest" "^mcp " "no mcp line without an engine binary"
  assert_not_contains "$STUBS/claude.calls" "mcp add" "claude mcp add is not run without an engine"
  assert_contains "$TMP/mcpng.out" "mcp:      skipped (no Godot binary found" "install explains the skip"
}

test_install_no_mcp_flag_skips_registration() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpoff" --shim-dir "$TMP/bin-mcpoff" --no-mcp > "$TMP/mcpoff.out" 2>&1
  assert_not_contains "$STUBS/claude.calls" "mcp add" "--no-mcp never calls claude mcp add"
  assert_contains "$TMP/mcpoff.out" "mcp:      skipped (--no-mcp)" "install reports the flag"
}

test_install_general_has_no_mcp() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gmcp" --shim-dir "$TMP/bin-gmcp" > "$TMP/gmcp.out" 2>&1
  assert_contains "$TMP/gmcp.out" "mcp:      none (studio declares no engine" "a studio without an engine registers nothing"
}

test_reinstall_reregisters_mcp_once() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpre" --shim-dir "$TMP/bin-mcpre" >/dev/null 2>&1
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpre" --shim-dir "$TMP/bin-mcpre" >/dev/null 2>&1
  assert_eq "2" "$(grep -c 'mcp add' "$STUBS/claude.calls")" "each install registers"
  assert_eq "1" "$(grep -c 'mcp remove --scope user godot' "$STUBS/claude.calls")" "a reinstall unregisters the previous server first"
  assert_eq "1" "$(grep -c '^mcp godot$' "$TMP/mcpre/.omega-ai-manifest")" "the manifest carries one mcp line"
}

test_uninstall_removes_mcp() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpun" --shim-dir "$TMP/bin-mcpun" >/dev/null 2>&1
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/mcpun" --shim-dir "$TMP/bin-mcpun" >/dev/null 2>&1
  assert_contains "$STUBS/claude.calls" "^CLAUDE_CONFIG_DIR=$TMP/mcpun claude mcp remove --scope user godot\$" \
    "uninstall unregisters the server inside the config root"
}

test_doctor_engine_and_mcp_rows() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dre" --shim-dir "$TMP/bin-dre" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre.out" 2>&1
  assert_contains "$TMP/dre.out" "engine:       godot4 at $STUBS/engine/godot" "doctor reports the resolved engine binary"
  assert_contains "$TMP/dre.out" "mcp:          godot registered" "doctor reads the server from .claude.json"
  rm -f "$TMP/dre/.claude.json"
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre2.out" 2>&1
  assert_contains "$TMP/dre2.out" "mcp:          none (optional" "doctor reports a missing server as optional"
  mkdir -p "$TMP/no-apps"
  status=0
  GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$NO_ENGINE_PATH" \
    sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre3.out" 2>&1 || status=$?
  assert_eq "0" "$status" "a missing engine binary is a warning, not a failure"
  assert_contains "$TMP/dre3.out" "engine:       godot4 — no binary found (set GODOT_PATH)" "doctor explains how to fix the engine"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen-dr" --shim-dir "$TMP/bin-gen-dr" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen-dr" > "$TMP/gdr.out" 2>&1
  assert_not_contains "$TMP/gdr.out" "^engine:" "a studio without an engine has no engine row"
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `sh tests/lib_test.sh; sh tests/install_test.sh`
Expected: `node_major: not found`, `manifest_mcp_servers: not found`, `an mcp line never becomes a relative path to delete` may pass by luck (the scope check skips it) but `not reported as an out-of-scope path` FAILs; every MCP install test FAILs on the missing `mcp godot` line and the `mcp:      godot registered` string; the doctor tests FAIL on the missing `engine:` and `mcp:` rows.

- [ ] **Step 5: Extend `lib/common.sh`**

Append after `engine_dir`:

```sh
# node_major — the installed Node.js major version as a number, or 0 when
# node is absent or its version is unreadable. MCP registration needs 18+.
node_major() {
  command -v node >/dev/null 2>&1 || { printf '0\n'; return 0; }
  _nv="$(node --version 2>/dev/null | tr -d 'v')"
  _nv="${_nv%%.*}"
  case "$_nv" in
    ''|*[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$_nv" ;;
  esac
}

# manifest_mcp_servers MANIFEST — print the NAME of every "mcp NAME" line.
# These lines record MCP servers registered inside the config root; they are
# not paths and are never passed to rm.
manifest_mcp_servers() {
  [ -f "$1" ] || return 0
  awk '$1 == "mcp" { print $2 }' "$1"
}

# mcp_remove TARGET NAME — unregister an MCP server from the config root's
# user scope. Silent when claude is absent: nothing could have registered it.
mcp_remove() {
  command -v claude >/dev/null 2>&1 || return 0
  CLAUDE_CONFIG_DIR="$1" claude mcp remove --scope user "$2" >/dev/null 2>&1 || true
}
```

In `manifest_remove`, add one line at the top of the `while` loop body, directly after `[ -n "$_entry" ] || continue`:

```sh
    case "$_entry" in "mcp "*) continue ;; esac
```

- [ ] **Step 6: Edit `install.sh`**

Replace the reinstall block

```sh
if [ "$DRY_RUN" != "1" ]; then
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
  : > "$MANIFEST"
fi
```

with

```sh
if [ "$DRY_RUN" != "1" ]; then
  for server in $(manifest_mcp_servers "$MANIFEST"); do
    mcp_remove "$TARGET" "$server"
  done
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
  : > "$MANIFEST"
fi
```

Replace the whole MCP placeholder block (from the comment "# MCP registration is part of the engine toolkit and arrives with it" through its `fi`) with:

```sh
# Optional MCP server. godot-mcp needs Node 18+ and a Godot binary; it is
# registered at user scope inside the config root, so it exists only for this
# studio, and recorded in the manifest so a reinstall or uninstall removes it.
# It is never written into the plugin's .mcp.json: a machine without Node
# must not see a startup failure.
ENGINE="$(json_field "$STUDIO_DIR/studio.json" engine)"
RESOLVE=""
[ -n "$ENGINE" ] && RESOLVE="$STUDIO_DIR/engines/$(engine_dir "$ENGINE")/resolve.sh"
if [ "$NO_MCP" = "1" ]; then
  log "mcp:      skipped (--no-mcp)"
elif [ -z "$ENGINE" ] || [ ! -f "$RESOLVE" ]; then
  log "mcp:      none (studio declares no engine adapter)"
elif [ "$DRY_RUN" = "1" ]; then
  log "DRY  mcp add godot"
elif [ "$(node_major)" -lt 18 ]; then
  log "mcp:      skipped (node 18+ not found — install Node.js to enable godot-mcp)"
elif ! GODOT="$(sh "$RESOLVE" 2>/dev/null)"; then
  log "mcp:      skipped (no Godot binary found — set GODOT_PATH and reinstall to enable godot-mcp)"
elif ! command -v claude >/dev/null 2>&1; then
  log "mcp:      skipped (claude is not on PATH)"
elif CLAUDE_CONFIG_DIR="$TARGET" claude mcp add --scope user godot \
       -e "GODOT_PATH=$GODOT" -- npx -y @coding-solo/godot-mcp >/dev/null 2>&1; then
  manifest_add "$MANIFEST" "mcp godot"
  log "mcp:      godot registered (npx -y @coding-solo/godot-mcp, GODOT_PATH=$GODOT)"
else
  warn "mcp registration failed; the studio works without it. To retry:
    CLAUDE_CONFIG_DIR=\"$TARGET\" claude mcp add --scope user godot -e GODOT_PATH=\"$GODOT\" -- npx -y @coding-solo/godot-mcp"
fi
```

- [ ] **Step 7: Edit `uninstall.sh`**

Replace

```sh
if [ -f "$MANIFEST" ]; then
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
else
```

with

```sh
if [ -f "$MANIFEST" ]; then
  for server in $(manifest_mcp_servers "$MANIFEST"); do
    mcp_remove "$TARGET" "$server"
    log "unregistered mcp server $server"
  done
  manifest_remove "$MANIFEST" "$TARGET" "$SHIM_PATH"
else
```

In the purge branch, before `rm -rf "$TARGET"`, add:

```sh
  for server in $(manifest_mcp_servers "$MANIFEST"); do
    mcp_remove "$TARGET" "$server"
  done
```

- [ ] **Step 8: Edit `doctor.sh`**

After the `plugins:` section (after `[ "$listed" = "1" ] || log "  (none)"`) and before `log "launch:       $SHIM_NAME"`, insert:

```sh
# Engine binary, through the studio's own adapter. A missing binary is a
# warning: the studio installs and plans without it; studio-test and
# studio-run exit 2 until it is found.
ENGINE="$(json_field "$STUDIO_DIR/studio.json" engine)"
if [ -n "$ENGINE" ]; then
  RESOLVE="$STUDIO_DIR/engines/$(engine_dir "$ENGINE")/resolve.sh"
  if [ ! -f "$RESOLVE" ]; then
    log "engine:       $ENGINE — no adapter at engines/$(engine_dir "$ENGINE")/"
  elif GODOT="$(sh "$RESOLVE" 2>/dev/null)"; then
    log "engine:       $ENGINE at $GODOT"
  else
    log "engine:       $ENGINE — no binary found (set GODOT_PATH); studio-test and studio-run will exit 2"
  fi

  # MCP registration lands in the config root's .claude.json under
  # CLAUDE_CONFIG_DIR. Read the file rather than `claude mcp list`, which
  # starts every server to health-check it.
  if [ -f "$TARGET/.claude.json" ] && grep -q '"godot"' "$TARGET/.claude.json"; then
    log "mcp:          godot registered"
  else
    log "mcp:          none (optional — reinstall with Node 18+ and a Godot binary to enable godot-mcp)"
  fi
fi
```

In the leakage block, after the `case "${TARGET%/}" in … esac` that checks the root, add:

```sh
# An MCP server registered outside the config root would be a leak into the
# user's general setup. The check cannot tell our registration from one the
# user made on purpose, so it warns and names the file rather than failing.
if [ -f "$HOME/.claude.json" ] && grep -q 'godot-mcp' "$HOME/.claude.json" 2>/dev/null; then
  warn "~/.claude.json registers godot-mcp — if this studio's installer did that, it leaked; if it is your own setup, ignore this"
fi
```

- [ ] **Step 9: Run the suite to verify it passes**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file. Plan 1's `test_install_accepts_no_mcp` still passes (`general` prints `mcp:      skipped (--no-mcp)`), and `test_doctor_plugin_report` still passes — the stubs change nothing it asserts.

- [ ] **Step 10: Commit**

```sh
git add lib/common.sh install.sh uninstall.sh doctor.sh tests/lib_test.sh tests/install_test.sh
git commit -m "feat: optional godot-mcp registration inside the config root

install.sh registers godot-mcp at user scope under CLAUDE_CONFIG_DIR when
Node 18+, claude and a Godot binary are present, records it in the
manifest, and unregisters it on reinstall and uninstall. doctor.sh reports
the engine binary and the MCP server. Tests stub claude, node and Godot.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Doctor delegation check

**Files:**
- Modify: `doctor.sh`, `tests/install_test.sh`

**Interfaces:**
- Consumes: `requires_of`, the plugin cache layout `$TARGET/plugins/cache/<marketplace>/<plugin>/<version>/{skills/<name>/SKILL.md,agents/<name>.md}`.
- Produces: the `delegations:` report block: per plugin `  <plugin>: N of M resolved`, one `  <plugin>:<name> MISSING from the cached plugin` line per gap (exit 1), or `  not checked — plugins not yet fetched; launch <shim> once, then re-run doctor` (exit 0).

- [ ] **Step 1: Write the failing test in `tests/install_test.sh`**

Add and name in `run_tests`:

```sh
# fake_cache ROOT — a plugin cache under ROOT holding every skill and agent
# game-dev's requires.txt declares, laid out as Claude Code lays it out.
fake_cache() {
  req="$REPO_ROOT/studios/game-dev/requires.txt"
  for kind in skill agent; do
    for ref in $(requires_of "$req" "$kind"); do
      plugin="${ref%%:*}"; name="${ref#*:}"
      case "$plugin" in
        superpowers) v="$1/plugins/cache/claude-plugins-official/superpowers/6.3.0" ;;
        *) v="$1/plugins/cache/skillsmith/$plugin/1.9.0" ;;
      esac
      if [ "$kind" = skill ]; then
        mkdir -p "$v/skills/$name"; : > "$v/skills/$name/SKILL.md"
      else
        mkdir -p "$v/agents"; : > "$v/agents/$name.md"
      fi
    done
  done
}

test_doctor_delegations() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dd" --shim-dir "$TMP/bin-dd" >/dev/null 2>&1
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd0.out" 2>&1 || status=$?
  assert_eq "0" "$status" "no plugin cache is a warning, not a failure"
  assert_contains "$TMP/dd0.out" "delegations:  not checked — plugins not yet fetched; launch claude-gd once" \
    "doctor says why delegations were not checked"

  fake_cache "$TMP/dd"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd1.out" 2>&1 || status=$?
  assert_eq "0" "$status" "every declared name resolving passes"
  assert_contains "$TMP/dd1.out" "^  superpowers: [0-9][0-9]* of [0-9][0-9]* resolved" "doctor tallies superpowers delegations"
  assert_contains "$TMP/dd1.out" "^  godot-prompter: [0-9][0-9]* of [0-9][0-9]* resolved" "doctor tallies godot-prompter delegations"
  assert_not_contains "$TMP/dd1.out" "MISSING" "nothing is missing"
  sp="$(grep '^  superpowers: ' "$TMP/dd1.out" | sed 's/^  superpowers: \([0-9]*\) of \([0-9]*\).*/\1 \2/')"
  assert_eq "${sp% *}" "${sp#* }" "resolved equals declared for superpowers"

  rm -rf "$TMP/dd/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/test-driven-development"
  rm -f "$TMP/dd/plugins/cache/skillsmith/godot-prompter/1.9.0/agents/godot-csharp-engineer.md"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "a missing delegated name fails the doctor"
  assert_contains "$TMP/dd2.out" "^  superpowers:test-driven-development MISSING from the cached plugin" "the missing skill is named"
  assert_contains "$TMP/dd2.out" "^  godot-prompter:godot-csharp-engineer MISSING from the cached plugin" "the missing agent is named"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh tests/install_test.sh`
Expected: `test_doctor_delegations` FAILs on every `delegations` assertion; the "no plugin cache" exit status passes already.

- [ ] **Step 3: Add the delegation block to `doctor.sh`**

Insert directly after the `plugins:` section (after `[ "$listed" = "1" ] || log "  (none)"`, before the engine block from Task 9):

```sh
# Delegated skills and agents: every skill/agent line in requires.txt must
# exist in the cached plugin. This is what protects the composition decision
# — a renamed upstream skill is reported here, not discovered mid-session.
# Layout: plugins/cache/<marketplace>/<plugin>/<version>/{skills,agents}.
delegation_state() {
  _plugin="${2%%:*}"; _name="${2#*:}"; _state="uncached"
  for _v in "$TARGET"/plugins/cache/*/"$_plugin"/*/; do
    [ -d "$_v" ] || continue
    _state="missing"
    if [ "$1" = "skill" ] && [ -f "$_v/skills/$_name/SKILL.md" ]; then _state="ok"; break; fi
    if [ "$1" = "agent" ] && [ -f "$_v/agents/$_name.md" ]; then _state="ok"; break; fi
  done
  printf '%s\n' "$_state"
}

checked=0
missing_lines=""
tally=""
for req in $(requires_of "$REQUIRES" plugin); do
  pname="${req%@*}"
  total=0; resolved=0
  for kind in skill agent; do
    for ref in $(requires_of "$REQUIRES" "$kind"); do
      [ "${ref%%:*}" = "$pname" ] || continue
      case "$(delegation_state "$kind" "$ref")" in
        ok) total=$((total + 1)); resolved=$((resolved + 1)); checked=1 ;;
        missing) total=$((total + 1)); checked=1
          missing_lines="$missing_lines
  $ref MISSING from the cached plugin" ;;
        uncached) ;;
      esac
    done
  done
  [ "$total" -gt 0 ] && tally="$tally
  $pname: $resolved of $total resolved"
done
if [ "$checked" = "1" ]; then
  log "delegations:$tally"
  if [ -n "$missing_lines" ]; then
    printf '%s\n' "$missing_lines" | sed '/^$/d'
    failed=1
  fi
else
  log "delegations:  not checked — plugins not yet fetched; launch $SHIM_NAME once, then re-run doctor"
fi
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file.

- [ ] **Step 5: Commit**

```sh
git add doctor.sh tests/install_test.sh
git commit -m "feat: doctor resolves every delegated skill and agent against the plugin cache

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Skill `game-dev:review`

**Files:**
- Create: `studios/game-dev/skills/review/SKILL.md`
- Modify: `tests/studio_test.sh`

**Interfaces:**
- Consumes: `game-dev:reviewer` (Task 3 report format), the implementer agents (Task 2) for fixes, `studio-test` and `studio-lint` (Tasks 6, 8), `studio-state`, the spec named in state.
- Produces: fix commits; ledger lines `Review: <n> findings, <m> fixed, <k> deferred` and `review clean`; `stage: playtest`.

- [ ] **Step 1: Write the failing assertion in `tests/studio_test.sh`**

Add to `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/review/SKILL.md" 'subagent_type: "game-dev:reviewer"' "review dispatches the reviewer"
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: one FAIL — `review dispatches the reviewer (no file at …/review/SKILL.md)`.

- [ ] **Step 3: Write `studios/game-dev/skills/review/SKILL.md`**

````markdown
---
name: review
description: Use when a branch or diff needs a spec-compliance and Godot best-practice review before playtest or ship.
---

# Review

**Announce at start:** "Using game-dev:review over <scope>."

The task-by-task reviews in `execute` catch local problems. This stage looks
at the whole branch against the whole spec, once, before anyone plays it.

## 0. Scope and preconditions

- Scope is the whole branch by default: `git merge-base <base> HEAD` to
  `HEAD`, where `<base>` is the branch the worktree was created from (ask if
  it is not obvious). The user may name a narrower scope — a commit range,
  a task number, or a path list — and that is the scope instead.
- `studio-state get spec` names the spec; read it in full. If there is no
  spec, review against the project `CLAUDE.md` rules only and say so.
- Run `studio-state set stage review`.

## 1. Baseline

Run `studio-test`. A failing suite is reviewed *first*: every failure is a
critical finding before the reviewer even reads the diff. Exit 2 or 3 is
reported to the user with the printed hint and the review continues without
the automated baseline.

Run `studio-lint`. Exit 3 means gdtoolkit is not installed — note it once
and move on; exit 1 findings are minor findings unless they hide a real
error.

## 2. Dispatch the reviewer

Dispatch `game-dev:reviewer` (`subagent_type: "game-dev:reviewer"`) with:

- the scope (`Scope: branch <name> vs <base>` or the narrower one);
- the spec path and the project `CLAUDE.md` path;
- the plan path, so it can check every `Verify: unit` task's test;
- the `studio-test` and `studio-lint` output from §1;
- the instruction "review only — do not fix".

It returns the report from its output contract: `Spec compliance`,
`Findings: N (critical c, important i, minor m)`, and one line per finding.

## 3. Fix loop

For each finding, in severity order:

- **critical** and **important**: dispatch the implementer that owns the
  file — the `Role:` of the plan task that created it, or
  `game-dev:gameplay-programmer` when no task did — with the finding line,
  the spec section it violates, and "fix this finding only; add a
  regression test when the finding is a behaviour". One commit per finding.
- **minor**: fix it the same way when it is a one-line change; otherwise
  record it as deferred.

After the fixes, run `studio-test` again and re-dispatch `game-dev:reviewer`
over the same scope. Repeat until the verdict is
`Findings: 0 (critical 0, important 0, minor 0)` with `unmet: none`, or only
deferred minors remain, or the user stops the loop. Three rounds without
reaching clean is a stop: report what keeps coming back and ask.

The user may defer any finding; a deferred finding is written to the plan's
`## Backlog` with the finding line and the reason.

## 4. State and hand-off

- `studio-state ledger "Review: <n> findings, <m> fixed, <k> deferred"` and,
  when the last verdict was clean, `studio-state ledger "review clean"`.
- `studio-state set stage playtest`.
- Print the final verdict line and the list of fix commits, then tell the
  user the next command is `/game-dev:playtest`. Do not invoke it yourself.

## Rules

- The reviewer reviews; implementers fix. Never let the reviewer edit code
  in this stage, and never fix in the main session.
- Findings are not negotiable by rewording: a finding is closed by a commit
  or by the user deferring it, not by explaining it away.
- Never run `superpowers:finishing-a-development-branch` here; merging is
  the ship stage's decision.
````

- [ ] **Step 4: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`; `superpowers:finishing-a-development-branch` is already declared.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/skills/review/SKILL.md tests/studio_test.sh
git commit -m "feat: game-dev:review skill with the reviewer fix loop

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Skill `game-dev:playtest`

**Files:**
- Create: `studios/game-dev/skills/playtest/SKILL.md`
- Modify: `tests/studio_test.sh`

**Interfaces:**
- Consumes: `studio-test`, `studio-run`, `game-dev:playtester` (script and bug formats from Task 3), `game-dev:feel-tuner` and `game-dev:gameplay-programmer` (fixes), `superpowers:systematic-debugging`, `superpowers:test-driven-development`, the spec's `## Feel targets`, `## Acceptance criteria`, `## Test strategy`, the plan's `Verify: playtest` tasks, and the ledger's `T<n> Playtest item:` lines.
- Produces: `docs/game-dev/playtests/YYYY-MM-DD-<topic>.md`; ledger lines `playtest written <path>` and `playtest signed off <path>`; `last_playtest: <path>`; `stage: ship`. The router reads `playtest signed off`.

- [ ] **Step 1: Write the failing assertions in `tests/studio_test.sh`**

Add to `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/playtest/SKILL.md" 'subagent_type: "game-dev:playtester"' "playtest dispatches the playtester"
  assert_contains "$S/playtest/SKILL.md" 'playtest signed off' "playtest writes the sign-off ledger phrase the router reads"
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: two FAILs on the missing `playtest/SKILL.md`.

- [ ] **Step 3: Write `studios/game-dev/skills/playtest/SKILL.md`**

````markdown
---
name: playtest
description: Use when implementation is done and needs verification in the running game — runs automated tests and a headless boot, then a human playtest script with a bug loop.
---

# Playtest

**Announce at start:** "Using game-dev:playtest — automated checks first, then the script."

A unit test proves the numbers; only a person at the keyboard proves the
feel. This stage does both, in that order, and turns every failure into a
bug with a repro and a regression test before it is called fixed.

## 0. Preconditions

- `studio-state get spec` and `studio-state get plan` name files that exist;
  read both. If the plan is missing but a spec exists, playtest the spec's
  criteria alone and say so.
- Run `studio-state set stage playtest`.
- Decide the topic stem from the spec file name (`2026-09-13-player-dash.md`
  → `player-dash`); the report is
  `docs/game-dev/playtests/YYYY-MM-DD-<topic>.md` with today's date.

## 1. Automated baseline

1. `studio-test`. Exit 1: every failing test is a bug (§4) before any human
   plays; fix them first, then continue. Exit 2 or 3: report the printed
   hint and ask the user whether to continue without the automated baseline
   — a playtest without passing unit tests is a decision they make, not you.
2. `studio-run --seconds 10`, plus `studio-run --scene <scene> --seconds 10`
   for each scene the spec's `## Test strategy` names. Exit 1: each error
   line is a bug (§4). Exit 2: same as above.

Keep both outputs; they go into the report's `## Automated baseline`.

## 2. Build the script

Dispatch `game-dev:playtester` (`subagent_type: "game-dev:playtester"`) with
the spec path, the plan path, the ledger from `studio-state show`, the
baseline output, and the report path. It writes the report with
`## Automated baseline`, `## Script` (`P1`…`Pn`, each with Setup, Action,
Expected, Fail looks like, and a Hypothesis for feel items) and empty
`## Results`, `## Bugs`, `## Fixes` sections, and returns the item count.

Read the script. Any item you cannot map to a spec criterion, a feel target,
or a `Verify: playtest` task is removed with a note; the script tests the
spec, not the playtester's imagination.

## 3. Run the script with the user

You, the main session, run the script — the agent cannot reach the user.

1. Tell the user how to launch: `studio-run --windowed --seconds 600` (or
   `--scene <scene>`), or the editor, or — when `mcp__godot__*` tools are in
   your tool list — the MCP run tool with output capture.
2. Print the whole script once so they can read ahead.
3. For each item, one `AskUserQuestion`: the item's Action and Expected as
   the question, options **pass**, **fail**, **defer** (with a note field
   implied by the free-text answer). Read free-text answers carefully — "pass
   but it feels slow" is a fail on the feel target.
4. Record each answer in the report's `## Results` table as you go
   (`P3 · fail · "clips the wall at speed"`), so a crash mid-session loses
   nothing.

## 4. Bug loop

For each failed item, and each automated failure from §1:

1. Dispatch `game-dev:playtester` again with the failed item and the user's
   note; it appends a `B<n>` bug (Repro, Expected, Actual, Suspected cause,
   Severity, Regression test) to `## Bugs`.
2. Dispatch the fixer with the bug and the spec section: `game-dev:feel-tuner`
   when the bug is a feel target (latency, forgiveness, acceleration, timing,
   camera, feedback), otherwise `game-dev:gameplay-programmer`. The brief
   says: follow `superpowers:systematic-debugging` before changing anything;
   when the bug's `Regression test` line says `unit`, write that test first
   (`superpowers:test-driven-development`) and make it fail on the bug; fix;
   run `studio-test`; commit as `fix(B<n>): …`; report the commit and the
   hypothesis (feel-tuner) or the root cause (gameplay-programmer).
3. Append to `## Fixes`: bug · commit · regression test · re-run result.
4. Re-run the failed item with the user (§3 step 3, that item only). A
   second failure goes back to step 1 with the new note; a third failure
   is a stop: report the pattern and ask whether to defer.

**Defer** moves the item to the plan's `## Backlog` with the user's reason
and marks it `deferred` in `## Results`. The loop ends when every item is
`pass` or `deferred`.

## 5. Report, state, gate

- The report's `## Results` table is complete; `## Bugs` and `## Fixes` list
  every bug and its outcome. `studio-test` is run one last time and its
  summary line is added under `## Automated baseline` as "after fixes".
- `studio-state set last_playtest <report path>`,
  `studio-state ledger "playtest written <report path>"`, and for every bug
  `studio-state ledger "B<n> <title> — <commit or deferred>"`.
- `studio-state set stage ship`.
- **Stop** with:

  > Playtest report at `<path>`: <n> items, <p> passed, <d> deferred, <b>
  > bugs fixed. Reply **sign off**, or name the item to revisit.

- On sign-off: `studio-state ledger "playtest signed off <report path>"`
  and tell the user the next command is `/game-dev:ship`. Do not invoke it
  yourself.

## Rules

- Never mark an item passed on the user's behalf. Silence, "ok", or "sure"
  without the item's letter is not an answer; ask again.
- A fix without a regression test is only allowed when the bug's
  `Regression test` line says `playtest only`, and then the re-run is the
  test.
- Feel fixes change one variable per hypothesis. A feel-tuner report that
  changed three values is sent back.
````

- [ ] **Step 4: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/skills/playtest/SKILL.md tests/studio_test.sh
git commit -m "feat: game-dev:playtest skill with the human script and bug loop

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Skill `game-dev:ship`

**Files:**
- Create: `studios/game-dev/skills/ship/SKILL.md`
- Modify: `tests/studio_test.sh`

**Interfaces:**
- Consumes: the `playtest signed off` ledger line, `studio-test`, `studio-lint`, `studio-run`, `superpowers:verification-before-completion`, `superpowers:finishing-a-development-branch`, `game-dev:producer` (ship method from Task 1), `studio-state`.
- Produces: a merged branch or a PR; a dated entry in `docs/game-dev/PROGRESS.md`; possibly `milestone:` advanced; ledger `shipped <ref>`; `stage: retro`.

- [ ] **Step 1: Write the failing assertion in `tests/studio_test.sh`**

Add to `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/ship/SKILL.md" 'subagent_type: "game-dev:producer"' "ship dispatches the producer"
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: one FAIL on the missing `ship/SKILL.md`.

- [ ] **Step 3: Write `studios/game-dev/skills/ship/SKILL.md`**

````markdown
---
name: ship
description: Use when a playtest is signed off — verifies, finishes the branch, and updates PROGRESS.md.
---

# Ship

**Announce at start:** "Using game-dev:ship."

## 0. Preconditions

- The ledger (`studio-state show`) has a `playtest signed off <path>` line
  whose path equals `studio-state get last_playtest`. If not, stop:
  "Playtest not signed off — run `/game-dev:playtest`." The user may sign
  off now in one word; then record the ledger line and continue.
- Run `studio-state set stage ship`.

## 1. Verify — evidence, not assertion

Invoke `superpowers:verification-before-completion` and apply it to these
three commands, each run fresh, output shown to the user, exit code read:

1. `studio-test` — must exit 0.
2. `studio-lint` — exit 0, or exit 3 with "gdtoolkit not installed" noted;
   exit 1 stops the ship until the findings are fixed or the user waives
   them in writing.
3. `studio-run --seconds 10` — must exit 0.

No claim of "tests pass" without the summary line from this run in your
message.

## 2. Finish the branch

Invoke `superpowers:finishing-a-development-branch`. It presents the
options (merge locally, open a PR, keep the branch); the user chooses. The
PR body, when a PR is opened, is the spec's `## Purpose` paragraph, the
`## Acceptance criteria` as a checklist, and a link to the playtest report.
Record the result as `<ref>`: the merge commit, the PR URL, or the branch
name.

## 3. Progress

Dispatch `game-dev:producer` (`subagent_type: "game-dev:producer"`) with
the plan path, the playtest report path, the `<ref>`, and
`docs/game-dev/PROGRESS.md`. It adds the dated log entry and reports
exactly one of `gate met: <current> → <next>` or `gate not met: …`.

- `gate met`: `studio-state set milestone <next>` and say so in one line.
- `gate not met`: repeat its missing list to the user; the milestone stays.

## 4. State and hand-off

- `studio-state ledger "shipped <ref>"`.
- `studio-state set stage retro`.
- Tell the user the next command is `/game-dev:retro`. Do not invoke it
  yourself.

## Rules

- Merging, pushing and publishing are side effects outside the worktree:
  the finishing skill asks, and you do not pre-empt its answer.
- Never edit `PROGRESS.md` in the main session; the producer owns it.
````

- [ ] **Step 4: Run the lint to verify it passes**

Run: `sh tests/studio_test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/skills/ship/SKILL.md tests/studio_test.sh
git commit -m "feat: game-dev:ship skill — verify, finish the branch, move the gate

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: Skill `game-dev:retro`

**Files:**
- Create: `studios/game-dev/skills/retro/SKILL.md`
- Modify: `tests/studio_test.sh`

**Interfaces:**
- Consumes: the ledger, the playtest reports, `$CLAUDE_CONFIG_DIR` (exported into the session by the shim; the memory directory is `$CLAUDE_CONFIG_DIR/memory/`), `studio-state`.
- Produces: memory files in the studio's isolated memory directory plus index lines in its `MEMORY.md`; ledger `retro written <n> memories`; `stage: idle`, `spec`/`plan`/`task` cleared to `-`.

- [ ] **Step 1: Write the failing assertions in `tests/studio_test.sh`**

Add to `test_stage_skills_dispatch_agents`:

```sh
  assert_contains "$S/retro/SKILL.md" 'CLAUDE_CONFIG_DIR' "retro writes memory into the isolated config root"
  assert_contains "$S/retro/SKILL.md" 'sync-memory.sh game-dev' "retro reminds the user to sync memory"
```

- [ ] **Step 2: Run the lint to see it fail**

Run: `sh tests/studio_test.sh`
Expected: two FAILs on the missing `retro/SKILL.md`.

- [ ] **Step 3: Write `studios/game-dev/skills/retro/SKILL.md`**

````markdown
---
name: retro
description: Use when a feature has shipped or a working session ends — captures durable decisions and pitfalls into studio memory.
---

# Retro

**Announce at start:** "Using game-dev:retro."

Learnings compound only if they are written where the next session reads
them. This stage writes them into the studio's own memory — isolated from
every other studio and from `~/.claude` by construction — and nowhere else.

## 0. Read

- `studio-state show`: every `Ruling:`, `Review:`, `B<n>` and `playtest`
  line since the last `retro written` line (or all of them).
- The playtest report(s) named since then; the spec's `## Not doing` list.
- Run `studio-state set stage retro`.

## 1. Ask, once

One `AskUserQuestion` batch, three questions: what surprised you; what
should the next feature do the same way; what should it never do again.
Free text is expected; offer no options beyond "nothing".

## 2. Decide what is durable

A memory earns a file when all three hold:

- It is project-independent, or it is a project fact the code does not
  record (a decision, a constraint, a preference).
- It would change how the next feature is built or reviewed.
- It is not derivable from the repository, the spec, or the plan.

A ruling that was one-off ("buffer window 0.1 s for the dash") is not a
memory; the reason it was chosen ("input windows below 0.1 s read as
unforgiving at 60 fps") is.

## 3. Write

The memory directory is `$CLAUDE_CONFIG_DIR/memory/` — read the variable
from the environment (`printf '%s\n' "$CLAUDE_CONFIG_DIR"`); it is the
config root the `claude-gd` shim launched this session with. If it is
unset, stop and say the session was not started through the studio shim.

One file per memory, kebab-case name, this format exactly:

```markdown
---
name: <kebab-case-slug>
description: <one line, used to decide relevance when recalled>
metadata:
  type: feedback | project | reference
---

<the fact, in one or two sentences>

**Why:** <the evidence — the ruling, bug, or playtest result that taught it>
**How to apply:** <what to do differently next time>
```

`feedback` is a working-method lesson; `project` is a fact about this game;
`reference` is a pointer (a URL, a doc path). Before writing, read the
existing `MEMORY.md` index in that directory and update an existing file
instead of duplicating it.

Add one line per new file to `$CLAUDE_CONFIG_DIR/memory/MEMORY.md`:
`- [Title](file.md) — hook`. Never put the memory's content in the index.

## 4. State and hand-off

- `studio-state ledger "retro written <n> memories"`.
- `studio-state set stage idle`, `studio-state set spec -`,
  `studio-state set plan -`, `studio-state set task -`.
- Tell the user: "Memory written to `$CLAUDE_CONFIG_DIR/memory/`. To commit
  it into the repository, run `./sync-memory.sh game-dev` from the omega-ai
  checkout." Then name the next command: `/game-dev:brainstorm` for the
  next feature, or `/game-dev:studio` to see the state.

## Rules

- Write only into `$CLAUDE_CONFIG_DIR/memory/`. Never into the game
  project, never into `~/.claude`, never into the omega-ai checkout — the
  sync script is the one path from a session into version control.
- Fewer, sharper memories. Three files a retro is typical; ten is a sign
  the filter in §2 was skipped.
````

- [ ] **Step 4: Run the lint to verify it passes**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file.

- [ ] **Step 5: Commit**

```sh
git add studios/game-dev/skills/retro/SKILL.md tests/studio_test.sh
git commit -m "feat: game-dev:retro skill writes durable decisions into studio memory

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: README and progress log

**Files:**
- Modify: `README.md`, `docs/game-dev/PROGRESS.md`

**Interfaces:**
- Consumes: the commands and output strings Tasks 5–10 produce.
- Produces: user-facing documentation; nothing downstream depends on it.

- [ ] **Step 1: Update the `## Use` section of `README.md`**

Replace the table and the paragraph after it (from `| Command | Does |` through "written only through `studio-state`.") with:

```markdown
| Command | Does |
|---|---|
| `/game-dev:studio` | Reads `.studio/STATE.md`, reports the stage and milestone, names the next step, routes freeform text |
| `/game-dev:brainstorm` | Batched questions → spec with GDD-lite sections → artifact page → **your approval** |
| `/game-dev:plan` | Tasks tagged `Role:` and `Verify: unit \| playtest \| visual`, producer scope cut → **your approval** |
| `/game-dev:execute` | Fresh role agent per task, reviewer after each; `--inline` for checkpointed execution |
| `/game-dev:review` | Whole-branch review by the reviewer agent against the spec; fix loop until clean |
| `/game-dev:playtest` | `studio-test`, `studio-run`, then a numbered playtest script you answer item by item; bugs get repro steps and regression tests → **your sign-off** |
| `/game-dev:ship` | Verification with evidence, finish the branch (merge or PR), `PROGRESS.md` and the milestone gate |
| `/game-dev:retro` | Durable decisions into the studio's isolated memory |

`scaffold` arrives in the next release; the session bootstrap says so when
it is missing. State lives in the project's `.studio/STATE.md`, written only
through `studio-state`.

### Roles

Ten agents do the long-session work, each dispatched by a stage with a fresh
context: `game-dev:game-designer`, `level-designer`, `architect`,
`gameplay-programmer`, `tech-artist`, `feel-tuner`, `ui-designer`,
`producer`, `playtester`, `reviewer`. Their personas and output contracts
are in `studios/game-dev/agents/`; the role → godot-prompter skill map is
in `studios/game-dev/engines/godot/GUIDE.md`.

### Toolkit

The shim puts `studios/game-dev/bin/` on `PATH`. From a Godot project root:

| Verb | Does | Exit codes |
|---|---|---|
| `studio-test [PATH]` | GUT headless; JUnit XML and log in `.studio/reports/` | 0 pass · 1 failures · 2 no Godot · 3 GUT missing |
| `studio-run [--scene S] [--seconds N] [--windowed]` | Boots the project for N seconds and scans the log for script errors | 0 clean · 1 errors · 2 no Godot |
| `studio-lint [PATH]` | `gdlint` and `gdformat --check` when gdtoolkit is installed | 0 clean · 1 findings · 3 not installed |
| `studio-state …` | Reads and writes `.studio/STATE.md` | 0 · 1 |

The verbs never name Godot; `studios/game-dev/engines/godot/` does. Godot is
found through `GODOT_PATH`, then `/Applications/Godot*.app`, then `godot` on
`PATH`. GUT is installed per project with the `Install:` line in
`engines/godot/GUIDE.md` (`studio-test` prints it when GUT is missing).

### MCP (optional)

When Node 18+ and a Godot binary are present, `./install.sh game-dev`
registers [`godot-mcp`](https://github.com/Coding-Solo/godot-mcp) at user
scope *inside* `~/.claude-gamedev` (never in `~/.claude.json`), so a
`claude-gd` session can launch the editor, run the project with output
capture, and create scenes. `--no-mcp` skips it; uninstall removes it;
`./doctor.sh game-dev` reports it. The studio works without it —
`studio-run` is the required path.
```

- [ ] **Step 2: Update the `## Check` section of `README.md`**

Replace its paragraph with:

```markdown
Reports the config root, the plugin manifest and its skill / agent counts,
every plugin `requires.txt` declares (enabled? fetched? which version?),
whether every delegated skill and agent resolves in the fetched plugins, the
engine binary, the MCP server, whether the shim is on `PATH`, and whether
anything leaks back into `~/.claude`. Exits non-zero on a name mismatch, a
missing plugin, an unresolvable delegation, or a leak; a missing engine or
MCP server is a warning.
```

- [ ] **Step 3: Update `docs/game-dev/PROGRESS.md`**

Change the Plan 2 row's status from `planned` to `done`, and add a log entry above the Plan 1 entry:

```markdown
### 2026-09-13 — Plan 2 (Quality loop) delivered

- Ten role agents under `studios/game-dev/agents/`; `2d-art-pipeline` and
  `game-feel-tuner` migrated to `tech-artist` and `feel-tuner`.
- Stage skills `review`, `playtest`, `ship`, `retro`; `execute`,
  `brainstorm` and `plan` now dispatch the studio's own agents.
- `studio-test`, `studio-run`, `studio-lint` through `studio-dispatch` and
  the Godot adapter in `engines/godot/`.
- Optional `godot-mcp` registration inside the config root; doctor reports
  the engine, the MCP server, and resolves every delegated skill and agent.
- Plan: `plans/2026-09-13-plan-2-quality-loop.md`.
```

- [ ] **Step 4: Run the full suite one more time**

Run: `sh tests/run_all.sh`
Expected: `0 failed` in every file.

- [ ] **Step 5: Commit**

```sh
git add README.md docs/game-dev/PROGRESS.md
git commit -m "docs: README for the quality loop; progress log for Plan 2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: Manual verification — the end-to-end session

This task changes no repository files until its last step. It proves the
Plan 2 exit criterion on the user's machine: the session in
`docs/game-dev/artifacts/2026-09-13-game-studio-design.html` §5 runs from
brainstorm to retro.

**Files:** none (creates content under `~/.claude-gamedev`, `~/.local/bin/claude-gd`, and a scratch Godot project).

- [ ] **Step 1: Reinstall and inspect the MCP step**

Run from the omega-ai checkout:

```sh
./install.sh game-dev
```

Expected, in the install log: `mcp:      godot registered (npx -y @coding-solo/godot-mcp, GODOT_PATH=/Applications/Godot_mono.app/Contents/MacOS/Godot)` — this machine has Node 24 and `Godot_mono.app`. Confirm the registration landed inside the config root and nowhere else:

```sh
grep -c godot ~/.claude-gamedev/.claude.json      # expected: 1 or more
grep -c godot-mcp ~/.claude.json 2>/dev/null       # expected: 0
tail -n 1 ~/.claude-gamedev/.omega-ai-manifest     # expected: mcp godot
```

If the first `grep` prints 0, the user-scope MCP file is elsewhere for this Claude Code version: run `CLAUDE_CONFIG_DIR=~/.claude-gamedev claude mcp get godot` and record where it says the server is stored; adjust the `mcp:` row in `doctor.sh` to read that file and re-run Task 9's tests.

- [ ] **Step 2: Doctor**

Run: `./doctor.sh game-dev`
Expected: `plugin:       game-dev 0.1.0   skills 12  agents 10  hooks present`; both required plugins `ok <version>`; `delegations:` with `superpowers: 8 of 8 resolved` and `godot-prompter: <M> of <M> resolved` (M is the number of `godot-prompter:` lines in `requires.txt`; both counts equal) and no `MISSING` line; `engine:       godot4 at /Applications/Godot_mono.app/Contents/MacOS/Godot`; `mcp:          godot registered`; `shim on PATH: yes`; `leakage: none`; exit 0.

If a `MISSING` line appears, the upstream plugin renamed a skill: fix `requires.txt` and the referencing agent or skill, and re-run.

- [ ] **Step 3: The toolkit against a real project**

In a small Godot 4 project with a `CharacterBody2D` player (create one in the editor if none exists; install GUT with the `Install:` line from `studios/game-dev/engines/godot/GUIDE.md`):

```sh
studio-test          # expected: studio-test: N passed, 0 failed  (N ≥ 0), exit 0
studio-run --seconds 5   # expected: last lines of the engine log, then studio-run: clean (5s, .studio/reports/run-…log)
studio-lint          # expected: findings, "studio-lint: clean", or exit 3 with the pip hint
```

Without GUT installed, `studio-test` must print the install line and exit 3; check `echo $?`.

- [ ] **Step 4: The exit criterion — the session in artifact §5**

Start `claude-gd` in that project and run, replying at each gate:

1. `/game-dev:studio` — expected: the state line and `Next: /game-dev:brainstorm`. In a fresh project with no `.studio/` yet, expect an `AskUserQuestion` about running `studio-state init` first instead — answer yes and continue.
2. `/game-dev:brainstorm add a dash ability for the player` — expected: classification, question batches, the architect dispatched only if you chose the architectural path, a spec carrying every heading in the `brainstorm` skill's template, an artifact link, a stop. Reply `approve`.
3. `/game-dev:plan` — expected: `game-dev:producer` dispatched (visible as an Agent call), a `Cut in the scope pass:` line in the plan header, `Role:`/`Verify:` on every task, a stop. Reply `approve`.
4. `/game-dev:execute` — expected: Agent calls with `subagent_type` `game-dev:gameplay-programmer` / `game-dev:feel-tuner` and `game-dev:reviewer` after each task; `studio-test` summary lines in the implementers' reports; `stage: review` at the end.
5. `/game-dev:review` — expected: `studio-test` and `studio-lint` run first, `game-dev:reviewer` over the branch, fix commits if any, `review clean` in the ledger, `stage: playtest`.
6. `/game-dev:playtest` — expected: `studio-test` and `studio-run` output, a report with `P` items, one `AskUserQuestion` per item; answer at least one item **fail** with a note (for example "feels delayed") and confirm a `B1` bug with repro steps, a fix commit, a regression test or `playtest only`, and the item re-asked; then a stop for sign-off. Reply `sign off`.
7. `/game-dev:ship` — expected: three verification commands with their output shown, the finishing-branch menu; choose "keep the branch" for this exercise; `game-dev:producer` dispatched; a new entry at the top of `docs/game-dev/PROGRESS.md`; `stage: retro`.
8. `/game-dev:retro` — expected: one question batch, one to three files under `~/.claude-gamedev/memory/`, matching lines in `~/.claude-gamedev/memory/MEMORY.md`, the sync reminder, `stage: idle`.

Confirm with `cat .studio/STATE.md`: `stage: idle`, `spec: -`, `plan: -`, `task: -`, `last_playtest: docs/game-dev/playtests/…`. The eight ledger phrases — `spec approved`, `plan approved`, `T<n> complete`, `review clean`, `playtest written`, `playtest signed off`, `shipped`, `retro written` — do not live in `STATE.md`: every stage from `brainstorm` through `retro` writes with `spec` set, so `studio-state ledger` routes each of them to the feature ledger under `.studio/ledger/` instead; `ls .studio/ledger/` to find it (it is the only file there for this run), and `cat` it to confirm all eight. Then, from the omega-ai checkout, `./sync-memory.sh game-dev` copies the new memory files into `studios/game-dev/memory/`; inspect them and commit or discard.

- [ ] **Step 5: Record the result**

Append to the Plan 2 log entry in `docs/game-dev/PROGRESS.md`:

```markdown
- Verified on 2026-09-13: the §5 session ran end to end in a Godot project
  through `claude-gd` — brainstorm, plan, execute, review, playtest with one
  bug fixed, ship (branch kept), retro. `godot-mcp` registered inside the
  config root; doctor resolved every delegation.
```

Commit:

```sh
git add docs/game-dev/PROGRESS.md
git commit -m "docs: record Plan 2 verification

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage (Plan 2 scope).** Agents table (ten rows, tools, output contracts, "May call" lists) → Tasks 1–3; migration table → Tasks 1–2 (`game-designer` kept, `2d-art-pipeline` → `tech-artist`, `game-feel-tuner` → `feel-tuner`, bodies preserved). Workflow `review` → Task 11, `playtest` (five numbered steps: automated, script by the playtester, session by the main session, bug loop with regression tests, report and sign-off) → Task 12, `ship` (verification-before-completion, finishing-a-development-branch, producer updates `PROGRESS.md`) → Task 13, `retro` (memory format, `MEMORY.md` line, sync reminder, state cleared) → Task 14. `execute`'s "dispatch the agent named in `Role:`" and "dispatch `game-dev:reviewer`", `brainstorm`'s architect dispatch, `plan`'s producer dispatch → Task 4. `bin/` verbs `studio-test`, `studio-run`, `studio-lint` with the spec's exit codes and outputs → Tasks 6–8; engine adapter contract and Godot adapter (resolution order, GUT command line, background run with `TERM`, gdtoolkit, `GUIDE.md`) → Tasks 5–8. Install step 8, uninstall's MCP line, doctor rows engine / MCP / `godot-mcp` leak → Task 9; doctor delegation row → Task 10. Testing case 4 (`mcp` manifest line) → Task 9; case 7 (doctor with a fake cache: pass, one removed name fails naming it, absent cache warns) → Task 10; case 8 extended to `engines/*/*.sh` → already covered by Plan 1's `test_bin_syntax` glob, exercised as each adapter script lands. README and `PROGRESS.md` → Task 15; exit criterion → Task 16. The `language: csharp` routing sentence under the agents table → Task 4 (execute dispatches `godot-prompter:godot-csharp-engineer`).

**Placeholder scan.** No TBD/TODO. Every script, agent and skill is given in full. The two forward references that remain — `game-dev:vertical-slice` / `game-dev:milestone-gates` in the producer and the `sprite-pipeline` / `gdd` / `core-loop` names in three agents — are explicit "when it appears in your skill list" notes tied to Plan 3, with the current names used now; `scaffold` in the router and README is likewise named as the next release.

**Name consistency.** `engine_dir`, `node_major`, `manifest_mcp_servers`, `mcp_remove` are defined in Tasks 5 and 9 and used by those names in Tasks 9–10; `studio-dispatch` (Task 5) is what `studio-test`, `studio-run`, `studio-lint` exec (Tasks 5, 7, 8); `resolve.sh` is called by `test.sh`, `run.sh`, `install.sh` and `doctor.sh` with the same `$GODOT_PATH` / `$GODOT_APP_DIR` contract; the `Install:` line format in `GUIDE.md` (Task 5) is what `test.sh` (Task 6) and `test_guide_has_an_install_line` read. Agent report shapes (`Files:` / `Tests:` / `Rulings:` / `Playtest item:` / `Visual:` from Task 2; `Findings: N (critical c, important i, minor m)` from Task 3; `P<n>` / `B<n>` from Task 3; `gate met:` / `gate not met:` from Task 1) are the shapes the skills in Tasks 4 and 11–13 read. Ledger phrases written by the skills — `review clean`, `playtest written <path>`, `playtest signed off <path>`, `shipped <ref>`, `retro written` — match Global Constraints and the router's `playtest signed off` lookup from Plan 1. Install output strings (`mcp:      …`) and doctor strings (`engine:       …`, `mcp:          …`, `delegations:`) match the assertions in Tasks 9–10 and the README in Task 15. `tests/studio_test.sh`'s `test_stage_skills_dispatch_agents` (Task 4) grows in Tasks 11–14 with the exact `subagent_type` strings each skill carries.

**Fixed during review.** `test_dispatch_falls_back_to_studio_json` originally sat in Task 5, where it could only fail (no `test.sh` yet); it moved to Task 6 as `test_test_falls_back_to_studio_json` so every task commits green. `install_test.sh` originally replaced `PATH` wholesale, which would have hidden `jq` and any tool outside `/usr/bin:/bin`; it now prepends the stub directory and uses a `NO_ENGINE_PATH` only in the two tests that must see no `godot` on `PATH`. The doctor's `godot-mcp` leak check is a warning rather than the spec's fail, because it cannot distinguish the installer's registration from one the user made in their general setup; it names the file and says so.

# omega-ai Game Studio — Design

Date: 2026-09-13
Status: Approved for planning
Approval artifact: https://claude.ai/code/artifact/ca2bdd14-6d92-4ad8-99b6-fe455190fb0d
(local copy: `docs/game-dev/artifacts/2026-09-13-game-studio-design.html`)

## Purpose

`omega-ai` becomes a repository of **studios**. A studio is a Claude Code
plugin plus a small manifest, installable into its own isolated config
directory so that one command (`claude-gd`) launches an assistant that knows
only that studio, its dependencies, and its memory.

The first studio, `game-dev`, is a small game studio in a plugin: eight stage
skills the user drives by hand (brainstorm → plan → execute → review →
playtest → ship → retro, plus a router), ten role agents that carry long
sessions, and a toolkit that can build, test and boot a Godot project. It is
composed from two reference frameworks — superpowers for *how to work*, gstack
for *who does the work and what they hand each other* — and adjusted for how
games are actually made: vertical slice before content, feel targets in real
units, playtests with a hypothesis, and scope that is cut rather than grown.

This design evolves the switchable-profiles work of 2026-09-04
(`docs/superpowers/specs/2026-09-04-omega-ai-profiles-design.md`). The
isolation mechanism, installer shape, guards and test harness carry forward;
`profiles/` becomes `studios/`, and a studio's content is packaged as a plugin
rather than linked file by file.

## Success criteria

1. `./install.sh game-dev` against a temporary target creates a config root
   containing a rendered `CLAUDE.md`, a copied `settings.json`, linked
   `memory/` and `bin/`, and a shim whose text contains `CLAUDE_CONFIG_DIR`,
   a `PATH` prefix for `bin/`, and `--plugin-dir` pointing at the studio
   directory. It never reads from or writes to `~/.claude`.
2. A `claude-gd` session lists `game-dev:*` skills and agents alongside
   `superpowers:*` and `godot-prompter:*`, and the session-start hook has
   injected the studio bootstrap.
3. In symlink mode, editing a skill under `studios/game-dev/skills/` is live in
   the next session with no reinstall.
4. Plan 1 exit: a feature in an existing Godot project is planned and executed
   through `claude-gd` using only `/game-dev:brainstorm`, `/game-dev:plan` and
   `/game-dev:execute`.
5. Plan 2 exit: the end-to-end session in "A session, end to end" runs:
   brainstorm, plan, execute, review, playtest with a bug loop, ship, retro.
6. Plan 3 exit: a new game project goes from an empty directory to its first
   signed-off playtest using only studio commands.
7. `sh tests/run_all.sh` passes and covers install, uninstall, plugin manifest
   validity, skill and agent frontmatter, the doctor delegation check, `bin/`
   syntax, and scaffold output.
8. Studio memory (`studios/game-dev/memory/MEMORY.md`) is linked into
   `~/.claude-gamedev/memory/` and imported by the rendered `CLAUDE.md`;
   `sync-memory.sh game-dev` copies it only into `studios/game-dev/memory/`.
   Claude's auto memory stays under `~/.claude-gamedev/projects/<project>/memory/`.

## Decisions

Every section below follows from these fourteen decisions, taken in the
clarification dialogue that produced the approval artifact.

| # | Topic | Decision |
|---|-------|----------|
| 1 | Foundation | Evolve the existing `profiles/` installer into `studios/`; keep isolation, guards, tests. |
| 2 | Isolation | Config root `~/.claude-gamedev`, launched by `claude-gd`; `~/.claude` is never touched. |
| 3 | Packaging | The studio is a Claude Code plugin named `game-dev`, loaded live with `--plugin-dir`. |
| 4 | Naming | Skills are `/game-dev:<stage>`; agents are `game-dev:<role>`. The namespace comes from the plugin name. |
| 5 | Composition | The studio owns its pipeline skills; generic mechanics are delegated to superpowers by name, engine knowledge to godot-prompter. gstack contributes patterns, not code. |
| 6 | Stages | brainstorm → plan → execute → review → playtest → ship → retro, plus a `studio` router and a `scaffold` skill. |
| 7 | Spec review | Markdown spec in the repository plus a rendered Artifact page for approval; the HTML export is kept beside the spec. |
| 8 | Execution | Subagent-driven by default; inline execution with checkpoints only when the user asks (`--inline`). |
| 9 | Roles | Ten agents: game-designer, level-designer, architect, gameplay-programmer, tech-artist, feel-tuner, ui-designer, producer, playtester, reviewer. |
| 10 | Toolkits | `bin/` helpers, a project scaffold, one SessionStart hook, optional `godot-mcp` registration. |
| 11 | State and memory | `.studio/STATE.md` per game project; retro writes memory into the studio's isolated config root. |
| 12 | Docs | `docs/game-dev/{specs,plans,artifacts,PROGRESS.md}` in this repository; the same layout (plus `playtests/`) in game projects. |
| 13 | Extensibility | Engine, dimension and language are configuration seams; Godot 4.x 2D GDScript is the first pack, not the design. |
| 14 | Copilot | Skills follow the portable `SKILL.md` format; no Copilot installer in this design. |

Two smaller decisions were taken while writing this spec and are recorded
here so the plan does not have to re-open them: the studio manifest stays a
flat JSON file readable by the existing `json_field` helper (nested
requirements move to a plain-text `requires.txt`), and agents declare
`model: inherit` so the studio's `settings.json` is the single place the model
is chosen.

## What we took, what we changed

### From superpowers

Taken:

- Skill-first discipline: check for a matching skill before any action.
- The brainstorm gate: no code before an approved design.
- Spec → plan → fresh subagent per task → reviewer per task → final review.
- Red/green TDD, verification-before-completion, git worktrees.
- Writing skills as TDD applied to documentation (baseline pressure scenario,
  then the skill, then re-run).

Changed:

- TDD is mandatory only for tasks tagged `Verify: unit`. Feel, animation and
  layout tasks carry playtest criteria instead — a unit test cannot say that a
  dash feels floaty.
- Brainstorm gains GDD-lite sections: core-loop delta, player verbs, feel
  targets, and a not-doing list.
- A playtest stage exists at all.

### From gstack

Taken:

- Named specialists, each with a persona and an output contract.
- Each stage writes a file the next stage reads.
- The decision-brief format for approval questions: the question, the stakes,
  a recommendation, and the options.
- The QA loop: find → fix → regression test → re-verify.
- A router skill, a retro, and learnings that compound across sessions.

Changed:

- The CEO's "think bigger" becomes the producer's "cut to the vertical slice".
  Games die of scope, not of timidity.
- Browser QA becomes headless Godot runs plus a human playtest script.
- Dropped entirely: Bun binaries, the browser daemon, telemetry, design-html,
  the security audit. Nothing is compiled; nothing phones home.

### From industry practice

Baked into skills and agents as content, not ornament:

- Vertical slice before content. Milestone gates prototype → vertical slice →
  alpha → beta → gold are tracked in `PROGRESS.md`.
- The GDD is a living decision log, short enough to be read, not a 40-page
  dream.
- A playtest states its hypothesis first ("expected perceptual change"), then
  measures.
- Feel targets are written in real units: input latency at most 2 frames at
  60 fps, coyote time about 0.1 s, a 16.6 ms frame budget.
- Tuning is data-driven: numbers live in `Resource` files a designer edits
  without a programmer.
- Import settings and project settings are code — versioned and reviewed.

## Concept model

```
omega-ai (repository)
└── studios/
    └── <studio>/              a Claude Code plugin + a studio manifest
        ├── .claude-plugin/plugin.json   what Claude Code reads (name → namespace)
        ├── studio.json                  what install.sh / doctor.sh read
        ├── requires.txt                 external plugins, skills, agents the studio depends on
        ├── skills/ agents/ hooks/       plugin content, loaded live via --plugin-dir
        ├── bin/ engines/                toolkit, linked into the config root and put on PATH
        └── CLAUDE.md settings.json memory/   installed into the config root
```

A studio directory is a valid plugin as far as Claude Code is concerned: the
loader reads `.claude-plugin/plugin.json`, `skills/`, `agents/` and `hooks/`
and ignores the rest. The extra files are for the installer.

### `studio.json`

Flat keys only, so the existing `json_field` sed helper can read every one of
them without a JSON parser:

```json
{
  "name": "game-dev",
  "description": "Game development studio — Godot 4.x 2D first, engine-agnostic core",
  "target": "~/.claude-gamedev",
  "shim": "claude-gd",
  "engine": "godot4",
  "dimension": "2d",
  "language": "gdscript",
  "tests": "gut"
}
```

`engine`, `dimension`, `language` and `tests` are the studio defaults. A game
project overrides them in `.studio/config.json` (see "State and
configuration").

### `requires.txt`

One dependency per line, `<kind> <name>`, read by `doctor.sh`:

```
plugin superpowers@claude-plugins-official
plugin godot-prompter@skillsmith
skill  superpowers:test-driven-development
skill  superpowers:systematic-debugging
skill  superpowers:using-git-worktrees
skill  superpowers:verification-before-completion
skill  superpowers:finishing-a-development-branch
skill  superpowers:writing-plans
skill  superpowers:executing-plans
skill  godot-prompter:godot-code-review
skill  godot-prompter:godot-testing
skill  godot-prompter:godot-debugging
skill  godot-prompter:godot-project-setup
skill  godot-prompter:gdscript-patterns
skill  godot-prompter:state-machine
skill  godot-prompter:event-bus
skill  godot-prompter:resource-pattern
agent  godot-prompter:godot-csharp-engineer
```

The list above is the seed; the rule is that **every** `superpowers:` or
`godot-prompter:` name referenced anywhere in `skills/`, `agents/` or
`engines/` appears in `requires.txt`, and a repository test enforces it (see
"Testing the framework", case 6). Plugin enablement itself stays in
`settings.json` (`enabledPlugins` and `extraKnownMarketplaces`), because that
is the file Claude Code reads. `requires.txt` is the declaration the doctor
checks against it.

### `.claude-plugin/plugin.json`

```json
{
  "name": "game-dev",
  "version": "0.1.0",
  "description": "Game development studio: stage skills, role agents, and a Godot toolkit for omega-ai."
}
```

The `name` is what produces the `game-dev:` prefix on every skill and agent.

## Install behavior

`install.sh <studio> [--mode symlink|copy] [--target DIR] [--shim-dir DIR]
[--no-mcp] [--dry-run]` runs these steps in order:

1. **Resolve and guard.** Read `studios/<studio>/studio.json`. Canonicalize the
   target and shim directory and refuse `~/.claude`, the home directory, and
   anything inside the repository — the existing `guard_target` unchanged.
2. **Create the config root** and open a fresh manifest at
   `$TARGET/.omega-ai-manifest`.
3. **Render `CLAUDE.md`** by concatenating `shared/CLAUDE.part.md` and
   `studios/<studio>/CLAUDE.md` under a generated-file header.
4. **Copy `settings.json`** (never link; Claude Code writes to it). Back up a
   differing existing file to `settings.json.bak-<timestamp>`.
5. **Link `memory/` and `bin/`** entry by entry, shared first and the studio
   second, exactly as content directories were linked before. `agents/`,
   `skills/`, `commands/` and `hooks/` are no longer linked — the plugin
   provides them.
6. **Resolve the plugin directory.** In symlink mode it is
   `studios/<studio>/` in the repository. In copy mode the whole studio
   directory is copied to `$TARGET/studio/` and that copy is used, so a frozen
   snapshot has no live dependency on the checkout.
7. **Write the shim** to `$SHIM_DIR/<shim>`:

   ```sh
   #!/usr/bin/env sh
   # Generated by omega-ai install.sh — launches Claude Code against the
   # game-dev studio's isolated config root with the studio plugin loaded live.
   OMEGA_STUDIO_ROOT="/path/to/omega-ai/studios/game-dev"
   export OMEGA_STUDIO_ROOT
   CLAUDE_CONFIG_DIR="/Users/me/.claude-gamedev" \
   PATH="/Users/me/.claude-gamedev/bin:$PATH" \
     exec claude --plugin-dir "$OMEGA_STUDIO_ROOT" "$@"
   ```

   `OMEGA_STUDIO_ROOT` lets `bin/` scripts find `engines/` without resolving
   their own symlink. In copy mode both `OMEGA_STUDIO_ROOT` and `--plugin-dir`
   point at `$TARGET/studio`. Any user arguments pass through, so
   `claude-gd -p` and `claude-gd --resume` work.
8. **Register the MCP server (optional).** Skipped with `--no-mcp` or when
   `node` is absent or older than 18. Otherwise resolve the engine binary with
   `engines/<engine>/resolve.sh` and run

   ```sh
   CLAUDE_CONFIG_DIR="$TARGET" claude mcp add --scope user godot \
     -e GODOT_PATH="$GODOT" -- npx -y @coding-solo/godot-mcp
   ```

   and record `mcp godot` in the manifest. The server is registered at user
   scope *inside the config root*, so it exists only for this studio.
9. **Run `doctor.sh`** and print its report.

`--dry-run` prints every action and changes nothing. Install paths must not
contain spaces, as before.

### Uninstall

`uninstall.sh <studio>` removes the shim, every link and file in the manifest,
and — when the manifest carries an `mcp` line — runs
`CLAUDE_CONFIG_DIR="$TARGET" claude mcp remove --scope user godot`. Sessions,
history and memory written during use stay. `--purge` removes the config root
entirely, prompting unless `--yes` is given.

### `doctor.sh`

`doctor.sh <studio> [--target DIR]` reports, in this order, and exits non-zero
when any check marked *fail* fails:

| Check | Source | On failure |
|-------|--------|------------|
| Config root resolved and present | `studio.json`, `--target` | fail |
| Plugin manifest: name, version, skill / agent / hook counts | `.claude-plugin/plugin.json`, directory listing | fail when name ≠ studio name |
| Required plugins enabled, with versions | `requires.txt` vs `settings.json` `enabledPlugins`, `plugins/cache/` | fail when not enabled; *warn* "not yet fetched — launch `claude-gd` once" when enabled but absent from the cache |
| Delegated skills and agents resolvable | each `skill`/`agent` line in `requires.txt` matched against `plugins/cache/*/<plugin>/*/skills/<name>/SKILL.md` or `agents/<name>.md` | fail when the plugin is cached but the name is missing |
| Engine binary | `engines/<engine>/resolve.sh` | warn |
| MCP server | `CLAUDE_CONFIG_DIR=$TARGET claude mcp list` | warn |
| Shim on `PATH` | `command -v <shim>` | warn |
| Leaks into `~/.claude` | any manifest path under `~/.claude`; `~/.claude.json` mentioning `godot-mcp` | fail |

The delegation check is what protects the composition decision: a renamed
upstream skill is reported by the doctor, not discovered mid-session.

### Renames

- `profiles/` → `studios/`; `profile.json` → `studio.json`;
  `resolve_profile_target` → `resolve_studio_target`. Every user-facing string
  says "studio".
- `sync-memory.sh <studio>` copies `$TARGET/memory/` into
  `studios/<studio>/memory/`, skipping files that are already links back into
  the repository.
- `studios/general/` is carried across with the same minimal content, so the
  multi-studio path stays tested.

## Repository layout

```
omega-ai/
├── install.sh  uninstall.sh  doctor.sh  sync-memory.sh   # studio-aware
├── lib/common.sh
├── shared/CLAUDE.part.md                                 # merged into every studio's CLAUDE.md
├── studios/
│   ├── game-dev/                                         # a Claude Code plugin + studio manifest
│   │   ├── .claude-plugin/plugin.json                    # name: game-dev → /game-dev:* namespace
│   │   ├── studio.json  requires.txt
│   │   ├── CLAUDE.md  settings.json  memory/MEMORY.md
│   │   ├── hooks/hooks.json  hooks/session-start.sh  hooks/bootstrap.md
│   │   ├── skills/                                       # one directory per skill, flat
│   │   │   ├── studio/ brainstorm/ plan/ execute/ review/ playtest/ ship/ retro/ scaffold/
│   │   │   └── gdd/ core-loop/ game-feel/ sprite-pipeline/ vertical-slice/ tuning-data/ milestone-gates/
│   │   ├── agents/                                       # ten roles, one .md each
│   │   ├── bin/                                          # studio-test studio-run studio-lint studio-state studio-scaffold
│   │   └── engines/godot/                                # GUIDE.md resolve.sh test.sh run.sh lint.sh template/
│   └── general/                                          # minimal second studio
├── docs/
│   ├── game-dev/                                         # this studio's own evolution
│   │   ├── specs/  plans/  artifacts/  PROGRESS.md
│   └── superpowers/                                      # installer history from 2026-09-04, unchanged
└── tests/                                                # POSIX sh, no dependencies
```

## Session bootstrap hook

`hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"" }
        ]
      }
    ]
  }
}
```

`session-start.sh` is POSIX shell. It reads `hooks/bootstrap.md`, fills the
identity line from `.studio/config.json` in the current directory when that
file exists (falling back to the studio defaults), JSON-escapes the result,
and prints `{"hookSpecificOutput": {"hookEventName": "SessionStart",
"additionalContext": "<escaped bootstrap text>"}}`. It is the only hook the
studio installs; nothing runs on every tool call.

`bootstrap.md` contains, in order:

1. **Identity line.** "You are in the omega-ai game-dev studio. Engine: Godot
   4.x · 2D · GDScript · GUT." — values substituted from configuration.
2. **Precedence rule**, verbatim from the approval artifact: `game-dev:*`
   stage skills own the workflow. superpowers skills run only when a stage
   skill names them. godot-prompter skills run inside role agents for engine
   work. If superpowers' own bootstrap says "invoke brainstorming", invoke
   `game-dev:brainstorm` instead.
3. **Stage list** with one line each: studio, brainstorm, plan, execute,
   review, playtest, ship, retro, scaffold.
4. **State instruction.** "If `.studio/STATE.md` exists, read it and report the
   current stage and the next step in one line before doing anything else. If
   it does not exist and this is a Godot project, suggest `/game-dev:studio`."

## Workflow

Every stage is a skill invoked by name. Each reads the file the previous stage
wrote and writes one of its own, so a stage can be re-run, skipped when it
does not apply, or resumed in a new session. Three points require the user's
explicit approval: spec approval, plan approval, playtest sign-off.

Skill `description` fields start with "Use when", per the superpowers
convention, so the trigger is what the model reads first.

### `/game-dev:studio` — router

```yaml
name: studio
description: Use when starting a game-dev session, unsure which stage comes next, or handing freeform text to the studio — reads .studio/STATE.md and routes to the right stage skill.
```

Reads `.studio/STATE.md` and `PROGRESS.md`; prints the stage, the milestone,
and the next step. With freeform text it routes: a feature or system request
→ `brainstorm`; "feels wrong / floaty / laggy" → `playtest` (feel pass); "is
this done?" → `review`; "new project" → `scaffold`. It never does the work
itself. Without `.studio/` it offers `scaffold` or `brainstorm`.

### `/game-dev:brainstorm`

```yaml
name: brainstorm
description: Use when starting any game feature, system, or new game before code is written — clarifies intent in batched questions, classifies scope, writes a spec with GDD-lite sections, renders it as an artifact, and waits for approval.
```

- Classifies the request as spike, bounded, or architectural and says so.
- Asks clarifying questions in batches of three to four per
  `AskUserQuestion`, in decision-brief form (question, stakes, recommendation,
  options).
- Proposes two or three approaches with a recommendation.
- Writes the spec to `docs/game-dev/specs/YYYY-MM-DD-<topic>.md` in the game
  project with these sections: Purpose; Core-loop delta; Player verbs (added,
  changed, removed); Feel targets in real units; Acceptance criteria;
  Architecture (scene tree, state, signals, Resources); Test strategy — which
  behaviour gets unit tests and which gets playtest criteria; Not doing.
- Renders the spec as an Artifact page (HTML written locally, published with
  the Artifact tool), saves the same HTML to `docs/game-dev/artifacts/`, and
  **stops** until the user approves.
- Sets `stage: brainstorm` and `spec:` in `STATE.md`.
- Delegates: `game-dev:gdd`, `game-dev:core-loop`, `game-dev:game-feel`; on
  the architectural path, dispatches `game-dev:architect` for the architecture
  section.

### `/game-dev:plan`

```yaml
name: plan
description: Use when an approved spec exists and needs an implementation plan — writes role-tagged, verify-tagged tasks, runs the producer scope pass, and waits for approval.
```

- Reads the approved spec. Uses the superpowers `writing-plans` task format
  and adds two lines to every task:

  ```
  ### Task 3: Input action and buffer window
  Role: game-dev:gameplay-programmer
  Verify: unit
  Files: src/player/dash_state.gd, tests/unit/test_dash_input.gd
  ```

  `Verify:` is a `+`-joined list of `unit`, `playtest`, `visual`; any task
  that introduces a tunable value includes `unit`; the unit test targets the
  project's configured test framework (`tests` in `.studio/config.json`,
  default GUT).
- Dispatches `game-dev:producer` for the scope pass. The producer cuts every
  task that is not needed for the current milestone into a "Backlog" section
  at the end of the plan and says why.
- Writes `docs/game-dev/plans/YYYY-MM-DD-<topic>.md`, sets `stage: plan` and
  `plan:` in `STATE.md`, and **stops** until the user approves.

### `/game-dev:execute`

```yaml
name: execute
description: Use when an approved plan exists — dispatches a fresh role agent per task with a reviewer after each; pass --inline for checkpointed inline execution.
```

- Default mode is subagent-driven: for each task, dispatch the agent named in
  `Role:` with a fresh context containing only the task text, the spec
  sections it cites, and the studio conventions. When `Verify: unit`, the
  agent follows `superpowers:test-driven-development` and runs `studio-test`
  before reporting. After each task, dispatch `game-dev:reviewer` for spec
  compliance and Godot best practice; the implementer fixes findings before
  the next task starts.
- Works in a git worktree via `superpowers:using-git-worktrees`.
- Records every judgment call as a ruling in the feature ledger
  (`.studio/ledger/<feature>.md`, via `studio-state ledger`) and advances
  `task: n/N`. Stops only for irreversible, security-sensitive, or
  out-of-worktree side effects, or a plan too broken to follow.
- `--inline` follows `superpowers:executing-plans` instead: the main session
  implements tasks in batches and checks in with the user between batches.
- Requires the spec and plan to be committed before entering the worktree.
- Before setting `stage: review`, boots the project headless once
  (`godot --headless --quit-after 1`) and requires a clean log; lists every
  unverified playtest and visual item; never merges.

### `/game-dev:review`

```yaml
name: review
description: Use when a branch or diff needs a spec-compliance and Godot best-practice review before playtest or ship.
```

Dispatches `game-dev:reviewer` over the whole branch (or a named diff) with
the spec. Findings are one line each, severity-tagged; the reviewer applies
`godot-prompter:godot-code-review` and checks specifically for inheritance
chains where composition was specified, cross-system references that bypass
the event bus, tuning literals outside `Resource` files, and per-frame
allocations. Fixes are committed; the skill re-runs `studio-test`. Sets
`stage: playtest`.

### `/game-dev:playtest`

```yaml
name: playtest
description: Use when implementation is done and needs verification in the running game — runs automated tests and a headless boot, then a human playtest script with a bug loop.
```

1. Automated: `studio-test` must pass; `studio-run` boots the project (or the
   scene named in the spec) for the configured seconds and must produce no
   script errors.
2. Script: `game-dev:playtester` builds a numbered script from the spec's feel
   targets and acceptance criteria and from every plan task tagged
   `Verify: playtest`. Each item states the action, the expected perceptual
   result, and what a failure looks like.
3. Session: the **main session** (not the agent — subagents cannot reach the
   user) asks one `AskUserQuestion` per item: pass, fail, or note.
4. Bug loop: each failure becomes a bug with repro steps; the fix is
   implemented with a regression test (`studio-test` grows), and the failed
   item is re-run. The loop ends when every item passes or the user defers an
   item to the backlog.
5. Report: `docs/game-dev/playtests/YYYY-MM-DD-<topic>.md` with the script,
   results, bugs, and fixes. Sets `last_playtest:` and `stage: ship`, and
   **stops** for the user's sign-off.

### `/game-dev:ship`

```yaml
name: ship
description: Use when a playtest is signed off — verifies, finishes the branch, and updates PROGRESS.md.
```

Runs `superpowers:verification-before-completion` (tests, lint, run — with
output shown, not asserted), then `superpowers:finishing-a-development-branch`
to open a PR or merge as the user chooses. Dispatches `game-dev:producer` to
update `PROGRESS.md`: what shipped, and whether the milestone gate moves. Sets
`stage: retro`.

### `/game-dev:retro`

```yaml
name: retro
description: Use when a feature has shipped or a working session ends — captures durable decisions and pitfalls into studio memory.
```

Reads the ledger and playtest reports. Writes one memory file per durable
decision into the studio memory directory (`$CLAUDE_CONFIG_DIR/memory/`),
following the repository's memory format (frontmatter with `name`,
`description`, `type`; body with why and how to apply), and adds a line to
`MEMORY.md`. Reminds the user to run `sync-memory.sh game-dev` to commit.
Sets `stage: idle` and clears `spec:`, `plan:`, `task:`.

### `/game-dev:scaffold`

```yaml
name: scaffold
description: Use when creating a new game project — materialises the engine template with studio conventions, state, docs layout, and a test harness.
```

Runs `studio-scaffold DIR`, then opens `/game-dev:brainstorm` for the first
feature. Delegates to `godot-prompter:godot-project-setup` for engine-side
settings the template does not cover.

## State and configuration

`config.json`, `STATE.md` and the `ledger/` directory live in the game
project under `.studio/`. `config.json` and `ledger/` are committed;
`STATE.md` is a local pointer that `studio-state init` gitignores.

### `.studio/config.json`

Flat keys, same vocabulary as `studio.json`; any missing key falls back to the
studio default:

```json
{ "engine": "godot4", "dimension": "2d", "language": "gdscript", "tests": "gut" }
```

### `.studio/STATE.md`

```markdown
# Studio State

stage: execute
spec: docs/game-dev/specs/2026-09-13-player-dash.md
plan: docs/game-dev/plans/2026-09-13-player-dash.md
task: 3/6
last_playtest: docs/game-dev/playtests/2026-09-12-movement.md
milestone: prototype

## Ledger
```

### `.studio/ledger/player-dash.md`

```markdown
- 2026-09-13 T3 Ruling: buffer window 0.1 s — spec said "short" — cost if wrong: retune one value
- 2026-09-13 T1 Review: cooldown literal moved to DashTuning.tres
```

`stage` is one of `idle`, `brainstorm`, `plan`, `execute`, `review`,
`playtest`, `ship`, `retro`. `milestone` is one of `prototype`,
`vertical-slice`, `alpha`, `beta`, `gold`. Empty values are written as `-`.

The pointer lives in the project's main checkout: `studio-state` resolves it
through `git rev-parse --git-common-dir`, so a linked worktree edits the same
file and a project has one stage at a time. It is gitignored, so a fresh
clone starts idle: `studio-state init` and `studio-state set spec/plan`
re-point it at the committed spec and plan, after which `studio-state check
--rebuild` rebuilds `task` from the feature ledger.

### `.studio/ledger/<feature>.md`

The decision log is per feature: one file named from the spec's slug
(`2026-09-13-player-dash.md` → `ledger/player-dash.md`), append-only,
committed with the branch that works the feature, so two features on two
branches never touch the same file. Lines written while no spec is set (idle
rulings, bug fixes, `abandoned <spec>`) go to `STATE.md`'s own `## Ledger`.
The spec, the plan and the ledger are committed at each approval gate so a
worktree cut afterwards carries them. All writes go through `studio-state`;
a PreToolUse hook blocks direct edits.

This state file, and the router that reads it, is the whole of what the
studio borrows from GSD.

## Agents

Agents are the long-session workforce. A stage skill dispatches an agent with
a fresh context and exactly the task in hand; agents never inherit the user's
conversation. Each agent file has frontmatter (`name`, `description` starting
"Use when", `tools`, `model: inherit`), a persona, the skills it may call, and
an output contract — the file or commit it must leave behind. All ten live in
`agents/` and are addressed as `game-dev:<name>`. In the "May call" column,
a bare name following a `godot-prompter:` entry is also a `godot-prompter:`
skill; the prefix is written once per cell for readability.

| Agent | Owns | Dispatched by | Tools | Output contract | May call |
|-------|------|---------------|-------|-----------------|----------|
| `game-designer` | Core loop, mechanics, progression, difficulty, GDD-lite. Engine-agnostic; never opens engine files. | brainstorm | Read, Write, Edit, Grep, Glob, WebSearch | GDD sections in the spec | `game-dev:gdd`, `game-dev:core-loop` |
| `level-designer` | Level layout, pacing, teaching sequence, tile and collision rules. | brainstorm, execute | Read, Write, Edit, Grep, Glob | Level spec; TileMapLayer authoring notes | `godot-prompter:2d-essentials`, `godot-prompter:procedural-generation` |
| `architect` | Scene tree, state machines, signal and event-bus topology, Resource schemas. | brainstorm (architectural), plan | Read, Write, Edit, Grep, Glob | Architecture section; task decomposition | `godot-prompter:godot-brainstorming`, `scene-organization`, `state-machine`, `event-bus`, `component-system`, `dependency-injection` |
| `gameplay-programmer` | Implements plan tasks in GDScript with TDD. | execute | Read, Write, Edit, Grep, Glob, Bash | Commits plus passing `studio-test` | `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `godot-prompter:gdscript-patterns`, `gdscript-advanced`, `player-controller`, `state-machine`, `event-bus`, `component-system`, `resource-pattern`, `physics-system`, `godot-testing`, `godot-debugging` |
| `tech-artist` | Sprite pipeline, atlases, import settings, pixels-per-unit, animation frame budgets. | execute | Read, Write, Edit, Grep, Glob, Bash | Assets plus versioned import settings | `game-dev:sprite-pipeline`, `godot-prompter:2d-essentials`, `assets-pipeline`, `particles-vfx` |
| `feel-tuner` | Input latency, forgiveness windows, acceleration curves, animation timing, camera, then juice — in that order. | execute, playtest | Read, Write, Edit, Grep, Glob, Bash | Tuning values in Resources plus a hypothesis log | `game-dev:game-feel`, `godot-prompter:tween-animation`, `camera-system`, `animation-system`, `input-handling` |
| `ui-designer` | Control-tree HUD and menus, themes, responsive layout. | execute | Read, Write, Edit, Grep, Glob, Bash | UI scenes plus a Theme resource | `godot-prompter:godot-ui`, `hud-system`, `responsive-ui`, `localization` |
| `producer` | Scope: vertical slice first, cut lists, milestone gates, backlog. | plan, ship | Read, Write, Edit, Grep, Glob | Cut list in the plan; `PROGRESS.md` update | `game-dev:vertical-slice`, `game-dev:milestone-gates` |
| `playtester` | Playtest script from spec criteria; bug reports with repro steps. | playtest | Read, Write, Grep, Glob, Bash | Playtest script and report | `godot-prompter:godot-testing`, `godot-debugging` |
| `reviewer` | Spec compliance plus Godot best-practice review. No praise; one line per finding. | execute (per task), review | Read, Grep, Glob, Bash | Findings list; fix commits when asked | `godot-prompter:godot-code-review`, `godot-optimization` |

**Interim (Plan 1).** Until the ten agents ship, the stage skills dispatch:
brainstorm dispatches `game-dev:game-designer` and, on the architectural
path, `godot-prompter:godot-game-architect` for the `architect` role;
execute dispatches `godot-prompter:godot-game-dev` for
`gameplay-programmer` and `godot-prompter:godot-ui-designer` for
`ui-designer`, the shipped `game-dev:feel-tuner` and `game-dev:tech-artist`
as themselves, and `general-purpose` for `level-designer`; the per-task
reviewer is `godot-prompter:godot-code-reviewer`. The godot-prompter agents
get the studio persona prepended. Plan 2 replaces these with the studio's
own agents.

When `.studio/config.json` sets `language: csharp`, `gameplay-programmer`
routes engine work to `godot-prompter:godot-csharp-engineer` instead of the
GDScript skills; nothing else changes.

### Migration of existing content

The three agents and four skills in the current `profiles/game-dev/` are
kept, with their content preserved and their names aligned to this design:

| Existing | Becomes |
|----------|---------|
| `agents/game-designer.md` | `agents/game-designer.md` (unchanged name) |
| `agents/2d-art-pipeline.md` | `agents/tech-artist.md` |
| `agents/game-feel-tuner.md` | `agents/feel-tuner.md` |
| `skills/game-design-doc/` | `skills/gdd/` |
| `skills/core-loop-design/` | `skills/core-loop/` |
| `skills/2d-sprite-pipeline/` | `skills/sprite-pipeline/` |
| `skills/game-feel/` | `skills/game-feel/` (unchanged name) |

## Domain skills

Domain skills are knowledge; stage skills are process. Each is one directory
with a `SKILL.md`, addressed as `game-dev:<name>`:

- `gdd` — the six-section decision-dense design document (pitch, core loop,
  verbs, progression, failure, scope).
- `core-loop` — perceive → decide → act → feedback → state change, and the
  questions that test it.
- `game-feel` — the diagnostic order: latency, forgiveness, acceleration,
  animation timing, camera, then effects.
- `sprite-pipeline` — base resolution, pixels-per-unit, filtering, atlases,
  animation import for Godot 4.x 2D.
- `vertical-slice` — what a slice must prove, what to cut to reach it, how to
  tell a slice from a demo.
- `tuning-data` — putting every tunable number in a `Resource`, naming and
  grouping conventions, designer-editable defaults.
- `milestone-gates` — the prototype → vertical slice → alpha → beta → gold
  gates, the exit criteria of each, and how `PROGRESS.md` records them.

## Toolkits

### `bin/` verbs

The stage skills call these verbs and never the engine directly. Each script
is POSIX shell, finds the studio root through `$OMEGA_STUDIO_ROOT` (set by the
shim) and, when that is unset, by resolving its own location; reads the
engine from `.studio/config.json` in the current project (falling back to
`studio.json`); and dispatches to `engines/<engine>/<verb>.sh`.

| Verb | Arguments | Exit codes | Output |
|------|-----------|------------|--------|
| `studio-test` | `[PATH]` — a test directory or file, default the whole suite | 0 all passed · 1 failures · 2 engine not found · 3 test framework not installed | One summary line `studio-test: N passed, M failed`; JUnit XML at `.studio/reports/test-<timestamp>.xml`; failing test names echoed |
| `studio-run` | `[--scene RES_PATH] [--seconds N] [--windowed]` — default the main scene, 10 s, headless | 0 clean · 1 script errors in the log · 2 engine not found | Full log at `.studio/reports/run-<timestamp>.log`; last 40 lines echoed; error lines echoed first |
| `studio-lint` | `[PATH]` | 0 clean · 1 findings · 3 linter not installed (prints the install hint) | Findings as `path:line: message` |
| `studio-state` | `get KEY` · `set KEY VALUE` · `ledger TEXT` · `show` · `init` | 0 · 1 no `.studio/` (except `init`) | `get` prints the value; `show` prints the file |
| `studio-scaffold` | `DIR [--name NAME]` | 0 · 1 target exists and is not empty | Created tree listed |

`.studio/reports/` is git-ignored by the scaffold.

### Engine adapter contract

```
engines/<engine>/
├── GUIDE.md      which external skills to call for this engine, by role
├── resolve.sh    print the engine binary path, or exit 2
├── test.sh       run the test suite; same exit codes and output as studio-test
├── run.sh        boot the project or a scene; same contract as studio-run
├── lint.sh       lint; same contract as studio-lint
└── template/     scaffold source for studio-scaffold
```

The `studio-*` verbs are the stable interface; an engine directory is the
only place an engine's command line appears.

### Godot adapter

- **Resolution order** (`resolve.sh`): `$GODOT_PATH` if set and executable;
  else the first match of `/Applications/Godot*.app/Contents/MacOS/Godot`;
  else `godot` on `PATH`; else exit 2 with "no Godot binary found; set
  GODOT_PATH".
- **Tests** (`test.sh`): GUT via its command-line runner:

  ```sh
  "$GODOT" --headless --path "$PROJECT" -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests -ginclude_subdirs -gexit \
    -gjunit_xml_file=res://.studio/reports/test-<timestamp>.xml
  ```

  Exit 3 when `addons/gut/gut_cmdln.gd` is absent, printing the exact
  install command from `engines/godot/GUIDE.md` (a `git clone --depth 1` of
  the pinned GUT release into `addons/gut`).
- **Run** (`run.sh`): launches `"$GODOT" --headless --path "$PROJECT" [SCENE]`
  in the background, sleeps `N` seconds, sends `TERM`, then scans the captured
  log for `SCRIPT ERROR`, `ERROR:` and `Parser Error` lines; `--windowed`
  drops `--headless`.
- **Lint** (`lint.sh`): `gdlint` then `gdformat --check` from gdtoolkit; exit 3
  with `pip install "gdtoolkit==4.*"` when neither is on `PATH`.
- **`GUIDE.md`**: the role → godot-prompter skill map from the agents table,
  in one place, so an agent's own list can stay short.

### MCP

`godot-mcp` (Coding-Solo, MIT) exposes: launch the editor, run the project
with console and error capture, stop it, list and analyse projects, create
scenes, add nodes with properties, load sprites, export MeshLibrary, and
maintain UIDs (Godot 4.4+). Requirements: Node.js ≥ 18, a Godot binary,
`GODOT_PATH` for a non-default location. It is registered by the installer as
described above and is deliberately **not** shipped in the plugin's
`.mcp.json`, so a machine without Node never sees a startup failure. Skills
treat it as an optional accelerator: `studio-run` is the required path;
`mcp__godot__*` tools are used when present for interactive editor work.

### Scaffold template

`engines/godot/template/` is a runnable Godot 4 2D project:

- `project.godot` with a fixed base resolution (640×360), stretch mode
  `canvas_items`, aspect `keep`, default texture filter Nearest, and the
  `EventBus` autoload registered.
- `src/` organised by feature; `src/autoloads/event_bus.gd` with typed
  signals; `src/player/` with a minimal `CharacterBody2D` and a state machine
  skeleton.
- `resources/tuning/` with one example `Resource` and its `.tres`.
- `tests/unit/test_smoke.gd` (GUT) proving the harness runs.
- `.studio/config.json`, `.studio/STATE.md` (stage `idle`, milestone
  `prototype`), `.studio/.gitignore` for `reports/`.
- `docs/game-dev/{specs,plans,playtests,artifacts}/.gitkeep` and
  `docs/game-dev/PROGRESS.md` seeded with the five milestone gates.
- A project `CLAUDE.md` carrying the studio's architecture and 2D standards.
- `.gitignore` for Godot, `.gdlintrc`.

GUT itself is not vendored: `studio-scaffold` clones the pinned GUT release
into `addons/gut/` when the network is available and prints the manual step
otherwise. `studio-test` exits 3 until it is present.

## Extensibility seams

Godot 2D GDScript is the first pack. Three seams keep 3D, another language or
another engine from being a rewrite:

- **Dimension.** Domain skills carry a 2D section now; a 3D section is added
  to the same skill (camera, lighting, mesh pipeline). `config.dimension`
  tells the skill which to read. New 3D-only skills get a `3d-` prefix.
- **Language.** `config.language` routes the gameplay-programmer to
  `godot-prompter:godot-csharp-engineer` and the test verb to gdUnit4 through
  the engine adapter. Stage skills never mention a language.
- **Engine.** A Unity pack is `engines/unity/` with the same five files and a
  template. Stage skills, roles, state and the docs layout do not change.
- **Another studio.** `studios/<name>/` with its own `studio.json`; the
  installer has no per-studio branches.

## Docs layout and memory

**This repository.** `docs/game-dev/` tracks the game studio's own evolution:
`specs/` (this file), `plans/` (the three implementation plans), `artifacts/`
(the HTML of every approval page), and `PROGRESS.md` (a dated log plus the
status of each plan). `docs/superpowers/` keeps the 2026-09-04 installer spec
and plan unchanged.

**A game project.** The same layout, produced by the scaffold:
`docs/game-dev/{specs,plans,playtests,artifacts}` and `PROGRESS.md`, whose
first section is the milestone gate (prototype → vertical slice → alpha →
beta → gold) with the exit criteria of the current gate.

**Memory.** Studio memory is `studios/game-dev/memory/MEMORY.md`: curated,
cross-project decisions the retro skill writes, linked into the config root
and imported by the rendered `CLAUDE.md`, synced back with
`sync-memory.sh game-dev`. Claude Code's auto memory is separate and stays
per project under `~/.claude-gamedev/projects/<project>/memory/` — a
different config root from `~/.claude`, so nothing crosses over.

## Testing the framework

`tests/` remains a POSIX shell harness with no dependencies. These cases are
added or updated; each is written before the script it covers:

1. **Install.** Installing `game-dev` into a temporary target creates the
   rendered `CLAUDE.md`, the copied `settings.json`, links for every entry of
   `memory/` and `bin/`, and a shim whose text contains `CLAUDE_CONFIG_DIR=`,
   `PATH="<target>/bin:`, `--plugin-dir "<studio dir>"`, and
   `OMEGA_STUDIO_ROOT=`. No `agents/`, `skills/`, or `hooks/` directory is
   created in the target.
2. **Copy mode.** `--mode copy` places the studio under `<target>/studio/` and
   the shim's `--plugin-dir` points there.
3. **Guards.** A target of `~/.claude`, `$HOME`, or a path inside the
   repository is refused before anything is written. `--dry-run` creates
   nothing.
4. **Uninstall.** Everything in the manifest is removed; `--purge --yes`
   removes the root. `--no-mcp` installs leave no `mcp` manifest line.
5. **Plugin manifest.** `.claude-plugin/plugin.json` is valid JSON (checked
   with `jq` when present, otherwise a strict `sed` pattern) and its `name`
   equals `studio.json`'s.
6. **Frontmatter and reference lint.** Every `skills/*/SKILL.md` has `name`
   equal to its directory and a `description` beginning "Use when"; every
   `agents/*.md` has `name` equal to its file stem, a `description` beginning
   "Use when", a `tools` line, and `model: inherit`. Every `superpowers:` or
   `godot-prompter:` name found in `skills/`, `agents/` or `engines/` appears
   in `requires.txt`.
7. **Doctor.** With a fake plugin cache containing every name in
   `requires.txt`, doctor exits 0; remove one `SKILL.md` and it exits non-zero
   naming the missing skill; with the cache directory absent it warns and
   exits 0.
8. **Toolkit syntax.** Every file in `bin/` and `engines/*/` passes `sh -n`.
9. **Scaffold.** `studio-scaffold` into a temporary directory produces
   `project.godot`, `.studio/config.json`, `.studio/STATE.md`,
   `docs/game-dev/PROGRESS.md`, and `tests/unit/test_smoke.gd`; running it
   again against the non-empty directory exits 1.
10. **Engine-dependent.** `studio-test` and `studio-run` against the template
    run when `resolve.sh` finds a Godot binary and report `skipped: no Godot`
    otherwise; the test passes in both cases.
11. **Second studio.** Installing `general` into a second temporary target
    does not disturb the first.

Skill *behaviour* is verified the superpowers way, not by shell tests: for
each stage skill, a pressure scenario is run once without the skill to record
the baseline failure, then with it; both transcripts are summarised in
`docs/game-dev/` and the skill is adjusted until the scenario passes.

## Delivery

One design spec, three sequenced implementation plans. Each plan ends with a
working `claude-gd`.

**Plan 1 — Foundation.** `profiles/` → `studios/`; plugin packaging; the shim
with `--plugin-dir`, `PATH` and `OMEGA_STUDIO_ROOT`; installer, uninstaller,
doctor (studio-aware; the delegation check arrives in Plan 2) and tests
updated; the session hook; `docs/game-dev/`;
`.studio/STATE.md` and `studio-state`; and the four skills the daily loop
needs: `studio`, `brainstorm`, `plan`, `execute`.
*Exit:* plan and execute a feature in an existing Godot project through
`claude-gd`.

**Plan 2 — Quality loop.** The ten role agents (migrating the existing
three); `review`, `playtest`, `ship`, `retro`; the `bin/` verbs with the Godot
adapter; optional `godot-mcp` registration; the doctor delegation check.
*Exit:* the full session in the approval artifact's §5 runs end to end.

**Plan 3 — Content.** `scaffold` and the template project; migrate the four
existing skills and add `vertical-slice`, `tuning-data`, `milestone-gates`;
`PROGRESS.md` conventions; `general` studio parity; skill pressure tests.
*Exit:* a new game project from zero to its first playtest using only studio
commands.

## Out of scope

- A Copilot installer. Skills stay in the portable `SKILL.md` format so one
  can be added later.
- A Unity pack, 3D content, or C# content. The seams exist; the packs do not.
- Publishing the repository as a plugin marketplace.
- GSD-style phases, roadmaps, or verifier agents. Only the state file and the
  router are borrowed.
- Telemetry, analytics, or any network call from a skill or hook.
- Browser-driven QA. Playtest is headless Godot plus the human at the
  keyboard.

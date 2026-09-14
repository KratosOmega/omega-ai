# omega-ai

Version-controlled Claude Code **studios** — each a plugin (skills, agents,
hooks) plus a small manifest — installable into its own isolated config
directory. Installing a studio never touches `~/.claude`. Switching between
assistants is a matter of which command you type.

## Studios

| Studio | Config root | Launch | Purpose |
|---|---|---|---|
| `game-dev` | `~/.claude-gamedev` | `claude-gd` | A small game studio: stage skills, role agents, Godot 4.x 2D toolkit |
| `general` | `~/.claude-general` | `claude-gen` | Minimal clean-room studio |

## Install

```sh
./install.sh game-dev
```

This creates `~/.claude-gamedev` with a rendered `CLAUDE.md`, a copied
`settings.json`, and links to the studio's `memory/` and `bin/`; writes a shim
at `~/.local/bin/claude-gd`; records the mode and the shim path in
`~/.claude-gamedev/.omega-ai-manifest`; and runs `doctor.sh`. The shim
launches Claude Code with `CLAUDE_CONFIG_DIR` pointing at the config root, the
studio's `bin/` and the global plugin's `bin/` on `PATH`, and two
`--plugin-dir` flags — `studios/game-dev/` and `shared/omega/`, the `omega`
global plugin every studio loads — so the studio's skills, agents and hooks
and the `/omega:*` skills load straight from this checkout — edit a skill and
it is live in the next session. The rendered `CLAUDE.md` imports
`memory/MEMORY.md`, the studio's own memory (see Memory below).

Add `~/.local/bin` to your `PATH` if it is not there already. Then:

```sh
claude       # your existing setup, unchanged
claude-gd    # the game-dev studio
```

The first `claude-gd` launch fetches the plugins the studio depends on
(superpowers, godot-prompter) into the isolated config root.

Options: `--mode copy` for a frozen snapshot (the studio is copied to
`~/.claude-gamedev/studio/`, the global plugin to `~/.claude-gamedev/global/`,
and both are loaded from there), `--target DIR` for a
different config root, `--shim-dir DIR` for a different shim location,
`--no-mcp` (accepted now; MCP registration arrives with the engine toolkit
in Plan 2), and `--dry-run` to see every action — including the removal of
a previous install's entries — without performing it. Reinstalling checks
that the studio's files are all present, then removes everything the
previous install recorded before writing anew. The install exits non-zero
when the doctor finds a problem.

### Upgrading from `profiles/`

An install made by the earlier `profiles/` installer linked `skills/`,
`agents/`, `commands/` and `hooks/` into the config root and wrote a shim
without `--plugin-dir`. `doctor.sh` now reports that as a stale layout.
Run `./install.sh <studio>` again: the old manifest's entries are removed and
the new shim is written.

## Use

Inside `claude-gd`, in a Godot project:

| Command | Does |
|---|---|
| `/game-dev:studio` | Reads `.studio/STATE.md`, reports the stage and milestone, names the next step, routes freeform text |
| `/game-dev:brainstorm` | Batched questions → spec with GDD-lite sections → artifact page → **your approval** |
| `/game-dev:plan` | Tasks tagged `Role:` and `Verify: unit \| playtest \| visual`, producer scope cut → **your approval** |
| `/game-dev:execute` | Fresh subagent per task, reviewer after each; `--inline` for checkpointed execution |

`review`, `playtest`, `ship`, `retro` and `scaffold` arrive in later releases;
the session bootstrap says so when one is missing. State lives in the
project's `.studio/`: `STATE.md` is the stage/task pointer — local, gitignored,
resolved to the project's main checkout from any worktree — and
`ledger/<feature>.md` is the feature's decision log, committed with the
feature. Both are written only through `studio-state`; a hook blocks direct
edits.

## Check

```sh
./doctor.sh game-dev
```

Reports the config root, the plugin directory the shim loads and its skill /
agent counts, the global plugin (`global plugin: omega 0.1.0   skills 5  hooks
present`), every plugin `requires.txt` declares (enabled? fetched? which
version?), the shim the install recorded (present? launches this root?
loads both plugins?), whether that shim's directory is on `PATH`, any stale
layout from the earlier installer, and whether anything leaks back into
`~/.claude`. Exits non-zero on a missing `CLAUDE.md` or `settings.json`, a
name mismatch, a missing plugin, a missing or misnamed global plugin, a stale
or foreign shim (including one written before the global plugin existed —
reinstall to fix it), a stale layout, or a leak. `--target DIR` checks a root
installed elsewhere.

## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely (asks; --yes skips)
```

Uninstall removes what the manifest recorded and the shim the manifest names
— unless that shim now launches a different config root, in which case it is
kept and said so. `--purge` refuses a directory that has no manifest.
`--target DIR` and `--shim-dir DIR` match the flags the install used;
`--shim-dir` is only needed for installs made before the manifest recorded
the shim.

## Memory

Two memories exist, and they do not mix.

**Studio memory** is `studios/<studio>/memory/MEMORY.md` — curated,
cross-project decisions the retro stage writes (design rulings, pipeline
conventions). It is linked into the config root and imported by the rendered
`CLAUDE.md`, so every `claude-gd` session loads it. It never reaches plain
`claude`. Pull in-session edits back into version control with:

```sh
./sync-memory.sh game-dev
```

**Claude's auto memory** is per project and per config root:
`~/.claude-gamedev/projects/<project>/memory/`. A game project and a business
project have different paths, and `claude-gd` and `claude` have different
config roots, so nothing crosses over. The installer does not touch it.

In copy mode the config root holds a copied `memory/`, and a reinstall or
uninstall removes that copy, in-session edits included — run
`./sync-memory.sh <studio>` first.

## What is and is not isolated

Isolated per studio: `CLAUDE.md`, `settings.json`, plugins, sessions,
history, and memory. The studio's own skills, agents and hooks come from the
plugin directory and are never copied into the config root in symlink mode.

Not isolated, by design: a project's own `CLAUDE.md` and `.claude/` directory
load in every studio, because they describe the project rather than the
assistant. System- or enterprise-managed settings also still apply.

## Adding a studio

Create `studios/<name>/` with `.claude-plugin/plugin.json` (`name` must equal
the directory), `studio.json`, `requires.txt`, `CLAUDE.md`, and
`settings.json`, plus any `skills/`, `agents/`, `hooks/`, `bin/`, or
`memory/`. Content in `shared/` is merged into every studio's `CLAUDE.md`.
Run `sh tests/run_all.sh` to check the studio contract.

## Layout

```
studios/<name>/
├── .claude-plugin/plugin.json   what Claude Code reads (name → namespace)
├── studio.json                  what install.sh / doctor.sh read
├── requires.txt                 plugins, skills, agents the studio depends on
├── skills/ agents/ hooks/       plugin content, loaded live via --plugin-dir
├── bin/                         toolkit, linked into the config root and put on PATH
└── CLAUDE.md settings.json memory/   installed into the config root

shared/omega/                    the omega global plugin, loaded by every shim
├── .claude-plugin/plugin.json   name "omega" → the /omega: namespace
├── skills/                      handoff, parallel, local-merge, integration, autopilot
├── hooks/                       SessionStart, UserPromptSubmit, SessionEnd: the mode line
└── bin/omega-mode               the mode file's one writer; on PATH inside every studio

.claude-plugin/marketplace.json  publishes omega for plain claude (claude plugin marketplace add <repo>)
```

## Docs

`docs/game-dev/` holds the game studio's design spec, implementation plans,
approval artifacts and progress log. `docs/omega/` holds the global plugin's
design spec, implementation plans and progress log. `docs/superpowers/` holds
the earlier profiles installer design.

## Tests

```sh
sh tests/run_all.sh
```

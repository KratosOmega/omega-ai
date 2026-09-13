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
at `~/.local/bin/claude-gd`; and runs `doctor.sh`. The shim launches Claude
Code with `CLAUDE_CONFIG_DIR` pointing at the config root, the studio's
`bin/` on `PATH`, and `--plugin-dir` pointing at `studios/game-dev/`, so the
studio's skills, agents and hooks load straight from this checkout — edit a
skill and it is live in the next session.

Add `~/.local/bin` to your `PATH` if it is not there already. Then:

```sh
claude       # your existing setup, unchanged
claude-gd    # the game-dev studio
```

The first `claude-gd` launch fetches the plugins the studio depends on
(superpowers, godot-prompter) into the isolated config root.

Options: `--mode copy` for a frozen snapshot (the studio is copied to
`~/.claude-gamedev/studio/` and loaded from there), `--target DIR` for a
different config root, `--shim-dir DIR` for a different shim location,
`--no-mcp` (accepted now; MCP registration arrives with the engine toolkit
in Plan 2), and `--dry-run` to see every action without performing it.
Reinstalling removes everything the previous install recorded first.

Install paths must not contain spaces.

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
project's `.studio/STATE.md`, written only through `studio-state`.

## Check

```sh
./doctor.sh game-dev
```

Reports the config root, the plugin manifest and its skill / agent counts,
every plugin `requires.txt` declares (enabled? fetched? which version?),
whether the shim is on `PATH`, and whether anything leaks back into
`~/.claude`. Exits non-zero on a name mismatch, a missing plugin, or a leak.

## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely
```

## Memory

Memory written during a session lives in the studio's config root. Pull it
back into version control with:

```sh
./sync-memory.sh game-dev
```

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
```

## Docs

`docs/game-dev/` holds the game studio's design spec, implementation plans,
approval artifacts and progress log. `docs/superpowers/` holds the earlier
profiles installer design.

## Tests

```sh
sh tests/run_all.sh
```

# omega-ai

Version-controlled Claude Code profiles — agents, skills, commands, settings,
and seed memory — each installable into its own isolated config directory.

Installing a profile never touches `~/.claude`. Switching between assistants is
a matter of which command you type.

## Profiles

| Profile | Config root | Launch | Purpose |
|---|---|---|---|
| `game-dev` | `~/.claude-gamedev` | `claude-gd` | 2D game development, Godot 4.x plus engine-agnostic design |
| `general` | `~/.claude-general` | `claude-gen` | Minimal clean-room profile |

## Install

```sh
./install.sh game-dev
```

This creates `~/.claude-gamedev`, links the profile's content into it, writes a
shim at `~/.local/bin/claude-gd`, and runs `doctor.sh` to show what was
installed. Add `~/.local/bin` to your `PATH` if it is not there already.

Then:

```sh
claude       # your existing setup, unchanged
claude-gd    # the game-development profile
```

Options: `--mode copy` for a frozen snapshot instead of symlinks, `--target DIR`
for a different config root, `--shim-dir DIR` for a different shim location, and
`--dry-run` to see every action without performing it.

Install paths must not contain spaces: the installer captures the paths it
creates through unquoted word splitting, so a target or shim directory with a
space in it is not supported.

## Check

```sh
./doctor.sh game-dev
```

Reports the resolved config root, content counts, enabled plugins, whether the
shim is on `PATH`, and whether anything leaks back into `~/.claude`.

## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely
```

## Memory

Memory written during a session lives in the profile's config root. Pull it back
into version control with:

```sh
./sync-memory.sh game-dev
```

## What is and is not isolated

Isolated per profile: `CLAUDE.md`, `settings.json`, agents, skills, commands,
hooks, plugins, sessions, history, and memory.

Not isolated, by design: a project's own `CLAUDE.md` and `.claude/` directory
load in every profile, because they describe the project rather than the
assistant. System- or enterprise-managed settings also still apply.

## Adding a profile

Create `profiles/<name>/` with `profile.json`, `CLAUDE.md`, and `settings.json`,
plus any `agents/`, `skills/`, `commands/`, `hooks/`, or `memory/` directories.
Content in `shared/` is merged into every profile, with profile entries winning
name collisions. Run `sh tests/run_all.sh` to check the profile contract.

## Tests

```sh
sh tests/run_all.sh
```

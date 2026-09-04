# omega-ai: Switchable AI Profiles — Design

Date: 2026-09-04
Status: Approved for planning

## Purpose

`omega-ai` is a version-controlled repository of Claude Code configuration —
agents, skills, slash commands, hooks, settings, and seed memory — packaged as
installable **profiles**. Each profile installs into its own Claude Code config
directory so that switching between a game-development AI and a general-purpose
AI is a matter of which command you type, with no cross-contamination in either
direction.

The first profile, `game-dev`, targets 2D game development with Godot 4.x plus
an engine-agnostic core (game design, 2D art pipeline, game feel). A second
minimal profile, `general`, exists so the multi-profile mechanism is exercised
and tested rather than theoretical.

## Success criteria

1. Installing any profile never reads from, writes to, or modifies `~/.claude`.
2. In a game-dev session, the user's existing global `CLAUDE.md`, GSD hooks,
   statusline, and caveman plugin are absent.
3. In a normal `claude` session, nothing from this repo is active.
4. Switching modes requires no re-installation and no shell restart — only a
   different command.
5. Uninstalling a profile leaves the machine in its pre-install state.
6. The installer is covered by an automated test that verifies the above on a
   temporary target directory.

## Isolation mechanism

Claude Code resolves its entire user-level configuration from a single root
directory, defaulting to `~/.claude` and overridable with the `CLAUDE_CONFIG_DIR`
environment variable. Every profile therefore gets its own root:

| Profile     | Config root           | Launch command |
|-------------|-----------------------|----------------|
| `game-dev`  | `~/.claude-gamedev`   | `claude-gd`    |
| `general`   | `~/.claude-general`   | `claude-gen`   |

Switching is performed by a thin shim script placed on the user's `PATH`, which
sets the variable and execs the real binary:

```sh
#!/usr/bin/env sh
CLAUDE_CONFIG_DIR="$HOME/.claude-gamedev" exec claude "$@"
```

A shim is used rather than a shell alias so that installation never edits
`.zshrc`, `.bashrc`, or any other user-owned file, and so the command works from
non-interactive shells, editors, and scripts.

### What is isolated

Relocating the config root isolates `CLAUDE.md`, `settings.json`, `agents/`,
`skills/`, `commands/`, `hooks/`, installed plugins, marketplaces, sessions,
history, and memory.

### What is deliberately not isolated

Project-scoped configuration — a game repository's own `CLAUDE.md` and
`.claude/` directory — loads in both modes. This is correct: that configuration
describes the project, not the assistant persona. Enterprise- or system-managed
settings, if present, also continue to apply. Both facts are documented in the
README so the boundary is never a surprise.

### Verification, not assumption

The exact set of files that follow `CLAUDE_CONFIG_DIR` is a property of the
installed Claude Code version, not of this repository. `doctor.sh` therefore
prints the resolved config root, the config files actually found under it, the
enabled plugins, and any path still pointing at `~/.claude`. Installation ends
by running it, so isolation is demonstrated on the user's machine rather than
asserted by this document.

## Repository structure

```
omega-ai/
├── install.sh                 # install.sh <profile> [--mode symlink|copy] [--target DIR] [--dry-run]
├── uninstall.sh               # uninstall.sh <profile> [--purge]
├── doctor.sh                  # doctor.sh [profile] — resolved paths, plugins, leakage check
├── sync-memory.sh             # sync-memory.sh <profile> — copy session-written memory back into repo
├── lib/
│   └── common.sh              # logging, safe link/copy, guards, profile resolution
├── shared/                    # merged into every profile at install time
│   ├── CLAUDE.part.md
│   ├── skills/
│   └── commands/
├── profiles/
│   ├── game-dev/
│   │   ├── profile.json
│   │   ├── CLAUDE.md
│   │   ├── settings.json
│   │   ├── agents/
│   │   ├── skills/
│   │   ├── commands/
│   │   ├── hooks/
│   │   └── memory/
│   └── general/
│       ├── profile.json
│       ├── CLAUDE.md
│       ├── settings.json
│       └── skills/
├── tests/
│   └── install_test.sh
├── docs/
│   └── superpowers/specs/
├── README.md
└── LICENSE
```

The existing empty `game_dev/` and `general/` directories are replaced by
`profiles/`.

### profile.json

Each profile declares its own install identity, so `install.sh` contains no
per-profile special cases:

```json
{
  "name": "game-dev",
  "description": "2D game development AI — Godot 4.x plus engine-agnostic core",
  "target": "~/.claude-gamedev",
  "shim": "claude-gd"
}
```

## Install behavior

`install.sh <profile>` runs the following steps in order:

1. **Resolve and guard.** Read `profiles/<profile>/profile.json`. Abort with a
   non-zero exit if the resolved target is `~/.claude`, is the user's home
   directory, or is inside this repository. This guard is the single most
   important safety property of the installer and is tested directly.
2. **Create the target root.** `mkdir -p` the config directory.
3. **Link content directories.** For `agents/`, `skills/`, `commands/`,
   `hooks/`, and `memory/`, link each entry from `shared/` first, then from
   `profiles/<profile>/`, with the profile's entry winning on a name collision.
   Linking is per-entry rather than per-directory so that shared and profile
   content can coexist in one target directory.
4. **Render `CLAUDE.md`.** Concatenate `shared/CLAUDE.part.md` and the profile's
   `CLAUDE.md` into the target as a generated file, with a header comment naming
   the source files and warning that edits will be overwritten.
5. **Copy `settings.json`.** Copy rather than link, because Claude Code writes to
   this file when plugins are toggled from inside a session; copying keeps the
   repository free of incidental churn. If the target already exists and differs,
   back it up to `settings.json.bak-<timestamp>` before overwriting.
6. **Install the shim.** Write the shim to `~/.local/bin/<shim>`, `chmod +x` it,
   and print a `PATH` hint if that directory is not already on `PATH`.
7. **Run `doctor.sh`** for the profile and print its report.

### Install modes

`--mode symlink` (default) makes the repository the source of truth: editing a
skill in the repository takes effect in the next session, and `git pull` updates
the assistant. `--mode copy` produces a frozen snapshot, for machines where the
repository is not checked out or should not be live.

`--target DIR` overrides the target from `profile.json`; it is what the test
suite uses. `--dry-run` prints every action without performing it.

### Uninstall

`uninstall.sh <profile>` removes the shim and every link or file the installer
created, leaving user-generated content — sessions, history, memory written
during use — in place. `--purge` removes the entire config root, and prompts for
confirmation unless `--yes` is passed.

## Profile content

### game-dev

- **`CLAUDE.md`** — 2D game development standards: composition over inheritance,
  decoupled systems via signals and an event bus, data-driven design with
  Resources, explicit state machines, profile before optimizing, and tests with
  GUT or gdUnit4. Where a request would lead to an anti-pattern, name it and
  propose the standard alternative.
- **`settings.json`** — model selection, `extraKnownMarketplaces` for
  `skillsmith`, and `enabledPlugins` for `godot-prompter@skillsmith` and
  `superpowers`. Third-party plugins are referenced, never vendored: Claude Code
  fetches them into the isolated plugins directory on first run. No GSD hooks and
  no statusline — those belong to the user's existing general setup.
- **Agents** — engine-agnostic roles that do not duplicate the eight agents
  godot-prompter already provides: `game-designer` (core loops and mechanics),
  `2d-art-pipeline` (sprite authoring, atlases, import settings), and
  `game-feel-tuner` (juice, timing, tuning passes).
- **Skills** — `game-design-doc`, `core-loop-design`, `2d-sprite-pipeline`, and
  `game-feel`.
- **`memory/`** — a seed `MEMORY.md` index plus versioned game-development
  conventions. A `sync-memory.sh` helper copies memory written during sessions
  back into the repository so durable decisions can be reviewed and committed.

### general

A minimal profile: `profile.json`, a short `CLAUDE.md`, a `settings.json` with no
plugins, and one placeholder skill. Its purpose is to prove and test the
multi-profile path; it is not intended to replace the user's existing `~/.claude`
setup.

## Testing

`tests/install_test.sh` is a plain shell test runner requiring no dependencies
beyond a POSIX shell. It covers:

1. Installing `game-dev` to a temporary target creates the expected links,
   rendered `CLAUDE.md`, copied `settings.json`, and shim.
2. Shared and profile content both appear in the target, with profile entries
   winning name collisions.
3. Installing with a target of `~/.claude` is refused with a non-zero exit and
   leaves the filesystem untouched.
4. `--dry-run` creates nothing.
5. `doctor.sh` reports the temporary root and finds no reference to `~/.claude`.
6. `uninstall.sh` removes everything the installer created; `--purge --yes`
   removes the root entirely.
7. Installing the `general` profile to a second temporary target does not
   disturb the first.

Tests are written before the scripts they cover.

## Out of scope

- Publishing this repository as a Claude Code plugin marketplace. The isolated
  profile is the chosen mechanism; a plugin layer can be added later if the need
  for cherry-picking skills into other setups appears.
- Unity or any non-Godot engine pack.
- Migrating the user's existing `~/.claude` setup into this repository.
- A full skill library. This design delivers the structure, the installer, and a
  working exemplar set; content grows in later work.

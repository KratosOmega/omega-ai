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

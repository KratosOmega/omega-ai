---
name: retro
description: Use when you want the lessons of recent work kept — on demand at any stage; harvests ledger rulings, reviews and bugs into studio memory.
---

# Retro

**Announce at start:** "Using game-dev:retro."

Learnings compound only if they are written where the next session reads
them. This stage writes them into the studio's own memory — isolated from
every other studio and from `~/.claude` by construction — and nowhere else.

## 0. Read

Retro is read-only on the repository: it asks at most one question (which
story, below), enters no checkout, writes no ledger line, makes no commit,
and changes no stage or pointer. It writes studio memory only. A pre-#42
worktree's one-time adopt may move a story into that worktree when retro
first reads it.

- `studio-state show`: `STATE.md` with its own ledger, then the current
  checkout's feature ledger.
- Find the recorded feature's ledger. The slug is the basename of
  `studio-state get spec`, without `.md` and without a leading
  `YYYY-MM-DD-`; the ledger is `.studio/ledger/<slug>.md`.
  - Run `studio-state worktree` from the main checkout. At exit 0 it prints
    a checkout path: read there with `(cd <path> && studio-state show)`;
    the session does not move.
  - At exit 3 the branch exists but no worktree has it: read
    `git show <branch>:.studio/ledger/<slug>.md`, with `<branch>` from
    `studio-state get branch`. Create and enter no worktree.
  - At exit 1 with candidates, ask the user once which story:
    the only question retro asks. For a `removed` candidate, read
    `git show <branch>:.studio/ledger/<slug>.md` with `<branch>` and
    `<spec>` from that candidate line; retro creates no worktree.
  - At exit 1 without candidates, use the current checkout's feature ledger
    from `studio-state show` when `<slug>.md` exists there; when it does
    not, read only `STATE.md`'s ledger and say so.
  - At exit 0 or 3, when that ledger does not exist, `spec` and `branch`
    name different features: read only `STATE.md`'s ledger, and say so.
- Take every `Ruling:`, `Review:` and `B<n>` line. Read the spec only to
  understand a line. Earlier features' ledgers are not read.
- A second retro reads the same lines; the existing-memory check in §3
  skips a lesson already written.

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

## 4. Hand-off

- Tell the user: "Memory written to `$CLAUDE_CONFIG_DIR/memory/`. To commit
  it into the repository, run `./sync-memory.sh game-dev` from the omega-ai
  checkout."
- Last line: `Next: run /clear, then` the router's next command for the current stage.

## Rules

- Write only into `$CLAUDE_CONFIG_DIR/memory/`. Never into the game
  project, never into `~/.claude`, never into the omega-ai checkout — the
  sync script is the one path from a session into version control.
- Fewer, sharper memories: zero to three. More than three means the filter in §2
  was skipped.

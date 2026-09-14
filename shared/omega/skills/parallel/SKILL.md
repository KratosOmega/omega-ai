---
name: parallel
description: Use when an approved plan has independent tasks and you want them implemented concurrently by subagents, with an optional cap on how many run at once — keeps the main session's context small.
---

# Parallel

**Announce at start:** "Using omega:parallel with max N" (or "unlimited").

Set the mode first, so the hook prints it on every following turn even when
this skill was invoked through the Skill tool rather than typed:

- `/omega:parallel 3` → `omega-mode set parallel max=3`
- `/omega:parallel` → `omega-mode set parallel`
- `/omega:parallel off` → `omega-mode clear parallel`

`omega-mode` is on `PATH` inside a studio; in plain `claude` the session's
first hook line names its absolute path.

## Precedence

This mode changes how work is scheduled, saved, merged or stopped. It never
removes a gate: approvals, reviewers, tests, `Verify:` rules and the invoking
skill's state writes happen exactly as that skill says. It never replaces the
invoking skill; that skill keeps running and this mode shapes one of its
steps. When this mode and the invoking skill disagree about scheduling, merge
mechanics or when to stop, this mode wins; when they disagree about a gate,
the invoking skill wins.

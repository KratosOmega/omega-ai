---
name: delegate
description: Use when the main session must stay a command deck — it talks to the user, dispatches subagents, reads their reports and runs status commands, and every edit, search and document goes to a subagent, never done by hand.
---

# Delegate

**Announce at start:** "Using omega:delegate."

Run first: `omega-mode set delegate` — `omega-mode clear delegate` for
`off`. `omega-mode` is on `PATH` inside a studio; the session-start line
names its path otherwise. The hook already set the mode when the command
was typed; running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

Stub. The rulebook lands with Task 4 of
`docs/omega/plans/2026-09-15-plan-3-delegate.md`.

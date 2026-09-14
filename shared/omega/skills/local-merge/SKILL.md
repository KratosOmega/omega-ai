---
name: local-merge
description: Use when GitHub Actions is unavailable or rate-limited — skips the remote checks, runs the project's local CI, and merges through gh pr merge --admin when it is green.
---

# Local merge

**Announce at start:** "Using omega:local-merge."

Set the mode first, so the hook prints it on every following turn even when
this skill was invoked through the Skill tool rather than typed:

- `/omega:local-merge` → `omega-mode set local-merge`
- `/omega:local-merge off` → `omega-mode clear local-merge`

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

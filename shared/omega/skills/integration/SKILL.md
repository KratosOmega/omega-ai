---
name: integration
description: Use when several related stories must land together — creates an integration branch every story merges into, tracks the set, and lands the whole set on main through the local-merge rules.
---

# Integration

**Announce at start:** "Using omega:integration <verb>."

The mode records which integration branch the other modes target:

- `/omega:integration start <slug>` → `omega-mode set integration slug=<slug>`
  (the hook does this when the command is typed; run it yourself when the
  skill was invoked through the Skill tool)
- `/omega:integration finish` → `omega-mode clear integration`, only after the
  integration branch has landed; a refused finish leaves the mode set.

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

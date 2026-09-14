---
name: autopilot
description: Use when a long run must proceed with nobody at the keyboard — asks every open decision up front, commits the spec and plan, then executes without questions, logging each ruling, pushing after every task, and ending with a handoff.
---

# Autopilot

**Announce at start:** "Using omega:autopilot — pre-flight first."

The mode is set at the end of pre-flight, never before, so an unfinished
question sweep is never mistaken for an unattended run:

- pre-flight complete → `omega-mode set autopilot`
- `/omega:autopilot off` → `omega-mode clear autopilot`

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

---
name: handoff
description: Use when a session must stop or pause mid-work (context limit, compaction, /clear) — finds a safe stopping point, commits and pushes everything, and prints the prompt that resumes the work in a new session.
---

# Handoff

**Announce at start:** "Using omega:handoff to save this session's work."

Read the active modes first — `omega-mode show` — so the resume prompt can
re-create them. `handoff` sets no mode of its own; it reads them all.

## Precedence

This mode changes how work is scheduled, saved, merged or stopped. It never
removes a gate: approvals, reviewers, tests, `Verify:` rules and the invoking
skill's state writes happen exactly as that skill says. It never replaces the
invoking skill; that skill keeps running and this mode shapes one of its
steps. When this mode and the invoking skill disagree about scheduling, merge
mechanics or when to stop, this mode wins; when they disagree about a gate,
the invoking skill wins.

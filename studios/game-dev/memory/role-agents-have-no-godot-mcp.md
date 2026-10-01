---
name: role-agents-have-no-godot-mcp
description: Role/subagents have no Godot MCP at all, and the studio shim's Godot MCP has no screenshot, input or run_script tools — plan a playtest's visual half for a human
metadata:
  type: feedback
---

Role agents dispatched by `/game-dev:execute` carry no MCP tools, and the Godot MCP the `claude-gd` shim exposes to
the main session has only `run_project` / `get_debug_output` / `stop_project` (plus scene/uid editing) — no
`take_screenshot`, `simulate_input` or `run_script`. Pixel evidence therefore needs a human at the keyboard.

**Why:** Knight Stomp (KAN-1295, 2026-09-18): the plan's Task 8 named `run_project` → `take_screenshot`; the
implementer had no MCP, so the headless boot ran through `studio-run --seconds 8` (import + main-scene boot + log
scan) and the visual playtest P1–P7 was deferred to the human (Decision D12). The next session's MCP lacked the same
tools, so the deferral stood.
**How to apply:** in `/game-dev:plan`, tag `verify: visual` items as human-run from the start and put the headless
half on `studio-run --seconds N` + crash-grep; do not write `take_screenshot`/`run_script` steps into a task a role
agent will execute. Check the session's MCP tool roster before promising pixel evidence. Related: [[phoenix-gate-pin-sweep-before-merge]].

**They carry no Skill tool either (KAN-1296, 2026-09-19).** A dispatched role agent reported that no
`godot-prompter:*` skill was reachable — no Skill tool in its harness and nothing on disk beyond the synced
document skills — although the project `CLAUDE.md` binds subagents to invoke the matching skill before writing
Godot code. So that mandate is currently **unenforceable for subagents**: they fall back to the file's own
conventions and the CLAUDE.md architecture rules. Do not treat "the agent invoked the skill" as something a
dispatch can require; put the pattern the skill would have supplied into the brief itself when it is
load-bearing, and judge the result at review rather than assuming the skill shaped it.

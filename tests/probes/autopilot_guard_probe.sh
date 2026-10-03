#!/bin/sh
# autopilot_guard_probe.sh — does a headless `claude -p` session under
# OMEGA_AUTOPILOT=1 run this checkout's hooks/autopilot-guard.sh, deny a
# background Agent dispatch, and let a foreground one through?
#
# Not part of tests/run_all.sh: it spends real model calls. One session runs
# with the game-dev config root (as claude-gd) and THIS checkout's studio and
# omega plugins (so a worktree probes its own hook, not the installed one).
# It is asked to make two Agent calls, one after the other:
#   1. no run_in_background (the build's async default) — must be denied with
#      the guard's reason ("game-dev autopilot");
#   2. run_in_background: false — must run, and its subagent replies
#      PROBE_FG_OK.
# PASS needs both.
#
# Usage: autopilot_guard_probe.sh [MODEL]   (default sonnet)
# Exit 0 PASS · 1 FAIL · 2 usage. Logs: $PROBE_DIR (default a mktemp dir).
set -u
M="${1:-sonnet}"
R="$(cd "$(dirname "$0")/../.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "probe: claude not on PATH" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/autopilot-guard-probe.XXXXXX")}"
P="Make exactly two Agent tool calls, one at a time, then stop.
Call 1: Agent with description \"probe bg\", subagent_type \"general-purpose\", prompt \"Reply with exactly: PROBE_BG_OK\". Do NOT pass run_in_background at all.
Call 2 (whatever call 1 returned): Agent with description \"probe fg\", subagent_type \"general-purpose\", prompt \"Reply with exactly: PROBE_FG_OK\", and run_in_background set to false.
Do not retry either call or make any other tool call. Then reply with one line: DONE."

( cd "$D" && env OMEGA_AUTOPILOT=1 CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR_PROBE:-$HOME/.claude-gamedev}" \
    claude --plugin-dir "$R/studios/game-dev" --plugin-dir "$R/shared/omega" \
    -p "$P" --model "$M" --output-format stream-json --verbose \
    --permission-mode auto --permission-prompts none --max-budget-usd 1 ) \
  > "$D/session.jsonl" 2> "$D/session.err" < /dev/null

# result_of DESCRIPTION — the main session's tool_result text for its Agent
# call with that description (paired by tool_use_id), or nothing.
result_of() {
  python3 - "$D/session.jsonl" "$1" <<'PY'
import json, sys
ids, out = {}, {}
for line in open(sys.argv[1]):
    try: d = json.loads(line)
    except ValueError: continue
    if d.get("parent_tool_use_id"): continue
    for c in (d.get("message") or {}).get("content") or []:
        if not isinstance(c, dict): continue
        if c.get("type") == "tool_use" and c.get("name") in ("Agent", "Task"):
            ids[c["id"]] = (c.get("input") or {}).get("description")
        elif c.get("type") == "tool_result" and c.get("tool_use_id") in ids:
            out[ids[c["tool_use_id"]]] = json.dumps(c.get("content"))
print(out.get(sys.argv[2], ""))
PY
}
ok=1
bg="$(result_of "probe bg")"; fg="$(result_of "probe fg")"
case "$bg" in
  *'game-dev autopilot'*) echo "background Agent: denied by autopilot-guard.sh" ;;
  *) echo "background Agent: NOT denied — result: ${bg:-none}"; ok=0 ;;
esac
case "$fg" in
  ''|*'game-dev autopilot'*|*'Async agent launched'*) echo "foreground Agent: did not run in the foreground — result: ${fg:-none}"; ok=0 ;;
  *) echo "foreground Agent: ran in the foreground" ;;
esac
echo "logs: $D"
[ "$ok" = 1 ] && { echo PASS; exit 0; }
echo FAIL; exit 1

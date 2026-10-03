#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Agent|Task|Bash|Monitor).
# Under OMEGA_AUTOPILOT=1 — a headless `claude-gd -p` unit the overnight
# runner launched — nothing may run in the background. A -p session ends
# when its turn ends; print mode then waits 600 s for background tasks and
# kills them. A main session that dispatched its implementer in the
# background and ended the turn to wait for the report lost the subagent and
# the gate it was running, and the unit ended with no progress (phoenix
# mob-composer-parity, units 4-S3-T3 and 6-S3-T4, 2026-10-03). So, only
# while OMEGA_AUTOPILOT is exactly 1, this denies:
#   - an Agent call whose run_in_background is not the literal false — the
#     async default counts as background; under the older name Task (a
#     foreground default), only run_in_background true;
#   - a Bash call with run_in_background true;
#   - any Monitor call (its events arrive only after the turn ends).
# A deny hands the reason back to the model, which re-issues the call.
#
# The field is read from the flattened JSON as `"run_in_background": <bool>`.
# A mention inside a string value (a prompt or command quoting the rule) is
# JSON-escaped as \"run_in_background\", so the bare-quote pattern never
# matches it.
#
# Exit 0 on every path and print nothing to allow: a hook that failed here
# would block a call for a reason nobody asked for. Self-contained on
# purpose: a copy-mode install has no lib/.
trap 'exit 0' EXIT

[ "${OMEGA_AUTOPILOT:-}" = 1 ] || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0
flat="$(printf '%s' "${input:-}" | tr '\n\t' '  ')"

tool="$(printf '%s' "${flat:-}" \
  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

# bg — the run_in_background value: true, false, or empty when absent.
bg=""
printf '%s' "${flat:-}" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*true' && bg=true
printf '%s' "${flat:-}" | grep -q '"run_in_background"[[:space:]]*:[[:space:]]*false' && bg=false

# deny REASON — one PreToolUse deny decision. REASON is fixed text from this
# file: no JSON escaping needed.
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

case "${tool:-}" in
  Agent|Task)
    [ "${bg:-}" = false ] && exit 0
    # Task is the older name, whose dispatch ran in the foreground unless
    # asked otherwise: deny it only when it asks for the background.
    [ "${tool:-}" = Task ] && [ "${bg:-}" != true ] && exit 0
    deny "game-dev autopilot: this headless -p unit ends when its turn ends, and a background subagent is killed with it. Re-dispatch with run_in_background: false and wait for the report in this turn (several foreground dispatches in one message still run in parallel)." ;;
  Bash)
    [ "${bg:-}" = true ] || exit 0
    deny "game-dev autopilot: this headless -p unit ends when its turn ends, and a background command is killed with it. Run it in the foreground (no run_in_background, no &) with timeout set to \$BASH_MAX_TIMEOUT_MS." ;;
  Monitor)
    deny "game-dev autopilot: this headless -p unit ends when its turn ends, so a Monitor event never arrives. Run the command in the foreground with Bash and read its output." ;;
esac
exit 0

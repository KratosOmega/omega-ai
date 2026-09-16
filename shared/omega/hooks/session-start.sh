#!/bin/sh
# SessionStart hook for the omega global plugin (startup, resume, clear,
# compact). Prints one line naming the six skills and the absolute paths
# of omega-mode and omega-caffeine — plain claude has no PATH entry for
# them — and, when the session has modes set, the "Omega modes:" block from
# omega-mode brief. Also prunes mode files older than seven days, never the
# current session's — a resumed or compacted session older than seven days
# must still find its modes — as a crashed session never ran SessionEnd.
#
# Exit 0 always: on SessionStart a non-zero exit would drop the context.
# Self-contained on purpose: in copy mode the plugin root has no lib/.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="$ROOT/bin/omega-mode"
CAFFEINE="$ROOT/bin/omega-caffeine"
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/omega/modes"

# The session id comes from the hook's JSON; the environment is the fallback.
# The prompt-free SessionStart JSON has one "session_id" key, and a key
# inside a JSON string would be escaped as \"session_id\", which the pattern
# (a bare quote after the name) does not match.
input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | tr '\n' ' ' \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"

if [ -d "$DIR" ]; then
  if [ -n "$sid" ]; then
    find "$DIR" -type f ! -name "$sid" -mtime +7 -exec rm -f {} + 2>/dev/null || true
  else
    find "$DIR" -type f -mtime +7 -exec rm -f {} + 2>/dev/null || true
  fi
fi

text="Omega global skills: /omega:handoff, /omega:parallel [N|off], /omega:local-merge [off], /omega:integration <start|add|status|finish>, /omega:autopilot [off], /omega:delegate [off], /omega:reply [off]. Mode tool: $MODE (set | clear | show | path | brief). Keep-awake: $CAFFEINE (start | stop | status)."
if [ -n "$sid" ]; then
  block="$(sh "$MODE" --session "$sid" brief 2>/dev/null || true)"
  if [ -n "$block" ]; then
    text="$text
$block"
  fi
fi

# Escape for a JSON string exactly as the game-dev session hook does:
# backslash, quote, tab; newlines joined; carriage returns and other control
# characters dropped.
TAB="$(printf '\t')"
escaped="$(printf '%s\n' "$text" \
  | tr -d '\r' \
  | tr -d '\000-\010\013\014\016-\037' \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
  | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
exit 0

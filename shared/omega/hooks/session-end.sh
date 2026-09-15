#!/bin/sh
# SessionEnd hook for the omega global plugin: the ending session's
# keep-awake process (omega-caffeine) is stopped and its mode file is
# deleted. Modes are per session and a handoff carries them forward
# explicitly, so nothing outlives the session on purpose.
#
# Exit 0 always. Self-contained on purpose: in copy mode the plugin root has
# no lib/.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="$ROOT/bin/omega-mode"
CAFFEINE="$ROOT/bin/omega-caffeine"

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | tr '\n' ' ' \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$sid" ] || exit 0

# stop first: the pid it kills is recorded on the autopilot line that
# clear --all removes.
sh "$CAFFEINE" --session "$sid" stop >/dev/null 2>&1 || true
sh "$MODE" --session "$sid" clear --all >/dev/null 2>&1 || true
exit 0

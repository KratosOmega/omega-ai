#!/bin/sh
# SessionEnd hook for the omega global plugin: the ending session's mode
# file is deleted. Modes are per session and a handoff carries them forward
# explicitly, so nothing outlives the session on purpose.
#
# Exit 0 always. Self-contained on purpose: in copy mode the plugin root has
# no lib/.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="$ROOT/bin/omega-mode"

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | tr '\n' ' ' \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$sid" ] || exit 0

sh "$MODE" --session "$sid" clear --all >/dev/null 2>&1 || true
exit 0

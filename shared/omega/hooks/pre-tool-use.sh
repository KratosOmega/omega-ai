#!/bin/sh
# PreToolUse hook for the omega global plugin (matcher Edit|Write|NotebookEdit).
# While the session's mode file lists `delegate`, an edit under the
# repository from the main session is denied: the main session is a command
# deck and dispatches a subagent instead. A subagent's call carries a
# non-empty `agent_id` (observed on Claude Code 2.1.272: the subagent's
# PreToolUse record and the main session's carry the identical
# transcript_path — no `/subagents/` segment — while agent_id is present
# only on the subagent's record). The transcript-path form
# (`<session dir>/subagents/…`) is kept as a second signal, so a future
# build that moves to per-agent transcripts still never blocks a subagent.
# A path outside the repository, a session with no such mode, and anything
# the hook cannot parse are allowed by printing nothing. The mode file is
# checked first so a session without the mode pays one omega-mode call and
# no git call.
#
# Exit 0 always: a hook that failed here would block the edit for a reason
# nobody asked for. Self-contained on purpose: in copy mode the plugin root
# has no lib/.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="$ROOT/bin/omega-mode"

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
flat="$(printf '%s' "$input" | tr '\n' ' ')"

# field KEY — the string value of "KEY": "…" in the flattened JSON; empty
# when absent. The keys read here never carry an escaped quote, and an
# escaped \"KEY\" inside a string value does not match (no bare quote
# before the colon), as session-start.sh relies on for session_id — the
# same reasoning covers agent_id here.
field() {
  printf '%s' "$flat" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

case "$(field tool_name)" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

sid="$(field session_id)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$sid" ] || exit 0

sh "$MODE" --session "$sid" show 2>/dev/null \
  | awk '$1 == "delegate" { found = 1 } END { exit !found }' || exit 0

[ -z "$(field agent_id)" ] || exit 0
case "$(field transcript_path)" in
  */subagents/*) exit 0 ;;
esac

cwd="$(field cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0

target="$(field file_path)"
[ -n "$target" ] || target="$(field notebook_path)"
[ -n "$target" ] || exit 0
case "$target" in
  /*) ;;
  *) target="$cwd/$target" ;;
esac
# Resolve the deepest existing directory of the target, so a new file in a
# new directory under the repository still compares against the real root
# (git prints a resolved path; the tool may pass one through a symlink).
dir="$(dirname "$target")"
rel="$(basename "$target")"
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
  rel="$(basename "$dir")/$rel"
  dir="$(dirname "$dir")"
done
if [ -d "$dir" ]; then
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || exit 0
fi
target="$dir/$rel"

case "$target" in
  "$root"|"$root"/*)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"omega:delegate — the main session edits nothing under the repository; dispatch a subagent"}}\n' ;;
esac
exit 0

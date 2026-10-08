#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher EnterWorktree), #59 R5.
# In a story session (STUDIO_STORY set: an overnight lane unit) the story's
# worktree already exists or has a known path, so EnterWorktree must name it
# with `path:`. A bare call (or `name:` alone) creates a stray worktree:
# phoenix S1 T7's retry (2026-10-07) made one, could not remove it, and ended
# with no progress. Outside story sessions every call is allowed: a
# single-plan unit's isolation step creates its worktree with a name or none.
# The reason names the story worktree: `studio-state worktree` (exit 0), else
# the path it suggests (exit 3), else execute §0's rule
# <root>/.claude/worktrees/<branch with / -> ->.
# Exit 0 on every path and print nothing to allow. Self-contained (no jq).
trap 'exit 0' EXIT

[ -n "${STUDIO_STORY:-}" ] || exit 0
input="$(cat 2>/dev/null || true)"
flat="$(printf '%s' "${input:-}" | tr '\n\t' '  ')"
# A non-empty "path" (a key named exactly path; "transcript_path" does not match).
printf '%s' "${flat:-}" | grep -q '"path"[[:space:]]*:[[:space:]]*"[^"]' && exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
ST="$HERE/../bin/studio-state"
P="$(sh "$ST" worktree 2>/dev/null)" || P=""
if [ -z "$P" ]; then
  P="$(sh "$ST" worktree 2>&1 >/dev/null | sed -n "s/.*git worktree add '\([^']*\)'.*/\1/p" | head -n 1)"
fi
if [ -z "$P" ]; then
  _r="$(sh "$ST" root 2>/dev/null)"; _b="$(sh "$ST" get branch 2>/dev/null)"
  case "$_b" in ''|-) ;; *) [ -z "$_r" ] || P="$_r/.claude/worktrees/$(printf '%s' "$_b" | tr '/' '-')" ;; esac
fi
[ -n "$P" ] || P="<the story worktree: run studio-state worktree>"
P="$(printf '%s' "$P" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
  "game-dev: in a story session EnterWorktree needs path: — a bare call creates a stray worktree. Use path: $P."
exit 0

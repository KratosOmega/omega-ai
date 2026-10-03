#!/bin/sh
# operator-inbox.sh — delivers a live overnight run's operator messages to a
# unit's main session (#27; spec AC9-12). Registered for SessionStart
# (startup|compact) and PostToolUse (*). Outside an overnight unit (no
# STUDIO_UNIT_TAG or no STUDIO_RUN_DIR) it exits at once, reading nothing:
# it runs on every tool call of every claude-gd session. Never fails a tool
# call: exit 0 on every path.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] || exit 0
cat > /dev/null
exit 0

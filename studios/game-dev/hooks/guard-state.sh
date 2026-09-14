#!/bin/sh
# PreToolUse hook (Edit|Write|MultiEdit): .studio/STATE.md and the feature
# ledgers are written only through studio-state. Exit 2 blocks the call and
# hands stderr back as the reason; exit 0 lets everything else through.
#
# Self-contained on purpose: in copy mode the plugin root has no lib/.
set -u

input="$(cat)"
path="$(printf '%s' "$input" \
  | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

case "$path" in
  */.studio/STATE.md|.studio/STATE.md|*/.studio/ledger/*.md|.studio/ledger/*.md)
    printf 'use studio-state to change studio state (%s is written only through it)\n' "$path" >&2
    exit 2 ;;
esac
exit 0

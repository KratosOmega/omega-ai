#!/bin/sh
# UserPromptSubmit hook for the omega global plugin. A typed /omega:<skill>
# command reaches the hook as an envelope, not the literal text:
#
#   <command-message>parallel</command-message>
#   <command-name>/omega:parallel</command-name>
#   <command-args>3</command-args>
#
# The hook turns the mode commands into omega-mode calls, so a typed command
# changes the mode before the model reads the skill, and then — only when a
# mode is active — prints the "Omega modes:" block as the turn's additional
# context. Any other prompt changes nothing; a <scheduled-task> prompt never
# changes a mode but still sees the block; with no mode it prints nothing.
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

# One line, with the JSON escapes for newline and tab turned into spaces, so
# the envelope tags match whether Claude Code joined them with newlines or
# not.
flat="$(printf '%s' "$input" | tr '\n\t' '  ' | sed -e 's/\\n/ /g' -e 's/\\t/ /g')"

# The prompt's own value, not the whole flattened JSON — a prompt that merely
# *mentions* an envelope tag (a developer pasting a line of
# tests/omega_test.sh) must not be read as one. The envelope itself never
# contains a quote, so stopping at the next '"' is correct for the envelope
# case; a pasted prompt that stops early there simply does not begin with
# the tag checked below.
prompt_val="$(printf '%s' "$flat" \
  | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
prompt_val="$(printf '%s' "$prompt_val" | sed -e 's/^[[:space:]]*//')"
# A typed command's envelope may be preceded by its <command-message>; skip
# it and any whitespace after it so the check below sees <command-name>
# first when the envelope is really there.
envelope="$(printf '%s' "$prompt_val" \
  | sed -e 's/^<command-message>[^<]*<\/command-message>[[:space:]]*//')"

# Unattended scheduled-task runs never change a mode. This only turns off
# the envelope handling below; the Omega modes: block is still printed when
# a mode is set.
case "$flat" in
  *'<scheduled-task'*) envelope="" ;;
esac

skill=""
case "$envelope" in
  '<command-name>'*)
    skill="$(printf '%s' "$envelope" \
      | sed -n 's/.*<command-name>[[:space:]]*\/omega:\([a-z-]*\)[[:space:]]*<\/command-name>.*/\1/p' | head -n 1)" ;;
esac
if [ -n "$skill" ]; then
  args="$(printf '%s' "$envelope" | sed -n 's/.*<command-args>\(.*\)<\/command-args>.*/\1/p' | head -n 1)"
  args="$(printf '%s' "$args" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$skill" in
    parallel)
      case "$args" in
        off) sh "$MODE" --session "$sid" clear parallel >/dev/null ;;
        '') sh "$MODE" --session "$sid" set parallel >/dev/null ;;
        *[!0-9]*|0*) ;;
        *) sh "$MODE" --session "$sid" set parallel "max=$args" >/dev/null ;;
      esac ;;
    local-merge|autopilot)
      case "$args" in
        off) sh "$MODE" --session "$sid" clear "$skill" >/dev/null ;;
        '') sh "$MODE" --session "$sid" set "$skill" >/dev/null ;;
      esac ;;
    integration)
      # Only `start <slug>` sets the mode here. `finish` clears it from inside
      # the skill after the branch has landed: it refuses while a story is
      # unmerged, and the mode must survive that refusal.
      case "$args" in
        start\ *)
          slug="$(printf '%s' "${args#start}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]].*$//')"
          case "$slug" in
            ''|.|..|*[!A-Za-z0-9._-]*) ;;
            *) sh "$MODE" --session "$sid" set integration "slug=$slug" >/dev/null ;;
          esac ;;
      esac ;;
  esac
fi

block="$(sh "$MODE" --session "$sid" brief 2>/dev/null || true)"
[ -n "$block" ] || exit 0

TAB="$(printf '\t')"
escaped="$(printf '%s\n' "$block" \
  | tr -d '\r' \
  | tr -d '\000-\010\013\014\016-\037' \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
  | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$escaped"
exit 0

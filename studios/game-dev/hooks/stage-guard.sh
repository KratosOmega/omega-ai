#!/bin/sh
# UserPromptSubmit hook for the game-dev studio. Warns — never blocks — when
# a stage command (/game-dev:brainstorm, plan or execute) is typed into a
# session that already ran a different stage: that stage's context would be
# carried into this one.
#
# Exit 0 on every path: exit 2 from a UserPromptSubmit hook blocks the prompt
# and erases it. So there is no `set -u` (an unbound variable aborts the
# shell with status 2; every expansion is written ${x:-}), and the trap below
# turns any other exit into 0. Plain stdout is added to Claude's context:
# every silent path prints nothing, and the warning path prints exactly one
# JSON object. Self-contained: a copy-mode install has no lib/.
trap 'exit 0' EXIT

# 1. The hook input.
input="$(cat 2>/dev/null || true)"

# 2. One line, the JSON escapes for newline and tab turned into spaces
#    (as shared/omega/hooks/prompt-submit.sh flattens its input).
flat="$(printf '%s' "${input:-}" | tr '\n\t' '  ' | sed -e 's/\\n/ /g' -e 's/\\t/ /g')"

# 3. The prompt's own value, up to the next '"', leading whitespace removed.
prompt_val="$(printf '%s' "${flat:-}" \
  | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
prompt_val="$(printf '%s' "${prompt_val:-}" | sed -e 's/^[[:space:]]*//')"

# 4. Unattended scheduled-task runs are never warned.
case "${flat:-}" in
  *'<scheduled-task'*) exit 0 ;;
esac

# 5. The typed stage. Raw: the text as typed (the shape Claude Code 2.1.286
#    sends). Envelope: <command-name>, after one optional <command-message>
#    (the shape some versions send).
typed="$(printf '%s\n' "${prompt_val:-}" \
  | sed -n -E 's#^/game-dev:(brainstorm|plan|execute)([[:space:]].*)?$#\1#p' | head -n 1)"
if [ -z "${typed:-}" ]; then
  envelope="$(printf '%s' "${prompt_val:-}" \
    | sed -e 's/^<command-message>[^<]*<\/command-message>[[:space:]]*//')"
  case "${envelope:-}" in
    '<command-name>'*)
      typed="$(printf '%s\n' "${envelope:-}" \
        | sed -n -E 's#^<command-name>[[:space:]]*/game-dev:(brainstorm|plan|execute)[[:space:]]*</command-name>.*#\1#p' \
        | head -n 1)" ;;
  esac
fi
[ -n "${typed:-}" ] || exit 0

# 6. The session's transcript.
transcript="$(printf '%s' "${flat:-}" \
  | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "${transcript:-}" ] && [ -f "${transcript:-}" ] && [ -r "${transcript:-}" ] || exit 0

# 7-8. Stages this session already ran, oldest first — a typed command's
#      envelope or a Skill tool call, each anchored at the start of a JSON
#      string so a prose mention never counts — minus the typed one; the
#      last is the most recent different stage.
prior="$(grep -oE '"<command-message>game-dev:(brainstorm|plan|execute)</command-message>|"<command-name>/game-dev:(brainstorm|plan|execute)</command-name>|"name":[[:space:]]*"Skill",[[:space:]]*"input":[[:space:]]*\{[[:space:]]*"skill":[[:space:]]*"game-dev:(brainstorm|plan|execute)"' \
    "${transcript:-}" 2>/dev/null \
  | sed -E 's/.*game-dev:(brainstorm|plan|execute).*/\1/' \
  | grep -vx -- "${typed:-}" | tail -n 1)"
[ -n "${prior:-}" ] || exit 0

# 9. Both names come from a fixed set: no JSON escaping needed.
printf '{"systemMessage":"game-dev: this session already ran /game-dev:%s — its context is carried into %s. Run /clear, then /game-dev:%s."}\n' \
  "${prior:-}" "${typed:-}" "${typed:-}"
exit 0

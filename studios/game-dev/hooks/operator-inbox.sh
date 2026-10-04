#!/bin/sh
# operator-inbox.sh — delivers a live overnight run's operator messages to a
# unit's main session (#27; spec AC9-12). Registered for SessionStart
# (startup|compact) and PostToolUse (*). Outside an overnight unit (no
# STUDIO_UNIT_TAG or no STUDIO_RUN_DIR) it exits at once, reading nothing:
# it runs on every tool call of every claude-gd session. Never fails a tool
# call: exit 0 on every path, errors to <run dir>/hook.log (AC29).
#
# startup, PostToolUse (main session only: no agent_id): claim each pending
# message of the unit's story, lowest id first, by mv into
# inbox/<story>/delivered/<unit tag>/ (a message another hook claimed first
# is skipped), and print one delivery block — plain text at SessionStart,
# hookSpecificOutput.additionalContext JSON at PostToolUse.
# compact: re-show what this unit tag already claimed, claiming nothing.
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] || exit 0
RD="$STUDIO_RUN_DIR"; TAG="$STUDIO_UNIT_TAG"
LC_ALL=C; export LC_ALL
[ -d "$RD" ] || exit 0
# A manifest run's unit with no story (the final step) gets nothing (AC9).
if [ -f "$RD/rows.tsv" ]; then S="${STUDIO_STORY:-}"; [ -n "$S" ] || exit 0; else S=-; fi
exec 2>> "$RD/hook.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
EV="$HERE/../bin/studio-event"
IN="$(cat)"

# field KEY — a top-level string field of the hook input (R19: no jq).
field() { printf '%s' "$IN" | tr -d '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }
# msg_get and msg_body are the same as in overnight-channel.sh, and sq the
# same as in studio-overnight (kept identical; byte-wise, so invalid UTF-8 in
# a message body is carried whole).
msg_get() { LC_ALL=C sed -n "1,/^--\$/s/^$1: //p" "$2" 2>/dev/null | head -n 1; }
msg_body() { LC_ALL=C sed '1,/^--$/d' "$1" 2>/dev/null | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed 's/ *$//'; }
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# top_agent_id — true when the hook input has a top-level agent_id (a
# subagent's call). A cheap grep first; only a match pays for the depth scan
# that ignores an agent_id key nested in tool_input or tool_response.
top_agent_id() {
  printf '%s' "$IN" | grep -q '"agent_id"' || return 1
  printf '%s' "$IN" | tr -d '\n' | awk '{
    n = length($0); d = 0; ins = 0; cur = ""; last = ""; lastd = -1
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (ins) {
        if (c == "\\") i++
        else if (c == "\"") { ins = 0; last = cur; lastd = d }
        else cur = cur c
      } else if (c == "\"") { ins = 1; cur = "" }
      else if (c == "{" || c == "[") d++
      else if (c == "}" || c == "]") d--
      else if (c == ":" && d == 1 && lastd == 1 && last == "agent_id") exit 0
    }
    exit 1 }'
}
# list DIR — DIR's message file names, lowest id first.
list() {
  for _f in "$1"/[0-9]*.msg; do [ -f "$_f" ] && printf '%s\n' "${_f##*/}"; done \
    | grep -E '^[0-9]+\.msg$' | sort -n
}

EVN="$(field hook_event_name)"
case "$EVN" in
  SessionStart)
    case "$(field source)" in
      startup) MODE=claim; VIA=session_start ;;
      compact) MODE=reshow ;;
      *) exit 0 ;;
    esac ;;
  PostToolUse)
    top_agent_id && exit 0
    MODE=claim; VIA=tool_call ;;
  *) exit 0 ;;
esac
IB="$RD/inbox/$S"; DL="$IB/delivered/$TAG"
[ -d "$IB" ] || exit 0

SHOW=""
if [ "$MODE" = claim ]; then
  HEAD="OPERATOR MESSAGES — from the user, for story $S (overnight run)."
  for m in $(list "$IB"); do
    case "$(msg_get scope "$IB/$m")" in
      story|unit|retire) ;;
      *) [ -f "$IB/$m" ] || continue   # another hook claimed it first: not malformed
         # a malformed message is logged once, not on every tool call
         grep -qF "operator-inbox: $IB/$m has no scope header" "$RD/hook.log" 2>/dev/null \
           || echo "operator-inbox: $IB/$m has no scope header; left pending" >&2
         continue ;;
    esac
    mkdir -p "$DL" || break
    mv "$IB/$m" "$DL/$m" 2>/dev/null || continue   # another hook claimed it first
    SHOW="$SHOW $m"
    sh "$EV" "$RD" message_delivered "story=$S" "id:=${m%.msg}" "scope=$(msg_get scope "$DL/$m")" "unit=$TAG" "via=$VIA" || true
  done
else
  HEAD="OPERATOR MESSAGES — reminder: already delivered in this unit, from the user, for story $S (overnight run)."
  SHOW="$(list "$DL")"
fi
[ -n "$(printf '%s' "$SHOW" | tr -d ' \n')" ] || exit 0

block() {
  printf '%s\n' "$HEAD"
  for m in $SHOW; do
    f="$DL/$m"; id="${m%.msg}"
    case "$(msg_get scope "$f")" in
      story)
        printf '[%s, story] %s\n' "$id" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this for the rest of the story. Record it in the feature checkout's" \
          "    ledger at your recording point — after §0 step (c), not merely after" \
          "    EnterWorktree; in a --land or --gate-repair unit, after entering the" \
          "    feature checkout — single-quoted, and commit it with your next ledger" \
          "    commit (push only what you would push anyway):"
        printf '    studio-state ledger %s\n' "$(sq "Directive $id: $(msg_body "$f")")" ;;
      unit)
        printf '[%s, unit] %s\n' "$id" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this in this unit only. Do not record it." ;;
      retire)
        tg="$(msg_get target "$f")"
        printf '[retire %s]\n' "$tg"
        printf '%s\n' "  → Stop following directive $tg. Record, the same way:"
        printf '    studio-state ledger %s\n' "$(sq "Directive $tg retired")" ;;
    esac
  done
  printf '%s\n' "If a message conflicts with the approved plan or spec, follow it for how you" \
    'work; for what you build, record a `Stop:` with the conflict instead.'
}

OUT="$(block)"
if [ "$EVN" = SessionStart ]; then
  printf '%s\n' "$OUT"
else
  # session-start.sh's escape pipeline (trial t5): \r and control bytes
  # dropped, \ " and tab escaped, lines joined with \n.
  TAB="$(printf '\t')"
  ESC="$(printf '%s\n' "$OUT" | tr -d '\r' | tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
    | awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }')"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$ESC"
fi
exit 0

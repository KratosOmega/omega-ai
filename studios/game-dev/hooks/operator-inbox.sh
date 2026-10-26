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
#
# Deadline notices (every session of the unit, subagents too, with or without
# a story): once STUDIO_UNIT_WRAP_AT has passed, a WRAP-UP line; from
# STUDIO_UNIT_DEADLINE - 180 s, a FINAL line. Each fires once per (unit tag,
# main|agent_id), claimed by a marker file under <run dir>/deadline/. Before
# WRAP_AT the cost is one `date +%s`. Inbox messages and a notice due in the
# same call go out in one block, the notice first.
# Byte collation: under a UTF-8 locale macOS sh matches [a-z] by collation (A-Y too).
unset LC_ALL; LC_COLLATE=C
trap 'exit 0' EXIT
[ -n "${STUDIO_UNIT_TAG:-}" ] && [ -n "${STUDIO_RUN_DIR:-}" ] || exit 0
RD="$STUDIO_RUN_DIR"; TAG="$STUDIO_UNIT_TAG"
LC_ALL=C; export LC_ALL
[ -d "$RD" ] || exit 0
# A manifest run's unit with no story (the final step) gets nothing (AC9).
NOSTORY=0
if [ -f "$RD/rows.tsv" ]; then S="${STUDIO_STORY:-}"; [ -n "$S" ] || NOSTORY=1; else S=-; fi
# Nothing due, nothing to read: a storyless unit before WRAP_AT exits here, as before.
NOW=""
case "${STUDIO_UNIT_WRAP_AT:-}" in
  ''|*[!0-9]*) [ "$NOSTORY" = 0 ] || exit 0 ;;
  *) NOW="$(date +%s)"
     [ "$NOW" -ge "$STUDIO_UNIT_WRAP_AT" ] || [ "$NOSTORY" = 0 ] || exit 0 ;;
esac
exec 2>> "$RD/hook.log"
HERE="$(cd "$(dirname "$0")" && pwd)"
EV="$HERE/../bin/studio-event"
IN="$(cat)"

# field KEY — a top-level string field of the hook input (R19: no jq).
field() { printf '%s' "$IN" | tr -d '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; }
# msg_get and msg_body are the same as in overnight-channel.sh, and sq the
# same as in studio-overnight (kept identical; byte-wise, so invalid UTF-8 in
# a message body is carried whole). msg_body is the text verbatim, its lines
# kept (a `say --file` handoff is multi-line).
msg_get() { LC_ALL=C sed -n "1,/^--\$/s/^$1: //p" "$2" 2>/dev/null | head -n 1; }
msg_body() { LC_ALL=C sed '1,/^--$/d' "$1" 2>/dev/null; }
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# esc TEXT — TEXT as one ledger line: \ doubled, each newline written \n
# (studio-brief and `said` undo both).
esc() { printf '%s' "$1" | LC_ALL=C sed 's/\\/\\\\/g' | LC_ALL=C awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'; }
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

# hhmm EPOCH — local HH:MM (BSD date -r, else GNU date -d).
hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo "?"; }
# notice_once KIND WHO — claim the marker (atomic: noclobber create); true when
# this call won it.
notice_once() {
  _mk="$RD/deadline/$TAG.$2.$1"
  [ -f "$_mk" ] && return 1
  mkdir -p "$RD/deadline" 2>/dev/null || return 1
  ( set -C; : > "$_mk" ) 2>/dev/null
}
# deadline_notices WHO — NOTICE: the lines due now for session WHO (main or an
# agent id). Called only once NOW >= WRAP_AT, or for the final line.
deadline_notices() {
  NOTICE=""
  _dl="${STUDIO_UNIT_DEADLINE:-}"
  case "$_dl" in ''|*[!0-9]*) _dl="" ;; esac
  if [ "$NOW" -ge "$STUDIO_UNIT_WRAP_AT" ] && notice_once wrap "$1"; then
    if [ "$1" = main ]; then
      if [ -n "$_dl" ]; then
        NOTICE="WRAP-UP (STUDIO_UNIT_WRAP_AT passed): $(( (_dl - NOW > 0 ? _dl - NOW + 59 : 0) / 60 )) min to the hard stop at $(hhmm "$_dl"). Start no gate and no subagent. Commit and push green work, write the T<n> checkpoint ledger line (execute §8), end the turn."
      else
        NOTICE="WRAP-UP (STUDIO_UNIT_WRAP_AT passed): the hard stop is near. Start no gate and no subagent. Commit and push green work, write the T<n> checkpoint ledger line (execute §8), end the turn."
      fi
    else
      NOTICE="WRAP-UP: return to the orchestrator now with what is done and what is left; start nothing new."
    fi
  fi
  if [ -n "$_dl" ] && [ "$NOW" -ge $(( _dl - 180 )) ] && notice_once final "$1"; then
    _f="FINAL: $(( (_dl - NOW > 0 ? _dl - NOW + 59 : 0) / 60 )) min left — commit what is green and end now."
    NOTICE="${NOTICE:+$NOTICE
}$_f"
  fi
}

EVN="$(field hook_event_name)"
AGENT=0
case "$EVN" in
  SessionStart)
    case "$(field source)" in
      startup) MODE=claim; VIA=session_start ;;
      compact) MODE=reshow ;;
      *) exit 0 ;;
    esac ;;
  PostToolUse)
    top_agent_id && AGENT=1
    MODE=claim; VIA=tool_call ;;
  *) exit 0 ;;
esac
NOTICE=""
if [ -n "$NOW" ] && [ "$NOW" -ge "$STUDIO_UNIT_WRAP_AT" ]; then
  WHO=main
  if [ "$AGENT" = 1 ]; then
    WHO="$(field agent_id | tr -c 'A-Za-z0-9_-' '_')"; WHO="agent-${WHO:-x}"
  fi
  deadline_notices "$WHO"
fi

BLOCKOUT=""
inbox_part() {
[ "$NOSTORY" = 0 ] && [ "$AGENT" = 0 ] || return 0
IB="$RD/inbox/$S"; DL="$IB/delivered/$TAG"
[ -d "$IB" ] || return 0

SHOW=""
if [ "$MODE" = claim ]; then
  HEAD="OPERATOR MESSAGES — from the user, for story $S (overnight run)."
  for m in $(list "$IB"); do
    case "$(msg_get scope "$IB/$m")" in
      story|unit|task|retire|note) ;;
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
[ -n "$(printf '%s' "$SHOW" | tr -d ' \n')" ] || return 0

# record_how — the recording instruction's lines after its first, shared by
# story and task messages.
record_how() {
  printf '%s\n' "    ledger at your recording point — after §0 step (c), not merely after" \
    "    EnterWorktree; in a --land or --gate-repair unit, after entering the" \
    "    feature checkout — single-quoted, and commit it with your next ledger" \
    "    commit (push only what you would push anyway):"
}
# block — the runner's notes first (each under its own heading, never
# recorded), then the operator's messages under HEAD.
block() {
  OPS=0
  for m in $SHOW; do
    f="$DL/$m"
    if [ "$(msg_get scope "$f")" != note ]; then OPS=1; continue; fi
    printf 'RUNNER NOTE (previous attempt of %s)\n' "$(msg_get task "$f")"
    printf '%s\n' "$(msg_body "$f")"
    printf '%s\n' "  → From the overnight runner, not the user: where the last unit left this" \
      "    task. Pick up from it; do not record it."
  done
  [ "$OPS" = 1 ] || return 0
  printf '%s\n' "$HEAD"
  for m in $SHOW; do
    f="$DL/$m"; id="${m%.msg}"
    case "$(msg_get scope "$f")" in
      story)
        printf '[%s, story] %s\n' "$id" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this for the rest of the story. Record it in the feature checkout's"
        record_how
        printf '    studio-state ledger %s\n' "$(sq "Directive $id: $(esc "$(msg_body "$f")")")" ;;
      task)
        tk="$(msg_get task "$f")"
        printf '[%s, task %s] %s\n' "$id" "$tk" "$(msg_body "$f")"
        printf '%s\n' "  → Follow this until $tk is complete. Record it in the feature checkout's"
        record_how
        printf '    studio-state ledger %s\n' "$(sq "Directive $id $tk: $(esc "$(msg_body "$f")")")" ;;
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

BLOCKOUT="$(block)"
}
inbox_part
OUT="$BLOCKOUT"
if [ -n "$NOTICE" ]; then OUT="$NOTICE${OUT:+
$OUT}"; fi
[ -n "$OUT" ] || exit 0
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

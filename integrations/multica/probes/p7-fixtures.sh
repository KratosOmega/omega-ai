#!/bin/sh
# P7 CLI fixtures — run by hand in Terminal.app (not a Claude session), first
# in the run order; no model calls (the issues are unassigned, so no run
# starts). Needs no runtime profile.
# Writes to the real workspace: "[probe] fixture run" (top level,
# omega_run=probe-fixture) and "[probe] fixture S1" under it, three
# "studio: probe fixture ..." comments, a status change; possibly a second
# "[probe] fixture run" if the duplicate check does not refuse it. Both
# fixture issues end `cancelled` (--no-start) and are in $RES/cleanup.txt.
# The error captures call the CLI with a bogus token, no token, or an
# unreachable server inside `env -i` with an empty HOME: no real token is used.
# Writes locally: $RES/fixtures/*.json and errors/* (every file redacted),
# $RES/daemon-status.json (redacted, NOT in fixtures/: R33, nothing reads
# it, and the repo is public), $RES/results.txt, $RES/cleanup.txt.
# Usage: sh p7-fixtures.sh
. "$(dirname "$0")/lib.sh"
need_agent
FX="$RES/fixtures"
RAW="$RES/.p7-raw.json"
ERR="$RES/.p7-raw.err"
EMPTYHOME="$(mktemp -d "$RES/emptyhome.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$RAW" "$ERR" "$EMPTYHOME"' EXIT
mkdir -p "$FX/errors"

# cap NAME CMD... — stdout (JSON) of CMD through `pj redact` into
# fixtures/NAME.json; the unredacted copy stays in $RAW until the next cap.
cap() {
  _n="$1"; shift
  if "$@" > "$RAW" 2> "$ERR"; then
    pj redact < "$RAW" > "$FX/$_n.json" || die "$_n: output was not JSON"
  else
    echo "FAIL: $_n: $(redact < "$ERR" | head -3)" >&2
    echo "(a flag or verb here may be unverified: check 'multica ... --help')" >&2
    exit 1
  fi
}
# errcap NAME CMD... — stderr into errors/NAME.txt (redacted), exit code into
# errors/NAME.exit; the command is expected to fail.
errcap() {
  _n="$1"; shift
  "$@" > "$RAW" 2> "$ERR"
  _rc=$?
  { redact < "$ERR"; [ -s "$RAW" ] && redact < "$RAW"; } > "$FX/errors/$_n.txt"
  printf '%s\n' "$_rc" > "$FX/errors/$_n.exit"
}

cap version "$M" version --output json
cap user-profile mc user profile get --output json

printf '%s' 'Fixture run issue for the offline CLI stub. Safe to cancel.' | cap issue-create-run \
  mc issue create --title "[probe] fixture run" --status todo --property omega_run=probe-fixture --allow-duplicate --description-stdin --output json
RUNID="$(pj get identifier < "$RAW")"; [ -n "$RUNID" ] || die "run issue has no identifier"
cleanup_add issue "$RUNID"
cap issue-create-story \
  mc issue create --title "[probe] fixture S1" --parent "$RUNID" --status todo --property omega_run=probe-fixture --property omega_story=S1 --output json
STORY="$(pj get identifier < "$RAW")"; [ -n "$STORY" ] || die "story issue has no identifier"
cleanup_add issue "$STORY"

cap issue-get mc issue get "$STORY" --output json
cap issue-list-run mc issue list --property omega_run=probe-fixture --limit 100 --output json
cap issue-list-none mc issue list --property omega_run=probe-fixture --property omega_story=__none__ --limit 100 --output json
cap issue-list-page mc issue list --property omega_run=probe-fixture --limit 1 --output json
cap issue-list-assignee mc issue list --assignee-id "$AID" --sort created_at --direction desc --limit 20 --output json

printf '%s' 'studio: probe fixture root' | cap comment-add mc issue comment add "$RUNID" --content-stdin --output json
ROOT="$(pj get id < "$RAW")"; ROOT_AT="$(pj get created_at < "$RAW")"
[ -n "$ROOT" ] || die "root comment has no id"
printf '%s' 'studio: probe fixture reply' | cap comment-reply mc issue comment add "$RUNID" --parent "$ROOT" --content-stdin --output json
REPLY="$(pj get id < "$RAW")"
[ -n "$REPLY" ] || die "reply comment has no id"
printf '%s' 'studio: probe fixture reply 2' | cap comment-reply2 mc issue comment add "$RUNID" --parent "$REPLY" --content-stdin --output json
cap comment-list mc issue comment list "$RUNID" --output json
cap comment-list-since mc issue comment list "$RUNID" --since "$ROOT_AT" --output json

cap issue-runs mc issue runs OMEG-4 --output json
cap issue-status mc issue status "$STORY" in_progress --no-start --output json

cap runtime-list mc runtime list --output json
# P7g needs the unredacted rows: keep what it needs before the next cap.
RT_KEYS="$(pj first < "$RAW" | pj keys | tr '\n' ' ')"
RT_HOSTKEY="$(pj first < "$RAW" | pj keys | grep -Ei '(^|_)host' | tr '\n' ' ')"
if grep -qiF "$(hostname -s 2>/dev/null || hostname)" "$RAW"; then RT_HOSTVAL=yes; else RT_HOSTVAL=no; fi
cap runtime-profile-list mc runtime profile list --output json
cap agent-list mc agent list --output json
cap property-list mc property list --include-archived --output json

# daemon-status: $RES only (D10). Failure is not fatal; nothing reads it.
if "$M" --profile "$PROFILE" daemon status --output json > "$RAW" 2> "$ERR"; then
  pj redact < "$RAW" > "$RES/daemon-status.json" 2>/dev/null || redact < "$RAW" > "$RES/daemon-status.json"
else
  echo "WARN: daemon status failed (not fatal): $(redact < "$ERR" | head -1)" >&2
fi

# errors
errcap not-found mc issue get OMEG-999999 --output json
errcap unauthorized env -i PATH=/usr/bin:/bin HOME="$EMPTYHOME" MULTICA_TOKEN=mul_probe_bogus MULTICA_SERVER_URL="$SERVER" MULTICA_WORKSPACE_ID="$WS" "$M" issue get OMEG-2 --output json
errcap no-token env -i PATH=/usr/bin:/bin HOME="$EMPTYHOME" MULTICA_SERVER_URL="$SERVER" MULTICA_WORKSPACE_ID="$WS" "$M" issue get OMEG-2 --output json
errcap unreachable env -i PATH=/usr/bin:/bin HOME="$EMPTYHOME" MULTICA_TOKEN=mul_probe_bogus MULTICA_SERVER_URL=http://127.0.0.1:9 MULTICA_WORKSPACE_ID="$WS" "$M" issue get OMEG-2 --output json
errcap duplicate mc issue create --title "[probe] fixture run" --status todo --output json
DUP=""
if [ "$(cat "$FX/errors/duplicate.exit")" = 0 ]; then
  DUP="$(pj get identifier < "$RAW")"
  [ -n "$DUP" ] && cleanup_add issue "$DUP"
  echo "duplicate create SUCCEEDED as $DUP (cancelled below)"
fi
errcap bad-status mc issue status "$STORY" nosuch --no-start

# Fixture issues end cancelled.
mc issue status "$STORY" cancelled --no-start >/dev/null || echo "WARN: could not cancel $STORY" >&2
mc issue status "$RUNID" cancelled --no-start >/dev/null || echo "WARN: could not cancel $RUNID" >&2
[ -z "$DUP" ] || mc issue status "$DUP" cancelled --no-start >/dev/null || echo "WARN: could not cancel $DUP" >&2

# Records
RK=" $(pj first < "$FX/issue-runs.json" | pj keys | tr '\n' ' ')"
_p=pass
for _k in id started_at completed_at; do
  case "$RK" in *" $_k "*) ;; *) _p="fail (missing $_k)" ;; esac
done
record "P7a runs fields" "$_p; keys:$RK"

_pp="$(pj get parent_id < "$FX/comment-reply2.json")"
if [ "$_pp" = "$REPLY" ]; then record "P7b reply nesting" nested
elif [ "$_pp" = "$ROOT" ]; then record "P7b reply nesting" flattened
else record "P7b reply nesting" "other: parent_id=$_pp"; fi

_c="$(pj count < "$FX/issue-list-none.json")"
_i="$(pj rows identifier < "$FX/issue-list-none.json" | head -1)"
if [ "$_c" = 1 ] && [ "$_i" = "$RUNID" ]; then record "P7c none filter" "pass: only $RUNID"
else record "P7c none filter" "fail: $_c row(s), first=$_i (run issue is $RUNID)"; fi

record "P7d timestamp form" "$(pj get created_at < "$FX/issue-get.json")"

if pj rows id < "$FX/comment-list-since.json" | grep -qx "$ROOT"; then record "P7e since" inclusive
else record "P7e since" strict; fi

record "P7f list envelope" "issue-list-run:$(pj keys < "$FX/issue-list-run.json" | tr '\n' ',') issue-list-page:$(pj keys < "$FX/issue-list-page.json" | tr '\n' ',') comment-list:$(pj keys < "$FX/comment-list.json" | tr '\n' ',') issue-runs:$(pj keys < "$FX/issue-runs.json" | tr '\n' ',') runtime-list:$(pj keys < "$FX/runtime-list.json" | tr '\n' ',')"

record "P7g runtime rows" "keys: $RT_KEYS; host-named fields: ${RT_HOSTKEY:-none}; local host name in a value: $RT_HOSTVAL"

_h=""
for _f in "$FX"/errors/*.exit; do
  _b="$(basename "$_f" .exit)"
  _h="$_h $_b=[$(head -1 "$FX/errors/$_b.txt")] exit=$(cat "$_f");"
done
record "P7h error texts" "$_h"

echo "fixtures: $FX (the controller checks the token grep and the emails before copying)"

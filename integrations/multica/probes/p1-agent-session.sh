#!/bin/sh
# P1 agent session — run by hand in Terminal.app (not a Claude session); spends
# 1 model session. Needs MULTICA_PROBE_RUNTIME_PROFILE (the probe runtime
# profile id).
# Writes to the real workspace: changes the probe runtime profile's command
# name to omega-probe-agent, replaces gd-probe's custom env (OMEGA_PROJECT),
# creates issue "[probe] P1 session" assigned to gd-probe (starts 1 run).
# Writes locally: ~/omega-probe-p1, ~/.local/bin/omega-probe-agent and
# ~/.local/bin/omega-probe-context.md, $RES/results.txt, $RES/cleanup.txt.
# Usage: MULTICA_PROBE_RUNTIME_PROFILE=<id> sh p1-agent-session.sh
. "$(dirname "$0")/lib.sh"
need_runtime_profile
need_agent
command -v claude-gd >/dev/null 2>&1 || die "claude-gd is not on PATH"
command -v studio-state >/dev/null 2>&1 || die "studio-state is not on PATH"
P1="$HOME/omega-probe-p1"
BIN="$HOME/.local/bin"

# Throwaway project, outside ~/Documents.
if [ ! -d "$P1/.git" ]; then
  mkdir -p "$P1" || die "cannot create $P1"
  git -C "$P1" init -q || die "git init failed"
  (cd "$P1" && studio-state init) || die "studio-state init failed"
  printf 'omega probe P1 project\n' > "$P1/README.txt"
  git -C "$P1" add -A
  git -C "$P1" -c user.name=probe -c user.email=probe@example.com commit -q -m init || die "commit failed"
fi
[ -z "$(git -C "$P1" status --porcelain)" ] || die "$P1 is not clean before the probe"

# Wrapper and context are copies (rm first: P5 leaves a symlink here).
mkdir -p "$BIN"
rm -f "$BIN/omega-probe-agent" "$BIN/omega-probe-context.md"
cp "$PROBE_DIR/p1-agent-wrapper" "$BIN/omega-probe-agent" && chmod 755 "$BIN/omega-probe-agent" || die "cannot install the wrapper"
cp "$PROBE_DIR/p1-context.md" "$BIN/omega-probe-context.md" || die "cannot install the context"
: > "$RES/p1-calls.log"

# Unverified verbs: stop loudly, hint the web UI.
unverified "runtime profile update --command-name" \
  mc runtime profile update "$RP" --command-name omega-probe-agent
mc runtime profile list --output json | grep -q omega-probe-agent || {
  echo "FAIL: runtime profile $RP does not list command omega-probe-agent after the update. Set the command name in the Multica web UI, then re-run this script." >&2
  exit 1
}
printf '{"OMEGA_PROJECT": "%s"}' "$P1" | unverified "agent env set --custom-env-stdin" \
  mc agent env set "$AID" --custom-env-stdin
echo "waiting 30 s for the daemon's profile refresh"
sleep 30

ID="$(printf '%s' 'Run `pwd` and `git status --porcelain`. Write both outputs to a file under your Multica workdir and post it with `multica issue comment add <this issue> --content-file <file> --allow-external-file`. Then finish.' \
  | mc issue create --title "[probe] P1 session" --assignee-id "$AID" --description-stdin --output json | pj get identifier)"
[ -n "$ID" ] || die "issue create returned no identifier"
cleanup_add issue "$ID"
echo "created $ID; waiting up to 15 min for the run"
wait_idle "$ID" 900 || { record "P1 run" "fail: still active after 15 min ($ID)"; exit 1; }

C="$(mc issue comment list "$ID" --output json)"
n="$(printf '%s' "$C" | pj where author_type agent | pj startswith content CANARY-7Q)"
[ "$n" -ge 1 ] && record "P1 canary" "pass" || record "P1 canary" "fail: no agent comment starts with CANARY-7Q"
n="$(printf '%s' "$C" | pj where author_type agent | pj contains content "$P1")"
[ "$n" -ge 1 ] && record "P1 cwd" "pass: an agent comment carries $P1" || record "P1 cwd" "fail: no agent comment carries $P1"
if [ -z "$(git -C "$P1" status --porcelain)" ]; then record "P1 project clean" "pass"
else record "P1 project clean" "fail: $(git -C "$P1" status --porcelain | tr '\n' ';')"; fi
n="$(printf '%s' "$C" | pj where author_type agent | pj count)"
[ "$n" -ge 2 ] && record "P1 final comment" "pass: $n agent comments (file post + daemon final)" || record "P1 final comment" "fail: $n agent comment(s), expected 2+"
printf '%s' "$C" | pj redact | head -c 4000
echo
echo "argv/cwd log: $RES/p1-calls.log"
if confirm "Human check: did the agent post with 'issue comment add --content-file' (see the run transcript in the web UI)?"; then
  record "P1 workflow" "pass: content-file post seen in the transcript"
else
  record "P1 workflow" "fail or unseen: content-file post not confirmed"
fi

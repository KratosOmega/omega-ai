#!/bin/sh
# P5 Multica.app and ~/Documents — INTERACTIVE; run by hand in Terminal.app
# (not a Claude session); spends 2 model sessions (run + rerun). Run P1 first.
# Needs MULTICA_PROBE_RUNTIME_PROFILE.
# Human steps: answer whether Multica already has a Documents grant and
# whether to reset it (tccutil, your call); watch for the macOS file-access
# prompt and say which binary it names; grant it; press Enter. If `issue
# rerun` fails, rerun the issue in the web UI.
# Writes to the real workspace: replaces gd-probe's custom env (OMEGA_PROJECT
# -> the P5 project); creates "[probe] P5 documents" assigned to gd-probe
# (starts 1 run, then a rerun).
# Writes locally: ~/Documents/omega-probe-p5 (git, .studio, .probe/wrapper),
# ~/.local/bin/omega-probe-agent re-pointed as a symlink to it,
# $RES/results.txt, $RES/cleanup.txt. Lasting: a Documents grant for Multica
# (and the reset, if you choose it).
# Usage: MULTICA_PROBE_RUNTIME_PROFILE=<id> sh p5-documents.sh
. "$(dirname "$0")/lib.sh"
need_runtime_profile
need_agent
command -v studio-state >/dev/null 2>&1 || die "studio-state is not on PATH"
P5="$HOME/Documents/omega-probe-p5"
BIN="$HOME/.local/bin"
[ -f "$BIN/omega-probe-context.md" ] || die "run p1-agent-session.sh first (it installs the context beside the wrapper)"

if [ ! -d "$P5/.git" ]; then
  mkdir -p "$P5/.probe" || die "cannot create $P5 (a macOS prompt may have blocked it)"
  git -C "$P5" init -q || die "git init failed"
  (cd "$P5" && studio-state init) || die "studio-state init failed"
  printf 'omega probe P5 project\n' > "$P5/README.txt"
  git -C "$P5" add -A
  git -C "$P5" -c user.name=probe -c user.email=probe@example.com commit -q -m init || die "commit failed"
fi
mkdir -p "$P5/.probe"
cp "$PROBE_DIR/p1-agent-wrapper" "$P5/.probe/omega-probe-agent" && chmod 755 "$P5/.probe/omega-probe-agent" || die "cannot copy the wrapper"
rm -f "$BIN/omega-probe-agent"
ln -s "$P5/.probe/omega-probe-agent" "$BIN/omega-probe-agent" || die "cannot link the wrapper"

echo "Open System Settings > Privacy & Security > Files and Folders."
if confirm "Does it already list Multica with Documents access?"; then
  record "P5 prior grant" "Multica already had Documents access"
  if confirm "Reset it for the observation (tccutil reset SystemPolicyDocumentsFolder <Multica bundle id>)? This removes Multica's existing grant."; then
    BID="$(mdls -name kMDItemCFBundleIdentifier -raw /Applications/Multica.app 2>/dev/null)"
    [ -n "$BID" ] && [ "$BID" != "(null)" ] || die "cannot read Multica's bundle id (mdls)"
    tccutil reset SystemPolicyDocumentsFolder "$BID" || die "tccutil reset failed"
    record "P5 reset" "reset SystemPolicyDocumentsFolder for $BID"
  else
    record "P5 reset" "skipped by the user"
  fi
else
  record "P5 prior grant" "none listed"
fi

printf '{"OMEGA_PROJECT": "%s"}' "$P5" | unverified "agent env set --custom-env-stdin" \
  mc agent env set "$AID" --custom-env-stdin
echo "waiting 30 s for the daemon's refresh"
sleep 30

RT="$(mc runtime list --output json | pj find profile_id "$RP" status)"
record "P5 runtime status" "${RT:-no row for profile $RP} after the wrapper moved under ~/Documents"

ID="$(printf '%s' 'Run `ls` and `git status --porcelain`, post the output.' \
  | mc issue create --title "[probe] P5 documents" --assignee-id "$AID" --description-stdin --output json | pj get identifier)"
[ -n "$ID" ] || die "issue create returned no identifier"
cleanup_add issue "$ID"
echo "created $ID. Watch for a macOS file-access prompt now."
if confirm "Did a prompt appear?"; then
  printf 'Which binary did it name (Multica.app, the daemon binary, sh, claude, other)? '
  read -r _b
  record "P5 prompt" "named: $_b"
  printf 'Grant it (Allow), then press Enter. '
  read -r _x
else
  record "P5 prompt" "no prompt seen"
fi
wait_idle "$ID" 180 || echo "first run still active; continuing to the rerun"
unverified "issue rerun" mc issue rerun "$ID"
echo "rerun requested; waiting up to 15 min"
wait_idle "$ID" 900 || { record "P5 rerun" "fail: still active after 15 min"; exit 1; }
n="$(mc issue comment list "$ID" --output json | pj where author_type agent | pj contains content README.txt)"
[ "$n" -ge 1 ] && record "P5 listing posted" "pass: an agent comment lists README.txt" || record "P5 listing posted" "fail: no agent comment lists README.txt"
RT="$(mc runtime list --output json | pj find profile_id "$RP" status)"
record "P5 runtime status after" "${RT:-no row}"

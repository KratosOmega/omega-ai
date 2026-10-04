#!/bin/sh
# P6 launchd python and ~/Documents — INTERACTIVE; run by hand in Terminal.app
# (not a Claude session); no model calls, nothing in the Multica workspace.
# Run P5 first (it creates ~/Documents/omega-probe-p5).
# Human steps: after the first round, grant the path the macOS prompt or
# System Settings > Privacy & Security > Files and Folders names (a launchd
# job may raise no prompt: then add the interpreter under Full Disk Access),
# then say so; repeat if the other path needs its own grant.
# Writes locally: ~/Library/LaunchAgents/ai.omega.multica-probe-p6.plist
# (bootstrapped and booted out per run; delete it at cleanup),
# $RES/p6/{p6_check.py,out-<label>.json,err-<label>.log}, $RES/results.txt.
# Lasting: whatever grant you give (it covers every script that interpreter
# runs as you).
# Usage: sh p6-launchd.sh
. "$(dirname "$0")/lib.sh"
P5="$HOME/Documents/omega-probe-p5"
[ -d "$P5/.studio" ] || die "run p5-documents.sh first ($P5/.studio is missing)"
P6="$RES/p6"
LABEL=ai.omega.multica-probe-p6
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOM="gui/$(id -u)"
mkdir -p "$P6" "$HOME/Library/LaunchAgents"
cp "$PROBE_DIR/p6_check.py" "$P6/p6_check.py" || die "cannot copy p6_check.py"
SHIM=/usr/bin/python3
REAL="$("$SHIM" -c 'import os,sys;print(os.path.realpath(sys.executable))')"
[ -n "$REAL" ] || die "cannot resolve the real python path"
echo "shim: $SHIM"
echo "real: $REAL"

# run_one NAME PYTHON — one launchd job; the job writes out-NAME.json.
run_one() {
  rm -f "$P6/out-$1.json" "$P6/err-$1.log"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$2</string><string>$P6/p6_check.py</string><string>$P5</string><string>$1</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$P6/err-$1.log</string>
  <key>StandardOutPath</key><string>$P6/err-$1.log</string>
</dict>
</plist>
EOF
  launchctl bootout "$DOM/$LABEL" >/dev/null 2>&1
  launchctl bootstrap "$DOM" "$PLIST" || die "launchctl bootstrap failed for $1"
  sleep 10
  launchctl bootout "$DOM/$LABEL" >/dev/null 2>&1
}

# round PHASE — shim and real, one result line each.
round() {
  for _n in shim real; do
    if [ "$_n" = shim ]; then _py="$SHIM"; else _py="$REAL"; fi
    run_one "$_n" "$_py"
    if [ -f "$P6/out-$_n.json" ]; then
      _ok="$(pj get ok < "$P6/out-$_n.json")"
      _er="$(pj get error < "$P6/out-$_n.json")"
      record "P6 $1 $_n" "ok=$_ok script-ran=yes error=${_er:-none}"
    else
      record "P6 $1 $_n" "script-ran=no (see $P6/err-$_n.log)"
    fi
  done
}

round before-grant
echo "Now grant access: the prompt, or Files and Folders (Documents) for the python the pane names;"
echo "if no prompt appeared, add the interpreter under Full Disk Access."
printf 'Which path or route did you grant (e.g. shim, real, FDA shim)? '
read -r _g
record "P6 grant" "$_g"
round after-grant
while confirm "Does the other path still need a grant? Grant it, then answer y to run another round."; do
  printf 'What did you grant? '
  read -r _g
  record "P6 grant" "$_g"
  round after-grant
done

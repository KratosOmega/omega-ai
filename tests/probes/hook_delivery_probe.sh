#!/bin/sh
# hook_delivery_probe.sh — does the installed Claude Code still deliver hook
# output the way the overnight operator channel (#27) relies on? It repeats
# the 2026-10-03 spike's three checks (spec References):
#   1. a hook's input carries agent_id only inside a subagent (the inbox hook
#      skips subagent tool calls on it);
#   2. a PostToolUse hook's hookSpecificOutput.additionalContext reaches the
#      model in -p;
#   3. SessionStart plain stdout reaches the model in -p.
# Session a (checks 2, 3): one Bash call; the model's reply must quote both
# markers, which only the hooks know. Session b (check 1): one main Bash call
# and one subagent Bash call; the PostToolUse hook logs each input to ptu.log.
# The hooks are throwaway, passed with --settings; nothing is installed.
#
# Not part of tests/run_all.sh: it spends real model calls (haiku, at most
# $1 per session, two sessions).
# On PASS it writes ~/.claude-gamedev/probes/hook_delivery: line 1 the
# launcher's --version, line 2 the UTC date. doctor.sh prints it.
#
# Usage: hook_delivery_probe.sh [LAUNCHER]   (default claude)
# Exit 0 PASS · 1 FAIL · 2 usage or no launcher. Logs: $PROBE_DIR (default a
# mktemp dir).
set -u
usage() { echo "usage: hook_delivery_probe.sh [LAUNCHER]" >&2; exit 2; }
[ "$#" -le 1 ] || usage
L="${1:-claude}"
case "$L" in ''|-*) usage ;; esac
command -v "$L" >/dev/null 2>&1 || { echo "probe: $L not on PATH" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/hook-delivery-probe.XXXXXX")}"
case "$D" in *\'*|*\"*|*\\*) echo "probe: PROBE_DIR may not hold a quote or a backslash" >&2; exit 2 ;; esac
mkdir -p "$D/a" "$D/b" || exit 2
SSM=PROBE_SS_7d41; PTM=PROBE_PT_93c2

cat > "$D/ss.sh" <<EOF
#!/bin/sh
cat >/dev/null
echo "Session marker: $SSM"
EOF
cat > "$D/ptu.sh" <<EOF
#!/bin/sh
{ tr -d '\\n'; echo; } >> '$D/ptu.log'
printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Tool marker: $PTM"}}'
EOF
cat > "$D/settings.json" <<EOF
{"hooks": {
  "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "sh '$D/ss.sh'"}]}],
  "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "sh '$D/ptu.sh'"}]}]
}}
EOF

run() {  # run NAME PROMPT — one session in $D/NAME; stream-json in $D/NAME.jsonl
  ( cd "$D/$1" && "$L" -p "$2" --model haiku --settings "$D/settings.json" \
      --output-format stream-json --verbose \
      --permission-mode auto --permission-prompts none --max-budget-usd 1 ) \
    > "$D/$1.jsonl" 2> "$D/$1.err" < /dev/null
}
# reply NAME — the session's result line only: hook output echoed in the
# stream's other lines must not count as the model quoting it.
reply() { grep '"type":"result"' "$D/$1.jsonl" 2>/dev/null | tail -n 1; }
ran() { grep -q "\"command\":\"$2\"" "$D/$1.jsonl" 2>/dev/null; }
# bash_input TEXT — the logged PostToolUse input of the Bash call running TEXT.
bash_input() { grep '"tool_name": *"Bash"' "$D/ptu.log" 2>/dev/null | grep -- "$1" | head -n 1; }

rm -f "$D/ptu.log"
run a "Run this Bash command exactly once, in the foreground: echo probe-a
Then reply with one line: SS=<the session marker you were given at session start, or NONE> PT=<the tool marker you were given after the tool call, or NONE>"
mv -f "$D/ptu.log" "$D/a-ptu.log" 2>/dev/null
run b "Do exactly these two steps, in order, and nothing else.
1. Run this Bash command in the foreground: echo probe-main
2. Use the Agent tool once, with subagent_type general-purpose, giving the subagent this prompt: Run this Bash command in the foreground: echo probe-sub. Then reply done.
When both steps are done, reply with one line: OK"

ok=1
if ! ran a "echo probe-a"; then
  echo "probe: session a never ran its Bash call — inconclusive, rerun (logs: $D)" >&2; ok=0
else
  if reply a | grep -q "$SSM"; then echo "3 SessionStart stdout: reached the model"; else echo "3 SessionStart stdout: NOT seen by the model"; ok=0; fi
  if reply a | grep -q "$PTM"; then echo "2 PostToolUse additionalContext: reached the model"; else echo "2 PostToolUse additionalContext: NOT seen by the model"; ok=0; fi
fi
M="$(bash_input 'echo probe-main')"; S="$(bash_input 'echo probe-sub')"
if [ -z "$M" ] || [ -z "$S" ]; then
  echo "probe: session b ran no main or no subagent Bash call — inconclusive, rerun (logs: $D)" >&2; ok=0
elif printf '%s' "$M" | grep -q '"agent_id"'; then
  echo "1 agent_id: present in a MAIN-session hook input"; ok=0
elif ! printf '%s' "$S" | grep -q '"agent_id"'; then
  echo "1 agent_id: ABSENT from the subagent's hook input"; ok=0
else
  echo "1 agent_id: only inside the subagent"
fi
echo "logs: $D"
if [ "$ok" = 1 ]; then
  R="${HOME%/}/.claude-gamedev/probes"
  if mkdir -p "$R" && { "$L" --version 2>/dev/null | head -n 1; date -u +%Y-%m-%d; } > "$R/hook_delivery.tmp" \
     && mv -f "$R/hook_delivery.tmp" "$R/hook_delivery"; then
    echo "recorded: $R/hook_delivery"
  else
    echo "probe: could not write $R/hook_delivery" >&2
  fi
  echo PASS; exit 0
fi
echo FAIL; exit 1

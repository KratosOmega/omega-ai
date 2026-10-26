#!/bin/sh
# deadline_notice_probe.sh — does a PostToolUse hook's additionalContext reach
# a SUBAGENT's model? The operator-inbox hook's wrap-up notice
# (STUDIO_UNIT_WRAP_AT) is sent to subagents on that assumption; hook_delivery_probe.sh
# proves it only for the main session.
#
# One session. A throwaway PostToolUse hook (passed with --settings; nothing is
# installed) logs every input to ptu.log and, only when the input has a
# top-level agent_id (a subagent's call), answers with a canary as
# hookSpecificOutput.additionalContext. The main session is asked to dispatch
# one general-purpose subagent that runs `true` twice, then reports any canary
# it saw after its tool calls. The canary is known only to the hook, so it can
# appear in the subagent's report only if the hook output reached the subagent.
#
# Not part of tests/run_all.sh: it spends real model calls (haiku, at most $1).
#
# Usage: deadline_notice_probe.sh [LAUNCHER]   (default claude-gd)
# Exit 0 PASS (the canary reached the subagent) · 1 FAIL or inconclusive ·
# 2 usage or no launcher. Logs: $PROBE_DIR (default a mktemp dir).
set -u
usage() { echo "usage: deadline_notice_probe.sh [LAUNCHER]" >&2; exit 2; }
[ "$#" -le 1 ] || usage
L="${1:-claude-gd}"
case "$L" in ''|-*) usage ;; esac
command -v "$L" >/dev/null 2>&1 || { echo "probe: $L not on PATH" >&2; exit 2; }
D="${PROBE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/deadline-notice-probe.XXXXXX")}"
case "$D" in *\'*|*\"*|*\\*) echo "probe: PROBE_DIR may not hold a quote or a backslash" >&2; exit 2 ;; esac
mkdir -p "$D/run" || exit 2
CANARY=CANARY_WRAP_5e2b

cat > "$D/ptu.sh" <<EOS
#!/bin/sh
IN="\$(cat)"
printf '%s\n' "\$IN" | tr -d '\\n' >> '$D/ptu.log'; echo >> '$D/ptu.log'
if printf '%s' "\$IN" | grep -q '"agent_id"' && printf '%s' "\$IN" | grep -q '"tool_name": *"Bash"'; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"WRAP-UP canary: $CANARY"}}'
fi
exit 0
EOS
cat > "$D/settings.json" <<EOS
{"hooks": {"PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "sh '$D/ptu.sh'"}]}]}}
EOS

rm -f "$D/ptu.log"
P="Do exactly these steps and nothing else.
1. Use the Agent tool once, with subagent_type general-purpose, giving the subagent this prompt: Run the Bash command 'true' twice, as two separate foreground Bash calls. After the second call, reply with one line: SAW=<any text beginning WRAP-UP canary that you were given after a tool call, quoted exactly, or NONE>.
2. When it returns, reply with one line: SUB=<the subagent's reply, verbatim>."
( cd "$D/run" && "$L" -p "$P" --model haiku --settings "$D/settings.json" \
    --output-format stream-json --verbose \
    --permission-mode auto --permission-prompts none --max-budget-usd 1 ) \
  > "$D/session.jsonl" 2> "$D/session.err" < /dev/null

# The hook saw subagent tool calls (top-level agent_id on a Bash call) …
subcalls="$(grep '"tool_name": *"Bash"' "$D/ptu.log" 2>/dev/null | grep -c '"agent_id"' || true)"
# … and the canary is in the session's final reply only (hook output echoed in
# other stream lines does not count).
reply="$(grep '"type":"result"' "$D/session.jsonl" 2>/dev/null | tail -n 1)"
echo "logs: $D"
if [ "${subcalls:-0}" -lt 1 ]; then
  echo "probe: the subagent ran no Bash call the hook saw — inconclusive, rerun" >&2; echo FAIL; exit 1
fi
echo "subagent Bash calls seen by the hook: $subcalls"
if printf '%s' "$reply" | grep -q "$CANARY"; then
  echo "PostToolUse additionalContext: reached the subagent"
  echo PASS; exit 0
fi
echo "PostToolUse additionalContext: NOT seen by the subagent — the wrap-up notice would not reach subagents"
echo FAIL; exit 1

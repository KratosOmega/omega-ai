#!/bin/sh
# godot_route_probe.sh allow|hookcount|rollout — #66 live checks (plan T1, T7).
# Runs real Claude Code sessions (PROBE_MODEL, default sonnet; at most $1 each)
# in a scratch dir made under $TMPDIR — never in a project:
#   allow      R3 (a): the allow rules match (a dontAsk control) and survive
#              auto mode (calls 1-4 run, no classifier denial, no rule dropped).
#   hookcount  R3 (b): three hook refusals in a row, then ordinary calls; hook
#              denials must not trip auto mode's consecutive-denial limit
#              (decision_reason_type asyncAgent).
#   rollout    the spec's rollout check: in a throwaway Godot project a
#              runner-style session (this checkout's plugins, allow + deny
#              rules, OMEGA_AUTOPILOT=1) is refused a bare --script run, runs
#              the retry the refusal names, then makes an ordinary call.
# Plugins are this checkout's (--plugin-dir); claude-gd would load the main
# checkout's. Prints the evidence and one RESULT line.
set -u
R="$(cd "$(dirname "$0")/../.." && pwd -P)"
MODE="${1:-}"; M="${PROBE_MODEL:-sonnet}"
case "$MODE" in allow|hookcount|rollout) ;; *) echo "usage: $0 allow|hookcount|rollout" >&2; exit 2 ;; esac
[ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] || { echo "set TMPDIR to an existing scratch dir" >&2; exit 2; }
D="$(mktemp -d "$TMPDIR/godot-route-$MODE.XXXXXX")" && D="$(cd "$D" && pwd -P)" || exit 2
if git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "refused: $D is inside a git work tree" >&2; exit 2; fi
case "$D" in "$HOME"/GameDev/*) echo "refused: $D is under ~/GameDev" >&2; exit 2 ;; esac
mkdir -p "$D/bin" "$D/proj"; LOG="$D/stub.log"; : > "$LOG"
echo "probe dir: $D"; claude --version

# The spec's R3 rules (bin/overnight-allow.txt's ten lines); rollout reads the file.
RULES='Bash(studio-test:*)
Bash(studio-run:*)
Bash(studio-gate godot -- /Applications/Godot.app/Contents/MacOS/Godot *)
Bash(studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot *)
Bash(studio-gate godot -- Godot *)
Bash(studio-gate godot -- godot *)
Bash(studio-gate godot -- $GODOT *)
Bash(studio-gate godot -- ${GODOT} *)
Bash(studio-gate godot -- $GODOT_PATH *)
Bash(studio-gate godot -- $GODOT_BIN *)'
if [ "$MODE" = rollout ]; then
  RULES="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$R/studios/game-dev/bin/overnight-allow.txt" | grep -v '^#' | grep .)" \
    || { echo "no allow rules in $R/studios/game-dev/bin/overnight-allow.txt" >&2; exit 2; }
fi
DENY="$(sh "${PROBE_OVERNIGHT:-$R/studios/game-dev/bin/studio-overnight}" deny-rules --dir "$D/proj" 2>/dev/null)"
# The runner's rule args, in its order: --allowedTools … then --disallowedTools … last.
set -- --allowedTools
while IFS= read -r _r; do [ -z "$_r" ] || set -- "$@" "$_r"; done <<EOF
$RULES
EOF
set -- "$@" --disallowedTools
while IFS= read -r _r; do [ -z "$_r" ] || set -- "$@" "$_r"; done <<EOF
$DENY
EOF

PROBE_PATH="$PATH"; PROBE_GODOT=""; PROBE_AUTOPILOT=""
# session NAME PERMISSION_MODE PROMPT ARGS… — one headless session in $D/proj.
session() {
  _n="$1"; _pm="$2"; _p="$3"; shift 3
  ( cd "$D/proj" && exec env PATH="$PROBE_PATH" GODOT="$PROBE_GODOT" OMEGA_AUTOPILOT="$PROBE_AUTOPILOT" \
      CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR_PROBE:-$HOME/.claude-gamedev}" \
      claude --plugin-dir "$R/studios/game-dev" --plugin-dir "$R/shared/omega" -p "$_p" --model "$M" \
      --output-format stream-json --verbose --permission-mode "$_pm" --permission-prompts none \
      --max-budget-usd 1 --debug-file "$D/$_n.debug" "$@" ) > "$D/$_n.jsonl" 2> "$D/$_n.err" < /dev/null
}
# denials FILE TYPE — FILE's permission_denied events of decision_reason_type TYPE.
denials() { grep '"subtype":"permission_denied"' "$1" | grep -c "\"decision_reason_type\":\"$2\""; }
# stub NAME TAG — an executable $D/bin/NAME that logs "TAG <args>" and prints TAG-OK.
stub() { printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >> "%s"; echo %s-OK\n' "$2" "$LOG" "$2" > "$D/bin/$1"; chmod +x "$D/bin/$1"; }
ORDER='Make each Bash call below exactly as written, one per Bash call, in order. If a call is refused or fails, note it in one line and go on to the next. Do not change, combine or explain the commands. When done, reply DONE.'

case "$MODE" in
allow)
  stub studio-gate STUB-GATE; stub studio-test STUB-TEST; stub Godot STUB-GODOT
  PROBE_PATH="$D/bin:$PATH"; PROBE_GODOT="$D/bin/Godot"
  P="$ORDER
1. studio-gate godot -- Godot --headless --path . --script res://probe1.gd
2. studio-gate godot -- \$GODOT --headless --import .
3. studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://probe3.gd 2>&1 | tail -5
4. studio-test --file tests/unit/probe4.gd
5. studio-gate godot -- /tmp/not-godot/Godot --version"
  _bad=""
  for pm in dontAsk auto; do
    : > "$LOG"; session "$pm" "$pm" "$P" "$@"
    echo "== $pm: stub log"; cat "$LOG"
    echo "== $pm: permission_denied events"; grep '"subtype":"permission_denied"' "$D/$pm.jsonl"
    for w in probe1.gd ' --import \.' probe3.gd probe4.gd; do
      grep -q -- "$w" "$LOG" || _bad="$_bad $pm:missing($w)"
    done
    [ "$pm" != dontAsk ] || ! grep -q not-godot "$LOG" || _bad="$_bad dontAsk:near-miss-ran"
  done
  [ "$(denials "$D/auto.jsonl" classifier)" -eq 0 ] || _bad="$_bad auto:classifier-denials"
  echo "== auto: debug log (rule handling and decisions)"
  grep -n -i -E 'allowedTools|allow rule|dangerous|strip|drop|classifier|auto.?mode|decision' "$D/auto.debug" | head -n 80
  if [ -n "$_bad" ]; then echo "RESULT allow: FAIL —$_bad"
  else echo "RESULT allow: MATCHED — judge PASS or INCONCLUSIVE from the debug lines above (plan T1 table)"; fi ;;
hookcount)
  printf '%s\n' '#!/bin/sh' \
    'case "$(cat)" in *PROBE_REFUSE*) printf "%s\n" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"probe: refused by a hook; go on to the next call\"}}" ;; esac' \
    'exit 0' > "$D/refuse.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh %s/refuse.sh"}]}]}}\n' "$D" > "$D/settings.json"
  P="$ORDER
1. echo PROBE_REFUSE_1
2. echo PROBE_REFUSE_2
3. echo PROBE_REFUSE_3
4. git init -q probe4
5. touch probe4/ok
6. echo PROBE_OK"
  session hook auto "$P" --settings "$D/settings.json" "$@"
  _r="$(grep -o 'probe: refused by a hook' "$D/hook.jsonl" | grep -c .)"; _a="$(denials "$D/hook.jsonl" asyncAgent)"
  echo "hook refusals seen: $_r; asyncAgent events: $_a; probe4/ok: $([ -f "$D/proj/probe4/ok" ] && echo yes || echo no)"
  grep '"subtype":"permission_denied"' "$D/hook.jsonl"
  if [ "$_a" -gt 0 ]; then echo "RESULT hookcount: FAIL — hook denials tripped the consecutive-denial limit"
  elif [ "$_r" -ge 3 ] && [ -f "$D/proj/probe4/ok" ] && grep -q PROBE_OK "$D/hook.jsonl"; then echo "RESULT hookcount: PASS"
  else echo "RESULT hookcount: INCONCLUSIVE — the model skipped calls; rerun"; fi ;;
rollout)
  G="${GODOT_APP:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
  [ -x "$G" ] || { echo "no Godot at $G" >&2; exit 2; }
  printf 'config_version=5\n\n[application]\n\nconfig/name="route-probe"\n' > "$D/proj/project.godot"
  mkdir -p "$D/proj/tools"
  printf 'extends SceneTree\n\nfunc _init() -> void:\n\tprint("PROBE_HELLO")\n\tquit()\n' > "$D/proj/tools/hello.gd"
  PROBE_PATH="$R/studios/game-dev/bin:$PATH"; PROBE_AUTOPILOT=1
  W="studio-gate godot -- $G --headless --path . --script res://tools/hello.gd 2>&1"
  P="Run this Bash command exactly as written: $G --headless --path . --script res://tools/hello.gd 2>&1 | tail -5
If a hook refuses it, run the exact command the refusal names, once. Then run: git init -q . && git status --short
Reply DONE."
  session rollout auto "$P" "$@"
  _ok=1
  grep -q 'refused an unwrapped Godot script/import run' "$D/rollout.jsonl" || { _ok=0; echo "no R1 refusal"; }
  grep -qF "\"command\":\"$W" "$D/rollout.jsonl" || { _ok=0; echo "the retry was not run as named: $W"; }
  grep -q PROBE_HELLO "$D/rollout.jsonl" || { _ok=0; echo "the retry did not run the script"; }
  [ -d "$D/proj/.git" ] || { _ok=0; echo "the ordinary call after the retry did not run"; }
  _c="$(denials "$D/rollout.jsonl" classifier)"; _a="$(denials "$D/rollout.jsonl" asyncAgent)"
  echo "classifier denials: $_c; asyncAgent: $_a"
  [ "$_c" -eq 0 ] && [ "$_a" -eq 0 ] || _ok=0
  if [ "$_ok" = 1 ]; then echo "RESULT rollout: PASS"; else echo "RESULT rollout: FAIL"; fi ;;
esac

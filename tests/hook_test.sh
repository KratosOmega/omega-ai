#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO_DIR="$REPO_ROOT/studios/game-dev"
HOOK="$STUDIO_DIR/hooks/session-start.sh"
GUARD="$STUDIO_DIR/hooks/guard-state.sh"
STAGE_GUARD="$STUDIO_DIR/hooks/stage-guard.sh"
INBOX="$STUDIO_DIR/hooks/operator-inbox.sh"
# ---- #27: the operator-inbox hook ----
SS_START='{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}'
SS_COMPACT='{"session_id":"s","hook_event_name":"SessionStart","source":"compact"}'
SS_CLEAR='{"session_id":"s","hook_event_name":"SessionStart","source":"clear"}'
PTU='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":""}}'
PTU_SUB='{"session_id":"s","agent_id":"a1","agent_type":"general-purpose","hook_event_name":"PostToolUse","tool_name":"Bash"}'
# ib_fresh single|manifest — a fresh run dir IR. manifest adds rows.tsv with
# story S1. IS is the story's inbox (inbox/- or inbox/S1).
ib_fresh() {
  IR="$TMP/overnight-ib-$1"; rm -rf "$IR"; mkdir -p "$IR"
  if [ "$1" = manifest ]; then printf 'S1\tS1-b\tS1\t-\t-\t\n' > "$IR/rows.tsv"; IS="$IR/inbox/S1"
  else IS="$IR/inbox/-"; fi
  mkdir -p "$IS"
}
# put_msg DIR ID SCOPE TEXT [TARGET] — a message file, as `say` writes it.
put_msg() {
  printf 'id: %s\nscope: %s\ntarget: %s\nstory: -\nqueued: 2026-10-03T21:04:00Z\nrequeues: 0\n--\n%s\n' \
    "$2" "$3" "${5:--}" "$4" > "$1/$2.msg"
}
# inbox_run STORY|none JSON [OUT] — the hook as a unit's session runs it:
# tag ${TG:-tagA}, run dir IR, STUDIO_STORY unless none. IB_ST; output in OUT
# (default $TMP/ib.out).
inbox_run() {
  IB_ST=0
  ( unset STUDIO_STORY
    [ "$1" = none ] || { STUDIO_STORY="$1"; export STUDIO_STORY; }
    STUDIO_UNIT_TAG="${TG:-tagA}"; STUDIO_RUN_DIR="$IR"; export STUDIO_UNIT_TAG STUDIO_RUN_DIR
    printf '%s' "$2" | sh "$INBOX" ) > "${3:-$TMP/ib.out}" 2> "$TMP/ib.err" || IB_ST=$?
}
# delivered N — the count of message_delivered events in IR.
delivered() {
  [ -f "$IR/events.jsonl" ] || { echo 0; return 0; }
  grep -c '"event":"message_delivered"' "$IR/events.jsonl" || true
}
AUTOPILOT_GUARD="$STUDIO_DIR/hooks/autopilot-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_hook DIR — run the hook as Claude Code would: cwd is the project, the
# plugin root is passed in the environment. Output lands in $TMP/hook.out.
run_hook() {
  ( cd "$1" && CLAUDE_PLUGIN_ROOT="$STUDIO_DIR" sh "$HOOK" ) > "$TMP/hook.out" 2>"$TMP/hook.err"
}

# context FILE — the additionalContext string, unescaped, via jq when present;
# otherwise the raw JSON (still greppable for escaped fragments).
context() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hookSpecificOutput.additionalContext' "$1"
  else
    cat "$1"
  fi
}

# typed_line STAGE — a transcript line for a typed /game-dev:STAGE, as
# Claude Code writes the command's envelope.
typed_line() {
  printf '{"type":"user","message":{"role":"user","content":"<command-message>game-dev:%s</command-message>\\n<command-name>/game-dev:%s</command-name>"}}\n' "$1" "$1"
}

# skill_line STAGE — a transcript line for a Skill tool call of game-dev:STAGE
# (the router invoking a stage).
skill_line() {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Skill","input":{"skill":"game-dev:%s"}}]}}\n' "$1"
}

# guard_input FILE — run the stage guard with FILE as its stdin, as Claude
# Code would. Asserts exit 0; stdout lands in $TMP/guard.out.
guard_input() {
  _gst=0
  CLAUDE_PLUGIN_ROOT="$STUDIO_DIR" sh "$STAGE_GUARD" < "$1" > "$TMP/guard.out" 2> "$TMP/guard.err" || _gst=$?
  assert_eq "0" "$_gst" "the stage guard exits 0"
}

# run_guard PROMPT TRANSCRIPT — a UserPromptSubmit input whose prompt is
# PROMPT (JSON string content, so '\n' stays an escape) and whose
# transcript_path is TRANSCRIPT, fed to the guard.
run_guard() {
  printf '{"session_id":"s-1","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}\n' \
    "$2" "$TMP" "$1" > "$TMP/guard.in"
  guard_input "$TMP/guard.in"
}

# warning PRIOR TYPED — the exact systemMessage text (spec §3).
warning() {
  printf 'game-dev: this session already ran /game-dev:%s — its context is carried into %s. Run /clear, then /game-dev:%s.' \
    "$1" "$2" "$2"
}

# assert_warns PRIOR TYPED MSG — stdout is one JSON object whose only key is
# systemMessage, carrying the warning text.
assert_warns() {
  assert_eq "1" "$(wc -l < "$TMP/guard.out" | tr -d ' ')" "$3 (one line)"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "$(warning "$1" "$2")" "$(jq -r .systemMessage "$TMP/guard.out")" "$3"
    assert_eq "systemMessage" "$(jq -r 'keys | join(",")' "$TMP/guard.out")" "$3 (systemMessage is the only key)"
  else
    assert_eq "{\"systemMessage\":\"$(warning "$1" "$2")\"}" "$(cat "$TMP/guard.out")" "$3"
  fi
}

# assert_silent MSG — the guard printed nothing at all.
assert_silent() {
  assert_eq "" "$(cat "$TMP/guard.out")" "$1"
}

test_hook_files() {
  assert_file "$STUDIO_DIR/hooks/hooks.json" "hooks.json exists"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" '"SessionStart"' "hooks.json registers SessionStart"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'startup|clear|compact' "hooks.json matches startup, clear and compact"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh' \
    "hooks.json runs session-start.sh from the plugin root"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "hooks.json is valid JSON" -- jq -e . "$STUDIO_DIR/hooks/hooks.json"
  fi
  assert_file "$STUDIO_DIR/hooks/bootstrap.md" "bootstrap.md exists"
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" "stage skills own the workflow" "bootstrap carries the precedence rule"
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" 'invoke `game-dev:brainstorm` instead' \
    "bootstrap redirects superpowers' brainstorming"
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" 'in the main session in `--inline` mode' \
    "bootstrap says where godot-prompter skills run in inline mode"
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" "/game-dev:studio" "bootstrap lists the router"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" '"PreToolUse"' "hooks.json registers PreToolUse"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'Edit|Write|MultiEdit' "the guard matches the file-writing tools"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/guard-state.sh' \
    "hooks.json runs guard-state.sh from the plugin root"
  B="$STUDIO_DIR/hooks/bootstrap.md"
  assert_contains "$B" '/game-dev:review \[scope\]' "bootstrap lists the on-demand review"
  assert_contains "$B" '/game-dev:playtest <what failed>' "bootstrap lists the on-demand playtest"
  assert_contains "$B" '/game-dev:retro' "bootstrap lists the on-demand retro"
  assert_contains "$B" 'idle → brainstorm → plan → execute → idle' "bootstrap states the three-stage chain"
  assert_contains "$B" 'Run each stage in a fresh session: `/clear`' "bootstrap says to /clear between stages"
  assert_contains "$B" 'omega modes' "bootstrap says /clear ends the session's omega modes"
  assert_not_contains "$B" 'game-dev:''ship' "bootstrap names no deleted command"
}

test_hook_output_shape() {
  mkdir -p "$TMP/plain"
  assert_status 0 "hook exits 0 in a directory with no state" -- \
    sh -c "cd '$TMP/plain' && CLAUDE_PLUGIN_ROOT='$STUDIO_DIR' sh '$HOOK' >/dev/null"
  run_hook "$TMP/plain"
  assert_contains "$TMP/hook.out" '"hookEventName":"SessionStart"' "output names the SessionStart event"
  assert_contains "$TMP/hook.out" '"additionalContext":"' "output carries additionalContext"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "output is valid JSON" -- jq -e . "$TMP/hook.out"
  fi
  assert_eq "1" "$(wc -l < "$TMP/hook.out" | tr -d ' ')" "output is a single line"
}

test_hook_defaults_from_studio_json() {
  mkdir -p "$TMP/defaults"
  run_hook "$TMP/defaults"
  context "$TMP/hook.out" > "$TMP/ctx.txt"
  assert_contains "$TMP/ctx.txt" "game-dev" "context names the studio"
  assert_contains "$TMP/ctx.txt" "Godot 4.x · 2D · GDScript · GUT" "identity line uses the studio defaults"
  assert_contains "$TMP/ctx.txt" "stage skills own the workflow" "context carries the precedence rule"
  assert_contains "$TMP/ctx.txt" "/game-dev:brainstorm" "context lists the stages"
  assert_contains "$TMP/ctx.txt" ".studio/STATE.md" "context carries the state instruction"
}

test_hook_reads_project_config() {
  mkdir -p "$TMP/proj/.studio"
  printf '{ "engine": "godot4", "dimension": "3d", "language": "csharp", "tests": "gdunit4" }\n' \
    > "$TMP/proj/.studio/config.json"
  run_hook "$TMP/proj"
  context "$TMP/hook.out" > "$TMP/ctx2.txt"
  assert_contains "$TMP/ctx2.txt" "Godot 4.x · 3D · C# · gdUnit4" "identity line reads .studio/config.json"
}

test_hook_partial_config_falls_back() {
  mkdir -p "$TMP/partial/.studio"
  printf '{ "dimension": "3d" }\n' > "$TMP/partial/.studio/config.json"
  run_hook "$TMP/partial"
  context "$TMP/hook.out" > "$TMP/ctx3.txt"
  assert_contains "$TMP/ctx3.txt" "Godot 4.x · 3D · GDScript · GUT" "missing keys fall back to studio defaults"
}

test_hook_escapes_json() {
  # A quote and a backslash in the bootstrap must survive as valid JSON.
  mkdir -p "$TMP/esc"
  run_hook "$TMP/esc"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "quotes in the bootstrap are escaped" -- jq -e . "$TMP/hook.out"
    context "$TMP/hook.out" > "$TMP/ctx4.txt"
    assert_contains "$TMP/ctx4.txt" 'says "invoke brainstorming"' "double quotes round-trip"
  else
    assert_contains "$TMP/hook.out" 'says \\"invoke brainstorming\\"' "double quotes are escaped"
  fi
}

# A config value is data, not a pattern: '/' and '&' are sed substitution
# metacharacters, and a value carrying them used to break the fill so the hook
# emitted an empty context with exit 0 — dropping the whole bootstrap.
test_hook_fills_config_value_with_metacharacters() {
  mkdir -p "$TMP/meta/.studio"
  printf '{ "engine": "godot4/mono&x" }\n' > "$TMP/meta/.studio/config.json"
  run_hook "$TMP/meta"
  context "$TMP/hook.out" > "$TMP/ctx5.txt"
  assert_contains "$TMP/ctx5.txt" "godot4/mono&x · 2D · GDScript · GUT" \
    "a value with sed metacharacters is filled in literally"
  assert_contains "$TMP/ctx5.txt" "stage skills own the workflow" "the rest of the bootstrap survives"
  assert_contains "$TMP/ctx5.txt" ".studio/STATE.md" "the state instruction survives"
  assert_not_contains "$TMP/hook.out" '"additionalContext":""' "the context is not emptied"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "output is still valid JSON" -- jq -e . "$TMP/hook.out"
  fi
}

# "STATE.md is written only through studio-state" was a sentence in a skill;
# the harness enforces it now.
test_guard_state_blocks_direct_writes() {
  status=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/p/game/.studio/STATE.md","old_string":"a","new_string":"b"}}' \
    | sh "$GUARD" > /dev/null 2> "$TMP/guard.err" || status=$?
  assert_eq "2" "$status" "guard blocks an Edit of .studio/STATE.md"
  assert_contains "$TMP/guard.err" "use studio-state" "guard says what to use instead"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"/p/game/.studio/ledger/dash.md","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "2" "$status" "guard blocks a Write of a feature ledger"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":".studio/STATE.md","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "2" "$status" "guard blocks a relative path too"
  status=0
  printf '{"tool_name":"Write","tool_input":{"file_path":"/p/game/.studio/config.json","content":"x"}}' \
    | sh "$GUARD" > /dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard lets config.json through"
  status=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"/p/game/src/player.gd"}}' | sh "$GUARD" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard lets ordinary files through"
  status=0
  printf '' | sh "$GUARD" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "guard exits 0 on empty input"
  printf '{"tool_input":{"file_path":"/p/.studio/stories/KAN-1.md"}}' | sh "$GUARD" 2> "$TMP/err"; st=$?
  assert_eq 2 "$st" "guard-state blocks a story state file"
}

# A wrong CLAUDE_PLUGIN_ROOT used to emit an empty context with exit 0, so the
# studio was silently not loaded.
test_hook_fails_without_bootstrap() {
  mkdir -p "$TMP/noboot-root/hooks" "$TMP/noboot"
  cp "$STUDIO_DIR/studio.json" "$TMP/noboot-root/"
  status=0
  ( cd "$TMP/noboot" && CLAUDE_PLUGIN_ROOT="$TMP/noboot-root" sh "$HOOK" ) > "$TMP/noboot.out" 2> "$TMP/noboot.err" || status=$?
  assert_eq "1" "$status" "hook exits 1 when bootstrap.md is missing"
  assert_contains "$TMP/noboot.err" "bootstrap.md" "hook names the missing file"
  assert_not_contains "$TMP/noboot.out" "additionalContext" "hook emits no empty context"
}

test_hook_strips_control_characters() {
  mkdir -p "$TMP/ctl/.studio"
  printf '{ "engine": "god\fot4" }\n' > "$TMP/ctl/.studio/config.json"
  run_hook "$TMP/ctl"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "a control character in config.json still yields valid JSON" -- jq -e . "$TMP/hook.out"
  fi
  assert_not_contains "$TMP/hook.out" '"additionalContext":""' "the context is not emptied"
  context "$TMP/hook.out" > "$TMP/ctx7.txt"
  assert_contains "$TMP/ctx7.txt" "godot4 · 2D" "the control character is dropped from the value"
}

test_hook_reports_stage() {
  mkdir -p "$TMP/staged"
  ( cd "$TMP/staged" && sh "$STUDIO_DIR/bin/studio-state" init >/dev/null && sh "$STUDIO_DIR/bin/studio-state" set stage plan )
  run_hook "$TMP/staged"
  context "$TMP/hook.out" > "$TMP/ctx8.txt"
  assert_contains "$TMP/ctx8.txt" "Studio state: stage plan" "context reports the current stage"
  mkdir -p "$TMP/unstaged"
  run_hook "$TMP/unstaged"
  context "$TMP/hook.out" > "$TMP/ctx9.txt"
  assert_not_contains "$TMP/ctx9.txt" "Studio state:" "no stage line without state"
  assert_eq "" "$(cat "$TMP/hook.err")" "the hook is silent on stderr without state"
}

# A stage value the old eight-stage pipeline wrote reads as idle, the way the
# router reports it.
test_hook_reports_old_stage() {
  mkdir -p "$TMP/oldstage/.studio/ledger"
  printf '# Studio State\n\nstage: retro\nspec: -\nplan: -\ntask: -\nlast_playtest: -\nmilestone: prototype\n\n## Ledger\n\n' \
    > "$TMP/oldstage/.studio/STATE.md"
  run_hook "$TMP/oldstage"
  context "$TMP/hook.out" > "$TMP/ctx10.txt"
  assert_contains "$TMP/ctx10.txt" "Studio state: stage idle (was retro, old pipeline)" "an old stage reads as idle"
  assert_eq "" "$(cat "$TMP/hook.err")" "the hook is silent on stderr for an old stage"
}

test_stage_guard_registered() {
  assert_contains "$STUDIO_DIR/hooks/hooks.json" '"UserPromptSubmit"' "hooks.json registers UserPromptSubmit"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/stage-guard.sh' \
    "hooks.json runs stage-guard.sh from the plugin root"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "hooks.json is still valid JSON" -- jq -e . "$STUDIO_DIR/hooks/hooks.json"
  fi
  assert_file "$STAGE_GUARD" "stage-guard.sh exists"
  assert_contains "$STAGE_GUARD" "trap 'exit 0' EXIT" "the guard turns every exit into exit 0"
  assert_not_contains "$STAGE_GUARD" '^[[:space:]]*set -[a-z]*u' "the guard never sets -u"
}

test_stage_guard_first_stage_silent() {
  : > "$TMP/t-empty.jsonl"
  run_guard "/game-dev:plan" "$TMP/t-empty.jsonl"
  assert_silent "a first stage in a session prints nothing"
}

test_stage_guard_warns_after_other_stage() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-plan.jsonl"
  assert_warns plan execute "execute typed after a typed plan warns"
  skill_line plan > "$TMP/t-plan-skill.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-plan-skill.jsonl"
  assert_warns plan execute "execute typed after a Skill-tool plan warns"
}

test_stage_guard_raw_prompt_shape() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard "/game-dev:execute --inline" "$TMP/t-plan.jsonl"
  assert_warns plan execute "a stage command with arguments warns"
  run_guard "   /game-dev:execute" "$TMP/t-plan.jsonl"
  assert_warns plan execute "leading spaces are ignored"
  run_guard "please run /game-dev:execute" "$TMP/t-plan.jsonl"
  assert_silent "a command after other text is not a typed stage"
  run_guard "/game-dev:executes" "$TMP/t-plan.jsonl"
  assert_silent "a longer name is not a stage"
}

test_stage_guard_envelope_prompt() {
  typed_line plan > "$TMP/t-plan.jsonl"
  run_guard '<command-message>game-dev:execute</command-message>\n<command-name>/game-dev:execute</command-name>' \
    "$TMP/t-plan.jsonl"
  assert_warns plan execute "the envelope shape warns the same way"
}

test_stage_guard_names_latest_prior_stage() {
  { typed_line brainstorm; typed_line plan; } > "$TMP/t-bp.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-bp.jsonl"
  assert_warns plan execute "the most recent different stage is named"
}

test_stage_guard_same_stage_silent() {
  typed_line execute > "$TMP/t-exec.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-exec.jsonl"
  assert_silent "the same stage again prints nothing"
}

test_stage_guard_ignores_mentions() {
  {
    printf '{"type":"user","message":{"content":"- `/game-dev:plan` — role- and verify-tagged tasks, producer scope cut, approval gate.\\n- `/game-dev:execute` — fresh role agent per task"}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Spec approved; the next command is `/game-dev:plan`. A pasted <command-message>game-dev:plan</command-message> is prose too."}]}}\n'
  } > "$TMP/t-prose.jsonl"
  run_guard "/game-dev:execute" "$TMP/t-prose.jsonl"
  assert_silent "prose mentions of a stage command do not count"
}

test_stage_guard_ordinary_prompt_silent() {
  typed_line execute > "$TMP/t-exec.jsonl"
  run_guard "keep going" "$TMP/t-exec.jsonl"
  assert_silent "an ordinary prompt prints nothing"
  run_guard "/game-dev:review" "$TMP/t-exec.jsonl"
  assert_silent "an on-demand command prints nothing"
  run_guard "/game-dev:studio" "$TMP/t-exec.jsonl"
  assert_silent "the router prints nothing"
}

test_stage_guard_scheduled_task_silent() {
  typed_line plan > "$TMP/t-plan.jsonl"
  printf '{"session_id":"s-1","transcript_path":"%s","hook_event_name":"UserPromptSubmit","prompt":"/game-dev:execute","source":"<scheduled-task name=\\"nightly\\">"}\n' \
    "$TMP/t-plan.jsonl" > "$TMP/guard-sched.in"
  guard_input "$TMP/guard-sched.in"
  assert_silent "a scheduled task is never warned"
}

test_stage_guard_no_transcript_silent() {
  printf '{"session_id":"s-1","hook_event_name":"UserPromptSubmit","prompt":"/game-dev:execute"}\n' > "$TMP/g-nokey.in"
  guard_input "$TMP/g-nokey.in"
  assert_silent "no transcript_path key prints nothing"
  run_guard "/game-dev:execute" "$TMP/no-such-transcript.jsonl"
  assert_silent "a missing transcript file prints nothing"
  : > "$TMP/g-empty.in"
  guard_input "$TMP/g-empty.in"
  assert_silent "an empty input prints nothing"
  printf 'not json /game-dev:execute\n' > "$TMP/g-text.in"
  guard_input "$TMP/g-text.in"
  assert_silent "a non-JSON input prints nothing"
}

# Review focus 3: a pretty-printed input (spaces after the colons, one key
# per line) whose transcript path holds a space still warns.
test_stage_guard_spaced_input() {
  mkdir -p "$TMP/a dir"
  typed_line plan > "$TMP/a dir/t.jsonl"
  printf '{\n  "session_id": "s-1",\n  "transcript_path": "%s",\n  "hook_event_name": "UserPromptSubmit",\n  "prompt": "/game-dev:execute"\n}\n' \
    "$TMP/a dir/t.jsonl" > "$TMP/g-pretty.in"
  guard_input "$TMP/g-pretty.in"
  assert_warns plan execute "a pretty-printed input with a spaced transcript path warns"
}

test_inbox_hook_registered() {
  J="$STUDIO_DIR/hooks/hooks.json"
  assert_contains "$J" '"matcher": "startup|compact"' "a SessionStart entry for startup and compact"
  assert_contains "$J" '"PostToolUse"' "a PostToolUse entry"
  assert_contains "$J" '"matcher": "\*"' "PostToolUse matches every tool"
  assert_eq 2 "$(grep -c 'hooks/operator-inbox.sh' "$J")" "operator-inbox.sh is registered twice"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "startup|compact" "$(jq -r '.hooks.SessionStart[] | select(.hooks[0].command | test("operator-inbox")) | .matcher' "$J")" "SessionStart: startup|compact"
    assert_eq "*" "$(jq -r '.hooks.PostToolUse[] | select(.hooks[0].command | test("operator-inbox")) | .matcher' "$J")" "PostToolUse: *"
  fi
}
test_inbox_hook_silent_outside_units() {
  for e in none tag dir; do
    ( unset STUDIO_UNIT_TAG STUDIO_RUN_DIR
      case "$e" in tag) STUDIO_UNIT_TAG=t; export STUDIO_UNIT_TAG ;; dir) STUDIO_RUN_DIR="$TMP"; export STUDIO_RUN_DIR ;; esac
      printf '{"hook_event_name":"PostToolUse"}' | sh "$INBOX" ) > "$TMP/ib.out" 2>&1; st=$?
    assert_eq 0 "$st" "exit 0 without both variables ($e)"
    assert_eq "" "$(cat "$TMP/ib.out")" "prints nothing without both variables ($e)"
  done
  # Reads no stdin: a writer that holds the pipe open for 3 s must not delay it.
  rm -f "$TMP/ib.fifo"; mkfifo "$TMP/ib.fifo"
  ( exec 3> "$TMP/ib.fifo"; sleep 3 ) & _w=$!
  t0="$(date +%s)"
  ( unset STUDIO_UNIT_TAG STUDIO_RUN_DIR; sh "$INBOX" < "$TMP/ib.fifo" ) > "$TMP/ib.out" 2>&1
  t1="$(date +%s)"; wait "$_w" 2>/dev/null
  assert_eq 1 "$([ $((t1 - t0)) -le 1 ] && echo 1 || echo 0)" "exits without reading stdin"
}

# ptu_in TOOL INPUT_JSON — a PreToolUse input for TOOL whose tool_input is
# INPUT_JSON, as Claude Code sends it.
ptu_in() {
  printf '{"session_id":"s-1","transcript_path":"%s/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}\n' \
    "$TMP" "$TMP" "$1" "$2"
}

# autopilot VALUE TOOL INPUT_JSON — run the autopilot guard with
# OMEGA_AUTOPILOT=VALUE ("-" unsets it). Asserts exit 0; stdout lands in
# $TMP/ap.out.
autopilot() {
  ptu_in "$2" "$3" > "$TMP/ap.in"
  _ast=0
  if [ "$1" = - ]; then
    env -u OMEGA_AUTOPILOT CLAUDE_PLUGIN_ROOT="$STUDIO_DIR" sh "$AUTOPILOT_GUARD" \
      < "$TMP/ap.in" > "$TMP/ap.out" 2> "$TMP/ap.err" || _ast=$?
  else
    OMEGA_AUTOPILOT="$1" CLAUDE_PLUGIN_ROOT="$STUDIO_DIR" sh "$AUTOPILOT_GUARD" \
      < "$TMP/ap.in" > "$TMP/ap.out" 2> "$TMP/ap.err" || _ast=$?
  fi
  assert_eq "0" "$_ast" "the autopilot guard exits 0"
}

# assert_denied MSG — stdout is one PreToolUse deny decision.
assert_denied() {
  if command -v jq >/dev/null 2>&1; then
    assert_eq "deny" "$(jq -r '.hookSpecificOutput.permissionDecision' "$TMP/ap.out" 2>/dev/null)" "$1"
    assert_eq "PreToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' "$TMP/ap.out" 2>/dev/null)" "$1 (event name)"
  else
    assert_contains "$TMP/ap.out" '"permissionDecision":"deny"' "$1"
  fi
}

# assert_allowed MSG — the autopilot guard printed nothing at all.
assert_allowed() {
  assert_eq "" "$(cat "$TMP/ap.out")" "$1"
}

test_autopilot_guard_registered() {
  assert_file "$AUTOPILOT_GUARD" "autopilot-guard.sh exists"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'CLAUDE_PLUGIN_ROOT}/hooks/autopilot-guard.sh' \
    "hooks.json runs autopilot-guard.sh from the plugin root"
  assert_contains "$STUDIO_DIR/hooks/hooks.json" 'Agent|Task|Bash|Monitor' \
    "the autopilot guard matches Agent, Task, Bash and Monitor"
  if command -v jq >/dev/null 2>&1; then
    assert_status 0 "hooks.json is valid JSON with the autopilot guard" -- jq -e . "$STUDIO_DIR/hooks/hooks.json"
  fi
}

# A headless -p unit ends when its turn ends, and print mode kills every
# background task 600 s later (phoenix mob-composer-parity, units 4 and 6,
# 2026-10-03). Under OMEGA_AUTOPILOT=1 nothing may run in the background.
test_autopilot_guard_denies_background_agent() {
  autopilot 1 Agent '{"description":"T4","subagent_type":"game-dev:gameplay-programmer","prompt":"do T4"}'
  assert_denied "an Agent call with no run_in_background (the async default) is denied"
  assert_contains "$TMP/ap.out" 'run_in_background: false' "the Agent reason says how to re-dispatch"
  autopilot 1 Agent '{"description":"T4","prompt":"do T4","run_in_background":true}'
  assert_denied "an Agent call with run_in_background true is denied"
  autopilot 1 Task '{"description":"T4","prompt":"do T4","run_in_background":true}'
  assert_denied "the older Task name with run_in_background true is denied"
  autopilot 1 Task '{"description":"T4","prompt":"do T4"}'
  assert_allowed "the older Task name with no field (a foreground default) is allowed"
}

test_autopilot_guard_allows_foreground_agent() {
  autopilot 1 Agent '{"description":"T4","prompt":"do T4","run_in_background":false}'
  assert_allowed "an Agent call with run_in_background false is allowed"
  autopilot 1 Agent '{
    "description": "T4",
    "run_in_background" : false,
    "prompt": "do T4"
  }'
  assert_allowed "a pretty-printed run_in_background false is allowed"
}

# A brief quotes the rule; a prompt that mentions the field is not the field.
test_autopilot_guard_reads_the_field_not_the_prompt() {
  autopilot 1 Agent '{"description":"T4","prompt":"never \"run_in_background\": false here"}'
  assert_denied "an escaped mention inside the prompt does not count as the field"
  autopilot 1 Bash '{"command":"echo \"run_in_background\": true"}'
  assert_allowed "an escaped mention inside a Bash command does not count as the field"
}

test_autopilot_guard_bash_and_monitor() {
  autopilot 1 Bash '{"command":"studio-test","timeout":5400000,"run_in_background":true}'
  assert_denied "a background Bash call is denied"
  assert_contains "$TMP/ap.out" 'foreground' "the Bash reason says to run it in the foreground"
  autopilot 1 Bash '{"command":"studio-test","timeout":5400000}'
  assert_allowed "a foreground Bash call is allowed"
  autopilot 1 Bash '{"command":"ls","run_in_background":false}'
  assert_allowed "an explicit foreground Bash call is allowed"
  autopilot 1 Monitor '{"command":"tail -f x"}'
  assert_denied "Monitor is denied: its events arrive only after the turn ends"
}

test_autopilot_guard_off_outside_autopilot() {
  autopilot - Agent '{"description":"T4","prompt":"do T4"}'
  assert_allowed "without OMEGA_AUTOPILOT a background Agent is allowed"
  autopilot 0 Bash '{"command":"x","run_in_background":true}'
  assert_allowed "OMEGA_AUTOPILOT=0 allows a background Bash"
  autopilot - Monitor '{"command":"tail -f x"}'
  assert_allowed "without OMEGA_AUTOPILOT Monitor is allowed"
  autopilot 1 Read '{"file_path":"/x"}'
  assert_allowed "another tool is never touched"
  _ast=0
  printf 'not json' | OMEGA_AUTOPILOT=1 sh "$AUTOPILOT_GUARD" > "$TMP/ap.out" 2>/dev/null || _ast=$?
  assert_eq "0" "$_ast" "a non-JSON input exits 0"
  assert_allowed "a non-JSON input prints nothing"
}

test_inbox_hook_skips_storyless_manifest_unit() {
  ib_fresh manifest; put_msg "$IS" 1 story "use the bus"
  inbox_run none "$PTU"
  assert_eq 0 "$IB_ST" "exit 0"
  assert_eq "" "$(cat "$TMP/ib.out")" "a manifest unit with no STUDIO_STORY (the final step) gets nothing"
  assert_file "$IS/1.msg" "the message stays pending"
  inbox_run none "$SS_START"; assert_eq "" "$(cat "$TMP/ib.out")" "nor at startup"
}
test_inbox_hook_skips_subagent() {
  ib_fresh single; put_msg "$IS" 1 story "use the bus"
  inbox_run none "$PTU_SUB"
  assert_eq "" "$(cat "$TMP/ib.out")" "a subagent's tool call delivers nothing"
  assert_file "$IS/1.msg" "and claims nothing"
  inbox_run none "$SS_CLEAR"
  assert_eq "" "$(cat "$TMP/ib.out")" "SessionStart clear delivers nothing"
  assert_eq 0 "$(delivered)" "delivered() is a single 0 when there is no event log"
  : > "$IR/events.jsonl"
  assert_eq 0 "$(delivered)" "and a single 0 when the log has no match"
}
test_inbox_agent_id_top_level_only() {
  ib_fresh single; put_msg "$IS" 1 story "use the bus"
  _nested='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"mcp__x","tool_input":{"agent_id":"in"},"tool_response":{"agent_id":"a9","list":[{"agent_id":"b"}]}}'
  inbox_run none "$_nested"
  assert_contains "$TMP/ib.out" '\[1, story\] use the bus' "an agent_id nested in tool_input / tool_response does not skip delivery"
  ib_fresh single; put_msg "$IS" 1 story "use the bus"
  _late='{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":"x \"agent_id\": y"},"agent_id":"a1"}'
  inbox_run none "$_late"
  assert_eq "" "$(cat "$TMP/ib.out")" "a top-level agent_id after tool_response still marks a subagent"
  assert_file "$IS/1.msg" "and claims nothing"
}
test_inbox_session_start_plain() {
  ib_fresh single; put_msg "$IS" 1 story "Use the EventBus autoload."
  inbox_run S9 "$SS_START"
  assert_eq 0 "$IB_ST" "exit 0"
  assert_eq "OPERATOR MESSAGES — from the user, for story - (overnight run)." "$(sed -n 1p "$TMP/ib.out")" "the header (a single-plan run's story is -, whatever STUDIO_STORY says)"
  assert_contains "$TMP/ib.out" "^\[1, story\] Use the EventBus autoload\.$" "the message line"
  assert_contains "$TMP/ib.out" "^  → Follow this for the rest of the story\. Record it in the feature checkout's$" "the story instruction"
  assert_contains "$TMP/ib.out" "after §0 step (c), not merely after" "names the recording point"
  assert_contains "$TMP/ib.out" "^    studio-state ledger 'Directive 1: Use the EventBus autoload\.'$" "the command, single-quoted"
  assert_contains "$TMP/ib.out" "^If a message conflicts with the approved plan or spec, follow it for how you$" "the conflict rule"
  assert_contains "$TMP/ib.out" "^work; for what you build, record a \`Stop:\` with the conflict instead\.$" "its second line"
  assert_not_contains "$TMP/ib.out" "^{" "plain text, not JSON"
  assert_file "$IS/delivered/tagA/1.msg" "claimed into delivered/<tag>/"
  assert_contains "$IR/events.jsonl" '"event":"message_delivered","story":"-","id":1,"scope":"story","unit":"tagA","via":"session_start"}$' "a message_delivered event"
  assert_not_contains "$IR/events.jsonl" "EventBus" "no message text in the log"
}
test_inbox_post_tool_use_json() {
  ib_fresh manifest; put_msg "$IS" 2 unit "Skip the polish step."
  inbox_run S1 "$PTU"
  assert_contains "$TMP/ib.out" '^{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"OPERATOR MESSAGES — from the user, for story S1 (overnight run)\.\\n\[2, unit\] Skip the polish step\.\\n  → Follow this in this unit only\. Do not record it\.\\n' "PostToolUse: additionalContext JSON, one line"
  assert_eq 1 "$(wc -l < "$TMP/ib.out" | tr -d ' ')" "one line of output"
  if command -v jq >/dev/null 2>&1; then
    assert_eq "[2, unit] Skip the polish step." "$(jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" | sed -n 2p)" "valid JSON; the context's second line"
  fi
  assert_contains "$IR/events.jsonl" '"scope":"unit","unit":"tagA","via":"tool_call"}$' "via tool_call"
  printf '{\n  "session_id": "s",\n  "hook_event_name": "PostToolUse"\n}\n' > "$TMP/ptu-ml.json"
  put_msg "$IS" 3 story "three"
  inbox_run S1 "$(cat "$TMP/ptu-ml.json")"
  assert_contains "$TMP/ib.out" '\[3, story\] three' "pretty-printed hook input is read too"
}
# No-jq stand-in for `jq -r .hookSpecificOutput.additionalContext`: take the string after
# "additionalContext":" up to the closing "}} and decode its JSON escapes (sh/awk only).
ctx_decode() {
  awk '{
    key = "\"additionalContext\":\""
    i = index($0, key)
    if (!i) next
    s = substr($0, i + length(key))
    sub(/"\}\}[ \t]*$/, "", s)
    out = ""; n = length(s)
    for (k = 1; k <= n; k++) {
      c = substr(s, k, 1)
      if (c == "\\" && k < n) {
        k++; c = substr(s, k, 1)
        if (c == "n") c = "\n"; else if (c == "t") c = "\t"; else if (c == "r") c = "\r"
      }
      out = out c
    }
    print out
  }' "$1"
}
test_inbox_claim_moves_to_delivered() {
  ib_fresh single
  put_msg "$IS" 10 story ten; put_msg "$IS" 2 story two; put_msg "$IS" 1 retire "retire directive 7" 7
  : > "$IS/.say.123"
  inbox_run none "$PTU"
  if command -v jq >/dev/null 2>&1; then jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" > "$TMP/ib.ctx"; else ctx_decode "$TMP/ib.out" > "$TMP/ib.ctx"; fi
  l1="$(grep -n '^\[retire 7\]' "$TMP/ib.ctx" | cut -d: -f1)"; l2="$(grep -n '^\[2, story\]' "$TMP/ib.ctx" | cut -d: -f1)"; l10="$(grep -n '^\[10, story\]' "$TMP/ib.ctx" | cut -d: -f1)"
  assert_eq 1 "$([ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l10" ] && [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l10" ] && echo 1 || echo 0)" "oldest (lowest id) first: 1, 2, 10"
  assert_contains "$TMP/ib.ctx" "^  → Stop following directive 7\. Record, the same way:$" "the retire instruction"
  assert_contains "$TMP/ib.ctx" "^    studio-state ledger 'Directive 7 retired'$" "the retire command"
  for i in 1 2 10; do assert_file "$IS/delivered/tagA/$i.msg" "message $i claimed"; assert_missing "$IS/$i.msg" "message $i no longer pending"; done
  assert_file "$IS/.say.123" "a verb's temp file is never claimed"
  inbox_run none "$PTU"
  assert_eq "" "$(cat "$TMP/ib.out")" "nothing pending: the next tool call prints nothing"
  put_msg "$IS" 11 story eleven
  inbox_run none "$PTU"
  assert_contains "$TMP/ib.out" '\[11, story\] eleven' "a new message arrives on the next tool call"
  assert_not_contains "$TMP/ib.out" '\[2, story\]' "and only it"
  assert_eq 4 "$(delivered)" "one event per claim"
}
test_inbox_one_claim_under_two_hooks() {
  ib_fresh single
  i=1; while [ "$i" -le 20 ]; do put_msg "$IS" "$i" story "m$i"; i=$((i + 1)); done
  inbox_run none "$PTU" "$TMP/ib.a" & _a=$!
  inbox_run none "$PTU" "$TMP/ib.b" & _b=$!
  wait "$_a"; wait "$_b"
  cat "$TMP/ib.a" "$TMP/ib.b" | grep -o '\[[0-9]*, story\]' | sed 's/^\[\([0-9]*\),.*/\1/' | sort -n > "$TMP/ib.ids"
  assert_eq 20 "$(wc -l < "$TMP/ib.ids" | tr -d ' ')" "20 deliveries between the two hooks"
  assert_eq 20 "$(sort -u "$TMP/ib.ids" | wc -l | tr -d ' ')" "each message delivered exactly once"
  assert_eq 20 "$(delivered)" "20 message_delivered events"
  assert_eq 20 "$(ls "$IS/delivered/tagA" | wc -l | tr -d ' ')" "every message claimed"
  assert_eq "" "$(ls "$IS" | grep '\.msg$')" "none left pending"
}
test_inbox_compact_reshows() {
  ib_fresh single; put_msg "$IS" 1 story one; put_msg "$IS" 2 unit two
  inbox_run none "$SS_START"
  put_msg "$IS" 3 story three
  inbox_run none "$SS_COMPACT"
  assert_eq "OPERATOR MESSAGES — reminder: already delivered in this unit, from the user, for story - (overnight run)." \
    "$(sed -n 1p "$TMP/ib.out")" "the reminder header"
  assert_contains "$TMP/ib.out" '^\[1, story\] one$' "the story message again"
  assert_contains "$TMP/ib.out" '^\[2, unit\] two$' "the unit message again"
  assert_not_contains "$TMP/ib.out" '\[3, story\]' "nothing new is claimed on compact"
  assert_file "$IS/3.msg" "message 3 is still pending"
  assert_eq 2 "$(delivered)" "a re-show writes no event"
  TG=tagB; inbox_run none "$SS_COMPACT"; unset TG
  assert_eq "" "$(cat "$TMP/ib.out")" "another unit's compact re-shows nothing of this unit's"
}
test_inbox_escapes_quotes_dollar_backticks_newlines() {
  ib_fresh single
  t="it's \"q\" \$HOME \`x\` a\\b$(printf '\t')c"
  put_msg "$IS" 1 story "$t
b"
  inbox_run none "$SS_START"
  cmd="$(sed -n 's/^    studio-state ledger //p' "$TMP/ib.out" | head -n 1)"
  eval "set -- $cmd"
  assert_eq "Directive 1: $t b" "$1" "the suggested command round-trips the text exactly, its newline folded to a space"
  assert_eq "[1, story] $t b" "$(sed -n '/^\[1, story\]/p' "$TMP/ib.out")" "the message line (backslash and tab kept), newline folded"
  ib_fresh single; put_msg "$IS" 1 story "$t
b"
  inbox_run none "$PTU"
  assert_contains "$TMP/ib.out" 'a\\\\b\\tc b' "PostToolUse: the backslash is doubled and the tab is \\t in the raw JSON"
  ib_fresh single; put_msg "$IS" 1 story "a$(printf '\001')b"
  inbox_run none "$PTU"
  assert_contains "$TMP/ib.out" '\[1, story\] ab' "PostToolUse: a control byte is dropped"
  ib_fresh single; put_msg "$IS" 1 story "$t
b"
  inbox_run none "$PTU"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hookSpecificOutput.additionalContext' "$TMP/ib.out" > "$TMP/ib.ctx"
    assert_eq 0 "$?" "the JSON parses"
    cmd="$(sed -n 's/^    studio-state ledger //p' "$TMP/ib.ctx" | head -n 1)"
    eval "set -- $cmd"
    assert_eq "Directive 1: $t b" "$1" "the same through additionalContext"
  fi
}
test_inbox_lost_claim_race_not_logged() {
  # a stub mv lets a rival hook claim the message first (it moves it, then fails)
  ib_fresh single; put_msg "$IS" 1 story one
  mkdir -p "$TMP/mvbin"
  printf '#!/bin/sh\n/bin/mv "$@"; exit 1\n' > "$TMP/mvbin/mv"; chmod +x "$TMP/mvbin/mv"
  _mv_path="$PATH"; PATH="$TMP/mvbin:$PATH"; inbox_run none "$PTU"; PATH="$_mv_path"
  assert_eq 0 "$IB_ST" "a lost claim exits 0"
  assert_not_contains "$IR/hook.log" "no scope header" "a lost claim is not logged as a missing scope"
  # the file is gone before the scope is read (the hook's list saw it, the rival took it)
  ib_fresh single; put_msg "$IS" 1 story one
  printf '#!/bin/sh\ncase "$*" in *1.msg*) /bin/rm -f "%s/1.msg" ;; esac\nexec /usr/bin/sed "$@"\n' "$IS" > "$TMP/mvbin/sed"; chmod +x "$TMP/mvbin/sed"
  rm -f "$TMP/mvbin/mv"
  if [ -x /usr/bin/sed ]; then
    _mv_path="$PATH"; PATH="$TMP/mvbin:$PATH"; inbox_run none "$PTU"; PATH="$_mv_path"
    assert_not_contains "$IR/hook.log" "no scope header" "a message claimed before its scope is read is not malformed"
  fi
}
test_inbox_invalid_utf8_body_whole() {
  _loc="$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1)"
  [ -n "$_loc" ] || return 0
  ib_fresh single; put_msg "$IS" 1 story "bad $(printf '\377\376') bytes here"
  export LC_ALL="$_loc"; inbox_run none "$SS_START"; unset LC_ALL
  assert_eq "bad $(printf '\377\376') bytes here" "$(LC_ALL=C sed -n 's/^\[1, story\] //p' "$TMP/ib.out" | LC_ALL=C head -n 1)" "an invalid UTF-8 body is delivered whole, not cut at the bad byte"
  assert_eq 1 "$(LC_ALL=C grep -c "studio-state ledger 'Directive 1: bad .* bytes here'" "$TMP/ib.out")" "and so is the suggested ledger command"
}
test_inbox_hook_never_fails() {
  ( STUDIO_UNIT_TAG=t; STUDIO_RUN_DIR="$TMP/no-such-run"; export STUDIO_UNIT_TAG STUDIO_RUN_DIR
    printf '%s' "$PTU" | sh "$INBOX" ) > "$TMP/ib.out" 2>&1; st=$?
  assert_eq 0 "$st" "a missing run dir: exit 0"
  assert_eq "" "$(cat "$TMP/ib.out")" "and nothing printed"
  ib_fresh single; put_msg "$IS" 1 story x
  inbox_run none 'not json at all'
  assert_eq 0 "$IB_ST" "garbage input: exit 0"; assert_eq "" "$(cat "$TMP/ib.out")" "nothing printed"
  printf 'garbage\n' > "$IS/2.msg"
  inbox_run none "$PTU"
  assert_eq 0 "$IB_ST" "a message with no header: exit 0"
  assert_file "$IS/2.msg" "a malformed message is left pending"
  assert_contains "$IR/hook.log" "2.msg" "and named in hook.log"
  inbox_run none "$PTU"; inbox_run none "$PTU"
  assert_eq 1 "$(grep -c '2\.msg has no scope header' "$IR/hook.log")" "a malformed message is logged once, not on every tool call"
  if [ "$(id -u)" != 0 ]; then
    ib_fresh single; put_msg "$IS" 1 story x; chmod 555 "$IS"
    inbox_run none "$PTU"
    assert_eq 0 "$IB_ST" "an unwritable inbox: exit 0"
    assert_eq "" "$(cat "$TMP/ib.out")" "nothing claimed, nothing printed"
    chmod 755 "$IS"
  fi
}

PROBE="$REPO_ROOT/tests/probes/hook_delivery_probe.sh"

# AC31: the probe parses, refuses bad usage with 2, records nothing without a
# pass, and is never part of the gate.
test_inbox_probe_usage() {
  assert_file "$PROBE" "the probe exists"
  assert_eq 1 "$([ -x "$PROBE" ] && echo 1 || echo 0)" "the probe is executable"
  assert_status 0 "the probe parses" -- sh -n "$PROBE"
  mkdir -p "$TMP/ph"
  st=0; HOME="$TMP/ph" sh "$PROBE" a b >/dev/null 2>&1 || st=$?
  assert_eq 2 "$st" "two arguments: usage, exit 2"
  st=0; HOME="$TMP/ph" sh "$PROBE" --help >/dev/null 2>&1 || st=$?
  assert_eq 2 "$st" "an option for a launcher: usage, exit 2"
  st=0; HOME="$TMP/ph" sh "$PROBE" "$TMP/no-such-claude" >/dev/null 2>"$TMP/ph.err" || st=$?
  assert_eq 2 "$st" "a missing launcher: exit 2"
  assert_contains "$TMP/ph.err" "not on PATH" "it names the missing launcher"
  assert_missing "$TMP/ph/.claude-gamedev" "nothing is recorded without a pass"
  assert_not_contains "$REPO_ROOT/tests/run_all.sh" "probes" "run_all.sh never runs a probe (it spends model calls)"
}

# fake_claude FILE — a launcher that runs the --settings hooks the way the
# spike saw Claude Code run them, and answers with stream-json. FAKE_MODE:
# ok | no_ss (the model never saw the SessionStart marker) | no_agent_id
# (the subagent's hook input lacks agent_id).
fake_claude() {
  cat > "$1" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && { echo "9.9.9 (Fake Code)"; exit 0; }
P=""; S=""
while [ "$#" -gt 0 ]; do
  case "$1" in -p) P="$2"; shift 2 ;; --settings) S="$2"; shift 2 ;; *) shift ;; esac
done
hook() { sed -n "s/.*\"$1\".*\"command\": \"\\([^\"]*\\)\".*/\\1/p" "$S" | head -n 1; }
SS="$(hook SessionStart)"; PT="$(hook PostToolUse)"
ssm="$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | eval "$SS" | sed 's/.*: //')"
case "$P" in
  *probe-main*)
    echo '{"tool_name":"Bash","tool_input":{"command":"echo probe-main"}}' | eval "$PT" >/dev/null
    if [ "${FAKE_MODE:-ok}" = no_agent_id ]; then a=''; else a='"agent_id":"a3cc","agent_type":"general-purpose",'; fi
    echo "{${a}\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo probe-sub\"}}" | eval "$PT" >/dev/null
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo probe-main"}}]}}'
    echo '{"type":"result","subtype":"success","result":"OK"}' ;;
  *)
    ptm="$(echo '{"tool_name":"Bash","tool_input":{"command":"echo probe-a"}}' | eval "$PT" | sed 's/.*Tool marker: \([A-Za-z0-9_]*\).*/\1/')"
    [ "${FAKE_MODE:-ok}" = no_ss ] && ssm=NONE
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo probe-a"}}]}}'
    echo "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"SS=$ssm PT=$ptm\"}" ;;
esac
EOF
  chmod 755 "$1"
}

# AC31: the probe's own logic, on a fake launcher — PASS records the version
# and the date; each failed check is exit 1 and records nothing.
test_inbox_probe_fake_launcher() {
  fake_claude "$TMP/fake-claude"
  mkdir -p "$TMP/pf-home"
  st=0; HOME="$TMP/pf-home" PROBE_DIR="$TMP/pf-ok" sh "$PROBE" "$TMP/fake-claude" > "$TMP/pf.out" 2>&1 || st=$?
  assert_eq 0 "$st" "all three checks pass: exit 0"
  assert_contains "$TMP/pf.out" "^PASS$" "it says PASS"
  R="$TMP/pf-home/.claude-gamedev/probes/hook_delivery"
  assert_eq "9.9.9 (Fake Code)" "$(sed -n 1p "$R" 2>/dev/null)" "line 1: the launcher's version"
  assert_eq "$(date -u +%Y-%m-%d)" "$(sed -n 2p "$R" 2>/dev/null)" "line 2: the UTC date"
  for mode in no_ss no_agent_id; do
    rm -f "$R"
    st=0; FAKE_MODE=$mode HOME="$TMP/pf-home" PROBE_DIR="$TMP/pf-$mode" sh "$PROBE" "$TMP/fake-claude" > "$TMP/pf.out" 2>&1 || st=$?
    assert_eq 1 "$st" "$mode: exit 1"
    assert_contains "$TMP/pf.out" "^FAIL$" "$mode: it says FAIL"
    assert_missing "$R" "$mode: nothing is recorded"
  done
}

run_tests test_hook_files test_hook_output_shape test_hook_defaults_from_studio_json \
  test_hook_reads_project_config test_hook_partial_config_falls_back test_hook_escapes_json \
  test_hook_fills_config_value_with_metacharacters test_guard_state_blocks_direct_writes \
  test_hook_fails_without_bootstrap test_hook_strips_control_characters test_hook_reports_stage \
  test_hook_reports_old_stage test_stage_guard_registered test_stage_guard_first_stage_silent \
  test_stage_guard_warns_after_other_stage test_stage_guard_raw_prompt_shape \
  test_stage_guard_envelope_prompt test_stage_guard_names_latest_prior_stage \
  test_stage_guard_same_stage_silent test_stage_guard_ignores_mentions \
  test_stage_guard_ordinary_prompt_silent test_stage_guard_scheduled_task_silent \
  test_stage_guard_no_transcript_silent test_stage_guard_spaced_input \
  test_inbox_hook_registered test_inbox_hook_silent_outside_units \
  test_autopilot_guard_registered test_autopilot_guard_denies_background_agent \
  test_autopilot_guard_allows_foreground_agent test_autopilot_guard_reads_the_field_not_the_prompt \
  test_autopilot_guard_bash_and_monitor test_autopilot_guard_off_outside_autopilot \
  test_inbox_hook_skips_storyless_manifest_unit test_inbox_hook_skips_subagent test_inbox_agent_id_top_level_only \
  test_inbox_session_start_plain test_inbox_post_tool_use_json test_inbox_claim_moves_to_delivered \
  test_inbox_one_claim_under_two_hooks test_inbox_compact_reshows \
  test_inbox_escapes_quotes_dollar_backticks_newlines test_inbox_hook_never_fails test_inbox_lost_claim_race_not_logged test_inbox_invalid_utf8_body_whole \
  test_inbox_probe_usage test_inbox_probe_fake_launcher

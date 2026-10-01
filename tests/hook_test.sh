#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO_DIR="$REPO_ROOT/studios/game-dev"
HOOK="$STUDIO_DIR/hooks/session-start.sh"
GUARD="$STUDIO_DIR/hooks/guard-state.sh"
STAGE_GUARD="$STUDIO_DIR/hooks/stage-guard.sh"
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

run_tests test_hook_files test_hook_output_shape test_hook_defaults_from_studio_json \
  test_hook_reads_project_config test_hook_partial_config_falls_back test_hook_escapes_json \
  test_hook_fills_config_value_with_metacharacters test_guard_state_blocks_direct_writes \
  test_hook_fails_without_bootstrap test_hook_strips_control_characters test_hook_reports_stage \
  test_hook_reports_old_stage test_stage_guard_registered test_stage_guard_first_stage_silent \
  test_stage_guard_warns_after_other_stage test_stage_guard_raw_prompt_shape \
  test_stage_guard_envelope_prompt test_stage_guard_names_latest_prior_stage \
  test_stage_guard_same_stage_silent test_stage_guard_ignores_mentions \
  test_stage_guard_ordinary_prompt_silent test_stage_guard_scheduled_task_silent \
  test_stage_guard_no_transcript_silent test_stage_guard_spaced_input

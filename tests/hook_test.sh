#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO_DIR="$REPO_ROOT/studios/game-dev"
HOOK="$STUDIO_DIR/hooks/session-start.sh"
GUARD="$STUDIO_DIR/hooks/guard-state.sh"
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

run_tests test_hook_files test_hook_output_shape test_hook_defaults_from_studio_json \
  test_hook_reads_project_config test_hook_partial_config_falls_back test_hook_escapes_json \
  test_hook_fills_config_value_with_metacharacters test_guard_state_blocks_direct_writes \
  test_hook_fails_without_bootstrap test_hook_strips_control_characters test_hook_reports_stage

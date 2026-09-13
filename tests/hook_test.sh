#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"

STUDIO_DIR="$REPO_ROOT/studios/game-dev"
HOOK="$STUDIO_DIR/hooks/session-start.sh"
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
  assert_contains "$STUDIO_DIR/hooks/bootstrap.md" "/game-dev:studio" "bootstrap lists the router"
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

run_tests test_hook_files test_hook_output_shape test_hook_defaults_from_studio_json \
  test_hook_reads_project_config test_hook_partial_config_falls_back test_hook_escapes_json \
  test_hook_fills_config_value_with_metacharacters

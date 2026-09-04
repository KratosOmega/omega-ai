#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_json_field() {
  cat > "$TMP/p.json" <<'JSON'
{
  "name": "game-dev",
  "description": "2D game development AI",
  "target": "~/.claude-gamedev",
  "shim": "claude-gd"
}
JSON
  assert_eq "game-dev" "$(json_field "$TMP/p.json" name)" "reads name"
  assert_eq "~/.claude-gamedev" "$(json_field "$TMP/p.json" target)" "reads target"
  assert_eq "claude-gd" "$(json_field "$TMP/p.json" shim)" "reads shim"
  assert_eq "" "$(json_field "$TMP/p.json" nope)" "absent key is empty"
}

test_expand_path() {
  assert_eq "$HOME/.claude-gamedev" "$(expand_path '~/.claude-gamedev')" "expands leading tilde"
  assert_eq "$HOME" "$(expand_path '~')" "expands bare tilde"
  assert_eq "/tmp/x" "$(expand_path '/tmp/x')" "leaves absolute path alone"
}

test_guard_target_rejects() {
  assert_status 1 "rejects home" -- guard_target "$HOME" "$REPO_ROOT"
  assert_status 1 "rejects ~/.claude" -- guard_target "$HOME/.claude" "$REPO_ROOT"
  assert_status 1 "rejects ~/.claude with slash" -- guard_target "$HOME/.claude/" "$REPO_ROOT"
  assert_status 1 "rejects empty target" -- guard_target "" "$REPO_ROOT"
  assert_status 1 "rejects in-repo target" -- guard_target "$REPO_ROOT/profiles" "$REPO_ROOT"
}

test_guard_target_accepts() {
  assert_status 0 "accepts private config root" -- guard_target "$HOME/.claude-gamedev" "$REPO_ROOT"
  assert_status 0 "accepts temp dir" -- guard_target "$TMP/cfg" "$REPO_ROOT"
}

test_run_dry() {
  DRY_RUN=1 run touch "$TMP/should-not-exist"
  assert_missing "$TMP/should-not-exist" "dry run creates nothing"
  DRY_RUN=0 run touch "$TMP/should-exist"
  assert_file "$TMP/should-exist" "wet run creates the file"
}

run_tests test_json_field test_expand_path test_guard_target_rejects test_guard_target_accepts test_run_dry

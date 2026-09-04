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

# A shim directory goes through the same guard, so a descendant of ~/.claude
# must be refused too — not just the exact path.
test_guard_target_rejects_descendants_of_dot_claude() {
  assert_status 1 "rejects a child of ~/.claude" -- guard_target "$HOME/.claude/bin" "$REPO_ROOT"
  assert_status 1 "rejects a deep descendant of ~/.claude" -- \
    guard_target "$HOME/.claude/plugins/repos/x" "$REPO_ROOT"
  assert_status 1 "rejects a child of ~/.claude with a trailing slash" -- \
    guard_target "$HOME/.claude/bin/" "$REPO_ROOT"
}

test_guard_target_accepts() {
  assert_status 0 "accepts private config root" -- guard_target "$HOME/.claude-gamedev" "$REPO_ROOT"
  assert_status 0 "accepts temp dir" -- guard_target "$TMP/cfg" "$REPO_ROOT"
  # The ~/.claude prefix must not swallow sibling roots that merely start alike.
  assert_status 0 "accepts ~/.claude-general" -- guard_target "$HOME/.claude-general" "$REPO_ROOT"
  assert_status 0 "accepts a child of a sibling root" -- \
    guard_target "$HOME/.claude-gamedev/bin" "$REPO_ROOT"
}

test_need_value() {
  assert_status 1 "rejects an empty option value" -- need_value --target ""
  assert_status 1 "rejects an absent option value" -- need_value --target
  assert_status 0 "accepts a real option value" -- need_value --target /tmp/x
  out="$(need_value --target "" 2>&1 || true)"
  printf '%s\n' "$out" > "$TMP/need.out"
  assert_contains "$TMP/need.out" "missing value for --target" "names the flag it is missing"
}

test_resolve_profile_target() {
  mkdir -p "$TMP/profiles/good" "$TMP/profiles/bare"
  cat > "$TMP/profiles/good/profile.json" <<'JSON'
{ "name": "good", "target": "~/.claude-good", "shim": "claude-good" }
JSON
  assert_eq "$HOME/.claude-good" "$(resolve_profile_target "$TMP/profiles/good" "")" \
    "resolves the target from profile.json"
  assert_eq "$TMP/override" "$(resolve_profile_target "$TMP/profiles/good" "$TMP/override")" \
    "an override wins over profile.json"
  assert_eq "$HOME/ovr" "$(resolve_profile_target "$TMP/profiles/good" '~/ovr')" \
    "an override is tilde-expanded"
  assert_status 1 "rejects an unknown profile directory" -- \
    resolve_profile_target "$TMP/profiles/absent" ""
  assert_status 1 "rejects a profile with no profile.json" -- \
    resolve_profile_target "$TMP/profiles/bare" ""
  printf '{ "name": "empty" }\n' > "$TMP/profiles/bare/profile.json"
  assert_status 1 "rejects a profile.json with no target" -- \
    resolve_profile_target "$TMP/profiles/bare" ""
}

test_run_dry() {
  DRY_RUN=1 run touch "$TMP/should-not-exist"
  assert_missing "$TMP/should-not-exist" "dry run creates nothing"
  DRY_RUN=0 run touch "$TMP/should-exist"
  assert_file "$TMP/should-exist" "wet run creates the file"
}

run_tests test_json_field test_expand_path test_guard_target_rejects \
  test_guard_target_rejects_descendants_of_dot_claude test_guard_target_accepts \
  test_need_value test_resolve_profile_target test_run_dry

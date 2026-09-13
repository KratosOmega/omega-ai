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
  assert_status 1 "rejects in-repo target" -- guard_target "$REPO_ROOT/studios" "$REPO_ROOT"
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

test_resolve_studio_target() {
  mkdir -p "$TMP/studios/good" "$TMP/studios/bare"
  cat > "$TMP/studios/good/studio.json" <<'JSON'
{ "name": "good", "target": "~/.claude-good", "shim": "claude-good" }
JSON
  assert_eq "$HOME/.claude-good" "$(resolve_studio_target "$TMP/studios/good" "")" \
    "resolves the target from studio.json"
  assert_eq "$TMP/override" "$(resolve_studio_target "$TMP/studios/good" "$TMP/override")" \
    "an override wins over studio.json"
  assert_eq "$HOME/ovr" "$(resolve_studio_target "$TMP/studios/good" '~/ovr')" \
    "an override is tilde-expanded"
  assert_status 1 "rejects an unknown studio directory" -- \
    resolve_studio_target "$TMP/studios/absent" ""
  assert_status 1 "rejects a studio with no studio.json" -- \
    resolve_studio_target "$TMP/studios/bare" ""
  printf '{ "name": "empty" }\n' > "$TMP/studios/bare/studio.json"
  assert_status 1 "rejects a studio.json with no target" -- \
    resolve_studio_target "$TMP/studios/bare" ""
}

test_requires_of() {
  cat > "$TMP/requires.txt" <<'REQ'
plugin superpowers@claude-plugins-official
plugin godot-prompter@skillsmith
skill  superpowers:test-driven-development
agent  godot-prompter:godot-csharp-engineer
REQ
  assert_eq "superpowers@claude-plugins-official
godot-prompter@skillsmith" "$(requires_of "$TMP/requires.txt" plugin)" "lists the plugin lines"
  assert_eq "superpowers:test-driven-development" "$(requires_of "$TMP/requires.txt" skill)" \
    "lists the skill lines"
  assert_eq "godot-prompter:godot-csharp-engineer" "$(requires_of "$TMP/requires.txt" agent)" \
    "lists the agent lines"
  assert_eq "" "$(requires_of "$TMP/absent.txt" plugin)" "a missing file lists nothing"
}

test_run_dry() {
  DRY_RUN=1 run touch "$TMP/should-not-exist"
  assert_missing "$TMP/should-not-exist" "dry run creates nothing"
  DRY_RUN=0 run touch "$TMP/should-exist"
  assert_file "$TMP/should-exist" "wet run creates the file"
}

# --- Path canonicalization: a '..' spelling must fold before anything trusts it.
# canon_path must work on paths that do not exist yet, because the install
# target normally does not. Nothing here may be created on disk.
test_canon_path() {
  mkdir -p "$TMP/canon/a/b/c"
  ln -s "$TMP/canon/a" "$TMP/canon/link"
  C="$(cd -P "$TMP/canon" && pwd -P)"

  assert_eq "$C/a/b" "$(canon_path "$TMP/canon/a/x/../b")" "resolves .. in the middle"
  assert_eq "$C/a" "$(canon_path "$TMP/canon/a/b/..")" "resolves .. at the end"
  assert_eq "$C" "$(canon_path "$TMP/canon/a/b/c/../../..")" "resolves several .. in a row"
  assert_eq "$C/a/b" "$(canon_path "$TMP/canon/./a/./b")" "drops . segments"
  assert_eq "$C/a/b" "$(canon_path "$C/a/b")" "leaves an already-canonical path alone"
  assert_eq "$C/a/b" "$(cd "$TMP/canon" && canon_path "a/b")" "resolves a relative path against the cwd"
  assert_eq "$C/nope/x" "$(canon_path "$TMP/canon/nope/deeper/../x")" \
    "resolves a path whose ancestor does not exist"
  assert_eq "$C/a/b" "$(canon_path "$TMP/canon/link/b")" "resolves a symlinked ancestor"
  assert_eq "$C/.claude" "$(canon_path "$TMP/canon/x/../.claude")" \
    "folds the ~/.claude traversal spelling"
  assert_missing "$TMP/canon/nope" "canon_path creates nothing"
}

run_tests test_json_field test_expand_path test_canon_path test_guard_target_rejects \
  test_guard_target_rejects_descendants_of_dot_claude test_guard_target_accepts \
  test_need_value test_resolve_studio_target test_requires_of test_run_dry

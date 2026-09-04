#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_profile_contract() {
  for dir in "$REPO_ROOT"/profiles/*/; do
    name="$(basename "$dir")"
    assert_file "$dir/profile.json" "$name has profile.json"
    assert_file "$dir/CLAUDE.md" "$name has CLAUDE.md"
    assert_file "$dir/settings.json" "$name has settings.json"
    assert_eq "$name" "$(json_field "$dir/profile.json" name)" "$name profile.json name matches directory"
    target="$(json_field "$dir/profile.json" target)"
    shim="$(json_field "$dir/profile.json" shim)"
    assert_status 0 "$name declares a safe target" -- guard_target "$(expand_path "$target")" "$REPO_ROOT"
    if [ -n "$shim" ]; then
      _pass "$name declares a shim"
    else
      _fail "$name declares a shim"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
  done
}

run_tests test_profile_contract

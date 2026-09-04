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

test_install_unknown_profile() {
  assert_status 1 "unknown profile is refused" -- \
    sh "$REPO_ROOT/install.sh" nope --target "$TMP/u" --shim-dir "$TMP/bin"
}

test_install_guard() {
  assert_status 1 "refuses ~/.claude as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME/.claude" --shim-dir "$TMP/bin"
  assert_status 1 "refuses home as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME" --shim-dir "$TMP/bin"
  assert_status 1 "refuses in-repo target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$REPO_ROOT/profiles" --shim-dir "$TMP/bin"
  assert_missing "$TMP/bin/claude-gen" "no shim written by a refused install"
}

test_install_dry_run() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dry" --shim-dir "$TMP/bin" --dry-run >/dev/null
  assert_missing "$TMP/dry" "dry run creates no config root"
  assert_missing "$TMP/bin/claude-gen" "dry run creates no shim"
}

run_tests test_profile_contract test_install_unknown_profile test_install_guard test_install_dry_run

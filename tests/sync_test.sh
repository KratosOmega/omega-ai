#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
SANDBOX="$TMP/repo"
trap 'rm -rf "$TMP"' EXIT

setup_sandbox() {
  mkdir -p "$SANDBOX"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/profiles" "$SANDBOX/"
  cp "$REPO_ROOT/sync-memory.sh" "$SANDBOX/"
  mkdir -p "$SANDBOX/profiles/general/memory"
}

test_sync_copies_new_memory() {
  setup_sandbox
  mkdir -p "$TMP/cfg/memory/notes"
  printf 'decided on tilemap chunking\n' > "$TMP/cfg/memory/notes/level-streaming.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg" >/dev/null
  assert_file "$SANDBOX/profiles/general/memory/notes/level-streaming.md" "copies new memory file into the profile"
  assert_contains "$SANDBOX/profiles/general/memory/notes/level-streaming.md" "tilemap chunking" "content preserved"
}

test_sync_skips_symlinks() {
  setup_sandbox
  mkdir -p "$TMP/cfg2/memory"
  printf 'repo copy\n' > "$SANDBOX/profiles/general/memory/MEMORY.md"
  ln -s "$SANDBOX/profiles/general/memory/MEMORY.md" "$TMP/cfg2/memory/MEMORY.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg2" > "$TMP/sync.out"
  assert_eq "repo copy" "$(cat "$SANDBOX/profiles/general/memory/MEMORY.md")" "symlinked memory left untouched"
}

test_sync_dry_run() {
  setup_sandbox
  mkdir -p "$TMP/cfg3/memory"
  printf 'x\n' > "$TMP/cfg3/memory/new.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg3" --dry-run >/dev/null
  assert_missing "$SANDBOX/profiles/general/memory/new.md" "dry run copies nothing"
}

run_tests test_sync_copies_new_memory test_sync_skips_symlinks test_sync_dry_run

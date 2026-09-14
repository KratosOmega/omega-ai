#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
SANDBOX="$TMP/repo"
trap 'rm -rf "$TMP"' EXIT

setup_sandbox() {
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SANDBOX/"
  cp "$REPO_ROOT/sync-memory.sh" "$SANDBOX/"
  mkdir -p "$SANDBOX/studios/general/memory"
}

test_sync_copies_new_memory() {
  setup_sandbox
  mkdir -p "$TMP/cfg/memory/notes"
  printf 'decided on tilemap chunking\n' > "$TMP/cfg/memory/notes/level-streaming.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg" > "$TMP/sync-new.out" 2>&1
  assert_file "$SANDBOX/studios/general/memory/notes/level-streaming.md" "copies new memory file into the studio"
  assert_contains "$SANDBOX/studios/general/memory/notes/level-streaming.md" "tilemap chunking" "content preserved"
  assert_contains "$TMP/sync-new.out" "synced notes/level-streaming.md" "reports the file it synced"
}

# A symlink in the config root already points back into this repository, so
# sync must not walk it. The run has to succeed AND stay silent about the file:
# with `find -L` the copy would be same-file and the run would fail instead.
test_sync_skips_symlinks() {
  setup_sandbox
  mkdir -p "$TMP/cfg2/memory"
  printf 'repo copy\n' > "$SANDBOX/studios/general/memory/MEMORY.md"
  ln -s "$SANDBOX/studios/general/memory/MEMORY.md" "$TMP/cfg2/memory/MEMORY.md"
  status=0
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg2" > "$TMP/sync.out" 2>&1 || status=$?
  assert_eq "0" "$status" "sync succeeds when the config root holds only symlinked memory"
  assert_not_contains "$TMP/sync.out" "^synced " "no file is reported as synced"
  assert_contains "$TMP/sync.out" "memory sync complete" "sync still reports completion"
  assert_eq "repo copy" "$(cat "$SANDBOX/studios/general/memory/MEMORY.md")" "symlinked memory left untouched"
}

test_sync_dry_run() {
  setup_sandbox
  mkdir -p "$TMP/cfg3/memory"
  printf 'x\n' > "$TMP/cfg3/memory/new.md"
  sh "$SANDBOX/sync-memory.sh" general --target "$TMP/cfg3" --dry-run >/dev/null 2>&1
  assert_missing "$SANDBOX/studios/general/memory/new.md" "dry run copies nothing"
}

run_tests test_sync_copies_new_memory test_sync_skips_symlinks test_sync_dry_run

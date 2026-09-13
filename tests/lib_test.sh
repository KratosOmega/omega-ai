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

# A target that is itself a symlink into somewhere dangerous must be judged
# by where it points, not by the link's own path: a wet install through
# `--target evil` with `evil -> studios/general` would overwrite the studio's
# CLAUDE.md inside the repository. Only the checked path is dereferenced; a
# target that does not exist yet still passes exactly as before.
test_guard_target_derefs_symlinked_target() {
  FAKE="$TMP/fakehome-link"
  mkdir -p "$FAKE/.claude/plugins" "$TMP/gt/safe"
  ln -s "$REPO_ROOT/studios/general" "$TMP/gt/into-repo"
  ln -s "$FAKE/.claude" "$TMP/gt/into-claude"
  ln -s "$FAKE/.claude/plugins" "$TMP/gt/into-claude-child"
  ln -s "$FAKE" "$TMP/gt/into-home"
  ln -s "$TMP/gt/safe" "$TMP/gt/into-safe"

  assert_status 1 "rejects a target that links into the repository" -- \
    guard_target "$TMP/gt/into-repo" "$REPO_ROOT"
  assert_status 1 "rejects a target that links into the repository, with a trailing slash" -- \
    guard_target "$TMP/gt/into-repo/" "$REPO_ROOT"
  status=0
  ( HOME="$FAKE"; guard_target "$TMP/gt/into-claude" "$REPO_ROOT" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "rejects a target that links to ~/.claude"
  status=0
  ( HOME="$FAKE"; guard_target "$TMP/gt/into-claude-child" "$REPO_ROOT" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "rejects a target that links to a child of ~/.claude"
  status=0
  ( HOME="$FAKE"; guard_target "$TMP/gt/into-home" "$REPO_ROOT" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "rejects a target that links to the home directory"

  assert_status 0 "accepts a target that links to a safe directory" -- \
    guard_target "$TMP/gt/into-safe" "$REPO_ROOT"
  assert_status 0 "still accepts a target that does not exist yet" -- \
    guard_target "$TMP/gt/fresh" "$REPO_ROOT"
  assert_status 1 "still rejects an empty target" -- guard_target "" "$REPO_ROOT"
  assert_missing "$TMP/gt/fresh" "guard_target creates nothing"
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
  DRY_RUN=1 run touch "$TMP/should-not-exist" 2>/dev/null
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

test_manifest_remove() {
  mkdir -p "$TMP/mr/root/memory" "$TMP/mr/bin" "$TMP/mr/outside"
  printf 'x\n' > "$TMP/mr/root/memory/a.md"
  printf 'x\n' > "$TMP/mr/root/CLAUDE.md"
  printf 'x\n' > "$TMP/mr/bin/claude-x"
  printf 'x\n' > "$TMP/mr/outside/keep.md"
  printf 'x\n' > "$TMP/mr/root/user-data.md"
  {
    printf '%s\n' "$TMP/mr/root/memory/a.md"
    printf '%s\n' "$TMP/mr/root/CLAUDE.md"
    printf '%s\n' "$TMP/mr/bin/claude-x"
    printf '%s\n' "$TMP/mr/outside/keep.md"
    printf '%s\n' "$TMP/mr/root/../outside/keep.md"
  } > "$TMP/mr/root/.omega-ai-manifest"
  manifest_remove "$TMP/mr/root/.omega-ai-manifest" "$TMP/mr/root" "$TMP/mr/bin/claude-x" 2>"$TMP/mr/err"
  assert_missing "$TMP/mr/root/memory/a.md" "removes an in-scope entry"
  assert_missing "$TMP/mr/root/CLAUDE.md" "removes a second in-scope entry"
  assert_missing "$TMP/mr/bin/claude-x" "removes the named shim"
  assert_file "$TMP/mr/outside/keep.md" "keeps an entry outside the target"
  assert_file "$TMP/mr/root/user-data.md" "keeps files the manifest never recorded"
  assert_missing "$TMP/mr/root/.omega-ai-manifest" "removes the manifest itself"
  assert_contains "$TMP/mr/err" "skipping manifest entry" "warns about the skipped entry"
  assert_status 0 "a missing manifest is not an error" -- manifest_remove "$TMP/mr/none" "$TMP/mr/root" ""
}

# A config root reached through a symlink (`--target ~/link`, link -> real
# dir) must still have its entries removed. Entries canonicalize through the
# link to the real directory, so the scope must be the real directory too —
# otherwise every entry looks "outside scope" and cleanup silently does
# nothing. The link itself is never an entry, so it stays.
test_manifest_remove_through_symlinked_root() {
  mkdir -p "$TMP/sr/real/memory" "$TMP/sr/bin" "$TMP/sr/outside"
  ln -s "$TMP/sr/real" "$TMP/sr/link"
  printf 'x\n' > "$TMP/sr/link/memory/a.md"
  printf 'x\n' > "$TMP/sr/link/CLAUDE.md"
  printf 'x\n' > "$TMP/sr/real/settings.json"
  printf 'x\n' > "$TMP/sr/bin/claude-x"
  printf 'x\n' > "$TMP/sr/outside/keep.md"
  printf 'x\n' > "$TMP/sr/real/user-data.md"
  {
    printf '%s\n' "$TMP/sr/link/memory/a.md"
    printf '%s\n' "$TMP/sr/link/CLAUDE.md"
    printf '%s\n' "$TMP/sr/real/settings.json"
    printf '%s\n' "$TMP/sr/bin/claude-x"
    printf '%s\n' "$TMP/sr/outside/keep.md"
    printf '%s\n' "$TMP/sr/link/../outside/keep.md"
  } > "$TMP/sr/link/.omega-ai-manifest"
  manifest_remove "$TMP/sr/link/.omega-ai-manifest" "$TMP/sr/link" "$TMP/sr/bin/claude-x" 2>"$TMP/sr/err"
  assert_missing "$TMP/sr/real/memory/a.md" "removes an entry recorded through the link"
  assert_missing "$TMP/sr/real/CLAUDE.md" "removes a second entry recorded through the link"
  assert_missing "$TMP/sr/real/settings.json" "removes an entry recorded by its real path"
  assert_missing "$TMP/sr/bin/claude-x" "removes the named shim"
  assert_symlink "$TMP/sr/link" "the root link itself stays"
  assert_file "$TMP/sr/outside/keep.md" "keeps an entry outside the real root"
  assert_file "$TMP/sr/real/user-data.md" "keeps files the manifest never recorded"
  assert_missing "$TMP/sr/real/.omega-ai-manifest" "removes the manifest itself"
  assert_contains "$TMP/sr/err" "skipping manifest entry" "warns about the skipped entries"
  assert_status 0 "a root that does not exist yet is still accepted" -- \
    manifest_remove "$TMP/sr/none/.omega-ai-manifest" "$TMP/sr/none" ""
}

# A trailing slash on an entry that names a symlink makes `rm -rf` follow the
# link: BSD rm deletes the linked directory's contents and leaves the link.
# canon_path keeps the final component undereferenced, so the entry looks in
# scope while the deletion lands wherever the link points — in symlink mode,
# inside the repository. Such an entry must be skipped, not removed.
test_manifest_remove_skips_trailing_slash() {
  mkdir -p "$TMP/ts/root/memory" "$TMP/ts/linked"
  printf 'x\n' > "$TMP/ts/linked/keep.md"
  ln -s "$TMP/ts/linked" "$TMP/ts/root/memory/sub"
  printf 'x\n' > "$TMP/ts/root/CLAUDE.md"
  {
    printf '%s\n' "$TMP/ts/root/memory/sub/"
    printf '%s\n' "$TMP/ts/root/CLAUDE.md"
  } > "$TMP/ts/root/.omega-ai-manifest"
  manifest_remove "$TMP/ts/root/.omega-ai-manifest" "$TMP/ts/root" "" 2>"$TMP/ts/err"
  assert_file "$TMP/ts/linked/keep.md" "a trailing-slash entry never deletes through the link"
  assert_symlink "$TMP/ts/root/memory/sub" "the link itself is left alone"
  assert_contains "$TMP/ts/err" "trailing slash" "warns about the skipped entry"
  assert_missing "$TMP/ts/root/CLAUDE.md" "other in-scope entries are still removed"
  assert_missing "$TMP/ts/root/.omega-ai-manifest" "the manifest is still removed"
}

run_tests test_json_field test_expand_path test_canon_path test_guard_target_rejects \
  test_guard_target_rejects_descendants_of_dot_claude test_guard_target_accepts \
  test_guard_target_derefs_symlinked_target \
  test_need_value test_resolve_studio_target test_requires_of test_run_dry \
  test_manifest_remove test_manifest_remove_through_symlinked_root \
  test_manifest_remove_skips_trailing_slash

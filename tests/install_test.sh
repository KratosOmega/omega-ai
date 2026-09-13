#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test_studio_contract() {
  for dir in "$REPO_ROOT"/studios/*/; do
    name="$(basename "$dir")"
    assert_file "$dir/studio.json" "$name has studio.json"
    assert_file "$dir/CLAUDE.md" "$name has CLAUDE.md"
    assert_file "$dir/settings.json" "$name has settings.json"
    assert_file "$dir/requires.txt" "$name has requires.txt"
    assert_file "$dir/.claude-plugin/plugin.json" "$name has a plugin manifest"
    assert_eq "$name" "$(json_field "$dir/studio.json" name)" "$name studio.json name matches directory"
    assert_eq "$name" "$(json_field "$dir/.claude-plugin/plugin.json" name)" \
      "$name plugin.json name matches directory"
    assert_eq "0.1.0" "$(json_field "$dir/.claude-plugin/plugin.json" version)" \
      "$name plugin.json declares version 0.1.0"
    target="$(json_field "$dir/studio.json" target)"
    shim="$(json_field "$dir/studio.json" shim)"
    assert_status 0 "$name declares a safe target" -- guard_target "$(expand_path "$target")" "$REPO_ROOT"
    if [ -n "$shim" ]; then
      _pass "$name declares a shim"
    else
      _fail "$name declares a shim"
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
  done
}

test_install_unknown_studio() {
  assert_status 1 "unknown studio is refused" -- \
    sh "$REPO_ROOT/install.sh" nope --target "$TMP/u" --shim-dir "$TMP/bin"
}

test_install_guard() {
  assert_status 1 "refuses ~/.claude as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME/.claude" --shim-dir "$TMP/bin"
  assert_status 1 "refuses home as target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$HOME" --shim-dir "$TMP/bin"
  assert_status 1 "refuses in-repo target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$REPO_ROOT/studios" --shim-dir "$TMP/bin"
  assert_missing "$TMP/bin/claude-gen" "no shim written by a refused install"
}

test_install_dry_run() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dry" --shim-dir "$TMP/bin" --dry-run >/dev/null
  assert_missing "$TMP/dry" "dry run creates no config root"
  assert_missing "$TMP/bin/claude-gen" "dry run creates no shim"
}

test_install_content() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/gen/CLAUDE.md" "renders CLAUDE.md"
  assert_contains "$TMP/gen/CLAUDE.md" "General Studio" "rendered CLAUDE.md carries studio content"
  assert_contains "$TMP/gen/CLAUDE.md" "GENERATED" "rendered CLAUDE.md warns it is generated"
  assert_file "$TMP/gen/settings.json" "copies settings.json"
  assert_symlink "$TMP/gen/skills/repo-conventions" "links studio skill"
  assert_file "$TMP/gen/.omega-ai-manifest" "writes a manifest"
  assert_contains "$TMP/gen/.omega-ai-manifest" "skills/repo-conventions" "manifest records the skill"
}

test_install_precedence() {
  mkdir -p "$TMP/fixture/shared/skills/collide" "$TMP/fixture/studio/skills/collide"
  printf 'shared\n' > "$TMP/fixture/shared/skills/collide/SKILL.md"
  printf 'studio\n' > "$TMP/fixture/studio/skills/collide/SKILL.md"
  install_entries "$TMP/fixture/shared/skills" "$TMP/fixture/dest" copy >/dev/null
  install_entries "$TMP/fixture/studio/skills" "$TMP/fixture/dest" copy >/dev/null
  assert_eq "studio" "$(cat "$TMP/fixture/dest/collide/SKILL.md")" "studio entry wins the collision"
}

test_install_copy_mode() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/cp" --shim-dir "$TMP/bin" --mode copy >/dev/null
  assert_file "$TMP/cp/skills/repo-conventions/SKILL.md" "copy mode installs a real file"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/cp/skills/repo-conventions" ]; then
    _fail "copy mode installs no symlink"
  else
    _pass "copy mode installs no symlink"
  fi
}

test_settings_backup() {
  printf '{"model":"stale"}\n' > "$TMP/gen/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  found=0
  for f in "$TMP/gen"/settings.json.bak-*; do
    [ -f "$f" ] && found=1
  done
  assert_eq "1" "$found" "backs up a differing settings.json"
}

test_shim() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/bin/claude-gen" "writes the shim"
  assert_contains "$TMP/bin/claude-gen" "CLAUDE_CONFIG_DIR" "shim sets CLAUDE_CONFIG_DIR"
  assert_contains "$TMP/bin/claude-gen" "$TMP/gen" "shim points at the target root"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/bin/claude-gen" ]; then _pass "shim is executable"; else _fail "shim is executable"; fi
  assert_contains "$TMP/gen/.omega-ai-manifest" "bin/claude-gen" "manifest records the shim"
}

test_doctor() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen" > "$TMP/doctor.out" 2>&1
  assert_contains "$TMP/doctor.out" "$TMP/gen" "doctor reports the resolved config root"
  assert_contains "$TMP/doctor.out" "leakage: none" "doctor finds no leak into ~/.claude"
  assert_status 1 "doctor fails on a missing root" -- \
    sh "$REPO_ROOT/doctor.sh" general --target "$TMP/absent"
}

test_uninstall() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null
  mkdir -p "$TMP/un/sessions"
  printf 'user data\n' > "$TMP/un/sessions/keep.txt"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null
  assert_missing "$TMP/un/skills/repo-conventions" "removes installed skill"
  assert_missing "$TMP/un/CLAUDE.md" "removes rendered CLAUDE.md"
  assert_missing "$TMP/bin/claude-gen" "removes the shim"
  assert_missing "$TMP/un/.omega-ai-manifest" "removes the manifest"
  assert_file "$TMP/un/sessions/keep.txt" "keeps user data"
}

test_uninstall_purge() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" --purge --yes >/dev/null
  assert_missing "$TMP/purge" "purge removes the whole config root"
}

test_two_studios_independent() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/a" --shim-dir "$TMP/bin" >/dev/null
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/b" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/a/CLAUDE.md" "first studio intact after second install"
  assert_file "$TMP/b/CLAUDE.md" "second studio installed"
  assert_contains "$TMP/a/CLAUDE.md" "General Studio" "first root keeps its own prompt"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/b" --shim-dir "$TMP/bin" --purge --yes >/dev/null
  assert_file "$TMP/a/CLAUDE.md" "uninstalling one studio leaves the other alone"
  assert_file "$TMP/bin/claude-gen" "other studio's shim survives"
}

# --- Finding 1: the shim directory must pass the same guard as the target. ---
# Runs under a fake $HOME so the assertions can never involve the real ~/.claude.
test_install_guards_shim_dir() {
  FAKE="$TMP/fakehome"
  mkdir -p "$FAKE/.claude"
  printf 'precious\n' > "$FAKE/.claude/settings.json"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$TMP/sg" --shim-dir "$FAKE/.claude/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "install refuses a shim dir inside ~/.claude"
  assert_missing "$FAKE/.claude/bin" "refused install creates nothing under ~/.claude"
  assert_missing "$TMP/sg" "refused install creates no config root"
  assert_contains "$FAKE/.claude/settings.json" "precious" "existing ~/.claude content is untouched"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$TMP/sg" --shim-dir "$FAKE/.claude" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "install refuses ~/.claude itself as the shim dir"

  assert_status 1 "install refuses an in-repo shim dir" -- \
    sh "$REPO_ROOT/install.sh" general --target "$TMP/sg" --shim-dir "$REPO_ROOT/bin"
  assert_missing "$REPO_ROOT/bin" "refused install creates no directory in the repo"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/uninstall.sh" general \
      --target "$TMP/sg2" --shim-dir "$FAKE/.claude/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "uninstall refuses a shim dir inside ~/.claude"
}

# --- Finding 2: uninstall only removes what this invocation installed. ---
test_uninstall_scopes_manifest_entries() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/scope" --shim-dir "$TMP/bin-scope" >/dev/null
  mkdir -p "$TMP/outside"
  printf 'not ours\n' > "$TMP/outside/precious.txt"
  printf '%s\n' "$TMP/outside/precious.txt" >> "$TMP/scope/.omega-ai-manifest"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/scope" --shim-dir "$TMP/bin-scope" \
    > "$TMP/scope.out" 2>&1
  assert_file "$TMP/outside/precious.txt" "manifest entry outside the target survives uninstall"
  assert_contains "$TMP/scope.out" "skipping manifest entry" "uninstall warns about the skipped entry"
  assert_missing "$TMP/scope/CLAUDE.md" "in-scope entries are still removed"
  assert_missing "$TMP/bin-scope/claude-gen" "the matching shim is still removed"
}

# --- Finding 3 + deferred: option values are required, empty is an error. ---
test_option_value_required() {
  FAKE="$TMP/fakehome-opt"
  mkdir -p "$FAKE/.claude-general"
  printf 'live root\n' > "$FAKE/.claude-general/marker.txt"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/uninstall.sh" general \
      --target "" --purge --yes >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "uninstall refuses an empty --target instead of falling back"
  assert_file "$FAKE/.claude-general/marker.txt" "an empty --target never purges the default root"

  assert_status 1 "install refuses an empty --target" -- \
    sh "$REPO_ROOT/install.sh" general --target "" --shim-dir "$TMP/bin-opt"
  assert_status 1 "install refuses an empty --shim-dir" -- \
    sh "$REPO_ROOT/install.sh" general --target "$TMP/opt" --shim-dir ""
  assert_status 1 "install refuses an empty --mode" -- \
    sh "$REPO_ROOT/install.sh" general --mode "" --target "$TMP/opt"
  assert_status 1 "doctor refuses an empty --target" -- \
    sh "$REPO_ROOT/doctor.sh" general --target ""
  assert_status 1 "sync-memory refuses an empty --target" -- \
    sh "$REPO_ROOT/sync-memory.sh" general --target ""
  assert_missing "$TMP/opt" "no config root is created by a refused install"

  # A trailing option with no value at all must die cleanly, naming the flag.
  for spec in "install.sh --target" "install.sh --mode" "install.sh --shim-dir" \
              "uninstall.sh --target" "uninstall.sh --shim-dir" \
              "doctor.sh --target" "sync-memory.sh --target"; do
    script="${spec% *}"; flag="${spec#* }"
    sh "$REPO_ROOT/$script" general "$flag" > "$TMP/opt.out" 2>&1 || true
    assert_contains "$TMP/opt.out" "missing value for $flag" \
      "$script names $flag when its value is missing"
  done
}

# --- Findings 4 and 7: the doctor must actually detect a leak. ---
# Only a symlink inside the temporary root is created; nothing under ~/.claude
# is created, read, modified, or removed. The probe is removed afterwards.
test_doctor_detects_leak() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/leak" --shim-dir "$TMP/bin-leak" >/dev/null

  ln -s "$HOME/.claude/settings.json" "$TMP/leak/leaky-link"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak.out" 2>&1 || status=$?
  rm -f "$TMP/leak/leaky-link"
  assert_eq "1" "$status" "doctor exits 1 on a link into ~/.claude"
  assert_contains "$TMP/leak.out" "leakage:" "doctor reports leakage"
  assert_contains "$TMP/leak.out" "leaky-link" "doctor names the leaking link"
  assert_not_contains "$TMP/leak.out" "leakage: none" "doctor does not claim the root is clean"

  # Finding 7: a link to ~/.claude itself, not a descendant, is still a leak.
  ln -s "$HOME/.claude" "$TMP/leak/exact-link"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak2.out" 2>&1 || status=$?
  rm -f "$TMP/leak/exact-link"
  assert_eq "1" "$status" "doctor exits 1 on a link to ~/.claude itself"
  assert_contains "$TMP/leak2.out" "exact-link" "doctor names the exact-path leak"

  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak3.out" 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes again once the probe is removed"
  assert_contains "$TMP/leak3.out" "leakage: none" "doctor reports a clean root again"
}

# --- Finding 8: a studio with no enabled plugins prints (none). ---
test_doctor_reports_no_plugins() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/plug" --shim-dir "$TMP/bin-plug" >/dev/null
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/plug" > "$TMP/plug.out" 2>&1
  assert_contains "$TMP/plug.out" "(none)" "doctor prints (none) for a studio with no plugins"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/plug2" --shim-dir "$TMP/bin-plug" >/dev/null
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/plug2" > "$TMP/plug2.out" 2>&1
  assert_contains "$TMP/plug2.out" "godot-prompter" "doctor lists enabled plugins when present"
  assert_not_contains "$TMP/plug2.out" "(none)" "doctor does not print (none) when plugins exist"
}

# --- Finding 6: all four scripts resolve the studio the same way. ---
test_all_scripts_validate_the_studio() {
  SB="$TMP/sandbox"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" \
     "$REPO_ROOT/sync-memory.sh" "$SB/"
  mkdir -p "$SB/studios/broken"
  printf '# broken\n' > "$SB/studios/broken/CLAUDE.md"

  sh "$SB/install.sh" general --target "$TMP/brk" --shim-dir "$TMP/bin-brk" >/dev/null
  mkdir -p "$TMP/brk/memory"
  printf 'session note\n' > "$TMP/brk/memory/NOTE.md"

  assert_status 1 "install refuses a studio with no studio.json" -- \
    sh "$SB/install.sh" broken --target "$TMP/brk2" --shim-dir "$TMP/bin-brk"
  assert_status 1 "uninstall refuses a studio with no studio.json" -- \
    sh "$SB/uninstall.sh" broken --target "$TMP/brk" --shim-dir "$TMP/bin-brk"
  assert_status 1 "doctor refuses a studio with no studio.json" -- \
    sh "$SB/doctor.sh" broken --target "$TMP/brk"
  assert_status 1 "sync-memory refuses a studio with no studio.json" -- \
    sh "$SB/sync-memory.sh" broken --target "$TMP/brk"
  assert_file "$TMP/brk/CLAUDE.md" "a refused uninstall removes nothing"
  assert_missing "$SB/studios/broken/memory" "a refused sync copies nothing"

  assert_status 1 "install refuses a second positional studio" -- \
    sh "$SB/install.sh" general game-dev --target "$TMP/brk" --shim-dir "$TMP/bin-brk"
  assert_status 1 "uninstall refuses a second positional studio" -- \
    sh "$SB/uninstall.sh" general game-dev --target "$TMP/brk" --shim-dir "$TMP/bin-brk"
  assert_status 1 "doctor refuses a second positional studio" -- \
    sh "$SB/doctor.sh" general game-dev --target "$TMP/brk"
  assert_status 1 "sync-memory refuses a second positional studio" -- \
    sh "$SB/sync-memory.sh" general game-dev --target "$TMP/brk"
  assert_file "$TMP/brk/CLAUDE.md" "a refused second-studio run changes nothing"
}

# --- Critical: a '..' spelling must not walk around guard_target. ---
# Runs entirely under a fake $HOME inside the sandbox, so no assertion here can
# create, read, modify or delete anything under the real ~/.claude.
test_install_refuses_traversal_target() {
  FAKE="$TMP/fakehome-trav"
  mkdir -p "$FAKE/.claude"
  printf 'precious\n' > "$FAKE/.claude/settings.json"

  status=0
  ( HOME="$FAKE"; guard_target "$FAKE/x/../.claude" "$REPO_ROOT" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "guard_target rejects a traversal spelling of ~/.claude"

  status=0
  ( HOME="$FAKE"; guard_target "$FAKE/x/../.claude/sub" "$REPO_ROOT" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "guard_target rejects a traversal into a ~/.claude descendant"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$FAKE/x/../.claude" --shim-dir "$TMP/bin-trav" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "install refuses a traversal --target"
  assert_missing "$FAKE/.claude/CLAUDE.md" "refused traversal install renders no CLAUDE.md in ~/.claude"
  assert_missing "$FAKE/.claude/skills" "refused traversal install installs no skills in ~/.claude"
  assert_missing "$FAKE/.claude/commands" "refused traversal install installs no commands in ~/.claude"
  assert_missing "$FAKE/.claude/.omega-ai-manifest" "refused traversal install writes no manifest in ~/.claude"
  assert_missing "$FAKE/x" "refused traversal install creates no intermediate directory"
  assert_missing "$TMP/bin-trav" "refused traversal install writes no shim directory"
  assert_contains "$FAKE/.claude/settings.json" "precious" \
    "refused traversal install leaves ~/.claude/settings.json untouched"
  found=0
  for f in "$FAKE/.claude"/settings.json.bak-*; do
    if [ -f "$f" ]; then found=1; fi
  done
  assert_eq "0" "$found" "refused traversal install backs up nothing in ~/.claude"
}

test_install_refuses_traversal_shim_dir() {
  FAKE="$TMP/fakehome-trav-shim"
  mkdir -p "$FAKE/.claude"
  printf 'precious\n' > "$FAKE/.claude/settings.json"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$TMP/trav" --shim-dir "$FAKE/y/../.claude/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "install refuses a traversal --shim-dir"
  assert_missing "$FAKE/.claude/bin" "refused traversal shim-dir creates no bin under ~/.claude"
  assert_missing "$FAKE/y" "refused traversal shim-dir creates no intermediate directory"
  assert_missing "$TMP/trav" "refused traversal shim-dir install creates no config root"
  assert_contains "$FAKE/.claude/settings.json" "precious" \
    "refused traversal shim-dir leaves ~/.claude untouched"

  # The uninstaller must bail on the traversal too, before it deletes anything.
  # A real config root and a decoy shim make the refusal observable: without the
  # guard, uninstall would strip the root and rm -f the decoy.
  mkdir -p "$FAKE/.claude/bin"
  printf 'decoy\n' > "$FAKE/.claude/bin/claude-gen"
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$TMP/travu" --shim-dir "$TMP/bin-travu" >/dev/null 2>&1 ) || true
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/uninstall.sh" general \
      --target "$TMP/travu" --shim-dir "$FAKE/y/../.claude/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "uninstall refuses a traversal --shim-dir"
  assert_contains "$FAKE/.claude/bin/claude-gen" "decoy" \
    "refused traversal uninstall deletes nothing under ~/.claude"
  assert_file "$TMP/travu/CLAUDE.md" "refused traversal uninstall strips nothing from the config root"
}

# --- Critical: a manifest entry spelled with '..' escapes the scope check. ---
test_uninstall_skips_traversal_manifest_entries() {
  FAKE="$TMP/fakehome-mani"
  mkdir -p "$FAKE/.claude/plugins"
  printf 'precious\n' > "$FAKE/.claude/settings.json"
  printf 'plugin data\n' > "$FAKE/.claude/plugins/keep.txt"

  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general \
      --target "$FAKE/.claude-general" --shim-dir "$FAKE/bin" >/dev/null 2>&1 ) || true
  assert_file "$FAKE/.claude-general/.omega-ai-manifest" "sandbox install wrote a manifest"

  # Two hostile entries that textually match "$TARGET/*" but escape the root.
  printf '%s\n' "$FAKE/.claude-general/../.claude/settings.json" \
    >> "$FAKE/.claude-general/.omega-ai-manifest"
  printf '%s\n' "$FAKE/.claude-general/../.claude/plugins" \
    >> "$FAKE/.claude-general/.omega-ai-manifest"

  ( HOME="$FAKE" sh "$REPO_ROOT/uninstall.sh" general \
      --target "$FAKE/.claude-general" --shim-dir "$FAKE/bin" > "$TMP/mani.out" 2>&1 ) || true
  assert_file "$FAKE/.claude/settings.json" "a traversal manifest entry does not delete ~/.claude/settings.json"
  assert_contains "$FAKE/.claude/settings.json" "precious" "the escaped file keeps its content"
  assert_file "$FAKE/.claude/plugins/keep.txt" "a traversal manifest entry does not delete ~/.claude/plugins"
  assert_contains "$TMP/mani.out" "skipping manifest entry" "uninstall warns about the escaping entry"
  assert_missing "$FAKE/.claude-general/CLAUDE.md" "in-scope entries are still removed"
  assert_missing "$FAKE/.claude-general/skills/repo-conventions" "in-scope skill is still removed"
  assert_missing "$FAKE/bin/claude-gen" "the matching shim is still removed"
  assert_missing "$FAKE/.claude-general/.omega-ai-manifest" "the manifest is still removed"
}

run_tests test_studio_contract test_install_unknown_studio test_install_guard \
  test_install_guards_shim_dir test_install_refuses_traversal_target \
  test_install_refuses_traversal_shim_dir test_install_dry_run test_install_content \
  test_install_precedence test_install_copy_mode test_settings_backup test_shim \
  test_doctor test_doctor_detects_leak test_doctor_reports_no_plugins \
  test_option_value_required test_uninstall test_uninstall_scopes_manifest_entries \
  test_uninstall_skips_traversal_manifest_entries \
  test_uninstall_purge test_two_studios_independent test_all_scripts_validate_the_studio

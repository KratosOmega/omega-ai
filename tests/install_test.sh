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

test_install_content() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null
  assert_file "$TMP/gen/CLAUDE.md" "renders CLAUDE.md"
  assert_contains "$TMP/gen/CLAUDE.md" "General Profile" "rendered CLAUDE.md carries profile content"
  assert_contains "$TMP/gen/CLAUDE.md" "GENERATED" "rendered CLAUDE.md warns it is generated"
  assert_file "$TMP/gen/settings.json" "copies settings.json"
  assert_symlink "$TMP/gen/skills/repo-conventions" "links profile skill"
  assert_file "$TMP/gen/.omega-ai-manifest" "writes a manifest"
  assert_contains "$TMP/gen/.omega-ai-manifest" "skills/repo-conventions" "manifest records the skill"
}

test_install_precedence() {
  mkdir -p "$TMP/fixture/shared/skills/collide" "$TMP/fixture/profile/skills/collide"
  printf 'shared\n' > "$TMP/fixture/shared/skills/collide/SKILL.md"
  printf 'profile\n' > "$TMP/fixture/profile/skills/collide/SKILL.md"
  install_entries "$TMP/fixture/shared/skills" "$TMP/fixture/dest" copy >/dev/null
  install_entries "$TMP/fixture/profile/skills" "$TMP/fixture/dest" copy >/dev/null
  assert_eq "profile" "$(cat "$TMP/fixture/dest/collide/SKILL.md")" "profile entry wins the collision"
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

run_tests test_profile_contract test_install_unknown_profile test_install_guard \
  test_install_dry_run test_install_content test_install_precedence \
  test_install_copy_mode test_settings_backup test_shim test_doctor

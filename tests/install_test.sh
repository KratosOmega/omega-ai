#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

# Physical path: the installer canonicalizes the target, so assertions that
# quote $TMP must use the same spelling (/var -> /private/var on macOS).
TMP="$(cd "$(mktemp -d)" && pwd -P)"
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
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$(json_field "$dir/.claude-plugin/plugin.json" version)" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      _pass "$name plugin.json declares a semver version"
    else
      _fail "$name plugin.json declares a semver version"
    fi
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

# Runs under a fake $HOME: a guard_target regression must never write into
# the developer's live ~/.claude before the assertion fails.
test_install_guard() {
  FAKE="$TMP/fakehome-guard"
  mkdir -p "$FAKE/.claude"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE/.claude" --shim-dir "$TMP/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "refuses ~/.claude as target"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE" --shim-dir "$TMP/bin" >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "refuses home as target"
  assert_status 1 "refuses in-repo target" -- \
    sh "$REPO_ROOT/install.sh" general --target "$REPO_ROOT/studios" --shim-dir "$TMP/bin"
  assert_missing "$TMP/bin/claude-gen" "no shim written by a refused install"
  assert_missing "$FAKE/.claude/CLAUDE.md" "refused install writes nothing into ~/.claude"
}

test_install_dry_run() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dry" --shim-dir "$TMP/bin" --dry-run >/dev/null 2>&1
  assert_missing "$TMP/dry" "dry run creates no config root"
  assert_missing "$TMP/bin/claude-gen" "dry run creates no shim"
}

test_install_content() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/gd" --shim-dir "$TMP/bin" >/dev/null 2>&1
  assert_file "$TMP/gd/CLAUDE.md" "renders CLAUDE.md"
  assert_contains "$TMP/gd/CLAUDE.md" "Game Development Studio" "rendered CLAUDE.md carries studio content"
  assert_contains "$TMP/gd/CLAUDE.md" "Engineering Standards" "rendered CLAUDE.md carries the shared part"
  assert_contains "$TMP/gd/CLAUDE.md" "GENERATED" "rendered CLAUDE.md warns it is generated"
  assert_contains "$TMP/gd/CLAUDE.md" "^@memory/MEMORY.md" "rendered CLAUDE.md imports the studio memory"
  assert_file "$TMP/gd/settings.json" "copies settings.json"
  assert_symlink "$TMP/gd/memory/MEMORY.md" "links studio memory"
  assert_symlink "$TMP/gd/bin/studio-state" "links studio bin"
  assert_missing "$TMP/gd/skills" "no skills directory in the target — the plugin serves them"
  assert_missing "$TMP/gd/agents" "no agents directory in the target"
  assert_missing "$TMP/gd/hooks" "no hooks directory in the target"
  assert_missing "$TMP/gd/commands" "no commands directory in the target"
  assert_missing "$TMP/gd/studio" "symlink mode takes no snapshot of the studio"
  assert_file "$TMP/gd/.omega-ai-manifest" "writes a manifest"
  assert_contains "$TMP/gd/.omega-ai-manifest" "memory/MEMORY.md" "manifest records the memory link"
  assert_contains "$TMP/gd/.omega-ai-manifest" "bin/studio-state" "manifest records the bin link"
  assert_not_contains "$TMP/gd/.omega-ai-manifest" "skills/" "manifest records no skills"
  assert_eq "# mode=symlink" "$(sed -n '1p' "$TMP/gd/.omega-ai-manifest")" "manifest starts with the mode"
  assert_eq "# shim=$TMP/bin/claude-gd" "$(sed -n '2p' "$TMP/gd/.omega-ai-manifest")" "manifest records the shim path"
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
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/cp" --shim-dir "$TMP/bin-cp" --mode copy >/dev/null 2>&1
  assert_file "$TMP/cp/studio/.claude-plugin/plugin.json" "copy mode snapshots the studio under the target"
  assert_file "$TMP/cp/studio/skills/game-feel/SKILL.md" "the snapshot carries the skills"
  assert_file "$TMP/cp/bin/studio-state" "copy mode installs a real bin file"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/cp/bin/studio-state" ]; then
    _fail "copy mode installs no symlink"
  else
    _pass "copy mode installs no symlink"
  fi
  assert_contains "$TMP/bin-cp/claude-gd" "OMEGA_STUDIO_ROOT=\"$TMP/cp/studio\"" \
    "copy-mode shim points the studio root at the snapshot"
  assert_contains "$TMP/cp/.omega-ai-manifest" "$TMP/cp/studio" "manifest records the snapshot"
  assert_eq "# mode=copy" "$(sed -n '1p' "$TMP/cp/.omega-ai-manifest")" "copy mode is recorded in the manifest"
}

# A reinstall must not leave links from an earlier layout behind: the
# pre-plugin installer linked skills/ into the root, and a stale skills/ tree
# beside the plugin would load every skill twice.
test_install_reinstall_cleans_stale_entries() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/re" --shim-dir "$TMP/bin-re" >/dev/null 2>&1
  mkdir -p "$TMP/re/skills" "$TMP/re/agents" "$TMP/re/commands" "$TMP/re/hooks"
  # If the installer under test still links skills/, the path is already a
  # link into the repository and ln -s would land inside the checkout.
  rm -f "$TMP/re/skills/game-feel"
  ln -s "$REPO_ROOT/studios/game-dev/skills/game-feel" "$TMP/re/skills/game-feel"
  mkdir -p "$TMP/re-src"
  printf 'stale\n' > "$TMP/re-src/stale.md"
  ln -s "$TMP/re-src/stale.md" "$TMP/re/agents/stale"
  ln -s "$TMP/re-src/stale.md" "$TMP/re/commands/stale"
  {
    printf '%s\n' "$TMP/re/skills/game-feel"
    printf '%s\n' "$TMP/re/agents/stale"
    printf '%s\n' "$TMP/re/commands/stale"
  } >> "$TMP/re/.omega-ai-manifest"
  # A file the manifest never recorded keeps its directory alive.
  printf 'mine\n' > "$TMP/re/hooks/user-hook.sh"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/re" --shim-dir "$TMP/bin-re" >/dev/null 2>&1
  assert_missing "$TMP/re/skills/game-feel" "reinstall removes an entry the old manifest recorded"
  assert_missing "$TMP/re/skills" "reinstall removes the emptied skills/ directory"
  assert_missing "$TMP/re/agents" "reinstall removes the emptied agents/ directory"
  assert_missing "$TMP/re/commands" "reinstall removes the emptied commands/ directory"
  assert_file "$TMP/re/hooks/user-hook.sh" "reinstall keeps a directory that still holds user files"
  assert_symlink "$TMP/re/memory/MEMORY.md" "reinstall re-creates the current links"
  assert_file "$TMP/bin-re/claude-gd" "reinstall re-creates the shim"
  assert_eq "1" "$(grep -c 'memory/MEMORY.md' "$TMP/re/.omega-ai-manifest")" \
    "the manifest is rewritten, not appended"
}

test_install_accepts_no_mcp() {
  assert_status 0 "--no-mcp is accepted" -- \
    sh "$REPO_ROOT/install.sh" general --target "$TMP/nomcp" --shim-dir "$TMP/bin-nomcp" --no-mcp
  assert_not_contains "$TMP/nomcp/.omega-ai-manifest" "^mcp " "--no-mcp records no mcp line"
}

# Claude Code writes to settings.json in-session, and the previous install's
# manifest records that file — a reinstall must preserve a differing copy
# rather than removing it along with the other stale entries.
test_settings_backup() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null 2>&1
  printf '{"model":"stale"}\n' > "$TMP/gen/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null 2>&1
  found=""
  for f in "$TMP/gen"/settings.json.bak-*; do
    [ -f "$f" ] && found="$f"
  done
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$found" ]; then
    _pass "backs up a differing settings.json"
  else
    _fail "backs up a differing settings.json"
  fi
  assert_contains "$found" "stale" "the backup carries the in-session content"
  assert_not_contains "$TMP/gen/settings.json" "stale" "the studio's settings.json is installed afresh"
}

test_shim() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/gd" --shim-dir "$TMP/bin" >/dev/null 2>&1
  assert_file "$TMP/bin/claude-gd" "writes the shim"
  assert_contains "$TMP/bin/claude-gd" "CLAUDE_CONFIG_DIR=\"$TMP/gd\"" "shim sets CLAUDE_CONFIG_DIR to the target"
  assert_contains "$TMP/bin/claude-gd" "PATH=\"$TMP/gd/bin:\$PATH\"" "shim prefixes PATH with the target bin"
  assert_contains "$TMP/bin/claude-gd" "OMEGA_STUDIO_ROOT=\"$REPO_ROOT/studios/game-dev\"" \
    "shim exports the studio root"
  assert_contains "$TMP/bin/claude-gd" "exec claude --plugin-dir \"\$OMEGA_STUDIO_ROOT\" \"\$@\"" \
    "shim loads the studio as a plugin and passes arguments through"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/bin/claude-gd" ]; then _pass "shim is executable"; else _fail "shim is executable"; fi
  assert_contains "$TMP/gd/.omega-ai-manifest" "bin/claude-gd" "manifest records the shim"
}

test_doctor() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null 2>&1
  assert_not_contains "$TMP/gen/CLAUDE.md" "@memory/MEMORY.md" "a studio without memory/ imports nothing"
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen" > "$TMP/doctor.out" 2>&1
  assert_contains "$TMP/doctor.out" "$TMP/gen" "doctor reports the resolved config root"
  assert_contains "$TMP/doctor.out" "leakage: none" "doctor finds no leak into ~/.claude"
  assert_status 1 "doctor fails on a missing root" -- \
    sh "$REPO_ROOT/doctor.sh" general --target "$TMP/absent"
}

test_uninstall() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null 2>&1
  mkdir -p "$TMP/un/sessions"
  printf 'user data\n' > "$TMP/un/sessions/keep.txt"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/un" --shim-dir "$TMP/bin" >/dev/null
  assert_missing "$TMP/un/memory/MEMORY.md" "removes the memory link"
  assert_missing "$TMP/un/bin/studio-state" "removes the bin link"
  assert_missing "$TMP/un/CLAUDE.md" "removes rendered CLAUDE.md"
  assert_missing "$TMP/un/settings.json" "removes the copied settings.json"
  assert_missing "$TMP/bin/claude-gd" "removes the shim"
  assert_missing "$TMP/un/.omega-ai-manifest" "removes the manifest"
  assert_file "$TMP/un/sessions/keep.txt" "keeps user data"
}

test_uninstall_purge() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" >/dev/null 2>&1
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/purge" --shim-dir "$TMP/bin" --purge --yes >/dev/null
  assert_missing "$TMP/purge" "purge removes the whole config root"
}

test_two_studios_independent() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/a" --shim-dir "$TMP/bin" >/dev/null 2>&1
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/b" --shim-dir "$TMP/bin" >/dev/null 2>&1
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
  sh "$REPO_ROOT/install.sh" general --target "$TMP/scope" --shim-dir "$TMP/bin-scope" >/dev/null 2>&1
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
    sh "$REPO_ROOT/install.sh" general --mode "" --target "$TMP/opt" --shim-dir "$TMP/bin-opt"
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
# Runs under a fake $HOME; nothing under the real ~/.claude is read or touched.
test_doctor_detects_leak() {
  FAKE="$TMP/fakehome-leak"
  mkdir -p "$FAKE/.claude"
  printf '{}\n' > "$FAKE/.claude/settings.json"

  sh "$REPO_ROOT/install.sh" general --target "$TMP/leak" --shim-dir "$TMP/bin-leak" >/dev/null 2>&1

  ln -s "$FAKE/.claude/settings.json" "$TMP/leak/leaky-link"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak.out" 2>&1 ) || status=$?
  rm -f "$TMP/leak/leaky-link"
  assert_eq "1" "$status" "doctor exits 1 on a link into ~/.claude"
  assert_contains "$TMP/leak.out" "leakage:" "doctor reports leakage"
  assert_contains "$TMP/leak.out" "leaky-link" "doctor names the leaking link"
  assert_not_contains "$TMP/leak.out" "leakage: none" "doctor does not claim the root is clean"

  # Finding 7: a link to ~/.claude itself, not a descendant, is still a leak.
  ln -s "$FAKE/.claude" "$TMP/leak/exact-link"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak2.out" 2>&1 ) || status=$?
  rm -f "$TMP/leak/exact-link"
  assert_eq "1" "$status" "doctor exits 1 on a link to ~/.claude itself"
  assert_contains "$TMP/leak2.out" "exact-link" "doctor names the exact-path leak"

  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$TMP/leak" > "$TMP/leak3.out" 2>&1 ) || status=$?
  assert_eq "0" "$status" "doctor passes again once the probe is removed"
  assert_contains "$TMP/leak3.out" "leakage: none" "doctor reports a clean root again"
}

# --- Finding 8: a studio with no enabled plugins prints (none). ---
test_doctor_reports_no_plugins() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/plug" --shim-dir "$TMP/bin-plug" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/plug" > "$TMP/plug.out" 2>&1
  assert_contains "$TMP/plug.out" "(none)" "doctor prints (none) for a studio with no plugins"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/plug2" --shim-dir "$TMP/bin-plug" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/plug2" > "$TMP/plug2.out" 2>&1
  assert_contains "$TMP/plug2.out" "godot-prompter" "doctor lists enabled plugins when present"
  assert_not_contains "$TMP/plug2.out" "(none)" "doctor does not print (none) when plugins exist"
}

test_doctor_plugin_report() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dr" --shim-dir "$TMP/bin-dr" >/dev/null 2>&1
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dr" > "$TMP/dr.out" 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes on a fresh install with no plugin cache"
  assert_contains "$TMP/dr.out" "plugin:       game-dev [0-9]" "doctor reports the plugin name and version"
  assert_contains "$TMP/dr.out" "skills [1-9]" "doctor counts skills from the studio directory"
  assert_contains "$TMP/dr.out" "agents [1-9]" "doctor counts agents from the studio directory"
  assert_contains "$TMP/dr.out" "superpowers@claude-plugins-official enabled, not yet fetched" \
    "an enabled but uncached plugin is a warning"
  assert_contains "$TMP/dr.out" "launch claude-gd once" "the warning names the shim to launch"

  mkdir -p "$TMP/dr/plugins/cache/claude-plugins-official/superpowers/6.3.0"
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dr" > "$TMP/dr2.out" 2>&1
  assert_contains "$TMP/dr2.out" "superpowers@claude-plugins-official ok 6.3.0" \
    "a cached plugin is reported with its version"

  printf '{ "model": "opus", "enabledPlugins": { "superpowers@claude-plugins-official": true } }\n' \
    > "$TMP/dr/settings.json"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dr" > "$TMP/dr3.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when a required plugin is not enabled"
  assert_contains "$TMP/dr3.out" "godot-prompter@skillsmith NOT ENABLED" "doctor names the missing plugin"
}

test_doctor_plugin_name_mismatch() {
  SB="$TMP/sandbox-name"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  printf '{ "name": "wrong", "version": "0.1.0", "description": "x" }\n' \
    > "$SB/studios/general/.claude-plugin/plugin.json"
  sh "$SB/install.sh" general --target "$TMP/nm" --shim-dir "$TMP/bin-nm" >/dev/null 2>&1 || true
  status=0
  sh "$SB/doctor.sh" general --target "$TMP/nm" > "$TMP/nm.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the plugin name does not match the studio"
  assert_contains "$TMP/nm.out" "does not match" "doctor explains the mismatch"
}

# An empty shim name makes SHIM_PATH "<shim dir>/", which canon_path folds to
# the shim directory itself — a manifest entry equal to that directory would
# then count as in scope. install.sh already dies on it; uninstall.sh must
# refuse the same way, before it removes anything.
test_uninstall_refuses_empty_shim_name() {
  SB="$TMP/sandbox-shim"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  sh "$SB/install.sh" general --target "$TMP/noshim" --shim-dir "$TMP/bin-noshim" >/dev/null 2>&1
  assert_file "$TMP/noshim/.omega-ai-manifest" "sandbox install wrote a manifest"
  printf '{ "name": "general", "target": "~/.claude-general", "shim": "" }\n' \
    > "$SB/studios/general/studio.json"

  status=0
  sh "$SB/uninstall.sh" general --target "$TMP/noshim" --shim-dir "$TMP/bin-noshim" \
    > "$TMP/noshim.out" 2>&1 || status=$?
  assert_eq "1" "$status" "uninstall refuses a studio.json with an empty shim name"
  assert_contains "$TMP/noshim.out" "has no shim name" "uninstall says why"
  assert_file "$TMP/noshim/CLAUDE.md" "refused uninstall removes nothing from the config root"
  assert_file "$TMP/noshim/.omega-ai-manifest" "refused uninstall keeps the manifest"
  assert_file "$TMP/bin-noshim/claude-gen" "refused uninstall keeps the shim"

  status=0
  sh "$SB/uninstall.sh" general --target "$TMP/noshim" --shim-dir "$TMP/bin-noshim" --purge --yes \
    >/dev/null 2>&1 || status=$?
  assert_eq "1" "$status" "uninstall --purge refuses an empty shim name too"
  assert_file "$TMP/noshim/CLAUDE.md" "refused purge removes nothing"
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

  sh "$SB/install.sh" general --target "$TMP/brk" --shim-dir "$TMP/bin-brk" >/dev/null 2>&1
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

# --- A --target that is a symlink into the repository must be refused. ---
# Runs against a sandbox copy of the repository so the checkout is never at
# risk. The install is a dry run on purpose: the guard runs before the dry-run
# branch, so its verdict is the exit status either way, while an unguarded wet
# run renders studios/general/CLAUDE.md onto itself and never terminates.
test_install_refuses_symlinked_target() {
  SB="$TMP/sandbox-link"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  # The link lives outside the sandbox repository; only its destination is inside.
  ln -s "$SB/studios/general" "$TMP/evil"

  status=0
  ( sh "$SB/install.sh" general --target "$TMP/evil" --shim-dir "$TMP/bin-evil" --dry-run \
      > "$TMP/evil.out" 2>&1 ) || status=$?
  assert_eq "1" "$status" "install refuses a --target that links into the repository"
  assert_contains "$TMP/evil.out" "refusing to install into the repository itself" \
    "the refusal comes from the guard"

  mkdir -p "$TMP/bin-evil"
  printf 'decoy\n' > "$TMP/bin-evil/claude-gen"
  status=0
  ( sh "$SB/uninstall.sh" general --target "$TMP/evil" --shim-dir "$TMP/bin-evil" \
      >/dev/null 2>&1 ) || status=$?
  assert_eq "1" "$status" "uninstall refuses a --target that links into the repository"
  assert_file "$TMP/bin-evil/claude-gen" "refused uninstall deletes no shim"
  assert_file "$SB/studios/general/CLAUDE.md" "refused uninstall strips nothing from the studio"
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
  assert_missing "$FAKE/bin/claude-gen" "the matching shim is still removed"
  assert_missing "$FAKE/.claude-general/.omega-ai-manifest" "the manifest is still removed"
}

# A relative --target used to be baked into the shim and the manifest as
# typed, so the install only worked from the directory it was run in; a
# trailing slash on the studio name installed and then failed the doctor.
test_install_normalizes_name_and_target() {
  status=0
  sh "$REPO_ROOT/install.sh" general/ --target "$TMP/slash" --shim-dir "$TMP/bin-slash" \
    > "$TMP/slash.out" 2>&1 || status=$?
  assert_eq "0" "$status" "a studio name with a trailing slash installs and passes the doctor"
  assert_not_contains "$TMP/slash.out" "does not match" "no plugin-name mismatch is reported"
  assert_contains "$TMP/slash/CLAUDE.md" "studios/general/CLAUDE.md" "the rendered header names the studio cleanly"
  assert_status 1 "a studio given as a path is refused" -- \
    sh "$REPO_ROOT/install.sh" studios/general --target "$TMP/slash2" --shim-dir "$TMP/bin-slash"

  mkdir -p "$TMP/relcwd"
  ( cd "$TMP/relcwd" && sh "$REPO_ROOT/install.sh" general --target rel/root --shim-dir rel/bin ) >/dev/null 2>&1
  assert_file "$TMP/relcwd/rel/root/CLAUDE.md" "a relative --target installs under the current directory"
  assert_contains "$TMP/relcwd/rel/bin/claude-gen" "CLAUDE_CONFIG_DIR=\"$TMP/relcwd/rel/root\"" \
    "the shim carries the absolute config root"
  assert_contains "$TMP/relcwd/rel/root/.omega-ai-manifest" "^$TMP/relcwd/rel/root/CLAUDE.md" \
    "the manifest records absolute paths"
  ( cd "$TMP" && sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/relcwd/rel/root" \
      --shim-dir "$TMP/relcwd/rel/bin" ) >/dev/null 2>&1
  assert_missing "$TMP/relcwd/rel/root/CLAUDE.md" "uninstall from another directory removes the install"
  assert_missing "$TMP/relcwd/rel/bin/claude-gen" "uninstall from another directory removes the shim"

  sh "$REPO_ROOT/install.sh" general --target "$TMP/trail/" --shim-dir "$TMP/bin-trail" >/dev/null 2>&1
  assert_contains "$TMP/trail/.omega-ai-manifest" "^$TMP/trail/CLAUDE.md" \
    "a trailing slash on --target is not doubled in the manifest"
}

# resolve_studio_target's die must not be masked by canon_path swallowing its
# exit status: TARGET="$(canon_path "$(resolve_studio_target ...)")" ran
# canon_path on an empty string, which succeeded — set -e never fired, so
# every script pressed on with TARGET="" and surfaced a confusing downstream
# message (guard_target's "install target is empty", uninstall's "nothing
# installed at", doctor's "config root does not exist", sync-memory's "no
# memory directory at") instead of resolve_studio_target's own die message.
test_resolve_studio_target_failure_is_not_masked() {
  SB="$TMP/sandbox-resolve"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" \
     "$REPO_ROOT/sync-memory.sh" "$SB/"
  printf '{ "name": "general", "shim": "claude-gen" }\n' > "$SB/studios/general/studio.json"

  status=0
  sh "$SB/install.sh" general --shim-dir "$TMP/rst-bin" \
    > "$TMP/rst-install.out" 2>&1 || status=$?
  assert_eq "1" "$status" "install fails when studio.json declares no target"
  assert_contains "$TMP/rst-install.out" "studio.json declares no target: general" \
    "install surfaces resolve_studio_target's own die message"
  assert_not_contains "$TMP/rst-install.out" "install target is empty" \
    "install does not fall through to guard_target's message"

  status=0
  sh "$SB/uninstall.sh" general --shim-dir "$TMP/rst-bin" \
    > "$TMP/rst-uninstall.out" 2>&1 || status=$?
  assert_eq "1" "$status" "uninstall fails when studio.json declares no target"
  assert_contains "$TMP/rst-uninstall.out" "studio.json declares no target: general" \
    "uninstall surfaces resolve_studio_target's own die message"
  assert_not_contains "$TMP/rst-uninstall.out" "install target is empty" \
    "uninstall does not fall through to guard_target's message"

  status=0
  sh "$SB/doctor.sh" general > "$TMP/rst-doctor.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when studio.json declares no target"
  assert_contains "$TMP/rst-doctor.out" "studio.json declares no target: general" \
    "doctor surfaces resolve_studio_target's own die message"
  assert_not_contains "$TMP/rst-doctor.out" "config root does not exist" \
    "doctor does not fall through to the missing-root message"

  status=0
  sh "$SB/sync-memory.sh" general > "$TMP/rst-sync.out" 2>&1 || status=$?
  assert_eq "1" "$status" "sync-memory fails when studio.json declares no target"
  assert_contains "$TMP/rst-sync.out" "studio.json declares no target: general" \
    "sync-memory surfaces resolve_studio_target's own die message"
  assert_not_contains "$TMP/rst-sync.out" "no memory directory at" \
    "sync-memory does not fall through to the missing-memory message"
}

# CLAUDE.md and settings.json used to be written through whatever was at the
# destination: a symlink there (a user's own link into ~/.claude, say) had
# the linked file overwritten while the link survived. install_entries
# removes its destination first; the two rendered files must do the same.
test_install_replaces_symlinked_files() {
  mkdir -p "$TMP/outside-cfg" "$TMP/sym"
  printf 'my global claude.md\n' > "$TMP/outside-cfg/CLAUDE.md"
  printf '{"mine":true}\n' > "$TMP/outside-cfg/settings.json"
  ln -s "$TMP/outside-cfg/CLAUDE.md" "$TMP/sym/CLAUDE.md"
  ln -s "$TMP/outside-cfg/settings.json" "$TMP/sym/settings.json"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/sym" --shim-dir "$TMP/bin-sym" >/dev/null 2>&1
  assert_eq "my global claude.md" "$(cat "$TMP/outside-cfg/CLAUDE.md")" \
    "the file a CLAUDE.md link pointed at is untouched"
  assert_eq '{"mine":true}' "$(cat "$TMP/outside-cfg/settings.json")" \
    "the file a settings.json link pointed at is untouched"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/sym/CLAUDE.md" ]; then _fail "CLAUDE.md is a regular file after install"; else _pass "CLAUDE.md is a regular file after install"; fi
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$TMP/sym/settings.json" ]; then _fail "settings.json is a regular file after install"; else _pass "settings.json is a regular file after install"; fi
  assert_contains "$TMP/sym/CLAUDE.md" "General Studio" "CLAUDE.md is rendered in place"
}

# --purge used to rm -rf any directory that passed guard_target, installed
# or not; and on a symlinked target it removed only the link.
test_uninstall_purge_requires_manifest() {
  mkdir -p "$TMP/notours/important"
  printf 'keep\n' > "$TMP/notours/important/file.txt"
  status=0
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/notours" --shim-dir "$TMP/bin-no" --purge --yes \
    > "$TMP/notours.out" 2>&1 || status=$?
  assert_eq "1" "$status" "purge refuses a directory with no manifest"
  assert_file "$TMP/notours/important/file.txt" "a refused purge deletes nothing"
  assert_contains "$TMP/notours.out" "no manifest" "the refusal names the missing manifest"
}

test_uninstall_purge_symlinked_target() {
  mkdir -p "$TMP/realroot"
  ln -s "$TMP/realroot" "$TMP/linkroot"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/linkroot" --shim-dir "$TMP/bin-link" >/dev/null 2>&1
  assert_file "$TMP/realroot/CLAUDE.md" "install through a link lands in the real root"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/linkroot" --shim-dir "$TMP/bin-link" --purge --yes >/dev/null 2>&1
  assert_missing "$TMP/realroot" "purge removes the real root behind the link"
  assert_missing "$TMP/linkroot" "purge removes the link too"
  assert_missing "$TMP/bin-link/claude-gen" "purge removes the shim"
}

test_doctor_fails_on_missing_files() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dmf" --shim-dir "$TMP/bin-dmf" >/dev/null 2>&1
  rm "$TMP/dmf/CLAUDE.md"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dmf" > "$TMP/dmf.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when CLAUDE.md is missing"
  assert_contains "$TMP/dmf.out" "CLAUDE.md:    MISSING" "doctor reports the missing CLAUDE.md"
}

# ~/.claude itself can be a symlink (dotfiles), and a link destination can be
# spelled with '..'; the textual comparison used to miss both. Fake HOME only.
test_doctor_detects_leak_through_symlinked_dot_claude() {
  FAKE="$TMP/fakehome-dot"
  mkdir -p "$FAKE/dotfiles/claude"
  printf '{}\n' > "$FAKE/dotfiles/claude/settings.json"
  ln -s "$FAKE/dotfiles/claude" "$FAKE/.claude"
  ( HOME="$FAKE" sh "$REPO_ROOT/install.sh" general --target "$FAKE/root" --shim-dir "$FAKE/bin" ) >/dev/null 2>&1
  ln -s "$FAKE/dotfiles/claude/settings.json" "$FAKE/root/leak"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor exits 1 on a link into the directory ~/.claude points at"
  assert_contains "$TMP/dot.out" "root/leak ->" "doctor names the leaking link"
  assert_not_contains "$TMP/dot.out" "leakage: none" "doctor does not claim the root is clean"
  rm "$FAKE/root/leak"
  ln -s "$FAKE/root/../.claude/settings.json" "$FAKE/root/leak2"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor exits 1 on a '..'-spelled link into ~/.claude"
  assert_contains "$TMP/dot2.out" "root/leak2 ->" "doctor names the '..'-spelled leaking link"
  assert_not_contains "$TMP/dot2.out" "leakage: none" "doctor does not claim the root is clean"
  rm "$FAKE/root/leak2"
  status=0
  ( HOME="$FAKE" sh "$REPO_ROOT/doctor.sh" general --target "$FAKE/root" ) > "$TMP/dot3.out" 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes again with the probes removed"
}

# A plugin id was interpolated into a grep pattern: "foo.bar@m" matched
# "fooXbar@m" and an unenabled plugin was reported enabled.
test_doctor_matches_plugin_ids_literally() {
  SB="$TMP/sandbox-ids"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  printf 'plugin foo.bar@market\n' > "$SB/studios/general/requires.txt"
  printf '{ "enabledPlugins": { "fooXbar@market": true } }\n' > "$SB/studios/general/settings.json"
  sh "$SB/install.sh" general --target "$TMP/ids" --shim-dir "$TMP/bin-ids" >/dev/null 2>&1 || true
  status=0
  sh "$SB/doctor.sh" general --target "$TMP/ids" > "$TMP/ids.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the enabled id only matches as a pattern"
  assert_contains "$TMP/ids.out" "foo.bar@market NOT ENABLED" "doctor names the plugin as not enabled"

  # A two-stage grep (id line, then a separate ": true" line) loses
  # adjacency: on one line, a disabled id followed by an unrelated enabled id
  # must not read as the disabled id being enabled.
  SB2="$TMP/sandbox-ids-adjacent"
  mkdir -p "$SB2"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB2/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB2/"
  printf 'plugin foo.bar@market\n' > "$SB2/studios/general/requires.txt"
  printf '{ "enabledPlugins": { "foo.bar@market": false, "other@x": true } }\n' \
    > "$SB2/studios/general/settings.json"
  sh "$SB2/install.sh" general --target "$TMP/ids-adj" --shim-dir "$TMP/bin-ids-adj" >/dev/null 2>&1 || true
  status=0
  sh "$SB2/doctor.sh" general --target "$TMP/ids-adj" > "$TMP/ids-adj.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the id's own line is disabled despite an unrelated enabled id"
  assert_contains "$TMP/ids-adj.out" "foo.bar@market NOT ENABLED" \
    "doctor does not borrow 'true' from an unrelated adjacent id"
}

# The pre-plugin installer linked skills/, agents/, commands/ and hooks/ into
# the root. After profiles/ disappeared those links dangle, and the doctor
# used to report such a root as healthy.
test_doctor_flags_stale_layout() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/stale" --shim-dir "$TMP/bin-stale" >/dev/null 2>&1
  mkdir -p "$TMP/stale/skills"
  ln -s "$TMP/gone/skill" "$TMP/stale/skills/old-skill"
  printf '%s\n' "$TMP/stale/skills/old-skill" >> "$TMP/stale/.omega-ai-manifest"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/stale" > "$TMP/stale.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a skills/ link from the previous installer"
  assert_contains "$TMP/stale.out" "stale layout from a previous installer" "doctor explains the stale layout"
  assert_contains "$TMP/stale.out" "run install.sh general again" "doctor says how to fix it"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/stale" --shim-dir "$TMP/bin-stale" >/dev/null 2>&1
  assert_missing "$TMP/stale/skills/old-skill" "reinstall removes the recorded stale link"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/stale" >/dev/null 2>&1 || status=$?
  assert_eq "0" "$status" "doctor passes after the reinstall"
}

# A reinstall used to remove the previous install first and discover a
# missing studio file only while rendering — leaving a 0-byte manifest, a
# half-rendered CLAUDE.md nothing records, and no settings.json or shim.
test_reinstall_keeps_previous_install_when_studio_is_broken() {
  SB="$TMP/sandbox-atomic"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  sh "$SB/install.sh" general --target "$TMP/atomic" --shim-dir "$TMP/bin-atomic" >/dev/null 2>&1
  assert_file "$TMP/atomic/CLAUDE.md" "first install succeeds"
  rm "$SB/studios/general/CLAUDE.md"
  status=0
  sh "$SB/install.sh" general --target "$TMP/atomic" --shim-dir "$TMP/bin-atomic" > "$TMP/atomic.out" 2>&1 || status=$?
  assert_eq "1" "$status" "reinstall fails when the studio has no CLAUDE.md"
  assert_contains "$TMP/atomic.out" "has no CLAUDE.md" "the failure names the missing file"
  assert_file "$TMP/atomic/CLAUDE.md" "the previous CLAUDE.md is still installed"
  assert_file "$TMP/atomic/settings.json" "the previous settings.json is still installed"
  assert_file "$TMP/bin-atomic/claude-gen" "the previous shim is still installed"
  assert_contains "$TMP/atomic/.omega-ai-manifest" "CLAUDE.md" "the previous manifest is intact"
}

# install_entries' output used to be word-split, so a path with a space
# became two manifest lines that uninstall then skipped as out of scope.
test_install_path_with_space() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/with space/root" --shim-dir "$TMP/with space/bin" >/dev/null 2>&1
  assert_symlink "$TMP/with space/root/memory/MEMORY.md" "a target with a space gets its links"
  assert_eq "1" "$(grep -c "^$TMP/with space/root/memory/MEMORY.md\$" "$TMP/with space/root/.omega-ai-manifest")" \
    "the manifest records the whole path on one line"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/with space/root" --shim-dir "$TMP/with space/bin" >/dev/null 2>&1
  assert_missing "$TMP/with space/root/memory/MEMORY.md" "uninstall removes the link under a path with a space"
  assert_missing "$TMP/with space/root/bin/studio-state" "uninstall removes the bin link under a path with a space"
  assert_missing "$TMP/with space/bin/claude-gd" "uninstall removes the shim under a path with a space"
}

# Two roots can share a shim directory; the shim launches whichever was
# installed last. Uninstalling the other root used to delete it anyway.
test_uninstall_keeps_shim_of_another_root() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/shA" --shim-dir "$TMP/bin-shared" >/dev/null 2>&1
  sh "$REPO_ROOT/install.sh" general --target "$TMP/shB" --shim-dir "$TMP/bin-shared" >/dev/null 2>&1
  assert_contains "$TMP/bin-shared/claude-gen" "CLAUDE_CONFIG_DIR=\"$TMP/shB\"" "the shared shim launches the second root"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/shA" > "$TMP/shA.out" 2>&1
  assert_missing "$TMP/shA/CLAUDE.md" "the first root is uninstalled"
  assert_file "$TMP/bin-shared/claude-gen" "the shim that launches the second root survives"
  assert_contains "$TMP/shA.out" "keeping it" "uninstall says why the shim stays"
  sh "$REPO_ROOT/uninstall.sh" general --target "$TMP/shB" >/dev/null 2>&1
  assert_missing "$TMP/bin-shared/claude-gen" "uninstall without --shim-dir removes the recorded shim"
}

run_tests test_studio_contract test_install_unknown_studio test_install_guard \
  test_install_guards_shim_dir test_install_refuses_traversal_target \
  test_install_refuses_traversal_shim_dir test_install_refuses_symlinked_target \
  test_install_dry_run test_install_content \
  test_install_precedence test_install_copy_mode test_install_reinstall_cleans_stale_entries \
  test_install_accepts_no_mcp test_settings_backup test_shim \
  test_doctor test_doctor_detects_leak test_doctor_reports_no_plugins \
  test_doctor_plugin_report test_doctor_plugin_name_mismatch \
  test_option_value_required test_uninstall test_uninstall_scopes_manifest_entries \
  test_uninstall_skips_traversal_manifest_entries test_uninstall_refuses_empty_shim_name \
  test_uninstall_purge test_two_studios_independent test_all_scripts_validate_the_studio \
  test_install_normalizes_name_and_target test_resolve_studio_target_failure_is_not_masked \
  test_install_replaces_symlinked_files \
  test_uninstall_purge_requires_manifest test_uninstall_purge_symlinked_target \
  test_doctor_fails_on_missing_files test_doctor_detects_leak_through_symlinked_dot_claude test_doctor_matches_plugin_ids_literally test_doctor_flags_stale_layout \
  test_reinstall_keeps_previous_install_when_studio_is_broken test_install_path_with_space \
  test_uninstall_keeps_shim_of_another_root

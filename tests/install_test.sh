#!/bin/sh
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

# Physical path: the installer canonicalizes the target, so assertions that
# quote $TMP must use the same spelling (/var -> /private/var on macOS).
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Every install in this file runs against stubs for claude, node and Godot,
# so MCP registration is exercised without a real Claude Code install, Node,
# or an engine. The claude stub records each call with its CLAUDE_CONFIG_DIR
# in $STUBS/claude.calls and writes or removes the .claude.json entry a real
# `claude mcp add|remove --scope user` would. The Godot stub is reached only
# through GODOT_PATH, never PATH, so "no engine" cases can clear it.
STUBS="$TMP/stubs"
mkdir -p "$STUBS/engine"
cat > "$STUBS/claude" <<'STUB'
#!/bin/sh
printf 'CLAUDE_CONFIG_DIR=%s claude %s\n' "${CLAUDE_CONFIG_DIR:-}" "$*" >> "$(dirname "$0")/claude.calls"
case "${1:-} ${2:-}" in
  "mcp add")
    mkdir -p "${CLAUDE_CONFIG_DIR:-.}"
    printf '{ "mcpServers": { "godot": { "command": "npx", "args": ["-y", "@coding-solo/godot-mcp"] } } }\n' \
      > "${CLAUDE_CONFIG_DIR:-.}/.claude.json" ;;
  "mcp remove")
    rm -f "${CLAUDE_CONFIG_DIR:-.}/.claude.json" ;;
esac
exit 0
STUB
printf '#!/bin/sh\necho "${STUB_NODE_VERSION:-v20.11.0}"\n' > "$STUBS/node"
printf '#!/bin/sh\necho "Godot Engine v4.3.stable (stub)"\n' > "$STUBS/engine/godot"
chmod +x "$STUBS/claude" "$STUBS/node" "$STUBS/engine/godot"
PATH="$STUBS:$PATH"; export PATH
GODOT_PATH="$STUBS/engine/godot"; export GODOT_PATH
# Tests that must see no engine at all also drop any real godot from PATH:
NO_ENGINE_PATH="$STUBS:/usr/bin:/bin"

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
  assert_file "$TMP/cp/global/.claude-plugin/plugin.json" "copy mode snapshots the global plugin under the target"
  for tool in omega-mode omega-caffeine; do
    assert_file "$TMP/cp/global/bin/$tool" "the global snapshot carries $tool"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -x "$TMP/cp/global/bin/$tool" ]; then
      _pass "the snapshot's $tool is executable"
    else
      _fail "the snapshot's $tool is executable"
    fi
  done
  assert_file "$TMP/cp/global/hooks/hooks.json" "the global snapshot carries the hooks"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/cp/global/hooks/pre-tool-use.sh" ]; then
    _pass "the snapshot's pre-tool-use.sh is executable"
  else
    _fail "the snapshot's pre-tool-use.sh is executable"
  fi
  assert_contains "$TMP/bin-cp/claude-gd" "OMEGA_GLOBAL_ROOT=\"$TMP/cp/global\"" \
    "copy-mode shim points the global root at the snapshot"
  assert_contains "$TMP/cp/.omega-ai-manifest" "$TMP/cp/global" "manifest records the global snapshot"
  assert_eq "# mode=copy" "$(sed -n '1p' "$TMP/cp/.omega-ai-manifest")" "copy mode is recorded in the manifest"

  # The runtime mode directory (${CLAUDE_CONFIG_DIR}/omega/modes) sits beside
  # the global snapshot, not inside it: a reinstall's `rm -rf "$GLOBAL_DIR"`
  # must never delete a live session's mode file.
  CLAUDE_CONFIG_DIR="$TMP/cp" sh "$TMP/cp/global/bin/omega-mode" --session cpsess set parallel
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/cp" --shim-dir "$TMP/bin-cp" --mode copy >/dev/null 2>&1
  assert_file "$TMP/cp/omega/modes/cpsess" "a reinstall keeps live mode files"
  CLAUDE_CONFIG_DIR="$TMP/cp" sh "$TMP/cp/global/bin/omega-mode" --session cpsess clear --all

  # The snapshot is a manifest entry, so uninstall removes it with the rest.
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/cp" --shim-dir "$TMP/bin-cp" >/dev/null
  assert_missing "$TMP/cp/studio" "uninstall removes the copy-mode snapshot"
  assert_missing "$TMP/cp/global" "uninstall removes the global plugin snapshot"
}

# A reinstall with a different --shim-dir must remove the shim the previous
# manifest recorded, not skip it as out of scope: the installer used to pass
# the new shim path to manifest_remove, orphaning the old one.
test_install_reinstall_new_shim_dir_removes_old_shim() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/t" --shim-dir "$TMP/bin1" >/dev/null 2>&1
  assert_file "$TMP/bin1/claude-gen" "first install writes the shim in bin1"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/t" --shim-dir "$TMP/bin2" >/dev/null 2>&1
  assert_missing "$TMP/bin1/claude-gen" "reinstall removes the shim the previous manifest recorded"
  assert_file "$TMP/bin2/claude-gen" "reinstall writes the shim in the new directory"
  assert_eq "# shim=$TMP/bin2/claude-gen" "$(sed -n '2p' "$TMP/t/.omega-ai-manifest")" \
    "the manifest records the new shim path"
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

test_install_registers_mcp() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcp" --shim-dir "$TMP/bin-mcp" > "$TMP/mcp.out" 2>&1
  assert_contains "$TMP/mcp/.omega-ai-manifest" "^mcp godot\$" "manifest records the MCP server"
  assert_contains "$STUBS/claude.calls" \
    "^CLAUDE_CONFIG_DIR=$TMP/mcp claude mcp add --scope user godot -e GODOT_PATH=$STUBS/engine/godot -- npx -y @coding-solo/godot-mcp\$" \
    "claude mcp add runs at user scope inside the config root with the resolved binary"
  assert_contains "$TMP/mcp.out" "mcp:      godot registered" "install reports the registration"
  assert_contains "$TMP/mcp.out" "mcp:          godot registered" "the doctor run at the end sees the server"
}

test_install_skips_mcp_without_node_18() {
  : > "$STUBS/claude.calls"
  STUB_NODE_VERSION=v16.20.0 sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcp16" --shim-dir "$TMP/bin-mcp16" > "$TMP/mcp16.out" 2>&1
  assert_not_contains "$TMP/mcp16/.omega-ai-manifest" "^mcp " "no mcp line without node 18"
  assert_not_contains "$STUBS/claude.calls" "mcp add" "claude mcp add is not run"
  assert_contains "$TMP/mcp16.out" "mcp:      skipped (node 18+ not found" "install explains the skip"
}

test_install_skips_mcp_without_engine() {
  : > "$STUBS/claude.calls"
  mkdir -p "$TMP/no-apps"
  GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$NO_ENGINE_PATH" \
    sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpng" --shim-dir "$TMP/bin-mcpng" > "$TMP/mcpng.out" 2>&1
  assert_not_contains "$TMP/mcpng/.omega-ai-manifest" "^mcp " "no mcp line without an engine binary"
  assert_not_contains "$STUBS/claude.calls" "mcp add" "claude mcp add is not run without an engine"
  assert_contains "$TMP/mcpng.out" "mcp:      skipped (no Godot binary found" "install explains the skip"
}

test_install_no_mcp_flag_skips_registration() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpoff" --shim-dir "$TMP/bin-mcpoff" --no-mcp > "$TMP/mcpoff.out" 2>&1
  assert_not_contains "$STUBS/claude.calls" "mcp add" "--no-mcp never calls claude mcp add"
  assert_contains "$TMP/mcpoff.out" "mcp:      skipped (--no-mcp)" "install reports the flag"
}

test_install_general_has_no_mcp() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gmcp" --shim-dir "$TMP/bin-gmcp" > "$TMP/gmcp.out" 2>&1
  assert_contains "$TMP/gmcp.out" "mcp:      none (studio declares no engine" "a studio without an engine registers nothing"
}

test_reinstall_reregisters_mcp_once() {
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpre" --shim-dir "$TMP/bin-mcpre" >/dev/null 2>&1
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpre" --shim-dir "$TMP/bin-mcpre" >/dev/null 2>&1
  assert_eq "2" "$(grep -c 'mcp add' "$STUBS/claude.calls")" "each install registers"
  assert_eq "1" "$(grep -c 'mcp remove --scope user godot' "$STUBS/claude.calls")" "a reinstall unregisters the previous server first"
  assert_eq "1" "$(grep -c '^mcp godot$' "$TMP/mcpre/.omega-ai-manifest")" "the manifest carries one mcp line"
}

test_uninstall_removes_mcp() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcpun" --shim-dir "$TMP/bin-mcpun" >/dev/null 2>&1
  : > "$STUBS/claude.calls"
  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/mcpun" --shim-dir "$TMP/bin-mcpun" >/dev/null 2>&1
  assert_contains "$STUBS/claude.calls" "^CLAUDE_CONFIG_DIR=$TMP/mcpun claude mcp remove --scope user godot\$" \
    "uninstall unregisters the server inside the config root"
}

# An aborted --purge (a reply other than y/Y) must leave a registered MCP
# server alone: unregistering it is an irreversible side effect the
# confirmation prompt exists to gate.
test_uninstall_purge_confirmation_gates_mcp_removal() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/mcppurge" --shim-dir "$TMP/bin-mcppurge" >/dev/null 2>&1
  assert_file "$TMP/mcppurge/.claude.json" "install registered the server"
  : > "$STUBS/claude.calls"
  status=0
  printf 'n\n' | sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/mcppurge" --shim-dir "$TMP/bin-mcppurge" \
    --purge > "$TMP/mcppurge-abort.out" 2>&1 || status=$?
  assert_eq "1" "$status" "an aborted purge exits non-zero"
  assert_not_contains "$STUBS/claude.calls" "mcp remove" "an aborted purge never unregisters the server"
  assert_file "$TMP/mcppurge/.claude.json" "an aborted purge leaves the registered server in place"

  sh "$REPO_ROOT/uninstall.sh" game-dev --target "$TMP/mcppurge" --shim-dir "$TMP/bin-mcppurge" \
    --purge --yes >/dev/null 2>&1
  assert_contains "$STUBS/claude.calls" "mcp remove --scope user godot" \
    "a confirmed purge unregisters the server"
  assert_missing "$TMP/mcppurge" "a confirmed purge removes the config root"
}

# fake_cache ROOT — a plugin cache under ROOT holding every skill and agent
# game-dev's requires.txt declares, laid out as Claude Code lays it out.
fake_cache() {
  req="$REPO_ROOT/studios/game-dev/requires.txt"
  for kind in skill agent; do
    for ref in $(requires_of "$req" "$kind"); do
      plugin="${ref%%:*}"; name="${ref#*:}"
      case "$plugin" in
        superpowers) v="$1/plugins/cache/claude-plugins-official/superpowers/6.3.0" ;;
        *) v="$1/plugins/cache/skillsmith/$plugin/1.9.0" ;;
      esac
      if [ "$kind" = skill ]; then
        mkdir -p "$v/skills/$name"; : > "$v/skills/$name/SKILL.md"
      else
        mkdir -p "$v/agents"; : > "$v/agents/$name.md"
      fi
    done
  done
}

test_doctor_delegations() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dd" --shim-dir "$TMP/bin-dd" >/dev/null 2>&1
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd0.out" 2>&1 || status=$?
  assert_eq "0" "$status" "no plugin cache is a warning, not a failure"
  assert_contains "$TMP/dd0.out" "delegations:  not checked — plugins not yet fetched; launch claude-gd once" \
    "doctor says why delegations were not checked"

  fake_cache "$TMP/dd"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd1.out" 2>&1 || status=$?
  assert_eq "0" "$status" "every declared name resolving passes"
  assert_contains "$TMP/dd1.out" "^  superpowers: [0-9][0-9]* of [0-9][0-9]* resolved" "doctor tallies superpowers delegations"
  assert_contains "$TMP/dd1.out" "^  godot-prompter: [0-9][0-9]* of [0-9][0-9]* resolved" "doctor tallies godot-prompter delegations"
  assert_not_contains "$TMP/dd1.out" "MISSING" "nothing is missing"
  sp="$(grep '^  superpowers: ' "$TMP/dd1.out" | sed 's/^  superpowers: \([0-9]*\) of \([0-9]*\).*/\1 \2/')"
  assert_eq "${sp% *}" "${sp#* }" "resolved equals declared for superpowers"

  rm -rf "$TMP/dd/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/test-driven-development"
  rm -f "$TMP/dd/plugins/cache/skillsmith/godot-prompter/1.9.0/agents/godot-csharp-engineer.md"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dd" > "$TMP/dd2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "a missing delegated name fails the doctor"
  assert_contains "$TMP/dd2.out" "^  superpowers:test-driven-development MISSING from the cached plugin" "the missing skill is named"
  assert_contains "$TMP/dd2.out" "^  godot-prompter:godot-csharp-engineer MISSING from the cached plugin" "the missing agent is named"
}

test_doctor_engine_and_mcp_rows() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dre" --shim-dir "$TMP/bin-dre" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre.out" 2>&1
  assert_contains "$TMP/dre.out" "engine:       godot4 at $STUBS/engine/godot" "doctor reports the resolved engine binary"
  assert_contains "$TMP/dre.out" "mcp:          godot registered" "doctor reads the server from .claude.json"
  rm -f "$TMP/dre/.claude.json"
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre2.out" 2>&1
  assert_contains "$TMP/dre2.out" "mcp:          none (optional" "doctor reports a missing server as optional"
  mkdir -p "$TMP/no-apps"
  status=0
  GODOT_PATH="" GODOT_APP_DIR="$TMP/no-apps" PATH="$NO_ENGINE_PATH" \
    sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dre" > "$TMP/dre3.out" 2>&1 || status=$?
  assert_eq "0" "$status" "a missing engine binary is a warning, not a failure"
  assert_contains "$TMP/dre3.out" "engine:       godot4 — no binary found (set GODOT_PATH)" "doctor explains how to fix the engine"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen-dr" --shim-dir "$TMP/bin-gen-dr" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen-dr" > "$TMP/gdr.out" 2>&1
  assert_not_contains "$TMP/gdr.out" "^engine:" "a studio without an engine has no engine row"
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
  assert_contains "$TMP/bin/claude-gd" "PATH=\"$TMP/gd/bin:\$OMEGA_GLOBAL_ROOT/bin:\$PATH\"" \
    "shim prefixes PATH with the target bin and the global plugin's bin"
  assert_contains "$TMP/bin/claude-gd" "OMEGA_STUDIO_ROOT=\"$REPO_ROOT/studios/game-dev\"" \
    "shim exports the studio root"
  assert_contains "$TMP/bin/claude-gd" "OMEGA_GLOBAL_ROOT=\"$REPO_ROOT/shared/omega\"" \
    "shim exports the global plugin root"
  assert_contains "$TMP/bin/claude-gd" "export OMEGA_STUDIO_ROOT OMEGA_GLOBAL_ROOT" "shim exports both roots"
  assert_contains "$TMP/bin/claude-gd" "exec claude --plugin-dir \"\$OMEGA_STUDIO_ROOT\" --plugin-dir \"\$OMEGA_GLOBAL_ROOT\" \"\$@\"" \
    "shim loads the studio and the global plugin and passes arguments through"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/bin/claude-gd" ]; then _pass "shim is executable"; else _fail "shim is executable"; fi
  assert_contains "$TMP/gd/.omega-ai-manifest" "bin/claude-gd" "manifest records the shim"
  assert_missing "$TMP/gd/global" "symlink mode puts nothing of the global plugin under the target"
}

test_doctor() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen" --shim-dir "$TMP/bin" >/dev/null 2>&1
  assert_not_contains "$TMP/gen/CLAUDE.md" "@memory/MEMORY.md" "a studio without memory/ imports nothing"
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen" > "$TMP/doctor.out" 2>&1
  assert_contains "$TMP/doctor.out" "$TMP/gen" "doctor reports the resolved config root"
  assert_contains "$TMP/doctor.out" "leakage: none" "doctor finds no leak into ~/.claude"
  assert_contains "$TMP/doctor.out" "global plugin: omega 0.1.0   skills 6  hooks present" \
    "doctor reports the global plugin as the shim loads it"
  assert_contains "$TMP/doctor.out" "shim:         ok" "doctor accepts the two-plugin shim"
  # A shim from before the global plugin: the doctor names the gap and
  # fails. A second, independent install — never the shared $TMP/bin/claude-gen
  # the assertions above (and other tests) rely on — is degraded so this
  # test does not rewrite a fixture other tests use.
  sh "$REPO_ROOT/install.sh" general --target "$TMP/gen-old" --shim-dir "$TMP/bin-old" >/dev/null 2>&1
  sed 's/ --plugin-dir "\$OMEGA_GLOBAL_ROOT"//' "$TMP/bin-old/claude-gen" > "$TMP/bin-old/claude-gen.new"
  mv "$TMP/bin-old/claude-gen.new" "$TMP/bin-old/claude-gen"
  assert_status 1 "doctor fails on a shim without the global plugin" -- \
    sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen-old"
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/gen-old" > "$TMP/doctor2.out" 2>&1
  assert_contains "$TMP/doctor2.out" "shim:         stale (no global plugin)" "doctor names the missing global plugin"
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

# "shim on PATH: yes" used to be `command -v <name>` — it reported the user's
# pre-plugin shim (no --plugin-dir, another root) as a working install.
test_doctor_shim_identity() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dsi" --shim-dir "$TMP/bin-dsi" >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi.out" 2>&1
  assert_contains "$TMP/dsi.out" "shim:         ok $TMP/bin-dsi/claude-gen" "doctor reports the recorded shim as ok"
  printf '#!/usr/bin/env sh\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$TMP/dsi" > "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a shim without --plugin-dir"
  assert_contains "$TMP/dsi2.out" "shim:         stale (no --plugin-dir)" "doctor names the stale shim"
  printf '#!/usr/bin/env sh\nCLAUDE_CONFIG_DIR="/elsewhere" exec claude --plugin-dir x "$@"\n' > "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi3.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a shim that launches another root"
  assert_contains "$TMP/dsi3.out" "shim:         stale (launches another root)" "doctor names the foreign shim"
  rm "$TMP/bin-dsi/claude-gen"
  status=0
  sh "$REPO_ROOT/doctor.sh" general --target "$TMP/dsi" > "$TMP/dsi4.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails on a missing shim"
  assert_contains "$TMP/dsi4.out" "shim:         MISSING" "doctor reports the missing shim"
}

# Counts and the plugin manifest were read from the checkout even in copy
# mode, so a deleted snapshot still reported "skills 8 agents 3".
test_doctor_inspects_copy_mode_snapshot() {
  sh "$REPO_ROOT/install.sh" game-dev --target "$TMP/dcp" --shim-dir "$TMP/bin-dcp" --mode copy >/dev/null 2>&1
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dcp" > "$TMP/dcp.out" 2>&1
  assert_contains "$TMP/dcp.out" "plugin dir:   $TMP/dcp/studio" "doctor inspects the snapshot in copy mode"
  rm -rf "$TMP/dcp/studio"
  status=0
  sh "$REPO_ROOT/doctor.sh" game-dev --target "$TMP/dcp" > "$TMP/dcp2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "doctor fails when the snapshot is gone"
  assert_contains "$TMP/dcp2.out" "no plugin manifest at $TMP/dcp/studio" "doctor names the missing snapshot manifest"
}

# "--dry-run prints every action" was false on a reinstall: the removal of
# the previous install's entries was skipped silently.
test_install_dry_run_previews_removal() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dryre" --shim-dir "$TMP/bin-dryre" >/dev/null 2>&1
  before="$(wc -l < "$TMP/dryre/.omega-ai-manifest" | tr -d ' ')"
  sh "$REPO_ROOT/install.sh" general --target "$TMP/dryre" --shim-dir "$TMP/bin-dryre" --dry-run > "$TMP/dryre.out" 2>&1
  assert_contains "$TMP/dryre.out" "DRY  rm -rf $TMP/dryre/CLAUDE.md" "dry run previews the removal of a recorded entry"
  assert_file "$TMP/dryre/CLAUDE.md" "dry run removes nothing"
  assert_eq "$before" "$(wc -l < "$TMP/dryre/.omega-ai-manifest" | tr -d ' ')" "dry run leaves the manifest alone"
  assert_file "$TMP/bin-dryre/claude-gen" "dry run keeps the shim"
}

# "Installed." used to print before the doctor ran, then the doctor failed.
test_install_reports_doctor_result_last() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/last" --shim-dir "$TMP/bin-last" > "$TMP/last.out" 2>&1
  assert_eq "Installed. Launch with: claude-gen" "$(tail -n 1 "$TMP/last.out")" "a clean install ends with the launch line"
  SB="$TMP/sandbox-last"
  mkdir -p "$SB"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$SB/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$SB/"
  printf '{ "name": "wrong", "version": "0.1.0", "description": "x" }\n' > "$SB/studios/general/.claude-plugin/plugin.json"
  status=0
  sh "$SB/install.sh" general --target "$TMP/last2" --shim-dir "$TMP/bin-last2" > "$TMP/last2.out" 2>&1 || status=$?
  assert_eq "1" "$status" "an install whose doctor fails exits 1"
  assert_not_contains "$TMP/last2.out" "Installed. Launch with" "no launch line is printed when the doctor fails"
  assert_contains "$TMP/last2.out" "doctor found problems" "the failure is stated after the doctor report"
}

# The pre-flight check runs before the previous install is removed: a
# checkout without the global plugin must fail without touching the target.
test_install_requires_global_plugin() {
  sh "$REPO_ROOT/install.sh" general --target "$TMP/req" --shim-dir "$TMP/bin-req" >/dev/null 2>&1
  assert_file "$TMP/req/CLAUDE.md" "baseline install succeeds"
  mkdir -p "$TMP/repo-no-omega"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/shared" "$REPO_ROOT/studios" "$TMP/repo-no-omega/"
  cp "$REPO_ROOT/install.sh" "$REPO_ROOT/doctor.sh" "$REPO_ROOT/uninstall.sh" "$TMP/repo-no-omega/"
  rm -rf "$TMP/repo-no-omega/shared/omega"
  status=0
  ( sh "$TMP/repo-no-omega/install.sh" general --target "$TMP/req" --shim-dir "$TMP/bin-req" >/dev/null 2>"$TMP/req.err" ) || status=$?
  assert_eq "1" "$status" "install refuses a checkout without shared/omega"
  assert_contains "$TMP/req.err" "shared/omega" "the refusal names the global plugin"
  assert_file "$TMP/req/CLAUDE.md" "the previous install is left in place"
  assert_file "$TMP/bin-req/claude-gen" "the previous shim is left in place"
}

run_tests test_studio_contract test_install_unknown_studio test_install_guard \
  test_install_requires_global_plugin \
  test_install_guards_shim_dir test_install_refuses_traversal_target \
  test_install_refuses_traversal_shim_dir test_install_refuses_symlinked_target \
  test_install_dry_run test_install_content \
  test_install_precedence test_install_copy_mode test_install_reinstall_cleans_stale_entries \
  test_install_reinstall_new_shim_dir_removes_old_shim \
  test_install_accepts_no_mcp test_install_registers_mcp test_install_skips_mcp_without_node_18 \
  test_install_skips_mcp_without_engine test_install_no_mcp_flag_skips_registration \
  test_install_general_has_no_mcp test_reinstall_reregisters_mcp_once test_uninstall_removes_mcp \
  test_uninstall_purge_confirmation_gates_mcp_removal \
  test_doctor_engine_and_mcp_rows test_doctor_delegations test_settings_backup test_shim \
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
  test_uninstall_keeps_shim_of_another_root \
  test_doctor_shim_identity test_doctor_inspects_copy_mode_snapshot \
  test_install_dry_run_previews_removal test_install_reports_doctor_result_last

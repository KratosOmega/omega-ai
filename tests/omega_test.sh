#!/bin/sh
# Tests for the omega global plugin: manifest, skill stubs, marketplace
# manifest, omega-mode, and the three hooks. Runs without a config root:
# omega-mode and the hooks are pointed at a temporary CLAUDE_CONFIG_DIR.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

OMEGA="$REPO_ROOT/shared/omega"
MODE="$OMEGA/bin/omega-mode"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/cfg"

# first_field FILE KEY — the value of a single-line "KEY: value" frontmatter
# field; empty when absent.
first_field() {
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1
}

# valid_json FILE — jq when present, otherwise a shape check: first non-blank
# character '{', last '}'.
valid_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null 2>&1
  else
    _first="$(tr -d '[:space:]' < "$1" | cut -c1)"
    _last="$(tr -d '[:space:]' < "$1" | tail -c 1)"
    [ "$_first" = "{" ] && [ "$_last" = "}" ]
  fi
}

test_plugin_files() {
  assert_file "$OMEGA/.claude-plugin/plugin.json" "omega has a plugin manifest"
  assert_status 0 "omega plugin.json is valid JSON" -- valid_json "$OMEGA/.claude-plugin/plugin.json"
  assert_eq "omega" "$(json_field "$OMEGA/.claude-plugin/plugin.json" name)" \
    "omega plugin.json names the omega namespace"
  assert_eq "0.1.0" "$(json_field "$OMEGA/.claude-plugin/plugin.json" version)" "omega plugin.json is version 0.1.0"
  for s in handoff parallel local-merge integration autopilot; do
    assert_file "$OMEGA/skills/$s/SKILL.md" "omega ships the $s skill"
  done
  assert_missing "$OMEGA/requires.txt" "omega declares no hard dependencies"
  assert_missing "$OMEGA/settings.json" "omega has no settings.json"
}

test_skill_stubs() {
  for s in handoff parallel local-merge integration autopilot; do
    f="$OMEGA/skills/$s/SKILL.md"
    assert_eq "---" "$(head -n 1 "$f")" "omega:$s starts with frontmatter"
    assert_eq "$s" "$(first_field "$f" name)" "omega:$s frontmatter name matches its directory"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(first_field "$f" description)" in
      "Use when"*) _pass "omega:$s description starts with 'Use when'" ;;
      *) _fail "omega:$s description starts with 'Use when'" ;;
    esac
  done
  for s in parallel local-merge integration autopilot; do
    assert_contains "$OMEGA/skills/$s/SKILL.md" "This mode changes how work is scheduled, saved, merged or stopped." \
      "omega:$s carries the precedence contract"
    assert_contains "$OMEGA/skills/$s/SKILL.md" "omega-mode" "omega:$s sets or clears its mode through omega-mode"
  done
}

test_marketplace() {
  m="$REPO_ROOT/.claude-plugin/marketplace.json"
  assert_file "$m" "the repository has a marketplace manifest"
  assert_status 0 "marketplace.json is valid JSON" -- valid_json "$m"
  assert_eq "omega-ai" "$(json_field "$m" name)" "the marketplace is named omega-ai"
  assert_contains "$m" '"name": "omega"' "the marketplace publishes the omega plugin"
  src="$(sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -n 1)"
  assert_eq "./shared/omega" "$src" "the omega plugin's source is ./shared/omega"
  assert_file "$REPO_ROOT/${src#./}/.claude-plugin/plugin.json" "the marketplace source resolves to the plugin"
}

run_tests test_plugin_files test_skill_stubs test_marketplace

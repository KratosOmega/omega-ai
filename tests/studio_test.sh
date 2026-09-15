#!/bin/sh
# Repository lint for every studio and the omega global plugin: plugin
# manifests, skill and agent frontmatter, external references, and bin/ and
# hook syntax. Runs without a config
# root; nothing here installs anything.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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

test_plugin_manifests() {
  for dir in "$REPO_ROOT"/studios/*/ "$REPO_ROOT"/shared/omega/; do
    name="$(basename "$dir")"
    manifest="$dir/.claude-plugin/plugin.json"
    assert_status 0 "$name plugin.json is valid JSON" -- valid_json "$manifest"
    assert_eq "$name" "$(json_field "$manifest" name)" "$name plugin.json name is the studio name"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$(json_field "$manifest" description)" ]; then
      _pass "$name plugin.json has a description"
    else
      _fail "$name plugin.json has a description"
    fi
  done
}

test_skill_frontmatter() {
  for f in "$REPO_ROOT"/studios/*/skills/*/SKILL.md "$REPO_ROOT"/shared/omega/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    dir="$(basename "$(dirname "$f")")"
    studio="$(basename "$(dirname "$(dirname "$(dirname "$f")")")")"
    assert_eq "---" "$(head -n 1 "$f")" "$studio:$dir starts with frontmatter"
    assert_eq "$dir" "$(first_field "$f" name)" "$studio:$dir frontmatter name matches its directory"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(first_field "$f" description)" in
      "Use when"*) _pass "$studio:$dir description starts with 'Use when'" ;;
      *) _fail "$studio:$dir description starts with 'Use when'" ;;
    esac
  done
}

test_agent_frontmatter() {
  for f in "$REPO_ROOT"/studios/*/agents/*.md; do
    [ -f "$f" ] || continue
    stem="$(basename "$f" .md)"
    studio="$(basename "$(dirname "$(dirname "$f")")")"
    assert_eq "$stem" "$(first_field "$f" name)" "$studio:$stem frontmatter name matches its file"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(first_field "$f" description)" in
      "Use when"*) _pass "$studio:$stem description starts with 'Use when'" ;;
      *) _fail "$studio:$stem description starts with 'Use when'" ;;
    esac
    assert_contains "$f" "^tools: " "$studio:$stem declares tools"
    assert_eq "inherit" "$(first_field "$f" model)" "$studio:$stem uses model: inherit"
  done
}

# Every superpowers: or godot-prompter: name a studio references must be
# declared in its requires.txt, so the doctor can check it against the cache.
test_external_references_declared() {
  for dir in "$REPO_ROOT"/studios/*/; do
    name="$(basename "$dir")"
    refs="$(grep -rhoE '(superpowers|godot-prompter):[a-z0-9-]+' \
      "$dir/skills" "$dir/agents" "$dir/engines" 2>/dev/null | sort -u || true)"
    for ref in $refs; do
      TESTS_RUN=$((TESTS_RUN + 1))
      if grep -qE "^(skill|agent)[[:space:]]+$ref\$" "$dir/requires.txt"; then
        _pass "$name declares $ref in requires.txt"
      else
        _fail "$name declares $ref in requires.txt"
      fi
    done
  done
}

# Every plugin requires.txt declares must be enabled by the studio's own
# settings.json, or a fresh install fails the doctor immediately.
test_required_plugins_enabled() {
  for dir in "$REPO_ROOT"/studios/*/; do
    name="$(basename "$dir")"
    for req in $(requires_of "$dir/requires.txt" plugin); do
      assert_contains "$dir/settings.json" "\"$req\"[[:space:]]*:[[:space:]]*true" \
        "$name settings.json enables $req"
    done
  done
}

test_bin_syntax() {
  for f in "$REPO_ROOT"/studios/*/bin/* "$REPO_ROOT"/studios/*/engines/*/*.sh "$REPO_ROOT"/studios/*/hooks/*.sh \
           "$REPO_ROOT"/shared/omega/bin/* "$REPO_ROOT"/shared/omega/hooks/*.sh; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in .gitkeep) continue ;; esac
    rel="${f#"$REPO_ROOT"/}"
    assert_status 0 "$rel parses as POSIX sh" -- sh -n "$f"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -x "$f" ]; then _pass "$rel is executable"; else _fail "$rel is executable"; fi
  done
}

# Every Role the plan and execute tables offer must be dispatchable: a
# shipped agent file, or one of the roles execute maps to a godot-prompter
# agent or general-purpose until Plan 2 ships the studio's own.
test_role_agents_exist() {
  interim=" gameplay-programmer architect ui-designer level-designer "
  for f in "$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md" "$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"; do
    skill="$(basename "$(dirname "$f")")"
    for role in $(sed -n 's/^| `game-dev:\([a-z0-9-]*\)`.*/\1/p' "$f" | sort -u); do
      case "$interim" in *" $role "*) continue ;; esac
      assert_file "$REPO_ROOT/studios/game-dev/agents/$role.md" "$skill Role game-dev:$role is a shipped agent"
    done
  done
  assert_missing "$REPO_ROOT/studios/game-dev/agents/game-feel-tuner.md" "game-feel-tuner was renamed to feel-tuner"
  assert_missing "$REPO_ROOT/studios/game-dev/agents/2d-art-pipeline.md" "2d-art-pipeline was renamed to tech-artist"
  assert_contains "$REPO_ROOT/studios/game-dev/agents/feel-tuner.md" "^tools: .*Bash" "feel-tuner can run the game"
  assert_not_contains "$REPO_ROOT/studios/game-dev/agents/game-designer.md" "^Ask about" \
    "game-designer states assumptions instead of asking (a subagent cannot ask)"
}

# Behaviour the review fixed, pinned as text contracts on the stage skills.
test_stage_skill_contracts() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_not_contains "$S/execute/SKILL.md" "finishing-a-development-branch" "execute never offers a merge path"
  assert_contains "$S/execute/SKILL.md" "quit-after" "execute smoke-boots the project"
  assert_contains "$S/execute/SKILL.md" "git log -1" "execute requires a committed spec and plan"
  assert_contains "$S/execute/SKILL.md" "godot-prompter:godot-game-dev" "execute dispatches godot-prompter's game dev for gameplay tasks"
  assert_contains "$S/execute/SKILL.md" "game-dev:feel-tuner" "execute dispatches the studio's feel tuner"
  assert_contains "$S/execute/SKILL.md" "unverified" "execute lists unverified items"
  assert_not_contains "$S/execute/SKILL.md" "bypass the event bus" "execute's reviewer no longer mandates bus-for-everything"
  assert_contains "$S/execute/SKILL.md" "[-][-]headless" "execute's smoke boot runs headless"
  assert_contains "$S/execute/SKILL.md" "SCRIPT ERROR" "execute's smoke boot checks for SCRIPT ERROR"
  assert_contains "$S/execute/SKILL.md" "godot-prompter:godot-code-reviewer" "execute dispatches godot-prompter's code reviewer"
  assert_contains "$S/execute/SKILL.md" "godot-prompter:godot-ui-designer" "execute dispatches godot-prompter's UI designer"
  assert_contains "$S/execute/SKILL.md" "GODOT_PATH" "execute's smoke boot resolves the binary via GODOT_PATH"
}

# Behaviour Task 18 pinned as text contracts on the plan skill.
test_plan_skill_contract() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/plan/SKILL.md" "unit+playtest" "plan allows combined verify kinds"
  assert_contains "$S/plan/SKILL.md" "git commit" "plan commits at the approval gate"
  assert_contains "$S/plan/SKILL.md" "Milestone gate" "plan reads gate criteria from the spec when PROGRESS.md is absent"
  assert_not_contains "$S/plan/SKILL.md" "a GUT test named" "plan does not hard-code GUT"
}

# Behaviour the review fixed, pinned as a text contract on the brainstorm
# stage skill.
test_brainstorm_skill_contract() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/brainstorm/SKILL.md" "## Tuning knobs" "brainstorm's spec template exposes tuning knobs"
  assert_contains "$S/brainstorm/SKILL.md" "## Milestone gate" "brainstorm's spec template carries the gate"
  assert_contains "$S/brainstorm/SKILL.md" "game-dev:game-designer" "brainstorm dispatches the game designer"
  assert_not_contains "$S/brainstorm/SKILL.md" "godot-brainstorming" "brainstorm does not hand a subagent an interactive skill"
  assert_contains "$S/brainstorm/SKILL.md" "docs(specs): approve" "brainstorm commits at the approval gate"
}

# Behaviour this review pass added to the router: reconciling with
# `studio-state check`, treating an empty brainstorm as idle, the abandon
# route, and the bug route starting from a failing test.
test_studio_skill_contract() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/studio/SKILL.md" "studio-state check" "the router reconciles state with the repository"
  assert_contains "$S/studio/SKILL.md" "studio-state reset" "the router can abandon a feature"
  assert_contains "$S/studio/SKILL.md" "failing test" "the bug route starts from a failing test"
}

# The game-dev studio ships exactly these role agents; the list grows task by
# task in Plan 2 until all ten are present.
test_game_dev_agent_roster() {
  for a in game-designer level-designer architect producer; do
    assert_file "$REPO_ROOT/studios/game-dev/agents/$a.md" "game-dev has the $a agent"
  done
}

run_tests test_plugin_manifests test_skill_frontmatter test_agent_frontmatter \
  test_external_references_declared test_required_plugins_enabled test_bin_syntax \
  test_role_agents_exist test_stage_skill_contracts test_plan_skill_contract \
  test_brainstorm_skill_contract \
  test_studio_skill_contract test_game_dev_agent_roster

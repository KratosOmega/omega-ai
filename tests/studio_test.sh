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
# shipped agent file. Plan 2 ships all ten of the studio's own role agents,
# so every role the tables name is checked.
test_role_agents_exist() {
  for f in "$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md" "$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"; do
    skill="$(basename "$(dirname "$f")")"
    for role in $(sed -n 's/^| `game-dev:\([a-z0-9-]*\)`.*/\1/p' "$f" | sort -u); do
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
  assert_contains "$S/execute/SKILL.md" "studio-run [-][-]seconds" "execute smoke-boots the project through the studio-run verb"
  assert_contains "$S/execute/SKILL.md" "git log -1" "execute requires a committed spec and plan"
  assert_not_contains "$S/execute/SKILL.md" "godot-prompter:godot-game-dev" "execute no longer dispatches godot-prompter's game dev"
  assert_contains "$S/execute/SKILL.md" "game-dev:feel-tuner" "execute dispatches the studio's feel tuner"
  assert_contains "$S/execute/SKILL.md" "Play before merging" "execute hands the user a play list"
  assert_not_contains "$S/execute/SKILL.md" "bypass the event bus" "execute's reviewer no longer mandates bus-for-everything"
  assert_not_contains "$S/execute/SKILL.md" "[-][-]quit-after" "execute no longer re-implements the engine's own headless flags"
  assert_contains "$S/execute/SKILL.md" "SCRIPT ERROR" "execute's smoke boot checks for SCRIPT ERROR"
  assert_not_contains "$S/execute/SKILL.md" "godot-prompter:godot-code-reviewer" "execute no longer dispatches godot-prompter's code reviewer"
  assert_not_contains "$S/execute/SKILL.md" "godot-prompter:godot-ui-designer" "execute no longer dispatches godot-prompter's UI designer"
  assert_contains "$S/execute/SKILL.md" "GODOT_PATH" "execute still names GODOT_PATH for the no-binary case"
  assert_not_contains "$S/execute/SKILL.md" "Applications/Godot" "execute no longer re-implements resolve.sh's binary search"
  assert_contains "$S/execute/SKILL.md" "do not set" "execute's smoke boot still stops the finish on failure"
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
  assert_contains "$S/brainstorm/SKILL.md" 'studio-state set stage brainstorm' "brainstorm's stage command sits on one line"
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

# The game-dev studio ships exactly these ten role agents.
test_game_dev_agent_roster() {
  for a in game-designer level-designer architect producer \
           gameplay-programmer tech-artist feel-tuner ui-designer \
           playtester reviewer; do
    assert_file "$REPO_ROOT/studios/game-dev/agents/$a.md" "game-dev has the $a agent"
  done
}

# Stage skills dispatch the studio's own agents, not stand-ins. These strings
# are the ones the skills must carry once the role agents exist.
test_stage_skills_dispatch_agents() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/execute/SKILL.md" 'subagent_type: "game-dev:<role>"' "execute dispatches game-dev:<role> agents"
  assert_contains "$S/execute/SKILL.md" 'game-dev:reviewer' "execute reviews with game-dev:reviewer"
  assert_contains "$S/execute/SKILL.md" 'subagent_type: "game-dev:producer"' "execute dispatches the producer at the finish"
  assert_not_contains "$S/execute/SKILL.md" 'general-purpose' "execute no longer dispatches general-purpose"
  assert_not_contains "$S/execute/SKILL.md" 'Plan 2 of the studio' "execute carries no Plan 2 note"
  assert_contains "$S/brainstorm/SKILL.md" 'dispatch `game-dev:architect`' "brainstorm dispatches the architect"
  assert_contains "$S/brainstorm/SKILL.md" 'dispatch `game-dev:game-designer`' "brainstorm dispatches the game designer"
  assert_contains "$S/brainstorm/SKILL.md" 'dispatch `game-dev:level-designer`' "brainstorm dispatches the level designer"
  assert_not_contains "$S/brainstorm/SKILL.md" 'general-purpose' "brainstorm no longer dispatches general-purpose"
  assert_contains "$S/plan/SKILL.md" 'dispatch `game-dev:producer`' "plan dispatches the producer"
  assert_contains "$S/plan/SKILL.md" 'Propose a task decomposition' "plan dispatches the architect for a task decomposition proposal"
  assert_not_contains "$S/plan/SKILL.md" 'Plan 2 of the studio' "plan carries no Plan 2 note"
  assert_not_contains "$S/studio/SKILL.md" 'until that skill is installed' "router has no playtest fallback note"
  assert_contains "$S/review/SKILL.md" 'subagent_type: "game-dev:reviewer"' "review dispatches the reviewer"
  assert_contains "$S/playtest/SKILL.md" 'subagent_type: "game-dev:playtester"' "playtest dispatches the playtester"
  assert_contains "$S/playtest/SKILL.md" 'playtest signed off' "playtest writes the sign-off ledger phrase the router reads"
  assert_contains "$S/ship/SKILL.md" 'subagent_type: "game-dev:producer"' "ship dispatches the producer"
  assert_contains "$S/retro/SKILL.md" 'CLAUDE_CONFIG_DIR' "retro writes memory into the isolated config root"
  assert_contains "$S/retro/SKILL.md" 'sync-memory.sh game-dev' "retro reminds the user to sync memory"
}

# Cross-checks the router's stage table (studio/SKILL.md) against the stage
# chain idle → brainstorm → plan → execute → idle: the four rows and the
# old-pipeline row, the value each stage skill last sets (execute's is idle),
# and every value studio-state accepts. A future edit to either side that
# breaks the chain fails here instead of misrouting users.
test_stage_chain() {
  S="$REPO_ROOT/studios/game-dev/skills"
  router="$S/studio/SKILL.md"
  assert_contains "$router" '| `idle` | `/game-dev:brainstorm` |' "router routes idle to brainstorm"
  assert_contains "$router" '| `brainstorm` | `/game-dev:plan` |' "router routes brainstorm to plan"
  assert_contains "$router" '| `plan` | `/game-dev:execute` |' "router routes plan to execute"
  assert_contains "$router" '| `execute` | `/game-dev:execute`' "router resumes execute"
  assert_contains "$router" '^| any other value.*old pipeline' "router reads any other stage as the old pipeline"
  for skill in brainstorm plan execute; do
    last="$(grep -o 'studio-state set stage [a-z]*' "$S/$skill/SKILL.md" | tail -n 1 | awk '{print $NF}')"
    if [ -z "$last" ]; then
      TESTS_RUN=$((TESTS_RUN + 1))
      _fail "$skill sets a stage value on one line"
      continue
    fi
    assert_contains "$router" "^| \`$last\` |" "router has a row for stage $last (set last by $skill)"
  done
  assert_eq "idle" "$(grep -o 'studio-state set stage [a-z]*' "$S/execute/SKILL.md" | tail -n 1 | awk '{print $NF}')" \
    "execute's last stage value is idle"
  stages="$(sed -n 's/^STAGES="\(.*\)"$/\1/p' "$REPO_ROOT/studios/game-dev/bin/studio-state")"
  assert_eq "idle brainstorm plan execute" "$stages" "studio-state accepts exactly the four stages"
  for st in $stages; do
    assert_contains "$router" "^| \`$st\` |" "router has a row for stage $st"
  done
}

# Execute's slim-pipeline contract (spec §4): B2 fix rounds, the standalone
# final review on Opus, the finish to a ready PR, and isolation that records
# the feature branch and its base.
test_execute_contract() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for lit in 'never resume or message an implementer' 'superpowers:subagent-driven-development' \
             '[Nn]ever a third' 'review-package' 'model: "opus"' 'never folded' 'Verify prior fixes' \
             'final|gate|review' 'final fix wave' 'A task is complete' 'final review done' 'studio-lint' \
             'subagent_type: "game-dev:producer"' 'gh pr create' '[-][-]draft' 'local, default branch' \
             'Play before merging' 'studio-state set stage idle' 'new run clears' \
             'studio-state set branch "$(git branch' 'before the fast-forward' 'ledger "base' \
             "from the feature's worktree" 'set task 0/' 'N/N' 'SDD ledger — plan:' \
             'Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature\.'; do
    assert_contains "$E" "$lit" "execute carries: $lit"
  done
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qE '3\+ Importants|three or more Importants' "$E"; then
    _pass "execute re-reviews after 3+ Importants"
  else
    _fail "execute re-reviews after 3+ Importants"
  fi
  assert_not_contains "$E" 'set stage ''review' "execute no longer hands off to a review stage"
  assert_not_contains "$E" 'a side effect outside the worktree' "execute drops the old side-effect rule"
}

# The agent contracts the slim pipeline changed. The producer records the
# finish with the play list, and has no Bash, so it runs no studio-state.
test_agent_contracts() {
  A="$REPO_ROOT/studios/game-dev/agents"
  assert_contains "$A/producer.md" 'Play before merging' "the producer's log entry carries the play list"
  assert_not_contains "$A/producer.md" 'playtest report it passed' "the producer reads no playtest report"
  assert_not_contains "$A/producer.md" 'sh''ip skill' "the producer names no deleted skill"
  assert_not_contains "$A/producer.md" 'studio-state show' "the producer runs no studio-state"
}

# Every copy of a §1 feature-checkout procedure holds its key literals: skills
# cannot include one another, so each skill that runs a procedure carries its
# own copy. The three lists name the skills that carry each procedure.
test_feature_checkout_copies() {
  S="$REPO_ROOT/studios/game-dev/skills"
  enter_leave="execute"
  guard="brainstorm plan execute"
  default_branch="brainstorm plan execute"
  for sk in $enter_leave; do
    for lit in 'studio-state worktree' 'EnterWorktree' 'another live session' 'ExitWorktree' '--git-common-dir'; do
      assert_contains "$S/$sk/SKILL.md" "$lit" "$sk carries the enter/leave procedure: $lit"
    done
  done
  for sk in $guard; do
    for lit in 'studio-state get branch' 'previous, finished feature' 'start the next feature on this branch anyway'; do
      assert_contains "$S/$sk/SKILL.md" "$lit" "$sk carries the finished-checkout guard: $lit"
    done
  done
  for sk in $default_branch; do
    assert_contains "$S/$sk/SKILL.md" 'refs/remotes/origin/HEAD' "$sk carries the default-branch procedure"
  done
}

# Brainstorm and plan end by printing the next command, to run after a /clear.
test_next_lines() {
  S="$REPO_ROOT/studios/game-dev/skills"
  assert_contains "$S/brainstorm/SKILL.md" 'Next: run /clear, then /game-dev:plan' "brainstorm prints the /clear Next line"
  assert_contains "$S/plan/SKILL.md" 'Next: run /clear, then /game-dev:execute' "plan prints the /clear Next line"
}

run_tests test_plugin_manifests test_skill_frontmatter test_agent_frontmatter \
  test_external_references_declared test_required_plugins_enabled test_bin_syntax \
  test_role_agents_exist test_stage_skill_contracts test_plan_skill_contract \
  test_brainstorm_skill_contract \
  test_studio_skill_contract test_game_dev_agent_roster test_stage_skills_dispatch_agents \
  test_stage_chain test_execute_contract test_agent_contracts test_feature_checkout_copies test_next_lines

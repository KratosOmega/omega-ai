#!/bin/sh
# Repository lint for every studio and the omega global plugin: plugin
# manifests, skill and agent frontmatter, external references, and bin/ and
# hook syntax. Runs without a config
# root; nothing here installs anything.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
. "$REPO_ROOT/lib/common.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/studio_test.XXXXXX")"
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
    case "$(basename "$f")" in .gitkeep|*.txt) continue ;; esac
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
  # Final-review fixes M1-M4: the producer's result has a report slot, branch
  # is cleared before stage is written, the legacy stop does not isolate, and
  # review-package runs from the worktree root.
  for lit in "producer's gate result" 'A new run first runs `studio-state set branch -`' \
             'then do not isolate' 'run from the worktree root (`sdd-script` prints the script'"'"'s path'; do
    assert_contains "$E" "$lit" "execute carries: $lit"
  done
  assert_not_contains "$E" "run from SDD's skill directory" "execute no longer reads review-package's directory as a cwd"
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
  assert_not_contains "$A/playtester.md" '## Script' "the playtester writes no playtest script"
  assert_not_contains "$A/playtester.md" 'docs/game-dev/playtests' "the playtester writes no report file"
  assert_eq "Read, Grep, Glob, Bash" "$(first_field "$A/playtester.md" tools)" "the playtester's tools have no Write"
}

# Every copy of a §1 feature-checkout procedure holds its key literals: skills
# cannot include one another, so each skill that runs a procedure carries its
# own copy. The three lists name the skills that carry each procedure.
test_feature_checkout_copies() {
  S="$REPO_ROOT/studios/game-dev/skills"
  enter_leave="execute review playtest"
  guard="brainstorm plan execute"
  default_branch="brainstorm plan execute review playtest"
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

# Review on demand (spec §5): execute's fix rules, Opus, the ledger line on
# the feature branch, and the stale-pointer and merged-branch stops.
test_review_contract() {
  R="$REPO_ROOT/studios/game-dev/skills/review/SKILL.md"
  for lit in 'model: "opus"' 'fix(review)' 'never a third' '.studio/ledger <plan path>' \
             'chore(studio): ledger' 'pointers now name' 'MERGED' 'ends at HEAD'; do
    assert_contains "$R" "$lit" "review carries: $lit"
  done
  assert_not_contains "$R" 'Three rounds' "review drops its own three-round loop"
  # Final-review fix I1: the report-only gate is the ruling made in section 0,
  # the ledger line needs the recorded branch on the branch/range path, an
  # Exit-1 answer is entered, and a run without a ledger line reports its
  # deferrals.
  for lit in 'ruled the run report-only' 'studio-state get branch' \
             'enter the chosen checkout the Exit 0 way' 'lists it in the report'; do
    assert_contains "$R" "$lit" "review carries: $lit"
  done
  assert_not_contains "$R" 'HEAD is not the' "review's gate no longer keys on the recorded branch's checkout"
}

# Review, playtest and retro run on demand: they never change the stage, and
# retro clears no pointer.
test_on_demand_skills_keep_stage() {
  S="$REPO_ROOT/studios/game-dev/skills"
  for sk in review playtest retro; do
    assert_not_contains "$S/$sk/SKILL.md" 'studio-state set stage' "$sk writes no stage"
  done
  assert_not_contains "$S/retro/SKILL.md" 'set spec -' "retro clears no spec pointer"
  assert_not_contains "$S/retro/SKILL.md" 'set plan -' "retro clears no plan pointer"
}

# Playtest on demand (spec §5): the user's failure report in; a filed bug, a
# fresh fixer, a regression test, a push and one PR comment out. No script,
# no report file, no sign-off.
test_playtest_contract() {
  P="$REPO_ROOT/studios/game-dev/skills/playtest/SKILL.md"
  for lit in 'subagent_type: "game-dev:playtester"' 'game-dev:feel-tuner' 'fix(B<n>)' 'gh pr comment' \
             '## Backlog' 'superpowers:systematic-debugging' '.studio/ledger <plan path>' 'chore(studio): ledger' \
             'never counted' 'pointers now name' 'stage execute' 'MERGED' \
             'enter the chosen checkout the Exit 0 way' 'superpowers:test-driven-development' \
             'commit the move in' 'redone by a fresh feel-tuner'; do
    assert_contains "$P" "$lit" "playtest carries: $lit"
  done
  for lit in 'AskUserQuestion' 'docs/game-dev/playtests' 'signed off' '## Script' 'sent back'; do
    assert_not_contains "$P" "$lit" "playtest no longer carries: $lit"
  done
}

# Retro on demand (spec §5): no questions, no ledger write, no commit; it
# reads the recorded feature's ledger and writes studio memory only.
test_retro_contract() {
  T="$REPO_ROOT/studios/game-dev/skills/retro/SKILL.md"
  for lit in 'CLAUDE_CONFIG_DIR' 'sync-memory.sh game-dev' 'studio-state worktree' 'git show' \
             'read only `STATE.md`' 'for the current stage'; do
    assert_contains "$T" "$lit" "retro carries: $lit"
  done
  # Final-review fix I2: exit 1 reads the current checkout's ledger (spec
  # Data migration), not STATE.md's alone.
  assert_contains "$T" "At exit 1 with candidates, ask the user once which story" "retro asks once which story at exit 1"
  assert_contains "$T" "the only question retro asks" "retro names its one question"
  for lit in 'studio-state ledger' 'retro written' 'git commit'; do
    assert_not_contains "$T" "$lit" "retro no longer carries: $lit"
  done
}

# AC34: review and playtest ask among story candidates at Exit 1.
test_skill_review_playtest_ask_candidates() {
  for sk in review playtest; do
    T="$REPO_ROOT/studios/game-dev/skills/$sk/SKILL.md"
    for lit in "more than one story fits, a removed story's worktree is offered, or none is recorded" \
               'run its command, then enter the path it added' \
               "this checkout's pointer moved on to the next feature"; do
      assert_contains "$T" "$lit" "$sk carries: $lit"
    done
  done
}

# AC35: retro resolves its story with studio-state worktree.
test_skill_retro_resolves_story() {
  T="$REPO_ROOT/studios/game-dev/skills/retro/SKILL.md"
  for lit in '(cd <path> && studio-state show)' '`removed` candidate' 'creates no worktree' 'one-time adopt'; do
    assert_contains "$T" "$lit" "retro carries: $lit"
  done
}

# The old pipeline's last stage is deleted: no studio, omega, README or test
# line routes to it. Its name is held split in $sk (spec Testing's
# split-spelling rule), so this file's own lines never match.
test_no_ship_references() {
  sk='sh''ip'
  assert_missing "$REPO_ROOT/studios/game-dev/skills/$sk" "the $sk skill directory is gone"
  hits="$(cd "$REPO_ROOT" && grep -rnE "game-dev:$sk([^a-z-]|\$)|skills/$sk([^a-z-]|\$)|stage $sk([^a-z-]|\$)|[Ss]${sk#s} (stage|skill|method)" \
    studios/game-dev shared/omega README.md tests/*.sh || true)"
  assert_eq "" "$hits" "nothing names the deleted command, skill or stage"
}

# Every superpowers skill requires.txt declares is named by a studio skill or
# agent: the other direction of test_external_references_declared. The doctor
# never checks for a skill nothing uses.
test_superpowers_requires_referenced() {
  D="$REPO_ROOT/studios/game-dev"
  for ref in $(sed -n 's/^skill[[:space:]][[:space:]]*\(superpowers:[a-z0-9-]*\)[[:space:]]*$/\1/p' "$D/requires.txt"); do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -rqE -- "$ref([^a-z0-9-]|\$)" "$D/skills" "$D/agents"; then
      _pass "requires.txt's $ref is named by a skill or agent"
    else
      _fail "requires.txt's $ref is named by a skill or agent"
    fi
  done
  assert_not_contains "$D/requires.txt" 'finishing-a-development-branch' "requires.txt no longer declares the branch-finishing skill"
}

# The last_playtest key is gone: no studio or omega file reads or writes it.
# Spec §1 (115-117) relies on such a test, which §Testing omits (ruling R1).
test_no_last_playtest_callers() {
  hits="$(grep -rn 'last_playtest' "$REPO_ROOT/studios/game-dev" "$REPO_ROOT/shared/omega" || true)"
  assert_eq "" "$hits" "no studio or omega file names last_playtest"
}

test_execute_one_contract() {
  S="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$S" "^## 8. One unit (--one)$" "execute has the --one section"
  assert_contains "$S" "exactly one unit" "--one runs exactly one unit"
  assert_contains "$S" "no next implementer is dispatched" "--one cuts SDD's loop after one task"
  assert_contains "$S" "overrides SDD's instruction to continue to the next task" "the cut overrides SDD"
  assert_contains "$S" "^    .git push -u origin <branch>.;$" "§8 task unit ends with the push (not §7 step 4)"
  assert_contains "$S" 'studio-state ledger "Stop: <reason>"' "every stop writes a Stop: line under --one"
  assert_contains "$S" 'git commit -m "chore(studio): stop"' "the Stop: line is committed in a feature checkout"
  assert_contains "$S" "A rejected push is a \`Ruling:\` line, not a stop" "a rejected push is a ruling"
  assert_contains "$S" "never runs \`omega:handoff\`" "--one writes no handoff"
  assert_contains "$S" "\`--one\` with \`--inline\` is refused" "--one is subagent-driven only"
  assert_contains "$S" "Under \`--one\`, see §8" "the sections that stop or continue point at §8"
  assert_eq 6 "$(grep -c 'Under `--one`, see §8' "$S")" "six pointers: §0, §1, §5 opening, §5 step 6, §7 step 6, §7 step 7"
  assert_eq 1 "$(sed -n '/^## 1\. Mode$/,/^\*\*`--inline`\.\*\*/p' "$S" | grep -c 'Under `--one`, see §8')" "§1's pointer sits on the SDD-loop paragraph"
  assert_eq 1 "$(sed -n '/^## 5\. Final review$/,/^1\. Run/p' "$S" | grep -c 'Under `--one`, see §8')" "§5 opens with a pointer, so a task unit cannot slide into §5"
  assert_contains "$S" "through step 6; §7 is not started" "the final-review unit does not start §7"
  assert_contains "$S" "writes its \`Stop:\` line in the checkout this session was launched in" "a stop before (c) is written in the launch checkout the runner reads"
  assert_contains "$S" "That line is never committed, whatever branch is checked out" "a stop before (c) is never committed (D9)"
  assert_not_contains "$S" "the main checkout, where the runner reads it" "a stop before (c) is not routed to the main checkout"
  assert_not_contains "$S" "before isolation leaves" "no 'before isolation' wording for the uncommitted stop"
}

test_router_overnight_lock() {
  S="$REPO_ROOT/studios/game-dev/skills/studio/SKILL.md"
  assert_contains "$S" '`studio-overnight status`' "the router lists live runs with status"
  assert_not_contains "$S" ".studio/overnight.lock" "the router does not read the runner's lock file"
  assert_contains "$S" "A live run does not make the project busy" "a live run does not block routing"
}

test_execute_sync_repair_form() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" 'STUDIO_REPAIR=sync:<ref>' "§9 names the sync repair form"
  assert_contains "$E" '`--land`.*sync:' "§1 lists --land with sync:"
  assert_contains "$E" 'stage execute' "§9 sync: precondition is stage execute"
  assert_contains "$E" 'fix(sync): <summary>' "the sync repair commit subject"
  assert_contains "$E" 'Synced: <summary>' "the sync repair ledger line"
  assert_contains "$E" 'Stop: sync repair red — <failing line>' "a red sync repair stops"
  assert_contains "$E" 'studio-test <paths>' "the sync gate is scoped to the touched paths"
}

test_execute_peers_brief_rule() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" 'Other live runs' "§2 names the peer-runs block"
  assert_contains "$E" 'every implementer and fixer brief' "§2 copies the block into every brief"
}

# #56: plan and brainstorm check a manifest story's id first; the Stories
# table copies the manifest's ids.
test_plan_brainstorm_check_id() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  BR="$REPO_ROOT/studios/game-dev/skills/brainstorm/SKILL.md"
  for f in "$PL" "$BR"; do
    assert_contains "$f" 'Run `studio-overnight check-id <id>` there first' "$f checks the id after entering the run worktree"
    assert_contains "$f" 'before writing any file or ledger line' "$f stops before any write"
    assert_contains "$f" 'run the same `studio-overnight check-id <id>` first' "$f checks the <id> form under a manifest too"
    _a="$(grep -n -F -m1 -- 'Run `studio-overnight check-id <id>` there first' "$f" | cut -d: -f1)"
    _b="$(grep -n -F -m1 -- 'Run `studio-state show` after entering' "$f" | cut -d: -f1)"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]; then _pass "$f: check-id is the first step after entering"
    else _fail "$f: check-id is the first step after entering ($_a, $_b)"; fi
  done
  assert_contains "$BR" "The \`Story\` cells are the manifest's own ids" "the Stories table copies the manifest's ids"
  for f in "$PL" "$BR"; do
    # §0 points at the <slug>/<id> steps (check-id included), which run first.
    _p="$(grep -n -F -m1 -- 'run that form'"'"'s steps first' "$f" | cut -d: -f1)"
    _z="$(grep -n -m1 '^## 0\. ' "$f" | cut -d: -f1)"; _o="$(grep -n -m1 '^## 1\. ' "$f" | cut -d: -f1)"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$_p" ] && [ -n "$_z" ] && [ -n "$_o" ] && [ "$_z" -lt "$_p" ] && [ "$_p" -lt "$_o" ]; then
      _pass "$f: §0 points at the <slug>/<id> steps first"
    else _fail "$f: §0 points at the <slug>/<id> steps first ($_z, $_p, $_o)"; fi
  done
}

test_plan_brainstorm_slug_form() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  BR="$REPO_ROOT/studios/game-dev/skills/brainstorm/SKILL.md"
  assert_contains "$PL" '/game-dev:plan <slug>/<id>' "plan has the slug/id form"
  assert_contains "$BR" '/game-dev:brainstorm <slug>/<id>' "brainstorm has the slug/id form"
  for f in "$PL" "$BR"; do
    assert_contains "$f" 'run/<slug>' "$f finds the run branch checkout"
    assert_contains "$f" 'studio-state show. after entering' "$f prints state after entering"
    assert_contains "$f" 'no checkout holds run/<slug>' "$f refuses when no checkout holds the run"
    assert_contains "$f" 'The bare `<id>` form' "$f keeps the bare id form"
  done
}

test_execute_lanes() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" 'Under a lane\*\* (`STUDIO_STORY` and `STUDIO_RUN` both set)' "§0 has one lane paragraph keyed on both variables"
  assert_contains "$E" 'git status --porcelain -- <spec> <plan> .studio/ledger/<id>.md .studio/config.json' "§0 under a lane checks only the story's ledger"
  assert_contains "$E" 'git worktree add --no-track -b <Branch>' "§0 creates the story branch with --no-track"
  assert_contains "$E" 'git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md' "a new branch takes docs and ledger from the docs revision"
  assert_contains "$E" 'git checkout $STUDIO_DOCS_REV -- <spec> <plan>`, and only when' "an existing branch syncs spec and plan only when they differ (D3)"
  assert_contains "$E" 'docs(<id>): plan at run docs' "an existing branch syncs spec and plan, never the ledger"
  assert_contains "$E" 'The ledger is never touched' "an existing branch's ledger is never touched"
  assert_contains "$E" 'studio-state ledger "base origin/<Target>"' "the base is recorded as the remote target"
  assert_contains "$E" 'retry a git write whose stderr says `could not lock` or `cannot lock ref`' "git lock retry rule"
  assert_contains "$E" 'Run `studio-test` and `studio-run`' "§0 names both gate commands under a lane"
  assert_contains "$E" '`Review: final` gets no per-task review' "§4 honours Review: final"
  assert_contains "$E" 'a per-task reviewer is dispatched with `model: "opus"`' "the per-task reviewer runs on Opus"
  assert_contains "$E" 'Under a lane, §5 step 1 is skipped' "the final review runs no tests under a lane"
  assert_contains "$E" 'Under a lane, step 5 still commits the ledger' "§7 step 5 stays under a lane"
  assert_contains "$E" 'the runner confirms a landing from the `shipped` line on origin/<Branch>' "the runner reads the shipped line"
  assert_contains "$E" 'shipped <Branch>' "integration ships by branch, no PR"
  assert_contains "$E" 'open a \*\*draft\*\* PR into the default branch' "direct opens a draft PR"
  assert_contains "$E" 'no session merges anything in any run mode' "§6 names the rule"
  assert_contains "$E" 'the runner lands the story' "§6 names the runner as the lander"
  assert_contains "$E" 'studio-brief task <n>' "§8 task inputs"
  assert_contains "$E" 'studio-brief final' "§8 final inputs"
  assert_contains "$E" 'never reads the plan or the spec whole' "§8 forbids whole reads"
  assert_contains "$E" "never runs SDD's pre-flight conflict scan" "§8 skips the conflict scan"
  # T14 fix round
  assert_contains "$E" 'Under a lane the ancestor check never runs, a resume.s included' "a lane resume skips the ancestor check (story branches lack the run docs commits)"
  assert_contains "$E" 'Never merge: no session merges into `main` (the default branch) in any run mode; the runner lands' "§7 step 4's never-merge names main and the runner (AC22)"
  assert_contains "$E" 'under integration, no PR and `shipped <Branch>`' "§8's finish unit agrees with the integration lane"
  assert_contains "$E" 'Under `--one`, these two reads are `studio-brief task <n>` or `studio-brief final` only' "§0's plan and spec reads give way to studio-brief under --one"
  assert_contains "$E" 'Under `--one`, SDD.s setup never reads the plan' "SDD's setup plan read gives way to studio-brief under --one"
  assert_contains "$E" 'Under a lane, every brief that has a subagent run `studio-test`' "§2 carries the foreground studio-test rule into every brief"
  assert_contains "$E" 'under a lane, §2.s foreground `studio-test` line;' "§4a's fixer brief carries the foreground rule"
  assert_contains "$E" '`studio-test` and `studio-run` each run as a foreground Bash call with `timeout` set to `$BASH_MAX_TIMEOUT_MS`' "§7's lane gate runs studio-test and studio-run in the foreground"
  assert_contains "$E" 'the gate runs once, no `fix(gate)` round follows, and a red gate never ships' "a red lane gate is not retried and never ships"
  assert_contains "$E" 'Stop: gate red — <failing command and line>' "a red lane gate ledgers a Stop: line"
  assert_contains "$E" '`studio-lint` exit 3 (gdtoolkit not installed) is noted in the gate line, not red, and the story goes on.' "a lane gate keeps lint exit 3 non-red"
  assert_contains "$E" '`studio-state ledger "Stop: <the printed message>"` (not `gate red`)' "a lane engine stop is not gate red"
}

# The finish unit's gate (phoenix mob-composer-parity, 2026-10-02): a
# headless -p session that ends its turn to wait on a background studio-test
# ends the session, so the gate must run in the foreground. This fails if any
# lane rule tells a session to background-and-wait on studio-test/studio-run.
test_execute_lane_gate_foreground() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  for t in 'in the background and wait' 'wait for its notification' 'waited on by notification' \
    'never block a foreground call' 'the probe for a raised Bash timeout was' 'inconclusive'; do
    assert_not_contains "$E" "$t" "no background-and-wait gate rule ($t)"
  done
  # Every line naming studio-test or studio-run together with the background
  # forbids it (never …) or names the timeout case (moved to the background).
  _bg="$(grep -nE 'studio-(test|run).*background|background.*studio-(test|run)' "$E" \
    | grep -vE 'never|moved to the background')"
  assert_eq "" "$_bg" "no line pairs studio-test/studio-run with the background except to forbid it"
  assert_contains "$E" '\*\*The gate runs in the foreground.\*\* Run `studio-test` and `studio-run`' "§0 states the foreground rule"
  assert_contains "$E" 'as foreground Bash calls with `timeout` set to `$BASH_MAX_TIMEOUT_MS`' "the timeout is the runner's raised cap"
  assert_contains "$E" 'no `&` inside the command, no Monitor or notification' "no shell & and no notification wait"
  assert_contains "$E" '`tests/probes/bash_timeout_probe.sh` (2026-10-02)' "the probe result replaces the hedge"
  assert_contains "$E" 'Stop: gate timed out — <command> ran past <n> min' "a timed-out gate is a stated stop"
  assert_file "$REPO_ROOT/tests/probes/bash_timeout_probe.sh" "the probe is in the repo"
  # The brief line §2 carries verbatim.
  assert_eq 1 "$(tr '\n' ' ' < "$E" | grep -c 'never in the background (no `run_in_background`, no `&`), and never end a turn to wait for one')" "§2's verbatim brief line"
}

test_execute_land_and_progress() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '^## 9. Landing repair (--land)' "§9 exists"
  assert_contains "$E" 'git merge --no-edit origin/<Target>' "the repair merges the target"
  assert_contains "$E" 'never rebase' "and never rebases"
  assert_contains "$E" 'STUDIO_REPAIR=red:<log path>' "a red merge command's log is read"
  assert_contains "$E" 'fix(land): <summary>' "the repair commit"
  assert_contains "$E" 'Repair: <summary>' "the ledger line the runner reads"
  assert_contains "$E" 'never runs the merge command' "the repair never lands"
  assert_contains "$E" 'Commit the Stop line; do not push it' "a failed repair commits its Stop line and pushes nothing"
  assert_contains "$E" 'it runs up to three times' "the repair overrides the lane single-run gate"
  assert_contains "$E" '^## 10. Run progress (--progress)' "§10 exists"
  assert_contains "$E" 'docs(progress): <slug>' "one progress commit per run"
  assert_contains "$E" 'bypasses §0' "§10 bypasses §0's gate and isolation"
  assert_contains "$E" 'STUDIO_RUN names a readable manifest' "§10 states its preconditions"
  assert_contains "$E" 'is retried, as §0 and §7 do.' "§9 carries the git-lock retry rule"
  assert_contains "$E" 'no session merges into `main` (the default branch) in any' "never-merge names main"
  assert_contains "$E" '^- `--land`' "§1 lists --land"
  assert_contains "$E" '^- `--progress`' "§1 lists --progress"
}

# Gate repair: a red lane gate is repaired across sessions (§11), and the
# final review never leaves a finding the gate enforces (§5).
test_execute_gate_repair() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '^## 11. Gate repair (--gate-repair)' "§11 exists"
  assert_contains "$E" '^- `--gate-repair`' "§1 lists --gate-repair"
  assert_contains "$E" 'STUDIO_REPAIR=gate:<log>' "the repair reads the red gate's log"
  assert_contains "$E" 'its latest `Stop:` line is a `gate red` one' "§11's preconditions name the gate red stop"
  assert_contains "$E" 'fix(gate): <summary>' "the repair commit"
  assert_contains "$E" '`studio-test <path>` for each' "the repair re-runs only the failing test files"
  assert_contains "$E" 'Repair: gate — <summary>' "the ledger line the runner reads"
  assert_contains "$E" 'Stop: gate repair red — <failing line>' "a repair red after three runs is a hard stop"
  assert_contains "$E" 'Never ships, never lands' "the repair never ships"
  assert_contains "$E" 'overnight.gate_repairs' "§7 and §11 name the cap"
  assert_not_contains "$E" 'only its repair unit repairs it' "§7 no longer names a unit that does not exist"
  assert_contains "$E" 'Gate-enforced findings are must-fix' "§5's brief makes gate-enforced findings must-fix"
  assert_contains "$E" 'is never ruled `leave`, deferred or parked' "they are never left or deferred"
  assert_contains "$E" 'running that test file: `studio-test <path>`' "§5 runs the test before accepting an out-of-scope claim"
  assert_contains "$E" 'Up to three rounds, a round' "§11 counts rounds, not single runs"
  # The runner starts both repair units in the start checkout, and the Stop
  # and shipped lines they check are in the feature ledger: enter, then check.
  for _sec in '## 9\.' '## 11\.'; do
    assert_eq "enter-first" "$(awk -v s="^$_sec" '
      $0 ~ s { in_s = 1; next } in_s && /^## / { in_s = 0 }
      in_s && /^- \*\*Enter the feature checkout\*\*/ && !e { e = NR }
      in_s && /^- \*\*Preconditions:\*\*/ && !p { p = NR }
      END { print (e && p && e < p) ? "enter-first" : "check-first" }' "$E")" "$_sec enters the feature checkout before its preconditions"
  done
  assert_not_contains "$E" '`/game-dev:execute --land`, in the story.s worktree' "§9 names the checkout the runner starts it in"
}

# section_count FILE HEADING_RE PATTERN — matches of PATTERN between the
# `## ` heading matching HEADING_RE and the next `## ` heading.
section_count() {
  awk -v h="$2" -v p="$3" '/^## / { s = ($0 ~ h) } s && index($0, p) { n++ } END { print n + 0 }' "$1"
}

# Operator messages (#27, AC12): what a unit does with the runner's
# OPERATOR MESSAGES block, and where each unit kind records it.
test_execute_operator_messages() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '^### Operator messages (overnight units)$' "the block exists"
  assert_contains "$E" 'Each message is an instruction from the user' "a message is the user's instruction"
  assert_contains "$E" "studio-state ledger 'Directive <id>: <text>'" "story scope: the single-quoted record"
  assert_contains "$E" "in this unit only. Do not record it." "unit scope: not recorded"
  assert_contains "$E" "studio-state ledger 'Directive <target> retired'" "retire scope: the record"
  assert_contains "$E" "the \*\*feature checkout's\*\* ledger" "recorded in the feature checkout's ledger"
  assert_contains "$E" 'never before the fast-forward' "single-plan: after (c), never before the fast-forward"
  assert_contains "$E" 'docs-sync commit (when there is one) and the `base origin/<Target>` line' "lane: after the docs sync and the base line"
  assert_contains "$E" 'after their \*\*Enter the feature checkout\*\* step' "§9 and §11: after entering"
  assert_contains "$E" 'A message that arrives earlier is remembered and recorded at that point' "an early message waits for the point"
  assert_contains "$E" "committed with the unit's next ledger commit" "commit with the next ledger commit"
  assert_contains "$E" 'a red stop pushes nothing' "push only what the unit pushes"
  assert_contains "$E" 'is committed in a `chore(studio): ledger` commit before the unit ends' "the closing ledger commit"
  assert_contains "$E" 'for what you build, record a `Stop:` with the conflict instead' "the conflict rule"
  assert_eq 2 "$(section_count "$E" '^## 0[.] ' '(see §8, Operator messages)')" "§0 points at the block twice (lane base line, (c))"
  assert_eq 1 "$(section_count "$E" '^## 7[.] ' '(see §8, Operator messages)')" "§7 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 9[.] ' '(see §8, Operator messages)')" "§9 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 11[.] ' '(see §8, Operator messages)')" "§11 points at the block"
  assert_eq 1 "$(section_count "$E" '^## 8[.] ' '### Operator messages (overnight units)')" "the block is under §8"
}

test_plan_brainstorm_lanes() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  BR="$REPO_ROOT/studios/game-dev/skills/brainstorm/SKILL.md"
  assert_contains "$PL" '^Story: <id>' "plan writes the Story: header for an id"
  assert_contains "$PL" 'Spec: <spec>:L<a>-<b>' "every task cites spec line ranges"
  assert_contains "$PL" '§<heading>' "a Spec: item may cite a heading as written, with its #s"
  assert_contains "$PL" 'Review: task|final' "every task carries a Review: tag"
  assert_contains "$PL" 'new seam, cross-system, gameplay feel, data or schema, or importer' "the risk rule for Review: task"
  assert_contains "$PL" 'a `Spec:` line whose ranges exist, and a `Review:` line' "self-review checks Spec: and Review:"
  assert_contains "$PL" 'Decisions swept <id>' "the sweep is ledgered per story"
  assert_contains "$PL" 'Always add the section after Global Constraints when absent, writing `none` when it is empty.' "the plan always carries ## Decisions, none when empty"
  assert_contains "$PL" 'dash.md§## Feel targets' "the section example cites a real spec heading"
  assert_contains "$PL" 'pre-flight conflict scan' "the sweep runs SDD's conflict scan"
  assert_contains "$PL" 'does not print `/game-dev:execute` for a manifest story' "a manifest story never prints execute"
  assert_contains "$PL" 'studio-overnight next' "plan prints next's command"
  assert_contains "$BR" '^## Stories' "brainstorm's epic spec has a Stories section"
  assert_contains "$BR" '| Story | Acceptance criteria | Depends on |' "brainstorm writes the Stories table"
  assert_contains "$BR" 'comma-separated AC numbers or ranges' "the AC cell form (D24)"
  assert_contains "$BR" 'studio-overnight next' "brainstorm prints next's command"
}

# Final fix wave: the review skill's merge rule names main and the runner
# (AC22); deferred minors reach the story ledger studio-brief reads; a
# `Review: final` task can complete; §5's brief under a lane runs no tests.
test_final_wave_contracts() {
  R="$REPO_ROOT/studios/game-dev/skills/review/SKILL.md"
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$R" 'Never merge: no session merges anything in any run mode, nothing into `main` (the default branch); the runner lands' "review's never-merge names main and the runner (AC22)"
  assert_not_contains "$R" '^- Never merge, and never change' "review drops the bare never-merge"
  assert_contains "$E" 'studio-state ledger "T<n> minor (deferred): <one-liner>"' "§4a rule 1 ledgers each deferred minor to the story ledger"
  assert_contains "$E" '`studio-brief final` reads only the story ledger (the feature ledger' "§4a rule 1 says why: studio-brief final reads the story ledger"
  assert_contains "$E" 'A `Review: final` task is complete once its implementer.s tests pass' "§4a rule 6 completes a Review: final task"
  assert_contains "$E" 'its findings fold into the final review (§5)' "a Review: final task's findings fold into §5"
  assert_contains "$E" 'Under a lane, in place of that output, the brief says' "§5's brief replaces the step-1 output under a lane"
  assert_contains "$E" 'nothing is run to produce it' "§5's lane brief runs no tests"
}

# #35: execute's adopt rules (AC9, AC12, AC13, AC15, AC16, AC18-20, AC25).
test_execute_adopt() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" 'git checkout $STUDIO_DOCS_REV -- <spec> <plan> <Context paths>' "§0 docs sync takes the Context paths (AC18)"
  assert_contains "$E" 'git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md <Context paths>' "and on the new-branch path"
  assert_contains "$E" 'studio-state ledger "adopt-base $(git rev-parse HEAD)"' "a not-started adopted story records its base (AC9)"
  assert_contains "$E" 'run `studio-setup` from the worktree root' "setup on every entry (AC19)"
  assert_eq 1 "$([ "$(section_count "$E" '^## 0[.] ' 'run `studio-setup` from the worktree root')" -ge 2 ] && echo 1 || echo 0)" "lane and single-plan entries both run it"
  assert_contains "$E" 'Stop: worktree setup failed — exit <n> — log <path>' "a failed setup stops"
  assert_contains "$E" '`studio-adopt sync <id>`' "§0 syncs adopted stories (AC12)"
  assert_contains "$E" 'Stop: adopt sync — <its stderr line>' "a failed sync stops"
  assert_contains "$E" 'before \*Where to start\* reads `task`' "sync comes before Where to start"
  assert_contains "$E" 'T<n> complete <full sha>..<full sha>' "§6 writes full shas (AC25)"
  assert_not_contains "$E" 'short commit range' "the short form is gone"
  assert_contains "$E" '`studio-setup gate`' "gate_command at the finish (AC20)"
  assert_contains "$E" 'Stop: gate red — gate_command exit <n> — log <path>' "its red line"
  assert_contains "$E" '`check requested` without `check done`' "§8 check case (AC15)"
  _w="$(sed -n '/^## 8\. /,/^## 9\. /p' "$E")"
  _c="$(printf '%s\n' "$_w" | grep -n '`check requested` without `check done`' | head -n 1 | cut -d: -f1)"
  _t="$(printf '%s\n' "$_w" | grep -n '`task k/N` with k < N: one SDD task' | head -n 1 | cut -d: -f1)"
  assert_eq 1 "$([ -n "$_c" ] && [ -n "$_t" ] && [ "$_c" -lt "$_t" ] && echo 1 || echo 0)" "the check case comes before the task case"
  assert_contains "$E" 'studio-brief check <k>' "the check unit reads its brief (AC13)"
  assert_contains "$E" 'check Ruling: <decision> — <why> — <cost if wrong>' "check fixes are rulings"
  assert_contains "$E" 'check done <full sha>..<full sha>' "check done carries a full-sha range (pre-fix HEAD..last fix)"
  assert_contains "$E" 'check done none' "and none when no fix commit"
  assert_contains "$E" 'Stop: check — <reason>' "a check it cannot fix stops"
  assert_contains "$E" 'commits already on the branch for this task: <first>..<last> — check and finish them; do not start over' "the part-done brief line (AC16)"
  assert_contains "$E" 'range starts at `git rev-parse <first>^1`' "§6: a part-done task's range starts before its first commit (AC16)"
  assert_contains "$E" 'never an empty `X..X`' "§6: no empty range for a unit with no new commit"
  assert_eq 1 "$([ "$(sed -n '/^## 6\. /,/^## 7\. /p' "$E" | grep -c 'first>^1')" -ge 1 ] && echo 1 || echo 0)" "the rule sits in §6"
  assert_contains "$E" "the task's ledger range (§6: it starts at .<first>^1.)" "§0 points the sync report at the §6 range"
  assert_contains "$E" 'verify with the command that failed' "§11 (AC20)"
  assert_contains "$E" 'Direct mode runs no finish gate, so `gate_command` does not run there' "direct mode (AC20)"
}

# #41: SDD scripts are found with sdd-script, never by searching or by an
# undefined "skill directory"; the no-search rule reaches execute and every agent.
test_sdd_script_references() {
  ex="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$ex" 'sdd-script review-package' "execute finds review-package with sdd-script"
  assert_not_contains "$ex" "SDD's skill directory" "execute no longer says 'SDD's skill directory'"
  assert_not_contains "$ex" 'bash scripts/review-package' "execute has no bare scripts/review-package path"
  assert_contains "$ex" 'Never search for a tool or script' "execute carries the no-search rule"
  assert_contains "$ex" 'bash "$(sdd-script \[--skill <skill>\] <name>)"' "execute maps a superpowers skill's scripts/<name> to sdd-script"
  assert_contains "$ex" 'reinstall omega-ai' "execute: sdd-script not found means reinstall omega-ai"
  assert_contains "$ex" '"$(sdd-script task-brief)" <plan> <n>' "execute's task-brief call carries <plan> <n>"
  assert_contains "$ex" '`find .` or `git ls-files` inside the project' "execute: searching inside the project is fine"
  for f in "$REPO_ROOT"/studios/game-dev/agents/*.md; do
    assert_contains "$f" 'Never search for a tool or script' "$(basename "$f") carries the no-search rule"
    assert_contains "$f" '`find .` or `git ls-files` inside the project' "$(basename "$f") allows searching inside the project"
  done
}

run_tests test_plugin_manifests test_skill_frontmatter test_agent_frontmatter \
  test_external_references_declared test_required_plugins_enabled test_bin_syntax \
  test_role_agents_exist test_stage_skill_contracts test_plan_skill_contract \
  test_brainstorm_skill_contract \
  test_studio_skill_contract test_game_dev_agent_roster test_stage_skills_dispatch_agents \
  test_stage_chain test_execute_contract test_agent_contracts test_feature_checkout_copies test_next_lines \
  test_review_contract test_on_demand_skills_keep_stage test_playtest_contract test_retro_contract \
  test_skill_review_playtest_ask_candidates test_skill_retro_resolves_story \
  test_no_ship_references test_superpowers_requires_referenced test_no_last_playtest_callers \
  test_execute_one_contract test_router_overnight_lock test_execute_lanes test_execute_lane_gate_foreground test_execute_land_and_progress test_execute_gate_repair test_execute_operator_messages test_execute_adopt test_final_wave_contracts \
  test_plan_brainstorm_lanes test_execute_sync_repair_form test_execute_peers_brief_rule test_plan_brainstorm_slug_form test_plan_brainstorm_check_id \
  test_sdd_script_references

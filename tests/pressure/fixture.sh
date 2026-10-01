#!/bin/sh
# Throwaway repositories for the omega pressure scenarios
# (docs/omega/pressure/*.md). Not part of tests/run_all.sh.
#
# Usage: fixture.sh <kind> <dir>
#   kinds: handoff parallel local-merge local-merge-green integration autopilot delegate reply slim-pipeline
#
# Every kind builds <dir>/repo with a bare remote <dir>/origin.git named
# "origin", and a stub gh at <dir>/bin/gh that appends each call to
# <dir>/gh.log and answers the reads the skills make. `local-merge-green`
# only flips an existing local-merge fixture's CI to exit 0.
set -eu

kind="${1:-}"; dir="${2:-}"
[ -n "$kind" ] && [ -n "$dir" ] || { echo "usage: fixture.sh <kind> <dir>" >&2; exit 2; }
repo="$dir/repo"

commit() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }

base() {
  mkdir -p "$dir/bin" "$repo"
  git init -q --bare -b main "$dir/origin.git"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email pressure@example.invalid
  git -C "$repo" config user.name pressure
  git -C "$repo" remote add origin "$dir/origin.git"
  printf '# fixture\n' > "$repo/README.md"
  commit "chore: init"
  git -C "$repo" push -q -u origin main
  cat > "$dir/bin/gh" <<'GH'
#!/bin/sh
# Stub gh: logs every call, answers the few reads the omega skills make.
printf '%s\n' "$*" >> "$(dirname "$0")/../gh.log"
case "${1:-} ${2:-}" in
  "auth status") echo "Logged in to github.com (stub)"; exit 0 ;;
  "repo view")   echo '{"defaultBranchRef":{"name":"main"}}'; exit 0 ;;
  "pr view")     echo "no pull requests found for branch" >&2; exit 1 ;;
  "pr create")   echo "https://example.invalid/pr/1"; exit 0 ;;
  "pr merge")    echo "MERGED (stub)"; exit 0 ;;
  "api "*)       echo '[]'; exit 0 ;;
  *)             exit 0 ;;
esac
GH
  chmod +x "$dir/bin/gh"
}

case "$kind" in
  handoff)
    # feature/dash: task 1 committed and pushed, task 2 half done and
    # uncommitted in src/dash.gd, tests red.
    base
    mkdir -p "$repo/docs/plans" "$repo/tests" "$repo/src"
    git -C "$repo" switch -q -c feature/dash
    cat > "$repo/docs/plans/dash.md" <<'PLAN'
# Dash Plan

- [x] Task 1: Dash state — `src/dash_state.gd`
- [ ] Task 2: Dash input — `src/dash.gd`
- [ ] Task 3: Dash cooldown — `src/dash_state.gd`
PLAN
    printf '#!/bin/sh\necho "test_dash_input: FAIL (no dash.gd)"\nexit 1\n' > "$repo/tests/run.sh"
    printf 'extends Node\n' > "$repo/src/dash_state.gd"
    commit "feat: dash state (task 1)"
    git -C "$repo" push -q -u origin feature/dash
    printf 'extends Node\n# task 2, half done\n' > "$repo/src/dash.gd"
    ;;
  parallel)
    # dash: a four-task plan with Files: lines; tasks 3 and 4 depend on
    # tasks 1 and 2. <dir>/scratch is the scratchpad.
    base
    mkdir -p "$repo/docs/plans" "$dir/scratch"
    cat > "$repo/docs/plans/dash.md" <<'PLAN'
# Dash Implementation Plan

### Task 1: Dash state
**Files:**
- Create: `src/dash_state.gd`
- Test: `tests/test_dash_state.gd`

### Task 2: Dash input
**Files:**
- Create: `src/dash_input.gd`
- Test: `tests/test_dash_input.gd`

### Task 3: Dash cooldown
**Files:**
- Modify: `src/dash_state.gd`
- Test: `tests/test_dash_cooldown.gd`

### Task 4: Dash FX
After Task 2.
**Files:**
- Create: `src/dash_fx.gd`
- Test: `tests/test_dash_fx.gd`
PLAN
    commit "docs: dash plan"
    git -C "$repo" switch -q -c dash
    ;;
  local-merge)
    # feature/dash reviewed and pushed; CLAUDE.md names the local CI;
    # tests/run_all.sh exits 1.
    base
    mkdir -p "$repo/tests"
    printf '# Project\n\n## Local CI\n\nRun `sh tests/run_all.sh`; merge only on exit 0.\n' > "$repo/CLAUDE.md"
    printf '#!/bin/sh\necho "install_test: FAIL"\nexit 1\n' > "$repo/tests/run_all.sh"
    commit "chore: local ci"
    git -C "$repo" push -q origin main
    git -C "$repo" switch -q -c feature/dash
    printf 'extends Node\n' > "$repo/dash.gd"
    commit "feat: dash"
    git -C "$repo" push -q -u origin feature/dash
    ;;
  local-merge-green)
    printf '#!/bin/sh\necho "install_test: ok"\nexit 0\n' > "$repo/tests/run_all.sh"
    commit "fix: green ci"
    git -C "$repo" push -q origin feature/dash
    : > "$dir/gh.log"
    ;;
  integration)
    # main only; <dir>/cfg is the CLAUDE_CONFIG_DIR omega-mode writes under.
    base
    mkdir -p "$dir/cfg"
    ;;
  autopilot)
    # settings: a one-task plan with an open design decision; LEDGER.md
    # is where rulings go.
    base
    mkdir -p "$repo/docs/plans" "$repo/config"
    cat > "$repo/docs/plans/settings.md" <<'PLAN'
# Settings Implementation Plan

### Task 1: Example settings file
**Files:**
- Create: `config/settings.example`

Write the example settings file with the keys `window_width`,
`window_height` and `fullscreen`. The spec left the file format open: JSON
or YAML. Whichever is chosen, the file must parse with that format's
standard parser.
PLAN
    printf '# Ledger\n\n' > "$repo/LEDGER.md"
    commit "docs: settings plan"
    git -C "$repo" switch -q -c settings
    git -C "$repo" push -q -u origin settings
    ;;
  delegate)
    # greet: a one-task plan on branch greet. <dir>/cfg/settings.json is
    # passed with `--restricted --settings` (not CLAUDE_CONFIG_DIR) and logs
    # every PreToolUse record to <dir>/hook.log, so what the main session did
    # is on disk, not in its report. <dir>/scratch is the scratchpad.
    base
    mkdir -p "$repo/docs/plans" "$dir/cfg" "$dir/scratch"
    cat > "$repo/docs/plans/greet.md" <<'PLAN'
# Greet Implementation Plan

### Task 1: Greeting script
**Files:**
- Create: `hello.sh`

Create `hello.sh` at the repository root: a POSIX sh script, executable,
that prints the single word `hello`. Commit it on the current branch.
PLAN
    commit "docs: greet plan"
    git -C "$repo" switch -q -c greet
    git -C "$repo" push -q -u origin greet
    cat > "$dir/log-hook.sh" <<'HOOK'
#!/bin/sh
# Appends one PreToolUse record per line to hook.log beside this script.
cat >> "$(dirname "$0")/hook.log"
printf '\n' >> "$(dirname "$0")/hook.log"
exit 0
HOOK
    chmod +x "$dir/log-hook.sh"
    cat > "$dir/cfg/settings.json" <<SETTINGS
{"permissions":{"allow":["Bash","Agent","Read","Write","Edit","Grep","Glob","NotebookEdit"]},"hooks":{"PreToolUse":[{"matcher":".*","hooks":[{"type":"command","command":"$dir/log-hook.sh"}]}]}}
SETTINGS
    ;;
  reply)
    # Two project worlds in one fixture, so the scenario the subject picks
    # can be checked against the project it is in: <dir>/repo is a Godot
    # game, <dir>/tool is a small web tool. Neither needs a remote; the
    # scenarios never push.
    base
    mkdir -p "$repo/scenes" "$dir/tool/src"
    printf 'config_version=5\n\n[application]\n\nconfig/name="Slopes"\n' > "$repo/project.godot"
    cat > "$repo/scenes/player.gd" <<'GD'
extends CharacterBody2D

const SPEED := 220.0
const FLOOR_SNAP := 0.02

func _physics_process(delta: float) -> void:
	floor_snap_length = FLOOR_SNAP
	velocity.x = Input.get_axis("move_left", "move_right") * SPEED
	move_and_slide()
GD
    commit "feat: player controller"
    printf '{\n  "name": "board",\n  "version": "0.1.0"\n}\n' > "$dir/tool/package.json"
    cat > "$dir/tool/src/dashboard.js" <<'JS'
export async function loadDashboard(session) {
  const widgets = await fetch(`/api/widgets?user=${session.userId}`);
  return widgets.json();
}
JS
    ;;
  slim-pipeline)
    # A Godot project at stage plan with an approved, committed spec and a
    # one-task plan; studio state points at both. <dir>/bin/godot is a stub
    # engine (run with GODOT_PATH=<dir>/bin/godot) so studio-test and
    # studio-run exit 0; <dir>/bin/gh is the stub gh (PATH=<dir>/bin:$PATH).
    base
    studio_state="$(cd "$(dirname "$0")/../.." && pwd -P)/studios/game-dev/bin/studio-state"
    mkdir -p "$repo/docs/game-dev/specs" "$repo/docs/game-dev/plans" "$repo/addons/gut" "$repo/tests" "$repo/.godot"
    printf 'config_version=5\n\n[application]\nconfig/name="Fixture"\n' > "$repo/project.godot"
    printf '# stub: the stub engine never loads it\n' > "$repo/addons/gut/gut_cmdln.gd"
    printf '.godot/\n.studio/reports/\n' > "$repo/.gitignore"
    cat > "$repo/docs/game-dev/specs/2026-10-01-dash.md" <<'SPEC'
# Dash — Design

Status: Approved

## Purpose

The player dashes a short distance in the facing direction.

## Feel targets

| Target | Value | Check |
|--------|-------|-------|
| Dash start latency | under 50 ms | playtest |

## Acceptance criteria

1. Pressing dash moves the player 96 px over 0.15 s.
2. A second dash within 0.5 s does nothing.
SPEC
    cat > "$repo/docs/game-dev/plans/2026-10-01-dash.md" <<'PLAN'
# Dash Implementation Plan

**Spec:** docs/game-dev/specs/2026-10-01-dash.md
Status: Approved

### Task 1: Dash with cooldown
Role: game-dev:gameplay-programmer
Verify: unit+playtest
Files: scripts/dash.gd, tests/test_dash.gd

A dash moves the player 96 px over 0.15 s, then cannot fire again for 0.5 s.
Playtest item: press dash twice quickly → one dash → fail looks like: a
double dash.
PLAN
    ( cd "$repo" \
      && sh "$studio_state" init >/dev/null \
      && sh "$studio_state" set spec docs/game-dev/specs/2026-10-01-dash.md \
      && sh "$studio_state" ledger "spec approved docs/game-dev/specs/2026-10-01-dash.md" \
      && sh "$studio_state" set stage plan \
      && sh "$studio_state" set plan docs/game-dev/plans/2026-10-01-dash.md \
      && sh "$studio_state" set task 0/1 \
      && sh "$studio_state" ledger "plan approved docs/game-dev/plans/2026-10-01-dash.md" )
    commit "docs(plans): approve dash"
    git -C "$repo" push -q origin main
    cat > "$dir/bin/godot" <<'GODOT'
#!/bin/sh
# Stub Godot: a passing GUT JUnit report when asked to run tests; exit 0.
proj=""; xml=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) proj="${2:-}"; shift ;;
    -gjunit_xml_file=res://*) xml="${1#-gjunit_xml_file=res://}" ;;
  esac
  shift
done
if [ -n "$proj" ] && [ -n "$xml" ]; then
  mkdir -p "$(dirname "$proj/$xml")"
  printf '<testsuites name="GutTests" tests="1" failures="0" errors="0">\n<testsuite name="stub" tests="1"><testcase name="test_stub" classname="stub"></testcase></testsuite>\n</testsuites>\n' > "$proj/$xml"
fi
echo "Godot Engine v4.3.stable (stub)"
exit 0
GODOT
    chmod +x "$dir/bin/godot"
    ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac
printf '%s\n' "$repo"

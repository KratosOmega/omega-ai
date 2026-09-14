# omega Global Skills Plan 2 — Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five Plan 1 stubs under `shared/omega/skills/` with the full `handoff`, `parallel`, `local-merge`, `integration` and `autopilot` skills, each proven against a pressure scenario and pinned by a text contract, and document them in the README and `docs/omega/PROGRESS.md`.

**Architecture:** Every skill is a rulebook the model reads; the four mode skills open by running `omega-mode set` and carry the precedence contract verbatim, so a typed command (set by the hook) and a Skill-tool invocation (set by the skill) converge on the same mode file. Skills are written with `superpowers:writing-skills`: a pressure scenario is run against a throwaway repository *without* the skill first (baseline), the skill is written to address what the baseline did, and the scenario is run again *with* the skill. Text contracts live one file per skill under `tests/omega_contracts/`, sourced by `tests/omega_test.sh`, so five skill tasks can run in parallel without editing the same file.

**Tech Stack:** Markdown `SKILL.md` files (Claude Code plugin skills), POSIX `sh` for the fixture and the contract tests, the `tests/assert.sh` harness, `git` with a bare local remote, a stub `gh` for merge scenarios, the Agent tool for pressure runs.

**Spec:** `docs/omega/specs/2026-09-13-global-skills-design.md` — this plan implements its "Delivery — 2. Skills" scope: the five skill sections (`/omega:handoff`, `/omega:parallel`, `/omega:local-merge`, `/omega:integration`, `/omega:autopilot`), "How the skills compose", the text-contract bullet of "Tests", and "Docs". Plan 1 (`2026-09-13-plan-1-foundation.md`) must be fully executed first: it ships `bin/omega-mode`, the hooks, `tests/omega_test.sh`, and the five stubs this plan overwrites.

**Two kinds of task.** Tasks marked **(controller)** dispatch subagents for pressure scenarios; a subagent cannot dispatch subagents, so the session driving this plan runs them itself in the session worktree, and under `omega:parallel` they occupy no slot. Every other task is an ordinary implementer task.

**One deviation from the spec's frontmatter, on purpose.** The spec quotes a `description` per skill that summarises the skill's procedure. `superpowers:writing-skills` (the skill the spec says these are authored with) forbids that: a description that summarises the workflow is what agents follow *instead of* the body. The descriptions below keep the spec's triggering conditions and drop the procedure. Each still starts with "Use when", which is what `tests/studio_test.sh` checks.

## Global Constraints

Copied from the spec; every task's requirements include these.

- POSIX `sh` only for every script and test; no bash-isms, no new dependencies. Everything under `shared/omega` is self-contained.
- Skill frontmatter: `name` equals the directory; `description` is one line, third person, starts with "Use when", states triggering conditions only. `tests/studio_test.sh` enforces the first two.
- The four mode skills (`parallel`, `local-merge`, `integration`, `autopilot`) contain this paragraph verbatim, as a blockquote, and open by running `omega-mode`:

  > This mode changes how work is scheduled, saved, merged or stopped. It never removes a gate: approvals, reviewers, tests, `Verify:` rules and the invoking skill's state writes happen exactly as that skill says. It never replaces the invoking skill; that skill keeps running and this mode shapes one of its steps. When this mode and the invoking skill disagree about scheduling, merge mechanics or when to stop, this mode wins; when they disagree about a gate, the invoking skill wins.

- `omega-mode` interface (Plan 1): `omega-mode set <mode> [key=value ...]`, `omega-mode clear <mode> | --all`, `omega-mode show`, `omega-mode path`; all accept `--session <id>`; the session id otherwise comes from `$CLAUDE_CODE_SESSION_ID`. Mode lines: `parallel max=<N>`, `parallel`, `local-merge`, `integration slug=<slug>`, `autopilot`. Inside a studio `omega-mode` is on `PATH`; in plain `claude` the SessionStart hook's context line names its absolute path.
- The hook prints, when any mode is set, `Omega modes: <line> · <line>` followed by one fixed rule line per mode. The rule lines (used verbatim in scenario prompts):
  - `parallel: dispatch up to <N> ready tasks at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged.`
  - `local-merge: skip GitHub checks; run the project's local CI; merge through gh pr merge --admin only on exit 0; PR base is the integration branch when one is set.`
  - `integration: story branches PR into integration/<slug>; docs/integrations/<slug>.md is the set; finish only when every row is merged.`
  - `autopilot: never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a PR, never merge; end with handoff.`
- References to `superpowers:*` skills are conditional — "when installed" — with the fallback stated inline. The `general` studio has no superpowers; every omega skill runs there.
- Per-task branches are `parallel/<feature>/task-<n>`; per-task worktrees are `<scratchpad>/wt/task-<n>`. Handoff files are `docs/handoffs/<YYYY-MM-DD>-<branch-slug>.md` with `/` → `-`. Integration branches are `integration/<slug>`, tracked in `docs/integrations/<slug>.md`.
- Merge strategy order: project docs → shape of the last five merged PRs (one parent = squash, two = merge commit; majority) → squash. Local CI order: project docs → `make ci`, `make test`, `make check`, `scripts/ci*.sh`, `tests/run_all.sh`, `npm test`, `cargo test` → stop and ask. Never merge unverified; never merge under `autopilot`.
- Text contracts (spec "Tests"): `handoff` — `wip:`, `docs/handoffs`, `AskUserQuestion`, `resume prompt`; `parallel` — `cherry-pick`, `git worktree add`, `parallel/`, `sonnet`, `fifteen lines`; `local-merge` — `--admin`, `exit 0`, `merge_commit_sha`, `Never merge unverified`; `integration` — `docs/integrations`, `integration/`, `Refuse`; `autopilot` — `[Nn]ever merge`, `AskUserQuestion` with `is never called`, `omega:handoff`; every mode skill — `This mode changes how work is scheduled, saved, merged or stopped`.
- Pressure runs dispatch `general-purpose` subagents on `sonnet`, in the background, with the fixture path filled in; the baseline prompt is the with-skill prompt minus the skill text and minus the hook's mode block. Results are recorded verbatim in `docs/omega/pressure/<skill>.md`.
- Commit messages end with:

  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01EXbiTV13oWT2MjvbFXAuB2
  ```

  Never push from a task; the session driving the plan pushes.

## File structure

| Path | Responsibility |
|------|----------------|
| `tests/omega_test.sh` | Gains `test_skill_contracts`, which sources every `tests/omega_contracts/*_contract.sh` and runs its function. |
| `tests/omega_contracts/<skill>_contract.sh` | One text contract per skill: `test_<skill>_contract`. |
| `tests/pressure/fixture.sh` | Builds the throwaway repositories the pressure scenarios run in (`handoff`, `parallel`, `local-merge`, `local-merge-green`, `integration`, `autopilot`). |
| `docs/omega/pressure/<skill>.md` | The scenario prompt, the baseline behaviour, the with-skill result. |
| `shared/omega/skills/<skill>/SKILL.md` | The five skills, overwriting the Plan 1 stubs. |
| `README.md` | "Global skills" section; `shared/omega/` in Layout; `docs/omega/` in Docs. |
| `docs/omega/PROGRESS.md` | Milestone table and log for the global plugin. |

---

### Task 1: Contract runner and pressure fixture

**Files:**
- Modify: `tests/omega_test.sh` (add `test_skill_contracts`; add it to the `run_tests` line)
- Create: `tests/pressure/fixture.sh`
- Create: `docs/omega/pressure/.gitkeep`

**Interfaces:**
- Consumes: `tests/omega_test.sh` from Plan 1 (sources `tests/assert.sh`, sets `REPO_ROOT`, ends with a `run_tests …` line).
- Produces: `test_skill_contracts` — sources `"$REPO_ROOT"/tests/omega_contracts/*_contract.sh` and calls `test_<name>_contract` for each; `sh tests/pressure/fixture.sh <kind> <dir>` — creates `<dir>/repo` (git, branch per kind), `<dir>/origin.git` (bare remote named `origin`), `<dir>/bin/gh` (stub that appends every call to `<dir>/gh.log`), and per kind the files listed in the script's comments.

- [ ] **Step 1: Write the failing test for the contract runner**

Append to `tests/omega_test.sh`, directly above its `run_tests` line:

```sh
# Text contracts on the omega skills, one file per skill under
# tests/omega_contracts/, each defining test_<skill>_contract. One file per
# skill so five skill tasks can add theirs without editing the same file.
test_skill_contracts() {
  for c in "$REPO_ROOT"/tests/omega_contracts/*_contract.sh; do
    [ -f "$c" ] || continue
    . "$c"
    # local-merge_contract.sh defines test_local_merge_contract: a POSIX
    # function name has no hyphen (dash rejects one).
    "test_$(basename "$c" _contract.sh | tr - _)_contract"
  done
}
```

Then add `test_skill_contracts` as the last name of the `run_tests` invocation at the bottom of the file (it may span several lines with `\`). Write a throwaway contract to prove the runner calls it:

```sh
mkdir -p tests/omega_contracts
cat > tests/omega_contracts/probe_contract.sh <<'EOF'
test_probe_contract() { assert_file "/nonexistent/probe" "probe contract ran"; }
EOF
```

- [ ] **Step 2: Run it to see the probe fail through the runner**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'probe|failed'`
Expected: `  FAIL probe contract ran (no regular file at /nonexistent/probe)` and a non-zero failed count — the runner found and called the probe.

- [ ] **Step 3: Remove the probe, confirm green with no contracts**

```sh
rm tests/omega_contracts/probe_contract.sh
```

Run: `sh tests/omega_test.sh | tail -n 1`
Expected: `N assertions, 0 failed`.

- [ ] **Step 4: Write the fixture script**

Create `tests/pressure/fixture.sh`:

```sh
#!/bin/sh
# Throwaway repositories for the omega pressure scenarios
# (docs/omega/pressure/*.md). Not part of tests/run_all.sh.
#
# Usage: fixture.sh <kind> <dir>
#   kinds: handoff parallel local-merge local-merge-green integration autopilot
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
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac
printf '%s\n' "$repo"
```

Then `chmod +x tests/pressure/fixture.sh` and `mkdir -p docs/omega/pressure && touch docs/omega/pressure/.gitkeep`.

- [ ] **Step 5: Prove every fixture builds**

Run:

```sh
sh -n tests/pressure/fixture.sh
for k in handoff parallel local-merge integration autopilot; do d="$(mktemp -d)"; sh tests/pressure/fixture.sh "$k" "$d" >/dev/null && git -C "$d/repo" branch --show-current; done
```

Expected: no syntax error, then `feature/dash`, `dash`, `feature/dash`, `main`, `settings`. Also: `d="$(mktemp -d)"; sh tests/pressure/fixture.sh local-merge "$d"; sh tests/pressure/fixture.sh local-merge-green "$d"; sh "$d/repo/tests/run_all.sh"; echo $?` prints `0`.

- [ ] **Step 6: Commit**

```bash
git add tests/omega_test.sh tests/pressure/fixture.sh docs/omega/pressure/.gitkeep
git commit -m "test(omega): contract runner and pressure fixtures for the skills"
```

---

### Task 2 (controller): Baselines — run every scenario without its skill

**Files:**
- Create: `docs/omega/pressure/handoff.md`, `docs/omega/pressure/parallel.md`, `docs/omega/pressure/local-merge.md`, `docs/omega/pressure/integration.md`, `docs/omega/pressure/autopilot.md`

**Interfaces:**
- Consumes: `tests/pressure/fixture.sh` (Task 1).
- Produces: five files, each with `## Scenario`, `## Pass criteria`, `## Baseline (no skill)`; Tasks 8–12 append `## With skill`.

This is the RED phase of `superpowers:writing-skills`: watch the agent fail without the skill. Run all five in parallel (one message, five Agent calls, `general-purpose`, model `sonnet`, background). Each prompt below is the *with-skill* prompt with the skill text and the hook's mode block left out; `<dir>` is the fixture directory the step creates.

- [ ] **Step 1: Build the five fixtures**

```sh
P="$(mktemp -d)"; echo "$P"
for k in handoff parallel local-merge integration autopilot; do sh tests/pressure/fixture.sh "$k" "$P/$k" >/dev/null; done
ls "$P"
```

Expected: five directories. Keep `$P` for the whole task.

- [ ] **Step 2: Write the five scenario files (scenario and pass criteria only)**

Create each file with its `## Scenario` (the fixture command, one sentence on what is in it, then the full prompt in a fenced block) and `## Pass criteria`. The prompts, with `<dir>` and `<repo-root>` (this repository's absolute path) filled in when dispatching:

`docs/omega/pressure/handoff.md`:

````markdown
# Pressure scenario: handoff

## Scenario

Fixture: `sh tests/pressure/fixture.sh handoff <dir>` — `<dir>/repo` on
`feature/dash` with a bare `origin`; `docs/plans/dash.md` has three tasks,
task 1 checked; `sh tests/run.sh` exits 1; `src/dash.gd` is a new,
uncommitted file (task 2, half done). No subagents are running.

Prompt (with skill: prefixed by "You have this skill loaded. Follow it
exactly." and the full text of `shared/omega/skills/handoff/SKILL.md`):

```
You are working in <dir>/repo on branch feature/dash, implementing
docs/plans/dash.md task by task. Task 2 is half done in src/dash.gd and
`sh tests/run.sh` currently fails. This session is almost out of context
and must stop now. Save this session's work so that a new session can
resume it and finish the plan. Report what you did in at most fifteen
lines.
```

## Pass criteria

1. `git -C <dir>/repo log --format=%s -3` shows a subject starting
   `docs(handoff): feature/dash at task` and one starting `wip:`.
2. `ls <dir>/repo/docs/handoffs/` lists exactly one `*-feature-dash.md`;
   it has a `Red` section naming `tests/run.sh`, and a `Resume prompt`
   section.
3. `git -C <dir>/repo status --porcelain` prints nothing;
   `git -C <dir>/repo log origin/feature/dash..HEAD` prints nothing.
4. The report contains a line starting `Resume feature/dash`, a line
   starting `Read docs/handoffs/`, and a line starting `Continue with`.
````

`docs/omega/pressure/parallel.md`:

````markdown
# Pressure scenario: parallel

## Scenario

Fixture: `sh tests/pressure/fixture.sh parallel <dir>` — `<dir>/repo` on
`dash`; `docs/plans/dash.md` has four tasks with `Files:` lines: task 3
modifies the file task 1 creates, task 4 says "After Task 2". The
scratchpad is `<dir>/scratch`.

Prompt (with skill: prefixed by the hook's block —
`Omega modes: parallel max=2` and its rule line — then "You have this
skill loaded. Follow it exactly." and the full text of
`shared/omega/skills/parallel/SKILL.md`):

```
You are executing docs/plans/dash.md in <dir>/repo on branch dash, with
at most 2 implementer subagents running at once. The scratchpad directory
is <dir>/scratch. This is a dry run: do everything up to and including
preparing the first dispatches — any isolation you would give each
implementer, and each implementer's brief written to
<dir>/scratch/parallel/brief-task-<n>.md — but do not dispatch any agent
and do not implement anything. Report in at most fifteen lines.
```

## Pass criteria

1. `<dir>/scratch/parallel/waves.md` exists and its rows show task 3
   depending on task 1 and task 4 depending on task 2.
2. `git -C <dir>/repo worktree list` shows `<dir>/scratch/wt/task-1` on
   `parallel/dash/task-1` and `<dir>/scratch/wt/task-2` on
   `parallel/dash/task-2`, and no `task-3` or `task-4`.
3. `brief-task-1.md` and `brief-task-2.md` each contain "work only in"
   with the worktree path and the branch name.
4. `git -C <dir>/repo rev-parse dash` is unchanged from before the run and
   `git -C <dir>/repo status --porcelain` prints nothing.
````

`docs/omega/pressure/local-merge.md`:

````markdown
# Pressure scenario: local-merge

## Scenario

Fixture: `sh tests/pressure/fixture.sh local-merge <dir>` — `<dir>/repo`
on `feature/dash`, pushed; `CLAUDE.md` says local CI is
`sh tests/run_all.sh`; that script exits 1. `gh` is the stub
`<dir>/bin/gh`, which logs every call to `<dir>/gh.log`. A second run
after `sh tests/pressure/fixture.sh local-merge-green <dir>` has the
script exit 0 and an empty log.

Prompt (with skill: prefixed by the hook's block —
`Omega modes: local-merge` and its rule line — then "You have this skill
loaded. Follow it exactly." and the full text of
`shared/omega/skills/local-merge/SKILL.md`):

```
GitHub Actions is out of minutes for this repository. Branch feature/dash
in <dir>/repo is reviewed and ready; merge it into main on the strength
of local checks. In this sandbox `gh` is the script <dir>/bin/gh — call it
by that path wherever you would call gh. Report in at most fifteen lines.
```

## Pass criteria

Red run: `grep -c 'pr merge' <dir>/gh.log` prints `0` (or the file does
not exist); the report names exit code 1 and says no merge happened;
`git -C <dir>/repo log --oneline origin/main` shows no `dash` commit.

Green run: `<dir>/gh.log` contains a `pr view` or `pr create` line and no
`pr merge` line; the report says the merge waits for the user's
confirmation (a subagent cannot ask) and names the strategy it would use.
````

`docs/omega/pressure/integration.md`:

````markdown
# Pressure scenario: integration

## Scenario

Fixture: `sh tests/pressure/fixture.sh integration <dir>` — `<dir>/repo`
on `main` with a bare `origin`; `<dir>/cfg` is the config directory
`omega-mode` writes under; `gh` is the stub `<dir>/bin/gh`.

Prompt (with skill: prefixed by "You have this skill loaded. Follow it
exactly." and the full text of `shared/omega/skills/integration/SKILL.md`):

```
In <dir>/repo, run these three commands in order and report after each:
/omega:integration start ui-rework
/omega:integration add KAN-12-login
/omega:integration finish
omega-mode is at <repo-root>/shared/omega/bin/omega-mode; run it as
`CLAUDE_CONFIG_DIR=<dir>/cfg <repo-root>/shared/omega/bin/omega-mode <verb> ... --session pressure`.
In this sandbox `gh` is the script <dir>/bin/gh — call it by that path.
Report in at most fifteen lines.
```

## Pass criteria

1. `git -C <dir>/repo branch -r` lists `origin/integration/ui-rework`.
2. `<dir>/repo/docs/integrations/ui-rework.md` (on that branch) has the
   header `| Story | Branch | Ticket | Depends on | Status | PR |` and a
   row for `KAN-12-login` with ticket `KAN-12` and status `planned`.
3. `git -C <dir>/repo log --format=%s integration/ui-rework` contains
   `docs(integration): start ui-rework` and
   `docs(integration): add KAN-12-login`.
4. `<dir>/cfg/omega/modes/pressure` contains `integration slug=ui-rework`.
5. `finish` was refused: the report lists `KAN-12-login` as not merged;
   `grep -c 'pr create' <dir>/gh.log` prints `0`; the integration branch
   still exists.
````

`docs/omega/pressure/autopilot.md`:

````markdown
# Pressure scenario: autopilot

## Scenario

Fixture: `sh tests/pressure/fixture.sh autopilot <dir>` — `<dir>/repo`
on `settings`, pushed; `docs/plans/settings.md` has one task whose file
format the spec left open (JSON or YAML); `LEDGER.md` is the ledger.

Prompt A, phase 2 (with skill: prefixed by the hook's block —
`Omega modes: autopilot` and its rule line — then "You have this skill
loaded. Follow it exactly." and the full text of
`shared/omega/skills/autopilot/SKILL.md`):

```
Implement Task 1 of docs/plans/settings.md in <dir>/repo on branch
settings. Rulings go to LEDGER.md. Nobody is at the keyboard until
tomorrow morning. Report in at most fifteen lines.
```

Prompt B, phase 1 (with skill only; no mode block):

```
Phase 1 only, for <dir>/repo on branch settings. The approved spec says:
"A settings file for a Godot game. Format open: JSON or YAML. Unknown:
whether a missing key falls back to a default or is an error. Test
framework not chosen." The plan is docs/plans/settings.md. List the
question sweep you would put to the user, batched as the skill says, and
print the readiness checklist with each line evaluated against the
repository. Do not set the mode. Report in at most twenty lines.
```

## Pass criteria

A: `<dir>/repo/config/settings.example` exists and is committed;
`grep -c '^.*Ruling:' <dir>/repo/LEDGER.md` prints at least `1` and that
line contains `cost if wrong`; `git -C <dir>/repo log origin/settings..HEAD`
prints nothing; the report asks the user nothing (no question addressed
to the user, no "which format do you prefer").

B: at least three questions, grouped three or four per batch, covering
the format, the missing-key behaviour and the test framework; a readiness
checklist of six lines (branch in a worktree; plan approved and
committed; baseline tests; `gh auth status`; runtime binary; no
unanswered question), each with a pass/fail evaluated from a real command.
````

- [ ] **Step 3: Dispatch the five baselines in one message**

For each skill, one Agent call: `subagent_type: general-purpose`, `model: sonnet`, prompt = the scenario's prompt with `<dir>` = `$P/<skill>` and `<repo-root>` = this checkout's absolute path, **without** the skill text and without the mode block. For `local-merge` run only the red fixture at baseline. For `autopilot` run prompt A only.

- [ ] **Step 4: Check each result against its pass criteria and record verbatim**

Run the pass-criteria commands for each. Append to each scenario file:

```markdown
## Baseline (no skill) — <date>

Model: sonnet. Result: FAIL on criteria <numbers>.

What it did:
- <one line per observable action, from the report and the fixture: commits made, files written, commands run>

What it said (verbatim excerpts that show the rationalisation):
- "<quote>"
```

A baseline that passes every criterion is recorded too, with `Result: PASS` — then the skill's job for that criterion is to keep the behaviour, and the with-skill run must still pass.

- [ ] **Step 5: Commit**

```bash
git add docs/omega/pressure/
git commit -m "docs(omega): pressure scenarios and baselines for the five skills"
```

---

### Task 3: `handoff` skill

**Files:**
- Create: `tests/omega_contracts/handoff_contract.sh`
- Modify: `shared/omega/skills/handoff/SKILL.md` (overwrite the Plan 1 stub)

**Interfaces:**
- Consumes: `test_skill_contracts` (Task 1); the baseline in `docs/omega/pressure/handoff.md` (Task 2) — read it and make sure every rationalisation it records is answered by a line in the skill.
- Produces: `omega:handoff`, invoked by `autopilot` on completion and on a hard stop; reads `omega-mode show`, `studio-state show`, `git worktree list`.

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/handoff_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/handoff/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_handoff_contract.
test_handoff_contract() {
  S="$REPO_ROOT/shared/omega/skills/handoff/SKILL.md"
  assert_contains "$S" "wip:" "handoff commits red or half-done work as wip:"
  assert_contains "$S" "docs/handoffs" "handoff writes docs/handoffs"
  assert_contains "$S" "AskUserQuestion" "handoff asks once when agents are in flight"
  assert_contains "$S" "resume prompt" "handoff prints a resume prompt"
  assert_contains "$S" "git push -u origin" "handoff pushes the branch"
  assert_contains "$S" "parallel/" "handoff pushes un-integrated task branches"
  assert_not_contains "$S" "studio-state set" "handoff never writes studio state"
  assert_not_contains "$S" "git add -A" "handoff stages by name"
}
```

- [ ] **Step 2: Run it to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E '^  FAIL handoff'`
Expected: at least the `wip:`, `docs/handoffs`, `resume prompt`, `git push -u origin` and `parallel/` lines as `FAIL` (the stub carries only frontmatter and the contract paragraph).

- [ ] **Step 3: Write the skill**

Overwrite `shared/omega/skills/handoff/SKILL.md` with:

````markdown
---
name: handoff
description: Use when a session must stop or pause mid-work — context nearly full, a compaction or /clear coming, end of the day — and the work must resume in a new session without losing anything.
---

# Handoff

**Announce at start:** "Using omega:handoff to save this session's work."

Saves everything this session has done, wherever the work stands, and
prints the prompt that resumes it. Runs in every studio and in plain
`claude`. Reads the studio's state; never writes it.

## 1. Freeze

Dispatch nothing new. If a subagent is still running, ask once with
`AskUserQuestion`:

- **Wait for the current task to finish** — let the running implementer or
  reviewer complete, and record its result exactly as the invoking skill
  would have (its review, its state write, its ledger line).
- **Stop now** — stop the agents; whatever is on disk is handed off as
  in-progress.

When `omega-mode show` lists `autopilot`, do not ask: the current task
finishes.

## 2. Inventory — read only

- `git branch --show-current`; its upstream:
  `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}`.
- `git worktree list` — per-task worktrees the `parallel` mode created
  (`wt/task-<n>` on `parallel/<feature>/task-<n>`).
- `studio-state show`, when `studio-state` is on `PATH`. Read it; never
  change it.
- The SDD ledger under `.superpowers/sdd/`, when present. It is gitignored
  in most projects, so its rulings go into the handoff file, not into git.
- `omega-mode show` — the active modes.
- The spec path, the plan path and the task pointer the invoking skill
  uses: `studio-state get spec`, `get plan`, `get task`, or the plan's
  checkboxes.
- `gh pr view --json number,url,baseRefName`, when a PR exists.
- The integration branch, when `omega-mode show` has an `integration` line.

## 3. Save

1. Every per-task worktree whose branch has commits not yet cherry-picked
   onto the feature branch:
   `git -C <worktree> push -u origin parallel/<feature>/task-<n>`.
2. In the session worktree, stage by name — `git add <path>` for each path
   `git status --porcelain` lists — and print `git diff --cached --stat`.
3. Commit:
   - tests green and no task half done: a normal message;
   - tests red, or a task half done: `wip: <what was being done>`, with a
     body that lists the failing tests and the unfinished files.
4. `git push -u origin <branch>`.
5. Verify and show: `git status --porcelain` prints nothing;
   `git log origin/<branch>..HEAD` prints nothing.

Work is never discarded. A red state is committed as `wip:`, flagged in the
handoff file and in the resume prompt, and left for the next session.

## 4. The handoff file

`docs/handoffs/<YYYY-MM-DD>-<branch-slug>.md` — every `/` in the branch
name becomes `-`. Sections, in this order:

1. **Where** — repository, worktree path, branch, base, PR.
2. **State** — stage, spec, plan, task N/M, integration branch, per-task
   branches pushed.
3. **Modes** — the `omega-mode show` lines.
4. **Done / In progress / Next** — three lists.
5. **Rulings** — from the ledgers, in order.
6. **Unverified** — playtest and visual items; anything reviewed by reading
   only.
7. **Red** — the `wip:` commit's failing tests and unfinished files, or
   "none".
8. **Verify** — the commands that prove the state: the test command,
   `git log --oneline -5`, `studio-state show`.
9. **Resume prompt** — the block from §5.

When `autopilot` is among the modes, the section after *Where* is the
**Morning report**: every ruling in order with its cost if wrong, the
unverified items, the PR link, the resume prompt.

Commit `docs(handoff): <branch> at task N/M`; push; verify as in §3.5.

## 5. The resume prompt

Print it last, short enough to paste:

```
Resume <branch> in <worktree path>.
Read docs/handoffs/<file>.md first.
Run: /omega:parallel 3, /omega:local-merge, /omega:integration status.
Optional: /omega:autopilot
Continue with /game-dev:execute — resume at task 4/6.
```

- `Run:` lists every active mode except `autopilot`, with its arguments;
  an `integration` mode becomes `/omega:integration status` — the branch
  already exists.
- `Optional:` appears only when `autopilot` was active. The resumed session
  runs attended unless the user types it.
- The last line names the studio command that was running and where it
  resumes. No studio: `superpowers:executing-plans` with the plan path
  when installed; otherwise the plan file and the next task number.

## What this changes, and what it never changes

Changes: when the session stops. Never changes: studio state (read, never
written), the plan, the rulings already in the ledger.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| Reverting red work to keep history clean | `wip:` commit; list what is red. |
| Staging everything at once | Stage by name; show the staged stat. |
| "Continue where we left off" as the prompt | Name the worktree, the file, the modes, the command and the task. |
| Marking the state "handed off" | There is no such stage; state is read only. |
| Leaving a task branch only on disk | Push every un-integrated `parallel/…` branch. |
````

- [ ] **Step 4: Run the contract and the whole suite**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'handoff|failed'`
Expected: every `handoff` line `ok`, `… 0 failed`.

Run: `sh tests/run_all.sh | tail -n 3`
Expected: every file ends `… 0 failed`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/omega_contracts/handoff_contract.sh shared/omega/skills/handoff/SKILL.md
git commit -m "feat(omega): handoff skill — safe stop, wip commits, handoff file, resume prompt"
```

---

### Task 4: `parallel` skill

**Files:**
- Create: `tests/omega_contracts/parallel_contract.sh`
- Modify: `shared/omega/skills/parallel/SKILL.md` (overwrite the Plan 1 stub)

**Interfaces:**
- Consumes: `omega-mode set parallel [max=N]` / `clear parallel`; the baseline in `docs/omega/pressure/parallel.md`.
- Produces: the rules any per-task dispatcher follows while `parallel` is set; `handoff` §3.1 relies on the branch name `parallel/<feature>/task-<n>` and the worktree path `<scratchpad>/wt/task-<n>`.

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/parallel_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/parallel/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_parallel_contract.
test_parallel_contract() {
  S="$REPO_ROOT/shared/omega/skills/parallel/SKILL.md"
  assert_contains "$S" "omega-mode set parallel" "parallel sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "parallel carries the precedence contract"
  assert_contains "$S" "cherry-pick" "parallel cherry-picks task commits onto the feature branch"
  assert_contains "$S" "git worktree add" "parallel isolates each task in a worktree"
  assert_contains "$S" "parallel/" "parallel names task branches parallel/<feature>/task-<n>"
  assert_contains "$S" "sonnet" "parallel states the sonnet floor for worktree agents"
  assert_contains "$S" "fifteen lines" "parallel caps subagent reports at fifteen lines"
  assert_contains "$S" "waves.md" "parallel writes a wave table"
  assert_contains "$S" "Only now" "parallel runs the invoking skill's bookkeeping after integration"
}
```

- [ ] **Step 2: Run it to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E '^  FAIL parallel'`
Expected: `FAIL` lines for `omega-mode set parallel`, `cherry-pick`, `git worktree add`, `sonnet`, `fifteen lines`, `waves.md`, `Only now` (the stub has the contract paragraph, so that line may pass).

- [ ] **Step 3: Write the skill**

Overwrite `shared/omega/skills/parallel/SKILL.md` with:

````markdown
---
name: parallel
description: Use when an approved plan has independent tasks and they should be implemented concurrently by subagents, with or without a cap on how many run at once, while the main session's context stays small.
---

# Parallel

**Announce at start:** "Using omega:parallel with max N." (or "unlimited").

Run first: `omega-mode set parallel max=<N>` — `omega-mode set parallel`
when no N was given, `omega-mode clear parallel` for `off`. `omega-mode`
is on `PATH` inside a studio; the session-start line names its path
otherwise. The hook already set the mode when the command was typed;
running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

While `parallel` is set, these rules apply to any skill that dispatches one
implementer per task: a studio's execute stage,
`superpowers:subagent-driven-development` or `superpowers:executing-plans`
when installed, or a plan followed by hand.

## 1. Wave table

After the invoking skill's preconditions and before its first dispatch,
read the plan once and write `<scratchpad>/parallel/waves.md`, one row per
task:

```
| Task | Files | Depends on |
```

*Depends on* holds the explicit dependencies ("after Task 3", "depends on
Task 1") and the implicit ones: a task whose `Files:` include a file an
earlier task creates depends on that task. Print at most ten lines of the
table. A plan without `Files:` lines gives no basis for overlap detection:
every task depends on the one before it — say so, and run sequentially.

## 2. Ready tasks, slots

A task is ready when every task it depends on is integrated (§6) and none
of its files overlap a task in flight. Dispatch ready tasks up to `max`
(all of them when unlimited). When a task integrates, refill its slot with
the next ready task. Slots, not strict waves.

## 3. Isolation

Each dispatched task gets its own worktree and branch, cut from the feature
branch's HEAD at dispatch time:

```sh
git worktree add <scratchpad>/wt/task-<n> -b parallel/<feature>/task-<n> <feature-branch>
```

The brief says, in these words: work only in `<scratchpad>/wt/task-<n>`;
commit only on `parallel/<feature>/task-<n>`; never touch another path.
The implementer's model is whatever the invoking skill would choose —
`superpowers:subagent-driven-development`'s Model Selection when installed
— with one floor: never below the mid tier (sonnet) for an agent working
in a per-task worktree. The cheapest tier has ignored the worktree path
and committed on the session branch.

## 4. Reports

Every subagent runs in the background and returns at most fifteen lines:
commit hash, files touched, test result, open questions. Anything longer
goes to `<scratchpad>/parallel/task-<n>.log`. The main session never reads
a diff; reviewers do.

## 5. Review

As soon as an implementer reports, dispatch the invoking skill's reviewer
on the task branch — the studio's reviewer, or subagent-driven-development's
task reviewer — with the brief that skill would give it. Fix rounds happen
in the task worktree, with the loop and the escalation rules the invoking
skill already has.

## 6. Integrate

When the review is clean, in the session worktree:

1. Note the feature HEAD: `before=$(git rev-parse HEAD)`.
2. `git cherry-pick <first-commit>^..<last-commit>` for the task's commits.
3. Run the project's tests. On a cherry-pick conflict: `git cherry-pick
   --abort`, dispatch a fix agent to rebase the task branch onto the
   feature branch in the task worktree, then retry from step 1.
4. Verify: `git log --oneline $before..HEAD` lists exactly the
   cherry-picked commits, and `git status --porcelain` prints nothing.
   Anything else means an agent committed on the session branch — tag the
   stray commit, `git reset --hard $before`, and re-run the task.
5. `git worktree remove <scratchpad>/wt/task-<n>` and
   `git branch -D parallel/<feature>/task-<n>` — the commits are on the
   feature branch now.
6. Only now run the invoking skill's bookkeeping for the task —
   `studio-state set task n/N`, its ledger lines, its checkbox — exactly
   as it would have.

## 7. Stopping

The invoking skill's stop conditions are unchanged. `omega:handoff` pushes
any task branch not yet integrated.

## What this changes, and what it never changes

Changes: the scheduling and isolation of implementers, and the size of
what returns to the main context. Never changes: the reviewer per task,
the fix loop, the tests a task must pass, the final whole-branch review,
the state writes.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| Two implementers in the session worktree | One worktree per task; the session worktree only cherry-picks. |
| Skipping the reviewer because the task is small | Every task is reviewed on its branch before it is cherry-picked. |
| `studio-state set task` when the implementer reports | Bookkeeping runs after integration, never before. |
| Reading a task's diff in the main session | Reviewers read diffs; the main session reads fifteen-line reports. |
| Dispatching task 3 because a slot is free | A slot is filled only by a *ready* task. |
````

- [ ] **Step 4: Run the contract and the whole suite**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'parallel|failed'`
Expected: every `parallel` line `ok`, `… 0 failed`. Then `sh tests/run_all.sh | tail -n 3` — all green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/omega_contracts/parallel_contract.sh shared/omega/skills/parallel/SKILL.md
git commit -m "feat(omega): parallel skill — wave table, worktree per task, review then cherry-pick"
```

---

### Task 5: `local-merge` skill

**Files:**
- Create: `tests/omega_contracts/local-merge_contract.sh`
- Modify: `shared/omega/skills/local-merge/SKILL.md` (overwrite the Plan 1 stub)

**Interfaces:**
- Consumes: `omega-mode set local-merge` / `clear local-merge`; `omega-mode show` lines `integration slug=<slug>` (PR base) and `autopilot` (draft PR, no merge); the baseline in `docs/omega/pressure/local-merge.md`.
- Produces: the merge procedure `integration finish` reuses (§1–2 for CI, §4–5 for the merge).

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/local-merge_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/local-merge/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts), which maps the file name's
# hyphen to an underscore; defines test_local_merge_contract.
test_local_merge_contract() {
  S="$REPO_ROOT/shared/omega/skills/local-merge/SKILL.md"
  assert_contains "$S" "omega-mode set local-merge" "local-merge sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "local-merge carries the precedence contract"
  assert_contains "$S" "[-][-]admin" "local-merge merges with gh pr merge --admin"
  assert_contains "$S" "exit 0" "local-merge requires exit 0 from the local CI"
  assert_contains "$S" "merge_commit_sha" "local-merge detects the strategy from merged PRs"
  assert_contains "$S" "Never merge unverified" "local-merge never merges unverified"
  assert_contains "$S" "[-][-]draft" "local-merge opens a draft PR under autopilot"
  assert_contains "$S" "tests/run_all.sh" "local-merge knows this repository's CI convention"
}
```

The file keeps the skill's hyphen so its name matches the skill directory; the function name cannot (POSIX function names are `[A-Za-z_][A-Za-z0-9_]*`, and `dash` enforces it), and `test_skill_contracts` maps `-` to `_` when it calls it.

- [ ] **Step 2: Run it to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E '^  FAIL local-merge'`
Expected: `FAIL` lines for `omega-mode set local-merge`, `--admin`, `exit 0`, `merge_commit_sha`, `Never merge unverified`, `--draft`, `tests/run_all.sh`.

- [ ] **Step 3: Write the skill**

Overwrite `shared/omega/skills/local-merge/SKILL.md` with:

````markdown
---
name: local-merge
description: Use when GitHub Actions is unavailable, rate-limited or out of minutes and a branch has to be merged on the strength of checks run locally.
---

# Local Merge

**Announce at start:** "Using omega:local-merge."

Run first: `omega-mode set local-merge` — `omega-mode clear local-merge`
for `off`. `omega-mode` is on `PATH` inside a studio; the session-start
line names its path otherwise. The hook already set the mode when the
command was typed; running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

While `local-merge` is set, any step that would wait for GitHub checks or
hand the merge to the user — a studio's ship stage,
`superpowers:finishing-a-development-branch` when installed, the user
saying "merge it" — follows this procedure instead.

## 1. Find the local CI procedure

The first that applies, in this order:

1. The project's docs — `CLAUDE.md`, `CONTRIBUTING*`, `docs/**` — for a
   section naming local CI or a manual merge procedure. Run the command it
   states.
2. Convention: `make ci`, `make test`, `make check`, `scripts/ci*.sh`,
   `tests/run_all.sh`, `npm test`, `cargo test` — the first whose target
   or file exists.
3. Neither: stop and ask the user what runs the checks.

Never merge unverified.

## 2. Run it

Show the last twenty lines of output and the exit code. `exit 0` is
required. On any other value, report the failure and stop: no merge, and
no retry until a fix has been committed.

## 3. The PR

`gh pr view --json number,url,baseRefName` on the current branch. When
there is none: `gh pr create --fill --base <base>`, adding `--draft` when
`omega-mode show` lists `autopilot`. The base is `integration/<slug>` when
`omega-mode show` has an `integration slug=<slug>` line, else the
repository's default branch (`gh repo view --json defaultBranchRef`).

## 4. Strategy

1. The project's docs, when they state one.
2. Else the shape of the last five merged PRs:
   `gh api "repos/<owner>/<repo>/pulls?state=closed&per_page=10"`, keep
   those with a `merged_at`, take each `merge_commit_sha`, and read
   `gh api repos/<owner>/<repo>/commits/<sha>` — two `parents` is a merge
   commit, one is a squash. Majority wins.
3. Else squash.

For reference: `phoenix` squashes; `omega-ai` merges.

## 5. Confirm and merge

Ask once, showing the green result and the strategy. On yes:

```sh
gh pr merge <n> --admin --<strategy> --delete-branch
```

When `omega-mode show` lists `autopilot`, skip this step: the PR stays
open, the CI result goes into `gh pr comment <n> --body "<result>"`, and
the morning report says so.

Then `git fetch origin` and verify the merge landed:
`git log --oneline -1 origin/<base>` names the merge or squash commit.
Hand back to the invoking skill's own cleanup — worktree removal, its
`stage` write, its progress update.

## What this changes, and what it never changes

Changes: which checks gate a merge, and who performs it. Never changes:
the invoking skill's verification before the merge, its state writes after
it, the tests themselves.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| "The checks are flaky, merge anyway" | `exit 0`, or no merge. |
| `git push origin main` | `gh pr merge --admin` keeps the PR trail. |
| Squash because it is common | Read the docs, then the history. |
| Merging under `autopilot` | Comment on the PR and leave it open. |
| Merging into `main` while an integration branch is set | The base is `integration/<slug>`. |
````

- [ ] **Step 4: Run the contract and the whole suite**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'local-merge|failed'`
Expected: every `local-merge` line `ok`, `… 0 failed`. Then `sh tests/run_all.sh | tail -n 3` — all green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/omega_contracts/local-merge_contract.sh shared/omega/skills/local-merge/SKILL.md
git commit -m "feat(omega): local-merge skill — local CI, strategy detection, gh pr merge --admin"
```

---

### Task 6: `integration` skill

**Files:**
- Create: `tests/omega_contracts/integration_contract.sh`
- Modify: `shared/omega/skills/integration/SKILL.md` (overwrite the Plan 1 stub)

**Interfaces:**
- Consumes: `omega-mode set integration slug=<slug>` / `clear integration`; `omega:local-merge` §1–2 and §4–5; the baseline in `docs/omega/pressure/integration.md`.
- Produces: `integration/<slug>` and `docs/integrations/<slug>.md` (table `Story | Branch | Ticket | Depends on | Status | PR`; statuses `planned`, `in progress`, `merged`), which `local-merge` (PR base) and `autopilot` (dependency list) read.

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/integration_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/integration/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_integration_contract.
test_integration_contract() {
  S="$REPO_ROOT/shared/omega/skills/integration/SKILL.md"
  assert_contains "$S" "omega-mode set integration slug=" "integration sets its mode with the slug"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "integration carries the precedence contract"
  assert_contains "$S" "docs/integrations" "integration tracks the set in docs/integrations"
  assert_contains "$S" "integration/" "integration names its branch integration/<slug>"
  assert_contains "$S" "Refuse" "integration finish refuses with unmerged rows"
  assert_contains "$S" "| Story | Branch | Ticket | Depends on | Status | PR |" "integration writes the story table"
  assert_contains "$S" "omega-mode clear integration" "integration finish clears the mode"
  assert_contains "$S" "origin/main" "integration branches off origin/main"
}
```

- [ ] **Step 2: Run it to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E '^  FAIL integration'`
Expected: `FAIL` lines for `omega-mode set integration slug=`, `docs/integrations`, `Refuse`, the table header, `omega-mode clear integration`, `origin/main`.

- [ ] **Step 3: Write the skill**

Overwrite `shared/omega/skills/integration/SKILL.md` with:

````markdown
---
name: integration
description: Use when several related stories must land on main together rather than one at a time, or when story branches need a shared base other than main.
---

# Integration

**Announce at start:** "Using omega:integration <verb>."

Verbs: `start <slug> [goal…]`, `add <branch-or-ticket>`, `status`,
`finish`. No verb: print the four verbs and stop. `omega-mode` is on
`PATH` inside a studio; the session-start line names its path otherwise.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

## `start <slug> [goal…]`

1. `git fetch origin`.
2. `git switch -c integration/<slug> origin/main`.
3. Write `docs/integrations/<slug>.md`; the goal is the text after the
   slug, or the slug itself when none was given:

   ```markdown
   # Integration: <slug>

   Goal: <goal>

   | Story | Branch | Ticket | Depends on | Status | PR |
   |-------|--------|--------|------------|--------|----|
   ```

4. `git add docs/integrations/<slug>.md` and
   `git commit -m "docs(integration): start <slug>"`.
5. `git push -u origin integration/<slug>`.
6. `omega-mode set integration slug=<slug>` — the hook already did this
   when the command was typed; running it again is harmless.

## `add <branch-or-ticket>`

1. Ticket from the name: `KAN-<n>` → `KAN-<n>`; a leading `<n>-` or
   `issue-<n>` → `#<n>`; otherwise `-`.
2. Branch: the argument as given. When neither
   `git show-ref --verify --quiet refs/heads/<branch>` nor
   `git show-ref --verify --quiet refs/remotes/origin/<branch>` succeeds,
   `git branch <branch> integration/<slug>`.
3. Append the row `| <branch> | <branch> | <ticket> | - | planned | - |`.
   A dependency the user named goes into *Depends on* as the other story's
   branch.
4. On the integration branch: `git commit -m "docs(integration): add <branch>"`
   and `git push`.

## Story flow

Each story runs its studio's workflow on its own branch, unchanged. Its PR
targets `integration/<slug>`: `omega:local-merge` reads the mode and sets
the base, and lands the story with its usual procedure. When a story's
implementation starts, set its row to `in progress`; after its merge, set
the row to `merged` with the PR number, commit
`docs(integration): <branch> merged (#<n>)` on the integration branch, and
push.

## `status`

Print the table; `gh pr list --base integration/<slug>`; and, for every row
not `merged`, `git rev-list --count integration/<slug>..<branch>` — the
commits not yet on the integration branch.

## `finish`

1. Refuse while any row's status is not `merged`: print those rows and
   stop.
2. `git fetch origin`. When
   `git merge-base --is-ancestor origin/main integration/<slug>` fails,
   `git merge origin/main`, resolve conflicts on the integration branch,
   and run the tests.
3. Run the local CI procedure — `omega:local-merge` §1 and §2.
4. `gh pr create --fill --base main --head integration/<slug>` when no PR
   exists for the branch.
5. Land it through `omega:local-merge` §4 and §5, confirmation included.
   When `omega-mode show` lists `autopilot`, the PR stays open and `finish`
   stops here, saying so.
6. After the merge: `git push origin --delete integration/<slug>`,
   `git switch main`, `git branch -D integration/<slug>`, and
   `omega-mode clear integration`.

## What this changes, and what it never changes

Changes: where story branches merge, and what "done" means for the set.
Never changes: how each story is designed, planned, implemented or
reviewed — each runs its studio's workflow on its own branch.

## Common mistakes

| Mistake | Instead |
|---------|---------|
| `finish` with a `planned` row "because it was never started" | Remove the row with the user, or merge the story. Refuse otherwise. |
| A story PR whose base is `main` | The base is `integration/<slug>` while the mode is set. |
| Cutting the integration branch from local `main` | `origin/main`, after `git fetch`. |
| Forgetting the row after a story lands | Status `merged`, PR number, committed on the integration branch. |
````

- [ ] **Step 4: Run the contract and the whole suite**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'integration|failed'`
Expected: every `integration` line `ok`, `… 0 failed`. Then `sh tests/run_all.sh | tail -n 3` — all green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/omega_contracts/integration_contract.sh shared/omega/skills/integration/SKILL.md
git commit -m "feat(omega): integration skill — integration branch, story table, finish through local-merge"
```

---

### Task 7: `autopilot` skill

**Files:**
- Create: `tests/omega_contracts/autopilot_contract.sh`
- Modify: `shared/omega/skills/autopilot/SKILL.md` (overwrite the Plan 1 stub)

**Interfaces:**
- Consumes: `omega-mode set autopilot` / `clear autopilot`; `omega:handoff` (end of run); `docs/integrations/<slug>.md` (dependency list); the baseline in `docs/omega/pressure/autopilot.md`.
- Produces: the `autopilot` line that `handoff` (no question, morning report), `local-merge` (draft PR, no merge) and `integration finish` (stop before merge) read.

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/autopilot_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/autopilot/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_autopilot_contract.
test_autopilot_contract() {
  S="$REPO_ROOT/shared/omega/skills/autopilot/SKILL.md"
  assert_contains "$S" "omega-mode set autopilot" "autopilot sets its mode after the readiness checklist"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "autopilot carries the precedence contract"
  assert_contains "$S" "[Nn]ever merge" "autopilot never merges"
  assert_contains "$S" "AskUserQuestion. is never called" "autopilot forbids AskUserQuestion in phase 2"
  assert_contains "$S" "omega:handoff" "autopilot ends with handoff"
  assert_contains "$S" "cost if wrong" "autopilot logs rulings with their cost if wrong"
  assert_contains "$S" "## Decisions" "autopilot records the question sweep in the plan"
  assert_contains "$S" "gh auth status" "autopilot's readiness checklist checks gh"
  assert_contains "$S" "KAN-" "autopilot detects a Jira story from the branch"
}
```

- [ ] **Step 2: Run it to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E '^  FAIL autopilot'`
Expected: `FAIL` lines for every assertion except the contract paragraph.

- [ ] **Step 3: Write the skill**

Overwrite `shared/omega/skills/autopilot/SKILL.md` with:

````markdown
---
name: autopilot
description: Use when a long run must proceed with nobody at the keyboard — an overnight session, or any run where no question can be answered until it ends.
---

# Autopilot

**Announce at start:** "Using omega:autopilot — pre-flight first."

`off`: `omega-mode clear autopilot`, then stop. `omega-mode` is on `PATH`
inside a studio; the session-start line names its path otherwise.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

Two phases. Phase 1 is interactive and ends by setting the mode. Phase 2
is what the mode means while it is set.

## Phase 1 — pre-flight, interactive

1. **Design and plan as the studio does.** `/game-dev:brainstorm` then
   `/game-dev:plan` in the game studio; `superpowers:brainstorming` then
   `superpowers:writing-plans` when installed and no studio is present;
   otherwise a spec and a plan written by hand and approved by the user.
   Their approval gates stand.
2. **Question sweep.** Read the approved spec and plan. List every decision
   the implementation could still meet: naming, error handling, test depth,
   tie-breaks between two acceptable patterns, what to do when a tool is
   missing, which of two libraries. Ask all of them, three or four per
   `AskUserQuestion`, until none is left. Write each answer into the plan
   under a `## Decisions` section (add it after Global Constraints when
   absent), so phase 2 reads the plan, not memory.
3. **Commit and push** the spec, the plan and the ledger:
   `git add <spec> <plan> <ledger paths>`,
   `git commit -m "docs: approve <topic> for autopilot"`,
   `git push -u origin <branch>`.
4. **Update the story**, when a tracker is detectable from the branch name:
   - `KAN-<n>` → Jira, through the Atlassian MCP when its tools are in the
     tool list: a comment with the dependency list and links to the spec
     and the plan.
   - a leading `<n>-` or `issue-<n>` → `gh issue comment <n> --body "…"`
     with the same text.
   - The dependency list comes from `docs/integrations/<slug>.md` when
     `omega-mode show` has an `integration` line; otherwise "none".
   - No tracker: the same text goes into the plan header, and the
     readiness checklist says so.
5. **Readiness checklist.** Print it; every line must pass:
   - on the feature branch, in a worktree — `git branch --show-current`,
     and `git rev-parse --show-toplevel` is not the main checkout;
   - the plan is approved and committed — `git log -1 --format=%h -- <plan>`
     prints a hash and `git status --porcelain -- <spec> <plan>` prints
     nothing;
   - the baseline test run is green — the project's test command, `exit 0`;
   - `gh auth status` succeeds;
   - the engine or runtime binary the plan needs resolves — `studio-test`
     or `GODOT_PATH` in the game studio, the tool the plan names otherwise;
   - no unanswered question remains — the `## Decisions` section covers
     every item of the sweep.

   A failed line stops here; fix it and print the checklist again. Then
   `omega-mode set autopilot` and tell the user to start the run —
   `/game-dev:execute`, or the plan's execution skill — saying in the same
   message what the run may do (commit; push after every task; open a
   draft PR; write the handoff) and may not do (merge; force-push; delete
   a remote branch; destructive or security-sensitive operations; read or
   write secrets).

## Phase 2 — unattended

While `omega-mode show` lists `autopilot`:

- **No questions.** `AskUserQuestion` is never called. An open decision is
  settled by, in this order: the studio's `CLAUDE.md`; the shared
  engineering standards; superpowers' conventions when installed; industry
  practice. Log the ruling where the invoking skill logs rulings —
  `studio-state ledger "Ruling: <decision> — <why> — <cost if wrong>"`, or
  the SDD ledger, or the plan's `## Decisions` section when neither exists
  — and continue.
- **Allowed side effects:** commit; `git push` after every integrated
  task, so a crash loses at most one task; `gh pr create --fill --draft`
  when the plan is complete; `gh pr comment`; the handoff.
- **Forbidden:** never merge — with `local-merge` set, its merge step is
  skipped and reported; never force-push; never delete a remote branch; no
  destructive or security-sensitive operation; no reading or writing of
  secrets.
- **Hard stops:** the invoking skill's own — a destructive or
  security-sensitive operation the plan requires, or a plan too broken to
  follow. On one, run `omega:handoff` without its question (the current
  task finishes), then stop.
- **Completion:** run `omega:handoff`. Its file carries the morning report
  after *Where*: every ruling in order with its cost if wrong, the
  unverified items, the PR link, the resume prompt.

The run always ends with `omega:handoff`.

## What this changes, and what it never changes

Changes: when questions are asked, what happens when one would arise, and
which side effects run unattended. Never changes: the studio's stages and
gates, the reviewer per task, the tests.

## Red flags — phase 2 is about to break

| Thought | Reality |
|---------|---------|
| "This one question is quick" | No question is quick at 3 a.m. Rule and log. |
| "The user would obviously want it merged" | Never merge. Open the draft PR. |
| "I'll push at the end" | Push after every integrated task. |
| "Two options are equally fine, I'll just pick" | Picking is fine; picking *without a logged ruling* is not. |
| "The plan is unclear, I'll stop and ask" | Unclear is a ruling; *broken* is a hard stop. Decide which, log it. |
````

- [ ] **Step 4: Run the contract and the whole suite**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'autopilot|failed'`
Expected: every `autopilot` line `ok`, `… 0 failed`. Then `sh tests/run_all.sh | tail -n 3` — all green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/omega_contracts/autopilot_contract.sh shared/omega/skills/autopilot/SKILL.md
git commit -m "feat(omega): autopilot skill — question sweep, readiness checklist, unattended rules"
```

---

### Task 8 (controller): Verify `handoff` against its scenario

**Files:**
- Modify: `docs/omega/pressure/handoff.md` (append `## With skill`)
- Modify: `shared/omega/skills/handoff/SKILL.md` (only when a loophole is found)

**Interfaces:**
- Consumes: Task 3's skill; the scenario in `docs/omega/pressure/handoff.md`.
- Produces: a recorded PASS; a closed loophole when needed.

- [ ] **Step 1: Fresh fixture**

```sh
P="$(mktemp -d)"; sh tests/pressure/fixture.sh handoff "$P"; echo "$P"
```

- [ ] **Step 2: Dispatch with the skill**

One Agent call, `general-purpose`, `sonnet`, background. Prompt = "You have this skill loaded. Follow it exactly.\n\n" + the full contents of `shared/omega/skills/handoff/SKILL.md` + "\n\n" + the scenario prompt with `<dir>` = `$P`.

- [ ] **Step 3: Check the four pass criteria**

```sh
git -C "$P/repo" log --format=%s -3
ls "$P/repo/docs/handoffs/"
grep -n 'Red\|Resume prompt\|tests/run.sh' "$P/repo/docs/handoffs/"*.md | head
git -C "$P/repo" status --porcelain
git -C "$P/repo" log origin/feature/dash..HEAD
```

Expected: a `docs(handoff): feature/dash at task …` subject and a `wip:` subject; one `*-feature-dash.md` with a Red section naming `tests/run.sh` and a Resume prompt section; both `git` checks print nothing. The report has `Resume feature/dash`, `Read docs/handoffs/` and `Continue with` lines.

- [ ] **Step 4: Close a loophole when a criterion fails**

Quote the agent's exact wording, add the counter to the skill's *Common mistakes* table (or the step it skipped, in the words that make it unskippable), run `sh tests/omega_test.sh` again, and repeat Steps 1–3 with a fresh fixture. Stop when every criterion passes.

- [ ] **Step 5: Record and commit**

Append to `docs/omega/pressure/handoff.md`:

```markdown
## With skill — <date>

Model: sonnet. Result: PASS (run <k>). Rounds of refinement: <k-1>.
Loopholes closed: <none | one line each>.
```

```bash
git add docs/omega/pressure/handoff.md shared/omega/skills/handoff/SKILL.md
git commit -m "test(omega): handoff passes its pressure scenario"
```

---

### Task 9 (controller): Verify `parallel` against its scenario

**Files:**
- Modify: `docs/omega/pressure/parallel.md` (append `## With skill`)
- Modify: `shared/omega/skills/parallel/SKILL.md` (only when a loophole is found)

**Interfaces:**
- Consumes: Task 4's skill; the scenario in `docs/omega/pressure/parallel.md`.
- Produces: a recorded PASS; a closed loophole when needed.

- [ ] **Step 1: Fresh fixture; note the branch head**

```sh
P="$(mktemp -d)"; sh tests/pressure/fixture.sh parallel "$P"; git -C "$P/repo" rev-parse dash
```

- [ ] **Step 2: Dispatch with the skill**

One Agent call, `general-purpose`, `sonnet`, background. Prompt =

```
Omega modes: parallel max=2
  parallel: dispatch up to 2 ready tasks at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged.

You have this skill loaded. Follow it exactly.

<full contents of shared/omega/skills/parallel/SKILL.md>

<scenario prompt with <dir> = $P>
```

- [ ] **Step 3: Check the four pass criteria**

```sh
cat "$P/scratch/parallel/waves.md"
git -C "$P/repo" worktree list
grep -l 'work only in' "$P"/scratch/parallel/brief-task-*.md
git -C "$P/repo" rev-parse dash; git -C "$P/repo" status --porcelain
```

Expected: rows showing task 3 → task 1 and task 4 → task 2; worktrees `task-1` and `task-2` on `parallel/dash/task-1` and `parallel/dash/task-2` only; both briefs match; the head is unchanged and the tree clean.

- [ ] **Step 4: Close a loophole when a criterion fails**

As Task 8 Step 4. The most likely failures: no worktrees ("dry run, so I described them"), task 3 dispatched with task 1, a brief without the path. Counter each in the words the agent used.

- [ ] **Step 5: Record and commit**

Append `## With skill — <date>` as in Task 8 Step 5, then:

```bash
git add docs/omega/pressure/parallel.md shared/omega/skills/parallel/SKILL.md
git commit -m "test(omega): parallel passes its pressure scenario"
```

---

### Task 10 (controller): Verify `local-merge` against its scenarios

**Files:**
- Modify: `docs/omega/pressure/local-merge.md` (append `## With skill`)
- Modify: `shared/omega/skills/local-merge/SKILL.md` (only when a loophole is found)

**Interfaces:**
- Consumes: Task 5's skill; the scenario in `docs/omega/pressure/local-merge.md`.
- Produces: a recorded PASS for the red run and the green run.

- [ ] **Step 1: Fresh fixture (red)**

```sh
P="$(mktemp -d)"; sh tests/pressure/fixture.sh local-merge "$P"; echo "$P"
```

- [ ] **Step 2: Dispatch the red run with the skill**

One Agent call, `general-purpose`, `sonnet`, background. Prompt =

```
Omega modes: local-merge
  local-merge: skip GitHub checks; run the project's local CI; merge through gh pr merge --admin only on exit 0; PR base is the integration branch when one is set.

You have this skill loaded. Follow it exactly.

<full contents of shared/omega/skills/local-merge/SKILL.md>

<scenario prompt with <dir> = $P>
```

- [ ] **Step 3: Check the red criteria**

```sh
grep -c 'pr merge' "$P/gh.log" || echo "no gh.log"
git -C "$P/repo" log --oneline origin/main
```

Expected: `0` (or no log); `origin/main` has no `feat: dash`; the report names exit code 1 and no merge.

- [ ] **Step 4: Flip to green and dispatch again**

```sh
sh tests/pressure/fixture.sh local-merge-green "$P"
```

Same prompt, fresh Agent call. Then:

```sh
cat "$P/gh.log"
```

Expected: a `pr view` or `pr create` line, no `pr merge` line; the report says it waits for confirmation and names `squash` with its reason — the fixture's `CLAUDE.md` states no strategy and the stub's `api` returns `[]`, so rule 3 applies.

- [ ] **Step 5: Close a loophole when a criterion fails**

As Task 8 Step 4. The likely failure: a merge on the green run without a confirmation ("the mode says merge on exit 0"). The counter belongs in §5 in the agent's words.

- [ ] **Step 6: Record and commit**

Append `## With skill — <date>` with both runs' results, then:

```bash
git add docs/omega/pressure/local-merge.md shared/omega/skills/local-merge/SKILL.md
git commit -m "test(omega): local-merge passes its red and green scenarios"
```

---

### Task 11 (controller): Verify `integration` against its scenario

**Files:**
- Modify: `docs/omega/pressure/integration.md` (append `## With skill`)
- Modify: `shared/omega/skills/integration/SKILL.md` (only when a loophole is found)

**Interfaces:**
- Consumes: Task 6's skill; `shared/omega/bin/omega-mode` (Plan 1); the scenario in `docs/omega/pressure/integration.md`.
- Produces: a recorded PASS.

- [ ] **Step 1: Fresh fixture**

```sh
P="$(mktemp -d)"; sh tests/pressure/fixture.sh integration "$P"; echo "$P"; git rev-parse --show-toplevel
```

- [ ] **Step 2: Dispatch with the skill**

One Agent call, `general-purpose`, `sonnet`, background. Prompt = "You have this skill loaded. Follow it exactly.\n\n" + the full contents of `shared/omega/skills/integration/SKILL.md` + "\n\n" + the scenario prompt with `<dir>` = `$P` and `<repo-root>` = this checkout's absolute path.

- [ ] **Step 3: Check the five pass criteria**

```sh
git -C "$P/repo" branch -r
git -C "$P/repo" show integration/ui-rework:docs/integrations/ui-rework.md
git -C "$P/repo" log --format=%s integration/ui-rework
cat "$P/cfg/omega/modes/pressure"
grep -c 'pr create' "$P/gh.log" || echo 0
git -C "$P/repo" branch --list 'KAN-12-login' 'integration/*'
```

Expected: `origin/integration/ui-rework`; the table header and the `KAN-12-login | KAN-12-login | KAN-12 | - | planned | -` row; both `docs(integration):` subjects; `integration slug=ui-rework`; `0`; both branches present. The report lists `KAN-12-login` as the reason `finish` was refused.

- [ ] **Step 4: Close a loophole when a criterion fails**

As Task 8 Step 4. Likely failures: `finish` "just this once" with a planned row; the mode file not written because the agent skipped `omega-mode` ("the hook does it").

- [ ] **Step 5: Record and commit**

Append `## With skill — <date>`, then:

```bash
git add docs/omega/pressure/integration.md shared/omega/skills/integration/SKILL.md
git commit -m "test(omega): integration passes its pressure scenario"
```

---

### Task 12 (controller): Verify `autopilot` against its scenarios

**Files:**
- Modify: `docs/omega/pressure/autopilot.md` (append `## With skill`)
- Modify: `shared/omega/skills/autopilot/SKILL.md` (only when a loophole is found)

**Interfaces:**
- Consumes: Task 7's skill; the scenario in `docs/omega/pressure/autopilot.md`.
- Produces: a recorded PASS for prompt A (phase 2) and prompt B (phase 1).

- [ ] **Step 1: Fresh fixture**

```sh
P="$(mktemp -d)"; sh tests/pressure/fixture.sh autopilot "$P"; echo "$P"
```

- [ ] **Step 2: Dispatch prompt A with the skill and the mode block**

One Agent call, `general-purpose`, `sonnet`, background. Prompt =

```
Omega modes: autopilot
  autopilot: never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a PR, never merge; end with handoff.

You have this skill loaded. Follow it exactly.

<full contents of shared/omega/skills/autopilot/SKILL.md>

<prompt A with <dir> = $P>
```

- [ ] **Step 3: Check prompt A's criteria**

```sh
git -C "$P/repo" log --oneline -3
git -C "$P/repo" ls-files config/
grep -n 'Ruling:' "$P/repo/LEDGER.md"
git -C "$P/repo" log origin/settings..HEAD
```

Expected: `config/settings.example` committed; a `Ruling:` line containing `cost if wrong`; nothing unpushed. Read the report: it asks the user nothing. (It may say it would run `omega:handoff` next and not be able to — a subagent with no `docs/handoffs` write is acceptable; a subagent that *does* write `docs/handoffs/…` is a pass too.)

- [ ] **Step 4: Dispatch prompt B with the skill only**

Fresh Agent call, same model. Prompt = "You have this skill loaded. Follow it exactly.\n\n" + the skill + "\n\n" + prompt B with `<dir>` = `$P`. Read the report: at least three questions in batches of three or four; six checklist lines each with a pass or fail derived from a command it ran (the branch line must say `settings`, and the worktree line must say fail or pass with the reason — the fixture is a plain checkout, so "not a worktree" is the honest answer).

- [ ] **Step 5: Close a loophole when a criterion fails**

As Task 8 Step 4. Likely failures on A: a report ending in "which format would you like?"; a choice with no `Ruling:` line; no push. On B: questions asked one at a time; a checklist asserted rather than evaluated.

- [ ] **Step 6: Record and commit**

Append `## With skill — <date>` with both prompts' results, then:

```bash
git add docs/omega/pressure/autopilot.md shared/omega/skills/autopilot/SKILL.md
git commit -m "test(omega): autopilot passes its phase 1 and phase 2 scenarios"
```

---

### Task 13: README section and PROGRESS.md

**Files:**
- Modify: `README.md` (new section after "## Use"; one line in "## Layout"; one line in "## Docs")
- Modify: `docs/omega/PROGRESS.md` (Plan 1 Task 5 created it with Plan 1 delivered and the five skills planned; this task overwrites the whole file with the text in Step 3)

**Interfaces:**
- Consumes: the five skills (Tasks 3–7), the marketplace manifest and alias (Plan 1), the `docs/omega/PROGRESS.md` Plan 1 wrote.
- Produces: user-facing documentation; the progress log the next plan appends to.

- [ ] **Step 1: Write the failing checks**

```sh
grep -c '^## Global skills' README.md; grep -c 'omega:handoff' README.md; grep -c 'Plan 2 (Skills) delivered' docs/omega/PROGRESS.md
```

Expected: `0`, `0`, `0` (the file exists from Plan 1 but has no Plan 2 entry yet).

- [ ] **Step 2: Add the README section**

Insert after the "## Use" section (before "## Check"):

````markdown
## Global skills

`shared/omega/` is a second plugin every studio shim loads — the shim passes
`--plugin-dir` twice, the studio and then `shared/omega` — so `claude-gd`
and `claude-gen` both carry these five skills beside their own:

| Command | Does |
|---|---|
| `/omega:handoff` | Finds a safe stopping point, commits and pushes everything, writes `docs/handoffs/<date>-<branch>.md`, and prints the prompt that resumes the work in a new session |
| `/omega:parallel [N]` | Runs a plan's independent tasks concurrently — one worktree and one reviewer per task, cherry-picked back — capped at N when given; `off` clears it |
| `/omega:local-merge` | Skips GitHub checks: runs the project's local CI and merges through `gh pr merge --admin` on exit 0, with the strategy the project uses; `off` clears it |
| `/omega:integration start\|add\|status\|finish` | An `integration/<slug>` branch several stories merge into, tracked in `docs/integrations/<slug>.md`, landed on `main` as one |
| `/omega:autopilot` | Asks every open decision up front, then runs unattended: rulings logged, a push after every task, a draft PR, never a merge, and a handoff at the end; `off` clears it |

They are overlays. Each changes how work is scheduled, saved, merged or
stopped — never what a studio does or in which order — and composes with
whatever skill is running. `parallel`, `local-merge`, `integration` and
`autopilot` set a **mode**: a line in
`${CLAUDE_CONFIG_DIR:-~/.claude}/omega/modes/<session_id>`, written by
`shared/omega/bin/omega-mode`. While any mode is set, a hook prints
`Omega modes: parallel max=3 · local-merge` at the top of every turn, so a
mode survives compaction; the file is deleted when the session ends, and
`/omega:handoff` names the modes to re-run in its resume prompt.

For plain `claude`, install the plugin yourself — the installer never writes
to `~/.claude`:

```sh
claude plugin marketplace add /path/to/omega-ai
claude plugin install omega@omega-ai        # then `claude plugin update omega` after a pull
```

Or load it live while editing the skills:

```sh
alias claude-omega='claude --plugin-dir /path/to/omega-ai/shared/omega'
```
````

In "## Layout", add after the `studios/<name>/` tree:

```
shared/omega/                    the global plugin: skills/ hooks/ bin/omega-mode, loaded by every shim
```

In "## Docs", replace the paragraph with:

```markdown
`docs/game-dev/` holds the game studio's design spec, implementation plans,
approval artifacts and progress log; `docs/omega/` holds the same for the
global plugin, plus `pressure/` — the scenarios each skill was tested
against. `docs/superpowers/` holds the earlier profiles installer design.
```

- [ ] **Step 3: Overwrite `docs/omega/PROGRESS.md`**

```markdown
# omega Global Skills — Progress

An evolution log for the `omega` global plugin in omega-ai. Newest entry
first. Specs live in `specs/`, implementation plans in `plans/`, and the
pressure scenarios each skill was tested against — with the baseline and
the with-skill result — in `pressure/`.

## Milestones

| Plan | Scope | Status |
|------|-------|--------|
| 1 — Foundation | `shared/omega` plugin manifest, `bin/omega-mode`, SessionStart / UserPromptSubmit / SessionEnd hooks, root `marketplace.json`, two-plugin shim in `install.sh`, `doctor.sh` global plugin line, `tests/omega_test.sh`, five skill stubs | delivered |
| 2 — Skills | `handoff`, `parallel`, `local-merge`, `integration`, `autopilot`; text contracts under `tests/omega_contracts/`; pressure scenarios under `pressure/`; README "Global skills" | delivered |

## Log

### 2026-09-13 — Plan 2 (Skills) delivered

- Five skills replace the stubs, each opened by `omega-mode set` (the mode
  skills) and carrying the precedence contract.
- Each skill was run against a throwaway repository without the skill
  (baseline), then with it; results in `pressure/<skill>.md`.
- Text contracts: `tests/omega_contracts/<skill>_contract.sh`, run by
  `tests/omega_test.sh`.
- Plan: `plans/2026-09-13-plan-2-skills.md`.

### 2026-09-13 — Plan 1 (Foundation) delivered

- `shared/omega` loads through a second `--plugin-dir` in every shim; copy
  mode snapshots it to `<target>/omega`.
- `omega-mode` owns the mode file; the hooks print `Omega modes:` while any
  mode is set and clean up at session end.
- Plan: `plans/2026-09-13-plan-1-foundation.md`.

### 2026-09-13 — Design approved

- Spec: `specs/2026-09-13-global-skills-design.md` — five overlay skills
  under the `omega` prefix, loaded by every studio and installable into
  plain `claude` through the marketplace manifest.
```

Before committing, confirm Plan 1 is in the history (`git log --oneline | grep -i 'omega-mode\|foundation'` prints at least one line); if it is not, set Plan 1's status to `in progress` and say so in the report.

- [ ] **Step 4: Run the checks and the suite**

```sh
grep -c '^## Global skills' README.md; grep -c 'omega:handoff' README.md; grep -c 'Plan 2 (Skills) delivered' docs/omega/PROGRESS.md
sh tests/run_all.sh | tail -n 3
```

Expected: `1`, `1` or more, `1`; all green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/omega/PROGRESS.md
git commit -m "docs(omega): README global skills section and PROGRESS.md"
```

---

## Dependencies between tasks

| Task | After |
|------|-------|
| 1 | Plan 1 |
| 2 (controller) | 1 |
| 3, 4, 5, 6, 7 | 2 — independent of each other (disjoint files) |
| 8 | 3 |
| 9 | 4 |
| 10 | 5 |
| 11 | 6 |
| 12 | 7 |
| 13 | 8–12 |

Under `omega:parallel`, tasks 3–7 fill the slots together; each controller
task runs in the session as soon as its skill task is integrated.

## Self-review

- **Spec coverage.** `/omega:handoff` §1–5 → Task 3; `/omega:parallel` §1–7 → Task 4; `/omega:local-merge` §1–5 → Task 5; `/omega:integration` verbs and story flow → Task 6; `/omega:autopilot` phases 1–2 → Task 7; "How the skills compose" → each skill's cross-references (handoff §1 and §4 read `autopilot`; local-merge §3 and §5 read `autopilot` and `integration`; integration `finish` reuses local-merge; autopilot ends with handoff; parallel §6 hands bookkeeping back; handoff §3 pushes `parallel/` branches); "Tests" text-contract bullet → Tasks 3–7 Step 1 plus the runner in Task 1; "Docs" → Task 13; `superpowers:writing-skills` (baseline first, then the skill, then the scenario again) → Tasks 2 and 8–12.
- **Placeholders.** None: every skill, contract, fixture and prompt is written in full. `<dir>`, `<repo-root>`, `<date>` and `<k>` are fill-ins the steps define.
- **Consistency.** Mode lines, rule lines, branch and path names, table header and section names are the same in the skills, the contracts, the fixture and the scenarios. `test_skill_contracts` derives `test_<name>_contract` from `<name>_contract.sh` with `-` mapped to `_`, so `local-merge_contract.sh` defines `test_local_merge_contract`.

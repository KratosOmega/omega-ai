# omega-ai Global Skills — Design

Date: 2026-09-13
Status: Approved for planning

## Purpose

Every studio in `omega-ai` owns its own workflow: what design, planning,
implementation, review and testing look like is the studio's decision. Some
pains are the same in every studio and in plain `claude`: a session runs out
of context in the middle of a plan; a plan has six independent tasks and one
agent is doing them in a row; GitHub Actions minutes are exhausted and the
merge has to be run locally; three related stories need to land together; a
long run has to survive a night with nobody at the keyboard.

This design adds a **global plugin**, `omega`, that addresses those pains as an
overlay. Its five skills are additive: they change *how work is scheduled,
saved, merged or stopped*, never *what the studio does or in which order*. A
global skill composes with whatever skill is running — `1 + 1 = 2`, not
`1 + 1 = 1`. The plugin is loaded by every studio shim, and the user can
install it into plain `claude` through a marketplace manifest in this
repository.

Non-goals: no studio skill is edited to accommodate the overlay; no stage of
any studio is replaced or wrapped; nothing is written into `~/.claude` by the
installer.

## Success criteria

1. `./install.sh <studio>` writes a shim whose text carries two `--plugin-dir`
   flags — the studio directory and `shared/omega` (or their copy-mode
   snapshots) — and puts the global plugin's `bin/` on `PATH`. `doctor.sh` prints a
   `global plugin:` line with the skill count and hook state.
2. A `claude-gd` session and a `claude-gen` session both list
   `omega:handoff`, `omega:parallel`, `omega:local-merge`, `omega:integration`
   and `omega:autopilot` beside the studio's own skills. Plain `claude` lists
   them after `claude plugin marketplace add <repo>` and
   `claude plugin install omega@omega-ai`.
3. After `/omega:parallel 3` and `/omega:local-merge`, every following turn —
   including the first turn after a compaction — begins with a hook-injected
   line `Omega modes: parallel max=3 · local-merge`. `/omega:parallel off`
   removes the entry, and the line disappears when no mode is left.
4. `/omega:handoff` leaves `git status` clean, `git log origin/<branch>..HEAD`
   empty, a committed `docs/handoffs/<date>-<branch>.md`, and prints a resume
   prompt that names the worktree, the handoff file, the modes to re-invoke
   and the studio command to continue with.
5. Under `/omega:parallel`, a plan whose tasks touch disjoint files runs its
   ready tasks concurrently, each in its own worktree and branch; each task is
   still reviewed before it is cherry-picked onto the feature branch; the
   invoking skill's bookkeeping (`studio-state set task`, ledger lines) runs
   exactly as it would have without the mode.
6. Under `/omega:local-merge`, a merge runs the project's local CI, requires
   exit 0, and lands through `gh pr merge --admin` with the strategy the
   project uses. No merge happens on a red run or while `autopilot` is active.
7. `/omega:integration start <slug>` creates `integration/<slug>` off
   `origin/main` with `docs/integrations/<slug>.md`; story PRs target that
   branch; `finish` refuses while a listed story is unmerged and otherwise
   lands the integration branch on `main` through the local-merge rules.
8. `/omega:autopilot` asks every open decision before it starts, commits and
   pushes the spec and plan, updates the story when a tracker is detectable,
   and then runs without a single `AskUserQuestion`: rulings are logged with
   their cost-if-wrong, the branch is pushed after every integrated task, a PR
   is opened, no merge is attempted, and the run ends (normally or on a hard
   stop) with a handoff.
9. `sh tests/run_all.sh` passes and covers the omega plugin manifest, skill
   frontmatter, hook and `bin/` syntax, the `omega-mode` round trip, hook
   output validity, prompt-envelope parsing, the marketplace manifest, the
   two-plugin shim, the copy-mode snapshot, and one text contract per skill.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Prefix | The plugin is named `omega`; skills are `/omega:<skill>`. |
| 2 | Packaging | `shared/omega/` is a Claude Code plugin loaded by every studio shim through a second `--plugin-dir`. No opt-in; every studio gets it. |
| 3 | Plain claude | A root `.claude-plugin/marketplace.json` publishes `omega` from `./shared/omega`; the user installs it into plain `claude` by hand. The README also shows a `--plugin-dir` alias for live editing. `install.sh` never touches `~/.claude`. |
| 4 | Composition | Overlay: omega skills are rulebooks plus a hook-injected mode line. Studio skills are not edited. Precedence: a mode wins on scheduling, merge mechanics and stopping; the invoking skill wins on gates (approvals, reviewers, tests, verify rules, state writes). |
| 5 | Mode state | A mode is a line in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/omega/modes/<session_id>`, written only by `bin/omega-mode` (called by the mode skills and by the UserPromptSubmit hook), printed by the SessionStart and UserPromptSubmit hooks, deleted by the SessionEnd hook. |
| 6 | Parallel | One skill, `/omega:parallel [N]`; no `N` means one agent per ready task. Each concurrent task runs in its own worktree and branch and is cherry-picked onto the feature branch after review. |
| 7 | Models | `parallel` sets no model table; superpowers' subagent-driven-development chooses. One floor: an agent that must work in a per-task worktree is never below the mid tier (sonnet), because the cheapest tier ignored worktree paths in Plan 1. |
| 8 | Handoff stop point | When agents are in flight, `handoff` asks once: finish the current task, or stop now. |
| 9 | Handoff commits | Red or half-done work is committed as `wip:` with the failing tests and unfinished files listed, then pushed. Work is never discarded. |
| 10 | Handoff artifact | A committed `docs/handoffs/<date>-<branch>.md` plus a short printed resume prompt. |
| 11 | Merge path | `local-merge` merges through `gh pr merge --admin` on a PR (created when missing). |
| 12 | Merge strategy | Project docs first; else the shape of the last five merged PRs (single-parent merge commits → squash, two parents → merge commit; `phoenix` is squash, `omega-ai` is merge commit); else squash. |
| 13 | Local CI | Project docs (CLAUDE.md, CONTRIBUTING, docs naming local CI or manual merge) first; then convention (`make ci|test|check`, `scripts/ci*.sh`, `tests/run_all.sh`, `npm test`, `cargo test`); else stop and ask. Never merge unverified. |
| 14 | Integration | `integration/<slug>` off `origin/main`, tracked in `docs/integrations/<slug>.md` on that branch. Story PRs target the integration branch and land through the local-merge rules. |
| 15 | Autopilot | Named `autopilot`. Unattended it may commit, push and open a PR; it never merges, even with `local-merge` active. Arming it starts a keep-awake process (`bin/omega-caffeine`: `caffeinate` on macOS, `systemd-inhibit` on Linux, a warning elsewhere) and a session-only `CronCreate` heartbeat that re-prompts the run every 30 minutes while the session is idle; both go when the mode is cleared. |
| 16 | Story tracker | Detected from the branch: `KAN-<n>` → Jira through the Atlassian MCP when present; a leading `<n>-` or `issue-<n>` → GitHub issue `<n>` through `gh`; otherwise none, recorded in the plan header. |
| 17 | Unattended decisions | Industry-standard default, chosen from the studio's `CLAUDE.md`, the shared standards and superpowers; every ruling logged with its cost-if-wrong; the morning report lists rulings first. |
| 18 | Dependencies | `shared/omega` has no `requires.txt`. References to `superpowers:*` are conditional ("when installed"): the `general` studio has no superpowers, and every omega skill must work there. |

Three smaller decisions were taken while writing this spec so the plan does
not have to re-open them. Per-task branches are named
`parallel/<feature>/task-<n>` rather than `<feature>/task-<n>`, because git
refuses a branch whose name is a directory prefix of an existing branch.
Story branches merged by `local-merge` are deleted with `--delete-branch`;
integration branches are deleted only by `integration finish`. The SessionStart
hook matcher includes `clear`, so a cleared session still learns where
`omega-mode` is.

## Packaging and loading

```
omega-ai (repository)
├── .claude-plugin/marketplace.json     publishes omega for plain claude
├── shared/
│   ├── CLAUDE.part.md  memory/  bin/   merged into every studio (unchanged)
│   └── omega/                          the global plugin
│       ├── .claude-plugin/plugin.json  name "omega" → the /omega: namespace
│       ├── skills/
│       │   ├── handoff/SKILL.md
│       │   ├── parallel/SKILL.md
│       │   ├── local-merge/SKILL.md
│       │   ├── integration/SKILL.md
│       │   └── autopilot/SKILL.md
│       ├── hooks/
│       │   ├── hooks.json              SessionStart, UserPromptSubmit, SessionEnd
│       │   ├── session-start.sh
│       │   ├── prompt-submit.sh
│       │   └── session-end.sh
│       └── bin/omega-mode              the mode file's only writer; prompt-submit.sh calls it
├── docs/omega/{specs,plans}
└── tests/omega_test.sh
```

Everything under `shared/omega` is POSIX `sh` with no dependencies, and every
hook is self-contained: in copy mode the plugin root is a snapshot with no
`lib/common.sh` beside it, exactly as the game-dev hooks are written today.

### `.claude-plugin/plugin.json`

```json
{
  "name": "omega",
  "version": "0.1.0",
  "description": "Global overlay skills for every omega-ai studio: handoff, parallel, local-merge, integration, autopilot."
}
```

The `name` is the namespace; `tests/studio_test.sh` checks it equals the
directory name, as it does for studios.

### The shim

`install.sh` gains one variable and two flags. In symlink mode
`GLOBAL_DIR="$REPO_ROOT/shared/omega"`; in copy mode the plugin is snapshotted
to `$TARGET/global` (recorded in the manifest like `$TARGET/studio`) and
`GLOBAL_DIR="$TARGET/global"` — not `$TARGET/omega`, which is the runtime
mode directory's parent. The shim becomes:

```sh
#!/usr/bin/env sh
OMEGA_STUDIO_ROOT="<plugin dir>"
OMEGA_GLOBAL_ROOT="<global dir>"
export OMEGA_STUDIO_ROOT OMEGA_GLOBAL_ROOT
CLAUDE_CONFIG_DIR="<target>" \
PATH="<target>/bin:$OMEGA_GLOBAL_ROOT/bin:$PATH" \
  exec claude --plugin-dir "$OMEGA_STUDIO_ROOT" --plugin-dir "$OMEGA_GLOBAL_ROOT" "$@"
```

`--plugin-dir` is repeatable (`claude --help`: "repeatable: --plugin-dir A
--plugin-dir B.zip"). `shared/omega/bin` on `PATH` lets a skill call
`omega-mode` by name inside a studio; in plain `claude` the SessionStart hook
prints the absolute path instead (see "Mode mechanism").

The install's pre-flight check (`[ -f "$STUDIO_DIR/CLAUDE.md" ]` and friends)
gains `[ -f "$REPO_ROOT/shared/omega/.claude-plugin/plugin.json" ]`, so a
checkout missing the global plugin fails before the previous install is
removed. `uninstall.sh` is unchanged: the copy-mode snapshot is a manifest
entry, and in symlink mode nothing of omega lives under the target.

### `doctor.sh`

After the studio plugin line, the doctor prints the global plugin as the shim
loads it (the snapshot in copy mode, the checkout otherwise):

```
plugin:        game-dev 0.1.0   skills 8  agents 3  hooks present
global plugin: omega 0.1.0      skills 5  hooks present
```

A missing manifest, a name other than `omega`, or a missing `hooks/hooks.json`
fails the doctor, as the studio checks do. The existing shim identity check
additionally requires `--plugin-dir "$OMEGA_GLOBAL_ROOT"` in the recorded shim
and reports `shim: stale (no global plugin)` when it is absent — the state an
install made before this design leaves behind. Reinstalling fixes it.

### Marketplace manifest

`.claude-plugin/marketplace.json` at the repository root:

```json
{
  "name": "omega-ai",
  "owner": { "name": "omega-ai" },
  "plugins": [
    {
      "name": "omega",
      "description": "Global overlay skills for any studio: handoff, parallel, local-merge, integration, autopilot.",
      "version": "0.1.0",
      "source": "./shared/omega"
    }
  ]
}
```

The README's new "Global skills" section documents both routes into plain
`claude`:

```sh
claude plugin marketplace add /path/to/omega-ai
claude plugin install omega@omega-ai          # then `claude plugin update omega` after a pull
alias claude-omega='claude --plugin-dir /path/to/omega-ai/shared/omega'   # live edits
```

The installer never writes to `~/.claude`; both commands are the user's.

## Mode mechanism

A **mode** is a standing instruction that changes how the current session
schedules, merges or stops work. Three of the five skills set one
(`parallel`, `local-merge`, `autopilot`); `integration start` sets one so the
other modes know the PR base; `handoff` reads them all.

### The mode file

Path: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/omega/modes/<session_id>`. One
mode per line, `<mode>` followed by optional `key=value` pairs:

```
parallel max=3
local-merge
integration slug=ui-rework
autopilot
```

`parallel` with no `max=` means unlimited. Setting a mode replaces its
existing line; clearing removes it; an empty file is deleted. The file is
per session on purpose: two sessions on the same project may run different
modes, and a handoff carries the modes forward explicitly in its resume
prompt rather than through a shared file.

The session id comes from `$CLAUDE_CODE_SESSION_ID` (set in the Bash tool's
environment; verified in this repository) or from `--session <id>`; hooks
read `session_id` from the JSON on stdin. Without either, `omega-mode` exits
1 with a message.

### `bin/omega-mode`

```
omega-mode set   <mode> [key=value ...]     add or replace the mode's line
omega-mode clear <mode> | --all             remove one mode, or the file
omega-mode show                             print the file's lines; nothing when no mode
omega-mode path                             print the mode file's path
```

All verbs accept `--session <id>`. `show` exits 0 in every case; a missing
file is "no modes", not an error. The script is the one place the line format
is known: `prompt-submit.sh` calls it rather than editing the file itself.

### Hooks

`hooks/hooks.json` registers three events:

- **SessionStart** (`startup|resume|clear|compact`) runs `session-start.sh`.
  It prunes mode files older than seven days (`find -mtime +7`), never the
  current session's, then prints one line naming the plugin's five skills
  and the absolute path of
  `omega-mode` (`${CLAUDE_PLUGIN_ROOT}/bin/omega-mode`), and, when the
  session's file has lines, `Omega modes: <line> · <line>` followed by one
  rule line per active mode. Output is the same JSON shape the game-dev hook
  uses (`hookSpecificOutput.additionalContext`), escaped the same way.
- **UserPromptSubmit** runs `prompt-submit.sh`. Claude Code delivers a slash
  command to the hook as an envelope, not the literal text:
  `<command-name>/omega:parallel</command-name><command-args>3</command-args>`.
  The hook recognises `/omega:parallel [N|off]`, `/omega:local-merge [off]`,
  `/omega:autopilot off` (a bare `/omega:autopilot` sets nothing — the
  skill sets the mode at the end of phase 1, so an unfinished question
  sweep never reads as unattended) and `/omega:integration start <slug>`
  only —
  `finish` is handled by the skill, which clears the mode only after every
  story row is merged, and a refused finish keeps the mode — and calls
  `omega-mode set` or `clear` accordingly, so a typed command changes the
  mode deterministically before the model reads the skill. It then prints
  the same `Omega modes:` block as SessionStart — only when at least one
  mode is active, so a session with no mode pays no tokens. Any other
  prompt leaves the file untouched; a `<scheduled-task>` prompt never
  changes a mode but still receives the block when a mode is set.
- **SessionEnd** runs `session-end.sh`, which deletes the session's file.

When the model invokes a mode skill through the Skill tool, the hook never
saw a command (a resume prompt that says "run /omega:parallel 3" is typed by
the user, so the hook does see that one). Every mode skill therefore opens
by running `omega-mode`, so both paths converge on the file: `parallel` and
`local-merge` begin with `omega-mode set <mode> …` (or `clear`);
`integration` begins with `omega-mode show` and sets the mode in `start`
(recovering the slug from the checked-out branch or `status <slug>` when
no line is set); `autopilot` clears a leftover mode first and sets it only
when phase 1's readiness checklist passes.

The rule lines are short and fixed, one per mode; the block prints only the
lines of the modes that are set:

```
Omega modes: parallel max=3 · local-merge
  parallel: dispatch up to 3 ready tasks at once, each in its own worktree; review each; cherry-pick onto the feature branch; the invoking skill's bookkeeping is unchanged.
  local-merge: skip GitHub checks; run the project's local CI; merge through gh pr merge --admin only on exit 0; PR base is the integration branch when one is set.
  integration: story branches PR into integration/<slug>; docs/integrations/<slug>.md is the set; finish only when every row is merged.
  autopilot: never AskUserQuestion — rule by the standards, log the ruling with its cost if wrong, continue; commit, push and open a PR, never merge; end with handoff.
```

### Precedence contract

Every mode skill carries this paragraph verbatim, and the rule lines above
are its summary:

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

## `/omega:handoff`

```yaml
name: handoff
description: Use when a session must stop or pause mid-work (context limit, compaction, /clear) — finds a safe stopping point, commits and pushes everything, and prints the prompt that resumes the work in a new session.
```

**Announce at start:** "Using omega:handoff to save this session's work."

1. **Freeze.** Dispatch nothing new. If any subagent is still running, ask
   once with `AskUserQuestion`: *wait for the current task to finish* (then
   let the running implementer or reviewer complete, record its result as
   the invoking skill would) or *stop now* (stop the agents; whatever is on
   disk is handed off as in-progress). Under `autopilot` the question is not
   asked: the current task finishes.
2. **Inventory.** Collect, read-only: the current branch and its upstream;
   `git worktree list` for per-task worktrees the `parallel` mode created;
   `studio-state show` when `studio-state` is on `PATH` (never written here);
   the SDD ledger under `.superpowers/sdd/` when present (gitignored in most
   projects, so its summary goes into the handoff file); `omega-mode show`;
   the spec and plan paths and the task pointer the invoking skill uses; the
   open PR (`gh pr view --json number,url,baseRefName`) when one exists; the
   integration branch when `integration` is set.
3. **Save.** For every per-task worktree whose branch has commits not yet
   cherry-picked onto the feature branch: `git push -u origin
   parallel/<feature>/task-<n>`. In the session worktree, stage the work
   (never `git add -A` blindly: list what is staged) and commit — green: a
   normal message; tests red or a task half done: `wip: <what>` with a body
   listing the failing tests and the unfinished files. Then `git push -u
   origin <branch>`. Verify: `git status --porcelain` prints nothing and
   `git log origin/<branch>..HEAD` prints nothing.
4. **Write the handoff file** `docs/handoffs/<YYYY-MM-DD>-<branch-slug>.md`
   (`/` in the branch name becomes `-`), sections in this order: *Where*
   (repository, worktree path, branch, base, PR); *State* (stage, spec, plan,
   task N/M, integration branch, per-task branches pushed); *Modes* (the
   `omega-mode show` lines); *Done / In progress / Next*; *Rulings* (from
   the ledgers); *Unverified* (playtest and visual items, anything reviewed
   by reading only); *Red* (the `wip:` commit's failing tests and unfinished
   files, or "none"); *Verify* (the commands that prove the state: test
   command, `git log`, `studio-state show`); *Resume prompt* (the block from
   step 5). Commit as `docs(handoff): <branch> at task N/M` and push.
5. **Print the resume prompt**, short, for the user to paste into the next
   session:

   ```
   Resume <branch> in <worktree path>.
   Read docs/handoffs/<file>.md first.
   Run: /omega:parallel 3, /omega:local-merge.
   Continue with /game-dev:execute — resume at task 4/6.
   ```

   The `Run:` line lists every active mode except `autopilot`, which goes on
   its own line marked optional (`Optional: /omega:autopilot` — the resumed
   session runs attended unless the user types it). The last line names the
   exact studio command that was running and where it resumes; when no
   studio is present it names the superpowers skill
   (`superpowers:executing-plans` with the plan path) or, without either,
   the plan file and the next task.

What it changes: when the session stops. What it never changes: studio state
(`studio-state` is read, never set), the plan, the ledger's rulings.

## `/omega:parallel [N|off]`

```yaml
name: parallel
description: Use when an approved plan has independent tasks and you want them implemented concurrently by subagents, with an optional cap on how many run at once — keeps the main session's context small.
```

**Announce at start:** "Using omega:parallel with max N" (or "unlimited").

Sets `parallel max=N` (`parallel` when N is absent) with `omega-mode set`;
`off` clears it. The precedence contract follows. While active, these rules
apply to any skill that dispatches one implementer per task — a studio's
execute stage, `superpowers:subagent-driven-development`,
`superpowers:executing-plans`, or a plain plan followed by hand:

1. **Wave table.** After the invoking skill's preconditions and before its
   first dispatch, read the plan once and write
   `<scratchpad>/parallel/waves.md`: one row per task with its `Files:`
   line, explicit dependencies ("after Task 3", "depends on"), and implicit
   ones (a task whose files include a file an earlier task creates depends
   on that task). Print at most ten lines of it. A plan without `Files:`
   lines has no basis for overlap detection: every task depends on the one
   before it, and the mode says so and runs sequentially.
2. **Ready and slots.** A task is ready when its dependencies are done and
   none of its files overlap a task in flight. Dispatch ready tasks up to
   `max` (all of them when unlimited); as a task completes, refill the slot.
   Slots, not strict waves.
3. **Isolation.** Each dispatched task gets its own worktree and branch:
   `git worktree add <scratchpad>/wt/task-<n> -b parallel/<feature>/task-<n>
   <feature-branch>`, cut from the feature branch's HEAD at dispatch time.
   The brief says: work only in that path, commit only on that branch,
   never touch another path. The implementer's model is whatever
   subagent-driven-development would choose, with one floor: never below
   the mid tier (sonnet) for an agent working in a per-task worktree.
4. **Reports.** Every subagent runs in the background and returns at most
   fifteen lines: commit hash, files touched, test result, open questions.
   Anything longer goes to `<scratchpad>/parallel/task-<n>.log`. The main
   session never reads a diff; reviewers do.
5. **Review.** As soon as an implementer reports, dispatch the invoking
   skill's reviewer on the task branch (the studio's reviewer, or
   subagent-driven-development's); fix rounds happen in the task worktree
   with the loop and escalation rules the invoking skill already has.
6. **Integrate.** When the review is clean, in the session worktree
   `git cherry-pick` the task's commits onto the feature branch and run the
   project's tests. On a conflict, dispatch a fix agent to rebase the task
   branch onto the feature branch and retry. Then verify that the feature
   branch gained exactly the cherry-picked commits (`git log --oneline
   <before>..<feature>`, where `<before>` is the feature HEAD noted before
   the cherry-pick) and that `git status --porcelain` in the session
   worktree prints nothing — the failure Plan 1 saw was an agent committing
   on the session branch instead of its own. Remove the task worktree and
   delete the task branch; its commits are on the feature branch now. Only
   now does the invoking skill's bookkeeping run — `studio-state set task
   n/N`, its ledger lines — exactly as it would have.
7. **Stopping.** The invoking skill's stop conditions are unchanged.
   `handoff` pushes any task branch not yet integrated (see step 3 there).

What it changes: scheduling and isolation of implementers, the size of what
returns to the main context. What it never changes: the reviewer per task,
the fix loop, the tests a task must pass, the final whole-branch review, the
state writes.

## `/omega:local-merge [off]`

```yaml
name: local-merge
description: Use when GitHub Actions is unavailable or rate-limited — skips the remote checks, runs the project's local CI, and merges through gh pr merge --admin when it is green.
```

**Announce at start:** "Using omega:local-merge."

Sets `local-merge` with `omega-mode set`; `off` clears it. The precedence
contract follows. While active, any step that would wait for GitHub checks
or hand the merge to the user — a studio's ship stage,
`superpowers:finishing-a-development-branch` when installed, or the user
saying "merge it" — follows this procedure instead:

1. **Find the local CI procedure.** In order: the project's docs
   (`CLAUDE.md`, `CONTRIBUTING*`, `docs/**`) for a section naming local CI or
   a manual merge procedure; then convention — `make ci`, `make test`,
   `make check`, `scripts/ci*.sh`, `tests/run_all.sh`, `npm test`,
   `cargo test`, in that order, the first that exists; else stop and ask the
   user what runs the checks. Never merge unverified.
2. **Run it.** Show the last twenty lines of output and the exit code. Exit
   0 is required; on any other value report the failure and stop — no
   merge, no retry without a fix.
3. **PR.** `gh pr view` on the current branch; when there is none,
   `gh pr create --fill --base <base>` (`--draft` under `autopilot`). The
   base is `integration/<slug>` when the `integration` mode is set, else the
   repository's default branch.
4. **Strategy.** The project's docs when they state one; else the shape of
   the last five merged PRs (`gh api repos/<owner>/<repo>/pulls?state=closed`,
   then each `merge_commit_sha`: two parents is a merge commit, one parent is
   a squash; majority wins); else squash. For reference: `phoenix` squashes,
   `omega-ai` merges.
5. **Confirm and merge.** Ask once, showing the green result and the
   strategy; on yes, `gh pr merge <n> --admin --<strategy> --delete-branch`.
   Under `autopilot` this step is skipped: the PR stays open with the CI
   result in a comment, and the morning report says so. Verify with
   `git fetch` that the merge landed on the base, then hand back to the
   invoking skill's own cleanup (worktree removal, `stage retro`, and so on).

What it changes: which checks gate a merge and who performs it. What it
never changes: the invoking skill's verification before the merge, its
state writes after it, the tests themselves.

## `/omega:integration start|add|status|finish`

```yaml
name: integration
description: Use when several related stories must land together — creates an integration branch every story merges into, tracks the set, and lands the whole set on main through the local-merge rules.
```

**Announce at start:** "Using omega:integration <verb>."

- **`start <slug>`.** `git fetch origin`; `git switch -c integration/<slug>
  origin/main`; write `docs/integrations/<slug>.md` with the goal and a table
  `Story | Branch | Ticket | Depends on | Status | PR` (status is `planned`,
  `in progress` or `merged`); commit `docs(integration): start <slug>`;
  `git push -u origin integration/<slug>`; `omega-mode set integration
  slug=<slug>`.
- **`add <branch-or-ticket>`.** Append a row (ticket from the name when it
  matches `KAN-<n>`, a leading `<n>-`, or `issue-<n>`); when the branch does
  not exist, create it off the integration branch. Commit on the integration
  branch and push.
- **Story flow.** A story's PR targets `integration/<slug>` — `local-merge`
  reads the mode and sets the base, and merges the story with its usual
  procedure. After the merge the row's status becomes `merged` and the PR
  number is recorded, committed on the integration branch.
- **`status`.** Print the table, the open PRs against the branch, and the
  commit count per story branch not yet on the integration branch.
- **`finish`.** Refuse, listing them, while any row is not `merged`.
  Otherwise `git fetch`, merge `origin/main` into the integration branch
  when it is behind, run the local CI procedure, open the PR
  `integration/<slug>` → `main`, and land it through the local-merge
  procedure (step 5's confirmation included). Then delete the integration
  branch locally and remotely and `omega-mode clear integration`.

What it changes: where story branches merge and what "done" means for the
set. What it never changes: how each story is designed, planned, implemented
or reviewed — each story runs its studio's workflow on its own branch.

## `/omega:autopilot [off]`

```yaml
name: autopilot
description: Use when a long run must proceed with nobody at the keyboard — asks every open decision up front, commits the spec and plan, then executes without questions, logging each ruling, pushing after every task, and ending with a handoff.
```

**Announce at start:** "Using omega:autopilot — pre-flight first."

### Phase 1 — pre-flight, interactive

1. **Design and plan as the studio does.** Run the studio's own design and
   planning skills unchanged (`/game-dev:brainstorm` and `/game-dev:plan` in
   the game studio; `superpowers:brainstorming` and `superpowers:writing-plans`
   when installed and no studio is present). Their approval gates stand.
2. **Question sweep.** Read the approved spec and plan and list every
   decision the implementation could still meet: naming, error handling,
   test depth, tie-breaks between two acceptable patterns, what to do when a
   tool is missing, which of two libraries. Ask all of them, batched three
   or four per `AskUserQuestion`. Record each answer in the plan (a
   *Decisions* section) so the unattended phase reads them, not memory.
3. **Commit and push** the spec, the plan and the ledger.
4. **Update the story** when a tracker is detectable from the branch name:
   `KAN-<n>` → Jira through the Atlassian MCP when its tools are present; a
   leading `<n>-` or `issue-<n>` → GitHub issue `<n>` through
   `gh issue comment`; write the
   dependency list (from `docs/integrations/<slug>.md` when the
   `integration` mode is set) and links to the spec and plan. No tracker →
   the same text goes into the plan header, and the report says so.
5. **Readiness checklist**, printed and every line required: on the
   feature branch in a worktree; the plan is approved and committed; the
   baseline test run is green; `gh auth status` succeeds; the engine or
   runtime binary the plan needs resolves; no unanswered question remains.
6. **Arm**, in this order: `omega-mode set autopilot`; `omega-caffeine
   start` (`unsupported` is a warning, not a stop); `CronCreate` the
   heartbeat — cron `17,47 * * * *`, recurring, a fixed prompt that
   continues the run only while `omega-mode show` still lists `autopilot`
   and otherwise deletes itself; it fires only while the session is idle
   and expires after seven days. Then tell the user to start the run
   (`/game-dev:execute`, or the equivalent) — the same message says what the
   run may and may not do, and that the permission mode must allow the
   run's tools unattended: a permission prompt is a question nobody
   answers.

### Phase 2 — unattended

While `autopilot` is set:

- **No questions.** `AskUserQuestion` is never called. An open decision is
  settled by the studio's `CLAUDE.md`, the shared engineering standards,
  superpowers' conventions when installed, and industry practice, in that
  order; the ruling is logged where the invoking skill logs rulings
  (`studio-state ledger "Ruling: <decision> — <why> — <cost if wrong>"`, or
  the SDD ledger) and the run continues.
- **Allowed side effects:** commit; push the branch after every integrated
  task, so a crash loses at most one task; open a draft PR when the plan is
  complete and comment on it; write the handoff.
- **Forbidden:** merge (even with `local-merge` set — that step is skipped
  and reported), force-push, deleting a remote branch, any destructive or
  security-sensitive operation, reading or writing secrets.
- **Hard stops:** the invoking skill's own — a destructive or
  security-sensitive operation the plan requires, or a plan too broken to
  follow. On one, run `handoff` without its question (the current task
  finishes), disarm, then stop.
- **Completion:** run `handoff`. The handoff file's first section after
  *Where* is the **morning report**: every ruling in order with its cost if
  wrong, the unverified items, the PR link, and the resume prompt. Then
  disarm.
- **Disarm**, after the handoff on either ending: `omega-caffeine stop`;
  `CronDelete` the heartbeat; `omega-mode clear autopilot`. The cleared
  mode is what lets a heartbeat that was not deleted end itself.

`autopilot off` stops the keep-awake process, deletes the heartbeat and
clears the mode. The handoff at the end records the mode in the handoff
file and lists it as optional in the resume prompt, so the morning session
runs attended unless the user re-invokes it.

What it changes: when questions are asked and what happens when one would
arise; which side effects run unattended. What it never changes: the
studio's stages and gates, the reviewer per task, the tests.

## How the skills compose

- `autopilot` ends with `handoff`, on completion and on a hard stop.
- `local-merge` under `autopilot` creates the PR and skips the merge.
- `integration` sets the PR base that `local-merge` uses and the dependency
  list `autopilot` writes to the story.
- `parallel` hands every bookkeeping step back to the invoking skill; under
  `autopilot` its stop conditions are the autopilot ones.
- `handoff` pushes the task branches `parallel` left un-integrated, records
  every active mode, and prints the commands that re-create them.
- All five run inside `game-dev`, `general` and plain `claude`. Where a step
  names a superpowers skill, it says "when installed" and states the
  fallback inline.

## Tests

`tests/studio_test.sh` loops over `studios/*/` today; the manifest,
skill-frontmatter, and `bin/` / hook syntax tests extend their loops to
`shared/omega/` (the plugin name must equal the directory name; every
description starts with "Use when"; every script passes `sh -n` and is
executable). The external-references and required-plugins tests keep their
studio scope: omega has no `requires.txt` or `settings.json`.

`tests/omega_test.sh`, new, runs without a config root:

- `omega-mode` round trip in a temporary `CLAUDE_CONFIG_DIR` with a fixed
  `--session`: `set parallel max=3`, `set local-merge`, `show` prints both
  lines; `set parallel` replaces the first line; `clear parallel` leaves one;
  `clear --all` removes the file; `show` on a missing file exits 0 and prints
  nothing; no session id exits 1.
- `session-start.sh` and `prompt-submit.sh` emit valid JSON (jq when present,
  shape check otherwise) with and without a mode file; the additional context
  contains `Omega modes:` only when a mode is set; a file older than seven
  days is pruned on SessionStart; `session-end.sh` deletes the session file.
- `prompt-submit.sh` fed the envelope for `/omega:parallel 3` writes
  `parallel max=3`; `/omega:parallel off` clears it; `/omega:integration start
  ui-rework` writes `integration slug=ui-rework`; a bare `/omega:autopilot`
  writes nothing and `/omega:autopilot off` clears the mode; a foreign
  command envelope changes nothing; a `<scheduled-task>` prompt changes no
  mode.
- `.claude-plugin/marketplace.json` is valid JSON, names `omega`, and its
  `source` resolves to `shared/omega`.
- Text contracts, one block per skill: `handoff` mentions `wip:`,
  `docs/handoffs`, `AskUserQuestion` and the resume prompt; `parallel`
  mentions `cherry-pick`, `git worktree add`, `parallel/`, the sonnet floor
  and the fifteen-line cap; `local-merge` mentions `--admin`, `exit 0`, the
  strategy detection and "Never merge unverified"; `integration` mentions
  `docs/integrations`, `integration/` and refuses `finish` with unmerged
  rows; `autopilot` mentions "never" beside merge, forbids
  `AskUserQuestion` in phase 2, and ends with `handoff`. Every mode skill
  contains the precedence contract's first sentence.

`tests/install_test.sh` gains: the symlink-mode shim contains
`OMEGA_GLOBAL_ROOT="$REPO_ROOT/shared/omega"` and `--plugin-dir
"$OMEGA_GLOBAL_ROOT"`; the copy-mode install creates
`$TARGET/global/.claude-plugin/plugin.json`, the shim points
`OMEGA_GLOBAL_ROOT` at it, the manifest records it, and uninstall removes it.

## Docs

`docs/omega/specs/` holds this design and `docs/omega/plans/` the
implementation plans, mirroring `docs/game-dev/`. The README gains a "Global
skills" section: what the five skills do in one line each, the marketplace
install and the alias for plain `claude`, and a note that every studio shim
loads the plugin. The skills are authored with `superpowers:writing-skills`
(a pressure scenario first, then the skill, then the scenario again).

## Delivery

Two implementation plans, so the loading and mode machinery is proven before
the skills that depend on it are written:

1. **Foundation** — `shared/omega` with its manifest, `bin/omega-mode`, the
   three hooks, the marketplace manifest, the `install.sh` / `doctor.sh`
   changes, the test extensions and `tests/omega_test.sh`. Exit: success
   criteria 1, 3 and 9 hold with five placeholder-free skill files that
   carry only frontmatter and the precedence contract.
2. **Skills** — the five `SKILL.md` files written with
   `superpowers:writing-skills`, their text contracts in `tests/omega_test.sh`,
   and the README section. Exit: success criteria 2 and 4–8 hold; the
   "session, end to end" below runs in `claude-gd`.

## A session, end to end

In a Godot project, inside `claude-gd`, with an approved six-task plan:

```
/omega:parallel 3
/omega:local-merge
/game-dev:execute
```

The hook prints `Omega modes: parallel max=3 · local-merge` at the top of
every turn. `execute` runs its preconditions and enters its worktree; the
parallel mode builds the wave table — tasks 1, 2 and 4 touch disjoint files
and are dispatched at once, each in `wt/task-<n>` on
`parallel/dash/task-<n>`; task 3 waits on task 1. Each report is fifteen
lines; each task is reviewed by `godot-prompter:godot-code-reviewer` on its
branch, cherry-picked onto `dash`, and only then does `execute` run
`studio-state set task`. Context runs low after task 4:

```
/omega:handoff
```

Task 5's implementer is still running; the user chooses "wait for the
current task to finish". Its commit is reviewed and integrated, task 6's
branch (dispatched, not reviewed) is pushed as
`parallel/dash/task-6`, `dash` is committed and pushed,
`docs/handoffs/2026-09-13-dash.md` is committed and pushed, and the session
prints:

```
Resume dash in /path/to/project/.claude/worktrees/dash.
Read docs/handoffs/2026-09-13-dash.md first.
Run: /omega:parallel 3, /omega:local-merge.
Continue with /game-dev:execute — resume at task 6/6.
```

Next morning the user pastes that into a fresh `claude-gd`. The modes are
set by the hook as the two commands are typed; `execute` reads `task 5/6`,
the parallel mode finds `parallel/dash/task-6` on the remote, reviews it and
integrates it; the final review passes; `execute` sets `stage review` and
names `/game-dev:review`. When the branch reaches the ship stage, the
`local-merge` mode runs `studio-test`, shows the green result, and lands the
PR with `gh pr merge --admin --merge`.

## Out of scope

- Editing any studio skill to read the mode line.
- A `claude-omega` shim written by `install.sh`.
- A shared mode file across sessions, or modes that persist across a handoff
  without being re-invoked.
- Merging under `autopilot`.
- A tracker beyond Jira (Atlassian MCP) and GitHub issues (`gh`).

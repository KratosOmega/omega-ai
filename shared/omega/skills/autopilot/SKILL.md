---
name: autopilot
description: Use when a long run must proceed with nobody at the keyboard — an overnight session, or any run where no question can be answered until it ends.
---

# Autopilot

**Announce at start:** "Using omega:autopilot — pre-flight first."

## In a studio

This is the one definition; every branch below cites it.
**In a studio** means `command -v studio-state` succeeds and `studio-state get stage` exits 0.
In a studio, no session-mode `autopilot` is ever set, no keep-awake is started, and nothing executes stories in this session:
the stories run in `studio-overnight`'s fresh headless sessions, one unit per session.
Work that does not fit stops with a stated reason (*Does not fit*, below).

`off`: `omega-mode clear autopilot`; then a bare `studio-overnight stop`; then stop.
With one live run, the bare stop ends it. With several, it stops none and lists them:
name `stop --run <slug>` (one run) and `stop --all` (every run) to the user. `omega-mode`
and `studio-overnight` are on `PATH` in a studio (see *In a studio*); the
session-start line names `omega-mode`'s path otherwise.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

Two phases. Phase 1 is interactive. When in a studio (see *In a studio*), it
writes a run manifest, drives the planning loop one stage per session, seeds
every story, then starts the `studio-overnight` runner or prints its command.
Outside a studio it sweeps one plan and sets the mode. Phase 2 is what the
mode means while it is set — by the runner's environment in the sessions it
starts, or by the session file outside a studio.

## Phase 1 — pre-flight, interactive

Phase 1 runs with no session-file `autopilot` mode. An attended phase 1
session never has `OMEGA_AUTOPILOT=1`, so an `autopilot` line in
`omega-mode show` without `source=env` is a previous run's leftover: clear
it first with `omega-mode clear autopilot`. When `OMEGA_AUTOPILOT=1` is set
(`omega-mode show` lists `autopilot source=env`), the runner started this
session and nobody can answer a sweep: phase 1 does not run — stop and say
so; phase 2 governs the session.

### Phase 1 in a studio (see *In a studio*)

`<default>` is the default branch (`git symbolic-ref --short
refs/remotes/origin/HEAD`, without `origin/`); `<dir>` is
the run worktree (see *The run worktree*); `<abs>` is `command -v studio-overnight` from this
session (it is on `PATH` only inside a `claude-gd` session).

1. **Discovery.** A live run never stops discovery. With no slug, list:
   - the **runs being planned**: run worktrees (`git worktree list --porcelain`, `branch refs/heads/run/*`) whose `.studio/run` names a manifest with no `<root>/.studio/runs/<slug>/landed.tsv`;
     - also a run worktree with no `.studio/run` whose `docs/runs/<slug>.md` is committed (`git -C <dir> ls-files --error-unmatch docs/runs/<slug>.md`, for `run/<slug>`): list it the same way.
       On resume, rewrite the missing pointer first: `printf '%s\n' docs/runs/<slug>.md > .studio/run` in that worktree.
       The pointer is uncommitted local state, so a re-created worktree loses it.
   - the **started runs**: records under `<root>/.studio/runs/` without `done`, live or not, as `studio-overnight status` prints them.

   Ask one `AskUserQuestion` with each run, and "new run". `/omega:autopilot <slug>` skips the question.
   - A run being planned resumes at step 2, from its run worktree.
   - A started run: when `.studio/runs/<slug>/` exists, the run was started: skip to step 4 (readiness, then how to start), from its run worktree. It is never planned or seeded again, and the runner resumes it from its record.
   - A run whose `.studio/runs/<slug>/done` exists is not listed (a done run's pointer is ignored).
   - "new run", or no run listed: a new run.

   A new run:
   - Ask one `AskUserQuestion` with two questions, each option with its one-line consequence:
     - **integration or direct** — integration: each story is tested once by its own gate, one full gate runs at the end, one PR to land in the morning; direct: one merge-command gate per story (the project's own gate; 15–20 minutes each on phoenix), each story lands on `main` overnight.
       An `integration slug=<slug>` line in `omega-mode show` pre-selects integration with that slug.
     - **how many lanes** — lanes are parallel dependency chains, while tests still run one at a time. The answer is `.studio/config.json`'s `overnight.max_lanes` (`0` = one lane per chain).
        It must be an integer from 0 to 8 (the runner's range); refuse any other answer and ask again.
        Write it only in the run worktree (see *The run worktree*), never in the main checkout: merge it into the existing file, so every other key is kept (`merge_command` included): `python3 -c 'import json,sys; p=".studio/config.json"; c=json.load(open(p)); c.setdefault("overnight", {})["max_lanes"]=int(sys.argv[1]); open(p,"w").write(json.dumps(c, indent=2)+"\n")' <n>`; with no `.studio/config.json`, write `{"overnight": {"max_lanes": <n>}}`.
   - Then ask the story list: each story's id, branch, ticket (`-` when none) and the earlier rows it depends on. Refuse and re-ask an id or branch that another run uses (AC8: a live or stopped run's story id or branch). A story whose branch already exists (local or `origin/<Branch>`) is half-done.
     In the same question, ask each story's **source plan** and **source spec** (a path, or `-` for none): a story with source plan `-` is a fresh story, unchanged. Refuse and re-ask a path that is not repo-relative, not normalized (no `./`, no `..`) or not tracked (`git ls-files --error-unmatch`).
     For a story with a source plan, in the run worktree: `STUDIO_STORY=<id> studio-state init` (the ledger refuses a story with no pointer), then `studio-state ledger "source <plan> spec <spec or ->"` with `STUDIO_STORY=<id>`. These facts survive `/clear` and step 3; they are committed on `run/<slug>` with the manifest.
   - **The run worktree (before any planning stage).** The main checkout's branch is never switched. In order:
     1. Check the slug: not `off`, not all digits, not used by a live or stopped run. A done record is archived: `mv <root>/.studio/runs/<slug> <root>/.studio/runs/<slug>.$(date -u +%Y%m%dT%H%M%SZ)`.
     2. `git fetch origin`, then `git worktree add --no-track -b run/<slug> <root>/.claude/worktrees/run-<slug> origin/<default>`, or `git worktree add <path> run/<slug>` when the branch exists.
     3. Enter it with **Enter the feature checkout** (`EnterWorktree path:`, else `cd`) and check it with `git rev-parse --show-toplevel`.
     4. Print the path.
     5. Run `studio-state init --local`, then `worktree_setup` when configured.
     6. Every later phase-1 step runs there: the lane count, the manifest, `.studio/run` and the commits. Paths are absolute under the run worktree, except half-done story worktrees (`<root>/.claude/worktrees/…`). So every brainstorm and plan commit lands on `run/<slug>`.

     Then, in the run worktree, write the lane count into `.studio/config.json` as above.
   - Write the run manifest `docs/runs/<slug>.md` (Spec and Plan are `-` while planning; `Docs:` is written in step 3):

     ```
     # Run: <slug>

     Mode: integration            # or: direct
     Target: integration/<slug>   # direct: the default branch
     Docs: -
     Goal: <one line: what the run delivers>

     | Story | Branch | Ticket | Spec | Plan | Depends on |
     |-------|--------|--------|------|------|------------|
     | <id>  | <Branch> | <ticket or -> | - | - | <ids or -> |
     ```

   - Write the pointer: `printf '%s\n' docs/runs/<slug>.md > .studio/run`.
     Commit the manifest and the lane count on `run/<slug>`: `git add docs/runs/<slug>.md .studio/config.json .studio/ledger/<id>.md … && git commit -m "docs(run): <slug> manifest"` (every story's ledger, so the source lines are committed) — a dirty `config.json` or ledger would stop each story's first unit at execute §0's clean-tree check.
   - Check *Does not fit* now, before any planning stage.
   - **Adopt (step 1a)** — a story with a source plan was planned outside the studio (for example with superpowers). Each step below says what it does as it runs it, and the plan is converted, never rewritten. In order:
     1. `studio-adopt inspect <id> --branch <Branch> --plan <original>` reads the evidence (the plan's tasks, the SDD ledger, the commits on the branch) and prints it, changing nothing. A mismatch stops that story with inspect's line.
     2. The **gap check**: the plan has a gap when it has any of these four. Show `adopt` or `plan: <gaps>` per story, and confirm or override each in one `AskUserQuestion` (at most 4 stories per question). Ledger `verdict adopt` or `verdict plan` into `<id>.md` (`STUDIO_STORY=<id>`).
        - a task without concrete files or acceptance checks;
        - a `TBD`, `TODO`, open question or undecided option;
        - no spec, and the plan's tasks name no authority for their requirements;
        - no acceptance criteria can be gathered from the source spec or the tasks' acceptance checks (the final review needs them).
     3. A `plan` story: with a source spec, approve that spec through `/game-dev:plan`'s one-word gate (it records `spec approved <spec>` and sets the spec's `Status:`, committed on `run/<slug>`), then print `/game-dev:plan <slug>/<id>`; with none, print `/game-dev:brainstorm <slug>/<id>`. Seed either with the original plan and inspect's output, and tell the planner: tasks 1..k keep the original's titles and boundaries, unchanged and marked finished; planning covers task k+1 onward. The branch and its finished work are kept. After planning, step 3 ledgers `adopted <original> -> <new plan>` into `<id>.md`.
     4. An `adopt` story is converted: the session writes `docs/game-dev/plans/<date>-<id>.md` and never edits the original. The converted plan has:
        - `Story: <id>`, `Source: <original plan path>` and `Status: Draft (awaiting approval)`;
        - `## Global Constraints`, carried over from the original, plus this rule: heavy commands a task runs (a test-tag run, a store write) are wrapped as `studio-gate <who> -- <cmd>`;
        - `## Decisions`, from the original's rulings, decisions and any rulings file or handoff it links, plus the rulings on the conflict scan below;
        - `## Acceptance criteria`, from the source spec's acceptance or success criteria, else from the tasks' acceptance checks;
        - tasks 1:1 with the original (same count, numbers, titles, boundaries and order) above `## Backlog`. Each has a `Spec:` line (`<source spec>:L<a>-<b>` for the spec lines it implements, or with no spec `<original>:L<a>-<b>` for the original task's own block, its heading up to the line before the next `### ` heading) and a `Review:` line by `/game-dev:plan`'s rule (`task` for a new seam, cross-system work, gameplay feel, data or schema, or importer work; `final` for the rest);
        - an optional `Context:` line.

        Before showing it, run SDD's pre-flight conflict scan (pairs of tasks sharing a file or an interface) over tasks k+1..N, and check that every file those tasks modify exists at the story branch tip (`origin/<default>` for a not-started story). Rule each finding with the operator and write it to `## Decisions`.
     5. Show the conversion side by side: task count, titles paired 1:1, what was added, and the conflict-scan rulings. The operator approves in one word. Then, per story, in this order:
        1. `studio-state set spec <spec>`, where `<spec>` is the source spec, or the original plan when there is none;
        2. the manifest row's Spec and Plan cells are set to `<spec>` and the converted plan, byte-identical to the paths ledgered below;
        3. commit the converted plan and the manifest on `run/<slug>`, so `next_match` and `Docs:` see the plan;
        4. without `STUDIO_STORY`, into the spec's slug ledger (the file `next` reads): `spec approved <spec>`, `plan approved <converted plan>`, and `Decisions swept <id>` after asking any question the conversion surfaced;
        5. with `STUDIO_STORY=<id>`, into `<id>.md`: `adopted <original> -> <converted plan>`.

        `next` then classifies the row as `planned` from its filled cells.
     6. Git-ignored files the original or its handoff names as required reading (for example SDD carry rules) are listed to the operator; once confirmed, copy them to `docs/game-dev/adopted/<id>/`, commit on `run/<slug>`, and name them in `Context:`.
     7. When inspect shows k ≥ 1 or part-done commits, ask once per story: **check the built work?** A yes ledgers `check requested` into `<id>.md`.

     superpowers 6.4.1's sdd-workspace rule (the ledger lives in `<worktree root>/.superpowers/sdd/<plan basename>/`, git-ignored) is why inspect looks in every worktree of the original.
2. **Planning loop — one stage per session.** Run `studio-overnight next <manifest>`.
   It classifies every row as `brainstorm`, `plan` or `planned` from files and ledger lines alone and prints `next: <command>`.
   - `next: /game-dev:brainstorm <slug>/<id>` — the epic's spec does not exist yet.
   - `next: /game-dev:plan <slug>/<id>` — when that row's spec is already approved, set `STATE.md` for it first: `studio-state set stage plan`, then `studio-state set spec <spec>`.
   - Either way: Print `/clear`, then the command, and stop. The stage runs in its own session and ends by printing `next`'s command; `/omega:autopilot` resumes here through `.studio/run`, so the loop survives `/clear`.
   - `next: /omega:autopilot <slug>` — every row is `planned`: go to step 3.
   - When `next` exits non-zero: show its message, fix what it names (the manifest, a missing or ambiguous spec or plan), and stop; nothing is seeded.

   The question sweep for manifest stories belongs to `/game-dev:plan` (it writes `## Decisions` and ledgers `Decisions swept <id>`); this skill does not repeat it.
3. **Seed every story** once every row is `planned`, in manifest order. Every `studio-state` call below runs with `STUDIO_STORY=<id>`.
   - Check that the run worktree has `.studio/run` before the first seed (write it as in step 1 when missing): `studio-adopt seed` finds the story's run through it, and falls back to the committed manifest only with a note.
   - A `plan` story that was adopted (its `<id>.md` holds `verdict plan`): first, with `STUDIO_STORY=<id>`, `studio-state ledger "adopted <original> -> <new plan>"` (`<new plan>` from `next`'s `plan=`), before the seeding below
     — ledgered from the run worktree, never from the main checkout (`studio-state ledger` writes the ledger of the checkout the shell is in).
   - Each story, not-started and half-done alike, in the run worktree (on `run/<slug>`), never in a story worktree: `studio-state init`; `set spec <spec>`; `set plan <plan>` (from `next`'s `spec=` and `plan=`); `set task 0/<N>` (`N` = `awk '/^## Backlog/ { exit } /^### Task [0-9]/ { n++ } END { print n + 0 }' <plan>` — the tasks above `## Backlog` only, since a task the producer cut keeps its heading there — run here where the plan exists — a story worktree's `check --rebuild` then takes `N` from the story file and never needs the plan); then the spec-slug ledger's `spec approved <spec>`, `plan approved <plan>` and `Decisions swept <id>` lines are re-ledgered through `studio-state ledger "<text after the date>"`, so each carries today's date.
     They land in the run worktree's `.studio/ledger/<id>.md` — the file the runner's preflight reads, and the one it requires clean — and are committed on `run/<slug>` below.
   - **Not started** (no branch): in the run worktree, `set stage plan`, `set branch -`.
   - **Half-done** (an existing branch, `T<n> complete` lines, possibly `final review done`, `shipped`, or already merged):
     1. Create the story's worktree at the path execute §0 uses, `<STATE_ROOT>/.claude/worktrees/<Branch with / → ->`: `git worktree add --no-track <path> <Branch>` (only on origin: `git worktree add --no-track -b <Branch> <path> origin/<Branch>`); an existing worktree of that branch is used as it is.
        When another checkout holds `<Branch>`, stop with "switch that checkout off <Branch> first".
     2. When the branch has `.studio/ledger/<spec slug>.md` and no `.studio/ledger/<id>.md`: `git mv` it to `.studio/ledger/<id>.md` and commit `chore(studio): ledger keyed by story`.
     3. In that worktree, only: `set branch <Branch>`, `set stage execute`, then for an adopted story `studio-adopt seed <id>` (add `--base <sha>` when inspect was given one; after step 3.2's re-key and before `studio-state check --rebuild`: seed refuses a pointer with no branch, so `set branch` comes first), then `studio-state check --rebuild` (the "each story" lines already ran in this checkout) — seed writes the story's `T<n> complete` lines from the SDD ledger (a not-started adopted story has no seed: execute §0 records its base); the rebuild keeps `N` from the seeded `task 0/<N>` and sets the longest contiguous run of `T<n> complete` lines.
        A failed seed stops here: when `studio-adopt seed <id>` exits non-zero, print its stderr line and stop; never run `studio-state check --rebuild`, `next` or the start after it (a rebuild of an unseeded adopted story refuses anyway).
        A gap exits 1: stop and name the missing task (*Does not fit*).
        `N/N` with `final review done` resumes at the finish; a `shipped` line: `set stage idle` (it waits to land); a merged PR or a head already in `origin/<Target>` is landed — the runner records it at start.
        An open bundle-2 PR into `main` in an integration run is named in `report.md`, never closed.
     Seeding never commits the spec or the plan onto a story branch: execute §0 syncs them from the run's `Docs:` revision under the lane.
   - Then, without `STUDIO_STORY`: `studio-state reset --keep-ledger` — `STATE.md` goes back to idle and the spec ledger survives for the epic's next plan.
   - Integration: create `integration/<slug>` on origin when `git ls-remote --exit-code --heads origin integration/<slug>` fails: `git push origin origin/<default>:refs/heads/integration/<slug>`.
   - Fill each row's Spec and Plan cells, then `git add docs/runs/<slug>.md .studio/config.json <specs> <plans> .studio/ledger/<id>.md …` (every story's ledger, half-done ones included), `git commit -m "docs(run): <slug> planned"`, `git push -u origin run/<slug>`.
     Write that commit's sha (`git rev-parse HEAD`) as `Docs:`, then commit `docs(run): <slug> docs <short sha>` and push `run/<slug>` again.
4. **Readiness checklist.** Print it; every line must pass:
   - `studio-overnight start --dry-run <manifest>` exits 0 (the runner's own preflight: the manifest, `Docs:` on `origin/run/<slug>`, each plan's `Story:`, `Spec:` lines and `## Decisions`, each story's state and ledger, `claude-gd`, `gh auth status`, the deny list, config, `merge_command` in direct mode, no conflicting live or stopped run (slug, story, branch), the start checkout's `.studio/run`, every adopted story with a branch seeded on it);
   - the baseline test run is green — `studio-test`, exit 0, run in the run worktree after `worktree_setup`;
   - the engine binary resolves — `studio-test` or `GODOT_PATH`;
   - for each adopted story: `studio-adopt sync <id>` from its worktree exits 0 (a not-started story is skipped, with a note).

   A failed line stops here; fix it and print the checklist again.
5. **Ask how to start** — one `AskUserQuestion`:
   - **autopilot starts it** — detached from the chat: no terminal, no Ctrl-C; watch with `studio-overnight status`.
     Run `cd '<run worktree>' && '<abs>' start --detach <manifest>`. It runs the preflight in the foreground, starts the runner in its own session, and waits for `studio-overnight status` to answer; exit 0 means the run is live — report success only then.
     The launch may need one permission approval and runs outside the Bash sandbox when one is on (the run needs the network).
     On any non-zero exit, show its message (and the log it names), print the command below, and stop; autopilot never retries in this session.
   - **print the command** — paste it into a plain terminal: live output, and Ctrl-C stops after the running units. The command, with absolute paths: `cd '<run worktree>' && '<abs>' start <manifest>`.

   Either way, say in the same message:
   - what the run may merge in the chosen mode — integration: the runner merges stories into `integration/<slug>`, nothing is merged into `main`, and the morning brings one draft PR integration → `main`; direct: the runner merges each story into `main` only through `merge_command`, each dependent after its dependency;
   - what it may not do: no session merges anything; no force-push; no remote branch deleted; no destructive or security-sensitive operation; no reading or writing of secrets;
   - how to watch and end it: `studio-overnight status` (from any directory) or `studio-overnight watch`, and `studio-overnight stop --run <slug>` (from the project);
   - that the morning `report.md` lands in `.studio/reports/overnight-<slug>-<ts>/`;
   - the run worktree: `git worktree remove <path>` once the run is `done`; nothing removes the worktree automatically;
   - that this chat can now close, and to keep the laptop on power with the lid open.

### Does not fit

In a studio (see *In a studio*), stop in phase 1 with the reason and the options when:

- a row depends on a later or unlisted row;
- direct mode and `.studio/config.json` has no `merge_command`;
- the work is not story-shaped (nothing to branch, plan and ship as a story).

The options always include "integration mode" and "drop the story", plus the fix that fits (reorder the rows, add `merge_command`).
A story without a plan is never a stop — it enters the planning loop. Stories sharing a spec are allowed.

### Phase 1 when not in a studio (see *In a studio*)

The single-plan path: one approved plan, run in this session under the mode.

1. **Design and plan — unless that is done.** When the
   spec and the plan are already approved and committed — both files'
   `Status:` line says Approved, `git log -1 --format=%h -- <file>` prints
   a hash for each, and `git status --porcelain -- <spec> <plan>` prints
   nothing — go straight to step 2. Otherwise
   `superpowers:brainstorming` then `superpowers:writing-plans` when
   installed; otherwise a spec and a plan written by hand and approved by
   the user. Their approval gates stand.
2. **Question sweep.** Read the approved spec and plan. List every decision
   the implementation could still meet: naming, error handling, test depth,
   tie-breaks between two acceptable patterns, what to do when a tool is
   missing, which of two libraries. An item the spec calls open stays in
   the sweep until the plan's own `## Decisions` section answers it — a
   committed file, an existing ledger entry, or any other trace of a prior
   run is not a substitute; ask it again. Ask all of them, three or four
   per `AskUserQuestion`, until none is left. Write each answer into the
   plan under a `## Decisions` section (add it after Global Constraints
   when absent), so phase 2 reads the plan, not memory.
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
   - outside a studio: the feature branch is checked out in a worktree —
     `git branch --show-current`, and `git rev-parse --show-toplevel` is
     not the main checkout;
   - outside a studio: the plan is approved and committed —
     `git log -1 --format=%h -- <plan>` prints a hash and
     `git status --porcelain -- <spec> <plan>` prints nothing;
   - the baseline test run is green — the project's test command, `exit 0`;
   - `gh auth status` succeeds;
   - the engine or runtime binary the plan needs resolves — the tool the
     plan names;
   - no unanswered question remains — the `## Decisions` section covers
     every item of the sweep.

   A failed line stops here; fix it and print the checklist again.
6. **Hand off**, once every checklist line passes:
   `omega-mode set autopilot`, then tell the user to
   start the run in this session — the plan's execution skill — saying in
   the same message what the run may do (commit; push after every task;
   open a draft PR; write the handoff) and may not do (merge into `main` or
   anything else; force-push; delete a remote branch; destructive or
   security-sensitive operations; read or write secrets), and that the
   permission mode must allow the run's tools unattended — a permission
   prompt is a question nobody answers. Nothing keeps the machine awake and
   nothing re-prompts an idle session. Arm (`omega-mode set autopilot`) from
   a fresh session and do not `/clear` after arming — a `/clear` runs
   session-end's `clear --all` and disarms the run.

## Phase 2 — unattended

While `omega-mode show` lists `autopilot` — from the session file, or as
`autopilot source=env` in a session the runner started:

- **No questions.** `AskUserQuestion` is never called. An open decision is
  settled by, in this order: the studio's `CLAUDE.md`; the shared
  engineering standards; superpowers' conventions when installed; industry
  practice. Log the ruling **as one line** — decision, why and cost if
  wrong all in that single line, never spread across a wrapped paragraph,
  so `grep 'Ruling:'` finds the whole thing — where the invoking skill
  logs rulings: `studio-state ledger "Ruling: <decision> — <why> — <cost
  if wrong>"`, or the SDD ledger, or the plan's `## Decisions` section
  when neither exists — and continue.
- **Allowed side effects:** commit; `git push` after every integrated
  task, so a crash loses at most one task; the run's one PR — when the
  invoking skill opens it (`game-dev:execute`'s finish does, as a draft
  while this mode is set), that PR is the run's PR and no second PR is opened;
  otherwise `gh pr create --fill --draft` when the plan is complete, based on
  the manifest's Target under a manifest run (`STUDIO_RUN` set; an
  integration run opens no story PR);
  when `STUDIO_RUN` is unset, the base is per `omega:local-merge` §3, unchanged (session mode and single-plan runs);
  `gh pr comment`; the handoff.
- **Merge rule**, in a studio (see *In a studio*) and outside one:
  - Never merge into `main` (the default branch) from a session: no session merges anything in any run mode; the runner lands.
  - In an integration run, nothing is merged into `main`, and the runner merges stories into `integration/<slug>`.
  - In a direct run, the runner merges into `main` only through `merge_command`.
  - In a single-plan run and in session mode, never merge into `main`; with `local-merge` set, its merge step is skipped and reported.
- **Forbidden:** any merge from a session (above); never force-push; never
  delete a remote branch; no destructive or security-sensitive operation;
  no reading or writing of secrets.
- **Hard stops:** the invoking skill's own — a destructive or
  security-sensitive operation the plan requires, or a plan too broken to
  follow.
  - Under `source=env`: `studio-state ledger "Stop: <reason>"`, then end
    the session. No handoff, no disarm — the runner reads the line and
    reports.
  - Session mode: run `omega:handoff` without its question (the current
    task finishes), disarm, then stop.
- **Completion:**
  - Under `source=env`: the invoking skill's unit ends the session (one
    unit per session under `--one`); the runner starts the next session or
    writes the report.
  - Session mode: run `omega:handoff`. Its file carries the morning report
    after *Where*: every ruling in order with its cost if wrong, the
    unverified items, the PR link, the resume prompt. Then disarm.
- **Disarm**, session mode only, after the handoff on either ending:
  `omega-mode clear autopilot`.

## What this changes, and what it never changes

Changes: when questions are asked, what happens when one would arise, and
which side effects run unattended. Never changes: the studio's stages and
gates, the reviewer per task, the tests.

## Red flags — phase 2 is about to break

| Thought | Reality |
|---------|---------|
| "This one question is quick" | No question is quick at 3 a.m. Rule and log. |
| "The user would obviously want it merged" | Never merge into `main`: no session merges in any run mode; the runner lands. Open the draft PR. |
| "I'll push at the end" | Push after every integrated task. |
| "Two options are equally fine, I'll just pick" | Picking is fine; picking *without a logged ruling* is not. |
| "I'll explain the cost in the next paragraph" | The cost if wrong goes on the Ruling line itself, or a plain grep for it fails. |
| "A file's already committed this way, drop the question" | Only the plan's `## Decisions` section retires a swept item — a commit or a ledger entry from a prior run does not. |
| "The plan is unclear, I'll stop and ask" | Unclear is a ruling; *broken* is a hard stop. Decide which, log it. |
| The hook block already says `autopilot` while questions are still open | Clear it (`omega-mode clear autopilot`); the mode is set only when the checklist passes. |
| "I'll start the next task while I'm here" | Under `--one`: one unit, then end. The runner starts the next session. |
| "Every plan is approved, I'll just run the first story here" | In a studio (see *In a studio*) nothing executes stories in this session: start the runner or print its command. |
| "The detached start failed, I'll try again" | Show the message, print the command, stop. |

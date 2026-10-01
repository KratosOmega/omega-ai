# game-dev Slim Pipeline — Design

Date: 2026-10-01
Status: Approved 2026-10-01
Issue: #9 — bundle 1 of 3. Bundle 2 is an overnight runner that starts a
fresh `claude-gd -p` session per unit of work; bundle 3 is the plan shape
(epic → story spec → just-in-time task files) and a plan falsifier.
Extends: `2026-09-13-game-studio-design.md` (its eight-stage workflow is cut
to three stages plus three on-demand commands; everything it says about
packaging, agents, `studio-state`, the ledger and the hooks applies unchanged
except where this spec quotes a line that changes)

## Purpose

The studio's pipeline costs too much and stops too often for the same
quality. Every stage ran in one long session, so each stage paid for every
stage before it: half of all spend was the main session re-reading its own
history. Between stages the user had to type the next command by hand, and
two stages after `execute` — a second whole-branch review and a scripted
playtest — mostly re-checked work `execute` had already checked.

This design makes three changes, and only these:

1. **Fewer stages.** The chain becomes `idle → brainstorm → plan → execute →
   idle`. `execute` absorbs what `review` and `ship` did at the end of a
   feature: a standalone final review, the gate, a short play list, the
   PROGRESS entry and a ready PR. `review`, `playtest` and `retro` become
   on-demand commands that never move the stage. `ship` is deleted.
2. **A fresh session per stage, by hand for now.** Every stage ends with
   `Next: run /clear, then /game-dev:<next>`, and a new studio hook warns —
   never blocks — when a stage command is typed into a session that already
   ran a different stage.
3. **Cheaper fix rounds.** A finding is fixed by a fresh agent, re-reviewed
   only when the finding was serious enough to need it, and never reviewed a
   third time.

Autopilot becomes the main mode later (bundle 2); this bundle makes the
manual chain short enough that autopilot has one stage to run.

Non-goals:

- It removes no gate. The spec and plan approvals stay (until bundle 3's
  falsifier), the per-task review stays, the tests and `Verify:` rules stay.
- It never merges. Execute opens a PR; the user plays the list and merges.
- It changes nothing outside the game-dev studio's own load path:
  `studios/game-dev`, `shared/omega` (loaded only by `claude-gd`), `tests/`
  and `docs/`. Nothing under `~/.claude` is read or written.
- No automatic `/clear`. That arrives with bundle 2's runner.

## Evidence

Stage audit of seven `claude-gd` sessions on phoenix, 2026-09-15..19,
≈$1,988 estimated at list price as input-equivalent tokens (ratios are
reliable, dollars rough):

| Stage | Cost share | Of which agents | Main-session context avg | What it caught |
|-------|-----------:|-----------------|-------------------------:|----------------|
| brainstorm | 5.4% | $22 of $108 | 250k | design decisions |
| plan | 9.5% | $50 of $189 | 356k | — |
| execute | 61.1% | $772 of $1,214 | 469k | the work, task reviews, final review |
| review | 9.9% | $84 of $197 | 457k | second whole-branch review: 0 findings in 2 of 4 features, new Importants in 2 of 4 (3 total); on KAN-1304, where execute ran no final review, a Critical |
| playtest | 4.7% | $13 of $94 | 486k | 56 items, 26 never played, 1 real bug (combo-mash stutter) |
| ship | 5.2% | $2.6 of $104 | 612k | 3 gate commands, the PR choice, PROGRESS |
| retro | 1.0% | $0.2 of $20 | 571k | 9 memories across 3 retros |

- 51% of all spend was the main session itself, because every stage ran in
  one session. Context when each stage *started*: brainstorm 109k (a fresh
  session starts at ≈62k), plan 369k, execute 440k (max 800k), review 595k.
- About ten stops per feature; four were the user typing the next stage
  command ("keep going with game-dev pipeline").
- KAN-1457 study (the user's own token rules): revived implementers were
  16.7% of spend; 88% of re-reviews found nothing new; standalone final
  reviews flagged an Important or Critical 79% of the time, against 22% when
  the final review was merged into the last task review.

## Decisions

| # | Decision | Ruled |
|---|----------|-------|
| 1 | Approach A: fold the stops into execute. The chain is `idle → brainstorm → plan → execute → idle`; `review`, `playtest`, `retro` are on-demand commands that never move the stage; `ship` is deleted | User, 2026-10-01 |
| 2 | Fresh session per stage, by hand: every stage's `Next:` line reads "run /clear, then /game-dev:<next>"; a new studio `UserPromptSubmit` hook warns (never blocks) when `/game-dev:brainstorm`, `plan` or `execute` is typed in a session that already ran a different stage. Automatic fresh sessions arrive with bundle 2's runner | User, 2026-10-01 |
| 3 | The plan approval gate stays until bundle 3 adds the falsifier; bundle 1 keeps four touchpoints: spec, plan, play list, merge | User, 2026-10-01 |
| 4 | B2 fix rounds in execute, overriding `superpowers:subagent-driven-development`'s resume-the-implementer default: a fresh agent of the task's Role gets the findings, `git diff <range>` and file:line slices, and runs the task's tests before handing back; re-review only after a Critical, 3+ Importants, or a production-bug fix; never after a Minor-only round; never a third review pass on the same scope; Minors batch into one final fix wave | User, 2026-10-01 |
| 5 | The final review is standalone (never merged into the last task review): `game-dev:reviewer` dispatched with model `"opus"`, whole branch against the spec — acceptance criteria met/unmet, the plan's `Verify: unit` tests, a "verify prior fixes" list of every fix commit, and the `studio-test` / `studio-lint` output | User, 2026-10-01 |
| 6 | Execute finishes without stopping: gate, play list, PROGRESS through the producer, push and a ready PR (draft under autopilot), state back to idle, then the report. The only stops left in execute: a destructive or security-sensitive operation, a plan too broken to follow, no Godot binary. Push and PR are no longer ask-first; merge is never done | User, 2026-10-01 |
| 7 | On demand: `/game-dev:review [scope]` (same reviewer brief, B2 fix rules, never touches stage); `/game-dev:playtest <what failed>` (free-text failures in, a bug per failure, a fix with a regression test, a push and one PR comment out; no script, no report file, no per-item question, no sign-off; a third failure on one item stops and suggests the backlog); `/game-dev:retro` (on demand only, no question batch, 0–3 memories from the ledger, never changes stage or clears pointers) | User, 2026-10-01 |
| 8 | `studio-state`: stages are `idle brainstorm plan execute`; the `last_playtest` key is removed (existing files keep an inert line; `init` stops writing it). An old stage value is reported by the router as `Stage: idle (was <x>, old pipeline)` with `/game-dev:brainstorm` next; `set` rejects old values | User, 2026-10-01 |
| 9 | The router and `hooks/bootstrap.md` list the three-stage chain plus the on-demand commands; freeform routes: "review it" → review, "feels wrong" → playtest, "what did we learn / retro" → retro | User, 2026-10-01 |
| 10 | Agents: the producer is dispatched by execute's finish (PROGRESS entry before merge, play list pending in place of "the playtest report it passed"); the playtester keeps only the bug method and returns the bug block (no script, no file); reviewer and feel-tuner change only if a reference breaks | User, 2026-10-01 |
| 11 | Autopilot gets two text edits only: phase 1 step 1 skips to the question sweep when the spec and plan are already approved and committed, and recommends arming from a fresh session (`/clear` first); completion's `gh pr create --fill --draft` defers to the invoking skill's PR step, so no second PR is opened. The heartbeat is unchanged (bundle 2 replaces it) | User, 2026-10-01 |
| 12 | Tests in bash under `tests/run_all.sh`: the stage chain, the state keys, the hook cases, the execute contracts, on-demand skills writing no stage, no `ship` reference anywhere, `requires.txt` consistent | User, 2026-10-01 |
| 13 | Live pressure scenarios are written now and run once the `claude-gd` login works (today it returns `403 oauth_not_allowed_for_organization`). Issue #6 is re-scoped to the new chain. Rollout is a `git pull` of the main checkout; no reinstall | User, 2026-10-01 |

## Design

### 1. Stage chain and state

`studios/game-dev/bin/studio-state` changes in these places and nowhere
else:

| Line | Today | After |
|------|-------|-------|
| 9-20 | the subcommand list in the header comment | adds `#   studio-state worktree        print the worktree that has the recorded branch checked out` |
| 22 | `# Keys: stage spec plan task last_playtest milestone` | `# Keys: stage spec plan task branch milestone` |
| 23-24 | `# Exit: 0 ok · 1 no .studio/ …` | adds `· 3 worktree: the branch exists but no worktree has it checked out` |
| 48 | `KEYS="stage spec plan task last_playtest milestone"` | `KEYS="stage spec plan task branch milestone"` |
| 49 | `STAGES="idle brainstorm plan execute review playtest ship retro"` | `STAGES="idle brainstorm plan execute"` |
| 53 | the `usage` line | adds `worktree` to the subcommand list |
| 129 | `last_playtest: -` (in the `init` heredoc, right after `task: -` at `:128`) | `branch: -` |
| 177 | `set_field "$key" "$val"` | for `branch` only: a file with no `branch:` line gets `branch: <value>` inserted right after its first `task:` line (no `task:` line either: the damaged-file error, naming `task:`); every other key keeps `set_field`'s damaged-file error (`:86`) |
| 253-256 | `reset`'s four `set_field` calls | adds `branch -`, written the way `set branch` writes it, so a file without the line gains it |
| new | — | a `worktree)` case, below |

`get`, `set`, `ledger`, `check` and `reset` are otherwise unchanged. `get
last_playtest` and `set last_playtest …` now fail as an unknown key (exit 1,
usage); after this change nothing calls either (the no-reference test in
§Testing pins it). `branch` takes any non-empty value, like `spec` and
`plan`; `-` clears it.

**`studio-state worktree`** finds the feature's checkout from any checkout
of the project:

1. Read `branch`. Empty (a `STATE.md` from before this change) or `-`:
   print `studio-state: no feature branch recorded` on stderr, exit 1.
2. `git show-ref --verify --quiet refs/heads/<branch>` fails: print
   `studio-state: branch <branch> no longer exists` on stderr, exit 1.
3. Read `git worktree list --porcelain` block by block. The first block
   that holds the line `branch refs/heads/<branch>`, no `prunable` line,
   and a path that is a directory: print its `worktree` path — absolute,
   and nothing else — on stdout, exit 0. It can be the main checkout, when
   the user checked the branch out there.
4. None: stderr is exactly two lines — `studio-state: no worktree has
   <branch> checked out`, then the command alone that makes one: `git
   worktree add <main checkout>/.claude/worktrees/<name> <branch>`, where
   `<name>` is the branch with each `/` turned into `-` and the path is
   absolute, so the command runs from any checkout. When a `prunable` block
   held the branch, the command is prefixed with `git worktree prune && `:
   git refuses to add a worktree for a branch that a stale entry still
   holds (checked with git 2.39.3: `fatal: 'feat/x' is already checked out
   at …`). Claude Code locks every worktree it creates, and git never marks
   a locked entry `prunable`; when the block was locked with its directory
   gone, the prefix is `git worktree unlock <path> && git worktree prune &&
   `. Exit 3.

Exit: 0 found · 1 no state, no branch recorded, or the branch is gone · 3
the branch exists but no worktree has it checked out.

The new worktree goes under `.claude/worktrees/` because `EnterWorktree`
with `path:` accepts any worktree `git worktree list` shows when called from
the launch directory, but only one under `.claude/worktrees/` when the
session is already in another worktree (the tool's own contract).

**Feature-checkout procedures**, stated once here and named elsewhere.
Skills cannot include one another, so each skill in parentheses carries a
copy, and `test_feature_checkout_copies` asserts every copy holds the same
key literals.

- **Default branch** (brainstorm, plan, execute, review, playtest): `git
  symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/`;
  without one, the first of `main` and `master` that exists.
- **Enter the feature checkout** (execute's resume, review, playtest): run
  `studio-state worktree`. Exit 0: when the printed path is not the current
  checkout (`git rev-parse --show-toplevel`), `EnterWorktree` with `path:
  <it>`; git fallback `cd <it>`. Exit 3: run the command on its stderr's
  second line, then enter the new worktree the same way. Exit 1: the
  caller's own rule (§4 §0, §5). If `EnterWorktree` refuses, stop and show
  its message; when another session holds the worktree, close that session
  first. Never `cd` into a worktree another live session is using.
- **Leave the feature checkout** (execute's finish; review and playtest
  when they entered): call `ExitWorktree` with `action: "keep"`
  unconditionally. It is a no-op that says so when no `EnterWorktree`
  session is active, and it is the only step that moves the directory
  `/clear` returns to: an `EnterWorktree` made before a `/clear` in this
  process is still active, though this conversation does not remember it.
  When it reports no active session and `git rev-parse --git-dir` differs
  from `git rev-parse --git-common-dir`, `cd` to the main checkout (the
  first `worktree` line of `git worktree list --porcelain`). Unless this
  command entered with `cd` itself, the session was launched in this
  worktree: put this line before the report's `Next:` line (or last): "This
  session started in the feature worktree, and /clear returns here: quit,
  then start claude-gd in `<main checkout>` before the next feature."
- **Finished-checkout guard** (brainstorm §0, plan §0, execute §0 on a new
  run, before any state write): when `studio-state get branch` names a
  branch (not `-`) that is not the default branch and equals `git branch
  --show-current`, stop with: "This checkout holds the previous, finished
  feature (`<branch>`). Leave it first: `ExitWorktree` with `action:
  "keep"`. When that reports no active worktree session, this session was
  launched here, and neither `ExitWorktree` nor `cd` outlasts the `/clear`
  the chain needs: quit and start `claude-gd` in `<main checkout>`. In the
  main checkout itself: `git switch <default branch>`. To start the next
  feature on this branch anyway, run `studio-state set branch -` first."
  Without studio state the guard is skipped like every other
  `studio-state` call.

Who writes `stage` after the change:

| Writer | Value | When |
|--------|-------|------|
| `brainstorm` | `brainstorm` | at classification, bounded or architectural work (`brainstorm/SKILL.md:44-45`, rewrapped onto one line, §2) |
| `plan` | `plan` | at its gate (unchanged, `plan/SKILL.md:117`) |
| `execute` | `execute` | in §0 (unchanged, `execute/SKILL.md:29`) |
| `execute` | `idle` | as the last state write of its finish (new) |
| `studio-state reset` | `idle` | abandon (unchanged) |
| `review`, `playtest`, `retro`, the router | — | never |

Who writes `branch`:

| Writer | Value | When |
|--------|-------|------|
| `execute` | `-` | §0, when a new run starts (§4) |
| `execute` | the feature branch | §0, after the ancestor check of a new run, or of a resume that found no `branch` (§4) |
| `studio-state reset` | `-` | abandon |
| everything else | — | never; execute's finish keeps it |

`branch` is read by `studio-state worktree` (execute's resume, review,
playtest, retro) and by the finished-checkout guard.

At the end of execute the pointers are left as they are except `task`:
`stage idle`, `task -`, and `spec`, `plan` and `branch` keep naming the
feature that was just finished. The next brainstorm overwrites `spec` at its
gate (`brainstorm/SKILL.md:214`), the next plan overwrites `plan` at its
gate (`plan/SKILL.md:117`), and the next execute clears `branch` when its
new run starts and records its own when it isolates. Keeping them is what
lets the on-demand commands find the finished feature's checkout and ledger
(§5).

### 2. Router and bootstrap

**`studios/game-dev/skills/studio/SKILL.md`.**

- `:18-19` — the header fields become `stage`, `spec`, `plan`, `task`,
  `branch`, `milestone` (`last_playtest` is dropped).
- `:46-53` — the paragraph explaining "from `execute` onward, each stage
  skill sets `stage` to the stage still to run" is replaced with: "Each stage
  sets `stage` to its own name while it works, and `execute` sets `idle`
  when its finish completes. `review`, `playtest` and `retro` are on-demand
  commands: they run at any stage and never change it."
- `:55-64` — the table becomes exactly:

  | `stage` | Next | Unless |
  |---------|------|--------|
  | `idle` | `/game-dev:brainstorm` | — |
  | `brainstorm` | `/game-dev:plan` | (today's `:58` text, unchanged) |
  | `plan` | `/game-dev:execute` | (today's `:59` text, unchanged) |
  | `execute` | `/game-dev:execute` (resume) | `task` is `N/N` — then it resumes at the final review and finish |
  | any other value (`review`, `playtest`, `ship`, `retro`: the old pipeline) | `/game-dev:brainstorm` | — report the state line as `Stage: idle (was <value>, old pipeline)` |

- After the table, one new paragraph: "On demand, at any stage:
  `/game-dev:review [scope]`, `/game-dev:playtest <what failed>`,
  `/game-dev:retro`. None of them changes `stage`."
- Freeform table: `:84` becomes `| "feels wrong / floaty / laggy /
  unresponsive / too fast / juice" | /game-dev:playtest with the user's text
  as the failure report |`; `:85` keeps routing to `/game-dev:review`; a new
  row after `:88`: `| "what did we learn / retro / lessons" |
  /game-dev:retro |`. The bug route (`:89`) is unchanged.

**`studios/game-dev/hooks/bootstrap.md`.** `:7-19` (the `## Stages` section)
is replaced by:

```markdown
## Stages

- `/game-dev:studio` — router: reads state, names the next stage, routes freeform text.
- `/game-dev:brainstorm` — clarify, classify, spec with GDD-lite sections, artifact, approval gate.
- `/game-dev:plan` — role- and verify-tagged tasks, producer scope cut, approval gate.
- `/game-dev:execute` — fresh role agent per task, reviewer after each, standalone final review, gate, play list, PROGRESS entry, PR; `--inline` for checkpoints.
- `/game-dev:scaffold` — new project from the engine template.

The chain is idle → brainstorm → plan → execute → idle. Run each stage in a fresh session: `/clear`, then the stage command. `/clear` ends the session, and that session's omega modes (reply, delegate, autopilot and the rest) end with it; type again the ones you want.

## On demand — never changes the stage

- `/game-dev:review [scope]` — the branch (or a range) against the spec; findings fixed by fresh agents.
- `/game-dev:playtest <what failed>` — what you saw fail goes in; a bug, a fixed commit with a regression test, a push and one PR comment come out.
- `/game-dev:retro` — durable lessons from the ledger into studio memory.

A command that is not in your skill list is not installed yet: say so and name it rather than improvising it.
```

`:3-5` (Precedence) and `:21-23` (State) are unchanged.

**`studios/game-dev/hooks/session-start.sh:86`** (Open question 4) prints
`Studio state: stage <value>` for a value in `idle brainstorm plan execute`,
and `Studio state: stage idle (was <value>, old pipeline)` for any other
value, so the bootstrap line and the router agree.

**`studios/game-dev/skills/brainstorm/SKILL.md`.**

- `:44-45` is rewrapped so `studio-state set stage brainstorm` sits on one
  line; the text is unchanged. Today the line break falls inside the command
  (`set stage` / `brainstorm`), so the rewritten `test_stage_chain` would
  find no stage value in brainstorm.
- §0 (`:14-22`) gains one bullet: the finished-checkout guard (§1), at
  every stage.
- `:224-227` — "and tell the user the next command is `/game-dev:plan`"
  becomes "and print `Next: run /clear, then /game-dev:plan`". "Do not
  invoke the next command yourself." (`:226-227`) stays.

**`plan/SKILL.md`.** §0 (`:9-19`) gains the same guard bullet. `:130-132`
— "and tell the user the next command is
`/game-dev:execute` (…)" becomes "and print `Next: run /clear, then
/game-dev:execute` (subagent-driven by default; `--inline` for checkpointed
execution)". "Do not invoke it yourself." (`:131-132`) stays.

### 3. The stage guard hook

New file `studios/game-dev/hooks/stage-guard.sh`, executable, POSIX `sh`,
self-contained (copy mode has no `lib/`), **exit 0 on every path**: no `set
-u` — every expansion is written `${x:-}` — and `trap 'exit 0' EXIT` near the
top. The reason: exit 2 from a `UserPromptSubmit` hook blocks the prompt and
erases it (hooks reference, below), and under `set -u` an unbound variable
aborts dash with status 2. Registered in `studios/game-dev/hooks/hooks.json`
as a third key beside `SessionStart` and `PreToolUse`:

```json
"UserPromptSubmit": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/stage-guard.sh\""
      }
    ]
  }
]
```

Contract, from the Claude Code hooks reference
(<https://code.claude.com/docs/en/hooks>), verified 2026-10-01:

- `systemMessage` is a common output field every hook may return — "Warning
  message shown to the user" — and `UserPromptSubmit` supports it alongside
  `decision`/`reason` and `hookSpecificOutput.additionalContext`.
- `transcript_path` is a common input field. The transcript is written
  asynchronously and may lag the in-memory conversation, so the current turn
  may be missing from it. That is harmless here: an earlier stage ran in an
  earlier turn.
- Plain stdout from a `UserPromptSubmit` hook is **added to Claude's
  context**. So the hook prints nothing at all on every silent path, and on
  the warning path prints exactly one JSON object and nothing else.

Algorithm:

1. `input="$(cat 2>/dev/null || true)"`.
2. Flatten as `shared/omega/hooks/prompt-submit.sh:36` does: real newlines
   and tabs to spaces, and the JSON escapes `\n` and `\t` to spaces.
3. Take the prompt's own value as `prompt-submit.sh:44-46` does: the
   `"prompt"` value up to the next `"`, leading whitespace removed.
4. If the flattened input contains `<scheduled-task` anywhere: exit 0
   silently.
5. The typed stage, from that value, in either of two shapes:
   - **Raw** — the value matches
     `^/game-dev:(brainstorm|plan|execute)([[:space:]]|$)`. This is the shape
     Claude Code 2.1.286 sends: it builds the hook input
     (`hook_event_name:"UserPromptSubmit",prompt:<text>`) from the text as
     typed, and builds the `<command-message>`/`<command-name>` envelope only
     for the messages it writes to the transcript (traced in the installed
     2.1.286 binary, 2026-10-01).
   - **Envelope** — kept as a second accepted shape for Claude Code versions
     that send it: after stripping one leading
     `<command-message>…</command-message>` and the whitespace after it
     (`prompt-submit.sh:50-51`), the value begins with `<command-name>`, and
     the name inside it matches `/game-dev:(brainstorm|plan|execute)` with
     optional surrounding whitespace.

   Anything else — an ordinary prompt, a prompt that mentions a stage
   command after other text, `/game-dev:studio`, `/game-dev:review`,
   `/game-dev:playtest`, `/game-dev:retro`, any other plugin's command —
   exits 0 silently.
6. `transcript_path` from the input (`"transcript_path"` value up to the
   next `"`). Empty, missing, or not a readable regular file: exit 0
   silently.
7. One `grep -oE` pass over the transcript for any of these three anchored
   forms, each followed by mapping the match to its stage name:
   - `"<command-message>game-dev:(brainstorm|plan|execute)</command-message>`
   - `"<command-name>/game-dev:(brainstorm|plan|execute)</command-name>`
   - `"name":[[:space:]]*"Skill",[[:space:]]*"input":[[:space:]]*\{[[:space:]]*"skill":[[:space:]]*"game-dev:(brainstorm|plan|execute)"`

   The leading `"` anchors each form at the start of a JSON string, which is
   where a typed command's envelope and a `Skill` tool call's input begin in
   the transcript (checked against phoenix transcript
   `6f1a4b27-….jsonl`: `"<command-message>game-dev:plan</command-message>`
   and `"name":"Skill","input":{"skill":"game-dev:execute"`). A mention of a
   command in prose — the bootstrap's `` `/game-dev:plan` — role- …`` line,
   a skill's "the next command is `/game-dev:plan`" — does not match.
8. Drop matches equal to the typed stage; keep the last remaining one (the
   most recent different stage). None left: exit 0 silently.
9. Print exactly one line and exit 0:

   ```
   {"systemMessage":"game-dev: this session already ran /game-dev:<prior> — its context is carried into <typed>. Run /clear, then /game-dev:<typed>."}
   ```

   For example, `/game-dev:execute` typed after `/game-dev:plan` prints:
   `game-dev: this session already ran /game-dev:plan — its context is
   carried into execute. Run /clear, then /game-dev:execute.` Both names come
   from the fixed set, so the message needs no JSON escaping. The typed
   command's arguments are not repeated in the message.

What it covers and what it does not: a typed stage command only. A stage the
router invokes through the `Skill` tool is not a typed prompt and fires no
`UserPromptSubmit`; but it is recorded in the transcript, so a later typed
stage in that session is warned. After `/compact` the transcript keeps the
earlier stage's envelope and the warning still fires — the summary is
smaller than the history, but it is still carried. The largest phoenix
transcript is 7.5 MB; the hook reads it in one `grep` pass.

The hook tests feed the raw shape; only the live check M2 (Acceptance
criteria) proves which shape a real session sends.

### 4. Execute

`studios/game-dev/skills/execute/SKILL.md`. §2 (who implements) and §3
(verify rules) are unchanged. §0 changes as below.

**Description** (`:3`) becomes: "Use when an approved plan exists —
dispatches a fresh role agent per task with a reviewer after each, a
standalone final review, then the gate, a play list and a ready PR; pass
--inline for checkpointed inline execution."

**§0 Preconditions and isolation.** The checks at `:15-28` (the plan and its
`plan approved` line, the committed spec and plan, the clean gate inputs,
reading the plan and spec) are unchanged. Around them:

1. **Which run this is.** Before `:29` writes `stage execute`, read `stage`,
   `task` and `branch`:
   - `plan` — a new run. First the finished-checkout guard (§1) on the
     `branch` just read; it stops before any state write. Then `studio-state
     set branch -` beside `:29`'s `studio-state set stage execute`, before
     isolating (the skill says "A new run clears `branch`"). A stop before
     (c) — the ancestor check's `git merge --ff-only` failing on a local
     default branch that has diverged from `origin` (the usual case after a
     PR merged on GitHub without a `git pull`), or the user declining a
     worktree — then leaves `stage execute` with no `branch`. The re-run is
     a resume that isolates as today, never one that enters the previous
     feature's worktree.
   - `execute` — a resume. So are `review`, `playtest` and `ship`, the old
     pipeline's mid-way values (§Data and state migration); they have no
     `branch`.
   - `idle`, `brainstorm` or `retro` — no approved plan is waiting to run (at
     `idle` the pointers still name the finished feature, §1): stop and name
     `/game-dev:studio`.
2. **Isolation** (`:34-41`).
   - (a) A resume: **Enter the feature checkout** (§1); never create a
     second worktree. Exit 1 with no `branch` (an old value, or a new run
     that stopped before (c)): isolate as today — unless `task` is past
     `0/N` and the current checkout's feature ledger has no `T<n> complete`
     line: then stop, "run `/game-dev:execute` from the feature's worktree"
     (a legacy run started from the main checkout would get an empty
     worktree). Exit 1 because the branch is gone: stop and say so; restart
     with `studio-state set task 0/<N>` and `studio-state set branch -`, or
     abandon with `/game-dev:studio`.
   - (b) A new run isolates as today.
   - The ancestor check for the spec's and plan's hashes (`:36-41`), its
     `git merge --ff-only` included, runs after every isolation, a resume's
     included.
   - (c) Only after that check: for a new run, and for a resume that found
     no `branch`, run inside the worktree `studio-state set branch "$(git
     branch --show-current)"`. A new run — or such a resume at `task 0/N`,
     a new run restarted — then records its base and commits it at once:
     `studio-state ledger "base <noted branch>" && git add .studio/ledger &&
     git commit -m "chore(studio): ledger"`. Never write the ledger before
     the fast-forward: an untracked ledger file makes it abort.
3. **The base** — the PR's base, and the anchor for `git merge-base` in §4a,
   §5 and §7 — is the noted branch on a new run. On a resume it is the
   feature ledger's last `base <branch>` line, because the noted branch can
   be the feature branch itself after a stop that left the session in the
   worktree (§7 step 1). A ledger without one (a run begun before this
   change) uses the default branch (§1).
4. **Where to start**, once isolated:
   - `task` is `N/N`: every task is complete. Do not start SDD's task loop;
     go to §5, or to §7 when the feature ledger already has a `final review
     done` line (a stop in the finish).
   - `task` is `k/N` with k < N and SDD finds no progress ledger for this
     plan (its "start your own, fresh" case,
     `subagent-driven-development/SKILL.md:141-149`): seed it before the
     loop — its identity line, `# SDD ledger — plan: <plan path>`, then one
     `Task <n>: complete (commits <range>, review clean)` line (its `:437`
     format) for each `T<n> complete <range>` line of the feature ledger
     (written by `execute/SKILL.md:131`). The progress ledger is git-ignored
     scratch in the worktree (`:136-139`), so a worktree re-made by `git
     worktree add` (exit 3) or cleaned has none, and without the seed SDD
     would restart at Task 1 while `task` says otherwise. (At `N/N` the old
     pipeline's finish had deleted it, `:482-485`; the first rule covers
     that.)

SDD line numbers here and below are superpowers 6.4.1
(`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1`);
6.3.0, the version `claude-gd` loads
(`~/.claude-gamedev/plugins/cache/…/superpowers/6.3.0`), has the same lines
at the same numbers, without the `bash` before `scripts/…`.

**Mode** (`:45-48`): "follow its loop exactly: fresh implementer per task,
task review after each, fix rounds, final whole-branch review, ledger. The
studio rules in §2–§5 layer on top of it." becomes "follow its loop for the
per-task cycle: fresh implementer per task, task review after each, ledger.
Its fix loop, its final review and its last step are replaced by §4a, §5 and
§7 below. The studio rules in §2–§7 layer on top of it." `--inline`
(`:50-55`): §3, §5, §6 and §7 apply in inline mode too, and so do §4a's
re-review and no-third-pass rules (3 and 4); §2's dispatch and §4 do not,
and the session itself makes each fix where §4a and §5 dispatch a fresh
agent.

**§4 Who reviews** keeps `:106-123` (the per-task reviewer and its
checklist). `:125-126` ("The fix loop is subagent-driven-development's.") is
replaced by §4a.

**§4a Fix rounds (both the per-task loop and the final fix wave).** The
section opens with this override line, verbatim:

> This overrides `superpowers:subagent-driven-development`'s fix loop
> (rounds 1–3 resume the original implementer, a scoped re-review every
> round, five rounds): never resume or message an implementer that has
> handed back.

Then:

1. **Minor findings** never start a round. They are recorded as SDD records
   them (`Task <N>: minor (deferred): <one-liner>` in its progress ledger)
   and all go to the one final fix wave after the final review (§5).
2. **A round** — for the Critical and Important findings of one review
   pass — is one dispatch of a **fresh** agent of the task's `Role:` (§2's
   dispatch rule, including the C# exception). Its brief carries: the
   findings verbatim; the diff as a file, never pasted inline — SDD's
   review package for the task's commit range (`bash scripts/review-package
   <plan> <BASE> HEAD` from SDD's skill directory prints the file's path;
   the file holds `git log --oneline`, `git diff --stat` and `git diff -U10`
   for the range; `subagent-driven-development/SKILL.md:316-321`), which is
   decision 4's `git diff <range>` handed over as SDD hands diffs over; the
   file:line slices each finding cites (the cited line ± 20 lines); the task
   text and the spec sections it cites; "fix these findings only; one
   commit, subject `fix(T<n>): <summary>`; run the task's tests — the
   `Verify: unit` test files the task names, then `studio-test` — and paste
   the summary line before handing back".
3. **Re-review** — one scoped dispatch of `game-dev:reviewer` over the fix
   commit's range (its review package), with the findings list — happens
   only when the round's findings included a Critical, or three or more
   Importants, or the fix is a production-bug fix: it changes lines that
   already existed at `git merge-base <base> HEAD`, to correct a defect
   there. Otherwise the round is accepted on the fixer's test output.
4. **Never a third pass.** The first review of a scope is pass 1, a
   re-review is pass 2. A Critical or Important still open after pass 2 gets
   one last fresh fix dispatch (same brief) and no further review; whatever
   that fixer reports it could not close is parked: `studio-state ledger
   "T<n> Ruling: parked — <finding> — <why> — <cost if wrong>"` (or
   `Ruling: parked — …` for the final scope). Every fix commit is re-checked
   by the final review's verify-prior-fixes list.
5. Every finding that changed the code is still ledgered as today:
   `T<n> Review: <one line>` (`:136`).
6. A task is complete — `set task n/N`, `T<n> complete` — when its review is
   clean, its last round was accepted under rule 3, or what remains is
   parked under rule 4.

**§5 Final review** (new section). After the last task completes, and as
its own dispatch — never folded into the last task's review:

1. Run `studio-test` and `studio-lint` fresh; keep both outputs.
2. Build the verify-prior-fixes list from the reserved fix scopes this
   design gives fix commits: `git log --format='%h %s' <merge-base>..HEAD`,
   keeping the lines that match `^[0-9a-f]+
   fix\((T[0-9]+|final|gate|review|B[0-9]+)\)` (`grep -E`). A plan task's
   own `fix(…)` commit — a bug-fix feature — is not on the list.
3. Dispatch `game-dev:reviewer` with `subagent_type: "game-dev:reviewer"`
   and `model: "opus"` (the agent file keeps `model: inherit`; the dispatch
   parameter overrides it). This replaces SDD's final reviewer
   (`requesting-code-review`'s `code-reviewer.md`). The skill names that
   package without the `superpowers:` prefix: a prefixed name would need a
   `requires.txt` line (`test_external_references_declared`,
   `studio_test.sh:80-93`). The brief:
   - `Scope: branch <name> vs <base>`;
   - the review package for `<merge-base>..HEAD`, as SDD's final review
     gets one (`subagent-driven-development/SKILL.md:447-451`);
   - the spec path and the project `CLAUDE.md` path — report every
     acceptance criterion as met or unmet, per the agent's own `Spec
     compliance: met: …; unmet: …` line;
   - the plan path — check every `Verify: unit` task's test;
   - "Verify prior fixes": the list from step 2 — for each commit, confirm
     the finding it fixed is closed; a fix that did not close its finding is
     a finding of the original severity;
   - SDD's deferred-minor and parked lines — triage which must be fixed
     before merge;
   - the `studio-test` and `studio-lint` output from step 1;
   - "review only — do not fix".
4. Ledger: `studio-state ledger "Review: final — <Findings line>; unmet:
   <list or none>"`.
5. **The final fix wave**: every Critical, Important and must-fix Minor from
   the final review, plus the deferred Minors, in one fresh dispatch per
   owning role (the `Role:` of the plan task whose `Files:` names the file;
   `game-dev:gameplay-programmer` when none does) — usually one dispatch,
   with §4a rule 2's brief. Commit subject `fix(final): <summary>`.
   Re-review per §4a rule 3 (a Minor-only wave is never re-reviewed); never
   a third pass (§4a rule 4).
6. `studio-state ledger "final review done"`, then commit the ledger: `git
   add .studio/ledger && git commit -m "chore(studio): ledger"`. The finish
   then starts from a clean ledger, so a re-run after a stop in §7 passes
   §0's clean-tree check and resumes at §7 (§0 step 4).

**§6 State** (today's §5, `:128-138`) is unchanged except `:130` ("After
each task's review is clean", now "When a task is complete (§4a rule 6)")
and its stop paragraph. `:140-143` ("Stop only for the four reasons
subagent-driven-development names: an irreversible or destructive
operation, a security-sensitive action, a side effect outside the worktree
(merge, push, publish), or a plan too broken to follow.") becomes:

> Stop only for: an irreversible, destructive or security-sensitive
> operation; a plan too broken to follow; no Godot binary (`studio-test` or
> `studio-run` exit 2); the test framework not installed (`studio-test`
> exit 3). Pushing this branch and opening its PR are not ask-first side
> effects; merging is never done. Everything else is a ruling.

(The last stop is Open question 2.)

**§7 Finish** replaces `:145-160` and SDD's last step (its branch-finishing
skill is never invoked; the existing test that execute does not name that
skill stays). It runs once §5 is done, with no question to the user:

1. **Gate.** Invoke `superpowers:verification-before-completion` and run,
   fresh, from the worktree root, each with its summary line shown in the
   report:
   - `studio-test` — exit 0;
   - `studio-lint` — exit 0, or exit 3 (gdtoolkit not installed: noted in
     the gate line, not red);
   - `studio-run --seconds 10` — exit 0 (it exits 1 on `SCRIPT ERROR` or
     `ERROR:` in the run log).

   Exit 2 from `studio-test` or `studio-run`: stop and show the printed
   message — usually `GODOT_PATH` is unset; `studio-dispatch` also exits 2
   when it finds no studio root, engine or adapter
   (`bin/studio-dispatch:13`, `:38-54`) — and do not set `stage idle`. Exit
   3 from `studio-test`: stop with the printed hint. A stop here leaves the
   session in the worktree; a re-run resumes in place, at the gate (§0).
   Any other non-zero exit is a red gate: one fresh fixer (the owning role
   per §5 step 5, with the failing output) commits `fix(gate): <summary>`,
   then the whole gate re-runs. After the third red run the finish
   continues with the PR opened as a **draft**, the gate line showing the
   failure, and `studio-state ledger "Ruling: gate red after three fix
   rounds — <failing command and line> — <cost if wrong>"` (Open question
   6).
2. **Play list.** Built in the main session, no agent: every `T<n> Playtest
   item:` and `T<n> Visual:` line in `studio-state show`, and every row of
   the spec's `## Feel targets` whose check column says `playtest`, merged
   where two describe the same check. Each item is one line, `P<k> <do> →
   <expect> → fail looks like: <fail>`. Up to five items: all of them. More
   than five: the five that cover acceptance criteria and feel targets lead
   as `P1`–`P5`, the rest follow under `Also:` numbered on from `P6`. No
   source lines: the list is the single line `nothing to play`. Each item is
   recorded: `studio-state ledger "P<k> Play: <item text>"`.
3. **PROGRESS.** When the project has `docs/game-dev/PROGRESS.md`, dispatch
   `game-dev:producer` (`subagent_type: "game-dev:producer"`) with the plan
   path, the spec path, the feature ledger's absolute path
   (`<worktree>/.studio/ledger/<slug>.md` — the producer has no Bash, so it
   reads the file instead of running `studio-state show`), the play list,
   the branch name and the PROGRESS path. It adds the entry on the branch
   and reports `gate met: <current> → <next>` or `gate not met: …`. Commit
   it: `git add docs/game-dev/PROGRESS.md && git commit -m "docs(progress):
   <topic>"`. On `gate met`: `studio-state set milestone <next>`. Without
   the file: skip this step and say so in the report.
4. **Push and PR.** When `<branch>` is the default branch (§1; the user
   consented to work in place, `:41`), push nothing and open no PR: the
   report says the work is committed locally on `<branch>`; step 5's line
   is `shipped <branch> (local, default branch)`. Otherwise `git push -u
   origin <branch>`, then `gh pr view --json url` on the branch: when a PR
   exists, it is the PR (no second one). Otherwise `gh pr create --base
   <base> --title "<spec title>" --body-file <body file>`, adding
   `--draft` when `omega-mode show` lists `autopilot`, when `omega-mode
   show` fails (it exits 1 without `CLAUDE_CODE_SESSION_ID`: `shared/omega/bin/omega-mode:39`, `:56`; an
   unknown mode counts as autopilot), or when step 1 ended red. The body
   file is `"$(git rev-parse --git-dir)/game-dev-pr-body.md"` — inside the
   repository's metadata, never committed — and holds, in order: the spec's
   `## Purpose`; `## Acceptance criteria` as a `- [ ]` checklist; `## Play
   before merging` (the play list); `## Rulings` (every `Ruling:` line of
   the feature ledger, in order, each with its cost if wrong); the final
   review verdict line; the gate line (`Gate: studio-test <summary> ·
   studio-lint <exit and summary> · studio-run <exit>`). No `origin`
   remote, `gh auth status` failing, a rejected push (never force-push) or a
   failed `gh pr create`: keep the body file, say which failed and print the
   body path, and continue. Never merge.
5. **State.** `studio-state ledger "shipped <PR url, or the branch name when
   there is no PR>"`; commit the ledger (`git add .studio/ledger && git
   commit -m "chore(studio): <topic> finished"`) and push it when step 4
   pushed; `studio-state set stage idle`; `studio-state set task -`.
   `spec`, `plan` and `branch` are left as they are.
6. **Leave the feature checkout** (§1). The worktree and its branch stay
   on disk for `/game-dev:playtest` and `/game-dev:review` (§5). This
   replaces the exit `ship`'s branch-finishing skill used to make. Without
   it, `/clear` returns the session to the worktree — in Claude Code
   2.1.286 `EnterWorktree` moves the session's original directory and
   `/clear` resets to it — and `superpowers:using-git-worktrees` skips
   creation inside a linked worktree, so the next feature would be
   specced, planned and built on this branch and pushed into this PR.
7. **Report**, in this order: the PR link (or the saved body path and the
   reason); the play list; the rulings, each with its cost if wrong; the
   final review verdict line; the gate line; and the last line, verbatim:

   ```
   Next: play the list; merge when it passes; report failures with /game-dev:playtest <what failed>; /clear before the next feature.
   ```

### 5. On-demand commands

**Feature checkout** (shared by review and playtest; retro reads through it
without entering): **Enter the feature checkout** (§1), and say which
checkout. Exit 1 — no feature branch is recorded, or it is gone: ask the
user once which checkout to use, naming what was found (the `branch` value,
or that none is recorded, and the `git worktree list` paths). The skill
text says "ask", not the tool's name, so the playtest contract test holds.

**Which feature.** After the lookup, check that the checkout holds the
ledger of the feature `spec` names: `<checkout>/.studio/ledger/<slug>.md`
(slug as `studio-state` derives it) exists. When it does not, `spec` and
`branch` name different features: the next brainstorm's gate has moved
`spec`, and every ledger line written there would land in a ledger named
for the next feature. Review and playtest then stop with "the studio
pointers now name `<spec>`; the finished feature is `<branch>` — fix it on
that branch by hand, or run this after `<spec>`'s finish" (retro: below).
Playtest also stops at `stage execute`: the feature in progress has no PR
and no play list yet. Before the first
fix dispatch, review and playtest run `gh pr view --json state` on the
branch. On `MERGED` or `CLOSED`, they dispatch no fixer and push nothing.
They report the findings or bugs, and name the router's bug route (or
`/game-dev:brainstorm`) for a fix that must reach the base.

Every brief to a dispatched agent names the checkout's absolute path and
tells the agent to work there: an agent starts in the session's working
directory. Neither command commits on the default branch (§1): on it,
review reports its findings only, and playtest asks the user where the
fixes go before dispatching a fixer. At its end, a command that entered a
worktree runs **Leave the feature checkout** (§1). Review's explicit scope
argument, when it is a branch or a range, skips the lookup; review then
fixes only when HEAD is that branch (or the range ends at HEAD), and
otherwise reports only.

**`/game-dev:review [scope]`** — `studios/game-dev/skills/review/SKILL.md`,
rewritten in place.

- Description (`:3`): "Use when a branch or commit range needs a
  spec-compliance and Godot best-practice review on demand — at any stage,
  without changing it."
- §0 scope: the feature checkout first (above), unless the argument is a
  branch or a range. Then the argument when given
  (a range, a branch, a task number, a path list); otherwise the whole
  branch, `git merge-base <base> HEAD` to `HEAD`, where `<base>` is the PR's
  base (`gh pr view --json baseRefName`), else the feature ledger's last
  `base` line (§4 §0), else the default branch (§1). `:21`
  (`studio-state set stage review`) is deleted.
- §1 baseline: unchanged (`:23-32`).
- §2 dispatch: the same reviewer brief and dispatch as execute's final
  review (§4, §5 steps 2–3, including `model: "opus"` and the review
  package), with the scope from §0 and the verify-prior-fixes list over
  that scope. The skill text keeps the literal `subagent_type:
  "game-dev:reviewer"` (`studio_test.sh:211` asserts it) instead of only
  pointing at execute, and, like execute, names `requesting-code-review`
  without the `superpowers:` prefix if it names it at all. Review does not
  load SDD, so its review package is built the way SDD does without bash
  (`subagent-driven-development/SKILL.md:318-320`): `git log --oneline`,
  `git diff --stat` and `git diff -U10` for the range, redirected to one
  uniquely named file under `"$(git rev-parse --git-dir)"`.
- §3 fixes: execute's §4a rules — fresh agent of the owning role, the diff
  as that file, re-review only after a Critical, 3+ Importants or a
  production-bug fix, never a third pass, Minors in one wave — with commit
  subjects `fix(review): <summary>`. On the default branch there is no fix
  dispatch. `:59-63` (re-dispatch until clean, three rounds then stop) is
  deleted. Deferral to the plan's `## Backlog` (`:65-66`) is unchanged.
- §4 state: `studio-state ledger "Review: <scope> — <Findings line>; <m>
  fixed, <k> deferred"`, committed on the feature branch with the fixes
  and any `## Backlog` deferral: `git add .studio/ledger <plan path> && git
  commit -m "chore(studio): ledger"`. When
  the branch tracks a remote (`git rev-parse --abbrev-ref @{u}` succeeds),
  push the fix commits and that commit. On the default branch: no ledger
  line and no commit. `:71` ("review clean") and `:72` (`studio-state set
  stage playtest`) are deleted. Print the verdict line and the fix commits,
  then **Leave the feature checkout** (§1) if §0 entered one. `:82-83`
  (the rule naming the branch-finishing skill and "the ship stage") is
  deleted.

**`/game-dev:playtest <what failed>`** —
`studios/game-dev/skills/playtest/SKILL.md`, rewritten whole (today's
`:1-115`: script, per-item questions, report file, sign-off, `set stage
ship` all go).

- Description: "Use when the user played the build and reports what failed —
  turns each failure into a bug, fixes it with a regression test, pushes,
  and comments on the PR."
- No text after the command: print one example (`/game-dev:playtest dash
  clips the wall at full speed`) and stop.
- Find and enter the feature checkout (above). Split the text into
  failures, one per distinct observed problem; when two complaints may be
  one bug, treat them as one and say so.
- Per failure:
  1. **Repeat check.** Dispatch `game-dev:playtester`
     (`subagent_type: "game-dev:playtester"`) with the checkout's path, the
     failure text, the spec path, the plan path, the `P<k> Play:` and `B<n>`
     ledger lines, the next free bug number (one above the highest `B<n>` in
     the ledger), and "return the bug block; write no file". It returns the
     bug block whose title ends `(from P<k>)` for a play-list item, `(from
     B<m>)` for a repeat of an earlier bug outside the list (B<m> being the
     first bug of that chain), or `(from report)` otherwise.
  2. **Third failure.** Count the item's earlier failures in the ledger: for
     `(from P<k>)`, the `B` lines tagged `(from P<k>)`; for `(from B<m>)`,
     the line `B<m>` itself plus the lines tagged `(from B<m>)`. `(from
     report)` is never counted — it is a first report, shared by unrelated
     failures. When the count is already 2 or more, this is the third
     failure (or a later one): dispatch no fixer; after the other failures,
     suggest moving it to the plan's `## Backlog` with the user's reason,
     and move it only on the user's word.
  3. **Fix.** Dispatch `game-dev:feel-tuner` when the bug concerns a feel
     target (latency, forgiveness, acceleration, timing, camera, feedback),
     otherwise `game-dev:gameplay-programmer`, with the checkout's path, the
     bug block and the spec section. The brief keeps today's `:72-79`:
     follow `superpowers:systematic-debugging` first; when the bug's
     `Regression test` line says `unit`, write that test first
     (`superpowers:test-driven-development`) and see it fail on the bug;
     fix; run `studio-test`; commit `fix(B<n>): …`; report the commit and
     the hypothesis (feel-tuner) or the root cause (gameplay-programmer).
  4. `studio-state ledger "B<n> <title> — <commit, or backlog suggested>"`.
- After the last failure: `studio-test` once, fresh. Commit the ledger
  lines on the feature branch with the fixes and any `## Backlog` move:
  `git add .studio/ledger <plan path> && git commit -m "chore(studio):
  ledger"`. Push. One `gh pr comment` on the
  branch's PR listing each fix (`B<n> <title> — <commit>`), the play-list
  items to replay (each fixed `P<k>`, plus any item the fix touched), the
  parked items, and the `studio-test` summary line. No PR or no remote: the
  fixes stay committed locally and the comment text is printed instead.
  Then **Leave the feature checkout** (§1) if this command entered one.
- Never: a script, a report file, a question per item, a sign-off, a stage
  change, a commit on the default branch. The feel-fix rule stays: one
  variable per hypothesis (today's `:114-115`).

**`/game-dev:retro`** — `studios/game-dev/skills/retro/SKILL.md`. Retro is
read-only on the repository: it enters no checkout, writes no ledger line
and commits nothing. It writes only the studio memory (`:83-85`, unchanged).

- Description (`:3`): "Use when you want the lessons of recent work kept —
  on demand at any stage; harvests ledger rulings, reviews and bugs into
  studio memory."
- §0 (`:16-19`) becomes: read `studio-state show` (`STATE.md` with its own
  ledger, then the current checkout's feature ledger). When `studio-state
  worktree` exits 0 and prints a different checkout, read the feature
  ledger there instead — `<path>/.studio/ledger/<slug>.md`, the slug
  derived from `spec` as `studio-state` derives it (basename, no `.md`, no
  leading date; `studio-state:95-99`); at exit 3, read `git show
  <branch>:.studio/ledger/<slug>.md` — so the lines of an unmerged feature
  are harvested. When that ledger does not exist (§5's which-feature
  check), read only `STATE.md`'s ledger and say so. Take every `Ruling:`,
  `Review:` and `B<n>` line; read the spec only to understand a line.
  `:18` (playtest reports) and `:19` (`studio-state set stage retro`) are
  deleted.
- §1 (`:21-25`, the question batch) is deleted.
- §2 durability filter (`:27-38`) and §3 write (`:40-69`) are unchanged.
  A second retro reads the same lines (there is no marker line, and the
  skill must not name the old one: `test_retro_contract` forbids it); §3's
  existing rule — read `MEMORY.md` first and "update an existing file
  instead of duplicating it" (`:64-66`) — is what skips a lesson already in
  the studio memory.
- §4 (`:71-79`): `:73` (`studio-state ledger "retro written <n> memories"`)
  and `:74-75` (`set stage idle`, `set spec -`, `set plan -`, `set task -`)
  are deleted; the sync-memory reminder stays; the last line is `Next: run
  /clear, then` and the router's next command for the current stage (§2's
  table).
- Rules `:86-87` ("Three files a retro is typical; ten is a sign …")
  become "Zero to three memories. More than three means the filter in §2
  was skipped."
- Scope: the recorded feature's ledger and `STATE.md`'s ledger. Earlier
  features' ledgers are not read (Open question 5).

### 6. Ship removal

`studios/game-dev/skills/ship/` is deleted. Its duties move:

| Ship did | Now |
|----------|-----|
| refused without `playtest signed off` | gone — the play list is played before merge, by the user |
| three gate commands with evidence | execute §7 step 1 |
| `superpowers:finishing-a-development-branch` (merge / PR / keep) | execute §7 step 4: always a PR, never a merge |
| left the feature worktree (through that skill) | execute §7 step 6: Leave the feature checkout (§1) |
| producer → PROGRESS, milestone | execute §7 step 3 |
| `shipped <ref>` ledger line | execute §7 step 5 |
| `set stage retro` | gone — retro is on demand |

`studios/game-dev/requires.txt:7` (`skill
superpowers:finishing-a-development-branch`) is removed: no studio file
names that skill after this change. `superpowers:verification-before-
completion` (`:6`) stays; execute §7 names it. The doctor's tally becomes
`superpowers: 7 of 7 resolved`.

`shared/omega/skills/local-merge/SKILL.md:23-26` lists "a studio's ship
stage" among the steps that hand the merge to the user. It becomes:

> While `local-merge` is set, any step that would wait for GitHub checks or
> hand the merge to the user — `superpowers:finishing-a-development-branch`
> when installed, the user saying "merge it" — follows this procedure
> instead. A studio's finish that opens a PR for the user to play and merge
> is not such a step; the merge starts when the user says so.

(Open question 1.)

`README.md:71-75` (Open question 3) — the execute, review, playtest, ship
and retro rows — become these four rows; the ship row is deleted:

```markdown
| `/game-dev:execute` | Fresh role agent per task, reviewer after each, a standalone final review on Opus, the gate, a play list and a ready PR (never a merge); `--inline` for checkpointed execution |
| `/game-dev:review [scope]` | On demand, at any stage: the branch (or a range) against the spec; findings fixed by fresh agents; never changes the stage |
| `/game-dev:playtest <what failed>` | On demand: what you saw fail goes in; a bug, a fixed commit with a regression test, a push and one PR comment come out |
| `/game-dev:retro` | On demand: durable lessons from the feature's ledger into the studio's isolated memory |
```

### 7. Agents

**producer** (`studios/game-dev/agents/producer.md`).

- `:3` description: "…, or when a feature's branch is finished and
  PROGRESS.md must record it and decide whether the milestone gate moves."
- `:33-43` "Ship method" becomes "Finish method": (1) read the plan, the
  feature ledger at the path in the brief (the agent has no Bash, `:4`), and
  the play list in the brief; (2) add a dated entry at the top of `## Log`:
  what the branch delivers, one line per player-visible change, then `Play
  before merging: <n> items pending` (or `nothing to play`), then the branch
  name — the entry lands with the PR, before the merge; (3) the gate check,
  unchanged, ending "the execute skill moves `milestone` in state".
- `:58-60` output contract: "When dispatched by `/game-dev:execute`'s
  finish: …" (same report: `gate met: <current> → <next>` or `gate not met:
  <missing, one line each>`).

**playtester** (`studios/game-dev/agents/playtester.md`).

- `:3` description: "Use when a playtest failure the user reported must be
  filed as a bug with repro steps, a suspected cause, a severity and a
  regression-test kind."
- `:4` tools: `Read, Grep, Glob, Bash` (no `Write`; it writes no file).
- `:8-11` persona keeps its second half: it turns a reported failure into a
  bug someone can reproduce in one minute, and never talks to the player.
- `:13-37` (script method) is deleted. The bug method (`:39-52`) stays,
  with the title rule from §5 (`(from P<k>)`, `(from B<m>)` or `(from
  report)`).
- `:61-68` output contract: "Return the bug block as your report. Write no
  file."

**reviewer** — unchanged. Its output contract already carries `Scope:
branch <name> vs <base>` and `Spec compliance: met: …; unmet: …`; the model
comes from the dispatch. **feel-tuner** — unchanged: its `:59` contract
("When dispatched by `/game-dev:playtest` for a failed feel item") still
describes the on-demand playtest.

### 8. Autopilot

`shared/omega/skills/autopilot/SKILL.md`, two text edits; nothing else in
the skill changes (the heartbeat included).

**Phase 1 step 1** (`:33-37`) becomes:

> 1. **Design and plan as the studio does — unless that is done.** When the
>    spec and the plan are already approved and committed — the studio
>    ledger has `spec approved <spec>` and `plan approved <plan>` lines
>    (outside a studio, both files' `Status:` line says Approved), `git log
>    -1 --format=%h -- <file>` prints a hash for each, and `git status
>    --porcelain -- <spec> <plan>` prints nothing — go straight to step 2.
>    Otherwise `/game-dev:brainstorm` then `/game-dev:plan` in the game
>    studio; `superpowers:brainstorming` then `superpowers:writing-plans`
>    when installed and no studio is present; otherwise a spec and a plan
>    written by hand and approved by the user. Their approval gates stand.
>    Arm from a fresh session: run `/clear` first. `/clear` ends a session,
>    and its SessionEnd hook clears every omega mode that session set — a
>    `/clear` after arming disarms the run.

**Allowed side effects** (`:118-123`) becomes:

> - **Allowed side effects:** commit; `git push` after every integrated
>   task, so a crash loses at most one task; the run's one PR — when the
>   invoking skill opens it (`game-dev:execute`'s finish does, as a draft
>   while this mode is set), that PR is the run's PR and no second PR is
>   opened; otherwise `gh pr create --fill --draft` when the plan is
>   complete — base per `omega:local-merge` §3 (the integration branch when
>   an `integration` mode is set, else the repository's default branch);
>   `gh pr comment`; the handoff.

## Data and state migration

- **`STATE.md` in existing projects.** The `last_playtest:` header line
  stays and is inert: no key reads it, `write_field` only rewrites the key
  it is given, `show` prints it. `studio-state init` no longer writes it.
- **The `branch:` line.** Existing files lack it. Until it is written, `get
  branch` prints nothing and `studio-state worktree` exits 1, so review and
  playtest ask once, retro reads the current checkout's ledger, and a
  resume isolates as today. The first `set branch` (execute's next new run,
  or a legacy resume) or `reset` inserts it right after `task:`; no other
  missing line is ever inserted.
- **Old stage values.** `get stage` returns them unchanged (phoenix today:
  `stage: retro`, `task: 8/8`). The router reports `Stage: idle (was retro,
  old pipeline)` and names `/game-dev:brainstorm`; the session-start line
  says the same (Open question 4). `set stage review|playtest|ship|retro`
  exits 1 with "stage must be one of: idle brainstorm plan execute". The
  value is replaced the first time brainstorm, plan, execute or `reset`
  writes `stage`. Execute run at `retro` stops (§4 §0 step 1).
- **A project mid-way through the old pipeline** (stage `review`,
  `playtest` or `ship`, branch not merged): the router still names
  brainstorm. Running `/game-dev:execute` from the feature's worktree, with
  `task` at `N/N`, is a resume (§4 §0): `branch` is unset, so it isolates as
  today (`superpowers:using-git-worktrees` sees the linked worktree and
  creates none), records `branch`, takes the repository's default branch as
  the base (no `base` ledger line), and runs the final review and the
  finish — the PR that `ship` would have offered. Run from the main
  checkout, it stops and says so (§4 §0 step 2). Phoenix is at `retro`
  (finished) and is not affected.
- **Ledgers.** Old lines (`playtest written`, `playtest signed off`, `review
  clean`, `retro written`) stay and nothing reads them. Old reports under
  `docs/game-dev/playtests/` stay; brainstorm still reads the newest ones
  (`brainstorm/SKILL.md:28`), and no new ones are written.

## Error handling

| Failure | What happens |
|---------|--------------|
| `studio-test` or `studio-run` exit 2 during the finish | Stop and show the printed message (usually `GODOT_PATH` unset; `studio-dispatch` also exits 2 with no studio root, engine or adapter); `stage` stays `execute`; the session stays in the worktree; a re-run resumes at the gate |
| `studio-test` exit 3 (test framework missing) | Stop with the printed hint (Open question 2); resumes in place as above |
| `studio-test` / `studio-run` / `studio-lint` exit 1 | Red gate: a fresh `fix(gate)` fixer, then the whole gate again; after the third red run, a draft PR with the red gate line and a ruling (Open question 6) |
| `studio-lint` exit 3 | Noted in the gate line; not red |
| No `origin`, `gh` unauthenticated, push rejected, `gh pr create` fails | Body kept at `<git-dir>/game-dev-pr-body.md`, the failure and the path reported, ledger `shipped <branch>`, finish continues; never force-push |
| `omega-mode show` fails (no session id) | Unknown mode: the PR opens as a draft |
| A PR already exists for the branch | It is the PR; no second one (autopilot included) |
| No `docs/game-dev/PROGRESS.md` | Step 3 skipped and said in the report |
| Producer reports `gate not met` | Its missing list goes in the report; milestone unchanged |
| No play-list sources | `nothing to play` in the report, the PR body and PROGRESS |
| Final or re-review finding still open after pass 2 | One last fresh fix, no review; anything unclosed is a parked `Ruling:` in the PR body |
| Execute at `stage` `idle`, `brainstorm` or `retro` | Stop: no approved plan is waiting; name `/game-dev:studio` |
| A new run stops during isolation (fast-forward fails, worktree declined) | `stage execute`, `branch -`: the re-run is a resume that isolates as today |
| Execute resume, review or playtest: `studio-state worktree` exit 3 | Run the printed command (unlock and prune first when printed), enter it, continue |
| Execute resume: `studio-state worktree` exit 1 | No `branch`: isolate as today, record it after the ancestor check; a legacy run from the main checkout stops. The branch gone: stop; restart with `set task 0/<N>` and `set branch -`, or abandon |
| `EnterWorktree` refuses (another live session holds the worktree, or a path outside `.claude/worktrees/`) | Stop with its message (§1, Enter the feature checkout) |
| Execute ran in place on the default branch | No push, no PR; the guards skip the default branch |
| Brainstorm, plan or a new execute run in the previous feature's checkout | Stop: the finished-checkout guard (§1) |
| Session launched inside the feature worktree | `ExitWorktree` reports no session: `cd` to the main checkout, and the report says to quit and start `claude-gd` there (§1, Leave the feature checkout) |
| Review or playtest: `studio-state worktree` exit 1 | One question naming what was found |
| Review or playtest: the checkout has no ledger for `spec` (the next brainstorm moved it), or playtest at `stage execute` | Stop and say why (§5, Which feature); retro reads only `STATE.md`'s ledger |
| Review or playtest: the branch's PR is `MERGED` or `CLOSED` | No fixer, no push; findings or bugs reported with the bug route |
| Review or playtest in a checkout on the default branch | Review reports findings only (no fix, no ledger line, no commit); playtest asks where the fixes go |
| `stage-guard.sh`: malformed or empty input, no `transcript_path`, unreadable transcript | Silent, exit 0 |
| `stage-guard.sh`: any shell error | `trap 'exit 0' EXIT` turns it into exit 0; never exit 2, which would block and erase the prompt |
| `stage-guard.sh`: a file containing an envelope was read into the session | Possible spurious warning; it never blocks |
| `/clear` while autopilot is armed | The session ends and its modes are cleared: the run is disarmed; arm after `/clear`, never before |
| `/game-dev:playtest` with no text | One example printed; stop |
| Third failure of the same play item or bug chain | No fixer; backlog suggested; moved only on the user's word |
| `studio-state set branch` on a `STATE.md` without a `branch:` line | The line is inserted after `task:`; without `task:` either, the damaged-file error |
| `studio-state get last_playtest` | Exit 1 (unknown key); nothing calls it |

## Testing

All in bash under `tests/run_all.sh`; every new function is added to its
file's `run_tests` line.

One rule for every test file below: a test line that names a removed stage
or the ship name — an assertion of absence, or a value fed to `set stage` —
spells it split (`'sh''ip'`, `'game-dev:''ship'`, `'ship'' stage'`) or takes
it from a loop variable, so `test_no_ship_references` never matches the
tests' own lines.

**`tests/state_test.sh`**

- `test_state_init` — `:37` (`^last_playtest: -`) becomes
  `assert_not_contains … "^last_playtest:"`; adds `^branch: -`, and that
  the line after `task: -` is `branch: -`.
- `test_state_stage_list` (new) — `set stage` exits 0 for each of `idle
  brainstorm plan execute` and 1 for each removed value (a loop variable);
  `get last_playtest` and `set last_playtest x` exit 1.
- `test_state_legacy_file` (new) — a hand-written `STATE.md` with `stage:
  retro`, `last_playtest: docs/x.md` and no `branch:` line: `get stage`
  prints `retro`; `get branch` prints nothing; `worktree` exits 1; `set
  spec`, `set task`, `ledger` and `check` succeed; the `last_playtest:`
  line is still present afterwards; `set stage idle` succeeds.
- `test_state_branch_key` (new) — on an `init` file: `set branch feat/x`,
  then `get branch` prints `feat/x`; `reset` sets it back to `-`. With the
  `branch:` line removed: `set branch feat/x` exits 0 and the line after
  `task:` is `branch: feat/x`; on another such file `reset` exits 0 and
  leaves `branch: -` after `task:`. With both `branch:` and `task:` removed:
  `set branch feat/x` exits 1 and stderr names `task:`. (`set spec` on a
  file without `spec:` still fails: `test_state_set_hardening`, unchanged.)
- `test_state_worktree` (new) — real temporary git repositories and
  worktrees (as `test_state_resolves_to_main_checkout` builds them), every
  case asserting the exit status and stdout:
  - `branch -`: exit 1, stdout empty, stderr not empty;
  - `set branch nope` (no such branch): exit 1;
  - `git worktree add <tmp>/wt-f -b feat/f`, `set branch feat/f`: exit 0
    and stdout is exactly that worktree's physical path — run from the main
    checkout and from inside the worktree;
  - `git branch feat/g`, `set branch feat/g`: exit 3, stdout empty, stderr
    exactly two lines — `studio-state: no worktree has feat/g checked out`,
    then a line containing `git worktree add`, `.claude/worktrees/feat-g`
    and `feat/g`; running that second line then makes `worktree` exit 0
    with that path;
  - the `wt-f` directory removed by hand (`rm -rf`, leaving a `prunable`
    entry), `set branch feat/f`: exit 3 and stderr contains `git worktree
    prune`;
  - a worktree `wt-h` for `feat/h`, locked (`git worktree lock`), then its
    directory removed by hand, `set branch feat/h`: exit 3 and stderr's
    second line starts `git worktree unlock`.

**`tests/hook_test.sh`** — a `run_guard` helper writes a transcript file and
feeds the hook a `UserPromptSubmit` input JSON (`session_id`,
`transcript_path`, `prompt`) with `CLAUDE_PLUGIN_ROOT` set; `prompt` is the
raw typed text (`"prompt":"/game-dev:execute"`) unless a case says
otherwise; every case asserts exit 0.

- `test_stage_guard_registered` — `hooks.json` has `"UserPromptSubmit"`
  running `CLAUDE_PLUGIN_ROOT}/hooks/stage-guard.sh`; still valid JSON;
  `stage-guard.sh` contains `trap 'exit 0' EXIT` and no `set -u` line.
- `test_stage_guard_first_stage_silent` — `/game-dev:plan` typed, empty
  transcript: stdout empty.
- `test_stage_guard_warns_after_other_stage` — transcript holding a typed
  `/game-dev:plan` envelope, then `/game-dev:execute` typed: stdout is one
  JSON object whose `.systemMessage` equals the exact §3 text; the same with
  the transcript holding a `Skill` tool call for `game-dev:plan` instead.
- `test_stage_guard_raw_prompt_shape` (new) — transcript with `plan`:
  `/game-dev:execute --inline` and `   /game-dev:execute` (leading spaces)
  warn with the §3 text; `please run /game-dev:execute` and
  `/game-dev:executes` print nothing.
- `test_stage_guard_envelope_prompt` (new) — transcript with `plan`, the
  prompt in the envelope shape
  (`<command-message>game-dev:execute</command-message>\n<command-name>/game-dev:execute</command-name>`):
  the same §3 message.
- `test_stage_guard_names_latest_prior_stage` — transcript with brainstorm
  then plan, `execute` typed: the message names `/game-dev:plan`.
- `test_stage_guard_same_stage_silent` — transcript with `execute`,
  `execute` typed: stdout empty.
- `test_stage_guard_ignores_mentions` — transcript holding the bootstrap's
  stage list and a skill's "the next command is `/game-dev:plan`" as plain
  text, `execute` typed: stdout empty.
- `test_stage_guard_ordinary_prompt_silent` — "keep going", and
  `/game-dev:review` typed after a transcript with `execute`: stdout empty.
- `test_stage_guard_scheduled_task_silent` — prompt `/game-dev:execute`
  with `<scheduled-task` elsewhere in the input, transcript with `plan`:
  stdout empty.
- `test_stage_guard_no_transcript_silent` — no `transcript_path` key, a path
  to a missing file, an empty input and a non-JSON input: stdout empty.
- `test_hook_reports_old_stage` (new) — `stage: retro` in `STATE.md`: the
  session-start context carries `stage idle (was retro, old pipeline)`.
- `test_hook_files` — adds: bootstrap names `/game-dev:review [scope]`,
  `/game-dev:playtest <what failed>`, `/game-dev:retro`, the chain line,
  and `/clear` with "omega modes"; does not name the ship command (split
  spelling).

**`tests/studio_test.sh`**

- `test_stage_chain` (rewritten: the comment block from `:219`, the
  function `:226-244`) — the router table has the rows `` | `idle` |
  `/game-dev:brainstorm` | ``, `` | `brainstorm` | `/game-dev:plan` | ``,
  `` | `plan` | `/game-dev:execute` | ``, `` | `execute` |
  `/game-dev:execute` `` and a row containing `old pipeline`; for
  brainstorm, plan and execute, each skill's last `studio-state set stage
  <X>` value (one line, `grep -o`) has a router row (execute's is `idle`);
  every value in `studio-state`'s `STAGES` has a router row.
- `test_on_demand_skills_keep_stage` (new) — review, playtest and retro
  contain no `studio-state set stage`; retro contains no `set spec -` and no
  `set plan -`.
- `test_execute_contract` (new) — execute contains: the override line
  (`never resume or message an implementer`) and
  `superpowers:subagent-driven-development`; `3+ Importants` or `three or
  more Importants`; `[Nn]ever a third`; `review-package`; `model: "opus"`;
  `never folded`; `Verify prior fixes`; `final|gate|review` (the reserved
  scopes of the fix filter); `final fix wave`; `A task is complete`; `final
  review done`; `studio-lint`; `subagent_type: "game-dev:producer"`; `gh pr
  create`; `--draft`; `local, default branch`; `Play before merging`;
  `studio-state set stage idle`; `new run clears` (the clear before
  isolating); `studio-state set branch "$(git branch`; `before the
  fast-forward`; `ledger "base`; `from the feature's worktree` (the legacy
  stop); `set task 0/` (the gone-branch restart); `N/N`; `SDD ledger —
  plan:` (the seed); the verbatim `Next: play the list; …` line; and does
  not contain `set stage review` or `a side effect outside the worktree`.
- `test_review_contract` (new) — review contains `model: "opus"`,
  `fix(review)`, `never a third`, `.studio/ledger <plan path>`,
  `chore(studio): ledger`, `pointers now name`, `MERGED` and `ends at
  HEAD`; no `Three rounds`. (Its `subagent_type: "game-dev:reviewer"` stays
  pinned by `test_stage_skills_dispatch_agents`, `:211`.)
- `test_playtest_contract` (new) — playtest contains `subagent_type:
  "game-dev:playtester"`, `game-dev:feel-tuner`, `fix(B<n>)`, `gh pr
  comment`, `## Backlog`, `systematic-debugging`, `.studio/ledger <plan
  path>`, `chore(studio): ledger`, `never counted`, `pointers now name`,
  `stage execute` and `MERGED`; does not contain `AskUserQuestion`,
  `docs/game-dev/playtests`, `signed off` or `## Script`.
- `test_retro_contract` (new) — retro contains `CLAUDE_CONFIG_DIR`,
  `sync-memory.sh game-dev`, `studio-state worktree`, `git show`, ``read
  only `STATE.md` `` and `for the current stage`; does not contain
  `AskUserQuestion`, `studio-state ledger`, `retro written` or `git
  commit`.
- `test_feature_checkout_copies` (new) — every copy of a §1 procedure holds
  its key literals: execute, review and playtest each contain `studio-state
  worktree`, `EnterWorktree`, `another live session`, `ExitWorktree` and
  `--git-common-dir`; brainstorm, plan and execute each contain
  `studio-state get branch`, `previous, finished feature` and `start the
  next feature on this branch anyway`; all five contain
  `refs/remotes/origin/HEAD`.
- `test_next_lines` (new) — brainstorm contains `Next: run /clear, then
  /game-dev:plan`; plan contains `Next: run /clear, then /game-dev:execute`.
- `test_agent_contracts` (new) — producer contains `Play before merging`
  and does not contain `playtest report it passed`, `ship skill` (split
  spelling) or `studio-state show`; playtester does not contain `## Script`
  or `docs/game-dev/playtests` and its `tools:` line has no `Write`.
- `test_no_ship_references` (new) — `studios/game-dev/skills/ship` does not
  exist; `grep -rnE` for `game-dev:ship([^a-z-]|$)`, `skills/ship([^a-z-]|$)`,
  `stage ship([^a-z-]|$)` and `[Ss]hip (stage|skill|method)` finds nothing in
  `studios/game-dev`, `shared/omega`, `README.md` and `tests/*.sh`, with
  nothing excluded: the split-spelling rule above keeps the tests' own
  lines from matching.
- `test_superpowers_requires_referenced` (new) — every line of
  `studios/game-dev/requires.txt` matching `^skill[[:space:]]+superpowers:`
  (the file pads with two spaces) is named by a file under
  `studios/game-dev/skills` or `studios/game-dev/agents`; the existing
  `test_external_references_declared` (the other direction) still passes.
- `test_stage_skill_contracts` — `:145` (`unverified`) becomes `Play before
  merging`; `:153` (`do not set`) stays (the exit-2 stop keeps "do not set
  `stage idle`"); `:151` (`GODOT_PATH`) stays.
- `test_stage_skills_dispatch_agents` — `:213` (`playtest signed off`) and
  `:214` (ship dispatches the producer) are removed; an assertion that
  execute dispatches `game-dev:producer` is added.
- `test_bin_syntax` — unchanged: it already parses every
  `studios/*/hooks/*.sh` and `studios/*/bin/*` file as POSIX sh and checks
  that it is executable (`:108-117`), so it covers `stage-guard.sh` and the
  changed `studio-state`.

**`tests/omega_contracts/`**

- `autopilot_contract.sh` — adds: `already approved and committed`, `/clear`
  and `no second PR is opened`; every existing assertion still passes.
- `local-merge_contract.sh` — adds an `assert_not_contains` for a studio
  ship stage, spelled split (`'ship'' stage'`).

**Pressure scenarios** — `docs/game-dev/pressure/slim-pipeline.md`, in the
format of `docs/omega/pressure/*.md`, with a new `slim-pipeline` kind in
`tests/pressure/fixture.sh` (a Godot fixture repo with an approved spec and
plan, a bare `origin`, a stub `gh` logging every call, and a stub engine so
`studio-test`/`studio-run` exit 0). Each runs once with `claude-gd -p`:

1. **Fixes go to a fresh agent.** A task review returns one Critical. Pass:
   the next dispatch is a new `Agent` call of the task's role carrying the
   findings and a review-package path — no message to the earlier
   implementer — followed by one scoped re-review; a second variant with
   one Important shows no re-review.
2. **The final review is standalone on Opus.** After the last task review
   comes back clean, pass: a separate `game-dev:reviewer` dispatch with
   `model: "opus"`, a whole-branch scope and a verify-prior-fixes list.
3. **The finish opens the PR without asking.** Gate green. Pass: `gh.log`
   shows `pr create` (no `--draft` when autopilot is off) and no `pr merge`;
   no `AskUserQuestion`; an `ExitWorktree` call (or a `cd` to the main
   checkout) after the state step; the report ends with the verbatim
   `Next:` line.

Status in the file: "written 2026-10-01; not yet run — `claude-gd` returns
`403 oauth_not_allowed_for_organization`".

## Rollout

1. Merge the PR (it closes #9).
2. `git pull` in the main checkout
   (`/Users/xinli/Documents/GameDev/_practice/omega-ai`). `claude-gd` is a
   symlink-mode install (`~/.claude-gamedev/.omega-ai-manifest`: `mode=
   symlink`), so it loads the studio and omega plugins from that checkout.
   No reinstall: `settings.json` and `CLAUDE.md` are unchanged. A copy-mode
   install would need `./install.sh game-dev` again.
3. Start a new `claude-gd` session (hooks are read at session start). In
   phoenix, `/game-dev:studio` prints `Stage: idle (was retro, old
   pipeline)` and `Next: /game-dev:brainstorm`.
4. Re-scope issue #6 (the old eight-stage manual walk of Plan 2 Task 16) to
   the new chain: brainstorm → `/clear` → plan → `/clear` → execute to a
   ready PR; after the finish and a `/clear`, `pwd` is the main checkout;
   then one `/game-dev:playtest <failure>` and one `/game-dev:review`, each
   working in the feature's worktree.
5. Once the `claude-gd` login works, run the three pressure scenarios and
   record the results in `docs/game-dev/pressure/slim-pipeline.md`.
6. Open a follow-up issue for `shared/omega/hooks/prompt-submit.sh` (Not
   doing).
7. `docs/game-dev/PROGRESS.md` gains the bundle's log entry on completion.

## Risks

| Risk | Mitigation |
|------|------------|
| The second whole-branch review is gone, and it caught new Importants in 2 of 4 features and a Critical on KAN-1304 | The Critical came where execute ran no final review; the final review is now mandatory, standalone and on Opus — the shape that flagged 79% of the time against 22% when merged. `/game-dev:review` stays one command away |
| Skipping the re-review for one or two Importants lets a bad fix through | The fixer runs the task's tests before handing back; the final review re-checks every reserved-scope fix commit by name |
| The playtest stage is gone, and it found one real bug | 26 of its 56 items were never played; the play list is 3–5 items the user plays before merging, and the merge is the user's |
| The user ignores the warning and runs stages in one session | The warning fires on every typed stage; the cost is today's cost, not worse; bundle 2's runner removes the choice |
| A later Claude Code changes the hook's input shape again | Both shapes are accepted; M2 records the version it ran on; the hook is warn-only, so a miss costs a warning, never a prompt |
| `systemMessage` stops being shown by a later Claude Code | The hook is warn-only and silent elsewhere; nothing depends on the message being seen |
| A spurious warning when a session read a file containing an envelope | Patterns are anchored at a JSON string start; `test_stage_guard_ignores_mentions` pins the common prose mentions |
| `/clear` returns the session to the finished feature's worktree (a session launched there, or a later Claude Code that changes `ExitWorktree`) | The finished-checkout guard (brainstorm, plan, execute) compares `branch` with the current branch and stops the next feature there; a session launched there is told to restart in the main checkout |
| A PR opened without asking is visible to collaborators | It is ready, never merged; under autopilot (or an unknown mode) it is a draft; the play list in its body says what must pass first |
| PROGRESS records a feature before it is merged | The entry says the play list is pending and names the branch; it lands with the PR, so a closed PR takes it away |
| A PR closed unmerged leaves `milestone` advanced in `STATE.md` (§7 step 3 moves it at PR time) | Fix it by hand with `studio-state set milestone <previous>`; the report names the move |
| `/clear` disarms autopilot | The step 1 text says to arm after `/clear`, never before |
| A project left mid-pipeline loses its next step | The migration note: `/game-dev:execute` from the feature worktree runs the finish |
| Execute's main session still averages 469k | Not addressed here: bundle 2 splits execute into fresh sessions per unit |

## Not doing

- The overnight runner and automatic fresh sessions (bundle 2).
- Removing or replacing the autopilot heartbeat (bundle 2).
- Per-task risk tags (B1), and folding mechanical tasks' reviews into the
  final review — every task keeps its task review in this bundle.
- The plan falsifier, and removing the plan approval gate (bundle 3).
- Model selection by role for implementers and task reviewers.
- Trimming `settings.json`.
- The plan shape: epic → story spec → just-in-time task files (bundle 3).
- The brainstorm HTML spec page: unchanged.
- The spec template: unchanged.
- A hook that blocks. The stage guard only warns.
- Retro harvesting across several features' ledgers (Open question 5).
- Removing a finished feature's worktree: it stays for playtest and review;
  the user removes it after the merge.
- The same input-shape defect in `shared/omega/hooks/prompt-submit.sh`: it
  sets a mode only from the envelope shape (`:50-65`), so a typed
  `/omega:<mode>` never sets one there; the omega skills hide it by running
  `omega-mode set` themselves. A follow-up issue, not fixed here.

## Acceptance criteria

1. `sh tests/run_all.sh` exits 0.
2. `studio-state set stage` accepts exactly `idle brainstorm plan execute`
   and rejects `review playtest ship retro` (`test_state_stage_list`).
3. `studio-state init` writes no `last_playtest` line, and `get
   last_playtest` exits 1 (`test_state_init`, `test_state_stage_list`).
4. A `STATE.md` with `stage: retro`, a `last_playtest:` line and no
   `branch:` line keeps working for every other key and keeps that line
   (`test_state_legacy_file`).
5. `studio-state init` writes `branch: -` right after `task: -`; `set
   branch` round-trips; on a file without the line, `set branch` and
   `reset` insert it after `task:`; `reset` sets `-`; any other missing
   header line is still the damaged-file error (`test_state_init`,
   `test_state_branch_key`, `test_state_set_hardening`).
6. `studio-state worktree` prints the path of the worktree that has
   `branch` checked out and exits 0; exits 1 when `branch` is `-` or the
   branch is gone; exits 3 with two stderr lines, the second the `git
   worktree add …/.claude/worktrees/…` command (with `git worktree prune`
   first for a stale entry, and `git worktree unlock` before that for a
   locked one whose directory is gone), when the branch exists but no
   worktree has it (`test_state_worktree`).
7. The router has rows `idle → brainstorm`, `brainstorm → plan`, `plan →
   execute`, `execute → execute (resume)` and an `old pipeline` row; every
   stage in `STAGES` has a row; brainstorm's `studio-state set stage
   brainstorm` is on one line; execute's last stage write is `idle`
   (`test_stage_chain`).
8. Review, playtest and retro write no `stage`; retro clears no pointer
   (`test_on_demand_skills_keep_stage`).
9. `studios/game-dev/skills/ship/` does not exist and no ship reference
   remains in the scanned paths (`test_no_ship_references`).
10. `requires.txt` has no `finishing-a-development-branch` line and every
    superpowers skill it declares is referenced; every reference is declared
    (`test_superpowers_requires_referenced`,
    `test_external_references_declared`).
11. Execute carries the B2 override, the re-review rule, the no-third-pass
    rule, the batched-minors wave and fixer briefs that hand the diff over
    as a review-package file (`test_execute_contract`).
12. Execute's final review is a standalone `game-dev:reviewer` dispatch
    with `model: "opus"` and a verify-prior-fixes list filtered on the
    reserved fix scopes, and ends with the `final review done` line
    (`test_execute_contract`).
13. Execute's §0 tells a new run from a resume: a resume enters the
    recorded worktree through `studio-state worktree` and `EnterWorktree`;
    a new run in the previous feature's checkout stops; a new run clears
    `branch` before isolating, then records `branch` and commits its `base`
    after the fast-forward; a resume whose branch is gone, or a legacy
    resume from the main checkout, stops; `task` `N/N` skips the task loop;
    a missing SDD progress ledger is seeded from the feature ledger; a task
    accepted under rule 3 or parked under rule 4 is complete
    (`test_execute_contract`, `test_feature_checkout_copies`).
14. Execute's finish runs the three gate commands, dispatches the producer,
    opens the PR with `gh pr create` (`--draft` under autopilot) or, on the
    default branch, pushes nothing and opens no PR, prints the play list
    under `Play before merging`, sets `stage idle`, leaves the feature
    checkout with `ExitWorktree`, and ends with the verbatim `Next:` line;
    it no longer lists push as an ask-first side effect
    (`test_execute_contract`, `test_stage_skill_contracts`,
    `test_feature_checkout_copies`).
15. Brainstorm, plan and a new execute run stop in the previous feature's
    checkout, never on the default branch, and every skill that carries a
    §1 procedure holds the same key literals
    (`test_feature_checkout_copies`).
16. Brainstorm and plan end with `Next: run /clear, then /game-dev:<next>`
    (`test_next_lines`).
17. The bootstrap lists the three-stage chain, the three on-demand commands
    and the `/clear`-clears-modes sentence, and not the ship command
    (`test_hook_files`).
18. `stage-guard.sh` exists, is executable, parses as POSIX sh, has `trap
    'exit 0' EXIT` and no `set -u`, and is registered under
    `UserPromptSubmit` (`test_bin_syntax`, `test_stage_guard_registered`).
19. A typed `/game-dev:brainstorm|plan|execute` after a different stage —
    in the raw shape, with or without arguments or leading spaces, or in
    the envelope shape — prints exactly the §3 `systemMessage` JSON naming
    the latest prior stage (`test_stage_guard_warns_after_other_stage`,
    `test_stage_guard_raw_prompt_shape`,
    `test_stage_guard_envelope_prompt`,
    `test_stage_guard_names_latest_prior_stage`).
20. The hook prints nothing for: a first stage, the same stage again, prose
    mentions in the transcript, a prompt that mentions a stage command after
    other text, an ordinary or on-demand prompt, a scheduled task, a missing
    transcript, an empty or non-JSON input (`test_stage_guard_*_silent`,
    `test_stage_guard_ignores_mentions`,
    `test_stage_guard_raw_prompt_shape`).
21. The session-start line reports an old stage as `idle (was <x>, old
    pipeline)` (`test_hook_reports_old_stage`).
22. Playtest finds the feature checkout through `studio-state worktree`,
    takes free-text failures, dispatches the playtester and the right fixer,
    counts third failures per item without counting `(from report)`,
    commits `fix(B<n>)` and its ledger lines, comments once on the PR,
    leaves the worktree it entered, never commits on the default branch,
    stops when the pointers name a different feature or at `stage
    execute`, dispatches no fixer once the PR is merged or closed, and has
    no script, report file,
    per-item question or sign-off (`test_playtest_contract`,
    `test_feature_checkout_copies`).
23. Review finds the feature checkout through `studio-state worktree`,
    dispatches on Opus with execute's fix rules and no three-round loop,
    commits its ledger line with its fixes, reports only on the default
    branch or when HEAD is not the branch or range it was given, stops
    when the pointers name a different feature, fixes nothing once the PR
    is merged or closed, and leaves the worktree it entered
    (`test_review_contract`, `test_stage_skills_dispatch_agents`,
    `test_feature_checkout_copies`).
24. Retro asks no questions, reads the recorded feature's ledger through
    `studio-state worktree` (with `git show` when its worktree is gone;
    only `STATE.md`'s when the pointers name a different feature), writes
    no ledger line and commits nothing, names the router's next
    command, and keeps memory in `CLAUDE_CONFIG_DIR`
    (`test_retro_contract`).
25. The producer and playtester carry their new contracts; the producer
    reads the ledger from the path in its brief, not `studio-state show`
    (`test_agent_contracts`).
26. Autopilot carries the skip-when-approved step, the `/clear` advice and
    the one-PR rule, and every older contract assertion still holds
    (`test_autopilot_contract`); local-merge no longer names a ship stage
    (`test_local_merge_contract`).
27. Manual check M1: `docs/game-dev/pressure/slim-pipeline.md` holds the
    three scenarios and their pass conditions, and `tests/pressure/
    fixture.sh slim-pipeline <dir>` builds the fixture.
28. Manual check M2, after rollout: in a fresh `claude-gd` session, typing
    `/game-dev:plan` after `/game-dev:brainstorm` shows the warning line to
    the user, and typing `/game-dev:brainstorm` as the first prompt shows
    nothing. M2 is the only live proof of the hook's input shape (§3 step
    5); the Claude Code version it ran on (`claude --version`) is recorded
    in `docs/game-dev/pressure/slim-pipeline.md`.
29. Manual check M3, after rollout: phoenix's `/game-dev:studio` prints
    `Stage: idle (was retro, old pipeline)` and `Next:
    /game-dev:brainstorm`.
30. Manual check M4: issue #6 describes the new chain, including the check
    that after the finish and `/clear` the session is in the main checkout
    (`gh issue view 6`).

## Review history

- First falsifier pass: 2 Critical, 7 Important, 12 Minor, all applied; headline: the stage guard matched the wrong prompt shape, and `/clear` stayed in the finished worktree.
- Second pass: 1 Critical, 4 Important, 13 Minor, all applied; headline: a run stopped during isolation re-entered the previous feature's worktree.

## Open questions — resolved

Each one was a conflict or gap the thirteen decisions did not settle. The
user ruled 1, 3 and 6 as recommended on 2026-10-01 and approved the spec,
with 2, 4 and 5 and the details below, as written. The spec is drafted to
these rulings.

1. **`local-merge` against "never merge".** `local-merge`'s precedence
   block says the mode wins on merge mechanics, and its `:23-26` names "a
   studio's ship stage" as a step it takes over — so with `local-merge`
   set, a finish would merge before anyone plays the list. *Recommended
   (drafted, §6):* execute never merges even with `local-merge` set; its
   `:23-26` drops the ship stage and says a studio's PR-opening finish is
   not a merge step. The PR base stays the branch the worktree was created
   from (the integration branch, in an integration flow).
2. **`studio-test` exit 3 (test framework not installed).** Decision 6's
   stop list names no Godot binary but not a missing GUT/gdUnit4, while
   `execute/SKILL.md:92` stops a task on "Exit 2 … or 3". *Recommended (drafted):*
   keep exit 3 as a stop — without it no `Verify: unit` test can run and a
   ruling would open a PR on untested code.
3. **`README.md:71-75`** is outside the four allowed paths but lists the
   ship command and the old playtest. *Recommended (drafted, §6):* replace
   those five rows with the four given in §6 — execute gains the final
   review, gate, play list and PR; review, playtest and retro are on
   demand; the ship row is deleted — since no session loads `README.md`, it
   does not touch the global setup; and include it in
   `test_no_ship_references`. If not, the test drops `README.md` and the
   README stays stale.
4. **The session-start line** (`session-start.sh:86`) prints `stage retro`
   raw; decision 8 only covers the router. *Recommended (drafted, §2):*
   print `stage idle (was retro, old pipeline)`, so the bootstrap line and
   the router agree.
5. **Retro across several features.** Retro now reads the recorded
   feature's ledger wherever its checkout is (§5), plus `STATE.md`'s, so it
   harvests the latest feature before its merge — until the next
   brainstorm's gate moves `spec`. On demand it may run after
   several features, and the earlier features' ledgers are not read.
   *Recommended (drafted):* keep it to the latest feature in bundle 1 — a
   repeated retro over the same lines writes no duplicate (retro
   `:64-66`) — and revisit harvesting across features with bundle 2's
   runner.
6. **A gate that stays red.** "Red gate = fix-loop work" has no bound, and
   decision 6's stop list has no gate stop. *Recommended (drafted, §4 step
   1):* three gate runs; after the third red one, open the PR as a draft
   with the red gate line and a ruling — no stop, no merge.

Details this draft fills in that no decision names, listed so they can be
vetoed: the `branch` state key and `studio-state worktree` (exit 0 / 1 / 3),
through which execute's resume, review, playtest and retro find the
feature's checkout (§1, §4, §5); the three named feature-checkout
procedures and their copies test; execute's §0 split into new run and
resume, with the stops at `idle`, `brainstorm` and `retro`, a new run
clearing `branch` before it isolates, and the `base` ledger line committed
after the fast-forward; the finished-checkout guard in brainstorm, plan
and execute; no push and no PR when execute ran on the default branch;
review's and playtest's which-feature and merged-PR checks; leaving the
feature checkout at the end of execute's finish, and of review and
playtest when they entered one; the `final review done` line and
ledger commit that let a stopped finish resume at the gate; the SDD progress
ledger seeded from the feature ledger; retro read-only on the repository (no
`retro written` line); review and playtest never commit on the default
branch, and commit their ledger lines with their fixes; play-list items as
`P<k> Play:` ledger lines and bug titles tagged `(from P<k>)` or `(from
B<m>)` for the per-item third-failure count; fix-commit subjects
`fix(T<n>)`, `fix(final)`, `fix(gate)`, `fix(review)`, `fix(B<n>)` so the
verify-prior-fixes list is a `git log` filter on those scopes; fixer briefs
that hand the diff over as a review-package file; one last unreviewed fix
after pass 2, with parked rulings for what stays open; `/game-dev:review` on
Opus and pushing its fixes when the branch tracks a remote; the idempotent
PR step (`gh pr view` first) and a draft when the mode is unknown; the final
review in `--inline` mode too; the PROGRESS step skipped when the project
has no `PROGRESS.md`.

# A pinned-reference mismatch blocks and carries on, the preflight checks the run's tools, and the final gate reads the run's config — design

Status: design approved by the operator in chat, 2026-10-23. The operator chose: a run-level blocks file with no date; the
venv probe is a `required_tools` entry, not a separate key; #82's done-record question is in scope.
Issues: #94 (Gap A), #95 (Gap B), #82 (Gap C); one PR, stacked on #93 (`fix/overnight-push-gaps`, #90-#92). The PR merges
after #93, and only after the live phoenix run (pid 10051) has ended. Then reinstall.
Coordination: #95's config key belongs to this spec. The throughput session dropped its Part B ("requires") on
2026-10-23 (its b480d0a). That session adds stdout lines after `tools_check` in `preflight()` and does not move it. A
per-plan `Requires:` header is a possible later layer on `required_tools`, and nobody is building one now.

## Incident (phoenix bat-sonic-rings, Mac.lan, run overnight-bat-sonic-rings-20261022-224317)

- **T46, 14:49 CDT.**
  - Plan Task 46 said "a difference … the run BLOCKS (D4, D24)". The plan's rules (phoenix plan l.566) and the kickoff
    define a BLOCK: mark the check pending `BLOCKED …`, write the finding to a blocks file, put it in the PR body, and
    keep doing independent work.
  - The execute skill has no such outcome; it knows only `Stop:`. So the unit wrote `Stop: T46 BLOCK …`, and the lane
    held for about 1 h until an operator sent `say` + `resume`. The re-run took 1.2 min.
- **T34, 11:39 CDT.**
  - The unit held because ffmpeg/ffprobe were not installed (`tools/convert_ambience.py`: `ffmpeg is not on PATH`).
  - It also rebuilt the worktree `.venv` on python3.12: `worktree_setup` runs `python3 -m venv .venv`, and `python3`
    was macOS's 3.9.6, which cannot import tools that use `int | None`.
  - `start` and `--dry-run` caught neither.
- **#82 (2026-10-21, bashful-bat-bite).**
  - `final_gate` ran without `STUDIO_START_DIR`, so the integration worktree, which has no `.studio/config.json`, never
    saw `test_engine_args "--fixed-fps 60"`. GUT ran wall-paced: 24 reds, and the final PR opened `[red]`.
  - After the operator landed that PR by hand, the record still had no `done`, so the phoenix session wrote
    `.studio/runs/<slug>/done` by hand.

## What already exists (verified, unchanged)

- Execute `--one` (§8): every stop is `Stop: <reason>`, committed in the feature checkout. The runner's `snapshot()`
  turns a new `Stop:` line into the ending `stop: <reason>`, and `holdable()` holds the story. A unit that moves
  `task` is progress.
- Rulings reach the reader through four paths:
  - `write_report` (single plan, `## Rulings`);
  - `story_ledger_lines` (the lanes report);
  - `final_body` (the integration final PR);
  - execute §7 step 4 (the PR body's `## Rulings`).
- `studio-brief final` feeds the final reviewer the ledger's `Ruling:` and `minor (deferred)` lines.
- Preflight (`studio-overnight` `preflight()`) refuses through `refuse` (stderr, exit 2) and prints its pass lines on
  stdout: #90's `push:` line and `env_line`. `setup_preflight` runs `worktree_setup` once in a scratch linked worktree
  off origin/<base>, in `start` and in `--detach`'s foreground. `--dry-run` only prints a note.
- `studio_cfg` (`gate-class.sh`, `engines/godot/cfg.sh`) reads a key from the checkout's `.studio/config.json`, and
  falls back to `$STUDIO_START_DIR`'s. Units get `STUDIO_START_DIR` from `start_session`.
- `RECORD/done` (`.studio/runs/<slug>/done`) is written only on the ending `done`. An open record (no `done`) is a
  resumable run: `mf_check` lists it as a clash for other runs, and autopilot discovery lists it.

## Goals

1. A check that disagrees with a pinned reference becomes a **Block**: the check goes pending, the finding is written
   down and reaches the PR, and the unit ends as progress. The story never holds for it.
2. A Stop stays a Stop: a missing tool, the environment, a push, a gate timeout or a setup failure.
3. `start`, `--dry-run` and `--detach` refuse a run whose declared tools are missing, too old, or do not run, and
   print each tool's install hint. A project with no `required_tools` sees no change.
4. Every gate the runner launches itself reads the run's `.studio/config.json`.
5. A run whose final PR was merged by hand is marked done, without anyone writing the file.

## Non-goals and anti-goals

- No existing check is weakened: no stop becomes a block by default, and #91's push stop and #90's push check are
  unchanged.
- A Block never edits, regenerates or loosens the pinned reference, and never marks a check pending when that check
  does not compare against a pinned reference.
- The runner does not parse Block lines into outcomes. They are records for the reader, like rulings.
- No per-plan tool list (throughput Part B may add one on top of this key). No new event type.
- `done` is **not** written on every terminal ending. A stopped or partial run must stay resumable, and a red final PR
  stays open, so a resume re-runs the final gate.

## Design

### Gap A — the Block outcome (#94)

**Definition (execute SKILL.md, a new §6a "Blocks", which §8 and §11 point to).**

- **A Block** is a check whose result disagrees with a **pinned reference** the unit must not change: a frozen
  fixture, a golden, an approved value or a capture. A reference is pinned when the plan, its `## Decisions`, its
  `## Global Constraints` or the spec says it is frozen, approved, golden or a capture, or when the plan's task says
  a difference "blocks".
- **Everything else stays as it is.**
  - A failing check against a reference that is not pinned is ordinary work: fix the code, TDD as usual.
  - A check that cannot run at all is a Stop: a tool not on PATH, an interpreter that cannot import, the engine
    missing, setup failed, a push rejected, a gate timed out.
  - When it is unclear whether a reference is pinned, it is not a Block: record a `Ruling:` and fix the code, or Stop
    if the fix would change the reference.

**Procedure.** A unit that meets a Block:

1. **Pending marker.** Mark pending only the failing assertions (a test or case, never a whole file or suite), using
   the framework's own pending or skip, with the reason `BLOCKED <story> <check>: <key> — expected <a>, got <b> — <where>`:
   - GUT: `pending("BLOCKED …")` and return;
   - vitest/jest: `it.skip("BLOCKED … <title>")`;
   - pytest: `pytest.skip("BLOCKED …")`.

   Every other assertion stays live. `<story>` is `$STUDIO_STORY`, else the feature slug. `<check>` is the test's
   name.
2. **Blocks file entry.** Append one entry to the blocks file:
   - The path is the `blocks:` line of `studio-brief task <n>` (below).
   - A missing file is created with the header `# <slug> — blocked checks` and the line
     `A run names a failed check against a pinned reference and carries on. It never resolves a block itself: the author rules.`
   - The entry has this shape:
     ```
     ## <story> B<k> — <check> — OPEN
     - **Where:** <test file:line, and the reference's path>
     - **Check:** <what it asserts>
     - **Expected / actual:** <key>: <reference value> vs <produced value>
     - **Why it is pinned:** <the plan/spec line that freezes it>
     - **Task:** T<n>, <YYYY-MM-DD>
     - **Options for the author:** <one line each, when the unit can see them>
     ```
   - `<k>` is the next number among this story's entries. Each story has its own sequence, so parallel lanes never
     renumber each other.
3. **Ledger.** `studio-state ledger "T<n> Block: <check> — <key>: <a> vs <b> — blocks <path>"`. The prefix is `check`
   in a check unit, `final` in the final fix wave and `gate` in a gate repair. The trailing `— blocks <path>` mirrors
   `Stop: … — log <path>`.
4. **Commit and complete.** Commit the marker, the blocks file and the ledger with the task's commits, then complete
   the task as §4a rule 6 and §6 say. The unit ends as progress. No `Stop:` line is written.
5. **Never.** Never regenerate, re-capture, loosen, re-approve or edit the pinned reference to get green, and never
   widen the pending marker beyond the failing assertions. Doing either is a Critical review finding.

**Where it applies.** A Block can happen in four places:

- a task's implementer or fixer (§2, §4a);
- the check unit (§8);
- the final fix wave (§5 step 5);
- a gate repair (§11): a red finish gate whose failure is a pinned-reference mismatch.

The orchestrator puts the procedure in the brief of each implementer or fixer it dispatches: "a check that disagrees
with a pinned reference: §6a's Block procedure, not a fix and not a stop".

**Review.**

- §4 adds two items to the task reviewer's checklist:
  - a Block's pending marker covers only the failing assertions;
  - the pinned reference is unchanged in the commit range.
- §5 step 3, the final reviewer's brief, gets the story's `Block:` lines with the instruction "report each open Block
  in the verdict; never a fix-wave item; a change to a pinned reference is Critical".
- §5 step 5's fix wave never takes a Block.
- `studio-brief final` adds `Block:` lines to the ledger lines it prints.

**Finish (§7 step 4).** The PR body gets `## Blocks` right after `## Rulings`:

- every `Block:` line of the feature ledger, in order;
- then, for each distinct path in those lines, the path and the file's entries for this story (`## <story> B<k>`
  sections);
- `(none)` when there are no Block lines.

The report's rulings item adds the Blocks. A PR with Blocks is still ready unless another rule makes it a draft.

**The blocks file's path, `studio-brief task <n>` line `blocks: <path>`.** The first of these that exists:

1. a `Blocks file: <path>` item in the plan's `## Global Constraints` (backticks stripped);
2. the `Blocks:` header of `$STUDIO_RUN` (the manifest);
3. `docs/game-dev/playtests/<slug>-blocks.md`, where `<slug>` is:
   - the manifest's `# Run:` slug when `$STUDIO_RUN` is set;
   - else the plan file's basename without a leading `YYYY-MM-DD-` and without `.md`.

There is no date in the path, so a unit after midnight or after a resume appends to the same file.

**Parallel lanes.** Two lanes can append to one run-level file. §9 (land repair) adds a rule: "a conflict in a blocks
file (`*-blocks.md`) is resolved by keeping both sides' entries, the target's first; entries are never renumbered".

**Runner (read only).** `Block:` lines are listed beside rulings in three places:

- `write_report`: `## Blocks` after `## Rulings` (`(none)` when there are none);
- `story_ledger_lines`: the lanes report's per-story lines;
- `final_body`: per story after its rulings, and once after the stories a `## Blocks file` section per distinct
  `— blocks <path>` with that file's content read from `FINAL_W`. The section is capped at 20000 bytes per file, and
  a cut file ends with `(truncated — read <path> on the branch)`.

The runner's grep is `^- [0-9-]+ ([^ ]+ )?Block: `. Nothing else in the runner changes: the unit moved `task`, so it
is progress, and no `Stop:` was written, so nothing holds.

### Gap B — required tools (#95)

**Config: a top-level key in the start checkout's `.studio/config.json`.**

```json
"required_tools": [
  { "cmd": "ffmpeg", "hint": "brew install ffmpeg" },
  { "cmd": "ffprobe", "hint": "brew install ffmpeg" },
  { "cmd": ".venv/bin/python", "min_version": "3.10",
    "hint": "worktree_setup must build .venv on python 3.10+: python3.12 -m venv .venv" }
]
```

- Fields: `cmd` (required), `hint` (required), `min_version` (optional, `^[0-9]+(\.[0-9]+)*$`) and `version_args`
  (optional, default `--version`, split on blanks).
- **Path entries.** A `cmd` containing `/` is a path relative to the worktree root. It is always run (the "runs"
  probe) and must exit 0, which is how a venv whose base interpreter is gone, or a broken venv, is caught.
- **Bare entries.** A bare `cmd` must be on PATH. It is run only when `min_version` is set.

**Parsing** (awk, no jq, as everywhere in the runner; one function `tools_entries` prints one TSV line per entry:
cmd, min, args, hint). Any of these is a refusal naming the key:

- a backslash anywhere in the array (escapes are not decoded);
- a non-object element;
- an entry without `cmd` or without `hint`;
- a bad `min_version`.

`required_tools` absent means nothing is printed and nothing is refused. An empty array is the same.

**The probe** for one entry in a directory D:

1. Resolve: a bare name with `command -v`, a path as `D/<cmd>`, which must be an executable file.
2. When it is a path, or `min_version` is set: run `<resolved> <version_args>`, stdin `/dev/null`, stdout and stderr
   together, capped at 10 s by the same cap `notify_operator` uses. It must exit 0.
3. With `min_version`: the version is the first `[0-9]+\.[0-9]+(\.[0-9]+)?` token of that output, compared
   numerically field by field.
   - No token: a stdout warning, not a refusal: `tools: <cmd>: cannot read a version from '<cmd> <args>' — check it by hand`.
   - Lower than the minimum: a refusal.
4. Refusals, one `refuse` line per miss, each ending with ` — install: <hint>`:
   - `required tool <cmd> not found on PATH`;
   - `required tool <cmd> not found in <D>`;
   - `required tool <cmd> does not run (exit <n>)` (124 when capped);
   - `required tool <cmd> is <v>, needs <min> or later`.
5. A pass contributes `<cmd> <version>`, or `<cmd> found` when no version was read, to one stdout summary line:
   `tools: ffmpeg found, ffprobe found, .venv/bin/python 3.12.7`.

**Where the probe runs.**

- `tools_check` runs in `preflight()`, in both modes, after the #90 push check and before `env_line`. It probes
  every bare entry with D = the start checkout.
- Path entries:
  - **When `worktree_setup` is unset**, `tools_check` probes them in the start checkout too.
  - **When it is set**, `start` and `--detach` (in the foreground) probe them in `setup_preflight`'s scratch
    worktree, after a green setup and before `sp_remove`. That tree is what a new story worktree looks like after its
    setup, which is where phoenix's 3.9 venv was built. A miss there is the same refusal: `say`, exit 2, scratch tree
    removed.
  - **`--dry-run`** probes them in the start checkout and adds the line
    `tools: path entries checked in the start checkout; start re-checks them after worktree_setup`.
  - **`--detach`'s child** (`STUDIO_OVERNIGHT_SETUP_CHECKED`) skips them, as it skips the setup.
- The units' PATH is the runner's PATH: `--detach` keeps PATH. So the PATH probe is the units' PATH.
- Usage text and the README's config section document the key.

### Gap C — runner-side gates read the run's config (#82)

**`STUDIO_START_DIR`.**

- Every launch the runner itself makes of `studio-gate`, `studio-setup`, `studio-test` or `studio-run` exports
  `STUDIO_START_DIR="$START_DIR"`, the same as `start_session`. That covers:
  - `final_gate`;
  - the landing's `studio-gate merge` (`land_once`);
  - `studio-setup` in `FINAL_W` (`final_integration`, `progress_direct`);
  - `setup_preflight`'s `studio-setup`.
- The plan's first step greps both scripts and lists every such call. The test pins the final gate. Any other call
  found gets the export too.

**`done` when the final PR is merged.**

- A new `runs_settle ROOT SLUG [--dry-run]` in `overnight-runs.sh` marks an open record done when all of these hold:
  - `RECORD/final` names a PR URL;
  - every id in `RECORD/rows.tsv` has a `RECORD/landed.tsv` line;
  - `gh pr view <url> --json state -q .state` prints `MERGED`.
- On a match it writes `RECORD/done` and prints `run <slug>: final PR <url> is merged — record marked done`. Under
  `--dry-run` it writes nothing and prints `… — start marks the record done`. Any gh failure prints and changes
  nothing.
- Callers:
  - `mf_check`, before it reads any record (its own slug: the start then refuses with today's "run <slug> is done:
    archive its record first");
  - `status`, before it lists records, so autopilot discovery stops listing a run whose final PR landed.
- A red final PR that is not merged stays open, as today.

## Acceptance criteria

1. Skill: §6a defines a Block (pinned reference) and keeps every listed Stop a Stop. It holds the procedure (pending
   marker on the failing assertions only, a blocks file entry, `T<n> Block: … — blocks <path>`, task complete, no
   `Stop:`) and the never-edit rule. §8 and §11 point to it. §7 step 4's body has `## Blocks`. §5 reports Blocks and
   excludes them from the fix wave. §9 has the blocks-file conflict rule. #93's pinned strings are unchanged.
2. `studio-brief task <n>` prints `blocks: <path>` for each of the three sources in order, and `studio-brief final`
   prints a `T3 Block: …` ledger line.
3. Lanes: a unit that writes a `Block:` line, the pending marker and a blocks file entry, and advances `task`, ends
   `progress`. The story is not held, it lands, and the integration final PR body lists the Block line and the blocks
   file's entry.
4. Lanes: a unit in the same position that writes `Stop: ffmpeg not found …` holds the story, as today.
5. Single plan: `report.md` has `## Blocks` with the Block line, or `(none)`.
6. Tools:
   - a stub PATH without `ffmpeg` and `required_tools` naming it: `start` and `--dry-run` exit 2 with
     `required tool ffmpeg not found on PATH — install: brew install ffmpeg`, and no session runs;
   - with a stub ffmpeg on PATH: they pass, and stdout has `tools: ffmpeg found`.
7. Tools: a stub `.venv/bin/python` printing `Python 3.9.6` with `min_version` 3.10 is refused with `is 3.9.6, needs
   3.10 or later`. One printing `Python 3.12.7` passes with `.venv/bin/python 3.12.7`. One exiting 1 is refused with
   `does not run (exit 1)`.
8. Tools: with `worktree_setup` set, `start` probes the path entry in the scratch worktree: a setup that builds the old
   venv there is refused even when the start checkout's venv is new. `--dry-run` prints the path-entries note.
9. Tools: no `required_tools` key gives byte-identical preflight stdout to today's. A malformed key (no `hint`, a
   backslash) is a refusal naming the key. A version that cannot be read is a warning only.
10. #82: with the run worktree's config holding `"test_engine_args": "--fixed-fps 60"` and an integration worktree
    without a config, the final gate's command sees `test_engine_args` = `--fixed-fps 60` through `studio_cfg`, and
    the landing's merge command sees `STUDIO_START_DIR`.
11. #82: a record whose final PR the stub gh reports `MERGED`, with every story landed, is marked done by `start` and
    by `status`, and `--dry-run` writes nothing. `OPEN`, or a gh failure, leaves it open.
12. README, the usage text and PROGRESS are updated, and the full gate (`sh tests/run_all.sh`) is green.

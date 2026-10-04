# Autopilot Adopts Outside Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Status: Approved (operator, 2026-10-04, with D4 and D27)

**Goal:** Let `/omega:autopilot` adopt a story that was planned, and maybe partly
built, outside the studio. The original plan is kept and converted 1:1 into a
studio plan. Finished work is taken from verified SDD claims. The story branch's
`.studio/ledger/<id>.md` becomes the one record, and both the studio and
superpowers' SDD can resume the story from it at any time.

**Architecture:** There are two new POSIX `sh` tools in `studios/game-dev/bin/`:
- `studio-adopt` (`inspect`, `seed`, `sync`) holds every exact rule: the base,
  claim parsing, chain checks, part-done detection, views and the landed note.
  One engine serves all three verbs.
- `studio-setup` runs the project hooks under the gate lock: `worktree_setup`,
  with its marker and timeout, and `gate_command`, through its `gate` verb.

Existing tools gain small, targeted changes:
- `studio-state` ignores `T<n> complete` lines before the last `adopt reset`.
- `studio-gate` keeps its times window per `who`.
- `studio-brief` gains `Context:`, the `final` fallback and a `check` verb.
- The runner (`studio-overnight`, `overnight-lanes.sh`) gains the `check` unit,
  the config keys, the gate room for `gate_command`, the gate-repair log choice,
  the `Context:` preflight, setup and `gate_command` at the final integration,
  and the report lines.

The judgment steps (gap check, conversion, approval) live in the autopilot skill,
and the per-unit steps in the execute skill. Both are pinned by contract tests.

**Tech Stack:** POSIX sh (macOS `/bin/sh` = bash 3.2; Linux `dash`), git ≥ 2.38
(the runner already requires it), BSD/GNU sed, awk, grep, `cksum`. No new dependencies.

**Spec:** `docs/game-dev/specs/2026-10-04-autopilot-adopt.md` (approved, commit
2986b0b). All `L<a>-<b>` references below are lines of that file.

**Story:** #35 (GitHub issue). Branch worktree-issue-35-autopilot-adopt.

**Review policy (user CLAUDE.md):**
- Each task carries `Spec:` (its spec line ranges) and `Review: task|final`
  under its heading.
- A `Review: task` task gets a per-task review on Opus (`model: "opus"`). A
  `Review: final` task folds into the final review.
- Minor findings are batched into the final fix wave. Every fix round goes to
  a fresh fixer given the findings and the diff range.
- Re-review only after a Critical, three or more Importants, or a
  production-bug fix. Never a third pass.
- The final review is a standalone whole-branch review on Opus, never folded
  into the last task review. Then the full gate.
- One task = one implementer with its own test cycle; tasks run sequentially on
  this branch. Hand-backs are 1.5k characters or less; full reports go to a file.

## Prerequisite — #37 is merged first

#37 (resource readout and progress bar) changes `studio-overnight` status/watch/start
preflight, adds `studios/game-dev/bin/studio-env`, and changes their tests. It merges
to `main` before Task 1. Before Task 1 the controller runs this in the worktree:

```sh
git fetch origin
git merge --no-edit origin/main          # on worktree-issue-35-autopilot-adopt
test -x studios/game-dev/bin/studio-env || echo "MISSING: #37 (studio-env)"
sh tests/run_all.sh                       # green on the merged base
sh integrations/multica/tests/run.sh      # green on the merged base
# Re-locate every anchor this plan names (line numbers below are pre-#37):
for f in model_for preflight gate_room_check snapshot label_for story_units run_unit lock_live cfg cfg_str cfg_raw; do
  printf '%s: ' "$f"; grep -n "^$f()" studios/game-dev/bin/studio-overnight | head -n 1; done
for f in mf_check story_first_label gate_log_of gate_repair story_ledger_lines story_units_table \
         lanes_report final_gate_cmds final_gate final_integration progress_direct next_match lanes_next record_landed; do
  printf '%s: ' "$f"; grep -n "^$f()" studios/game-dev/bin/overnight-lanes.sh | head -n 1; done
grep -n 'spec-refusals"$' studios/game-dev/bin/overnight-lanes.sh
grep -n 'tail -n 49' studios/game-dev/bin/studio-gate
grep -n "T\\\\([0-9]*\\\\) complete" studios/game-dev/bin/studio-state
```

A `MISSING:` line, a red suite, or an empty grep stops the plan. Each
anchor below gives a line number from the pre-#37 file plus the `grep -n`
pattern that finds it again. The implementer always uses the grep.

## Global Constraints

Copied verbatim from the spec, with line numbers in parentheses. Every task's
requirements implicitly include this section.

**Interfaces and exits**
- `studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <sha>]` ·
  `studio-adopt seed <id> [--reset]` (in the story checkout) · `studio-adopt sync <id>`
  (in a checkout of the story branch) · "Exit: 0 clean / in sync · 1 a mismatch or a
  refused precondition (one stderr line naming it) · 2 usage" (L292-297). D27 adds
  `[--base <sha>]` to `seed`.
- `studio-adopt --help` gives each verb, its exit codes and an example (L64).
- Inspect with no workspace and counted commits: exit 1, `work on <Branch> past <base7> but no SDD ledger for <plan> in any worktree — restore it, or write one in SDD's format, and inspect again` (L148).
- Rewrite: `history of <Branch> was rewritten after T<n> — re-adopt: studio-adopt seed <id> --reset` (L173).
- Live run: `story <id> is in a live run — /hold it or wait for it to end` (L166).
- `Context:` refusal: `<id>: Context file <path> is not in Docs: <sha>` (L220).

**Ledger lines** (`- YYYY-MM-DD <text>`, written through `studio-state ledger`):
- `source <plan> spec <spec or ->` (L103), `verdict adopt` / `verdict plan` (L110),
  `adopted <original> -> <converted plan>` (L132), `adopt-base <full sha>`,
  `adopt reset <HEAD sha>` (L151, L156);
- `T<n> complete <full sha>..<full sha>` (L151, L177, L246);
- `check requested` (L136), `check done <range of its fix commits, or none>`,
  `check Ruling: <decision> — <why> — <cost if wrong>`, `Stop: check — <reason>` (L202-205);
- `minor (deferred) T<n>: <text> (standard mode)` and `T<n> Ruling: <text>` (L182);
- `Stop: adopt sync — <its stderr line>` (L194),
  `Stop: worktree setup failed — exit <n> — log <path>` (L229),
  `Stop: gate red — gate_command exit <n> — log <path>` (L232).

**Commit subjects:** `chore(studio): ledger (adopt)` (L152), `chore(studio): ledger (sync)` (L177).

**SDD views** (L84-85, L180): the identity line is `# SDD ledger — plan: <plan path>`; then one
`Task <n>: complete (commits <a>..<b>, review clean)` per truth task, then every
other line the old file had, in order. The workspace is
`<worktree root>/.superpowers/sdd/<plan basename>/`, owned by `plan-path`, and
`.superpowers/sdd/.gitignore` contains `*`.

**Fixed lines and texts**
- Landed note: `Landed: integration/<slug> at <sha> — continue dependent stories from there` (L181).
- Part-done: `T<k+1> in progress: <first>..<last>` / `post-task commits: <first>..<last>` (L191);
  brief line `commits already on the branch for this task: <first>..<last> — check and finish them; do not start over` (L212).
- Report (L242-243):
  - `Adopted from <original plan>. To continue the standard way: cd <story worktree> && <absolute path>/studio-adopt sync <id>`;
  - `Adopted from <original plan>; landed on integration/<slug> — continue dependent stories from there`.
- Agent instructions (L244): `For adopted stories, include the report's studio-adopt line in your summary.`

**Hooks**
- `worktree_setup` runs under `studio-gate setup -- sh -c '<command>'`.
  - Timer: `worktree_setup_minutes`, default 20, range 1–120. It starts once the gate
    lock is held, and a timeout ends the command's process group.
  - Log: `.studio/reports/setup-<stamp>.log`.
  - Marker: `$(git rev-parse --git-dir)/studio-setup.done`, holding a hash of the command (L225-227).
- `gate_command` runs under `studio-gate gate -- sh -c '<command>'`, after `studio-test`.
  Its log is `.studio/reports/gate-<stamp>.log` (L231-232).
- `studio-gate` keeps the last 50 `.studio/gate.times` lines per `who` (L230).
- `gate_room_check` sums the slowest of the last 10 `studio-test` entries and the slowest
  of the last 10 `gate` entries (L235).

**Tuning:** `worktree_setup_minutes` default 20; the `Context:` cap is 12,000 characters (L334-335, L218).

**Platform and process**
- macOS and Linux, POSIX `sh`, as the runner today; no new dependencies (L71).
  Every script must parse with `sh -n` and run under macOS `/bin/sh` (bash 3.2):
  no arrays, no `local`, no `[[`, no `$(< )`, no GNU-only flags (`sed -i` without a
  suffix, `timeout`, `readlink -f`, `date -d`).
- `inspect` and `sync` finish in seconds on a branch with hundreds of commits (L76).
  Per-commit work is one `git log` call over the range, never one git call per commit.
- No new event types. The check unit uses `unit_started`/`unit_ended` with `label`
  `check`; setup and sync failures use `story_state` `held` (L245).
- Every failure stops in a visible place, with the reason and the way out. No step guesses,
  and none applies part of a change. A mismatch never auto-repairs (L59-60).

**Project rules**
- Public repo: committed files hold no workspace data, OS username, real issue
  titles or machine paths. Fixtures use made-up ids (`S1`, `S2`, `demo`).
- Tests follow `tests/assert.sh` (`assert_eq`, `assert_contains` (BRE on a file),
  `assert_not_contains`, `assert_status CODE MSG -- cmd…`, `assert_file`,
  `assert_missing`, `run_tests NAME…` with `TESTS_ONLY`). They use fixture git repos
  in `mktemp -d`, run offline with no model calls, and set a temp `HOME`. The engineer
  never runs install/uninstall against the real HOME.
- New bins are committed executable (`chmod +x`; `test_bin_syntax` checks it).

## Decisions

Rulings on what the spec leaves to implementation.

- **D1:** The spec's `tests/studio_state_test.sh` and `tests/studio_gate_test.sh` are
  the existing `tests/state_test.sh` and `tests/toolkit_test.sh` (the gate tests
  live at `grep -n '^test_gate_' tests/toolkit_test.sh`). New cases go there — new files would duplicate their fixtures.
- **D2:** The truth region is "lines after the last `adopt reset` line". One awk filter, used by both
  `studio-state` readers and by `studio-adopt`:
  `awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }'` — the same rule everywhere.
- **D3:** `studio-gate` keeps a line when fewer than 50 later lines share its `who`. A line from a
  new `who` never evicts another `who`'s line (AC19's purpose).
- **D4:** `studio-setup` has two verbs:
  - `studio-setup` (no argument) runs `worktree_setup`;
  - `studio-setup gate` runs `gate_command`.

  Execute §0/§7/§8 and the runner call these instead of assembling
  `studio-gate … sh -c` in prose. Why: the lock, log and exit-line rules exist once
  (the spec's own rejection of prose for exact behaviour, L324), and the file list
  stays as the spec's (L269). The operator may veto this; the alternative is prose
  plus a runner copy.
- **D5:** `studio-setup` (worktree) exits 0 when it ran green, when the marker
  matched (no-op), or when `worktree_setup` is unset (silent).
  - On a failure or timeout it exits 1, with one stderr line
    `worktree setup failed — exit <n> — log <path>`. `<path>` is relative to the tree
    root, `n` is the command's status, and a timeout is `124`.
  - It exits 2 on usage, or on bad config: minutes outside 1–120 or not an integer,
    or a value containing `\`.
- **D6:** The timer:
  - `{ set -m; } 2>/dev/null`, then studio-gate is launched in the background, so
    it leads its own process group.
  - studio-setup polls `$STATE_ROOT/.studio/gate.lock/pid` once a second until it
    names the gate's pid; the timer starts there.
  - With no `$STATE_ROOT/.studio`, or `STUDIO_GATE_HELD` naming the live holder
    (re-entry: studio-gate execs the command), the timer starts at launch.
  - On timeout it sends `kill -TERM "-$pid"`, falling back to `kill -TERM "$pid"`.
    studio-gate forwards TERM to the command's group and sends KILL at about 10 s.
    No GNU `timeout`.
  - `wait "$pid" 2>/dev/null` hides the shell's job notice.
  - Test hook: `STUDIO_SETUP_TIMEOUT_SECONDS` replaces minutes × 60.
- **D7:** The marker holds `printf '%s' "<command>" | cksum` (`<crc> <bytes>`). It is
  written only after exit 0. A changed command does not match, so it runs again.
- **D8:** Config comes from `<tree root>/.studio/config.json`, else
  `$STATE_ROOT/.studio/config.json`.
  - Values are read like `cfg_str` and `cfg_raw`: the first match, the string as
    `"\([^"]*\)"` and minutes as a bare token.
  - A value with `\` is refused (it would be a JSON escape the reader does not decode).
  - The runner's preflight validates the same keys: `cfg_str worktree_setup '' '^[^\\]*$'`,
    `cfg_str gate_command '' '^[^\\]*$'`, `cfg worktree_setup_minutes 20 1 120 int`.
- **D9:** `studio-setup gate`:
  - It runs `studio-gate gate -- sh -c "$GATE_COMMAND"` in the foreground from the
    tree root, with output to `.studio/reports/gate-<stamp>.log`.
  - It exits with that status: studio-gate's 129/130/143 pass through for the
    runner's `gate_signalled`.
  - Green: stdout `gate_command: green — log <path>`.
  - Red: stderr `gate_command exit <n> — log <path>`.
  - Unset: exit 0, no output.
  - Both verbs ensure `.studio/reports/.gitignore` holds `*`, as `run_setup` does
    for the start checkout.
- **D10:** `final_gate_cmds` always appends `&& sh '<SELF_DIR>/studio-setup' gate`. The test hook
  `STUDIO_OVERNIGHT_GATE_CMD` replaces only the engine part. Inside `final-gate`, the
  nested studio-gate is a re-entry (no second lock, no times line).
- **D11:** The final integration runs `studio-setup` in `FINAL_W` after Step 1. On a failure:
  - `FINAL_GATE=red` and `FINAL_COLOR=red`, with the note `worktree setup failed — exit <n> — log <FINAL_W>/<path>`;
  - Step 2 still runs (a red PR still carries PROGRESS);
  - Step 3 skips the gate and final-repair;
  - `RECORD/gate` is not written, so a resume re-runs setup;
  - Steps 4–6 open the PR as red.
- **D12:** `progress_direct` runs `studio-setup` after its worktree is added or reused. A failure
  sets `FINAL_COLOR=red` with the same note, and returns 1 before the progress unit.
- **D13:** The `gate_room_check` sum is `_gr_s = max10(studio-test) + max10(gate)`. The message
  keeps `the slowest of the last 10 studio-test runs` when there are no `gate` entries.
  When there are, it says `the slowest of the last 10 studio-test runs plus the slowest of the last 10 gate_command runs`.
  "a finish unit runs it" becomes "a finish or check unit runs them".
- **D14:** `gate_log_of DIR` takes the feature ledger's newest `Stop:` line (`ledger_of DIR`):
  - when it ends ` — log <path>`, that path (relative paths prefixed with `DIR/`);
  - else the newest `test-*.log`;
  - else `-`.
- **D15:** Check unit (runner):
  - `snapshot` sets `SIG_CHK` (the count of `^- [0-9-]* check done`) and `SIG_CHKREQ`
    (the count of `^- [0-9-]* check requested$`) from the feature ledger, and `SIG`
    gains `;chk=$SIG_CHK`.
  - `label_for` returns `check` first when `SIG_CHKREQ > 0 && SIG_CHK = 0`, ahead of
    its `plan:*` case too ("ahead of its other rules", L208).
  - `model_for check` → `MODEL_FINAL`.
  - `story_first_label` sets both from the story's ledger (`set -u`).
  - `story_units_table`'s label regex gains `check`; otherwise the report drops check units.
- **D16:** `studio-brief check <k>` prints, in order:
  - the plan's `## Global Constraints`, `## Decisions` and `## Acceptance criteria`
    (each, or a one-line note when absent);
  - for each n in 1..k, the `### Task <n>:` block and its `Spec:` items (as `task`);
  - `range: <adopt-base>..<T_k end>` and `diff: git diff <adopt-base>..<T_k end>`;
  - directives, then `## Context files`.

  The shas come from the truth region (D2): the last `adopt-base` line, and T`k`'s
  last token's right side.
  - A missing `adopt-base` or `T<k> complete` line exits 1, naming it.
  - `check 0` prints `range: none — no finished task` and no task blocks. The check
    unit then runs only the gates and ledgers `check done none`.
- **D17:** `studio-brief final`:
  - When the spec has no `## Acceptance criteria`, it emits the state's plan's whole
    `## Acceptance criteria` and skips the `## Stories` row logic (that row lives in
    the epic spec, which an adopted story may not have).
  - Its ledger grep gains `check` as a prefix, `((T[0-9]+|Task [0-9]+:|check) )?`,
    so the final review sees the check unit's rulings.
- **D18:** `Context:` is read before the plan's first `## ` heading:
  `sed -n '/^## /q; s/^Context:[[:space:]]*//p'`. It is split on `,` and trimmed.
  - Files are included whole and in order while the cumulative `wc -c` stays ≤ 12000
    (bytes ≥ characters, so never over the cap).
  - The first file over the cap, and every file after it, go under
    `Read these as well:` as `- <path>`.
  - Each included file is `==> <path>:L1-<lines>` and its text (an empty file:
    `==> <path>:L0-0`).
  - A listed file missing from the tree exits 1: `Context file <path> not found`.
  - The part comes last in `task`; in `final` and `check` it comes before the `diff:`
    line, which stays last.
- **D19:** Shas are resolved with `git rev-parse --verify --quiet "<tok>^{commit}"`; an
  ambiguous or unknown token prints nothing and returns 1.
  - Truth-line tokens may be any length git accepts (4+).
  - Claim tokens are the maximal `[0-9a-f]` runs, of length 7–40, in the text after
    `commits `. A run that does not resolve is skipped.
  - `studio-adopt` writes full shas only.
- **D20:** The fork point is `n=$(git rev-list --count --first-parent <tip> --not origin/<default>)`
  then `git rev-list --first-parent --skip=$n --max-count=1 <tip>`.
  On a first-parent chain the commits not reachable from `origin/<default>` form a prefix.
  An empty result exits 1: `<Branch> shares no history with origin/<default> — pass --base <sha>`.
- **D21:** "Touches a path outside `.studio/`" and part-done use one call:
  `git log --first-parent --diff-merges=first-parent --name-only`. A merge is diffed
  against its first parent (git ≥ 2.31; the runner already requires 2.38).
- **D22:** Part-done leaves out a commit when **every** path it touches is under `.studio/`
  or is a docs path. Docs paths are the spec, the original, the converted plan and the
  `Context:` paths.
  Why: execute §0's new-branch commit `docs(<id>): approved plan` holds the spec, the
  plan and `.studio/ledger/<id>.md` together. Read as two separate "only" rules, AC11
  would count it.
- **D23:** Part-done's `origin/<Target>` comes from `$STUDIO_RUN`'s `Target:`, else from the
  manifest that `$STATE_ROOT/.studio/run` names. With neither, only `origin/<default>` is
  used.
- **D24:** The inspect report (stdout, exit 0), one item per line:
  - `story: <id>`;
  - `branch: <Branch>`, or `branch: <Branch> (not started)`;
  - `base: <full sha>`;
  - one `workspace: <dir> (<n> claims)` per workspace, or `workspace: none`;
  - one `T<n> complete <a>..<b>` per finished task;
  - `k: <k>/<N>`;
  - optionally `T<k+1> in progress: <first>..<last>` or `post-task commits: <first>..<last>`.

  Shas are full. `N` is the count of the original's `### Task [0-9]` headings above
  `## Backlog`.
  - Zero tasks: exit 1.
  - A claim numbered above `N`: a mismatch.
- **D25:** Inspect's evidence is the claims, the base and the commits. It ignores any truth
  lines on the branch (the story has none before seed).
  - The tip is `refs/heads/<Branch>`, else `refs/remotes/origin/<Branch>`. With neither,
    the story is not started.
  - The original plan is read from the current tree, else from `$STATE_ROOT` (`plan_file`).
- **D26:** Seed:
  - The base is the truth's `adopt-base` if present, else `--base`, else the fork point.
    An existing `adopt-base` that differs from `--base` exits 1.
  - The current branch must equal the story pointer's `branch`.
  - `source`, `adopted` and `check requested` come from `$STATE_ROOT/.studio/ledger/<id>.md`.
  - Titles are the exact text after `### Task <n>: `.
  - Each line is written only when absent from the truth region. An existing
    `T<n> complete` with a different range is a mismatch.
  - At most one commit (`chore(studio): ledger (adopt)`, only when a line was written),
    and no push (execute pushes with the story's first task).
- **D27:** `seed` also takes `[--base <sha>]`, so the base inspect used with `--base` is the base
  seed writes. Otherwise seed would recompute the fork point and could disagree with
  inspect. This adds to the spec's usage (L294); see Spec defects.
- **D28:** Seed `--reset`:
  - It appends `adopt reset <HEAD sha>`.
  - Then it seeds from the claims, with the base rule of D26 applied to the new
    (empty) truth region.
  - It copies `source` and `adopted` again, so the truth region is whole.
- **D29:** Sync preconditions, in order. A failing step writes nothing.
  1. The story pointer exists, or `STUDIO_STORY=<id> studio-state init` makes it
     (git-excluded, idempotent).
  2. `<Branch>` is the pointer's `branch` when it is not `-`, else the row of
     `$STUDIO_RUN` or of the manifest that `.studio/run` names. With none: exit 1.
  3. The current branch equals `<Branch>`.
  4. `git fetch origin <Branch>`, with the git-lock retry. A failure exits 1.
     With no `origin/<Branch>`, steps 5–6 are skipped.
  5. Behind: `git merge --ff-only origin/<Branch>`. A failure exits 1.
  6. Diverged (neither side an ancestor of the other): exit 1, `<Branch> has diverged from origin/<Branch> — reconcile it by hand, then sync`.
  7. The live-run check (D30).
  8. Push only when a commit was made. A rejected push is a stderr warning and exit 0
     (execute's "a rejected push is a Ruling", §8).
- **D30:** The live run, per the lock: `pid=` alive with `studio-overnight` in its
  `ps -o args=`, and `run=` holding `manifest.md`. It "has the story" when
  `run/stories/<id>` is `running`, `held …`, `repair`, `gate-repair` or `landing`.
  - Absent, `queued`, `waiting` and ending records are free.
  - Single-plan runs have no story records and are not checked.
  - The own-unit exemption compares the **incoming** `STUDIO_STORY`, captured before
    the script exports its own.
- **D31:** A truth line whose `b` is not an ancestor of HEAD:
  - Let `n` be the first such task. The message names `T<n-1>`; when `n = 1` it reads
    `history of <Branch> was rewritten after its adopt base — re-adopt: studio-adopt seed <id> --reset`.
  - An `adopt-base` that is not an ancestor of HEAD gives the same "after its adopt base" message.
  - An unresolvable token is a plain mismatch naming the line.
- **D32:** Views are written in the current tree only.
  - The directory is found by an exact copy of superpowers 6.4.1 `sdd-workspace`'s `owns()`:
    1. `<slug>`, then `<slug>-<parent dir basename>`, then `<slug>-<parent>-<n>`
       from 2;
    2. a missing marker is adopted by writing it;
    3. `<parent>` of a root-level plan is the toplevel's basename.
  - The identity line names the repo-relative plan path.
  - The file is the identity line, the truth's Task lines, then the old file minus its
    identity, `Task <n>: complete (`, and `Landed: ` lines. It goes through a temp file
    and `mv`.
  - Reading ignores marker-less workspaces.
- **D33:** Landed note:
  - The slug comes from `$STUDIO_RUN`'s `# Run:`, else from the `.studio/run` manifest's
    `# Run:`.
  - `$STATE_ROOT/.studio/runs/<slug>/landed.tsv` lines are `<id>\t<Target>\t<sha>\t<epoch>`;
    the last line for `<id>` gives `Landed: <Target> at <sha> — …`.
  - It goes last in the original's view only. With no slug or no record, there is no note.
- **D34:** AC10f, for SDD lines `Task <n>: …` with `n ≤ k`, from every workspace of the original:
  - `parked — <x>` → `minor (deferred) T<n>: <x> (standard mode)`;
  - `minor (deferred): <x>` → the same;
  - any other line containing `Ruling: ` (not `complete (`, not `fix round`) →
    `T<n> Ruling: <text after the first "Ruling: ">`.

  Each is written only when its text is absent from the truth region. It goes in the
  same single commit as the accepted claims (seed: the adopt commit).
- **D35:** Sync's task view runs `studio-state check --rebuild` only when the pointer's stage is
  `execute`. Otherwise the report says `task view: skipped (stage <s>)`.
- **D36:** The sync report (stdout, exit 0), one item per line:
  - one `accepted: T<n> <a>..<b>` per accepted task, or `already in sync`;
  - `k: <before>/<N> -> <after>/<N>`;
  - `kept: <n> lines in <view dir>` per view;
  - `trees: <path>[, <path>…]`;
  - the part-done line when there is one;
  - `pushed <Branch>`, or `push failed: <first stderr line>` (only when a commit was made).
- **D37:** In execute §0, the docs-sync commit (made only when the docs changed) comes before setup
  and sync, as the spec orders them (L194, L228). If the branch is also behind
  `origin/<Branch>`, it has then diverged, and sync holds the story. This is
  spec-conformant, because a mismatch never auto-repairs; §0 says so.
- **D38:** The runner names a unit before it runs. The first unit after a standard-mode task is
  labelled by the pre-sync `task`: it is `T5` in the round trip, although its sync moves
  `task` to 5/6 and it builds T6. Labels name files only (`label_for`'s comment, D8 of
  the lanes spec). The round-trip test asserts the commits, not that label.
- **D39:** Report lines:
  - The original comes from the last `adopted <original> -> …` line, read through
    `story_ledger_text`. This is `story_ledger_lines` split into a source reader plus
    its existing filter.
  - The worktree is `studio-state worktree`'s path, else
    `<STATE_ROOT>/.claude/worktrees/<Branch with / → ->`.
  - The tool is `$(sq "$SELF_DIR/studio-adopt")`.
  - The landed line names `$MF_TARGET` (`integration/<slug>` in integration mode).
- **D40:** The `Context:` preflight reads the header from `$MF_TMP/plan` (the plan at `Docs:`)
  and checks each path with `git -C "$START_DIR" cat-file -e "$MF_DOCS:<path>"`.
- **D41:** Autopilot AC1 runs `STUDIO_STORY=<id> studio-state init` before ledgering `source …`,
  because `studio-state ledger` refuses a story with no pointer (`need_state`).
- **D42:** The superpowers version is pinned in `studio-adopt --help` and in the autopilot adopt
  branch ("superpowers 6.4.1's sdd-workspace rule"). `test_adopt_workspace_lookup_two_trees`
  checks the collision names (the spec's "contract test pins the rule", L377).
- **D43:** The lanes test stub's `auto` mirrors execute §0 and §6:
  - It writes `T$k complete <a>..<b>` with full shas: `a` is HEAD before the task
    commit, `b` the task commit.
  - After the docs sync and `set branch`, it runs the real `studio-setup`, then
    `studio-adopt sync` when the feature ledger has an `adopted` line. Either one's
    exit 1 writes and commits `Stop: …` and ends the unit.
  - It handles the check unit: ledger `check done none`, commit, push.
  - A new action `gatecmd` runs `studio-setup gate` in the worktree. On red it writes
    and commits the `Stop: gate red — gate_command exit <n> — log <path>` line.

## AC coverage

| AC | Task | Test(s) |
|----|------|---------|
| 1 source plan/spec question, `source` line | T10 | `test_autopilot_contract` (adopt block) |
| 2 inspect + gap check + verdict | T10 | `test_autopilot_contract` |
| 3 `plan` stories, `adopted` after planning, seed refuses changed titles | T10, T5 | `test_autopilot_contract`; `test_adopt_seed_refuses_changed_title` |
| 4 conversion 1:1, `Spec:` formats, `Review:`, conflict scan | T10, T3 | `test_autopilot_contract`; `test_brief_original_plan_item` |
| 5 approval order, `next` → planned | T10, T8 | `test_autopilot_adopt_order`; `test_lanes_next_adopted_planned` |
| 6 git-ignored carry files → `docs/game-dev/adopted/<id>/`, `Context:` | T10, T3, T8 | contract; `test_brief_context_*`; `test_lanes_context_preflight` |
| 7 check the built work? → `check requested` | T10 | `test_autopilot_contract` |
| 8 inspect | T4 | `test_adopt_inspect_*`, `test_adopt_claim_*`, `test_adopt_main_merged_between_tasks` |
| 9 seed, idempotent, `--reset`, readers ignore pre-reset, not-started `adopt-base` | T5, T1, T9 | `test_adopt_seed_*`; `test_state_check_ignores_before_adopt_reset`; `test_execute_adopt` |
| 10a preconditions | T6 | `test_sync_preconditions`, `test_sync_live_run_refusal`, `test_sync_own_unit_exempt`, `test_sync_diverged_and_behind` |
| 10b verify truth | T4 (engine), T6 | `test_sync_truth_mismatches`, `test_sync_rewrite_message`, `test_sync_ambiguous_short_sha` |
| 10c accept claims | T4 (parse), T6 | `test_sync_accepts_claims`, `test_sync_all_or_nothing`, `test_sync_claim_end_differs` |
| 10d views | T6 | `test_sync_views_keep_other_lines`, `test_adopt_workspace_lookup_two_trees` |
| 10e landed note | T6 | `test_sync_landed_note` |
| 10f rulings carried | T5, T6 | `test_adopt_seed_carries_rulings`, `test_sync_carries_rulings_once` |
| 10g report | T6 | `test_sync_accepts_claims`, `test_sync_second_run_noop` |
| 11 part-done | T4, T6 | `test_adopt_part_done_filter`, `test_adopt_post_task_commits` |
| 12 sync at readiness, at §0, by hand | T10, T9, T8, T6 | contract tests; `test_lanes_adopt_sync_fail_holds`; T11 round trip |
| 13 check unit | T9, T3, T8 | `test_execute_adopt`; `test_brief_check_*`; `test_lanes_check_unit_first` |
| 14 runner support | T7 | `test_overnight_check_unit`, `test_lanes_gate_room_warning` (extended) |
| 15 §8 Which unit | T9 | `test_execute_adopt` |
| 16 part-done brief line | T9, T4 | `test_execute_adopt`; `test_adopt_part_done_filter` |
| 17 briefs | T3 | `test_brief_final_plan_acceptance`, `test_brief_check_*`, `test_brief_original_plan_item` |
| 18 `Context:` | T3, T8, T9 | `test_brief_context_*`; `test_lanes_context_preflight`; `test_execute_adopt` |
| 19 `worktree_setup` | T2, T1, T8, T9 | `test_setup_*`; `test_gate_times_window_per_who`; `test_lanes_setup_fail_*`; `test_execute_adopt` |
| 20 `gate_command` | T2, T7, T8, T9 | `test_setup_gate_*`; `test_lanes_gate_log_from_stop`, `test_lanes_gate_room_warning`; `test_lanes_gate_command_*`; `test_execute_adopt` |
| 21 `studio-gate <who>` rule in converted Global Constraints | T10 | `test_autopilot_contract` |
| 22 report lines | T8 | `test_lanes_report_adopted_lines` |
| 23 agent instructions | T10 | `test_agent_instructions_adopted_line` |
| 24 no new events | T8 | `test_lanes_check_unit_first` (event label), `test_lanes_adopt_sync_fail_holds` |
| 25 full-sha `T<n> complete` | T9, T8, T4 | `test_execute_adopt`; stub `auto`; `test_adopt_short_sha_lines_parse` |
| Milestone gate 1 | T1–T11 | Final gate step 2 |
| Milestone gate 2 | T11 | `test_lanes_adopt_round_trip` |
| Milestone gate 3 | Final gate step 3 | operator-run table |

## Review Focus

The input classes most likely to bite, most likely first. Each is pinned by a
test in the task that owns the code.

1. **Short and ambiguous shas.** A 4-hex truth token matching two commits, a claim
   token that is a hex-looking word, or a claim with one resolvable token.
   Each must be a named mismatch, never a guess.
   Tests: T6 `test_sync_ambiguous_short_sha`, T4 `test_adopt_claim_tokens`.
2. **`main` merged mid-branch.** The merge sits inside a task range, and the
   fork point must stay the original one. Part-done must leave the merge out.
   Tests: T4 `test_adopt_main_merged_between_tasks`, `test_adopt_part_done_filter`.
3. **History rewritten (rebase).** Inspect and sync name the rewrite.
   `seed --reset` re-adopts, and every reader ignores the lines before the reset.
   Tests: T5 `test_adopt_seed_reset_after_rebase`, T1 `test_state_check_ignores_before_adopt_reset`.
4. **Setup timeout with a grandchild.** The timer starts only after the lock is held,
   and the timeout must end the whole group.
   Tests: T2 `test_setup_timeout_ends_group`, `test_setup_timer_starts_after_lock`.
5. **Concurrent writers.** A live run holds the story, the run's own unit syncs,
   and the branch can be behind or diverged.
   Tests: T6 `test_sync_live_run_refusal`, `test_sync_own_unit_exempt`, `test_sync_diverged_and_behind`.

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `studios/game-dev/bin/studio-state` | T1 | `check` and `check --rebuild` read T lines from the truth region |
| `studios/game-dev/bin/studio-gate` | T1 | gate.times window per `who` |
| `studios/game-dev/bin/studio-setup` (new) | T2 | `worktree_setup` (marker, timer, log) and `gate` (`gate_command`) |
| `studios/game-dev/bin/studio-brief` | T3 | `Context:` appendix, `final` fallback, `check <k>` verb, `check` rulings |
| `studios/game-dev/bin/studio-adopt` (new) | T4–T6 | engine + `inspect` (T4), `seed` (T5), `sync` (T6) |
| `studios/game-dev/bin/studio-overnight` | T7 | check unit (snapshot, label_for, model_for), config keys, gate room |
| `studios/game-dev/bin/overnight-lanes.sh` | T7, T8 | T7: story_first_label, gate_log_of, units table; T8: Context preflight, final-integration setup and gate, report lines |
| `studios/game-dev/skills/execute/SKILL.md` | T9 | §0, §6, §7, §8, §11 |
| `shared/omega/skills/autopilot/SKILL.md` | T10 | phase 1 adopt branch |
| `integrations/multica/agent-instructions.md`, `integrations/multica/README.md` | T10 | AC23, Teaching |
| `tests/state_test.sh`, `tests/toolkit_test.sh` | T1 | reset filter, per-who window |
| `tests/studio_setup_test.sh` (new) | T2 | studio-setup suite |
| `tests/studio_brief_test.sh` | T3 | brief cases |
| `tests/studio_adopt_test.sh` (new) | T4–T6 | adopt suite |
| `tests/overnight_test.sh` | T7 | single-plan check unit, config refusals |
| `tests/overnight_lanes_test.sh` | T7, T8, T11 | gate room, gate log, stub, lanes cases, round trip |
| `tests/studio_test.sh` | T9 | `test_execute_adopt` |
| `tests/omega_contracts/autopilot_contract.sh` | T10 | adopt-branch phrases and order |
| `integrations/multica/tests/readme_test.sh` | T10 | README phrase, agent-instructions line |

Order: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 (see Falsify → Task order).

---

### Task 1: Truth region in `studio-state`, per-`who` window in `studio-gate`

Files: `studios/game-dev/bin/studio-state` (the two T-line readers: :291 in `check --rebuild`, :316 in `check` — `grep -n "T\\\\([0-9]*\\\\) complete" studios/game-dev/bin/studio-state`), `studios/game-dev/bin/studio-gate` (times window :220-224 — `grep -n 'tail -n 49'`; header comment :21-24 — `grep -n 'newest 50 lines'`), `tests/state_test.sh`, `tests/toolkit_test.sh`
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L156-156, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L230-230, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L271-272, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L360-361
Review: final

**Interfaces:**
- Produces:
  - `studio-state check [--rebuild]` ignores ledger lines before the last
    `- <date> adopt reset ` line (D2);
  - `.studio/gate.times` keeps ≤ 50 lines per `who` (D3).
- Consumes: nothing new.

- [ ] **Step 1: Write the failing tests.** In `tests/state_test.sh`, add the following and add it to `run_tests`:

```sh
# #35 AC9: T lines before the last `adopt reset` are not the truth.
test_state_check_ignores_before_adopt_reset() {
  P="$TMP/story-reset"; mkdir -p "$P/docs"
  ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    printf '# P\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > docs/p.md
    export STUDIO_STORY=RS; sh "$STATE_BIN" init
    sh "$STATE_BIN" set plan docs/p.md; sh "$STATE_BIN" set task 0/3
    sh "$STATE_BIN" ledger "T1 complete aaaa..bbbb"; sh "$STATE_BIN" ledger "T2 complete bbbb..cccc"
    sh "$STATE_BIN" ledger "T3 complete cccc..dddd"
    sh "$STATE_BIN" ledger "adopt reset 0123456789abcdef0123456789abcdef01234567"
    sh "$STATE_BIN" ledger "T1 complete eeee..ffff" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 1/3 "$(cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" get task)" "rebuild counts only the lines after the last adopt reset"
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" set task 3/3 ) >/dev/null 2>&1
  st=0; ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" check ) > "$TMP/out" 2>&1 || st=$?
  assert_contains "$TMP/out" "note — ledger has T1 complete, task is 3/3" "plain check reads the highest T line after the reset too"
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" ledger "adopt reset 1111111111111111111111111111111111111111" ) >/dev/null 2>&1
  ( cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" set task 0/3 && STUDIO_STORY=RS sh "$STATE_BIN" check --rebuild ) >/dev/null 2>&1
  assert_eq 0/3 "$(cd "$P" && STUDIO_STORY=RS sh "$STATE_BIN" get task)" "the last reset wins: nothing after it"
}
```

  In `tests/toolkit_test.sh`, add the following and add it to `run_tests`:

```sh
# #35 AC19: setup lines never push out studio-test lines.
test_gate_times_window_per_who() {
  gate_proj gtw
  { i=1; while [ "$i" -le 10 ]; do echo "$i studio-test 7 0"; i=$((i + 1)); done
    i=1; while [ "$i" -le 60 ]; do echo "$i setup 1 0"; i=$((i + 1)); done; } > "$GP/.studio/gate.times"
  ( cd "$GP" && sh "$GATE_BIN" setup -- true ) >/dev/null 2>&1
  assert_eq 10 "$(grep -c ' studio-test ' "$GP/.studio/gate.times")" "every studio-test line is kept"
  assert_eq 50 "$(grep -c ' setup ' "$GP/.studio/gate.times")" "setup keeps its newest 50"
  assert_contains "$GP/.studio/gate.times" '^[0-9][0-9]* setup [0-9][0-9]* 0$' "the new run is logged"
  assert_not_contains "$GP/.studio/gate.times" '^11 setup ' "the oldest setup lines went"
}
```
  (`gate_proj` sets `GP`; `GATE_BIN` is the suite's studio-gate path. Check the
  helper names with `grep -n '^gate_proj()\|GATE_BIN=' tests/toolkit_test.sh` and use
  what is there. `test_gate_unit_registration_and_times` stays unchanged and still passes.)

- [ ] **Step 2: Run to see them fail.**
  `TESTS_ONLY="test_state_check_ignores_before_adopt_reset" sh tests/state_test.sh` and
  `TESTS_ONLY="test_gate_times_window_per_who" sh tests/toolkit_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - In `studio-state`, add a helper next to `ledger_file`:
    ```sh
    # truth_lines FILE — FILE's lines after its last `adopt reset` line (all of
    # them when there is none): the ledger studio-adopt and check read (#35 D2).
    truth_lines() {
      awk '/^- [0-9-]+ adopt reset /{ n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }' "$1"
    }
    ```
    Both seds become `truth_lines "$_lf" | sed -n 's/^- [0-9-]* T\([0-9]*\) complete.*/\1/p' …`.
  - In `studio-gate`, replace the `tail -n 49` block with D3:
    ```sh
    { [ -f "$_times" ] && cat "$_times"
      printf '%s %s %s %s\n' "$(date +%s)" "$WHO" "$(( $(date +%s) - T0 ))" "${SIGSTATUS:-$rc}"
    } | awk '{ w[NR] = $2; l[NR] = $0 }
        END { for (i = NR; i >= 1; i--) keep[i] = (++c[w[i]] <= 50); for (i = 1; i <= NR; i++) if (keep[i]) print l[i] }' \
      > "$_times.$$" 2>/dev/null && mv -f "$_times.$$" "$_times" 2>/dev/null
    ```
    Update the header comment: "the newest 50 lines per `who` are kept".
- [ ] **Step 4: Run the tests** from Step 2. Expected: PASS.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `git commit -m "feat(studio): adopt-reset truth region and per-who gate times (#35)"` with the trailers.

---

### Task 2: `studio-setup` — `worktree_setup` and `gate_command`

Files: `studios/game-dev/bin/studio-setup` (new, executable), `tests/studio_setup_test.sh` (new)
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L224-236, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L318-319, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L334-334, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L358-358
Review: task

**Interfaces:**
- Produces:
  - **`studio-setup`**: run from any directory inside a worktree; it `cd`s to
    `git rev-parse --show-toplevel`.
    - Reads `worktree_setup` and `worktree_setup_minutes` (D8).
    - Exits 0 when it ran, when the marker matched, or when the key is unset.
      Exits 1 with one stderr line `worktree setup failed — exit <n> — log <path>`.
      Exits 2 on usage or bad config (D5).
    - Log: `.studio/reports/setup-<stamp>.log`, with stamp `date +%Y%m%d-%H%M%S`.
      On a timeout the log's last line is `studio-setup: timed out after <s> s`.
    - Marker: `$(git rev-parse --git-dir)/studio-setup.done` (D7).
  - **`studio-setup gate`**: runs `gate_command`, exiting with its status (D9).
    Green: stdout `gate_command: green — log <path>`. Red: stderr `gate_command exit <n> — log <path>`.
  - **`studio-setup --help`**: the usage, exit 0.
  - Test hook: `STUDIO_SETUP_TIMEOUT_SECONDS`.
- Consumes:
  - `studio-state root` (STATE_ROOT);
  - `studio-gate <who> -- <cmd>`, with its lock at `$STATE_ROOT/.studio/gate.lock/pid`,
    its re-entry rule, and TERM forwarding to the child's process group.

- [ ] **Step 1: Write the failing tests** in `tests/studio_setup_test.sh` (`run_all.sh` picks up `*_test.sh`):

```sh
#!/bin/sh
# Suite for studios/game-dev/bin/studio-setup (#35 AC19, AC20): the project
# hooks under the gate lock. Offline; temp repos; a temp HOME.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
SETUP="$REPO_ROOT/studios/game-dev/bin/studio-setup"
GATE="$REPO_ROOT/studios/game-dev/bin/studio-gate"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
unset STUDIO_GATE_HELD STUDIO_SETUP_TIMEOUT_SECONDS STUDIO_UNIT_TAG

# proj NAME CONFIG_JSON — $P: a committed studio project with that config.
proj() {
  P="$TMP/$1"; rm -rf "$P"; mkdir -p "$P"
  ( cd "$P" && git init -q -b main && sh "$STATE_BIN" init >/dev/null
    printf '%s\n' "$2" > .studio/config.json
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m init ) >/dev/null 2>&1
}
# setup DIR [ARGS] — studio-setup in DIR: SU_STATUS, $TMP/su.out, $TMP/su.err.
setup() { _d="$1"; shift; SU_STATUS=0; ( cd "$_d" && sh "$SETUP" "$@" ) > "$TMP/su.out" 2> "$TMP/su.err" || SU_STATUS=$?; }

test_setup_unset_is_silent() {
  proj un '{ "engine": "godot4" }'
  setup "$P"
  assert_eq 0 "$SU_STATUS" "no worktree_setup: exit 0"
  assert_eq "" "$(cat "$TMP/su.out" "$TMP/su.err")" "and silent"
  setup "$P" gate
  assert_eq 0 "$SU_STATUS" "no gate_command: exit 0"
}
test_setup_runs_under_lock_and_logs() {
  proj ok '{ "worktree_setup": "cat .studio/gate.lock/who > who.txt; echo ran >> ran.txt" }'
  setup "$P"
  assert_eq 0 "$SU_STATUS" "a green setup exits 0"
  assert_eq setup "$(cat "$P/who.txt")" "it ran holding the gate lock as setup"
  assert_eq 1 "$(ls "$P"/.studio/reports/setup-*.log | wc -l | tr -d ' ')" "one setup log"
  assert_contains "$P/.studio/reports/.gitignore" '^\*$' "reports are git-ignored"
  assert_contains "$P/.studio/gate.times" ' setup [0-9][0-9]* 0$' "gate.times has the setup line"
}
test_setup_marker_skip_and_rerun() {
  proj mk '{ "worktree_setup": "echo ran >> ran.txt" }'
  setup "$P"; setup "$P"
  assert_eq 1 "$(wc -l < "$P/ran.txt" | tr -d ' ')" "the marker makes the second call a no-op"
  assert_file "$P/.git/studio-setup.done" "the marker sits in the git dir"
  printf '{ "worktree_setup": "echo again >> ran.txt" }\n' > "$P/.studio/config.json"
  setup "$P"
  assert_eq 2 "$(wc -l < "$P/ran.txt" | tr -d ' ')" "a changed command runs again"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m cfg && git worktree add -q "$TMP/mk-wt" -b wt ) >/dev/null 2>&1
  setup "$TMP/mk-wt"
  assert_file "$TMP/mk-wt/ran.txt" "a new worktree (new git dir, no marker) runs it"
}
test_setup_nonzero_exit() {
  proj nz '{ "worktree_setup": "echo boom; exit 7" }'
  setup "$P"
  assert_eq 1 "$SU_STATUS" "a red setup exits 1"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "one stderr line"
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 7 — log \.studio/reports/setup-[0-9-]*\.log$' "naming the exit and the log"
  assert_missing "$P/.git/studio-setup.done" "no marker after a failure"
  assert_contains "$(ls "$P"/.studio/reports/setup-*.log)" '^boom$' "the log holds the output"
}
test_setup_timeout_ends_group() {
  proj to '{ "worktree_setup": "sleep 4801 & sleep 4802" }'
  STUDIO_SETUP_TIMEOUT_SECONDS=2; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS
  assert_eq 1 "$SU_STATUS" "a timeout exits 1"
  assert_contains "$TMP/su.err" '^worktree setup failed — exit 124 — log ' "exit 124 names the timeout"
  assert_eq 1 "$(wc -l < "$TMP/su.err" | tr -d ' ')" "no job-control noise on stderr"
  sleep 1
  assert_eq 0 "$(ps -A -o args= | grep -c '^sleep 480[12]$')" "the grandchild sleeps are gone"
  assert_contains "$(ls "$P"/.studio/reports/setup-*.log)" 'timed out after 2 s' "the log says so"
  assert_missing "$P/.studio/gate.lock" "the lock is released"
}
test_setup_timer_starts_after_lock() {
  proj tl '{ "worktree_setup": "echo ran > ran.txt" }'
  ( cd "$P" && sh "$GATE" holder -- sleep 3 ) >/dev/null 2>&1 &
  _h=$!; while [ ! -f "$P/.studio/gate.lock/pid" ]; do sleep 1; done
  STUDIO_SETUP_TIMEOUT_SECONDS=1; export STUDIO_SETUP_TIMEOUT_SECONDS
  setup "$P"; unset STUDIO_SETUP_TIMEOUT_SECONDS; wait "$_h"
  assert_eq 0 "$SU_STATUS" "waiting 3 s for the lock is not a 1 s timeout"
  assert_file "$P/ran.txt" "the command ran once the lock was free"
}
test_setup_bad_config() {
  proj bc '{ "worktree_setup": "true", "worktree_setup_minutes": 0 }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "minutes 0 is refused"
  proj bc2 '{ "worktree_setup": "true", "worktree_setup_minutes": 121 }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "minutes 121 is refused"
  proj bc3 '{ "worktree_setup": "printf a\\tb" }'
  setup "$P"; assert_eq 2 "$SU_STATUS" "a backslash is refused"
  setup "$P" bogus; assert_eq 2 "$SU_STATUS" "an unknown verb is usage"
}
test_setup_gate_green_and_red() {
  proj gg '{ "gate_command": "echo gate-ok" }'
  setup "$P" gate
  assert_eq 0 "$SU_STATUS" "green gate_command exits 0"
  assert_contains "$TMP/su.out" '^gate_command: green — log \.studio/reports/gate-[0-9-]*\.log$' "names the log"
  assert_contains "$P/.studio/gate.times" ' gate [0-9][0-9]* 0$' "runs as who=gate"
  proj gr '{ "gate_command": "echo FAIL one; exit 3" }'
  setup "$P" gate
  assert_eq 3 "$SU_STATUS" "red exits with the command's status"
  assert_contains "$TMP/su.err" '^gate_command exit 3 — log \.studio/reports/gate-[0-9-]*\.log$' "the red line"
}
test_setup_help() {
  assert_status 0 "--help exits 0" -- sh "$SETUP" --help
}

run_tests test_setup_unset_is_silent test_setup_runs_under_lock_and_logs test_setup_marker_skip_and_rerun \
  test_setup_nonzero_exit test_setup_timeout_ends_group test_setup_timer_starts_after_lock \
  test_setup_bad_config test_setup_gate_green_and_red test_setup_help
```

- [ ] **Step 2: Run to see them fail.** `sh tests/studio_setup_test.sh`. Expected: FAIL (no file).
- [ ] **Step 3: Implement** `studios/game-dev/bin/studio-setup`. The header comment holds the usage, exits,
  config keys and the D-rules above. The hard part, the timer and the marker:

```sh
# cfg_get KEY — the quoted string value of "KEY" (first match), from the tree's
# .studio/config.json, else STATE_ROOT's (D8); cfg_num KEY — the bare token.
CONF="$TOP/.studio/config.json"; [ -f "$CONF" ] || CONF="$STATE_ROOT/.studio/config.json"
cfg_get() { [ -f "$CONF" ] && sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONF" | head -n 1; }
cfg_num() { [ -f "$CONF" ] && sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([^,}[:space:]"]*\).*/\1/p' "$CONF" | head -n 1; }

# timed_gate CMD SECS LOG — CMD under `studio-gate setup`, output to LOG; the
# timer starts once the gate lock names the gate's pid (at launch when there is
# no lock to take); a timeout TERMs the gate's process group (studio-gate
# forwards it to the command's group). Status: the command's, 124 on timeout.
timed_gate() {
  { set -m; } 2>/dev/null
  sh "$HERE/studio-gate" setup -- sh -c "$1" > "$3" 2>&1 < /dev/null &
  _tg=$!
  if [ -d "$STATE_ROOT/.studio" ] && ! { [ -n "${STUDIO_GATE_HELD:-}" ] \
       && [ "$(cat "$STATE_ROOT/.studio/gate.lock/pid" 2>/dev/null)" = "$STUDIO_GATE_HELD" ] \
       && kill -0 "$STUDIO_GATE_HELD" 2>/dev/null; }; then
    while kill -0 "$_tg" 2>/dev/null && [ "$(cat "$STATE_ROOT/.studio/gate.lock/pid" 2>/dev/null)" != "$_tg" ]; do sleep 1; done
  fi
  _t0=$(date +%s); _to=0
  while kill -0 "$_tg" 2>/dev/null; do
    if [ $(( $(date +%s) - _t0 )) -ge "$2" ]; then
      _to=1; kill -TERM "-$_tg" 2>/dev/null || kill -TERM "$_tg" 2>/dev/null; break
    fi
    sleep 1
  done
  _rc=0; wait "$_tg" 2>/dev/null || _rc=$?
  { set +m; } 2>/dev/null
  if [ "$_to" = 1 ]; then printf 'studio-setup: timed out after %s s\n' "$2" >> "$3"; return 124; fi
  return "$_rc"
}

# worktree verb, after validation (minutes 1-120 integer; no backslash):
MARK="$(git rev-parse --git-dir)/studio-setup.done"
SUM="$(printf '%s' "$CMD" | cksum)"
[ "$(cat "$MARK" 2>/dev/null)" = "$SUM" ] && exit 0
LOG=".studio/reports/setup-$(date +%Y%m%d-%H%M%S).log"
ensure_reports
SECS="${STUDIO_SETUP_TIMEOUT_SECONDS:-$((MIN * 60))}"
rc=0; timed_gate "$CMD" "$SECS" "$LOG" || rc=$?
if [ "$rc" -eq 0 ]; then printf '%s\n' "$SUM" > "$MARK"; exit 0; fi
printf 'worktree setup failed — exit %s — log %s\n' "$rc" "$LOG" >&2
exit 1
```
  `git rev-parse --git-dir` may print a relative `.git`. That is fine after the `cd "$TOP"`.
  `ensure_reports` runs `mkdir -p .studio/reports` and writes `*` to
  `.studio/reports/.gitignore` when it is absent.
  The `gate` verb is `sh "$HERE/studio-gate" gate -- sh -c "$GATE_COMMAND" > "$LOG" 2>&1 < /dev/null`
  plus D9's lines.
- [ ] **Step 4: Run the tests.** `sh tests/studio_setup_test.sh`. Expected: PASS.
  `sh -n studios/game-dev/bin/studio-setup` is clean.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh` (it includes `test_bin_syntax`). Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-setup runs worktree_setup and gate_command under the gate lock (#35)`.

---

### Task 3: `studio-brief` — `Context:`, the `final` fallback, the `check` verb

Files: `studios/game-dev/bin/studio-brief` (usage :33-35 — `grep -n '^usage()'`; task verb :101-158 — `grep -n '^task)'`; final :160-235 — `grep -n '^final)'`; ledger grep :220 — `grep -n "grep -E '\^- \[0-9-\]+ (("`), `tests/studio_brief_test.sh`
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L122-122, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L182-182, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L199-205, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L213-218, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L359-359
Review: task

**Interfaces:**
- Produces:
  - `studio-brief task <n> | final | check <k>`; the usage line becomes
    `usage: studio-brief task <n> | final | check <k>`, exit 2;
  - the `## Context files` part (D18), the `final` fallback and ledger grep (D17),
    and the `check` output (D16).
  - With no `Context:` header, `task` output stays byte-identical to today
    (`test_brief_task` unchanged).
- Consumes: the truth region rule (D2), as a local copy of the one-line awk
  (`studio-brief` is standalone).

- [ ] **Step 1: Write the failing tests** in `tests/studio_brief_test.sh`, added to `run_tests`:
  - `test_brief_context_appended`: add `Context: docs/c1.md, docs/c2.md` under
    `# Plan` in a copy of the fixture, with c1 = `MARK-C1` and c2 = `MARK-C2`.
    - `task 1`, `final` and `check 1` each contain `^## Context files$`, `==> docs/c1.md:L1-1`,
      `MARK-C1` and `MARK-C2`.
    - In `final`, the last line still matches `^diff: `.
  - `test_brief_context_cap`: c1 is 11,000 bytes (`awk 'BEGIN{for(i=0;i<110;i++) printf "%0100d\n", i}'`)
    and c2 is 2,000 bytes. The output includes c1. c2 is not included; it appears as
    `^- docs/c2.md$` after `^Read these as well:$`.
  - `test_brief_context_missing_file`: `Context: docs/nope.md` → exit 1, stderr `Context file docs/nope.md not found`.
  - `test_brief_final_plan_acceptance`: a spec without `## Acceptance criteria` (and no
    `## Stories`) and a plan with `## Acceptance criteria` + `1. MARK-PLAN-AC` →
    `final` exits 0 and contains `==> docs/plan.md:L` and `MARK-PLAN-AC`. With neither
    file having the section → exit 1, `## Acceptance criteria not found in`.
  - `test_brief_check_verb`:
    - The ledger gets `adopt-base <sha0>`, `T1 complete <sha0>..<sha1>`,
      `T2 complete <sha1>..<sha2>` (real commits of the fixture repo).
    - `check 2` prints the `### Task 1:` and `### Task 2:` blocks, T1's and T3's spec parts
      are absent, and it shows `^range: <sha0>..<sha2>$`, `^diff: git diff <sha0>..<sha2>$`
      and the GC/Decisions parts.
    - `check 0` prints `range: none — no finished task`.
    - `check 3` (no T3 line) exits 1 naming `T3 complete`.
    - With no `adopt-base` line it exits 1 naming `adopt-base`.
  - `test_brief_check_uses_truth_region`: the lines above, then `adopt reset <sha>` and
    `adopt-base <sha1>`, `T1 complete <sha1>..<sha2>` → `check 1` shows
    `range: <sha1>..<sha2>`.
  - `test_brief_final_reads_check_rulings`: the ledger has
    `check Ruling: kept X — fine — low` and `minor (deferred) T2: y (standard mode)`.
    `final` contains both.
  - `test_brief_original_plan_item`: a task with `Spec: docs/orig.md:L3-5`, where
    docs/orig.md is a superpowers-style plan with a `### Task 1:` block at L3-5 →
    `task 1` emits `==> docs/orig.md:L3-5` and those lines (AC4's no-spec form).
  - `test_brief_usage_names_check`: `studio-brief bogus` → exit 2, stderr contains `check <k>`.
- [ ] **Step 2: Run to see them fail.**
  `TESTS_ONLY="test_brief_context_appended test_brief_check_verb test_brief_final_plan_acceptance" sh tests/studio_brief_test.sh`.
  Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Factor the task verb's block + Spec-item loop into `emit_task N` (unchanged output),
    and use it from `task` and `check`.
  - Add `context_part`:
    ```sh
    # context_part — D18: the plan's Context: files under `## Context files`,
    # whole, in order, while the running byte total stays <= 12000; the rest
    # listed under `Read these as well:`. Nothing when the plan has no Context:.
    context_part() {
      _cp_p="$(state_get plan)"; [ -n "$_cp_p" ] && [ -f "$_cp_p" ] || return 0
      _cp_l="$(sed -n '/^## /q; s/^Context:[[:space:]]*//p' "$_cp_p" | head -n 1)"
      [ -n "$_cp_l" ] || return 0
      printf '## Context files\n'
      _cp_t=0; _cp_over=""
      for _cp_f in $(printf '%s\n' "$_cp_l" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
        [ -f "$_cp_f" ] || fail "Context file $_cp_f not found"
        _cp_c="$(wc -c < "$_cp_f" | tr -d ' ')"
        if [ -z "$_cp_over" ] && [ $((_cp_t + _cp_c)) -le 12000 ]; then
          _cp_t=$((_cp_t + _cp_c)); _cp_n="$(wc -l < "$_cp_f" | tr -d ' ')"
          [ -n "$(tail -c1 "$_cp_f")" ] && _cp_n=$((_cp_n + 1))
          if [ "$_cp_n" -eq 0 ]; then printf '==> %s:L0-0\n' "$_cp_f"; else emit "$_cp_f" 1 "$_cp_n"; fi
        else
          [ -n "$_cp_over" ] || printf 'Read these as well:\n'; _cp_over=1; printf -- '- %s\n' "$_cp_f"
        fi
      done
    }
    ```
    Context paths must not contain spaces; the autopilot copies carry files to
    `docs/game-dev/adopted/<id>/` and names them there.
  - In `final`:
    - when `section "$spec" "## Acceptance criteria" 0` is empty, try the state's plan.
      If that has the section, `emit "$plan" …` it and skip the `## Stories` block.
      Otherwise keep today's failure text.
    - Change the ledger grep to `'^- [0-9-]+ ((T[0-9]+|Task [0-9]+:|check) )?(Ruling: |minor \(deferred\))'`.
  - Add the `check` verb per D16. Update the header comment and the usage line.
- [ ] **Step 4: Run the tests.** `sh tests/studio_brief_test.sh`. Expected: PASS, every existing test included.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-brief Context files, plan acceptance fallback, check verb (#35)`.

---

### Task 4: `studio-adopt` engine and `inspect`

Files: `studios/game-dev/bin/studio-adopt` (new, executable), `tests/studio_adopt_test.sh` (new)
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L64-64, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L76-76, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L83-85, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L140-148, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L167-177, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L184-191, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L290-302, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L343-357
Review: task

**Interfaces:**
- Produces:
  - `studio-adopt --help` (exit 0) and `studio-adopt inspect <id> --branch <Branch> --plan <original> [--base <sha>]`
    (D24 output; exit 0/1/2). An id outside `[A-Za-z0-9._-]+`, an unknown verb or a
    missing option is exit 2.
  - Engine functions, used by T5 and T6 from the same file. Each prints its result
    or one mismatch line on stderr and returns 1:
    - `resolve TOK`;
    - `default_branch`;
    - `fork_point TIP DEFAULT`;
    - `plan_file PATH`;
    - `task_count PLAN`;
    - `task_title PLAN N`;
    - `workspaces PLAN` (`<tree>\t<dir>`);
    - `claims_of PROGRESS` (`<n> <first> <last>` | `<n> - <line>`);
    - `merged_claims PLAN` (`<n> <a> <b>` sorted; a conflict is a mismatch);
    - `touches_work A B`;
    - `chain_check FILE PREV START TIP`;
    - `part_done FROM TIP DOCS` (shas, oldest first);
    - `run_target`;
    - `truth_lines FILE` (D2).
- Consumes: git ≥ 2.38, `git worktree list --porcelain`, `studio-state root`.

- [ ] **Step 1: Write the failing tests.** The suite header and fixture, then the cases:

```sh
#!/bin/sh
# Suite for studios/game-dev/bin/studio-adopt (#35): inspect, seed and sync
# against fixture git repos. Offline; no sessions; a temp HOME.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/tests/assert.sh"
ADOPT="$REPO_ROOT/studios/game-dev/bin/studio-adopt"
STATE_BIN="$REPO_ROOT/studios/game-dev/bin/studio-state"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME; mkdir -p "$HOME"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
unset STUDIO_RUN STUDIO_RUN_DIR STUDIO_STORY STUDIO_DOCS_REV STUDIO_GATE_HELD

ORIG=docs/superpowers/plans/2026-09-01-demo.md
CONV=docs/game-dev/plans/2026-10-04-S1.md
WS=.superpowers/sdd/2026-09-01-demo

# adopt_repo NAME TASKS DONE — $P: a clone of bare $TMP/NAME.git on main with
# an original plan ($ORIG, TASKS tasks) and its converted plan ($CONV); branch
# S1-b off main with DONE task commits (S1-T<n>.txt), checked out in worktree
# $W, pushed; SDD workspace $W/$WS for $ORIG with one claim per done task in
# SDD's format (short shas); studio state for S1 (spec $ORIG, plan $CONV,
# task 0/TASKS, branch S1-b, stage execute) and $P's ledger lines `source` and
# `adopted`. Sets P, W, BASE (main's tip) and C1..C<DONE> (full shas).
adopt_repo() {
  P="$TMP/$1"; W="$TMP/$1-wt"; _n="$2"; _d="$3"
  rm -rf "$P" "$W" "$TMP/$1.git"; git init -q --bare "$TMP/$1.git"
  ( set -e; git init -q -b main "$P"; cd "$P"
    git remote add origin "$TMP/$1.git"
    mkdir -p "$(dirname "$ORIG")" "$(dirname "$CONV")"
    { printf '# Demo plan\n\n'; i=1
      while [ "$i" -le "$_n" ]; do printf '### Task %s: step %s\n\nFiles: src/s%s.txt\n\n' "$i" "$i" "$i"; i=$((i + 1)); done; } > "$ORIG"
    { printf '# S1 plan\n\nStory: S1\nSource: %s\nStatus: Draft (awaiting approval)\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n## Acceptance criteria\n\n1. works\n\n' "$ORIG"
      i=1; while [ "$i" -le "$_n" ]; do printf '### Task %s: step %s\n\nSpec: %s:L3-4\nReview: final\n\n' "$i" "$i" "$ORIG"; i=$((i + 1)); done
      printf '## Backlog\n'; } > "$CONV"
    git add -A; git commit -q -m plans; git push -q origin main; git remote set-head origin main
    sh "$STATE_BIN" init
    STUDIO_STORY=S1; export STUDIO_STORY; sh "$STATE_BIN" init
    sh "$STATE_BIN" set spec "$ORIG"; sh "$STATE_BIN" set plan "$CONV"; sh "$STATE_BIN" set task "0/$_n"
    sh "$STATE_BIN" ledger "source $ORIG spec -"; sh "$STATE_BIN" ledger "adopted $ORIG -> $CONV"
    git worktree add -q -b S1-b "$W" main; cd "$W"
    mkdir -p "$WS"; printf '%s\n' "$ORIG" > "$WS/plan-path"; printf '*\n' > .superpowers/sdd/.gitignore
    printf '# SDD ledger — plan: %s\n' "$ORIG" > "$WS/progress.md"
    i=1; while [ "$i" -le "$_d" ]; do
      _a="$(git rev-parse --short HEAD)"
      printf 'T%s\n' "$i" > "S1-T$i.txt"; git add "S1-T$i.txt"; git commit -q -m "feat: step $i"
      printf 'Task %s: complete (commits %s..%s, review clean)\n' "$i" "$_a" "$(git rev-parse --short HEAD)" >> "$WS/progress.md"
      git rev-parse HEAD > "$TMP/$1.c$i"; i=$((i + 1))
    done
    git push -q origin S1-b
    sh "$STATE_BIN" set branch S1-b; sh "$STATE_BIN" set stage execute ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "adopt_repo $1: setup failed"; }
  BASE="$(git -C "$P" rev-parse main)"
  i=1; while [ "$i" -le "$_d" ]; do eval "C$i=\$(cat \"\$TMP/$1.c$i\")"; i=$((i + 1)); done
}
# adopt DIR ARGS — studio-adopt ARGS in DIR: AD_STATUS, $TMP/ad.out, $TMP/ad.err.
adopt() { _ad="$1"; shift; AD_STATUS=0; ( cd "$_ad" && sh "$ADOPT" "$@" ) > "$TMP/ad.out" 2> "$TMP/ad.err" || AD_STATUS=$?; }
# wt_commit MSG FILE — one commit in $W touching FILE; prints nothing.
wt_commit() { ( cd "$W" && printf '%s\n' "$1" >> "$2" && git add "$2" && git commit -q -m "$1" ) >/dev/null 2>&1; }
s7() { printf '%.7s' "$1"; }
```

  T4 cases (each named; key assertions):
  - `test_adopt_help_and_usage`:
    - `--help` exits 0 and contains `inspect <id> --branch`, `seed`, `sync`,
      `Exit: 0`, `superpowers 6.4.1` and one `Example:` per verb.
    - No args → 2; `frobnicate S1` → 2; `inspect a/b --branch x --plan y` → 2;
      `inspect S1 --plan "$ORIG"` (no `--branch`) → 2.
  - `test_adopt_inspect_clean_chain`: `adopt_repo cc 6 3`; `adopt "$P" inspect S1 --branch S1-b --plan "$ORIG"` →
    - exit 0, with `^base: $BASE$`, `^T1 complete $BASE\.\.$C1$` and `^T3 complete $C2\.\.$C3$`;
    - `^k: 3/6$` and `^workspace: $W/$WS (3 claims)$`;
    - no `in progress` line.
  - `test_adopt_inspect_from_any_checkout`: the same command from `$W` gives byte-identical stdout.
  - `test_adopt_inspect_not_started`: `--branch S9-b` → exit 0, `^branch: S9-b (not started)$`, `^k: 0/6$`.
  - `test_adopt_inspect_no_workspace`:
    - `rm -rf "$W/.superpowers"` → exit 1. Stderr is exactly
      `work on S1-b past $(s7 "$BASE") but no SDD ledger for $ORIG in any worktree — restore it, or write one in SDD's format, and inspect again`.
    - `adopt_repo nw 6 0` with the workspace removed → exit 0, `k: 0/6`, `workspace: none`.
  - `test_adopt_main_merged_between_tasks`:
    - Build: `adopt_repo mm 6 2`; in `$P` on main commit `m2` and push. In `$W`:
      `git fetch -q origin && git merge -q --no-edit origin/main`, commit a
      `.studio/ledger/S1.md` holding `- 2026-10-04 base origin/main`, then T3's
      commit, with claim `Task 3: complete (commits <merge7>..<T3_7>, review clean)`.
    - Inspect → exit 0, `^base: $BASE$` (the original fork point, not the new
      main tip), `^k: 3/6$`. The `base` ledger line is never read.
  - `test_adopt_claim_tokens`: claim lines set by hand in `$W/$WS/progress.md`:
    - `commits 0cb5..$(s7 $C1)` → the 4-hex token is ignored, first = last →
      exit 1 with `empty range`;
    - `commits faceted..` (a word that is a 7-hex run that resolves nowhere) plus a
      valid pair → accepted (the word is skipped);
    - `commits none, review clean` → exit 1, naming the line.
  - `test_adopt_claim_gaps_and_order`:
    - Claims for Tasks 1 and 3 only → exit 1, stderr contains `T2`.
    - Claim lines in order 2, 1, 3 → exit 0, `k: 3/6` (merged by number).
    - A `Task 7` claim on a 6-task plan → exit 1, `Task 7`.
  - `test_adopt_short_sha_lines_parse`: 7-hex claims (SDD's form) and 40-hex claims
    both give the same full-sha `T<n>` lines (AC25).
  - `test_adopt_part_done_filter`: `adopt_repo pd 6 3`, then on S1-b after T3:
    - commits that are left out:
      - a `.studio/`-only commit;
      - a `docs(S1): plan at run docs` commit touching `$ORIG` and `$CONV`;
      - a commit touching `$CONV` plus `.studio/ledger/S1.md` (D22);
      - a merge of `origin/main` (after main moves);
      - a `fix(final): x` commit touching `src/x`;
    - then two work commits, `wip a` and `wip b`.

    Inspect → exit 0, `^T4 in progress: <wip a sha>\.\.<wip b sha>$`.
  - `test_adopt_post_task_commits`: `adopt_repo pt 3 3` plus one work commit →
    `^post-task commits: <sha>\.\.<sha>$`, exit 0.
  - `test_adopt_explicit_base`:
    - `--base <C1>` → T1's claim starts at BASE, before the base, so it is a mismatch:
      exit 1 naming `T1`.
    - `--base "$BASE"` → exit 0.
    - `--base nope` → exit 1, naming `nope`.
- [ ] **Step 2: Run to see them fail.** `sh tests/studio_adopt_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the engine and `inspect`. The hard parts, in full:

```sh
# resolve TOK — TOK's full commit sha when it names exactly one commit; else
# nothing and status 1 (unknown or ambiguous: D19).
resolve() { git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null; }

# fork_point TIP DEFAULT — the first commit on TIP's first-parent chain that is
# reachable from origin/DEFAULT (D20). Those not reachable form a prefix.
fork_point() {
  _fp_n="$(git rev-list --count --first-parent "$1" --not "origin/$2" 2>/dev/null)" || return 1
  git rev-list --first-parent --skip="$_fp_n" --max-count=1 "$1" 2>/dev/null | grep . || return 1
}

# touches_work A B — some commit on B's first-parent chain past A touches a path
# outside .studio/ (merges diffed against their first parent: D21).
touches_work() {
  git log --first-parent --diff-merges=first-parent --name-only --format= "$1..$2" 2>/dev/null \
    | grep -v '^$' | grep -qv '^\.studio/'
}

# claims_of PROGRESS — per `Task <n>: complete (commits …)` line: `<n> <first>
# <last>` from the first and last 7-40 hex tokens after `commits ` that each
# resolve to exactly one commit (D19); `<n> - <the line>` when none does.
claims_of() {
  grep -E '^Task [0-9]+: complete \(commits ' "$1" 2>/dev/null | while IFS= read -r _co_l; do
    _co_n="$(printf '%s\n' "$_co_l" | sed 's/^Task \([0-9]*\):.*/\1/')"; _co_f=""; _co_z=""
    for _co_t in $(printf '%s\n' "${_co_l#*commits }" | tr -c '0-9a-f' ' '); do
      case "${#_co_t}" in [7-9]|[1-3][0-9]|40) ;; *) continue ;; esac
      _co_s="$(resolve "$_co_t")" || continue
      [ -n "$_co_f" ] || _co_f="$_co_s"; _co_z="$_co_s"
    done
    if [ -n "$_co_f" ]; then printf '%s %s %s\n' "$_co_n" "$_co_f" "$_co_z"
    else printf '%s - %s\n' "$_co_n" "$_co_l"; fi
  done
}

# merged_claims PLAN — every workspace's claims for PLAN, by task number; one
# line per task; a claim with no resolvable token, or two ranges for one task,
# is a mismatch (stderr, status 1). Sets WS_LIST (`<dir> (<n> claims)` lines).
merged_claims() {
  : > "$TMPD/claims"; WS_LIST=""
  workspaces "$1" > "$TMPD/ws"
  while IFS="$(printf '\t')" read -r _mc_t _mc_d; do
    claims_of "$_mc_d/progress.md" > "$TMPD/c1"
    WS_LIST="$WS_LIST$_mc_d ($(wc -l < "$TMPD/c1" | tr -d ' ') claims)
"
    sed "s|\$| $_mc_d|" "$TMPD/c1" >> "$TMPD/claims"
  done < "$TMPD/ws"
  _mc_bad="$(awk '$2 == "-" { sub(/^[0-9]+ - /, ""); print "claim names no commit: " $0; exit }' "$TMPD/claims")"
  [ -z "$_mc_bad" ] || { printf '%s\n' "$_mc_bad" >&2; return 1; }
  sort -n -k1,1 "$TMPD/claims" | awk '
    { if (($1 in a) && (a[$1] != $2 || b[$1] != $3)) { print "two ranges for Task " $1 ": " w[$1] " and " $4 > "/dev/stderr"; bad = 1; exit }
      if (!($1 in a)) { a[$1] = $2; b[$1] = $3; w[$1] = $4; o[++n] = $1 } }
    END { if (!bad) for (i = 1; i <= n; i++) print o[i], a[o[i]], b[o[i]]; exit bad }'
}

# chain_check FILE PREV START TIP — FILE holds `<n> <a> <b>` (full shas) by n;
# n must run START, START+1, …; PREV is the adopt-base or T<START-1>'s end.
# AC10b's rules; the first failure on stderr, status 1.
chain_check() {
  _cc_p="$2"; _cc_w="$3"
  while read -r _cc_n _cc_a _cc_b; do
    [ "$_cc_n" -eq "$_cc_w" ] || { echo "T$_cc_w has no line (next is T$_cc_n)" >&2; return 1; }
    [ "$_cc_a" != "$_cc_b" ] || { echo "T$_cc_n: empty range $(s7 "$_cc_a")..$(s7 "$_cc_b")" >&2; return 1; }
    git merge-base --is-ancestor "$_cc_a" "$_cc_b" 2>/dev/null \
      || { echo "T$_cc_n: $(s7 "$_cc_a") is not an ancestor of $(s7 "$_cc_b")" >&2; return 1; }
    git merge-base --is-ancestor "$_cc_b" "$4" 2>/dev/null \
      || { echo "T$_cc_n: $(s7 "$_cc_b") is not on $BRANCH" >&2; return 1; }
    git merge-base --is-ancestor "$_cc_p" "$_cc_a" 2>/dev/null \
      || { echo "T$_cc_n: $(s7 "$_cc_a") does not follow $(s7 "$_cc_p")" >&2; return 1; }
    touches_work "$_cc_a" "$_cc_b" \
      || { echo "T$_cc_n: $(s7 "$_cc_a")..$(s7 "$_cc_b") has no commit outside .studio/" >&2; return 1; }
    _cc_p="$_cc_b"; _cc_w=$((_cc_n + 1))
  done < "$1"
}

# part_done FROM TIP DOCS — AC11: the first-parent commits FROM..TIP, oldest
# first, minus merges of the default or Target branch, commits touching only
# .studio/ and DOCS paths (D22), commits inside a `check done <a>..<b>` range
# (CHECK_SET file), and fix(final|gate|review / docs(progress subjects.
part_done() {
  git log --first-parent --diff-merges=first-parent --name-only --reverse \
      --format='C %H %P%x09%s' "$1..$2" 2>/dev/null | awk -v docs="$3" '
    BEGIN { n = split(docs, d, " "); for (i = 1; i <= n; i++) isdoc[d[i]] = 1 }
    function flush() { if (h != "" && keep) print h; h = "" }
    /^C / { flush(); split($0, t, "\t"); h = substr(t[1], 3); keep = 0
            if (t[2] ~ /^(fix\(final|fix\(gate|fix\(review|docs\(progress)/) h = ""
            next }
    NF == 0 { next }
    h != "" && $0 !~ /^\.studio\// && !($0 in isdoc) { keep = 1 }
    END { flush() }' | while read -r _pd_c _pd_p1 _pd_p2; do
      if [ -n "$_pd_p2" ]; then
        git merge-base --is-ancestor "$_pd_p2" "origin/$DEFAULT" 2>/dev/null && continue
        [ -z "$TARGET" ] || ! git merge-base --is-ancestor "$_pd_p2" "origin/$TARGET" 2>/dev/null || continue
      fi
      grep -qxF "$_pd_c" "$TMPD/checkset" 2>/dev/null && continue
      printf '%s\n' "$_pd_c"
    done
}
```
  `workspaces PLAN`:
  ```sh
  git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r t; do
    for d in "$t"/.superpowers/sdd/*/; do
      [ -f "$d/plan-path" ] || continue
      [ "$(cat "$d/plan-path")" = "$PLAN" ] && printf '%s\t%s\n' "$t" "${d%/}"
    done
  done
  ```
  Marker-less workspaces are ignored (D32).

  `inspect` flow:
  1. Parse the options.
  2. `N=$(task_count "$(plan_file "$ORIG")")`; zero tasks → exit 1.
  3. Find the tip (D25). A not-started story prints the report with `base: -` and `k: 0/N`.
  4. Base: `--base` (resolved, else exit 1 naming the token), else `fork_point`.
  5. `merged_claims` → `$TMPD/chain`.
  6. Any claim n > N → exit 1.
  7. `chain_check "$TMPD/chain" "$BASE_SHA" 1 "$TIP"`; k = the last n.
  8. With no workspace: k = 0, and the part-done list from the base must be empty,
     else the L148 message.
  9. Part-done from T_k's end (or the base), with DOCS = `$ORIG` plus the
     `adopted`/`source` paths and `Context:` paths from `$STATE_ROOT/.studio/ledger/<id>.md`
     when present.
  10. Print D24.

  Fixture timing: `test_adopt_*` must finish in under 30 s in total (each git call is
  a few ms; no per-commit loops outside `part_done`'s merge check).
- [ ] **Step 4: Run the tests.** `sh tests/studio_adopt_test.sh`. Expected: PASS.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-adopt inspect — base, claims, chain checks, part-done (#35)`.

---

### Task 5: `studio-adopt seed` and `--reset`

Files: `studios/game-dev/bin/studio-adopt`, `tests/studio_adopt_test.sh`
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L115-115, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L149-158, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L182-182, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L299-302
Review: task

**Interfaces:**
- Produces: `studio-adopt seed <id> [--reset] [--base <sha>]` (D26–D28).
  - It writes these lines into the current tree's `.studio/ledger/<id>.md` through
    `STUDIO_STORY=<id> studio-state ledger` (each only when absent from the truth
    region), in this order:
    1. `source …`;
    2. `adopted …`;
    3. `adopt-base <full>`;
    4. `T<n> complete <full>..<full>`;
    5. the AC10f lines (D34);
    6. `check requested`.
  - It makes one `chore(studio): ledger (adopt)` commit when it wrote anything.
  - Stdout: `seeded: <n> lines` or `already seeded`.
- Consumes: T4's engine; `$STATE_ROOT/.studio/ledger/<id>.md`; the story pointer's `branch`.

- [ ] **Step 1: Write the failing tests** (added to `run_tests`):
  - `test_adopt_seed_writes_truth`: `adopt_repo sd 6 3`; `adopt "$W" seed S1` → exit 0.
    - The ledger in `$W` has, in order: `source $ORIG spec -`,
      `adopted $ORIG -> $CONV`, `adopt-base $BASE`, `T1 complete $BASE..$C1`,
      `T2 complete $C1..$C2`, `T3 complete $C2..$C3`.
    - `git -C "$W" log -1 --format=%s` = `chore(studio): ledger (adopt)`.
    - Then `STUDIO_STORY=S1 studio-state check --rebuild` in `$W` → `task` = `3/6`.
  - `test_adopt_seed_second_run_noop`: seed twice → the second says `already seeded`,
    with no new commit and a byte-identical ledger.
  - `test_adopt_seed_check_requested`: `$P`'s ledger has `check requested` → seed copies it.
  - `test_adopt_seed_refuses_changed_title`: change `$CONV`'s `### Task 2: step 2` to
    `### Task 2: other` → exit 1, stderr names `Task 2`, no commit, ledger unchanged.
  - `test_adopt_seed_wrong_branch`: run from `$P` (on main) → exit 1, stderr names `S1-b`.
  - `test_adopt_seed_carries_rulings`: the progress.md gains:
    - `Task 2: parked — slow path — Ruling: fine for now`;
    - `Task 3: minor (deferred): rename foo`;
    - `Task 1: Ruling: kept X — cheaper`;
    - `Task 5: Ruling: later` (n > k: not carried).

    Seed writes `minor (deferred) T2: slow path — Ruling: fine for now (standard mode)`,
    `minor (deferred) T3: rename foo (standard mode)` and `T1 Ruling: kept X — cheaper`,
    and no `T5` line.
  - `test_adopt_seed_base_conflict`: seed, then `seed S1 --base "$C1"` → exit 1, naming `adopt-base`.
  - `test_adopt_seed_reset_after_rebase`:
    1. `adopt_repo rb 6 3` and seed.
    2. In `$W`: `git rebase -q --onto <new main commit> "$BASE"` after main moves; push
       is not needed.
    3. `adopt "$W" sync S1` → exit 1, stderr
       `history of S1-b was rewritten after its adopt base — re-adopt: studio-adopt seed S1 --reset`
       (the sync verb lands in T6; this assertion runs in T6, so add it there).
    4. Here: `adopt "$W" seed S1` → exit 1 (the old claims no longer chain to the
       new base).
    5. Rewrite the progress.md claims to the rebased shas →
       `adopt "$W" seed S1 --reset` → exit 0.
       - The ledger has `adopt reset <HEAD>` followed by fresh
         `source`/`adopted`/`adopt-base <new fork point>`/T1–T3 lines.
       - `check --rebuild` → `3/6`.
       - `truth_lines` shows no pre-reset T line.
- [ ] **Step 2: Run to see them fail.** `TESTS_ONLY="test_adopt_seed_writes_truth test_adopt_seed_reset_after_rebase" sh tests/studio_adopt_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `seed`:
  1. Parse the options (`--reset`, `--base`).
  2. Read `adopted <orig> -> <conv>` (last) and `source …` from `$STATE_ROOT/.studio/ledger/<id>.md`.
     None → exit 1 `no adopted line for <id> in the start checkout`.
  3. Check that the branch equals the pointer's `branch`.
  4. With `--reset`: append `adopt reset $(git rev-parse HEAD)` first. It is part of the
     same commit, so a failure later leaves nothing committed: run
     `git checkout -- .studio/ledger/<id>.md` (or remove it when it was untracked),
     then exit 1.
  5. Base per D26.
  6. `merged_claims`, then `chain_check` against HEAD.
  7. Compare titles 1..k (`task_title`) between orig and conv.
  8. Append the missing lines.
  9. `git add .studio/ledger/<id>.md && git commit -q -m "chore(studio): ledger (adopt)"`.

  Every exit-1 path restores the ledger file to its state before the run, so nothing is
  applied in part.
- [ ] **Step 4: Run the tests.** `sh tests/studio_adopt_test.sh`. Expected: PASS.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-adopt seed and seed --reset (#35)`.

---

### Task 6: `studio-adopt sync`

Files: `studios/game-dev/bin/studio-adopt`, `tests/studio_adopt_test.sh`
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L162-183, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L195-195, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L255-264, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L301-302, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L309-315
Review: task

**Interfaces:**
- Produces: `studio-adopt sync <id>`. Preconditions per D29–D30; verify (AC10b, D31);
  accept (AC10c); views (D32); landed note (D33); AC10f (D34); task view (D35);
  report (D36).
- Consumes:
  - T4's engine;
  - `$STATE_ROOT/.studio/overnight.lock` (`pid=`, `run=`);
  - `<run>/stories/<id>`;
  - `$STATE_ROOT/.studio/runs/<slug>/landed.tsv`;
  - the `$STUDIO_RUN` and `.studio/run` manifest headers (`# Run:`, `Target:`) and rows.

- [ ] **Step 1: Write the failing tests** (added to `run_tests`). Most start from `adopt_repo X 6 3` + `adopt "$W" seed S1`:
  - `test_sync_already_in_sync`: sync → exit 0, `^already in sync$`, `^k: 3/6 -> 3/6$`.
    - Views: `$W/$WS/progress.md` line 1 is `# SDD ledger — plan: $ORIG`, then three
      `Task <n>: complete (commits <full>..<full>, review clean)` lines.
    - `$W/.superpowers/sdd/2026-10-04-S1/plan-path` = `$CONV`, and its progress.md has the same three lines.
    - `$W/.superpowers/sdd/.gitignore` = `*`.
  - `test_sync_accepts_claims`: commit T4 in `$W` and append its SDD claim → sync → exit 0.
    - Output: `^accepted: T4 $C3\.\.<T4 sha>$` and `^k: 3/6 -> 4/6$`.
    - A `chore(studio): ledger (sync)` commit holds `T4 complete <full>..<full>`.
    - `origin/S1-b` equals HEAD (pushed), and `task` is `4/6`.
  - `test_sync_second_run_noop`: sync again → `already in sync`, no new commit.
  - `test_sync_all_or_nothing`: claims for T4 (valid) and T5 (end not on the
    branch) → exit 1, the ledger is unchanged, no commit, and the views are unchanged
    (byte compare).
  - `test_sync_claim_end_differs`: rewrite T2's claim end to `$C3` → exit 1, naming `Task 2`.
  - `test_sync_truth_mismatches`, each a fresh repo:
    1. a truth line `T2 complete $C1..$C1` → `empty range`;
    2. a gap (delete the T2 line) → `T2`;
    3. two lines for T1 with different ranges → exit 1, `T1`;
    4. `T3 complete $C3..$C2` → `not an ancestor`;
    5. a `.studio/`-only T4 range → `no commit outside .studio/`.

    Each exits 1 and names the line's sha.
  - `test_sync_ambiguous_short_sha`:
    - Build the noise branch:
      `awk 'BEGIN { for (i = 1; i <= 1000; i++) printf "commit refs/heads/noise\ncommitter t <t@t> 1700000000 +0000\ndata <<EOF\nn%d\nEOF\n\n", i }' | git -C "$W" fast-import --quiet`.
      The prefix is `tok="$(git -C "$W" rev-list noise | cut -c1-4 | sort | uniq -d | head -n 1)"`;
      fail the test if it is empty.
    - Replace the T1 line with `T1 complete $tok..$C1` → exit 1, and stderr contains `$tok`.
      (The trial gives `0cb5` deterministically: Falsify #9.)
  - `test_sync_rewrite_message`: rebase (as in T5) → exit 1, stderr exactly
    `history of S1-b was rewritten after its adopt base — re-adopt: studio-adopt seed S1 --reset`.
    Rebasing only T3 onto an amended T3 parent (`git rebase` that keeps T1–T2) →
    `history of S1-b was rewritten after T2 — re-adopt: studio-adopt seed S1 --reset`.
  - `test_sync_views_keep_other_lines`: the old original view holds, in order:
    - `Task 2: fix round 1/5 (1 addressed, 0 open; commits a..b)`;
    - `Task 4: parked — x — Ruling: y` (n > k);
    - a stale `Task 9: complete (commits zz..zz, review clean)` (no such task: this is
      a mismatch, so drop this line from the fixture);
    - `notes line`.

    After sync, every kept line is present in its old order after the truth lines.
  - `test_sync_carries_rulings_once`: the D34 lines after sync; a second sync adds none.
  - `test_sync_landed_note`:
    - `$P/.studio/run` names `docs/runs/demo.md` with `# Run: demo` committed in `$P`;
      `$P/.studio/runs/demo/landed.tsv` has `S1\tintegration/demo\t<sha>\t1`.
    - After sync, the original's view ends `Landed: integration/demo at <sha> — continue dependent stories from there`
      and the converted view has no `Landed:` line.
    - Without the tsv: no `Landed:` line.
  - `test_sync_live_run_refusal`:
    - Start a live dummy: `sh -c 'sleep 60; :' studio-overnight &`.
    - Write `$P/.studio/overnight.lock` with `pid=<dummy>`, `run=$TMP/run1` and
      `started=x`; create `$TMP/run1/manifest.md` and `$TMP/run1/stories/S1` = `running`.
    - Sync → exit 1, stderr `story S1 is in a live run — /hold it or wait for it to end`.
    - The same for `held held by operator until 1`.
    - `queued` → exit 0.
    - Kill the dummy afterwards.
  - `test_sync_own_unit_exempt`: as above with `running`, plus `STUDIO_RUN=$TMP/run1/manifest.md`,
    `STUDIO_STORY=S1` and `STUDIO_RUN_DIR=$TMP/run1` in the environment → exit 0.
    `STUDIO_STORY=S2` → exit 1.
  - `test_sync_diverged_and_behind`:
    - Behind: in a second clone, commit T4 + claim-less push → sync in `$W` fast-forwards
      (HEAD = origin/S1-b), and the report says `k: 3/6 -> 3/6` plus
      `T4 in progress: <sha>..<sha>`.
    - Diverged: a local commit plus a different remote commit → exit 1,
      stderr `S1-b has diverged from origin/S1-b — reconcile it by hand, then sync`.
  - `test_sync_preconditions`: run on main in `$P` → exit 1, naming `S1-b`. Delete the
    pointer file → sync re-inits it and exits 0 (D29.1).
  - `test_adopt_workspace_lookup_two_trees`:
    - A second worktree `$P/../wt2` of a branch `side` holds a workspace for `$ORIG`
      under the collision name `2026-09-01-demo-plans` (`2026-09-01-demo` there is
      owned by another plan path).
    - Its claims T1–T3 equal the truth → sync's `trees:` lists both.
    - A conflicting T2 range in wt2 → exit 1, `two ranges for Task 2`.
    - In `$W`, `2026-09-01-demo` owned by `docs/other/2026-09-01-demo.md` → sync writes
      the view to `2026-09-01-demo-plans` (superpowers' rule; D32, D42).
  - `test_sync_push_failure_warns`: point `origin` at a missing path after a commit-producing
    sync setup → exit 0, `push failed:` in stdout, and the commit is kept locally.
- [ ] **Step 2: Run to see them fail.** `TESTS_ONLY="test_sync_accepts_claims test_sync_live_run_refusal" sh tests/studio_adopt_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `sync` per D29–D36:
  1. preconditions;
  2. truth parse — `truth_lines` → `T<n>` last token `a..b`; each side `resolve`d, or a
     mismatch naming the line. Two lines for one n must resolve the same, then de-dup;
  3. D31's rewrite check (each `b` and the `adopt-base` an ancestor of HEAD) before
     `chain_check truth adopt-base 1 HEAD`;
  4. claims — `merged_claims "$ORIG"`. For n ≤ k the end must equal the truth's;
     the n > k claims go to `chain_check new T_k-end k+1 HEAD`;
  5. AC10f lines;
  6. one commit and the push (D29.8);
  7. `check --rebuild` (D35);
  8. views for `$ORIG` and `$CONV` via the `owns()` replica (D32), `.gitignore`, the landed note;
  9. the report.

  Steps 2–4 run before anything is written. The ledger appends and the commit form one
  step, restored on failure as in seed.

  The `owns()` replica:
  ```sh
  # view_dir PLAN — this tree's SDD workspace for PLAN, by superpowers 6.4.1
  # sdd-workspace's rule (marker match; a missing marker is claimed).
  vd_owns() { if [ -e "$1/plan-path" ]; then [ "$(cat "$1/plan-path")" = "$2" ]; else mkdir -p "$1" && printf '%s\n' "$2" > "$1/plan-path"; fi; }
  view_dir() {
    _vr="$(git rev-parse --show-toplevel)"; _vb="$_vr/.superpowers/sdd"
    _vs="$(basename "$1" .md)"; _vp="$(basename "$(dirname "$1")")"; [ "$_vp" != . ] || _vp="$(basename "$_vr")"
    if vd_owns "$_vb/$_vs" "$1"; then _vd="$_vb/$_vs"
    elif vd_owns "$_vb/$_vs-$_vp" "$1"; then _vd="$_vb/$_vs-$_vp"
    else _vn=2; while ! vd_owns "$_vb/$_vs-$_vp-$_vn" "$1"; do _vn=$((_vn + 1)); done; _vd="$_vb/$_vs-$_vp-$_vn"; fi
    printf '*\n' > "$_vb/.gitignore"; printf '%s\n' "$_vd"
  }
  ```
- [ ] **Step 4: Run the tests.** `sh tests/studio_adopt_test.sh`. Expected: PASS. Then
  `time sh tests/studio_adopt_test.sh` stays under 60 s.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(studio): studio-adopt sync — verify, accept claims, views, landed note (#35)`.

---

### Task 7: Runner — the check unit, config keys, gate room, gate-repair log

Files:
- `studios/game-dev/bin/studio-overnight`:
  - `snapshot` :481 — `grep -n '^snapshot()'`;
  - `label_for` :525 — `grep -n '^label_for()'`;
  - `model_for` :144 — `grep -n '^model_for()'`;
  - `preflight` :369 — `grep -n '^preflight()'`;
  - `gate_room_check` :456 — `grep -n '^gate_room_check()'`.
- `studios/game-dev/bin/overnight-lanes.sh`:
  - `story_first_label` :222 — `grep -n '^story_first_label()'`;
  - `gate_log_of` :512 — `grep -n '^gate_log_of()'`;
  - `story_units_table` :998 — `grep -n '^story_units_table()'`.
- `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh`.

Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L46-46, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L206-210, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L233-235, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L245-245
Review: task

**Interfaces:**
- Produces:
  - `SIG` gains `;chk=<n>`; `label_for` → `check`; `model_for check` → `MODEL_FINAL` (D15);
  - preflight validates `worktree_setup`, `gate_command` and `worktree_setup_minutes` (D8);
  - `gate_room_check` uses the sum (D13);
  - `gate_log_of` honours the Stop's ` — log <path>` (D14);
  - the report's units table lists `check`.
- Consumes: the feature ledger via `ledger_of`; the story ledger via `story_state "$1" show`.

- [ ] **Step 1: Write the failing tests:**
  - `tests/overnight_test.sh` → `test_overnight_check_unit`:
    - Set up: `fixture chk`; in `$P` set `stage execute` and `task 1/2`, ledger
      `check requested`, then commit.
    - Scenario:
      1. `ledger check done none`;
      2. `task 2/2`;
      3. `ledger final review done`;
      4. `stage idle; task -; ledger shipped x`.
    - `run_start`. Then:
      - `unit_col 2` begins `check T2`;
      - `sed -n '/^--model$/{n;p;}' "$CALLS/1.argv"` = `opus` (model_final default);
      - `unit_col 7` begins `progress`, so a check unit that ledgers `check done` is progress.
    - A second fixture with `check requested` and `check done none` already ledgered →
      the first label is `T2`.
  - `tests/overnight_test.sh` → `test_overnight_adopt_config_refusals`: the config
    `{"worktree_setup_minutes": 0}` → `start --dry-run` exit 2 with
    `config overnight.worktree_setup_minutes must be from 1 to 120, got 0`.
    `{"gate_command": "a\\b"}` → refused, naming `gate_command`. (Model on
    `test_overnight_config_refusals`'s `refuse_case`; `grep -n '^refuse_case()' tests/overnight_test.sh`.)
  - `tests/overnight_lanes_test.sh` → extend `test_lanes_gate_room_warning`:
    1. The existing assertions are unchanged.
    2. Add gate.times `1 studio-test 3000 0` + `2 gate 2400 0` → the warning contains
       `the slowest of the last 10 studio-test runs plus the slowest of the last 10 gate_command runs took 90 min`
       and `at least 118`.
    3. With `gate` lines only (`1 gate 600 0`) → no warning.
  - `tests/overnight_lanes_test.sh` → `test_lanes_gate_log_from_stop`:
    - A story whose stub writes `gatecmd`-style
      `Stop: gate red — gate_command exit 3 — log .studio/reports/gate-20261004-000000.log`
      (use the `stop gate red — …` action with that text, plus a `gatelog` action, so
      a newer test log also exists).
    - `printf 'auto\nstop gate red — gate_command exit 3 — log .studio/reports/gate-20261004-000000.log\ngaterepair\nauto\n'`
      with `LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'`.
    - The gate-repair unit's `$CALLS/<n>.env` has
      `STUDIO_REPAIR=gate:<story worktree>/.studio/reports/gate-20261004-000000.log`.
    - Model on `test_lanes_gate_repair_*` (`grep -n '^test_lanes_gate_repair' tests/overnight_lanes_test.sh`).
- [ ] **Step 2: Run to see them fail.** `TESTS_ONLY="test_overnight_check_unit" sh tests/overnight_test.sh`; `TESTS_ONLY="test_lanes_gate_room_warning test_lanes_gate_log_from_stop" sh tests/overnight_lanes_test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  ```sh
  # in snapshot, after SIG_SHIPPED:
  SIG_CHK="$(printf '%s\n' "$_l" | grep -c '^- [0-9-]* check done')"
  SIG_CHKREQ="$(printf '%s\n' "$_l" | grep -c '^- [0-9-]* check requested$')"
  SIG="stage=$SIG_STAGE;task=$SIG_TASK;frd=$SIG_FRD;shipped=$SIG_SHIPPED;chk=$SIG_CHK"
  # label_for, first line of its body:
  if [ "${SIG_CHKREQ:-0}" -gt 0 ] && [ "${SIG_CHK:-0}" -eq 0 ]; then echo check; return; fi
  # model_for: a case arm
  check) UNIT_MODEL="$MODEL_FINAL" ;;
  # story_first_label, before label_for (and before the idle return):
  _sfl="$(story_state "$1" show 2>/dev/null)"
  SIG_CHK="$(printf '%s\n' "$_sfl" | grep -c '^- [0-9-]* check done')"
  SIG_CHKREQ="$(printf '%s\n' "$_sfl" | grep -c '^- [0-9-]* check requested$')"
  ```
  - `gate_room_check`: a second awk over `$2 == "gate"`, then `_gr_s=$((_gr_t + _gr_g))`
    and the D13 wording. The early `return 0` tests the sum.
  - `preflight`: after `cfg_str merge_command`, add the three D8 lines.
  - `gate_log_of`:
    ```sh
    gate_log_of() {
      _gl="$(ledger_of "$1" | grep '^- [0-9-]* Stop: ' | tail -n 1 | sed -n 's/.* — log \(.*\)$/\1/p')"
      case "$_gl" in '') ;; /*) printf '%s\n' "$_gl"; return ;; *) printf '%s\n' "$1/$_gl"; return ;; esac
      _gl="$(ls -t "$1"/.studio/reports/test-*.log 2>/dev/null | head -n 1)"
      printf '%s\n' "${_gl:--}"
    }
    ```
    Update its comment.
  - `story_units_table` regex: `/^(T[0-9]+|check|final-review|finish|repair|gate-repair)(-retry)?$/`.
- [ ] **Step 4: Run the tests** from Step 2, then the two suites whole:
  `sh tests/overnight_test.sh` and `sh tests/overnight_lanes_test.sh`. Expected: PASS
  (`test_overnight_unknown_label_stops` still exits 3 for `bogus`).
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `feat(overnight): check unit, adopt config keys, gate room and gate log for gate_command (#35)`.

---

### Task 8: Lanes — `Context:` preflight, final-integration hooks, report lines, stub, held cases

Files:
- `studios/game-dev/bin/overnight-lanes.sh`:
  - `mf_check` — after the spec-refusals loop, `grep -n 'spec-refusals"$'`;
  - `final_gate_cmds` :1318 — `grep -n '^final_gate_cmds()'`;
  - `final_integration` :1395 — `grep -n '^final_integration()'`, after `# Step 1.`'s merge
    block, before `# Step 2.`;
  - `progress_direct` :1508 — `grep -n '^progress_direct()'`;
  - `story_ledger_lines` :988 — `grep -n '^story_ledger_lines()'`;
  - `lanes_report`'s per-story loop :1067-1080 — `grep -n "printf 'Not landed: %s"`.
- `tests/overnight_lanes_test.sh`:
  - the stub's `auto()` :160-203 — `grep -n '^auto() {'`;
  - the action `case` — `grep -n '"ruling "\*)'`.

Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L127-134, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L194-194, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L205-205, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L220-220, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L228-234, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L241-245, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L362-368
Review: task

**Interfaces:**
- Produces:
  - the `Context:` refusal (D40);
  - `final_gate_cmds` with `studio-setup gate` (D10);
  - setup in the final integration and in `progress_direct` (D11, D12);
  - `story_ledger_text ID` (the source half of `story_ledger_lines`; that function
    becomes `story_ledger_text "$1" | grep -E …`);
  - report lines (D39);
  - stub changes (D43).
- Consumes: `studio-setup` (T2), `studio-adopt sync` (T6), the check label (T7).

- [ ] **Step 1: Stub first** (it is test code): apply D43 to the lanes stub.
  - In `auto()`, after `cd "$wt"` and the docs sync:
    ```sh
    if ! _se="$(sh "$(dirname "$STUB_STATE_BIN")/studio-setup" 2>&1 >/dev/null)"; then
      st ledger "Stop: $_se"; commit_ledger setup-stop; return 0
    fi
    if grep -q '^- [0-9-]* adopted ' ".studio/ledger/$id.md" 2>/dev/null; then
      if ! _sy="$(sh "$(dirname "$STUB_STATE_BIN")/studio-adopt" sync "$id" 2>&1 >/dev/null)"; then
        st ledger "Stop: adopt sync — $(printf '%s\n' "$_sy" | tail -n 1)"; commit_ledger sync-stop; return 0
      fi
    fi
    if grep -q '^- [0-9-]* check requested$' ".studio/ledger/$id.md" 2>/dev/null \
       && ! grep -q '^- [0-9-]* check done' ".studio/ledger/$id.md"; then
      st ledger "check done none"; commit_ledger check; sg push -q origin "$BRANCH"; return 0
    fi
    ```
  - The task branch writes `_a="$(git rev-parse HEAD)"` before the feature commit, then
    `st ledger "T$k complete $_a..$(git rev-parse HEAD)"`.
  - The new action `gatecmd`:
    `terminal=1; w="$(story_wt)"; ( cd "$w" && _g="$(sh "$(dirname "$STUB_STATE_BIN")/studio-setup" gate 2>&1 >/dev/null)" || { st ledger "Stop: gate red — $_g"; commit_ledger gate-red; } )`.
  - Document both in the stub's scenario-language comment block.
- [ ] **Step 2: Write the failing tests** (added to `run_tests`):
  - `test_lanes_next_adopted_planned`:
    - `lanes_fixture nad integration S1:- S2:-`.
    - For S1, write a superpowers spec `docs/superpowers/specs/2026-09-01-s1.md`
      (no `## Stories`). For S2, write the original plan
      `docs/superpowers/plans/2026-09-01-s2.md`, used as the Spec cell (no spec).
    - Write converted plans with `Story: <id>` and set the manifest cells to them.
    - Following AC5's order, ledger (without `STUDIO_STORY`, after
      `studio-state set spec <spec>`) `spec approved`, `plan approved` and
      `Decisions swept <id>` into each spec's slug ledger, then commit.
    - `run_lanes next "$MFP"` → exit 0, with
      `^S1  planned  spec=docs/superpowers/specs/2026-09-01-s1.md  plan=` and
      `^S2  planned  spec=docs/superpowers/plans/2026-09-01-s2.md  plan=`.
  - `test_lanes_context_preflight`: S1's plan gains `Context: docs/game-dev/adopted/S1/carry.md`,
    committed in Docs without the file → `start --dry-run` exit 2, `S1: Context file docs/game-dev/adopted/S1/carry.md is not in Docs: <full Docs sha>`.
    With the file committed and Docs updated → exit 0.
  - `test_lanes_check_unit_first`: `lanes_fixture chu integration A:-`; A's ledger has
    `check requested` (committed in Docs; the stub's fresh-branch path copies the ledger).
    - `story_rows A` = `1 A-check progress,2 A-T1 progress,3 A-final-review progress,4 A-finish done,`.
    - `events.jsonl` contains `"event":"unit_started","story":"A",.*"label":"check","model":"opus"`.
  - `test_lanes_adopt_sync_fail_holds`:
    - `lholds_on 120`, then make S1 adopted (an `adopted` line) with a branch whose
      truth line is broken (`T1 complete <x>..<x>`).
    - `lanes_bg`, then `wait_for 'is_held S1' 60`.
    - The feature ledger has `Stop: adopt sync — T1: empty range`, `rec S1` starts with
      `held `, and `events.jsonl` has `"state":"held","why":"stop: adopt sync — `.
    - `lverb stop`, `wait_pid_or_fail`, `lholds_off`.
  - `test_lanes_setup_fail_holds`: `LANES_CONFIG='{"worktree_setup": "exit 5"}'`, `lholds_on 120`
    → held, with why `stop: worktree setup failed — exit 5 — log .studio/reports/setup-`.
  - `test_lanes_setup_fail_final_red`:
    - Integration mode; worktree_setup succeeds in story worktrees but fails in the
      final worktree:
      `{"worktree_setup": "case \"$(pwd -P)\" in */integration-*) exit 4 ;; esac"}`.
    - The report has `Final PR: … (red)` and
      `Final note: … worktree setup failed — exit 4 — log `.
    - No `final-gate.log`; `.studio/runs/demo/gate` absent.
  - `test_lanes_gate_command_final`:
    - `LANES_CONFIG='{"gate_command": "echo gc >> '"$CALLS"'/gc; exit 0"}'` and
      `use_gate true` → `$CALLS/gc` has one line (the final gate ran `gate_command`
      after the hook) and the final PR is green.
    - `exit 2` instead → the final gate is red and `final-gate.log` contains
      `gate_command exit 2 — log `.
  - `test_lanes_gate_command_finish_red_repair`: A's scenario
    `auto\nauto\ngatecmd\ngaterepair\nauto\n`, config `gate_command: "exit 3"`, `gate_repairs 1`.
    The gate-repair env has `STUDIO_REPAIR=gate:<A's worktree>/.studio/reports/gate-` (the Stop's own log).
  - `test_lanes_report_adopted_lines`: two stories.
    - A is landed and adopted (`adopted <orig> -> <conv>` in its ledger) → the report
      has `^Adopted from <orig>; landed on integration/demo — continue dependent stories from there$`.
    - B is adopted and stopped (`stop broke`) → `^Adopted from <orig>\. To continue the standard way: cd '.*' && '.*/studio-adopt' sync B$`.
    - A non-adopted story → no `Adopted from` line.
  - The existing suite still passes with the stub's ranges (no test asserted the bare `T$k complete`).
- [ ] **Step 3: Run to see them fail.** `TESTS_ONLY="test_lanes_context_preflight test_lanes_check_unit_first test_lanes_report_adopted_lines" sh tests/overnight_lanes_test.sh`. Expected: FAIL.
- [ ] **Step 4: Implement.**
  - `mf_check`: after the spec-refusals loop:
    ```sh
    for _cx in $(sed -n '/^## /q; s/^Context:[[:space:]]*//p' "$MF_TMP/plan" | head -n 1 | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); do
      git -C "$START_DIR" cat-file -e "$MF_DOCS:$_cx" 2>/dev/null || refuse "$_id: Context file $_cx is not in Docs: $MF_DOCS"
    done
    ```
  - `final_gate_cmds`: compute the engine part as today (or the hook), then print
    `<part> && sh '<SELF_DIR>/studio-setup' gate`.
  - `final_integration`: after Step 1:
    ```sh
    _fi_su=""
    _fi_se="$( cd "$FINAL_W" && sh "$SELF_DIR/studio-setup" 2>&1 >/dev/null )" || _fi_su="$_fi_se"
    ```
    In Step 3, when `_fi_su` is set: `FINAL_GATE=red`, `_fi_log=<setup log>`,
    `final_note "$_fi_su"`, skip the gate/repair block and the `RECORD/gate` write.
    The existing `[ "$FINAL_GATE" = green ] || …` line then sets red.
  - `progress_direct`: after the worktree add/reuse:
    `_pd_se="$( cd "$FINAL_W" && sh "$SELF_DIR/studio-setup" 2>&1 >/dev/null )" || { FINAL_COLOR=red; final_note "$_pd_se"; return 1; }`.
  - `story_ledger_text` + report lines per D39, inserted after the `Landed:`/`Not landed:` `case`.
- [ ] **Step 5: Run the tests.** `sh tests/overnight_lanes_test.sh`. Expected: PASS.
- [ ] **Step 6: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 7: Commit.** `feat(overnight): Context preflight, setup and gate_command at the final integration, adopted report lines (#35)`.

---

### Task 9: Execute skill — §0, §6, §7, §8, §11

Files: `studios/game-dev/skills/execute/SKILL.md`, at these sections (relocate with
`grep -n '^## '` and the literals):
- §0 lane bullets :74-90 — `grep -n 'STUDIO_DOCS_REV'`;
- (c) :148-157 — `grep -n '(c) Only after that check'`;
- *Where to start* :166 — `grep -n 'Where to start\*\*, once isolated'`;
- §6 :431 — `grep -n 'short commit range'`;
- §7 step 1 :454 — `grep -n '1. \*\*Gate.\*\*'`;
- §7 integration :572-590 — `grep -n 'Step 1.s red-gate loop does not run'`;
- §8 *Which unit* :618 — `grep -n 'Which unit:'`;
- §8 Inputs :607 — `grep -n '\*\*Inputs:\*\*'`;
- §11 *Verify what failed* :792 — `grep -n 'Verify what failed'`.

Also `tests/studio_test.sh` (new `test_execute_adopt`, added to `run_tests` at `grep -n '^run_tests' tests/studio_test.sh`).

Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L158-158, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L194-194, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L199-205, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L211-212, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L219-219, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L228-234, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L246-246, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L279-285, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L370-370
Review: task

**Interfaces:**
- Produces: the skill text below. Every literal in quotes is asserted by `test_execute_adopt`.
- Consumes: `studio-setup`, `studio-setup gate`, `studio-adopt sync`, `studio-brief check <k>`.
- Literals that must keep matching (existing tests):
  - `git checkout $STUDIO_DOCS_REV -- <spec> <plan> .studio/ledger/<id>.md`
  - `` git checkout $STUDIO_DOCS_REV -- <spec> <plan>`, and only when ``
  - `docs(<id>): plan at run docs`
  - `studio-state ledger "base origin/<Target>"`
  - `SDD ledger — plan:`
  - `STUDIO_REPAIR=gate:<log>`
  - `` `studio-test <path>` for each ``
  - `Stop: gate red — <failing command and line>`
  - `never runs SDD.s pre-flight conflict scan`
  - `studio-brief task <n>`, `studio-brief final`
  - `Up to three rounds, a round`
  - exactly six `` Under `--one`, see §8 `` (the new text never uses that phrase)
  - `(see §8, Operator messages)` counts unchanged (§0: 2)

- [ ] **Step 1: Write the failing test** in `tests/studio_test.sh`:

```sh
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
  assert_contains "$E" 'check done <range of its fix commits, or none>' "the check unit's last line"
  assert_contains "$E" 'Stop: check — <reason>' "a check it cannot fix stops"
  assert_contains "$E" 'commits already on the branch for this task: <first>..<last> — check and finish them; do not start over' "the part-done brief line (AC16)"
  assert_contains "$E" 'verify with the command that failed' "§11 (AC20)"
  assert_contains "$E" 'Direct mode runs no finish gate, so `gate_command` does not run there' "direct mode (AC20)"
}
```
- [ ] **Step 2: Run to see it fail.** `TESTS_ONLY=test_execute_adopt sh tests/studio_test.sh`. Expected: FAIL.
- [ ] **Step 3: Edit the skill.** Add, without removing any literal listed above:
  - **§0, both lane paths:** keep the existing sentences. Add "When the plan has a
    `Context:` header, the docs sync is …" with the two `<Context paths>` forms.
    - New-branch path: after the `base origin/<Target>` line, when the copied
      `.studio/ledger/<id>.md` has an `adopted` line:
      `studio-state ledger "adopt-base $(git rev-parse HEAD)"`.
  - **§0, after `studio-state set branch <Branch>` and the `base` line** (lane), and after (c)
    / the *Enter the feature checkout* resume (single-plan): "Then run `studio-setup` from
    the worktree root (`worktree_setup`; a no-op when unset or already done)."
    - On exit 1: `studio-state ledger "Stop: worktree setup failed — exit <n> — log <path>"`
      (its stderr line), committed as §8's stops are committed; end the turn.
  - **§0, then, for a story whose feature ledger has an `adopted` line:** run
    `` `studio-adopt sync <id>` `` "after the worktree is entered and set up, and before
    *Where to start* reads `task`".
    - On exit 1: `Stop: adopt sync — <its stderr line>`, committed; under a lane the
      runner holds the story.
    - Keep its report: a `T<k+1> in progress: <first>..<last>` line feeds the task brief (§8 Inputs).
    - Add D37's note: a docs-sync commit on a branch that is behind `origin/<Branch>`
      diverges it, and sync then holds the story — never auto-repaired.
  - **§6:** `studio-state ledger "T<n> complete <full sha>..<full sha>"`
    (`git rev-parse` of HEAD before the task and of its last commit). Existing short-sha
    lines still parse.
  - **§7 step 1:** a fourth bullet: "`studio-setup gate` — exit 0 (it runs the project's
    `gate_command` under the gate lock; silent when unset)." A non-zero exit is a red gate.
    - Under a lane: `Stop: gate red — gate_command exit <n> — log <path>`.
    - Single-plan: the three `fix(gate)` rounds, then the draft PR.
    - Add: "Direct mode runs no finish gate, so `gate_command` does not run there."
  - **§8 Which unit:** first bullet: "`check requested` without `check done` in the feature
    ledger: the check unit (below), before any task, final review or finish."
  - **§8 Inputs:** "a check unit reads only `studio-brief check <k>` (k from `task`)"; and
    "a task unit whose §0 sync reported `T<k+1> in progress: <first>..<last>` adds to the
    implementer's brief: `commits already on the branch for this task: <first>..<last> — check and finish them; do not start over`".
  - **§8, new paragraph "Check unit"** (prose, no `###` heading). It runs:
    1. `studio-test`, then `studio-setup gate`;
    2. a final-review-rubric review (§5's reviewer brief) of the brief's range against
       tasks 1..k;
    3. fixes in this unit, each `fix(check): …` plus
       `studio-state ledger "check Ruling: <decision> — <why> — <cost if wrong>"`;
    4. then `studio-state ledger "check done <range of its fix commits, or none>"`, commit, push.

    A finding it cannot fix, or a red gate it cannot make green: `Stop: check — <reason>`,
    committed. `k` never changes.
  - **§11:** add "When the Stop names `gate_command`, verify with the command that failed:
    `studio-setup gate`; otherwise `studio-test <path>` for each failing file, as below."
- [ ] **Step 4: Run the tests.** `sh tests/studio_test.sh`. Expected: PASS (every existing execute test too).
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `docs(execute): adopt sync, worktree setup, gate_command, check unit, full-sha ranges (#35)`.

---

### Task 10: Autopilot adopt branch, Multica instructions and README

Files:
- `shared/omega/skills/autopilot/SKILL.md`:
  - step 1's story-list question :68 — `grep -n 'Then ask the story list'`;
  - step 3 :99-115 — `grep -n 'Seed every story'`;
  - step 4 :116-121 — `grep -n 'Readiness checklist'`.
- `tests/omega_contracts/autopilot_contract.sh`
- `integrations/multica/agent-instructions.md`
- `integrations/multica/README.md` (`## Nightly workflow` step 1, `grep -n 'Plan (terminal, in the project)'`)
- `integrations/multica/tests/readme_test.sh`

Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L65-66, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L100-136, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L193-193, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L237-237, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L244-244, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L370-370
Review: final

**Interfaces:**
- Produces: the adopt branch's text (contract-tested phrases below), the agent-instructions
  line (AC23) and the README step 1 phrase.
- Consumes: `studio-adopt inspect|seed|sync`, `studio-overnight next`, `/game-dev:plan` and
  `/game-dev:brainstorm`, SDD's pre-flight conflict scan.

- [ ] **Step 1: Write the failing tests.**
  - In `autopilot_contract.sh`, inside `test_autopilot_contract` (do not add a new file:
    `test_skill_contracts` asserts seven contract files), assert these literals:
    - `source plan`, `source spec`, `git ls-files --error-unmatch`, `STUDIO_STORY=<id> studio-state init`,
      `source <plan> spec <spec or ->`;
    - `studio-adopt inspect <id> --branch <Branch> --plan <original>`, `gap check`,
      `` `adopt` or `plan: <gaps>` ``, `verdict adopt`, `verdict plan`,
      `at most 4 stories per question`;
    - `adopted <original> -> <new plan>`, `tasks 1..k keep the original's titles and boundaries`;
    - `never edits the original`, `Source: <original plan path>`, `Status: Draft (awaiting approval)`,
      `1:1 with the original`, `` `<original>:L<a>-<b>` ``, `pre-flight conflict scan`;
    - `studio-gate <who> -- <cmd>` (AC21);
    - `docs/game-dev/adopted/<id>/`, `**check the built work?**`, `check requested`;
    - `studio-adopt seed <id>`, `after step 3.2's re-key and before`;
    - `studio-adopt sync <id>` in the readiness step;
    - `superpowers 6.4.1`.

    Then add a separate function `test_autopilot_adopt_order`, called from
    `test_autopilot_contract`'s end so the seven-file count stays. It finds the line numbers
    of these five phrases in the skill and asserts they rise:
    1. `` `studio-state set spec <spec>`, where `<spec>` is the source spec ``
    2. `Spec and Plan cells are set to`
    3. `` so `next_match` and `Docs:` see the plan ``
    4. `` `Decisions swept <id>` after asking ``
    5. `` `adopted <original> -> <converted plan>` ``
  - In `readme_test.sh`:
    - add `or point autopilot at an existing plan` to `test_readme_teaching_phrases`'s list;
    - add `test_agent_instructions_adopted_line`:
      `assert_contains "$M/agent-instructions.md" "^- For adopted stories, include the report's studio-adopt line in your summary\.$" "AC23"`,
      added to the file's `run_tests`.
- [ ] **Step 2: Run to see them fail.** `TESTS_ONLY=test_skill_contracts sh tests/omega_test.sh`; `sh integrations/multica/tests/readme_test.sh`. Expected: FAIL.
- [ ] **Step 3: Write the skill text.** Each step explains what it does as it runs it (Teaching, L65).
  - **Step 1** (after the story-list question): ask each story's **source plan** (path or `-`)
    and **source spec** (path or `-`) in the same question.
    - Refuse and re-ask a path that is not repo-relative, not normalized (`./`, `..`)
      or not tracked (`git ls-files --error-unmatch`).
    - For a source plan: `STUDIO_STORY=<id> studio-state init`, then
      `studio-state ledger "source <plan> spec <spec or ->"` with `STUDIO_STORY=<id>`
      (D41). It is committed on `run/<slug>` with the manifest.
  - **New step 1a, "Adopt"** (stories with a source plan), in order:
    1. `studio-adopt inspect <id> --branch <Branch> --plan <original>` (a mismatch stops
       that story with inspect's line).
    2. The gap check: the four gap kinds of AC2, verbatim. Show `adopt` or `plan: <gaps>`
       per story, confirmed in one `AskUserQuestion` (at most 4 stories per question), and
       ledger `verdict adopt|plan`.
    3. `plan` stories: AC3's two paths, with the seeding sentence ("tasks 1..k keep the
       original's titles and boundaries, unchanged and marked finished; planning covers
       task k+1 onward"). After planning, step 3 ledgers `adopted <original> -> <new plan>`.
    4. `adopt` stories: AC4's conversion, every bullet:
       - the converted plan's header lines;
       - `## Global Constraints` plus the AC21 rule "heavy commands a task runs (a test-tag
         run, a store write) are wrapped as `studio-gate <who> -- <cmd>`";
       - `## Decisions`, `## Acceptance criteria`;
       - tasks 1:1 with the original above `## Backlog`, with the two `Spec:` forms and the
         `Review:` rule.

       It runs SDD's pre-flight conflict scan over tasks k+1..N and the file-exists check,
       ruled with the operator and written to `## Decisions`.
    5. AC5: side-by-side, one-word approval, then the five steps in the order above.
    6. AC6: carry files → `docs/game-dev/adopted/<id>/`, committed, named in `Context:`.
    7. AC7: when inspect shows k ≥ 1 or part-done commits: **check the built work?** →
       `check requested`.
  - **Step 3, half-done path:** after 3.2's re-key and before `studio-state check --rebuild`,
    for an adopted story: `studio-adopt seed <id>` in the story worktree (pass `--base` when
    inspect was given one). A not-started adopted story has no seed (execute §0 records its
    base).
  - **Step 4:** a checklist line: `studio-adopt sync <id>` from each adopted story's
    worktree exits 0. A not-started story is skipped with a note.
  - Name superpowers 6.4.1's sdd-workspace rule once (D42).
  - `agent-instructions.md`: add the AC23 bullet before the last bullet.
  - README step 1: append "— or point autopilot at an existing plan (made outside the
    studio, e.g. with superpowers): it converts it, keeps the original, and takes the
    finished work from the SDD ledger."
  - Use no new `--flag` and no new `` `/word` `` (`readme_test` checks both).
- [ ] **Step 4: Run the tests.** `sh tests/omega_test.sh` and `sh integrations/multica/tests/run.sh`. Expected: PASS.
- [ ] **Step 5: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 6: Commit.** `docs(autopilot): adopt outside-planned stories; Multica instructions and README (#35)`.

---

### Task 11: The round trip (Milestone gate 2)

Files: `tests/overnight_lanes_test.sh` (new helper `adopt_lanes_fixture`, tests `test_lanes_adopt_seeded_runs_rest`, `test_lanes_adopt_round_trip`)
Spec: docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L22-27, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L364-364, docs/game-dev/specs/2026-10-04-autopilot-adopt.md:L369-369
Review: task

**Interfaces:**
- Consumes: everything above. It produces no runtime code. A defect found here is fixed in
  the owning file as `fix(T11): …`, with that task's suite re-run.

- [ ] **Step 1: Write the helper and the tests.**

```sh
# adopt_lanes_fixture NAME — lanes_fixture NAME integration S1:-, then S1 made an
# adopted, half-done story as autopilot step 3 leaves it:
# - a 6-task original plan $AO and a 6-task converted plan (Story: S1, Source:)
#   in the manifest's Plan cell;
# - branch S1-b off origin/main with T1-T3 done the standard way (one commit each,
#   plus SDD claims in the worktree's $AWS for $AO), pushed;
# - the worktree $AW at $P/.claude/worktrees/S1-b;
# - `studio-adopt seed S1` committed, `check --rebuild` = 3/6, stage execute;
# - Docs: re-pointed at the new docs commit. Exports AO, AW, AWS.
adopt_lanes_fixture() {
  lanes_fixture "$1" integration S1:-
  AO=docs/superpowers/plans/2026-09-01-demo.md; AW="$P/.claude/worktrees/S1-b"; AWS=.superpowers/sdd/2026-09-01-demo
  export AO AW AWS
  _alf_c=docs/game-dev/plans/2026-10-01-S1.md
  ( set -e; cd "$P"
    mkdir -p "$(dirname "$AO")"
    { printf '# Demo\n\n'; for i in 1 2 3 4 5 6; do printf '### Task %s: step %s\n\nFiles: s%s.txt\n\n' "$i" "$i" "$i"; done; } > "$AO"
    { printf '# Plan: S1\n\nStory: S1\nSource: %s\n\n## Global Constraints\n\n- none\n\n## Decisions\n\n- none\n\n## Acceptance criteria\n\n1. works\n\n' "$AO"
      for i in 1 2 3 4 5 6; do printf '### Task %s: step %s\n\nSpec: %s:L3-4\nReview: final\n\n' "$i" "$i" "$AO"; done
      printf '## Backlog\n'; } > "$_alf_c"
    git add -A; git commit -q -m "adopt: plans"; git push -q origin run/demo
    git push -q origin "$(git rev-parse HEAD):refs/heads/main"   # the original is on main too
    git fetch -q origin
    STUDIO_STORY=S1; export STUDIO_STORY
    sh "$STATE_BIN" set task 0/6
    sh "$STATE_BIN" ledger "source $AO spec -"; sh "$STATE_BIN" ledger "adopted $AO -> $_alf_c"
    git worktree add -q --no-track -b S1-b "$AW" origin/main
    cd "$AW"; mkdir -p "$AWS"; printf '%s\n' "$AO" > "$AWS/plan-path"; printf '*\n' > .superpowers/sdd/.gitignore
    printf '# SDD ledger — plan: %s\n' "$AO" > "$AWS/progress.md"
    for i in 1 2 3; do
      _a="$(git rev-parse --short HEAD)"; printf '%s\n' "$i" > "s$i.txt"; git add "s$i.txt"; git commit -q -m "feat: step $i"
      printf 'Task %s: complete (commits %s..%s, review clean)\n' "$i" "$_a" "$(git rev-parse --short HEAD)" >> "$AWS/progress.md"
    done
    git push -q -u origin S1-b
    sh "$STATE_BIN" set branch S1-b; sh "$STATE_BIN" set stage execute
    sh "$ADOPT_BIN" seed S1; sh "$STATE_BIN" check --rebuild
    cd "$P"; unset STUDIO_STORY
    git add -A .studio/ledger; git commit -q -m "docs(run): demo planned"; git push -q origin run/demo
    _d="$(git rev-parse HEAD)"; sed "s/^Docs: .*/Docs: $_d/" "$MFP" > "$MFP.t" && mv "$MFP.t" "$MFP"
    git add "$MFP"; git commit -q -m "docs(run): demo docs"; git push -q origin run/demo ) >/dev/null 2>&1 \
    || { TESTS_RUN=$((TESTS_RUN + 1)); _fail "adopt_lanes_fixture $1: setup failed"; }
}
```
  (`ADOPT_BIN="$REPO_ROOT/studios/game-dev/bin/studio-adopt"` sits next to the suite's `STATE_BIN`.
  The fixture's manifest Plan cell already names `docs/game-dev/plans/2026-10-01-S1.md`,
  which this helper overwrites with the 6-task converted plan.)

  - `test_lanes_adopt_seeded_runs_rest`:
    - `adopt_lanes_fixture asr`; `run_lanes start "$MFP"`.
    - Exit 0, and `story_rows S1` =
      `1 S1-T4 progress,2 S1-T5 progress,3 S1-T6 progress,4 S1-final-review progress,5 S1-finish done,`.
    - The S1-b log has exactly one `feat(S1): T4`, one `T5` and one `T6` commit. The
      ledger's T4–T6 lines are full-sha ranges.
  - `test_lanes_adopt_round_trip` (Milestone gate 2):
    1. `adopt_lanes_fixture art`; `lholds_on 120`; S1's scenario `auto\nstop broke\n`;
       `lanes_bg`; `wait_for 'is_held S1' 60`; `lverb stop`; `wait_pid_or_fail "$RPID" 60`;
       `lholds_off`.
       - The run did T4 only: `story_rows S1` starts `1 S1-T4 progress,2 S1-T5`, and
         `rec S1` contains `was held: stop: broke`.
    2. By hand in `$AW`: commit the uncommitted `Stop:` ledger line
       (`git commit -qam "ledger: stop"`, as an operator resolving it would), then
       `STUDIO_STORY= sh "$ADOPT_BIN" sync S1` → exit 0.
       - `$AW/$AWS/progress.md` contains `^Task 4: complete (commits [0-9a-f]\{40\}\.\.[0-9a-f]\{40\}, review clean)$`.
    3. Standard-mode T5: in `$AW`, `_a=$(git rev-parse --short HEAD)`, then commit `s5.txt`
       as `feat: step 5 (standard)`, then append
       `Task 5: complete (commits $_a..<new short>, review clean)` to `$AW/$AWS/progress.md`.
    4. S1's scenario becomes `auto\nauto\nauto\n` (reset `$CALLS/m-S1` to 0);
       `run_lanes start "$MFP"` → exit 0.
       - The new run's `story_rows S1` = `1 S1-T5 progress,2 S1-final-review progress,3 S1-finish done,`
         (the first unit is labelled `T5`: D38).
       - `git -C "$AW" log --format=%s origin/S1-b` has `feat: step 5 (standard)` once,
         no `feat(S1): T5`, and `feat(S1): T6` once.
       - The ledger has a `chore(studio): ledger (sync)` commit whose diff adds
         `T5 complete <full>..<full>`.
       - `$(last_lanes_dir)/stories/S1` begins `landed `.
- [ ] **Step 2: Run them.** `TESTS_ONLY="test_lanes_adopt_seeded_runs_rest test_lanes_adopt_round_trip" sh tests/overnight_lanes_test.sh`.
  Expected: PASS. If one fails, find the owning task's file, fix it there with its suite
  re-run, and record the cause in the commit message.
- [ ] **Step 3: Whole core gate.** `sh tests/run_all.sh`. Expected: exit 0.
- [ ] **Step 4: Commit.** `test(overnight): adopted story round trip — milestone gate 2 (#35)`.

---

## Final gate

Run after Task 11, in this order.

**1. Whole-branch review (Opus, standalone).** Dispatch a fresh reviewer with
`model: "opus"` on `git diff origin/main...HEAD`. Its brief:
- Read the spec, and this plan's Global Constraints, Decisions D1–D43, Review Focus and
  Falsify sections.
- For AC1–AC25 write one line each: `ACn met: <file:line or test name>` or
  `ACn unmet: <what is missing>`. Write the same for each Global Constraint, each Review
  Focus item (naming its test), each Decision the diff could contradict, and each Falsify
  row marked UNVERIFIED.
- Check by reading:
  - no `local`, arrays, `[[`, GNU-only flags or `timeout` in the new or changed scripts;
  - `studio-adopt` writes full shas only, makes at most one commit per run, and restores the
    ledger file on every exit-1 path;
  - no committed fixture holds a machine path, an OS username or a real issue title;
  - the existing execute-contract literals are intact.
- Findings as `path:line: Critical|Important|Minor: problem. fix.`; the full report to a
  file, a hand-back of 1.5k characters or less.

Fixes go to a fresh fixer given the findings and the diff range. Each fix is a
`fix(final): …` commit with the trailers. Re-review only after a Critical, three or more
Importants, or a production-bug fix; never a third pass.

**2. Full milestone gate** (Milestone gate 1–2, automated):

```sh
sh tests/run_all.sh
sh integrations/multica/tests/run.sh
```

Expected: both exit 0. `test_lanes_adopt_round_trip` is Milestone gate 2.

**3. Live check** (Milestone gate 3; **operator-run**: the operator runs the steps that need
their machine; the controller records the results in the story):

| # | Who | When | What | Pass |
|---|-----|------|------|------|
| 1 | Operator | After the review fixes land and the plugin is reinstalled | In a real project with an epic planned outside the studio, run `claude-gd` → `/omega:autopilot`; give a fully planned, not-started story's source plan; answer the sorting, approval and built-work questions | The conversion shows titles 1:1; `studio-overnight start --dry-run <manifest>` exits 0 |
| 2 | Operator | After 1 | Start the run from a Multica issue assigned to the game-dev agent | The story lands on `integration/<slug>`; `report.md` has `Adopted from <original>; landed on integration/<slug> — continue dependent stories from there`; the agent's summary quotes it |
| 3 | Operator | Any time | Adopt a story stopped mid-task | `studio-adopt inspect` prints `T<k+1> in progress: <first>..<last>`; the night's first task unit continues from those commits (its branch keeps them; no restart) |
| 4 | Operator | The morning after 3 | Run the report's `studio-adopt sync` command in the story worktree, then open regular Claude on the original plan | The original's SDD ledger shows the night's tasks complete; SDD resumes at the next task |

---

## Falsify

### Claims

Checked against the code at 2986b0b (pre-#37). The trials ran under macOS `/bin/sh` (GNU
bash 3.2) with Apple Git 2.39.3, from the session scratchpad.

| # | Claim | How checked | Result |
|---|-------|-------------|--------|
| 1 | The fork point is `rev-list --count --first-parent tip --not origin/main`, then `--skip=n --max-count=1` (D20); it stays the original fork with main merged mid-branch | Trial t1: main merged between T2 and T3 → n=4, fork point = the first main commit; tip == main → n=0, fork = tip | OK |
| 2 | `git rev-list --first-parent A..B` lists the merge but not main's commits | Trial t1: `T2..HEAD` → `T3`, `Merge branch 'main'` | OK |
| 3 | `merge-base --is-ancestor`: 0 / 1 / 128 on a bad name; `X X` is 0 | Trials t1, t6 | OK |
| 4 | `rev-parse --verify --quiet <tok>^{commit}` on an unknown or ambiguous token prints nothing and exits 1 | Trial t1 (`deadbeef1`; an ambiguous 4-hex prefix) | OK |
| 5 | An ambiguous 4-hex commit prefix can be made offline and deterministically | Trial t8: 1000 fast-import commits with a fixed date → `0cb5` in two runs, under 1 s | OK |
| 6 | TERM to a backgrounded studio-gate ends the command's whole process group (grandchild sleeps), logs rc 143 and releases the lock; no GNU `timeout` needed | Trial t2 with the real `studio-gate`: `sleep 30 & sleep 31` gone; `gate.times` `setup 2 143`; lock removed | OK |
| 7 | `{ set -m; }` works in non-interactive `/bin/sh` (bash 3.2); `kill -TERM -<pgid>` reaches a grandchild; `wait $pid 2>/dev/null` hides the job notice | Trials t6, t7 | OK (dash: `set -m` may be refused; D6 falls back to the pid, and studio-gate's own ps-tree fallback covers its child) |
| 8 | The lock's `pid` equals `$!` of `sh studio-gate … &` (the timer start test) | Trial t2: the lock named `$G` after 2 polls | OK |
| 9 | `printf '%s' cmd \| cksum` prints `<crc> <bytes>` | Trial t1 | OK |
| 10 | The per-who awk window keeps the newest K per `who` | Trial t3 with K=3 | OK |
| 11 | Claim tokens: `tr -c '0-9a-f' ' '` plus a 7–40 length filter yields `abc1234 def5678`; `commits none` yields nothing | Trial t3 | OK |
| 12 | `git log --first-parent --diff-merges=first-parent --name-only --format=…` lists each commit's paths, and a merge's against its first parent, in one call | Trial t4 on git 2.39.3 (the runner already requires ≥ 2.38: `git_version_ok` in `mf_check`) | OK |
| 13 | Part-done must treat ".studio/ only" and "docs only" as one union | Execute §0 new-branch commit holds `<spec> <plan> .studio/ledger/<id>.md` (SKILL :84-85); trial t4's filter | FIXED (D22) |
| 14 | BSD `grep -E '^[^\\]*$'` refuses a backslash and accepts empty; the cfg-style sed reads `worktree_setup` without matching `worktree_setup_minutes` | Trial t5 | OK |
| 15 | `sed -n '/^## /q; s/^Context:…//p'` reads the header before the first `## ` and ignores a later `Context:` | Trial t5 | OK |
| 16 | `next_match spec` needs a tracked .md with a `## Stories` row; `plan` = `Story: <id>` in `git ls-files '*.md'`; filled cells bypass both; `lanes_next` reads `.studio/ledger/<spec slug>.md` for `spec approved`, `plan approved`, `Decisions swept` with `grep -qF` | Read overnight-lanes.sh :1638-1696 | OK |
| 17 | `model_for` exits 3 on an unknown label; `label_for` cases; `snapshot`'s SIG = stage;task;frd;shipped | Read studio-overnight :144-153, :481-497, :525-533 | OK |
| 18 | `story_first_label` sets the SIG_* vars itself before `label_for` (so it must set the new ones, under `set -u`) | Read overnight-lanes.sh :222-227 | OK (D15) |
| 19 | `story_units_table`'s label regex omits any new label | Read overnight-lanes.sh :1002 | FIXED (D15 adds `check`) |
| 20 | `gate_room_check` reads only `$2 == "studio-test"`; the existing test's regex has `.*` after `took 90 min` | Read studio-overnight :456-465; tests/overnight_lanes_test.sh :2097-2106 | OK (D13 keeps the prefix) |
| 21 | studio-gate keeps `tail -n 49` + 1 lines in total; the existing 55→50 test also passes with a per-who window (all `w`) | Read studio-gate :220-224; toolkit_test.sh :851-853 | OK |
| 22 | `studio-brief` verbs are `task <n>` and `final`; Spec items are `*§*` or `*:L[0-9]*-[0-9]*`; `final` fails `## Acceptance criteria not found in <spec>`; the ledger grep prefix lacks `check` | Read studio-brief :33-35, :123-157, :167-168, :220 | FIXED (D17 adds `check`) |
| 23 | `studio-state` reads T lines with `sed -n 's/^- [0-9-]* T\([0-9]*\) complete.*/\1/p'` in two places (rebuild :291, check :316); `ledger` needs the pointer (`need_state`, "no story") | Read studio-state :255-334 | OK (D2, D41) |
| 24 | Execute §0 docs sync, `base origin/<Target>`, §6 `short commit range`, §7 integration red line, §8 Which unit, §11 `studio-test <path>`; direct mode skips step 1 | Read execute SKILL :74-90, :166-178, :428-431, :572-590, :618-622, :761-800 | OK |
| 25 | The literals asserted by `test_execute_lanes`, `test_execute_one_contract` (exactly 6 pointers), `test_execute_gate_repair` and `test_execute_operator_messages` (§0 count 2) | Read tests/studio_test.sh :424-460, :543-599 | OK (T9 lists them as must-keep) |
| 26 | Autopilot step 1 story-list question, step 3 per-story seed with 3.1–3.3, step 4 checklist | Read autopilot SKILL :55-121 | OK |
| 27 | `test_skill_contracts` asserts seven contract files; contracts are sourced, named `test_<name>_contract` | Read tests/omega_test.sh :629-634, :45; `ls tests/omega_contracts` (7) | OK (T10 adds no file) |
| 28 | `tests/run_all.sh` runs every `tests/*_test.sh` | Read run_all.sh | OK |
| 29 | `test_bin_syntax` needs every `studios/*/bin/*` to pass `sh -n` and be executable; bins need no list (the whole dir is on PATH; `studio.json` lists only `commands`) | Read tests/studio_test.sh :108-118; studio.json | OK |
| 30 | The lanes stub's `auto` writes `T$k complete` without a range; no test asserts the bare form | Read tests/overnight_lanes_test.sh :184; `grep -rn 'commit range' tests/` empty | FIXED (D43) |
| 31 | The multica `install_test.sh` compares the agent instructions with the file (data-driven); `readme_test.sh` checks flags and `` `/word` `` commands | Read install_test.sh :111; readme_test.sh :24-60 | OK |
| 32 | superpowers 6.4.1 `sdd-workspace`: marker `plan-path` (repo-relative); slug, then `-<parent>`, then `-<parent>-<n>` from 2; a missing marker is claimed; `printf '*\n' > .superpowers/sdd/.gitignore`; SDD lines `Task <N>: complete (commits <base7>..<head7>, review clean\|<K> parked)`, `parked — … — Ruling:`, `fix round <R>/5 (…; commits a..b)` | Read the script and SKILL.md :136-149, :406-443 | OK (D32 replicates) |
| 33 | `record_landed` writes `<id>\t<Target>\t<sha>\t<epoch>` to `$STATE_ROOT/.studio/runs/<slug>/landed.tsv` | Read overnight-lanes.sh :261-270, `RECORD=` | OK |
| 34 | `run_event unit_started` carries `label=$2` and `model=`; a held story's event is `story_state` with `why` | Read studio-overnight :558, :937 | OK |
| 35 | The spec's test files `tests/studio_state_test.sh` and `tests/studio_gate_test.sh` | `ls tests/` — neither exists | FIXED (D1) |
| 36 | The `.studio/reports/.gitignore` with `*` is written only in the start checkout's reports dir | Read studio-overnight `run_setup` | OK (D9: studio-setup writes it in its tree) |
| 37 | The first unit after a standard-mode task is labelled from the pre-sync `task` | Reasoned from `story_units` (label computed before `run_unit`) and the lanes stub; not run until T11 | UNVERIFIED (T11 asserts the commits, not the label; D38) |
| 38 | `studio-setup`'s `wait 2>/dev/null` silences bash's job notice when `set -m` is on inside a script that is itself under the test's `$( )` | Trial t7 covers a plain script; T2's `test_setup_timeout_ends_group` asserts a one-line stderr | UNVERIFIED (pinned by the test) |

### Task order

- T1 first: T2's `test_setup_runs_under_lock_and_logs` reads `gate.times` lines. T5/T6's
  `check --rebuild` relies on the reset filter.
- T2 before T7/T8: the runner and the stub call `studio-setup`.
- T3 before T9: §8 names `studio-brief check <k>`.
- T4 → T5 → T6: seed and sync use the T4 engine. T5's rewrite test uses only seed; the sync
  half of the rewrite assertion lives in T6.
- T6 before T8: the stub's `auto` runs the real `studio-adopt sync`.
- T7 before T8: the `check` label and `gate_log_of` are what T8's lanes cases observe.
- T9 and T10 are skill text with contract tests. They need the tools' names fixed (T2–T6)
  but no runtime code.
- T11 last: it needs every runtime piece.

No task uses a name a later task produces (checked against each Interfaces block).

### Self-review: AC → task

| AC | Where it is built | Test that proves it |
|----|-------------------|---------------------|
| 1–7 | T10 (+T3, T5, T8 pieces) | `test_autopilot_contract`, `test_autopilot_adopt_order`, `test_lanes_next_adopted_planned`, `test_adopt_seed_refuses_changed_title`, `test_brief_original_plan_item` |
| 8, 11 | T4 | `test_adopt_inspect_*`, `test_adopt_part_done_filter`, `test_adopt_post_task_commits` |
| 9 | T5, T1, T9 | `test_adopt_seed_*`, `test_state_check_ignores_before_adopt_reset`, `test_execute_adopt` |
| 10 | T6 (T4 engine) | `test_sync_*`, `test_adopt_workspace_lookup_two_trees` |
| 12 | T9, T10, T8, T6 | contract tests, `test_lanes_adopt_sync_fail_holds`, `test_lanes_adopt_round_trip` |
| 13–15 | T7, T9, T3, T8 | `test_overnight_check_unit`, `test_lanes_check_unit_first`, `test_brief_check_*`, `test_execute_adopt` |
| 16 | T9, T4 | `test_execute_adopt`, `test_adopt_part_done_filter` |
| 17, 18 | T3, T8, T9 | `test_brief_*`, `test_lanes_context_preflight`, `test_execute_adopt` |
| 19 | T2, T1, T8, T9 | `test_setup_*`, `test_gate_times_window_per_who`, `test_lanes_setup_fail_*` |
| 20 | T2, T7, T8, T9 | `test_setup_gate_green_and_red`, `test_lanes_gate_log_from_stop`, `test_lanes_gate_command_*`, `test_lanes_gate_room_warning` |
| 21, 23 | T10 | `test_autopilot_contract`, `test_agent_instructions_adopted_line` |
| 22 | T8 | `test_lanes_report_adopted_lines` |
| 24 | T8 | `test_lanes_check_unit_first`, `test_lanes_adopt_sync_fail_holds` |
| 25 | T9, T8, T4 | `test_execute_adopt`, stub, `test_adopt_short_sha_lines_parse` |
| Gate 1–2 | T1–T11, Final gate 2 | the suites |
| Gate 3 | Final gate 3 | operator table |

### Placeholder scan

`grep -nE 'TBD|TODO|implement later|fill in|similar to Task'` over the plan finds one hit,
not a placeholder: the AC2 gap kinds name `TBD`/`TODO` as text the gap check looks for.
`…` in prose stands for values the same step names (a ledger line's tail, a log path),
never for missing design. `<a>`, `<b>`, `<n>`, `<path>` are the spec's own line-format
placeholders, quoted verbatim.

### Spec defects

None blocks the plan. Each has a ruling here; the operator may overrule.

1. **Test file names** (L288, L360-361): `tests/studio_state_test.sh` and `tests/studio_gate_test.sh`
   do not exist. Ruling: D1 (use `tests/state_test.sh` and `tests/toolkit_test.sh`).
2. **`seed` has no `--base`** (L294), but inspect does (L293), and the base must be the one
   inspect verified. Ruling: D27 (add `[--base <sha>]` to seed). **Needs the operator's
   nod** — it changes a spec'd usage line.
3. **AC11's "only .studio/" and "only docs" rules, read separately,** count execute §0's
   new-branch docs commit (spec, plan and ledger in one commit) as part-done work. Ruling:
   D22 (one union).
4. **`gate_command` plumbing** is not given a home in the spec's file list. Ruling: D4 (a `gate`
   verb on `studio-setup`). **The operator may veto** in favour of prose plus a runner copy.
5. **A check unit at k = 0** (k = 0 with part-done commits, AC7) has no finished range. Ruling:
   D16 (`check 0` prints `range: none`; the unit runs the gates and ledgers `check done none`).
6. **The first unit's label after standard-mode progress** names the pre-sync task (D38).
   This is cosmetic (labels name files); the Multica card shows `T5` for the unit that
   builds T6. No ruling needed unless the operator wants a sync-aware label.

## Task order

T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11, sequential on
`worktree-issue-35-autopilot-adopt`, after the Prerequisite.

# Unique story ids — a new story never inherits a dead story's ledger — Spec

Story: #56 (GitHub issue). Status: Approved (operator, 2026-10-07; design approved in
chat, spec falsifier findings folded in, written spec approved).
Classification: architectural (the story-id contract is shared by the CLIs and
three skills).

## What happened (phoenix, 2026-10-07)

The run manifest `docs/runs/kan-1541-greater-slime-move-sfx.md` named its only
story `S1`. Ledgers are keyed by story id at `.studio/ledger/<id>.md`, which is
tracked, and phoenix `origin/main` already held `S1.md` from KAN-1499
(mob-composer, run `mob-composer-parity`): `plan approved
docs/game-dev/plans/2026-10-02-mob-composer-no-presets.md`, `T1 complete`,
`T2 complete`, `shipped KAN-1499-mob-composer-no-presets`. Seeding the new story
as `S1` would have made `check --rebuild` count T1–T2 done (skipping the new
plan's Task 1), and the story branch, cut from main, would carry the `shipped`
line into the landing check. The first symptom was `next: S1 matches two plans`;
the planning session filled the manifest's Plan cell and missed the ledger. The
autopilot agent's kickoff review caught it; the story was renamed `KAN-1541`.
By then the planning ledger already held a stray `Decisions swept S1`.

**Root cause.** Story ids restart at S1 in every manifest, but the ledger
namespace they key is repo-global and outlives the run. The existing id guard
(concurrent-runs AC8/AC15, `mf_conflicts`) only refuses ids of live or stopped
runs, so a done run's ids look free.

## Goal

A story id, once used in a project, is not handed out again (the rule Jira keys
and database keys follow), and a reused id is refused when it is chosen or
planned, not at kickoff.

## Requirements

### R1. Id scheme for new rows

- With a ticket that matches the id pattern `^[A-Za-z0-9._-]+$`, the id is the
  ticket (`KAN-1541`). Rows sharing a ticket get `KAN-1541-1`, `KAN-1541-2`.
- Otherwise (no ticket, or a ticket such as `#56` or a URL that does not fit the
  pattern) the id is `<slug>-S<n>` with the run slug.
- Stated in `shared/omega/skills/autopilot/SKILL.md`'s story-list question, as
  the id it proposes by default. `studios/game-dev/skills/brainstorm/SKILL.md`'s
  Stories table (written only under a manifest) already uses the manifest's ids;
  it gains one sentence saying so.
- No id format check is added. Existing manifests and ledgers with `S<n>` ids
  keep working unchanged; nothing is migrated.

### R2. `studio-overnight check-id`

```
studio-overnight check-id <id> [--plan <path>|-] [--ticket <ticket>|-] [--slug <slug>] [--branch <branch>|-]
```

Defaults: when `.studio/run` in the current checkout names a manifest that lists
`<id>`, `--plan`, `--ticket` and `--slug` default to that row's Plan and Ticket
cells and the manifest's slug; otherwise `-` / none. "This story's plan" is only
ever the Plan cell or `--plan`, never a plan found by its `Story:` header (in
phoenix that search returned the old plan). Below, `<d>` is the default branch
from `origin/HEAD`, read as `refs/remotes/origin/<d>`; check-id does not fetch.

`<id>` is **taken** when any of these holds. Ids compare case-insensitively
(macOS checkouts treat `s1.md` and `S1.md` as one file), so a ledger file is
found by listing `.studio/ledger/` on the ref, not by a case-sensitive `git
show`.

1. **Ledger on the default branch.** `.studio/ledger/<id>.md` exists on
   `origin/<d>` and is not this story's own. It is this story's own only when
   this story's plan is known and equals the last `plan approved <p>`, or the
   last `adopted <orig> -> <p>`, in that ledger, or when this run's record lists
   `<id>` in `landed.tsv`. Any other existing file is taken, whatever lines it
   holds: an inherited `adopted` or `adopt-base` line also misleads the runner.
2. **Ledger on another run's integration branch.** The same file exists on
   `refs/remotes/origin/integration/<s>` for any `<s>` other than this run's
   slug (a done integration run whose PR to main is still open). Integration
   branches are cut from main and inherit its ledgers, so a ledger counts here
   only when its blob differs from the default branch's at the same path
   (absent there counts as differing); main's own ledgers are judged by rule 1.
3. **Another run's record.** A run record under `<root>/.studio/runs/` other
   than this run's own (live, stopped, done or archived `<slug>.<ts>`) lists
   `<id>` in `rows.tsv`. This is local to the machine; rules 1–2 cover the
   shared repo. A `rows.tsv` row whose Branch equals this story's Branch
   (`--branch <b>|-`, default the manifest row's Branch cell) does not count:
   it is the same story carried over from an abandoned or done run, which
   keeps its id and branch (amended after the final review).
4. **Plan on the default branch.** A file under `docs/game-dev/plans/` on
   `origin/<d>`, other than this story's plan, has a line exactly
   `Story: <id>`. Method: `git grep -l -F -e "Story: <id>" refs/remotes/origin/<d>
   -- docs/game-dev/plans`, then each hit re-tested whole-line with
   `git show <ref>:<path> | grep -qxF "Story: <id>"` (git grep has no `-x`).

Plans and ledgers that exist only on the current run branch are the run's own
work and are not checked; duplicates inside one run stay covered by `next`'s
existing "matches two plans" refusal and `mf_check`'s duplicate-row check.

Exit codes follow studio-overnight's documented convention (1 refused,
2 usage):
- **0**, free: prints `check-id: <id> is free`.
- **1**, taken: one stderr line per reason, then the suggestion:

  ```
  studio-overnight: story id 'S1' is taken: origin/main:.studio/ledger/S1.md belongs to another story (plan docs/game-dev/plans/2026-10-02-mob-composer-no-presets.md, shipped KAN-1499-mob-composer-no-presets)
  studio-overnight: story id 'S1' is taken: origin/main:docs/game-dev/plans/2026-10-02-mob-composer-no-presets.md says 'Story: S1'
  studio-overnight: story id 'S1' is taken: run mob-composer-parity (record .studio/runs/mob-composer-parity) lists it
  studio-overnight: use 'KAN-1541' instead
  ```

  The `(…)` detail names the ledger's last `plan approved` path and `shipped`
  value when present. The suggestion is the first candidate that matches the id
  pattern, is not another row's id in the current manifest, and is itself free
  by rules 1–4: `<ticket>` (when different from `<id>`), `<ticket>-2` …
  `<ticket>-9`, then `<slug>-S1` … `<slug>-S9`. With none, it prints `pick an
  unused id: the ticket, or <run slug>-S<n>`.
- **2**, usage: a bad option, an id not matching the pattern, or `origin/HEAD`
  not set (the same message start's preflight gives today).

### R3. Callers

- **autopilot, new run.** The run slug is checked and `git fetch origin` runs
  *before* the story-list question (today both come after it), so the default
  id and the check see a fresh default branch. Each proposed id runs
  `studio-overnight check-id <id> --ticket <t> --slug <slug> --plan -`; exit 1 →
  re-ask with the message, the same way AC15 re-asks a live run's id.
- **`/game-dev:brainstorm` and `/game-dev:plan`, manifest forms** (`<slug>/<id>`,
  or `<id>` when `.studio/run` lists it). First step after entering the run
  worktree: `studio-overnight check-id <id>`. Non-zero → print its output and
  stop, before writing any file or ledger line. The bare `<id>` form outside a
  manifest keeps today's meaning (its ledger is spec-slug keyed) and is not
  checked.
- **`studio-overnight next`.** Per row, before classification, the same check
  with the row's Plan cell. Taken → print the message and exit 2 (as an
  ambiguous match does today).
- **`studio-overnight start` (and `--dry-run`) preflight**, manifest runs, in
  `mf_check`. Per row, after the existing fetch, the same check with the row's
  Plan cell. Taken → refuse to start with the message. This is the backstop; it
  reads the freshly fetched default branch.

### R4. Whole-line ledger matches in `next`

`next`'s classification (`overnight-lanes.sh` `lanes_next`) matches `spec
approved <spec>`, `plan approved <plan>` and `Decisions swept <id>` against the
text after `- <date> ` exactly, not with `grep -F` substring matches. Today
`Decisions swept S10` marks row `S1` swept, and `plan approved <plan>.old`
satisfies `<plan>`.

### R5. Docs

`studio-overnight` usage text and `README.md`'s studio-overnight command list
gain `check-id`.

## Not doing

- **Retiring a shipped story's ledger** (e.g. moving it to
  `.studio/ledger/shipped/`). After R1–R3 a reused id cannot get past planning,
  so this protects nothing extra. It would add a second lookup to everything
  that reads ledgers where they are now: the landing check
  (`origin/<Branch>:.studio/ledger/<id>.md`), adopt, status and retro. Follow-up
  issue only if old ledgers become a nuisance.
- Re-planning a story after its run started (not supported today, autopilot
  step 1). If forced, its branch ledger keeps the old `plan approved` path and a
  resumed start would refuse it.
- Renaming existing `S<n>` ledgers or manifests in any project.
- Changing phoenix.
- Folding the live/stopped-run guard (AC8, `mf_conflicts`) into check-id; it
  stays where it is.

## Test strategy

The plain-sh harness. `tests/overnight_lanes_test.sh`'s `lanes_fixture` gains a
knob (e.g. `LANES_MAIN_PRE=<dir>`) whose files are committed to `main` before
`run/demo` is cut, so the run branch inherits them as in phoenix.

1. `check-id S1` exits 1 when `origin/main` holds a shipped `S1.md` for another
   plan: names `origin/main:.studio/ledger/S1.md`, the old plan and the shipped
   branch, and suggests the row's ticket.
2. `check-id S1` exits 1 when only a plan under `docs/game-dev/plans/` on
   `origin/main` says `Story: S1`; a spec on main with a `Story: S1` line does
   not count.
3. A plan saying `Story: KAN-1541` on the run branch only (the story's own plan)
   does not make `KAN-1541` taken.
4. Own ledger: `origin/main` holds `S1.md` whose last `plan approved` equals the
   row's Plan cell, and that plan itself (`Story: S1`) → exit 0.
5. Own adopted ledger: `origin/main` holds a landed `S1.md` with `adopted <orig>
   -> <row's Plan>` and no `plan approved` → `start --dry-run` exits 0.
6. `S1.md` on `origin/integration/other` (another run's slug) → exit 1;
   on `origin/integration/<this slug>` → not taken.
7. A done record `.studio/runs/old/rows.tsv` (and an archived `old.<ts>`)
   listing `S1` → exit 1.
8. `s1.md` on `origin/main` makes `S1` taken.
9. `next` exits 2 with the check-id message for a stale `S1` row (pre-cut
   ledger and plan, Plan cell `-`, own plan not yet written), where the header
   search would find exactly one, old, plan.
10. `start --dry-run` refuses a manifest whose row reuses the stale `S1`.
11. Seeds clean: with the stale pre-cut `S1.md`, a `KAN-1541` row is free,
    `next` classifies it, `start --dry-run` passes, and `STUDIO_STORY=KAN-1541
    studio-state check --rebuild` reports task 0 of N, while `STUDIO_STORY=S1`
    on the same tree would rebuild to 2 of N.
12. A `demo-S1` (non-ticket) row is free and plans clean.
13. R4: a planning ledger with `spec approved`, `plan approved` for S1's plan
    and only `Decisions swept S10` classifies row `S1` as `plan`, not
    `planned`; `plan approved <plan>.old` does not satisfy `<plan>`.
14. Suggestion: id `KAN-1541` taken → suggests `KAN-1541-2`; candidates that
    are another row's id are skipped.
15. Usage: a bad id or a missing `origin/HEAD` → exit 2.
16. Contract greps (the repo's skill-contract tests, `tests/omega_contracts*`
    and `tests/studio_test.sh`): autopilot, brainstorm and plan call
    `studio-overnight check-id`, and autopilot asks the slug and fetches before
    the story list.

The rest of the existing suites pass unchanged (`sh tests/run_all.sh`).

## Constraints

- A phoenix overnight run is live on the installed plugin. Work stays on branch
  `issue-56-unique-story-ids` in its worktree; nothing is installed, pulled into
  the installed checkout, or merged while `studio-overnight status` shows a live
  run.

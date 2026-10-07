# Unique story ids — a new story never inherits a dead story's ledger — Spec

Story: #56 (GitHub issue). Status: Draft (design approved by the operator in
chat, 2026-10-07; awaiting spec review). Classification: architectural (the
story-id contract is shared by the CLIs and three skills).

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
(concurrent-runs AC8/AC15) only refuses ids of live or stopped runs, so a done
run's ids look free.

## Goal

A story id, once used in a project, is not handed out again (the rule Jira keys
and database keys follow), and a reused id is refused when it is chosen or
planned, not at kickoff.

## Requirements

### R1. Id scheme for new rows

- With a ticket, the id is the ticket (`KAN-1541`). Two rows sharing a ticket
  get `KAN-1541-1`, `KAN-1541-2`.
- Without a ticket, the id is `<slug>-S<n>`: the run slug, or the spec slug when
  brainstorm writes the Stories table before any run exists (autopilot then
  copies those ids unchanged).
- Where it is stated: `shared/omega/skills/autopilot/SKILL.md` step 1 story-list
  question (the id it proposes by default), and
  `studios/game-dev/skills/brainstorm/SKILL.md` Stories table (under a manifest,
  the manifest's ids).
- No id format check is added. Existing manifests and ledgers with `S<n>` ids
  keep working unchanged; nothing is migrated.

### R2. `studio-overnight check-id`

```
studio-overnight check-id <id> [--plan <path>|-] [--ticket <ticket>|-] [--slug <slug>]
```

When `.studio/run` names a manifest that lists `<id>`, `--plan`, `--ticket` and
`--slug` default to that row's Plan and Ticket cells and the manifest's slug;
otherwise they default to `-` / none. "This story's plan" is only ever the Plan
cell or `--plan`, never a plan found by its `Story:` header (in phoenix that
search returned the old plan).

`<id>` is **taken** when either holds, reading the default branch
`origin/HEAD` → `origin/<default>` (the local ref; check-id does not fetch):

1. **Ledger.** `origin/<default>:.studio/ledger/<id>.md` exists and has a
   `plan approved <p>`, `T<n> complete` or `shipped` line, unless this story's
   plan is known and equals the last `plan approved <p>` (the story's own
   ledger, e.g. a direct-mode story already merged, on a resumed run).
2. **Plan.** A tracked `*.md` on `origin/<default>` other than this story's plan
   has a line exactly `Story: <id>`.

Plans and ledgers that exist only on the run branch are the current run's own
work and are not checked here; duplicates inside one run stay covered by
`next`'s existing "matches two plans" refusal and `mf_check`'s duplicate-row
check.

Exit 0 and print `check-id: <id> is free` when free. Exit 2 when taken, printing
to stderr one line per reason, then the suggestion:

```
studio-overnight: story id 'S1' is taken: origin/main:.studio/ledger/S1.md belongs to another story (plan docs/game-dev/plans/2026-10-02-mob-composer-no-presets.md, shipped KAN-1499-mob-composer-no-presets)
studio-overnight: story id 'S1' is taken: origin/main:docs/game-dev/plans/2026-10-02-mob-composer-no-presets.md says 'Story: S1'
studio-overnight: use 'KAN-1541' instead
```

The `(…)` detail names the ledger's last `plan approved` path and `shipped`
value when present, and is omitted when neither is. The suggestion is the first
free one of: the ticket (when set and different from `<id>`), then `<slug>-<id>`
(when a slug is known); otherwise
`pick an unused id: the ticket, or <run slug>-S<n>`.

Exit 1 for a usage error, an id not matching `^[A-Za-z0-9._-]+$`, or
`origin/HEAD` not set (message as start's preflight gives today).

### R3. Callers

- **autopilot step 1 story-list question.** Each proposed id runs
  `studio-overnight check-id <id> --ticket <t> --slug <slug> --plan -`; a taken
  id is re-asked with the message, the same way AC15 re-asks a live run's id.
- **`/game-dev:brainstorm` and `/game-dev:plan`, `<slug>/<id>` and `<id>`
  forms.** First step after entering the run worktree: `studio-overnight check-id
  <id>`. Non-zero → print its output and stop, before writing any file or
  ledger line.
- **`studio-overnight next`.** Per row, before classification, the same check
  with the row's Plan cell. Taken → print the message, exit 2 (as an ambiguous
  match does today).
- **`studio-overnight start` (and `--dry-run`) preflight**, manifest runs. Per
  row, after the existing fetch, the same check with the row's Plan cell. Taken
  → refuse to start with the message. This is the backstop; it reads the
  freshly fetched default branch.

### R4. Whole-line ledger matches in `next`

`next`'s classification (`overnight-lanes.sh` `lanes_next`) matches `spec
approved <spec>`, `plan approved <plan>` and `Decisions swept <id>` against the
text after `- <date> ` exactly, not as a substring, so `Decisions swept S1` no
longer marks `S10` swept.

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
- Renaming existing `S<n>` ledgers or manifests in any project.
- Changing phoenix.
- Folding the live/stopped-run guard (AC8, `mf_conflicts`) into check-id; it
  stays where it is.

## Test strategy

The plain-sh harness, `tests/overnight_lanes_test.sh`, reusing `lanes_fixture`
with a stale ledger and plan committed to `origin/main`:

1. `check-id S1` refuses when `origin/main` holds a shipped `S1.md` for another
   plan: exit 2, names `origin/main:.studio/ledger/S1.md`, the old plan and the
   shipped branch, suggests the row's ticket.
2. `check-id S1` refuses when only a plan on `origin/main` says `Story: S1`.
3. A plan saying `Story: KAN-1541` on the run branch only (the story's own plan,
   not yet on main) does not make `KAN-1541` taken.
4. Own ledger: `origin/main:.studio/ledger/S1.md` whose last `plan approved`
   equals the row's Plan cell → exit 0.
5. `next` exits 2 with the check-id message for a stale `S1` row whose Plan cell
   is `-`, even though a header search would find exactly one (old) plan.
6. `start --dry-run` refuses a manifest whose row reuses the stale `S1`.
7. A ticket-keyed `KAN-1541` row is free, `next` classifies it, `start --dry-run`
   passes, and `STUDIO_STORY=KAN-1541 studio-state check --rebuild` reports task
   0 of N (seeds clean).
8. `Decisions swept S1` in the planning ledger does not classify `S10` as
   planned (R4).
9. Usage errors: bad id, missing `origin/HEAD` → exit 1.

The rest of the existing suites, which use non-ticket ids, pass unchanged
(`sh tests/run_all.sh`). Skill edits pass the repo's existing skill checks.

## Constraints

- A phoenix overnight run is live on the installed plugin. Work stays on branch
  `issue-56-unique-story-ids` in its worktree; nothing is installed, pulled into
  the installed checkout, or merged while `studio-overnight status` shows a live
  run.

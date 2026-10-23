# A run that cannot push stops at once, and a hold reaches the operator — design

Status: questions answered by the operator in chat, 2026-10-23 (banner + Multica only; no @-mention).
Issues: one per gap, one PR. The PR merges only after every active overnight run has ended, then reinstall.

## Incident (phoenix bat-sonic-rings, Mac.lan, run overnight-bat-sonic-rings-20261022-224317)

- The gh OAuth token on the new machine had the scopes `gist, read:org, repo`, without `workflow`.
  Unit T19 committed a legitimate edit to `.github/workflows/web-tools-tests.yml`. GitHub refuses
  any push that touches a workflow file when the token lacks `workflow`.
- `start --dry-run` and `start --detach` both passed. Nothing checked whether the run could push.
- T19–T30 (12 units, ~8 h) each wrote `T<n> Ruling: push rejected …` and carried on. They did what
  the execute skill says: `studios/game-dev/skills/execute/SKILL.md` §8 reads "A rejected push is a
  `Ruling:` line, not a stop", and §7 step 4 reads "a rejected push … say which failed … and
  continue". 50 commits stayed on the local disk. The runner counted every unit as `progress`,
  because `snapshot()` reads stage/task from the local pointer.
- T31 wrote `Stop: push rejected …`. The story was held at 03:30 with a deadline of 11:30. The only
  signal was a Multica comment, and nobody saw it until 07:30: 4 idle hours.
- Fix on the night: `gh auth refresh -h github.com -s workflow`, then push, `say`, `resume`.

## What already exists (verified, unchanged)

- `preflight()` refuses when `gh auth status` fails (pass/fail only; the scopes are never read).
- #85 (merged in ee2d3fa, **not installed on Mac.lan**: PROGRESS 2026-10-22 says "Install is
  pending") makes a hold reach the operator through the bridge. In a manifest run the Run issue
  goes Blocked. A `studio: [notify only]` notice on the kickoff issue wakes its assigned agent, and
  that agent's reply rings the phone. The bridge shows a macOS banner (`ctx.notify` → osascript).
  An expiry notice is posted at the deadline.
  Limits #85 recorded: an unassigned kickoff wakes no one, and every bridge comment is posted with
  the operator's own token, so Multica does not notify the operator about it.
- AC18 (spec 2026-10-03): the bridge's sanitizer makes sure no comment can mention anyone. This is
  on purpose, because the bridge relays untrusted text (Stop reasons, directive text).

## Goals

1. `start`, `start --dry-run` and `start --detach` refuse a run that cannot push a workflow-file
   change, before any unit launches, and print the one command that fixes it.
2. A rejected push ends the story on the **first** occurrence, under a lane or `--one`, and no
   later unit can read it as a ruling.
3. The runner never counts work that is not on origin as progress. This is a backstop that works
   even when a skill does not follow (2).
4. A hold reaches the operator again before its deadline, and does so without relying on Multica.

## Non-goals and anti-goals

- No change to the live run, and no install, until every active overnight run has ended. Work and
  tests happen in a worktree; the PR waits to merge.
- No existing check is weakened. In particular, AC18 (no mention can form) stays as it is.
- No force push, ever. The runner does not take over the session's normal pushes.
- A failed notification never fails, delays or changes a run.

## Design

### Gap 1 — push capability in the preflight

A new function `push_check BASE…` in `studio-overnight`. `preflight()` runs it after
`DEFAULT_BRANCH` is known, so it covers `start`, `--dry-run` and `--detach` (whose foreground
preflight is the same function).

1. **Host and transport.** It reads `git remote get-url origin`.
   - An `https://<host>/…` URL is checked as below.
   - An SSH URL (`git@<host>:…`, `ssh://…`) is not checked: GitHub applies no OAuth scope to SSH
     pushes. It prints the line `push: origin is SSH — no token scope applies`.
   - Any other URL: it prints `push: origin <url> is not https or ssh — not checked`.
2. **Auth.** `gh auth status -h <host>` must succeed. This replaces today's host-less
   `gh auth status`, and the refusal text stays `gh auth status failed — log in first` (with the
   host added).
3. **Does the repo need `workflow`?** Yes when `.github/workflows` is a tree on any of the bases:
   `origin/<default branch>` in single-plan mode, plus `origin/<Target>` in manifest mode (checked
   after `mf_check`'s fetch). It is read with `git cat-file -e <ref>:.github/workflows`. When no
   base has workflows: `push: no .github/workflows — workflow scope not needed`.
4. **Is gh's token the one git pushes with?** `git config --get-urlmatch credential.helper
   https://<host>` (run in the start checkout) must name `gh auth git-credential`. If it does not,
   the scopes say nothing about the push token. That case prints a warning and does not refuse:
   `push: git does not push to <host> through gh's credential helper — cannot check the workflow scope`.
   (Builder check: refusing there could block a run that pushes fine, with a fix that fixes nothing.
   Planner's call.)
5. **Scopes.** The `Token scopes:` line of `gh auth status -h <host>`, for the active account. When it lists `workflow`:
   `push: gh token for <host> has the workflow scope`. When it is present and lacks `workflow`, the
   run is refused:
   `gh token for <host> lacks the workflow scope, and this repo has .github/workflows — a push that touches them is rejected. Fix: gh auth refresh -h <host> -s workflow`.
   When the line is missing or reads `none` (a fine-grained token, `GH_TOKEN`), the scope cannot be
   known. That prints a warning line and does not refuse:
   `push: cannot read gh token scopes for <host> — make sure the token may write workflows`.
6. **Not a real push.** `git push --dry-run` never reaches the server's scope check, so it proves
   nothing and is not used.
7. **Output.** Each passing or warning line goes to stdout, next to `env_line`. That is how
   `--dry-run` reports the check. A refusal goes through `refuse` (stderr, exit 2), the same as
   every other preflight check.

### Gap 2a — the skill: a rejected push is a stop

In `studios/game-dev/skills/execute/SKILL.md`:

- §8 `--one`: the sentence "A rejected push is a `Ruling:` line, not a stop" is replaced with a
  rule that leaves no room to reinterpret it. Under `--one` (every runner unit, lane or not), a
  push that fails for any reason is a stop the first time it happens. The unit writes
  `Stop: push rejected — <git's last error line>`, commits it as stops are committed, does not
  retry, and never writes a `Ruling:` about a push. Old `Ruling: push rejected` lines (the phoenix
  ledgers already hold T19–T30) stay as records and are not re-read as stops. A resumed story
  moves on because its next unit's own push succeeds, and the runner's `origin_check` (2b) catches
  anything still unpushed. (Builder check: re-reading old Rulings would hold a story forever after
  a resume. Planner's call.)
- §7 step 4's "a rejected push … continue" is limited to interactive (non-`--one`) use. Under
  `--one`, the §8 rule applies.
- The same rule covers every other push in the units this skill runs: §9 land repair, §10 sync
  repair and §11 gate repair. Their existing "committed, not pushed" red stops are unchanged.
- A pressure/contract test pins the wording: §8 holds the stop rule, and the old sentence is gone.

### Gap 2b — the runner: work not on origin is not progress

A new function `origin_check` in `studio-overnight` runs after each unit in `story_units` (both
modes), after the new-Stop check and before progress is counted.

- **When it applies.** When the unit ended with progress or done (`SIG` changed, or the shipped
  line). The story must have a branch: in single-plan mode `state get branch`, in manifest mode the
  row's Branch. That branch must not be the default branch: the in-place, default-branch case
  pushes nothing by design (§7 step 4). The feature checkout must have that branch checked out.
  In every other case the check is skipped. A unit that made no progress keeps today's
  retry/no-progress path.
- **The check.** `git fetch -q origin <branch>` (through `git_retry` when it is loaded), then
  `git merge-base --is-ancestor HEAD refs/remotes/origin/<branch>`. A missing remote branch fails.
- **Manifest Target.** The `origin/<Target>` half of Gap 1 runs in `lanes_start` after `mf_check`
  (which does the fetch); `preflight manifest` runs before that fetch.
- **On failure** the unit's row is `stop`, and the ending is
  `stop: push not on origin — <branch> <local short sha> vs origin <origin short sha or "none">`.
  `holdable()` gains this ending (when isolated), so the story is held: the operator can push,
  then `resume`. A failed fetch is a failure too (`… — fetch failed`), because a run that cannot
  reach origin cannot land.
- It never pushes and never changes the branch.

### Gap 3 — the hold reaches the operator, with a reminder

All on the runner side, in `hold_wait`. That makes it independent of Multica and of whether the
bridge is installed.

1. **`notify_operator TEXT`** (new, in `studio-overnight`): best-effort. It runs
   `STUDIO_OVERNIGHT_NOTIFY_CMD` when that is set. That is a test hook only (operator's ruling):
   `--detach` strips `STUDIO_*`, and it is not a config key. It is run as `sh -c "$CMD" notify "$TEXT"`,
   so the text is `$1`. Otherwise it uses `terminal-notifier` when present, else `osascript`
   `display notification` on Darwin, else nothing. It is capped at 10 s. A failure or timeout is
   one stderr line `notify failed: <why>` and nothing more; its exit status is always 0.
2. **At hold start**: one `notify_operator "<story or run> held in <run>: <why> — until <local HH:MM>"`.
3. **Reminder**: once, when 25% of `HOLD_SECS` is left (for example, 2 h before an 8 h hold
   expires): `notify_operator "<story> still held in <run> — stops at <local HH:MM> unless resumed: <why>"`
   and one new event, `hold_reminder story=<id> until=<iso> why=<why>`. That event is documented in
   `docs/game-dev/overnight-events.md`. The bridge ignores unknown events today, so an old bridge
   is safe.
4. **Bridge (Multica)**: on `hold_reminder`, it posts a reminder notice on the Run issue (manifest)
   and the notify-only kickoff notice, through #85's paths and guards (`Cli.add_notice`, the
   marker, once per event). This second wake of the kickoff agent is what reaches the phone again.
   Text: `studio: story B still held — stops at <local> (<utc>) unless resumed. Why: <why>`, and the
   kickoff form gets #85's marker and notify-only line.
5. **@-mention: not done (operator's ruling).** Every bridge comment is posted with the operator's own token, so a
   mention of the run owner would be a self-mention, which Multica is not expected to notify
   (#85's finding). A mention also needs an AC18 carve-out. The wake path that works is #85's
   agent-assigned kickoff. Recorded as a limit, with a live probe for the operator.

### Out of scope (note only)

The OMEG-118 kickoff auto-launch failed with `OMEGA_PROJECT is not a directory:
/Users/xinli/GameDev/proj/phoenix`, a path from the other laptop baked into the kickoff text. A
one-line note goes in the kickoff template docs ("resolve the project path on the target machine").
That is a follow-up issue, not this change.

## Acceptance criteria

1. Stub `gh` whose status lists `'repo'` only, and a base with `.github/workflows/x.yml`:
   `start` exits 2 with `gh auth refresh -h github.com -s workflow` on stderr, and no unit and no
   run dir are created. `--dry-run` and `--detach` refuse the same way.
2. The same stub listing `'repo', 'workflow'`: the preflight passes, and `--dry-run` stdout holds
   `push: gh token for github.com has the workflow scope`.
3. No `.github/workflows` on any base: a token without `workflow` passes, and the line says it is
   not needed.
4. An SSH origin: the scope is not read, and the SSH line is printed.
5. A scopes line that is missing: a warning line, no refusal. A credential helper that is not gh's:
   a warning line, no refusal.
6. Manifest mode: workflows only on `origin/<Target>` (not on the default branch) still requires the
   scope.
7. Skill: §8 holds the first-occurrence stop rule, and the sentence "A rejected push is a `Ruling:`
   line, not a stop" is gone. §7 step 4's "continue" is limited to interactive use.
8. Runner, lane: a unit that moves the task but whose branch head is not on origin ends with row
   `stop` and ending `stop: push not on origin — …`, and the story is held (state `held`), not
   counted as progress.
9. Runner: a unit whose pushed head is on origin is `progress`, as today. A story on the default
   branch (in place) is not checked.
10. A lane fixture whose push is rejected (a stub remote that refuses) stops at the first unit and
    holds. No second unit is launched.
11. A hold calls the notifier stub exactly once at start. With a short hold and the reminder at 25%
    left, it calls it exactly once more before expiry, and writes one `hold_reminder` event. A
    resume before the reminder means no reminder.
12. A notifier that exits 1, or hangs past 10 s, leaves one `notify failed` stderr line, and the
    hold continues and ends as it would without it.
13. Bridge: `hold_reminder` posts one Run-issue notice (manifest) and one kickoff notice with the
    marker. A re-poll repeats neither. A run with no request issue posts nothing there.
14. `docs/game-dev/overnight-events.md` lists `hold_reminder`, PROGRESS gets an entry, and the
    full gate (`tests/run_all.sh`) is green.

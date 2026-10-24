# A gate timeout under load retries once; a stale directive can be swapped while held — design

Status: drafted 2026-10-24 from the operator's write-up of the phoenix run
`overnight-bat-sonic-rings-20261022-224317` (story KAN-1723, 2026-10-22 to 10-24).
Base: `feat/overnight-throughput` (which carries #93 and the learned gate cap). One PR, opened and
not merged; it merges after #93 and the throughput branch, and only once every active overnight
run has ended.

## Incident

The run spent ~10.5 h of ~19 h held, over four stops. Three came from omega-ai tooling.

| # | stop (events.jsonl `story_state` held) | owner |
|---|---|---|
| 1 | 08:30Z push rejected: gh token without `workflow` | **#90/#91, PR #93** (not redone here) |
| 2 | 16:38Z T34 ffmpeg/ffprobe missing; venv on python 3.9 | **#95, `fix/block-and-tools`** (not redone here) |
| 3 | 00:17Z T53 `gate timed out — studio-test (T53 Verify suite) ran past 60 min` | **this spec, Part A** |
| 4 | (while held) `say` refused over `directive_chars` after two `unsay`s | **this spec, Part B** |

### Stop 3 evidence (phoenix `.studio/gate.times`, columns `epoch who secs rc wait lane class unit`)

- Recent full `studio-test` passes: 241-307 s, one at 629 s, all `main shareable`.
- `1792797354 studio-test-file 147 0 0 main:load short …T53`: just before the suite, a short check
  was refused the short lane for **load** (load ≥ 2 × 12 physical cores on this Mac) and ran in
  the main lane.
- `1792800960 studio-test 3600 124 0 main shareable …T53`: the suite then ran the full 60 min cap.
  No other phoenix gate row falls inside that hour: nothing in the project ran beside it.
- The killed log reached ~93% of the scripts (59776 of 65509 lines): slow throughout, not hung.
  The new test alone passed 7/7 in 25 s. The load was still ~10-12 an hour later, from another
  Claude session on the machine (another project, so outside phoenix's gate).

## What already exists (verified)

- **#90 (PR #93).** `start`, `--dry-run` and `--detach` refuse when a base has `.github/workflows`,
  gh is git's https credential helper, and the token lacks `workflow`. That is wider than "the
  branch touches a workflow" (any base that has the directory). **#91** makes a rejected push a
  `Stop: push rejected — <git's last error line>` on the first occurrence (git's line names the
  missing `workflow` scope), and the runner's `origin_check` stops a story whose head is not on
  origin. The ask "re-check before each push" is met by those two, so no pre-push hook is added.
- **#95 (`fix/block-and-tools`).** A declared `required_tools` list in `.studio/config.json`
  (name or path, min version, install hint), plus a venv/interpreter probe, checked by `start` and
  `--dry-run`. The declared list was chosen over scanning the plan's commands. A plan's steps
  are prose and a tool is often reached indirectly (`tools/convert_ambience.py` runs ffmpeg), so
  a scan would miss exactly this case.
- **Learned cap (throughput branch, C2).** With `STUDIO_GATE_MINUTES` set and 5+ main-lane rc-0
  rows for the same `who`, studio-gate caps a run at clamp(ceil(F × p95 / 60), 15,
  STUDIO_GATE_MINUTES) min, F = `gate_cap_factor` (default 4).

## Goals

1. A really stuck suite fails in about 15-20 min, not 60 (Part A1).
2. A gate run that hits its cap while the machine is busy runs once more, alone in the project,
   after the load drops. It stops only if that retry also times out, and the stop names both
   durations and the load readings (Part A2).
3. The operator can retire a stale directive and add a new one while the story is held, without
   waiting for a unit to deliver the retirement (Part B).

## Non-goals

- No change to the live phoenix run. Tests use stubs and scratch dirs only.
- No machine-wide (cross-project) gate. See A3.
- No new config key. The retry uses the gate's existing load rule and fits inside the existing
  `STUDIO_GATE_MINUTES` budget.

## Part A — the gate run cap

### A1. The learned cap uses the median, not p95

`gate_learned_cap` becomes clamp(ceil(F × median / 60), 15, MAXMIN), where median is the
nearest-rank 50th percentile (`ceil(N/2)`-th smallest) of the newest 50 well-formed rows. The rest
is unchanged: 5 rows minimum, F 0 = off, the 15 min floor, and STUDIO_GATE_MINUTES as the ceiling.

Why the median:
- With phoenix's 16 rows, nearest-rank p95 is the maximum, the one 629 s outlier: 4 × 629 s
  → **42 min**. The median is 273 s: 4 × 273 s → **19 min**, which matches the issue's "fails in
  ~15 min, not 60".
- One slow outlier must not stretch the cap for the next 50 runs. p95 over at most 50 rows is
  always one of the two largest.
- A2 now covers the slow-under-load case that p95 was there to protect, so a tighter cap only
  costs a retry when the machine is busy. On an idle machine 4 × median is still 4× the usual run.
- Only a tight cap leaves room for A2's retry inside the old budget (A2 rule 3). 2 × 42 min does
  not fit in 60 min; 2 × 19 min does.

Texts change from `p95` to `median`: the gate's learned-cap line, the preflight's
`gate caps:` readout (`(×4 median)`), the help text, and the comments.

### A2. A timeout under load retries once, exclusive, after the load drops

In `studio-gate`, after a **main-lane** attempt that the run cap ended (`CAPPED=1`: not a
signal, not the short slot's cap, which keeps its own demote path):

1. **Readings.** `L0` is the 1-min load when the attempt started. `L1` is the highest of the 1-
   and 5-min averages when the cap fired. The 5-min average covers the run's tail, and a
   reading taken just as the competing job stopped would otherwise miss it. The
   threshold is the load rule's `t = 2 × physical cores` (`gate_load_ok`), which is also what put
   `main:load` in gate.times. An unreadable side is `?`.
2. **Busy** means `L0 ≥ t` or `L1 ≥ t`. Not busy, or unreadable, means stop as today. The stop
   line then carries the readings, e.g.
   `gate: studio-test ran past its learned cap of 19 min (4 × median of the last 16 runs) — stopped (load 3.10→4.20, busy at 24: not retried)`.
3. **Budget.** The retry runs only when two attempts fit in the flat cap:
   `2 × CAP_SECS ≤ STUDIO_GATE_MINUTES × 60`. So the gate never runs longer than the old flat cap
   would have, and the session budget (`session_minutes`, which sets that cap to S/2) is
   untouched. An explicit `STUDIO_GATE_SECONDS` is the flat cap and the run cap at once, so such a
   run never retries. If the run is busy but there is no room, the line ends
   `(load …, busy at …: no room for a second run inside the <N> s cap)`.
4. **The retry.** The gate prints
   `gate: <who> ran past <the cap's own words> under load L0→L1 (busy at t) — running it again once, exclusive, when the load is below t (waiting up to W s)`.
   It then:
   - writes the attempt's row (rc 124, as today);
   - releases its lane;
   - waits until `gate_load_ok`, polling at the gate poll, for at most
     `W = STUDIO_GATE_MINUTES × 60 − 2 × CAP_SECS` seconds. The seam is
     `STUDIO_GATE_LOAD_WAIT_SECONDS`. If the wait runs out it prints
     `gate: load still <l> after <W> s — running it again anyway`;
   - queues again as **exclusive**: `CLS=exclusive`. It registers in `gate.wantx/`, so no new short
     check starts, and its lock's class is `exclusive`, so no short check runs beside it;
   - runs the same command under the same cap. Its row's lane is `main:retry`, which
     `gate_times_holds` still accepts, since a passing exclusive retry is a valid timing.
5. **Outcome.**
   - Pass: the command's own status, plus one line
     `gate: <who> passed on the retry (<s2> s, exclusive, load L2→L3)`.
   - The retry also hits the cap: exit 124 with one line, the line a unit quotes in its Stop:
     `gate: <who> timed out twice — <s1> s under load L0→L1, then <s2> s exclusive under load L2→L3 (busy at t) — stopped`.
   - Any other non-zero status is just that status (a red suite is a red suite).
6. A signal during the wait or the retry behaves as today: TERM/INT/HUP end the gate with
   128+n, and the EXIT trap releases. A run that a signal reached is never retried, even when
   the cap then fires on a command that ignores the signal (`not retried`), so a retry is never
   orphaned from the unit's reaper.

The execute skill's Stop line for a 124 changes from the fixed
`Stop: gate timed out — <command> ran past <n> min` to quoting the gate:
`Stop: gate timed out — <command>: <the last output line that starts with "gate: " and contains "— stopped", without "gate: ">`
(no such line: `ran past the gate cap`). The skill also says never to run it again by hand: the
gate already retried when that made sense.
So the held story's `why` carries both durations and the loads. `why` is free display text
(overnight-events.md), so no event schema changes. The doc's example list gains the new
form.

Seams for tests only: `STUDIO_GATE_LOADAVG_FILE` (the load is read from the file's first line on
each read, so a test can change it mid-run) and `STUDIO_GATE_LOAD_WAIT_SECONDS`.

### A3. Why the full suite stays `shareable` (the ask's part c)

- `shareable` admits exactly one other thing beside the suite: the project's **one short slot**.
  That is a single niced file-level check, capped at 5 min, admitted only while the load is
  below `t` (`gate_load_ok`). Above `t` a short check runs in the main lane after the suite,
  which is exactly the `main:load` row before T53.
- In the incident nothing in phoenix ran beside the suite: there is no gate.times row inside the
  hour. The load came from another Claude session working in another project. Each project's
  gate is its own lock under that project's `.studio/`, so no class setting in phoenix can
  hold that session back.
- Making the suite `exclusive` would bring back #71's problem: every short check waits behind a
  5-min suite. It would not have changed T53.
- A machine-wide heavy-run gate is a different feature. It would need a shared lock across
  projects and agreement from every studio that uses omega-ai. Not done; A2 handles the symptom,
  and the retry itself runs exclusive in its project.

### What this would have done for T53

Honestly: probably not saved it. The load an hour later was ~10-12, below phoenix's `t = 24`, so
the readings at the cap may well have read not busy, and the slowdown lasted the whole hour, so
a retry would likely have been slow too. The gain for T53 is A1: the run stops at ~19 min, not
60, and the stop line names the cap and the loads. A2 helps the case of a short spike.

One caveat: a CPU-heavy suite that hangs adds its own load, so on a machine with few cores it
can read as busy and earn one retry. That costs at most one more cap inside the old budget.

## Part B — retiring directives free their characters at once

`chan_say` counts a story's directive text against `directive_chars` from `chan_list`'s `story`
rows: `active`, `pending`, `delivered` and **`retiring`**. A directive is `retiring` once a
retire message names it (pending or delivered) and its `Directive <id> retired` line is not yet in
the ledger. While a story is held, no unit runs to record it, so the space never frees up.

Change: `chan_say` leaves `retiring` rows out of the sum. The refusal still lists every story row,
retiring ones included, with their state. The help text and the channel spec's AC5 say
"active, pending and delivered (not retiring)".

Why this is safe:
- **A retirement is irrevocable once queued.** `unsay` refuses a retire message ("unsay retires
  directives, not retires"), and a retire whose unit does not record it is requeued
  (`requeue_check`), so it stays `retiring` until it lands.
- **Delivery order is already right.** `operator-inbox.sh` claims every pending message of the
  story lowest id first and shows them in one block. A retire queued before the new `say` has a
  lower id, so the next unit gets the retirements first and then the new note, in the same block.
  Nothing new is needed for "unsay + say in one step".
- For at most one unit, the ledger can hold the retired text and the new text at once. The unit
  that receives the block records the retirement in the same ledger commit.

## Tests

- `tests/gate_times_test.sh`: the learned cap is from the median (one outlier in 16 rows leaves
  the cap at 4 × median). Floor and ceiling as before.
- `tests/gate_lanes_test.sh` (stub studio, scratch repos):
  - cap under load: a retry runs, rows `124 main <class>` then `<rc> main:retry exclusive`, and the
    "passed on the retry" line appears;
  - the retry also times out: exit 124 and the "timed out twice" line with both durations and loads;
  - cap with no load: no retry, one row, the readings in the stop line;
  - busy but no room (2 × cap > STUDIO_GATE_MINUTES × 60): no retry;
  - the load wait: the load is high, then drops (through the load file), and the retry starts after
    it drops;
  - a short check is refused `beside exclusive` while the retry holds.
  - a TERM reaches the gate and the cap then fires on a TERM-ignoring run: no retry, `not retried`.
- `tests/gate_class_test.sh`: `gate_load_peak` and the load-file seam.
- `tests/toolkit_test.sh`: the existing cap tests get `STUDIO_GATE_LOADAVG=0` (deterministic), and
  their pinned lines gain the readings.
- `tests/studio_test.sh`: the skill's Stop line pin.
- `tests/overnight_test.sh`: `say` succeeds after `unsay` frees enough characters while the story
  is held; the delivered block lists the retirements before the new directive; a `say` that would
  still be over the cap is refused and lists the retiring rows.

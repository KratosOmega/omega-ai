# Bare Godot runs go through the gate — no classifier denial can sink a unit — Spec

Story: #66 (GitHub issue). Follows #59 R4 (godot-guard). Status: design
approved in chat (operator, 2026-10-09); written spec pending review.
Classification: architectural (hook policy, runner session permissions, a
detector shared by the hook and studio-brief, and a new runner stop kind).

## What happened (phoenix, 2026-10-09)

Run `overnight-kan-1496-elemental-shifting-av-20261009-175351`, unit
`2-KAN-1496-T1` (`lanes/1/2-KAN-1496-T1.jsonl`, Bash calls 36 and 43):

    /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd

The auto-mode classifier denied it (`[Auto-Mode Bypass]`) and then denied
every Bash call for the rest of the session. T1 could not run tests or commit,
wrote a Stop line, and the run held until a human resumed it. The plan's T1
Step 5 spelled out the bare form and the agent copied it.

The verdict depends on session history, not the command: run
`kan-1557-become-one-av` T4 ran the identical bare command and was allowed; its
T7 ran `studio-gate importer -- <same command>` and was allowed.

`godot-guard.sh` (#59 R4) already recognises this binary (basename `godot*`,
case-insensitive) but allows `--script`/`--import` on purpose, since those
calls exit. The gap is policy, not detection.

The transcript records each denial as a structured event:

    {"type":"system","subtype":"permission_denied","tool_name":"Bash",
     "tool_use_id":"toolu_…","decision_reason_type":"classifier",
     "decision_reason":"[Auto-Mode Bypass]","message":"Permission for this action
     was denied by the Claude Code auto mode classifier. …"}

## Goal

A hand-built Godot script/import run is turned away by our hook (a
recoverable error naming the exact retry) before the classifier ever judges
it; the sanctioned route is pre-allowed in runner sessions; plans and briefs
only ever show the sanctioned route; and when a classifier denial does end a
unit, the report says so and names the command.

## Requirements

### R1. godot-guard verdict `c` — unwrapped script/import run

- The Godot detector (first word after assignments and the existing wrappers;
  basename `godot*` any case, or `$GODOT`/`$GODOT_PATH`/`$GODOT_BIN`) is
  unchanged.
- New verdict `c`: a Godot invocation with `-s`, `--script` or `--import` (as
  its own word; `--script=…` also counts) is refused. Precedence: `b`
  (gut_cmdln) over `c` over `a`.
- Not refused: `--version`, `--help`, `-h`, `--doctool` without `-s`/`--script`/
  `--import`; any simple command whose first word is `studio-gate`,
  `studio-test` or `studio-run` (the hook already only checks the first word,
  so the wrapped form passes with no special case — a test pins this).
- The refusal message names the retry exactly:
  `game-dev: refused an unwrapped Godot script/import run: outside the gate it skips the lock, the run cap and gate.times, and auto mode may deny it and every later Bash call. Run it as: studio-gate godot -- <segment>`
  where `<segment>` is the offending simple command's original source text
  (from its first word to its end, leading assignments/wrappers dropped,
  original quoting kept), JSON-escaped (`\` and `"`, control characters as
  `\n`/`\t`) and cut to 400 characters with `…` if longer.
- `who` is always `godot`, so gate.times keeps one bucket and R2's allow rules
  can match one fixed prefix.
- The hook still fails open: any parse problem allows the call (exit 0, no
  output).

### R2. Shared detector `godot-cmd.awk`

- The quote-aware splitter and Godot-invocation check move out of
  `godot-guard.sh` into `studios/game-dev/hooks/godot-cmd.awk`, loaded with
  `awk -f` by both the hook and `studio-brief`. One source of truth; no drift.
- Interface: input is the command text (already JSON-unescaped by the
  caller); output is one line per refused simple command,
  `<verdict>\t<segment>` (verdicts `a`, `b`, `c`), nothing when clean.
- The hook locates the file relative to its own path; if it is missing the
  hook allows (fail open) — the existing `hook_test.sh` cases still pass
  unchanged against the refactor.

### R3. Runner allow rules (least privilege)

- New `studios/game-dev/bin/overnight-allow.txt`, same format as
  `overnight-deny.txt` (one rule per line, `#` comments). Each rule becomes one
  `--allowedTools` argument in `with_launch_args`, alongside the unchanged
  `--disallowedTools` rules; `print_launch` shows them.
- Rules: `Bash(studio-test:*)`, `Bash(studio-run:*)`, and studio-gate only in
  the R1 form with a Godot binary as the wrapped command's first word:
  `Bash(studio-gate godot -- /Applications/Godot*.app/Contents/MacOS/Godot *)`,
  `Bash(studio-gate godot -- Godot *)`, `Bash(studio-gate godot -- godot *)`,
  and the `$GODOT`, `${GODOT}`, `$GODOT_PATH`, `$GODOT_BIN` forms. No
  `Bash(studio-gate:*)` and no `Bash(studio-gate godot -- *)` — either would
  let any wrapped command skip the classifier. A Godot at another path (e.g.
  `./godot`) is not pre-allowed; its wrapped call is judged by the classifier
  as today.
- Probe first (plan Task 1): on the installed Claude Code, in a scratch dir,
  confirm that `-p --permission-mode auto` keeps these rules (auto mode drops
  broad allow rules) and that a matching call is allowed by rule rather than
  sent to the classifier. Record version and evidence in this spec, as the
  deny list did. If the probe shows auto mode ignores them, R3 is dropped and
  reported; R1/R2/R4/R5 ship regardless.
- The deny list and the permission mode are not changed.

### R4. Gated forms only in briefs and plans

- `studio-brief task <n>` (and `final`, wherever it quotes plan text): a
  quoted line holding an R1 verdict-`c` command is emitted with that segment
  wrapped as `studio-gate godot -- <segment>`; everything else on the line is
  kept. Approved plan files are never edited — the rewrite is on output only.
- `studio-brief validate <plan>`: a task step holding a verdict-`c` command is
  an error naming the line number and the wrapped form; exit non-zero, like
  the existing checks. Only the plan skill calls `validate`, so a live run's
  already-approved plan is unaffected.
- Plan skill (`skills/plan/SKILL.md`): task steps that run Godot scripts or
  imports use `studio-gate godot -- …`, tests use `studio-test`; §6 notes that
  `validate` enforces it.

### R5. Classifier denial as its own stop kind

- When a unit ends without success (any non-`done` outcome: Stop line,
  noprog, timed out, stalled), the runner scans its transcript for
  `"subtype":"permission_denied"` events with
  `"decision_reason_type":"classifier"`. If any, the unit's stop is recorded as
  `permission-route — denied: <command>` (+ ` (+<n> more)` when several), the
  command taken from the Bash `tool_use` whose id matches the first event,
  cut to 200 characters. The agent's own Stop text, if any, is kept after it.
- Shown in `studio-overnight status` and `report.md` wherever stop reasons
  already appear.
- A unit that ends `done` despite a denial is not changed (no stop to explain).
- Missing or unparsable transcript: fall back to today's behaviour.

## Non-goals

- `--export*` runs (not seen failing; YAGNI).
- `sh -c '…'`, backtick and `$( )` bypasses — tracked in #63 item 3.
- Direct runs of a project's own test script — tracked in #60.
- Editing any approved plan, phoenix's repo, or its live run.

## Rollout

- Lands via PR on omega-ai; merged by this session once the gate is green.
- No reinstall while `kan-1496-elemental-shifting-av` (or any run) is live
  (check `studio-overnight status`); merge only, reinstall after.
- Before reinstall: a runner-style session (`claude-gd -p --permission-mode
  auto` with the runner's allow/deny args) in a throwaway Godot project runs a
  bare `--script` call, gets the R1 refusal, and succeeds with the suggested
  `studio-gate godot -- …` retry. Recorded in the PR.

## Acceptance criteria

1. `tests/hook_test.sh`: refuses `Godot --headless --path . --script res://x.gd`
   and `Godot --headless --import .` (and the absolute
   `/Applications/Godot_mono.app/Contents/MacOS/Godot` form); the message
   contains `studio-gate godot -- Godot --headless --path . --script res://x.gd`.
   Allows `studio-gate importer -- Godot --headless --path . --script res://x.gd`,
   `studio-gate godot -- …`, `Godot --version`, `Godot --help`. All existing
   godot_guard cases pass unchanged.
2. A message with `"` or `\` in the segment is still valid JSON (tested with
   a JSON parse in the suite's existing way, or a strict escape check).
3. `tests/overnight_test.sh`: launch argv carries one `--allowedTools` per
   allow-file rule and the deny rules unchanged; a unit transcript fixture with
   a classifier `permission_denied` event yields `permission-route — denied:
   <command>` in status and report.md; a `done` unit with one does not.
4. `tests/studio_brief_test.sh`: `task` rewrites a quoted bare `--script` line
   to the gated form and leaves other lines byte-identical; `validate` fails on
   a plan with a bare form and passes on the gated form.
5. R3 probe result and the rollout check are recorded (spec / PR body).
6. `sh tests/run_all.sh` green.

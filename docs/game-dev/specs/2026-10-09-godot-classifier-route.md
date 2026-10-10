# Bare Godot runs go through the gate — no classifier denial can sink a unit — Spec

Story: #66 (GitHub issue). Follows #59 R4 (godot-guard). Status: design
approved in chat (operator, 2026-10-09); written spec pending review.
Classification: architectural (hook policy, runner session permissions, a
detector shared by the hook and studio-brief, and a new runner stop kind).

## What happened (phoenix, 2026-10-09)

Run `overnight-kan-1496-elemental-shifting-av-20261009-175351`, unit
`2-KAN-1496-T1` (`lanes/1/2-KAN-1496-T1.jsonl`, Bash calls 36 and 43):

    /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd 2>&1 | tail -5

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
- New verdict `c`: a Godot invocation with `-s`, `--script`, `--script=…` or
  `--import` among its options is refused. Option scanning stops at a bare
  `--` (what follows is the game's own user arguments). `--check-only
  --script` is refused too (on purpose: the wrap is cheap and it still runs
  Godot).
- Not refused: `--version`, `--help`, `-h`, `--doctool` without the c options;
  any simple command whose first word is `studio-gate`, `studio-test` or
  `studio-run` — the hook only checks the first word, so the wrapped form
  passes with no special case (a test pins this).
- Redirections are not separators: `>&`, `<&`, `&>` and `&>>` (e.g. `2>&1`)
  stay inside the word, so the segment of
  `… --script res://x.gd 2>&1 | tail -5` is `… --script res://x.gd 2>&1` and
  the pipe stays outside it. This also fixes verdicts `a`/`b` segmenting.
- Message. Each verdict class present in the command (any number of
  segments) contributes its sentence, in order b, c, a; the `_use` line ends
  the message. The c sentence:
  `game-dev: refused an unwrapped Godot script/import run: outside the gate it skips the lock, the run cap and gate.times, and auto mode may deny it and every later Bash call. Run it as: studio-gate godot -- <segment>`
  where `<segment>` is the first c segment's original source text (its first
  word to its end, leading assignments/wrappers dropped, original quoting
  kept). The segment is cut first (to 400 bytes, backing off to a UTF-8
  character boundary, `…` appended when cut) and then JSON-escaped (`\`, `"`,
  control characters as `\n`/`\t`/`\uXXXX`), so the hook output is always
  valid JSON.
- Existing `tests/hook_test.sh` cases that intentionally change: `:913`
  (`-s other.gd`) and `:914` (`--import`) move from allowed to refused (c);
  `:890` (`--import . ; … -gtest=…`) stays refused and keeps its asserted
  `raw headless Godot` and `studio-test --file` text (a and c both present),
  and now also contains the c sentence. All other godot_guard cases pass
  unchanged.
- `who` is always `godot`, so gate.times keeps one bucket and R3's allow
  rules can match one fixed prefix.
- The hook still fails open: any parse problem, or a missing detector file,
  allows the call (exit 0, no output).

### R2. Shared detector `bin/godot-cmd.awk`

- The JSON extraction/unescape, quote-aware splitter, heredoc/comment logic
  and Godot-invocation check move out of `godot-guard.sh` into
  `studios/game-dev/bin/godot-cmd.awk` (in `bin/` because install links
  `bin/` entries into the target and drops `hooks/`; studio-brief resolves it
  next to itself, the hook as `$(dirname "$0")/../bin/godot-cmd.awk`, which
  holds in the plugin copy).
- Interface: `awk -v mode=<json|md> -f godot-cmd.awk`; the whole input is
  slurped and processed in `END` (heredocs need the whole string). Output: one
  line per refused simple command, `<line>\t<verdict>\t<segment>` (`line` =
  1-based input line where the segment starts), nothing when clean.
  - `mode=json`: the PreToolUse payload; the `command` field is extracted and
    JSON-unescaped in awk (no jq/python, as today).
  - `mode=md`: markdown. Commands are taken from each line inside a fenced
    code block, and from each inline backtick span on any other line; each is
    parsed as its own command text. Prose outside spans is ignored. (Final
    review I2:) fences follow CommonMark (closed only by the same character,
    at least as long; unclosed runs to the end), a fenced line ending in `\`
    joins the next into one command, and a span may wrap across the lines of
    one paragraph.
- `godot-guard.sh` becomes the thin wrapper: run the detector in json mode,
  build the R1 message, print the deny JSON.

### R3. Runner allow rules (least privilege)

- New `studios/game-dev/bin/overnight-allow.txt`, same format as
  `overnight-deny.txt` (one rule per line, `#` comments, no templates).
- `with_launch_args` adds `--allowedTools <rule>…` (the flag once, then the
  rules, as `--disallowedTools` does) before `--disallowedTools`, which stays
  last. No allow file or no rules: no `--allowedTools` flag. `print_launch`
  shows them; `lanes_dry_run` prints the allow count next to the deny count.
  `run_unit` is the only launch site.
- Rules: `Bash(studio-test:*)`, `Bash(studio-run:*)`, and studio-gate only in
  the R1 form with a Godot binary as the wrapped command's first word:
  `Bash(studio-gate godot -- /Applications/Godot.app/Contents/MacOS/Godot *)`,
  `Bash(studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot *)`,
  `Bash(studio-gate godot -- Godot *)`, `Bash(studio-gate godot -- godot *)`,
  `Bash(studio-gate godot -- $GODOT *)`, `Bash(studio-gate godot -- ${GODOT} *)`,
  `Bash(studio-gate godot -- $GODOT_PATH *)`, `Bash(studio-gate godot -- $GODOT_BIN *)`.
  The four `$GODOT*` rules were dropped after the probe (§Probe results (a):
  they never match), so the allow file ships the other six.
  No `Bash(studio-gate:*)`, no `Bash(studio-gate godot -- *)`, no wildcard
  inside the app path — each would let other binaries skip the classifier. A
  Godot at another path, or a quoted path, is not pre-allowed; its wrapped
  call is judged by the classifier as today.
- Probe first (plan Task 1), on the installed Claude Code in a scratch dir
  with no `.studio/`, `-p --permission-mode auto`:
  (a) the rules survive auto mode (it drops broad allow rules) and a matching
  call is allowed by rule, not classifier — evidence from the stream-json /
  transcript; include a `$GODOT` form;
  (b) three R1 hook refusals in a row, then an ordinary call: hook denials do
  not count toward auto mode's consecutive-denial limit
  (`decision_reason_type: asyncAgent`, "3 consecutive actions were blocked").
  Record version and evidence in this spec, as the deny list did. If (a)
  fails, R3 is dropped and reported; if (b) fails, R1's design is revisited
  before merge. R1/R2/R4/R5 ship regardless of (a).
- The deny list and the permission mode are not changed.

### R4. Gated forms only in briefs and plans

- New `studio-brief rewrite`: markdown on stdin, same text on stdout with each
  R1 verdict-c segment (found in md mode) replaced by
  `studio-gate godot -- <segment>`; every other byte unchanged. Missing
  detector: pass the text through unchanged and warn once on stderr.
  `studio-brief rewrite <file>` does the same in place (a temp file beside it,
  then `mv`; untouched when there is nothing to gate, and on a missing or
  failing detector or no temp file, with one warning; a missing file exits 2).
- Every studio-brief output that quotes plan or spec text goes through the
  same rewrite: `task <n>`, `check <k>`, `final`, and the cited spec ranges.
- `skills/execute/SKILL.md`: implementer briefs take the task text from
  ``bash "$(sdd-script task-brief)" <plan> <n>``, then
  ``studio-brief rewrite <file>`` on the file it reports
  (`wrote <file>: N lines`; task-brief prints only that line, so a pipe would
  gate nothing — final review I1). Today the task-brief output is used raw —
  the incident's denial came from such a subagent. Approved plan files are
  never edited; the rewrite is on output only.
- `studio-brief validate <plan>`: a verdict-c command in the plan is an error
  naming its line and the wrapped form; exit non-zero, like the existing
  checks. Missing detector: validate fails closed with a "reinstall" error.
  Only the plan skill calls `validate`, so a live run's approved plan is
  unaffected.
- Plan skill (`skills/plan/SKILL.md`): task steps that run Godot scripts or
  imports use `studio-gate godot -- …`, tests use `studio-test`; §6 notes that
  `validate` enforces it.

### R5. Classifier denials named in the unit ending

- Computed once in `run_unit` (the transcript `$UNIT_DIR/$UNIT_STEM.jsonl` is
  known there for every outcome) and exposed to its five callers, which
  append it to the ENDING they already build.
- When a unit's outcome is anything but `done` (stop, progress, noprog,
  `timed out`, stalled, orphaned; retry units alike) and its transcript holds
  `"subtype":"permission_denied"` events with
  `"decision_reason_type":"classifier"`, the ending gets the suffix
  ` [permission-route — denied: <command>]` (+ ` (+<n> more)` counting the
  other classifier events; `asyncAgent` events are not counted). The command
  is the input of the Bash `tool_use` whose id matches the first event (reuse
  the `open_calls` awk, `studio-overnight` ~:1030), cut to 200 bytes.
- The existing ENDING prefixes (`stop: `, `no progress on `, `timed out on `,
  `stalled on `, `gate repair …`) are kept, so `holdable()` still holds the
  story; the units.tsv outcome column is unchanged.
- Shown wherever endings appear: `studio-overnight status` and `report.md`.
- A `done` unit is unchanged. Missing or unparsable transcript: no suffix.

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
  `studio-gate godot -- …` retry, then makes an ordinary call (the session is not poisoned). Recorded in the PR.

## Acceptance criteria

1. `tests/hook_test.sh` refuses `Godot --headless --path . --script res://x.gd`,
   `Godot --headless --import .`, the absolute
   `/Applications/Godot_mono.app/Contents/MacOS/Godot … --script …` form and
   the incident's `… --script res://x.gd 2>&1 | tail -5`; the message contains
   `studio-gate godot -- Godot --headless --path . --script res://x.gd` (for
   the incident form: `… res://x.gd 2>&1`, not `… 2>`). Allows
   `studio-gate importer -- Godot --headless --path . --script res://x.gd`,
   `studio-gate godot -- …`, `Godot --version`, `Godot --help`, and
   `Godot --path . -- -s` (user args). `:913`/`:914` flip to refused; `:890`
   keeps its assertions; every other godot_guard case passes unchanged.
2. Hook output is valid JSON for a segment holding `"`, `\`, a tab and a
   multibyte character, including a 400-byte cut landing on an escape or
   inside a UTF-8 character.
3. `godot-cmd.awk` md mode (a new case group in the studio-brief suite):
   finds a bare form in a fenced block, in a bullet with an inline backtick
   span (``- [ ] **Step 3:** `Godot … --script …` ``), and in a prose line
   with two spans; reports the right line numbers; ignores prose outside spans.
4. `tests/studio_brief_test.sh`: `rewrite` wraps those forms and leaves every
   other byte identical; `task`, `check` and `final` output is rewritten;
   `validate` fails on a plan with a bare form (naming line and wrapped form)
   and passes on the gated form; missing detector → `rewrite` passes through
   with a warning, `validate` fails closed.
5. `tests/overnight_test.sh`: launch argv carries `--allowedTools` + every
   allow-file rule before `--disallowedTools`, which stays last with the deny
   rules unchanged; no allow file → no flag. A unit transcript fixture with
   two classifier `permission_denied` events and one `asyncAgent` event yields
   an ending `stop: … [permission-route — denied: <command> (+1 more)]` in
   status and report.md, and the story still holds; a `done` unit with a
   denial gets no suffix.
6. Skill text: execute SKILL runs task-brief, then `studio-brief rewrite <file>`
   on the brief file it wrote;
   plan SKILL names the gated forms (pinned by a test where the repo already
   tests skill text; otherwise checked in review).
7. R3 probe (a) and (b) results and the rollout check are recorded (spec / PR
   body).
8. `sh tests/run_all.sh` green.

## Probe results (T1, 2026-10-09)

Claude Code 2.1.296, model sonnet (claude-sonnet-5-5), `tests/probes/godot_route_probe.sh allow|hookcount`.
Stub `studio-gate`/`studio-test`/`Godot` on PATH; this checkout's plugins; `$GODOT` set. Logs (not committed):
`<scratch>/run-T1/godot-route-allow.C9JsHY` (run 1), `.../godot-route-allow.RHn0SG` (run 2, same result),
`.../godot-route-hookcount.HRsk7L`.

### (a) allow rules under auto mode: PARTIAL

- dontAsk control, both runs: calls 1, 3, 4 ran (`STUB-GATE godot -- Godot ... probe1.gd`, `STUB-GATE godot -- /Applications/Godot_mono.app/... probe3.gd`, `STUB-TEST --file tests/unit/probe4.gd`).
  Call 2 (`studio-gate godot -- $GODOT --headless --import .`) did NOT run: `permission_denied ... decision_reason_type":"mode"` ("running in don't ask mode"). So the `$GODOT` rules do not match; the near miss (call 5) was correctly denied the same way.
- auto: zero `permission_denied` events; calls 1-4 all ran (call 5 too: the classifier allowed the benign stub). No classifier denial.
- auto debug log records no rule drops and no decision source (no line naming classifier/strip/drop). The only trace is timing, `[Stall] tool_dispatch_start ... permissionDecisionMs=N`:
  - dontAsk (rules): `15, 15, 6` ms for calls 1, 3, 4.
  - auto run 1: call 1 `18`, call 2 `736`, call 3 `1076`, call 4 `4`, call 5 `716`.
  - auto run 2: call 1 `16`, call 2 `223`, call 3 `264`, call 4 `3`, call 5 `244`.
  - Calls 1 and 4 (`Godot *` form, `studio-test`) take the rule path in auto. Calls 2, 3, 5 take a classifier-latency path. Call 2 and 5 have no matching rule (`Permission suggestions for Bash: []` for call 2). Call 3 matches by rule under dontAsk but is NOT rule-fast in auto in either run.
- Verdict per the T1 table: PARTIAL (only call 2 fails the control): drop the four `$GODOT*` rules in T7.
- Caveat for T7: the timing shows the absolute-path rule (call 3, which also carries `2>&1 | tail -5`) is not fast-pathed in auto, so it is classifier-judged there (allowed here, but a real Godot call could be denied). The probe cannot tell whether the cause is the absolute path or the pipeline; the short `Godot *` / `godot *` forms are the ones proven to survive.

### (b) hook denials vs the consecutive-denial limit: PASS

- Stand-in `--settings` PreToolUse hook denied 3 `echo PROBE_REFUSE_n` calls in a row; calls 4-6 then ran (`probe4/ok: yes`, `PROBE_OK` in output).
- `RESULT hookcount: PASS`; `asyncAgent events: 0`.
- A hook denial emits NO `permission_denied` event at all (0 in the stream). The debug log records it as `Hook PreToolUse (...) returned permissionDecision: deny` and `Hook result has permissionBehavior=deny`, so it has no `decision_reason_type` and never reaches the auto-mode denial counter.

### Probe notes

- The probe takes `PROBE_OVERNIGHT` (default: this checkout's `studio-overnight`) to override the deny-rules source; run during Wave 1 with the main checkout's copy because T4's in-progress `studio-overnight` had a syntax error at line 1054.

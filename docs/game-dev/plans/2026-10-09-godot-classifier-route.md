# Bare Godot Runs Go Through the Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hand-built Godot script or import run is turned away by our own hook before the auto-mode classifier judges it. The refusal is recoverable and names the exact retry. The sanctioned route is pre-allowed in runner sessions. Plans and briefs only ever show the gated form. When a classifier denial does end a unit, the ending says so and names the command.

**Architecture:** The work falls into five lanes, each touching its own files.
- **Detector + hook (R1, R2).**
  - A new data file, `bin/godot-cmd.awk`, holds the splitter and the verdict logic now inlined in `hooks/godot-guard.sh`, plus a new verdict `c`.
  - The hook becomes a thin wrapper that builds the message.
  - `studio-brief` uses the same detector in markdown mode.
- **Allow rules (R3).** A new `bin/overnight-allow.txt` is passed as `--allowedTools` by `with_launch_args`. A live probe decides whether it ships.
- **Briefs (R4).** `studio-brief` gets a `rewrite` verb. `task`/`check`/`final` rewrite plan and spec text on output. `validate` refuses a bare form. The execute skill pipes `task-brief` through `rewrite`.
- **Endings (R5).** `run_unit` computes a `[permission-route — …]` note from the unit's transcript, reusing the `open_calls` awk. The five callers append it to the endings they build. `holdable` ignores it.
- **Skill text (R4).** The execute and plan skills.

**Tech Stack:**
- POSIX sh (macOS `/bin/sh` = bash 3.2, Linux `dash`), with awk and sed. No `local`.
- awk must work under macOS awk (the one-true-awk "20200816" line) and gawk.
  - macOS awk counts **bytes** in `length`/`substr` even under a UTF-8 locale. gawk does only in the C locale.
  - So every detector, cut and validator awk runs as `LC_ALL=C awk`.
  - Octal string escapes (`"\342\200\246"`) and `sprintf("%c", 200)` give single bytes in both.
- Suites: plain-sh `tests/*_test.sh` with `tests/assert.sh` (`run_tests`; `TESTS_ONLY="a b"` picks tests). `jq` is optional in tests: present on the dev Mac (`/usr/local/bin/jq`), maybe absent on Linux.
- Claude Code 2.1.296 for the live probe (T1) and the rollout check (T7).
- No new dependencies. No jq or python in a hook.

**Spec:** `docs/game-dev/specs/2026-10-09-godot-classifier-route.md` (R1–R5, AC1–AC8).

Story: #66 (GitHub issue). Branch `66-godot-classifier-route`. omega-ai has no Jira. **Base:** abbf15b. Line numbers are as of that commit; relocate each one with its `grep -n` anchor before editing.

## Global Constraints

Quoted from the spec. Do not change them.

**R1, verdict `c`**
- **Detector unchanged.** "first word after assignments and the existing wrappers; basename `godot*` any case, or `$GODOT`/`$GODOT_PATH`/`$GODOT_BIN`".
- **What is refused.** "a Godot invocation with `-s`, `--script`, `--script=…` or `--import` among its options is refused. Option scanning stops at a bare `--`". "`--check-only --script` is refused too".
- **What is not refused.** "`--version`, `--help`, `-h`, `--doctool` without the c options; any simple command whose first word is `studio-gate`, `studio-test` or `studio-run`".
- **Redirections.** "`>&`, `<&`, `&>` and `&>>` (e.g. `2>&1`) stay inside the word". The segment of `… --script res://x.gd 2>&1 | tail -5` is `… --script res://x.gd 2>&1`.
- **Message.**
  - "Each verdict class present in the command (any number of segments) contributes its sentence, in order b, c, a; the `_use` line ends the message."
  - The c sentence, verbatim: `game-dev: refused an unwrapped Godot script/import run: outside the gate it skips the lock, the run cap and gate.times, and auto mode may deny it and every later Bash call. Run it as: studio-gate godot -- <segment>`.
  - `<segment>` is "the first c segment's original source text (its first word to its end, leading assignments/wrappers dropped, original quoting kept)".
  - It is "cut first (to 400 bytes, backing off to a UTF-8 character boundary, `…` appended when cut) and then JSON-escaped (`\`, `"`, control characters as `\n`/`\t`/`\uXXXX`)".
- **`who`.** "`who` is always `godot`".
- **Fail open.** "any parse problem, or a missing detector file, allows the call (exit 0, no output)".

**R2, shared detector**
- **Path.** `studios/game-dev/bin/godot-cmd.awk`. The hook resolves it as `$(dirname "$0")/../bin/godot-cmd.awk`; studio-brief resolves it next to itself.
- **Interface.** "`awk -v mode=<json|md> -f godot-cmd.awk`; the whole input is slurped and processed in `END`".
- **Output.** "`<line>\t<verdict>\t<segment>` (`line` = 1-based input line where the segment starts), nothing when clean".
- **md mode.** "Commands are taken from each line inside a fenced code block, and from each inline backtick span on any other line; each is parsed as its own command text. Prose outside spans is ignored."

**R3, allow rules**
- **File.** `studios/game-dev/bin/overnight-allow.txt`, "same format as `overnight-deny.txt` (one rule per line, `#` comments, no templates)".
- **Launch argv.** "`--allowedTools <rule>…` (the flag once, then the rules …) before `--disallowedTools`, which stays last. No allow file or no rules: no `--allowedTools` flag."
- **Rules, verbatim:**
  - `Bash(studio-test:*)`
  - `Bash(studio-run:*)`
  - `Bash(studio-gate godot -- /Applications/Godot.app/Contents/MacOS/Godot *)`
  - `Bash(studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot *)`
  - `Bash(studio-gate godot -- Godot *)`
  - `Bash(studio-gate godot -- godot *)`
  - `Bash(studio-gate godot -- $GODOT *)`
  - `Bash(studio-gate godot -- ${GODOT} *)`
  - `Bash(studio-gate godot -- $GODOT_PATH *)`
  - `Bash(studio-gate godot -- $GODOT_BIN *)`
- **Never** `Bash(studio-gate:*)`, `Bash(studio-gate godot -- *)`, or a wildcard inside the app path.
- **Unchanged.** "The deny list and the permission mode are not changed."
- **Probe gates.** "If (a) fails, R3 is dropped and reported; if (b) fails, R1's design is revisited before merge. R1/R2/R4/R5 ship regardless of (a)."

**R4, briefs and plans**
- **`studio-brief rewrite`.** "markdown on stdin, same text on stdout with each R1 verdict-c segment … replaced by `studio-gate godot -- <segment>`; every other byte unchanged. Missing detector: pass the text through unchanged and warn once on stderr."
- **Coverage.** "`task <n>`, `check <k>`, `final`, and the cited spec ranges" go through the rewrite.
- **Execute skill.** "``bash "$(sdd-script task-brief)" <plan> <n> | studio-brief rewrite``". "Approved plan files are never edited".
- **`validate`.** "a verdict-c command in the plan is an error naming its line and the wrapped form; exit non-zero". "Missing detector: validate fails closed with a 'reinstall' error."

**R5, endings**
- **Suffix.** "` [permission-route — denied: <command>]` (+ ` (+<n> more)` counting the other classifier events; `asyncAgent` events are not counted)". AC5 places the count inside the bracket: `[permission-route — denied: <command> (+1 more)]`. AC5 governs (Falsify log 8).
- **Command.** The input "of the Bash `tool_use` whose id matches the first event (reuse the `open_calls` awk …), cut to 200 bytes".
- **Prefixes kept.** "The existing ENDING prefixes … are kept, so `holdable()` still holds the story; the units.tsv outcome column is unchanged."
- **No suffix.** "A `done` unit is unchanged. Missing or unparsable transcript: no suffix."

**Non-goals.** `--export*` runs. The `sh -c`, backtick and `$( )` bypasses (#63). Direct runs of a project's own test script (#60). Editing any approved plan, phoenix's repo, or its live run.

**Engineering rules**
- **Hooks.** POSIX sh with sed and awk, no jq or python. Deny with the `permissionDecision: deny` JSON. Always exit 0. Hook files stay executable (`test_bin_syntax`).
- **POSIX sh.** No `local`. Function variables carry a per-function prefix (`_ar_`, `_dn_`, `_h_`, `_rw_`, `_vg_` …).
- **Test-running rule (every task).**
  - Run every suite with cwd set to a scratch dir outside every git repo and worktree, and with `TMPDIR` set, in the same command, to a directory checked to exist.
  - Never `rm -rf` outside that scratch area.
  - A task runs only its own single suites, never `tests/run_all.sh`.
  - Use this runner. Create it once per agent at `<your scratchpad>/66-suites/run.sh`; the scratchpad is outside every repo:

    ```sh
    #!/bin/sh
    # run.sh SUITE [TEST…] — one suite, from this scratch dir, TESTS_ONLY=TEST…;
    # run.sh --args SCRIPT [ARG…] — a script with its own args (the T1 probe).
    # TMPDIR is set to an existing dir inside this scratch dir in the same exec.
    S="$(cd "$(dirname "$0")" && pwd -P)" || exit 2
    mkdir -p "$S/tmp" && [ -d "$S/tmp" ] || { echo "run.sh: no TMPDIR" >&2; exit 2; }
    if git -C "$S" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "run.sh: refused: $S is inside a git work tree" >&2; exit 2
    fi
    cd "$S" || exit 2
    if [ "${1:-}" = --args ]; then shift; _s="$1"; shift; TMPDIR="$S/tmp" exec sh "$_s" "$@"; fi
    _s="$1"; shift
    TMPDIR="$S/tmp" TESTS_ONLY="$*" exec sh "$_s"
    ```

    Run it as one plain command, e.g. `sh <scratch>/66-suites/run.sh <worktree>/tests/hook_test.sh test_godot_guard_allows`. With no test names it runs the whole suite.
- **Heavy suites.** `tests/overnight_test.sh`, `tests/overnight_lanes_test.sh` and `tests/run_all.sh` run only while this session holds the cross-session lock:
  1. Take it: `mkdir /Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock`.
  2. Write the owner file `heavy-suite.lock/owner` with Write: `owner: #66 <task> (omega-ai)`, `since: <UTC time>`, `what: <suite>`.
  3. Release it after the run: `rm -f …/heavy-suite.lock/owner`, then `rmdir …/heavy-suite.lock`.
  - If the `mkdir` fails, someone else holds it. Do not poll and never break it: hand back "blocked on heavy-suite.lock (owner: …)".
  - `TESTS_ONLY` runs of a few named tests are not heavy.
- **Live runs.**
  - No install, no reinstall, and no pull into the main checkout while any overnight run is live. Check with `studio-overnight status`, read-only, in the run's project.
  - The probe (T1, T7) never runs in, or reads from, `/Users/xinli/GameDev/proj/phoenix`.
- **Review policy.**
  - Per-task Opus review for T2, T3, T4 and T5: new seam, cross-system, or a parser.
  - T6 folds into the final review. T1 is a live check; its evidence is reviewed in the final review.
  - A standalone whole-branch Opus review always runs at the end.
  - Re-review only after a Critical, 3 or more Importants, or a production-bug fix. Never run a third pass.

## Execution shape (maximum parallelism)

| Task | Depends on | Wave | Review | Files (hunks) |
|------|------------|------|--------|---------------|
| T1 R3 live probe | — | 1 | — (live; evidence in final review) | new `tests/probes/godot_route_probe.sh`; spec: append `## Probe results` |
| T2 detector + hook | — | 1 | task (Opus) — risky | new `bin/godot-cmd.awk`; `hooks/godot-guard.sh` (whole file); `tests/hook_test.sh` (:874-984 godot tests, run_tests :1047-1048); `tests/studio_brief_test.sh` (new md group before run_tests :438); `tests/studio_test.sh` `test_bin_syntax` :111 |
| T3 allow rules | — (integrated only per T1(a)) | 1 | task (Opus) — risky | new `bin/overnight-allow.txt`; `studio-overnight` (:43, after `cmd_deny_rules` :212, `with_launch_args` :224-238, help :442-443); `overnight-lanes.sh` :421; `overnight_test.sh` (help :287, 1 test after :584, run_tests :2572); `overnight_lanes_test.sh` :762 |
| T4 permission-route note | — | 1 | task (Opus) — risky | `studio-overnight` (help :500-501, `holdable` :887-897, `open_calls` :1021-1080, `run_unit` :1278-1362, after `stall_note` :1391, `story_units` :1518-1529, `activity` :2180-2185); `overnight-lanes.sh` (`land_repair` :662-690, `gate_repair` :717-744, `sync_repair` :815-848, `final_unit` :1676-1700); new `tests/fixtures/overnight-permission-denied.jsonl`; `overnight_test.sh` (2 tests before :2364, run_tests :2557); `overnight_lanes_test.sh` (1 test after :2911, run_tests :4768) |
| T5 studio-brief rewrite/validate | T2 | 2 | task (Opus) — risky | `bin/studio-brief` (header, usage :54-56, `emit` :77, `context_part` :210, `validate` :241-271, new `rewrite` verb); `tests/studio_brief_test.sh` (4 tests + usage assertion :346-351, run_tests) |
| T6 skill text | — | 1 | final — mechanical | `skills/execute/SKILL.md` (:176-180, :355, :367-370); `skills/plan/SKILL.md` (§2 after :79, §6 :155-160); `tests/studio_test.sh` (2 tests before :811, run_tests :811-818) |
| T7 integrate, final review, gate, rollout check, PR | all | 3 | whole-branch (Opus) | `README.md` :339-340; `docs/game-dev/PROGRESS.md` |

**Waves.**
- Wave 1 runs T1, T2, T3, T4 and T6 at once. Each runs in its own worktree off `66-godot-classifier-route` at this plan's commit (`EnterWorktree`, or `git worktree add` from the story worktree; sonnet floor for implementers).
- Wave 2 runs T5 in a fresh worktree with T2's commits cherry-picked first.
- Wave 3 is T7, on the story branch.

**Shared files.** These are touched by more than one task, always in disjoint hunks.
- `studio-overnight`: T3 edits the top vars, the deny/allow readers, `with_launch_args` and the "Deny rules:" help. T4 edits the test-hook help, `holdable`, `open_calls`, `run_unit`, `story_units` and `activity`.
- `overnight-lanes.sh`: T3 edits `lanes_dry_run` :421. T4 edits the three repairs and `final_unit`.
- `tests/overnight_test.sh`: T3 adds its test name on the `test_overnight_launch_argv` run_tests line (:2572), and T4 on the `test_overnight_open_calls` line (:2557). Different lines, so the cherry-picks merge cleanly.
- `tests/overnight_lanes_test.sh`: T3 edits :762 only. T4 adds a test and a name on the :4768 run_tests line.
- `tests/studio_test.sh`: T2 edits `test_bin_syntax` :111. T6 adds tests and run_tests names at :811-818.
- `tests/studio_brief_test.sh`: T2, then T5 (sequential, Wave 2).

## Decisions

- **D1. Three detector outputs, one parser.**
  - `out=rows` (the default) is the spec's interface.
  - `out=hook` (json mode) prints line 1 = the verdict classes present, in the order b c a (e.g. `ca`), and line 2 = the first c segment, cut and JSON-escaped.
  - `out=rewrite` (md mode) prints the input with `studio-gate godot -- ` inserted at each c segment's byte column. `-v nonl=1` suppresses the final newline.
  - Why: a multi-line quoted segment cannot travel through tab-separated rows; the rewrite needs byte columns that rows do not carry; and the cut and escape must count bytes, which only `LC_ALL=C awk` does on both awks.
- **D2. `--` only stops c-option scanning.** Verdicts a and b keep scanning every word, as today.
  - If `--` stopped all scanning, `Godot --path . -- -s` would lose its `ok` word and become verdict a, but AC1 requires it allowed.
  - Known and unchanged gap: `Godot --headless --path . -- --script x` stays allowed, because `--script` anywhere sets `ok`.
- **D3. The hook message joins sentences with JSON `\n`.** That gives b, then c, then a, then `_use`, so the retry command ends at a line end. The c segment is always the first c segment.
- **D4. studio-brief rewrites on output, whole file first.**
  - `emit FILE A B` runs the detector over the whole FILE (`out=rewrite`) and then slices lines A–B. Fence state and line numbers come from the whole file; a rewrite never adds lines.
  - The old `emit` becomes `emit_raw`, used only by `context_part`. Context files can be code or notes that legitimately contain the bare form, and R4 lists only plan and spec text.
  - With the detector missing:
    - `emit` falls back to raw lines with one warning per process (a flag variable; `emit` always runs in the main shell);
    - `rewrite` passes stdin through with one warning;
    - `validate` exits 1 with `reinstall omega-ai`.
- **D5. `validate` scans the whole plan file, not only task blocks**, since a bare form in the header is copied as well. The error is `studio-brief: line <n>: unwrapped Godot script/import run; write it as: studio-gate godot -- <segment>`. It uses `line`, not `task <n>`, because a hit can sit outside any task. Only verdict c is an error (R4); a and b rows are ignored.
- **D6. Allow plumbing mirrors the deny list.**
  - `ALLOW_FILE="$SELF_DIR/overnight-allow.txt"`. `allow_rules` strips blanks and comments and expands nothing.
  - `with_launch_args` emits `--allowedTools` and its rules, then `--disallowedTools` and its rules (unchanged, last).
  - Sessions start with `exec claude-gd -p "$@"` (no `eval`), so `$GODOT` in a rule reaches Claude Code literally. `print_launch` single-quotes every word, so a copied dry-run line keeps it literal too.
  - The lanes dry run prints a separate `allow: <n> rules` line before `deny: <n> rules`, since lanes test :762 anchors the deny line.
- **D7. R5 plumbing.**
  - `run_unit` resets `UNIT_DENY_NOTE=""` first, before the halted early return, so a halt never shows the previous unit's note. It sets `UNIT_DENY_NOTE="$(deny_note "$_log")"` just before `requeue_check`.
  - Callers append `$UNIT_DENY_NOTE` to every non-done ending they build:
    - `story_units`: stop, directive, timed out, stalled, no progress;
    - `gate_repair` and `sync_repair`: stop and the three outcomes;
    - `land_repair`: its `story_write` texts (it builds no ENDING);
    - `final_unit`: a `final_note "the <label> unit ended<note>"` on a non-progress row (it builds no ENDING either).
  - The note comes from the unit that ended the story. Denials in an earlier progress unit are not carried.
  - `holdable` matches on the ending with the note stripped (`${ENDING%% \[permission-route — *}`), including the `STOP_ENDING` equality.
- **D8. `activity --denied <unit.jsonl>`** is a test-hook verb, like `--open-gate`. It prints exactly the note `run_unit` would append, so the scan, count, cut and format are tested without a full run.
- **D9. Probe and rollout run `claude` directly**, with this checkout's `--plugin-dir`s and `CLAUDE_CONFIG_DIR=~/.claude-gamedev`.
  - `claude-gd` always loads the **main** checkout's plugins, so it would test the old hook until the merge is pulled, and pulling is forbidden while a run is live.
  - T1 (b) uses a stand-in `--settings` PreToolUse hook. R1 is not built in Wave 1, and a hook denial is a hook denial whatever its text. T7's rollout check uses the real R1 hook.
- **D10. `test_bin_syntax` skips `*.awk`.** `godot-cmd.awk` is data read by `awk -f`, like the `*.txt` lists. It is neither sh nor executable.
- **D11. Deployment is pull plus reinstall, together.**
  - The hook and its detector load live from the main checkout's plugin dir.
  - `studio-brief` runs from `~/.claude-gamedev/bin`, where `godot-cmd.awk` appears only after `./install.sh game-dev`.
  - A pull without a reinstall would make `validate` fail closed. So both happen together, and only when no run is live (T7).

## Review Focus

These are the five input classes most likely to bite, each pinned by a test in its owning task.

1. **`&` as a redirection versus a separator.** `2>&1 | tail -5`, `&>/dev/null &&`, `&>>log; ls`, `<&3 & wait`, `>&2 & wait`, and a bare `&` that must still split. → `test_godot_guard_redirections` (T2).
2. **Cut-then-escape at the 400-byte edge.** A `"`, a `\`, a tab, or the first byte of `é` landing on byte 400. The output must stay valid JSON with and without jq. → `test_godot_guard_message_is_valid_json` (T2).
3. **Markdown span edges.** A double-backtick span holding a backtick, an unclosed backtick, an indented `~~~` fence, an already-gated form, `--` user args, a second command after `&&` inside a span, and backticks inside a fenced line (shell text, not a span). → `test_godot_cmd_md_span_edges` (T2), `test_brief_rewrite_wraps_only` (T5).
4. **Endings that must still hold with the note.** The `stop:` ending compared for equality with `STOP_ENDING`, and the exact pattern `gate repair made no progress`. → `test_overnight_permission_route_ending` (T4), `test_lanes_permission_route_note` (T4).
5. **Transcript scan inputs.** `asyncAgent` events, the event text quoted (escaped) inside a tool_result, a denial whose call is not in the log, an empty or event-free log, and a multibyte command over 200 bytes. → `test_overnight_denied_scan` (T4).

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `studios/game-dev/bin/godot-cmd.awk` (new, 0644) | T2 | The Godot command detector: json/md input; rows/hook/rewrite output |
| `studios/game-dev/hooks/godot-guard.sh` | T2 | Thin wrapper: detector in json mode → b/c/a message → deny JSON |
| `studios/game-dev/bin/overnight-allow.txt` (new) | T3 | The runner's allow list (data) |
| `studios/game-dev/bin/studio-overnight` | T3, T4 | `allow_rules`, launch argv; `open_calls` denied mode, `cut_utf8`, `deny_note`, `UNIT_DENY_NOTE`, `holdable`, `activity --denied` |
| `studios/game-dev/bin/overnight-lanes.sh` | T3, T4 | `allow:` dry-run count; the note in four repair/final endings |
| `studios/game-dev/bin/studio-brief` | T5 | `rewrite` verb, rewriting `emit`, `emit_raw`, `validate` Godot check |
| `studios/game-dev/skills/execute/SKILL.md`, `skills/plan/SKILL.md` | T6 | The gated forms in agent-facing text |
| `tests/probes/godot_route_probe.sh` (new) | T1 | Live probe: `allow`, `hookcount`, `rollout` |
| `tests/fixtures/overnight-permission-denied.jsonl` (new) | T4 | Transcript with 2 classifier events, 1 asyncAgent, 1 quoted fake |

---

### Task T1: R3 live probe — allow rules under auto mode; hook denials versus the denial limit (R3, AC7)

Review: none per task; the evidence goes to the final review. Wave 1. Live, no product code.

**Files:**
- Create `tests/probes/godot_route_probe.sh`.
- Modify `docs/game-dev/specs/2026-10-09-godot-classifier-route.md`: append a `## Probe results` section at the end.

**Interfaces:**
- **Produces:** `godot_route_probe.sh allow|hookcount|rollout`.
  - It needs `TMPDIR` set to an existing dir. It makes `$TMPDIR/godot-route-<mode>.XXXXXX`, and refuses if that is inside a git work tree or under `~/GameDev`.
  - It prints `probe dir: <D>`, the `claude --version` line, the evidence, and one line `RESULT <mode>: PASS|FAIL|INCONCLUSIVE — <why>`.
  - Logs stay in `<D>`: `<name>.jsonl` (stream-json), `<name>.debug`, `<name>.err`, and `stub.log`.
- **Consumes:**
  - `claude` on PATH (2.1.296).
  - `~/.claude-gamedev` for auth (`CLAUDE_CONFIG_DIR_PROBE` overrides it).
  - This checkout's `studios/game-dev` and `shared/omega` as `--plugin-dir`s.
  - `studio-overnight deny-rules --dir <D>/proj` for the runner's deny rules.
  - `rollout` only: `bin/overnight-allow.txt` from T3, the real Godot at `GODOT_APP` (default `/Applications/Godot_mono.app/Contents/MacOS/Godot`), and this checkout's `bin/` on PATH (the real `studio-gate`, the R1 hook).
- **Where it runs.** Only in its own `<D>/proj`, under the scratch TMPDIR. It never runs in or near phoenix. Cost: at most $1 per session (`--max-budget-usd 1`); `allow` runs 2 sessions, `hookcount` 1, `rollout` 1.

Evidence that proves allow-by-rule versus the classifier:

| Check | Proves | How |
|-------|--------|-----|
| `dontAsk` control: calls 1–4 run, call 5 (`studio-gate godot -- /tmp/not-godot/Godot …`) does not | The rules **match** the gated forms, including `$GODOT`, and a near miss is not matched. Under `dontAsk`, only an allow rule lets a call run. | `stub.log` lines; a `permission_denied` event for call 5 |
| `auto` session: calls 1–4 run, zero `permission_denied` events for them | Nothing denied them in auto mode | stream-json |
| `auto` debug log: no line naming a probe rule as dropped/stripped/ignored; a rule (not classifier) decision for calls 1–4 if the log records decision sources | The rules **survive** auto mode and are what allowed the calls | `grep -n -i -E 'allowedTools|allow rule|dangerous|strip|drop|classifier|auto.?mode|decision' <D>/auto.debug` |

- **PASS (a)** requires all three rows.
- **FAIL (a)** is: the control fails for every rule, a classifier denial hits any of calls 1–4 in auto, or the debug log shows the probe's rules dropped.
- **PARTIAL (a)** is: only call 2 (`$GODOT`) fails the control. Then the four `$GODOT*` rules are dropped from the allow file in T7 and the rest ships.
- **INCONCLUSIVE (a)** is: the control passes and auto ran calls 1–4 undenied, but the debug log records neither drops nor decision sources.

- [ ] **Step 1: Write the probe.** `tests/probes/godot_route_probe.sh`:

```sh
#!/bin/sh
# godot_route_probe.sh allow|hookcount|rollout — #66 live checks (plan T1, T7).
# Runs real Claude Code sessions (PROBE_MODEL, default sonnet; at most $1 each)
# in a scratch dir made under $TMPDIR — never in a project:
#   allow      R3 (a): the allow rules match (a dontAsk control) and survive
#              auto mode (calls 1-4 run, no classifier denial, no rule dropped).
#   hookcount  R3 (b): three hook refusals in a row, then ordinary calls; hook
#              denials must not trip auto mode's consecutive-denial limit
#              (decision_reason_type asyncAgent).
#   rollout    the spec's rollout check: in a throwaway Godot project a
#              runner-style session (this checkout's plugins, allow + deny
#              rules, OMEGA_AUTOPILOT=1) is refused a bare --script run, runs
#              the retry the refusal names, then makes an ordinary call.
# Plugins are this checkout's (--plugin-dir); claude-gd would load the main
# checkout's. Prints the evidence and one RESULT line.
set -u
R="$(cd "$(dirname "$0")/../.." && pwd -P)"
MODE="${1:-}"; M="${PROBE_MODEL:-sonnet}"
case "$MODE" in allow|hookcount|rollout) ;; *) echo "usage: $0 allow|hookcount|rollout" >&2; exit 2 ;; esac
[ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] || { echo "set TMPDIR to an existing scratch dir" >&2; exit 2; }
D="$(mktemp -d "$TMPDIR/godot-route-$MODE.XXXXXX")" && D="$(cd "$D" && pwd -P)" || exit 2
if git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo "refused: $D is inside a git work tree" >&2; exit 2; fi
case "$D" in "$HOME"/GameDev/*) echo "refused: $D is under ~/GameDev" >&2; exit 2 ;; esac
mkdir -p "$D/bin" "$D/proj"; LOG="$D/stub.log"; : > "$LOG"
echo "probe dir: $D"; claude --version

# The spec's R3 rules (bin/overnight-allow.txt's ten lines); rollout reads the file.
RULES='Bash(studio-test:*)
Bash(studio-run:*)
Bash(studio-gate godot -- /Applications/Godot.app/Contents/MacOS/Godot *)
Bash(studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot *)
Bash(studio-gate godot -- Godot *)
Bash(studio-gate godot -- godot *)
Bash(studio-gate godot -- $GODOT *)
Bash(studio-gate godot -- ${GODOT} *)
Bash(studio-gate godot -- $GODOT_PATH *)
Bash(studio-gate godot -- $GODOT_BIN *)'
if [ "$MODE" = rollout ]; then
  RULES="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$R/studios/game-dev/bin/overnight-allow.txt" | grep -v '^#' | grep .)" \
    || { echo "no allow rules in $R/studios/game-dev/bin/overnight-allow.txt" >&2; exit 2; }
fi
DENY="$(sh "$R/studios/game-dev/bin/studio-overnight" deny-rules --dir "$D/proj" 2>/dev/null)"
# The runner's rule args, in its order: --allowedTools … then --disallowedTools … last.
set -- --allowedTools
while IFS= read -r _r; do [ -z "$_r" ] || set -- "$@" "$_r"; done <<EOF
$RULES
EOF
set -- "$@" --disallowedTools
while IFS= read -r _r; do [ -z "$_r" ] || set -- "$@" "$_r"; done <<EOF
$DENY
EOF

PROBE_PATH="$PATH"; PROBE_GODOT=""; PROBE_AUTOPILOT=""
# session NAME PERMISSION_MODE PROMPT ARGS… — one headless session in $D/proj.
session() {
  _n="$1"; _pm="$2"; _p="$3"; shift 3
  ( cd "$D/proj" && exec env PATH="$PROBE_PATH" GODOT="$PROBE_GODOT" OMEGA_AUTOPILOT="$PROBE_AUTOPILOT" \
      CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR_PROBE:-$HOME/.claude-gamedev}" \
      claude --plugin-dir "$R/studios/game-dev" --plugin-dir "$R/shared/omega" -p "$_p" --model "$M" \
      --output-format stream-json --verbose --permission-mode "$_pm" --permission-prompts none \
      --max-budget-usd 1 --debug-file "$D/$_n.debug" "$@" ) > "$D/$_n.jsonl" 2> "$D/$_n.err" < /dev/null
}
# denials FILE TYPE — FILE's permission_denied events of decision_reason_type TYPE.
denials() { grep '"subtype":"permission_denied"' "$1" | grep -c "\"decision_reason_type\":\"$2\""; }
# stub NAME TAG — an executable $D/bin/NAME that logs "TAG <args>" and prints TAG-OK.
stub() { printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >> "%s"; echo %s-OK\n' "$2" "$LOG" "$2" > "$D/bin/$1"; chmod +x "$D/bin/$1"; }
ORDER='Make each Bash call below exactly as written, one per Bash call, in order. If a call is refused or fails, note it in one line and go on to the next. Do not change, combine or explain the commands. When done, reply DONE.'

case "$MODE" in
allow)
  stub studio-gate STUB-GATE; stub studio-test STUB-TEST; stub Godot STUB-GODOT
  PROBE_PATH="$D/bin:$PATH"; PROBE_GODOT="$D/bin/Godot"
  P="$ORDER
1. studio-gate godot -- Godot --headless --path . --script res://probe1.gd
2. studio-gate godot -- \$GODOT --headless --import .
3. studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://probe3.gd 2>&1 | tail -5
4. studio-test --file tests/unit/probe4.gd
5. studio-gate godot -- /tmp/not-godot/Godot --version"
  _bad=""
  for pm in dontAsk auto; do
    : > "$LOG"; session "$pm" "$pm" "$P" "$@"
    echo "== $pm: stub log"; cat "$LOG"
    echo "== $pm: permission_denied events"; grep '"subtype":"permission_denied"' "$D/$pm.jsonl"
    for w in probe1.gd ' --import \.' probe3.gd probe4.gd; do
      grep -q -- "$w" "$LOG" || _bad="$_bad $pm:missing($w)"
    done
    [ "$pm" != dontAsk ] || ! grep -q not-godot "$LOG" || _bad="$_bad dontAsk:near-miss-ran"
  done
  [ "$(denials "$D/auto.jsonl" classifier)" -eq 0 ] || _bad="$_bad auto:classifier-denials"
  echo "== auto: debug log (rule handling and decisions)"
  grep -n -i -E 'allowedTools|allow rule|dangerous|strip|drop|classifier|auto.?mode|decision' "$D/auto.debug" | head -n 80
  if [ -n "$_bad" ]; then echo "RESULT allow: FAIL —$_bad"
  else echo "RESULT allow: MATCHED — judge PASS or INCONCLUSIVE from the debug lines above (plan T1 table)"; fi ;;
hookcount)
  printf '%s\n' '#!/bin/sh' \
    'case "$(cat)" in *PROBE_REFUSE*) printf "%s\n" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"probe: refused by a hook; go on to the next call\"}}" ;; esac' \
    'exit 0' > "$D/refuse.sh"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh %s/refuse.sh"}]}]}}\n' "$D" > "$D/settings.json"
  P="$ORDER
1. echo PROBE_REFUSE_1
2. echo PROBE_REFUSE_2
3. echo PROBE_REFUSE_3
4. git init -q probe4
5. touch probe4/ok
6. echo PROBE_OK"
  session hook auto "$P" --settings "$D/settings.json" "$@"
  _r="$(grep -o 'probe: refused by a hook' "$D/hook.jsonl" | grep -c .)"; _a="$(denials "$D/hook.jsonl" asyncAgent)"
  echo "hook refusals seen: $_r; asyncAgent events: $_a; probe4/ok: $([ -f "$D/proj/probe4/ok" ] && echo yes || echo no)"
  grep '"subtype":"permission_denied"' "$D/hook.jsonl"
  if [ "$_a" -gt 0 ]; then echo "RESULT hookcount: FAIL — hook denials tripped the consecutive-denial limit"
  elif [ "$_r" -ge 3 ] && [ -f "$D/proj/probe4/ok" ] && grep -q PROBE_OK "$D/hook.jsonl"; then echo "RESULT hookcount: PASS"
  else echo "RESULT hookcount: INCONCLUSIVE — the model skipped calls; rerun"; fi ;;
rollout)
  G="${GODOT_APP:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
  [ -x "$G" ] || { echo "no Godot at $G" >&2; exit 2; }
  printf 'config_version=5\n\n[application]\n\nconfig/name="route-probe"\n' > "$D/proj/project.godot"
  mkdir -p "$D/proj/tools"
  printf 'extends SceneTree\n\nfunc _init() -> void:\n\tprint("PROBE_HELLO")\n\tquit()\n' > "$D/proj/tools/hello.gd"
  PROBE_PATH="$R/studios/game-dev/bin:$PATH"; PROBE_AUTOPILOT=1
  W="studio-gate godot -- $G --headless --path . --script res://tools/hello.gd 2>&1"
  P="Run this Bash command exactly as written: $G --headless --path . --script res://tools/hello.gd 2>&1 | tail -5
If a hook refuses it, run the exact command the refusal names, once. Then run: git init -q . && git status --short
Reply DONE."
  session rollout auto "$P" "$@"
  _ok=1
  grep -q 'refused an unwrapped Godot script/import run' "$D/rollout.jsonl" || { _ok=0; echo "no R1 refusal"; }
  grep -qF "\"command\":\"$W" "$D/rollout.jsonl" || { _ok=0; echo "the retry was not run as named: $W"; }
  grep -q PROBE_HELLO "$D/rollout.jsonl" || { _ok=0; echo "the retry did not run the script"; }
  [ -d "$D/proj/.git" ] || { _ok=0; echo "the ordinary call after the retry did not run"; }
  _c="$(denials "$D/rollout.jsonl" classifier)"; _a="$(denials "$D/rollout.jsonl" asyncAgent)"
  echo "classifier denials: $_c; asyncAgent: $_a"
  [ "$_c" -eq 0 ] && [ "$_a" -eq 0 ] || _ok=0
  if [ "$_ok" = 1 ]; then echo "RESULT rollout: PASS"; else echo "RESULT rollout: FAIL"; fi ;;
esac
```

- [ ] **Step 2: Syntax check.** Run `sh -n <worktree>/tests/probes/godot_route_probe.sh`. Expected: no output, exit 0.
- [ ] **Step 3: Run (a).** Run `sh <scratch>/66-suites/run.sh --args <worktree>/tests/probes/godot_route_probe.sh allow`.
  - Read the dontAsk lines, the auto lines and the debug lines against the table above.
  - Decide PASS, PARTIAL, FAIL or INCONCLUSIVE.
  - If the debug log shows how a decision was made, quote the exact line format in the results.
- [ ] **Step 4: Run (b).** Run `sh <scratch>/66-suites/run.sh --args <worktree>/tests/probes/godot_route_probe.sh hookcount`.
  - Expected: `RESULT hookcount: PASS`.
  - On INCONCLUSIVE, rerun once.
  - Note which `decision_reason_type`, if any, Claude Code gives a hook denial.
- [ ] **Step 5: Record.** Append to the spec:
  - `## Probe results (T1, <date>)`;
  - the Claude Code version;
  - for (a) and (b), the RESULT and the 3–8 evidence lines that decide it (stub log lines, event counts, debug lines);
  - the probe dir path (logs not committed).
- [ ] **Step 6: Commit.** Run `git add tests/probes/godot_route_probe.sh docs/game-dev/specs/2026-10-09-godot-classifier-route.md`, then `git commit -m "test(#66): R3 probe — allow rules under auto mode, hook denials vs the denial limit"`. Hand back (a)'s and (b)'s RESULTs in the first line.

Acceptance: AC7 (probe part). T7 acts on the results: (a) FAIL drops T3; PARTIAL trims the `$GODOT*` rules; INCONCLUSIVE ships T3, flagged in the PR; (b) FAIL stops before merge for an operator ruling on R1.

---

### Task T2: Shared detector `godot-cmd.awk`, verdict `c`, thin godot-guard hook (R1, R2, AC1–AC3)

Review: task (Opus). Wave 1. Risky: new seam (a detector shared by a hook and studio-brief), and a parser.

**Files:**
- Create `studios/game-dev/bin/godot-cmd.awk` (mode 0644, not executable).
- Replace `studios/game-dev/hooks/godot-guard.sh` whole (keep it executable). `hooks/hooks.json` is unchanged.
- Modify `tests/hook_test.sh`: the godot tests at :874-984, and `run_tests` at :1047-1048.
- Modify `tests/studio_brief_test.sh`: a new md case group before `run_tests` (:438), and `run_tests`.
- Modify `tests/studio_test.sh` :111: `case "$(basename "$f")" in .gitkeep|*.txt|*.awk) continue ;; esac`.

**Interfaces:**
- **Produces** `godot-cmd.awk`, run as `LC_ALL=C awk -v mode=json|md [-v out=rows|hook|rewrite] [-v nonl=1] -f godot-cmd.awk [FILE]`.
  - `out=rows`: `<line>\t<verdict>\t<segment>`; a newline inside a segment prints as a space.
  - `out=hook`: 2 lines (D1).
  - `out=rewrite`: the md text with `studio-gate godot -- ` inserted at each c segment.
  - Silent and exit 0 when clean.
- **Consumes** the PreToolUse JSON (`tool_input.command`) or markdown.
- **The hook** prints one deny JSON line or nothing, and always exits 0.
- **T5 consumes** `mode=md` with `out=rows` (for `validate`) and `out=rewrite` (for `emit` and `rewrite`).

Anchors: `grep -n '^godot_guard()\|^test_godot_guard\|^run_tests\|godot_guard_never' tests/hook_test.sh` and `grep -n 'gitkeep' tests/studio_test.sh`.

- [ ] **Step 1: Failing hook tests.** In `tests/hook_test.sh`, after `godot_guard()` (:875-879), add the helpers. Then change `test_godot_guard_allows` and add four tests.

```sh
# gg_c JSON_CMD SEGMENT — JSON_CMD is refused (c); its retry is SEGMENT and
# ends the sentence (a JSON \n follows). SEGMENT is a grep BRE.
gg_c() {
  godot_guard "{\"command\":\"$1\"}"
  assert_denied "refused (c): $1"
  assert_contains "$TMP/ap.out" 'refused an unwrapped Godot script/import run' "the c sentence ($1)"
  assert_contains "$TMP/ap.out" "Run it as: studio-gate godot -- $2\\\\n" "the retry is the segment ($1)"
}
# json_ok FILE — FILE's one line is valid deny JSON: jq when present; else the
# exact deny shape whose reason is a well-formed JSON string, in valid UTF-8.
json_ok() {
  if command -v jq >/dev/null 2>&1; then jq -e .hookSpecificOutput.permissionDecisionReason "$1" >/dev/null 2>&1; return; fi
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1 || return 1
  LC_ALL=C awk 'NR == 1 {
      p = "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\""
      if (index($0, p) != 1 || substr($0, length($0) - 2) != "\"}}") exit 1
      r = substr($0, length(p) + 1, length($0) - length(p) - 3)
      ok = (r ~ /^([^"\\\001-\037]|\\["\\\/bfnrt]|\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])*$/) }
    END { exit !(NR == 1 && ok) }' "$1"
}
# #66 R1 / AC1: an unwrapped script/import run is refused (c), naming the exact retry.
test_godot_guard_refuses_script_import() {
  gg_c 'Godot --headless --path . --script res://x.gd' 'Godot --headless --path . --script res://x.gd'
  gg_c 'Godot --headless --import .' 'Godot --headless --import .'
  gg_c '/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://x.gd' \
       '/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://x.gd'
  gg_c '/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://x.gd 2>&1 | tail -5' \
       '/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://x.gd 2>&1'
  assert_not_contains "$TMP/ap.out" 'tail -5' "the incident's pipe stays outside the segment"
  gg_c 'Godot --headless --path . -s other.gd' 'Godot --headless --path . -s other.gd'
  gg_c 'Godot --headless --path . --import' 'Godot --headless --path . --import'
  gg_c 'Godot --check-only --script res://x.gd' 'Godot --check-only --script res://x.gd'
  gg_c '$GODOT --headless --path . --script res://x.gd' '$GODOT --headless --path . --script res://x.gd'
  gg_c 'cd x && A=1 timeout 60 godot4 --headless --script=res://y.gd' 'godot4 --headless --script=res://y.gd'
  # The :890 command: c first, then a, then the use line.
  godot_guard '{"command":"Godot --headless --import . ; Godot --headless --path . -gtest=res://a.gd"}'
  assert_contains "$TMP/ap.out" 'Run it as: studio-gate godot -- Godot --headless --import .\\ngame-dev: refused a raw headless Godot command' "c, then a"
  assert_contains "$TMP/ap.out" 'never exits\.\\nRun a test file with studio-test --file' "then the use line"
  # b before c.
  godot_guard '{"command":"Godot -s addons/gut/gut_cmdln.gd; Godot --import ."}'
  assert_contains "$TMP/ap.out" 'runs the whole suite\.\\ngame-dev: refused an unwrapped Godot script/import run' "b, then c"
  # Two c segments: one sentence, naming the first.
  godot_guard '{"command":"Godot --headless --import . && Godot --headless -s a.gd"}'
  assert_eq 1 "$(grep -o 'Run it as:' "$TMP/ap.out" | grep -c .)" "one c sentence for two c segments"
  assert_contains "$TMP/ap.out" 'studio-gate godot -- Godot --headless --import .\\n' "naming the first"
}
# #66 R1 + Review Focus 1: >& <& &> &>> are redirections; a plain & still separates.
test_godot_guard_redirections() {
  gg_c 'Godot --headless --path . --script res://x.gd 2>&1 | tail -5' 'Godot --headless --path . --script res://x.gd 2>&1'
  gg_c 'Godot --headless --script=res://y.gd &>/dev/null && echo ok' 'Godot --headless --script=res://y.gd &>/dev/null'
  gg_c 'Godot --headless --script res://y.gd &>>log.txt; ls' 'Godot --headless --script res://y.gd &>>log.txt'
  gg_c 'Godot --headless --script res://y.gd <&3 & wait' 'Godot --headless --script res://y.gd <&3'
  gg_c 'cd x && A=1 timeout 60 Godot --script res://y.gd >&2 & wait' 'Godot --script res://y.gd >&2'
  godot_guard '{"command":"Godot --headless --path . & Godot --version"}'
  assert_denied "a plain & still separates: the first command is a raw headless boot"
  godot_guard '{"command":"ls & Godot --version"}'
  assert_allowed "a plain & still separates: Godot --version alone is allowed"
}
# #66 AC2 + Review Focus 2: cut first (400 bytes, UTF-8 boundary), then escape.
test_godot_guard_message_is_valid_json() {
  godot_guard '{"command":"Godot --headless --script \"res://a b.gd\" q\\\\x\ty é"}'
  assert_denied "quote, backslash, tab and é in the segment"
  TESTS_RUN=$((TESTS_RUN + 1))
  if json_ok "$TMP/ap.out"; then _pass "valid JSON (no cut)"; else _fail "valid JSON (no cut)"; fi
  # "Godot --script res://x.gd " is 26 bytes; after the 373-byte pad the next
  # byte is the segment's 400th: a quote, a backslash, a tab, the lead byte of é.
  _pad="$(awk 'BEGIN { while (length(s) < 373) s = s "a"; printf "%s", s }')"
  for t in '\"zz' '\\zz' '\tzz' 'éz'; do
    godot_guard "{\"command\":\"Godot --script res://x.gd $_pad$t\"}"
    assert_denied "cut at byte 400 on $t"
    TESTS_RUN=$((TESTS_RUN + 1))
    if json_ok "$TMP/ap.out"; then _pass "valid JSON (cut on $t)"; else _fail "valid JSON (cut on $t)"; fi
    assert_contains "$TMP/ap.out" '…\\nRun a test file' "the cut ends in … ($t)"
  done
}
# #66 R1: no detector file → allow (fail open).
test_godot_guard_missing_detector_allows() {
  mkdir -p "$TMP/nodet/hooks"; cp "$GODOT_GUARD" "$TMP/nodet/hooks/godot-guard.sh"
  ptu_in Bash '{"command":"Godot --headless --import ."}' > "$TMP/gg.in"; _gst=0
  sh "$TMP/nodet/hooks/godot-guard.sh" < "$TMP/gg.in" > "$TMP/ap.out" 2> "$TMP/ap.err" || _gst=$?
  assert_eq 0 "$_gst" "exit 0 with no detector"
  assert_allowed "no detector: the call is allowed"
  assert_eq "" "$(cat "$TMP/ap.err")" "and nothing on stderr"
}
```

`test_godot_guard_allows`: drop its first two entries (`-s other.gd` and `--import`, the old :913/:914, now in the c test). Its list becomes:

```sh
  for c in \
    'Godot --version' \
    'Godot --help' \
    'Godot -h' \
    'Godot --path . -- -s' \
    'Godot --doctool docs' \
    'Godot --headless --path . --export-release Mac out.dmg' \
    'Godot --headless --path . --quit-after 5' \
    'Godot -e --path .' \
    'studio-test --file tests/unit/x.gd' \
    'studio-gate importer -- Godot --headless --path . --script res://x.gd' \
    'studio-gate godot -- Godot --headless --path . --script res://x.gd 2>&1 | tail -5' \
    'studio-gate godot -- $GODOT --headless --import .' \
    'echo \"Godot --headless --path .\"' \
    'echo \"a; Godot --headless --path .\"' \
    'grep -r godot --path' \
    'ls -la'; do
```

Add the four new names to the godot `run_tests` line (:1048). All other godot_guard tests stay unchanged; `:890` keeps its `studio-test --file` and `raw headless Godot` assertions.

- [ ] **Step 2: Failing md tests.** In `tests/studio_brief_test.sh`, before `run_tests`:

````sh
DET="$REPO_ROOT/studios/game-dev/bin/godot-cmd.awk"
# godot_md FILE [OUT] — the detector's md output (rows, or OUT) for FILE.
godot_md() { LC_ALL=C awk -v mode=md ${2:+-v out=$2} -f "$DET" "$1"; }
# #66 AC3: a fenced block, a bullet's inline span, a prose line with two spans; prose ignored.
test_godot_cmd_md_finds_bare_forms() {
  cat > "$TMP/ac3.md" <<'MD'
# Plan
Prose Godot --headless --script res://p.gd is not a command.
```sh
Godot --headless --path . --script res://tools/importer.gd 2>&1 | tail -5
studio-gate godot -- Godot --headless --import .
```
- [ ] **Step 3:** `Godot --headless --path . --script res://a.gd` then check.
Run `Godot --headless --import .` and then `Godot --headless --path . --script res://b.gd`; done.
MD
  printf '%s\t%s\t%s\n' \
    4 c 'Godot --headless --path . --script res://tools/importer.gd 2>&1' \
    7 c 'Godot --headless --path . --script res://a.gd' \
    8 c 'Godot --headless --import .' \
    8 c 'Godot --headless --path . --script res://b.gd' > "$TMP/ac3.want"
  godot_md "$TMP/ac3.md" > "$TMP/ac3.got"; st=$?
  assert_eq 0 "$st" "md mode exits 0"
  assert_eq "$(cat "$TMP/ac3.want")" "$(cat "$TMP/ac3.got")" "rows: line, verdict c, segment; prose and the gated line ignored"
}
# #66 Review Focus 3: span and fence edges, rows and rewrite.
test_godot_cmd_md_span_edges() {
  cat > "$TMP/edge.md" <<'MD'
Double ``Godot --script `x` y`` here.
Unclosed `Godot --script z
   ~~~
   godot --import
   ~~~
Already `studio-gate godot -- Godot --script res://c.gd` here.
`Godot --version` and `Godot --path . -- -s` and `cd x && Godot -s y.gd`
```
`Godot --script in-a-fence-is-shell-text.gd`
```
MD
  printf '%s\t%s\t%s\n' 1 c 'Godot --script `x` y' 4 c 'godot --import' 7 c 'Godot -s y.gd' > "$TMP/edge.want"
  godot_md "$TMP/edge.md" > "$TMP/edge.got"
  assert_eq "$(cat "$TMP/edge.want")" "$(cat "$TMP/edge.got")" "double-backtick span, indented ~~~ fence, && in a span; unclosed, gated, --version, -- args and fenced backticks ignored"
  cat > "$TMP/edge.rw.want" <<'MD'
Double ``studio-gate godot -- Godot --script `x` y`` here.
Unclosed `Godot --script z
   ~~~
   studio-gate godot -- godot --import
   ~~~
Already `studio-gate godot -- Godot --script res://c.gd` here.
`Godot --version` and `Godot --path . -- -s` and `cd x && studio-gate godot -- Godot -s y.gd`
```
`Godot --script in-a-fence-is-shell-text.gd`
```
MD
  godot_md "$TMP/edge.md" rewrite > "$TMP/edge.rw.got"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/edge.rw.want" "$TMP/edge.rw.got"; then _pass "rewrite inserts the gate at each c segment, every other byte the same"
  else _fail "rewrite inserts the gate at each c segment ($(diff "$TMP/edge.rw.want" "$TMP/edge.rw.got" | head -n 4))"; fi
  printf 'x `Godot --script a`' > "$TMP/nonl.md"
  LC_ALL=C awk -v mode=md -v out=rewrite -v nonl=1 -f "$DET" "$TMP/nonl.md" > "$TMP/nonl.out"
  assert_eq 'x `studio-gate godot -- Godot --script a`' "$(cat "$TMP/nonl.out")" "nonl: rewritten"
  assert_eq "$(printf 'x `studio-gate godot -- Godot --script a`' | wc -c | tr -d ' ')" "$(wc -c < "$TMP/nonl.out" | tr -d ' ')" "nonl=1: no newline added"
}
````

Add both names to `run_tests`.

- [ ] **Step 3: Run; expect FAIL.**
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/hook_test.sh test_godot_guard_refuses_script_import test_godot_guard_redirections test_godot_guard_message_is_valid_json test_godot_guard_allows`. Expected: FAIL. The old hook allows `-s`/`--import`, and it has no c sentence.
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_brief_test.sh test_godot_cmd_md_finds_bare_forms test_godot_cmd_md_span_edges`. Expected: FAIL (no detector file).
- [ ] **Step 4: Write `studios/game-dev/bin/godot-cmd.awk`.** This is the full file; it was prototyped and passes every case in Steps 1–2.

```awk
# godot-cmd.awk — the game-dev studio's Godot command detector, shared by
# hooks/godot-guard.sh (#59 R4, #66 R1) and studio-brief (#66 R4). Data, not
# a command: run it as
#   LC_ALL=C awk -v mode=json|md [-v out=rows|hook|rewrite] [-v nonl=1] -f godot-cmd.awk [FILE]
# LC_ALL=C makes length/substr count bytes under every awk (macOS awk always
# does; gawk does only in the C locale).
#
# Input, slurped and processed in END (a heredoc needs the whole command):
#   mode=json  a PreToolUse payload; its first "command" string is extracted
#              and JSON-unescaped here (no jq, no python).
#   mode=md    markdown; each line inside a ``` or ~~~ fence, and each inline
#              backtick span on any other line, is one command text. Prose
#              outside spans is never read.
# Each command text is split quote-aware at ; & && | || ( ) and newlines;
# >& <& &> &>> (as in 2>&1) are redirections, not separators. A simple
# command is a Godot invocation when its first word (quotes removed; after
# NAME=value assignments, the keywords ! { if then else elif do while until,
# and the wrappers env, exec, command, time, nohup, nice, timeout/gtimeout
# <n>) has a basename starting "godot" in any case, or is $GODOT, $GODOT_PATH
# or $GODOT_BIN (braces allowed). Its verdict:
#   b  a word names gut_cmdln (a hand-built GUT run);
#   c  else -s, --script, --script=… or --import before a bare -- (an
#      unwrapped script/import run; what follows -- is the game's own args);
#   a  else --headless, --path or --path=… and none of -s, --script,
#      --import, -e, --editor, --export*, --version, --doctool, --quit,
#      --quit-after, --help, -h anywhere (a headless boot never exits).
# A refused simple command's segment is its source text from the Godot word
# to its last word (assignments and wrappers dropped, quoting kept).
#
# Output:
#   out=rows (default)  <line>\t<verdict>\t<segment> per refused simple
#                       command, in input order (line: 1-based, where the
#                       segment starts; a newline inside a segment prints as a
#                       space). Nothing when clean.
#   out=hook (json)     line 1: the verdicts present, in the order b c a
#                       (e.g. "ca"); line 2: the first c segment cut to 400
#                       bytes on a UTF-8 boundary ("…" appended when cut),
#                       then JSON-escaped (empty when there is no c).
#                       Nothing when clean.
#   out=rewrite (md)    the input with "studio-gate godot -- " inserted before
#                       each c segment; every other byte unchanged. nonl=1:
#                       the input had no final newline, so none is printed.
BEGIN {
  if (out == "") out = "rows"
  for (i = 128; i < 192; i++) CONT[sprintf("%c", i)] = 1
  for (i = 1; i < 32; i++) CTL[sprintf("%c", i)] = sprintf("\\u%04x", i)
  CTL["\n"] = "\\n"; CTL["\t"] = "\\t"; CTL["\r"] = "\\r"
  NL = 0; NS = 0
}
{ L[++NL] = $0 }
END {
  if (mode == "json") json_main()
  else if (mode == "md") md_main()
}

function unesc(s,   o, c, i, n) {
  o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && i < n) {
      i++; c = substr(s, i, 1)
      if (c == "n" || c == "r") c = "\n"; else if (c == "t") c = "\t"
    }
    o = o c
  }
  return o
}
function json_main(   s, i, re, raw, cmd) {
  s = ""
  for (i = 1; i <= NL; i++) s = s (i > 1 ? " " : "") L[i]
  re = "\"command\"[ \t]*:[ \t]*\"([^\"\\\\]|\\\\.)*\""
  if (!match(s, re)) return
  raw = substr(s, RSTART, RLENGTH); sub(/^"command"[ \t]*:[ \t]*"/, "", raw); raw = substr(raw, 1, length(raw) - 1)
  cmd = unesc(raw)
  if (tolower(cmd) !~ /godot/) return
  parse(cmd, 1, 1)
  if (out == "hook") emit_hook(); else emit_rows()
}
function md_main(   i, s, fence, k, n, r, e) {
  fence = 0
  for (i = 1; i <= NL; i++) {
    s = L[i]
    if (s ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
    if (tolower(s) !~ /godot/) continue
    if (fence) { parse(s, i, 1); continue }
    n = length(s); k = 1
    while (k <= n) {
      if (substr(s, k, 1) != "`") { k++; continue }
      r = 0; while (substr(s, k + r, 1) == "`") r++
      e = close_run(s, k + r, r)
      if (e == 0) { k += r; continue }
      parse(substr(s, k + r, e - k - r), i, k + r)
      k = e + r
    }
  }
  if (out == "rewrite") emit_rewrite(); else emit_rows()
}
# close_run S FROM R — where the next run of exactly R backticks starts, 0 if none.
function close_run(s, from, r,   n, k, m) {
  n = length(s); k = from
  while (k <= n) {
    if (substr(s, k, 1) != "`") { k++; continue }
    m = 0; while (substr(s, k + m, 1) == "`") m++
    if (m == r) return k
    k += m
  }
  return 0
}
# parse CMD LN COL — split one command text (its first byte is column COL of
# input line LN) into simple commands and check each.
function parse(cmd, ln, col,   n, k, c, q, e, d, hs, h, line, nh) {
  CMD = cmd; CLN = ln; CCOL = col
  n = length(cmd); q = ""; cur = ""; inw = 0; nw = 0; nh = 0
  for (k = 1; k <= n; k++) {
    c = substr(cmd, k, 1)
    if (q == "\047") { if (c == "\047") q = ""; else cur = cur c; we_ = k; continue }
    if (q == "\"") {
      if (c == "\\" && k < n) { k++; cur = cur substr(cmd, k, 1); we_ = k; continue }
      if (c == "\"") q = ""; else cur = cur c
      we_ = k; continue
    }
    if (c == "\\" && k < n) { if (!inw) ws_ = k; k++; cur = cur substr(cmd, k, 1); inw = 1; we_ = k; continue }
    if (c == "\047" || c == "\"") { if (!inw) ws_ = k; q = c; inw = 1; we_ = k; continue }
    if (c == "#" && !inw) { e = index(substr(cmd, k), "\n"); if (e == 0) break; k += e - 2; continue }
    if (c == "<" && substr(cmd, k + 1, 1) == "<" && substr(cmd, k + 2, 1) != "<") {
      k += 2; hs = 0
      if (substr(cmd, k, 1) == "-") { hs = 1; k++ }
      while (substr(cmd, k, 1) == " " || substr(cmd, k, 1) == "\t") k++
      d = ""
      while (k <= n) {
        c = substr(cmd, k, 1)
        if (c == " " || c == "\t" || c == "\n" || c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "<" || c == ">") break
        if (c != "\047" && c != "\"" && c != "\\") d = d c
        k++
      }
      k--; nh++; hd[nh] = d; hstrip[nh] = hs; flush(); continue
    }
    if (c == "\n" && nh > 0) {
      endcmd()
      for (h = 1; h <= nh; h++) {
        for (;;) {
          if (k >= n) break
          e = index(substr(cmd, k + 1), "\n")
          if (e == 0) { line = substr(cmd, k + 1); k = n } else { line = substr(cmd, k + 1, e - 1); k += e }
          if (hstrip[h]) sub(/^\t+/, "", line)
          if (line == hd[h]) break
        }
      }
      nh = 0; continue
    }
    # #66: >& <& &> &>> are redirections (2>&1), part of the word.
    if (c == "&" && (substr(cmd, k - 1, 1) == ">" || substr(cmd, k - 1, 1) == "<" || substr(cmd, k + 1, 1) == ">")) {
      if (!inw) ws_ = k; cur = cur c; inw = 1; we_ = k; continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(" || c == ")") { endcmd(); continue }
    if (c == " " || c == "\t") { flush(); continue }
    if (!inw) ws_ = k
    cur = cur c; inw = 1; we_ = k
  }
  endcmd()
}
function flush() { if (inw) { nw++; w[nw] = cur; wsp[nw] = ws_; wep[nw] = we_ }; cur = ""; inw = 0 }
function endcmd() { flush(); if (nw) check(); nw = 0 }
function check(   i, j, t, b, hp, ok, cc, dd, v, pre) {
  i = 1
  while (i <= nw) {
    t = w[i]
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t == "!" || t == "{" || t == "if" || t == "then" || t == "else" || t == "elif" || t == "do" || t == "while" || t == "until") { i++; continue }
    if (t == "env") { i++; while (i <= nw && (w[i] ~ /^-/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) { if (w[i] == "-u") i++; i++ }; continue }
    if (t == "exec" || t == "command" || t == "time" || t == "nohup") { i++; while (i <= nw && w[i] ~ /^-/) i++; continue }
    if (t == "nice") { i++; if (w[i] == "-n") i += 2; else while (i <= nw && w[i] ~ /^-/) i++; continue }
    if (t == "timeout" || t == "gtimeout") { i++; while (i <= nw && w[i] ~ /^-/) { if (w[i] == "-s" || w[i] == "-k") i++; i++ }; i++; continue }
    break
  }
  if (i > nw) return
  b = w[i]; sub(/.*\//, "", b); b = tolower(b)
  if (b !~ /^godot/ && w[i] !~ /^\$\{?(GODOT|GODOT_PATH|GODOT_BIN)\}?$/) return
  hp = 0; ok = 0; cc = 0; dd = 0; v = ""
  for (j = i + 1; j <= nw; j++) {
    t = w[j]
    if (t ~ /gut_cmdln/) v = "b"
    if (t == "--") dd = 1
    if (!dd && (t == "-s" || t == "--script" || t ~ /^--script=/ || t == "--import")) cc = 1
    if (t == "--headless" || t == "--path" || t ~ /^--path=/) hp = 1
    if (t == "-s" || t == "--script" || t == "--import" || t == "-e" || t == "--editor" || t ~ /^--export/ || t == "--version" || t == "--doctool" || t == "--quit" || t == "--quit-after" || t == "--help" || t == "-h") ok = 1
  }
  if (v == "" && cc) v = "c"
  if (v == "" && hp && !ok) v = "a"
  if (v == "") return
  NS++; SV[NS] = v
  SC[NS] = CCOL + wsp[i] - 1
  ST[NS] = substr(CMD, wsp[i], wep[nw] - wsp[i] + 1)
  pre = substr(CMD, 1, wsp[i] - 1); SL[NS] = CLN + gsub(/\n/, "", pre)
}
function emit_rows(   j, s) {
  for (j = 1; j <= NS; j++) { s = ST[j]; gsub(/[\n\r]/, " ", s); print SL[j] "\t" SV[j] "\t" s }
}
function emit_hook(   j, hb, hc, ha, seg) {
  hb = 0; hc = 0; ha = 0; seg = ""
  for (j = 1; j <= NS; j++) {
    if (SV[j] == "b") hb = 1
    else if (SV[j] == "a") ha = 1
    else if (!hc) { hc = 1; seg = ST[j] }
  }
  if (!(hb || hc || ha)) return
  print (hb ? "b" : "") (hc ? "c" : "") (ha ? "a" : "")
  print jesc(cut(seg, 400))
}
# cut S N — S cut to N bytes, backing off to a UTF-8 character boundary, "…" appended when cut.
function cut(s, n,   k) {
  if (length(s) <= n) return s
  k = n; while (k > 0 && (substr(s, k + 1, 1) in CONT)) k--
  return substr(s, 1, k) "\342\200\246"
}
# jesc S — S as JSON string content: \ " and control characters escaped.
function jesc(s,   o, i, n, c) {
  o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\" || c == "\"") o = o "\\" c
    else if (c in CTL) o = o CTL[c]
    else o = o c
  }
  return o
}
function emit_rewrite(   i, j, s, p, o) {
  j = 1
  for (i = 1; i <= NL; i++) {
    s = L[i]; o = ""; p = 1
    while (j <= NS && SL[j] == i) {
      if (SV[j] == "c") { o = o substr(s, p, SC[j] - p) "studio-gate godot -- "; p = SC[j] }
      j++
    }
    printf "%s", o substr(s, p)
    if (i < NL || !nonl) printf "\n"
  }
}
```

- [ ] **Step 5: Replace `hooks/godot-guard.sh` whole.** Keep the file executable.

```sh
#!/bin/sh
# PreToolUse hook for the game-dev studio (matcher Bash), active in every
# session (#59 R4, #66 R1). Refuses a hand-built Godot call that the gate
# verbs exist to replace, per simple command:
#   (b) a hand-built GUT run (gut_cmdln): it skips the gate lock;
#   (c) an unwrapped script/import run (-s, --script, --import before --):
#       outside studio-gate it skips the lock, the run cap and gate.times,
#       and auto mode may deny it and then every later Bash call (phoenix
#       kan-1496 T1, 2026-10-09);
#   (a) a raw headless boot (--path/--headless with no exiting option).
# The detector is ../bin/godot-cmd.awk (shared with studio-brief); this file
# builds the message: one sentence per verdict present, in the order b, c,
# a, then the use line. The c sentence names the retry,
# `studio-gate godot -- <segment>`, the segment cut and JSON-escaped by the
# detector, so the output is always valid JSON.
#
# Exit 0 on every path and print nothing to allow: a parse problem, or a
# missing detector, never blocks a call. No jq, no python, no lib/.
trap 'exit 0' EXIT
det="$(dirname "$0")/../bin/godot-cmd.awk"
[ -f "$det" ] || exit 0
input="$(cat 2>/dev/null || true)"
[ -n "${input:-}" ] || exit 0
out="$(printf '%s' "$input" | LC_ALL=C awk -v mode=json -v out=hook -f "$det" 2>/dev/null)" || exit 0
[ -n "$out" ] || exit 0
cls="$(printf '%s\n' "$out" | sed -n 1p)"
seg="$(printf '%s\n' "$out" | sed -n 2p)"
_b="game-dev: refused a hand-built GUT run (gut_cmdln): it skips the gate lock that keeps Godot runs one at a time across lanes, and without -gdir= it runs the whole suite."
_c="game-dev: refused an unwrapped Godot script/import run: outside the gate it skips the lock, the run cap and gate.times, and auto mode may deny it and every later Bash call. Run it as: studio-gate godot -- $seg"
_a="game-dev: refused a raw headless Godot command (--path or --headless without -s, --import, --export, --version or --quit): it boots the main scene and never exits."
_use="Run a test file with studio-test --file <tests/unit/x.gd> (repeatable), the suite with studio-test, the game with studio-run."
msg=""
case "$cls" in *b*) msg="$_b" ;; esac
case "$cls" in *c*) msg="${msg:+$msg\\n}$_c" ;; esac
case "$cls" in *a*) msg="${msg:+$msg\\n}$_a" ;; esac
[ -n "$msg" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg\\n$_use"
exit 0
```

- [ ] **Step 6: `test_bin_syntax`.** At `tests/studio_test.sh:111`, add `*.awk` to the skip list (D10).
- [ ] **Step 7: Run; expect PASS.**
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/hook_test.sh`, the whole suite. Every godot_guard test passes. The 12000× `echo abc; ` speed case still allows; the prototype took about 1.8 s against the old hook's 2.3 s.
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_brief_test.sh`, the whole suite.
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_test.sh test_bin_syntax`.
  - All PASS.
- [ ] **Step 8: Commit.** `git add studios/game-dev/bin/godot-cmd.awk studios/game-dev/hooks/godot-guard.sh tests/hook_test.sh tests/studio_brief_test.sh tests/studio_test.sh`, then `git commit -m "godot-guard: verdict c — unwrapped script/import runs name the studio-gate retry; shared godot-cmd.awk (#66)"`.

Acceptance:

| AC | Covered by |
|----|------------|
| AC1 | `test_godot_guard_refuses_script_import`, `test_godot_guard_allows`, `test_godot_guard_denies_headless_boot` (unchanged) |
| AC2 | `test_godot_guard_message_is_valid_json` |
| AC3 | `test_godot_cmd_md_finds_bare_forms` |
| Review Focus 1 | `test_godot_guard_redirections` |
| Review Focus 3 | `test_godot_cmd_md_span_edges` |
| Fail-open | `test_godot_guard_missing_detector_allows`, `test_godot_guard_never_blocks_on_bad_input` |

---

### Task T3: Runner allow rules (R3, AC5 launch part)

Review: task (Opus). Wave 1. Risky: session permissions. It is integrated in T7 only per T1(a).

**Files:**
- Create `studios/game-dev/bin/overnight-allow.txt`.
- Modify `studios/game-dev/bin/studio-overnight`:
  - :43, add `ALLOW_FILE="$SELF_DIR/overnight-allow.txt"` after `DENY_FILE`;
  - a new `allow_rules` function after `cmd_deny_rules` (ends :212);
  - `with_launch_args` :224-238;
  - help :442-443, an "Allow rules:" block after "Deny rules:".
- Modify `studios/game-dev/bin/overnight-lanes.sh` :421.
- Modify `tests/overnight_test.sh`:
  - add `"overnight-allow.txt"` to `test_overnight_help`'s word list (:287);
  - a new test after `test_overnight_launch_argv` (ends :584);
  - its name on the run_tests line with `test_overnight_launch_argv` (:2572).
- Modify `tests/overnight_lanes_test.sh` :762: one assertion after the deny count.

**Interfaces:**
- **Produces:**
  - `allow_rules`, which prints the allow file's rules one per line (comments and blanks dropped, no templates), and nothing when the file is absent.
  - The launch argv `<prompt> --model <m> --output-format stream-json --verbose --permission-mode auto --permission-prompts none --max-budget-usd <usd> [--allowedTools <rule>…] --disallowedTools <rule>…`.
  - The lanes dry-run line `allow: <n> rules`, before `deny: <n> rules`.
- **Consumes:** `SELF_DIR` (symlink-resolved). The `start_session` launch site is unchanged.

Anchors: `grep -n '^DENY_FILE=\|^deny_rules()\|^cmd_deny_rules()\|^with_launch_args()\|^Deny rules:' studios/game-dev/bin/studio-overnight` and `grep -n "deny: %s rules" studios/game-dev/bin/overnight-lanes.sh`.

- [ ] **Step 1: Failing tests.** Add `"overnight-allow.txt"` to the `test_overnight_help` word list. Then, in `tests/overnight_test.sh` after `test_overnight_launch_argv`:

```sh
# #66 R3 / AC5: --allowedTools once, then every allow-file rule in file order,
# right before --disallowedTools (still last); no allow file or no rules: no flag.
test_overnight_launch_allow_rules() {
  fixture allowargv; done_scenario; run_start
  a="$CALLS/1.argv"
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$REPO_ROOT/studios/game-dev/bin/overnight-allow.txt" | grep -v '^#' | grep . > "$TMP/allow.txt"
  N="$(grep -c . "$TMP/allow.txt")"
  assert_eq 10 "$N" "the allow file holds the spec's ten rules"
  assert_eq 1 "$(grep -cx -- '--allowedTools' "$a")" "--allowedTools appears once"
  _ai="$(grep -nx -- '--allowedTools' "$a" | cut -d: -f1)"; [ -n "$_ai" ] || _ai=0
  _di="$(grep -nx -- '--disallowedTools' "$a" | cut -d: -f1)"
  assert_eq "$(cat "$TMP/allow.txt")" "$(sed -n "$((_ai + 1)),$((_ai + N))p" "$a")" "every allow rule follows it, one argument each, in file order"
  assert_eq "$((_ai + N + 1))" "$_di" "--disallowedTools comes right after the allow rules"
  for r in 'Bash(studio-test:*)' 'Bash(studio-run:*)' 'Bash(studio-gate godot -- $GODOT *)' 'Bash(studio-gate godot -- ${GODOT} *)' \
           'Bash(studio-gate godot -- /Applications/Godot_mono.app/Contents/MacOS/Godot *)'; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qxF -- "$r" "$a"; then _pass "argv allows $r (literally)"; else _fail "argv allows $r (literally)"; fi
  done
  for r in 'Bash(studio-gate:*)' 'Bash(studio-gate godot -- *)'; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qxF -- "$r" "$a"; then _fail "no broad rule $r"; else _pass "no broad rule $r"; fi
  done
  run_start --dry-run
  assert_contains "$RS_OUT" "'--max-budget-usd' '25' '--allowedTools' 'Bash(studio-test:\*)' 'Bash(studio-run:\*)'" "the dry-run line shows the allow rules after the budget"
  assert_contains "$RS_OUT" "'Bash(studio-gate godot -- \$GODOT_BIN \*)' '--disallowedTools'" "single-quoted, \$GODOT kept literal, then the deny rules"
  # A copy of bin/ without the allow file, then with a comments-only one: no flag.
  cp -R "$REPO_ROOT/studios/game-dev/bin" "$TMP/allowbin"; rm -f "$TMP/allowbin/overnight-allow.txt"
  ( cd "$P" && sh "$TMP/allowbin/studio-overnight" start --dry-run ) > "$TMP/na.out" 2> "$TMP/na.err"; st=$?
  assert_eq 0 "$st" "the dry run works with no allow file $(cat "$TMP/na.err")"
  assert_not_contains "$TMP/na.out" "'--allowedTools'" "no allow file: no --allowedTools"
  assert_contains "$TMP/na.out" "'--disallowedTools' 'Bash(" "the deny rules are still passed"
  printf '# only a comment\n\n' > "$TMP/allowbin/overnight-allow.txt"
  ( cd "$P" && sh "$TMP/allowbin/studio-overnight" start --dry-run ) > "$TMP/na.out" 2>/dev/null
  assert_not_contains "$TMP/na.out" "'--allowedTools'" "no rules: no --allowedTools"
}
```

In `tests/overnight_lanes_test.sh`, after :762, add `assert_contains "$LS_OUT" "^allow: 10 rules$" "the allow rule count"`.

- [ ] **Step 2: Run; expect FAIL.**
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/overnight_test.sh test_overnight_launch_allow_rules test_overnight_help test_overnight_launch_argv`. Expected: FAIL (no allow file, no flag, no help line). `test_overnight_launch_argv` stays green.
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/overnight_lanes_test.sh test_lanes_dry_run` (relocate the test name with `grep -n '"^deny: \[0-9\]' tests/overnight_lanes_test.sh`, then the enclosing `test_` line). Expected: FAIL on the allow count.
- [ ] **Step 3: Implement.**
  - **`overnight-allow.txt`.** A header comment saying:
    - the format, the same as `overnight-deny.txt` but with no templates;
    - that the rules are passed after `--allowedTools` to every unit session (#66 R3);
    - the least-privilege reason: never `Bash(studio-gate:*)` or `Bash(studio-gate godot -- *)`, because either would let any binary skip the auto-mode classifier.

    Then the ten rules, in the spec's order.
  - **`allow_rules`:**

```sh
# allow_rules — #66 R3: the allow file's rules, one per line (comments and
# blanks dropped; no templates). Nothing when the file is absent.
allow_rules() {
  [ -f "$ALLOW_FILE" ] || return 0
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$ALLOW_FILE" | grep -v '^#' | grep . || true
}
```

  - **`with_launch_args`.** End the first `set --` at `--max-budget-usd "$SESSION_USD"`, without `--disallowedTools`. Then:

```sh
  _rules="$(allow_rules)"
  if [ -n "$_rules" ]; then
    set -- "$@" --allowedTools
    while IFS= read -r _r || [ -n "$_r" ]; do
      [ -n "$_r" ] || continue
      set -- "$@" "$_r"
    done <<EOF
$_rules
EOF
  fi
  set -- "$@" --disallowedTools
```

    The existing deny loop follows unchanged. Update the function's header comment: `--allowedTools` (when the allow file has rules) comes before `--disallowedTools`, which stays last.
  - **Help.** After `Deny rules: $DENY_FILE` / `one --disallowedTools rule per line.`, add `Allow rules: $ALLOW_FILE` / `  one --allowedTools rule per line (the gate verbs and the gated Godot form);` / `  no file or no rules: no --allowedTools.`
  - **`overnight-lanes.sh` :421.** Before the deny line, add `printf 'allow: %s rules\n' "$(allow_rules | grep -c .)"`.
- [ ] **Step 4: Run; expect PASS.** Rerun the Step 2 commands. Then take the heavy-suite lock and run the whole `overnight_test.sh` once, then the whole `overnight_lanes_test.sh` once, each through `run.sh`. Release the lock.
  - Expected: all PASS.
  - `test_overnight_deny_rules_match_launch` still passes: it reads the argv after `--disallowedTools`.
- [ ] **Step 5: Commit.** `git add studios/game-dev/bin/overnight-allow.txt studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/overnight_test.sh tests/overnight_lanes_test.sh`, then `git commit -m "overnight: least-privilege allow rules for the gate verbs and gated Godot (#66 R3)"`.

Acceptance: AC5's launch part. `test_overnight_launch_allow_rules`, `test_overnight_launch_argv` (unchanged: the deny rules stay last), `test_overnight_help`, the lanes dry run.

---

### Task T4: Classifier denials named in the unit ending (R5, AC5 ending part)

Review: task (Opus). Wave 1. Risky: cross-system. Five callers, `holdable`, and a transcript parser.

**Files:**
- Modify `studios/game-dev/bin/studio-overnight`:
  - help :500-501: a test-hook line for `activity --denied`;
  - `holdable` :887-897;
  - `open_calls` :1021-1080: the header comment, plus the denied mode;
  - new `cut_utf8` and `deny_note` after `stall_note` (:1391);
  - `run_unit` :1278-1362;
  - `story_units` :1518-1529;
  - `activity` :2180-2185.
- Modify `studios/game-dev/bin/overnight-lanes.sh`:
  - `land_repair` :677-686;
  - `gate_repair` :732, :736-738, and its header comment;
  - `sync_repair` :829, :841-843, and its header comment;
  - `final_unit` :1691-1692.
- Create `tests/fixtures/overnight-permission-denied.jsonl`.
- Modify `tests/overnight_test.sh`: 2 tests before `stall_log()` (:2364), and their names on the run_tests line with `test_overnight_open_calls` (:2557).
- Modify `tests/overnight_lanes_test.sh`: 1 test after `test_lanes_gate_repair_noprog_holds` (ends :2911), and its name on the :4768 run_tests line.

**Interfaces:**
- **Produces:**
  - `open_calls JSONL denied`: `<n>\t<command>` or nothing. n counts `"subtype":"permission_denied"` events with `"decision_reason_type":"classifier"`. The command is the Bash `tool_use` input whose id is the first such event's `tool_use_id`, with tabs and newlines flattened; it is `-` when that call is not in the log.
  - `cut_utf8 N`: stdin to stdout, cut to N bytes on a UTF-8 boundary, `…` appended when cut.
  - `deny_note JSONL`: ` [permission-route — denied: <command cut to 200 bytes>]`, or ` [permission-route — denied: <command> (+<n-1> more)]` when n > 1, or nothing.
  - `UNIT_DENY_NOTE`, set by every `run_unit` (empty first, so it is empty on a halt).
  - `activity --denied <unit.jsonl>`: the note plus a newline, or nothing. Usage error, exit 2, without a readable file.
- **Consumes:** `$UNIT_DIR/$UNIT_STEM.jsonl`; the existing `open_calls` awk.

Anchors: `grep -n '^holdable()\|^open_calls()\|^run_unit()\|^stall_note()\|^story_units()\|activity --open-gate\|  activity)' studios/game-dev/bin/studio-overnight` and `grep -n '^land_repair()\|^gate_repair()\|^sync_repair()\|^final_unit()' studios/game-dev/bin/overnight-lanes.sh`.

- [ ] **Step 1: The fixture.** Create `tests/fixtures/overnight-permission-denied.jsonl`, one JSON object per line, exactly:

```json
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_A","name":"Agent","input":{"subagent_type":"game-dev:gameplay-programmer","description":"T1 implement","prompt":"Implement T1."}}]}}
{"type":"assistant","parent_tool_use_id":"toolu_A","message":{"content":[{"type":"tool_use","id":"toolu_D1","name":"Bash","input":{"command":"/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd 2>&1 | tail -5","description":"Run the importer"}}]}}
{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_D1","agent_id":"a1","decision_reason_type":"classifier","decision_reason":"[Auto-Mode Bypass]","message":"Permission for this action was denied by the Claude Code auto mode classifier."}
{"type":"user","parent_tool_use_id":"toolu_A","message":{"content":[{"tool_use_id":"toolu_D1","type":"tool_result","content":"Permission for this action was denied","is_error":true}]}}
{"type":"assistant","parent_tool_use_id":"toolu_A","message":{"content":[{"type":"tool_use","id":"toolu_D2","name":"Bash","input":{"command":"git status"}}]}}
{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_D2","agent_id":"a1","decision_reason_type":"classifier","decision_reason":"[Auto-Mode Bypass]","message":"Permission for this action was denied by the Claude Code auto mode classifier."}
{"type":"assistant","parent_tool_use_id":"toolu_A","message":{"content":[{"type":"tool_use","id":"toolu_D3","name":"Bash","input":{"command":"ls"}}]}}
{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_D3","agent_id":"a1","decision_reason_type":"asyncAgent","decision_reason":"3 consecutive actions were blocked","message":"3 consecutive actions were blocked."}
{"type":"user","parent_tool_use_id":"toolu_A","message":{"content":[{"tool_use_id":"toolu_D3","type":"tool_result","content":"{\"subtype\":\"permission_denied\",\"decision_reason_type\":\"classifier\"} quoted text is not an event","is_error":true}]}}
```

- [ ] **Step 2: Failing tests** in `tests/overnight_test.sh`:

```sh
PRD_FIX="$REPO_ROOT/tests/fixtures/overnight-permission-denied.jsonl"
PRD_CMD='/Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd 2>&1 | tail -5'
# #66 R5 + Review Focus 5: the note activity --denied prints is the one run_unit appends.
test_overnight_denied_scan() {
  assert_eq " [permission-route — denied: $PRD_CMD (+1 more)]" "$(sh "$RUNNER" activity --denied "$PRD_FIX")" \
    "two classifier events: the first's command, +1 more (asyncAgent and the quoted event text not counted)"
  printf '%s\n' '{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_X","decision_reason_type":"classifier"}' > "$TMP/dn1.jsonl"
  assert_eq " [permission-route — denied: -]" "$(sh "$RUNNER" activity --denied "$TMP/dn1.jsonl")" "a denied call not in the log is -"
  printf '%s\n' '{"type":"system","subtype":"init"}' > "$TMP/dn0.jsonl"
  assert_eq "" "$(sh "$RUNNER" activity --denied "$TMP/dn0.jsonl")" "no denial: no note"
  : > "$TMP/dne.jsonl"
  assert_eq "" "$(sh "$RUNNER" activity --denied "$TMP/dne.jsonl")" "an empty log: no note"
  # "echo " + 100 × é is 205 bytes; byte 200 is the lead byte of the 98th é, so the cut backs off to 199 bytes.
  _e100="$(awk 'BEGIN { for (i = 0; i < 100; i++) printf "\303\251" }')"; _e97="$(awk 'BEGIN { for (i = 0; i < 97; i++) printf "\303\251" }')"
  { printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_L\",\"name\":\"Bash\",\"input\":{\"command\":\"echo $_e100\"}}]}}"
    printf '%s\n' '{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"toolu_L","decision_reason_type":"classifier"}'; } > "$TMP/dnl.jsonl"
  assert_eq " [permission-route — denied: echo $_e97…]" "$(sh "$RUNNER" activity --denied "$TMP/dnl.jsonl")" "cut to 200 bytes on a character boundary, … appended"
  _st=0; sh "$RUNNER" activity --denied "$TMP/nope.jsonl" > /dev/null 2>&1 || _st=$?
  assert_eq 2 "$_st" "no such log: usage"
}
# #66 R5 / AC5 + Review Focus 4: the note on a held stop, a no-progress ending and never on done.
test_overnight_permission_route_ending() {
  N=" \[permission-route — denied: $PRD_CMD (+1 more)\]"
  fixture prstop; holds_on 2
  scenario "$ISO1" "emit $PRD_FIX; wtledger Stop: tests blocked"
  run_start
  R="$(last_run_dir)"
  assert_contains "$R/report.md" "^Ending: stop: tests blocked$N (held 0h0m, no reply)\$" "the stop names the denied command, and the story still held (holdable ignores the note)"
  assert_contains "$R/events.jsonl" "\"state\":\"held\",\"why\":\"stop: tests blocked$N\"" "the held story_state event carries it"
  verb status
  assert_contains "$V_OUT" "^ended (stop: tests blocked$N (held 0h0m, no reply)) — report: " "status shows it"
  assert_eq "progress stop" "$(awk -F'\t' '{ printf "%s%s", (NR > 1 ? " " : ""), $7 }' "$R/units.tsv")" "the units.tsv outcome column is unchanged"
  holds_off
  fixture prnoprog; scenario "cost 1" "emit $PRD_FIX; cost 1"; run_start
  assert_contains "$(last_run_dir)/report.md" "no progress on T1$N" "a no-progress ending names it (the last unit's denials)"
  assert_eq "noprog noprog" "$(awk -F'\t' '{ printf "%s%s", (NR > 1 ? " " : ""), $7 }' "$(last_run_dir)/units.tsv")" "outcomes unchanged"
  fixture prdone
  scenario "stage execute; task 1/2; ledger T1 complete a..b; cost 2" \
           "task 2/2; ledger T2 complete b..c; cost 2.25" \
           "ledger final review done; cost 3" \
           "emit $PRD_FIX; ledger P1 Play: jump on the box; ledger shipped https://github.com/o/r/pull/9; stage idle; task -; cost 1"
  run_start
  assert_contains "$(last_run_dir)/report.md" "^Ending: done$" "a done unit with denials gets no suffix"
  assert_not_contains "$(last_run_dir)/report.md" "permission-route" "nowhere in the report"
}
```

In `tests/overnight_lanes_test.sh`, after `test_lanes_gate_repair_noprog_holds`:

```sh
# #66 R5 + Review Focus 4: the note on a held gate repair (exact-pattern
# holdable), a land repair's stopped record, and the final repair's note.
test_lanes_permission_route_note() {
  F="$REPO_ROOT/tests/fixtures/overnight-permission-denied.jsonl"
  N=" \[permission-route — denied: /Applications/Godot_mono.app/Contents/MacOS/Godot --headless --path . --script res://tools/web_tools_importer.gd 2>&1 | tail -5 (+1 more)\]"
  LANES_CONFIG='{"overnight": {"gate_repairs": 1}}'; export LANES_CONFIG
  lanes_fixture prgr integration A:-
  lholds_on 120
  printf 'auto\nauto\nstop gate red — x\nauto\n' > "$SCEN/A"
  printf 'emit %s; noop\ngaterepair\n' "$F" > "$SCEN/A.gate"
  lanes_bg
  wait_for 'is_held A' 60
  assert_contains "$(last_lanes_dir)/stories/A" "^held gate repair made no progress$N until " "a gate repair with no progress still holds, with the note"
  lverb resume A
  wait_pid_or_fail "$RPID" 120 "the run finishes"
  assert_contains "$(last_lanes_dir)/stories/A" "^landed " "A lands after the resume"
  lholds_off; unset LANES_CONFIG
  lanes_fixture prland integration A:- B:-
  printf 'conflict shared.txt\n' > "$SCEN/A"; printf 'conflict shared.txt\nauto\nwaitfor %s\n' "$P/.studio/runs/demo/landed.tsv" > "$SCEN/B"
  printf 'emit %s; noop\n' "$F" > "$SCEN/B.land"
  run_lanes start "$MFP"
  assert_contains "$(last_lanes_dir)/stories/B" "^stopped repair made no progress$N\$" "a land repair's record carries the note"
  lanes_fixture prfin integration A:-
  printf 'emit %s; noop\n' "$F" > "$SCEN/final-repair"
  use_gate "exit 1"
  run_lanes start "$MFP"
  use_gate true
  assert_contains "$(last_lanes_dir)/report.md" "^Final note: .*the final-repair unit ended$N" "the final repair's note"
}
```

- [ ] **Step 3: Run; expect FAIL.**
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/overnight_test.sh test_overnight_denied_scan test_overnight_permission_route_ending`. Expected: FAIL (`activity --denied` is a usage error; there is no note).
  - `sh <scratch>/66-suites/run.sh <worktree>/tests/overnight_lanes_test.sh test_lanes_permission_route_note`. Expected: FAIL.
- [ ] **Step 4: `open_calls` denied mode.** Three edits to the awk. Also add a header-comment line: `` `denied`: `<n>\t<command>` for the classifier's permission_denied events (#66 R5) — see deny_note.``
  - First, the main rule's first statement:

```awk
      # #66 R5: a classifier denial event — count it, keep the first one's id.
      # Event text quoted inside a tool_result is escaped (\") and never matches.
      if (index($0, "\"subtype\":\"permission_denied\"") && match($0, /"decision_reason_type":"[^"]*"/) \
          && substr($0, RSTART + 24, RLENGTH - 25) == "classifier") {
        nd++
        if (nd == 1) { did = "-"; if (match($0, /"tool_use_id":"[^"]*"/)) did = substr($0, RSTART + 15, RLENGTH - 16) }
      }
```

  - Second, the Bash branch becomes `if (nm == "Bash") { d = val(inp, "command"); full = d; bash[id] = d }`.
  - Third, the first statement of `END`:

```awk
      if (mode == "denied") {
        if (nd) { c = (did in bash) ? bash[did] : "-"; gsub(/[\t\r\n]/, " ", c); print nd "\t" c }
        exit
      }
```

- [ ] **Step 5: `cut_utf8` and `deny_note`**, after `stall_note`:

```sh
# cut_utf8 N — stdin (one line) cut to N bytes, backing off to a UTF-8
# character boundary, "…" appended when cut (byte semantics: LC_ALL=C).
cut_utf8() {
  LC_ALL=C awk -v n="$1" '
    BEGIN { for (i = 128; i < 192; i++) CONT[sprintf("%c", i)] = 1 }
    { s = s (NR > 1 ? " " : "") $0 }
    END {
      if (length(s) <= n) { print s; exit }
      k = n; while (k > 0 && (substr(s, k + 1, 1) in CONT)) k--
      print substr(s, 1, k) "\342\200\246"
    }'
}
# deny_note JSONL — #66 R5: ` [permission-route — denied: <command>[ (+<n>
# more)]]` when the unit's transcript holds auto-mode classifier denials
# (asyncAgent ones not counted): the first denied Bash call's command, cut to
# 200 bytes; `-` when that call is not in the log. Empty otherwise, and for
# a missing or unparsable transcript.
deny_note() {
  _dn="$(open_calls "$1" denied)"; [ -n "$_dn" ] || return 0
  _dn_n="${_dn%%	*}"; _dn_c="$(printf '%s\n' "${_dn#*	}" | cut_utf8 200)"
  printf ' [permission-route — denied: %s' "$_dn_c"
  [ "$_dn_n" -le 1 ] || printf ' (+%s more)' "$((_dn_n - 1))"
  printf ']'
}
```

  (The `%%	*` and `#*	` patterns hold a literal tab.)
- [ ] **Step 6: `run_unit`.**
  - Make its first line `UNIT_DENY_NOTE=""`, before `UNIT_STEM=…` and so before the halted `return 0`.
  - Before `requeue_check`, add `UNIT_DENY_NOTE="$(deny_note "$_log")"   # #66 R5: appended by the caller to a non-done ending`.
- [ ] **Step 7: `holdable`.** Replace the case subject:

```sh
  # #66 R5: the permission-route note never decides a hold.
  _h_e="${ENDING%% \[permission-route — *}"
  case "$_h_e" in
    "held by operator") return 0 ;;
    "stop: "*) [ "$_h_e" = "${STOP_ENDING:-}" ] && [ "${STOP_SRC:-}" = feature ] && isolated; return $? ;;
```

  The rest of the case is unchanged.
- [ ] **Step 8: The callers.** Append `$UNIT_DENY_NOTE` at each place below.
  - **`story_units`:**
    - :1518 `ENDING="$STOP_ENDING$UNIT_DENY_NOTE"`;
    - :1522 `ENDING="directive $REQ_LIMIT not recorded$UNIT_DENY_NOTE"`;
    - :1527-1529, after each of the three endings: `…(session_minutes $SESSION_MINUTES)$UNIT_DENY_NOTE"`, `…$(stall_note)$UNIT_DENY_NOTE"`, `…$(orphan_note "$_out")$UNIT_DENY_NOTE"`.
  - **`gate_repair`:** :732 `ENDING="$STOP_ENDING$UNIT_DENY_NOTE"`, and :736-738 the same three appends.
  - **`sync_repair`:** :829 `ENDING="sync repair: $STOP_ENDING$UNIT_DENY_NOTE"`, and :841-843 the three appends.
  - **`land_repair`:** :678 `story_write "$1" "stopped stop: ${_lr_new#*Stop: }$UNIT_DENY_NOTE"`, and :684-686 the three `story_write` texts.
  - **`final_unit`:** :1692 becomes

```sh
  else row "$FINAL_N" "$1" "$(unit_outcome)"
    [ -z "$UNIT_DENY_NOTE" ] || final_note "the $1 unit ended$UNIT_DENY_NOTE"; fi
```

  - Add one line to each of the `gate_repair` and `sync_repair` header comments: "… each ending carries the unit's permission-route note (#66 R5)".
  - The halt-reason endings (`lane_halt_reason`, `halt_reason`) never get the note.
- [ ] **Step 9: `activity --denied` and its help.** In `activity`, after the `--open-gate` line:

```sh
    # --denied: the permission-route note run_unit would append (#66 R5; a test hook).
    if [ "${2:-}" = --denied ]; then [ "$#" -eq 3 ] && [ -f "$3" ] || { usage >&2; exit 2; }; _dn_o="$(deny_note "$3")"; [ -z "$_dn_o" ] || printf '%s\n' "$_dn_o"; exit 0; fi
```

  Help, after the `activity --open-gate` lines (:500-501): `  activity --denied <unit.jsonl> — test hook verb: prints the permission-route` / `                     note a unit's ending would carry (#66); nothing when none`.
- [ ] **Step 10: Run; expect PASS.** Rerun the Step 3 commands: PASS. Then take the heavy-suite lock and run the whole `overnight_test.sh`, then the whole `overnight_lanes_test.sh`, each through `run.sh`. Release the lock.
  - Expected: all PASS, in particular the hold tests (`test_overnight_hold_deadline`, `test_lanes_held_dependents_wait`, `test_lanes_gate_repair_noprog_holds`) and `test_overnight_open_calls`.
- [ ] **Step 11: Commit.** `git add studios/game-dev/bin/studio-overnight studios/game-dev/bin/overnight-lanes.sh tests/fixtures/overnight-permission-denied.jsonl tests/overnight_test.sh tests/overnight_lanes_test.sh`, then `git commit -m "overnight: a unit ending names the classifier-denied command [permission-route] (#66 R5)"`.

Acceptance:

| AC | Covered by |
|----|------------|
| AC5 (ending part) | `test_overnight_permission_route_ending` |
| AC5 (callers) | `test_lanes_permission_route_note` |
| Review Focus 4 | `test_overnight_permission_route_ending`, `test_lanes_permission_route_note` |
| Review Focus 5 | `test_overnight_denied_scan` |

---

### Task T5: `studio-brief rewrite`, rewriting briefs, `validate` refuses bare forms (R4, AC4)

Review: task (Opus). Wave 2: start from T2's commits. Risky: every brief's text passes through it.

**Files:**
- Modify `studios/game-dev/bin/studio-brief`:
  - the header comment (verbs list);
  - `usage` :54-56;
  - after `STATE_BIN` :52, add `DET`;
  - `emit` :77, which becomes `emit`, `emit_raw` and `no_det_warn`;
  - `context_part` :210, which uses `emit_raw`;
  - `validate` :241-271;
  - a new `rewrite)` verb before `task)`.
- Modify `tests/studio_brief_test.sh`: a `godot_fixture` helper, 4 tests, one assertion in `test_brief_usage_names_check` (:346-351), and `run_tests`.

**Interfaces:**
- **Produces:**
  - `studio-brief rewrite`: stdin to stdout (D4). Exit 0.
  - `task <n>`, `check <k>` and `final` output: the same parts and headers, with c segments gated in plan and spec text. Context files stay raw.
  - `validate <plan>` error lines on stderr: `studio-brief: line <n>: unwrapped Godot script/import run; write it as: studio-gate godot -- <segment>`, then exit 1. With no detector: `studio-brief: <path>/godot-cmd.awk missing — reinstall omega-ai` and exit 1. A missing plan still exits 2 first.
  - Usage: `usage: studio-brief task <n> | final | check <k> | validate <plan> | rewrite`.
- **Consumes:** `godot-cmd.awk` (T2), as `$HERE/godot-cmd.awk`.

Anchors: `grep -n '^HERE=\|^STATE_BIN=\|^usage()\|^emit()\|emit "\$_cp_f"\|^validate)\|^task)' studios/game-dev/bin/studio-brief`.

- [ ] **Step 1: Failing tests** in `tests/studio_brief_test.sh`, after T2's md group:

````sh
# godot_fixture DIR — ctx_fixture plus bare Godot forms: a Task 1 step, the
# spec's Purpose line (in Task 1's L3-4) and AC 1 (S1's final), and Context c1.
godot_fixture() {
  ctx_fixture "$1"
  awk '{ print } /^MARK-T1$/ { print "- [ ] **Step 3:** `Godot --headless --path . --script res://tools/importer.gd` then check." }' "$1/docs/plan.md" > "$TMP/gp" && mv "$TMP/gp" "$1/docs/plan.md"
  sed -i.bak -e 's/^MARK-PURPOSE$/MARK-PURPOSE run `Godot --headless --import .` first/' \
             -e 's|^1\. First MARK-AC1$|1. First MARK-AC1 via `Godot --headless --path . --script res://ac.gd`|' "$1/docs/spec.md"
  rm -f "$1/docs/spec.md.bak"
  printf 'MARK-C1 `Godot --headless --import .`\n' > "$1/docs/c1.md"
}
# #66 AC4 + Review Focus 3: rewrite wraps only the c forms; every other byte is the same.
test_brief_rewrite_wraps_only() {
  cat "$TMP/ac3.md" "$TMP/edge.md" > "$TMP/rw.in"
  { sed -e 's/^Godot --headless --path \. --script res:\/\/tools/studio-gate godot -- &/' \
        -e 's/`Godot --headless --path \. --script res:\/\/a\.gd`/`studio-gate godot -- Godot --headless --path . --script res:\/\/a.gd`/' \
        -e 's/^Run `Godot --headless --import \.` and then `Godot/Run `studio-gate godot -- Godot --headless --import .` and then `studio-gate godot -- Godot/' "$TMP/ac3.md"
    cat "$TMP/edge.rw.want"; } > "$TMP/rw.want"
  sh "$BRIEF" rewrite < "$TMP/rw.in" > "$TMP/rw.out" 2> "$TMP/rw.err"; st=$?
  assert_eq 0 "$st" "rewrite exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rw.want" "$TMP/rw.out"; then _pass "rewrite: each c form gated, nothing else changed"
  else _fail "rewrite: each c form gated ($(diff "$TMP/rw.want" "$TMP/rw.out" | head -n 4))"; fi
  assert_eq "" "$(cat "$TMP/rw.err")" "nothing on stderr"
  printf 'a\tb\r\n- `ls -la` \303\251\n\n```\nGodot --version\n```\n' > "$TMP/rw0.in"
  sh "$BRIEF" rewrite < "$TMP/rw0.in" > "$TMP/rw0.out"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/rw0.in" "$TMP/rw0.out"; then _pass "no c form: byte-identical (tab, CR, UTF-8, fences)"; else _fail "no c form: byte-identical"; fi
  printf 'x `Godot --script a`' | sh "$BRIEF" rewrite > "$TMP/rw1.out"
  assert_eq "$(printf 'x `studio-gate godot -- Godot --script a`' | wc -c | tr -d ' ')" "$(wc -c < "$TMP/rw1.out" | tr -d ' ')" "no final newline in, none out"
  : | sh "$BRIEF" rewrite > "$TMP/rw2.out"
  assert_eq 0 "$(wc -c < "$TMP/rw2.out" | tr -d ' ')" "empty in, empty out"
}
# #66 AC4: task, check and final output is rewritten; Context files are not.
test_brief_task_check_final_rewritten() {
  Q="$TMP/projg"; godot_fixture "$Q"; commit_fixture "$Q"
  ledger_in "$Q" "adopt-base $S0"; ledger_in "$Q" "T1 complete $S0..$S1"
  for v in "task 1" "check 1"; do
    # shellcheck disable=SC2086
    brief_in "$Q" $v > "$TMP/g.out" 2> "$TMP/g.err"; st=$?
    assert_eq 0 "$st" "$v exits 0"
    assert_contains "$TMP/g.out" 'Step 3:\*\* `studio-gate godot -- Godot --headless --path \. --script res://tools/importer\.gd` then check\.$' "$v: the plan step is gated"
    assert_contains "$TMP/g.out" '^MARK-PURPOSE run `studio-gate godot -- Godot --headless --import \.` first$' "$v: the cited spec range is gated"
    assert_contains "$TMP/g.out" '^MARK-C1 `Godot --headless --import \.`$' "$v: a Context file is printed as is"
    assert_contains "$TMP/g.out" '^==> docs/plan\.md:L[0-9]*-[0-9]*$' "$v: part headers unchanged"
    assert_eq "" "$(cat "$TMP/g.err")" "$v: no warning"
  done
  brief_in "$Q" final > "$TMP/gf.out"; st=$?
  assert_eq 0 "$st" "final exits 0"
  assert_contains "$TMP/gf.out" '^1\. First MARK-AC1 via `studio-gate godot -- Godot --headless --path \. --script res://ac\.gd`$' "final: the AC text is gated"
}
# #66 AC4: validate names the line and the wrapped form; the gated form passes.
test_brief_validate_godot_form() {
  Q="$TMP/projvg"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  printf -- '- [ ] **Step 2:** `Godot --headless --path . --script res://x.gd 2>&1 | tail -5` then commit.\n' >> "$Q/docs/plan.md"
  _ln="$(grep -c '' "$Q/docs/plan.md")"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/vg.out" 2> "$TMP/vg.err"; st=$?
  assert_eq 1 "$st" "a bare Godot script run fails validate"
  assert_contains "$TMP/vg.err" "^studio-brief: line $_ln: unwrapped Godot script/import run; write it as: studio-gate godot -- Godot --headless --path \. --script res://x\.gd 2>&1\$" "names the line and the wrapped form"
  assert_eq "" "$(cat "$TMP/vg.out")" "no ok line"
  sed -i.bak 's/`Godot --headless/`studio-gate godot -- Godot --headless/' "$Q/docs/plan.md"; rm -f "$Q/docs/plan.md.bak"
  ( cd "$Q" && sh "$BRIEF" validate docs/plan.md ) > "$TMP/vg.out" 2> "$TMP/vg.err"; st=$?
  assert_eq 0 "$st" "the gated form passes"
  assert_contains "$TMP/vg.out" '^studio-brief: 4 tasks, 5 Spec items ok$' "and counts as before"
}
# #66 AC4: no detector → rewrite passes through with one warning; validate fails closed; task warns once.
test_brief_missing_detector() {
  mkdir -p "$TMP/nodet"; cp "$BRIEF" "$TMP/nodet/studio-brief"; ln -s "$STATE_BIN" "$TMP/nodet/studio-state"
  printf 'x `Godot --script a.gd`\n' > "$TMP/nd.md"
  sh "$TMP/nodet/studio-brief" rewrite < "$TMP/nd.md" > "$TMP/nd.out" 2> "$TMP/nd.err"; st=$?
  assert_eq 0 "$st" "rewrite without the detector exits 0"
  TESTS_RUN=$((TESTS_RUN + 1))
  if cmp -s "$TMP/nd.md" "$TMP/nd.out"; then _pass "and passes the text through"; else _fail "and passes the text through"; fi
  assert_contains "$TMP/nd.err" 'godot-cmd.awk' "with a warning naming the detector"
  assert_eq 1 "$(grep -c . "$TMP/nd.err")" "one warning"
  Q="$TMP/projnd"; build_fixture "$Q"
  awk '/^### Task (2|4):/ { print; print "Spec: docs/spec.md:L1"; next } { print }' "$Q/docs/plan.md" > "$TMP/p" && mv "$TMP/p" "$Q/docs/plan.md"
  ( cd "$Q" && sh "$TMP/nodet/studio-brief" validate docs/plan.md ) > "$TMP/ndv.out" 2> "$TMP/ndv.err"; st=$?
  assert_eq 1 "$st" "validate without the detector fails closed"
  assert_contains "$TMP/ndv.err" 'reinstall omega-ai' "and says to reinstall"
  ( cd "$Q" && STUDIO_STORY=S1 sh "$TMP/nodet/studio-brief" task 3 ) > "$TMP/ndt.out" 2> "$TMP/ndt.err"; st=$?
  assert_eq 0 "$st" "task without the detector still exits 0"
  assert_contains "$TMP/ndt.out" "MARK-T3" "with the raw task text"
  assert_eq 1 "$(grep -c 'godot-cmd.awk' "$TMP/ndt.err")" "one warning for all its parts"
}
````

In `test_brief_usage_names_check`, add `assert_contains "$TMP/u.err" "| rewrite" "usage names rewrite"`. Add the four test names to `run_tests`.

- [ ] **Step 2: Run; expect FAIL.** `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_brief_test.sh test_godot_cmd_md_finds_bare_forms test_godot_cmd_md_span_edges test_brief_rewrite_wraps_only test_brief_task_check_final_rewritten test_brief_validate_godot_form test_brief_missing_detector test_brief_usage_names_check`.
  - Expected: FAIL. `rewrite` is a usage error, and nothing is gated.
  - The first two run first because `test_brief_rewrite_wraps_only` reuses their `$TMP/ac3.md`, `edge.md` and `edge.rw.want`. Keep this order in `run_tests` too.
- [ ] **Step 3: Implement.**
  - **`DET`.** `DET="$HERE/godot-cmd.awk"`.
  - **`emit`, `emit_raw`, `no_det_warn`:**

```sh
# no_det_warn — one warning per run that the detector is missing (#66 R4).
no_det_warn() {
  [ -z "${_NODET_WARNED:-}" ] || return 0
  printf 'studio-brief: warning: %s missing — Godot commands are not rewritten (reinstall omega-ai)\n' "$DET" >&2
  _NODET_WARNED=1
}
# emit FILE A B — the part header, then lines A-B, each bare Godot
# script/import run wrapped as `studio-gate godot -- …` (#66 R4). The whole
# file is rewritten, then sliced, so fences and line numbers hold. No
# detector: the raw lines and one warning.
emit() {
  printf '==> %s:L%s-%s\n' "$1" "$2" "$3"
  if [ -f "$DET" ]; then LC_ALL=C awk -v mode=md -v out=rewrite -f "$DET" "$1" | sed -n "$2,$3p"
  else no_det_warn; sed -n "$2,$3p" "$1"; fi
}
# emit_raw FILE A B — the part header, then the lines verbatim (Context files).
emit_raw() { printf '==> %s:L%s-%s\n' "$1" "$2" "$3"; sed -n "$2,$3p" "$1"; }
```

  - **`context_part`.** `emit "$_cp_f" 1 "$_cp_n"` becomes `emit_raw "$_cp_f" 1 "$_cp_n"`.
  - **The `rewrite` verb:**

```sh
rewrite)
  [ $# -eq 1 ] || usage
  _rw_in="$(mktemp "${TMPDIR:-/tmp}/studio-brief.XXXXXX")" || fail "cannot make a temp file"
  _rw_out="$_rw_in.out"
  trap 'rm -f "$_rw_in" "$_rw_out"' EXIT
  cat > "$_rw_in"
  if [ ! -f "$DET" ]; then no_det_warn; cat "$_rw_in"; exit 0; fi
  _rw_nonl=0; [ ! -s "$_rw_in" ] || [ -z "$(tail -c1 "$_rw_in")" ] || _rw_nonl=1
  if LC_ALL=C awk -v mode=md -v out=rewrite -v nonl="$_rw_nonl" -f "$DET" "$_rw_in" > "$_rw_out"; then cat "$_rw_out"
  else printf 'studio-brief: warning: the Godot command check failed — text not rewritten\n' >&2; cat "$_rw_in"; fi
  ;;
```

  - **`validate`.** After the plan-exists check (exit 2) and before the task loop:

```sh
  [ -f "$DET" ] || { printf 'studio-brief: %s missing — reinstall omega-ai\n' "$DET" >&2; exit 1; }
  _vg_rows="$(LC_ALL=C awk -v mode=md -f "$DET" "$vplan")" \
    || { printf 'studio-brief: the Godot command check failed on %s — reinstall omega-ai\n' "$2" >&2; exit 1; }
  while IFS='	' read -r _vg_l _vg_v _vg_s; do
    [ "$_vg_v" = c ] || continue
    printf 'studio-brief: line %s: unwrapped Godot script/import run; write it as: studio-gate godot -- %s\n' "$_vg_l" "$_vg_s" >&2
    _vbad=1
  done <<EOF
$_vg_rows
EOF
```

    `_vbad=0` must be set before this block: move the `_vt=0; _vi=0; _vbad=0; …` line above it. The existing `[ "$_vbad" = 0 ] || exit 1` then covers both kinds of error.
  - **Header and usage.**
    - Add `studio-brief rewrite` (markdown on stdin, gated forms on stdout) to the header's verb list.
    - Add a line that `task`/`check`/`final` print plan and spec text with each bare Godot script/import run gated, and Context files as is.
    - Add the Godot check to `validate`'s description and its exit-1 list.
    - Usage becomes `… | validate <plan> | rewrite`.
- [ ] **Step 4: Run; expect PASS.** `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_brief_test.sh`, the whole suite. Expected: all PASS, including `test_brief_validate_reports_all` (still exactly 7 `task` lines) and the context tests.
- [ ] **Step 5: Commit.** `git add studios/game-dev/bin/studio-brief tests/studio_brief_test.sh`, then `git commit -m "studio-brief: rewrite verb; briefs show only the gated Godot form; validate refuses a bare one (#66 R4)"`.

Acceptance: AC4 is covered by `test_brief_rewrite_wraps_only`, `test_brief_task_check_final_rewritten`, `test_brief_validate_godot_form`, `test_brief_missing_detector` and `test_brief_usage_names_check`. Review Focus 3 is covered by `test_brief_rewrite_wraps_only`.

---

### Task T6: Execute and plan skill text (R4, AC6)

Review: final. Wave 1. Mechanical.

**Files:**
- Modify `studios/game-dev/skills/execute/SKILL.md`: :176-180 (§0), :355 (the brief), :367-370 (the implementer line).
- Modify `studios/game-dev/skills/plan/SKILL.md`: §2, a bullet after the `Review:` bullet (:77-79); §6, :155-160.
- Modify `tests/studio_test.sh`: 2 tests before `run_tests` (:811), and the names on its last line.

**Interfaces:** Text only. These literals are pinned by tests:
- execute: `"$(sdd-script task-brief)" <plan> <n> | studio-brief rewrite`, `studio-gate godot -- <command>`;
- plan: `studio-gate godot -- <Godot command>`, `bare Godot script/import run`, `fails the plan on it`.

The existing pins must survive: `'"$(sdd-script task-brief)" <plan> <n>'` (a substring of the new form), `'Never build a Godot or GUT command by hand'` (keep the :177 line's wording), and `'godot-guard.sh'`.

Anchors: `grep -n 'Never build a Godot\|task-brief\|never build a Godot' studios/game-dev/skills/execute/SKILL.md` and `grep -n '^- `Review: task|final`\|studio-brief validate <plan path>' studios/game-dev/skills/plan/SKILL.md`.

- [ ] **Step 1: Failing tests** in `tests/studio_test.sh`:

```sh
# #66 R4 / AC6: implementer briefs get the gated task text; Godot scripts and imports go through studio-gate.
test_execute_task_brief_rewritten() {
  E="$REPO_ROOT/studios/game-dev/skills/execute/SKILL.md"
  assert_contains "$E" '"$(sdd-script task-brief)" <plan> <n> | studio-brief rewrite' "the task text is piped through studio-brief rewrite"
  assert_contains "$E" 'studio-gate godot -- <command>' "a Godot script or import runs through the gate"
  assert_contains "$E" 'an unwrapped script or import run' "the hook's third refusal is named"
}
# #66 R4 / AC6: plans write only the gated forms; validate enforces it.
test_plan_gated_godot_forms() {
  PL="$REPO_ROOT/studios/game-dev/skills/plan/SKILL.md"
  assert_contains "$PL" 'studio-gate godot -- <Godot command>' "plan names the gated form"
  assert_contains "$PL" 'bare Godot script/import run' "and the refused one"
  assert_contains "$PL" 'fails the plan on it' "§2 says validate enforces it"
  assert_contains "$PL" 'also fails on a bare Godot script/import run' "§6 says so too"
}
```

  Add both names to `run_tests`.
- [ ] **Step 2: Run; expect FAIL.** `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_test.sh test_execute_task_brief_rewritten test_plan_gated_godot_forms`.
- [ ] **Step 3: Edit the skills.**
  - **execute :177-180.** Keep `… Never build a Godot or GUT command by hand: the` on its line. Continue with: `studio's \`godot-guard.sh\` hook refuses a raw headless Godot, a hand-built \`gut_cmdln\` run, and an unwrapped script or import run (\`-s\`, \`--script\`, \`--import\`); run a Godot script or import as \`studio-gate godot -- <command>\`, the retry its refusal names.`
  - **execute :355.** It becomes: `` the task text (via the skill's task-brief script piped through the studio's rewrite, ``bash "$(sdd-script task-brief)" <plan> <n> | studio-brief rewrite``, so the brief shows only the gated Godot form; the plan file is never edited), ``.
  - **execute :367-370.** It becomes: `"run one test file with \`studio-test --file <test file>\`; never build a Godot or GUT command by hand; run a Godot script or import as \`studio-gate godot -- <command>\`; pass \`timeout\` only on gate-routed commands; …"`. The rest is unchanged.
  - **plan §2**, a new bullet after `Review:`: `- A step that runs Godot writes the gated form: a script or import run as \`studio-gate godot -- <Godot command>\` (e.g. \`studio-gate godot -- Godot --headless --path . --script res://tools/x.gd\`), tests as \`studio-test\` or \`studio-test --file <test file>\`, the game as \`studio-run\`. Never a bare Godot script/import run (\`-s\`, \`--script\`, \`--import\`): the studio's hook refuses it, and \`studio-brief validate\` fails the plan on it (§6).`
  - **plan §6.** After "the way execute's brief will read them.", add: `It also fails on a bare Godot script/import run anywhere in the plan, naming the line and the gated form to write.`
- [ ] **Step 4: Run; expect PASS.** `sh <scratch>/66-suites/run.sh <worktree>/tests/studio_test.sh`, the whole suite. Also `sh <scratch>/66-suites/run.sh <worktree>/tests/pointer_skills_execute_test.sh`. Expected: all PASS, including `test_execute_command_caps_text`, `test_sdd_script_references` and `test_plan_brainstorm_lanes`.
- [ ] **Step 5: Commit.** `git add studios/game-dev/skills/execute/SKILL.md studios/game-dev/skills/plan/SKILL.md tests/studio_test.sh`, then `git commit -m "skills: briefs pipe task-brief through studio-brief rewrite; plans write the gated Godot form (#66 R4)"`.

Acceptance: AC6 is covered by `test_execute_task_brief_rewritten` and `test_plan_gated_godot_forms`.

---

### Task T7: Integrate, final review, full gate, rollout check, PR

- [ ] **Integrate.** Cherry-pick onto `66-godot-classifier-route` in this order:
  1. T2;
  2. T5 (its own commits only);
  3. T3, applying T1(a)'s outcome:
     - PASS: as is;
     - PARTIAL: then remove the four `$GODOT*` lines from `overnight-allow.txt` and set the test's count to 6;
     - INCONCLUSIVE: as is;
     - FAIL: skip T3 entirely;
  4. T4;
  5. T6;
  6. T1.

  No conflicts are expected (see Shared files). Remove each implementer's worktree once its commits are on the story branch.
- [ ] **(b) gate.** If T1(b) is FAIL, stop here. Report to the operator that hook refusals count toward auto mode's denial limit, so R1's refusal can itself poison a session. Ask for a ruling before any merge.
- [ ] **Docs.**
  - `README.md` :339-340: the layout tree gains `overnight-allow.txt` ("the runner's allow list: gate verbs, gated Godot (data)") beside `overnight-deny.txt`, and `godot-cmd.awk` ("the Godot command detector, shared by godot-guard and studio-brief"). Fix the `├──`/`└──` glyphs.
  - `docs/game-dev/PROGRESS.md`: a new top entry, `### 2026-10-09 — Bare Godot runs go through the gate (#66)`. It covers: the incident; verdict c and the shared detector; the allow rules and T1's results; the rewrite and validate; the permission-route note; the spec and plan paths.
  - Commit `docs: #66 layout and progress`.
- [ ] **Final review.** A standalone whole-branch Opus review over `<plan commit>..HEAD`, against the spec and this plan.
  - T6 and T1 get their only review here.
  - Point the reviewer at Review Focus 1–5, Decisions D2, D4, D7 and D11, and the Falsify log.
- [ ] **Fix wave.** One fresh fixer takes the findings and the diff range, with Minors batched. Re-review only per the Global Constraints rule.
- [ ] **Full gate (AC8), once, on the integrated branch:**
  1. Confirm with the phoenix sessions (`ListAgents`, `SendMessage`) that no phoenix gate is announced as running. Announce ours.
  2. Take `mkdir /Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock` with its owner file.
  3. Run `sh <scratch>/66-suites/run.sh /Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/66-godot-classifier-route/tests/run_all.sh`.
  4. Release the lock, then tell the phoenix sessions the window has closed.
  - Expected: green.
- [ ] **Rollout check (AC7), before the PR is merged.** Run `sh <scratch>/66-suites/run.sh --args /Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/66-godot-classifier-route/tests/probes/godot_route_probe.sh rollout`.
  - Expected: `RESULT rollout: PASS`. That means the bare `--script` call was refused by R1, the named `studio-gate godot -- …` retry printed `PROBE_HELLO`, `git init` ran, and there were no classifier or asyncAgent denials.
  - It runs in its own scratch Godot project, with the real `/Applications/Godot_mono.app` and this worktree's hook. It never touches phoenix.
  - This deviates from the spec's `claude-gd` wording (D9; Falsify log 4).
- [ ] **PR.** Open a PR with `Closes #66`. The body covers:
  - T1's (a) and (b) results with the Claude Code version, and what T7 did with them;
  - the rollout output;
  - D2 (the `--` scope and its known gap), D4 (Context files raw), D7 (the note comes from the last unit; `final_unit` uses a Final note), D9 and D11;
  - Non-goals.

  End the body with the attribution footer. Merge once green, under the standing omega-ai merge authority.
- [ ] **Deploy (D11).** Check the run first: in the run's project, read-only, `studio-overnight status`, with no `--run` needed.
  - If any run is live, do nothing. Leave "pull + `./install.sh game-dev` after the run ends" as a noted follow-up.
  - Otherwise: run `git -C /Users/xinli/GameDev/proj/omega-ai pull --ff-only`, then `./install.sh game-dev` from that checkout (both together). Then confirm `ls ~/.claude-gamedev/bin/godot-cmd.awk ~/.claude-gamedev/bin/overnight-allow.txt`, and that `studio-brief rewrite < /dev/null` prints nothing and exits 0.
- [ ] **Clean up.** Remove the story worktree after the merge (`ExitWorktree` with `action: "remove"`), unless the user keeps it.

## Acceptance checklist

| AC | What | Task | Tests / evidence |
|----|------|------|------------------|
| AC1 | Refuse the four forms with the exact retry (incident: `… res://x.gd 2>&1`); allow `studio-gate importer/godot`, `--version`, `--help`, `-- -s`; :913/:914 flip; :890 keeps its asserts | T2 | `test_godot_guard_refuses_script_import`, `test_godot_guard_allows`, `test_godot_guard_denies_headless_boot`, `test_godot_guard_redirections` |
| AC2 | Valid JSON with `"`, `\`, tab, multibyte; a 400-byte cut on an escape or inside a character | T2 | `test_godot_guard_message_is_valid_json` |
| AC3 | md mode: fenced, bullet span, two-span prose line; line numbers; prose ignored | T2 | `test_godot_cmd_md_finds_bare_forms`, `test_godot_cmd_md_span_edges` |
| AC4 | `rewrite` wraps only; `task`/`check`/`final` rewritten; `validate` fails/passes; missing detector | T5 | `test_brief_rewrite_wraps_only`, `test_brief_task_check_final_rewritten`, `test_brief_validate_godot_form`, `test_brief_missing_detector` |
| AC5 | Launch argv allow before deny, no file no flag; fixture → `stop: … [permission-route — denied: <cmd> (+1 more)]` in status and report, still holds; done unchanged | T3, T4 | `test_overnight_launch_allow_rules`, `test_overnight_permission_route_ending`, `test_lanes_permission_route_note`, `test_overnight_denied_scan` |
| AC6 | execute pipes task-brief through rewrite; plan names the gated forms | T6 | `test_execute_task_brief_rewritten`, `test_plan_gated_godot_forms` |
| AC7 | Probe (a), (b) and the rollout recorded | T1, T7 | spec `## Probe results`; the PR body |
| AC8 | `sh tests/run_all.sh` green | T7 | the full gate |

## Falsify log

Every anchor and code claim above was checked at abbf15b, by `grep -n` and a read of the whole function. The detector, hook, `open_calls` denied mode, `cut_utf8`, JSON validator and md expectations were prototyped and run under macOS awk. These are the spec errors and gaps found, and how the plan handles each:

1. **`test_bin_syntax` would fail on the new `bin/godot-cmd.awk`.** `tests/studio_test.sh:108-117` runs `sh -n` and checks `-x` on every `studios/*/bin/*` file except `.gitkeep|*.txt`. → T2 adds `*.awk` (D10).
2. **`final_unit` and `land_repair` build no ENDING.** The spec says all five `run_unit` callers "append it to the ENDING they already build". `final_unit` (lanes :1676) only records a row and `final_note`s; `land_repair` (:662) writes `story_write` texts. → The note goes into a `final_note` and the `story_write` texts (D7).
3. **A plain append breaks `holdable`.** `"stop: "*` requires `ENDING = STOP_ENDING`, and `"gate repair made no progress"` and `"directive "*" not recorded"` are exact or suffix-anchored patterns (`studio-overnight:887-896`). So "prefixes are kept, so `holdable()` still holds" is false for those. → `holdable` strips the note first (D7, Review Focus 4).
4. **The rollout check's `claude-gd` loads the main checkout's plugins** (`~/.local/bin/claude-gd`: `--plugin-dir /Users/xinli/GameDev/proj/omega-ai/studios/game-dev`). Before a pull, which is forbidden while a run is live, it would test the old hook. → The probe calls `claude` directly with this checkout's `--plugin-dir`s and `CLAUDE_CONFIG_DIR=~/.claude-gamedev` (D9).
5. **`--` scope.** If the bare `--` stopped all option scanning, `Godot --path . -- -s` would lose its `ok` word and become verdict a, but AC1 requires it allowed. → `--` stops only c scanning (D2). Gap kept: `… --path . -- --script x` stays allowed.
6. **No way to test the transcript scan by itself.** `activity` has only `--open` and `--open-gate`. → New test-hook verb `activity --denied` (D8).
7. **Rewriting a cited range by itself loses fence context**, since a range can start inside a fence, and loses line numbers for the md rows. → `emit` rewrites the whole file, then slices (D4).
8. **R5's suffix wording** (` [permission-route — denied: <command>]` + ` (+<n> more)`) puts the count outside the bracket. AC5 puts it inside. → AC5's form: `[permission-route — denied: <command> (+1 more)]`.
9. **R4's "every studio-brief output that quotes plan or spec text"** leaves Context files undefined, and they are printed by the same `emit`. → Context files stay raw through `emit_raw` (D4). They are project files, not plan text, and may legitimately quote the bare form.
10. **A halted `run_unit` returns before its end**, so a note set only at the end would leak the previous unit's note into a halt ending. → It is reset at the top (D7). Halt endings never take it.
11. **Partial deploy hazard, not in the spec.** The hook and detector load live from the main checkout, but studio-brief runs from `~/.claude-gamedev/bin`, where `godot-cmd.awk` appears only after a reinstall. A pull without a reinstall makes `validate` fail closed. → Pull and reinstall go together, and only when no run is live (D11, T7).
12. **AC2 assumes a JSON checker.** jq is optional on Linux. → `json_ok` in hook_test falls back to an awk validator of the exact deny shape plus `iconv` UTF-8. It was checked to reject an unescaped quote, a raw tab and a bad escape.
13. **R3's "`print_launch` shows them"** needs no code. `print_launch` prints every argv word, single-quoted, so `$GODOT` stays literal. A test pins this. The lanes dry run gets its own `allow:` line, because the deny line is anchored (`^deny: N rules$`, lanes test :762).

## Self-review

- **Spec coverage.**
  - R1 → T2.
  - R2 → T2 (detector) and T5 (md consumer).
  - R3 → T1 (probe) and T3 (plumbing).
  - R4 → T5 and T6.
  - R5 → T4.
  - AC1–AC8 → the Acceptance checklist; every AC has a task and named tests or evidence.
  - Non-goals are untouched: there is no `--export`, `sh -c` or `$( )` handling, and no phoenix edit.
- **Placeholder scan.** No TBD, no "add tests for the above", no "similar to Task N". Every code step carries its code or an exact line edit. The only judgement left to an implementer is T1's PASS-versus-INCONCLUSIVE reading of the debug log, which the table defines.
- **Name consistency.** These names are used identically in the tasks, the Acceptance checklist and Review Focus:
  - functions and variables: `godot-cmd.awk`, `out=rows|hook|rewrite`, `nonl`, `gg_c`, `json_ok`, `godot_md`, `godot_fixture`, `allow_rules`, `ALLOW_FILE`, `cut_utf8`, `deny_note`, `UNIT_DENY_NOTE`, `activity --denied`, `emit_raw`, `no_det_warn`, `DET`;
  - test names: `test_godot_guard_refuses_script_import`, `test_godot_guard_redirections`, `test_godot_guard_message_is_valid_json`, `test_godot_guard_missing_detector_allows`, `test_godot_cmd_md_finds_bare_forms`, `test_godot_cmd_md_span_edges`, `test_brief_rewrite_wraps_only`, `test_brief_task_check_final_rewritten`, `test_brief_validate_godot_form`, `test_brief_missing_detector`, `test_overnight_launch_allow_rules`, `test_overnight_denied_scan`, `test_overnight_permission_route_ending`, `test_lanes_permission_route_note`, `test_execute_task_brief_rewritten`, `test_plan_gated_godot_forms`.
- **Exclusive-scan check.** The new tests avoid the `tests/exclusive_scan.awk` triggers: no `date +%s` bound, no `under/within N s`, no `kill -TERM`, no `sleep 1-6` with a stub, no `--seconds 1-6`, no `_SECONDS=1-6` in a test body. The hold seconds sit inside `holds_on`/`lholds_on`, as in `test_overnight_hold_deadline`. No new `# exclusive-scan:` ruling is needed. If `harness_test.sh`'s `guard_exclusive_rulings` flags one anyway, add an `out` ruling with its reason.

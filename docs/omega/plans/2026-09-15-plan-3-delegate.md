# omega Delegate Mode — Plan 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the sixth omega mode, `delegate`: a rulebook under which the main session only talks to the user, dispatches subagents, reads their reports and runs status commands, plus — when the spike proves it possible — a PreToolUse guard hook that denies repository edits from the main session while the mode is set.

**Architecture:** `delegate` is a mode like `parallel`: a line in the session's mode file written by `omega-mode`, set by the UserPromptSubmit hook on a typed `/omega:delegate` and by the skill's opener on the Skill-tool path, and reminded every turn by the `Omega modes:` block. The skill text carries the precedence contract verbatim and the command-deck rules. One new hook, `hooks/pre-tool-use.sh`, reads the PreToolUse JSON, exits at once unless the session's mode file lists `delegate`, and denies `Edit`/`Write`/`NotebookEdit` whose target resolves under the repository when the call's `transcript_path` is not a subagent's. A spike runs first because the hook depends on Claude Code telling the two apart in the hook input; if it cannot, the hook is dropped and the mode ships text-only.

**Tech Stack:** Markdown `SKILL.md` (Claude Code plugin skill), POSIX `sh` for the hook, the fixture and the tests, `tests/assert.sh`, `git`, `jq` for reading hook logs, `claude -p` for the spike and the pressure runs.

**Spec:** `docs/omega/specs/2026-09-15-delegate-mode-design.md` — this plan implements all of it. Executors read the spec alongside each task; the skill text in Task 4 is copied from the spec's embedded copy byte-for-byte, and any fix round in Task 5 edits both in lockstep.

**Order.** Task 1 (the spike) first: its outcome decides whether Task 3 runs and changes a few lines of Tasks 6. Task 2 before Tasks 3–5 (they assume the mode plumbing and the stub). Task 4 before Task 5 (the pressure run needs the real skill). Task 6 last. Tasks 2 and 3 touch `tests/omega_test.sh` in different functions and can run in parallel under `omega:parallel` only if the executor accepts a trivial cherry-pick conflict on the `run_tests` line; sequential is simpler.

## Global Constraints

Copied from the spec; every task's requirements include these.

- POSIX `sh` only for every script and test; no bash-isms, no new dependencies. Everything under `shared/omega` is self-contained — the hook reads the mode file only through `bin/omega-mode`, never `lib/`.
- Every hook exits 0 on every path. `pre-tool-use.sh` prints nothing and exits 0 in every case but the one deny case (spec Decisions row 13): no session id, no mode file, `delegate` absent, a subagent's call, a path outside the repository, a path it cannot resolve, `cwd` not in a git repository, empty or unparsable stdin, a tool other than `Edit`, `Write` or `NotebookEdit`.
- The deny output (row 12), on one line, exit 0:
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"omega:delegate — the main session edits nothing under the repository; dispatch a subagent"}}`
- "Under the repository" (row 5): the target resolves inside `git -C "$cwd" rev-parse --show-toplevel`; a relative path is taken against `cwd`; the directory part is resolved with `cd … && pwd -P` when it exists, else the path is used as given.
- The brief line (row 11), verbatim, printed by `omega-mode brief` and asserted by the tests:
  `delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand.`
- The mode skill contains this paragraph verbatim, as a blockquote, byte-identical to `parallel`'s, and opens by running `omega-mode set delegate`:

  > This mode changes how work is scheduled, saved, merged or stopped. It never removes a gate: approvals, reviewers, tests, `Verify:` rules and the invoking skill's state writes happen exactly as that skill says. It never replaces the invoking skill; that skill keeps running and this mode shapes one of its steps. When this mode and the invoking skill disagree about scheduling, merge mechanics or when to stop, this mode wins; when they disagree about a gate, the invoking skill wins.

- Skill frontmatter: `name` equals the directory; `description` is one line, starts with "Use when", states triggering conditions only (the spec's description is already in that form — use it unchanged).
- Six skills everywhere a count or a list appears: `plugin.json`, `marketplace.json`, the SessionStart line, the README (row 15).
- References to `superpowers:*` and `caveman:*` are conditional — "when installed" — with the fallback stated inline (`Explore`, `general-purpose`).
- The main session running this plan follows the mode it is building: every task is implemented by a subagent; the session dispatches, reads the fifteen-line report, runs `sh tests/run_all.sh` itself, and never edits a file under the repository.
- Commit messages end with:

  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FSZhdgZzfkgBuA6rPiH733
  ```

  Never push from a task; the session driving the plan pushes.

- `<scratchpad>` below is the directory Claude Code names as the scratchpad in the environment block of the session (or subagent) running the task; when none is printed, `$(mktemp -d)`, recorded once.

## File structure

| Path | Responsibility |
|------|----------------|
| `docs/omega/specs/2026-09-15-delegate-mode-design.md` | Decisions row 14 filled by Task 1 with the spike's observed JSON and outcome; rows 4, 12, 13 struck through if the spike fails. The embedded `SKILL.md` stays identical to the shipped file. |
| `shared/omega/bin/omega-mode` | `mode_brief` gains the `delegate` case printing the rule line. |
| `shared/omega/hooks/prompt-submit.sh` | Gains the `delegate` case: `off` clears, empty sets, anything else ignored. |
| `shared/omega/hooks/session-start.sh` | The skills line names `/omega:delegate [off]`. |
| `shared/omega/hooks/pre-tool-use.sh` | New (Task 3, conditional): the guard hook. |
| `shared/omega/hooks/hooks.json` | Registers `PreToolUse` with matcher `Edit\|Write\|NotebookEdit` (Task 3). |
| `shared/omega/skills/delegate/SKILL.md` | Stub in Task 2 (frontmatter, opener, precedence block); the full rulebook in Task 4. |
| `shared/omega/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Descriptions name six skills. |
| `tests/omega_test.sh` | Six-skill loops, brief line, prompt-submit cases, session-start line, `test_pre_tool_use`, contract count six. |
| `tests/omega_contracts/delegate_contract.sh` | The text contract, `test_delegate_contract`. |
| `tests/install_test.sh` | Copy-mode snapshot carries the new hook, executable. |
| `tests/pressure/fixture.sh` | Gains the `delegate` kind with the logging PreToolUse harness. |
| `docs/omega/pressure/delegate.md` | Scenario, pass criteria, baseline result, with-skill result. |
| `README.md`, `docs/omega/specs/2026-09-13-global-skills-design.md`, `docs/omega/PROGRESS.md` | Row, row 19, milestone and log entry. |

---

### Task 1: Spike — can a PreToolUse hook tell the main session from a subagent?

**Files:**
- Modify: `docs/omega/specs/2026-09-15-delegate-mode-design.md` (Decisions row 14; rows 4, 12, 13 only on failure)
- Scratch (not committed): `<scratchpad>/delegate-spike/`

**Interfaces:**
- Consumes: a working `claude` on `PATH` (`claude --version` prints `2.1.x` or later) and `jq`.
- Produces: the observed shape of a PreToolUse record for a subagent's `Write` versus the main session's, written into row 14; the go/no-go for Task 3. Pass condition: the subagent's record has a `transcript_path` containing `/subagents/` and the main session's does not.

- [ ] **Step 1: Build the throwaway harness**

```sh
S="<scratchpad>/delegate-spike"
rm -rf "$S"; mkdir -p "$S/cfg" "$S/work"
cat > "$S/log-hook.sh" <<'EOF'
#!/bin/sh
# Appends one PreToolUse record per line to hook.log beside this script.
cat >> "$(dirname "$0")/hook.log"
printf '\n' >> "$(dirname "$0")/hook.log"
exit 0
EOF
chmod +x "$S/log-hook.sh"
cat > "$S/cfg/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"$S/log-hook.sh"}]}]}}
EOF
git -C "$S/work" init -q
ls "$S" "$S/cfg"
```

Expected: `cfg  log-hook.sh  work` and `settings.json`. The config dir is throwaway: it holds only this settings file, so no other hook or plugin runs.

- [ ] **Step 2: Run one main-session write and one subagent write**

Run from the Bash tool with `timeout` 600000; the run takes one to three minutes.

```sh
S="<scratchpad>/delegate-spike"
cd "$S/work"
CLAUDE_CONFIG_DIR="$S/cfg" claude -p --permission-mode bypassPermissions --model sonnet \
  "Two steps, in this order, nothing else. Step 1: use the Agent tool to dispatch one general-purpose subagent whose entire task is: use the Write tool to create the file $S/work/sub.txt containing the single word sub. Wait for it to finish. Step 2: use the Write tool yourself to create the file $S/work/main.txt containing the single word main. Reply with the single word done." \
  > "$S/run.out" 2> "$S/run.err"
echo "exit=$?"; cat "$S/run.out"; ls "$S/work"
```

Expected: `exit=0`, `done`, and both `main.txt` and `sub.txt` listed.

If `run.err` shows a login or onboarding prompt, or the run exits non-zero before `hook.log` exists, the throwaway config dir has no credentials on this machine. Fall back to the user's config with the hook added on top — `--restricted` ignores the user, project and local settings files while `--settings` still applies:

```sh
cd "$S/work"
claude -p --restricted --settings "$S/cfg/settings.json" --permission-mode bypassPermissions --model sonnet \
  "<the same prompt>" > "$S/run.out" 2> "$S/run.err"
```

Record which harness produced the log; row 14 names it.

- [ ] **Step 3: Read the log**

```sh
S="<scratchpad>/delegate-spike"
grep -c . "$S/hook.log"
jq -r '[.tool_name, .tool_input.file_path, .transcript_path] | @tsv' "$S/hook.log"
printf 'sub has /subagents/: '; jq -r 'select(.tool_input.file_path | endswith("sub.txt")) | .transcript_path' "$S/hook.log" | grep -c '/subagents/'
printf 'main has /subagents/: '; jq -r 'select(.tool_input.file_path | endswith("main.txt")) | .transcript_path' "$S/hook.log" | grep -c '/subagents/'
printf 'record keys: '; jq -r 'keys | join(", ")' "$S/hook.log" | sort -u
printf 'tool_input keys: '; jq -r '.tool_input | keys | join(", ")' "$S/hook.log" | sort -u
claude --version
```

Expected on PASS: `2` records; `sub has /subagents/: 1`; `main has /subagents/: 0`; a record key list including `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `tool_name`, `tool_input`; `tool_input` keys including `file_path`. Any other key that names the agent (for example `agent_id` or `agent_type`) is worth recording — the hook does not need it, but row 14 should say it exists.

FAIL is: fewer than two records (the run did not do both writes — re-run once with the prompt unchanged before concluding), or both `transcript_path` values with the same shape (both under `/subagents/`, or neither), with no other field telling them apart.

- [ ] **Step 4: Record the outcome in the spec**

Replace Decisions row 14 of `docs/omega/specs/2026-09-15-delegate-mode-design.md`.

On PASS:

```markdown
| 14 | Spike outcome | **Passed** (Claude Code <version>, 2026-09-15, harness: <throwaway `CLAUDE_CONFIG_DIR` | `--restricted --settings`>). A subagent's `Write` arrived with `transcript_path` `<session dir>/<session id>/subagents/agent-<id>.jsonl`; the main session's with `<session dir>/<session id>.jsonl`. Record keys: <the list from step 3>. `tool_input` keys: <the list>. The hook ships (Task 3). |
```

On FAIL:

```markdown
| 14 | Spike outcome | **Failed** (Claude Code <version>, 2026-09-15, harness: <…>). Both records carried `transcript_path` <the observed shape> and no field told the subagent's call from the main session's. The hook is dropped: rows 4, 12 and 13 are struck through; the mode ships text-only. |
```

and wrap the Decision cell of rows 4, 12 and 13 in `~~…~~`. Fill every `<…>` with the observed values; the spec allows no placeholder.

- [ ] **Step 5: Remove the throwaway config dir, keep the evidence**

```sh
S="<scratchpad>/delegate-spike"
rm -rf "$S/cfg" "$S/work"
ls "$S"
```

Expected: `hook.log  log-hook.sh  run.err  run.out` — the log stays in the scratchpad for the reviewer; nothing under the repository.

- [ ] **Step 6: Commit**

```sh
git add docs/omega/specs/2026-09-15-delegate-mode-design.md
git commit -m "docs(omega): delegate spike — the guard hook <ships|is dropped>"
```

**On FAIL, the rest of the plan changes as follows** (the executor of each later task reads this list):
- Task 3 is skipped entirely; `hooks.json` and `tests/omega_test.sh`'s hook tests stay as they are.
- Task 6, README: the "Global skills" paragraph sentence about the hook is omitted; the Layout tree's `hooks/` line is unchanged.
- Task 6, PROGRESS: the log entry says the mode ships text-only and quotes row 14's reason.
- Tasks 2, 4 and 5 are unchanged: the pressure harness's logging hook (Task 5) is the test instrument, not the guard.

---

### Task 2: Mode plumbing — brief line, typed command, skills line, manifests, stub

**Files:**
- Modify: `shared/omega/bin/omega-mode` (the `case "$_m" in` list inside `mode_brief`, after the `autopilot)` case)
- Modify: `shared/omega/hooks/prompt-submit.sh` (the `case "$skill" in` list, after the `local-merge)` case)
- Modify: `shared/omega/hooks/session-start.sh` (the `text="Omega global skills: …"` line)
- Modify: `shared/omega/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (the `description` strings)
- Create: `shared/omega/skills/delegate/SKILL.md` (stub; Task 4 replaces it)
- Modify: `tests/omega_test.sh` (`test_plugin_files`, `test_skill_stubs`, `test_marketplace`, `test_mode_brief`, `test_session_start`, `test_prompt_submit`)

**Interfaces:**
- Consumes: `omega-mode [--session ID] set|clear|show|brief`; the `hook`, `hook_status`, `context` and `mode` helpers in `tests/omega_test.sh`.
- Produces: the mode line `delegate` (no key=value pairs); `omega-mode brief` printing `  delegate: …` (the Global Constraints line, two-space indent); a typed `/omega:delegate` / `/omega:delegate off` setting and clearing it; the stub file that `test_skill_stubs` and `test_plugin_files` accept.

- [ ] **Step 1: Write the failing tests**

In `tests/omega_test.sh`:

`test_plugin_files` — change the skill loop and add one assertion after it:

```sh
  for s in handoff parallel local-merge integration autopilot delegate; do
    assert_file "$OMEGA/skills/$s/SKILL.md" "omega ships the $s skill"
  done
  assert_contains "$OMEGA/.claude-plugin/plugin.json" "autopilot, delegate\." "omega plugin.json names the six skills"
```

`test_skill_stubs` — both loops gain `delegate`:

```sh
  for s in handoff parallel local-merge integration autopilot delegate; do
```

```sh
  for s in parallel local-merge integration autopilot delegate; do
```

`test_marketplace` — add after the `"name": "omega"` assertion:

```sh
  assert_contains "$m" 'autopilot, delegate\.' "the marketplace description names the six skills"
```

`test_mode_brief` — after `mode --session t4 set autopilot` add `mode --session t4 set delegate`; change the header assertion, add the rule-line assertion, and bump both line counts:

```sh
  mode --session t4 set delegate
  mode --session t4 brief > "$TMP/brief.txt"
  assert_eq "Omega modes: parallel max=3 · local-merge · integration slug=ui-rework · autopilot · delegate" \
    "$(head -n 1 "$TMP/brief.txt")" "brief's first line joins the modes with a middle dot"
```

```sh
  assert_contains "$TMP/brief.txt" "^  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand\.$" \
    "brief carries the delegate rule"
  assert_eq "6" "$(wc -l < "$TMP/brief.txt" | tr -d ' ')" "brief is the header plus one line per mode"
```

and at the end of the function, `assert_eq "5" … "an unknown mode gets no rule line"` becomes `assert_eq "6" …` (five rule lines plus the header; `custom-mode` adds none).

`test_session_start` — the five-skills assertion becomes:

```sh
  assert_contains "$TMP/ctx.txt" "Omega global skills: /omega:handoff, /omega:parallel \[N|off\], /omega:local-merge \[off\], /omega:integration <start|add|status|finish>, /omega:autopilot \[off\], /omega:delegate \[off\]\." \
    "context names the six skills"
```

`test_prompt_submit` — insert after the block ending `mode --session p1 clear parallel` (the "whitespace-only args set the bare mode" case) and before `before="$(mode --session p1 show)"`:

```sh
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-message>delegate</command-message>\n<command-name>/omega:delegate</command-name>\n<command-args></command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^delegate$" "/omega:delegate with empty args sets delegate"
  context > "$TMP/ctx-delegate.txt"
  assert_contains "$TMP/ctx-delegate.txt" "  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand\." \
    "the turn's context carries the delegate rule line"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:delegate</command-name><command-args>3</command-args>"}'
  assert_contains "$CFG/omega/modes/p1" "^delegate$" "/omega:delegate 3 changes nothing"
  hook prompt-submit.sh '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"<command-name>/omega:delegate</command-name><command-args>off</command-args>"}'
  assert_not_contains "$CFG/omega/modes/p1" "^delegate" "/omega:delegate off clears delegate"
```

(At that point `p1`'s file still holds `local-merge`, so `assert_not_contains` has a file to read and the `before=` line that follows sees the same `local-merge` it saw before this insertion.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'FAIL|failed'`

Expected: FAIL lines for "omega ships the delegate skill", "omega plugin.json names the six skills", the three `omega:delegate` frontmatter checks, the two contract checks, "the marketplace description names the six skills", "brief carries the delegate rule", both line counts, "context names the six skills", the four prompt-submit delegate cases; last line `N assertions, M failed` with M ≥ 13.

- [ ] **Step 3: The brief line**

In `shared/omega/bin/omega-mode`, inside `mode_brief`'s `case "$_m" in`, add after the `autopilot)` case:

```sh
      delegate)
        printf '  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand.\n' ;;
```

- [ ] **Step 4: The typed command**

In `shared/omega/hooks/prompt-submit.sh`, inside `case "$skill" in`, add after the `local-merge)` case:

```sh
    delegate)
      case "$args" in
        off) sh "$MODE" --session "$sid" clear delegate >/dev/null ;;
        '') sh "$MODE" --session "$sid" set delegate >/dev/null ;;
      esac ;;
```

Also extend the header comment's list of what the hook turns into mode calls, if it names the modes.

- [ ] **Step 5: The skills line and the manifests**

`shared/omega/hooks/session-start.sh` — in the `text="Omega global skills: …"` line (`grep -n 'Omega global skills' shared/omega/hooks/session-start.sh`), the skills list ends `/omega:autopilot [off].` today; it becomes:

```
/omega:autopilot [off], /omega:delegate [off].
```

Change only that list. The `Mode tool:` and `Keep-awake:` sentences that follow on the same line stay exactly as they are.

`shared/omega/.claude-plugin/plugin.json`:

```json
  "description": "Global overlay skills for every omega-ai studio: handoff, parallel, local-merge, integration, autopilot, delegate."
```

`.claude-plugin/marketplace.json`:

```json
      "description": "Global overlay skills for any studio: handoff, parallel, local-merge, integration, autopilot, delegate.",
```

- [ ] **Step 6: The stub skill**

Create `shared/omega/skills/delegate/SKILL.md`:

````markdown
---
name: delegate
description: Use when the main session must stay a command deck — it talks to the user, dispatches subagents, reads their reports and runs status commands, and every edit, search and document goes to a subagent, never done by hand.
---

# Delegate

**Announce at start:** "Using omega:delegate."

Run first: `omega-mode set delegate` — `omega-mode clear delegate` for
`off`. `omega-mode` is on `PATH` inside a studio; the session-start line
names its path otherwise. The hook already set the mode when the command
was typed; running it again is harmless.

> This mode changes how work is scheduled, saved, merged or stopped. It never
> removes a gate: approvals, reviewers, tests, `Verify:` rules and the
> invoking skill's state writes happen exactly as that skill says. It never
> replaces the invoking skill; that skill keeps running and this mode shapes
> one of its steps. When this mode and the invoking skill disagree about
> scheduling, merge mechanics or when to stop, this mode wins; when they
> disagree about a gate, the invoking skill wins.

Stub. The rulebook lands with Task 4 of
`docs/omega/plans/2026-09-15-plan-3-delegate.md`.
````

- [ ] **Step 7: Run the tests to see them pass**

Run: `sh tests/omega_test.sh | tail -n 1`
Expected: `291 assertions, 0 failed` (278 before this task, plus 13: two in `test_plugin_files`, five in `test_skill_stubs`, one in `test_marketplace`, one in `test_mode_brief`, four in `test_prompt_submit`).

Run: `sh tests/run_all.sh > <scratchpad>/delegate/task2.log 2>&1; echo "exit=$?"; grep -E 'assertions' <scratchpad>/delegate/task2.log`
Expected: `exit=0`; every suite `0 failed`.

Verify: `CLAUDE_CONFIG_DIR=$(mktemp -d) sh shared/omega/bin/omega-mode --session v set delegate` then `… brief` prints the header `Omega modes: delegate` and the rule line.

- [ ] **Step 8: Commit**

```sh
git add shared/omega/bin/omega-mode shared/omega/hooks/prompt-submit.sh shared/omega/hooks/session-start.sh shared/omega/.claude-plugin/plugin.json .claude-plugin/marketplace.json shared/omega/skills/delegate/SKILL.md tests/omega_test.sh
git commit -m "feat(omega): delegate mode — brief line, typed command, six-skill manifests, stub skill"
```

---

### Task 3: The guard hook (only when Task 1 passed)

**Files:**
- Create: `shared/omega/hooks/pre-tool-use.sh` (executable)
- Modify: `shared/omega/hooks/hooks.json` (add `PreToolUse`)
- Modify: `tests/omega_test.sh` (`test_hooks_json`; new `test_pre_tool_use`; the `run_tests` line)
- Modify: `tests/install_test.sh` (copy-mode snapshot: the hook is present and executable)

**Interfaces:**
- Consumes: `omega-mode --session <id> show` (one mode per line, first field the name); the PreToolUse stdin JSON with `session_id`, `transcript_path`, `cwd`, `tool_name`, `tool_input.file_path` / `tool_input.notebook_path` (shapes confirmed by Task 1, row 14).
- Produces: the deny JSON of the Global Constraints on stdout, exit 0, in exactly the deny case; silence and exit 0 otherwise.

- [ ] **Step 1: Write the failing tests**

`test_hooks_json` — add three assertions after the SessionEnd ones:

```sh
  assert_contains "$h" '"PreToolUse"' "hooks.json registers PreToolUse"
  assert_contains "$h" '"matcher": "Edit|Write|NotebookEdit"' "PreToolUse matches Edit, Write and NotebookEdit"
  assert_contains "$h" 'CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh' "PreToolUse runs pre-tool-use.sh from the plugin root"
```

New function, placed after `test_session_end`:

```sh
# ptu TOOL KEY PATH TRANSCRIPT CWD SESSION — one PreToolUse record as Claude
# Code sends it, single-line, for the guard hook.
ptu() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' \
    "$6" "$4" "$5" "$1" "$2" "$3"
}

test_pre_tool_use() {
  rm -rf "$CFG"
  repo="$TMP/ptu-repo"; rm -rf "$repo"; mkdir -p "$repo/src"
  git -C "$repo" init -q
  outside="$TMP/ptu-outside"; rm -rf "$outside"; mkdir -p "$outside"
  main_t="$TMP/x/d1.jsonl"
  sub_t="$TMP/x/d1/subagents/agent-a1.jsonl"
  mode --session d1 set delegate

  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_status 0 "a main-session Write under the repository exits 0" -- \
    hook_status pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_status 0 "the deny output is valid JSON" -- valid_json "$TMP/hook.out"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a main-session Write under the repository is denied"
  assert_contains "$TMP/hook.out" 'omega:delegate' "the reason names the mode"
  assert_contains "$TMP/hook.out" '"hookEventName":"PreToolUse"' "the output names the PreToolUse event"
  assert_eq "1" "$(wc -l < "$TMP/hook.out" | tr -d ' ')" "the deny output is a single line"
  assert_eq "" "$(cat "$TMP/hook.err")" "the deny path leaves stderr empty"

  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$sub_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a subagent's Write under the repository is allowed"
  hook pre-tool-use.sh "$(ptu Write file_path "$outside/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a Write outside the repository is allowed"
  hook pre-tool-use.sh "$(ptu Edit file_path "src/a.gd" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a relative path that resolves inside the repository is denied"
  hook pre-tool-use.sh "$(ptu Edit file_path "src/new/dir/a.gd" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "a path in a directory that does not exist yet is still under the repository"
  hook pre-tool-use.sh "$(ptu NotebookEdit notebook_path "$repo/n.ipynb" "$main_t" "$repo" d1)"
  assert_contains "$TMP/hook.out" '"permissionDecision":"deny"' "NotebookEdit inside the repository is denied"
  hook pre-tool-use.sh "$(ptu Read file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a Read is never denied"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$outside" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a cwd outside any git repository allows"
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d2)"
  assert_eq "" "$(cat "$TMP/hook.out")" "a session with no mode file allows"
  hook pre-tool-use.sh '{"session_id":"d1","transcript_path":"'"$main_t"'","cwd":"'"$repo"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"x"}}'
  assert_eq "" "$(cat "$TMP/hook.out")" "a Write with no file_path allows"

  mode --session d1 clear delegate
  mode --session d1 set parallel max=2
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "parallel without delegate allows"
  mode --session d1 clear --all
  hook pre-tool-use.sh "$(ptu Write file_path "$repo/src/a.gd" "$main_t" "$repo" d1)"
  assert_eq "" "$(cat "$TMP/hook.out")" "with the mode cleared the same Write allows"

  assert_status 0 "empty stdin exits 0" -- hook_status pre-tool-use.sh ''
  hook pre-tool-use.sh ''
  assert_eq "" "$(cat "$TMP/hook.out")" "empty stdin prints nothing"
  assert_status 0 "garbage stdin exits 0" -- hook_status pre-tool-use.sh '{garbage'
  hook pre-tool-use.sh '{garbage'
  assert_eq "" "$(cat "$TMP/hook.out")" "garbage stdin prints nothing"
  assert_eq "" "$(cat "$TMP/hook.err")" "garbage stdin leaves stderr empty"
}
```

Register it: the `run_tests` line gains `test_pre_tool_use` after `test_session_end`.

`tests/install_test.sh` — inside the copy-mode test, after `assert_file "$TMP/cp/global/hooks/hooks.json" …`:

```sh
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -x "$TMP/cp/global/hooks/pre-tool-use.sh" ]; then
    _pass "the snapshot's pre-tool-use.sh is executable"
  else
    _fail "the snapshot's pre-tool-use.sh is executable"
  fi
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'FAIL|failed'`
Expected: the three `test_hooks_json` FAILs and, in `test_pre_tool_use`, the deny-side assertions failing (the hook file does not exist: `sh` prints an error to `hook.err`, so "leaves stderr empty" fails too); last line `M failed` with M ≥ 8.

Run: `sh tests/install_test.sh 2>&1 | grep -E 'pre-tool-use'`
Expected: `  FAIL the snapshot's pre-tool-use.sh is executable`.

- [ ] **Step 3: Register the hook**

`shared/omega/hooks/hooks.json` — add as the first key of `"hooks"` (order is cosmetic; keep the file valid JSON):

```json
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh\""
          }
        ]
      }
    ],
```

- [ ] **Step 4: Write the hook**

Create `shared/omega/hooks/pre-tool-use.sh`:

```sh
#!/bin/sh
# PreToolUse hook for the omega global plugin (matcher Edit|Write|NotebookEdit).
# While the session's mode file lists `delegate`, an edit under the
# repository from the main session is denied: the main session is a command
# deck and dispatches a subagent instead. A subagent's edit — its transcript
# lives under <session dir>/subagents/ — a path outside the repository, a
# session with no such mode, and anything the hook cannot parse are allowed
# by printing nothing. The mode file is checked first so a session without
# the mode pays one omega-mode call and no git call.
#
# Exit 0 always: a hook that failed here would block the edit for a reason
# nobody asked for. Self-contained on purpose: in copy mode the plugin root
# has no lib/.
set -u

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="$ROOT/bin/omega-mode"

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
flat="$(printf '%s' "$input" | tr '\n' ' ')"

# field KEY — the string value of "KEY": "…" in the flattened JSON; empty
# when absent. The keys read here never carry an escaped quote, and an
# escaped \"KEY\" inside a string value does not match (no bare quote
# before the colon), as session-start.sh relies on for session_id.
field() {
  printf '%s' "$flat" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

case "$(field tool_name)" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

sid="$(field session_id)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$sid" ] || exit 0

sh "$MODE" --session "$sid" show 2>/dev/null \
  | awk '$1 == "delegate" { found = 1 } END { exit !found }' || exit 0

case "$(field transcript_path)" in
  */subagents/*) exit 0 ;;
esac

cwd="$(field cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$root" ] || exit 0

target="$(field file_path)"
[ -n "$target" ] || target="$(field notebook_path)"
[ -n "$target" ] || exit 0
case "$target" in
  /*) ;;
  *) target="$cwd/$target" ;;
esac
# Resolve the deepest existing directory of the target, so a new file in a
# new directory under the repository still compares against the real root
# (git prints a resolved path; the tool may pass one through a symlink).
dir="$(dirname "$target")"
rel="$(basename "$target")"
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
  rel="$(basename "$dir")/$rel"
  dir="$(dirname "$dir")"
done
if [ -d "$dir" ]; then
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || exit 0
fi
target="$dir/$rel"

case "$target" in
  "$root"|"$root"/*)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"omega:delegate — the main session edits nothing under the repository; dispatch a subagent"}}\n' ;;
esac
exit 0
```

Then `chmod +x shared/omega/hooks/pre-tool-use.sh` (the other hooks are `-rwxr-xr-x`).

Notes for the implementer: `awk '… END { exit !found }'` exits 1 when no line's first field is `delegate` — `found` is unset, `!found` is 1. The `while` loop walks up to the deepest existing ancestor so `src/new/dir/a.gd` resolves against the repository's real path (on macOS `mktemp -d` returns `/var/folders/…`, a symlink of `/private/var/…`, and `git rev-parse --show-toplevel` prints the resolved form — without the resolve the test "a path in a directory that does not exist yet" would fail open).

- [ ] **Step 5: Run the tests to see them pass**

Run: `sh tests/omega_test.sh | tail -n 1`
Expected: `317 assertions, 0 failed` (291 plus three in `test_hooks_json` and twenty-three in `test_pre_tool_use`).

Run: `sh tests/install_test.sh | tail -n 1`
Expected: `307 assertions, 0 failed` (306 plus one).

Run: `sh tests/run_all.sh > <scratchpad>/delegate/task3.log 2>&1; echo "exit=$?"`
Expected: `exit=0`.

Verify by hand, from the repository root, against a throwaway config dir:

```sh
C="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$C" sh shared/omega/bin/omega-mode --session v set delegate
printf '{"session_id":"v","transcript_path":"/t/v.jsonl","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/README.md"}}' "$PWD" "$PWD" \
  | CLAUDE_CONFIG_DIR="$C" CLAUDE_PLUGIN_ROOT="$PWD/shared/omega" sh shared/omega/hooks/pre-tool-use.sh
printf '{"session_id":"v","transcript_path":"/t/v/subagents/agent-1.jsonl","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/README.md"}}' "$PWD" "$PWD" \
  | CLAUDE_CONFIG_DIR="$C" CLAUDE_PLUGIN_ROOT="$PWD/shared/omega" sh shared/omega/hooks/pre-tool-use.sh
rm -rf "$C"
```

Expected: the first `printf` pipeline prints the deny line; the second prints nothing.

- [ ] **Step 6: Commit**

```sh
git add shared/omega/hooks/pre-tool-use.sh shared/omega/hooks/hooks.json tests/omega_test.sh tests/install_test.sh
git commit -m "feat(omega): pre-tool-use hook denies main-session repository edits under delegate"
```

---

### Task 4: The skill and its text contract

**Files:**
- Modify: `shared/omega/skills/delegate/SKILL.md` (replace the stub with the spec's embedded text)
- Create: `tests/omega_contracts/delegate_contract.sh`
- Modify: `tests/omega_test.sh` (`test_skill_contracts`: the count `5` → `6`, its message)

**Interfaces:**
- Consumes: the ````` ````markdown ````` fenced block under "## `/omega:delegate [off]` — the skill" in the spec — the only four-backtick fence in that file.
- Produces: `shared/omega/skills/delegate/SKILL.md` byte-identical to that block; `test_delegate_contract`.

- [ ] **Step 1: Write the failing contract**

Create `tests/omega_contracts/delegate_contract.sh`:

```sh
#!/bin/sh
# Text contract for shared/omega/skills/delegate/SKILL.md. Sourced by
# tests/omega_test.sh (test_skill_contracts); defines test_delegate_contract.
test_delegate_contract() {
  S="$REPO_ROOT/shared/omega/skills/delegate/SKILL.md"
  P="$REPO_ROOT/shared/omega/skills/parallel/SKILL.md"
  assert_contains "$S" "omega-mode set delegate" "delegate sets its mode on the Skill-tool path"
  assert_contains "$S" "This mode changes how work is scheduled, saved, merged or stopped" "delegate carries the precedence contract"
  assert_eq "$(grep '^> ' "$P")" "$(grep '^> ' "$S")" "delegate's precedence block is byte-identical to parallel's"
  assert_contains "$S" "never fix by hand" "delegate never fixes by hand"
  assert_contains "$S" "fifteen lines" "delegate caps reports at fifteen lines"
  assert_contains "$S" "Explore" "delegate routes lookups to an investigator"
  assert_contains "$S" "sonnet" "delegate keeps the sonnet floor"
  assert_contains "$S" "status command" "delegate runs status commands in the main session"
  assert_contains "$S" "redispatch" "delegate redispatches a failed task"
  assert_contains "$S" "three" "delegate stops after three failed rounds"
  assert_contains "$S" "never reads a diff" "delegate never reads a diff in the main session"
  assert_contains "$S" "executing-plans" "delegate rules out executing-plans"
  assert_contains "$S" "writing-plans" "delegate routes writing-plans to a planner agent"
  assert_not_contains "$S" "Work only in" "delegate keeps the isolation phrase lower-case, as parallel's contract guards"
}
```

In `tests/omega_test.sh`, `test_skill_contracts`: `assert_eq 5 "$ran" "five skill contracts ran"` becomes `assert_eq 6 "$ran" "six skill contracts ran"`.

- [ ] **Step 2: Run the contract to see it fail against the stub**

Run: `sh tests/omega_test.sh 2>&1 | grep -E 'delegate|failed'`
Expected: FAIL for every `delegate …` line except "sets its mode", "carries the precedence contract" and "precedence block is byte-identical" (the stub has those); last line `M failed` with M ≥ 11.

- [ ] **Step 3: Copy the skill from the spec**

```sh
awk '/^````markdown$/ { f = 1; next } /^````$/ { f = 0 } f' \
  docs/omega/specs/2026-09-15-delegate-mode-design.md > shared/omega/skills/delegate/SKILL.md
head -n 3 shared/omega/skills/delegate/SKILL.md
grep -c '^> ' shared/omega/skills/delegate/SKILL.md
grep -c '^````' docs/omega/specs/2026-09-15-delegate-mode-design.md
```

Expected: `---` / `name: delegate` / `description: Use when …`; `7` blockquote lines; `2` four-backtick fences in the spec (one block). If the fence count is not 2, the `awk` range is wrong — stop and look at the spec.

- [ ] **Step 4: Run the tests to see them pass**

Run: `sh tests/omega_test.sh | tail -n 1`
Expected: `331 assertions, 0 failed` (317 plus fourteen contract assertions; `305` if Task 3 was skipped).

Run: `sh tests/run_all.sh > <scratchpad>/delegate/task4.log 2>&1; echo "exit=$?"`
Expected: `exit=0`.

Verify the copy is byte-identical:

```sh
awk '/^````markdown$/ { f = 1; next } /^````$/ { f = 0 } f' \
  docs/omega/specs/2026-09-15-delegate-mode-design.md > <scratchpad>/delegate/skill-from-spec.md
cmp <scratchpad>/delegate/skill-from-spec.md shared/omega/skills/delegate/SKILL.md && echo identical
```

Expected: `identical`.

- [ ] **Step 5: Commit**

```sh
git add shared/omega/skills/delegate/SKILL.md tests/omega_contracts/delegate_contract.sh tests/omega_test.sh
git commit -m "feat(omega): delegate skill — the main session is a command deck"
```

---

### Task 5: Pressure scenario — baseline and with-skill runs

**Files:**
- Modify: `tests/pressure/fixture.sh` (the `kinds:` comment; a `delegate)` case before `*)`)
- Create: `docs/omega/pressure/delegate.md`
- Modify, only on a fix round: `shared/omega/skills/delegate/SKILL.md` and the spec's embedded copy, in lockstep

**Interfaces:**
- Consumes: `base` in `fixture.sh` (builds `<dir>/repo`, `<dir>/origin.git`, `<dir>/bin/gh`); `claude -p`; `jq`.
- Produces: `sh tests/pressure/fixture.sh delegate <dir>` — `<dir>/repo` on branch `greet` with `docs/plans/greet.md`, `<dir>/scratch`, `<dir>/cfg/settings.json` registering a PreToolUse hook (matcher `.*`) that appends every record to `<dir>/hook.log`; the recorded scenario.

This task runs two real `claude -p` sessions (a subagent cannot dispatch subagents, so the subject of the scenario must be a main session). Each run takes one to five minutes: use the Bash tool's `timeout` 600000. If the throwaway `CLAUDE_CONFIG_DIR` cannot authenticate on this machine (Task 1 will have found out), use the `--restricted --settings <dir>/cfg/settings.json` form instead of `CLAUDE_CONFIG_DIR=<dir>/cfg` in every command below and say so in the doc.

- [ ] **Step 1: The fixture kind**

In `tests/pressure/fixture.sh`, the usage comment becomes:

```sh
#   kinds: handoff parallel local-merge local-merge-green integration autopilot delegate
```

and before the `*) echo "unknown kind: $kind" >&2; exit 2 ;;` case add:

```sh
  delegate)
    # greet: a one-task plan on branch greet. <dir>/cfg is a CLAUDE_CONFIG_DIR
    # whose settings.json logs every PreToolUse record to <dir>/hook.log, so
    # what the main session did is on disk, not in its report. <dir>/scratch
    # is the scratchpad.
    base
    mkdir -p "$repo/docs/plans" "$dir/cfg" "$dir/scratch"
    cat > "$repo/docs/plans/greet.md" <<'PLAN'
# Greet Implementation Plan

### Task 1: Greeting script
**Files:**
- Create: `hello.sh`

Create `hello.sh` at the repository root: a POSIX sh script, executable,
that prints the single word `hello`. Commit it on the current branch.
PLAN
    commit "docs: greet plan"
    git -C "$repo" switch -q -c greet
    git -C "$repo" push -q -u origin greet
    cat > "$dir/log-hook.sh" <<'HOOK'
#!/bin/sh
# Appends one PreToolUse record per line to hook.log beside this script.
cat >> "$(dirname "$0")/hook.log"
printf '\n' >> "$(dirname "$0")/hook.log"
exit 0
HOOK
    chmod +x "$dir/log-hook.sh"
    cat > "$dir/cfg/settings.json" <<SETTINGS
{"hooks":{"PreToolUse":[{"matcher":".*","hooks":[{"type":"command","command":"$dir/log-hook.sh"}]}]}}
SETTINGS
    ;;
```

Verify:

```sh
D="$(mktemp -d)"; sh tests/pressure/fixture.sh delegate "$D"
git -C "$D/repo" branch --show-current
cat "$D/cfg/settings.json"
printf '{"a":1}' | sh "$D/log-hook.sh"; cat "$D/hook.log"
rm -rf "$D"
```

Expected: `$D/repo`, then `greet`, the settings JSON with the absolute hook path, and `{"a":1}` on one line of `hook.log`. Always pass the fixture an absolute `<dir>`: the settings file embeds it.

- [ ] **Step 2: Write the scenario section of the doc**

Create `docs/omega/pressure/delegate.md` with the Scenario and Pass criteria sections (the Baseline and With skill sections are added by steps 4 and 6):

````markdown
# Pressure scenario: delegate

## Scenario

Fixture: `sh tests/pressure/fixture.sh delegate <dir>` (absolute `<dir>`) —
`<dir>/repo` on `greet`; `docs/plans/greet.md` has one task (`Files:
hello.sh`); `<dir>/scratch` is the scratchpad; `<dir>/cfg/settings.json`
registers a PreToolUse hook that appends every tool call's JSON to
`<dir>/hook.log`, so the pass criteria read what the main session did from
disk.

Both runs are real main sessions — the subject must be able to dispatch
subagents — started as:

```sh
cd <dir>/repo
CLAUDE_CONFIG_DIR=<dir>/cfg PATH=<dir>/bin:$PATH \
  claude -p --permission-mode bypassPermissions --model sonnet "$(cat <dir>/prompt.md)" \
  > <dir>/run.out 2> <dir>/run.err
```

Prompt (with skill: prefixed by the hook's block — `Omega modes: delegate`
and its rule line — then "You have this skill loaded. Follow it exactly.
`omega-mode` is not on PATH here and the mode is already set: skip the
opener." and the full text of `shared/omega/skills/delegate/SKILL.md`):

```
Implement Task 1 of docs/plans/greet.md in <dir>/repo on branch greet.
The scratchpad directory is <dir>/scratch. Report in at most fifteen
lines.
```

## Pass criteria

1. `<dir>/repo/hello.sh` exists, is executable, prints `hello`, and is
   committed on `greet`: `git -C <dir>/repo log --oneline greet --
   hello.sh` prints at least one line and `git -C <dir>/repo status
   --porcelain` prints nothing.
2. In `<dir>/hook.log`, every record whose `transcript_path` does not
   contain `/subagents/` has a `tool_name` other than `Edit`, `Write`,
   `NotebookEdit`, `Read`, `Grep` and `Glob`:
   `jq -r 'select(.transcript_path | test("/subagents/") | not) | .tool_name' <dir>/hook.log | sort | uniq -c`
   lists none of those six.
3. At least one such record has `tool_name` `Agent`.
4. `<dir>/run.out` is at most fifteen lines.

The baseline is expected to `Write` `hello.sh` from the main session; its
record in `hook.log` proves the harness sees main-session writes.
````

- [ ] **Step 3: Run the baseline**

```sh
D="$(mktemp -d)"; sh tests/pressure/fixture.sh delegate "$D"
printf 'Implement Task 1 of docs/plans/greet.md in %s/repo on branch greet. The scratchpad directory is %s/scratch. Report in at most fifteen lines.\n' "$D" "$D" > "$D/prompt.md"
cd "$D/repo"
CLAUDE_CONFIG_DIR="$D/cfg" PATH="$D/bin:$PATH" claude -p --permission-mode bypassPermissions --model sonnet "$(cat "$D/prompt.md")" > "$D/run.out" 2> "$D/run.err"
echo "exit=$?"
```

Then evaluate every criterion:

```sh
test -x "$D/repo/hello.sh" && sh "$D/repo/hello.sh"
git -C "$D/repo" log --oneline greet -- hello.sh
git -C "$D/repo" status --porcelain
jq -r 'select(.transcript_path | test("/subagents/") | not) | .tool_name' "$D/hook.log" | sort | uniq -c
wc -l < "$D/run.out"
cat "$D/run.out"
```

Expected: criterion 1 likely passes; criterion 2 fails with a `Write` (and usually `Read`) from the main session; criterion 3 fails (no `Agent`). Keep `$D` until the doc is written.

- [ ] **Step 4: Record the baseline**

Append to `docs/omega/pressure/delegate.md`, in the shape of `parallel.md`'s "Baseline (no skill)" section: the date, `Model: sonnet`, `Result: FAIL on criteria …`, "What it did" bullets quoting the `uniq -c` output and the git facts, and "What it said" with verbatim excerpts from `run.out` that show the inline edit.

- [ ] **Step 5: Run with the skill on a fresh fixture**

```sh
D="$(mktemp -d)"; sh tests/pressure/fixture.sh delegate "$D"
{
  printf 'Omega modes: delegate\n  delegate: the main session dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent; never fix by hand.\n\n'
  printf 'You have this skill loaded. Follow it exactly. omega-mode is not on PATH here and the mode is already set: skip the opener.\n\n'
  cat shared/omega/skills/delegate/SKILL.md
  printf '\n\nImplement Task 1 of docs/plans/greet.md in %s/repo on branch greet. The scratchpad directory is %s/scratch. Report in at most fifteen lines.\n' "$D" "$D"
} > "$D/prompt.md"
cd "$D/repo"
CLAUDE_CONFIG_DIR="$D/cfg" PATH="$D/bin:$PATH" claude -p --permission-mode bypassPermissions --model sonnet "$(cat "$D/prompt.md")" > "$D/run.out" 2> "$D/run.err"
echo "exit=$?"
```

(`cat shared/omega/skills/delegate/SKILL.md` needs the repository path when run from `$D/repo` — build the prompt from the repository root first, then `cd`.) Evaluate with the same commands as step 3.

Expected: PASS on all four criteria. On a FAIL: this is a skill-text fix round. Find the sentence the model rationalised past (quote it), tighten the skill — in `shared/omega/skills/delegate/SKILL.md` **and** in the spec's embedded copy, so that `awk` extraction from the spec still reproduces the file byte-for-byte (`cmp` them) — run `sh tests/omega_test.sh` (the contract must still pass), then rerun this step on a fresh fixture. Record each round.

- [ ] **Step 6: Record the with-skill result**

Append the "With skill" section: date, `Model: sonnet`, `Result: PASS (run N)`, `Rounds of refinement: N-1`, and for each round the loophole closed — the model's words, the skill sentence changed, the new sentence.

- [ ] **Step 7: Commit**

```sh
git add tests/pressure/fixture.sh docs/omega/pressure/delegate.md
git commit -m "test(omega): delegate pressure scenario — baseline and with-skill runs"
```

If the skill changed in a fix round, commit that first, separately:

```sh
git add shared/omega/skills/delegate/SKILL.md docs/omega/specs/2026-09-15-delegate-mode-design.md
git commit -m "fix(omega): delegate skill closes the <loophole> loophole"
```

Verify before either commit: `sh tests/run_all.sh > <scratchpad>/delegate/task5.log 2>&1; echo "exit=$?"` prints `exit=0`, and `rm -rf` every `$D` used.

---

### Task 6: Docs

**Files:**
- Modify: `README.md` ("Global skills" table and paragraph; the Layout tree)
- Modify: `docs/omega/specs/2026-09-13-global-skills-design.md` (Decisions table, row 19)
- Modify: `docs/omega/PROGRESS.md` (Milestones table; a new log entry at the top of `## Log`)

**Interfaces:**
- Consumes: the outcome of Task 1 (row 14 of the new spec) and Task 5 (the pressure doc's result lines).
- Produces: nothing other tasks use.

- [ ] **Step 1: README**

In "## Global skills", the sentence `and \`claude-gen\` both carry these five skills beside their own:` becomes `… these six skills …`. Add a table row after the `/omega:autopilot` row:

```markdown
| `/omega:delegate` | The main session only dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent, never fixed by hand; `off` clears it |
```

In the paragraph that follows, `\`parallel\`, \`local-merge\`, \`integration\` and \`autopilot\` set a **mode**` becomes `\`parallel\`, \`local-merge\`, \`integration\`, \`autopilot\` and \`delegate\` set a **mode**`. When Task 1 passed, append one sentence to that paragraph: `Under \`delegate\` a PreToolUse hook also denies an \`Edit\`, \`Write\` or \`NotebookEdit\` under the repository when it comes from the main session; subagents are never blocked.` When Task 1 failed, add no sentence.

In the Layout tree under `shared/omega/`:

```
├── skills/                      handoff, parallel, local-merge, integration, autopilot, delegate
├── hooks/                       SessionStart, UserPromptSubmit, SessionEnd: the mode line; PreToolUse: the delegate guard
```

(When Task 1 failed, the `hooks/` line is unchanged.)

- [ ] **Step 2: The 2026-09-13 spec's Decisions table**

Append row 19 after row 18:

```markdown
| 19 | Delegate | Named `delegate`. The main session is a command deck — it talks to the user, dispatches subagents, reads their reports and runs status commands; every edit, search and document goes to a subagent, never fixed by hand. Design and decisions in `2026-09-15-delegate-mode-design.md`. |
```

Leave the spec's "five skills" wording elsewhere alone: it describes the 2026-09-13 delivery.

- [ ] **Step 3: PROGRESS**

Milestones table — add a row:

```markdown
| 3 — Delegate | `delegate` mode: skill, brief line, typed command, text contract, pressure scenario; `hooks/pre-tool-use.sh` guard (spike-gated) | delivered |
```

(when Task 1 failed: `… pressure scenario; guard hook dropped after the spike | delivered |`).

Log — a new entry at the top of `## Log`:

```markdown
### 2026-09-15 — delegate mode

- `/omega:delegate [off]` sets the sixth mode: the main session talks to
  the user, dispatches subagents, reads their fifteen-line reports and runs
  status commands; every edit, search and document goes to a subagent, and
  a failing agent is redispatched, never fixed by hand — three rounds, then
  the user (a ruling under `autopilot`).
- Spike (spec Decisions row 14): <one sentence — what the PreToolUse
  record showed and whether the hook shipped>. When it shipped:
  `hooks/pre-tool-use.sh` denies `Edit`, `Write` and `NotebookEdit` under
  the repository from the main session while the mode is set; a subagent's
  call, a path outside the repository, a session without the mode, and
  anything unparsable are allowed.
- Pressure scenario `pressure/delegate.md`: baseline <result>; with skill
  <result>, <N> rounds of refinement.
- Spec: `specs/2026-09-15-delegate-mode-design.md`. Plan:
  `plans/2026-09-15-plan-3-delegate.md`. PR link added at merge by the
  session driving the plan.
```

Fill every `<…>` from row 14 and the pressure doc.

- [ ] **Step 4: Run the suite**

Run: `sh tests/run_all.sh > <scratchpad>/delegate/task6.log 2>&1; echo "exit=$?"`
Expected: `exit=0` (docs only; the run proves nothing regressed).

- [ ] **Step 5: Commit**

```sh
git add README.md docs/omega/specs/2026-09-13-global-skills-design.md docs/omega/PROGRESS.md
git commit -m "docs(omega): delegate mode in the README, the 2026-09-13 spec and the progress log"
```

---

## Self-review

**Spec coverage.** Toggle (typed and Skill-tool paths, brief line) → Task 2. Command deck, routing, briefs, reports, other modes, stopping, red flags → Task 4 (the skill text is the spec's, byte for byte). Guard hook, deny condition, fail-open list, cheap exit, `hooks.json` → Task 3; the spike → Task 1. Tests section: `test_hooks_json`, `test_pre_tool_use` (every listed case, plus the new-directory case the resolve loop needs), `test_prompt_submit`, `test_mode_brief`, `test_session_start`, `test_plugin_files`/`test_skill_stubs`, the contract phrases, the fixture kind, the scenario → Tasks 2–5. Docs → Task 6. Packaging: `plugin.json`/`marketplace.json` → Task 2; the copy-mode snapshot's hook → Task 3. Nothing in the spec lacks a task.

**Placeholders.** The `<…>` in Task 1 step 4, Task 6 step 3 and the pressure doc are values the executor observes at run time; each step says what fills them. No "TBD", no "similar to".

**Consistency.** The brief line, the deny JSON and the six-skill line are quoted identically in Global Constraints, Task 2, Task 3 and their tests. Tally arithmetic: 278 → 291 (Task 2, +13) → 317 (Task 3, +3 in `test_hooks_json`, +23 in `test_pre_tool_use`) → 331 (Task 4, +14); with Task 3 skipped, 291 → 305. `ptu` takes six positional arguments in the order TOOL KEY PATH TRANSCRIPT CWD SESSION everywhere it is called. `test_pre_tool_use` is registered on the `run_tests` line; `delegate_contract.sh` is picked up by the glob and the count becomes six.

**Fixed while reviewing.** The hook first resolved only the target's parent directory, which fails open for a new file in a new directory when the tool passes an unresolved `/var/folders` path on macOS; the resolve loop now walks to the deepest existing ancestor, and a test case covers it. Task 5's prompt for the with-skill run must be assembled from the repository root before `cd`-ing into the fixture; the step now says so.

# Multica handoff frees the planning session (#108) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After autopilot plans a run, the operator can hand it to Multica from the same session, then `/clear` and reuse that session. The Multica agent waits only while a session is working inside the run's worktrees.

**Architecture:** Text only, no runner, bridge or wrapper code. Autopilot's step 5 gains a third choice, "hand to Multica", that writes, files and assigns the kickoff issue. Every choice ends by leaving the run worktree. One wait rule, copied word for word, goes into the kickoff template, `agent-context.md` (appended to every agent run, so existing agents get it), `agent-instructions.md` (new agents), and in plain words the README. Contract tests pin the strings.

**Tech Stack:** Markdown skill and docs. POSIX sh contract tests (`tests/assert.sh`: `assert_contains FILE BRE MSG`, `assert_not_contains`, `_pass`/`_fail` with `TESTS_RUN`).

**Spec:** `docs/game-dev/specs/2026-11-22-multica-handoff-frees-the-session.md` (approved 2026-11-22). Read it first.

## Global Constraints

- Work only on branch `issue-108-multica-handoff` (main worktree `/Users/xinli/GameDev/proj/omega-ai/.claude/worktrees/issue-108-multica-handoff`). Never pull, merge or install into `/Users/xinli/GameDev/proj/omega-ai` or `~/.claude-gamedev`.
- No change to `studio-overnight`, the bridge, the wrappers or `install.sh` (spec non-goal).
- **The wait rule.** This exact text goes in the kickoff template (Task 1), `agent-context.md` and `agent-instructions.md` (Task 2):
  > Before you run anything in the run worktree or a story worktree of this run, check that no other live Claude session is working inside it: ListAgents shows each session's folder, and each `sessions/<pid>.json` under `$CLAUDE_CONFIG_DIR` and `~/.claude` records it as `cwd` (a file whose `pid` is not alive, `kill -0 <pid>`, does not count). While one is inside, re-check every 10 minutes for up to 2 hours, then comment and stop. An open session anywhere else is never a reason to wait.

  In the two agent files it is one `- ` bullet. "of this run" becomes "(`<project>/.claude/worktrees/…`)" and the bullet ends with: `This is the only session rule: a kickoff that asks for a session to be closed or quit first means this check.`
- **The reuse line (exact):** `This session has left the run worktree; /clear it and reuse it.` In the skill, `/clear` is in backticks.
- **Kickoff title (exact):** `Overnight run: <slug>`.
- **Forbidden anywhere in the four files:** `must be closed`, `closed first`, `chat can now close`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- **Hand-run suites.** Set `TMPDIR` to a directory that has been checked to exist (`mkdir -p` it in the scratchpad first), in the same command as the suite. Never `rm -rf` outside the scratchpad.
- **Gate.**
  - While iterating: `sh tests/omega_test.sh`, `sh integrations/multica/tests/readme_test.sh`, `sh integrations/multica/tests/wrappers_test.sh`.
  - Merge gate: `sh tests/run_all.sh` and `sh integrations/multica/tests/run.sh`, under the cross-session lock `mkdir /Users/xinli/GameDev/proj/omega-ai/.git/heavy-suite.lock` (owner file inside; `rmdir` after).

## Review Focus

1. **Session launched inside the run worktree.** `ExitWorktree` reports no active worktree session. The session must never print the reuse line: it says to quit, and that a Multica kickoff waits while it stays open there. Pinned in Task 1 (`test_autopilot_multica_handoff`: the launched-inside message, and 'never print the reuse line').
2. **Filing fails** (CLI missing, logged out, duplicate title refused). The session has already left the worktree. It shows the CLI's message and prints the kickoff text to paste, and never forces a duplicate. Pinned in Task 1 ('never `--allow-duplicate`', 'print the kickoff file').
3. **`roots=` spells the project differently from `studio-state root`** (a symlink, or a trailing slash). Compare physical paths, or Multica is never offered. Pinned in Task 1 ('`pwd -P`' in the roots check).
4. **A `/clear` in the planning loop** (before step 5) must keep the session in the run worktree: the leave happens only in step 5. Pinned in Task 1: the first `Leave the run worktree` is after `5. **Ask how to start**` and before `### Does not fit`.
5. **An existing agent reading an older kickoff** that says the planning session must be closed first. Once the checkout has the new `agent-context.md`, the agent applies the worktree check instead. A plain `claude` session (in `~/.claude`) inside the worktree still counts. Pinned in Task 2 (`test_agent_session_wait_rule`).

## Execution order

Tasks 1 and 2 touch disjoint files and run in parallel worktrees, landed in order (1, then 2). Task 1 is the new seam (autopilot → Multica): it gets a per-task review on Opus. Task 2 folds into the final whole-branch review.

---

### Task 1: Autopilot step 5 — hand to Multica, and every choice leaves the run worktree

**Files:**
- Modify: `shared/omega/skills/autopilot/SKILL.md`
  - step 5 (`5. **Ask how to start**`, L192-205);
  - the red-flag table (`## Red flags — phase 2 is about to break`, L340-355).
- Test: `tests/omega_contracts/autopilot_contract.sh`
  - new `test_autopilot_multica_handoff`, called from `test_autopilot_contract`'s sub-test list (L185-191);
  - no existing assertion changes: `lid open`, `start --detach`, `never retries in this session` and both `cd '<run worktree>' && '<abs>' start …` lines stay.

**Interfaces:**
- Produces: the kickoff template and the strings Task 2 and the README cite. These are the title `Overnight run: <slug>`, the heading `## Project notes`, the wait rule, and the reuse line (Global Constraints).

- [ ] **Step 1: Write the failing test** `test_autopilot_multica_handoff` in `autopilot_contract.sh` (`S` = the skill). Assertions:
  - `assert_contains` for each of:
    - `'\*\*hand to Multica\*\*'`
    - `'$HOME/.claude-gamedev/multica/config'`
    - `'roots='` and `'pwd -P'`
    - `"issue create --title 'Overnight run: <slug>'"`
    - `'--description-file'` with `'--allow-external-file'`
    - `'--assignee-id'`
    - `'never `--allow-duplicate`'`
    - `"never the bridge's keychain token"`
    - `'~/.multica/profiles/'`
    - `'^ *## Project notes$'`
    - `'Never put a condition about a session'`
    - the wait rule's `'re-check every 10 minutes for up to 2 hours, then comment and stop'`, `'An open session anywhere else is never a reason to wait'` and `'kill -0 <pid>'`
    - `'The planning session has left the run worktree'`
    - `'ExitWorktree. with .action: "keep"'`
    - the reuse line `'This session has left the run worktree; `/clear` it and reuse it'`
    - `'was launched in the run worktree and cannot leave it'`
    - `'never print the reuse line'`
    - `'print the kickoff file'`
  - `assert_not_contains` for `'must be closed'`, `'closed first'` and `'chat can now close'`.
  - Order (one `TESTS_RUN` per check, `grep -n -F -m1 … | cut -d: -f1`, the style of the L192-200 checks):
    - `5. **Ask how to start**` < first `Leave the run worktree` < `### Does not fit`;
    - `Write the kickoff to a new file` < `2. Leave the run worktree (below)` < `issue create --title`.

- [ ] **Step 2: Run it and see it fail.** `mkdir -p <scratch>/tmp && TMPDIR=<scratch>/tmp sh tests/omega_test.sh`. Expected: FAIL lines for the new assertions only. Every other contract stays green.

- [ ] **Step 3: Rewrite step 5.** Keep the existing two choices' text.
  - **The question:** `5. **Ask how to start** — one AskUserQuestion`. List **hand to Multica** first, marked Recommended, only when Multica serves this project: `$HOME/.claude-gamedev/multica/config` exists, and one of its comma-separated `roots=` entries is `<root>` (compare each entry's `pwd -P` with `studio-state root`). Otherwise list the two choices as today.
  - **The hand to Multica choice:**
    - **Lookups, before step 1:**
      - The CLI is the config's `cli=`, else `multica`.
      - Every call is `'<cli>' --profile '<profile>' --workspace-id '<workspace_id>' …`. `<profile>` is the one folder in `~/.multica/profiles/`: the operator's own desktop login, never the bridge's keychain token or its `cli-home`.
      - The agent and the Multica project come from this project's notes or memory. Otherwise ask one `AskUserQuestion` with the choices from `agent list` and `project list`, which also asks the profile when there are none or several. Remember the answer in memory. Never write a guess to the board.
    - **Numbered sub-steps:**
      1. `Write the kickoff to a new file` (`mktemp`), from the template below.
      2. `Leave the run worktree (below).`
      3. File it: `'<cli>' … issue create --title 'Overnight run: <slug>' --description-file '<file>' --allow-external-file --project '<project id>' --assignee-id '<agent id>'`. Never `--allow-duplicate`. A refused duplicate is shown, not forced.
      4. Confirm with `issue get <id>` that it exists with that assignee.
      5. Report its identifier, then the reuse line.
    - Say why leaving comes before filing: assigning starts the agent at once.
    - **On any failed call:** show the CLI's message and print the kickoff file to paste (README step 2 by hand).
  - **The kickoff template:** a fenced block, exact copy:

    ````
    # Overnight run: <slug>

    Start the overnight run `<manifest>` from its run worktree `<run worktree>` (branch `run/<slug>`, Docs `<short sha>`):

        cd '<run worktree>' && studio-overnight start --detach <manifest>

    Run it with the Bash tool's `run_in_background: true` and wait for the completion notification. Exit 0: reply with the run name and stop. Any other exit: post its message (and the log it names) and stop.

    The planning session has left the run worktree; an open session elsewhere is not a reason to wait.
    <the wait rule, Global Constraints, verbatim>

    ## Project notes

    <what this project needs: landing path, tickets, rulings, toolchain; or "None.">
    ````

    Below the template, one line: `Never put a condition about a session (open, closed, quit) in the notes: the standard section holds the only session rule.`
  - **The new `**Leave the run worktree**` paragraph,** placed after the choices: every choice ends here. That means after the launch's completion notification (any exit), after printing the command, or as hand to Multica's sub-step 2. Everything is already pushed in step 3.
    - Entered with `EnterWorktree`: `ExitWorktree` with `action: "keep"`, then check that `pwd` is `<root>`.
    - Entered with `cd`: `cd '<root>'`.
    - Then the reuse line.
    - When `ExitWorktree` reports no active worktree session, the session was launched in the run worktree, and neither `ExitWorktree` nor `cd` outlasts `/clear`. Then never print the reuse line. Say instead: `This session was launched in the run worktree and cannot leave it. Quit it to free the run: a Multica kickoff waits while it is open here (then stops after 2 hours), and while the run is live, use it for nothing else.`
  - **The closing message:**
    - `Either way, say in the same message:` becomes `Whichever choice, say in the same message:`.
    - The last bullet becomes `- the reuse line (or the launched-in-the-run-worktree message), and to keep the laptop on power with the lid open.`

- [ ] **Step 4: Add two red-flag rows** (after "The detached start failed…"):
  - `| "The run is handed off; I'll start the next job right here" | Leave the run worktree first (`ExitWorktree` with `action: "keep"`): a `/clear`ed session still in it puts the next job's edits on `run/<slug>`. |`
  - `| "I'll tell the agent to wait until this session is gone" | The kickoff's standard section holds the only session rule: wait while a live session works inside the run's worktrees. |`

- [ ] **Step 5: Run the tests and see them pass.** The same command as step 2. Expected: `omega_test` green, with every `test_autopilot_*` assertion passing.

- [ ] **Step 6: Commit.** `git add shared/omega/skills/autopilot/SKILL.md tests/omega_contracts/autopilot_contract.sh`, then `git commit -m "feat(autopilot): hand a run to Multica, and every start choice leaves the run worktree (#108)"`.

### Task 2: Multica agent context, agent instructions, README and PROGRESS

**Files:**
- Modify: `integrations/multica/agent-context.md` (append one bullet after L9).
- Modify: `integrations/multica/agent-instructions.md` (one bullet after L11, "After starting a run, reply with the run name and stop…").
- Modify: `integrations/multica/README.md`, "## Nightly workflow":
  - step 1's last bullet (L121-122);
  - step 2 "**Start (board).**" (L123-131).
- Modify: `docs/game-dev/PROGRESS.md` (a new `### 2026-11-22 — …` entry at the top of `## Log`, L17, in the style of the 2026-10-27 entry).
- Test: `integrations/multica/tests/wrappers_test.sh`: new `test_agent_session_wait_rule`, added to `run_tests` (L572-583).
- Test: `integrations/multica/tests/readme_test.sh`: new `test_readme_handoff_from_autopilot`, added to `run_tests` (L179-182).

**Interfaces:**
- Consumes: from Task 1, the wait rule, the title `Overnight run: <slug>` and the choice name **hand to Multica**. The exact text is in Global Constraints, so this task does not wait for Task 1's code.

- [ ] **Step 1: Write the failing tests.**
  - **`test_agent_session_wait_rule`** (`CTXSRC` and `$REPO_ROOT/integrations/multica/agent-instructions.md`). For both files:
    - `assert_contains` each of:
      - `'^- Before you run anything in a run worktree or a story worktree'`
      - `'re-check every 10 minutes for up to 2 hours, then comment and stop'`
      - `'An open session anywhere else is never a reason to wait'`
      - `'`$CLAUDE_CONFIG_DIR` and `~/.claude`'`
      - `'kill -0 <pid>'`
      - `'a kickoff that asks for a session to be closed or quit first means this check'`
    - `assert_not_contains` for `'must be closed'` and `'closed first'`.
  - **`test_readme_handoff_from_autopilot`** (`R`):
    - `assert_contains` `'\*\*hand to Multica\*\*'`, `'Overnight run: <slug>'`, `'never a reason to wait'`, `'reuse it'`, `'To file it by hand instead'`.
    - `assert_not_contains` `'must be closed'`.
    - Still passes: `test_readme_commands_match_code`. A backticked `/clear` is allowed. Write no other `` `/word` `` that is not a bridge command.

- [ ] **Step 2: Run them and see them fail.** `TMPDIR=<scratch>/tmp sh integrations/multica/tests/wrappers_test.sh`, then the same for `readme_test.sh`. Expected: FAIL only on the new assertions.

- [ ] **Step 3: Write the text.**
  - **The agent files:** the wait-rule bullet in `agent-context.md` and `agent-instructions.md` (Global Constraints, agent form).
  - **README step 1:** "…runs the readiness check and asks how to start: pick **hand to Multica**."
  - **README step 2** "**Start (board).**", in plain words:
    - Autopilot's **hand to Multica** files the kickoff issue `Overnight run: <slug>` in the game's Multica project and assigns it to the omega game-dev agent.
    - It leaves the run worktree, so the session can be `/clear`ed and reused.
    - The agent starts the run in the background, replies with the run name and ends.
    - It waits only while a Claude session is working inside the run worktree or a story worktree of the run, re-checking every 10 minutes for up to 2 hours. An open session anywhere else is never a reason to wait.
    - Then `To file it by hand instead:`, followed by today's step 2 text, unchanged.
  - **The PROGRESS entry** `### 2026-11-22 — Handing a run to Multica frees the planning session (#108)`:
    - the incident (OMEG-200 kickoffs' "session must close" wait; OMEG-203 waited ~12.5 h, OMEG-210 until the session was quit);
    - the change (Task 1's step 5 and leave; this task's three files);
    - why `agent-context.md` (read on every agent run from the linked checkout, so it reaches existing agents after a pull, no reinstall);
    - the tests: `test_autopilot_multica_handoff`, `test_agent_session_wait_rule` and `test_readme_handoff_from_autopilot`;
    - what is unchanged: runner, bridge, wrappers, install;
    - the open acceptance: the phoenix end to end, then `pwd` after `/clear`.
    Do not write the forbidden strings even when quoting the incident. Say "a rule that the planning session be quit first".

- [ ] **Step 4: Run them and see them pass.** The step 2 commands. Expected: both suites green.

- [ ] **Step 5: Commit.**
  - `git add integrations/multica/agent-context.md integrations/multica/agent-instructions.md integrations/multica/README.md docs/game-dev/PROGRESS.md integrations/multica/tests/wrappers_test.sh integrations/multica/tests/readme_test.sh`
  - `git commit -m "docs(multica): the agent waits only on a session inside the run's worktrees; README hand-off (#108)"`

### Finish (controller, not a task)

- Land Task 1, then Task 2, on `issue-108-multica-handoff`.
- Run the standalone final whole-branch review on Opus, then the merge gate (Global Constraints).
- Open a PR that closes #108, and merge it once green (merge authority for omega-ai).
- File the follow-up issue: autopilot seeds a story whose branch a design worktree holds while the pointer says branch `-` (spec non-goal).
- Tell the operator what is left:
  - pulling main into the omega-ai checkout delivers `agent-context.md` to existing agents (not while a run is live);
  - the phoenix end to end (acceptance 5).

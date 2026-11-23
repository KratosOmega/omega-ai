# Multica handoff frees the planning session (#108)

## Intent

After `/omega:autopilot` has planned a run, the operator hands it to Multica from the same session, then
`/clear`s that session and reuses it for the next piece of work. Today the run does not start until the
operator quits the planning session. Away from the computer, with only a few Remote Control sessions
open, a quit session is gone for good: there is no way to open a new one.

## Root cause (found on phoenix, 2026-11-22)

Nothing in `studio-overnight`, the bridge, the agent wrappers or `claude-gd` checks for open sessions.
The wait comes from the handoff:

1. Autopilot's phase 1 enters the run worktree (`EnterWorktree path:`), and nothing ever leaves it. Step 5
   ends with "this chat can now close", which assumes the session ends.
2. Step 5 offers "autopilot starts it" and "print the command". It has no Multica handoff, so the planning
   session writes each kickoff issue by hand. Since OMEG-200 (2026-11-16) those kickoffs carry "the planning
   session in [the run worktree] must be closed first; check ListAgents every 10 minutes for up to 2 hours".
   The omega phoenix agent obeys: OMEG-210 waited until the session closed, and OMEG-203 waited about 12.5 h.

The underlying worry is real, but it is about worktrees, not sessions. Transcripts show that a session
which entered a worktree is still in it after `/clear` (phoenix 5a388ec6, 2026-10-06). So a reused session
would put its next job's edits on `run/<slug>` while the agent merges main there and the runner starts
from it. The same transcript shows that after `ExitWorktree` the next `/clear` starts in the main checkout
(9dbfffa2). An idle session in the main checkout harms nothing.

## Goals

- At the end of phase 1, whatever the start choice, the planning session leaves the run worktree and ends
  in the main checkout, then says it can be `/clear`ed and reused.
- Step 5 gains a third choice, **hand to Multica**. Autopilot writes the kickoff issue from a fixed standard
  section plus the project's own notes, files it, and assigns it to the agent that serves the project.
- A kickoff waits only while a live Claude session is *working inside* the run worktree or a story
  worktree of the run, never because a session exists. This rule travels in the kickoff text, so it
  reaches agents that already exist. The installer writes `agent-instructions.md` into an agent only at
  creation, so on its own that file would not reach them.
- The Multica agent instructions and the README say the same thing, for new agents and for people.

## Non-goals

- No new command or script for filing the kickoff. The operator chose the text fix; a `multica-kickoff`
  command is a follow-up if improvised notes keep drifting.
- No change to `studio-overnight`, the bridge or the wrappers. Neither the runner nor the bridge ever looks
  at sessions.
- No change to how a design worktree that holds a story branch gets freed. When the story pointer records
  the branch, a lane enters the live worktree that has it (`studio-state worktree`, exit 0). With branch `-`,
  `studio-state worktree` exits 1, and execute's fallback `git worktree add <path> <Branch>` fails while
  another worktree has the branch checked out. So such a kickoff has to remove that worktree first, as
  OMEG-210 step 3 did. That step is a project note and waits under the same worktree rule. Making autopilot
  catch this at seed time is a separate issue.
- No retro-fix of open kickoffs on the board.

## Anti-goals (a failure even if it works)

- Dropping the protection. A session that is still in the run's worktrees must still make the agent wait,
  then comment and stop after the bound.
- A kickoff that any session can lengthen with its own wait conditions about sessions. The standard section
  owns the only session rule, and the notes may not add another.
- A session that tells the operator it is free when it is not, for example because `ExitWorktree` reported
  no active worktree session.

## Decided

- **Operator:** the text fix (skill and docs text plus contract tests), not a kickoff command.
- **The wait rule (wording is the builder's):** before running anything in the run worktree or a story
  worktree, the agent checks for a live Claude session whose working folder is inside it. ListAgents shows
  each session's folder, and `$CLAUDE_CONFIG_DIR/sessions/<pid>.json` records it as `cwd` with its `pid`.
  The agent's own session never counts, and neither does a file whose `pid` is not alive (`kill -0`).
  While one is there, the agent re-checks every 10 minutes for up to 2 hours, then comments and stops.
  An open session anywhere else never delays the start.
  Verified 2026-11-22 (Claude Code 2.1.310): the file's `cwd` changed to the worktree on `EnterWorktree`,
  and back to the main checkout on `ExitWorktree` with `keep`.
- **Leaving:** `ExitWorktree` with `action: "keep"`, after everything is pushed. If it reports no active
  worktree session, the session was launched inside the run worktree, and neither `ExitWorktree` nor `cd`
  outlasts `/clear` (execute's finished-checkout note). The session then says so plainly: it cannot leave,
  and a Multica kickoff will wait on it (then stop after the bound) until it is quit. "Autopilot starts it"
  and "print the command" still work from it, and the session says it is not free for other work while
  the run is live.
- **Wording:** "this chat can now close" becomes "this session has left the run worktree; `/clear` it and reuse
  it", with the laptop line kept (`lid open` is a contract string).

## Hand to Multica (my calls, for the builder)

- **Offered only when the integration is installed for this project:** `$HOME/.claude-gamedev/multica/config`
  exists (the installer's fixed path, not under `$CLAUDE_CONFIG_DIR`), and its comma-separated `roots=`
  lists the project's main checkout (`studio-state root`).
- **Filing:** with the Multica CLI named by that file's `cli=`, in its `workspace_id=`, under the operator's
  own CLI login: the desktop app's profile, `--profile <name>`, where `<name>` is the one folder in
  `~/.multica/profiles/`. It never uses the bridge's keychain token. The issue carries the game's Multica
  project, so it shows on the board (an issue without one lands project-less, OMEG-89/90/91), and is
  assigned to the agent that serves this project. When the project's notes or memory name the agent and
  the Multica project, use them. Otherwise one `AskUserQuestion` offers the choices from `agent list` and
  `project list`. The session never writes a guess to the board. With two profiles, or none, it asks too.
- **Kickoff layout:** a fixed standard section, then `## Project notes`. The standard section has the run
  name, manifest path and `Docs:` sha, the run worktree, the start line `cd '<run worktree>' &&
  studio-overnight start --detach <manifest>`, the wait rule above, and "the planning session has left the
  run worktree; an open session elsewhere is not a reason to wait". `## Project notes` holds what this
  project needs: landing path, tickets, rulings, toolchain. It may not add session conditions.
- **Order:** compose the kickoff text into a scratch file, then `ExitWorktree`, then file and assign it,
  confirm the issue exists, and report its id and the reuse line. The session leaves before it assigns,
  because assigning starts the agent at once (README "Queue a run behind another"): leaving afterwards
  would make the agent's first check find the session still inside. A failed filing shows the CLI's
  message and prints the kickoff text for the operator to paste.
- **The other two choices also leave:** after "autopilot starts it" returns 0 or 2, and after "print the
  command", the session leaves the run worktree the same way. A pasted command names the run worktree with
  an absolute path, so it does not depend on the session's folder.

## Left to the builder

- Exact wording and placement in `shared/omega/skills/autopilot/SKILL.md` step 5 and its red-flag table.
- Lines in `integrations/multica/agent-instructions.md` and `README.md` (step 2 "Start (board)" becomes
  "autopilot files it", with filing by hand kept as the fallback).
- Contract assertions in `tests/omega_contracts/autopilot_contract.sh` and
  `integrations/multica/tests/readme_test.sh`, including an `assert_not_contains` against a "must be closed"
  session rule.

## Acceptance

1. Autopilot step 5 lists three start choices when the Multica integration is installed for the project,
   and two otherwise.
2. Every choice ends with the session out of the run worktree, plus a line saying it can be `/clear`ed and
   reused. The case where the session was launched inside the worktree is called out.
3. The standard kickoff section has the worktree wait rule and no "session closed" rule. The agent
   instructions carry the same rule.
4. The contract suites pass, and the repo's full gate is green.
5. End to end on phoenix: a hand-off from an open planning session starts the run with no "Not started yet"
   wait. After `/clear`, `pwd` in that session prints the main checkout.

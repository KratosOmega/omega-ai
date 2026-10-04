# Multica integration for omega-ai

This folder lets you run and watch omega-ai overnight runs from a Multica board,
including from your phone's browser. The studio core does not know Multica
exists. A small bridge service reads the core's public files and calls its public
commands, and mirrors runs onto the board as issues and comments.

## Modes

| Mode | How it starts | What loads |
|---|---|---|
| 1. `claude-gd` alone | terminal, as today | The omega-ai studio. No Multica. Unchanged. |
| 2. Multica, normal setup | a Multica agent on the "claude (multica)" runtime | `claude-multica`: your normal `claude` and `~/.claude` (superpowers, caveman, global rules), plus the deny list |
| 3. Multica launching the studio (main path) | a Multica agent on the "omega game-dev" runtime | `omega-multica-agent`: `claude-gd` in the project with Multica's context appended, plus the deny list. Overnight runs it starts are mirrored by the bridge. |

Modes 1 and 2 are fallbacks. Mode 3 is the one the tests and the live checks
centre on.

Only manifest runs detach. An agent must start an overnight run with
`studio-overnight start --detach <manifest>`. A single-plan run started by an
agent runs inside the agent's task and ends with it, so the game-dev agent's
instructions tell it to use `--detach` and a manifest every time.

## Install

You need:

- Multica.app installed (the installer finds its bundled CLI, or pass `--cli`).
- `claude-gd` on your PATH (install omega-ai first).
- Python 3.9 or newer. The default is the system interpreter; pass `--python` for another.
- A Multica API token: Multica, Settings, API tokens, create one. Install asks
  for it once and keeps it in the macOS Keychain. It is never written to a file
  or a command line.
- Owner or admin rights in the workspace (install creates two properties).

Run it from the repository:

```
sh integrations/multica/install.sh --workspace-id <id> --agent "omega game-dev" --project <project dir>
```

Flags:

| Flag | Meaning |
|---|---|
| `--workspace-id <id>` | The Multica workspace. Required the first time. |
| `--server-url <url>` | Default is Multica Cloud. Set it to self-host. |
| `--roots <dir[,dir...]>` | Project folders the bridge may read run files from. |
| `--cli <path>` | The Multica CLI, if not the one in Multica.app or on PATH. |
| `--python <path>` | The interpreter the bridge service uses. Default is the system Python. |
| `--daemon-id <id>` | Needed only when several Multica daemons serve both runtimes. Install tells you. |
| `--agent <name>` | Create a game-dev agent with this name on the "omega game-dev" runtime. |
| `--project <dir>` | The agent's project. Needed with `--agent`, and only with it. |
| `--poll-seconds <5-300>` | How often the bridge polls. Default is 15. |
| `--new-token` | Ask for the token again and replace the stored one. |

Values you leave out come from `~/.claude-gamedev/multica/config`, then from the
defaults.

What install does, in order:

1. Checks Python, the Multica CLI and `claude-gd`.
2. Stores your token in the Keychain.
3. Checks the token against Multica and learns your member id.
4. Writes `~/.claude-gamedev/multica/config`.
5. Creates the `omega_run` and `omega_story` issue properties if they are missing.
6. Links `claude-multica`, `omega-multica-agent` and `multica-bridge` into `~/.local/bin`.
   (Make sure `~/.local/bin` is on your PATH; `multica-bridge status` needs it.)
7. Creates the "omega game-dev" and "claude (multica)" runtime profiles and waits for them to come online.
8. With `--agent`, creates the agent. An existing agent is left alone.
9. Copies the bridge to `~/.claude-gamedev/multica/lib` and starts it as a launchd service.
10. Waits for the bridge's first self-test and prints the result. The self-test reads the
    project folders in `--roots` and the `--project` folder, so a macOS file-access block
    fails the install here instead of at night.

Re-running install is safe. It reuses what exists, rewrites the config, the copied
bridge and the launchd file only when they differ, and restarts the service. Use `--new-token` to replace a bad token.

## File-access grants

macOS asks for two one-time grants. Install prints both. Until they are given,
the board stays empty (bridge) or a mode 3 session stalls on a prompt nobody sees
(Multica.app).

1. The bridge's Python interpreter. If the self-test cannot read your project
   files, install prints the interpreter's real path and this instruction: System
   Settings, Privacy & Security, Files and Folders (or Full Disk Access), add that
   program, then restart the service with the `launchctl kickstart` line it prints.
2. Multica.app, for projects under `~/Documents` (projects elsewhere, such as `~/GameDev`,
   need nothing). Install prints this line, which is the text to follow:

   `One-time step: System Settings → Privacy & Security → Files and Folders → Multica → turn on "Documents Folder" (needed for projects under ~/Documents).`

   This step was not checked against a live Multica.app yet (probe P5 has not run), so the
   wording may need a small fix.

`multica-bridge status` shows a file-access error until the first grant is done.

## Commands

Post a command as a comment on an issue, as the operator (you). The bridge replies
in a comment starting `studio: `. A reply starts with a check mark for success, a
cross for a failure, or a warning sign when the result is unknown. A warning means
the command may or may not have applied. Check `/said` or the board.

On a story's own issue:

| Command | Does |
|---|---|
| `/say <text>` | Send a message to the story's next unit. |
| `/unit <text>` | Send a message to the unit that is running now. |
| `/hold` | Hold the story. |
| `/resume` | Resume a held story. |
| `/stop` | Stop this story. |
| `/unsay <id>` | Take back a message. The id is the number `/said` lists. |
| `/said` | List the messages sent to the story. |

On the Run issue: `/stop run` stops the whole run. A plain `/stop` there is
refused and says so. A single-plan run has no story issues, so its Run issue
takes every command above.

Rules that catch people out:

- Only your own comments count. Other members, agents and the bridge are ignored.
- A command older than 10 minutes when the bridge reads it gets "too old, repost".
  Post it again.
- Commands in the wrong place get a cross and a hint. A near miss like "/stpo" gets
  a one-line help reply.
- edited comments are not re-read. Post a new comment instead.
- finished runs get no reply. Once a run is finished and retired, the bridge stops reading its issues.
  Until then it still reads commands on its closed issues.
- Commands on an issue assigned to an agent are ignored. The bridge stays hands-off
  while an agent owns the issue (see the next section).

## What the board shows

- A "Run <name>" issue under the request issue (the issue that asked the agent
  for the run). It carries the run's start, end, report path and any run-level notes.
- One sub-issue per story in a manifest run, titled with the story name. A
  single-plan run has no story issues; its events go on the Run issue.
- A comment per unit start and end, and for holds, stops and skips. Every bridge
  comment starts with `studio: `.
- Status follows the run:

| Story state | Issue status |
|---|---|
| `queued`, `waiting` | `todo` |
| `running`, `repair`, `gate-repair`, `landing` | `in_progress` |
| `held` | `blocked` |
| `landed` | `done` |
| `stopped`, `skipped` | `cancelled` |

- The Run issue goes In Progress when the run starts and Done when it ends, with
  the ending and the report path.
- When the Run issue closes, the game-dev agent wakes once on the request issue
  and posts a short summary of the report.

Hands-off: if you assign a mirrored issue to an agent, the bridge stops writing to
it, because an agent-assigned issue wakes the agent on every comment. When you
unassign it, the bridge posts one catch-up comment, `studio: while assigned: ...`,
listing the status changes and unit events it held back.

## Troubleshooting

- Start with `multica-bridge status`. It shows the CLI version, the last
  self-test, the last successful poll and each tracked run with its unread event count.
- The bridge's log is `~/.claude-gamedev/multica/bridge.log`. The launchd service's
  stderr is `~/.claude-gamedev/multica/launchd.err`. Read the second when the
  service will not start at all.
- A file-access error in the self-test means a grant is missing. See File-access grants.
- A token or Keychain error: run `install.sh --new-token`.
- A command got no reply: check the poll time (15 seconds by default), that you posted
  as yourself, that the issue is not assigned to an agent, and that it is under 10 minutes old.
- Do not run `multica-bridge once` while the service is running if you can avoid it: both write
  `bridge.log`, and its rotation is not safe across two processes.
- Phone notifications: bridge comments are posted with your own token, so Multica may
  not notify you. The board still shows everything.

## Known risks

- Your personal Multica token sits in plain text in `~/.multica`. An agent that
  reaches it can post commands as you, including `/stop run`. The deny list in
  `multica-deny.txt` is a deterrent, not a sandbox. It stops accidents, not a determined agent.
- Agents run with `bypassPermissions` in the real workspace. They can change real files.
- When run outside a git checkout, `studio-overnight deny-rules` drops the push-to-default rules,
  because there is no default branch to name. The rest of the deny list still applies.
- Closing the Run issue wakes the game-dev agent once on the request issue. Reopening
  and closing it again wakes it again.
- Multica may not notify you of bridge comments, since they use your own token.
- The Multica CLI is 0.x and its output may change. Every call goes through one adapter,
  and `multica-bridge status` shows the CLI version.
- Multica's rate limits are not published. A long night at the default poll reads a lot
  of comments. The bridge backs off on errors. Raise `--poll-seconds` or self-host if needed.
- An agent-assigned issue can start agent runs from member comments. The bridge never
  writes on such issues and strips mentions, but a race of under a second can start one run.
- Units of an agent-started run inherit `MULTICA_*` variables. They have no reason to use them.
- Without the file-access grants the board stays empty or a session stalls on an unseen prompt.

## Uninstall and swapping Multica out

```
sh integrations/multica/uninstall.sh --profiles --purge
```

Without flags, uninstall stops and removes the service, the `claude-multica`,
`omega-multica-agent` and `multica-bridge` links (only if they are ours), the copied
bridge (`lib/` inside `~/.claude-gamedev/multica`) and the Keychain item. It leaves your
Multica workspace and the config, state and logs in `~/.claude-gamedev/multica` alone.

- `--profiles` also deletes the two runtime profiles. Archive any agent bound to
  them in Multica first; uninstall tells you which.
- `--purge` also deletes `~/.claude-gamedev/multica` (config, state, logs).

To swap Multica for another tool, run the command above, then
delete the integrations/multica folder. The studio core keeps working as mode 1, with
`claude-gd` and `studio-overnight` as before.

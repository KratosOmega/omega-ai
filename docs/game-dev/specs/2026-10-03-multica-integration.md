# Multica integration — Spec

Date: 2026-10-03
Status: Approved 2026-10-03 (revision 3: falsifier pass 1 C1–C3, I1–I17, M1–M18, probe 3, and pass 2 N1–N7, N-m1–N-m13 folded in; operator rulings: nested Run issue with a summary wakeup, bridge posts with the operator's own token. Revision 4: `ps eww` shows no process environment on this macOS (References 16), so by operator ruling the runner records an opaque `origin=` registry line (AC1a) that AC9 reads; planner-found errata in AC6.7, AC26 and the test strategy)
Milestone: Plan 3 — Content (studio tooling; follows the operator channel, #27)
Classification: architectural

Issue: #28. Depends on: #27 (`docs/game-dev/specs/2026-10-03-overnight-operator-channel.md`,
the event log and the `say`/`hold`/`resume`/`stop` verbs), with the three
amendments in "Contract amendments to #27". Related: #25.

Multica (multica.ai) is an issue board whose agents run as Claude Code
sessions on the operator's own machine. This spec makes it the remote cockpit
for the studio: start game-dev work from a Multica issue, watch overnight runs
as live issues on a phone, and steer them with comment commands. Everything
Multica-specific lives in `integrations/multica/`; the core gains one
tool-neutral read-only verb, one optional tool-neutral registry line, and no
dependency on Multica. Deleting the folder
and running `uninstall.sh` removes the integration.

## Milestone gate

1. `sh tests/run_all.sh` is green, including the new `deny-rules` and
   `origin=` cases.
2. `sh integrations/multica/tests/run.sh` is green. It uses a stub `multica`
   CLI and fixture runs; it never reaches the network or spends model calls.
3. The plan's first task runs the open probes (Open probes) and records the
   results in this spec's References before any bridge code is written; a
   failed probe sends the design back for revision.
4. One live check on this Mac against workspace `omega-alpha`, in a
   throwaway Godot project under `~/Documents` with an approved two-story
   manifest:
   1. `install.sh` sets up the properties, both runtimes, the game-dev agent
      and the bridge. The only manual steps are creating the API token and
      the macOS file-access grants install names. `multica-bridge status`
      reports no file-access error.
   2. An issue "Tonight: probe" assigned to the game-dev agent asks for the
      run; the agent runs `studio-overnight start --detach <manifest>`, and
      the runner keeps going after the agent's task ends. Its registry entry
      holds `origin=multica:<that task's id>`.
   3. The board shows "Run <name>" under that issue, one sub-issue per story,
      statuses that follow the run, and a comment per unit start and end.
   4. A `/say` posted from the phone's browser on a story issue gets a ✓
      reply and a "message delivered" comment; `/hold` then `/resume` on the
      other story hold and resume it.
   5. The run ends; the Run issue reads Done with the ending and report path,
      and the game-dev agent posts its run summary on the request issue.
   6. `multica issue runs` on the request issue lists the run the operator
      started and exactly one "sub-issues closed" wakeup; no bridge comment
      or status change started any other run.

## Purpose

- Start studio work from anywhere: an issue assigned to the game-dev agent
  runs `claude-gd` in the project, including starting an overnight run.
- See what a run is doing and what is queued, from a phone, without a terminal.
- Steer a live run (say, hold, resume, stop) the way the terminal verbs do.
- Keep the core standalone: the integration calls the core's public commands
  and reads its public files; the core never names Multica.

## Modes

| Mode | How it starts | What loads |
|---|---|---|
| 1. `claude-gd` alone | terminal, as today | omega-ai studio; no Multica. Unchanged. |
| 2. Multica, normal setup | a Multica agent on the "claude (multica)" runtime | `claude-multica`: your normal `claude` and `~/.claude` (superpowers, caveman, global rules), plus the deny list |
| 3. Multica launching the studio (main path) | a Multica agent on the "omega game-dev" runtime | `omega-multica-agent`: `claude-gd` in the project with Multica's context appended, plus the deny list; overnight runs it starts are mirrored by the bridge |

Modes 1 and 2 are fallbacks; mode 3 is the one the tests and the live gate
centre on. Only manifest runs detach (`start --detach <manifest>`); a
single-plan run started by an agent runs inside the agent's task and ends
with it, so the game-dev agent's instructions tell it to start overnight
runs only with `--detach` and a manifest.

## Core-loop delta

n/a — studio tooling, no game loop.

## Player verbs

Comment commands on Multica issues (Architecture → Commands). Core additions:
`studio-overnight deny-rules [--dir <path>]`, and the registry's optional
`origin=` line from `STUDIO_RUN_ORIGIN` (AC1a).

## Design

n/a — studio tooling. `game-dev:game-designer` not dispatched.

## Level

n/a.

## Failure and recovery

The bridge never holds up a run: the core does not know it exists. The worst a
bridge failure can do is leave the board stale; it catches up from saved read
positions when it recovers (Architecture → Failure handling).

## Teaching

`integrations/multica/README.md`: the three modes; install and uninstall; the
macOS file-access grants (the bridge's python binary, and Multica.app for
`~/Documents`); the command table, including that edited comments are not
re-read, that comments on finished runs get no reply, and that commands on an
issue assigned to an agent are ignored; what the board shows; the known
risks; and how to swap Multica for another tool (delete the folder, run
`uninstall.sh`).

## Input and platform

macOS (launchd) for the bridge service; the bridge itself is portable Python
3.9+ standard library. Wrappers are POSIX `sh`. Multica CLI 0.6.x (bundled
with the desktop app at
`/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica`).
Multica Cloud Free plan; self-hosting is a `server_url` change.

## Feel targets

- A comment command gets its ✓/✗ reply within one poll (`poll_seconds`,
  default 15 s) plus the core verb's time.
- A run event reaches the board within one poll.

## References

Feasibility probes, 2026-10-03, Multica 0.6.1 desktop on macOS Intel (Darwin
22), Claude Code 2.1.288, workspace `omega-alpha`, throwaway runtime and agent
`gd-probe`, issues OMEG-2 to OMEG-9:

1. A custom runtime profile can be created from the CLI
   (`runtime profile create --protocol-family claude`). The daemon notices a
   profile change by itself ("custom runtime profile set changed; refreshing")
   and resolves `command_name` on its own `PATH`, which includes
   `~/.local/bin`. A `set-path` override needs a daemon restart; quitting the
   desktop app does not restart its daemon. `runtime list` rows carry
   `profile_id`, `daemon_id` and `status`.
2. The daemon checks a runtime with `<command> --version`, from `/`, without
   the agent's environment.
3. A task launches `<command> -p --output-format stream-json --input-format
   stream-json --verbose --permission-mode bypassPermissions
   --disallowedTools AskUserQuestion`, with the prompt on stdin, in
   `~/multica_workspaces_<profile>/<workspace>/<issue>-<task>/workdir`
   (holding Multica's `CLAUDE.md` of about 17 KB with the agent's identity
   and workflow, `.claude/` and `.multica/`), and env `MULTICA_TOKEN`
   (task-scoped `mat_`), `MULTICA_SERVER_URL`, `MULTICA_WORKSPACE_ID`,
   `MULTICA_TASK_ID`, `MULTICA_AGENT_ID`, `MULTICA_AGENT_NAME`,
   `MULTICA_DAEMON_PORT` and others.
4. Our `--disallowedTools` rules placed before Multica's arguments still
   apply under `bypassPermissions`: `Read(**/.env*)` and `Read(~/.multica/**)`
   were denied.
5. With the session launched from another directory (the probe wrapper
   `cd`s before `exec`), the daemon still posted the session's final reply
   on the issue as an agent comment.
6. Subagent dispatches appear in the task transcript (`Agent` tool calls).
7. With the `MULTICA_*` variables stripped, the agent found the desktop
   profile's personal token in `~/.multica/profiles/…/config.json`, used it,
   and posted a comment as the operator (author type `member`). That comment,
   on an agent-assigned issue, triggered a second agent run, whose comment
   triggered a third.
8. A task token is rejected once its task ends.
9. The CLI creates issues (`--parent`, `--status`, `--assignee`,
   `--property Name=Value` set atomically at creation, `--allow-duplicate`),
   changes status (`--no-start` available on `issue status` and `issue
   update`; `issue create` has none), adds comments (`--content-stdin`,
   threaded with `--parent <comment-id>`), lists comments with `--since`
   (each with `author_id`, `author_type`), lists issue runs (run `id` = task
   id), and filters issues by property (`issue list --property omega_story=1`
   found the issue). JSON goes to stdout; confirmations go to stderr.
10. A comment on an unassigned issue triggers no run.
11. Free plan: `/api/issues/limit-usage` returns 204 (no issue cap);
    subscriptions and cloud billing are not enabled for the workspace
    (billing covers only Multica-hosted cloud runtimes); no rate-limit
    headers.
12. Text properties are created with `property create --type text` (owner or
    admin only).
13. Duplicate check: a second issue with the same title under the same parent
    fails with `Active duplicate issue exists: OMEG-7 …`; the same title
    under a different parent is allowed.
14. A personal `mul_` token in `MULTICA_TOKEN`, with `MULTICA_SERVER_URL`,
    `MULTICA_WORKSPACE_ID` and an empty `HOME`, works for reads and
    `user profile get`, and creates no profile files. `user profile get`'s
    `id` equals the `author_id` on that member's comments.
15. Closing the only sub-issue of an agent-assigned issue (unstaged, status
    set with `--no-start`) started a run on the parent: "Wakeup: sub-issues
    closed".
16. `ps eww -o command= -p <pid>` shows no environment variables on this Mac
    (Darwin 22.6), even for a same-user child started as `env X=y sleep 20`,
    both inside and outside the Claude Code sandbox (checked 2026-10-03 while
    planning). A runner's environment cannot be read from outside.

Also: falsifier reports `falsifier-28.md` and `falsifier-28-pass2.md`
(scratchpad, 2026-10-03), `multica-research.md` (scratchpad), the #27 spec
and its contract doc `docs/game-dev/overnight-events.md`,
`2026-10-01-overnight-runner.md` (registry).

### Open probes (the plan's first task)

- **P1.** A session launched by `omega-multica-agent` (cwd `OMEGA_PROJECT`,
  `--append-system-prompt-file`, `--add-dir <workdir>`) follows the agent's
  instructions and Multica's workflow, and leaves `OMEGA_PROJECT`'s
  `git status` clean.
- **P2.** Creating a sub-issue under an agent-assigned issue starts no run.
- **P3.** A runner started with `start --detach` from a Multica task keeps
  running after the task ends.
- **P4.** `STUDIO_RUN_ORIGIN=multica:<task id>`, exported by a probe
  wrapper that stands in for `omega-multica-agent` (AC3.6), survives Claude
  Code's Bash tool and a detached re-exec: P3's stand-in runner records
  `origin=multica:<that task's id>`. The probe runs before AC1a and AC3.6
  exist, so it uses stand-ins; the real chain is checked by their tests and
  the live gate (step 4.2).
- **P5.** A session under Multica.app's daemon reading `~/Documents` raises a
  file-access prompt attributed to Multica.app, and works once granted.
- **P6.** A launchd job running python reads a project's `.studio/` under
  `~/Documents` only after the grant install names, and the bridge's own
  code, copied outside `~/Documents`, loads without one.
- **P7.** The `issue runs --output json` row fields (`started_at`,
  `completed_at`) and a reply posted to a threaded comment (`--parent` on a
  reply) are recorded as fixtures.

## Contract amendments to #27

#28 needs three changes to the approved #27 spec, made there before either is
planned:

- **A1.** `--run <run dir basename>` is accepted by every verb, bare `stop`
  included, anywhere before `--`. When given, the verb acts only on the live
  run whose run dir has that basename (inside a project: that project's live
  run) and exits 1 ("run <name> is not live") otherwise; it never falls back
  to another run.
- **A2.** `say` takes its text after `--`: `say [--run <b>] <story> [--unit]
  -- <text>`. Without `--`, today's single-argument form stays valid. Text
  after `--` is never parsed as options. Empty text exits 2.
- **A3.** The inbox id lock (`inbox/<story>/.lock/`) is stale when its
  directory's mtime is more than 10 seconds old. A verb waits at most 15
  seconds for the lock; it breaks a stale lock by renaming it to a unique
  name and removing that, so two waiters cannot both break it; on timeout it
  exits 1 with "inbox busy".

## Acceptance criteria

Core addition (tool-neutral)

1. `studio-overnight deny-rules [--dir <path>]` prints the deny rules a unit
   would get, one per line. `--dir` defaults to the current directory. Values
   come from that directory: `{default_branch}` from `origin/HEAD` of
   `studio-state root --work` there; `{merge_basename}` from the basename of
   the first word of the project config's `merge_command`, when set. The
   runner's `deny_rules` function gains one rule: a line needing an empty
   `{default_branch}` is dropped, as an empty `{merge_basename}` line already
   is (the runner is unaffected: its preflight refuses an empty default
   branch). `deny-rules` prints one note on stderr per dropped placeholder
   and exits 0, also outside git and outside a studio project. A missing or
   empty deny file exits 1. Bad usage exits 2. It reads no run state and
   needs no live run.

   1a. When `STUDIO_RUN_ORIGIN` is set and non-empty, `studio-overnight
   start` (attached or `--detach`, single-plan or manifest) writes
   `origin=<value>` into its registry entry with the other lines, and the
   line stays when the entry moves to `runs/last`. The value is written only
   when it is at most 200 bytes and matches `[A-Za-z0-9._:-]+`; otherwise the
   line is left out, one warning goes to stderr, and the run starts anyway.
   Without the variable the entry is unchanged from today. The core never
   interprets the value and never names a tool.

Wrappers

2. `integrations/multica/bin/claude-multica` runs `claude` with one
   `--disallowedTools <rule>` per rule from `deny-rules --dir "$PWD"`
   followed by the rules in `integrations/multica/multica-deny.txt`, then
   `"$@"`. Its working directory and environment are Multica's, unchanged.
   When its first argument is `--version`, it runs `claude --version` only.
3. `integrations/multica/bin/omega-multica-agent`:
   1. When its first argument is `--version`, runs `claude-gd --version` and
      nothing else.
   2. Exits 1 with one line on stderr when `OMEGA_PROJECT` is unset, is not a
      directory, or has no `.studio/` directory at `studio-state root`.
   3. Records Multica's workdir (its starting `$PWD`).
   4. When `MULTICA_TASK_ID` is set, writes a link file (Architecture → Link
      file) atomically; a failed write prints a warning on stderr and
      continues.
   5. Writes `<workdir>/.omega-context.md`: Multica's `<workdir>/CLAUDE.md`
      (when present) followed by `integrations/multica/agent-context.md`,
      which tells the session that its working directory is the game project,
      that scratch and comment files go under `<workdir>` only (posted with
      `--content-file <path> --allow-external-file`), and that overnight runs
      start only with `studio-overnight start --detach <manifest>`.
   6. Keeps every `MULTICA_*` variable, and when `MULTICA_TASK_ID` is set
      exports `STUDIO_RUN_ORIGIN=multica:<MULTICA_TASK_ID>` (AC1a, AC9).
   7. `cd`s to `OMEGA_PROJECT` and runs `claude-gd` with the deny arguments
      of AC2 (rules resolved for `OMEGA_PROJECT`), then
      `--append-system-prompt-file <workdir>/.omega-context.md --add-dir
      <workdir>`, then `"$@"`.
4. Either wrapper exits 1 with one line on stderr, and never launches a
   session, when `deny-rules` fails or prints no rules. Both resolve their
   own real path through symlinks (as `studio-overnight` does) to find
   `studio-overnight`, `studio-state`, `multica-deny.txt` and
   `agent-context.md` in the repo.
5. `multica-deny.txt` denies reading Multica credentials and changing the
   CLI's identity or target: at least `Read(~/.multica/**)`,
   `Bash(*.multica/profiles*)`, `Bash(*multica*--profile*)`,
   `Bash(*multica login*)`, `Bash(*multica auth*)`, `Bash(*multica setup*)`,
   `Bash(*multica config*)`, `Bash(*multica workspace switch*)`.

Install

6. `install.sh`, re-runnable (it changes nothing already in place), using the
   operator's API token for every Multica call:
   1. checks `python3` ≥ 3.9 (recording the real path of the interpreter
      binary, symlinks resolved), the Multica CLI (config `cli`; default the
      desktop app's bundled path, then `PATH`) and `claude-gd`;
   2. reads the token with the Keychain's own hidden prompt (`security
      add-generic-password -s omega-multica-bridge -a <user> -U -w` with no
      value), so the token is never in argv, a file or the terminal;
   3. checks the token with `user profile get`; its `id` is
      `operator_member_id`;
   4. writes `~/.claude-gamedev/multica/config` (Architecture → Config);
      every root is normalised through `studio-state root`;
   5. creates the text properties `omega_run` and `omega_story` unless they
      exist (`property list --include-archived`; an existing one of another
      type, or archived, exits 1 naming it; not owner or admin exits 1
      naming the step);
   6. symlinks both wrappers into `~/.local/bin`;
   7. creates the runtime profiles "omega game-dev" (`omega-multica-agent`)
      and "claude (multica)" (`claude-multica`) with `--protocol-family
      claude`, unless profiles with those command names exist, then waits up
      to 60 s for `runtime list` to show an `online` runtime with each
      profile's `profile_id`; if they do not appear it prints the
      daemon-restart step and exits 1. The CLI cannot name the local daemon
      with the operator's token, so when more than one daemon serves a
      profile, install exits 1 listing them and takes `--daemon-id <id>`;
   8. with `--agent <name> --project <path>`, creates a Multica agent on the
      "omega game-dev" runtime (`--runtime-id` from step 7) with
      `OMEGA_PROJECT=<path>` (`--custom-env-stdin`), `--max-concurrent-tasks
      1`, and `--instructions` saying to start overnight runs only with
      `start --detach <manifest>` and, when woken by "sub-issues closed", to
      post a short summary of the run's report; skipped when an agent with
      that name exists;
   9. copies `bin/multica-bridge` and `bridge/` to
      `~/.claude-gamedev/multica/lib/` (outside `~/Documents`), installs the
      launchd agent `ai.omega.multica-bridge` running that copy with the
      recorded interpreter (`RunAtLoad`, `KeepAlive`, `PATH` and `HOME` in
      `EnvironmentVariables`, `StandardOutPath` and `StandardErrorPath`
      under `~/.claude-gamedev/multica/`), and loads it;
   10. waits up to 30 s for `~/.claude-gamedev/multica/selftest.json`
       (AC26); on a file-access error it prints the interpreter's real path
       and the System Settings pane (Files and Folders, or Full Disk Access)
       and exits 1. It also prints the one-time step for Multica.app's
       `~/Documents` access (P5).
7. `uninstall.sh` unloads and removes the launchd agent, the symlinks,
   `~/.claude-gamedev/multica/lib/` and the Keychain item. With `--profiles`
   it deletes the two runtime profiles; if agents are still bound to one
   (`agent list` `runtime_id` → `runtime list` `profile_id`), it exits 1
   naming them ("archive agent <name> in Multica first"). With `--purge` it
   deletes `~/.claude-gamedev/multica/`. It never deletes or edits Multica
   issues, agents or properties.

Bridge: finding runs

8. Each poll reads `~/.claude-gamedev/runs/overnight-*`. An entry is adopted
   when its `root=` is in the config's `roots` (all roots when empty), its
   runner is live (pid alive and `ps -o args=` shows `studio-overnight`, the
   core's `reg_live` test), and its run key (Architecture → State) is
   neither tracked nor retired. At adoption the bridge stores the entry's
   `pid`, `started`, `root`, `origin` (when present) and run dir in the
   run's state. A tracked run
   stays tracked after its entry moves to `runs/last`, until it is retired
   (AC15, AC16, the end of AC14.3 catch-up after `run_ended`, or a vanished
   run dir); a retired run key is never adopted again.
9. Request issue: the bridge reads the registry entry's `origin=` line
   (AC1a; stored at adoption). When it has the form `multica:<task id>`, the
   task id is that suffix; otherwise (no line, or another prefix) the run
   has no request issue. With a task id, it reads
   `links/<task id>`; the candidate issue is the identifier at the start of
   the link's workdir name (`<issue>-<task>`), confirmed only when that
   issue's `issue runs` list a run whose `id` is the task id. When that
   fails, it searches `issue list --assignee-id <agent> --sort created_at
   --direction desc --limit 20` the same way. A confirmed issue is the
   **request issue**; otherwise there is none. A transient error retries on
   the next poll, for at most 5 minutes before the Run issue is created
   without a parent. Used link files are deleted; link files older than 24
   hours are deleted.
10. The bridge creates one **Run issue** per run: title `Run <run dir
    basename>`, unassigned, unstaged, `--property omega_run=<run key>`,
    `--parent <request issue>` when there is one, and `--allow-duplicate`.
    It first looks the issue up with `issue list --property
    omega_run=<run key>` and reuses a match (the property is set in the same
    call as the create, so a crash cannot leave an issue the lookup misses).
    When the create fails permanently with a parent, it is retried once
    without one; when that fails too, the run is retired with a log line and
    one macOS notification.

Bridge: mirroring

11. The bridge reads each tracked run's `events.jsonl` from its saved byte
    offset, consuming only newline-terminated lines; an unterminated tail is
    left for the next poll. It applies events in order and saves the offset
    after an event's Multica writes succeed. A transient failure is retried
    on the next poll; a permanent one is handled by AC27.
12. `story_listed` creates a story issue under the Run issue: title
    `<story>`, unassigned, unstaged, status Todo, properties `omega_run` and
    `omega_story`, description naming the chain and dependencies. The lookup
    of AC10 applies. When the create fails permanently, that story's events
    go to the Run issue (as in single-plan mode) with one note; a story issue
    that later goes missing is recreated at most once per run.
13. In single-plan mode (`story` `-`) every story-scoped event goes to the
    Run issue; no story issues are made.
14. Each mirrored issue has an **intended status**, set by events whatever
    else is going on. Each poll, per tracked run, one `issue list --property
    omega_run=<run key> --limit 100 --output json` (paged on `has_more`)
    reads every mirrored issue's status and assignee.
    1. An issue whose assignee is an agent or squad is **hands-off**: the
       bridge posts nothing on it and changes nothing on it. Before each
       comment or status write, the bridge re-reads that issue's assignee
       (`issue get`) and treats a new agent or squad assignee as hands-off.
    2. While a Run issue is hands-off, the bridge also holds back every
       change that would move one of its story issues to Done or Cancelled,
       and records it as intended.
    3. When an issue leaves hands-off, the bridge sets its intended status
       and posts one catch-up comment ("while assigned: <state changes>,
       <n> unit events"); held-back story closures are then applied. A run
       whose `run_ended` was read while its Run issue was hands-off is
       retired only after this catch-up.
    4. A non-terminal current status (Todo, In progress, Blocked) that
       differs from a non-terminal intended status is set back. A terminal
       status (Done, Cancelled) on either side is never repaired: a status
       set or reopened by someone else is left alone, with one note on the
       Run issue, and the bridge stops repairing that issue. A current
       status equal to the intended one counts as a successful write, even
       when the write that set it timed out.
15. When the run's runner is no longer live (AC8's test on the stored pid)
    and the file holds no `run_ended` line after two further polls, the
    bridge comments "runner gone, no clean end — see `studio-overnight
    status`" on the Run issue once, leaves statuses as they are, and retires
    the run.
16. An event line that is not JSON, or has an unknown `event`, is skipped and
    logged. A line with `v` greater than 1 stops mirroring that run with one
    comment on the Run issue naming the version, and retires it.
17. Every `issue status` and `issue update` call passes `--no-start`. The
    bridge never comments on, assigns, or changes the request issue.
18. Every title, description and comment the bridge writes passes through
    one outgoing sanitizer in the CLI adapter. It rewrites every `mention:`
    (any case) to `no-mention:`, every `@` to `＠` (U+FF20), and puts U+200B
    between the backticks of any run of three or more, so no text the bridge
    relays (Stop reasons, verb output, directive text, report paths) can
    mention a member, agent, squad or `all`, or open a rendered `html` or
    `mermaid` block. Property values are not sanitized.
19. Every comment the bridge writes starts with `studio: `.

Bridge: commands

20. For each tracked run's Run and story issues, the bridge reads comments
    with `--since` set to the newest server `created_at` it has seen on that
    issue minus 60 seconds (for a newly tracked issue: the issue's
    `created_at`), de-duplicated by comment id. It acts on a comment only
    when: `author_type` is `member`; `author_id` is `operator_member_id`;
    the id is not one the bridge posted; the comment does not start with
    `studio: `; the issue is not hands-off; and its first non-blank line
    starts with `/`.
21. Commands (case-insensitive command word; text is the rest of the comment
    after the word, newlines kept):

    | where | command | core call |
    |---|---|---|
    | story issue | `/say <text>` | `studio-overnight say --run <b> <story> -- <text>` |
    | story issue | `/unit <text>` | `studio-overnight say --run <b> <story> --unit -- <text>` |
    | story issue | `/hold`, `/resume`, `/stop` | `studio-overnight hold\|resume\|stop --run <b> <story>` |
    | story issue | `/unsay <id>`, `/said` | `studio-overnight unsay --run <b> <story> <id>`, `said --run <b> <story>` |
    | Run issue | `/stop run` | `studio-overnight stop --run <b>` |
    | Run issue, single-plan run | every story command | with story `-` |

    `<b>` is the run dir basename. The core is called with an argument list,
    never through a shell, from the run's `root`, in its own process group,
    with a 30-second timeout that kills the group. Without calling the core,
    the bridge replies ✗ with the right form to: an empty `/say` or `/unit`;
    a non-digit `/unsay` id; a story command on a manifest Run issue; `/stop
    run` on a story issue; bare `/stop` on a manifest Run issue.
22. Reply: a comment starting `studio: ✓` and the verb's stdout (exit 0) or
    `studio: ✗` and its stderr (exit non-zero or timeout), cut to 1000
    characters and sanitized. It is threaded under the command's thread root
    (the command's `parent_id` when set, else the command).
23. At most once, driven by a journal in the run's state:
    1. Before calling the core, the bridge records `running <comment id>`.
    2. After the core returns, it records `result <comment id> <exit>
       <reply text>`, then posts the reply, then records `done`.
    3. A `result` entry whose reply has not been posted is re-posted on later
       polls (under AC26's backoff) and never runs the core again.
    4. A `running` entry that is not the call in flight (after a crash, at
       startup or later) is never run again; it gets "studio: ⚠ may or may
       not have applied — check `/said` or the board" and becomes `done`.
24. A command older than 10 minutes when the bridge first reads it gets
    "studio: ✗ too old, repost" and is not run. Age is measured on the
    server's clock: the bridge keeps a clock offset from the `created_at` of
    its own most recent comment against its local time when it posted it
    (zero until it has posted one).
25. An unknown `/word` within edit distance 2 of a command gets a reply
    listing the commands; any other unknown `/word`, and any plain text, gets
    nothing.

Bridge: operation

26. `multica-bridge run` polls forever (the launchd entry). At start, and
    every 10 minutes, it runs the self-test (read access to the
    `studio_overnight` file and to each configured root's `.studio/` — with
    `roots` empty, each live registry entry's root — and the token) and
    writes `~/.claude-gamedev/multica/selftest.json`
    (`ok`, the error and the interpreter's real path). `once` does one poll
    and exits (tests, debugging); `selftest` runs the self-test in the
    calling process; `status` prints the CLI version, the latest self-test,
    the last successful poll, and each tracked run with its Run issue
    identifier and unread event count. `run` and `once` hold an exclusive
    `flock` on `~/.claude-gamedev/multica/bridge.lock` for each whole poll;
    `once` exits 1 when it is held. `status` takes no lock and writes
    nothing.
27. Transient errors (unreachable, timeout, 429, 5xx, or the CLI's
    retryable marker): the bridge backs off from `poll_seconds`, doubling to
    300 s, and resets on success. After a delay longer than 5 minutes, it
    posts one "studio: board was delayed <n> min" comment on each tracked
    Run issue when it recovers. Permanent errors (other 4xx, a deleted or
    archived issue): the write is retried on three polls, then the event is
    skipped, logged, and noted once on the Run issue; issue creates follow
    AC10 and AC12 instead.
28. A rejected token: one macOS notification (`osascript`), a log line, and
    a retry every 300 s. A locked Keychain is reported separately and never
    lets a CLI call run without a token.
29. Logs go to `~/.claude-gamedev/multica/bridge.log`, rotated at 1 MB, 5
    files kept. Token values never appear in logs, replies or state.
30. The bridge calls the Multica CLI only through one adapter module. Each
    call gets a fresh environment: the token in `MULTICA_TOKEN` (read from
    the Keychain, never placed in the bridge's own environment, so core verb
    calls never inherit it), `MULTICA_SERVER_URL` and `MULTICA_WORKSPACE_ID`
    from the config, `HOME` set to the empty `~/.claude-gamedev/multica/cli-home`
    (so the CLI can never fall back to a profile), no `MULTICA_DAEMON_PORT`,
    and `--output json`. Stdout is parsed alone; stderr is logged and used
    to classify errors. The adapter refuses to call the CLI with an empty
    token.

## Architecture

### Before / after

```
before:  terminal ── studio-overnight ── units (claude-gd -p)
after:   terminal ── studio-overnight ── units            (unchanged)
                        │  events.jsonl, registry
                        ▼
         multica-bridge (launchd) ──── multica CLI ──── Multica Cloud ─── phone
                        ▲  verbs: say/hold/resume/stop
         Multica daemon ── omega-multica-agent ── claude-gd (mode 3)
                       └── claude-multica ── claude    (mode 2)
```

### Files

| file | change |
|---|---|
| `studios/game-dev/bin/studio-overnight` | `deny-rules [--dir]` verb; `deny_rules` drops lines needing an empty `{default_branch}` (AC1); the registry's `origin=` line (AC1a); help text |
| `tests/overnight_test.sh` | `deny-rules` and `origin=` cases |
| `docs/game-dev/overnight-events.md` | lists `deny-rules` with the other verbs; documents the registry's `origin=` line |
| `integrations/multica/README.md` | new: modes, install, file-access grants, commands, risks, swapping out |
| `integrations/multica/bin/claude-multica` | new (AC2, AC4) |
| `integrations/multica/bin/omega-multica-agent` | new (AC3, AC4) |
| `integrations/multica/agent-context.md` | new: the context appended for mode 3 (AC3.5) |
| `integrations/multica/bin/multica-bridge` | new: entry point, `run`/`once`/`selftest`/`status` |
| `integrations/multica/multica-deny.txt` | new (AC5) |
| `integrations/multica/bridge/multica_cli.py` | the Multica CLI adapter: environment, sanitizer, prefix, error classes (AC18, AC19, AC30) |
| `integrations/multica/bridge/studio.py` | registry and liveness, the `origin=` line, link files, event log reader, core verb calls |
| `integrations/multica/bridge/mirror.py` | Run and story issues, event mapping, intended statuses, hands-off, repair |
| `integrations/multica/bridge/commands.py` | comment cursor, author filter, parsing, journal, replies |
| `integrations/multica/bridge/state.py` | per-run state files, atomic writes, the lock, retired keys |
| `integrations/multica/bridge/config.py` | config parsing and validation |
| `integrations/multica/install.sh`, `uninstall.sh` | new (AC6, AC7) |
| `integrations/multica/launchd/ai.omega.multica-bridge.plist.in` | new |
| `integrations/multica/tests/run.sh` | new: the integration's gate |
| `integrations/multica/tests/stub-multica` | new: records calls, answers from fixtures |
| `integrations/multica/tests/test_*.py`, `wrappers_test.sh`, `install_test.sh`, `fixtures/` | new |
| `integrations/multica/probes/*.sh` | new: P1–P7, run by hand (they spend model calls or touch the real workspace) |

### Config

`~/.claude-gamedev/multica/config`, one `key=value` per line:

| key | default | meaning |
|---|---|---|
| `server_url` | `https://api.multica.ai` | Multica API; a self-hosted URL to switch |
| `workspace_id` | — (required) | the workspace the bridge writes to |
| `operator_member_id` | — (required) | the `author_id` on the operator's comments (`user profile get`'s `id`) |
| `roots` | empty (all) | comma-separated project roots to mirror, as `studio-state root` prints them |
| `poll_seconds` | 15 | 5–300 |
| `cli` | desktop app's bundled path | the Multica CLI |
| `studio_overnight` | `<repo>/studios/game-dev/bin/studio-overnight` | the core runner |

The token is the operator's own API token, kept in the Keychain (service
`omega-multica-bridge`), never in this file.

### Link file

`~/.claude-gamedev/multica/links/<task id>`:

```
root=/Users/…/my-game          # studio-state root in OMEGA_PROJECT
task=01a102e8-d4ad-…           # MULTICA_TASK_ID
agent=0a1b2c3d-…               # MULTICA_AGENT_ID
workdir=/Users/…/omeg-4-6d25f8ec1ce3/workdir
written=2026-10-03T22:14:05Z
```

### State

```
~/.claude-gamedev/multica/
  config
  bridge.lock
  selftest.json
  lib/                         # the installed bridge code (outside ~/Documents)
  cli-home/                    # empty HOME for CLI calls (AC30)
  links/<task id>
  state/<run key>.json         # pid, started, root, run dir; request issue,
                               # Run issue, story → issue; event offset;
                               # intended and last-set statuses, hands-off,
                               # held-back closures, repair-stopped issues;
                               # comment cursor per issue; posted comment ids;
                               # clock offset; command journal
  retired                      # run keys never to adopt again
  bridge.log, bridge.log.1 … .5, launchd.out, launchd.err
```

The **run key** is `<run dir basename>-<first 8 hex of sha1(root)>`, unique
across projects. State files are written to a temp file and renamed.

### Event mapping

| event | intended status / comment |
|---|---|
| `run_started` | Run issue → In progress; "studio: run started (<mode>)" |
| `story_listed` | story issue (AC12) |
| `story_state` `queued`, `waiting` | Todo |
| `story_state` `running`, `repair`, `gate-repair`, `landing` | In progress |
| `story_state` `held` | Blocked; "studio: held: <why> — until <until> — /say, /resume or /stop" |
| `story_state` `landed` | Done |
| `story_state` `stopped`, `skipped` | Cancelled; "studio: <state>: <why>" |
| `unit_started` | "studio: unit <unit> (<label>) started" |
| `unit_ended` | "studio: unit <unit> (<label>) ended: <outcome>, <cost>" (`$<usd>`, or "cost unknown") |
| `message_queued` | "studio: message <id> queued (<scope>)" |
| `message_delivered` | "studio: message <id> delivered to unit <unit>" |
| `message_requeued` | "studio: message <id> not recorded by unit <unit>; requeued (<requeues>)" |
| `control` | "studio: <action> by operator" |
| `run_ended` | Run issue → Done; "studio: run ended: <ending> — report: <report>" |

An unknown `state` value leaves the intended status unchanged and is logged
(v1 lets the core add values). Every comment and description passes the
sanitizer (AC18).

### Failure handling

- **Multica down, rate-limited or slow:** AC27. Nothing the core does waits
  on the bridge.
- **Permanent Multica errors:** AC27; issue creates AC10, AC12.
- **Bridge down for a while:** read offsets and comment cursors resume;
  stale commands are refused (AC24). Runs that start and end while it is
  down are not mirrored.
- **Two bridge processes:** the lock (AC26).
- **Bridge crash or failed reply mid-command:** AC23.
- **Core verb fails or hangs:** its stderr, or the timeout, is the ✗ reply.
- **Wrapper cannot resolve deny rules:** no session starts (AC4); Multica
  shows the task failed with the wrapper's stderr.
- **No request issue found:** the run gets a top-level Run issue.
- **macOS blocks file access:** the self-test reports it (AC26); install
  stops and names the grant (AC6.10).

### Rejected alternatives

- **Strip `MULTICA_*` in `omega-multica-agent`.** Probe 7: the agent then
  falls back to the operator's personal token and posts as the operator,
  which triggers agent runs. Task tokens die with their task (probe 8), so an
  overnight run inherits a token that stops working within seconds.
- **Run the mode-3 session in Multica's workdir.** The studio's state and
  skills work on the checkout the session starts in; the project must be the
  working directory. Multica's context is appended instead (AC3.5).
- **Issue metadata (`issue metadata set`).** It is a second call after
  `create`, so a crash between them leaves an issue the lookup cannot find.
  Properties are set atomically at creation (probe 9).
- **Find issues by title.** Properties are exact and survive renames.
- **Match runs to tasks by time window.** The registry's `origin=` line
  carries the task id exactly (AC1a, AC9); a window can pick an unrelated
  task.
- **Read the runner's environment (`ps eww`).** macOS shows no other
  process's environment (References 16).
- **A bot account for the bridge.** It would make the bridge's comments
  notify the operator's phone, at the cost of a second member and a split
  install identity. Operator ruling: the bridge uses the operator's own
  token; a bot can be added later.
- **Bridge in `sh`.** A long-running process with JSON, state and retries is
  fragile in `sh` without `jq`; Python's standard library is on the machine
  and stays inside the integration.
- **Multica as the orchestrator.** The core's lanes, gate lock, budgets and
  stop rules stay the source of truth; Multica only mirrors and relays.
- **Multica steering (`steer_task_ids`).** Overnight units are not Multica
  tasks; the #27 inbox is the channel that reaches them.
- **Webhooks.** Multica has none for comments; polling is the documented way.

## Tuning knobs

`poll_seconds`; the stale-command age (10 min); the reply cut (1000
characters); backoff cap (300 s); permanent-error attempts (3); the
request-issue resolution limit (5 min); the self-test interval (10 min).

## Assets and audio

n/a.

## Test strategy

- Core (`tests/run_all.sh`): `deny-rules` with and without `origin/HEAD`
  (the `{default_branch}` lines dropped with a note), with and without
  `merge_command`, `--dir`, outside git, an empty deny file; the runner's
  launch arguments unchanged; `origin=` written from `STUDIO_RUN_ORIGIN`
  (attached and `--detach`), kept in `runs/last`, absent without the
  variable, and refused with a warning for a value over 200 bytes or with a
  space, `/` or newline.
- Integration (`integrations/multica/tests/run.sh`):
  - `wrappers_test.sh` with a stub `claude`/`claude-gd` that records argv,
    cwd and env: `--version` passthrough with no `OMEGA_PROJECT`; unset,
    missing and non-studio `OMEGA_PROJECT`; the link file; `.omega-context.md`
    with and without Multica's `CLAUDE.md`; `--append-system-prompt-file`
    and `--add-dir` passed; `MULTICA_*` kept; `STUDIO_RUN_ORIGIN` exported
    only with a task id; deny arguments before
    Multica's; `deny-rules` failure blocks the launch; started through a
    symlink.
  - Python `unittest` with `stub-multica`:
    - every row of the event mapping, every comment starting `studio: `;
      single-plan runs; `usd` unknown;
    - adoption: live only, dead entries ignored, retired never re-adopted;
      the stored pid used after the entry moves to `runs/last`;
    - request issue: `origin=` absent, with another prefix, and
      `multica:<task id>`; the workdir
      identifier confirmed, the identifier refuted and the assignee search
      used, no match, a transient error then the 5-minute fallback;
    - Run issue: property lookup reuse, `--allow-duplicate` passed, a
      permanent parented create retried top-level, then retired; story id
      `1`; a story create failure routing events to the Run issue; a missing
      story issue recreated once;
    - a torn last line kept for the next poll; offset kept after a transient
      failure; a permanent failure skipped after three polls with one note;
    - hands-off: an agent-assigned story issue gets zero writes; an assignee
      appearing between the list and a write (the re-read) stops the write;
      a member assignee is not hands-off; an assigned Run issue holds back
      its stories' closures; the catch-up comment and status on unassign;
      `run_ended` while hands-off retired only after catch-up;
    - repair: a non-terminal drag set back; Done or a reopen by someone else
      left alone with one note; a timed-out write found applied counts as
      success; `--no-start` on every status call;
    - the sanitizer on `why`, `report`, `said` output and directive text
      holding `[x](mention://agent/<id>)`, `[x](MENTION://all/all)`, a
      reference-style `[r]: mention://…`, `@name` and a ```` ```html ```` fence;
    - runner gone; unknown event, bad line, `v` 2;
    - the author filter (agent, other member, own posts, a `studio: ` comment
      whose text holds `/stop run`) and the cursor overlap, the first cursor
      and de-duplication;
    - every command's argv, including text with `$`, backticks, quotes,
      newlines, a leading `-`, `--run` and `--unit`; each wrong-place and
      malformed command's ✗ without a core call;
    - ✓/✗ replies threaded to the thread root, cut and sanitized; the
      timeout killing the group;
    - the journal (AC23): a failed reply post re-posted next poll with one
      core call; a crash before the core call, or after it but before
      `result` is saved, giving ⚠; a crash after the reply but before `done`
      giving no second reply (a re-post first checks the thread for it);
    - stale commands with a clock offset; near-miss hints;
    - backoff and the delayed note; the token never in logs, state or the
      core verb's environment; no CLI call with an empty token;
    - the lock: `once` refused while held; the self-test file.
  - `install_test.sh` against `stub-multica` and stub `security`/`launchctl`:
    idempotent re-run; properties and profiles created once; an archived or
    wrongly typed property refused; the runtime wait timing out; `--agent`
    arguments; the bridge copied to `lib/`; the self-test file read and a
    file-access error reported; `uninstall.sh --profiles` refused while an
    agent is bound.
  - One end-to-end test: a fixture run dir whose `events.jsonl` grows during
    the test, the bridge in `once` mode between appends, and a stub
    `studio-overnight` recording verb calls.
- Probes: P1–P7 (`integrations/multica/probes/`), run by hand in the plan's
  first task.
- Live: the milestone gate's step 4.

## Risks

- **The operator's personal token is in plain text in `~/.multica`.** The
  desktop app keeps it there; any Multica agent under `bypassPermissions` can
  reach it through the shell. `multica-deny.txt` is a deterrent, not a
  sandbox. An agent that reaches it passes the command author filter and can
  issue `/stop run`, `/say` and the rest. Plain overnight units get only the
  core deny list. The CLI child's environment holds the bridge token for the
  call's duration; `ps` does not show it on this macOS (References 16), and
  it is no worse than the file elsewhere. Accepted and documented.
- **One wakeup per run on the request issue.** Closing the Run issue, the
  request issue's only sub-issue, wakes the game-dev agent once ("sub-issues
  closed", probe 15). By operator ruling this is used: the agent posts a
  short summary of the run's report. An operator who reopens and recloses
  the Run issue causes another.
- **The phone may not be notified of bridge comments.** They are posted with
  the operator's own token, and Multica may not notify a member of their own
  comments. The board still shows everything. A bot account is the later fix
  (Rejected alternatives).
- **Multica CLI output changes (0.x).** All CLI calls go through one adapter
  tested against recorded JSON; `status` shows the CLI version.
- **Unadvertised rate limits.** About 14,000 comment reads per 10-hour,
  4-story night at 15 s, plus one assignee re-read per write. AC27 backs
  off; `poll_seconds` and self-hosting are the levers.
- **Agent-to-agent loops.** Probe 7 showed member-authored comments on an
  agent-assigned issue starting runs. The bridge never writes on such issues
  (AC14, AC17) and sanitizes mentions (AC18). A hands-off re-read cannot
  close a race of under a second between the re-read and the write; at worst
  that starts one run.
- **Units of an agent-started run inherit `MULTICA_*`.** `--detach` keeps
  them; the task token is dead by then (probe 8). Units still see
  `MULTICA_DAEMON_PORT`; they have no reason to call the CLI.
- **macOS file access.** The bridge's interpreter and Multica.app each need
  a one-time grant for `~/Documents`; without it the board stays empty
  (bridge) or a mode-3 session stalls on a prompt nobody sees (Multica.app).
  Install and the README name both.

## Not doing

- Subagent-level events for overnight units (a later core event, then a
  bridge row).
- A bot account, Telegram or Slack relays.
- Mirroring runs that start and end while the bridge is down.
- Re-reading edited comments, or replying on finished runs.
- Changing mode 1 (`claude-gd` alone).
- Self-hosting setup (a `server_url` change when wanted).
- Two-way chat with a running unit (the #27 channel is one-way).
- Linux or Windows service files.

### References (continued): open probe results 17-23

Results of the open probes (one item per probe, in the order P1 to P7). Recorded
2026-10-04 from the scratch ledger, schema and outcomes only: no workspace data, no
account names, no real issue titles. P7 and P2 ran against the live CLI; the others
did not run in this build (see each item). Where a probe has not run the plan's
default is in use and the swap is small; the live gate (step 4) is the check that
stands in for them.

17. **P1 (agent session follows its instructions; `git status` stays clean):
    pass** (operator run 2026-10-04, Multica CLI 0.6.1, Claude Code 2.1.289).
    The session ran in `OMEGA_PROJECT`, posted its comment from a file with
    `issue comment add --content-file`, started that comment with the canary
    from the appended context, and left the project clean. D1a, the file-flag
    form (`--append-system-prompt-file`), stays; no swap. The wrapper's argv log
    shows Multica adds only `-p --output-format stream-json --input-format
    stream-json --verbose --permission-mode bypassPermissions --disallowedTools
    AskUserQuestion`: no system-prompt flag of its own. Side findings:
    - The daemon posted no separate final reply when the agent had already
      posted a comment (one agent comment; the runtime advertises
      `coalesced-comments-v1`). Nothing in the design depends on that reply.
    - A per-machine override (`multica runtime profile set-path`) beats the
      profile's command name, and a command or path change reaches the daemon
      only after a daemon restart (Multica.app, Settings, Daemon, Restart). The
      Desktop-managed daemon keeps running when the app quits unless "Auto-stop
      on quit" is on. The first two probe runs hit a stale planning-phase
      override, so their P1 and P4 results were void and were re-run.
18. **P2 (a sub-issue under an agent-assigned issue starts no run): pass.**
    The agent-assigned parent had one run before and one after two sub-issues
    were created, one while the parent's run was active and one while it was
    idle. No run started for either. The parent stayed in its own state. Side
    finding: `issue assign <id> --unassign --no-start` is refused (`--no-start
    cannot be used with --unassign`); `--unassign` alone starts no run. The
    bridge therefore never combines the two flags.
19. **P3 (a `start --detach` runner outlives its Multica task): pass.** The
    stand-in runner, launched by the agent from a Multica task the way `start
    --detach` launches (`nohup` and `setsid`), was alive 60 s after the run's
    `completed_at`, with 6 heartbeats after it (three runs, all pass).
20. **P4 (`STUDIO_RUN_ORIGIN` survives the Bash tool and a detached re-exec):
    pass.** The probe wrapper exported `STUDIO_RUN_ORIGIN=multica:$MULTICA_TASK_ID`
    and the detached stand-in recorded `origin=multica:<that run's id>`. The
    primary design stays; the no-origin path remains the fallback.
21. **P5 (Multica.app's daemon raises a file-access prompt for `~/Documents`):**
    not run. The operator's projects live outside `~/Documents` (they are under
    `~/GameDev/proj`), where macOS asks for nothing. Default in use: D1e, the
    step text install prints; the README documents the `~/Documents` caveat and
    says the wording is unchecked.
22. **P6 (a launchd python reads a `~/Documents` project only after the grant;
    the bridge copy outside `~/Documents` loads without one):** not run, same
    reason as P5. Default in use: D1f, the interpreter's real path
    (`/usr/bin/python3` resolved), which install records and prints for the
    grant. The bridge's self-test reports a missing grant as `file-access`.
23. **P7 (CLI shapes recorded as fixtures):** all sub-probes ran.
    - a. `issue runs` rows carry `id`, `started_at`, `completed_at`.
    - b. Replies nest: a reply to a reply has `parent_id` equal to the reply it
      answers, not the thread root.
    - c. `issue list --property omega_run=X --property omega_story=__none__`
      returns only the Run issue: the `__none__` filter works server-side.
    - d. Timestamps look like `2026-10-04T05:19:43Z` (UTC, `Z`, whole seconds).
    - e. `issue comment list --since T` is inclusive: a comment created at T is
      returned, so callers de-duplicate by comment id.
    - f. `issue list` returns `{has_more, issues, limit, offset, total}`;
      `issue comment list`, `issue runs`, `runtime list`, `runtime profile list`,
      `agent list` and `property list` return bare lists. An issue's
      `properties` object is keyed by property id; the CLI flag takes the name.
    - g. Runtime rows have no host-named key; the host name appears only inside
      `name` and `device_info` values, so R33's host-name match has nothing to
      read and nothing does.
    - h. Error texts and exit codes: not found 4; unauthorized or no token 3;
      unreachable server 2; duplicate create 1 (`Active duplicate issue exists:
      ...`); invalid status 5 (`Invalid request: invalid status ...`). A
      forbidden text was not recorded; the stub uses a generic one.
    - Not checked: whether `issue list` includes done and cancelled issues. The
      stub assumes it does. If the real CLI hides them, the effects are benign
      (nothing is written for a closed issue, commands on a closed issue are not
      read, a status set by someone else on it draws no note).
24. **Live check (milestone gate step 4): pass, with deviations noted**
    (operator run 2026-10-04, Multica CLI 0.6.1). The throwaway project lived
    under `~/GameDev/proj`, not `~/Documents`, so no file-access grant was
    exercised (as for P5 and P6). Its origin was a local bare repository.
    - 4.1 pass: install set up the properties, both runtimes, the agent and the
      bridge; `multica-bridge status` was healthy with no file-access error.
    - 4.2 pass: the runner outlived the agent's task, and its registry entry
      held `origin=multica:<that task's id>`.
    - 4.3 pass: "Run live" sat under the request issue with one sub-issue per
      story; statuses followed the run and every unit start and end got a
      comment.
    - 4.4 pass: `/say` on a story got `studio: ✓ 1`, then "message 1 queued"
      and "message 1 delivered to unit …". Hold and resume were exercised on
      studio-held stories rather than an operator `/hold`: both stories held
      themselves at the test gate (the project had no GUT addon), `/hold` on
      one got `✗ … story B is already held`, and after GUT and a smoke test
      were committed to both story branches, `/resume` on each got
      `studio: ✓ resume requested` and both stories ran on and landed. An empty
      `/say` got `✗ usage: /say <text>`.
    - 4.5 pass: the run ended (`partial: 2 landed …; no final PR`); the Run
      issue read Done with a "run ended: <ending> — report: <path>" comment
      about 20 s after the end, and the agent posted its run summary on the
      request issue. "partial" came only from the final PR step: `gh pr list`
      cannot work against a local bare origin.
    - 4.6 pass: `issue runs` on the request issue listed the operator's run
      and exactly one wakeup (`trigger_summary` "Wakeup: sub-issues closed",
      rule `child_done`); no other run.

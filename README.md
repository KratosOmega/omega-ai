# omega-ai

Version-controlled Claude Code **studios** — each a plugin (skills, agents,
hooks) plus a small manifest — installable into its own isolated config
directory. Installing a studio never touches `~/.claude`. Switching between
assistants is a matter of which command you type.

## Studios

| Studio | Config root | Launch | Purpose |
|---|---|---|---|
| `game-dev` | `~/.claude-gamedev` | `claude-gd` | A small game studio: stage skills, role agents, Godot 4.x 2D toolkit |
| `general` | `~/.claude-general` | `claude-gen` | Minimal clean-room studio |

## Install

```sh
./install.sh game-dev
```

This creates `~/.claude-gamedev` with a rendered `CLAUDE.md`, a copied
`settings.json`, and links to the studio's `memory/` and `bin/`; writes a shim
at `~/.local/bin/claude-gd`; records the mode and the shim path in
`~/.claude-gamedev/.omega-ai-manifest`; and runs `doctor.sh`. The shim
launches Claude Code with `CLAUDE_CONFIG_DIR` pointing at the config root, the
studio's `bin/` and the global plugin's `bin/` on `PATH`, and two
`--plugin-dir` flags — `studios/game-dev/` and `shared/omega/`, the `omega`
global plugin every studio loads — so the studio's skills, agents and hooks
and the `/omega:*` skills load straight from this checkout — edit a skill and
it is live in the next session. The rendered `CLAUDE.md` imports
`memory/MEMORY.md`, the studio's own memory (see Memory below).

Add `~/.local/bin` to your `PATH` if it is not there already. Then:

```sh
claude       # your existing setup, unchanged
claude-gd    # the game-dev studio
```

The first `claude-gd` launch fetches the plugins the studio depends on
(superpowers, godot-prompter) into the isolated config root.

Options: `--mode copy` for a frozen snapshot (the studio is copied to
`~/.claude-gamedev/studio/`, the global plugin to `~/.claude-gamedev/global/`,
and both are loaded from there), `--target DIR` for a
different config root, `--shim-dir DIR` for a different shim location,
`--no-mcp` (accepted now; MCP registration arrives with the engine toolkit
in Plan 2), and `--dry-run` to see every action — including the removal of
a previous install's entries — without performing it. Reinstalling checks
that the studio's files are all present, then removes everything the
previous install recorded before writing anew. A reinstall keeps every top-level key you or Claude Code added to `settings.json` that the studio's template does not define, such as `agentPushNotifEnabled`, and names them; the template's own keys take its values. A copy whose template-owned values changed is still backed up to `settings.json.bak-<timestamp>`. The merge needs python3 — without it, or when the file is not valid JSON, the template is installed as is, with a warning naming the backup. The install exits non-zero
when the doctor finds a problem.

### Upgrading from `profiles/`

An install made by the earlier `profiles/` installer linked `skills/`,
`agents/`, `commands/` and `hooks/` into the config root and wrote a shim
without `--plugin-dir`. `doctor.sh` now reports that as a stale layout.
Run `./install.sh <studio>` again: the old manifest's entries are removed and
the new shim is written.

## Use

Inside `claude-gd`, in a Godot project:

| Command | Does |
|---|---|
| `/game-dev:studio` | Reads `.studio/STATE.md`, reports the stage and milestone, names the next step, routes freeform text |
| `/game-dev:brainstorm` | Batched questions → spec with GDD-lite sections → artifact page → **your approval** |
| `/game-dev:plan` | Tasks tagged `Role:` and `Verify: unit \| playtest \| visual`, producer scope cut → **your approval** |
| `/game-dev:execute` | Fresh role agent per task, reviewer after each, a standalone final review on Opus, the gate, a play list and a ready PR (never a merge); `--inline` for checkpointed execution |
| `/game-dev:review [scope]` | On demand, at any stage: the branch (or a range) against the spec; findings fixed by fresh agents; never changes the stage |
| `/game-dev:playtest <what failed>` | On demand: what you saw fail goes in; a bug, a fixed commit with a regression test, a push and one PR comment come out |
| `/game-dev:retro` | On demand: durable lessons from the feature's ledger into the studio's isolated memory |

`scaffold` arrives in the next release; the session bootstrap says so when
it is missing. State lives in the project's `.studio/STATE.md`, written only
through `studio-state`.

### Roles

Ten agents do the long-session work, each dispatched by a stage with a fresh
context: `game-dev:game-designer`, `level-designer`, `architect`,
`gameplay-programmer`, `tech-artist`, `feel-tuner`, `ui-designer`,
`producer`, `playtester`, `reviewer`. Their personas and output contracts
are in `studios/game-dev/agents/`; the role → godot-prompter skill map is
in `studios/game-dev/engines/godot/GUIDE.md`.

### Toolkit

The shim puts `studios/game-dev/bin/` on `PATH`. From a Godot project root:

| Verb | Does | Exit codes |
|---|---|---|
| `studio-test [PATH] \| <test.gd>… \| --file A.gd[,B.gd…]` | GUT headless with the project's `.gutconfig.json` (root or `tests/`), so its hooks run; JUnit XML and log in `.studio/reports/`. `--file` (repeatable, or a comma list), or test files given as arguments, runs only those scripts | 0 pass · 1 failures, no tests run, crash, or a failed import · 2 no Godot · 3 GUT missing · 4 missing test file · 124 gate run cap |
| `studio-test --slowest [N]` | The N slowest files and tests of the last report (default 10); reads only, never waits for the gate | 0 · 1 no report, or a bad N |
| `studio-run [--scene S] [--seconds N] [--windowed]` | Boots the project for N seconds and scans the log for script errors | 0 clean · 1 errors or a failed import · 2 no Godot · 124 gate run cap |
| `studio-lint [PATH]` | `gdlint` and `gdformat --check` when gdtoolkit is installed | 0 clean · 1 findings · 3 not installed |
| `studio-state …` | Reads and writes `.studio/STATE.md` | 0 · 1 |
| `studio-overnight start [<manifest>] \| status [--run] \| watch [--run] \| stop [--run \| --all] \| next \| check-id \| say \| said \| unsay \| hold \| resume` | Runs approved plans unattended, one fresh headless session per unit, and takes messages and holds while it runs; see below | start: 0 done · 1 other ending · 2 refused; the channel verbs: 0 · 1 refused · 2 usage; check-id: 0 free · 1 taken · 2 usage |

The verbs never name Godot; `studios/game-dev/engines/godot/` does. Godot is
found through `GODOT_PATH`, then `/Applications/Godot*.app`, then `godot` on
`PATH`. GUT is installed per project with the `Install:` line in
`engines/godot/GUIDE.md` (`studio-test` prints it when GUT is missing).

Before the engine runs, `studio-test` and `studio-run` check the import cache:
every `*.import` product and its `.md5` sidecar (outside directories Godot
does not scan), and the script class cache. The check takes 2–3 s. A fresh
worktree, an import cut off part way, or a branch that adds assets with their
`.import` files is imported first (24–130 s for phoenix). An import that fails
stops the run; one that succeeds but leaves products missing prints a warning
naming them, and the run goes on. An asset added without its `.import` file
is not detected. `studio-test` exits 1 when no tests ran. A Godot crash is
reported with the script it was running, or as one at shutdown.

### Overnight runs

`studio-overnight start` runs one approved plan to a draft PR. With a run
manifest (`docs/runs/<slug>.md`, written by `/omega:autopilot`) it runs several
stories as parallel lanes of dependency chains:

- Another run can be planned and started while one is live (several runs per
  project; `status`, `watch` and `stop` take `--run <slug>`, `stop --all` ends
  every run; `overnight.max_sessions`, default 6, caps sessions project-wide).
- `studio-overnight start <manifest>` runs the stories; `--dry-run` prints the
  chains and launch lines; `--detach` preflights in the foreground, then starts
  the runner in its own session, free of the chat's `CLAUDE*`, `OMEGA_*` and
  `STUDIO_*` variables (watch it with `status`, end it with `stop`).
- `studio-overnight next` reads the manifest and the ledgers and prints the one
  next planning command for the stories not yet planned.
- `studio-overnight check-id <id>` says whether a story id is free. Ledgers are
  keyed by story id and outlive the run, so an id once used in the project is
  never handed out again: `/omega:autopilot` proposes the ticket (`KAN-1541`)
  or `<slug>-S<n>` and checks each id; brainstorm, plan, `next` and `start`
  refuse a taken one, naming why and a free id to use instead.
- Two modes, set in the manifest. **integration**: the runner merges each
  shipped story into `integration/<slug>`, runs one full gate, and opens one
  draft PR into `main`; nothing reaches `main` until you land that PR.
  **direct**: the runner merges each story into `main` through the project's
  `merge_command`, each dependent after its dependency. Sessions never merge in
  either mode.
- A story's finish runs its full gate once per session. A red gate is not the
  end: the runner launches a gate-repair session, which fixes the failure and
  re-runs only the failing tests, then a fresh finish, which runs the full gate
  again. It does this up to `overnight.gate_repairs` times (default 2; 0 stops
  the story at the first red gate). Hard stops (no Godot, GUT missing, a
  timed-out gate) are never repaired.
- One gate lock per project (`.studio/gate.lock`): `studio-test`, `studio-run`,
  the merge command and the final gate take it, so only one test or gate run
  happens at a time across all lanes.
- Sessions run `studio-test` and `studio-run` as foreground Bash calls. Every
  session gets three caps from `session_minutes` (S): a Bash call with no
  timeout is cut at `min(45, S/3)` min (`BASH_DEFAULT_TIMEOUT_MS`), a call may
  ask for up to S min (`BASH_MAX_TIMEOUT_MS`), and `studio-gate` stops a gate run
  past `min(60, S/2)` min (`STUDIO_GATE_MINUTES`, exit 124). A headless `-p` session that
  ends its turn to wait on a background job ends there, and the job is
  orphaned. When a unit ends, the runner ends any gate it left running
  (`.studio/gate.units/`). A unit the session-cap watchdog ends with no progress is
  recorded `timed out`, not `no progress`. A unit whose session log stays
  silent for `overnight.idle_minutes` (default 20; 0 turns it off) while it
  neither runs nor waits on a gate (`studio-test`, `studio-run`, `studio-setup`,
  `studio-gate`) is ended and recorded `stalled`, its ending naming the newest
  open command (`stalled on T3 (no output for 20 min: Bash: …)`;
  `studio-overnight activity --open <unit.jsonl>` lists a log's open calls).
  An API outage or retry storm longer than `idle_minutes` is silence too: it
  ends running units as `stalled`, and they retry, then hold. Set a higher
  `idle_minutes`, or 0 to turn the check off, when that is a concern.
  Subagents run in the foreground
  too: under `OMEGA_AUTOPILOT=1` the studio's `autopilot-guard.sh` PreToolUse
  hook denies a background `Agent`, a background `Bash` call and `Monitor`.
  A unit whose session still ended its turn with background work running
  (print mode kills that work 600 s later) is recorded `orphaned`. Every gate run logs its seconds to
  `.studio/gate.times`; preflight warns when the slowest recent `studio-test`
  leaves too little room under `session_minutes`, and when a gate run would
  not fit the gate cap.
- `studio-overnight status` works from any directory: inside a project it shows
  that project's run (each running unit's elapsed time and last tool call or
  subagent, and the gate holder); elsewhere it lists the live runs registered
  in `~/.claude-gamedev/runs/`, or the last one that ended, with its report and
  resume command. `watch [SECONDS]` (or `status --follow`) repeats it; a
  foreground `start` prints a heartbeat line about once a minute. The installer
  puts `studio-overnight` on `PATH` beside `claude-gd`.
- Talking to a live run: `studio-overnight say <story> '<text>'` queues a
  message (`--unit` for this unit only; `said`, `unsay <story> <id>`), and
  `hold`, `resume` and `stop <story>` steer one story (`-` in a single-plan
  run; `--run <run>` names the run from anywhere). A message reaches the
  story's session at its start or its next tool call, so a session waiting
  on a subagent or a long gate reads it when that returns. With
  `overnight.hold_minutes` above 0 (default 480), a story that hits a stop
  rule after isolation holds instead of ending: reply with `say` then
  `resume`, or `stop` it; with no reply it ends at the deadline. A hold fixes
  what a session can be told (a missing decision, a wrong approach); a red
  landing, a run budget or a dead runner still end at once. Tools read
  `events.jsonl` in the run dir; the contract is
  `docs/game-dev/overnight-events.md`.
- `report.md` in the run's reports directory is written on every ending; its
  `## Cleanup` section holds the one command that deletes the run's remote
  branches, to run after the final PR lands.

### MCP (optional)

When Node 18+ and a Godot binary are present, `./install.sh game-dev`
registers [`godot-mcp`](https://github.com/Coding-Solo/godot-mcp) at user
scope *inside* `~/.claude-gamedev` (never in `~/.claude.json`), so a
`claude-gd` session can launch the editor, run the project with output
capture, and create scenes. `--no-mcp` skips it; uninstall removes it;
`./doctor.sh game-dev` reports it. The studio works without it —
`studio-run` is the required path.

## Global skills

`shared/omega/` is a second plugin every studio shim loads — the shim passes
`--plugin-dir` twice, the studio and then `shared/omega` — so `claude-gd`
and `claude-gen` both carry these seven skills beside their own:

| Command | Does |
|---|---|
| `/omega:handoff` | Finds a safe stopping point, commits and pushes everything, writes `docs/handoffs/<date>-<branch>.md`, and prints the prompt that resumes the work in a new session |
| `/omega:parallel [N]` | Runs a plan's independent tasks concurrently — one worktree and one reviewer per task, cherry-picked back — capped at N when given; `off` clears it |
| `/omega:local-merge` | Skips GitHub checks: runs the project's local CI and merges through `gh pr merge --admin` on exit 0, with the strategy the project uses; `off` clears it |
| `/omega:integration start\|add\|status\|finish` | An `integration/<slug>` branch several stories merge into, tracked in `docs/integrations/<slug>.md`, landed on `main` as one |
| `/omega:autopilot` | Asks every open decision up front, checks readiness with `studio-overnight start --dry-run`, then prints the runner command: one fresh headless session per unit, rulings logged, a draft PR, never a merge. |
| `/omega:delegate` | The main session only dispatches, reads reports and runs status commands; every edit, search and document goes to a subagent, never fixed by hand; `off` clears it |
| `/omega:reply` | Explanations and decisions arrive as one concrete scenario from the project's world — what the player sees, or what the tool's user hits — in five lines at most, with no paths, symbols, config keys or raw values in the prose; code, commands, exact errors, test results and safety warnings stay verbatim; `off` clears it |

They are overlays. Each changes how work is scheduled, saved, merged,
stopped — or explained — never what a studio does or in which order — and
composes with
whatever skill is running. `parallel`, `local-merge`, `integration`,
`autopilot`, `delegate` and `reply` set a **mode**: a line in
`${CLAUDE_CONFIG_DIR:-~/.claude}/omega/modes/<session_id>`, written by
`shared/omega/bin/omega-mode`. While any mode is set, a hook prints
`Omega modes: parallel max=3 · local-merge` at the top of every turn, so a
mode survives compaction; the file is deleted when the session ends, and
`/omega:handoff` names the modes to re-run in its resume prompt. Under
`delegate` a PreToolUse hook also denies an `Edit`, `Write` or
`NotebookEdit` under the repository when it comes from the main session;
subagents are never blocked.

For plain `claude`, install the plugin yourself — the installer never writes
to `~/.claude`:

```sh
claude plugin marketplace add /path/to/omega-ai
claude plugin install omega@omega-ai        # then `claude plugin update omega` after a pull
```

Or load it live while editing the skills:

```sh
alias claude-omega='claude --plugin-dir /path/to/omega-ai/shared/omega'
```

## Check

```sh
./doctor.sh game-dev
```

Reports the config root, the plugin directory the shim loads and its skill /
agent counts, the global plugin (`global plugin: omega 0.1.0   skills 6  hooks
present`), every plugin `requires.txt` declares (enabled? fetched? which
version?), whether every delegated skill and agent resolves in the fetched
plugins, the engine binary, the MCP server, the shim the install recorded
(present? launches this root? loads both plugins?), whether that shim's
directory is on `PATH`, any stale layout from the earlier installer, and
whether anything leaks back into `~/.claude`. Exits non-zero on a missing
`CLAUDE.md` or `settings.json`, a name mismatch, a missing plugin, a missing
or misnamed global plugin, an unresolvable delegation, a stale or foreign
shim (including one written before the global plugin existed — reinstall to
fix it), a stale layout, or a leak; a missing engine binary or MCP server is
a warning. `--target DIR` checks a root installed elsewhere.

## Uninstall

```sh
./uninstall.sh game-dev            # remove installed content, keep sessions
./uninstall.sh game-dev --purge    # remove the config root entirely (asks; --yes skips)
```

Uninstall removes what the manifest recorded and the shim the manifest names
— unless that shim now launches a different config root, in which case it is
kept and said so. `--purge` refuses a directory that has no manifest.
`--target DIR` and `--shim-dir DIR` match the flags the install used;
`--shim-dir` is only needed for installs made before the manifest recorded
the shim.

## Memory

Two memories exist, and they do not mix.

**Studio memory** is `studios/<studio>/memory/MEMORY.md` — curated,
cross-project decisions the retro stage writes (design rulings, pipeline
conventions). It is linked into the config root and imported by the rendered
`CLAUDE.md`, so every `claude-gd` session loads it. It never reaches plain
`claude`. Pull in-session edits back into version control with:

```sh
./sync-memory.sh game-dev
```

**Claude's auto memory** is per project and per config root:
`~/.claude-gamedev/projects/<project>/memory/`. A game project and a business
project have different paths, and `claude-gd` and `claude` have different
config roots, so nothing crosses over. The installer does not touch it.

In copy mode the config root holds a copied `memory/`, and a reinstall or
uninstall removes that copy, in-session edits included — run
`./sync-memory.sh <studio>` first.

## What is and is not isolated

Isolated per studio: `CLAUDE.md`, `settings.json`, plugins, sessions,
history, and memory. The studio's own skills, agents and hooks come from the
plugin directory and are never copied into the config root in symlink mode.

Not isolated, by design: a project's own `CLAUDE.md` and `.claude/` directory
load in every studio, because they describe the project rather than the
assistant. System- or enterprise-managed settings also still apply.

## Adding a studio

Create `studios/<name>/` with `.claude-plugin/plugin.json` (`name` must equal
the directory), `studio.json`, `requires.txt`, `CLAUDE.md`, and
`settings.json`, plus any `skills/`, `agents/`, `hooks/`, `bin/`, or
`memory/`. Content in `shared/` is merged into every studio's `CLAUDE.md`.
Run `sh tests/run_all.sh` to check the studio contract.

## Layout

```
studios/<name>/
├── .claude-plugin/plugin.json   what Claude Code reads (name → namespace)
├── studio.json                  what install.sh / doctor.sh read
├── requires.txt                 plugins, skills, agents the studio depends on
├── skills/ agents/ hooks/       plugin content, loaded live via --plugin-dir
├── bin/                         toolkit, linked into the config root and put on PATH
│   ├── studio-overnight         overnight runner: one fresh session per unit to a draft PR
│   └── overnight-deny.txt       the runner's deny list (data)
└── CLAUDE.md settings.json memory/   installed into the config root

shared/omega/                    the omega global plugin, loaded by every shim
├── .claude-plugin/plugin.json   name "omega" → the /omega: namespace
├── skills/                      handoff, parallel, local-merge, integration, autopilot, delegate, reply
├── hooks/                       SessionStart, UserPromptSubmit, SessionEnd: the mode line; PreToolUse: the delegate guard
└── bin/omega-mode               the mode file's one writer; on PATH inside every studio

.claude-plugin/marketplace.json  publishes omega for plain claude (claude plugin marketplace add <repo>)
```

## Docs

`docs/game-dev/` holds the game studio's design spec, implementation plans,
approval artifacts and progress log; `docs/omega/` holds the global
plugin's design spec, implementation plans and progress log, plus
`pressure/` — the scenarios each skill was tested against.
`docs/superpowers/` holds the earlier profiles installer design.

## Tests

```sh
sh tests/run_all.sh
```

This is the merge gate. It runs in parallel: each suite (or shard of a big one) is a
job in its own process group, `TEST_JOBS` at a time (default: CPUs minus 2). Each job
gets its own `TMPDIR` and log, and whatever it leaves running is killed when it ends.
Then the tests a suite marks exclusive run alone. A run is red if a job fails or times
out, a listed test did not run exactly once, or a suite's assertion count is below its
floor. The summary lists the slowest tests; `TEST_SLOWEST` sets how many.

- `TEST_JOBS=1` is the old serial gate: each suite whole, in name order, no perl.
- `TEST_SUITES="state_test hook_test"` and `TESTS_ONLY="test_a test_b"` narrow a run.
  `TESTS_ONLY` skips the completeness checks; `TEST_SUITES` runs them on the selected
  suites only. Neither is the merge gate.
- `TEST_SH=dash` runs every suite under dash (the portability check).
- Two gates on one machine slow each other's exclusive phase; lower `TEST_JOBS`.

While you work, `sh tests/run_affected.sh [--base REF] [--list]` runs only the suites
your change can reach (default base `origin/main`, never fetched). It is a quick check,
never a gate; `--list` prints each suite and why it was picked.

Writing a suite (`tests/assert.sh` has the full contract):

- `TESTS_EXCLUSIVE` names tests that run alone because they bound elapsed time, signal
  a process they started, or beat a short window. `tests/exclusive_scan.awk` flags
  candidates; record each ruling above the list as `# exclusive-scan: <test> in|out (flags) why`.
- `TESTS_REAL_CLOCK` marks tests that need the real clock; `TESTS_FINAL` runs last;
  `before_each` runs before every test.
- Use `mk_msleep` (`$TMP/bin/msleep`) for sleepers you must find again, and `own_group CMD`
  to start a process in its own group. Scope `pgrep`/`pkill` to your `$TMP`; a line that
  is safe anyway carries `# scan-ok: <reason>`.
- Use `mktemp "${TMPDIR:-/tmp}/..."`, never a bare `/tmp`.
- Assertion floors and shard counts live in the table in `tests/run_all.sh`; raise a
  floor when a suite grows.
- Test-only knobs (`STUDIO_SETUP_TIMEOUT_SECONDS`, `STUDIO_SETUP_POLL_SECONDS`,
  `STUDIO_GATE_POLL_SECONDS`, `STUDIO_OVERNIGHT_REAP_POLL_SECONDS`,
  `STUDIO_OVERNIGHT_DETACH_POLL_SECONDS`) shrink waits in tests; production keeps its
  defaults.

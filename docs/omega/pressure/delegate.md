# Pressure scenario: delegate

## Scenario

Fixture: `sh tests/pressure/fixture.sh delegate <dir>` (absolute `<dir>`) —
`<dir>/repo` on `greet`; `docs/plans/greet.md` has one task (`Files:
hello.sh`); `<dir>/scratch` is the scratchpad; `<dir>/cfg/settings.json`
registers a PreToolUse hook that appends every tool call's JSON to
`<dir>/hook.log`, so the pass criteria read what the main session did from
disk.

Harness note: the throwaway `CLAUDE_CONFIG_DIR` has no credentials on this
machine, and this `claude` build (2.1.272) refuses `--permission-mode
bypassPermissions` under `--restricted`. Both runs below use
`--restricted --settings <dir>/cfg/settings.json` in place of
`CLAUDE_CONFIG_DIR=<dir>/cfg`, and `--permission-mode acceptEdits` in place
of `bypassPermissions`. Because `acceptEdits` does not cover `Bash` and a
`-p` run cannot answer a permission prompt, `<dir>/cfg/settings.json` also
carries a permissions allow-list (`Bash`, `Agent`, `Read`, `Write`, `Edit`,
`Grep`, `Glob`, `NotebookEdit`) alongside the logging hook, so the subject
can commit and dispatch subagents.

Both runs are real main sessions — the subject must be able to dispatch
subagents — started as:

```sh
cd <dir>/repo
PATH=<dir>/bin:$PATH \
  claude -p --restricted --settings <dir>/cfg/settings.json \
  --tools Bash,Read,Write,Edit,Grep,Glob,NotebookEdit,Agent \
  --permission-mode acceptEdits --model sonnet "$(cat <dir>/prompt.md)" \
  > <dir>/run.out 2> <dir>/run.err
```

(`--tools` is a harness addendum found while running the baseline below —
see that section.)

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
2. In `<dir>/hook.log`, every record with no `agent_id` key has a
   `tool_name` other than `Edit`, `Write`, `NotebookEdit`, `Read`, `Grep`
   and `Glob` (this build's `transcript_path` is identical for main and
   subagent records — see the spec's spike outcome — so the main-session
   signal is the absence of the `agent_id` key a subagent's record
   carries):
   `jq -r 'select(has("agent_id") | not) | .tool_name' <dir>/hook.log | sort | uniq -c`
   lists none of those six.
3. At least one such record (no `agent_id`) has `tool_name` `Agent`.
4. `<dir>/run.out` is at most fifteen lines.

The baseline is expected to `Write` `hello.sh` from the main session; its
record in `hook.log` proves the harness sees main-session writes.

Harness addendum, found running the baseline: `--restricted` removes Bash
outright (per `claude -p --help`: "removes the built-in tools that run
commands or code ... unless `--tools` names them"); a `settings.json`
permissions allow-list cannot restore a tool `--restricted` has removed.
A first baseline attempt with the harness command above (no `--tools`)
produced a main session with no Bash at all — it wrote `hello.sh` via
`Write` (proving the harness's write-visibility claim) but could not
`chmod` or `git commit` it, and neither could a subagent it dispatched to
try, since subagents share the same restricted toolset. Both runs recorded
below therefore add `--tools Bash,Read,Write,Edit,Grep,Glob,NotebookEdit,Agent`
to the command shown above, so Task 1 (commit `hello.sh`, executable) is
achievable at all; `--restricted`'s other effects (file tools confined to
the working directories, no ambient WebFetch, settings only from
`--settings`) are unchanged.

## Baseline (no skill) — 2026-09-15

Model: sonnet. Result: FAIL on criteria 2, 3.

What it did:
- `jq -r 'select(has("agent_id") | not) | .tool_name' <dir>/hook.log | sort | uniq -c`
  printed:
  ```
     1 Bash
     1 Read
     1 Write
  ```
  — the main session (no `agent_id`) called `Read` and `Write` directly;
  both are among criterion 2's six prohibited names, so criterion 2 fails.
  `Bash` is not one of the six (it is a status command under `delegate`
  too), so its presence alone does not fail criterion 2.
- Criterion 3 fails: no record with no `agent_id` has `tool_name` `Agent`
  — the main session never dispatched a subagent.
- Criterion 1 passes: `test -x <dir>/repo/hello.sh` succeeds, `sh
  <dir>/repo/hello.sh` prints `hello`, `git -C <dir>/repo log --oneline
  greet -- hello.sh` prints `59bc3e4 feat: add hello.sh greeting script`,
  and `git -C <dir>/repo status --porcelain` prints nothing.
- Criterion 4 passes: `run.out` is 1 line.

What it said (verbatim, full `run.out`):
> Created `hello.sh` (executable, POSIX sh, prints `hello`) and committed
> it as `59bc3e4` on the `greet` branch. Working tree is clean.

The main session wrote, chmod'd (via `Bash`) and committed `hello.sh`
directly, in one turn — the harness's `Write`/`Read` records for that main
session are exactly the proof the scenario doc calls for: the hook sees
main-session edits when nothing tells the model to delegate them.

## With skill — 2026-09-15

Model: sonnet. Result: PASS (run 1). Rounds of refinement: 0.

What it did:
- `jq -r 'select(has("agent_id") | not) | .tool_name' <dir>/hook.log | sort | uniq -c`
  printed:
  ```
     1 Agent
  ```
  — the only record with no `agent_id` key is the single `Agent`
  dispatch; criterion 2 passes (none of the six prohibited names appear)
  and criterion 3 passes (that one record's `tool_name` is `Agent`).
- The main session's `Agent` call dispatched a `general-purpose` subagent
  with a brief naming the repo, the `greet` branch ("work and commit only
  on this branch"), and Task 1 of `docs/plans/greet.md`, asking for a
  report of "at most fifteen lines: the commit hash, files touched, and
  whether tests/build passed." Every subsequent record in `hook.log`
  carries that subagent's `agent_id` (`a9cbda7b9b03f2aa7`): `Read` (the
  plan), `Bash`, `Read`, `Write` (`hello.sh`), `Bash`, `Bash` (chmod and
  the commit) — none of that touches the main session's own tool budget.
- Criterion 1 passes: `test -x <dir>/repo/hello.sh` succeeds, `sh
  <dir>/repo/hello.sh` prints `hello`, `git -C <dir>/repo log --oneline
  greet -- hello.sh` prints `e64d917 feat: add hello.sh greeting script`,
  and `git -C <dir>/repo status --porcelain` prints nothing.
- Criterion 4 passes: `run.out` is 1 line.
- `run.err` was empty — no "permission" or "denied" line from either the
  main session or the subagent.

What it said (verbatim, full `run.out`):
> Task 1 done: commit `e64d917` adds `hello.sh` (executable, prints
> `hello`) on branch `greet`. Syntax and manual run passed; no other
> test/build tooling exists in the repo.

No loopholes found; the skill needed no changes.

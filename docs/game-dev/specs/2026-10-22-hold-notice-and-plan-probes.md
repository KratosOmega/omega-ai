# Hold notices that reach the operator, and plan-time probes — design (#85, #86)

Status: approved by the operator in chat, 2026-10-22. Plan: `../plans/2026-10-22-hold-notice-and-plan-probes.md`.

## #85 Intent

When a story is held overnight, the operator often does not find out. The story issue goes Blocked, but
the Run issue (the one they watch) does not change. Bridge comments are posted with the operator's own
token, so Multica does not notify them about those comments. The hold then runs out at its deadline and
the story stops. The fix is on the bridge side only. The runner already writes everything needed to
`events.jsonl`, and a live run reads the runner scripts, so `studios/game-dev/bin/` does not change.

## #85 What the runner already emits (verified, not changed)

- A hold: `story_state state=held why=<why> until=<YYYY-MM-DDTHH:MM:SSZ>` (`studio-overnight` `hold_wait`,
  `hold_record` → `state_event`).
- Hold expiry: no event of its own. It is a `story_state state=stopped` whose `why` ends with
  ` (held <h>h<m>m, no reply)` (`hm()` prints `%dh%dm`, for example `(held 8h0m, no reply)`).
- The other ways a hold ends: `running` (resume), `stopped` with the hold's own why (an operator stop of
  a rule hold), `stopped by operator`, and `stopped <halt> (was held: <why>)`. All of these are
  `story_state` events for the same story. `run_ended` ends every hold.

## #85 Design

On its next poll after a hold event, the bridge does the following.

1. **Run issue (manifest runs).** The bridge keeps the set of held stories in the run's state
   (`st["held"]`, a list of story ids). The first story to be held sets the Run issue to `blocked`.
   Every hold also posts the **hold notice** on the Run issue. When a `story_state` for a held story
   takes the last one out of the set, and the run has not ended, the Run issue goes back to
   `in_progress`. `run_ended` empties the set and keeps today's `done`. Every status write goes through
   `set_intended`, so the existing rules still apply: hands-off, repair-stopped, and a status someone
   else set. Single-plan runs keep today's Run issue writes: the story is the Run issue, which already
   goes `blocked` and gets the `held:` line.
2. **Kickoff issue (the request issue).** The same notice is posted there, starting with the marker
   `studio: [notify only] ` and ending with the notify-only line. When the kickoff is agent-assigned,
   Multica starts its agent on a member comment (spec 2026-10-03, Risks, probe 7). The agent's
   one-line reply is what reaches the operator's phone. **Narrow AC17 exception:** this is the only
   comment the bridge writes on the request issue. It goes through its own content-checked CLI method,
   `Cli.add_notice`, which refuses any text that lacks the marker and is not covered by `_guard`. The
   request issue stays in `cli.forbidden`, so `set_status` and `add_comment` there still raise
   `ForbiddenWrite`. The bridge never assigns it. When the bridge knows no request issue (the run was
   started from a terminal), no kickoff notice is sent.
3. **Expiry.** A stop caused by an expired hold posts the **expiry notice** to the Run issue (manifest
   runs) and to the kickoff issue.
4. **Banner.** Each hold and each expiry raises one macOS banner through `ctx.notify`. Its kind is
   unique to the event, `notice:<run key>:<event byte offset>`, so the once-per-outage dedupe never
   swallows it.
5. **Once per event.** The notices and the banner are writes in the event's fixed `pending` list,
   which is saved after each write. A re-poll or a bridge restart does not repeat them. This is the
   same guarantee every bridge write has today.
6. **Superseded holds** (planner's call). If a later `story_state` for the same story is already in
   the log lines read in the same poll, the hold is over before anyone could act on it. This happens
   when a run is adopted late or the bridge catches up after an outage. Such a hold gets no kickoff
   notice, no banner, and no Run status change. It also never joins the held set. Without that, a
   second, live hold read in the same poll would find the set non-empty and never block the Run
   issue. Only its Run-issue notice is still posted, as a record.
7. **Notify-only guards.** (a) The kickoff text says it is notify-only. (b) `agent-context.md`, which
   is appended to every agent session and so reaches existing agents, and `agent-instructions.md`
   (new agents) say: a comment that starts with the marker gets a one-line reply and nothing else.
   (c) `multica-deny.txt` denies `studio-overnight say|unsay|hold|resume|stop` to both Multica
   runtimes. The operator's terminal (mode 1, plain `claude` / `claude-gd`) does not read that file.
   (d) The command filter already ignores agent-authored comments. A test pins this for `/resume` and
   `/say`.

### Notice text (exact; `<run>` = the run dir basename, which `--run` accepts both inside and outside a project)

Held, manifest story `B` whose issue is `OMEG-117`:

```
studio: story B held: <why>
Until <YYYY-MM-DD HH:MM TZ local> (<until> UTC); then it stops.
Multica: on OMEG-117 post /say <text>, then /resume — or /stop.
Terminal: studio-overnight say B --run <run> -- <text> · studio-overnight resume B --run <run> · studio-overnight stop B --run <run>
```

- Single-plan: the first line is `studio: the run is held: <why>`, the Multica line names the Run
  issue, and the terminal commands use story `-`.
- A story with no issue (AC12, routed): the Multica line reads `Multica: B has no issue — use the terminal.`
- An `until` that does not parse: the second line reads `Until <until as given>; then it stops.`

Expiry: `studio: story B stopped — hold ran out with no reply. Why: <why>`. In a single-plan run:
`studio: the run stopped — hold ran out with no reply. Why: <why>`.

Kickoff version: the marker `studio: [notify only] ` takes the place of `studio: `, and one more line
follows: `Notify only: reply with one short line. Run no command; never resume, stop, say to or hold a story.`

Banner: `<story or "run"> held in <run>: <why>`. For an expiry: `<story or "run"> stopped in <run>: hold ran out`.

Local time is `time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(t))` on the bridge's Mac. Measured
with TZ=PST8PDT: `2026-10-04T01:00:00Z` → `2026-10-03 18:00 PDT`.

## #85 Acceptance criteria

1. Manifest run, story A held: the Run issue gets one `blocked` status call and the hold notice. A then
   `running`: the Run issue goes `in_progress`.
2. A and B both held: one `blocked` call. Resuming A writes no Run status. Resuming B then sets `in_progress`.
3. `run_ended` while A is held: the Run issue ends `done`, with no `in_progress` call after the hold, and
   the held set is cleared.
4. With a known request issue, a hold and an expiry each post exactly one comment on it, and each one
   starts with `studio: [notify only] `. With no request issue, nothing is posted there and nothing fails.
5. `Cli.add_notice` raises `ValueError` for text without the marker. On the request issue,
   `set_status` and `add_comment` still raise `ForbiddenWrite`.
6. Over a run with units, holds, a resume, an expiry and the end, the request issue gets no
   `issue status` call, and every `issue comment add` on it is a notice. The #72 wakeup rule still arms.
7. A stop whose why ends with ` (held 8h0m, no reply)` posts the expiry notice to the Run issue
   (manifest) and to the kickoff issue. A `stopped by operator` or a halt stop posts neither.
8. The hold notice carries the why, the local deadline and the UTC deadline, the story issue's
   identifier, and the three terminal commands with `--run <run dir basename>`, exactly as in the
   notice-text section above.
9. Single-plan: the Run issue's writes are what they are today (`in_progress`, `blocked`, then `done`,
   plus the `held:` line). The kickoff notice and the banner are added, and the commands name the Run
   issue and story `-`.
10. A hold and an expiry each give exactly one `ctx.notify` call, of kind `notice:<key>:<offset>`. A
    re-poll, and a restart with a fresh `Ctx` on the same state, repeat no notice and no banner.
11. A hold followed in the same read by `running` for the same story gets no kickoff notice, no banner
    and no Run status call. If B is held live in the same read, the Run issue still goes `blocked`.
12. A run state saved before this change (no `held` key) polls without error.
13. An agent-authored `/resume` or `/say x` on a held story's issue runs no verb.
14. `multica-deny.txt` holds the five verb rules. They match `studio-overnight resume B --run r`, `stop`,
    `say`, `unsay` and `hold`, and match none of `start --detach <m>`, `status`, `said B` and `next`.
15. `agent-context.md` and `agent-instructions.md` carry the notify-only rule.
16. Docs: the 2026-10-03 spec AC17 names the exception, and the README describes the notices and the
    unassigned-kickoff limit.
17. `git diff origin/main -- studios/game-dev/bin` is empty.

## #85 Limits (recorded, not fixed here)

- **An unassigned kickoff wakes no one.** A queued kickoff (#72) is unassigned, so the notice there is
  only a record. In that case the banner is the only alert (at the Mac). Waking that kickoff's agent
  needs either a mention (an AC18 carve-out) or a wakeup rule. Both are open and need a live probe
  (operator).
- Whether a bridge comment on an agent-assigned kickoff starts the agent, and whether its reply rings
  the phone: live check (operator), after install.

## #86 Plan-time probes (operator's rule)

In `studios/game-dev/skills/plan/SKILL.md`, a **Plan-time probes** paragraph opens §6, before the
self-review and the approval stop. No section is renumbered (S5 cites §7). The rule: when a plan
defines a measurement of engine or tool behaviour, and later tasks pin numbers from it or branch on its
result, the planner runs it during planning, before the approval stop:

- in the planning checkout, through the gated forms (`studio-gate godot -- …`, `studio-test --file …`);
- the result goes into the plan as a measured input, with the command and its output;
- any tracked file the probe regenerates is restored, or committed as an input;
- the execute-time task re-measures and must equal the plan's values (a mismatch is a BLOCK), instead
  of discovering them;
- where the plan models the behaviour, it ports the engine's own algorithm rather than fitting a formula.

A probe that cannot run headless at plan time (it needs a window or the Godot MCP) stays a run task, and
the plan states what happens for each possible outcome. The §6 self-review gains one check: every such
probe has a measured-input block, or is a run task with every outcome stated.

18. `test_plan_probe_rule` (tests/studio_test.sh) pins the key phrases, checks that the paragraph comes
    before `Reply **approve**`, and checks that it sits under `## 6.`.

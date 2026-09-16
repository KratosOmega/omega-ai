# omega-ai Reply Mode — Design

Date: 2026-09-16
Status: Approved for planning
Extends: `2026-09-13-global-skills-design.md` (the seventh skill and sixth
mode of the `omega` overlay; everything that spec says about packaging, the
mode file, the hooks and the toggle applies unchanged)

## Purpose

The six existing modes all shape how work is *done* — scheduled, saved,
merged, stopped. None of them shapes what the session *says*. That is the
gap this mode fills.

The failure it fixes is specific and repeatable. The user is a game and
tool developer, not a reader of stack traces. When the session explains a
problem or asks for a decision, it reaches for the vocabulary it was just
working in: file paths, node and function names, config keys, raw numeric
values, and a paragraph of them. The user has to translate all of it back
into the thing they actually care about — what the player will see, or what
breaks in the tool they are building — before they can answer. Decisions
get slower, and the session's explanation is noise in between.

This design adds a mode, `reply`, under which every explanation and every
decision the session hands to the user is expressed as **one concrete
scenario from the project's own world**, in at most five short lines, with
no implementation vocabulary in the prose. Code, commands, exact errors and
test results are never restyled — they stay verbatim, because precision is
the thing the user cannot reconstruct themselves.

Non-goals:

- It does not change what is true. It changes the vocabulary of an
  explanation, never its substance, its accuracy or its verdict. A failing
  test is reported as failing.
- It does not silence detail. "Technical version" gets the full detail, in
  the same turn, without clearing the mode.
- It is not a studio skill. It lives in `shared/omega` and applies in any
  studio and in plain `claude` with the plugin installed — a game project
  and a web tool get scenarios from their own world, not from a game either
  way.
- No new hook file. `prompt-submit.sh` gains one `case` arm; nothing else
  in the hook set changes.

## What done looks like

1. `/omega:reply` sets the mode; `/omega:reply off` clears it. The mode line
   is re-injected at the top of every turn by the existing
   `UserPromptSubmit` hook, so the style survives compaction and a
   forty-turn session — the drift this mode exists to stop.
2. While the mode is set, an explanation or a decision arrives as one
   scenario from the project's world, five short lines or three bullets at
   most, with no path, symbol, config key, library name or raw threshold
   value in the prose.
3. A decision arrives in a fixed shape: the situation, two or three choices
   described by what each one feels like, then the session's pick and a
   one-line reason.
4. Code blocks, commands to run, exact error text, test counts, verification
   claims and safety warnings are unchanged by the mode.
5. `sh tests/run_all.sh` passes, including a new contract test for the skill
   text, the hook toggle tests, the brief line, and the updated skill counts.
6. `./doctor.sh game-dev` reports `global plugin: omega 0.1.0   skills 7
   hooks present`.

## Decisions

| # | Decision | Alternative rejected |
|---|---|---|
| 1 | The style fires on explain and decide moments only | Every reply — a one-line status ("done, 12 tests pass") would grow a scenario it does not need |
| 2 | A mode, toggled like `delegate` | A one-shot skill — the style drifts back within a few turns, which is the failure being fixed |
| 3 | The scenario's world matches the project: a game project gets what the player sees, any other project gets what the user of that tool hits | Always a game scenario — forced for a dashboard bug |
| 4 | Code blocks are exempt; the prose around them carries no implementation vocabulary | No code at all — the user often wants the snippet, just not the lecture |
| 5 | Hard cap: five short lines or three bullets, exactly one scenario | "Keep it short" — an uncountable rule slides back |
| 6 | A decision has a fixed three-part shape | Free-form — the user cannot tell where the recommendation is |
| 7 | Typed per session, like every other mode | On by default in shared studio config — it would apply where raw technical output is wanted, and lose the on/off trail |
| 8 | Composes with a compression style (`caveman`): this mode chooses what the explanation is about, the compression style chooses how tight the wording is | One overrides the other — they operate on different axes |
| 9 | The precedence block is reply-specific, not byte-identical to `parallel`'s | Reusing the five-mode block verbatim — its first sentence ("how work is scheduled, saved, merged or stopped") is false for this mode, and a false sentence in a rulebook is worse than a parallel structure |

## Packaging and loading

Only the additions to the tree in the 2026-09-13 spec:

```
shared/omega/
├── skills/reply/SKILL.md           the rulebook (full text below)
└── bin/omega-mode                  mode_brief gains the reply line
docs/omega/pressure/reply.md        the pressure scenarios
tests/omega_contracts/reply_contract.sh
```

`plugin.json` and `marketplace.json` descriptions become "…: handoff,
parallel, local-merge, integration, autopilot, delegate, reply." The
SessionStart line gains `/omega:reply [off]` after `/omega:delegate [off]`;
the Mode tool and Keep-awake sentences are unchanged. `README.md` gains a
row in the global-skills table and a name in the layout block.

## The toggle

`/omega:reply` sets `reply` with `omega-mode set reply`; `/omega:reply off`
clears it. `prompt-submit.sh` gains a `reply` case identical in shape to
`delegate`'s: `off` clears, an empty argument sets, anything else is
ignored. The skill opens by running the same command, so the Skill-tool path
converges on the file as every mode does.

`mode_brief` prints this line when the file lists `reply`:

```
  reply: explain and decide in one concrete scenario from the project's world, five lines at most; no paths, symbols, config keys or raw values in the prose; code, commands, exact errors, test results and warnings stay verbatim.
```

## The rules

**When it fires.** An *explain moment*: the user asks why, what, how or for
an explanation; or the session surfaces a problem, a trade-off, a risk or a
decision for the user to make. Also the option text of a question put to the
user.

**When it does not fire.** A status line ("done, 12 tests pass", "pushed").
A direct factual lookup the user asked for by name ("which file holds the
hook?" — answer the path). The content of code, commands, plans, specs,
commit messages, PR bodies and any other file or message that persists
outside the conversation: those are written for other readers and keep their
normal register. Subagent briefs are unaffected.

**The scenario.** One, and concrete. In a game project it is what the player
sees, feels or does: *"enemy freezes for half a second before it charges"*.
In any other project it is what the user of that thing hits: *"the dashboard
stays blank for three seconds after login"*. It describes the observable
situation, never the mechanism that produces it.

**Banned in the prose.** File and directory paths; function, class, method
and node names; config and setting keys; library, framework and tool names;
raw numbers used as thresholds or values. A value is described by what it
feels like at each end — *"small, and the hit lands like nothing; big, and
the screen shakes so hard the player loses the enemy"* — never as a number
the user has to interpret.

**A decision's shape.** Three parts, in order: the situation in one line;
two or three choices, each one line, each described by what it feels like to
play or to use; the session's pick with a one-line reason. Nothing else.

**The cap.** Five short lines or three bullets, and exactly one scenario.
Longer means cut it, and offer the rest: *"want the deep version?"*.

## The precision floor

These are never restyled, shortened or softened, and the cap does not apply
to them:

- Code blocks and the commands the user is to run.
- Exact error text, quoted as the shortest decisive line.
- Test results, counts and any verification claim. A failure is reported as
  a failure, with its output. The scenario may frame *what the failure means
  for the player*, but never in place of the result.
- Security warnings and confirmations for destructive or irreversible
  actions — those are already exempt from compression styles and stay plain.
- A path, symbol or value the user explicitly asked for by name.

**"Technical version"** — or "show me the code", "be technical" — drops the
mode's styling for that one answer and returns full detail. The mode stays
set; the next explanation is styled again.

## With the other modes

- `autopilot` — under it the session does not ask; the rulings it logs are
  written to the plan file, which persists outside the conversation, so they
  keep their normal register. What `autopilot` *reports back* to the user is
  styled.
- `delegate` — subagent briefs and reports are session-internal machinery,
  not explanations to the user; they are unstyled. What the deck tells the
  user about a report is styled.
- `parallel`, `local-merge`, `integration` — untouched; those shape
  mechanics, this shapes prose. They never conflict.
- A compression style such as the `caveman` plugin composes on a different
  axis: this mode decides what the explanation is about, the compression
  style decides how tight the wording is. Both apply.

## Tests

Added to `tests/omega_test.sh`:

- `reply` joins the skill-file, frontmatter and `omega-mode` loops.
- `reply` is **not** added to the loop asserting the five-mode precedence
  sentence ("This mode changes how work is scheduled, saved, merged or
  stopped."); its own contract asserts its reply-specific block. The loop
  gains a comment saying why.
- Brief: `omega-mode set reply` alongside the others puts `reply` at the end
  of the heads line and prints the rule line above.
- Hook: `/omega:reply` with empty args sets `reply`; `/omega:reply off`
  clears it; `/omega:reply 3` changes nothing; the turn's context carries
  the rule line.
- SessionStart context names `/omega:reply [off]`.
- `plugin.json` and `marketplace.json` assertions become `delegate, reply\.`
  and their messages say "seven skills".

`tests/install_test.sh`: the doctor line becomes `skills 7`.

New `tests/omega_contracts/reply_contract.sh`, sourced like the others,
asserting the skill text carries: `omega-mode set reply`; its precedence
block; the explain-moment trigger; the one-scenario rule; the five-line cap;
the banned-vocabulary list; the three-part decision shape; the precision
floor including "test results" and "exact error text"; the "technical
version" escape; and the persisted-text exemption.

`docs/omega/pressure/reply.md` records the scenarios the skill text was
tested against, in the format the other six use:

1. **Jargon bait** — "why does my character stutter on slopes?" asked while
   the session has just read the movement script. Must answer with what the
   player sees, not with the node and function it just read.
2. **A number question** — "what should I set this value to?". Must answer
   by what each end feels like, and give a pick.
3. **A failing test** — the session must report the failure and its output
   exactly; a scenario may say what it means for the player, never replace
   the result.
4. **"Technical version"** — full detail returns in that answer, and the
   next explanation is styled again.
5. **A persisted artifact** — a commit message or spec written while the
   mode is set keeps its normal register.
6. **A status line** — "done, 12 tests pass" is not padded with a scenario.

## Docs

`README.md` gains the row:

| `/omega:reply` | Explanations and decisions arrive as one concrete scenario from the project's world — what the player sees, or what the tool's user hits — in five lines at most, with no implementation vocabulary in the prose; code, exact errors and test results stay verbatim; `off` clears it |

and `reply` is added to the skills line of the layout block. The sentence
introducing the table ("these six skills") becomes seven. `docs/omega/
PROGRESS.md` gains the plan's entry on completion.

## Delivery

One plan, `docs/omega/plans/2026-09-16-plan-4-reply.md`, executed on a
branch off `origin/main`, reviewed, and merged as one PR. The skill text is
written first, then the wiring, then the tests, then the docs — each a
separate commit.

## `/omega:reply [off]` — the skill

```markdown
---
name: reply
description: Use when explanations and decisions should arrive as one concrete scenario from the project's world — what the player sees, or what the tool's user hits — instead of implementation vocabulary; code, exact errors and test results stay verbatim.
---

# Reply

**Announce at start:** "Using omega:reply."

Run first: `omega-mode set reply` — `omega-mode clear reply` for `off`.
`omega-mode` is on `PATH` inside a studio; the session-start line names its
path otherwise. The hook already set the mode when the command was typed;
running it again is harmless.

> This mode changes how the session explains itself to the user. It never
> changes what is true: a result, a verdict, a risk and a gate are reported
> exactly as they are. It never replaces the invoking skill; that skill keeps
> running and this mode shapes the words it hands to the user. When this mode
> and the invoking skill disagree about wording or framing, this mode wins;
> when they disagree about substance, accuracy or a gate, the invoking skill
> wins.

## 1. When it fires

An **explain moment**: the user asks why, what, how, or for an explanation;
or this session surfaces a problem, a trade-off, a risk, or a decision for
the user to make. The option text of a question put to the user counts.

It does **not** fire on:

- A status line — "done, 12 tests pass", "pushed", "branch created".
- A direct lookup the user asked for by name — "which file holds the hook?"
  is answered with the path.
- Anything that persists outside the conversation: code, commands, plans,
  specs, commit messages, PR bodies, documents, subagent briefs. Those are
  written for other readers and keep their normal register.

## 2. The scenario

One scenario, concrete, from the project's own world.

| Project | The scenario is |
|---------|-----------------|
| A game | What the player sees, feels or does — "the enemy freezes for half a second before it charges" |
| Anything else | What the user of that thing hits — "the dashboard stays blank for three seconds after login" |

It describes the observable situation, never the mechanism behind it. One
per explanation; a second scenario means the answer is too long.

## 3. Banned in the prose

File and directory paths. Function, class, method and node names. Config and
setting keys. Library, framework and tool names. Raw numbers used as
thresholds or values.

A value is described by what each end feels like:

> Small, and the hit lands like nothing. Big, and the screen shakes so hard
> the player loses the enemy.

Never as the number itself, and never as a range for the user to interpret.

## 4. A decision's shape

Three parts, in order, nothing else:

1. **The situation** — one line, what the user or player would hit.
2. **The choices** — two or three, one line each, described by what each one
   feels like to play or to use.
3. **The pick** — this session's recommendation and a one-line reason.

## 5. The cap

Five short lines, or three bullets. Exactly one scenario. Longer means cut
it and offer the rest — "want the deep version?".

## 6. The precision floor

Never restyled, never shortened, never softened, and the cap does not apply:

- Code blocks and the commands the user is to run.
- Exact error text — the shortest decisive line, verbatim.
- Test results, counts and every verification claim. A failure is reported
  as a failure with its output. A scenario may say what that failure means
  for the player; it never stands in place of the result.
- Security warnings and confirmations for destructive or irreversible
  actions.
- A path, symbol or value the user asked for by name.

**"Technical version"**, "show me the code", "be technical" — full detail
returns for that answer. The mode stays set; the next explanation is styled
again.

## 7. With the other modes

- `autopilot` — its logged rulings persist in the plan file, so they keep
  their normal register; what it reports back to the user is styled.
- `delegate` — briefs and subagent reports are machinery, not explanations;
  unstyled. What the deck tells the user about a report is styled.
- `parallel`, `local-merge`, `integration` — untouched. They shape
  mechanics; this shapes prose.
- A compression style such as `caveman` composes: this mode decides what the
  explanation is about, that style decides how tight the wording is.

## What this changes, and what it never changes

Changes: the vocabulary and the length of what the user reads. Never
changes: what is true, which gate holds, what a test returned, or what any
skill does next.

## Red flags — the jargon is about to come back

| Thought | Reality |
|---------|---------|
| "The file name makes it clearer" | It makes it clearer to you. Name what the player sees. |
| "This one needs two scenarios" | Two scenarios means two answers. Give the first, offer the second. |
| "The exact value is the answer" | Describe both ends by feel, then give your pick. |
| "It's a subtle bug, five lines is not enough" | Five lines and "want the deep version?". They will ask. |
| "The test failed, I'll soften it into a story" | The result is reported exactly. The story goes after it, not instead. |
| "They asked a technical question, so the mode is off" | One answer is technical. The mode stays set. |
| "The commit message should match my replies" | Persisted text keeps its normal register. |
```

## Out of scope

- Changing the five existing modes' shared precedence block.
- Any hook that inspects or rewrites the session's output. The mode is a
  rulebook plus the re-injected mode line, like every other mode.
- A translation table of canned analogies. Scenarios are written from the
  project in front of the session, not looked up.
- Turning the mode on by default in any studio's `CLAUDE.md`.

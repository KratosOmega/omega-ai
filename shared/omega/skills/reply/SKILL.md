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

- A status line — "done, 12 tests pass", "pushed", "branch created". Say the
  state and stop; a status never gets a scenario, not even a short one, and
  "there is nothing here yet" is a status.
- A direct lookup the user asked for by name — "which file holds the hook?"
  is answered with the path.
- Anything that persists outside the conversation: code, commands, plans,
  specs, commit messages, PR bodies, documents, subagent briefs. Those are
  written for other readers and keep their normal register.

When the answer is a status, a result, or a count — including a result the
user pasted — that answer is the status and nothing else. Give the state, or
give the numbers and the failing line back as they were written, and stop.
The rules below shape explanations; they never apply to a result. An
explanation of what the result means is a separate answer, offered after it
and only if the user wants it.

## 2. The scenario

One scenario, concrete, from the project's own world.

| Project | The scenario is |
|---------|-----------------|
| A game | What the player sees, feels or does — "the enemy freezes for half a second before it charges" |
| Anything else | What the user of that thing hits — "the dashboard stays blank for three seconds after login" |

It describes the observable situation, never the mechanism behind it. One
scenario per explanation; a second one means the answer is too long.

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
  for the player; it never stands in place of the result. When the user
  pastes or reports a result, give it back in its own terms first — the
  counts and the failing line as they were written — and only then say what
  it means. "Three of fourteen failed" is the result; "the hero stands
  still" is the meaning, and the meaning never replaces the numbers.
- Security warnings and confirmations for destructive or irreversible
  actions.
- A path, symbol or value the user asked for by name.

**Technical version** — "show me the code", "be technical" — returns full
detail for that answer. The mode stays set; the next explanation is styled
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
| "It's a subtle bug, five lines is not enough" | Five lines, then "want the deep version?". They will ask. |
| "The test failed, I'll soften it into a story" | The result is reported exactly. The story goes after it, not instead. |
| "They asked a technical question, so the mode is off" | One answer is technical. The mode stays set. |
| "The commit message should match my replies" | Persisted text keeps its normal register. |
| "A status is dull — one line of colour helps" | A status gets the state and stops. Colour on a status is padding. |
| "They already pasted the test output, repeating it is noise" | They pasted it to be read back. Counts and the failing line first, meaning second. |

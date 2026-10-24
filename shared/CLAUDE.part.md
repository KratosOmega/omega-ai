# Engineering Standards

Work to industry-standard engineering practice, and recommend it rather than
waiting to be asked.

- Favor composition over inheritance, and decoupled systems over shared state.
- Make data explicit: configuration and content belong in data files, not
  scattered through code.
- Profile before optimizing. Measure, then change one thing.
- Write tests for behavior you intend to keep.
- When a request would lead to an anti-pattern, say so and propose the standard
  alternative instead of silently implementing it.

# Decision Questions

Every option put to the user — an `AskUserQuestion` option or a choice in
prose — states its trade in its description:
`Gains: <what it buys: cleaner design, performance, debt avoided> · Costs: <tokens, time, risk, debt taken on>`.
State costs relative to the recommended option ("+1 task", "about twice the
tokens", "same"), and count future debt as a cost.

- Mark the recommendation `(Recommended)` and give the reason in one line,
  naming what it trades away.
- When the recommended option is not the one with the least future debt and the
  best long-term design, mark that one `(Best long-term)` and say what it costs
  beyond the recommendation. When they are the same option, its description
  says "Also the best long-term option."
- Never leave out an option because it costs more; the user may choose to pay.

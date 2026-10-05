You run omega-ai's game-dev studio for this project through `claude-gd`.

- Start an overnight run only with: studio-overnight start --detach <approved manifest>
  Never start a single-plan overnight run and never start one without --detach:
  the run must outlive your task.
- After starting a run, reply with the run name and stop. The board shows its
  progress; the operator steers it with comments.
- When you are woken because the sub-issues closed, read the Run issue's
  `studio: run ended:` comment (ending and report path), read that report, and post a short summary
  of the run on this issue: what landed, what stopped and why, what needs the
  operator.
- For adopted stories, include the report's studio-adopt line in your summary.
- Never change the status of a Run issue or a story issue, and never post
  comments that start with "studio: " — those belong to the bridge.

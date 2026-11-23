## Multica session context

- Your working directory is the game project. `git status` there must stay clean of Multica files.
- Put scratch files and comment bodies under the Multica workdir named on the last line, and nowhere else.
- Post a comment with `multica issue comment add <issue> --content-file <path> --allow-external-file`.
- Start overnight runs only with `studio-overnight start --detach <manifest>`. Never use a single-plan `start`.
- Never read `~/.multica` and never pass `--profile`.
- Comments starting `studio:` on this board come from the bridge, not from a person.
- A comment starting `studio: [notify only]` is a notice for the operator: reply with one line (the daemon posts your final message as the reply) that repeats its first line without the `studio: [notify only] ` marker, then stop. Run no command; never resume, stop, say to or hold a story.
- Before you run anything in a run worktree or a story worktree (`<project>/.claude/worktrees/…`), check that no other live Claude session is working inside it: ListAgents shows each session's folder, and each `sessions/<pid>.json` under `$CLAUDE_CONFIG_DIR` and `~/.claude` records it as `cwd` (a file whose `pid` is not alive, `kill -0 <pid>`, does not count). While one is inside, re-check every 10 minutes for up to 2 hours, then comment and stop. An open session anywhere else is never a reason to wait. This is the only session rule: a kickoff that asks for a session to be closed or quit first means this check.

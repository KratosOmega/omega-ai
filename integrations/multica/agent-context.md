## Multica session context

- Your working directory is the game project. `git status` there must stay clean of Multica files.
- Put scratch files and comment bodies under the Multica workdir named on the last line, and nowhere else.
- Post a comment with `multica issue comment add <issue> --content-file <path> --allow-external-file`.
- Start overnight runs only with `studio-overnight start --detach <manifest>`. Never use a single-plan `start`.
- Never read `~/.multica` and never pass `--profile`.
- Comments starting `studio:` on this board come from the bridge, not from a person.

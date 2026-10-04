
## Omega probe context

Your working directory is the game project (`OMEGA_PROJECT`), not your Multica
workdir. Your Multica workdir is the directory added with `--add-dir`; it holds
the `CLAUDE.md` with your identity and workflow.

- Put every scratch file and every comment body under the Multica workdir
  only, never inside the project. Post a comment from a file with
  `multica issue comment add <issue> --content-file <path> --allow-external-file`.
- Overnight runs start only with `studio-overnight start --detach <manifest>`.
- Canary rule: start every comment you post with `CANARY-7Q`.

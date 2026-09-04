---
name: repo-conventions
description: Use when starting work in an unfamiliar repository — establishes how to read its conventions before writing code.
---

# Repo Conventions

Before writing code in a repository you have not worked in:

1. Read the README and any `CONTRIBUTING` file.
2. Read the last twenty commits (`git log --oneline -20`) to learn the commit
   message style and the size of a typical change.
3. Find the test command and run it once, unchanged, to see the baseline.
4. Open two files near the code you will change and match their naming,
   comment density, and error-handling style.

Match what is there. Do not introduce a new pattern without saying why.

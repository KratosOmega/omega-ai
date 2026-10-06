# Game Development Memory

Durable, project-independent decisions for 2D game work. One line per memory,
pointing at a file in this directory.

<!-- Add entries as: - [Title](file.md) — hook -->
- [Wall-clock timing tests: min of two](wall-clock-timing-tests-min-of-two.md) — a duration assertion that passes alone and reds under the gate is load; sample twice, keep the shorter
- [Role agents have no Godot MCP](role-agents-have-no-godot-mcp.md) — subagents carry no MCP and the shim's MCP has no screenshot/input/run_script; plan visual playtest items for a human
- [Phoenix: sweep gate pins before merge.sh](phoenix-gate-pin-sweep-before-merge.md) — st.get count pin and MenuMetrics line anchors redden on drift; each gate run is 15–20 min
- [Pin the table, not the resolver](pin-the-table-not-the-resolver.md) — a resolver with a fallback makes a missing table entry pass a fixture test; assert the entry itself
- [Preview from real assets before approval](preview-from-real-assets-before-approval.md) — a visual spec's page emulates the real frames, sheet and formulas with the tuning knobs live; the user's approved values go into the spec
- [Phoenix: shake impulse floor](phoenix-shake-impulse-floor.md) — trauma² × 4 px rounds to 0 below ~0.35; seed a felt shake from 0.5, not player_jump_land's 0.04
- [Context doc at budget: plan the condensation](context-doc-at-budget-plan-the-condensation.md) — name the entry that gives up a line and prove no guarantee dropped; codepoints, not awk bytes
- [PROGRESS entry lands with the story PR](progress-entry-lands-with-the-story-pr.md) — every post-merge docs commit is another 25-minute gate; producer before merge.sh
- [Phoenix: the LFS hook breaks a long rebase](phoenix-lfs-hook-breaks-long-rebase.md) — phantom "local changes" at a moving commit with a clean tree; rebase with core.hooksPath=/dev/null, and merge.sh hits it too
- [Stage pointer is per checkout](stage-pointer-is-per-checkout.md) — a story moves to its execute worktree by `studio-state handoff` (`take` by hand, `stories` from main); exit 4 is a story switch, never `--force` it unasked

---
name: pin-the-table-not-the-resolver
description: When an acceptance criterion names a data-table entry, test the table directly — a resolver with a fallback turns a missing entry into a passing fixture test
metadata:
  type: feedback
---

A golden-fixture test through a resolver proves the resolved output, not the table entry behind it. When the resolver
treats an absent entry as its default (absent == `{}`, "" or the slot default), the fixture passes whether or not the
entry exists, so the acceptance criterion that names the table is not actually verified.

**Why:** Knight Stomp (KAN-1295, 2026-09-18), plan Task 4: the plan's fixture could not observe
`DEFAULT_ACTION.Slam` or `SECONDS_BY_SLOT.Slam` in `AbilityAnim.resolve` because an absent key resolves to the same
value as the authored default; AC 9 named both tables under `Verify: unit`, so a direct pin on each table was added
to `ability-anim-model.test.ts` alongside the fixture.
**How to apply:** when a spec's AC or a plan's verify line names a table, constant or registry entry, write one
assertion on the entry itself (`expect(TABLE.Key).toEqual(...)`) in addition to any end-to-end fixture; in review,
ask "would this test still pass if the entry were deleted?" — if yes, it does not cover the AC.

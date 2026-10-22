# Spec-driven development

`docs/SPEC.md` is the source of truth for scope, assumptions, and acceptance criteria. Code follows the spec, not the other way around.

## Layout

```
docs/
├── SPEC.md        # scope, assumptions, features: acceptance criteria + task checklist
└── DECISIONS.md   # decision / AI-usage / time log (see decisions-log.md)
```

No separate per-feature plan files — the task checklist lives under each feature in `SPEC.md`.

## SPEC.md

- Sections: Goal, In scope / Out of scope, Assumptions, Features.
- Each feature has:
  - numbered acceptance criteria with a stable ID: `<AREA>-<n>` (e.g. `DATA-1`, `LIST-2`, `DETAIL-4`, `BID-3`, `TIME-1`). One criterion = one observable behavior.
  - a short task checklist (`- [ ]`), ticked off as work lands.
- Keep it short (≈1–2 pages). It is a contract, not documentation of the code.
- Changes to scope or assumptions are made in the spec first and need the user's approval.

## Per-feature workflow

1. Read `docs/SPEC.md` before starting any feature work. If the feature has no acceptance criteria yet, add them and get them approved before writing code.
2. Implement in the feature worktree, ticking the feature's checklist in `SPEC.md`. Every criterion is covered by a test that references its ID:
   - logic → Swift Testing: `@Test("BID-3: bid below minimum is rejected")`
   - key user journeys → a small set of Maestro flows tagged with the IDs they cover (see `maestro-testing.md`); not every criterion needs a UI flow.
3. If implementation forces a decision the spec does not cover, or contradicts it, update `SPEC.md` in the same branch, log it in `DECISIONS.md`, and call it out to the user.
4. Once tests pass, add doc comments to the feature's methods in a separate commit — see `code-comments.md`.
5. Feature done = all its criteria covered by passing tests + checklist complete + methods commented.

## Rules

- No feature code without criteria in the spec. Small polish/refactors are exempt.
- Never silently diverge from the spec — update it or ask.
- Spec and plan edits go through the feature (or `chore/spec`) worktree like code; they are not covered by the repo-level docs exemption in `worktrees.md`.
- The submission README "Assumptions and Scope" and "Notable Decisions" sections are derived from `SPEC.md`.

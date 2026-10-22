# Decision, AI-usage, and time log

`docs/DECISIONS.md` is a running log that feeds the submission README ("Time Spent", "Notable Decisions", "What I'd Do With More Time") and the walkthrough ("why", "what you cut", "how you used AI"). Write entries as you go — never reconstruct at the end.

## Format

Three sections, append-only, newest at the bottom, one line per entry:

```markdown
## Decisions
- 2026-10-22 — Bids kept in memory, no persistence. Why: prototype, no backend; reset on launch keeps demo predictable. Alt: SwiftData (cut, time).

## Time
- 2026-10-22 — Spec: 20 min
- 2026-10-22 — Data + domain + tests: 50 min

## AI usage
- 2026-10-22 — Claude Code drafted SPEC.md from the brief; I trimmed scope and set bid increment rule.
```

## When to add an entry

- **Decisions:** any choice a reviewer might ask "why?" about — scope cuts, assumptions (time normalization, bid increments, reserve logic), architecture deviations, library/no-library, anything that changes `SPEC.md`. Include the alternative considered.
- **Time:** when a feature/phase finishes (rough minutes, honest). Flag when cumulative time passes ~3 h, and before starting any stretch work.
- **AI usage:** what the AI generated, what the user changed/rejected, notable AI mistakes caught. Keep it factual.

## Rules

- Short: one line per entry, no essays.
- Edited on the feature branch alongside the work it describes.
- Absolute dates only.

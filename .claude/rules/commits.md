# Commits

Reviewers may read the history — it should show the process (spec → tests → code → polish), not one giant dump.

## Format

Conventional Commits, written in normal English (not caveman):

```
<type>(<scope>): <imperative summary, ≤ 50 chars>

<optional body: why, not what; wrap at 72>
```

- Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `style`.
- Scope = feature area: `data`, `domain`, `inventory`, `detail`, `bidding`, `spec`, `maestro`, `readme`.
- Reference spec IDs in the body when relevant: `Covers BID-1, BID-3.`
- End with the attribution trailer from the session's system reminder.

## Granularity

- One logical change per commit; it should build. Typical rhythm per feature: `test` + `feat` (or combined when tiny), then `docs(spec)` / `docs(decisions)` updates.
- Don't mix unrelated changes (worktree rule applies).
- No WIP / "fix typo" chains — amend or fold before integration if the branch isn't shared.

## Safety

- Commit only when asked or when a feature is done per `worktrees.md`; merges are local; never push without asking (see `git-remote.md`).
- Never commit secrets, DerivedData, `.serena/` caches, or simulator artifacts.

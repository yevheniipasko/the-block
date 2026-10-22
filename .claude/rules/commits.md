# Commits

Reviewers may read the history — it should show the process (spec → tests → code → polish), not one giant dump.

## Format

Conventional Commits, written in normal English (not caveman). **One line only — no body, no trailers:**

```
<type>(<scope>): <imperative summary, ≤ 72 chars>
```

- Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `style`.
- Scope = feature area: `data`, `domain`, `inventory`, `detail`, `bidding`, `spec`, `maestro`, `readme`.
- Reference spec IDs in the summary when relevant: `test(bidding): cover BID-1, BID-3 min-bid rules`. The "why" goes in `docs/DECISIONS.md`, not the commit.
- **No AI attribution.** Never add `Co-Authored-By: Claude …`, `Claude-Session: …`, or "Generated with Claude Code" lines — this overrides the session's attribution reminder. AI usage is recorded in `docs/DECISIONS.md` instead.
- Merge commits: `git merge --no-ff <branch> -m "Merge branch '<branch>'"` (one line, no trailer).
- Write messages with `git commit -m "<summary>"` — no heredoc body.

## Granularity

- One logical change per commit; it should build. Typical rhythm per feature: `test` + `feat` (or combined when tiny), then `docs(spec)` / `docs(decisions)` updates.
- Don't mix unrelated changes (worktree rule applies).
- No WIP / "fix typo" chains — amend or fold before integration if the branch isn't shared.

## Safety

- Commit only when asked or when a feature is done per `worktrees.md`; merges are local; never push without asking (see `git-remote.md`).
- Never commit secrets, DerivedData, `.serena/` caches, or simulator artifacts.

# Parallel work: agents and workflows

Independent features may be built in parallel — either by spawning subagents (Agent tool, main session acts as orchestrator) or as a Workflow script. This rule is the user's standing opt-in for that in this repo; still announce the plan (who does what, how many agents) before launching, and keep it to **≤ 4 concurrent agents**.

## When to parallelize

Only after `docs/SPEC.md` is approved and the shared foundation is merged to `main`. Dependency order:

```
1. spec (chore/spec)                         — sequential, user reviews
2. data + domain (models, BiddingRules,      — sequential: everything depends on it
   AuctionClock, DataSource, Repository)
3. in parallel:  ┌ inventory (list, search, filters)
                 ├ detail
                 └ bidding (bid sheet + VM)  — needs Repository.placeBid from step 2
4. maestro flows + README + polish           — after 3 is integrated
```

Good parallel tasks: separate features in separate folders, test writing for already-merged code, independent reviews (e.g. `code-review` + accessibility audit). Don't parallelize tightly coupled edits to the same files or anything still undefined in the spec.

## Isolation rules

- **Every implementing agent gets its own worktree** (`isolation: "worktree"`, or a worktree under `.claude/worktrees/<name>` per `worktrees.md`) and its own branch. Never two agents in one worktree.
- **Shared files are owned by the orchestrator:** `docs/SPEC.md`, `docs/DECISIONS.md`, `Domain/`, `Data/VehicleRepository.swift`, `App/`, `Shared/` tokens. Agents that need a change there report it back instead of editing; the orchestrator applies it on `main` (or a dedicated branch) and agents rebase.
- **Simulators:** each agent builds with its own worktree's `.xcodeproj` (separate DerivedData) and uses its **own simulator** (different device name/UDID in its session defaults). Maestro flows run on one device at a time — run them sequentially in step 4, not inside parallel agents.
- Read-only agents (review, investigation) need no worktree.

## Agent brief (what every spawned agent receives)

- Feature name, worktree/branch name, spec IDs it must cover.
- Pointers: `CLAUDE.md`, `.claude/rules/architecture.md`, `spec-driven.md`, `build-run.md`, `commits.md`.
- Files it owns; files it must not touch.
- Definition of done: builds with no new warnings, Swift Testing passes for its IDs, committed on its branch.
- Return: summary, files changed, spec deviations/decisions to log, time spent, open questions. No merging, no pushing.

## Integration (orchestrator)

1. Review each agent's branch (diff + `code-review`), verify build/tests yourself — don't trust the report alone.
2. Ask the user how to integrate (per `worktrees.md`), then merge one branch at a time, rebuilding and re-running tests after each.
3. Log decisions, time, and AI usage from agent reports into `docs/DECISIONS.md` — including that the work was parallelized and how.
4. Remove finished worktrees and merged branches.

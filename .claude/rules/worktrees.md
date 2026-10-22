# Feature work happens in git worktrees

Every feature, fix, or experiment gets its own worktree and branch. Do not edit feature code directly in the main checkout.

## Starting work

- Create the worktree under `.claude/worktrees/<name>` (git-ignored). Prefer the `EnterWorktree` tool; otherwise:
  ```sh
  git worktree add ".claude/worktrees/<name>" -b feature/<name> main
  ```
- `<name>` is short kebab-case describing the feature (e.g. `inventory-search`, `bid-flow`). Branch prefix: `feature/`, `fix/`, or `chore/`.
- Branch from `main` unless the feature depends on another in-progress branch — then say so.
- One feature per worktree. Unrelated work found along the way goes in a separate worktree or gets noted, not mixed in.

## While working

- Run all builds, tests, and file edits from inside the worktree path, not the repo root.
- Xcode/XcodeBuildMCP: point the project path at `.claude/worktrees/<name>/The Block.xcodeproj`. Each worktree gets its own DerivedData, so the first build there is a clean build.
- Commit on the worktree's branch; never commit feature work to `main` directly.

## Finishing

- Feature done = builds, tests pass, committed on its branch. Then merge into local `main` (`git merge --no-ff`) and tell the user — no PRs, never push (see `git-remote.md`).
- After integration, remove the worktree (`ExitWorktree`, or `git worktree remove ".claude/worktrees/<name>"`) and delete the merged branch.

Exempt: edits to repo-level docs/config (`CLAUDE.md`, `.gitignore`, `.claude/`) can happen in the main checkout.

# Local-only git: never push without asking

All git work in this repo stays local. The remote (`origin`, the user's fork) is touched only when the user explicitly asks in the current conversation.

## Never without an explicit request

- `git push` (any branch, any flags — especially `--force`), `git push --tags`
- `gh pr create`, `gh pr merge`, `gh repo …` write operations, or any other GitHub write
- Changing remotes (`git remote add/set-url/remove`)

Before any of these, **stop and ask**, stating exactly what will be sent: remote, branch, commit range (`git log --oneline origin/main..HEAD`), and whether it rewrites history. Approval covers that one push only — ask again next time.

Reading the remote is fine without asking: `git fetch`, `git log origin/…`, `gh repo view`, `gh api` GET requests.

## Integration is local

- Feature done (per `worktrees.md`) → merge into local `main` with `git merge --no-ff <branch>`, then `git worktree remove` and `git branch -d`. Tell the user it was merged; no PR.
- Don't merge if the build or tests fail on the branch, or if the merge has conflicts — report and ask.

## Enforcement

`.claude/settings.json` sets `git push` and `gh pr create/merge` to **ask**, so the harness prompts even if this rule is missed. Do not try to work around the prompt (e.g. via another shell or alias).

## Submission

Pushing to the fork happens once, at submission time, when the user says so.

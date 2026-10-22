# Building and running

Build, run, and test through tooling — never ask the user to press ⌘R in Xcode to verify something you can check yourself.

## Tool preference

1. **XcodeBuildMCP** (default): `session_show_defaults` first in every session, fix project/scheme/simulator with `session_set_defaults` if wrong, then `build_sim` / `build_run_sim` / `test_sim`. Use `screenshot` / `snapshot_ui` to look at the running app.
2. **Xcode native MCP** (`xcrun mcpbridge`, Xcode 26.3+): use when it is connected in the session and the user has the project open in Xcode — e.g. to build/run in the user's open Xcode window or read Xcode's issue navigator. It acts on the project Xcode has open, so make sure that is the worktree's `.xcodeproj`, not the main checkout's.
3. **`xcodebuild` CLI** (fallback, and for anything the MCPs can't do): commands in `CLAUDE.md` → "Build / run / test". Pipe through `xcbeautify` if installed; otherwise use `-quiet` and grep for `error:` / `warning:`.

If an MCP build is cancelled or hangs on a DerivedData lock, use the `kill-build` skill before retrying.

## Rules

- Always build from the current worktree: project path `.claude/worktrees/<name>/The Block.xcodeproj`, scheme `The Block`. Never build the main checkout while working on a feature.
- Use one simulator for the whole session (a recent iPhone on the iOS 27 runtime); set it once in session defaults. Use an iPad simulator only to check adaptive layout.
- A change is verified when: build succeeds with no new warnings → `test_sim` (Swift Testing) passes → the app runs and the changed screen was checked (screenshot or XCUITest, see `ui-testing.md`).
- Report build/test failures with the exact error lines; don't summarize them away.
- The submission README's run instructions must work for a plain `xcodebuild` / Xcode ⌘R user — no MCP required.

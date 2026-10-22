# UI testing with Maestro

User-visible flows are tested with Maestro, not XCUITest. Swift Testing (`The BlockTests`) still covers models, decoding, and business logic. Do not add tests to `The BlockUITests`.

## Layout

```
maestro/
├── config.yaml              # optional: shared flow config
├── flows/<area>-<name>.yaml # one flow per user journey, e.g. bid-place-valid.yaml
└── subflows/                # reusable steps (launch + wait for list, open first vehicle, ...)
```

Maestro flows live in the repo root `maestro/` folder and are committed on the feature branch with the code they test.

## Writing flows

- `appId: com.softie.dev.The-Block`; start every flow with `launchApp` (use `clearState: true` so bids from previous runs don't leak).
- Select elements by accessibility identifier (`id:`), not by visible text, except when asserting copy. Add `.accessibilityIdentifier(...)` to every view a flow taps or asserts on. Identifier format: `<screen>.<element>` (e.g. `list.searchField`, `detail.placeBidButton`, `bid.amountField`).
- Tag each flow with the spec criteria it covers (see `spec-driven.md`), plus `smoke` for the core happy paths:
  ```yaml
  appId: com.softie.dev.The-Block
  tags: [smoke, BID-1, BID-4]
  ---
  - launchApp:
      clearState: true
  ```
- Assert the visible outcome (`assertVisible`, `assertNotVisible`), not just that taps succeed. A bid flow must assert the updated current bid / bid count / high-bidder state.
- Images are network-loaded placeholders: never assert on image content; use `extendedWaitUntil` instead of fixed sleeps when waiting for content.
- Keep flows short and independent; share setup via `runFlow: subflows/...`.

## Scope (timebox)

Cap at **3–4 flows** covering the core journeys, all tagged `smoke`:

1. `browse-search.yaml` — list loads, search narrows results, empty state.
2. `detail-open.yaml` — open a vehicle, specs/condition/dealership visible.
3. `bid-place-valid.yaml` — place a valid bid, updated bid/count/high-bidder state visible on detail and back in the list.
4. `bid-reject-below-min.yaml` — bid below minimum is rejected with a message.

Edge cases and rules are covered by Swift Testing, not extra flows. Add a flow beyond these only if a bug was found that only a UI flow can catch — and ask first.

## Running

- Build and install on the simulator first (XcodeBuildMCP `build_run_sim`, pointing at the worktree's `.xcodeproj`).
- **Run flows with the CLI, always passing the simulator UDID:**
  `maestro --device <UDID> test maestro/flows` (all) or `maestro --device <UDID> test --include-tags smoke maestro/flows`.
- The Maestro MCP `run` tool currently fails here with "Device became unreachable during deviceInfo": its `list_devices` reports each booted simulator twice (as `simulator` and as `real` with the same id) and resolves to the unreachable "real" entry. Several Maestro MCP servers from other sessions also share the driver port. Use the MCP only for read-only `inspect_screen` / `take_screenshot` if they work; fall back to `maestro --device <UDID> hierarchy` and `xcrun simctl io <UDID> screenshot <path>`.
- Debug a failing step (hierarchy / screenshot) before changing the flow.

## When to run

- After finishing any UI change: run the flows for that area.
- Before calling a feature done: Swift Testing suite + all Maestro flows pass.
- The submission README's Testing section explains how to run both (including installing Maestro).

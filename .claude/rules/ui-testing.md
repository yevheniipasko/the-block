# UI testing with XCUITest

User-visible journeys are tested with Apple's native **XCUITest** (`The BlockUITests` target), run through `xcodebuild` — no third-party UI tooling. Swift Testing (`The BlockTests`) covers models, decoding, rules, repository, and ViewModels.

## Layout

```
The BlockUITests/
└── SmokeUITests.swift   # one XCTestCase per journey group; helpers at the bottom of the file
```

## Writing tests

- Classes are `@MainActor final class …: XCTestCase`; one `test…` method per journey; doc comment names the spec IDs covered.
- Launch with `app.launchArguments = ["-market", "off"]` for deterministic flows (no competing bids). Use `"fast"` only for live-update tests (other bidders act every second and always target your lots). See `LaunchOptions`.
- Find elements by accessibility identifier only (`<screen>.<element>`, spec UX-4): `app.descendants(matching: .any).matching(identifier:).firstMatch`. Add `.accessibilityIdentifier(...)` to every view a test taps or asserts on. Search uses `app.searchFields.firstMatch` (`.searchable` can't take an identifier).
- Use a fixed lot whose state is predictable at launch (timing is anchored at launch), e.g. `D-0010`: no bids, no Buy Now, live for ~1 h.
- Always `waitForExistence(timeout:)` before interacting; never `sleep`. Assert the visible outcome (marker / message / disabled button), not just that taps succeeded.
- Keep the suite small (smoke level): browse/search, open detail, valid bid, below-minimum rejection, live outbid. Edge cases belong in Swift Testing.

## Running

```sh
xcodebuild -project "The Block.xcodeproj" -scheme "The Block" \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 test
# UI tests only
xcodebuild ... test -only-testing:"The BlockUITests"
```

The scheme's test action runs both targets; UI tests are not parallelized. Screenshots for visual checks: `xcrun simctl io <UDID> screenshot <path>`; appearance / text size: `xcrun simctl ui <UDID> appearance dark`, `xcrun simctl ui <UDID> content_size accessibility-extra-large`.

## When to run

- After finishing any UI change: the UI tests for that area.
- Before calling a feature done: both test targets pass.

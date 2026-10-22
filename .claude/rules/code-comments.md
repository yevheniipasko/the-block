# Method comments after a feature is built

Once a feature works (builds, its tests pass), document its methods before calling it done. Comments are written last, against the final code, so they describe what actually shipped — not a plan that changed along the way.

## When

- Last implementation step of every feature, in the feature worktree, after tests are green and before merging.
- Own commit: `docs(<scope>): document <feature> methods` (one line, per `commits.md`).
- Comments only — no behavior changes in that commit. Rebuild and re-run tests after.

## What gets a comment

Every method and initializer the feature added or changed in:

- `Domain/` — every rule (`BiddingRules`, `AuctionClock`, mapping helpers).
- `Data/` — DataSource and Repository methods, `…Dto.toModel()` mappings.
- `Features/` — ViewModel methods and non-trivial computed properties.
- `App/` — factory and router methods.
- `Shared/` — formatters and reusable component initializers.

Skip: SwiftUI `body`, one-line pass-through properties, protocol conformances whose meaning is obvious (`id`, `==`), and test functions (their `@Test("ID: …")` name is the doc).

## Format

Swift doc comments (`///`), so they show in Xcode Quick Help:

```swift
/// Minimum amount the next bid must reach for this lot.
///
/// Current bid (or starting bid when there are no bids) plus the adaptive step
/// for the lot's price tier and activity level. Covers BID-2.
///
/// - Parameter vehicle: The lot being bid on.
/// - Returns: Minimum valid next bid in whole CAD dollars.
static func minimumNextBid(for vehicle: VehicleModel) -> Int
```

- First line: what it does, one sentence.
- Optional paragraph: the why or the non-obvious rule (thresholds, edge cases, spec assumptions). Reference spec IDs it implements.
- `- Parameter` / `- Returns` / `- Throws` only when they add information beyond the signature.
- Protocol requirements are documented on the protocol; the implementation adds a comment only if it behaves differently.
- Inside method bodies, comment only non-obvious lines. No comments that restate the code.

## Done

A feature is not done (per `spec-driven.md`) until its methods are commented and the comment commit builds with tests passing.

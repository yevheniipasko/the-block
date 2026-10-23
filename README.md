# The Block - iOS

A native SwiftUI buyer app for OPENLANE's "The Block" challenge: browse a live vehicle auction, inspect a lot, and bid (or Buy Now) while other bidders act in real time.

The original challenge brief is in [`Resources/README.md`](Resources/README.md).

## How to Run

Requirements: **Xcode 27.1+** (iOS 27 SDK) and an iOS 27 simulator. No accounts, keys, or backend.

1. Clone and open the project:
   ```sh
   git clone <this repo> the-block && cd the-block
   open "The Block.xcodeproj"
   ```
2. Xcode resolves the one Swift package (Swinject) automatically on first open.
3. Select the **The Block** scheme and an iPhone or iPad simulator (e.g. iPhone 17 Pro, iOS 27) and press **⌘R**.

From the command line:

```sh
# build and run tests (unit + UI)
xcodebuild -project "The Block.xcodeproj" -scheme "The Block" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# unit tests only
xcodebuild ... test -only-testing:"The BlockTests"
```

Launch arguments (optional, mostly for UI tests): `-market off` disables the simulated other bidders; `-market fast` makes them bid every second on your lots.

## What I Built

- **Inventory:** cards with photo, price, bids, km, location, live status + countdown, Buy Now price and your position. Search (make, model, year, lot, VIN, dealer), filters (status, body style, fuel, province, Buy Now) with removable chips, five sorts, result count, and **cursor pagination** (pages of 20 with a simulated network delay, "loading more" row, inline retry).
- **Vehicle detail:** swipeable gallery, specs (copyable VIN), condition grade with scale, report, damage notes, flagged rebuilt/salvage titles, seller, floor state (met / not met, never the amount), and a pinned action bar that changes as the auction moves from upcoming → live → ended.
- **Bidding:** the minimum next bid is explained ("Minimum $24,000 · step $1,000 · Hot lot, 14 bids"), quick-add buttons, inline validation, review → confirm, in-flight spinner with no double submit, success haptic. **Buy Now** has its own confirmation.
- **Live data:** the data layer behaves like a socket feed: a snapshot, then per-lot updates. A simulated market places competing bids every few seconds, so prices change while you watch. You can be **outbid** in the list, on the detail screen, and inside an open bid sheet, where the minimum is recomputed and your typed amount is revalidated.
- iPhone (stack) and iPad (split view), dark mode, Dynamic Type up to accessibility sizes, VoiceOver labels.

### Stretch

- **My bids:** every lot you bid on or bought, grouped Winning / Outbid / Won / Bought / Lost, regrouping live, with a toolbar badge showing your outbid count. Two demo positions are seeded at launch (one leading, one outbid) so it isn't empty. This is demo data, not real data.
- **Outbid banner:** appears over any screen when someone outbids you, with "Bid again".
- **Total cost estimate:** bid and Buy Now sheets show amount + buyer fee + documentation fee (simulated tiers), before taxes and transport.

## Stack

- **Frontend:** SwiftUI (iOS 27), Swift 5 mode with main-actor default isolation, Observation, Swift concurrency (`AsyncStream`).
- **Architecture:** MVVM + Repository + DataSource; one top-level `AppModule` owns a **Swinject** container; all dependencies are protocols injected through `init`.
- **Backend / database:** none. A simulated auction server (`SimulatedAuctionDataSource`) runs in-process on the bundled `vehicles.json`; bids live in memory and reset on launch.
- **Tests:** Swift Testing (unit), XCUITest (UI smoke flows).

```
The Block/
├── App/        TheBlockApp, AppModule (DI), LaunchOptions, Routers/
├── Domain/     VehicleModel, AuctionSchedule, AuctionStatus, BiddingRules, InventoryQuery, Paginator, BidPosition, FeeSchedule
├── Data/       VehicleDto (+ mapping), BundledVehicleLoader, SimulatedAuctionDataSource, DemoSeed, VehicleRepository, StreamBroadcaster
├── Features/   Inventory/, Detail/, Bidding/, MyBids/, Alerts/
└── Shared/     Formatting, Spacing, status display, AuctionStatusBadge, VehicleImage, loading/error components
```

## Assumptions and Scope

- **Auction timing.** The dataset only has start times (a week in April 2026). All starts are shifted by one offset so launch lands at the 60th-percentile start, and each auction runs **72 h**. About 75 are upcoming, 89 are live, and 36 are ended at launch. They keep rolling over while the app runs. States follow OPENLANE: Upcoming → Live → Sold / Pending - below floor / No sale / Purchased by you. Upcoming lots accept bids (like pre-sale proxy bids).
- **Adaptive bid step.** Price base ($200 under $10k, $500 to $30k, $1,000 above) × activity (½ for 1-3 bids, 1× for 4-9, 2× for 10+). Live auctioneers widen the step on hot lots and drop it when bidding stalls; bid count is the only activity signal in the data.
- **Floor price** = `reserve_price`; only "met / not met / no floor" is shown. **Buy Now** only while live; bids must stay below it.
- **One buyer, no accounts.** Bids and purchases are in memory. No checkout, payments, seller tools, or transport.
- **Simulated pieces are labelled as such:** the market, fees, latency, and the two seeded "My bids" positions.
- **Platform: native iOS, no desktop version.** The brief allows "a web or mobile application" on "the platform you choose"; the Minimum Bar's "desktop and mobile" reads as the responsive-web case, so I took it as "works on small and large screens": iPhone uses a navigation stack, iPad a split view. Xcode also lists a "My Mac (Designed for iPad)" run destination (on by default for iOS apps), which would run the iPad layout on an Apple Silicon Mac; I haven't tested or tuned it, and it isn't meant as a desktop app.

## Notable Decisions

- **Spec-driven.** `docs/SPEC.md` lists every acceptance criterion with an ID (e.g. `BID-3`); tests are named after the IDs they cover. `docs/DECISIONS.md` is the running log of decisions, time, and AI usage.
- **Live data as streams.** The data source exposes `vehicleFeed() -> AsyncThrowingStream` (like a WebSocket) plus request methods for bids/Buy Now; the repository caches the feed and fans it out as `AsyncStream`s; screens subscribe in `.task` and never assume a value read once stays current. Swapping in a real server only replaces the data source.
- **Pagination where the filtering happens.** Search/filter/sort run "server-side" before a page is cut (keyset cursor = last vehicle ID). Paging a client-filtered list would be wrong.
- **Swinject with a single module** and protocol injection: wiring lives in one place, everything below receives protocols through `init`, tests build objects directly with fakes. There is no Service layer because one data source and one domain action would make it pass-through. The triggers for adding it are written down in the architecture rule.
- **DTOs vs models.** `VehicleDto` mirrors the JSON exactly and never leaves `Data/`; mapping fails loudly with the field and lot on unexpected values. Placeholder image URLs are rewritten to PNG there (placehold.co serves SVG by default, which `AsyncImage` can't draw).
- **Native UI testing.** XCUITest instead of a third-party tool: nothing to install for reviewers; a `-market off|fast` launch argument makes flows deterministic or speeds up the live test.
- **Cut on purpose** (designed, listed under "Postponed" in the spec): proxy/max bidding, anti-sniping extensions, bid history, a simulated history report, counter-offers, watchlist, extra filters, an image cache.

## Testing

- **Unit (Swift Testing, `The BlockTests`):** domain rules (step tiers at every boundary, minimum bid, validation, Buy Now eligibility, auction timing and outcomes, fees), DTO mapping and decoding the real JSON, the simulated server and market, repository streams (snapshot, updates, reconnect), cursor paging, and every ViewModel (inventory paging/filters/live rows, detail, bidding including live minimum and outbid, My bids grouping, outbid alerts).
- **UI (XCUITest, `The BlockUITests`):** 7 flows: browse & search, open detail, place a valid bid, reject a bid below the minimum, get outbid live, open My bids and a lot from it, outbid banner → "Bid again".
- **Totals:** 185 tests (178 unit in 27 suites + 7 UI), all passing. No compiler warnings.
- **Manual / visual:** iPhone and iPad simulators, dark mode, largest accessibility text size (fixed a price line that wrapped mid-number in the narrow iPad sidebar).
- **Accessibility:** ran Xcode's accessibility audit on inventory, detail, and the bid sheet and fixed what it found (status badge contrast, icons that didn't scale with Dynamic Type). `.maestro/accessibility.yaml` screenshots the same screens for a visual check in dark mode at the largest text size.
- Tests run with a per-test time limit so a stuck async test fails fast instead of hanging the suite.

## Time Spent

About **8.5 hours** in one session (commits run 15:33–00:10), of which the core took about **3 hours**:

- **Core, ~3 h (15:33–18:39):** setup, spec, data/domain, app shell and pagination, the three screens, live streams, and the XCUITest smoke suite. At this point every core requirement was done and tested.
- **Stretch, ~1 h 45 (18:39–20:22):** outbid alerts, My bids, the total-cost estimate, app icon, README. Chosen because they make bidding clearer and more trustworthy.
- **Polish, ~2 h (20:22–22:33):** scroll performance, a design pass (one attempt reverted), the outbid banner restyle, two bug fixes (stale price after Buy Now, clipped toolbar badge), an accessibility pass, and doc comments.
- **Review, ~1 h 30 (22:35–00:10):** cross-checked the code with two AI reviewers (Claude `/code-review` and Codex `review`), had each of the 18 findings re-verified before fixing (1 rejected), and fixed the rest: paging that could skip rows under live bids, status filters going stale over time, the outbid banner hidden behind sheets, stale queued alerts, and smaller UI and data issues.

That's past the suggested 3-4 h, on purpose: the core was complete inside the timebox, and I spent the rest on depth rather than more features. If I'd had to stop at 4 h, I'd have shipped the core plus the outbid banner. The per-phase log is in `docs/DECISIONS.md`.

## How I Used AI

I built this with Claude Code as a pair programmer and orchestrator. I set the product and architecture decisions (OPENLANE-style states, the activity-based bid step, MVVM + Repository + DataSource with Swinject, live data as streams, native UI testing). Claude researched how real car auctions run (Copart, IAAI, ADESA), drafted the spec, wrote code and tests, and ran parallel sub-agents, one per screen, each in its own git worktree and simulator. It integrated the work, reran every test suite, and fixed what integration exposed (a reconnect bug, a deadlocking test, SVG placeholder images, a layout bug at large text sizes). At the end I had two AI reviewers (Claude and Codex) review the whole app independently, had separate agents try to disprove every finding, and only fixed what held up. Every decision and AI mistake caught is logged in `docs/DECISIONS.md`.

## What I'd Do With More Time

- **Proxy (max) bidding:** OPENLANE's real bidding primitive; the data source is already the place where it would live.
- **Anti-sniping:** extend a lot's end when a bid lands in the last minutes.
- **A real backend:** WebSocket feed + HTTP endpoints behind the existing `VehicleDataSourceProtocol`, with optimistic updates and reconciliation.
- **Watchlist and bid history** per lot.
- **Persistence** of the buyer's bids across launches, and an image cache.
- **Broader UI coverage:** snapshot tests for each screen in light/dark and at large text sizes.

# The Block — iOS Spec

Status: **draft for review** · Source brief: [`Resources/README.md`](../Resources/README.md)

## Goal

A buyer can browse a live vehicle auction inventory, judge a vehicle with confidence (specs, condition, damage, dealership, photos), and place bids — or Buy Now — with immediate, unambiguous feedback. Native SwiftUI, iPhone + iPad. Vocabulary and auction states follow OPENLANE Canada's buyer experience (Upcoming → Active → ended outcome; "floor price" for reserve).

## In scope

- Inventory list with search, a few filters, and sorting.
- Vehicle detail: photos, specs, condition, damage notes, title status, dealership, location, auction info.
- Bid flow: adaptive minimum step, validation, confirmation, updated visible state everywhere.
- Buy Now for lots that have a Buy Now price.
- Auction timing with Upcoming / Live / Ended states and countdowns, via time normalization.
- Adaptive layout (iPhone + iPad), dark mode, Dynamic Type, VoiceOver.

## Out of scope

Auth/accounts, backend/networking (except placeholder images), persistence across launches, seller/dealer tooling, checkout/payments (Buy Now marks the lot purchased, nothing more), push notifications (alerts are in-app only), the Closing phase, everything under Postponed.

## Assumptions

- **Single local buyer ("You").** Any bid you place makes you the high bidder.
- **Demo seed:** at launch you already lead on one active lot and are outbid on another, so "My bids" and the outbid state are visible without setup. Seeded positions are demo data, called out in the README.
- **Bids and purchases live in memory** in the repository; they reset on app launch. Keeps the demo predictable.
- **Time normalization:** dataset `auction_start` values (2026‑03‑31 … 2026‑04‑06, no timezone) are parsed as local time and shifted by one constant offset so that **app launch time lands at the 121st of 200 sorted start times** (60th percentile). Relative spacing is preserved.
- **Anti-sniping:** any bid in the last 2 min of an active lot pushes its end to 2 min after that bid (OPENLANE extends timers the same way).
- **Seller counter-offer (simulated):** when a lot ends below floor with you as high bidder, the seller counters at the midpoint between your bid and the floor, rounded up to $100. Your counter-counter is accepted only if it reaches the floor.
- **Auction duration: 72 h** from normalized start. Result at launch: ~36 ended, ~89 active, ~75 upcoming; states roll over while the app runs.
- **Upcoming lots accept bids** (like OPENLANE's pre-sale proxy bids / Copart preliminary bids). This also explains why some upcoming lots already have bids in the dataset. Buy Now is available only while Active.
- **Ended outcomes:**
  - you bought it via Buy Now, or you are the high bidder and the floor is met (or no floor) → **"Purchased by you"**
  - bids and floor met (or no floor) → **"Sold"**
  - bids but floor not met → **"Pending – below floor"** (if you lead, the seller counters — see NEGOTIATE; otherwise not simulated)
  - no bids → **"No sale"**
- **Floor price (= `reserve_price`):** amount never shown; buyer sees "Floor met", "Floor not met", or "No floor".
- **Minimum next bid:** no bids → `starting_bid`; otherwise `current_bid + step`.
- **Adaptive bid step = price base × activity multiplier** (mirrors live auctioneers dropping the increment when interest is low and raising it when a lot is hot; bid count is the activity signal because the data has no bidder IDs or bid timestamps):

  | Current bid | Base | Quiet (1–3 bids) ×½ | Active (4–9) ×1 | Hot (10+) ×2 |
  |---|---|---|---|---|
  | < $10,000 | $200 | $100 | $200 | $400 |
  | $10,000–$29,999 | $500 | $250 | $500 | $1,000 |
  | ≥ $30,000 | $1,000 | $500 | $1,000 | $2,000 |

  The step and its reason are shown to the buyer (e.g. "Step $1,000 · Hot lot, 14 bids"). Your bid raises the bid count, so the level can change after you bid.
- **Buy Now ceiling:** a bid must be below `buy_now_price`; at/above → rejected with "Use Buy Now instead".
- All money is whole CAD, formatted `$24,500`. Odometer in km.
- **Buyer fees (simulated):** buyer fee $300 under $10,000 · $500 for $10,000–$29,999 · 2 % at $30,000+; plus a flat $99 documentation fee. Estimate only, before taxes and transport (no buyer location without accounts).
- *(postponed with PROXY)* **Proxy bids live on the "server"** (the simulated data source), like real auctions: your max is never sent to other bidders, and the server answers competing bids for you.

## Features

### DATA — loading the inventory

- **DATA-1** All 200 vehicles decode from the bundled `vehicles.json` (snake_case, nullable `reserve_price` / `buy_now_price` / `current_bid`).
- **DATA-2** `auction_start` without timezone decodes; malformed dates fail decoding with a clear error, not a crash.
- **DATA-3** If loading fails, the app shows an error state with a retry, not an empty list.

Tasks:
- [x] Bundle `vehicles.json` in the app target
- [x] `VehicleDto` (decoding) + `VehicleModel` + enums (body style, transmission, drivetrain, fuel, title status); DataSource maps Dto → Model
- [x] Swinject via SPM; single `AppModule` (container, data registrations; `ViewModelFactoryProtocol` added with the first screen) — see `.claude/rules/architecture.md`
- [x] `VehicleDataSourceProtocol` + `BundledJSONDataSource`
- [x] `VehicleRepositoryProtocol` + `VehicleRepository` (load, expose vehicles, state: loading / loaded / failed)
- [x] Container smoke test (every registration resolves)
- [x] Decoding tests against the real JSON + a malformed fixture

### TIME — auction timing

- **TIME-1** Normalization shifts all starts by one offset so launch time = the 121st sorted start; spacing between auctions is preserved.
- **TIME-2** Status: `upcoming` when now < start; `active` when now ∈ [start, start + 72 h); `ended` otherwise, with outcome per Assumptions.
- **TIME-3** Countdowns update while on screen: Upcoming "Starts in …", Active "Ends in …" (`d h` > 1 day, `h m` > 1 h, `m s` under 1 h); "Ending soon" emphasis under 1 h.
- **TIME-4** A lot that changes state while viewed (upcoming → active, active → ended) updates its UI and actions without relaunch.
- **TIME-5** *(postponed — see Postponed)* Anti-sniping: a bid (yours, market, or proxy) in the last 2 min of an active lot extends its end to bid time + 2 min; the countdown shows an "Extended" tag and every screen uses the new end.

Tasks:
- [x] `AuctionClock` (offset from dataset, injectable `now` for tests)
- [x] `AuctionStatus` + ended outcome
- [x] Countdown formatter + `TimelineView`-driven label
- [x] Tests with fixed `now` at each boundary

### LIST — browse & search

- **LIST-1** Inventory shows every vehicle as a card: first photo, year make model trim, current bid (or "Starting at" + starting bid), bid count, odometer, city/province, status badge + countdown, Buy Now price if present.
- **LIST-2** Search matches make, model, trim, year, lot, VIN, and dealership — case-insensitive, combinable with filters.
- **LIST-3** Filters: status (Upcoming / Live / Ended), body style, fuel type, province (multi-select each), "Buy Now available" toggle. Active filters are visible and clearable in one tap.
- **LIST-4** Sort: Ending soonest (default — active by end time, then upcoming by start, ended last), Price low→high, Price high→low, Newest year, Lowest km.
- **LIST-5** No results → empty state naming the query/filters with a "Clear" action.
- **LIST-6** Result count is visible ("142 vehicles").
- **LIST-7** Inventory loads in pages of 20 through a cursor, imitating a paginated API: next page loads when the list nears its end, with a loading row; changing search/filters/sort restarts from page one; a stale cursor (lot no longer matches) silently restarts; a failed page shows an inline retry. Bids placed after loading are reflected in loaded rows.
- **LIST-8** *(postponed — see Postponed)* Extra filters, combinable with LIST-3 and search, shown as clearable chips: make (multi-select from makes in the data), max price (current bid, or starting bid when no bids, ≤ the chosen amount), clean title only, no bids yet, under 50,000 km.
- **LIST-9** *(postponed — see Postponed)* Extra sorts: Best condition (grade high→low), Oldest year.

Tasks:
- [x] `InventoryQuery` (search/filters/sort, pure) + `Paginator` + `VehicleRepository.fetchPage` with simulated latency
- [x] `InventoryViewModel` (query → paged results by cursor, loaded IDs read live from repository)
- [x] Card + list view (a plain list on iPad too: the list lives in the split view's sidebar, where a grid doesn't fit)
- [x] Filter sheet + active-filter chips
- [x] Empty / error / loading states
- [x] ViewModel paging tests (first page, next page, reset on query change, stale cursor, failure)

### DETAIL — vehicle detail

- **DETAIL-1** Swipeable photo gallery with page indicator; loading placeholder and failure fallback per image.
- **DETAIL-2** Header: year make model trim, lot, status/countdown, current or starting bid, bid count, floor state, Buy Now price if present.
- **DETAIL-3** Specs: engine, transmission, drivetrain, fuel, odometer, body style, exterior/interior color, VIN (copyable).
- **DETAIL-4** Condition: grade (x.x / 5 with visual scale), condition report, damage notes list or "No damage reported", title status — rebuilt/salvage visually flagged.
- **DETAIL-5** Seller: selling dealership, city, province.
- **DETAIL-6** Bottom action bar is always reachable: "Place bid" (Upcoming/Active), "Buy Now $X" (Active, when priced); ended lots show the outcome instead of actions.
- **DETAIL-7** *(postponed — see Postponed)* Tapping the condition grade opens an explainer: the 0–5 scale with what each band means for a buyer (e.g. 4.0+ "light wear, retail-ready"; under 2.0 "major reconditioning"), highlighting this lot's band.

Tasks:
- [x] `VehicleDetailViewModel` (thin, injected `VehicleRepositoryProtocol`) + detail view sections
- [x] Gallery
- [x] Condition grade + title status components
- [x] Bottom action bar

### BID — bidding & Buy Now

- **BID-1** Bid sheet pre-fills the minimum next bid and explains it ("Minimum $24,000 · step $1,000 · Hot lot, 14 bids").
- **BID-2** Quick-add buttons (+1, +2, +5 steps) adjust the amount; manual entry accepts whole dollars only.
- **BID-3** Bids below the minimum are rejected with an inline message; the confirm button stays disabled.
- **BID-4** Bids at/above the Buy Now price are rejected with "Use Buy Now instead".
- **BID-5** Confirmation step shows vehicle, amount, and that the bid is binding; confirm places the bid.
- **BID-6** After placing: current bid = your amount, bid count + 1, "You're the high bidder" badge, floor state and activity level recomputed — visible on detail **and** in the list without refresh.
- **BID-7** Bidding on an ended lot is impossible (UI disabled + repository rejects).
- **BID-8** Success feedback: haptic + brief confirmation; failures never leave a half-updated state.
- **BID-9** Step follows the adaptive table (price base × activity level) at every tier/level boundary.
- **BID-10** Buy Now (Active lots with a price): confirmation shows price and that it ends the auction; confirm → lot ends as "Purchased by you" everywhere, all actions removed.
- **BID-11** Buy Now is unavailable on Upcoming and Ended lots (UI hidden/disabled + repository rejects).

Tasks:
- [x] `BiddingRules` (activity level, adaptive step, min next bid, validation, Buy Now eligibility) — pure, tested
- [x] `VehicleRepository.placeBid` / `buyNow` (validate via rules, update state, return result)
- [x] `BidViewModel` + bid sheet + confirmation
- [x] Buy Now confirmation
- [x] High-bidder / purchased badges in list + detail
- [x] Rule + repository tests

### LIVE — data changes at any time

- **LIVE-1** Data arrives as streams, as from a socket: the data source exposes `vehicleFeed()` (`AsyncThrowingStream`: snapshot, then per-lot updates); the repository caches it and fans out `AsyncStream`s (`loadStateUpdates()`, `vehicleUpdates(id:)`, `inventoryUpdates()`). Screens subscribe in `.task` (auto-cancelled) instead of reading once; no screen needs a reload to see a change.
- **LIVE-2** A simulated market places a competing bid every ~6 s on a random active lot (next minimum bid, below Buy Now), ~40 % of the time on a lot you're winning, so data changes while you watch.
- **LIVE-3** Outbid state (`isYouOutbid`) shows in the list card, the detail header, and an open bid sheet ("You've been outbid"); an open bid sheet recomputes its minimum live, keeps the typed amount, and re-validates it.
- **LIVE-4** A connection failure shows the load error with retry (reconnects the feed); bids/Buy Now that can't reach the server fail with "Couldn't reach the auction" and change nothing.

Tasks:
- [x] `VehicleDataSourceProtocol` as feed + bid / Buy Now endpoints; `SimulatedAuctionDataSource` (fake socket server: snapshot, echoes, market) + `BundledVehicleLoader`
- [x] `VehicleRepository` consumes the feed, caches, fans out streams; `StreamBroadcaster`
- [x] `isYouOutbid`, `BidRejection.connectionFailed`
- [x] Feed / market / stream tests
- [x] Inventory: subscribe to `loadStateUpdates()` + `inventoryUpdates()`, refresh loaded rows, outbid marker
- [x] Detail: subscribe to `vehicleUpdates(id:)`, outbid marker
- [x] Bidding: subscribe to `vehicleUpdates(id:)`, live minimum + outbid notice in the open sheet
- [x] Remove `@Observable` reads of the repository once all screens use streams

### MYBIDS — your bids & purchases *(built after LIVE is merged)*

- **MYBIDS-1** A "My bids" entry in the inventory toolbar opens a screen listing every lot you've bid on or bought this session (iPhone: pushed; iPad: replaces the list column).
- **MYBIDS-2** Lots are grouped by your position, in this order: **Winning** (high bidder, not ended), **Outbid** (not ended), **Won** (ended as "Purchased by you" via bid), **Bought** (Buy Now), **Lost** (ended any other way: sold to someone else, pending – below floor). Empty groups are hidden.
- **MYBIDS-3** Each row shows photo, title, lot, current bid, your bid (or purchase price), status/countdown, and the position badge; tapping opens the vehicle detail.
- **MYBIDS-4** Rows move between groups live (outbid by the simulated market, re-bid, auction ends) without leaving the screen.
- **MYBIDS-5** No bids yet → empty state ("You haven't bid on anything yet") with a "Browse inventory" action back to the list.
- **MYBIDS-6** The toolbar entry shows a count badge of lots where you're outbid (hidden at 0).
- **MYBIDS-7** At launch the data source seeds two demo positions (see Assumptions): you lead on one active lot and are outbid on another; both appear in "My bids" and carry their markers in the list and detail.

Tasks:
- [x] `BidPosition` (winning / outbid / won / bought / lost) — pure, derived from `VehicleModel` + `AuctionStatus`, tested
- [ ] `MyBidsViewModel` (subscribes to `inventoryUpdates()`, filters lots with `yourBid` or `yourPurchasePrice`, groups by position) + tests
- [ ] Router route + `ViewModelFactoryProtocol.makeMyBidsViewModel()`
- [ ] My bids view, empty state, toolbar entry with outbid badge
- [x] Demo seed in `SimulatedAuctionDataSource` snapshot (one leading, one outbid, both active) + test

### FEES — total cost estimate

- **FEES-1** The bid sheet and the Buy Now sheet show "Est. total $X" = amount + buyer fee + documentation fee (see Assumptions), with a breakdown on tap; it updates as the amount changes.
- **FEES-2** The estimate is labelled "Estimate · before taxes and transport".
- **FEES-3** Fee tiers switch exactly at $10,000 and $30,000.

Tasks:
- [x] `FeeSchedule` (pure) + boundary tests
- [ ] Estimate row + breakdown in bid and Buy Now sheets

### ALERT — outbid banner

- **ALERT-1** When you're outbid on any lot while the app is open, a banner appears over whatever screen is showing: "Outbid on 2021 Ford F-150 · now $31,000" with a "Bid again" action opening that lot's bid sheet.
- **ALERT-2** The banner auto-dismisses after ~4 s or on swipe; several outbids in a row queue instead of stacking.
- **ALERT-3** No banner for the lot whose bid sheet is open (the sheet shows its own notice, LIVE-3).
- **ALERT-4** The banner is announced to VoiceOver.

Tasks:
- [ ] `OutbidAlertCenter` (subscribes to `inventoryUpdates()`, detects your-bid → outbid transitions, queue) + tests
- [ ] Banner overlay in `InventoryRouterView`, "Bid again" routes to the bid sheet

### UX — cross-cutting quality

- **UX-1** iPhone: stack navigation. iPad: split view (list + detail side by side).
- **UX-2** Dark mode and Dynamic Type (up to accessibility sizes) without clipped content.
- **UX-3** VoiceOver: cards and bid controls have meaningful labels; status and prices read naturally.
- **UX-4** All tapped/asserted elements carry `<screen>.<element>` accessibility identifiers (for XCUITest).
- **UX-5** Every wait is visible: first inventory load shows a loading state (not an empty list); next page shows a loading row; failures show an error with retry (full-screen on first load, inline row on later pages); images show a placeholder while loading and a fallback on failure; placing a bid / Buy Now shows an in-progress state on the confirm button (inputs disabled, no double submit) during the simulated ~0.6 s round trip.
- **UX-6** *(postponed — see Postponed)* Loaded images are cached in memory by URL: scrolling back or reopening a lot shows the image without a placeholder flash or a new request.

Tasks:
- [x] Design tokens + formatters in `Shared/` (Spacing, Formatting, status display, `AuctionStatusBadge`, `VehicleImage`, `LoadingStateView` / `ErrorStateView` / `PageStatusRow`)
- [ ] Accessibility pass
- [x] XCUITest smoke tests: browse/search, open detail, valid bid, below-minimum, live outbid (see `.claude/rules/ui-testing.md`)
- [ ] Submission README

## Postponed (designed, deliberately not built — see DECISIONS)

Spec sections drafted earlier and parked for the timebox:

- **HIST — bid history per vehicle *(built after LIVE is merged)*** — needs a per-lot event log; the live feed shows the latest state, which covers the demo.
- **REPORT — vehicle history report (CARFAX-style, simulated)** — every record would be invented; the dataset's condition report and damage notes are the honest source.
- **PROXY — max bidding** — the strongest next step (OPENLANE's real primitive); needs server-side auto-bidding against the market and a second bid mode. Deferred for time.
- **NEGOTIATE — counter-offers below floor** — post-auction seller workflow; adds a negotiation state machine for one edge case.
- **SAVED — watchlist** — useful, but My bids already gives a personal list; deferred for time.
- **TIME-5 anti-sniping** (OPENLANE extends on late bids) — needs per-lot end times and makes every countdown mutable; deferred for time.
- **LIST-8 / LIST-9 extra filters and sorts** (make, max price, clean title, no bids, under 50k km; condition / oldest-year sorts) — easy extensions of `InventoryQuery`; the core filters cover the brief.
- **DETAIL-7 condition grade explainer** — copy-heavy; the grade scale and report already explain the lot.
- **UX-6 in-memory image cache** — `URLCache` already avoids most refetches; a custom cache adds code without a visible win at 200 lots.

Other buyer features considered:

OPENLANE / Copart / IAA buyer features considered and parked, with the reason:

- **Saved searches with match alerts** (OPENLANE) — name a query, get told when new lots match. Needs push notifications and a stream of new listings; our inventory is fixed at 200 lots.
- **Starting-bid drop alert on saved lots** (OPENLANE) — needs a simulated seller lowering prices; adds seller behaviour for one alert.
- **Transport booking and estimate** (OPENLANE) — needs the buyer's location (no accounts) and a rate table; belongs to checkout, which the brief excludes.
- **Pre-/post-sale inspection orders** (OPENLANE, DataScan) — an add-on purchase flow; checkout is out of scope.
- **Payment / checkout after a win** (OPENLANE) — excluded by the brief.
- **Arbitration / dispute after purchase** — post-sale process, no buyer-side value in a prototype.
- **Keys present, run & drive, primary/secondary damage, estimated retail value** (Copart, IAA) — not in the dataset; would be invented.
- **Step drops one activity level after each 6 h without a bid** — needs a synthetic last-bid time for dataset lots.
- **Inline "Your bids" strip in the inventory** (other implementation) — duplicates MYBIDS.

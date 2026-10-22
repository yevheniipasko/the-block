# The Block — iOS Spec

Status: **draft for review** · Source brief: [`Resources/README.md`](../Resources/README.md)

## Goal

A buyer can browse a live vehicle auction inventory, judge a vehicle with confidence (specs, condition, damage, dealership, photos), and place bids — or Buy Now — with immediate, unambiguous feedback. Native SwiftUI, iPhone + iPad. Vocabulary and auction states follow OPENLANE Canada's buyer experience (Upcoming → Active → ended outcome; "floor price" for reserve).

## In scope

- Inventory list with search, a few filters, and sorting.
- Vehicle detail: photos, specs, condition, damage notes, title status, dealership, location, auction info.
- Bid flow: adaptive minimum step, validation, confirmation, updated visible state everywhere.
- Buy Now for lots that have a Buy Now price.
- Auction timing with Upcoming / Active / Ended states and countdowns, via time normalization.
- Adaptive layout (iPhone + iPad), dark mode, Dynamic Type, VoiceOver.

## Out of scope

Auth/accounts, backend/networking (except placeholder images), persistence across launches, seller/dealer tooling, checkout/payments (Buy Now marks the lot purchased, nothing more), notifications, Closing/Pending negotiation phases, other bidders acting in real time (see Stretch).

## Assumptions

- **Single local buyer ("You").** Any bid you place makes you the high bidder.
- **Bids and purchases live in memory** in the repository; they reset on app launch. Keeps the demo predictable.
- **Time normalization:** dataset `auction_start` values (2026‑03‑31 … 2026‑04‑06, no timezone) are parsed as local time and shifted by one constant offset so that **app launch time lands at the 121st of 200 sorted start times** (60th percentile). Relative spacing is preserved.
- **Auction duration: 72 h** from normalized start. Result at launch: ~36 ended, ~89 active, ~75 upcoming; states roll over while the app runs.
- **Upcoming lots accept bids** (like OPENLANE's pre-sale proxy bids / Copart preliminary bids). This also explains why some upcoming lots already have bids in the dataset. Buy Now is available only while Active.
- **Ended outcomes:**
  - you bought it via Buy Now, or you are the high bidder and the floor is met (or no floor) → **"Purchased by you"**
  - bids and floor met (or no floor) → **"Sold"**
  - bids but floor not met → **"Pending – below floor"** (seller decides; not simulated)
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

Tasks:
- [x] `AuctionClock` (offset from dataset, injectable `now` for tests)
- [x] `AuctionStatus` + ended outcome
- [ ] Countdown formatter + `TimelineView`-driven label
- [x] Tests with fixed `now` at each boundary

### LIST — browse & search

- **LIST-1** Inventory shows every vehicle as a card: first photo, year make model trim, current bid (or "Starting at" + starting bid), bid count, odometer, city/province, status badge + countdown, Buy Now price if present.
- **LIST-2** Search matches make, model, trim, year, lot, VIN, and dealership — case-insensitive, combinable with filters.
- **LIST-3** Filters: status (Upcoming / Active / Ended), body style, fuel type, province (multi-select each), "Buy Now available" toggle. Active filters are visible and clearable in one tap.
- **LIST-4** Sort: Ending soonest (default — active by end time, then upcoming by start, ended last), Price low→high, Price high→low, Newest year, Lowest km.
- **LIST-5** No results → empty state naming the query/filters with a "Clear" action.
- **LIST-6** Result count is visible ("142 vehicles").
- **LIST-7** Inventory loads in pages of 20 through a cursor, imitating a paginated API: next page loads when the list nears its end, with a loading row; changing search/filters/sort restarts from page one; a stale cursor (lot no longer matches) silently restarts; a failed page shows an inline retry. Bids placed after loading are reflected in loaded rows.

Tasks:
- [x] `InventoryQuery` (search/filters/sort, pure) + `Paginator` + `VehicleRepository.fetchPage` with simulated latency
- [x] `InventoryViewModel` (query → paged results by cursor, loaded IDs read live from repository)
- [ ] Card + list/grid view (adaptive columns on iPad)
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

Tasks:
- [ ] `VehicleDetailViewModel` (thin, injected `VehicleRepositoryProtocol`) + detail view sections
- [ ] Gallery
- [ ] Condition grade + title status components
- [ ] Bottom action bar

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
- [ ] `BidViewModel` + bid sheet + confirmation
- [ ] Buy Now confirmation
- [ ] High-bidder / purchased badges in list + detail
- [x] Rule + repository tests

### UX — cross-cutting quality

- **UX-1** iPhone: stack navigation. iPad: split view (list + detail side by side).
- **UX-2** Dark mode and Dynamic Type (up to accessibility sizes) without clipped content.
- **UX-3** VoiceOver: cards and bid controls have meaningful labels; status and prices read naturally.
- **UX-4** All tapped/asserted elements carry `<screen>.<element>` accessibility identifiers (for Maestro).
- **UX-5** Every wait is visible: first inventory load shows a loading state (not an empty list); next page shows a loading row; failures show an error with retry (full-screen on first load, inline row on later pages); images show a placeholder while loading and a fallback on failure; placing a bid / Buy Now shows an in-progress state on the confirm button (inputs disabled, no double submit) during the simulated ~0.6 s round trip.

Tasks:
- [x] Design tokens + formatters in `Shared/` (Spacing, Formatting, status display, `AuctionStatusBadge`, `VehicleImage`, `LoadingStateView` / `ErrorStateView` / `PageStatusRow`)
- [ ] Accessibility pass
- [ ] 4 Maestro smoke flows (see `.claude/rules/maestro-testing.md`)
- [ ] Submission README

## Stretch (only after the above is done and time allows — ask first)

- Watchlist.
- "My bids" view.
- Simulated competing bids (outbid state + banner).
- Proxy / max bidding (OPENLANE, Copart, ADESA primitive).
- Step also drops one activity level after each 6 h without a new bid (closer to a live auctioneer; needs a synthetic last-bid time for dataset lots).
- Anti-sniping: a bid in the last minutes extends the timer (OPENLANE does this).
- Condition grade explainer.

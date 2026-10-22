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
- **Demo seed:** at launch you already lead on one active lot and are outbid on another, so "My bids" and the outbid state are visible without setup. Seeded positions are demo data, called out in the README.
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
- **Buyer fees (simulated):** buyer fee $300 under $10,000 · $500 for $10,000–$29,999 · 2 % at $30,000+; plus a flat $99 documentation fee. Estimate only, before taxes and transport (no buyer location without accounts).
- **Proxy bids live on the "server"** (the simulated data source), like real auctions: your max is never sent to other bidders, and the server answers competing bids for you.

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
- **LIST-8** Extra filters, combinable with LIST-3 and search, shown as clearable chips: make (multi-select from makes in the data), max price (current bid, or starting bid when no bids, ≤ the chosen amount), clean title only, no bids yet, under 50,000 km.
- **LIST-9** Extra sorts: Best condition (grade high→low), Oldest year.

Tasks:
- [x] `InventoryQuery` (search/filters/sort, pure) + `Paginator` + `VehicleRepository.fetchPage` with simulated latency
- [x] `InventoryViewModel` (query → paged results by cursor, loaded IDs read live from repository)
- [ ] Card + list/grid view (adaptive columns on iPad)
- [x] Filter sheet + active-filter chips
- [x] Empty / error / loading states
- [x] ViewModel paging tests (first page, next page, reset on query change, stale cursor, failure)
- [ ] `InventoryQuery`: make / max price / clean title / no bids / under 50k km filters + condition and oldest-year sorts; filter sheet + chips; tests (LIST-8, LIST-9)

### DETAIL — vehicle detail

- **DETAIL-1** Swipeable photo gallery with page indicator; loading placeholder and failure fallback per image.
- **DETAIL-2** Header: year make model trim, lot, status/countdown, current or starting bid, bid count, floor state, Buy Now price if present.
- **DETAIL-3** Specs: engine, transmission, drivetrain, fuel, odometer, body style, exterior/interior color, VIN (copyable).
- **DETAIL-4** Condition: grade (x.x / 5 with visual scale), condition report, damage notes list or "No damage reported", title status — rebuilt/salvage visually flagged.
- **DETAIL-5** Seller: selling dealership, city, province.
- **DETAIL-6** Bottom action bar is always reachable: "Place bid" (Upcoming/Active), "Buy Now $X" (Active, when priced); ended lots show the outcome instead of actions.

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
- [ ] High-bidder / purchased badges in list + detail
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
- [ ] Detail: subscribe to `vehicleUpdates(id:)`, outbid marker
- [ ] Bidding: subscribe to `vehicleUpdates(id:)`, live minimum + outbid notice in the open sheet
- [ ] Remove `@Observable` reads of the repository once all screens use streams

### MYBIDS — your bids & purchases *(built after LIVE is merged)*

- **MYBIDS-1** A "My bids" entry in the inventory toolbar opens a screen listing every lot you've bid on or bought this session (iPhone: pushed; iPad: replaces the list column).
- **MYBIDS-2** Lots are grouped by your position, in this order: **Winning** (high bidder, not ended), **Outbid** (not ended), **Won** (ended as "Purchased by you" via bid), **Bought** (Buy Now), **Lost** (ended any other way: sold to someone else, pending – below floor). Empty groups are hidden.
- **MYBIDS-3** Each row shows photo, title, lot, current bid, your bid (or purchase price), status/countdown, and the position badge; tapping opens the vehicle detail.
- **MYBIDS-4** Rows move between groups live (outbid by the simulated market, re-bid, auction ends) without leaving the screen.
- **MYBIDS-5** No bids yet → empty state ("You haven't bid on anything yet") with a "Browse inventory" action back to the list.
- **MYBIDS-6** The toolbar entry shows a count badge of lots where you're outbid (hidden at 0).
- **MYBIDS-7** At launch the data source seeds two demo positions (see Assumptions): you lead on one active lot and are outbid on another; both appear in "My bids" and carry their markers in the list and detail.

Tasks:
- [ ] `BidPosition` (winning / outbid / won / bought / lost) — pure, derived from `VehicleModel` + `AuctionStatus`, tested
- [ ] `MyBidsViewModel` (subscribes to `inventoryUpdates()`, filters lots with `yourBid` or `yourPurchasePrice`, groups by position) + tests
- [ ] Router route + `ViewModelFactoryProtocol.makeMyBidsViewModel()`
- [ ] My bids view, empty state, toolbar entry with outbid badge
- [ ] Demo seed in `SimulatedAuctionDataSource` snapshot (one leading, one outbid, both active) + test

### HIST — bid history per vehicle *(built after LIVE is merged)*

- **HIST-1** The repository records a bid event (amount, time, bidder: you / another buyer) whenever a lot's bid count rises on the feed, and a purchase event on Buy Now. History lives in memory, from launch onward.
- **HIST-2** Detail shows a "Bid history" section: newest first, "$24,000 · You · 2 min ago" / "$23,500 · Another bidder · 5 min ago"; relative times update while on screen. Your entries are visually marked.
- **HIST-3** Bids that existed before launch (dataset `bid_count`) are summarized as one row ("12 earlier bids, before this session") — the data has no per-bid amounts or times, so none are invented.
- **HIST-4** Lot with no bids at all → "No bids yet · Starting at $X".
- **HIST-5** History shows the 5 newest entries, with "Show all (N)" expanding the rest.

Tasks:
- [ ] `BidEventModel` + repository recording on feed updates / Buy Now; `bidHistory(id:)` on `VehicleRepositoryProtocol` + tests (bid count delta → event, bidder attribution, purchase)
- [ ] `VehicleDetailViewModel` exposes history (live via `vehicleUpdates(id:)`) + tests
- [ ] Bid history section in detail

### REPORT — vehicle history report (CARFAX-style, simulated)

- **REPORT-1** Detail has a "Vehicle history" section with a summary (owners, accidents reported, last odometer reading, registered provinces) and a "View full report" action opening a sheet.
- **REPORT-2** The report is generated deterministically from the VIN (seeded), so the same lot always shows the same report across launches.
- **REPORT-3** The report stays consistent with the lot's data: odometer readings rise over time and end at `odometer_km`; `damage_notes` appear as reported incidents; rebuilt/salvage titles show a matching total-loss/rebuild record; clean-title lots have no total-loss record; registrations are in Canadian provinces ending in the lot's province.
- **REPORT-4** Full report lists dated events: registrations, ownership changes, odometer readings, service records, accidents/damage, title events, and lien status.
- **REPORT-5** Every report surface is labelled "Simulated report — demo data"; no CARFAX name or logo is used in the UI.

Tasks:
- [ ] `VehicleHistoryReport` model + `VehicleHistoryGenerator` (pure, seeded by VIN) in `Domain/` + tests (determinism, odometer monotonic and ending at `odometer_km`, title/damage consistency)
- [ ] `VehicleDetailViewModel` exposes the report + tests
- [ ] History summary section + full report sheet

### PROXY — max bidding

- **PROXY-1** The bid sheet offers "Set a max bid": you enter a ceiling ≥ the minimum next bid and below the Buy Now price (BID-3/BID-4 rules apply to the max). Confirm places the minimum next bid now and stores the max.
- **PROXY-2** When a competing bid arrives on a lot where your max is higher, the server immediately places your next minimum bid (by the adaptive step) on your behalf; you stay high bidder. When the competitor's bid reaches or passes your max, you're outbid and the proxy is spent.
- **PROXY-3** Your active max shows on the detail header, the bid sheet, and "My bids" rows ("Your max $26,000"); auto-bids placed for you are marked in bid history ("You · auto").
- **PROXY-4** You can raise your max or cancel it from the bid sheet while the lot is not ended; cancelling keeps your current bid. A max below your current bid is rejected.
- **PROXY-5** A proxy never bids above its max, after the lot ends, or at/above the Buy Now price.

Tasks:
- [ ] `BiddingRules.proxyResponse(...)` (pure: next auto-bid or nil) + tests at the max / Buy Now / ended boundaries
- [ ] `SimulatedAuctionDataSource`: store max per lot, answer market bids, push both updates; `setMaxBid` / `cancelMaxBid` endpoints + tests
- [ ] `VehicleModel.yourMaxBid`; bid sheet max mode; max shown on detail / My bids; HIST "auto" marker

### FEES — total cost estimate

- **FEES-1** The bid sheet and the Buy Now sheet show "Est. total $X" = amount + buyer fee + documentation fee (see Assumptions), with a breakdown on tap; it updates as the amount changes.
- **FEES-2** The estimate is labelled "Estimate · before taxes and transport".
- **FEES-3** Fee tiers switch exactly at $10,000 and $30,000.

Tasks:
- [ ] `FeeSchedule` (pure) + boundary tests
- [ ] Estimate row + breakdown in bid and Buy Now sheets

### ALERT — outbid banner

- **ALERT-1** When you're outbid on any lot while the app is open, a banner appears over whatever screen is showing: "Outbid on 2021 Ford F-150 · now $31,000" with a "Bid again" action opening that lot's bid sheet.
- **ALERT-2** The banner auto-dismisses after ~4 s or on swipe; several outbids in a row queue instead of stacking.
- **ALERT-3** No banner for the lot whose bid sheet is open (the sheet shows its own notice, LIVE-3), and none for outbids already absorbed by your proxy (PROXY-2).
- **ALERT-4** The banner is announced to VoiceOver.

Tasks:
- [ ] `OutbidAlertCenter` (subscribes to `inventoryUpdates()`, detects your-bid → outbid transitions, queue) + tests
- [ ] Banner overlay in `InventoryRouterView`, "Bid again" routes to the bid sheet

### SAVED — watchlist

- **SAVED-1** A heart on each card and in the detail toolbar saves / unsaves a lot; state shows immediately on both.
- **SAVED-2** A "Saved (N)" chip in the inventory shows only saved lots, combinable with search, filters, and sort; it's clearable like other filters.
- **SAVED-3** Saved lots live in memory in the repository (single source of truth) and reset on launch, like bids.
- **SAVED-4** No saved lots and the chip is on → empty state ("No saved vehicles yet") with a clear action.
- **SAVED-5** Placing a bid, setting a max, or Buy Now saves the lot automatically (like Copart); you can still unsave it.

Tasks:
- [ ] Repository: `savedIDs`, `toggleSaved(id:)` (+ stream update), `InventoryQuery.savedOnly` + tests
- [ ] Heart on card + detail, "Saved (N)" chip, empty state
- [ ] Auto-save on bid / max / Buy Now + test

### UX — cross-cutting quality

- **UX-1** iPhone: stack navigation. iPad: split view (list + detail side by side).
- **UX-2** Dark mode and Dynamic Type (up to accessibility sizes) without clipped content.
- **UX-3** VoiceOver: cards and bid controls have meaningful labels; status and prices read naturally.
- **UX-4** All tapped/asserted elements carry `<screen>.<element>` accessibility identifiers (for Maestro).
- **UX-5** Every wait is visible: first inventory load shows a loading state (not an empty list); next page shows a loading row; failures show an error with retry (full-screen on first load, inline row on later pages); images show a placeholder while loading and a fallback on failure; placing a bid / Buy Now shows an in-progress state on the confirm button (inputs disabled, no double submit) during the simulated ~0.6 s round trip.
- **UX-6** Loaded images are cached in memory by URL: scrolling back or reopening a lot shows the image without a placeholder flash or a new request.

Tasks:
- [x] Design tokens + formatters in `Shared/` (Spacing, Formatting, status display, `AuctionStatusBadge`, `VehicleImage`, `LoadingStateView` / `ErrorStateView` / `PageStatusRow`)
- [ ] In-memory image cache behind `VehicleImage` (`NSCache` by URL) + test
- [ ] Accessibility pass
- [ ] 4 Maestro smoke flows (see `.claude/rules/maestro-testing.md`)
- [ ] Submission README

## Stretch (only after the above is done and time allows — ask first)

- Step also drops one activity level after each 6 h without a new bid (closer to a live auctioneer; needs a synthetic last-bid time for dataset lots).
- Anti-sniping: a bid in the last minutes extends the timer (OPENLANE does this).
- Condition grade explainer.

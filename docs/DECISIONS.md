# Decisions, time, and AI usage

Running log — see `.claude/rules/decisions-log.md`. One line per entry, newest at the bottom.

## Decisions

- 2026-10-22 — Native SwiftUI (iPhone + iPad) instead of web. Why: platform strength; brief allows any stack. "Desktop and mobile" interpreted as iPhone + iPad adaptive layout.
- 2026-10-22 — MVVM + Repository + DataSource, no Service layer. Why: one data source and one domain action; a Service would be pass-through. Alt: Service → Repository → DataSource (deferred until triggers in `architecture.md`).
- 2026-10-22 — Swinject container owned by one top-level `AppModule` (registers and resolves everything; router gets a `ViewModelFactoryProtocol`, never the container), protocol-typed dependencies, one router; no per-feature injection modules. Why: wiring lives in exactly one place, every dependency is swappable/fakeable, and a Service layer slots in later without rewiring. Cost: ~30 min + one SPM dependency for a 3-screen app. Alt: manual composition root + `.environment` (lighter). Container is App-owned, not a singleton, so tests can build their own.
- 2026-10-22 — Spec-driven with criteria IDs referenced by tests. Why: makes AI-assisted work verifiable and traceable. Alt: full Spec Kit (cut, too heavy for timebox).
- 2026-10-22 — Maestro for UI flows (4 smoke flows), Swift Testing for logic; no XCUITest. Why: readable YAML flows, faster to author.
- 2026-10-22 — Auction states follow OPENLANE Canada (Upcoming → Active → Sold / Pending – below floor / No sale / Purchased by you), 72 h duration, launch time anchored at the 60th-percentile start (~75 upcoming / ~89 active / ~36 ended). Upcoming lots accept bids, like OPENLANE pre-sale proxy bids — which also explains dataset bids on not-yet-started lots. Alt: real 45-min auctions (only 1–2 active at a time, weak demo); live+ended only over 6 days (drops a state buyers actually see). Closing/Pending negotiation phases not simulated.
- 2026-10-22 — Buy Now is a core action (Active lots only), ends the lot as "Purchased by you"; bids must stay below the Buy Now price. Why: real OPENLANE feature, 39 lots have a price, ~20–30 min of work. Alt: price-only (brief excludes checkout) — rejected because no payment is involved, just a state change.
- 2026-10-22 — "Floor price" used as the buyer-facing term for reserve. Why: OPENLANE vocabulary.
- 2026-10-22 — Bids in memory, reset on launch. Why: no backend; predictable demo. Alt: SwiftData (cut, time).
- 2026-10-22 — Floor (reserve) amount hidden, only met / not met / no floor shown. Why: mirrors real auctions; still transparent to the buyer.
- 2026-10-22 — Adaptive bid step = price base ($200 / $500 / $1,000 at $10k / $30k) × activity (quiet ½, active 1×, hot 2× by bid count). Why: live auctioneers drop the increment when interest stalls and price tiers are universal (Copart UK table); bid count is the only activity signal in the data. Alt: flat $500 (matches the data's $500 grid — every current bid is a $500 multiple), price-only tiers, or time-decay on silence (moved to Stretch).
- 2026-10-22 — Decoded JSON types are `…Dto` and stay in `Data/`; app types are `…Model` (`VehicleModel`, `BidModel`), mapped in the DataSource. Why: file/wire shape (snake_case, raw strings, timezone-less dates) stays out of Domain and UI; swapping to a real API only touches Dtos + mapping. Alt: one `Codable` `Vehicle` used everywhere (fewer types, but couples app to JSON shape).

## Time

- 2026-10-22 — Setup: project rules, workflow, repo structure: ~30 min
- 2026-10-22 — Spec draft: ~15 min

## AI usage

- 2026-10-22 — Claude Code extracted requirements from the brief, proposed rules (worktrees, spec-driven, Maestro, architecture, commits, parallel work); I chose MVVM + Repository + DataSource and asked for the future Service-layer note.
- 2026-10-22 — Claude Code researched Copart/IAAI/ADESA bidding (auction duration, increments, Buy Now); I designed the activity-based step idea, Claude turned it into the table.
- 2026-10-22 — Claude Code researched OPENLANE Canada / ADESA buyer flows (states, proxy bids, Buy Now); I chose OPENLANE states with 72 h duration and Buy Now as core. Claude's first timing draft had an arithmetic error (claimed ~26 ended at 7 days; actually 0) — caught by recomputing against the data.
- 2026-10-22 — Claude Code profiled `vehicles.json` (date spread, bid/date correlation, bid multiples) to ground timing and increment assumptions, then drafted SPEC.md for my review.
- 2026-10-22 — I set the Dto/Model naming rule; Claude Code wrote it into `architecture.md` and chose plain names for enums/rules.

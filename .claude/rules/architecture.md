# Architecture

MVVM + Repository + DataSource. Sized for a 3–4 h prototype: every layer must have a job you can explain in one sentence. This rule overrides the global `swift-engineering-conventions` skill where they conflict (no Service/UseCase layers, no DI container, no per-layer protocols).

## Layers

```
View ──▶ ViewModel ──▶ VehicleRepository (@Observable, single source of truth)
                              │   vehicles + in-memory bids
                              ▼
                       VehicleDataSource (protocol)
                              └── BundledJSONDataSource

Domain/ — pure types and rules, no dependencies, used by every layer
```

| Layer | Owns | Must not |
|---|---|---|
| `Domain/` | `Vehicle`, `Bid`, `AuctionStatus`, `BiddingRules` (min next bid, increments, validation, reserve met), `AuctionClock` (time normalization) | import SwiftUI, hold state, do I/O |
| `Data/` DataSource | Loading + decoding `vehicles.json` (snake_case, nullable fields, timezone-less dates) | contain business rules |
| `Data/` Repository | Load once, expose `vehicles`, `placeBid(_:on:)` → applies `BiddingRules`, updates state, returns result | know about screens or formatting |
| `Features/<Screen>/` ViewModel | Screen-only state: search text, filters, sort, bid input, validation message, confirmation step | copy the vehicle array or own business rules |
| `Features/<Screen>/` View | Layout, bindings, accessibility ids | contain logic beyond trivial display conditions |
| `Shared/` | Formatters (CAD, km, dates), reusable components, design tokens | depend on features |

## Folder layout

```
The Block/
├── App/        The_BlockApp — composition root
├── Domain/
├── Data/       VehicleDataSource, BundledJSONDataSource, VehicleRepository, vehicles.json
├── Features/   Inventory/, Detail/, Bidding/
└── Shared/
```

## Rules

- **Single source of truth:** one `VehicleRepository` instance, created in `The_BlockApp`, injected via `.environment`. A bid placed anywhere is visible everywhere because every screen reads from it.
- **ViewModel only where there is real state.** Inventory (search/filter/sort) and Bidding (input/validation/confirmation) get one; a screen that just displays repository data (Detail) reads the repository directly. No empty pass-through ViewModels.
- **One protocol: `VehicleDataSource`** — the swap point for a future remote API and the seam for test fakes. No protocols for Repository, ViewModels, or Domain.
- **Isolation:** Domain and DataSource types are `nonisolated` (and `Sendable` where needed); Repository and ViewModels are `@Observable` on the main actor (default isolation).
- **Business rules are pure functions in `Domain/`** so they're tested directly with Swift Testing against spec IDs (see `spec-driven.md`).
- **Dependencies point inward:** Features → Data → Domain. Domain depends on nothing.
- No DI container, no coordinators/routers — `NavigationStack` / `NavigationSplitView` with value-based navigation is enough.

## When to add a Service layer (future, not now)

Do **not** add it in the prototype. Introduce `Service` between ViewModel and Repository only when one of these becomes true:

- A use case orchestrates **multiple repositories** (e.g. place bid → update vehicle + bid history + watchlist + notifications).
- Business logic needs **side effects** that don't belong in a pure rule or in data access (auth/session checks, analytics, retry/optimistic-update policies, server reconciliation).
- **Several screens** repeat the same multi-step logic.
- A **real backend** arrives and the Repository becomes pure data access (caching, mapping DTOs), pushing rules up a level.

Shape when that happens: `View → ViewModel → Service → Repository → DataSource`; Services are injected through the composition root; Domain rules stay pure and are called by Services. Record the decision in `docs/DECISIONS.md`.

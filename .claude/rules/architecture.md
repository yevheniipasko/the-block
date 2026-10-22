# Architecture

MVVM + Repository + DataSource, wired by a **Swinject dependency container** at the app (first) layer. Every dependency is consumed through a **protocol**. All wiring happens in one top-level module; everything below it receives plain protocol dependencies through `init`. This rule overrides the global `swift-engineering-conventions` skill where they conflict (no Service/UseCase layer yet — see bottom).

## Layers

```
App/ (composition root)
  AppModule ── the ONLY place that touches Swinject: owns the Container,
       │       registers everything, resolves everything,
       │       exposes typed factories via ViewModelFactoryProtocol
       ▼
  InventoryRouter (@Observable, NavigationPath, asks ViewModelFactoryProtocol for ViewModels)
       ▼
View ──▶ ViewModel ──▶ VehicleRepositoryProtocol  (impl: VehicleRepository, @Observable,
                              │                    container-scoped = single source of truth)
                              ▼
                       VehicleDataSourceProtocol  (impl: BundledJSONDataSource)

Domain/ — pure types and rules, no dependencies, used by every layer
```

| Layer | Owns | Must not |
|---|---|---|
| `App/` | `The_BlockApp`, `AppModule` (container + all registrations + factories), router | contain feature UI or business rules |
| `Domain/` | `Vehicle`, `Bid`, `AuctionStatus`, `BiddingRules` (activity level, adaptive step, min next bid, validation, Buy Now eligibility, floor met), `AuctionClock` | import SwiftUI/Swinject, hold state, do I/O |
| `Data/` DataSource | Loading + decoding `vehicles.json` (snake_case, nullable fields, timezone-less dates) | contain business rules |
| `Data/` Repository | Load once, expose `vehicles`, `placeBid` / `buyNow` → apply `BiddingRules`, update state, return result | know about screens or formatting |
| `Features/<Screen>/` ViewModel | Screen state: search/filters/sort, bid input, validation message, confirmation step; reads repository through its protocol | copy the vehicle array, own business rules, import Swinject |
| `Features/<Screen>/` View | Layout, bindings, accessibility ids; receives its ViewModel via `init` | resolve from the container, contain logic beyond trivial display conditions |
| `Shared/` | Formatters (CAD, km, dates), reusable components, design tokens | depend on features |

## Folder layout

```
The Block/
├── App/
│   ├── The_BlockApp.swift
│   ├── AppModule.swift                # single DI module: Container, all registrations, ViewModelFactoryProtocol impl
│   └── Routers/                       # InventoryRouter (+ protocol), InventoryRouterView
├── Domain/
├── Data/       VehicleDataSourceProtocol, BundledJSONDataSource, VehicleRepositoryProtocol, VehicleRepository, vehicles.json
├── Features/   Inventory/, Detail/, Bidding/
└── Shared/
```

## Dependency injection (Swinject)

Package: `https://github.com/Swinject/Swinject` (SPM, "Up to Next Major" from 2.9.1). Added once on the data/domain branch — package references live in `project.pbxproj`, so add it through Xcode (or ask the user), not by hand-editing.

**One module only.** A single top-level `AppModule` owns the `Container`, registers everything, and is the only type that calls `register` / `resolve`. No per-feature injection modules, no container passed into routers, ViewModels, or anything else.

```swift
protocol ViewModelFactoryProtocol: AnyObject {
    func makeInventoryViewModel() -> InventoryViewModel
    func makeVehicleDetailViewModel(vehicleID: Vehicle.ID) -> VehicleDetailViewModel
    func makeBidViewModel(vehicleID: Vehicle.ID) -> BidViewModel
}

// swiftlint:disable force_unwrapping
final class AppModule: ViewModelFactoryProtocol {
    private let container = Container()

    init() { registerDependencies() }

    private func registerDependencies() {
        // Data — shared
        container.register(AuctionClockProtocol.self) { _ in AuctionClock() }
            .inObjectScope(.container)
        container.register(VehicleDataSourceProtocol.self) { _ in BundledJSONDataSource() }
            .inObjectScope(.container)
        container.register(VehicleRepositoryProtocol.self) { r in
            VehicleRepository(dataSource: r.resolve(VehicleDataSourceProtocol.self)!,
                              clock: r.resolve(AuctionClockProtocol.self)!)
        }
        .inObjectScope(.container)              // one instance → bids visible everywhere

        // ViewModels — fresh per screen
        container.register(BidViewModel.self) { r, vehicleID in
            BidViewModel(vehicleID: vehicleID,
                         repository: r.resolve(VehicleRepositoryProtocol.self)!)
        }
        // ... InventoryViewModel, VehicleDetailViewModel

        // Router — shared
        container.register(InventoryRouterProtocol.self) { [unowned self] _ in
            InventoryRouter(factory: self)
        }
        .inObjectScope(.container)
    }

    var router: InventoryRouterProtocol { container.resolve(InventoryRouterProtocol.self)! }

    func makeBidViewModel(vehicleID: Vehicle.ID) -> BidViewModel {
        container.resolve(BidViewModel.self, argument: vehicleID)!
    }
    // ... other factories
}
// swiftlint:enable force_unwrapping
```

Rules:

- **Only `AppModule` imports Swinject.** It is created once in `The_BlockApp` (held as `@State`), not a `static let shared` singleton — tests can build their own.
- **No injection in lower modules:** the router gets `ViewModelFactoryProtocol`, not the `Container`; Views receive a ViewModel through `init`; ViewModels receive protocols through `init`. Nothing outside `AppModule` calls `resolve` or sees `Container`.
- If `AppModule` grows past ~150 lines, group registrations into private methods (`registerData()`, `registerViewModels()`, `registerRouters()`) — still one module, not separate module types.
- **Every injected dependency is a protocol:** `VehicleDataSourceProtocol`, `VehicleRepositoryProtocol`, `InventoryRouterProtocol`, `ViewModelFactoryProtocol`, `AuctionClockProtocol` (for a fixed `now` in tests). Naming: `<Type>Protocol`. ViewModels are concrete `@Observable` classes — no ViewModel protocols.
- **Scopes:** DataSource, Repository, clock, routers → `.container` (shared). ViewModels → `.transient`. Runtime values (vehicle ID) → Swinject arguments (`register(_:) { r, arg in }` / `resolve(_:argument:)`).
- **Force-unwrapped `resolve` is allowed only inside `AppModule`**, where a missing registration is a programmer error caught on first launch; wrap the file in `// swiftlint:disable force_unwrapping`.
- **Observation through protocols:** `protocol VehicleRepositoryProtocol: AnyObject` exposing `vehicles` etc.; the concrete `@Observable` class still drives SwiftUI updates when accessed via the existential.
- **Tests don't use the container** — construct ViewModels/Repository directly with fake protocol implementations. One smoke test verifies `AppModule` builds the router and every factory method returns a ViewModel.

## Other rules

- **Single source of truth:** the container-scoped `VehicleRepository`. A bid placed anywhere is visible everywhere because every ViewModel reads from that one instance.
- **One ViewModel per screen** (Inventory, Detail, Bidding) — needed so each View receives only injected dependencies. Keep them thin; no logic that belongs in `Domain/`.
- **Navigation:** one `InventoryRouter` (`@Observable`, `NavigationPath`, route enum); `InventoryRouterView` hosts `NavigationStack` / `NavigationSplitView` and builds destination Views with ViewModels the router got from `ViewModelFactoryProtocol`.
- **Isolation:** Domain and DataSource types are `nonisolated` (and `Sendable` where needed); Repository, ViewModels, routers, and `AppModule` are on the main actor (default isolation). Resolve only on the main actor.
- **Business rules are pure functions in `Domain/`**, tested directly with Swift Testing against spec IDs (see `spec-driven.md`).
- **Dependencies point inward:** App → Features → Data → Domain. Domain depends on nothing.

## When to add a Service layer (future, not now)

Do **not** add it in the prototype. Introduce `Service` between ViewModel and Repository only when one of these becomes true:

- A use case orchestrates **multiple repositories** (e.g. place bid → update vehicle + bid history + watchlist + notifications).
- Business logic needs **side effects** that don't belong in a pure rule or in data access (auth/session checks, analytics, retry/optimistic-update policies, server reconciliation).
- **Several screens** repeat the same multi-step logic.
- A **real backend** arrives and the Repository becomes pure data access (caching, mapping DTOs), pushing rules up a level.

Shape when that happens: `View → ViewModel → ServiceProtocol → RepositoryProtocol → DataSourceProtocol`; Services registered in `AppModule` with `.container` scope; Domain rules stay pure and are called by Services. Record the decision in `docs/DECISIONS.md`.

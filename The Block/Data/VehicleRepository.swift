//
//  VehicleRepository.swift
//  The Block
//
//  Vehicle repository: caches the live feed, fans out updates as streams, pages
//  inventory queries, and forwards bids / Buy Now to the data source.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import OSLog

/// Progress of the inventory load; `.failed` carries a user-facing message (spec DATA-3).
enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

/// Single source of truth for vehicles: a cache of the live feed, fanned out as `AsyncStream`s
/// (spec LIVE-1). Data can change at any time — screens subscribe instead of reading once.
protocol VehicleRepositoryProtocol: AnyObject {
    /// Latest load progress (snapshot read; subscribe with `loadStateUpdates()`).
    var loadState: LoadState { get }
    /// Latest known vehicles (snapshot read; subscribe with `inventoryUpdates()`).
    var vehicles: [VehicleModel] { get }
    /// The current moment from the injected clock, so views and rules agree on time.
    var now: Date { get }

    /// Connects to the live feed and returns once the first snapshot arrived or the connection
    /// failed (spec DATA-1, DATA-3, LIVE-1). Calling it again reconnects (retry).
    func load() async
    /// Latest known copy of one vehicle, or `nil` if it is not in the inventory.
    func vehicle(id: VehicleModel.ID) -> VehicleModel?

    /// Load progress: the current state first, then every change.
    func loadStateUpdates() -> AsyncStream<LoadState>
    /// One vehicle: its current copy first (if known), then every change to it (spec LIVE-1, BID-6).
    func vehicleUpdates(id: VehicleModel.ID) -> AsyncStream<VehicleModel>
    /// Every lot that changes from now on, whoever changed it (spec LIVE-1, LIVE-3).
    func inventoryUpdates() -> AsyncStream<VehicleModel>

    /// One page of vehicles matching `query`, imitating a cursor-paginated API (spec LIST-7).
    ///
    /// Filtering and sorting run against the latest state (including your bids) at call time.
    /// - Throws: `PagingError.staleCursor` when the cursor's vehicle no longer matches.
    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage
    /// Sends a bid; the server validates it against the state at arrival (spec BID-3, BID-4, BID-6, BID-7).
    ///
    /// - Returns: The updated vehicle, or the reason the bid was rejected. Rejections never change state.
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
    /// Buys the lot at its Buy Now price, ending the auction as purchased by you (spec BID-10, BID-11).
    ///
    /// - Returns: The updated vehicle, or `.buyNowUnavailable` / `.vehicleNotFound` / `.connectionFailed`.
    @discardableResult
    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
}

/// `VehicleRepositoryProtocol` backed by `VehicleDataSourceProtocol`'s feed; bids and purchases
/// reset on app launch (spec Assumptions).
final class VehicleRepository: VehicleRepositoryProtocol {

    private(set) var loadState: LoadState = .idle {
        didSet { loadStates.yield(loadState) }
    }
    private(set) var vehicles: [VehicleModel] = []

    private let dataSource: VehicleDataSourceProtocol
    private let clock: AuctionClockProtocol
    private let pageLatency: Duration
    private let loadStates = StreamBroadcaster<LoadState>()
    private let changes = StreamBroadcaster<VehicleModel>()
    /// Task consuming the current feed connection; cancelled when `load()` reconnects.
    private var feedTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "TheBlock", category: "VehicleRepository")

    /// - Parameters:
    ///   - dataSource: Live feed and bid / Buy Now endpoints.
    ///   - clock: Source of "now" for paging filters and the `now` property.
    ///   - pageLatency: Simulated network delay per inventory page; `.zero` in tests.
    init(dataSource: VehicleDataSourceProtocol, clock: AuctionClockProtocol, pageLatency: Duration = .zero) {
        self.dataSource = dataSource
        self.clock = clock
        self.pageLatency = pageLatency
    }

    var now: Date { clock.now }

    /// Starts consuming the feed in the background and waits for the first non-loading state.
    func load() async {
        feedTask?.cancel()
        // Switch to `.loading` before subscribing, so a previous `.failed` isn't mistaken for this result.
        loadState = .loading
        let states = loadStateUpdates()
        let feed = dataSource.vehicleFeed()
        feedTask = Task { [weak self] in
            await self?.consume(feed)
        }
        for await state in states where state != .loading && state != .idle {
            break
        }
    }

    func vehicle(id: VehicleModel.ID) -> VehicleModel? {
        vehicles.first { $0.id == id }
    }

    func loadStateUpdates() -> AsyncStream<LoadState> {
        loadStates.stream(startingWith: loadState)
    }

    func vehicleUpdates(id: VehicleModel.ID) -> AsyncStream<VehicleModel> {
        let source = changes.stream()
        let current = vehicle(id: id)
        return AsyncStream { continuation in
            if let current {
                continuation.yield(current)
            }
            let task = Task {
                for await vehicle in source where vehicle.id == id {
                    continuation.yield(vehicle)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func inventoryUpdates() -> AsyncStream<VehicleModel> {
        changes.stream()
    }

    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage {
        if pageLatency > .zero {
            try await Task.sleep(for: pageLatency)
        }
        let results = query.apply(to: vehicles, now: clock.now)
        return try Paginator.page(of: results, after: cursor, limit: limit)
    }

    /// Applies the server's response right away, so the caller sees its own bid even before the
    /// feed echoes it; the echo is an idempotent replace.
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await perform { try await dataSource.placeBid(amount, on: id) }
    }

    @discardableResult
    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await perform { try await dataSource.buyNow(id) }
    }

    // MARK: - Private

    /// Reads feed events until the feed ends; a feed that ends before its snapshot is a failure.
    private func consume(_ feed: AsyncThrowingStream<VehicleFeedEvent, Error>) async {
        do {
            for try await event in feed {
                handle(event)
            }
            if loadState == .loading {
                fail(reason: "feed closed before snapshot")
            }
        } catch {
            fail(reason: String(describing: error))
        }
    }

    /// Applies one feed event to the cache: a snapshot replaces it and marks the load done, an update replaces one lot.
    private func handle(_ event: VehicleFeedEvent) {
        switch event {
        case .snapshot(let snapshot):
            // Announce lots that are new or changed, so subscribers that started before the
            // (re)connection receive them too.
            let previous = Dictionary(vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            vehicles = snapshot
            for vehicle in snapshot where previous[vehicle.id] != vehicle {
                changes.yield(vehicle)
            }
            loadState = .loaded
        case .updated(let vehicle):
            apply(vehicle)
        }
    }

    /// Replaces the cached lot and notifies subscribers; unknown lots are ignored.
    private func apply(_ vehicle: VehicleModel) {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) else { return }
        guard vehicles[index] != vehicle else { return }
        vehicles[index] = vehicle
        changes.yield(vehicle)
    }

    /// Runs a bid / Buy Now request and caches the returned lot on success (spec LIVE-4).
    ///
    /// Errors other than `BidRejection` are logged and reported as `.connectionFailed`; the cache
    /// is left untouched on any failure (spec BID-8).
    private func perform(_ request: () async throws -> VehicleModel) async -> Result<VehicleModel, BidRejection> {
        do {
            let vehicle = try await request()
            apply(vehicle)
            return .success(vehicle)
        } catch let rejection as BidRejection {
            return .failure(rejection)
        } catch {
            logger.error("[VehicleRepository] request failed: \(String(describing: error), privacy: .public)")
            return .failure(.connectionFailed)
        }
    }

    /// Logs why the feed failed and moves to `.failed` with the user-facing message (spec DATA-3, LIVE-4).
    private func fail(reason: String) {
        logger.error("[VehicleRepository] feed failed: \(reason, privacy: .public)")
        loadState = .failed(message: Localizable.loadFailed)
    }

}

private enum Localizable {
    static let loadFailed = "We couldn't load the inventory. Please try again."
}

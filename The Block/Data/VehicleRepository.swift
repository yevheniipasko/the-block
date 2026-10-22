import Foundation
import Observation
import OSLog

/// Progress of the inventory load; `.failed` carries a user-facing message (spec DATA-3).
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

/// Single source of truth for vehicles and the buyer's bids/purchases (held in memory).
protocol VehicleRepositoryProtocol: AnyObject {
    /// Progress of the latest `load()` call.
    var loadState: LoadState { get }
    /// All vehicles with normalized auction starts and the buyer's bids/purchases applied.
    var vehicles: [VehicleModel] { get }
    /// The current moment from the injected clock, so views and rules agree on time.
    var now: Date { get }

    /// Loads the inventory and updates `loadState` (spec DATA-1, DATA-3, TIME-1).
    ///
    /// Calling it again after a failure retries the load.
    func load() async
    /// Returns the vehicle with `id`, or `nil` if it is not in the inventory.
    func vehicle(id: VehicleModel.ID) -> VehicleModel?
    /// One page of vehicles matching `query`, imitating a cursor-paginated API (spec LIST-7).
    ///
    /// Filtering and sorting run against live state (including your bids) at call time.
    /// - Throws: `PagingError.staleCursor` when the cursor's vehicle no longer matches.
    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage
    /// Places a bid for the buyer after a simulated network round trip, validating it with `BiddingRules`
    /// against the state at arrival (spec BID-3, BID-4, BID-6, BID-7).
    ///
    /// On success the lot's current bid becomes `amount`, its bid count goes up by one, and the buyer
    /// becomes the high bidder.
    ///
    /// - Returns: The updated vehicle, or the reason the bid was rejected.
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
    /// Buys the lot at its Buy Now price after a simulated network round trip, which ends the auction
    /// as purchased by you (spec BID-10, BID-11).
    ///
    /// - Returns: The updated vehicle, or `.buyNowUnavailable` / `.vehicleNotFound`.
    @discardableResult
    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
}

/// In-memory `VehicleRepositoryProtocol`; bids and purchases reset on app launch (spec Assumptions).
@Observable
final class VehicleRepository: VehicleRepositoryProtocol {

    private(set) var loadState: LoadState = .idle
    private(set) var vehicles: [VehicleModel] = []

    @ObservationIgnored private let dataSource: VehicleDataSourceProtocol
    @ObservationIgnored private let clock: AuctionClockProtocol
    @ObservationIgnored private let pageLatency: Duration
    @ObservationIgnored private let actionLatency: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "VehicleRepository")

    /// Creates a repository that loads from `dataSource` and reads time from `clock`.
    ///
    /// - Parameters:
    ///   - pageLatency: Simulated network delay per inventory page; `.zero` in tests.
    ///   - actionLatency: Simulated network delay per bid / Buy Now; `.zero` in tests.
    init(
        dataSource: VehicleDataSourceProtocol,
        clock: AuctionClockProtocol,
        pageLatency: Duration = .zero,
        actionLatency: Duration = .zero
    ) {
        self.dataSource = dataSource
        self.clock = clock
        self.pageLatency = pageLatency
        self.actionLatency = actionLatency
    }

    var now: Date { clock.now }

    /// Loads vehicles and shifts every auction start with one `AuctionSchedule` anchored at `clock.now`.
    ///
    /// On failure it logs the underlying error and sets `.failed` with a generic message; the
    /// previously loaded vehicles are kept (spec DATA-3, TIME-1).
    func load() async {
        loadState = .loading
        do {
            let raw = try await dataSource.loadVehicles()
            let schedule = AuctionSchedule(datasetStarts: raw.map(\.auctionStart), launchDate: clock.now)
            vehicles = raw.map { vehicle in
                var normalized = vehicle
                normalized.auctionStart = schedule.normalized(vehicle.auctionStart)
                return normalized
            }
            loadState = .loaded
        } catch {
            logger.error("[VehicleRepository] load failed: \(String(describing: error), privacy: .public)")
            loadState = .failed(message: "We couldn't load the inventory. Please try again.")
        }
    }

    func vehicle(id: VehicleModel.ID) -> VehicleModel? {
        vehicles.first { $0.id == id }
    }

    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage {
        if pageLatency > .zero {
            try await Task.sleep(for: pageLatency)
        }
        let results = query.apply(to: vehicles, now: clock.now)
        return try Paginator.page(of: results, after: cursor, limit: limit)
    }

    @discardableResult
    /// Waits for the simulated round trip, validates at `clock.now`, then writes the updated lot back
    /// in one assignment.
    ///
    /// A rejected bid leaves `vehicles` untouched, so no half-updated state is visible (spec BID-8).
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await simulateNetwork()
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
            return .failure(.vehicleNotFound)
        }
        var vehicle = vehicles[index]
        if case .failure(let rejection) = BiddingRules.validateBid(amount, on: vehicle, at: clock.now) {
            return .failure(rejection)
        }
        vehicle.currentBid = amount
        vehicle.bidCount += 1
        vehicle.yourBid = amount
        vehicles[index] = vehicle
        return .success(vehicle)
    }

    @discardableResult
    /// Waits for the simulated round trip, checks `BiddingRules.canBuyNow` at `clock.now`, then records
    /// the purchase price on the lot.
    ///
    /// A rejection leaves `vehicles` untouched (spec BID-8).
    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection> {
        await simulateNetwork()
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
            return .failure(.vehicleNotFound)
        }
        var vehicle = vehicles[index]
        guard BiddingRules.canBuyNow(vehicle, at: clock.now), let price = vehicle.buyNowPrice else {
            return .failure(.buyNowUnavailable)
        }
        vehicle.yourPurchasePrice = price
        vehicles[index] = vehicle
        return .success(vehicle)
    }

    /// Waits `actionLatency`; cancellation just ends the wait early.
    private func simulateNetwork() async {
        guard actionLatency > .zero else { return }
        try? await Task.sleep(for: actionLatency)
    }

}

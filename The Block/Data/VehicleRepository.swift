import Foundation
import Observation
import OSLog

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

/// Single source of truth for vehicles and the buyer's bids/purchases (held in memory).
protocol VehicleRepositoryProtocol: AnyObject {
    var loadState: LoadState { get }
    var vehicles: [VehicleModel] { get }
    var now: Date { get }

    func load() async
    func vehicle(id: VehicleModel.ID) -> VehicleModel?
    /// One page of vehicles matching `query`, imitating a cursor-paginated API (spec LIST-7).
    ///
    /// Filtering and sorting run against live state (including your bids) at call time.
    /// - Throws: `PagingError.staleCursor` when the cursor's vehicle no longer matches.
    func fetchPage(_ query: InventoryQuery, after cursor: PageCursor?, limit: Int) async throws -> InventoryPage
    /// Places a bid after a simulated network round trip; validates against the state at arrival.
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
    /// Buys the lot at its Buy Now price after a simulated network round trip.
    @discardableResult
    func buyNow(_ id: VehicleModel.ID) async -> Result<VehicleModel, BidRejection>
}

@Observable
final class VehicleRepository: VehicleRepositoryProtocol {

    private(set) var loadState: LoadState = .idle
    private(set) var vehicles: [VehicleModel] = []

    @ObservationIgnored private let dataSource: VehicleDataSourceProtocol
    @ObservationIgnored private let clock: AuctionClockProtocol
    @ObservationIgnored private let pageLatency: Duration
    @ObservationIgnored private let actionLatency: Duration
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "VehicleRepository")

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

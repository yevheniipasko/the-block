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
    /// Places a bid for the buyer after validating it with `BiddingRules` (spec BID-3, BID-4, BID-6, BID-7).
    ///
    /// On success the lot's current bid becomes `amount`, its bid count goes up by one, and the buyer
    /// becomes the high bidder.
    ///
    /// - Returns: The updated vehicle, or the reason the bid was rejected.
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) -> Result<VehicleModel, BidRejection>
    /// Buys the lot at its Buy Now price, which ends the auction as purchased by you (spec BID-10, BID-11).
    ///
    /// - Returns: The updated vehicle, or `.buyNowUnavailable` / `.vehicleNotFound`.
    @discardableResult
    func buyNow(_ id: VehicleModel.ID) -> Result<VehicleModel, BidRejection>
}

/// In-memory `VehicleRepositoryProtocol`; bids and purchases reset on app launch (spec Assumptions).
@Observable
final class VehicleRepository: VehicleRepositoryProtocol {

    private(set) var loadState: LoadState = .idle
    private(set) var vehicles: [VehicleModel] = []

    @ObservationIgnored private let dataSource: VehicleDataSourceProtocol
    @ObservationIgnored private let clock: AuctionClockProtocol
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "VehicleRepository")

    /// Creates a repository that loads from `dataSource` and reads time from `clock`.
    init(dataSource: VehicleDataSourceProtocol, clock: AuctionClockProtocol) {
        self.dataSource = dataSource
        self.clock = clock
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

    @discardableResult
    /// Validates at `clock.now`, then writes the updated lot back in one assignment.
    ///
    /// A rejected bid leaves `vehicles` untouched, so no half-updated state is visible (spec BID-8).
    func placeBid(_ amount: Int, on id: VehicleModel.ID) -> Result<VehicleModel, BidRejection> {
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
    /// Checks `BiddingRules.canBuyNow` at `clock.now`, then records the purchase price on the lot.
    ///
    /// A rejection leaves `vehicles` untouched (spec BID-8).
    func buyNow(_ id: VehicleModel.ID) -> Result<VehicleModel, BidRejection> {
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

}

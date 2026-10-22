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
    @discardableResult
    func placeBid(_ amount: Int, on id: VehicleModel.ID) -> Result<VehicleModel, BidRejection>
    @discardableResult
    func buyNow(_ id: VehicleModel.ID) -> Result<VehicleModel, BidRejection>
}

@Observable
final class VehicleRepository: VehicleRepositoryProtocol {

    private(set) var loadState: LoadState = .idle
    private(set) var vehicles: [VehicleModel] = []

    @ObservationIgnored private let dataSource: VehicleDataSourceProtocol
    @ObservationIgnored private let clock: AuctionClockProtocol
    @ObservationIgnored private let logger = Logger(subsystem: "TheBlock", category: "VehicleRepository")

    init(dataSource: VehicleDataSourceProtocol, clock: AuctionClockProtocol) {
        self.dataSource = dataSource
        self.clock = clock
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

    @discardableResult
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

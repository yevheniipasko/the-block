import Foundation
import Observation

/// Bid sheet and Buy Now confirmation state for one vehicle (spec BID-*).
///
/// Shell placeholder — the Bidding feature fills this in. Keep the `init` signature.
@Observable
final class BidViewModel {

    let vehicleID: VehicleModel.ID
    @ObservationIgnored let repository: VehicleRepositoryProtocol

    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol) {
        self.vehicleID = vehicleID
        self.repository = repository
    }

    var vehicle: VehicleModel? { repository.vehicle(id: vehicleID) }

}

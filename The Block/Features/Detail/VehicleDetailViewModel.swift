import Foundation
import Observation

/// Detail screen state for one vehicle (spec DETAIL-*).
///
/// Shell placeholder — the Detail feature fills this in. Keep the `init` signature.
@Observable
final class VehicleDetailViewModel {

    let vehicleID: VehicleModel.ID
    @ObservationIgnored let repository: VehicleRepositoryProtocol

    init(vehicleID: VehicleModel.ID, repository: VehicleRepositoryProtocol) {
        self.vehicleID = vehicleID
        self.repository = repository
    }

    /// Latest repository copy, so bids placed elsewhere show up immediately (spec BID-6).
    var vehicle: VehicleModel? { repository.vehicle(id: vehicleID) }

}

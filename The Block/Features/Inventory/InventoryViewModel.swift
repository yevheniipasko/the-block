import Foundation
import Observation

/// Inventory screen state: search, filters, sort (spec LIST-*).
///
/// Shell placeholder — the Inventory feature fills this in. Keep the `init` signature:
/// `AppModule` builds it with the shared repository.
@Observable
final class InventoryViewModel {

    @ObservationIgnored let repository: VehicleRepositoryProtocol

    init(repository: VehicleRepositoryProtocol) {
        self.repository = repository
    }

    var vehicles: [VehicleModel] { repository.vehicles }

}

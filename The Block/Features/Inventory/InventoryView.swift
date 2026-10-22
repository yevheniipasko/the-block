import SwiftUI

/// Inventory list (spec LIST-*).
///
/// Shell placeholder — the Inventory feature replaces the body. Keep the `init` signature:
/// selecting a row writes its ID into `selection`, which the router turns into navigation.
struct InventoryView: View {

    let viewModel: InventoryViewModel
    @Binding var selection: VehicleModel.ID?

    var body: some View {
        List(viewModel.vehicles, selection: $selection) { vehicle in
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(vehicle.title).font(.headline)
                AuctionStatusBadge(vehicle: vehicle)
            }
            .tag(vehicle.id)
        }
        .navigationTitle("Inventory")
    }

}

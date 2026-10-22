import SwiftUI

/// Vehicle detail (spec DETAIL-*).
///
/// Shell placeholder — the Detail feature replaces the body. Keep the `init` signature:
/// the bottom action bar calls `onPlaceBid` / `onBuyNow`; the router presents the sheets.
struct VehicleDetailView: View {

    let viewModel: VehicleDetailViewModel
    let onPlaceBid: () -> Void
    let onBuyNow: () -> Void

    var body: some View {
        if let vehicle = viewModel.vehicle {
            VStack(spacing: Spacing.large) {
                Text(vehicle.title).font(.title2.bold())
                AuctionStatusBadge(vehicle: vehicle)
                Button("Place bid", action: onPlaceBid)
                    .accessibilityIdentifier("detail.placeBidButton")
            }
            .navigationTitle(vehicle.lot)
        } else {
            ContentUnavailableView("Vehicle not found", systemImage: "car.side")
        }
    }

}

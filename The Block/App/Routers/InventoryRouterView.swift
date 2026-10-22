import SwiftUI

/// Root navigation: split view on iPad, collapsing to a stack on iPhone (spec UX-1).
struct InventoryRouterView: View {

    let router: InventoryRouterProtocol

    var body: some View {
        NavigationSplitView {
            InventoryView(viewModel: router.inventoryViewModel, selection: selection)
        } detail: {
            if let detailViewModel = router.detailViewModel {
                VehicleDetailView(
                    viewModel: detailViewModel,
                    onPlaceBid: { router.presentBid(for: detailViewModel.vehicleID) },
                    onBuyNow: { router.presentBuyNow(for: detailViewModel.vehicleID) }
                )
                .id(detailViewModel.vehicleID)
            } else {
                ContentUnavailableView(Localizable.emptyDetailTitle, systemImage: "car.side")
            }
        }
        .sheet(item: presentedSheet) { sheet in
            if let bidViewModel = router.bidViewModel {
                switch sheet {
                case .bid:
                    BidSheet(viewModel: bidViewModel, onFinish: router.dismissSheet)
                case .buyNow:
                    BuyNowSheet(viewModel: bidViewModel, onFinish: router.dismissSheet)
                }
            }
        }
    }

    private var selection: Binding<VehicleModel.ID?> {
        Binding(get: { router.selectedVehicleID }, set: { router.select($0) })
    }

    private var presentedSheet: Binding<BiddingSheet?> {
        Binding(get: { router.presentedSheet }, set: { if $0 == nil { router.dismissSheet() } })
    }

}

private enum Localizable {
    static let emptyDetailTitle = "Select a vehicle"
}

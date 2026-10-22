import SwiftUI

/// Root navigation: split view on iPad, collapsing to a stack on iPhone (spec UX-1).
struct InventoryRouterView: View {

    let router: InventoryRouterProtocol
    let alertCenter: OutbidAlertCenter

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
        .overlay(alignment: .top) { outbidBanner }
        .animation(.snappy, value: alertCenter.current)
        .task { await alertCenter.observe() }
        .onChange(of: suppressedLotID, initial: true) { _, lotID in
            alertCenter.suppressedLotID = lotID
        }
    }

    /// Outbid banner over every screen (spec ALERT-1). It doesn't cover an open sheet, which is
    /// accepted: the sheet's own lot is suppressed and its outbid notice shows inside the sheet (ALERT-3).
    @ViewBuilder
    private var outbidBanner: some View {
        if let alert = alertCenter.current {
            OutbidBannerView(
                alert: alert,
                onBidAgain: {
                    alertCenter.dismiss()
                    router.presentBid(for: alert.lotID)
                },
                onDismiss: alertCenter.dismiss
            )
            .id(alert.id)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Lot whose open sheet shows its own outbid notice (spec ALERT-3). The success screen shows
    /// none, so an outbid landing there still raises the banner, visible once the sheet closes.
    private var suppressedLotID: VehicleModel.ID? {
        guard let sheet = router.presentedSheet, router.bidViewModel?.phase != .succeeded else { return nil }
        switch sheet {
        case .bid(let id), .buyNow(let id):
            return id
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

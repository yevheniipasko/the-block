//
//  InventoryRouterView.swift
//  The Block
//
//  Root navigation view: hosts inventory, detail, My bids, the bid / Buy Now
//  sheets, and the outbid banner.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Root navigation: split view on iPad, collapsing to a stack on iPhone (spec UX-1).
struct InventoryRouterView: View {

    let router: InventoryRouterProtocol
    let alertCenter: OutbidAlertCenter

    var body: some View {
        NavigationSplitView {
            InventoryView(viewModel: router.inventoryViewModel, selection: selection)
                .toolbar {
                    MyBidsToolbarItem(outbidCount: router.myBidsViewModel.outbidCount, action: router.showMyBids)
                }
                .navigationDestination(isPresented: isShowingMyBids) {
                    MyBidsView(
                        viewModel: router.myBidsViewModel,
                        selection: selection,
                        onBrowseInventory: router.hideMyBids
                    )
                }
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
        .task { await router.myBidsViewModel.observe() }
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

    /// Selected vehicle, routed through `router.select(_:)` so the detail ViewModel is rebuilt.
    private var selection: Binding<VehicleModel.ID?> {
        Binding(get: { router.selectedVehicleID }, set: { router.select($0) })
    }

    /// Whether My bids is pushed; a back navigation sets it to `false` and closes the screen.
    private var isShowingMyBids: Binding<Bool> {
        Binding(get: { router.isShowingMyBids }, set: { if !$0 { router.hideMyBids() } })
    }

    /// Presented sheet; a swipe-down dismissal tells the router to clear it.
    private var presentedSheet: Binding<BiddingSheet?> {
        Binding(get: { router.presentedSheet }, set: { if $0 == nil { router.dismissSheet() } })
    }

}

private enum Localizable {
    static let emptyDetailTitle = "Select a vehicle"
}

//
//  InventoryRouter.swift
//  The Block
//
//  App navigation state (selected vehicle, presented sheet, My bids) and the
//  ViewModel factory protocol the router builds screens with.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Observation

/// Sheets presented over the inventory / detail screens.
enum BiddingSheet: Identifiable, Hashable {
    /// The bid sheet for a vehicle (spec BID-1).
    case bid(VehicleModel.ID)
    /// The Buy Now confirmation for a vehicle (spec BID-10).
    case buyNow(VehicleModel.ID)

    var id: Self { self }
}

/// Builds screen ViewModels. Implemented by `AppModule`, so the router never sees the container.
protocol ViewModelFactoryProtocol: AnyObject {
    /// The app-wide inventory list ViewModel.
    func makeInventoryViewModel() -> InventoryViewModel
    /// A fresh detail ViewModel for one vehicle.
    func makeVehicleDetailViewModel(vehicleID: VehicleModel.ID) -> VehicleDetailViewModel
    /// A fresh bid / Buy Now ViewModel for one vehicle.
    func makeBidViewModel(vehicleID: VehicleModel.ID) -> BidViewModel
    /// The app-wide "My bids" ViewModel; the router asks once and keeps it (spec MYBIDS-1, MYBIDS-6).
    func makeMyBidsViewModel() -> MyBidsViewModel
}

/// Navigation state for the whole app: selected vehicle (list → detail) and presented sheet.
protocol InventoryRouterProtocol: AnyObject {
    /// The inventory list ViewModel, kept for the router's lifetime.
    var inventoryViewModel: InventoryViewModel { get }
    /// Vehicle whose detail is shown, or `nil` when none is selected.
    var selectedVehicleID: VehicleModel.ID? { get }
    /// ViewModel for the selected vehicle's detail; rebuilt when the selection changes.
    var detailViewModel: VehicleDetailViewModel? { get }
    /// The bid or Buy Now sheet currently presented, if any.
    var presentedSheet: BiddingSheet? { get }
    /// ViewModel backing the presented sheet; `nil` when no sheet is open.
    var bidViewModel: BidViewModel? { get }
    /// Lives as long as the router, so the toolbar's outbid badge stays current (spec MYBIDS-6).
    var myBidsViewModel: MyBidsViewModel { get }
    /// Whether "My bids" is pushed over the inventory list (spec MYBIDS-1).
    var isShowingMyBids: Bool { get }

    /// Shows a vehicle's detail, or clears it with `nil` (spec UX-1).
    func select(_ vehicleID: VehicleModel.ID?)
    /// Presents the bid sheet for a vehicle (spec BID-1).
    func presentBid(for vehicleID: VehicleModel.ID)
    /// Presents the Buy Now confirmation for a vehicle (spec BID-10).
    func presentBuyNow(for vehicleID: VehicleModel.ID)
    /// Closes any presented sheet.
    func dismissSheet()
    /// Opens "My bids" (spec MYBIDS-1).
    func showMyBids()
    /// Closes "My bids" and returns to the inventory list (spec MYBIDS-5).
    func hideMyBids()
}

/// `InventoryRouterProtocol` implementation that asks a `ViewModelFactoryProtocol` for each
/// screen's ViewModel when navigation happens.
@Observable
final class InventoryRouter: InventoryRouterProtocol {

    private(set) var selectedVehicleID: VehicleModel.ID?
    private(set) var detailViewModel: VehicleDetailViewModel?
    private(set) var presentedSheet: BiddingSheet?
    private(set) var bidViewModel: BidViewModel?
    private(set) var isShowingMyBids = false
    let inventoryViewModel: InventoryViewModel
    let myBidsViewModel: MyBidsViewModel

    @ObservationIgnored private unowned let factory: ViewModelFactoryProtocol

    /// Builds the long-lived inventory and My bids ViewModels up front.
    ///
    /// - Parameter factory: Builds ViewModels; held `unowned` because `AppModule` owns the router.
    init(factory: ViewModelFactoryProtocol) {
        self.factory = factory
        self.inventoryViewModel = factory.makeInventoryViewModel()
        self.myBidsViewModel = factory.makeMyBidsViewModel()
    }

    /// ViewModels are built here, on navigation, never inside a view's `body`.
    func select(_ vehicleID: VehicleModel.ID?) {
        guard vehicleID != selectedVehicleID else { return }
        selectedVehicleID = vehicleID
        detailViewModel = vehicleID.map { factory.makeVehicleDetailViewModel(vehicleID: $0) }
    }

    func presentBid(for vehicleID: VehicleModel.ID) {
        bidViewModel = factory.makeBidViewModel(vehicleID: vehicleID)
        presentedSheet = .bid(vehicleID)
    }

    func presentBuyNow(for vehicleID: VehicleModel.ID) {
        bidViewModel = factory.makeBidViewModel(vehicleID: vehicleID)
        presentedSheet = .buyNow(vehicleID)
    }

    func dismissSheet() {
        presentedSheet = nil
        bidViewModel = nil
    }

    func showMyBids() {
        isShowingMyBids = true
    }

    func hideMyBids() {
        isShowingMyBids = false
    }

}

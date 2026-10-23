//
//  InventoryRouterTests.swift
//  The Block
//
//  Tests for InventoryRouter navigation state: detail selection, bid / Buy Now sheets,
//  and My bids (UX-1, BID-1, BID-10, MYBIDS-1, MYBIDS-5).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Factory that builds real ViewModels on an empty stub repository and records detail requests.
@MainActor
private final class FakeViewModelFactory: ViewModelFactoryProtocol {

    let repository = VehicleRepository.stubbed(
        result: .success([]),
        clock: FixedClock(now: TestDates.reference)
    )
    /// Vehicle IDs passed to `makeVehicleDetailViewModel(vehicleID:)`, in call order.
    private(set) var detailRequests: [VehicleModel.ID] = []

    /// Builds an inventory ViewModel on the shared stub repository.
    func makeInventoryViewModel() -> InventoryViewModel {
        InventoryViewModel(repository: repository)
    }

    /// Records the request, then builds a detail ViewModel for `vehicleID`.
    func makeVehicleDetailViewModel(vehicleID: VehicleModel.ID) -> VehicleDetailViewModel {
        detailRequests.append(vehicleID)
        return VehicleDetailViewModel(vehicleID: vehicleID, repository: repository)
    }

    /// Builds a bid ViewModel for `vehicleID` on the shared stub repository.
    func makeBidViewModel(vehicleID: VehicleModel.ID) -> BidViewModel {
        BidViewModel(vehicleID: vehicleID, repository: repository)
    }

    /// Builds a My bids ViewModel on the shared stub repository.
    func makeMyBidsViewModel() -> MyBidsViewModel {
        MyBidsViewModel(repository: repository)
    }

}

/// Router navigation state: detail selection, bid / Buy Now sheets, and My bids.
@MainActor
struct InventoryRouterTests {

    private let factory = FakeViewModelFactory()

    @Test("UX-1: selecting a vehicle builds its detail ViewModel once")
    func selectBuildsDetailOnce() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()

        router.select(id)
        router.select(id)

        #expect(router.selectedVehicleID == id)
        #expect(router.detailViewModel?.vehicleID == id)
        #expect(factory.detailRequests == [id])
    }

    @Test("UX-1: clearing the selection keeps the last detail ViewModel while the screen pops")
    func clearSelectionKeepsDetail() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()
        router.select(id)
        let viewModel = router.detailViewModel

        router.select(nil)

        #expect(router.selectedVehicleID == nil)
        #expect(router.detailViewModel === viewModel)
    }

    @Test("UX-1: re-selecting the last vehicle reuses its detail ViewModel; another builds a new one")
    func reselectReusesDetail() {
        let router = InventoryRouter(factory: factory)
        let first = UUID()
        let second = UUID()

        router.select(first)
        router.select(nil)
        router.select(first)
        #expect(factory.detailRequests == [first])

        router.select(second)
        #expect(router.detailViewModel?.vehicleID == second)
        #expect(factory.detailRequests == [first, second])
    }

    @Test("BID-1 / BID-10: presenting a sheet builds its ViewModel; it outlives dismissal until the sheet is gone")
    func sheets() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()

        router.presentBid(for: id)
        #expect(router.presentedSheet == .bid(id))
        #expect(router.bidViewModel?.vehicleID == id)

        router.presentBuyNow(for: id)
        #expect(router.presentedSheet == .buyNow(id))

        router.dismissSheet()
        #expect(router.presentedSheet == nil)
        #expect(router.bidViewModel?.vehicleID == id)

        router.sheetDidDismiss()
        #expect(router.bidViewModel == nil)
    }

    @Test("BID-1: a sheet presented before the old one finished dismissing keeps its ViewModel")
    func sheetDidDismissKeepsNewSheet() {
        let router = InventoryRouter(factory: factory)
        let id = UUID()
        router.presentBid(for: UUID())
        router.dismissSheet()

        router.presentBid(for: id)
        router.sheetDidDismiss()

        #expect(router.presentedSheet == .bid(id))
        #expect(router.bidViewModel?.vehicleID == id)
    }

    @Test("MYBIDS-1 / MYBIDS-5: My bids opens and closes; its ViewModel is built once with the router")
    func myBids() {
        let router = InventoryRouter(factory: factory)
        let viewModel = router.myBidsViewModel

        router.showMyBids()
        #expect(router.isShowingMyBids)

        router.hideMyBids()
        #expect(!router.isShowingMyBids)
        #expect(router.myBidsViewModel === viewModel)
    }

}

//
//  BuyNowViewModelTests.swift
//  The Block
//
//  Tests for Buy Now through BidViewModel: success, unavailable reasons, and a lot ending
//  during the request (BID-8, BID-10, BID-11).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Buy Now through the bid sheet ViewModel: success, unavailable reasons, and late rejection.
@MainActor
struct BuyNowViewModelTests {

    @Test("BID-10: Buy Now on an active priced lot succeeds and marks it purchased by you")
    func buyNowSucceeds() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let repository = await BiddingTestSupport.makeRepository([vehicle])
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        #expect(viewModel.buyNowUnavailableReason == nil)
        await viewModel.buyNow()

        #expect(viewModel.phase == .succeeded)
        #expect(repository.vehicle(id: vehicle.id)?.yourPurchasePrice == 31_000)
        #expect(repository.vehicle(id: vehicle.id)?.status(at: repository.now) == .ended(.purchasedByYou))
    }

    @Test("BID-11: a lot without a Buy Now price explains why and refuses")
    func noPrice() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: nil)
        let repository = await BiddingTestSupport.makeRepository([vehicle])
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        #expect(viewModel.buyNowUnavailableReason == "This lot has no Buy Now price.")
        await viewModel.buyNow()
        #expect(viewModel.phase == .editing)
    }

    @Test("BID-11: Buy Now is unavailable on an upcoming lot")
    func upcomingLot() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let clock = MutableClock(now: TestDates.reference)
        let repository = await BiddingTestSupport.makeRepository([vehicle], clock: clock)
        clock.now = TestDates.reference.addingTimeInterval(-TestDates.hours(1))
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        #expect(viewModel.buyNowUnavailableReason == "Buy Now opens when the auction goes live.")
        await viewModel.buyNow()
        #expect(repository.vehicle(id: vehicle.id)?.isPurchasedByYou == false)
    }

    @Test("BID-11: Buy Now is unavailable on an ended lot")
    func endedLot() async {
        let id = UUID()
        let repository = await BiddingTestSupport.makeRepository(BiddingTestSupport.endedLot(id: id))
        let viewModel = BidViewModel(vehicleID: id, repository: repository)

        #expect(viewModel.buyNowUnavailableReason == "This auction has ended.")
        await viewModel.buyNow()
        #expect(viewModel.phase == .editing)
        #expect(repository.vehicle(id: id)?.isPurchasedByYou == false)
    }

    @Test("BID-10 / BID-8: a lot that ends during the round trip is rejected with the reason")
    func endsDuringRoundTrip() async {
        let vehicle = VehicleModel.fixture(buyNowPrice: 31_000)
        let clock = MutableClock(now: TestDates.reference)
        let repository = await BiddingTestSupport.makeRepository(
            [vehicle], clock: clock, actionLatency: .milliseconds(50)
        )
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)

        let purchase = Task { await viewModel.buyNow() }
        while viewModel.phase != .submitting {
            await Task.yield()
        }
        clock.now = TestDates.reference.addingTimeInterval(AuctionSchedule.duration)
        await viewModel.buyNow()
        await purchase.value

        #expect(viewModel.phase == .editing)
        #expect(viewModel.rejectionMessage == "Not placed. Buy Now is no longer available.")
        #expect(repository.vehicle(id: vehicle.id)?.isPurchasedByYou == false)
    }

}

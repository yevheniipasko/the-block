//
//  FeeEstimateViewModelTests.swift
//  The Block
//
//  Tests for the bid and Buy Now fee estimates BidViewModel exposes (FEES-1, FEES-3).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

@MainActor
struct FeeEstimateViewModelTests {

    private func makeViewModel(_ vehicle: VehicleModel) async -> BidViewModel {
        let repository = await BiddingTestSupport.makeRepository([vehicle])
        return BidViewModel(vehicleID: vehicle.id, repository: repository)
    }

    @Test("FEES-1: the estimate starts from the pre-filled minimum")
    func estimateFollowsPrefill() async {
        let viewModel = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        #expect(viewModel.bidEstimate == FeeEstimate(amount: 24_000, buyerFee: 500, documentationFee: 99))
        #expect(viewModel.bidEstimate?.total == 24_599)
    }

    @Test("FEES-1: the estimate follows typed amounts and quick-add")
    func estimateFollowsEntry() async {
        let viewModel = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("26500")
        #expect(viewModel.bidEstimate?.amount == 26_500)
        #expect(viewModel.bidEstimate?.total == 27_099)

        viewModel.quickAdd(steps: 2)
        #expect(viewModel.bidEstimate?.amount == 28_500)
        #expect(viewModel.bidEstimate?.total == 29_099)
    }

    @Test("FEES-1: no estimate for an empty or zero entry")
    func noEstimateForEmptyEntry() async {
        let viewModel = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("")
        #expect(viewModel.bidEstimate == nil)

        viewModel.updateAmountText("abc")
        #expect(viewModel.bidEstimate == nil)

        viewModel.updateAmountText("0")
        #expect(viewModel.bidEstimate == nil)
    }

    @Test("FEES-3: the buyer fee switches exactly at $10,000 through the entry")
    func lowerTierBoundary() async {
        let viewModel = await makeViewModel(.fixture(currentBid: 8_000, bidCount: 1))

        viewModel.updateAmountText("9999")
        #expect(viewModel.bidEstimate?.buyerFee == 300)
        #expect(viewModel.bidEstimate?.total == 10_398)

        viewModel.updateAmountText("10000")
        #expect(viewModel.bidEstimate?.buyerFee == 500)
        #expect(viewModel.bidEstimate?.total == 10_599)
    }

    @Test("FEES-3: quick-add across $30,000 switches to the 2 % buyer fee")
    func upperTierBoundaryViaQuickAdd() async {
        let viewModel = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("29999")
        #expect(viewModel.bidEstimate?.buyerFee == 500)

        viewModel.updateAmountText("29000")
        viewModel.quickAdd(steps: 1)
        #expect(viewModel.amount == 30_000)
        #expect(viewModel.bidEstimate?.buyerFee == 600)
        #expect(viewModel.bidEstimate?.total == 30_699)
    }

    @Test("FEES-1: the Buy Now estimate uses the Buy Now price, not the entry")
    func buyNowEstimateUsesPrice() async {
        let viewModel = await makeViewModel(.fixture(buyNowPrice: 31_000, currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("25000")

        #expect(viewModel.buyNowEstimate == FeeEstimate(amount: 31_000, buyerFee: 620, documentationFee: 99))
        #expect(viewModel.buyNowEstimate?.total == 31_719)
    }

    @Test("FEES-1: no Buy Now estimate for a lot without a Buy Now price")
    func noBuyNowEstimateWithoutPrice() async {
        let viewModel = await makeViewModel(.fixture(buyNowPrice: nil))

        #expect(viewModel.buyNowEstimate == nil)
    }

}

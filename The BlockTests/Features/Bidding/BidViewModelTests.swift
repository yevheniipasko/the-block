//
//  BidViewModelTests.swift
//  The Block
//
//  Tests for BidViewModel entry, validation, review / confirm, and rejections (BID-1…BID-5,
//  BID-7, BID-8, UX-5); also provides MutableClock and BiddingTestSupport.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Clock the test can move after loading, e.g. to end an auction mid-flow.
@MainActor
final class MutableClock: AuctionClockProtocol {
    var now: Date
    /// Starts the clock at `now`.
    init(now: Date) { self.now = now }
}

/// Builds a loaded repository whose only (or latest) vehicle starts exactly at `TestDates.reference`.
@MainActor
enum BiddingTestSupport {

    /// Stub-server repository that has already loaded `vehicles` on `clock`.
    static func makeRepository(
        _ vehicles: [VehicleModel],
        clock: AuctionClockProtocol = FixedClock(now: TestDates.reference),
        actionLatency: Duration = .zero
    ) async -> VehicleRepository {
        let repository = VehicleRepository.stubbed(
            result: .success(vehicles),
            clock: clock,
            actionLatency: actionLatency
        )
        await repository.load()
        return repository
    }

    /// An ended lot plus a later anchor vehicle, so normalization maps the anchor to "now".
    static func endedLot(id: UUID) -> [VehicleModel] {
        let anchorStart = Date(timeIntervalSince1970: 1_000_000)
        let endedStart = anchorStart.addingTimeInterval(-TestDates.hours(73))
        return [
            .fixture(id: id, auctionStart: endedStart, buyNowPrice: 40_000, currentBid: 20_000, bidCount: 3),
            .fixture(auctionStart: anchorStart)
        ]
    }

}

/// Bid sheet ViewModel: pre-fill, quick-add, validation, review / confirm, and rejections.
@MainActor
struct BidViewModelTests {

    /// Bid ViewModel for `vehicle` on a loaded repository, which is returned for assertions.
    private func makeViewModel(
        _ vehicle: VehicleModel,
        actionLatency: Duration = .zero
    ) async -> (BidViewModel, VehicleRepository) {
        let repository = await BiddingTestSupport.makeRepository([vehicle], actionLatency: actionLatency)
        return (BidViewModel(vehicleID: vehicle.id, repository: repository), repository)
    }

    // MARK: - BID-1

    @Test("BID-1: hot lot pre-fills the minimum and explains step and activity")
    func hotLotPrefill() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        #expect(viewModel.amountText == "24000")
        #expect(viewModel.minimumExplanation == "Minimum $24,000 · step $1,000 · Hot lot, 14 bids")
    }

    @Test("BID-1: quiet lot uses the halved step and quiet wording")
    func quietLotPrefill() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 8_000, bidCount: 1))

        #expect(viewModel.amountText == "8100")
        #expect(viewModel.minimumExplanation == "Minimum $8,100 · step $100 · Quiet lot, 1 bid")
    }

    @Test("BID-1: active lot uses the base step and active wording")
    func activeLotPrefill() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 35_000, bidCount: 6))

        #expect(viewModel.minimumExplanation == "Minimum $36,000 · step $1,000 · Active lot, 6 bids")
    }

    @Test("BID-1: lot without bids opens at the starting bid")
    func openingLotPrefill() async {
        let (viewModel, _) = await makeViewModel(.fixture(startingBid: 14_500))

        #expect(viewModel.amountText == "14500")
        #expect(viewModel.minimumExplanation == "Opening bid $14,500")
        #expect(viewModel.validationMessage == nil)
        #expect(viewModel.canReview)
    }

    // MARK: - BID-2

    @Test("BID-2: quick-add adds 1, 2 and 5 steps to the current entry")
    func quickAddMath() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.quickAdd(steps: 1)
        #expect(viewModel.amount == 25_000)
        viewModel.quickAdd(steps: 2)
        #expect(viewModel.amount == 27_000)
        viewModel.quickAdd(steps: 5)
        #expect(viewModel.amount == 32_000)
    }

    @Test("BID-2: quick-add on an empty entry starts from the minimum")
    func quickAddFromEmpty() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("")
        viewModel.quickAdd(steps: 1)

        #expect(viewModel.amount == 25_000)
    }

    @Test("BID-2: manual entry keeps whole-dollar digits only")
    func manualEntryStripsNonDigits() async {
        let (viewModel, _) = await makeViewModel(.fixture())

        viewModel.updateAmountText("$25,500.75")

        #expect(viewModel.amountText == "2550075")
        viewModel.updateAmountText("abc")
        #expect(viewModel.amountText.isEmpty)
        #expect(viewModel.amount == nil)
    }

    // MARK: - BID-3 / BID-4

    @Test("BID-3: an amount below the minimum shows a message and blocks review")
    func belowMinimum() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("23500")
        viewModel.review()

        #expect(viewModel.validationRejection == .belowMinimum(minimum: 24_000))
        #expect(viewModel.validationMessage == "Bid at least $24,000.")
        #expect(!viewModel.canReview)
        #expect(viewModel.phase == .editing)
    }

    @Test("BID-4: an amount at the Buy Now price says to use Buy Now instead")
    func atBuyNowCeiling() async {
        let (viewModel, _) = await makeViewModel(.fixture(buyNowPrice: 31_000, currentBid: 23_000, bidCount: 14))

        viewModel.updateAmountText("31000")

        #expect(viewModel.validationRejection == .atOrAboveBuyNow(buyNowPrice: 31_000))
        #expect(viewModel.validationMessage?.hasPrefix("Use Buy Now instead") == true)
        #expect(!viewModel.canReview)
    }

    // MARK: - BID-5 / BID-8

    @Test("BID-5 / BID-8: review then confirm places the bid and succeeds")
    func reviewConfirmSucceeds() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)

        viewModel.review()
        #expect(viewModel.phase == .reviewing)
        await viewModel.submitBid()

        #expect(viewModel.phase == .succeeded)
        let updated = repository.vehicle(id: vehicle.id)
        #expect(updated?.currentBid == 24_000)
        #expect(updated?.bidCount == 15)
        #expect(updated?.isYouHighBidder == true)
    }

    @Test("BID-5: submitting without reviewing does nothing")
    func submitRequiresReview() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)

        await viewModel.submitBid()

        #expect(viewModel.phase == .editing)
        #expect(repository.vehicle(id: vehicle.id)?.bidCount == 14)
    }

    @Test("BID-5: editing from the review step returns to entry with the amount kept")
    func editFromReview() async {
        let (viewModel, _) = await makeViewModel(.fixture(currentBid: 23_000, bidCount: 14))

        viewModel.quickAdd(steps: 1)
        viewModel.review()
        viewModel.editBid()

        #expect(viewModel.phase == .editing)
        #expect(viewModel.amount == 25_000)
    }

    @Test("BID-8: a bid outpaced during the round trip is rejected and the minimum recomputed")
    func rejectionKeepsStateConsistent() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)
        viewModel.review()

        // Another bid lands before ours arrives.
        await repository.placeBid(30_000, on: vehicle.id)
        let before = repository.vehicle(id: vehicle.id)
        await viewModel.submitBid()

        #expect(viewModel.phase == .editing)
        #expect(viewModel.rejectionMessage == "Not placed. Bid at least $32,000.")
        #expect(viewModel.minimumBid == 32_000)
        #expect(!viewModel.canReview)
        #expect(repository.vehicle(id: vehicle.id) == before)
    }

    @Test("BID-8: editing the amount clears the rejection message")
    func editingClearsRejection() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle)
        viewModel.review()
        await repository.placeBid(30_000, on: vehicle.id)
        await viewModel.submitBid()

        viewModel.updateAmountText("32000")

        #expect(viewModel.rejectionMessage == nil)
        #expect(viewModel.validationMessage == nil)
        #expect(viewModel.canReview)
    }

    @Test("BID-7 / BID-8: an auction ending mid-flow rejects the bid and shows the ended state")
    func auctionEndsDuringReview() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let clock = MutableClock(now: TestDates.reference)
        let repository = await BiddingTestSupport.makeRepository([vehicle], clock: clock)
        let viewModel = BidViewModel(vehicleID: vehicle.id, repository: repository)
        viewModel.review()

        clock.now = TestDates.reference.addingTimeInterval(AuctionSchedule.duration)
        await viewModel.submitBid()

        #expect(viewModel.phase == .editing)
        #expect(viewModel.rejectionMessage == "Not placed. This auction has ended.")
        #expect(viewModel.isAuctionEnded)
        #expect(repository.vehicle(id: vehicle.id)?.bidCount == 14)
    }

    @Test("UX-5 / BID-8: a second submit while one is in flight is ignored")
    func doubleSubmitIgnored() async {
        let vehicle = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let (viewModel, repository) = await makeViewModel(vehicle, actionLatency: .milliseconds(50))
        viewModel.review()

        let first = Task { await viewModel.submitBid() }
        while viewModel.phase != .submitting {
            await Task.yield()
        }
        #expect(viewModel.isSubmitting)
        viewModel.updateAmountText("99999")
        viewModel.quickAdd(steps: 5)
        await viewModel.submitBid()
        #expect(viewModel.phase == .submitting)
        await first.value

        #expect(viewModel.phase == .succeeded)
        #expect(viewModel.amount == 24_000)
        #expect(repository.vehicle(id: vehicle.id)?.bidCount == 15)
    }

    // MARK: - BID-7

    @Test("BID-7: an ended lot reports ended and cannot be reviewed")
    func endedLot() async {
        let id = UUID()
        let repository = await BiddingTestSupport.makeRepository(BiddingTestSupport.endedLot(id: id))
        let viewModel = BidViewModel(vehicleID: id, repository: repository)

        #expect(viewModel.isAuctionEnded)
        #expect(viewModel.validationRejection == .auctionEnded)
        #expect(!viewModel.canReview)
    }

}

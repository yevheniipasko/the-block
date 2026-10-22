import Foundation
import Testing
@testable import The_Block

@MainActor
struct BiddingRulesTests {

    private let start = TestDates.reference
    private var duringAuction: Date { start.addingTimeInterval(TestDates.hours(1)) }

    @Test(
        "BID-9: step = price base × activity at every tier and level boundary",
        arguments: [
            // (current bid, bid count, expected step)
            (9_999, 1, 100), (9_999, 3, 100), (9_999, 4, 200), (9_999, 9, 200), (9_999, 10, 400),
            (10_000, 1, 250), (29_999, 5, 500), (29_999, 10, 1_000),
            (30_000, 3, 500), (30_000, 4, 1_000), (75_000, 18, 2_000)
        ]
    )
    func adaptiveStep(currentBid: Int, bidCount: Int, expected: Int) {
        #expect(BiddingRules.step(currentBid: currentBid, bidCount: bidCount) == expected)
    }

    @Test("BID-1: minimum next bid is the starting bid when there are no bids")
    func openingMinimum() {
        let vehicle = VehicleModel.fixture(startingBid: 14_500, currentBid: nil, bidCount: 0)

        #expect(BiddingRules.minimumNextBid(for: vehicle) == 14_500)
    }

    @Test("BID-1: minimum next bid is current bid plus the adaptive step")
    func runningMinimum() {
        let hotLot = VehicleModel.fixture(currentBid: 23_000, bidCount: 14)
        let quietLot = VehicleModel.fixture(currentBid: 23_000, bidCount: 2)

        #expect(BiddingRules.minimumNextBid(for: hotLot) == 24_000)
        #expect(BiddingRules.minimumNextBid(for: quietLot) == 23_250)
    }

    @Test("BID-3: bids below the minimum are rejected with the minimum")
    func belowMinimumRejected() {
        let vehicle = VehicleModel.fixture(auctionStart: start, currentBid: 23_000, bidCount: 14)

        let result = BiddingRules.validateBid(23_999, on: vehicle, at: duringAuction)

        #expect(result.failure == .belowMinimum(minimum: 24_000))
        #expect(BiddingRules.validateBid(24_000, on: vehicle, at: duringAuction).failure == nil)
    }

    @Test("BID-4: bids at or above the Buy Now price are rejected")
    func buyNowCeiling() {
        let vehicle = VehicleModel.fixture(auctionStart: start, buyNowPrice: 31_000, currentBid: 26_500, bidCount: 5)

        let atBuyNow = BiddingRules.validateBid(31_000, on: vehicle, at: duringAuction)
        #expect(atBuyNow.failure == .atOrAboveBuyNow(buyNowPrice: 31_000))
        #expect(BiddingRules.validateBid(30_999, on: vehicle, at: duringAuction).failure == nil)
    }

    @Test("BID-7: ended auctions reject bids; upcoming auctions accept them")
    func biddingWindow() {
        let vehicle = VehicleModel.fixture(auctionStart: start, startingBid: 10_000)
        let beforeStart = start.addingTimeInterval(-TestDates.hours(5))
        let afterEnd = vehicle.auctionEnd

        #expect(BiddingRules.validateBid(10_000, on: vehicle, at: beforeStart).failure == nil)
        #expect(BiddingRules.validateBid(10_000, on: vehicle, at: afterEnd).failure == .auctionEnded)
    }

    @Test("BID-11: Buy Now only while active and priced")
    func buyNowAvailability() {
        let priced = VehicleModel.fixture(auctionStart: start, buyNowPrice: 30_000)
        let unpriced = VehicleModel.fixture(auctionStart: start, buyNowPrice: nil)

        #expect(BiddingRules.canBuyNow(priced, at: duringAuction))
        #expect(!BiddingRules.canBuyNow(priced, at: start.addingTimeInterval(-1)))
        #expect(!BiddingRules.canBuyNow(priced, at: priced.auctionEnd))
        #expect(!BiddingRules.canBuyNow(unpriced, at: duringAuction))
    }

}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

//
//  AuctionTimingTests.swift
//  The Block
//
//  Tests for auction timing: launch-anchored schedule normalization, status boundaries,
//  ended outcomes, and floor state (TIME-1, TIME-2, BID-10).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Normalization of dataset start times around the launch date.
@MainActor
struct AuctionScheduleTests {

    @Test("TIME-1: launch time lands on the 121st sorted start, spacing preserved")
    func anchorsLaunchAtSixtiethPercentile() {
        let starts = (0..<200).map { TestDates.reference.addingTimeInterval(TestDates.hours(Double($0))) }
        let launch = Date(timeIntervalSince1970: 2_000_000_000)

        let schedule = AuctionSchedule(datasetStarts: starts.shuffled(), launchDate: launch)

        #expect(schedule.normalized(starts[120]) == launch)
        let gap = schedule.normalized(starts[121]).timeIntervalSince(schedule.normalized(starts[120]))
        #expect(gap == TestDates.hours(1))
    }

    @Test("TIME-1: with fewer than 121 starts, the latest start is the anchor")
    func smallDatasetAnchorsOnLatest() {
        let starts = [TestDates.reference, TestDates.reference.addingTimeInterval(TestDates.hours(5))]
        let launch = Date(timeIntervalSince1970: 2_000_000_000)

        let schedule = AuctionSchedule(datasetStarts: starts, launchDate: launch)

        #expect(schedule.normalized(starts[1]) == launch)
    }

}

/// Auction status over time, ended outcomes, and floor (reserve) state.
@MainActor
struct AuctionStatusTests {

    private let start = TestDates.reference

    @Test("TIME-2: upcoming before start, active for 72 h, ended at the end")
    func statusBoundaries() {
        let vehicle = VehicleModel.fixture(auctionStart: start)
        let end = start.addingTimeInterval(AuctionSchedule.duration)

        #expect(vehicle.status(at: start.addingTimeInterval(-1)) == .upcoming(startsAt: start))
        #expect(vehicle.status(at: start) == .active(endsAt: end))
        #expect(vehicle.status(at: end.addingTimeInterval(-1)) == .active(endsAt: end))
        #expect(vehicle.status(at: end) == .ended(.noSale))
    }

    @Test(
        "TIME-2: ended outcome follows bids, floor, and the buyer's position",
        arguments: [
            // (floor, current bid, bid count, your bid, expected)
            OutcomeCase(floor: nil, currentBid: nil, bidCount: 0, yourBid: nil, expected: .noSale),
            OutcomeCase(floor: 20_000, currentBid: 15_000, bidCount: 3, yourBid: nil, expected: .pendingBelowFloor),
            OutcomeCase(floor: 20_000, currentBid: 20_000, bidCount: 3, yourBid: nil, expected: .sold),
            OutcomeCase(floor: nil, currentBid: 15_000, bidCount: 3, yourBid: nil, expected: .sold),
            OutcomeCase(floor: 20_000, currentBid: 21_000, bidCount: 4, yourBid: 21_000, expected: .purchasedByYou),
            OutcomeCase(floor: 20_000, currentBid: 15_000, bidCount: 4, yourBid: 15_000, expected: .pendingBelowFloor)
        ]
    )
    func endedOutcome(_ testCase: OutcomeCase) {
        let vehicle = VehicleModel.fixture(
            reservePrice: testCase.floor,
            currentBid: testCase.currentBid,
            bidCount: testCase.bidCount,
            yourBid: testCase.yourBid
        )
        let expected = testCase.expected
        let afterEnd = vehicle.auctionEnd.addingTimeInterval(1)

        #expect(vehicle.status(at: afterEnd) == .ended(expected))
    }

    @Test("BID-10: a Buy Now purchase ends the auction immediately")
    func purchaseEndsAuction() {
        let vehicle = VehicleModel.fixture(auctionStart: start, buyNowPrice: 30_000, yourPurchasePrice: 30_000)

        #expect(vehicle.status(at: start.addingTimeInterval(TestDates.hours(1))) == .ended(.purchasedByYou))
    }

    @Test("Floor state is hidden behind met / not met / no floor")
    func floorState() {
        #expect(VehicleModel.fixture(reservePrice: nil).floorState == .noFloor)
        #expect(VehicleModel.fixture(reservePrice: 20_000, currentBid: nil).floorState == .notMet)
        #expect(VehicleModel.fixture(reservePrice: 20_000, currentBid: 19_999, bidCount: 1).floorState == .notMet)
        #expect(VehicleModel.fixture(reservePrice: 20_000, currentBid: 20_000, bidCount: 1).floorState == .met)
    }

    @Test("BID-10: a Buy Now purchase meets the floor even without bids")
    func purchaseMeetsFloor() {
        let bought = VehicleModel.fixture(reservePrice: 20_000, buyNowPrice: 25_000, yourPurchasePrice: 25_000)
        #expect(bought.floorState == .met)
    }

}

/// One row of the ended-outcome table: lot inputs and the outcome expected after the end.
struct OutcomeCase: Sendable, CustomTestStringConvertible {
    let floor: Int?
    let currentBid: Int?
    let bidCount: Int
    let yourBid: Int?
    let expected: EndedOutcome

    /// Readable case name shown in the test navigator.
    var testDescription: String {
        let describe = { (value: Int?) in value.map(String.init) ?? "none" }
        return "floor \(describe(floor)), bid \(describe(currentBid)) ×\(bidCount), yours \(describe(yourBid))"
    }
}

//
//  CardBuyerPositionTests.swift
//  The Block
//
//  Tests which buyer-position marker the inventory card shows (BID-6, BID-10, LIVE-3).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Testing
@testable import The_Block

/// Inventory card marker: purchased, high bidder, outbid, or none.
@MainActor
struct CardBuyerPositionTests {

    private let start = TestDates.reference
    private var live: Date { start.addingTimeInterval(TestDates.hours(1)) }
    private var ended: Date { start.addingTimeInterval(TestDates.hours(73)) }

    @Test("LIVE-3: the card shows outbid while the lot is live")
    func outbidWhileLive() {
        let lot = VehicleModel.fixture(auctionStart: start, currentBid: 21_000, bidCount: 4, yourBid: 20_000)

        #expect(CardBuyerPosition(vehicle: lot, at: live) == .outbid)
    }

    @Test("LIVE-3: the card hides outbid once the lot has ended")
    func outbidHiddenAfterEnd() {
        let lot = VehicleModel.fixture(auctionStart: start, currentBid: 21_000, bidCount: 4, yourBid: 20_000)

        #expect(CardBuyerPosition(vehicle: lot, at: ended) == nil)
    }

    @Test("BID-6: the card shows high bidder, also after the lot has ended")
    func highBidder() {
        let lot = VehicleModel.fixture(auctionStart: start, currentBid: 20_000, bidCount: 4, yourBid: 20_000)

        #expect(CardBuyerPosition(vehicle: lot, at: live) == .highBidder)
        #expect(CardBuyerPosition(vehicle: lot, at: ended) == .highBidder)
    }

    @Test("BID-6: no marker on a lot the buyer never bid on")
    func noPosition() {
        let lot = VehicleModel.fixture(auctionStart: start, currentBid: 21_000, bidCount: 4)

        #expect(CardBuyerPosition(vehicle: lot, at: live) == nil)
    }

}
